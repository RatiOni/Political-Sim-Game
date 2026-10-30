extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const Polls = preload("res://tests/native/test_polls.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")


func _test_a_poor_government_mostly_loses(t) -> void:
	var unfunded: Dictionary = Polls.journeys(["government"], 0.0, false)
	t.truth(Polls.rate(unfunded, "player") <= 0.35, "a government that never passes a budget mostly loses (%d of %d)" % [unfunded["player_kept"], unfunded["player_held"]])


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


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_a_poor_government_mostly_loses(t)
	quit(t.finish())
