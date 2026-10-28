extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")


static func _state(role: String = "contextual") -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	BudgetSim.ensure_budget_state(state)
	return state


static func _balanced(state: GameState) -> void:
	var econ := state.country.economy
	econ.structural_revenue = econ.structural_expenditure + econ.interest_bill()
	econ.spending_trend = econ.structural_expenditure


func _test_growth_wears_down_the_debt_ratio(t) -> void:
	var state := _state()
	_balanced(state)
	var econ := state.country.economy
	econ.effective_interest_rate = 0.0
	var debt0 := econ.public_debt_pct
	for _i in range(24):
		econ.structural_revenue = econ.structural_expenditure + econ.interest_bill()
		EconomySim.update(state)
	t.truth(econ.public_debt_pct < debt0 - 0.01,
		"with a balanced budget, two years of growth lower the debt ratio (%.3f -> %.3f)" % [debt0, econ.public_debt_pct])


func _test_a_shrinking_economy_does_not_write_off_debt(t) -> void:
	var state := _state()
	var econ := state.country.economy
	var stock0 := econ.public_debt_pct * econ.gdp
	econ.gdp *= 0.90
	EconomySim._update_balance_sheet(state)
	var stock1 := econ.public_debt_pct * econ.gdp
	var deficit := (econ.budget.expenditure - econ.budget.revenue) / 12.0
	t.near(stock1, stock0 + deficit, 1.0, "a 10% fall in output leaves what is owed unchanged, plus this month's deficit")


func _test_a_law_growth_effect_lasts(t) -> void:
	var state := _state()
	var base := _state()
	EffectBundle.apply(state, {"gdp_growth_delta": 0.01}, "Test law", "law:test")
	for _i in range(24):
		EconomySim.update(state)
		EconomySim.update(base)
	var gap := state.country.economy.structural_growth_rate - base.country.economy.structural_growth_rate
	t.truth(gap > 0.008, "a permanent growth effect is still there two years later (%.4f of 0.01)" % gap)


func _test_inflation_reads_this_months_deficit(t) -> void:
	var a := _state()
	var b := _state()
	b.country.economy.structural_expenditure *= 1.5
	b.country.economy.spending_trend = b.country.economy.structural_expenditure
	EconomySim.update(a)
	EconomySim.update(b)
	t.truth(b.country.economy.structural_inflation > a.country.economy.structural_inflation,
		"a deficit opened this month pushes inflation this month")


func _test_unknown_envelopes_cannot_inflate_spending(t) -> void:
	var state := _state()
	state.active_budget.allocations["retired_envelope"] = 500.0
	var econ := state.country.economy
	EconomySim.update(state)
	t.near(state.active_budget.expenditure(), econ.structural_expenditure, 1.0,
		"the ledger still sums to the spending baseline when a save carries an unknown envelope")


func _test_an_emergency_keeps_escalating_across_january(t) -> void:
	var state := _state()
	state.year += 1
	state.month = 1
	BudgetSim.process_fiscal_year(state)
	for m in range(2, 13):
		state.month = m
		BudgetSim.process_fiscal_year(state)
	var months_before := state.active_budget.emergency_months
	var approval_before := state.player.approval
	state.year += 1
	state.month = 1
	BudgetSim.process_fiscal_year(state)
	t.truth(BudgetSim.is_emergency(state), "a second missed budget continues the emergency")
	t.equal(state.active_budget.emergency_months, months_before + 1, "and its months keep counting")
	var expected := BudgetSim.EMERGENCY_MONTHLY_APPROVAL_COST * minf(BudgetSim.EMERGENCY_MAX_ESCALATION,
		1.0 + float(months_before + 1) / BudgetSim.EMERGENCY_ESCALATION_MONTHS)
	t.near(approval_before - state.player.approval, expected, 1e-9,
		"January of year two costs the escalated monthly price, not a fresh start")


func _test_a_ministry_seeded_before_the_budget_gets_a_real_baseline(t) -> void:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "contextual", "seed": 1})
	MinistriesSim.ensure_ministries(state)
	BudgetSim.ensure_budget_state(state)
	MinistriesSim.simulate(state)
	var finance: MinistryState = state.ministries["Finance"]
	t.truth(finance.funding_ratio < 1.5, "a ministry checked before the first budget is not read as lavishly funded (%.2f)" % finance.funding_ratio)


func _test_trade_decays_once_a_pact_is_gone(t) -> void:
	var state := _state()
	var id := String(state.country.relations.keys()[0])
	DiplomacySim.set_trade(state, id, 2000.0)
	for _i in range(24):
		DiplomacySim.monthly(state)
	t.truth((state.country.relations[id] as Country.BilateralRelation).trade_volume < 2000.0,
		"without a pact, trade drifts down")


func _test_sanctions_keep_trade_at_zero(t) -> void:
	var state := _state()
	var id := String(state.country.relations.keys()[0])
	for rel in DiplomacySim.pair(state, id):
		(rel as Country.BilateralRelation).sanctioned = true
	DiplomacySim.set_trade(state, id, 800.0)
	for _i in range(6):
		DiplomacySim.monthly(state)
	t.truth((state.country.relations[id] as Country.BilateralRelation).trade_volume < 800.0 * 0.85,
		"trade under sanctions collapses")


