extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const KEY_ACTIONS := ["pause", "next_decision", "save", "load", "back"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t = TestSupportScript.new()
	var settings: Node = root.get_node("Settings")
	var saved_path: String = settings.path
	settings.path = "user://test_options_settings.cfg"
	var host := Control.new()
	root.add_child(host)
	var panel := OptionsPanel.open(host)
	await process_frame
	t.truth(Overlay.any_open(self), "options open as an overlay")

	var autosave: CheckButton = panel.find_child("Autosave", true, false)
	autosave.button_pressed = not bool(settings.get_value("gameplay/autosave"))
	t.equal(settings.get_value("gameplay/autosave"), autosave.button_pressed, "the autosave switch is the setting")
	var music: HSlider = panel.find_child("MusicVolume", true, false)
	music.value = 0.3
	t.near(float(settings.get_value("audio/music")), 0.3, 0.0001, "the music slider is the setting")
	var scale: OptionButton = panel.find_child("UiScale", true, false)
	t.equal(scale.item_count, 3, "three interface scales are offered")

	for action in KEY_ACTIONS:
		var row: Label = panel.find_child("KeyRow_%s" % action, true, false)
		t.truth(row != null and row.text.contains(Keys.label(action)), "the key list shows the real key for %s" % action)

	(panel.find_child("DoneButton", true, false) as Button).pressed.emit()
	await process_frame
	t.truth(not Overlay.any_open(self), "Done closes the options")
	DirAccess.remove_absolute(settings.path)
	settings.path = saved_path
	settings.load_from_disk()
	quit(t.finish())
