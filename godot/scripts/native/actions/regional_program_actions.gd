class_name RegionalProgramActions
extends RefCounted


static func options_for(state: GameState, region_id: String, content: Dictionary) -> Array:
	var definitions := _definitions(content)
	var ids: Array = definitions.keys()
	ids.sort()
	var rows: Array = []
	for raw_id in ids:
		var program_id := String(raw_id)
		var definition: Dictionary = definitions[program_id]
		var reason := _disabled_reason(state, region_id, program_id, definition)
		rows.append({
			"id": program_id,
			"name": String(definition.get("name", program_id.capitalize())),
			"short_name": String(definition.get("short_name", definition.get("name", program_id.capitalize()))),
			"body": String(definition.get("body", "")),
			"portfolio": String(definition.get("portfolio", "")),
			"pc_cost": float(definition.get("pc_cost", 0.0)),
			"duration": int(definition.get("duration", 0)),
			"monthly_cost": float(definition.get("monthly_cost", 0.0)),
			"eligible": reason.is_empty(),
			"disabled_reason": reason,
		})
	return rows


static func start(state: GameState, region_id: String, program_id: String,
		content: Dictionary) -> Dictionary:
	var definitions := _definitions(content)
	if not definitions.has(program_id):
		return _fail("Unknown regional programme.")
	var definition: Dictionary = definitions[program_id]
	var reason := _disabled_reason(state, region_id, program_id, definition)
	if not reason.is_empty():
		return _fail(reason)

	var region: RegionState = state.regions[region_id]
	var cost := float(definition.get("pc_cost", 0.0))
	var programme := RegionState.RegionalProgram.new()
	programme.id = "%s:%s:%d" % [program_id, region_id, state.turn]
	programme.program_id = program_id
	programme.region_id = region_id
	programme.started_turn = state.turn
	programme.duration = int(definition.get("duration", 0))
	programme.monthly_cost = float(definition.get("monthly_cost", 0.0))

	state.player.political_capital -= cost
	region.pressure = clampf(region.pressure + float(definition.get("launch_pressure", 0.0)), 0.0, 1.0)
	var loyalty_raw: Variant = definition.get("faction_loyalty_deltas", {})
	if loyalty_raw is Dictionary:
		for faction in state.country.factions:
			if (loyalty_raw as Dictionary).has(faction.id):
				faction.loyalty = clampf(faction.loyalty + float((loyalty_raw as Dictionary)[faction.id]), -1.0, 1.0)
	state.regional_programs.append(programme)

	var modifier := Modifier.new()
	modifier.id = "regional_program_%s" % programme.id
	modifier.source = "%s (%s)" % [String(definition.get("name", program_id)), _region_name(content, region_id)]
	modifier.target = "budget_expenditure"
	modifier.magnitude = programme.monthly_cost * 12.0
	modifier.onset_delay = 0
	modifier.ramp_duration = 1
	modifier.hold_duration = programme.duration
	modifier.decay_duration = 0
	modifier.source_id = programme.id
	modifier.institutional = false
	state.modifiers.append(modifier)
	return {"ok": true, "program_id": program_id, "region_id": region_id}


static func _disabled_reason(state: GameState, region_id: String, _program_id: String,
		definition: Dictionary) -> String:
	if state == null or state.player == null or state.country == null:
		return "No campaign is active."
	if not state.player.in_government:
		return "Regional programmes can only be launched from government."
	if BudgetSim.is_emergency(state):
		return "No new programmes can start while the state runs on an emergency budget. Pass a budget first."
	if not state.regions.has(region_id) or not (state.regions[region_id] is RegionState):
		return "Unknown region."
	for active in state.regional_programs:
		if active is RegionState.RegionalProgram and active.region_id == region_id:
			return "This region already has an active programme."
	var allowed_raw: Variant = definition.get("allowed_regions", [])
	if allowed_raw is Array and not (allowed_raw as Array).is_empty() and not region_id in (allowed_raw as Array):
		return "This programme is not available in the selected region."
	var region: RegionState = state.regions[region_id]
	var blocked_raw: Variant = definition.get("blocked_controls", [])
	if blocked_raw is Array and region.control in (blocked_raw as Array):
		return "The government cannot operate this programme under the region's current control."
	var cost := float(definition.get("pc_cost", 0.0))
	if state.player.political_capital < cost:
		return "Requires %.0f political capital." % cost
	return ""


static func _definitions(content: Dictionary) -> Dictionary:
	var catalogs_raw: Variant = content.get("catalogs", {})
	if not (catalogs_raw is Dictionary):
		return {}
	var regional_raw: Variant = (catalogs_raw as Dictionary).get("regions_and_programs", {})
	if not (regional_raw is Dictionary):
		return {}
	var definitions_raw: Variant = (regional_raw as Dictionary).get("regional_programs", {})
	return definitions_raw as Dictionary if definitions_raw is Dictionary else {}


static func _region_name(content: Dictionary, region_id: String) -> String:
	var catalogs: Dictionary = content.get("catalogs", {})
	var regional: Dictionary = catalogs.get("regions_and_programs", {})
	var profiles: Dictionary = regional.get("region_profiles", {})
	var profile: Dictionary = profiles.get(region_id, {})
	return String(profile.get("name", region_id.capitalize()))


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
