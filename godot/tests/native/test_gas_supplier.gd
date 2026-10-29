
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


static func _leverage(state: GameState, value: float) -> void:
	state.foreign.powers["krasova"]["leverage"] = value


static func _warmth(state: GameState, value: float) -> void:
	for r in DiplomacySim.pair(state, "krasova"):
		(r as Country.BilateralRelation).score = value


static func _member(state: GameState) -> void:
	state.foreign.reached["union_observer"] = state.turn
	OrientationActions._reach(state, "union_member")


static func _krasova(state: GameState) -> Country:
	return state.world_country("krasova")


func _test_renewal_prices_by_leverage(t) -> void:
	var state := _state()
	var notes: Array[String] = []
	_leverage(state, 0.5)
	state.turn = state.foreign.gas.term_end - 1
	GasSim._renew(state, notes)
	t.equal(state.foreign.gas.price, 50.0, "no renewal a month before the term ends")
	state.turn += 1
	GasSim._renew(state, notes)
	t.near(state.foreign.gas.price, 60.0, 0.000001, "at the term's end the price rises with leverage")
	t.equal(state.foreign.gas.term_end, state.turn + GasSim.TERM_MONTHS, "for a new three-year term")
	t.truth(notes.size() == 1, "and the renewal is reported")


func _test_renewal_respects_the_union_cap_and_the_second_line(t) -> void:
	var state := _state()
	_member(state)
	_leverage(state, 0.9)
	state.foreign.gas.second_line_volume = 2.0
	state.turn = state.foreign.gas.term_end
	GasSim._renew(state, [] as Array[String])
	t.near(state.foreign.gas.price, GasSim.union_cap(state.foreign.gas), 0.000001, "a member renews at the Union cap")
	t.near(state.foreign.gas.contracted_volume, 4.0, 0.000001, "and contracts only what the second line does not carry")


func _test_the_ladder_starts_with_a_demand(t) -> void:
	var state := _state()
	var notes: Array[String] = []
	_leverage(state, 0.6)
	state.foreign.gas.arrears = GasSim.ARREARS_DEMAND - 0.01
	t.equal(GasSim.coerce(state, _krasova(state), notes), "", "arrears just under the line draw no demand")
	state.foreign.gas.arrears = GasSim.ARREARS_DEMAND
	var warmth := GasSim.supplier_warmth(state)
	t.equal(GasSim.coerce(state, _krasova(state), notes), "gas_demand", "arrears at the line draw a demand")
	t.truth(GasSim.supplier_warmth(state) < warmth, "which cools relations")
	t.equal(state.foreign.gas.demands, 1, "and is counted")
	t.equal(GasSim.coerce(state, _krasova(state), notes), "", "nothing more is pressed the same month")
	t.equal(GasSim.coerce(state, state.world_country("solheim"), notes), "", "only the supplier can press for gas")


func _test_a_threat_follows_an_unheeded_demand(t) -> void:
	var state := _state()
	state.month = 1
	var notes: Array[String] = []
	_leverage(state, 0.6)
	state.foreign.gas.arrears = 80.0
	GasSim.coerce(state, _krasova(state), notes)
	state.turn += GasSim.THREAT_AFTER_DEMAND - 1
	t.equal(GasSim.coerce(state, _krasova(state), notes), "", "a threat waits two months after the demand")
	state.turn += 1
	_leverage(state, GasSim.THREAT_LEVERAGE - 0.01)
	t.equal(GasSim.coerce(state, _krasova(state), notes), "", "a supplier without leverage cannot threaten")
	_leverage(state, 0.6)
	t.equal(GasSim.coerce(state, _krasova(state), notes), "gas_threat", "with leverage it names a date")
	var threat := GasSim.valve_threat(state)
	t.equal(int(threat["due"]), state.turn + 1, "the cut is foreshadowed a month ahead")
	t.near(float(threat["share"]), 0.24, 0.000001, "and scales with leverage")
	t.equal(GasSim.coerce(state, _krasova(state), notes), "", "a pending threat is not repeated")


