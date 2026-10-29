class_name ForeignSim
extends RefCounted


const UNION_LOCKS := ["concert_agreement", "meridian_guarantee"]
const UNION_LOCKED_BLOCS := ["concert", "meridian"]
const GAS_WEIGHT := 0.5
const DEBT_WEIGHT := 0.25
const EXPORT_WEIGHT := 0.25
const HEATING_MONTHS := [10, 11, 12, 1, 2, 3]
const WINTER_GAS_BONUS := 0.25
const TREATY_COMMITMENT := {"trade": 0.15, "defense": 0.3}
const BLOC_COMMITMENT_TO_ANCHOR := 0.5
const UNION_TARIFF_SHARE := 0.6
const RESOLVED_VETRENKA := ["settled", "retaken", "partitioned"]


static func catalog() -> Dictionary:
	var data: Variant = ContentRepository.load_all().get("catalogs", {}).get("foreign_orientation", {})
	return data if data is Dictionary else {}


static func _ids(section: String) -> Array[String]:
	var out: Array[String] = []
	for row in catalog().get(section, []):
		out.append(String(row.get("id", "")))
	return out


static func _row(section: String, id: String) -> Dictionary:
	for row in catalog().get(section, []):
		if String(row.get("id", "")) == id:
			return row
	return {}


static func power_ids() -> Array[String]:
	return _ids("powers")


static func milestone_ids() -> Array[String]:
	return _ids("milestones")


static func bloc_ids() -> Array[String]:
	return _ids("blocs")


static func power(id: String) -> Dictionary:
	return _row("powers", id)


static func milestone(id: String) -> Dictionary:
	return _row("milestones", id)


static func bloc(id: String) -> Dictionary:
	return _row("blocs", id)


static func milestone_name(id: String) -> String:
	return String(milestone(id).get("name", id))


static func ensure(state: GameState) -> void:
	var f := state.foreign
	if f.seeded:
		if GasSim.ensure(state):
			update_spine(state)
		return
	for p in catalog().get("powers", []):
		f.gas_share[String(p["id"])] = float(p.get("gas_share", 0.0))
	for m in catalog().get("milestones", []):
		if bool(m.get("starts_reached", false)):
			f.reached[String(m["id"])] = state.turn
	for b in catalog().get("blocs", []):
		var ids: Array = []
		for country_id in b.get("seed_members", []):
			if state.world_country(String(country_id)) != null:
				ids.append(String(country_id))
		f.members[String(b["id"])] = ids
	f.isf = ForeignState.default_isf()
	f.seeded = true
	GasSim.ensure(state)
	update_spine(state)


static func countries_of(state: GameState, power_id: String) -> Array[String]:
	var out: Array[String] = []
	match String(power(power_id).get("kind", "")):
		"state":
			out.append(power_id)
		"bloc":
			for id in state.foreign.members.get(power_id, []):
				out.append(String(id))
	return out


static func debt_share(state: GameState, power_id: String) -> float:
	var econ := state.country.economy
	var debt := econ.public_debt_pct * econ.gdp
	if debt <= 0.0:
		return 0.0
	var held := float(state.foreign.isf.get("disbursed", 0.0)) if power_id == "isf" else 0.0
	var lenders := countries_of(state, power_id)
	for loan in econ.loans:
		if String(loan.get("lender_id", "")) in lenders:
			held += float(loan.get("principal", 0.0))
	return clampf(held / debt, 0.0, 1.0)


static func export_share(state: GameState, power_id: String) -> float:
	var partners := countries_of(state, power_id)
	var total := 0.0
	var held := 0.0
	for key in state.country.relations:
		var volume := (state.country.relations[key] as Country.BilateralRelation).trade_volume
		total += volume
		if String(key) in partners:
			held += volume
	return 0.0 if total <= 0.0 else clampf(held / total, 0.0, 1.0)


static func dependence(state: GameState, power_id: String) -> float:
	var gas := float(state.foreign.gas_share.get(power_id, 0.0))
	return clampf(GAS_WEIGHT * gas + DEBT_WEIGHT * debt_share(state, power_id)
		+ EXPORT_WEIGHT * export_share(state, power_id), 0.0, 1.0)


static func commitment(state: GameState, power_id: String) -> float:
	var total := 0.0
	for id in state.foreign.reached:
		var m := milestone(String(id))
		if String(m.get("power", "")) == power_id:
			total = maxf(total, float(m.get("commitment", 0.0)))
	if String(power(power_id).get("kind", "")) == "state":
		var p := DiplomacySim.pair(state, power_id)
		if not p.is_empty():
			for tr in (p[0] as Country.BilateralRelation).treaties:
				if tr is Dictionary:
					total += float(TREATY_COMMITMENT.get(String(tr.get("type", "")), 0.0))
		for other in power_ids():
			if other != power_id and String(power(other).get("anchor", "")) == power_id:
				total += BLOC_COMMITMENT_TO_ANCHOR * commitment(state, other)
	return clampf(total, 0.0, 1.0)


static func is_heating_season(state: GameState) -> bool:
	return state.month in HEATING_MONTHS


static func leverage(state: GameState, power_id: String) -> float:
	var anchor := String(power(power_id).get("anchor", ""))
	var warmth := 0.0
	if anchor != "" and state.country.relations.has(anchor):
		warmth = (state.country.relations[anchor] as Country.BilateralRelation).score
	var gas := float(state.foreign.gas_share.get(power_id, 0.0))
	var season := 1.0 + (WINTER_GAS_BONUS * gas if is_heating_season(state) else 0.0)
	return clampf(dependence(state, power_id) * (0.75 - 0.25 * warmth) * season, 0.0, 1.0)


static func leverage_of(state: GameState, power_id: String) -> float:
	if state.foreign == null:
		return 0.0
	var row: Variant = state.foreign.powers.get(power_id, {})
	return float((row as Dictionary).get("leverage", 0.0)) if row is Dictionary else 0.0


static func update_spine(state: GameState) -> void:
	for id in power_ids():
		state.foreign.powers[id] = {"dependence": dependence(state, id),
			"commitment": commitment(state, id), "leverage": leverage(state, id)}


static func monthly(state: GameState) -> Array[String]:
	ensure(state)
	var notes := OrientationSim.monthly(state)
	notes.append_array(GasSim.monthly(state))
	update_spine(state)
	return notes


static func trade_ceiling_share(state: GameState, country_id: String) -> float:
	if state.foreign == null or not state.foreign.reached.has("union_member"):
		return 1.0
	return UNION_TARIFF_SHARE if country_id in state.foreign.members.get("concert", []) else 1.0


static func vetrenka_resolved(state: GameState) -> bool:
	if not state.regions.has("vetrenka"):
		return true
	return String(state.campaign_meta.get("vetrenka_status", "")) in RESOLVED_VETRENKA
