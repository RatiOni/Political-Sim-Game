class_name GasSim
extends RefCounted


const PAYMENT_SHARE := 0.85
const WINTER_WEIGHT := 1.5
const STORAGE_MONTHS := 24
const SECOND_LINE_MONTHS := 48
const SECOND_LINE_OPENING := -0.1
const UNION_PRICE_SHARE := 0.7
const INJECTION_SHARE := 0.25
const SHORTFALL_NOTE := 0.05
const SEPARATIST := "separatist"
const HARDSHIP_PER_SEVERITY := 0.25
const REACH_PER_SEVERITY := 0.15
const JOBS_PER_SEVERITY := 0.06
const GROWTH_PER_SEVERITY := 0.06
const PRICE_GROWTH_WEIGHT := 0.01
const STABILITY_PER_SEVERITY := 0.10
const ARREARS_DEMAND := 60.0
const DEMAND_INTERVAL := 6
const THREAT_AFTER_DEMAND := 2
const THREAT_LEVERAGE := 0.5
const CUT_COOLDOWN := 24
const CUT_SHARE_PER_LEVERAGE := 0.4
const CUT_MONTHS := 2
const DEFUSED_SHARE := 0.5
const DEMAND_RELATIONS := -0.03
const TERM_MONTHS := 36
const RENEWAL_RISE := 0.4
const UNION_RESCHEDULED := 0.5
const UNION_CRISIS_WARMTH := -0.5
const EXIT_PRICE_RISE := 0.2


static func catalog() -> Dictionary:
	var data: Variant = ContentRepository.load_all().get("catalogs", {}).get("energy", {})
	return data if data is Dictionary else {}


static func season_weight(month: int) -> float:
	var weights: Array = catalog().get("season", [])
	return float(weights[month - 1]) if weights.size() == 12 else 1.0


static func line(key: String, fields: Dictionary = {}) -> String:
	return String(catalog().get("lines", {}).get(key, key)).format(fields)


static func gas(state: GameState) -> GasContract:
	return null if state.foreign == null else state.foreign.gas


static func is_active(state: GameState) -> bool:
	var g := gas(state)
	return g != null and g.is_active()


static func union_member(state: GameState) -> bool:
	return state.foreign != null and state.foreign.reached.has("union_member")


static func union_cap(g: GasContract) -> float:
	return g.reference_price * UNION_PRICE_SHARE


static func ensure(state: GameState) -> bool:
	var g := state.foreign.gas
	if g.is_active():
		return false
	var raw: Variant = catalog().get("contracts", {}).get(state.country.id, null)
	if not (raw is Dictionary):
		return false
	var row: Dictionary = raw
	if state.world_country(String(row.get("supplier_id", ""))) == null:
		return false
	g.supplier_id = String(row["supplier_id"])
	g.price = float(row["price"])
	g.reference_price = g.price
	g.annual_demand = float(row["annual_demand"])
	g.contracted_volume = float(row["contracted_volume"])
	g.arrears = float(row["arrears"])
	g.term_end = int(row["term_end"])
	g.take_or_pay = float(row["take_or_pay"])
	g.paid.clear()
	for _i in range(GasContract.PAID_MONTHS):
		g.paid.append(g.price * g.contracted_volume * PAYMENT_SHARE / float(GasContract.PAID_MONTHS))
	write_share(state)
	return true


static func write_share(state: GameState) -> void:
	var g := state.foreign.gas
	if not g.is_active() or not (g.supplier_id in ForeignSim.power_ids()):
		return
	var total := g.contracted_volume + g.second_line_volume
	state.foreign.gas_share[g.supplier_id] = 0.0 if total <= 0.0 else clampf(g.contracted_volume / total, 0.0, 1.0)


static func cap_to_union(state: GameState) -> void:
	var g := state.foreign.gas
	if g.is_active():
		g.price = minf(g.price, union_cap(g))


static func second_line_price_share() -> float:
	return float(catalog().get("second_line", {}).get("price_share", 1.0))


static func monthly(state: GameState) -> Array[String]:
	var notes: Array[String] = []
	if not is_active(state):
		return notes
	_renew(state, notes)
	_restore(state, notes)
	_mature_threat(state, notes)
	_advance_projects(state, notes)
	coerce(state, state.world_country(gas(state).supplier_id), notes)
	flow(state)
	write_share(state)
	if national_shortfall(state) >= SHORTFALL_NOTE:
		notes.append(line("gas_shortfall", {"share": roundi(national_shortfall(state) * 100.0)}))
	return notes


