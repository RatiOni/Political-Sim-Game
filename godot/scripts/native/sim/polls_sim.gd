class_name PollsSim
extends RefCounted


const MONTHLY_CAP := 0.01
const SUPPORT_FLOOR := 0.01
const ORDINARY_APPROVAL := 0.47
const ORDINARY_CONFIDENCE := 0.445
const ORDINARY_MISERY := 0.007
const ORDINARY_STABILITY := 0.52
const APPROVAL_WEIGHT := 0.012
const CONFIDENCE_WEIGHT := 0.010
const MISERY_WEIGHT := 0.06
const PARTNER_SHARE := 0.5
const REVERSION := 0.03
const PROXIMITY_FLOOR := 0.05
const STABILITY_IN_PROXY := 0.5


static func monthly(state: GameState) -> String:
	var factions := state.country.factions
	if factions.is_empty():
		return ""
	_ensure_base(state)
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


static func record(state: GameState) -> float:
	return (government_approval(state) - ORDINARY_APPROVAL) * APPROVAL_WEIGHT \
		+ (HouseholdsSim.national_confidence(state) - ORDINARY_CONFIDENCE) * CONFIDENCE_WEIGHT \
		- (misery_gap(state) - ORDINARY_MISERY) * MISERY_WEIGHT


static func misery_gap(state: GameState) -> float:
	var econ := state.country.economy
	return (econ.inflation + econ.unemployment) - (econ.structural_inflation + econ.natural_unemployment)


static func government_approval(state: GameState) -> float:
	if state.player.in_government:
		return state.player.approval
	return clampf(ORDINARY_APPROVAL + (HouseholdsSim.national_confidence(state) - ORDINARY_CONFIDENCE)
		+ (state.stability_value - ORDINARY_STABILITY) * STABILITY_IN_PROXY, 0.0, 1.0)


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
	var change := record(state)
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


static func _ensure_base(state: GameState) -> void:
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
