extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t = TestSupportScript.new()
	var header := Label.new()
	var footer := Label.new()
	root.add_child(header)
	root.add_child(footer)
	var notice := StatusNotice.new()
	root.add_child(notice)
	notice.bind(header, footer)
	notice.seconds = 0.1
	t.equal(header.text, "", "an idle header says nothing")
	notice.say("Saved to Slot 1")
	t.equal(header.text, "Saved to Slot 1", "the whole notice shows, not its last word")
	t.equal(header.get_theme_color("font_color"), UiPalette.GOOD, "a success is green")
	await create_timer(0.3).timeout
	t.equal(header.text, "", "and clears after a moment")
	t.truth(footer.text.contains("Saved to Slot 1"), "while the footer keeps the last notice")
	notice.say("Save failed: disk full", true)
	t.equal(header.get_theme_color("font_color"), UiPalette.BAD, "a failure is red")

	var h = AppHarness.new(self, "test_status_notice")
	var app: Node = await h.fresh()
	await h.tick(2)
	t.equal(app.find_child("PreviewStatus", true, false).text, "", "a day passing says nothing in the header")
	app._do_save()
	t.truth(app.find_child("PreviewStatus", true, false).text.to_upper().contains("SAVED"), "a save says so")
	h.finish()
	quit(t.finish())
