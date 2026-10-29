class_name OrientationActions
extends RefCounted


const VERBS := ["concert_application", "concert_agreement", "meridian_partnership", "meridian_guarantee",
	"union_observer", "union_member", "union_leave", "isf_renegotiate"]
const COSTS := {
	"concert_application": 5.0, "concert_agreement": 25.0, "meridian_partnership": 15.0,
	"meridian_guarantee": 30.0, "union_observer": 10.0, "union_member": 20.0,
	"union_leave": 0.0, "isf_renegotiate": 15.0,
}
const LABELS := {"union_leave": "Leave the Union", "isf_renegotiate": "Renegotiate the ISF terms"}
const TREASURY_DEBT := {"concert_agreement": 0.003, "meridian_partnership": 0.001, "meridian_guarantee": 0.002}
const REACTIONS := {
	"concert_agreement": {"krasova": -0.08},
	"meridian_partnership": {"krasova": -0.06},
	"meridian_guarantee": {"krasova": -0.15},
	"union_observer": {"krasova": 0.08, "bloc:concert": -0.03},
	"union_member": {"krasova": 0.10, "bloc:concert": -0.06},
}
const PLAYER_BLOCS := {"concert": "concert_agreement", "meridian": "meridian_guarantee", "union": "union_member"}
const QUALIFYING_MONTHS_FOR_AGREEMENT := 36
const PARTNERSHIP_MONTHS_FOR_GUARANTEE := 24
const OBSERVER_MONTHS_FOR_MEMBERSHIP := 12
const OBSERVER_WARMTH := -0.35
const MEMBER_WARMTH := -0.15
const UNION_REJOIN_MONTHS := 60
const CONCERT_GROWTH := 0.002
const CONCERT_GROWTH_RAMP := 24
const UNION_GROWTH := 0.003
const UNION_GROWTH_RAMP := 12
const UNION_RESCHEDULING := 60.0
const UNION_RESCHEDULING_MONTHS := 36
const PARTNERSHIP_STABILITY := 0.01
const GUARANTEE_STABILITY := 0.03
const STABILITY_CEILING := 0.95
const EXIT_RELATIONS_COST := -0.35
const OBSERVER_EXIT_COST := -0.10
const EXIT_STABILITY_COST := 0.04
const EXIT_GROWTH_COST := -0.004
const EXIT_GROWTH_MONTHS := 12
const EXIT_GROWTH_DECAY := 6


static func act(state: GameState, verb: String) -> Dictionary:
	var reason := reason_for(state, verb)
	if reason != "":
		return {"ok": false, "error": reason}
	state.player.political_capital -= float(COSTS[verb])
	var message := ""
	match verb:
		"isf_renegotiate":
			message = _renegotiate(state)
		"union_leave":
			message = _leave_union(state)
		_:
			message = _reach(state, verb)
	_react(state, verb)
	ForeignSim.update_spine(state)
	return {"ok": true, "message": message}


static func label_for(verb: String) -> String:
	return String(LABELS[verb]) if LABELS.has(verb) else ForeignSim.milestone_name(verb)


static func lock_reason(state: GameState, verb: String) -> String:
	var reached := state.foreign.reached
	if verb in ForeignSim.UNION_LOCKS and reached.has("union_member"):
		return "A Union member cannot take Western steps beyond partnership."
	if verb == "union_member":
		for locked in ForeignSim.UNION_LOCKS:
			if reached.has(locked):
				return "Union membership is incompatible with the %s." % ForeignSim.milestone_name(locked)
	return ""


static func reason_for(state: GameState, verb: String) -> String:
	if state == null or state.player == null:
		return "No campaign is active."
	if not COSTS.has(verb):
		return "Unknown orientation step."
	if not state.player.in_government:
		return "Foreign policy belongs to the government."
	if state.foreign == null or not state.foreign.seeded:
		return "The foreign ledger is not ready."
	var lock := lock_reason(state, verb)
	if lock != "":
		return lock
	var standing := _standing_reason(state, verb)
	if standing != "":
		return standing
	var condition := _condition_reason(state, verb)
	if condition != "":
		return condition
	if state.player.political_capital < float(COSTS[verb]):
		return "Requires %.0f political capital." % float(COSTS[verb])
	return ""


static func consent_reason(state: GameState, verb: String, country_id: String) -> String:
	if state.foreign == null or not state.foreign.reached.has("union_member"):
		return ""
	var in_union: bool = country_id in state.foreign.members.get("union", [])
	if verb in ["impose_sanctions", "condemn"] and in_union:
		return "The Union withholds its consent: you cannot turn on a fellow member."
	if verb == "defense_pact" and not in_union:
		return "The Union withholds its consent to a defence pact outside the bloc."
	return ""