func _test_a_threat_becomes_a_cut_unless_defused(t) -> void:
	var state := _state()
	var notes: Array[String] = []
	state.foreign.gas.arrears = 80.0
	state.foreign.gas.threat = {"turn": state.turn, "due": state.turn + 1, "share": 0.3}
	GasSim._mature_threat(state, notes)
	t.equal(state.foreign.gas.cut, 0.0, "nothing is cut before the named date")
	state.turn += 1
	GasSim._mature_threat(state, notes)
	t.near(state.foreign.gas.cut, 0.3, 0.000001, "on the date the valve turns")
	t.equal(state.foreign.gas.cut_until, state.turn + GasSim.CUT_MONTHS, "for two months")
	t.equal(state.foreign.gas.cuts, 1, "and the cut is counted")
	state.turn = state.foreign.gas.cut_until - 1
	GasSim._restore(state, notes)
	t.near(state.foreign.gas.cut, 0.3, 0.000001, "the cut holds through its second month")
	state.turn += 1
	GasSim._restore(state, notes)
	t.equal(state.foreign.gas.cut, 0.0, "and then the gas returns")
	var paid := _state()
	paid.foreign.gas.arrears = GasSim.ARREARS_DEMAND * GasSim.DEFUSED_SHARE - 0.01
	paid.foreign.gas.threat = {"turn": paid.turn, "due": paid.turn, "share": 0.3}
	GasSim._mature_threat(paid, notes)
	t.equal(paid.foreign.gas.cut, 0.0, "paying the arrears down defuses the threat")
	t.truth(paid.foreign.gas.threat.is_empty(), "and the threat lapses")


func _test_a_cut_is_not_repeated_within_two_years(t) -> void:
	var state := _state()
	state.month = 1
	state.turn = GasSim.CUT_COOLDOWN + GasSim.THREAT_AFTER_DEMAND
	var notes: Array[String] = []
	_leverage(state, 0.6)
	state.foreign.gas.arrears = 80.0
	state.foreign.gas.last_demand_turn = state.turn - GasSim.THREAT_AFTER_DEMAND
	state.foreign.gas.last_cut_turn = state.turn - GasSim.CUT_COOLDOWN + 1
	t.equal(GasSim.coerce(state, _krasova(state), notes), "", "no new threat within two years of a cut")
	state.foreign.gas.last_cut_turn = state.turn - GasSim.CUT_COOLDOWN
	t.equal(GasSim.coerce(state, _krasova(state), notes), "gas_threat", "after two years the valve is mentioned again")


func _test_the_union_shields_its_members_short_of_a_crisis(t) -> void:
	var state := _state()
	state.month = 1
	state.turn = GasSim.CUT_COOLDOWN + GasSim.THREAT_AFTER_DEMAND
	var notes: Array[String] = []
	state.foreign.gas.arrears = 100.0
	state.foreign.gas.cut = 0.3
	state.foreign.gas.cut_until = state.turn + 2
	_member(state)
	t.near(state.foreign.gas.price, 35.0, 0.000001, "membership caps the gas price")
	t.near(state.foreign.gas.arrears, 50.0, 0.000001, "and reschedules half the arrears")
	t.equal(state.foreign.gas.cut, 0.0, "and ends a running cut")
	_leverage(state, 0.9)
	_warmth(state, GasSim.UNION_CRISIS_WARMTH)
	state.foreign.gas.arrears = 100.0
	state.foreign.gas.last_demand_turn = state.turn - GasSim.THREAT_AFTER_DEMAND
	t.equal(GasSim.coerce(state, _krasova(state), notes), "", "a member at the crisis line is not threatened")
	_warmth(state, GasSim.UNION_CRISIS_WARMTH - 0.01)
	t.equal(GasSim.coerce(state, _krasova(state), notes), "gas_threat", "but in a crisis even a member hears of the valve")


func _test_leaving_the_union_costs_its_gas(t) -> void:
	var state := _state()
	_member(state)
	OrientationActions._leave_union(state)
	t.near(state.foreign.gas.price, 50.0 * (1.0 + GasSim.EXIT_PRICE_RISE), 0.000001, "walking out loses the Union price and then some")
	t.equal(state.foreign.gas.term_end, state.turn + GasSim.TERM_MONTHS, "on a fresh term")
	t.truth(StateValidator.validate(state).is_empty(), "and the ledger stays valid")



func _test_the_cut_lands_on_the_named_month(t) -> void:
	var state := _state()
	var notes: Array[String] = []
	state.foreign.gas.arrears = 80.0
	state.foreign.gas.threat = {"turn": state.turn, "due": state.turn + 1, "share": 0.3}
	NativeGameScript.next_month(state)
	t.near(state.foreign.gas.cut, 0.3, 0.000001, "the next calendar month closes with the valve turned")
	t.near(GasSim.national_shortfall(state), 0.3, 0.000001, "and that month's gas is short")
	NativeGameScript.next_month(state)
	t.near(state.foreign.gas.cut, 0.3, 0.000001, "the second month is short too")
	NativeGameScript.next_month(state)
	t.equal(state.foreign.gas.cut, 0.0, "the third is not")


