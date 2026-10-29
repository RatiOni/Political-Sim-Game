extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const Polls = preload("res://tests/native/test_polls.gd")


func _test_a_strong_government_mostly_wins_and_beats_steady(t) -> void:
	var steady: Dictionary = Polls.journeys(["government"], 0.0, true)
	var strong: Dictionary = Polls.journeys(["government"], 0.0, true, true)
	t.truth(Polls.rate(strong, "player") >= 0.6, "an able, loyal cabinet on a steady budget mostly wins (%d of %d)" % [strong["player_kept"], strong["player_held"]])
	t.truth(Polls.rate(strong, "player") - Polls.rate(steady, "player") >= 0.15,
		"an able cabinet is worth at least fifteen points of re-election (%.2f vs %.2f)" % [Polls.rate(strong, "player"), Polls.rate(steady, "player")])


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_a_strong_government_mostly_wins_and_beats_steady(t)
	quit(t.finish())
