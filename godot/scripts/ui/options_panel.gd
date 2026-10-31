class_name OptionsPanel
extends Overlay

## Display, sound, autosave and the key list. Every control writes straight to
## `Settings` (master volume and mute to `Ambience`, through the same control
## the header uses). The key list is read from the live InputMap.

const SettingsScript = preload("res://scripts/settings.gd")
const KEY_ROWS := [
	["pause", "Start or stop the clock"],
	["next_decision", "Go to the next waiting decision"],
	["save", "Save into the current slot"],
	["load", "Choose a save to load"],
	["back", "Close a desk, or open this menu"],
]


static func open(host: Node) -> OptionsPanel:
	var panel := OptionsPanel.new()
	panel.set_title("Options")
	var settings := host.get_node("/root/Settings")

	panel._section("Display")
	var fullscreen := CheckButton.new()
	fullscreen.name = "Fullscreen"
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = bool(settings.get_value("display/fullscreen"))
	fullscreen.toggled.connect(func(on: bool) -> void: settings.set_value("display/fullscreen", on))
	panel.body.add_child(fullscreen)
	var scale := OptionButton.new()
	scale.name = "UiScale"
	scale.tooltip_text = "Interface scale"
	for value: float in SettingsScript.UI_SCALES:
		scale.add_item("Interface %d%%" % roundi(value * 100.0))
		if is_equal_approx(value, float(settings.get_value("display/ui_scale"))):
			scale.select(scale.item_count - 1)
	scale.item_selected.connect(func(index: int) -> void: settings.set_value("display/ui_scale", SettingsScript.UI_SCALES[index]))
	panel.body.add_child(scale)
	panel._note("Larger scales need a larger window; Ardenia uses the largest that fits.")

	panel._section("Sound")
	var master := SoundControl.new()
	master.tooltip_text = "Master volume"
	panel.body.add_child(master)
	panel._slider("MusicVolume", "Music and ambience", "audio/music", settings)
	panel._slider("EffectsVolume", "Effects", "audio/effects", settings)

	panel._section("Gameplay")
	var autosave := CheckButton.new()
	autosave.name = "Autosave"
	autosave.text = "Autosave at the start of each month"
	autosave.button_pressed = bool(settings.get_value("gameplay/autosave"))
	autosave.toggled.connect(func(on: bool) -> void: settings.set_value("gameplay/autosave", on))
	panel.body.add_child(autosave)

	panel._section("Controls")
	var speeds := Label.new()
	speeds.name = "KeyRow_speeds"
	speeds.text = "%s – %s    Set the clock speed" % [Keys.label("speed_1"), Keys.label("speed_5")]
	panel.body.add_child(speeds)
	for row in KEY_ROWS:
		var line := Label.new()
		line.name = "KeyRow_%s" % row[0]
		line.text = "%s    %s" % [Keys.label(row[0]), row[1]]
		panel.body.add_child(line)

	var done := Button.new()
	done.name = "DoneButton"
	done.text = "Done"
	done.custom_minimum_size = Vector2(0, 44)
	done.pressed.connect(panel.close)
	panel.body.add_child(done)
	host.add_child(panel)
	done.grab_focus.call_deferred()
	return panel


func _section(text: String) -> void:
	var heading := Label.new()
	heading.theme_type_variation = &"Section"
	heading.text = text
	body.add_child(heading)


func _note(text: String) -> void:
	var note := Label.new()
	note.theme_type_variation = &"Muted"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(400, 0)
	note.text = text
	body.add_child(note)


func _slider(node_name: String, text: String, key: String, settings: Node) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(180, 0)
	slider.value = float(settings.get_value(key))
	slider.value_changed.connect(func(v: float) -> void: settings.set_value(key, v))
	row.add_child(label)
	row.add_child(slider)
	body.add_child(row)
