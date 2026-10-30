class_name WireLog
extends VBoxContainer

## The dispatch wire as a console log: one line per dispatch, newest at the
## bottom. A line that was not on the wire before arrives in bright white and
## settles to the normal tone over a second; older lines dim with age.

const SETTLE_SECONDS := 1.0
const FRESH := Color(1.0, 1.0, 1.0)
const AGE_STEP := 0.12
const AGE_FLOOR := 0.45

var _seen: Dictionary = {}


func _init() -> void:
	name = "WireLog"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)


func show_rows(rows: Array, empty_text: String) -> void:
	for child in get_children():
		child.queue_free()
	if rows.is_empty():
		_add(empty_text, UiPalette.TEXT_DIM, false)
		_seen.clear()
		return
	var seen := {}
	for i in rows.size():
		var text := str(rows[i])
		var age := rows.size() - 1 - i
		var tone := UiPalette.TEXT.lerp(UiPalette.TEXT_DIM, clampf(age * AGE_STEP / (1.0 - AGE_FLOOR), 0.0, 1.0))
		_add(text, tone, not _seen.has(text))
		seen[text] = true
	_seen = seen


func _add(text: String, tone: Color, fresh: bool) -> void:
	var line := Label.new()
	line.text = text
	line.uppercase = true
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_color_override("font_color", FRESH if fresh else tone)
	add_child(line)
	if fresh and is_inside_tree():
		var tween := line.create_tween()
		tween.tween_method(func(c: Color) -> void: line.add_theme_color_override("font_color", c),
			FRESH, tone, SETTLE_SECONDS).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	elif fresh:
		line.add_theme_color_override("font_color", tone)
