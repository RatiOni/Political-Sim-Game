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


func _test_an_ai_budget_grows_with_revenue_and_faces_parliament(t) -> void:
	var state := _state("opposition")
	var before := state.active_budget.expenditure()
	state.country.economy.structural_revenue *= 1.10
	state.year += 1
	state.month = 1
	state.pending_budget = null
	BudgetSim.process_fiscal_year(state)
	t.near(state.active_budget.expenditure() / before, 1.10, 0.02, "an AI government's budget grows with revenue")
	var seats := 0
	for f in state.country.factions:
		seats += f.seats
	t.equal(state.active_budget.votes_for + state.active_budget.votes_against, seats, "and is put to a division of the whole chamber")
	var hostile := _state("opposition")
	for f in hostile.country.factions:
		f.seats = 5 if f.in_coalition else 30
		f.ideology.economic = 1.0 if f.in_coalition else -1.0
		f.ideology.social = -1.0 if f.in_coalition else 1.0
		for w in f.wings:
			w.ideology.economic = f.ideology.economic
			w.ideology.social = f.ideology.social
	hostile.year += 1
	hostile.month = 1
	hostile.pending_budget = null
	BudgetSim.process_fiscal_year(hostile)
	var history_failed := hostile.budget_history.any(func(b: AnnualBudget) -> bool: return b.source == "government_ai" and b.status == "rejected")
	t.truth(history_failed and BudgetSim.is_emergency(hostile),
		"a minority AI budget can fail, and then the state runs on a continuing budget")


func _test_a_new_government_inherits_the_old_spending(t) -> void:
	var state := _state("opposition")
	state.active_budget.allocations["education"] = float(state.active_budget.allocations["education"]) * 1.30
	var skewed: float = _shares(state.active_budget)["education"]
	var default_share: float = _shares(BudgetSim.ensure_budget_state(_state("opposition")))["education"]
	for f in state.country.factions:
		if f.id != state.ruling_faction_id and f.id != state.player.faction_id and f.seats > 0:
			state.ruling_faction_id = f.id
			break
	state.year += 1
	state.month = 1
	state.pending_budget = null
	BudgetSim.process_fiscal_year(state)
	var now: float = _shares(state.active_budget)["education"]
	t.truth(absf(now - skewed) / skewed <= BudgetSim.AI_TILT_LIMIT + 1e-6 and absf(now - skewed) < absf(now - default_share),
		"a new government starts from the spending it inherits, not from a blank sheet (%.3f, inherited %.3f, default %.3f)" % [now, skewed, default_share])


func _test_inherited_laws_are_not_the_players_overhead(t) -> void:
	var state := _state("government")
	var inherited := Law.new()
	inherited.id = "minimum_wage_act"
	inherited.status = "enacted"
	inherited.proposed_by = "national_conservatives"
	state.enacted_laws.append(inherited)
	t.near(float(PoliticalCapital.upkeep(state)["laws"]), 0.0, 1e-9, "a law an earlier government passed costs this one no upkeep")
	var own := Law.new()
	own.id = "press_freedom_act"
	own.status = "enacted"
	own.proposed_by = state.player.faction_id
	state.enacted_laws.append(own)
	t.near(float(PoliticalCapital.upkeep(state)["laws"]), PoliticalCapital.PC_UPKEEP_LAW, 1e-9, "while the government's own laws do")


func _test_october_proposals_keep_a_long_government_funded(t) -> void:
	var state := _state("government", 919191)
	var emergency := 0
	for _m in range(240):
		if state.player.in_government and state.month == 10 and state.pending_budget == null:
			var plan := {}
			for e in ENVELOPES:
				plan[e] = -0.05 if state.year == 1993 else 0.0
			if BudgetActions.propose(state, plan).get("ok", false):
				for f in state.country.factions:
					if not f.in_coalition:
						BudgetActions.lobby(state, f.id)
						break
				BudgetActions.vote(state)
		NativeGameScript.next_month(state)
		if BudgetSim.is_emergency(state) and state.player.in_government:
			emergency += 1
	t.truth(emergency <= 3, "a government that proposes each October stays funded for twenty years (%d emergency months)" % emergency)


func _test_steady_households_hold_their_confidence(t) -> void:
	for seed in [919191, 31]:
		var state := _state("government", seed)
		var first := 0.0
		var last := 0.0
		for m in range(240):
			steady_budget(state)
			NativeGameScript.next_month(state)
			var c := HouseholdsSim.national_confidence(state)
			if m >= 12 and m < 48:
				first += c / 36.0
			if m >= 204:
				last += c / 36.0
		t.truth(absf(last - first) <= 0.03, "seed %d: steady government keeps household confidence flat over twenty years (%.3f to %.3f)" % [seed, first, last])


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_an_ai_government_ends_an_inherited_emergency_at_once(t)
	_test_an_ai_plan_is_restrained_not_compounding(t)
	_test_a_steady_player_budget_passes(t)
	_test_restoring_supply_is_always_affordable(t)
	_test_twenty_years_without_unfunded_years(t)
	_test_an_ai_budget_grows_with_revenue_and_faces_parliament(t)
	_test_a_new_government_inherits_the_old_spending(t)
	_test_inherited_laws_are_not_the_players_overhead(t)
	_test_october_proposals_keep_a_long_government_funded(t)
	_test_steady_households_hold_their_confidence(t)
	quit(t.finish())
