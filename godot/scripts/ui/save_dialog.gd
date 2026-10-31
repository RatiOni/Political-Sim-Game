class_name SaveDialog
extends Overlay

## Choose a slot to save into or load from. Each row says whose campaign it
## holds, its date in the game and when it was saved. Saving over a used slot
## and loading over unsaved progress both ask first. `finished` reports the
## chosen slot, or "" when the player backs out.

signal finished(slot: String)

var mode := "save"
var unsaved := false
var _host: Node


static func open(host: Node, mode: String, unsaved: bool, slots: Array[String] = []) -> SaveDialog:
	if slots.is_empty():
		slots = SaveStore.player_slots()
	var dialog := SaveDialog.new()
	dialog.mode = mode
	dialog.unsaved = unsaved
	dialog._host = host
	dialog.set_title("Save the campaign" if mode == "save" else "Load a campaign")
	for slot in slots:
		var info := SaveStore.slot_info(slot)
		var button := Button.new()
		button.name = "Slot_%s" % slot
		button.custom_minimum_size = Vector2(520, 48)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = dialog._row_text(slot, info)
		var read_only := mode == "save" and (slot == SaveStore.AUTOSAVE_SLOT or slot == SaveStore.LEGACY_SLOT)
		button.disabled = read_only or (mode == "load" and not bool(info["exists"]))
		button.pressed.connect(dialog._pick.bind(slot, info))
		dialog.body.add_child(button)
	var cancel := Button.new()
	cancel.name = "CancelButton"
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 44)
	cancel.pressed.connect(dialog._finish.bind(""))
	dialog.body.add_child(cancel)
	host.add_child(dialog)
	cancel.grab_focus.call_deferred()
	return dialog


func _row_text(slot: String, info: Dictionary) -> String:
	var label := SaveStore.slot_label(slot)
	if not bool(info["exists"]):
		return "%s   ·   Empty" % label
	# File times are UTC; the player reads their own clock.
	var bias_minutes := int(Time.get_time_zone_from_system().get("bias", 0))
	var local_unix := int(info["saved_unix"]) + bias_minutes * 60
	var saved := Time.get_datetime_string_from_unix_time(local_unix, true).substr(0, 16)
	var who := String(info["leader"]) if String(info["leader"]) != "" else "A campaign"
	var when := String(info["date_text"])
	if when == "":
		return "%s   ·   %s   ·   saved %s" % [label, who, saved]
	return "%s   ·   %s, %s   ·   saved %s" % [label, who, when, saved]


func _pick(slot: String, info: Dictionary) -> void:
	if mode == "save" and bool(info["exists"]):
		var prompt := ConfirmPrompt.ask(_host, "Overwrite %s?" % SaveStore.slot_label(slot),
			"It holds %s. Saving here replaces it." % _row_text(slot, info).get_slice("·", 1).strip_edges(),
			[["overwrite", "Overwrite"], ["cancel", "Cancel"]])
		var overwrite: String = await prompt.chosen
		if overwrite != "overwrite":
			return
	elif mode == "load" and unsaved:
		var prompt := ConfirmPrompt.ask(_host, "Load this save?",
			"Progress since your last save will be lost.",
			[["load", "Load"], ["cancel", "Cancel"]])
		var answer: String = await prompt.chosen
		if answer != "load":
			return
	_finish(slot)


func _on_back() -> void:
	_finish("")


func _finish(slot: String) -> void:
	finished.emit(slot)
	close()
