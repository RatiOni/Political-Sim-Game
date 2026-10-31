extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const MonthlyDigestScript = preload("res://scripts/native/presentation/monthly_digest.gd")
const StabilitySimScript = preload("res://scripts/native/sim/stability_sim.gd")
const HouseholdsSimScript = preload("res://scripts/native/sim/households_sim.gd")


func _initialize() -> void:
	_run.call_deferred()


func _state() -> GameState:
	var game: Node = root.get_node("NativeGame")
	game.new_campaign({"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal", "opening_role": "contextual", "seed": 424242})
	HouseholdsSimScript.ensure_households(game._state)
	return game._state


func _run() -> void:
	var t = TestSupportScript.new()

	# The named terms are exactly what approval moves toward.
	var state := _state()
	var terms: Dictionary = StabilitySimScript.approval_breakdown(state)
	t.equal(terms.keys(), ["The economy", "Party loyalty", "Household mood", "Public services", "Policy effects"], "approval names its five terms")
	var target := 0.5
	for value in terms.values():
		target += float(value)
	target = clampf(target, 0.05, 0.95)
	var expected := clampf(state.player.approval + (target - state.player.approval) * 0.05, 0.0, 1.0)
	StabilitySimScript.update_approval(state)
	t.near(state.player.approval, expected, 1e-12, "update_approval moves toward the sum of its named terms")

	# Causes.
	t.equal(MonthlyDigestScript._cause({"Unrest": -0.05, "Coalition loyalty": 0.20}, {"Unrest": -0.09, "Coalition loyalty": 0.20}, -0.01),
		", driven by unrest", "a fall names the term that fell")
	t.equal(MonthlyDigestScript._cause({"The economy": 0.01}, {"The economy": 0.03}, 0.01),
		", driven by the economy", "a rise names the term that rose")
	t.equal(MonthlyDigestScript._cause({"Unrest": -0.09, "Coalition loyalty": 0.2}, {"Unrest": -0.09, "Coalition loyalty": 0.2}, -0.01),
		", weighed down by unrest", "a fall with nothing moving names the heaviest drag")
	t.equal(MonthlyDigestScript._cause({"Coalition loyalty": 0.2}, {"Coalition loyalty": 0.2}, 0.01),
		"", "a rise with nothing moving names nothing rather than something structural")

	# The emergency comes first.
	state = _state()
	var before: Dictionary = MonthlyDigestScript.capture(state)
	state.active_budget.source = "continuing"
	state.player.approval -= 0.01
	var lines: Array[String] = MonthlyDigestScript.build(state, before)
	t.truth(lines[0].begins_with("The state is running on an emergency budget"), "an emergency budget leads the report")
	t.truth(lines[1].begins_with("Public approval deteriorates"), "ahead of approval")

	# Hardship names who.
	state = _state()
	before = MonthlyDigestScript.capture(state)
	for household in state.households.values():
		household.hardship += 0.10
	lines = MonthlyDigestScript.build(state, before)
	var hardship := ""
	for line in lines:
		if line.begins_with("Household hardship"):
			hardship = line
	var worst: HouseholdGroupState = HouseholdsSimScript.hardest_hit(state, 1)[0]
	t.truth(hardship.contains(", hardest for ") and hardship.contains(" in "), "rising hardship says who it hits hardest")
	t.truth(not hardship.contains(worst.group_id) and not hardship.contains(worst.region_id), "by name, not by id")

	# Polls close the month's report.
	state = _state()
	var game: Node = root.get_node("NativeGame")
	game.next_month(state)
	var digest: Array = state.monthly_digest
	t.truth(not digest.is_empty() and String(digest[-1]).begins_with("Polls:"), "the polls line comes last")

	# Month one: households are seeded by the first pulse, which is not a worsening.
	game.new_campaign({"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal", "opening_role": "contextual", "seed": 424242})
	game.next_month(game._state)
	var first_hardship := false
	for line in game._state.monthly_digest:
		if String(line).begins_with("Household hardship"):
			first_hardship = true
	t.truth(not first_hardship, "the first month does not report hardship deteriorating from nothing")
	quit(t.finish())
