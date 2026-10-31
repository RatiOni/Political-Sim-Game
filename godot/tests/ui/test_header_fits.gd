extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t = TestSupportScript.new()
	var h = AppHarness.new(self, "test_header_fits")
	var app: Node = await h.fresh()
	root.size = Vector2i(1280, 720)
	app._resize_layout()
	await h.frames(4)
	t.truth(app.get_combined_minimum_size().x <= 1280.0, "the dashboard minimum width fits 1280")
	for n in ["BudgetButton", "LegislationButton", "DiplomacyButton", "RecordsButton", "PlayButton", "SaveButton", "LoadButton"]:
		var c: Control = app.find_child(n, true, false)
		t.truth(c != null and c.is_visible_in_tree(), "%s stays reachable" % n)
	h.finish()
	quit(t.finish())
