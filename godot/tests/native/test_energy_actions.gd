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
	return state


static func _warmth(state: GameState) -> float:
	return GasSim.supplier_warmth(state)


func _test_energy_belongs_to_the_government(t) -> void:
	var state := _state("opposition")
	for verb in EnergyActions.VERBS:
		t.truth(EnergyActions.reason_for(state, verb).contains("belongs to the government"), "%s is refused in opposition" % verb)


func _test_paying_the_arrears(t) -> void:
	var state := _state()
	var debt := state.country.economy.public_debt_pct
	var warmth := _warmth(state)
	t.truth(EnergyActions.act(state, "gas_pay_arrears").get("ok", false), "the arrears can be paid")
	t.equal(state.foreign.gas.arrears, 0.0, "all forty are cleared")
	t.near(state.country.economy.public_debt_pct - debt, 40.0 / state.country.economy.gdp, 0.0000001, "with borrowed hard currency")
	t.truth(_warmth(state) >= warmth, "Krasova does not mind being paid")
	t.truth(EnergyActions.reason_for(state, "gas_pay_arrears").contains("no gas arrears"), "nothing left to pay is refused")
	state.foreign.gas.arrears = 120.0
	EnergyActions.act(state, "gas_pay_arrears")
	t.near(state.foreign.gas.arrears, 70.0, 0.000001, "a large debt is paid one tranche at a time")


func _test_a_spot_cargo_covers_a_cut(t) -> void:
	var state := _state()
	var debt := state.country.economy.public_debt_pct
	t.truth(EnergyActions.act(state, "gas_spot_purchase").get("ok", false), "a spot cargo can be bought")
	t.near(state.country.economy.public_debt_pct - debt, 0.5 * 50.0 * EnergyActions.SPOT_PREMIUM / state.country.economy.gdp, 0.0000001, "at a premium")
	t.truth(EnergyActions.reason_for(state, "gas_spot_purchase") != "", "and only one can be on its way")
	state.month = 1
	state.foreign.gas.cut = 0.5
	state.foreign.gas.cut_until = state.turn + 12
	GasSim.flow(state)
	t.near(GasSim.national_shortfall(state), 0.0, 0.000001, "the cargo fills a January cut")
	t.equal(state.foreign.gas.spot_pending, 0.0, "and is used up")


func _test_storage_is_built_over_two_years(t) -> void:
	var state := _state()
	t.truth(EnergyActions.act(state, "gas_storage").get("ok", false), "storage can be commissioned")
	t.truth(state.modifiers.any(func(m: Modifier) -> bool: return m.source_id == "gas_storage" and m.target == "budget_expenditure"), "and is paid for from the budget")
	t.truth(EnergyActions.reason_for(state, "gas_storage") != "", "once")
	for _i in range(GasSim.STORAGE_MONTHS / 2):
		NativeGameScript.next_month(state)
	t.near(state.foreign.gas.storage_capacity, 0.5, 0.000001, "half is built after a year")
	for _i in range(GasSim.STORAGE_MONTHS / 2 - 1):
		NativeGameScript.next_month(state)
	t.truth(state.foreign.gas.storage_capacity < 1.0, "not all of it a month early")
	NativeGameScript.next_month(state)
	t.near(state.foreign.gas.storage_capacity, 1.0, 0.000001, "all of it after two years")


func _test_the_second_line_takes_four_years_and_angers_krasova(t) -> void:
	var state := _state()
	var warmth := _warmth(state)
	t.truth(EnergyActions.act(state, "gas_second_line").get("ok", false), "the second line can be started")
	t.near(warmth - _warmth(state), -EnergyActions.SECOND_LINE_HOSTILITY, 0.000001, "Krasova takes it as hostile")
	for _i in range(GasSim.SECOND_LINE_MONTHS - 1):
		NativeGameScript.next_month(state)
	t.equal(state.foreign.gas.second_line_volume, 0.0, "nothing flows a month early")
	NativeGameScript.next_month(state)
	t.near(state.foreign.gas.second_line_volume, 2.0, 0.000001, "after four years the line opens")
	t.truth(float(state.foreign.gas_share["krasova"]) < 1.0, "and Krasova's share of Ardenia's gas falls")


