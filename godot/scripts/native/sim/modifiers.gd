class_name Modifiers
extends RefCounted


static func current_value(modifier: Modifier) -> float:
	return modifier.current_value()


static func is_expired(modifier: Modifier) -> bool:
	return modifier.is_expired()


static func age_all(state: GameState) -> void:
	var still_active: Array[Modifier] = []
	for m in state.modifiers:
		m.age += 1
		if not m.is_expired():
			still_active.append(m)
	state.modifiers = still_active
