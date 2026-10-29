extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")


static func _state() -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	return state


static func _flow(state: GameState, month: int) -> Dictionary:
	state.month = month
	GasSim.flow(state)
	return state.foreign.gas.last_flow


func _test_a_full_contract_meets_winter_demand(t) -> void:
	var state := _state()
	var arrears := state.foreign.gas.arrears
	var f := _flow(state, 1)
	t.near(float(f["demand"]), 0.75, 0.000001, "January demand is a winter month's share of the year")
	t.near(float(f["shortfall"]), 0.0, 0.000001, "a full contract leaves no shortfall")
	t.near(float(f["bill"]), 37.5, 0.000001, "the bill is the price of what was taken")
	t.near(state.foreign.gas.arrears - arrears, 37.5 * (1.0 - GasSim.PAYMENT_SHARE), 0.000001, "the unpaid share becomes arrears")
	t.equal(state.foreign.gas.paid.size(), GasContract.PAID_MONTHS, "the payment history keeps one year")


func _test_season_boundaries(t) -> void:
	var state := _state()
	t.near(float(_flow(state, 3)["demand"]), 0.75, 0.000001, "March is heated")
	t.near(float(_flow(state, 4)["demand"]), 0.25, 0.000001, "April is not")
	t.near(float(_flow(state, 9)["demand"]), 0.25, 0.000001, "September is not")
	t.near(float(_flow(state, 10)["demand"]), 0.75, 0.000001, "October is")


func _test_a_cut_is_buffered_by_storage(t) -> void:
	var state := _state()
	state.foreign.gas.cut = 0.4
	state.foreign.gas.cut_until = state.turn + 12
	t.near(float(_flow(state, 1)["shortfall"]), 0.4, 0.000001, "a 40% cut in January leaves 40% short")
	t.near(float(state.foreign.gas.last_flow["severity"]), 0.4, 0.000001, "at full winter severity")
	t.near(float(_flow(state, 7)["severity"]), 0.4 / 3.0, 0.000001, "the same cut in July is a third as severe")
	state.foreign.gas.storage_target = 1.0
	state.foreign.gas.storage_capacity = 1.0
	state.foreign.gas.storage = 0.2
	var f := _flow(state, 1)
	t.near(float(f["drawn"]), 0.2, 0.000001, "storage is drawn to cover the gap")
	t.near(float(f["shortfall"]), 0.1 / 0.75, 0.000001, "and only the rest is short")
	t.near(state.foreign.gas.storage, 0.0, 0.000001, "what was drawn leaves storage")


func _test_sabotage_cuts_delivered_supply(t) -> void:
	var state := _state()
	state.foreign.gas.sabotage = 0.5
	t.near(float(_flow(state, 1)["shortfall"]), 0.5, 0.000001, "sabotage on the line takes its share of supply")


func _test_summer_fills_storage(t) -> void:
	var state := _state()
	state.foreign.gas.storage_target = 1.0
	state.foreign.gas.storage_capacity = 1.0
	var f := _flow(state, 6)
	t.near(float(f["injected"]), GasSim.INJECTION_SHARE, 0.000001, "a summer month injects a quarter of capacity")
	t.near(state.foreign.gas.storage, GasSim.INJECTION_SHARE, 0.000001, "into storage")
	t.near(float(_flow(state, 1)["injected"]), 0.0, 0.000001, "a winter month injects nothing")


func _test_take_or_pay_bills_gas_not_taken(t) -> void:
	var state := _state()
	state.foreign.gas.second_line_volume = 6.0
	var f := _flow(state, 6)
	t.near(float(f["shortfall"]), 0.0, 0.000001, "the second line covers summer demand")
	t.near(float(f["bill"]), 50.0 * 0.8 * 0.25, 0.000001, "but Krasova still bills 80% of what it offered")


func _test_the_gas_bill_is_a_real_budget_line(t) -> void:
	var state := _state()
	var econ := state.country.economy
	EconomySim._update_budget_lines(state)
	var with_gas := econ.budget.expenditure
	state.foreign.gas.paid.clear()
	EconomySim._update_budget_lines(state)
	t.near(with_gas - econ.budget.expenditure, 50.0 * 6.0 * GasSim.PAYMENT_SHARE, 0.001, "a year of paid gas sits in expenditure")


func _test_a_shortfall_is_reported(t) -> void:
	var state := _state()
	state.month = 1
	state.foreign.gas.cut = 0.5
	state.foreign.gas.cut_until = state.turn + 12
	var notes := GasSim.monthly(state)
	t.truth(notes.any(func(n: String) -> bool: return n.contains("short")), "a real shortfall reaches the monthly report")
	state.foreign.gas.cut = GasSim.SHORTFALL_NOTE * 0.5
	notes = GasSim.monthly(state)
	t.truth(not notes.any(func(n: String) -> bool: return n.contains("short")), "a trace shortfall does not")


func _test_the_calendar_drives_the_season(t) -> void:
	var state := _state()
	NativeGameScript.next_month(state)
	t.equal(state.month, 4, "the first month closed is April")
	t.near(float(state.foreign.gas.last_flow["demand"]), 0.25, 0.000001, "and burns summer gas")
	while state.month != 10:
		NativeGameScript.next_month(state)
	t.near(float(state.foreign.gas.last_flow["demand"]), 0.75, 0.000001, "October's close burns winter gas")


func _test_dependence_reads_the_contract_in_the_month(t) -> void:
	var state := _state()
	var before := ForeignSim.dependence(state, "krasova")
	state.foreign.gas.second_line_volume = 6.0
	NativeGameScript.next_month(state)
	t.near(float(state.foreign.gas_share["krasova"]), 0.5, 0.000001, "the month writes Krasova's real share")
	t.near(float(state.foreign.powers["krasova"]["dependence"]), ForeignSim.dependence(state, "krasova"), 0.000001, "before the spine is read")
	t.truth(before - float(state.foreign.powers["krasova"]["dependence"]) > 0.2, "so dependence on Krasova falls")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_a_full_contract_meets_winter_demand(t)
	_test_season_boundaries(t)
	_test_a_cut_is_buffered_by_storage(t)
	_test_sabotage_cuts_delivered_supply(t)
	_test_summer_fills_storage(t)
	_test_take_or_pay_bills_gas_not_taken(t)
	_test_the_gas_bill_is_a_real_budget_line(t)
	_test_a_shortfall_is_reported(t)
	_test_the_calendar_drives_the_season(t)
	_test_dependence_reads_the_contract_in_the_month(t)
	quit(t.finish())
