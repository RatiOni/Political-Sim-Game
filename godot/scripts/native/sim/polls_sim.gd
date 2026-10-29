class_name PollsSim
extends RefCounted


const MONTHLY_CAP := 0.01
const SUPPORT_FLOOR := 0.01
const ORDINARY_GOVERNMENT := {"approval": 0.45, "confidence": 0.42, "misery": -0.009, "stability": 0.496}
const ORDINARY_OPPOSITION_LEADER_APPROVAL := 0.43
const APPROVAL_WEIGHT := 0.025
const CONFIDENCE_WEIGHT := 0.02
const MISERY_WEIGHT := 0.06
const PARTNER_SHARE := 0.5
const REVERSION := 0.03
const PROXIMITY_FLOOR := 0.05
const STABILITY_IN_PROXY := 0.5


static func monthly(state: GameState) -> String:
	var factions := state.country.factions
	if factions.is_empty():
		return ""
	ensure_base(state)
	var before := {}
	for f in factions:
		before[f.id] = f.support
	var deltas := _record_deltas(state)
	for f in factions:
		deltas[f.id] = float(deltas[f.id]) + (float(state.support_base.get(f.id, f.support)) - f.support) * REVERSION
	var scale := 1.0
	for f in factions:
		var d := float(deltas[f.id])
		if absf(d) > MONTHLY_CAP:
			scale = minf(scale, MONTHLY_CAP / absf(d))
		if d < 0.0:
			scale = minf(scale, maxf(0.0, f.support - SUPPORT_FLOOR) / -d)
	for f in factions:
		f.support = maxf(SUPPORT_FLOOR, f.support + float(deltas[f.id]) * scale)
	_renormalise(state)
	return poll_line(state, before)


const RULING_COST_PER_TERM := 0.022
const BROKEN_PLEDGE_WEIGHT := 0.5
const SCANDAL_WEIGHT := 0.75
const EMERGENCY_WEIGHT := 2.0
const DEFEAT_WEIGHT := 1.0
const TROUBLE_MEMORY_MONTHS := 12
const SCANDAL_EVENTS := ["cabinet_corruption_expose", "corruption_expose_media", "corruption_trial", "defection_drama"]


static func ruling_cost(state: GameState) -> float:
	return RULING_COST_PER_TERM / float(Elections.TERM_MONTHS) * (1.0 + trouble(state))


static func trouble(state: GameState) -> float:
	var weight := 0.0
	if BudgetSim.is_emergency(state):
		weight += EMERGENCY_WEIGHT
	for law in state.law_history:
		if law.status == "rejected" and law.proposed_by == state.ruling_faction_id \
				and state.turn - law.proposed_turn < TROUBLE_MEMORY_MONTHS:
			weight += DEFEAT_WEIGHT
	if state.player.in_government:
		for p in state.opposition.pledges:
			if String(p.get("status", "")) == "broken":
				weight += BROKEN_PLEDGE_WEIGHT
		for row in state.event_history:
			var recent := state.turn - int(row.get("turn", -999)) < TROUBLE_MEMORY_MONTHS
			if recent and String(row.get("event_id", "")) in SCANDAL_EVENTS:
				weight += SCANDAL_WEIGHT
	return weight


static func record(state: GameState) -> float:
	var ordinary := ordinary_government(state)
	return (government_approval(state) - float(ordinary["approval"])) * APPROVAL_WEIGHT \
		+ (HouseholdsSim.national_confidence(state) - float(ordinary["confidence"])) * CONFIDENCE_WEIGHT \
		- (misery_gap(state) - float(ordinary["misery"])) * MISERY_WEIGHT


const INHERITANCE_KEY := "inheritance"
const INHERITANCE_FADE_MONTHS := 72.0
const MEASURES := ["approval", "confidence", "misery", "stability"]


static func ordinary_government(state: GameState) -> Dictionary:
	var inherited := inheritance(state)
	var fade := exp(-float(state.turn - int(inherited["turn"])) / INHERITANCE_FADE_MONTHS)
	var expected := {}
	for key in MEASURES:
		var ordinary := float(ORDINARY_GOVERNMENT[key])
		expected[key] = ordinary + (float(inherited[key]) - ordinary) * fade
	return expected


static func inheritance(state: GameState) -> Dictionary:
	var inherited: Variant = state.campaign_meta.get(INHERITANCE_KEY, {})
	if inherited is Dictionary and String(inherited.get("party", "")) == state.ruling_faction_id:
		return inherited
	var fresh := {"party": state.ruling_faction_id, "turn": state.turn, "approval": government_approval(state),
		"confidence": HouseholdsSim.national_confidence(state), "misery": misery_gap(state), "stability": state.stability_value}
	state.campaign_meta[INHERITANCE_KEY] = fresh
	return fresh


static func misery_gap(state: GameState) -> float:
	var econ := state.country.economy
	return (econ.inflation + econ.unemployment) - (econ.structural_inflation + econ.natural_unemployment)


static func government_approval(state: GameState) -> float:
	if state.player.in_government:
		return state.player.approval
	var ordinary := ORDINARY_GOVERNMENT
	return clampf(float(ordinary["approval"]) + (HouseholdsSim.national_confidence(state) - float(ordinary["confidence"]))
		+ (state.stability_value - float(ordinary["stability"])) * STABILITY_IN_PROXY, 0.0, 1.0)


static func public_mood(state: GameState) -> Faction.Ideology:
	var mood := Faction.Ideology.new()
	var total := 0.0
	for f in state.country.factions:
		var ideology := f.effective_ideology()
		mood.economic += ideology.economic * f.support
		mood.social += ideology.social * f.support
		total += f.support
	if total > 0.0:
		mood.economic /= total
		mood.social /= total
	return mood


static func poll_line(state: GameState, before: Dictionary) -> String:
	var ranked := state.country.factions.duplicate()
	ranked.sort_custom(func(a: Faction, b: Faction) -> bool: return a.support > b.support or (a.support == b.support and a.id < b.id))
	var parts: Array[String] = []
	for f in ranked:
		parts.append("%s %.1f%% (%+.1f)" % [f.name, f.support * 100.0, (f.support - float(before.get(f.id, f.support))) * 100.0])
	return "Polls: %s." % ", ".join(parts)


static func _record_deltas(state: GameState) -> Dictionary:
	var change := record(state) - ruling_cost(state)
	var deltas := {}
	var government_total := 0.0
	var mood := public_mood(state)
	var weights := {}
	var weight_total := 0.0
	for f in state.country.factions:
		deltas[f.id] = 0.0
		if f.id == state.ruling_faction_id:
			deltas[f.id] = change
		elif f.in_coalition:
			deltas[f.id] = change * PARTNER_SHARE
		else:
			var w := maxf(PROXIMITY_FLOOR, 1.0 - f.effective_ideology().distance_to(mood) / ParliamentaryVote.MAX_DISTANCE)
			weights[f.id] = w
			weight_total += w
		government_total += float(deltas[f.id])
	for id in weights:
		deltas[id] = -government_total * float(weights[id]) / weight_total
	return deltas


static func ensure_base(state: GameState) -> void:
	if not state.support_base.is_empty():
		return
	for f in state.country.factions:
		state.support_base[f.id] = f.support


static func _renormalise(state: GameState) -> void:
	var target := 0.0
	var total := 0.0
	for f in state.country.factions:
		target += float(state.support_base.get(f.id, f.support))
		total += f.support
	if total <= 0.0:
		return
	for f in state.country.factions:
		f.support *= target / total
