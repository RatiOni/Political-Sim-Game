extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")
const SLOTS: Array[String] = ["zz_dialog_a", "zz_dialog_b"]


func _initialize() -> void:
	_run.call_deferred()


func _wipe() -> void:
	for slot in SLOTS:
		for suffix in ["", ".tmp", ".bak"]:
			var path := "user://saves/%s.json%s" % [slot, suffix]
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


func _newest_overlay() -> Node:
	var open := get_nodes_in_group(Overlay.GROUP)
	return open[-1] if not open.is_empty() else null


func _run() -> void:
	var t = TestSupportScript.new()
	_wipe()
	var h = AppHarness.new(self, SLOTS[0])
	var app: Node = await h.fresh()
	app._do_save()
	t.truth(not app._has_unsaved_progress(), "a fresh save leaves nothing unsaved")
	await h.tick(2)
	t.truth(app._has_unsaved_progress(), "two days later there is")

	var got := ["unset"]
	var dialog := SaveDialog.open(app, "save", false, SLOTS)
	dialog.finished.connect(func(slot: String) -> void: got[0] = slot)
	await h.frames()
	var used: Button = dialog.find_child("Slot_%s" % SLOTS[0], true, false)
	t.truth(used.text.to_upper().contains("1 MAR 1993"), "a used slot shows its campaign's date")
	used.pressed.emit()
	await h.frames()
	t.truth(_newest_overlay() is ConfirmPrompt, "saving over a used slot asks first")
	(_newest_overlay().find_child("Choice_cancel", true, false) as Button).pressed.emit()
	await h.frames()
	t.equal(got[0], "unset", "and cancelling saves nothing")
	(dialog.find_child("Slot_%s" % SLOTS[1], true, false) as Button).pressed.emit()
	await h.frames()
	t.equal(got[0], SLOTS[1], "an empty slot is taken without a question")

	var loading := SaveDialog.open(app, "load", true, SLOTS)
	await h.frames()
	t.truth((loading.find_child("Slot_%s" % SLOTS[1], true, false) as Button).disabled, "an empty slot cannot be loaded")
	(loading.find_child("Slot_%s" % SLOTS[0], true, false) as Button).pressed.emit()
	await h.frames()
	t.truth(_newest_overlay() is ConfirmPrompt, "loading over unsaved progress asks first")
	(_newest_overlay().find_child("Choice_cancel", true, false) as Button).pressed.emit()
	await h.frames()
	loading.close()
	await h.frames()

	var key := InputEventKey.new()
	key.physical_keycode = KEY_L
	key.ctrl_pressed = true
	key.pressed = true
	Input.parse_input_event(key)
	await h.frames(3)
	t.truth(_newest_overlay() is SaveDialog, "the load key opens the list instead of reloading at once")
	h.finish()
	_wipe()
	quit(t.finish())
