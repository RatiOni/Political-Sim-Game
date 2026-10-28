extends SceneTree

## Behaviour tests for the game screen (scripts/app.gd), driving the real
## main scene through the NativeGame autoload.
## Run via:
##   Godot --headless --path godot --script res://tests/ui/test_app_behaviour.gd

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const TEST_SLOT := "test_app_behaviour"

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


func _tick(days: int) -> void:
	app._paused = false
	for _i in range(days):
		app._clock_elapsed = 999.0
		app._process(0.0)
		await _frames(1)


func _wipe_slot() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := "user://saves/%s.json%s" % [TEST_SLOT, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _choose(choice: OptionButton, index: int) -> void:
	choice.select(index)
	choice.item_selected.emit(index)


func _run() -> void:
	_wipe_slot()
	await _test_the_save_slot_is_never_the_players(t)
	await _test_a_running_clock_does_not_jam_the_legislation_desk(t)
	await _test_a_chosen_programme_survives_the_clock(t)
	await _test_header_buttons_follow_the_open_desk(t)
	await _test_a_budget_draft_holds_the_clock(t)
	await _test_opening_a_situation_pauses_the_clock(t)
	await _test_escape_closes_the_desk(t)
	await _test_save_and_load_shortcuts_wait_while_a_desk_is_open(t)
	await _test_space_pauses_even_with_a_button_focused(t)
	await _test_loading_resets_the_desks(t)
	_wipe_slot()
	if app != null:
		app.queue_free()
	quit(t.finish())


func _test_the_save_slot_is_never_the_players(t) -> void:
	await _fresh()
	t.truth(app.SAVE_SLOT != TEST_SLOT, "the game's own slot is not the test slot")
	t.equal(app.save_slot, TEST_SLOT, "a test can point the screen at its own slot")


func _test_a_running_clock_does_not_jam_the_legislation_desk(t) -> void:
	await _fresh()
	app._open_legislation()
	await _tick(4)
	var status: String = app.find_child("LegislationPanel", true, false).find_child("LegislationStatus", true, false).text
	t.truth(not status.contains("in flight"), "the legislation desk never shows a refused-operation error while time runs (%s)" % status)


func _test_a_chosen_programme_survives_the_clock(t) -> void:
	await _fresh()
	var choice: OptionButton = app.find_child("ProgramChoice", true, false)
	if choice.item_count < 2:
		t.truth(false, "sanity: the selected region offers at least two programmes")
		return
	_choose(choice, choice.item_count - 1)
	var wanted: String = str(choice.get_item_metadata(choice.item_count - 1))
	await _tick(3)
	t.equal(app._selected_program_id, wanted, "a day passing does not change the programme the player picked")


func _test_header_buttons_follow_the_open_desk(t) -> void:
	await _fresh()
	app._paused = true
	app._open_budget()
	await _frames()
	t.truth(app.find_child("LegislationButton", true, false).disabled, "while a desk is open the other desks' buttons are off")
	app._close_budget()
	await _frames()
	t.truth(not app.find_child("LegislationButton", true, false).disabled, "and come back the moment it closes, even while paused")


func _test_a_budget_draft_holds_the_clock(t) -> void:
	await _fresh()
	app._open_budget()
	app._budget_adjustments["education"] = 0.05
	var day0: int = int(game.snapshot()["date"]["day_index"])
	await _tick(3)
	t.equal(int(game.snapshot()["date"]["day_index"]), day0, "time does not run over an unfinished budget draft")


func _test_opening_a_situation_pauses_the_clock(t) -> void:
	await _fresh()
	var s := Situation.new()
	s.event_id = "bank_run"
	s.arrived_turn = game._state.turn
	s.deadline_turn = game._state.turn + 2
	game._state.pending_situations.append(s)
	app.apply_snapshot(game.snapshot())
	app._paused = false
	app._open_situation("bank_run")
	t.truth(app._paused, "a decision on the desk stops the clock")


func _test_escape_closes_the_desk(t) -> void:
	await _fresh()
	app._open_diplomacy()
	var esc := InputEventAction.new()
	esc.action = "back"
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(2)
	t.truth(not app._desk_open(), "Escape closes the open desk")


func _test_save_and_load_shortcuts_wait_while_a_desk_is_open(t) -> void:
	await _fresh()
	_wipe_slot()
	app._open_budget()
	var save := InputEventAction.new()
	save.action = "save"
	save.pressed = true
	Input.parse_input_event(save)
	await _frames(2)
	t.truth(not FileAccess.file_exists("user://saves/%s.json" % TEST_SLOT), "the save shortcut does nothing while a desk is open")


func _test_space_pauses_even_with_a_button_focused(t) -> void:
	await _fresh()
	app._paused = false
	var budget_button: Button = app.find_child("BudgetButton", true, false)
	budget_button.grab_focus()
	var pause := InputEventAction.new()
	pause.action = "pause"
	pause.pressed = true
	Input.parse_input_event(pause)
	await _frames(2)
	t.truth(app._paused, "the pause key pauses")
	t.truth(not app._budget_open, "rather than pressing the focused button")


func _test_loading_resets_the_desks(t) -> void:
	await _fresh()
	app._do_save()
	await _frames()
	app._selected_country_id = "krasova"
	app._open_diplomacy()
	app._known_situations = {"ghost@1": true}
	app._do_load()
	await _frames(2)
	t.truth(not app._desk_open(), "loading a campaign closes any open desk")
	t.equal(app._selected_country_id, "", "and forgets selections from the previous state")
	t.truth(not app._known_situations.has("ghost@1"), "and what situations it had already seen")
