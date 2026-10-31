extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const SettingsScript = preload("res://scripts/settings.gd")
const TEST_PATH := "user://test_settings.cfg"


func _initialize() -> void:
	_run.call_deferred()


func _fresh() -> Node:
	var settings: Node = SettingsScript.new()
	settings.path = TEST_PATH
	settings.load_from_disk()
	return settings


func _run() -> void:
	var t = TestSupportScript.new()
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	var settings := _fresh()
	t.equal(settings.get_value("gameplay/autosave"), true, "autosave is on by default")
	t.equal(settings.get_value("display/ui_scale"), 1.0, "the interface starts at 100%")
	var heard := [""]
	settings.changed.connect(func(key: String) -> void: heard[0] = key)
	settings.set_value("gameplay/autosave", false)
	settings.set_value("audio/music", 0.25)
	t.equal(heard[0], "audio/music", "a change is announced")
	var again := _fresh()
	t.equal(again.get_value("gameplay/autosave"), false, "a preference survives a restart")
	t.near(float(again.get_value("audio/music")), 0.25, 0.0001, "so does a volume")

	var W := DisplayServer
	t.equal(SettingsScript.next_window_mode(W.WINDOW_MODE_MAXIMIZED, false), -1, "a maximized window is left alone with fullscreen off")
	t.equal(SettingsScript.next_window_mode(W.WINDOW_MODE_WINDOWED, true), W.WINDOW_MODE_FULLSCREEN, "fullscreen on enters fullscreen")
	t.equal(SettingsScript.next_window_mode(W.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, false), W.WINDOW_MODE_WINDOWED, "fullscreen off leaves it")
	t.equal(SettingsScript.next_window_mode(W.WINDOW_MODE_FULLSCREEN, true), -1, "already fullscreen is left alone")

	var music := AudioServer.get_bus_index(AudioBuses.ensure(&"Music"))
	t.truth(music >= 0, "music has its own bus")
	t.equal(AudioServer.get_bus_send(music), &"Master", "under the master volume")
	t.near(AudioServer.get_bus_volume_db(music), linear_to_db(0.25), 0.01, "at the chosen level")
	t.equal(AudioServer.get_bus_index(AudioBuses.ensure(&"Music")), music, "asking twice does not make a second bus")

	t.equal(SettingsScript.fitting_scale(1.3, Vector2(1920, 1080)), 1.3, "130% fits a 1080p window")
	t.equal(SettingsScript.fitting_scale(1.3, Vector2(1280, 720)), 1.0, "but not a 720p one, which keeps 100%")
	t.equal(SettingsScript.fitting_scale(1.3, Vector2(1600, 900)), 1.15, "a middling window gets the largest scale that fits")
	root.content_scale_factor = 0.5
	root.add_child(settings)
	settings._apply_ui_scale()
	t.equal(root.content_scale_factor, 0.5, "a 100% preference leaves another owner of the scale alone")
	root.remove_child(settings)
	root.content_scale_factor = 1.0
	DirAccess.remove_absolute(TEST_PATH)
	settings.free()
	again.free()
	quit(t.finish())
