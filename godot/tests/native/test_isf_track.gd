extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")


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


func _test_the_tranche_lasts_its_months_and_delivers_its_cash(t) -> void:
	var state := _state()
	state.month = 4
	_economy(state, 0.01, 0.03)
	OrientationSim.monthly(state)
	var tranche: Modifier = state.modifiers.filter(func(m: Modifier) -> bool: return m.id.begins_with("isf_tranche"))[0]
	t.equal(tranche.onset_delay + tranche.ramp_duration + tranche.hold_duration + tranche.decay_duration, OrientationSim.ISF_TRANCHE_MONTHS, "the tranche runs for its stated months")
	var cash := 0.0
	for _i in range(OrientationSim.ISF_TRANCHE_MONTHS + 25):
		cash += tranche.current_value()
		tranche.age += 1
	t.near(cash, float(state.foreign.isf["disbursed"]), 1e-6, "and delivers exactly the sum the ISF holds as debt")


func _test_reviews_fire_on_the_real_calendar(t) -> void:
	var state := _state()
	var fired: Array[int] = []
	var last := int(state.foreign.isf["reviews_held"])
	for _i in range(24):
		NativeGameScript.next_month(state)
		var now := int(state.foreign.isf["reviews_held"])
		if now != last:
			fired.append(state.month)
			last = now
	t.equal(fired.size(), 8, "two years hold eight reviews")
	t.truth(fired.all(func(m: int) -> bool: return m in [1, 4, 7, 10]), "and each falls in January, April, July or October")
	t.equal(fired.filter(func(m: int) -> bool: return m == 1).size(), 2, "twice in January")


func _test_the_pass_boundary_is_inclusive(t) -> void:
	var state := _state()
	var econ := state.country.economy
	econ.gdp = 1000.0
	econ.budget.revenue = 0.0
	econ.budget.expenditure = 1000.0 * OrientationSim.ISF_DEFICIT_TARGET
	econ.inflation = 0.03
	t.truth(OrientationSim.isf_passes(state), "a deficit exactly at target passes")
	econ.budget.expenditure = 1000.0 * OrientationSim.ISF_DEFICIT_TARGET + 0.01
	t.truth(not OrientationSim.isf_passes(state), "a deficit just above target fails")
	econ.budget.expenditure = 0.0
	econ.inflation = OrientationSim.ISF_INFLATION_TARGET
	t.truth(OrientationSim.isf_passes(state), "inflation exactly at target passes")
	econ.inflation = OrientationSim.ISF_INFLATION_TARGET + 0.0001
	t.truth(not OrientationSim.isf_passes(state), "inflation just above target fails")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_reviews_fall_due_each_quarter(t)
	_test_a_pass_releases_the_tranche(t)
	_test_a_fail_suspends_the_programme(t)
	_test_one_review_per_month(t)
	_test_the_bank_becomes_a_condition(t)
	_test_renegotiation_trades_capital_for_tighter_terms(t)
	_test_the_review_is_national_but_the_reply_is_the_governments(t)
	_test_the_tranche_lasts_its_months_and_delivers_its_cash(t)
	_test_reviews_fire_on_the_real_calendar(t)
	_test_the_pass_boundary_is_inclusive(t)
	quit(t.finish())