static func flow(state: GameState) -> void:
	var g := state.foreign.gas
	var season := season_weight(state.month)
	var supply := (1.0 - g.cut) * (1.0 - g.sabotage)
	var demand := g.annual_demand / 12.0 * season
	var offered := g.contracted_volume / 12.0 * season * supply
	var alternative := minf(demand, g.second_line_volume / 12.0 * season + g.spot_pending)
	g.spot_pending = 0.0
	var taken := minf(offered, demand - alternative)
	var gap := demand - alternative - taken
	var drawn := minf(g.storage, gap)
	g.storage -= drawn
	gap -= drawn
	var injected := 0.0
	if season < 1.0 and g.storage < g.storage_capacity:
		injected = minf(g.storage_capacity - g.storage, g.storage_capacity * INJECTION_SHARE) * supply
		g.storage += injected
	var bill := g.price * (maxf(taken, g.take_or_pay * offered) + injected)
	var alternative_bill := g.second_line_volume / 12.0 * season * g.reference_price * second_line_price_share()
	g.arrears += bill * (1.0 - PAYMENT_SHARE)
	g.paid.append(bill * PAYMENT_SHARE + alternative_bill)
	while g.paid.size() > GasContract.PAID_MONTHS:
		g.paid.pop_front()
	var shortfall := 0.0 if demand <= 0.0 else clampf(gap / demand, 0.0, 1.0)
	g.last_flow = {"demand": demand, "delivered": demand - gap, "drawn": drawn, "injected": injected,
		"bill": bill, "shortfall": shortfall, "severity": shortfall * season / WINTER_WEIGHT}


static func budget_cost(state: GameState) -> float:
	if not is_active(state):
		return 0.0
	var total := 0.0
	for p in gas(state).paid:
		total += p
	return total


static func national_shortfall(state: GameState) -> float:
	return 0.0 if not is_active(state) else float(gas(state).last_flow.get("shortfall", 0.0))


static func national_severity(state: GameState) -> float:
	return 0.0 if not is_active(state) else float(gas(state).last_flow.get("severity", 0.0))


static func exposure(region_id: String) -> float:
	return float(catalog().get("exposure", {}).get(region_id, 1.0))


static func _on_network(state: GameState, region_id: String) -> bool:
	var region: RegionState = state.regions.get(region_id) as RegionState
	return region != null and region.control != SEPARATIST


static func region_shortfall(state: GameState, region_id: String) -> float:
	if not _on_network(state, region_id):
		return 0.0
	return clampf(national_shortfall(state) * exposure(region_id), 0.0, 1.0)


static func region_severity(state: GameState, region_id: String) -> float:
	if not _on_network(state, region_id):
		return 0.0
	return clampf(national_severity(state) * exposure(region_id), 0.0, 1.0)


static func supply_by_region(state: GameState) -> Dictionary:
	var out := {}
	for key in state.regions:
		out[String(key)] = 1.0 - region_shortfall(state, String(key))
	return out


static func heating_hardship(state: GameState, region_id: String) -> float:
	return region_severity(state, region_id) * HARDSHIP_PER_SEVERITY


static func reach_loss(state: GameState, region_id: String) -> float:
	return region_severity(state, region_id) * REACH_PER_SEVERITY


static func industry_jobs_loss(state: GameState, region_id: String) -> float:
	if not (region_id in catalog().get("industrial", [])):
		return 0.0
	return region_severity(state, region_id) * JOBS_PER_SEVERITY


static func growth_effect(state: GameState) -> float:
	if not is_active(state) or gas(state).reference_price <= 0.0:
		return 0.0
	var g := gas(state)
	var advantage := clampf((g.reference_price - g.price) / g.reference_price, -1.0, 1.0)
	return advantage * PRICE_GROWTH_WEIGHT - national_severity(state) * GROWTH_PER_SEVERITY


static func stability_drag(state: GameState) -> float:
	return national_severity(state) * STABILITY_PER_SEVERITY


static func supplier_warmth(state: GameState) -> float:
	var p := DiplomacySim.pair(state, gas(state).supplier_id)
	return 0.0 if p.is_empty() else (p[0] as Country.BilateralRelation).score


static func crisis(state: GameState) -> bool:
	return supplier_warmth(state) < UNION_CRISIS_WARMTH


static func cuts_blocked(state: GameState) -> bool:
	return union_member(state) and not crisis(state)


static func valve_threat(state: GameState) -> Dictionary:
	return {} if not is_active(state) else gas(state).threat.duplicate()


