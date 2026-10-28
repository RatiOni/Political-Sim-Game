extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const TEST_SLOT := "test_opposition_panel"

var t = TestSupportScript.new()
var app: Node = null
var game: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int = 2) -> void:
	for _i in range(count):
		await process_frame


func _fresh(role: String) -> void:
	if app != null:
		app.queue_free()
		await _frames()
	root.get_node("GameFlow").start_mode = "new"
	root.get_node("GameFlow").pending_seed = 616161
	root.get_node("GameFlow").pending_role = role
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	app.save_slot = TEST_SLOT
	root.add_child(app)
	game = root.get_node("NativeGame")
	await _frames(3)


func _panel() -> Control:
	return app.find_child("OppositionPanel", true, false)


func _press(name: String) -> void:
	var button: Button = _panel().find_child(name, true, false)
	t.truth(button != null and not button.disabled, "%s can be pressed" % name)
	if button != null:
		button.pressed.emit()
	await _frames(2)


func _choose(name: String, index: int) -> void:
	var choice: OptionButton = _panel().find_child(name, true, false)
	choice.select(index)
	choice.item_selected.emit(index)


func _opposition() -> Dictionary:
	return game.snapshot().get("opposition", {})


func _run() -> void:
	await _test_the_desk_follows_the_players_side(t)
	await _test_every_opposition_action_works_through_the_panel(t)
	root.get_node("GameFlow").pending_role = "contextual"
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute("user://saves/%s.json%s" % [TEST_SLOT, suffix])
	if app != null:
		app.queue_free()
	quit(t.finish())


func _test_the_desk_follows_the_players_side(t) -> void:
	await _fresh("contextual")
	t.equal(app.save_slot, TEST_SLOT, "the test never touches the player's slot")
	t.equal(app.find_child("LegislationButton", true, false).text, "Legislation", "a government sees its legislation desk")
	await _fresh("opposition")
	var button: Button = app.find_child("LegislationButton", true, false)
	t.equal(button.text, "Opposition", "an opposition leader sees the opposition desk in the same place")
	button.pressed.emit()
	await _frames(2)
	t.truth(_panel().visible, "it opens")
	t.truth(not app.find_child("MapPanel", true, false).visible, "in the desk, like every other")
	t.truth(not app.find_child("LegislationPanel", true, false).visible, "instead of the government's legislation desk")
	var support: Button = _panel().find_child("SupportButton", true, false)
	t.truth(support.size.x <= 160.0, "the response buttons keep a compact width (%.0f px)" % support.size.x)
	var scroll: Control = _panel().find_child("Scroll", true, false)
	var body: Control = _panel().find_child("Body", true, false)
	t.truth(scroll.get_global_rect().end.x - body.get_global_rect().end.x >= 12.0, "and the desk's buttons clear the scrollbar")


func _test_every_opposition_action_works_through_the_panel(t) -> void:
	await _fresh("opposition")
	app.find_child("LegislationButton", true, false).pressed.emit()
	await _frames(2)
	var size_before: Vector2 = _panel().size
	_choose("ShadowChoice", 0)
	await _press("AppointShadowButton")
	t.equal(_opposition()["shadow_cabinet"].size(), 1, "a shadow minister is appointed from the panel")
	_choose("PledgeChoice", 0)
	await _press("AddPledgeButton")
	_choose("PledgeChoice", 1)
	await _press("AddPledgeButton")
	t.equal(_opposition()["pledges"].size(), 2, "pledges are published from the panel")
	await _press("CampaignButton1")
	t.equal(int(_opposition()["pledges"][0]["campaigns"]), 1, "the party campaigns on a pledge from the panel")
	t.truth((_panel().find_child("CampaignButton1", true, false) as Button).disabled, "and the pledge then rests")
	await _press("DropButton2")
	t.equal(_opposition()["pledges"].size(), 1, "a pledge is dropped from the panel")
	t.truth((_panel().find_child("DropButton3", true, false) as Button).disabled, "an empty platform slot has nothing to drop")
	t.truth(_panel().find_child("Pledge3", true, false).visible, "but keeps its place")
	t.truth((_panel().find_child("SupportButton", true, false) as Button).disabled, "with no government bill there is nothing to answer")
	app.find_child("CloseOppositionButton", true, false).pressed.emit()
	for _day in range(120):
		if _opposition().get("government_bill") != null:
			break
		game.advance_day()
	app.apply_snapshot(game.snapshot())
	app.find_child("LegislationButton", true, false).pressed.emit()
	await _frames(2)
	t.truth(_opposition().get("government_bill") != null, "the government brings a bill")
	t.truth(String((_panel().find_child("BillName", true, false) as Label).text).contains(
		String(_opposition()["government_bill"]["name"])), "the panel names it")
	await _press("AmendButton")
	t.equal(_opposition()["government_bill"]["response"], "amend", "the opposition answers it from the panel")
	t.truth((_panel().find_child("SupportButton", true, false) as Button).disabled, "once")
	t.equal(_panel().size, size_before, "and the desk never changed size")
