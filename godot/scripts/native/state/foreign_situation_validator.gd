class_name ForeignSituationValidator
extends RefCounted


static func validate(state: GameState, errors: Array[String]) -> void:
	for situation in state.pending_situations:
		if situation != null:
			_check(state, situation.event_id, situation.target_country_id, errors)
	for row in state.scheduled_events:
		_check(state, String(row.get("event_id", "")), String(row.get("target_country_id", "")), errors)


static func _check(state: GameState, event_id: String, target: String, errors: Array[String]) -> void:
	if target != "" and state.world_country(target) == null:
		errors.append("situation '%s' targets unknown country '%s'" % [event_id, target])
