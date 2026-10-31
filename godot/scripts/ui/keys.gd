class_name Keys
extends RefCounted

## The key a player presses for an action, read from the live InputMap so a
## tooltip can never promise a key that is not bound (the save button once
## said F5; the key was S).

static func label(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			return OS.get_keycode_string(code)
	return "—"
