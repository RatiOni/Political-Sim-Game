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


static func _trade(state: GameState, id: String) -> float:
	return (state.country.relations[id] as Country.BilateralRelation).trade_volume


static func _score(state: GameState, id: String) -> float:
	return (state.country.relations[id] as Country.BilateralRelation).score


func _test_gas_is_the_heaviest_dependence(t) -> void:
	var state := _state()
	state.foreign.gas_share["krasova"] = 1.0
	var with_gas := ForeignSim.dependence(state, "krasova")
	state.foreign.gas_share["krasova"] = 0.0
	t.near(with_gas - ForeignSim.dependence(state, "krasova"), 0.5, 1e-9, "the gas contract alone is half of Krasova's hold")


func _test_debt_held_abroad_is_dependence(t) -> void:
	var state := _state()
	var econ := state.country.economy
	econ.loans.clear()
	t.near(ForeignSim.debt_share(state, "krasova"), 0.0, 1e-9, "no Krasovan loans, no debt hold")
	var debt := econ.public_debt_pct * econ.gdp
	econ.loans.append({"id": "l1", "lender_id": "krasova", "principal": debt * 0.2, "rate": 0.03, "months_left": 12})
	t.near(ForeignSim.debt_share(state, "krasova"), 0.2, 1e-6, "a loan for a fifth of the debt is a fifth of the hold")
	state.foreign.isf["disbursed"] = debt * 0.1
	t.near(ForeignSim.debt_share(state, "isf"), 0.1, 1e-6, "ISF disbursements are debt the Fund holds")


func _test_trade_share_is_dependence(t) -> void:
	var state := _state()
	var total := 0.0
	for key in state.country.relations:
		total += _trade(state, String(key))
	t.near(ForeignSim.export_share(state, "krasova"), _trade(state, "krasova") / total, 1e-9, "Krasova's hold includes its share of trade")
	var concert := 0.0
	for id in state.foreign.members["concert"]:
		concert += _trade(state, String(id))
	t.near(ForeignSim.export_share(state, "concert"), concert / total, 1e-9, "a bloc's share is the trade with all its members")


func _test_commitment_is_what_has_been_signed(t) -> void:
	var state := _state()
	t.near(ForeignSim.commitment(state, "isf"), 0.4, 1e-9, "the standing ISF programme is a real commitment")
	t.near(ForeignSim.commitment(state, "union"), 0.0, 1e-9, "no Union step, no Union commitment")
	t.near(ForeignSim.commitment(state, "krasova"), 0.0, 1e-9, "and nothing signed with Krasova")
	DiplomacyActions.trade_agreement(state, DiplomacySim.world_country(state, "krasova"), "")
	t.near(ForeignSim.commitment(state, "krasova"), 0.15, 1e-9, "a trade pact commits a little")
	state.foreign.reached["union_observer"] = 0
	t.near(ForeignSim.commitment(state, "union"), 0.3, 1e-9, "observer status commits more")
	state.foreign.reached["union_member"] = 0
	t.near(ForeignSim.commitment(state, "union"), 0.8, 1e-9, "membership commits a great deal")
	t.near(ForeignSim.commitment(state, "krasova"), 0.55, 1e-9, "and binds Ardenia to the Union's anchor")


func _test_winter_sharpens_the_gas_lever(t) -> void:
	var state := _state()
	state.month = 7
	var summer := ForeignSim.leverage(state, "krasova")
	state.month = 1
	var winter := ForeignSim.leverage(state, "krasova")
	t.truth(winter > summer, "Krasova's leverage is greater in the heating season (%.3f > %.3f)" % [winter, summer])
	state.foreign.gas_share["krasova"] = 0.0
	var no_gas_winter := ForeignSim.leverage(state, "krasova")
	state.month = 7
	t.near(no_gas_winter, ForeignSim.leverage(state, "krasova"), 1e-9, "without gas the season does not matter")


func _test_warmth_blunts_leverage(t) -> void:
	var state := _state()
	var krasova := DiplomacySim.world_country(state, "krasova")
	DiplomacySim.shift_between(state.country, krasova, -0.5)
	var cold := ForeignSim.leverage(state, "krasova")
	DiplomacySim.shift_between(state.country, krasova, 0.8)
	t.truth(ForeignSim.leverage(state, "krasova") < cold, "a warmer relationship makes the same dependence less coercive")


