extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const Polls = preload("res://tests/native/test_polls.gd")


func _test_steady_governments_are_judged_like_ordinary_ones(t) -> void:
	var governing := Polls.journeys(["government"], 0.0, true)
	var opposing := Polls.journeys(["opposition"], 0.0, true)
	t.truth(governing["valid"] and opposing["valid"], "twenty calendar-true years from either side stay valid")
	var player_held: int = governing["player_held"] + opposing["player_held"]
	var player_kept: int = governing["player_kept"] + opposing["player_kept"]
	var player_rate := float(player_kept) / maxf(1.0, player_held)
	t.truth(player_rate >= 0.4 and player_rate <= PollsSim.STEADY_RETURN_CEILING, "a steady player government is usually returned (%d of %d)" % [player_kept, player_held])
	t.truth(Polls.rate(opposing, "player") >= 0.25, "a player who wins office from opposition is returned often enough (%d of %d)" % [opposing["player_kept"], opposing["player_held"]])
	var won_held: int = governing["ai_won_held"] + opposing["ai_won_held"]
	var won_kept: int = governing["ai_won_kept"] + opposing["ai_won_kept"]
	var won_rate := float(won_kept) / maxf(1.0, won_held)
	t.truth(won_rate >= 0.3 and won_rate <= 0.7, "an AI party that won power is returned often enough (%d of %d)" % [won_kept, won_held])
	var lost: Array = governing["lost"] + opposing["lost"]
	var kept: Array = governing["kept"] + opposing["kept"]
	t.truth(Polls.mean(lost) < Polls.mean(kept), "governments that fell were less approved (%.2f) than those returned (%.2f)" % [Polls.mean(lost), Polls.mean(kept)])
	t.truth((governing["sequences"] as Dictionary).size() >= 3,
		"six seeds write at least three political histories (%d)" % (governing["sequences"] as Dictionary).size())


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_steady_governments_are_judged_like_ordinary_ones(t)
	quit(t.finish())