static func _standing_reason(state: GameState, verb: String) -> String:
	var f := state.foreign
	match verb:
		"isf_renegotiate":
			if not bool(f.isf.get("suspended", false)):
				return "The ISF programme is not suspended; there is nothing to renegotiate."
		"union_leave":
			if not f.reached.has("union_observer"):
				return "Ardenia is not part of the Union."
		_:
			if f.reached.has(verb):
				return "%s is already in place." % ForeignSim.milestone_name(verb)
	return ""


static func _condition_reason(state: GameState, verb: String) -> String:
	var f := state.foreign
	match verb:
		"concert_agreement":
			if not f.reached.has("concert_application"):
				return "Apply for association first."
			if f.western_qualifying_months < QUALIFYING_MONTHS_FOR_AGREEMENT:
				return "The Concert wants %d months of budget discipline; Ardenia has %d." % [
					QUALIFYING_MONTHS_FOR_AGREEMENT, f.western_qualifying_months]
			if not OrientationSim.bank_independent(state):
				return "The Concert requires an independent central bank."
		"meridian_guarantee":
			if not f.reached.has("meridian_partnership"):
				return "Join the Meridian partnership first."
			var held := _months_held(state, "meridian_partnership")
			if held < PARTNERSHIP_MONTHS_FOR_GUARANTEE:
				return "The partnership must run %d months before a guarantee (%d so far)." % [
					PARTNERSHIP_MONTHS_FOR_GUARANTEE, held]
			if not ForeignSim.vetrenka_resolved(state):
				return "Meridian will not guarantee a country with an active territorial dispute."
		"union_observer":
			if f.union_left_turn >= 0 and state.turn - f.union_left_turn < UNION_REJOIN_MONTHS:
				return "Krasova will not readmit Ardenia for %d more months." % [
					UNION_REJOIN_MONTHS - (state.turn - f.union_left_turn)]
			if _krasova_warmth(state) < OBSERVER_WARMTH:
				return "Krasova will not seat an observer at this level of hostility (needs %.2f)." % OBSERVER_WARMTH
		"union_member":
			if not f.reached.has("union_observer"):
				return "Take observer status first."
			var observed := _months_held(state, "union_observer")
			if observed < OBSERVER_MONTHS_FOR_MEMBERSHIP:
				return "Observer status must run %d months before membership (%d so far)." % [
					OBSERVER_MONTHS_FOR_MEMBERSHIP, observed]
			if _krasova_warmth(state) < MEMBER_WARMTH:
				return "Krasova will not admit a member at this level of hostility (needs %.2f)." % MEMBER_WARMTH
	return ""


static func _months_held(state: GameState, milestone_id: String) -> int:
	return state.turn - int(state.foreign.reached.get(milestone_id, state.turn))


static func _krasova_warmth(state: GameState) -> float:
	var p := DiplomacySim.pair(state, "krasova")
	return -1.0 if p.is_empty() else (p[0] as Country.BilateralRelation).score


static func _reach(state: GameState, verb: String) -> String:
	state.foreign.reached[verb] = state.turn
	var debt := float(TREASURY_DEBT.get(verb, 0.0))
	if debt > 0.0:
		EffectBundle.apply(state, {"one_time_debt_pct_delta": debt}, "orientation", verb)
	match verb:
		"concert_agreement":
			state.modifiers.append(_phased(verb, "Concert association", CONCERT_GROWTH, CONCERT_GROWTH_RAMP))
		"meridian_partnership":
			state.stability_value = minf(STABILITY_CEILING, state.stability_value + PARTNERSHIP_STABILITY)
		"meridian_guarantee":
			state.stability_value = minf(STABILITY_CEILING, state.stability_value + GUARANTEE_STABILITY)
		"union_member":
			GasSim.cap_to_union(state)
			state.modifiers.append(_phased(verb, "Krasovan Economic Union", UNION_GROWTH, UNION_GROWTH_RAMP))
			var rescheduling := OrientationSim.timed_modifier("union_rescheduling", "Union debt rescheduling",
				"budget_expenditure", -UNION_RESCHEDULING, UNION_RESCHEDULING_MONTHS - 1, false)
			rescheduling.source_id = verb
			state.modifiers.append(rescheduling)
	return "%s. %s" % [ForeignSim.milestone_name(verb), String(ForeignSim.milestone(verb).get("body", ""))]


static func _phased(source_id: String, source: String, magnitude: float, ramp: int) -> Modifier:
	var m := Modifier.new()
	m.id = "%s_growth" % source_id
	m.source = source
	m.target = "gdp_growth"
	m.magnitude = magnitude
	m.onset_delay = 3
	m.ramp_duration = ramp
	m.hold_duration = Modifier.HOLDS_FOREVER
	m.source_id = source_id
	m.portfolio = "Foreign Affairs"
	return m