static func coerce(state: GameState, actor: Country, notes: Array[String]) -> String:
	if actor == null or not is_active(state) or actor.id != gas(state).supplier_id:
		return ""
	var g := gas(state)
	if not g.threat.is_empty() or g.cut > 0.0 or g.arrears < ARREARS_DEMAND:
		return ""
	if g.last_demand_turn < 0 or state.turn - g.last_demand_turn >= DEMAND_INTERVAL:
		g.last_demand_turn = state.turn
		g.demands += 1
		var before := supplier_warmth(state)
		DiplomacySim.shift(state, actor.id, DEMAND_RELATIONS * WorldSim.coercion_strength(state, actor), "Pressed for the gas arrears.")
		_log_harm(state, actor.id, supplier_warmth(state) - before)
		notes.append(line("gas_demand", {"supplier": actor.name, "arrears": roundi(g.arrears)}))
		return "gas_demand"
	var leverage := ForeignSim.leverage_of(state, actor.id)
	var cooling := g.last_cut_turn >= 0 and state.turn - g.last_cut_turn < CUT_COOLDOWN
	if state.turn - g.last_demand_turn < THREAT_AFTER_DEMAND or leverage < THREAT_LEVERAGE \
			or cooling or cuts_blocked(state) or season_weight(state.month) < WINTER_WEIGHT:
		return ""
	g.threat = {"turn": state.turn, "due": state.turn + 1,
		"share": clampf(CUT_SHARE_PER_LEVERAGE * leverage, 0.0, 1.0)}
	g.threats += 1
	_log_harm(state, actor.id, 0.0)
	notes.append(line("gas_threat", {"supplier": actor.name}))
	return "gas_threat"


static func _renew(state: GameState, notes: Array[String]) -> void:
	var g := gas(state)
	if state.turn < g.term_end:
		return
	var price := g.reference_price * (1.0 + RENEWAL_RISE * ForeignSim.leverage_of(state, g.supplier_id))
	if union_member(state):
		price = minf(price, union_cap(g))
	g.price = price
	g.contracted_volume = maxf(0.0, g.annual_demand - g.second_line_volume)
	g.term_end = state.turn + TERM_MONTHS
	notes.append(line("gas_renewal", {"price": snappedf(price, 0.1)}))


static func _restore(state: GameState, notes: Array[String]) -> void:
	var g := gas(state)
	if g.cut > 0.0 and (state.turn >= g.cut_until or cuts_blocked(state)):
		g.cut = 0.0
		g.cut_until = -1
		notes.append(line("gas_restored"))


static func _mature_threat(state: GameState, notes: Array[String]) -> void:
	var g := gas(state)
	if g.threat.is_empty() or state.turn < int(g.threat["due"]):
		return
	var share := float(g.threat["share"])
	g.threat = {}
	if cuts_blocked(state) or g.arrears < ARREARS_DEMAND * DEFUSED_SHARE:
		notes.append(line("gas_threat_lapsed"))
		return
	g.cut = share
	g.cut_until = state.turn + CUT_MONTHS
	g.last_cut_turn = state.turn
	g.cuts += 1
	_log_harm(state, g.supplier_id, 0.0, -share * GROWTH_PER_SEVERITY)
	notes.append(line("gas_cut", {"share": roundi(share * 100.0)}))


static func on_union_join(state: GameState) -> void:
	if not is_active(state):
		return
	var g := gas(state)
	g.price = minf(g.price, union_cap(g))
	g.arrears *= 1.0 - UNION_RESCHEDULED
	g.threat = {}
	g.cut = 0.0
	g.cut_until = -1


static func on_union_leave(state: GameState) -> void:
	if not is_active(state):
		return
	var g := gas(state)
	g.price = maxf(g.price, g.reference_price * (1.0 + EXIT_PRICE_RISE))
	g.term_end = state.turn + TERM_MONTHS


static func _log_harm(state: GameState, actor_id: String, relation: float, economy: float = 0.0) -> void:
	state.foreign.hostile_log.append({"turn": state.turn, "actor": actor_id,
		"relation": relation, "economy": economy, "stability": 0.0})
	while state.foreign.hostile_log.size() > WorldSim.HOSTILE_LOG_LIMIT:
		state.foreign.hostile_log.pop_front()


static func _advance_projects(state: GameState, notes: Array[String]) -> void:
	var g := gas(state)
	if g.storage_started >= 0 and g.storage_capacity < g.storage_target:
		var built := clampf(float(state.turn - g.storage_started) / float(STORAGE_MONTHS), 0.0, 1.0)
		g.storage_capacity = g.storage_target * built
		if built >= 1.0:
			notes.append(line("storage_ready"))
	if g.second_line_started >= 0 and g.second_line_volume <= 0.0 \
			and state.turn - g.second_line_started >= SECOND_LINE_MONTHS:
		g.second_line_volume = float(catalog().get("second_line", {}).get("volume", 0.0))
		DiplomacySim.shift(state, g.supplier_id, SECOND_LINE_OPENING, "Ardenia opened a gas line around Krasova.")
		notes.append(line("second_line_open"))
