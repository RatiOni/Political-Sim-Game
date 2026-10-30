extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const Polls = preload("res://tests/native/test_polls.gd")


func _test_an_austere_government_mostly_loses(t) -> void:
	var austere: Dictionary = Polls.journeys(["government"], -0.15, true)
	t.truth(Polls.rate(austere, "player") <= 0.35, "and so does one that cuts every year (%d of %d)" % [austere["player_kept"], austere["player_held"]])


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_an_austere_government_mostly_loses(t)
	quit(t.finish())
