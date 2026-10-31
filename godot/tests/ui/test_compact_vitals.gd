extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t = TestSupportScript.new()
	var h = AppHarness.new(self, "test_compact_vitals")
	var app: Node = await h.fresh()
	root.size = Vector2i(1280, 720)
	app._resize_layout()
	await h.frames(3)
	t.truth(app._is_compact(), "1280x720 is a compact layout")
	var national: Control = app.find_child("NationalPanel", true, false)
	t.truth(national.visible, "the government's vital signs survive a small window")
	t.equal(national.custom_minimum_size.x, float(app.NATIONAL_WIDTH_COMPACT), "in a narrower column")
	t.truth(app._vital_row("approval").visible, "approval is still on screen")

	root.size = Vector2i(1920, 1080)
	app._resize_layout()
	await h.frames(3)
	t.truth(not app._is_compact(), "1920x1080 is not compact")
	t.equal(national.custom_minimum_size.x, float(app.NATIONAL_WIDTH_WIDE), "and the column widens again")

	var bar := StatBar.new()
	root.add_child(bar)
	bar.set_meter("Stability", 0.5, "50%", UiPalette.GOOD)
	bar.size = Vector2(200, 22)
	t.truth(not bar.shows_gauge(), "a narrow meter drops its gauge and keeps its figure")
	bar.size = Vector2(300, 22)
	t.truth(bar.shows_gauge(), "a wide one keeps it")
	h.finish()
	quit(t.finish())
