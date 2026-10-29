extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const Polls = preload("res://tests/native/test_polls.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")


func _test_a_poor_government_mostly_loses(t) -> void:
	var unfunded: Dictionary = Polls.journeys(["government"], 0.0, false)
	var austere: Dictionary = Polls.journeys(["government"], -0.15, true)
	t.truth(Polls.rate(unfunded, "player") <= 0.35, "a government that never passes a budget mostly loses (%d of %d)" % [unfunded["player_kept"], unfunded["player_held"]])
	t.truth(Polls.rate(austere, "player") <= 0.35, "and so does one that cuts every year (%d of %d)" % [austere["player_kept"], austere["player_held"]])


func _test_a_strong_government_mostly_wins(t) -> void:
	var strong: Dictionary = Polls.journeys(["government"], 0.0, true, true)
	t.truth(Polls.rate(strong, "player") >= 0.6, "an able, loyal cabinet on a steady budget mostly wins (%d of %d)" % [strong["player_kept"], strong["player_held"]])


static func ruling_share(policy_step: float, able: bool, scale: float, seeds: Array = [11, 22, 33, 44, 55, 66]) -> float:
	PollsSim.record_scale = scale
	var total := 0.0
	var n := 0
	for seed in seeds:
		var state := Polls._state("government", seed)
		if able:
			for m in state.ministers:
				m.competence = 0.95
				m.loyalty = 0.95
				m.trait_id = "technocrat"
		for _m in range(Elections.TERM_MONTHS):
			Polls.budget_policy(state, policy_step)
			Polls.ordinary_programme(state)
			NativeGameScript.next_month(state)
		var r: ElectionResult = state.election_history[-1]
		total += float(r.vote_share[state.player.faction_id])
		n += 1
	PollsSim.record_scale = 1.0
	return total / n


func _test_the_record_moves_the_result(t) -> void:
	var austere_on := ruling_share(-0.15, false, 1.0)
	var austere_off := ruling_share(-0.15, false, 0.0)
	t.truth(austere_on < austere_off, "austerity's party polls worse when the record counts (%.3f vs %.3f)" % [austere_on, austere_off])
	var strong_on := ruling_share(0.0, true, 1.0)
	var strong_off := ruling_share(0.0, true, 0.0)
	t.truth(strong_on > strong_off, "a strong government's party polls better when the record counts (%.3f vs %.3f)" % [strong_on, strong_off])


func _test_a_strong_record_never_hurts(t) -> void:
	for seed in [11, 22, 33, 44, 55, 66]:
		var on := ruling_share(0.0, true, 1.0, [seed])
		var off := ruling_share(0.0, true, 0.0, [seed])
		t.truth(on > off, "seed %d: a strong government's record raises its party's share (%.3f vs %.3f)" % [seed, on, off])


func _test_strong_beats_steady(t) -> void:
	var steady: Dictionary = Polls.journeys(["government"], 0.0, true)
	var strong: Dictionary = Polls.journeys(["government"], 0.0, true, true)
	t.truth(Polls.rate(strong, "player") - Polls.rate(steady, "player") >= 0.15,
		"an able cabinet is worth at least fifteen points of re-election (%.2f vs %.2f)" % [Polls.rate(strong, "player"), Polls.rate(steady, "player")])


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_a_poor_government_mostly_loses(t)
	_test_a_strong_government_mostly_wins(t)
	_test_the_record_moves_the_result(t)
	_test_strong_beats_steady(t)
	_test_a_strong_record_never_hurts(t)
	quit(t.finish())
