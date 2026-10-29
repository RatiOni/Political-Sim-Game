extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")


static func _state(role: String = "government") -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	state.player.political_capital = 500.0
	state.turn = 10
	return state


static func _economy(state: GameState, deficit: float, inflation: float) -> void:
	var econ := state.country.economy
	econ.budget.expenditure = econ.budget.revenue + econ.gdp * deficit
	econ.inflation = inflation


static func _enact_bank_act(state: GameState) -> void:
	var law := Law.new()
	law.id = OrientationSim.BANK_ACT
	state.enacted_laws.append(law)


func _test_reviews_fall_due_each_quarter(t) -> void:
	var state := _state()
	state.month = 5
	t.truth(not OrientationSim.isf_review_due(state), "there is no review in May")
	state.month = 4
	t.truth(OrientationSim.isf_review_due(state), "the quarter's review falls due in April")
	state.foreign.isf["reviews_held"] = OrientationSim.ISF_REVIEWS
	t.truth(not OrientationSim.isf_review_due(state), "the programme ends after its last review")


func _test_a_pass_releases_the_tranche(t) -> void:
	var state := _state()
	state.month = 4
	_economy(state, 0.01, 0.03)
	var notes := OrientationSim.monthly(state)
	t.equal(int(state.foreign.isf["passed"]), 1, "a disciplined quarter passes")
	t.truth(float(state.foreign.isf["disbursed"]) > 0.0, "the tranche is released and held as ISF debt")
	t.truth(state.modifiers.any(func(m: Modifier) -> bool: return m.target == "budget_revenue" and m.magnitude > 0.0 and m.id.begins_with("isf_tranche")), "the money arrives in the budget")
	t.truth(state.modifiers.any(func(m: Modifier) -> bool: return m.target == "gdp_growth" and m.magnitude > 0.0 and m.id.begins_with("isf_confidence")), "and investors take heart")
	t.truth(notes.any(func(n: String) -> bool: return n.contains("signs off")), "the month reports the sign-off")


func _test_a_fail_suspends_the_programme(t) -> void:
	var state := _state()
	state.month = 7
	_economy(state, 0.10, 0.03)
	OrientationSim.monthly(state)
	t.equal(int(state.foreign.isf["failed"]), 1, "a loose quarter fails")
	t.truth(bool(state.foreign.isf["suspended"]), "and the programme is suspended")
	t.near(float(state.foreign.isf["disbursed"]), 0.0, 1e-9, "no tranche is released")
	t.truth(state.modifiers.any(func(m: Modifier) -> bool: return m.target == "gdp_growth" and m.magnitude < 0.0 and m.id.begins_with("isf_confidence")), "and confidence takes a knock")


func _test_one_review_per_month(t) -> void:
	var state := _state()
	state.month = 10
	_economy(state, 0.01, 0.03)
	OrientationSim.monthly(state)
	OrientationSim.monthly(state)
	t.equal(int(state.foreign.isf["reviews_held"]), 1, "a month never holds two reviews")


func _test_the_bank_becomes_a_condition(t) -> void:
	var state := _state()
	state.month = 1
	_economy(state, 0.01, 0.03)
	state.foreign.isf["reviews_held"] = OrientationSim.ISF_BANK_DUE_REVIEW
	state.foreign.isf["passed"] = OrientationSim.ISF_BANK_DUE_REVIEW
	t.truth(not OrientationSim.isf_passes(state), "from the fifth review, good numbers are not enough without an independent bank")
	_enact_bank_act(state)
	t.truth(OrientationSim.isf_passes(state), "an independent bank satisfies the Fund")


func _test_renegotiation_trades_capital_for_tighter_terms(t) -> void:
	var state := _state()
	var refused := OrientationActions.act(state, "isf_renegotiate")
	t.truth(not refused.get("ok", true) and String(refused["error"]).contains("not suspended"), "there is nothing to renegotiate while the programme runs")
	t.near(state.player.political_capital, 500.0, 1e-9, "and a refusal costs nothing")
	state.month = 7
	_economy(state, 0.10, 0.03)
	OrientationSim.monthly(state)
	var before := OrientationSim.isf_targets(state)
	var done := OrientationActions.act(state, "isf_renegotiate")
	t.truth(done.get("ok", false), "a suspended programme can be renegotiated")
	t.near(state.player.political_capital, 500.0 - float(OrientationActions.COSTS["isf_renegotiate"]), 1e-9, "for political capital")
	t.truth(not bool(state.foreign.isf["suspended"]), "the suspension lifts")
	t.truth(float(state.foreign.isf["disbursed"]) > 0.0, "the held tranche is released")
	var after := OrientationSim.isf_targets(state)
	t.truth(float(after["deficit"]) < float(before["deficit"]) and float(after["inflation"]) < float(before["inflation"]), "and the next targets are tighter")
	t.equal(int(after["bank_due_review"]), int(before["bank_due_review"]) + OrientationSim.ISF_BANK_DELAY, "while the bank condition is pushed back")


func _test_the_review_is_national_but_the_reply_is_the_governments(t) -> void:
	var state := _state("opposition")
	state.month = 7
	_economy(state, 0.10, 0.03)
	OrientationSim.monthly(state)
	t.equal(int(state.foreign.isf["failed"]), 1, "the Fund reviews the country whoever governs")
	t.equal(OrientationActions.reason_for(state, "isf_renegotiate"), "Foreign policy belongs to the government.", "but only the government may renegotiate")
	t.truth(not OrientationActions.act(state, "annex_the_moon").get("ok", true), "an unknown step is refused")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_reviews_fall_due_each_quarter(t)
	_test_a_pass_releases_the_tranche(t)
	_test_a_fail_suspends_the_programme(t)
	_test_one_review_per_month(t)
	_test_the_bank_becomes_a_condition(t)
	_test_renegotiation_trades_capital_for_tighter_terms(t)
	_test_the_review_is_national_but_the_reply_is_the_governments(t)
	quit(t.finish())
