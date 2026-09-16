class_name Modifiers
extends RefCounted

## Batch operations over a GameState's active Modifier collection. The
## lifecycle math itself already lives on Modifier (state/modifier.gd:
## current_value/is_expired/phase_label, ported from models/modifiers.py in
## Task 2) — this file wires that per-instance math into the turn-level
## operation engine/turn.py performs once a month
## (`TurnEngine._age_modifiers`): age every modifier, drop the ones that have
## now finished their onset/ramp/hold/decay lifecycle.
##
## `current_value`/`is_expired` are thin static delegates to the Modifier
## instance methods, kept here only so callers can use the interface named in
## the task brief (`Modifiers.current_value(modifier)`) without reaching for
## the Modifier instance method directly. Deliberately NOT re-deriving the
## lifecycle math — see modifier.gd for that.
##
## Note on `institutional`: Python's `_modifiers_sum` (engine/turn.py) is what
## discounts a modifier's value by ministry/government capacity, and only for
## `institutional == true` effects — `institutional == false` (e.g. loan
## interest) is deliberately never discounted. That discounting is a turn-
## engine concern (reads cabinet/stability state this task doesn't model) and
## is out of this task's scope; `current_value()` itself never applies any
## discount for either flag, by design, so it is exactly as safe to call on
## an `institutional == false` modifier as on any other.


static func current_value(modifier: Modifier) -> float:
	return modifier.current_value()


static func is_expired(modifier: Modifier) -> bool:
	return modifier.is_expired()


## Ages every modifier in state.modifiers by one month and removes any that
## have now expired (mirrors TurnEngine._age_modifiers, minus the dispatch
## logging call — flavor.say has no Godot port yet).
static func age_all(state: GameState) -> void:
	var still_active: Array[Modifier] = []
	for m in state.modifiers:
		m.age += 1
		if not m.is_expired():
			still_active.append(m)
	state.modifiers = still_active
