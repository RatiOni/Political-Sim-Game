extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const ENVELOPES := ["state_administration", "foreign_affairs", "justice_and_policing", "national_defense",
	"infrastructure", "industry_and_jobs", "education", "health_and_welfare"]


static func _state(role: String, seed: int = 717) -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": seed})
	state.rng = SimRng.from_seed(seed)
	BudgetSim.ensure_budget_state(state)
	return state


static func steady_budget(state: GameState) -> void:
	var due := state.month == 10 or BudgetSim.is_emergency(state)
	if not state.player.in_government or not due or state.pending_budget != null:
		return
	var adjustments := {}
	for e in ENVELOPES:
		adjustments[e] = 0.0
	if BudgetActions.propose(state, adjustments).get("ok", false):
		for f in state.country.factions:
			if not f.in_coalition:
				BudgetActions.lobby(state, f.id)
				break
		BudgetActions.vote(state)


static func _shares(budget: AnnualBudget) -> Dictionary:
	var total := 0.0
	for v in budget.allocations.values():
		total += float(v)
	var out := {}
	for k in budget.allocations:
		out[k] = float(budget.allocations[k]) / total
	return out


func _test_an_ai_government_ends_an_inherited_emergency_at_once(t) -> void:
	var state := _state("opposition")
	state.month = 6
	state.active_budget = BudgetSim.activate(state, BudgetSim._emergency_resolution(state))
	t.truth(BudgetSim.is_emergency(state), "sanity: the state starts on an emergency budget")
	BudgetSim.process_fiscal_year(state)
	t.truth(not BudgetSim.is_emergency(state), "a government that is not the player's passes its plan at once")
	t.equal(state.active_budget.source, "government_ai", "its own restrained plan")
	t.equal(state.active_budget.year, state.year, "for the current year")


func _test_an_ai_plan_is_restrained_not_compounding(t) -> void:
	var state := _state("opposition")
	var opening := _shares(state.active_budget)
	for _y in range(10):
		state.year += 1
		state.month = 1
		state.pending_budget = null
		BudgetSim.process_fiscal_year(state)
	var drift := 0.0
	var now := _shares(state.active_budget)
	for k in opening:
		drift = maxf(drift, absf(float(now[k]) - float(opening[k])) / float(opening[k]))
	t.truth(drift <= BudgetSim.AI_TILT_LIMIT + 1e-6, "ten years of the same government tilt each envelope at most once (%.3f)" % drift)


func _test_a_steady_player_budget_passes(t) -> void:
	var state := _state("government")
	state.month = 10
	steady_budget(state)
	t.truth(state.pending_budget != null and state.pending_budget.status == "approved",
		"a neutral budget clears an ordinary parliament")


func _test_restoring_supply_is_always_affordable(t) -> void:
	var state := _state("government")
	state.month = 3
	state.active_budget = BudgetSim.activate(state, BudgetSim._emergency_resolution(state))
	state.player.political_capital = 0.0
	var neutral := {}
	for e in ENVELOPES:
		neutral[e] = 0.0
	t.truth(BudgetActions.propose(state, neutral).get("ok", false), "an unfunded government can always table a neutral budget")
	var reshaped := _state("government")
	reshaped.month = 3
	reshaped.active_budget = BudgetSim.activate(reshaped, BudgetSim._emergency_resolution(reshaped))
	reshaped.player.political_capital = 0.0
	var cuts := neutral.duplicate()
	cuts["education"] = -0.10
	t.truth(not BudgetActions.propose(reshaped, cuts).get("ok", true), "but reshaping the state still costs capital")


func _test_twenty_years_without_unfunded_years(t) -> void:
	for role in ["government", "opposition"]:
		for seed in [919191, 31]:
			var state := _state(role, seed)
			var player_emergency := 0
			var ai_emergency := 0
			for _m in range(240):
				steady_budget(state)
				NativeGameScript.next_month(state)
				if BudgetSim.is_emergency(state):
					if state.player.in_government:
						player_emergency += 1
					else:
						ai_emergency += 1
			t.equal(ai_emergency, 0, "%s seed %d: an AI government is never left unfunded" % [role, seed])
			t.truth(player_emergency <= 6, "%s seed %d: a steady player government is almost never unfunded (%d months)" % [role, seed, player_emergency])


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_an_ai_government_ends_an_inherited_emergency_at_once(t)
	_test_an_ai_plan_is_restrained_not_compounding(t)
	_test_a_steady_player_budget_passes(t)
	_test_restoring_supply_is_always_affordable(t)
	_test_twenty_years_without_unfunded_years(t)
	quit(t.finish())
