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

	# Escape and the desk's own close button both ask before dropping a draft.
	await app._go_to_desk("budget")
	app._budget_adjustments["defense"] = 0.05
	await h.frames()
	var gold: Color = UiPalette.GOLD
	var bb := app.find_child("BudgetButton", true, false) as Button
	t.truth(bb.has_theme_color_override("font_color") and bb.get_theme_color("font_color") == gold, "the open desk's button is lit amber")
	t.truth(not (app.find_child("RecordsButton", true, false) as Button).has_theme_color_override("font_color"), "and another destination is not")
	var esc := InputEventAction.new()
	esc.action = "back"
	esc.pressed = true
	Input.parse_input_event(esc)
	await h.frames(3)
	t.truth(_prompt() != null, "Escape on a budget draft asks first")
	(_prompt().find_child("Choice_stay", true, false) as Button).pressed.emit()
	await h.frames()
	t.truth(app._budget_open, "keeping the draft after Escape stays on the budget")
	(app.find_child("CloseBudgetButton", true, false) as Button).pressed.emit()
	await h.frames()
	t.truth(_prompt() != null, "the budget desk's close button asks too")
	(_prompt().find_child("Choice_stay", true, false) as Button).pressed.emit()
	await h.frames()
	h.finish()
	quit(t.finish())
