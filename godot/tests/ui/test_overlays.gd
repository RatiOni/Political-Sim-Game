extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")


func _initialize() -> void:
	_run.call_deferred()


func _day(app: Node) -> int:
	return int(app.snapshot.get("date", {}).get("day_index", -1))


func _run() -> void:
	var t = TestSupportScript.new()
	var h = AppHarness.new(self, "test_overlays")
	var app: Node = await h.fresh()
	var answer := [""]
	var prompt := ConfirmPrompt.ask(app, "Discard?", "Something was left unfinished.", [["yes", "Discard"], ["no", "Keep"]])
	prompt.chosen.connect(func(choice: String) -> void: answer[0] = choice)
	await h.frames()
	t.truth(Overlay.any_open(self), "a prompt counts as an open overlay")
	t.truth(app._clock_held(), "and holds the clock")
	var day := _day(app)
	await h.tick(3)
	t.equal(_day(app), day, "no day passes under a prompt")
	(prompt.find_child("Choice_yes", true, false) as Button).pressed.emit()
	await h.frames()
	t.equal(answer[0], "yes", "a pressed answer is reported")
	t.truth(not Overlay.any_open(self), "and the prompt is gone")
	t.truth(not app._clock_held(), "and the clock is free")

	var second := ConfirmPrompt.ask(app, "Leave?", "Progress will be lost.", [["leave", "Leave"], ["stay", "Stay"]])
	second.chosen.connect(func(choice: String) -> void: answer[0] = choice)
	await h.frames()
	var escape := InputEventAction.new()
	escape.action = "back"
	escape.pressed = true
	Input.parse_input_event(escape)
	await h.frames(3)
	t.equal(answer[0], "stay", "Escape takes the last, safe answer")
	t.truth(not app._desk_open(), "and does not also act on the dashboard")
	h.finish()
	quit(t.finish())