func _test_a_member_cut_ends_when_the_crisis_eases(t) -> void:
	var state := _state()
	var notes: Array[String] = []
	_member(state)
	_warmth(state, GasSim.UNION_CRISIS_WARMTH - 0.1)
	state.foreign.gas.cut = 0.3
	state.foreign.gas.cut_until = state.turn + GasSim.CUT_MONTHS
	GasSim._restore(state, notes)
	t.near(state.foreign.gas.cut, 0.3, 0.000001, "a cut made in a crisis holds while the crisis lasts")
	_warmth(state, GasSim.UNION_CRISIS_WARMTH + 0.1)
	GasSim._restore(state, notes)
	t.equal(state.foreign.gas.cut, 0.0, "and the Union ends it once the crisis eases")


func _test_the_world_ai_keeps_its_ordinary_pressure(t) -> void:
	var state := _state()
	var notes: Array[String] = []
	var krasova := _krasova(state)
	state.foreign.gas.arrears = 80.0
	krasova.plan = {"objective": "undermine", "target": state.country.id, "matures_turn": state.turn}
	t.truth(WorldSim._execute(state, krasova, notes) in ["condemned", "undermined", "shelved"], "a matured undermine plan still presses in the ordinary way")
	t.equal(state.foreign.gas.demands, 0, "and leaves the gas to its own track")


func _test_no_threat_out_of_the_heating_season(t) -> void:
	var state := _state()
	var notes: Array[String] = []
	_leverage(state, 0.6)
	state.foreign.gas.arrears = 80.0
	state.turn = GasSim.THREAT_AFTER_DEMAND
	state.foreign.gas.last_demand_turn = 0
	state.month = 3
	t.equal(GasSim.coerce(state, _krasova(state), notes), "gas_threat", "March is still heating season")
	state.foreign.gas.threat = {}
	state.month = 4
	t.equal(GasSim.coerce(state, _krasova(state), notes), "", "in April the valve is not mentioned")


func _test_demand_harm_is_damped_by_warmth(t) -> void:
	var cold := _state()
	var warm := _state()
	_warmth(warm, 0.6)
	for s in [cold, warm]:
		(s as GameState).foreign.gas.arrears = 80.0
		GasSim.coerce(s, _krasova(s), [] as Array[String])
	var cold_harm := -float(cold.foreign.hostile_log[-1]["relation"])
	var warm_harm := -float(warm.foreign.hostile_log[-1]["relation"])
	t.truth(cold_harm > 0.0, "a demand is recorded as harm")
	t.truth(warm_harm < cold_harm, "and warm relations soften it")


func _test_the_ladder_climbs_on_the_calendar(t) -> void:
	var state := _state()
	state.foreign.gas.arrears = 80.0
	var cut_turn := -1
	var threat_turn := -1
	var demand_turn := -1
	for _m in range(30):
		_leverage(state, 0.6)
		NativeGameScript.next_month(state)
		state.foreign.gas.arrears = maxf(state.foreign.gas.arrears, 80.0)
		if demand_turn < 0 and state.foreign.gas.demands > 0:
			demand_turn = state.turn
		if threat_turn < 0 and state.foreign.gas.threats > 0:
			threat_turn = state.turn
		if cut_turn < 0 and state.foreign.gas.cuts > 0:
			cut_turn = state.turn
	t.truth(demand_turn > 0, "the supplier demands its arrears on its own clock")
	t.truth(threat_turn >= demand_turn + GasSim.THREAT_AFTER_DEMAND, "and threatens only after the demand goes unmet")
	t.equal(cut_turn, threat_turn + 1, "and the cut lands exactly one month after the threat")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_renewal_prices_by_leverage(t)
	_test_renewal_respects_the_union_cap_and_the_second_line(t)
	_test_the_ladder_starts_with_a_demand(t)
	_test_a_threat_follows_an_unheeded_demand(t)
	_test_a_threat_becomes_a_cut_unless_defused(t)
	_test_a_cut_is_not_repeated_within_two_years(t)
	_test_the_union_shields_its_members_short_of_a_crisis(t)
	_test_leaving_the_union_costs_its_gas(t)
	_test_the_world_ai_keeps_its_ordinary_pressure(t)
	_test_no_threat_out_of_the_heating_season(t)
	_test_demand_harm_is_damped_by_warmth(t)
	_test_the_ladder_climbs_on_the_calendar(t)
	_test_the_cut_lands_on_the_named_month(t)
	_test_a_member_cut_ends_when_the_crisis_eases(t)
	quit(t.finish())
