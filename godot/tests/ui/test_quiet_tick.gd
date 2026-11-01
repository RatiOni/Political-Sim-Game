extends SceneTree

## A day on which nothing visible changed must not rebuild or repaint the
## dashboard: the clock pushes a snapshot every day, and rebuilding identical
## rows and re-running the map's growth painter read as the UI twitching.

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")


func _initialize() -> void:
	_run.call_deferred()


func _ids(parent: Node) -> Array:
	return parent.get_children().map(func(n: Node) -> int: return n.get_instance_id())


func _run() -> void:
	var t = TestSupportScript.new()
	var h = AppHarness.new(self, "test_quiet_tick")
	var app: Node = await h.fresh()
	await h.tick(3)
	await create_timer(Arrive.TYPE_SECONDS + 0.5).timeout
	var map: Node = app.find_child("ArdeniaMap", true, false)
	var wire: Node = app.find_child("WireLog", true, false)
	var items: Node = app.find_child("DecisionItems", true, false)
	var report: Label = app.find_child("ReportText", true, false)

	# Feed the same snapshot again: the cheapest possible "quiet day".
	var map_key: int = map._snapshot_key
	var wire_ids := _ids(wire)
	var item_ids := _ids(items)
	var report_text := report.text
	app.apply_snapshot(app.snapshot)
	await h.frames()
	t.equal(map._snapshot_key, map_key, "an unchanged snapshot leaves the map alone")
	t.equal(_ids(wire), wire_ids, "an unchanged wire keeps its lines instead of rebuilding them")
	t.equal(_ids(items), item_ids, "an unchanged decision rail keeps its rows")
	t.equal(report.text, report_text, "the report keeps its text")
	t.equal(report.visible_ratio, 1.0, "and is not typed on again")

	# A new line on the wire types on rather than appearing whole.
	var changed: Dictionary = app.snapshot.duplicate(true)
	var rows: Array = changed.get("dispatches", []).duplicate()
	rows.append("A test dispatch arrives on the wire.")
	changed["dispatches"] = rows
	app.apply_snapshot(changed)
	await h.frames()
	var last := wire.get_child(wire.get_child_count() - 1) as Label
	t.truth(last.visible_ratio < 1.0, "a fresh dispatch types on instead of snapping in")
	h.finish()
	quit(t.finish())