static func _react(state: GameState, verb: String) -> void:
	var deltas: Dictionary = REACTIONS.get(verb, {})
	for key in deltas:
		var k := String(key)
		var targets: Array = state.foreign.members.get(k.trim_prefix("bloc:"), []) if k.begins_with("bloc:") else [k]
		for id in targets:
			DiplomacySim.shift(state, String(id), float(deltas[key]), "Reacted to %s." % label_for(verb))


static func _renegotiate(state: GameState) -> String:
	var isf := state.foreign.isf
	isf["renegotiations"] = int(isf.get("renegotiations", 0)) + 1
	isf["suspended"] = false
	OrientationSim.release_tranche(state, "ISF disbursement after renegotiation")
	var targets := OrientationSim.isf_targets(state)
	return "The ISF agrees new terms and releases the held tranche. From the next review it wants a deficit under %.1f%% and inflation under %.1f%%." % [
		float(targets["deficit"]) * 100.0, float(targets["inflation"]) * 100.0]


static func _leave_union(state: GameState) -> String:
	var f := state.foreign
	var was_member := f.reached.has("union_member")
	f.reached.erase("union_member")
	f.reached.erase("union_observer")
	f.union_left_turn = state.turn
	if not was_member:
		DiplomacySim.shift(state, "krasova", OBSERVER_EXIT_COST, "Ardenia gave up its Union seat.")
		return "Ardenia gives up its observer seat in the Krasovan Economic Union. Krasova notes the date."
	state.modifiers = state.modifiers.filter(func(m: Modifier) -> bool: return m.source_id != "union_member")
	state.stability_value = maxf(0.0, state.stability_value - EXIT_STABILITY_COST)
	var shock := OrientationSim.timed_modifier("union_exit_%d" % state.turn, "Union exit", "gdp_growth",
		EXIT_GROWTH_COST, EXIT_GROWTH_MONTHS, true)
	shock.decay_duration = EXIT_GROWTH_DECAY
	state.modifiers.append(shock)
	DiplomacySim.shift(state, "krasova", EXIT_RELATIONS_COST, "Ardenia walked out of the Union.")
	return "Ardenia walks out of the Krasovan Economic Union. Tariffs return overnight, and Krasova calls it betrayal."


static func memberships(state: GameState) -> Dictionary:
	var out := {}
	for bloc_id in state.foreign.members:
		for country_id in state.foreign.members[bloc_id]:
			if not out.has(country_id):
				out[country_id] = []
			(out[country_id] as Array).append(String(bloc_id))
	var own: Array = []
	for bloc_id in PLAYER_BLOCS:
		if state.foreign.reached.has(PLAYER_BLOCS[bloc_id]):
			own.append(bloc_id)
	out[state.country.id] = own
	return out


static func read_model(state: GameState) -> Dictionary:
	if state == null or state.foreign == null or not state.foreign.seeded:
		return {"powers": [], "steps": [], "isf": {}, "western_qualifying_months": 0,
			"qualifying_months_needed": QUALIFYING_MONTHS_FOR_AGREEMENT, "map": {"memberships": {}}}
	var powers: Array = []
	for id in ForeignSim.power_ids():
		var row: Dictionary = state.foreign.powers.get(id, {})
		var p := ForeignSim.power(id)
		powers.append({"id": id, "name": String(p.get("name", id)), "kind": String(p.get("kind", "")),
			"dependence": float(row.get("dependence", 0.0)), "commitment": float(row.get("commitment", 0.0)),
			"leverage": float(row.get("leverage", 0.0))})
	var steps: Array = []
	for verb in VERBS:
		var held := state.foreign.reached.has(verb)
		var reason := reason_for(state, verb)
		steps.append({"verb": verb, "label": label_for(verb), "cost": float(COSTS[verb]), "held": held,
			"eligible": reason == "", "disabled_reason": "" if held else reason})
	var isf := state.foreign.isf
	var targets := OrientationSim.isf_targets(state)
	return {
		"powers": powers,
		"steps": steps,
		"isf": {
			"reviews_held": int(isf.get("reviews_held", 0)),
			"reviews_total": OrientationSim.ISF_REVIEWS,
			"passed": int(isf.get("passed", 0)),
			"failed": int(isf.get("failed", 0)),
			"suspended": bool(isf.get("suspended", false)),
			"last_result": String(isf.get("last_result", "")),
			"deficit_target": float(targets["deficit"]),
			"inflation_target": float(targets["inflation"]),
			"bank_required": int(isf.get("reviews_held", 0)) >= int(targets["bank_due_review"]),
		},
		"western_qualifying_months": state.foreign.western_qualifying_months,
		"qualifying_months_needed": QUALIFYING_MONTHS_FOR_AGREEMENT,
		"map": {"memberships": memberships(state)},
	}
