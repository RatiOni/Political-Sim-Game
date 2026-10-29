class_name OrientationSim
extends RefCounted


const REVIEW_MONTHS := [1, 4, 7, 10]
const ISF_REVIEWS := 12
const ISF_DEFICIT_TARGET := 0.05
const ISF_INFLATION_TARGET := 0.08
const ISF_TIGHTENING := 0.85
const ISF_BANK_DUE_REVIEW := 4
const ISF_BANK_DELAY := 4
const BANK_ACT := "central_bank_independence_act"
const ISF_TRANCHE_SHARE := 0.004
const ISF_TRANCHE_MONTHS := 3
const ISF_CONFIDENCE_GAIN := 0.001
const ISF_CONFIDENCE_LOSS := -0.002
const ISF_CONFIDENCE_GAIN_MONTHS := 3
const ISF_CONFIDENCE_LOSS_MONTHS := 6
const CONCERT_DEFICIT_LIMIT := 0.04
const CONCERT_INFLATION_LIMIT := 0.08
const QUALIFYING_SETBACK := 2
const BLOC_MONTH := 1


static func monthly(state: GameState) -> Array[String]:
	var notes: Array[String] = []
	_isf_review(state, notes)
	_western_discipline(state)
	if state.month == BLOC_MONTH:
		_world_blocs(state, notes)
	return notes


static func isf_targets(state: GameState) -> Dictionary:
	var renegotiations := int(state.foreign.isf.get("renegotiations", 0))
	var tight := pow(ISF_TIGHTENING, float(renegotiations))
	return {"deficit": ISF_DEFICIT_TARGET * tight, "inflation": ISF_INFLATION_TARGET * tight,
		"bank_due_review": ISF_BANK_DUE_REVIEW + ISF_BANK_DELAY * renegotiations}


static func bank_independent(state: GameState) -> bool:
	return state.enacted_laws.any(func(l: Law) -> bool: return l.id == BANK_ACT)


static func isf_review_due(state: GameState) -> bool:
	var isf := state.foreign.isf
	return state.foreign.reached.has("isf_programme") and state.month in REVIEW_MONTHS \
		and int(isf.get("reviews_held", 0)) < ISF_REVIEWS \
		and int(isf.get("last_review_turn", -1)) != state.turn


static func isf_passes(state: GameState) -> bool:
	var econ := state.country.economy
	var targets := isf_targets(state)
	var bank_ok := int(state.foreign.isf.get("reviews_held", 0)) < int(targets["bank_due_review"]) \
		or bank_independent(state)
	return econ.deficit_share_of_gdp() <= float(targets["deficit"]) \
		and econ.inflation <= float(targets["inflation"]) and bank_ok


static func release_tranche(state: GameState, label: String) -> float:
	var tranche := state.country.economy.gdp * ISF_TRANCHE_SHARE
	state.foreign.isf["disbursed"] = float(state.foreign.isf.get("disbursed", 0.0)) + tranche
	state.modifiers.append(timed_modifier("isf_tranche_%d" % state.turn, label, "budget_revenue",
		tranche / float(ISF_TRANCHE_MONTHS), ISF_TRANCHE_MONTHS - 1, false))
	return tranche


static func timed_modifier(id: String, source: String, target: String, magnitude: float,
		hold: int, institutional: bool) -> Modifier:
	var m := Modifier.new()
	m.id = id
	m.source = source
	m.target = target
	m.magnitude = magnitude
	m.onset_delay = 0
	m.ramp_duration = 1
	m.hold_duration = hold
	m.decay_duration = 0
	m.source_id = id
	m.portfolio = "Foreign Affairs"
	m.institutional = institutional
	return m


static func line(key: String, fields: Dictionary = {}) -> String:
	return String(ForeignSim.catalog().get("lines", {}).get(key, key)).format(fields)


