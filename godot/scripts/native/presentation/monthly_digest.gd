class_name MonthlyDigest
extends RefCounted

## Pure completed-month report builder. Capture and build are read-only; only
## NativeGame stores the returned Array[String] on GameState after a pulse.

const HouseholdsSimScript = preload("res://scripts/native/sim/households_sim.gd")
const StabilitySimScript = preload("res://scripts/native/sim/stability_sim.gd")

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
	}

static func build(state: GameState, before: Dictionary) -> Array[String]:
	if before.is_empty():
		return []
	var after := capture(state)
	var lines: Array[String] = []
	_append_change(lines, "Public approval", float(before.get("approval", 0.0)), float(after["approval"]), 0.002, true)
	_append_change(lines, "Government stability", float(before.get("stability", 0.0)), float(after["stability"]), 0.002, true)
	_append_change(lines, "Inflation", float(before.get("inflation", 0.0)), float(after["inflation"]), 0.002, false)
	_append_change(lines, "Regional pressure", float(before.get("regional_pressure", 0.0)), float(after["regional_pressure"]), 0.003, false)
	_append_change(lines, "Household hardship", float(before.get("household_hardship", 0.0)), float(after["household_hardship"]), 0.003, false)
	return lines

static func _append_change(lines: Array[String], label: String, before: float, after: float, threshold: float, higher_is_better: bool) -> void:
	var delta := after - before
	if absf(delta) < threshold:
		return
	var improves := delta > 0.0 if higher_is_better else delta < 0.0
	var direction := "improves" if improves else "deteriorates"
	lines.append("%s %s (%+.1f points)." % [label, direction, delta * 100.0])