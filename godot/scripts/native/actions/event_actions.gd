class_name EventActions
extends RefCounted


static func resolve(state: GameState, event_id: String, option_id: String) -> Dictionary:
	if state == null or state.player == null:
		return _error("No campaign is active.")
	var situation := _pending(state, event_id)
	if situation == null:
		return _error("That situation is not waiting on a decision.")
	var event := EventsSim.event_by_id(event_id)
	if not EventsSim.audience_ok(state, event):
		return _error("This is a matter for the government, not the opposition.")
	var option := EventsSim.option_by_id(event, option_id)
	if option.is_empty():
		return _error("That is not one of the choices.")
	var reason := option_reason(state, option, situation.target_country_id)
	if reason != "":
		return _error(reason)
	state.player.political_capital -= float(option.get("pc_cost", 0.0))
	state.pending_situations.erase(situation)
	var line := EventsSim.apply_option(state, event, option, situation, false)
	var message := "%s: %s." % [String(event.get("title", event_id)), String(option.get("label", option_id))]
	if line != "":
		message += " " + line
	return {"ok": true, "message": message}


static func option_reason(state: GameState, option: Dictionary, target := "") -> String:
	var gate := EventsSim.gate_reason(state, option, target)
	if gate != "":
		return gate
	var cost := float(option.get("pc_cost", 0.0))
	if state.player.political_capital < cost:
		return "Requires %.0f political capital." % cost
	return ""


static func read_model(state: GameState) -> Array:
	var rows: Array = []
	if state == null:
		return rows
	for situation in state.pending_situations:
		var event := EventsSim.event_by_id(situation.event_id)
		if event.is_empty() or not EventsSim.audience_ok(state, event):
			continue
		var options: Array = []
		for option in event.get("options", []):
			var reason := option_reason(state, option, situation.target_country_id)
			options.append({
				"id": String(option.get("id", "")),
				"label": String(option.get("label", "")),
				"description": String(option.get("description", "")),
				"pc_cost": float(option.get("pc_cost", 0.0)),
				"eligible": reason == "",
				"disabled_reason": reason,
				"is_default": String(option.get("id", "")) == String(event.get("default_option_id", "")),
			})
		rows.append({
			"event_id": situation.event_id,
			"arrived_turn": situation.arrived_turn,
			"title": String(event.get("title", "")),
			"description": String(event.get("description", "")),
			"category": String(event.get("category", "")),
			"months_left": maxi(0, situation.deadline_turn - state.turn),
			"target_country": _country_name(state, situation.target_country_id),
			"options": options,
		})
	return rows


static func _pending(state: GameState, event_id: String) -> Situation:
	for s in state.pending_situations:
		if s.event_id == event_id:
			return s
	return null


static func _country_name(state: GameState, country_id: String) -> String:
	for c in state.world:
		if c.id == country_id:
			return c.name
	return ""


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
