extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const Polls = preload("res://tests/native/test_polls.gd")


func _test_a_poor_government_mostly_loses(t) -> void:
	var unfunded: Dictionary = Polls.journeys(["government"], 0.0, false)
	var austere: Dictionary = Polls.journeys(["government"], -0.15, true)
	t.truth(Polls.rate(unfunded, "player") < 0.4, "a government that never passes a budget mostly loses (%d of %d)" % [unfunded["player_kept"], unfunded["player_held"]])
	t.truth(Polls.rate(austere, "player") < 0.4, "and so does one that cuts every year (%d of %d)" % [austere["player_kept"], austere["player_held"]])


func _test_a_strong_government_mostly_wins(t) -> void:
	var strong: Dictionary = Polls.journeys(["government"], -0.05, true, true)
	t.truth(Polls.rate(strong, "player") > 0.6, "an able, loyal cabinet on a steady budget mostly wins (%d of %d)" % [strong["player_kept"], strong["player_held"]])


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_a_poor_government_mostly_loses(t)
	_test_a_strong_government_mostly_wins(t)
	quit(t.finish())