func _test_appointments_cost_capital_and_are_rationed(t) -> void:
	var state := _state()
	state.player.political_capital = 100.0
	var r := CabinetActions.issue_shortlist(state, "Finance")
	t.truth(r.get("ok", false), "a shortlist can be drawn")
	t.truth(state.player.political_capital < 100.0, "drawing one costs political capital")
	var shortlist: Array = state.cabinet_shortlists["Finance"]
	t.truth(CabinetActions.appoint(state, "Finance", shortlist[1].id).get("ok", false), "an appointment can be made")
	var again := CabinetActions.issue_shortlist(state, "Finance")
	t.truth(not again.get("ok", true), "the same post cannot be reshuffled again at once")


func _test_validator_checks_every_shortlist_candidate(t) -> void:
	var state := _state()
	state.player.political_capital = 100.0
	CabinetActions.issue_shortlist(state, "Finance")
	var candidate: Minister = state.cabinet_shortlists["Finance"][0]
	candidate.loyalty = 1.4
	t.truth(StateValidator.validate(state).size() > 0, "a candidate with impossible loyalty is rejected")
	candidate.loyalty = 0.5
	candidate.faction_id = "no_such_party"
	t.truth(StateValidator.validate(state).size() > 0, "so is one from a party that does not exist")
	candidate.faction_id = state.player.faction_id
	candidate.id = state.ministers[0].id
	t.truth(StateValidator.validate(state).size() > 0, "and one whose id belongs to a serving minister")


func _test_an_event_growth_shock_fades(t) -> void:
	var state := _state()
	var base := _state()
	EffectBundle.apply(state, {"gdp_growth_delta": -0.01}, "Test event", "event:test", false)
	for _i in range(24):
		EconomySim.update(state)
		EconomySim.update(base)
	var gap := base.country.economy.structural_growth_rate - state.country.economy.structural_growth_rate
	t.truth(gap < 0.002, "an event's growth shock has faded two years on (%.4f left of 0.01)" % gap)


func _test_emergency_escalation_is_capped(t) -> void:
	var state := _state()
	state.year += 1
	state.month = 1
	BudgetSim.process_fiscal_year(state)
	state.active_budget.emergency_months = 200
	var before := state.player.approval
	state.month = 2
	BudgetSim.process_fiscal_year(state)
	t.truth(before - state.player.approval <= BudgetSim.EMERGENCY_MONTHLY_APPROVAL_COST * BudgetSim.EMERGENCY_MAX_ESCALATION + 1e-9,
		"a years-long emergency costs a steep but bounded amount each month")


static func _test_save_floats_keep_full_precision(t) -> void:
	var slot := "test_precision"
	var config := {"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "contextual", "seed": 424242}
	var game = load("res://scripts/native/native_game.gd").new()
	game.new_campaign(config)
	for _i in range(70):
		game.advance_day()
	t.truth(game.save(slot).get("ok", false), "precision: save succeeds")
	var recorded: Dictionary = game._state.to_dict()
	game.load(slot)
	t.truth(game._state.to_dict() == recorded, "precision: a loaded state equals the saved one exactly")
	var second = load("res://scripts/native/native_game.gd").new()
	second.load(slot)
	for _i in range(40):
		game.advance_day()
		second.advance_day()
	t.truth(game._state.to_dict() == second._state.to_dict(), "precision: two loads of one file continue identically")
	var legacy_slot := "test_precision_json"
	var legacy := FileAccess.open("user://saves/%s.json" % legacy_slot, FileAccess.WRITE)
	legacy.store_string(JSON.stringify({"version": SaveStore.SAVE_FORMAT_VERSION, "state": game._state.to_dict()}))
	legacy.close()
	t.truth(second.load(legacy_slot).get("ok", false), "precision: an old JSON-format save still loads")
	DirAccess.remove_absolute("user://saves/%s.json" % legacy_slot)
	game.free()
	second.free()
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute("user://saves/%s.json%s" % [slot, suffix])


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_growth_wears_down_the_debt_ratio(t)
	_test_a_shrinking_economy_does_not_write_off_debt(t)
	_test_a_law_growth_effect_lasts(t)
	_test_inflation_reads_this_months_deficit(t)
	_test_unknown_envelopes_cannot_inflate_spending(t)
	_test_an_emergency_keeps_escalating_across_january(t)
	_test_a_ministry_seeded_before_the_budget_gets_a_real_baseline(t)
	_test_trade_decays_once_a_pact_is_gone(t)
	_test_sanctions_keep_trade_at_zero(t)
	_test_appointments_cost_capital_and_are_rationed(t)
	_test_validator_checks_every_shortlist_candidate(t)
	_test_an_event_growth_shock_fades(t)
	_test_emergency_escalation_is_capped(t)
	_test_save_floats_keep_full_precision(t)
	quit(t.finish())
