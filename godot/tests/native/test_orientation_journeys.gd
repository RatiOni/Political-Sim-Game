extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const FiscalJourneys = preload("res://tests/native/test_fiscal_journeys.gd")
const SEEDS := [919191, 31, 424242, 7]
const STRATEGIES := ["neutral", "western", "union"]
const MONTHS := 240
const WESTERN_STEPS := ["meridian_partnership", "concert_agreement", "meridian_guarantee"]
const UNION_STEPS := ["union_observer", "union_member"]
const OUTREACH_RESERVE := 40.0
const TARIFF_BITE := 0.75
const UNION_GDP_FLOOR := 0.99
const UNION_GAS_EDGE := 1.02
const DEFICIT_CEILING := 0.08
const INFLATION_CEILING := 0.12
const UNION_PRICE_CEILING := 0.75


static func _state(seed: int) -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": seed})
	state.rng = SimRng.from_seed(seed)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	return state


static func _score(state: GameState, id: String) -> float:
	return (state.country.relations[id] as Country.BilateralRelation).score


static func _bloc_trade(state: GameState, bloc_id: String) -> float:
	var total := 0.0
	for id in state.foreign.members.get(bloc_id, []):
		if state.country.relations.has(id):
			total += (state.country.relations[id] as Country.BilateralRelation).trade_volume
	return total


static func _play(state: GameState, strategy: String) -> void:
	FiscalJourneys.steady_budget(state)
	OrientationActions.act(state, "isf_renegotiate")
	match strategy:
		"western":
			if not state.enacted_laws.any(func(l: Law) -> bool: return l.id == OrientationSim.BANK_ACT):
				if LawActions.propose(state, OrientationSim.BANK_ACT).get("ok", false):
					LawActions.vote(state)
			for verb in WESTERN_STEPS:
				OrientationActions.act(state, verb)
		"union":
			for verb in UNION_STEPS:
				OrientationActions.act(state, verb)
			if state.player.political_capital > OUTREACH_RESERVE:
				DiplomacyActions.act(state, "improve_relations", "krasova")


static func _unbounded(state: GameState) -> int:
	var count := 0
	for id in ForeignSim.power_ids():
		var row: Dictionary = state.foreign.powers.get(id, {})
		for field in ["dependence", "commitment", "leverage"]:
			var v := float(row.get(field, -1.0))
			if not is_finite(v) or v < 0.0 or v > 1.0:
				count += 1
	return count


static func _signature(state: GameState) -> String:
	var reached: Array = state.foreign.reached.keys()
	reached.sort()
	return str([state.foreign.members, int(state.foreign.isf["passed"]), int(state.foreign.isf["failed"]),
		reached, snappedf(_score(state, "krasova"), 0.001), state.event_history.size(),
		state.foreign.gas.cuts, state.foreign.gas.threats, snappedf(state.foreign.gas.arrears, 1.0)])


static func _journey(seed: int, strategy: String, months: int) -> Dictionary:
	var state := _state(seed)
	var approval := 0.0
	var lowest_stability := 1.0
	var krasova_warmth := 0.0
	var governed := 0
	var concert_trade := 0.0
	var invalid := 0
	var unbounded := 0
	var gas_price := 0.0
	var blocked_cuts := 0
	var peak_arrears := 0.0
	var worst_deficit := 0.0
	var worst_inflation := 0.0
	for m in range(months):
		_play(state, strategy)
		NativeGameScript.next_month(state)
		gas_price += state.foreign.gas.price / float(months)
		peak_arrears = maxf(peak_arrears, state.foreign.gas.arrears)
		if GasSim.cuts_blocked(state) and state.foreign.gas.cut > 0.0:
			blocked_cuts += 1
		worst_deficit = maxf(worst_deficit, state.country.economy.deficit_share_of_gdp())
		worst_inflation = maxf(worst_inflation, state.country.economy.inflation)
		approval += state.player.approval / float(months)
		lowest_stability = minf(lowest_stability, state.stability_value)
		if state.player.in_government:
			krasova_warmth += _score(state, "krasova")
			governed += 1
		concert_trade += _bloc_trade(state, "concert") / float(months)
		unbounded += _unbounded(state)
		if m % 12 == 11 and not StateValidator.validate(state).is_empty():
			invalid += 1
	return {"approval": approval, "lowest_stability": lowest_stability, "krasova_warmth": krasova_warmth / maxf(1.0, governed),
		"concert_trade": concert_trade, "invalid": invalid, "unbounded": unbounded,
		"gdp": state.country.economy.gdp, "reached": state.foreign.reached.keys(),
		"isf": state.foreign.isf.duplicate(), "signature": _signature(state),
		"gas_cuts": state.foreign.gas.cuts, "gas_threats": state.foreign.gas.threats, "gas_price": gas_price, "reference_price": state.foreign.gas.reference_price,
		"blocked_cuts": blocked_cuts, "peak_arrears": peak_arrears, "worst_deficit": worst_deficit, "worst_inflation": worst_inflation, "foreign": state.foreign.to_dict()}


