class_name WireLog
extends VBoxContainer

## The dispatch wire as a console log: one line per dispatch, newest at the
## bottom. A line that was not on the wire before types on in bright white and
## settles to the normal tone; older lines dim with age. Nothing is rebuilt
## while the wire is unchanged — the clock pushes a snapshot every day, and
## rebuilding identical lines read as the panel twitching.

const SETTLE_SECONDS := 1.6
const STAGGER_SECONDS := 0.25
const FRESH := Color(1.0, 1.0, 1.0)
const AGE_STEP := 0.12
const AGE_FLOOR := 0.45

## Raised when fresh lines arrive, so the panel's heading can glow.
signal arrived

var _seen: Dictionary = {}
var _rows_key := 0
var _primed := false


func _init() -> void:
	name = "WireLog"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)


func show_rows(rows: Array, empty_text: String) -> void:
	var key := [rows, empty_text].hash()
	if key == _rows_key and get_child_count() > 0:
		return
	_rows_key = key
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var primed := _primed
	_primed = true
	if rows.is_empty():
		_add(empty_text, UiPalette.TEXT_DIM, false, 0)
		_seen.clear()
		return
	var seen := {}
	var fresh_count := 0
	for i in rows.size():
		var text := str(rows[i])
		var age := rows.size() - 1 - i
		var tone := UiPalette.TEXT.lerp(UiPalette.TEXT_DIM, clampf(age * AGE_STEP / (1.0 - AGE_FLOOR), 0.0, 1.0))
		var fresh := primed and not _seen.has(text)
		_add(text, tone, fresh, fresh_count)
		if fresh:
			fresh_count += 1
		seen[text] = true
	_seen = seen
	if fresh_count > 0:
		arrived.emit()


func _add(text: String, tone: Color, fresh: bool, order: int) -> void:
	var line := Label.new()
	line.text = text
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_color_override("font_color", tone)
	add_child(line)
	if not fresh or not is_inside_tree():
		return
	var delay := mini(order, 6) * STAGGER_SECONDS
	Arrive.type_on(line, delay)
	line.add_theme_color_override("font_color", FRESH)
	line.create_tween().tween_method(func(c: Color) -> void: line.add_theme_color_override("font_color", c),
		FRESH, tone, SETTLE_SECONDS).set_delay(delay + Arrive.TYPE_SECONDS) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