static func _isf_review(state: GameState, notes: Array[String]) -> void:
	if not isf_review_due(state):
		return
	var isf := state.foreign.isf
	var passed := isf_passes(state)
	isf["reviews_held"] = int(isf.get("reviews_held", 0)) + 1
	isf["last_review_turn"] = state.turn
	if passed:
		isf["passed"] = int(isf.get("passed", 0)) + 1
		isf["suspended"] = false
		isf["last_result"] = "passed"
		release_tranche(state, "ISF disbursement")
		state.modifiers.append(timed_modifier("isf_confidence_%d" % state.turn, "ISF review passed",
			"gdp_growth", ISF_CONFIDENCE_GAIN, ISF_CONFIDENCE_GAIN_MONTHS, true))
		notes.append(line("isf_pass"))
	else:
		isf["failed"] = int(isf.get("failed", 0)) + 1
		isf["suspended"] = true
		isf["last_result"] = "failed"
		state.modifiers.append(timed_modifier("isf_confidence_%d" % state.turn, "ISF review failed",
			"gdp_growth", ISF_CONFIDENCE_LOSS, ISF_CONFIDENCE_LOSS_MONTHS, true))
		notes.append(line("isf_fail"))


static func _western_discipline(state: GameState) -> void:
	var f := state.foreign
	if not f.reached.has("concert_application") or f.reached.has("concert_agreement"):
		return
	var econ := state.country.economy
	if econ.deficit_share_of_gdp() <= CONCERT_DEFICIT_LIMIT and econ.inflation <= CONCERT_INFLATION_LIMIT:
		f.western_qualifying_months += 1
	else:
		f.western_qualifying_months = maxi(0, f.western_qualifying_months - QUALIFYING_SETBACK)


static func _anchor(bloc_id: String) -> String:
	return String(ForeignSim.power(bloc_id).get("anchor", ""))


static func _warmth(c: Country, anchor: String) -> float:
	if c.id == anchor:
		return 1.0
	var rel: Country.BilateralRelation = c.relations.get(anchor)
	return 0.0 if rel == null else rel.score


static func _in_excluded(state: GameState, c: Country, b: Dictionary) -> bool:
	for other in b.get("excludes", []):
		if c.id in state.foreign.members.get(String(other), []):
			return true
	return false


static func bloc_fits(state: GameState, c: Country, b: Dictionary) -> bool:
	var anchor := _anchor(String(b["id"]))
	if c.in_civil_war or c.stability < float(b.get("min_stability", 0.0)) or _in_excluded(state, c, b):
		return false
	var requires := String(b.get("requires", ""))
	if requires != "" and not (c.id in state.foreign.members.get(requires, [])):
		return false
	var family := String(DiplomacySim.REGIME_FAMILY.get(c.regime_type, c.regime_type))
	var client := String(c.agenda.get("ally", "")) == anchor
	var kindred: bool = WorldSim.agenda_type(c) in b.get("agendas", []) and family in b.get("families", [])
	return (client or kindred) and _warmth(c, anchor) >= float(b.get("min_warmth", 0.0))


static func bloc_rejects(state: GameState, c: Country, b: Dictionary) -> bool:
	var anchor := _anchor(String(b["id"]))
	return c.in_civil_war or c.stability < float(b.get("leave_stability", 0.0)) \
		or _warmth(c, anchor) < float(b.get("leave_warmth", 0.0)) or _in_excluded(state, c, b)


static func _world_blocs(state: GameState, notes: Array[String]) -> void:
	for b in ForeignSim.catalog().get("blocs", []):
		var bloc_id := String(b["id"])
		var anchor := _anchor(bloc_id)
		var bloc_name := String(ForeignSim.power(bloc_id).get("name", bloc_id))
		var current: Array = state.foreign.members.get(bloc_id, [])
		var next: Array = []
		for c in state.world:
			var member: bool = c.id in current
			var stays := c.id == anchor or (not bloc_rejects(state, c, b) if member else bloc_fits(state, c, b))
			if stays:
				next.append(c.id)
			if stays != member:
				notes.append(line("bloc_join" if stays else "bloc_leave", {"country": c.name, "bloc": bloc_name}))
		state.foreign.members[bloc_id] = next