func _test_every_orientation_is_viable_and_bounded(t, runs: Dictionary) -> void:
	for key in runs:
		var r: Dictionary = runs[key]
		t.equal(int(r["invalid"]), 0, "%s: the state stays valid every year" % key)
		t.equal(int(r["unbounded"]), 0, "%s: every gauge stays within 0..1" % key)
		t.truth(float(r["approval"]) >= 0.25 and float(r["approval"]) <= 0.75, "%s: approval stays in a sane band (%.3f)" % [key, r["approval"]])
		t.truth(float(r["lowest_stability"]) >= 0.15, "%s: the state never collapses (lowest stability %.3f)" % [key, r["lowest_stability"]])


func _test_each_orientation_reaches_its_goal(t, runs: Dictionary) -> void:
	var members := 0
	for seed in SEEDS:
		t.truth("meridian_partnership" in runs["western/%d" % seed]["reached"], "seed %d: a Western-leaning government joins the Meridian partnership" % seed)
		t.truth("concert_agreement" in runs["western/%d" % seed]["reached"], "seed %d: and reaches the Concert association agreement" % seed)
		t.truth(not ("union_observer" in runs["neutral/%d" % seed]["reached"]), "seed %d: a neutral government stays out of the Union" % seed)
		t.truth(not ("union_observer" in runs["western/%d" % seed]["reached"]), "seed %d: a Western-leaning one does too" % seed)
		if "union_member" in runs["union/%d" % seed]["reached"]:
			members += 1
	t.truth(members * 2 >= SEEDS.size(), "a Krasova-leaning government usually reaches membership (%d of %d)" % [members, SEEDS.size()])


func _test_each_orientation_has_a_price(t, runs: Dictionary) -> void:
	var colder := 0
	var west_mean := 0.0
	var neutral_mean := 0.0
	for seed in SEEDS:
		var w := float(runs["western/%d" % seed]["krasova_warmth"])
		var n := float(runs["neutral/%d" % seed]["krasova_warmth"])
		colder += 1 if w < n else 0
		west_mean += w / float(SEEDS.size())
		neutral_mean += n / float(SEEDS.size())
	t.truth(west_mean < neutral_mean, "leaning west costs Krasova's goodwill on average (%.3f < %.3f)" % [west_mean, neutral_mean])
	t.truth(colder >= SEEDS.size() - 1, "and on all but at most one seed (%d of %d)" % [colder, SEEDS.size()])
	for seed in SEEDS:
		var neutral: Dictionary = runs["neutral/%d" % seed]
		var west: Dictionary = runs["western/%d" % seed]
		var union: Dictionary = runs["union/%d" % seed]
		if "union_member" in union["reached"]:
			t.truth(float(union["concert_trade"]) < float(neutral["concert_trade"]) * TARIFF_BITE, "seed %d: Union tariffs cost Western trade (%.0f < %.0f x 0.75)" % [seed, union["concert_trade"], neutral["concert_trade"]])
			t.truth(float(union["gdp"]) >= float(neutral["gdp"]) * UNION_GDP_FLOOR, "seed %d: the Union never costs real output (%.0f >= %.0f x 0.99)" % [seed, union["gdp"], neutral["gdp"]])
	var neutral_gdp := 0.0
	var union_gdp := 0.0
	for seed in SEEDS:
		neutral_gdp += float(runs["neutral/%d" % seed]["gdp"]) / SEEDS.size()
		union_gdp += float(runs["union/%d" % seed]["gdp"]) / SEEDS.size()
	t.truth(union_gdp > neutral_gdp, "on average staying neutral forgoes the Union's markets (%.0f < %.0f)" % [neutral_gdp, union_gdp])


