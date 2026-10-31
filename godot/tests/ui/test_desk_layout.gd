extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t = TestSupportScript.new()
	var h = AppHarness.new(self, "test_desk_layout")
	var app: Node = await h.fresh()
	root.size = Vector2i(1920, 1080)
	app._resize_layout()
	await app._go_to_desk("budget")
	await h.frames(8)
	var scroll: Control = app.find_child("EnvelopeScroll", true, false)
	var view: Rect2 = scroll.get_global_rect()
	var rows := app.find_child("BudgetRows", true, false).get_children()
	t.equal(rows.size(), 8, "the budget has eight envelopes")
	for row in rows:
		var r: Rect2 = (row as Control).get_global_rect()
		t.truth(r.end.y <= view.end.y + 1.0, "%s is on screen without scrolling" % row.name)
	var room: Control = app.find_child("BudgetPanel", true, false).find_child("Room", true, false)
	var column: Control = room.get_parent().get_child(0)
	t.truth(column.size.x >= 0.55 * (column.size.x + room.size.x), "the desk's controls take most of its width")
	h.finish()
	quit(t.finish())
