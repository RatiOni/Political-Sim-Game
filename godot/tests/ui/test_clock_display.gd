extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")


func _initialize() -> void:
	_run.call_deferred()


func _lit(pips: Array[Button]) -> int:
	var n := 0
	for pip in pips:
		if pip.button_pressed:
			n += 1
	return n


func _run() -> void:
	var t = TestSupportScript.new()
	var play := Button.new()
	var date := Label.new()
	var pips: Array[Button] = []
	for _i in 5:
		var pip := Button.new()
		pip.toggle_mode = true
		pips.append(pip)
		root.add_child(pip)
	root.add_child(play)
	root.add_child(date)
	var clock := ClockDisplay.new()
	root.add_child(clock)
	clock.bind(play, date, pips)

	clock.show_state("1 Mar 1993", true, 3, true)
	t.truth(play.text.to_upper().contains("PLAY"), "a stopped clock's button offers to start it")
	t.truth(date.text.contains("1 Mar 1993") and date.text.to_upper().contains("PAUSED"), "the date says the clock is stopped")
	t.equal(_lit(pips), 0, "no speed pip is lit while the clock is stopped")
	t.truth(clock.is_pulsing(), "a stopped clock pulses until someone starts it")

	clock.show_state("1 Mar 1993", false, 3, true)
	t.truth(play.text.to_upper().contains("PAUSE"), "a running clock's button offers to stop it")
	t.truth(date.text.to_upper().contains("SPEED 3") and not date.text.to_upper().contains("PAUSED"), "the date says how fast time runs")
	t.equal(_lit(pips), 3, "the pips light as a ladder up to the speed")
	t.truth(pips[2].button_pressed and not pips[3].button_pressed, "exactly the first three")
	t.truth(not clock.is_pulsing(), "a running clock does not pulse")
	t.near(date.modulate.a, 1.0, 0.001, "and sits at full brightness")

	clock.show_state("1 Mar 1993", true, 3, false)
	t.truth(not clock.is_pulsing(), "a clock with no campaign behind it does not pulse")

	var h = AppHarness.new(self, "test_clock_display")
	var app: Node = await h.fresh()
	t.truth(app.find_child("DateLabel", true, false).text.to_upper().contains("PAUSED"), "the dashboard opens on a visibly stopped clock")
	app._toggle_pause()
	await h.frames()
	t.truth(app.find_child("DateLabel", true, false).text.to_upper().contains("SPEED 1"), "and says so when it starts")
	h.finish()
	quit(t.finish())