func _test_leverage_is_bounded_at_the_extremes(t) -> void:
	var state := _state()
	state.month = 1
	var econ := state.country.economy
	econ.loans.append({"id": "all", "lender_id": "krasova", "principal": econ.public_debt_pct * econ.gdp * 5.0, "rate": 0.03, "months_left": 12})
	for key in state.country.relations:
		DiplomacySim.set_trade(state, String(key), 0.0)
	DiplomacySim.set_trade(state, "krasova", DiplomacySim.TRADE_CEILING)
	DiplomacySim.shift_between(state.country, DiplomacySim.world_country(state, "krasova"), -2.0)
	for id in ForeignSim.power_ids():
		var lev := ForeignSim.leverage(state, id)
		t.truth(is_finite(lev) and lev >= 0.0 and lev <= 1.0, "%s leverage stays within 0..1 at the extremes (%.3f)" % [id, lev])
	t.near(ForeignSim.leverage(state, "krasova"), 1.0, 1e-9, "total dependence on a hostile supplier in winter is total leverage")


func _test_the_month_records_every_power(t) -> void:
	var state := _state()
	state.foreign.powers.clear()
	NativeGameScript.next_month(state)
	for id in ForeignSim.power_ids():
		t.truth(state.foreign.powers.has(id), "%s is on the monthly ledger" % id)
	t.equal(StateValidator.validate(state).size(), 0, "and the month leaves a valid state")
	var unseeded := _state()
	unseeded.foreign = ForeignState.new()
	NativeGameScript.next_month(unseeded)
	t.truth(unseeded.foreign.seeded, "a campaign without a ledger is seeded by its first month")


func _test_leverage_sharpens_krasovan_pressure(t) -> void:
	var deltas: Array[float] = []
	for lev in [0.0, 1.0]:
		var state := _state()
		for key in state.country.relations:
			(state.country.relations[key] as Country.BilateralRelation).treaties.clear()
		var krasova := DiplomacySim.world_country(state, "krasova")
		state.foreign.powers["krasova"] = {"dependence": 1.0, "commitment": 0.0, "leverage": lev}
		var before := _score(state, "krasova")
		var notes: Array[String] = []
		WorldSim.hostile_action(state, krasova, state.country, notes)
		deltas.append(_score(state, "krasova") - before)
	t.truth(deltas[1] < deltas[0], "a supplier with leverage presses harder (%.3f vs %.3f)" % [deltas[1], deltas[0]])


func _test_a_meridian_guarantee_shields_like_a_pact(t) -> void:
	var state := _state()
	for key in state.country.relations:
		(state.country.relations[key] as Country.BilateralRelation).treaties.clear()
	var krasova := DiplomacySim.world_country(state, "krasova")
	t.truth(not WorldSim._shielded_from(state, krasova), "without pacts or a guarantee Ardenia stands alone")
	state.foreign.reached["meridian_guarantee"] = 0
	t.truth(WorldSim._shielded_from(state, krasova), "a Meridian guarantee deters like a defence pact")



static func _isolated(seed: int) -> GameState:
	var state := _state()
	for key in state.country.relations:
		(state.country.relations[key] as Country.BilateralRelation).treaties.clear()
	state.foreign.powers["krasova"] = {"dependence": 0.8, "commitment": 0.0, "leverage": 0.5}
	state.rng = SimRng.from_seed(seed)
	return state


static func _harm_at(score: float) -> float:
	var state := _isolated(777)
	var krasova := DiplomacySim.world_country(state, "krasova")
	var harm := 0.0
	for _i in range(20):
		DiplomacySim.shift_between(state.country, krasova, score - _score(state, "krasova"))
		WorldSim.hostile_action(state, krasova, state.country, [])
		var entry: Dictionary = state.foreign.hostile_log[-1]
		harm -= float(entry["relation"]) + float(entry["economy"]) + float(entry["stability"])
	return harm


func _test_warmth_never_raises_coercion(t) -> void:
	var previous_harm := INF
	var previous_frequency := INF
	var monotone_harm := true
	var monotone_frequency := true
	var score := WorldSim.SPENT_RIVALRY
	while score <= 1.0 + 1e-9:
		var harm := _harm_at(score)
		var frequency := 1.0 / float(WorldSim.press_interval(score))
		monotone_harm = monotone_harm and harm <= previous_harm + 1e-9
		monotone_frequency = monotone_frequency and frequency <= previous_frequency + 1e-9
		previous_harm = harm
		previous_frequency = frequency
		score += 0.1
	t.truth(monotone_harm, "harm per move never rises as relations warm")
	t.truth(monotone_frequency, "pressure never comes more often as relations warm")
	t.truth(_harm_at(0.5) < _harm_at(-0.7), "a warm relationship is coerced less than a feud (%.3f < %.3f)" % [_harm_at(0.5), _harm_at(-0.7)])


