class_name Arrive
extends RefCounted

## How new information enters the screen: it types on over a beat instead of
## snapping into existence, and the panel's heading glows amber for a moment so
## the eye is pulled to it. Text that has not changed is never re-animated.

const TYPE_SECONDS := 0.9
const FADE_SECONDS := 0.35
const GLOW_SECONDS := 1.6


## Types `label` on from nothing. `delay` staggers several arrivals.
static func type_on(label: Label, delay: float = 0.0) -> void:
	if not label.is_inside_tree():
		return
	label.visible_ratio = 0.0
	label.modulate.a = 0.0
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "modulate:a", 1.0, FADE_SECONDS).set_delay(delay)
	tween.tween_property(label, "visible_ratio", 1.0, TYPE_SECONDS).set_delay(delay) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


## Sets the text and types it on, but only when it actually changed.
static func set_text(label: Label, text: String) -> void:
	if label.text == text:
		return
	label.text = text
	type_on(label)


## Briefly lights a heading amber, then lets it settle back.
static func glow(heading: Label) -> void:
	if heading == null or not heading.is_inside_tree():
		return
	heading.remove_theme_color_override("font_color")
	var rest := heading.get_theme_color("font_color")
	heading.create_tween().tween_method(
		func(c: Color) -> void: heading.add_theme_color_override("font_color", c),
		UiPalette.GOLD, rest, GLOW_SECONDS).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
