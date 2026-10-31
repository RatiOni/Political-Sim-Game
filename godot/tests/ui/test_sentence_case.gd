extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t = TestSupportScript.new()
	var h = AppHarness.new(self, "test_sentence_case")
	var app: Node = await h.fresh()
	var report: Label = app.find_child("ReportText", true, false)
	t.truth(not report.uppercase, "the monthly report is prose and keeps its case")
	var intro: Label = app.find_child("BudgetIntro", true, false)
	t.truth(not intro.uppercase, "the budget's instructions are prose")
	var heading: Label = app.find_child("AssemblyHeading", true, false)
	t.truth(heading.uppercase, "a heading stays in capitals")

	var prose := Label.new()
	prose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	app.add_child(prose)
	var tag := Label.new()
	app.add_child(tag)
	await h.frames()
	t.truth(not prose.uppercase, "a wrapping label added later keeps its case")
	t.truth(tag.uppercase, "a one-line label added later is set in capitals")
	h.finish()
	quit(t.finish())
