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
	var prompt: Node = _overlays()[-1] if not _overlays().is_empty() else null
	t.truth(prompt is ConfirmPrompt, "leaving with unsaved progress asks")
	t.truth(prompt.find_child("Choice_save", true, false) != null and prompt.find_child("Choice_leave", true, false) != null, "offering to save first or leave anyway")
	(prompt.find_child("Choice_cancel", true, false) as Button).pressed.emit()
	await h.frames()
	t.truth(is_instance_valid(app) and app.is_inside_tree(), "and cancelling stays in the game")

	app.save_slot = SaveStore.AUTOSAVE_SLOT
	t.truth(app._quick_save_slot() == "slot_1", "quick save never targets the autosave")
	app.save_slot = SaveStore.LEGACY_SLOT
	t.truth(app._quick_save_slot() == "slot_1", "nor the legacy slot")
	app.save_slot = "zz_pause_menu"
	t.truth(app._quick_save_slot() == "zz_pause_menu", "a chosen manual slot is kept")
	h.finish()
	quit(t.finish())
