extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")


func _initialize() -> void:
	_run.call_deferred()


func _prompt() -> Node:
	var open := get_nodes_in_group(Overlay.GROUP)
	return open[0] if not open.is_empty() else null


func _run() -> void:
	var t = TestSupportScript.new()
	var h = AppHarness.new(self, "test_desk_navigation")
	var app: Node = await h.fresh()

	await app._go_to_desk("records")
	await app._go_to_desk("budget")
	await h.frames()
	t.truth(app._budget_open and not app._records_open, "switching from the record to the budget leaves one desk open")
	t.truth(not app.find_child("LegislationButton", true, false).disabled, "other destinations stay live beside an open desk")
	t.truth(app.find_child("NationalPanel", true, false).visible, "the vital signs stay in view beside a desk")
	await app._go_to_desk("budget")
	await h.frames()
	t.equal(app._open_desk_name(), "", "the open desk's own button closes it")

	await app._go_to_desk("budget")
	app._budget_adjustments["defense"] = 0.05
	app._go_to_desk("diplomacy")
	await h.frames()
	var prompt := _prompt()
	t.truth(prompt != null, "leaving a budget draft asks first")
	(prompt.find_child("Choice_stay", true, false) as Button).pressed.emit()
	await h.frames()
	t.truth(app._budget_open and not app._diplomacy_open, "keeping the draft stays on the budget")
	app._go_to_desk("diplomacy")
	await h.frames()
	(_prompt().find_child("Choice_discard", true, false) as Button).pressed.emit()
	await h.frames()
	t.truth(app._diplomacy_open and not app._budget_open, "discarding it moves on")

	app._situation_open = true
	await app._go_to_desk("records")
	t.truth(not app._situation_open, "opening any desk closes every other kind")
	h.finish()
	quit(t.finish())
