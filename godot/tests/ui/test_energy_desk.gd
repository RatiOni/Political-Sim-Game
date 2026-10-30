extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const TEST_SLOT := "test_energy_desk"

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


func _energy_button(prefix: String) -> Button:
	var steps: VBoxContainer = app.find_child("EnergySteps", true, false)
	for child in steps.get_children():
		if child is Button and (child as Button).text.to_upper().begins_with(prefix.to_upper()):
			return child
	return null


func _run() -> void:
	_wipe_slot()
	await _test_the_desk_shows_the_contract(t)
	await _test_arrears_can_be_paid_from_the_desk(t)
	await _test_a_threat_and_a_cut_keep_the_desk_width(t)
	await _test_a_refused_step_changes_nothing(t)
	_wipe_slot()
	if app != null:
		app.queue_free()
	quit(t.finish())


func _test_the_desk_shows_the_contract(t) -> void:
	await _fresh()
	app._open_diplomacy()
	await _frames()
	var contract: Label = app.find_child("EnergyContract", true, false)
	t.truth(contract != null and contract.text.contains("KRASOVA") and contract.text.contains("Arrears"), "the desk shows the gas contract and its arrears")
	var spot := _energy_button("Emergency spot purchase")
	t.truth(spot != null, "and offers the energy operations")


func _test_arrears_can_be_paid_from_the_desk(t) -> void:
	await _fresh()
	app._open_diplomacy()
	await _frames()
	var button := _energy_button("Pay down the gas arrears")
	t.truth(button != null and not button.disabled, "the arrears can be paid from the desk")
	button.pressed.emit()
	await _frames(3)
	t.equal(game._state.foreign.gas.arrears, 0.0, "pressing it pays them")
	var status: Label = app.find_child("DiplomacyStatus", true, false)
	t.truth(status.text.contains("arrears"), "the desk reports it")
	var again := _energy_button("Pay down the gas arrears")
	t.truth(again != null and again.disabled and again.tooltip_text.contains("no gas arrears"), "and then says why it cannot be pressed again")


func _test_a_threat_and_a_cut_keep_the_desk_width(t) -> void:
	await _fresh()
	app._open_diplomacy()
	await _frames(3)
	var panel: Control = app.find_child("DiplomacyPanel", true, false)
	var width := panel.size.x
	var window_width := root.size.x
	var energy: Dictionary = app.snapshot["foreign"]["energy"]
	energy["threat"] = true
	energy["cut"] = 0.4
	energy["supplier"] = "Krasova " .repeat(60)
	for step in energy["steps"]:
		step["label"] = "Ardenia " .repeat(80)
		step["disabled_reason"] = "Because " .repeat(80)
	app._refresh_energy()
	await _frames(3)
	t.equal(panel.size.x, width, "a threatened, cut, wordy contract leaves the desk width unchanged")
	t.equal(root.size.x, window_width, "and the window width")
	var contract: Label = app.find_child("EnergyContract", true, false)
	t.truth(contract.text.contains("VALVE") and contract.text.contains("CUT"), "and still names the threat and the cut")


func _test_a_refused_step_changes_nothing(t) -> void:
	await _fresh()
	app._open_diplomacy()
	await _frames()
	_energy_button("Pay down the gas arrears").pressed.emit()
	await _frames(3)
	var before: Dictionary = game._state.to_dict()
	var again := _energy_button("Pay down the gas arrears")
	again.pressed.emit()
	await _frames(3)
	var status: Label = app.find_child("DiplomacyStatus", true, false)
	t.truth(status.text.begins_with("REFUSED"), "a refused step says so on the desk")
	t.truth(game._state.to_dict() == before, "and changes no state")
	var steps: VBoxContainer = app.find_child("EnergySteps", true, false)
	var tall := true
	for child in steps.get_children():
		if child is Button and (child as Button).custom_minimum_size.y < 44.0:
			tall = false
	t.truth(tall, "every energy button is at least 44 px tall")