func _test_renegotiation_trades_price_for_concessions(t) -> void:
	var state := _state()
	var revenue_before := state.modifiers.size()
	t.truth(EnergyActions.act(state, "gas_renegotiate_transit").get("ok", false), "transit fees can be conceded")
	t.near(state.foreign.gas.price, 45.0, 0.000001, "for a lower price")
	t.truth(state.modifiers.size() == revenue_before + 1 and state.modifiers.any(func(m: Modifier) -> bool: return m.source_id == "gas_transit_concession" and m.target == "budget_revenue" and m.magnitude < 0.0), "at the cost of the transit revenue")
	state.turn += EnergyActions.RENEGOTIATE_COOLDOWN - 1
	t.truth(EnergyActions.reason_for(state, "gas_renegotiate_union").contains("will not reopen"), "the contract cannot be reopened within the year")
	state.turn += 1
	t.truth(EnergyActions.reason_for(state, "gas_renegotiate_transit").contains("already been conceded"), "and transit fees can be conceded once")
	var capital := state.player.political_capital
	t.truth(EnergyActions.act(state, "gas_renegotiate_union").get("ok", false), "after a year a Union step can be traded")
	t.truth(state.foreign.reached.has("union_observer"), "Ardenia takes observer status")
	t.near(state.foreign.gas.price, 45.0 * 0.85, 0.000001, "for a further discount")
	t.near(capital - state.player.political_capital, 20.0, 0.000001, "paying for the step and the talks")


func _test_shelving_the_second_line(t) -> void:
	var state := _state()
	t.truth(EnergyActions.reason_for(state, "gas_renegotiate_policy").contains("no second line"), "there is nothing to shelve yet")
	EnergyActions.act(state, "gas_second_line")
	var warmth := _warmth(state)
	t.truth(EnergyActions.act(state, "gas_renegotiate_policy").get("ok", false), "a line under construction can be shelved")
	t.equal(state.foreign.gas.second_line_started, -1, "the project stops")
	t.truth(not state.modifiers.any(func(m: Modifier) -> bool: return m.source_id == "gas_second_line"), "and so do its costs")
	t.truth(_warmth(state) > warmth, "Krasova is pleased")
	t.near(state.foreign.gas.price, 45.0, 0.000001, "and cuts the price")


func _test_renegotiation_needs_tolerable_relations_and_a_floor(t) -> void:
	var state := _state()
	for r in DiplomacySim.pair(state, "krasova"):
		(r as Country.BilateralRelation).score = EnergyActions.RENEGOTIATE_WARMTH - 0.01
	t.truth(EnergyActions.reason_for(state, "gas_renegotiate_transit").contains("too cold"), "a hostile supplier will not talk")
	for r in DiplomacySim.pair(state, "krasova"):
		(r as Country.BilateralRelation).score = EnergyActions.RENEGOTIATE_WARMTH
	t.equal(EnergyActions.reason_for(state, "gas_renegotiate_transit"), "", "at the line it will")
	state.foreign.gas.price = 26.0
	EnergyActions.act(state, "gas_renegotiate_transit")
	t.near(state.foreign.gas.price, 25.0, 0.000001, "and never sells below half the reference")


func _test_a_refused_operation_changes_nothing(t) -> void:
	var state := _state()
	state.player.political_capital = 4.0
	var before := state.foreign.gas.to_dict()
	var result := EnergyActions.act(state, "gas_spot_purchase")
	t.truth(not result.get("ok", true) and String(result["error"]).contains("political capital"), "too little capital is refused")
	t.equal(state.foreign.gas.to_dict(), before, "and changes nothing")
	t.equal(state.player.political_capital, 4.0, "and costs nothing")
	state.player.political_capital = 5.0
	t.equal(EnergyActions.reason_for(state, "gas_spot_purchase"), "", "exactly the price is enough")
	state.player.political_capital = 15.0
	t.truth(EnergyActions.reason_for(state, "gas_renegotiate_union").contains("political capital"), "a Union step needs capital for the talks and the step")


func _test_the_game_runs_energy_operations(t) -> void:
	var game: Node = NativeGameScript.new()
	game._state = _state()
	var result: Dictionary = game.energy_act("gas_pay_arrears")
	t.truth(result.get("ok", false) and result.has("snapshot"), "an operation runs through the game and returns a snapshot")
	t.truth(not game.energy_act("gas_pay_arrears").get("ok", true), "and refusals come back")
	game.free()


