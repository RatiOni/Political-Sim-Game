extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const SLOTS: Array[String] = ["zz_slots_a", "zz_slots_b"]


func _initialize() -> void:
	_run.call_deferred()


func _wipe() -> void:
	for slot in SLOTS:
		for suffix in ["", ".tmp", ".bak"]:
			var path := "user://saves/%s.json%s" % [slot, suffix]
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


func _run() -> void:
	var t = TestSupportScript.new()
	_wipe()
	var game: Node = root.get_node("NativeGame")
	game.new_campaign({"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal", "opening_role": "contextual", "seed": 424242})
	t.equal(SaveStore.slot_info(SLOTS[0])["exists"], false, "an unused slot is empty")
	t.equal(SaveStore.most_recent_slot(SLOTS), "", "and there is nothing to continue")
	t.truth(game.save(SLOTS[0]).get("ok", false), "a campaign saves")
	var info := SaveStore.slot_info(SLOTS[0])
	t.equal(info["date_text"], "1 Mar 1993", "the slot knows the campaign's date")
	t.truth(String(info["leader"]) != "", "and whose campaign it is")
	t.truth(game.load(SLOTS[0]).get("ok", false), "a save with its label still loads")
	OS.delay_msec(1100)
	SaveStore.save_slot(SLOTS[1], game._state)
	t.equal(SaveStore.slot_info(SLOTS[1])["date_text"], "", "a save without a label reads as unlabelled, not broken")
	t.equal(SaveStore.most_recent_slot(SLOTS), SLOTS[1], "the newest save is the one to continue")
	t.equal(SaveStore.slot_label("autosave"), "Autosave", "slots have player names")
	t.equal(SaveStore.slot_label("slot_2"), "Slot 2", "numbered ones too")
	t.equal(SaveStore.slot_label("godot_slice"), "Earlier save", "and the old single save")
	var slots := SaveStore.player_slots()
	t.equal(slots.slice(0, 4), ["autosave", "slot_1", "slot_2", "slot_3"], "the player's slots, autosave first")
	_wipe()
	quit(t.finish())
