class_name MonthlyDigest
extends RefCounted

## The month's report on what keeps a government in office. Lines run in order
## of consequence — an emergency budget first — and approval, stability and
## hardship say what moved them, so the report reads as an account rather than
## a list of numbers.

const HouseholdsSimScript = preload("res://scripts/native/sim/households_sim.gd")
const StabilitySimScript = preload("res://scripts/native/sim/stability_sim.gd")

## A term has to move at least this much in a month to be named as the cause.
const CAUSE_THRESHOLD := 0.001


static func capture(state: GameState) -> Dictionary:
	var econ := state.country.economy
	return {
		"approval": state.player.approval,
		"stability": state.stability_value,
		"growth": econ.growth_rate,
		"unemployment": econ.unemployment,
		"inflation": econ.inflation,
		"regional_pressure": StabilitySimScript.national_pressure(state),
		"household_confidence": HouseholdsSimScript.national_confidence(state),
		"household_hardship": HouseholdsSimScript.national_hardship(state),
		"debt": econ.public_debt_pct,
		"approval_terms": StabilitySimScript.approval_breakdown(state),
		"stability_terms": StabilitySimScript.stability_breakdown(state),
	}


static func build(state: GameState, before: Dictionary) -> Array[String]:
	if before.is_empty():
		return []
	var after := capture(state)
	var lines: Array[String] = []
	if BudgetSim.is_emergency(state):
		lines.append("The state is running on an emergency budget (month %d): no new programmes, every ministry overloaded, and the cost rises each month. Pass a budget to end it." % maxi(1, state.active_budget.emergency_months))
	var approval_delta := float(after["approval"]) - float(before.get("approval", 0.0))
	_append_change(lines, "Public approval", float(before.get("approval", 0.0)), float(after["approval"]), 0.002, true,
		_cause(before.get("approval_terms", {}), after["approval_terms"], approval_delta))
	var stability_delta := float(after["stability"]) - float(before.get("stability", 0.0))
	_append_change(lines, "Government stability", float(before.get("stability", 0.0)), float(after["stability"]), 0.002, true,
		_cause(before.get("stability_terms", {}), after["stability_terms"], stability_delta))
	_append_change(lines, "Inflation", float(before.get("inflation", 0.0)), float(after["inflation"]), 0.002, false)
	_append_change(lines, "Regional pressure", float(before.get("regional_pressure", 0.0)), float(after["regional_pressure"]), 0.003, false)
	var hardship_before := float(before.get("household_hardship", 0.0))
	var hardship_after := float(after["household_hardship"])
	_append_change(lines, "Household hardship", hardship_before, hardship_after, 0.003, false,
		_hardest_hit(state) if hardship_after > hardship_before else "")
	_append_change(lines, "Public debt", float(before.get("debt", after["debt"])), float(after["debt"]), 0.002, false)
	return lines


static func _append_change(lines: Array[String], label: String, before: float, after: float, threshold: float, higher_is_better: bool, cause: String = "") -> void:
	var delta := after - before
	if absf(delta) < threshold:
		return
	var improves := delta > 0.0 if higher_is_better else delta < 0.0
	var direction := "improves" if improves else "deteriorates"
	lines.append("%s %s (%+.1f points)%s." % [label, direction, delta * 100.0, cause])


## The term that moved the reading the way it went; for a fall with nothing
## moving, the heaviest drag on it. A rise with nothing moving names nothing:
## the largest positive term is structural and saying it every month says
## nothing.
static func _cause(before_terms: Dictionary, after_terms: Dictionary, delta: float) -> String:
	if after_terms.is_empty() or delta == 0.0:
		return ""
	var direction := signf(delta)
	var moved := ""
	var moved_by := CAUSE_THRESHOLD
	for term in after_terms:
		var change := (float(after_terms[term]) - float(before_terms.get(term, after_terms[term]))) * direction
		if change > moved_by:
			moved = String(term)
			moved_by = change
	if moved != "":
		return ", driven by %s" % moved.to_lower()
	if direction > 0.0:
		return ""
	var heaviest := ""
	var weight := 0.0
	for term in after_terms:
		if float(after_terms[term]) < weight:
			heaviest = String(term)
			weight = float(after_terms[term])
	return ", weighed down by %s" % heaviest.to_lower() if heaviest != "" else ""


static func _hardest_hit(state: GameState) -> String:
	var worst: Array = HouseholdsSimScript.hardest_hit(state, 1)
	if worst.is_empty():
		return ""
	var household: HouseholdGroupState = worst[0]
	var catalogs: Dictionary = ContentRepository.load_all().get("catalogs", {})
	var group_name := household.group_id.capitalize()
	for group in catalogs.get("household_groups", {}).get("groups", []):
		if String(group.get("id", "")) == household.group_id:
			group_name = String(group.get("name", group_name))
	var profile: Dictionary = catalogs.get("regions_and_programs", {}).get("region_profiles", {}).get(household.region_id, {})
	var region_name := String(profile.get("name", household.region_id.capitalize()))
	return ", hardest for %s in %s" % [group_name.to_lower(), region_name]
