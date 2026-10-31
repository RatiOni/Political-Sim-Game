extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t = TestSupportScript.new()
	var reveal := TitleReveal.new()
	reveal.size = Vector2(600, 180)
	root.add_child(reveal)
	var fired := [false]
	reveal.revealed.connect(func() -> void: fired[0] = true)
	for _i in range(60):
		reveal._process(0.1)
	t.truth(fired[0], "the word is revealed")
	t.truth(not reveal.is_processing(), "and the wall stops once it has settled")
	var frozen := reveal._wall.duplicate()
	reveal._process(0.1)
	t.equal(reveal._wall, frozen, "the settled wall no longer changes")
	quit(t.finish())