func _test_gas_shapes_each_orientation(t, runs: Dictionary) -> void:
	var neutral_gdp := 0.0
	var union_gdp := 0.0
	var neutral_cuts := 0
	var union_cuts := 0
	for seed in SEEDS:
		var neutral: Dictionary = runs["neutral/%d" % seed]
		var union: Dictionary = runs["union/%d" % seed]
		t.equal(int(union["blocked_cuts"]), 0, "seed %d: the Union never leaves a member cut short of a crisis" % seed)
		if "union_member" in union["reached"]:
			t.truth(float(union["gas_price"]) < float(neutral["gas_price"]), "seed %d: Union membership buys cheaper gas (%.1f < %.1f)" % [seed, union["gas_price"], neutral["gas_price"]])
			t.truth(float(union["gas_price"]) <= float(union["reference_price"]) * UNION_PRICE_CEILING, "seed %d: the Union keeps a member's gas well under the reference price (%.1f <= %.1f x 0.75)" % [seed, union["gas_price"], union["reference_price"]])
		neutral_gdp += float(neutral["gdp"])
		union_gdp += float(union["gdp"])
		neutral_cuts += int(neutral["gas_cuts"])
		union_cuts += int(union["gas_cuts"])
	t.truth(union_gdp >= neutral_gdp * UNION_GAS_EDGE, "the Union's cheap gas is a real growth edge (%.0f >= %.0f x 1.02)" % [union_gdp, neutral_gdp])
	t.truth(union_cuts < neutral_cuts, "the Union is cut less often than neutrality (%d < %d)" % [union_cuts, neutral_cuts])
	var threatened := 0
	for key in runs:
		var r: Dictionary = runs[key]
		if int(r["gas_threats"]) > 0:
			threatened += 1
		t.truth(float(r["peak_arrears"]) < 10000.0 and is_finite(float(r["peak_arrears"])), "%s: arrears stay finite and bounded" % key)
		t.truth(float(r["worst_deficit"]) <= DEFICIT_CEILING, "%s: the deficit never runs away (%.3f)" % [key, r["worst_deficit"]])
		t.truth(float(r["worst_inflation"]) <= INFLATION_CEILING, "%s: inflation never runs away (%.3f)" % [key, r["worst_inflation"]])
		print("JOURNEY %s gdp=%.0f price=%.1f cuts=%d threats=%d deficit=%.3f inflation=%.3f" % [key, r["gdp"], r["gas_price"], r["gas_cuts"], r["gas_threats"], r["worst_deficit"], r["worst_inflation"]])
	t.truth(threatened >= 1, "Krasova mentions the valve in at least one of the twelve histories (%d)" % threatened)
	for seed in SEEDS:
		t.truth(float(runs["western/%d" % seed]["gas_price"]) >= float(runs["union/%d" % seed]["gas_price"]), "seed %d: leaning west pays more for gas than the Union does" % seed)


func _test_the_isf_is_demanding_but_passable(t, runs: Dictionary) -> void:
	var passed := 0
	var held := 0
	for seed in SEEDS:
		var isf: Dictionary = runs["neutral/%d" % seed]["isf"]
		passed += int(isf["passed"])
		held += int(isf["reviews_held"])
	var share := float(passed) / float(maxi(1, held))
	t.equal(held, SEEDS.size() * OrientationSim.ISF_REVIEWS, "every programme runs all its reviews")
	t.truth(share >= 0.2 and share <= 0.9, "a steady government passes some reviews and fails others (%.2f)" % share)


func _test_seeds_write_different_foreign_histories(t, runs: Dictionary) -> void:
	var seen := {}
	for seed in SEEDS:
		seen[String(runs["neutral/%d" % seed]["signature"])] = true
	t.truth(seen.size() >= 3, "different seeds give different foreign histories (%d distinct of %d)" % [seen.size(), SEEDS.size()])


func _test_the_same_seed_and_choices_repeat_exactly(t) -> void:
	var a := _journey(424242, "union", 60)
	var b := _journey(424242, "union", 60)
	t.equal(a["foreign"], b["foreign"], "the same seed and the same choices give the same foreign ledger")
	t.equal(a["signature"], b["signature"], "and the same history")


func _initialize() -> void:
	var t = TestSupportScript.new()
	var runs := {}
	for strategy in STRATEGIES:
		for seed in SEEDS:
			runs["%s/%d" % [strategy, seed]] = _journey(seed, strategy, MONTHS)
	_test_every_orientation_is_viable_and_bounded(t, runs)
	_test_each_orientation_reaches_its_goal(t, runs)
	_test_each_orientation_has_a_price(t, runs)
	_test_gas_shapes_each_orientation(t, runs)
	_test_the_isf_is_demanding_but_passable(t, runs)
	_test_seeds_write_different_foreign_histories(t, runs)
	_test_the_same_seed_and_choices_repeat_exactly(t)
	quit(t.finish())
