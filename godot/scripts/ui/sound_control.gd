class_name SoundControl
extends HBoxContainer

## A mute toggle and a master volume slider, bound to the `Ambience` autoload.
## Every instance (menu, header) stays in step through `settings_changed`.

var mute_button := Button.new()
var slider := HSlider.new()
var _ambience: Node


func _ready() -> void:
	_ambience = get_node_or_null("/root/Ambience")
	add_theme_constant_override("separation", 6)
	mute_button.toggle_mode = true
	mute_button.theme_type_variation = &"QuietButton"
	mute_button.focus_mode = Control.FOCUS_NONE
	mute_button.custom_minimum_size = Vector2(72, 44)
	mute_button.tooltip_text = "Mute all sound"
	mute_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(110, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.tooltip_text = "Volume"
	add_child(mute_button)
	add_child(slider)
	if _ambience == null:
		return
	_sync()
	mute_button.toggled.connect(_ambience.set_muted)
	slider.value_changed.connect(_ambience.set_volume)
	_ambience.settings_changed.connect(_sync)


func _sync() -> void:
	mute_button.set_pressed_no_signal(_ambience.muted)
	mute_button.text = "MUTED" if _ambience.muted else "SOUND"
	slider.set_value_no_signal(_ambience.volume)
	slider.editable = not _ambience.muted