func _test_a_landed_move_logs_its_real_effect(t) -> void:
	var state := _isolated(5)
	var krasova := DiplomacySim.world_country(state, "krasova")
	var before := _score(state, "krasova")
	WorldSim.hostile_action(state, krasova, state.country, [])
	t.equal(state.foreign.hostile_log.size(), 1, "a landed move is logged")
	var entry: Dictionary = state.foreign.hostile_log[0]
	t.equal(String(entry["actor"]), "krasova", "under its actor")
	t.near(float(entry["relation"]), _score(state, "krasova") - before, 1e-9, "with the relation change actually applied")
	t.truth(entry.has("economy") and entry.has("stability"), "and its economic and stability effect")


func _test_the_hostile_log_is_bounded_valid_and_saved(t) -> void:
	var state := _isolated(9)
	var krasova := DiplomacySim.world_country(state, "krasova")
	for _i in range(WorldSim.HOSTILE_LOG_LIMIT + 6):
		DiplomacySim.shift_between(state.country, krasova, 0.5)
		WorldSim.hostile_action(state, krasova, state.country, [])
	t.equal(state.foreign.hostile_log.size(), WorldSim.HOSTILE_LOG_LIMIT, "the log keeps only its most recent moves")
	t.equal(StateValidator.validate(state).size(), 0, "a real log is valid")
	var loaded := GameState.from_dict(state.to_dict())
	t.equal(loaded.foreign.hostile_log, state.foreign.hostile_log, "and survives a save")
	var invented := GameState.from_dict(state.to_dict())
	invented.foreign.hostile_log.pop_front()
	invented.foreign.hostile_log.append({"turn": invented.turn, "actor": "atlantis", "relation": 0.0, "economy": 0.0, "stability": 0.0})
	t.truth(StateValidator.validate(invented).size() > 0, "an invented actor is rejected")
	var future := GameState.from_dict(state.to_dict())
	future.foreign.hostile_log.pop_front()
	future.foreign.hostile_log.append({"turn": future.turn + 5, "actor": "krasova", "relation": 0.0, "economy": 0.0, "stability": 0.0})
	t.truth(StateValidator.validate(future).size() > 0, "a future-dated entry is rejected")
	var bad := state.to_dict()
	bad["foreign"]["hostile_log"] = "nonsense"
	t.truth(ForeignState.from_dict(bad["foreign"]) == null, "a malformed log does not load")


static func _pressed_month(gas: float) -> float:
	var state := _isolated(31)
	var krasova := DiplomacySim.world_country(state, "krasova")
	state.foreign.powers["krasova"] = {"dependence": 0.0, "commitment": 0.0, "leverage": 0.0}
	krasova.plan = {"objective": "undermine", "target": "ardenia", "matures_turn": 0, "last_acted_turn": -1, "foreshadowed": true}
	state.foreign.gas_share["krasova"] = gas
	NativeGameScript.close_month(state)
	for entry in state.foreign.hostile_log:
		if String(entry["actor"]) == "krasova" and int(entry["turn"]) == state.turn:
			return -float(entry["relation"])
	return 0.0


func _test_the_spine_is_read_in_the_month_it_changes(t) -> void:
	var calm := _pressed_month(0.0)
	var dependent := _pressed_month(1.0)
	t.truth(calm > 0.0, "Krasova moves against Ardenia in the closing month (%.3f)" % calm)
	t.truth(dependent > calm, "that move already uses the leverage of the month it lands in (%.3f > %.3f)" % [dependent, calm])


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_gas_is_the_heaviest_dependence(t)
	_test_debt_held_abroad_is_dependence(t)
	_test_trade_share_is_dependence(t)
	_test_commitment_is_what_has_been_signed(t)
	_test_winter_sharpens_the_gas_lever(t)
	_test_warmth_blunts_leverage(t)
	_test_leverage_is_bounded_at_the_extremes(t)
	_test_the_month_records_every_power(t)
	_test_leverage_sharpens_krasovan_pressure(t)
	_test_a_meridian_guarantee_shields_like_a_pact(t)
	_test_warmth_never_raises_coercion(t)
	_test_a_landed_move_logs_its_real_effect(t)
	_test_the_hostile_log_is_bounded_valid_and_saved(t)
	_test_the_spine_is_read_in_the_month_it_changes(t)
	quit(t.finish())
