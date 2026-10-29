extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const TEST_SLOT := "test_orientation_desk"

var t = TestSupportScript.new()
var app: Node = null
var game: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int = 2) -> void:
	for _i in range(count):
		await process_frame


func _fresh() -> void:
	if app != null:
		app.queue_free()
		await _frames()
	root.get_node("GameFlow").start_mode = "new"
	root.get_node("GameFlow").pending_seed = 424242
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	app.save_slot = TEST_SLOT
	root.add_child(app)
	game = root.get_node("NativeGame")
	await _frames(3)


func _wipe_slot() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := "user://saves/%s.json%s" % [TEST_SLOT, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _step_button(prefix: String) -> Button:
	var steps: VBoxContainer = app.find_child("OrientationSteps", true, false)
	for child in steps.get_children():
		if child is Button and (child as Button).text.begins_with(prefix):
			return child
	return null


func _run() -> void:
	_wipe_slot()
	await _test_the_desk_shows_where_ardenia_stands(t)
	await _test_a_step_can_be_taken_from_the_desk(t)
	await _test_a_step_out_of_reach_says_why(t)
	_wipe_slot()
	if app != null:
		app.queue_free()
	quit(t.finish())


func _test_the_desk_shows_where_ardenia_stands(t) -> void:
	await _fresh()
	app._open_diplomacy()
	await _frames()
	var powers: Label = app.find_child("OrientationPowers", true, false)
	t.truth(powers != null and powers.text.contains("KRASOVA") and powers.text.contains("leverage"), "the desk lists each power's hold over Ardenia")
	var reviews: Label = app.find_child("OrientationReviews", true, false)
	t.truth(reviews != null and reviews.text.contains("ISF"), "and the state of the ISF programme")
	var steps: VBoxContainer = app.find_child("OrientationSteps", true, false)
	t.truth(steps.get_children().any(func(c: Node) -> bool: return c is Label and (c as Label).text.contains("IN PLACE")), "standing obligations are shown as in place")


func _test_a_step_can_be_taken_from_the_desk(t) -> void:
	await _fresh()
	t.truth(game._state.player.in_government, "the desk test opens in government")
	game._state.player.political_capital = 500.0
	app.apply_snapshot(game.snapshot())
	app._open_diplomacy()
	await _frames()
	var button := _step_button("Meridian partnership")
	t.truth(button != null and not button.disabled, "the Meridian partnership can be joined from the desk")
	button.pressed.emit()
	await _frames(3)
	t.truth(game._state.foreign.reached.has("meridian_partnership"), "pressing it takes the step")
	var status: Label = app.find_child("DiplomacyStatus", true, false)
	t.truth(status.text.contains("Meridian"), "the desk reports it")
	t.truth(_step_button("Meridian partnership") == null, "and no longer offers it")


func _test_a_step_out_of_reach_says_why(t) -> void:
	await _fresh()
	app._open_diplomacy()
	await _frames()
	var button := _step_button("Meridian security guarantee")
	t.truth(button != null and button.disabled and button.tooltip_text != "", "a step out of reach is disabled with its reason")
