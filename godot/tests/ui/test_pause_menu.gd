extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")


func _initialize() -> void:
	_run.call_deferred()


func _overlays() -> Array[Node]:
	return get_nodes_in_group(Overlay.GROUP)


func _escape() -> void:
	var ev := InputEventAction.new()
	ev.action = "back"
	ev.pressed = true
	Input.parse_input_event(ev)


func _run() -> void:
	var t = TestSupportScript.new()
	var h = AppHarness.new(self, "test_pause_menu")
	var app: Node = await h.fresh()
	_escape()
	await h.frames(3)
	t.truth(_overlays().size() == 1 and _overlays()[0] is PauseMenu, "Escape on the dashboard opens the pause menu")
	t.truth(app._clock_held(), "and the clock holds under it")
	for id in ["resume", "save", "load", "options", "main_menu", "quit"]:
		t.truth(_overlays()[0].find_child("Entry_%s" % id, true, false) != null, "it offers %s" % id)
	_escape()
	await h.frames(3)
	t.truth(_overlays().is_empty(), "Escape again resumes")

	await app._go_to_desk("records")
	_escape()
	await h.frames(3)
	t.truth(_overlays().is_empty() and not app._desk_open(), "with a desk open, Escape closes the desk instead")

	await h.tick(2)
	t.truth(app._has_unsaved_progress(), "two days of unsaved play")
	app._leave("menu")
	await h.frames()
	app._leave("menu")
	await h.frames()
	var stacked := 0
	for o in _overlays():
		if o is ConfirmPrompt:
			stacked += 1
	t.truth(stacked == 1, "repeated leave requests do not stack prompts")
	var prompt: Node = _overlays()[-1] if not _overlays().is_empty() else null
	t.truth(prompt is ConfirmPrompt, "leaving with unsaved progress asks")
	t.truth(prompt.find_child("Choice_save", true, false) != null and prompt.find_child("Choice_leave", true, false) != null, "offering to save first or leave anyway")
	(prompt.find_child("Choice_cancel", true, false) as Button).pressed.emit()
	await h.frames()
	t.truth(is_instance_valid(app) and app.is_inside_tree(), "and cancelling stays in the game")

	var zz_a := "zz_quick_a"
	var zz_b := "zz_quick_b"
	var zz: Array[String] = [zz_a, zz_b]
	var zz_file := "user://saves/%s.json" % zz_a
	DirAccess.make_dir_recursive_absolute("user://saves")
	app.save_slot = SaveStore.AUTOSAVE_SLOT
	t.truth(await app._quick_save_slot(zz) == zz_a, "quick save from the autosave takes the first empty slot")
	var f := FileAccess.open(zz_file, FileAccess.WRITE)
	f.store_string("{}")
	f = null
	app.save_slot = SaveStore.LEGACY_SLOT
	t.truth(await app._quick_save_slot(zz) == zz_b, "from the legacy slot it skips a used slot, never overwriting it")
	DirAccess.remove_absolute(zz_file)
	app.save_slot = "zz_pause_menu"
	t.truth(await app._quick_save_slot() == "zz_pause_menu", "a chosen manual slot is kept")
	var s: Node = root.get_node("Settings")
	t.equal(s.path, AppHarness.TEST_SETTINGS, "UI tests read their own settings file, not the player's")
	h.finish()
	quit(t.finish())
