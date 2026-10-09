class_name StabilitySim
extends RefCounted

## Deterministic approval and government-stability update for the native
## monthly pulse. This works over the Phase 2 typed state only: no premature
## Legislature or Cabinet wrapper is invented here.

const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")
const HouseholdsSimScript = preload("res://scripts/native/sim/households_sim.gd")

static func economic_signal(state: GameState) -> float:
	var econ := state.country.economy
	return (econ.growth_rate - 0.02) * 4.0 - econ.unemployment * 0.5 - econ.inflation * 0.3

static func national_pressure(state: GameState) -> float:
	if state.regions.is_empty():
		return 0.0
	var profiles := _region_profiles()
	var weighted := 0.0
	var total := 0.0
	for key in state.regions:
		var region: RegionState = state.regions[key] as RegionState
		if region == null:
			continue
		var profile: Variant = profiles.get(String(key), {})
		var weight := 1.0
		if profile is Dictionary:
			weight = float((profile as Dictionary).get("population_weight", 1.0))
		weighted += region.pressure * weight
		total += weight
	return weighted / total if total > 0.0 else 0.0

static func update_approval(state: GameState) -> void:
	if state.player == null or state.country == null or state.country.economy == null:
		return
	var faction_signal := 0.0
	var approval_bias := 0.0
	if state.player.in_government:
		var power_total := 0.0
		for faction in state.country.factions:
			power_total += faction.power
			faction_signal += faction.loyalty * faction.power
		if power_total > 0.0:
			faction_signal /= power_total
		for modifier in state.modifiers:
			if modifier.target == "approval_bias":
				approval_bias += modifier.current_value()
	var household_mood := (HouseholdsSimScript.national_confidence(state) - 0.5) * 2.0
	if not state.player.in_government:
		household_mood *= -1.0
	var target := 0.5 + economic_signal(state) * 0.25 + faction_signal * 0.15 + household_mood * 0.12 + approval_bias
	target = clampf(target, 0.05, 0.95)
	state.player.approval = clampf(state.player.approval + (target - state.player.approval) * 0.05, 0.0, 1.0)

static func stability_breakdown(state: GameState) -> Dictionary:
	var opposition := state.player != null and not state.player.in_government
	var members: Array = []
	for faction in state.country.factions:
		if faction.in_coalition:
			members.append(faction)
	var coalition_loyalty := 0.0
	var cohesion := 1.0
	if not members.is_empty():
		var loyalty_sum := 0.0
		var cohesion_sum := 0.0
		for faction in members:
			loyalty_sum += faction.loyalty
			cohesion_sum += faction.cohesion()
		coalition_loyalty = loyalty_sum / float(members.size())
		cohesion = cohesion_sum / float(members.size())
	var coalition_component := 0.5 if opposition else (coalition_loyalty + 1.0) * 0.5
	var cabinet_component := 0.5 if opposition else _cabinet_component(state)
	var risk := 0.0 if opposition else _cabinet_risk_fraction(state)
	var approval_component := 0.5 if opposition else state.player.approval
	var seats := 0
	var coalition_seats := 0
	for faction in state.country.factions:
		seats += faction.seats
		if faction.in_coalition:
			coalition_seats += faction.seats
	var majority := seats / 2 + 1
	var margin := float(coalition_seats - majority) / float(maxi(1, seats))
	var majority_component := clampf(0.5 + margin * 2.0, 0.0, 1.0)
	var economic_component := clampf(0.5 + economic_signal(state) * 0.5, 0.0, 1.0)
	var unrest := _unrest(state)
	return {
		"Coalition loyalty": coalition_component * 0.25,
		"Cabinet loyalty": cabinet_component * 0.20,
		"Parliamentary margin": majority_component * 0.20,
		"Public approval": approval_component * 0.15,
		"Economic conditions": economic_component * 0.10,
		"Cabinet dysfunction": -risk * 0.15,
		"Unrest": -unrest * 0.15,
		"Coalition cohesion": -(1.0 - cohesion) * 0.08,
	}

static func update_stability(state: GameState) -> void:
	if state.player == null or state.country == null or state.country.economy == null:
		return
	var breakdown := stability_breakdown(state)
	var target := 0.0
	for value in breakdown.values():
		target += float(value)
	target = clampf(target, 0.05, 0.95)
	state.stability_value = clampf(state.stability_value + (target - state.stability_value) * 0.06, 0.0, 1.0)

static func _cabinet_component(state: GameState) -> float:
	if state.ministers.is_empty():
		return 0.0
	var loyalty := 0.0
	var grandee_bonus := 0.0
	for minister in state.ministers:
		loyalty += minister.loyalty
		grandee_bonus += Minister.trait_effect(minister.trait_id, "stability_bonus")
	return minf(1.0, loyalty / float(state.ministers.size()) + grandee_bonus)

static func _cabinet_risk_fraction(state: GameState) -> float:
	if state.ministers.is_empty():
		return 0.0
	var threats := 0
	for minister in state.ministers:
		if minister.threat_level() > 0.5:
			threats += 1
	return float(threats) / float(state.ministers.size())

static func _unrest(state: GameState) -> float:
	var grievance := 0.0
	for faction in state.country.factions:
		grievance = maxf(grievance, faction.grievance_pressure())
	var unemployment := maxf(0.0, state.country.economy.unemployment - 0.10) * 3.0
	var region := maxf(0.0, national_pressure(state) - 0.45) * 0.50
	var household := maxf(0.0, HouseholdsSimScript.national_hardship(state) - 0.35) * 0.35
	return clampf(grievance * 0.60 + unemployment + region + household, 0.0, 1.0)

static func _region_profiles() -> Dictionary:
	var content: Dictionary = ContentRepositoryScript.load_all()
	var catalogs: Variant = content.get("catalogs", {})
	if not (catalogs is Dictionary):
		return {}
	var regions: Variant = (catalogs as Dictionary).get("regions_and_programs", {})
	if not (regions is Dictionary):
		return {}
	var profiles: Variant = (regions as Dictionary).get("region_profiles", {})
	return profiles as Dictionary if profiles is Dictionary else {}