func _test_an_ai_government_pays_down_a_threat(t) -> void:
	var state := _state("opposition")
	state.foreign.gas.arrears = 70.0
	state.foreign.gas.threat = {"turn": state.turn, "due": state.turn + 1, "share": 0.3}
	OppositionSim.monthly(state)
	t.truth(state.foreign.gas.arrears < GasSim.ARREARS_DEMAND * GasSim.DEFUSED_SHARE, "the ruling party pays the arrears below thirty")
	state.turn += 1
	GasSim.monthly(state)
	t.equal(state.foreign.gas.cut, 0.0, "and the threat lapses")
	var quiet := _state("opposition")
	EnergyActions.ai_policy(quiet)
	t.near(quiet.foreign.gas.arrears, 40.0, 0.000001, "nothing is paid without a demand or a threat")
	quiet.foreign.gas.last_demand_turn = quiet.turn
	EnergyActions.ai_policy(quiet)
	t.equal(quiet.foreign.gas.arrears, 0.0, "a live demand is enough")


func _test_an_ai_government_keeps_to_its_energy_budget(t) -> void:
	var state := _state("opposition")
	var g := state.foreign.gas
	g.arrears = 500.0
	g.threat = {"turn": state.turn, "due": state.turn + 1, "share": 0.3}
	g.cut = 0.5
	g.cut_until = state.turn + 3
	state.month = 9
	var debt := state.country.economy.public_debt_pct
	var capital := state.player.political_capital
	EnergyActions.ai_policy(state)
	t.truth((state.country.economy.public_debt_pct - debt) * state.country.economy.gdp <= EnergyActions.AI_MONTHLY_BUDGET + 0.000001, "it never spends more than its monthly energy budget")
	t.equal(g.spot_pending, 0.0, "so the cargo it cannot afford is not bought")
	t.equal(state.player.political_capital, capital, "and the player's capital is untouched")
	g.arrears = 0.0
	g.threat = {}
	state.month = 4
	EnergyActions.ai_policy(state)
	t.equal(g.spot_pending, 0.0, "no cargo is bought for the summer")
	state.month = 9
	EnergyActions.ai_policy(state)
	t.near(g.spot_pending, EnergyActions.SPOT_VOLUME, 0.000001, "but one is bought before the heating season")
	var held := state.country.economy.public_debt_pct
	EnergyActions.ai_policy(state)
	t.equal(state.country.economy.public_debt_pct, held, "and a second is not bought while one is on its way")
	g.spot_pending = 0.0
	g.price = EnergyActions.AI_MONTHLY_BUDGET / (EnergyActions.SPOT_VOLUME * EnergyActions.SPOT_PREMIUM) + 0.01
	EnergyActions.ai_policy(state)
	t.equal(g.spot_pending, 0.0, "unless it costs more than the budget")
	g.cut = 0.0
	g.price = 50.0
	EnergyActions.ai_policy(state)
	t.equal(g.spot_pending, 0.0, "and none without a cut")
	t.equal(g.second_line_started, -1, "and it never starts the second line")


func _test_the_player_in_government_is_never_auto_paid(t) -> void:
	var state := _state()
	state.foreign.gas.arrears = 70.0
	state.foreign.gas.threat = {"turn": state.turn, "due": state.turn + 1, "share": 0.3}
	var before := state.foreign.gas.to_dict()
	OppositionSim.monthly(state)
	EnergyActions.ai_policy(state)
	t.equal(state.foreign.gas.to_dict(), before, "a player government pays its own bills")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_energy_belongs_to_the_government(t)
	_test_paying_the_arrears(t)
	_test_a_spot_cargo_covers_a_cut(t)
	_test_storage_is_built_over_two_years(t)
	_test_the_second_line_takes_four_years_and_angers_krasova(t)
	_test_renegotiation_trades_price_for_concessions(t)
	_test_shelving_the_second_line(t)
	_test_renegotiation_needs_tolerable_relations_and_a_floor(t)
	_test_a_refused_operation_changes_nothing(t)
	_test_the_game_runs_energy_operations(t)
	_test_an_ai_government_pays_down_a_threat(t)
	_test_an_ai_government_keeps_to_its_energy_budget(t)
	_test_the_player_in_government_is_never_auto_paid(t)
	quit(t.finish())
