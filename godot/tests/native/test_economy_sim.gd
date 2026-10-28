extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")
const GameFactoryScript = preload("res://scripts/native/state/game_factory.gd")
const EconomySimScript = preload("res://scripts/native/sim/economy_sim.gd")
const BudgetSimScript = preload("res://scripts/native/sim/budget_sim.gd")

const FIXED_SEED := 424242


static func _base_config() -> Dictionary:
	return {
		"country_id": "ardenia",
		"background_id": "none",
		"difficulty_id": "normal",
		"opening_role": "contextual",
		"seed": FIXED_SEED,
	}


static func _add_modifier(state: GameState, target: String, magnitude: float,
		institutional: bool = false, portfolio: String = "") -> Modifier:
	var m := Modifier.new()
	m.id = "test-" + target
	m.source = "test"
	m.target = target
	m.magnitude = magnitude
	m.onset_delay = 0
	m.ramp_duration = 1
	m.hold_duration = -1
	m.decay_duration = 0
	m.age = 0
	m.institutional = institutional
	m.portfolio = portfolio
	state.modifiers.append(m)
	return m


static func _sum(allocations: Dictionary) -> float:
	var total := 0.0
	for v in allocations.values():
		total += float(v)
	return total


func _test_workforce_quality_responds_to_modifiers(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	t.equal(state.country.economy.workforce_quality, 0.5, "baseline workforce_quality with no modifiers")

	_add_modifier(state, "workforce_quality", 0.22)
	EconomySimScript.update(state)
	t.near(state.country.economy.workforce_quality, 0.72, 0.0001,
		"workforce_quality = BASE + modifier sum")


func _test_workforce_quality_clamps_to_unit_range(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	_add_modifier(state, "workforce_quality", 5.0)
	EconomySimScript.update(state)
	t.equal(state.country.economy.workforce_quality, 1.0, "workforce_quality clamps at 1.0")


func _test_bureaucratic_capacity_responds_to_modifiers(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var baseline := state.country.bureaucratic_capacity
	_add_modifier(state, "bureaucratic_capacity", -0.20)
	EconomySimScript.update(state)
	t.near(state.country.bureaucratic_capacity, 0.75 - 0.20, 0.0001,
		"bureaucratic_capacity = BASE + modifier sum")
	t.truth(state.country.bureaucratic_capacity != baseline,
		"bureaucratic_capacity actually moved from the campaign's authored baseline")


func _test_sectors_evolve_not_fixed(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var econ := state.country.economy
	t.truth(not econ.sectors.is_empty(), "ardenia has authored sectors")
	if econ.sectors.is_empty():
		return

	var before_shares: Array = []
	var before_growth: Array = []
	for s in econ.sectors:
		before_shares.append(s.gdp_share)
		before_growth.append(s.growth_rate)

	EconomySimScript.update(state)

	var any_share_changed := false
	for i in range(econ.sectors.size()):
		if not is_equal_approx(econ.sectors[i].gdp_share, before_shares[i]):
			any_share_changed = true
	t.truth(any_share_changed, "at least one sector's gdp_share moved after one pulse")
	t.truth(not is_nan(econ.structural_growth_rate), "structural_growth_rate is not NaN")

	for i in range(econ.sectors.size()):
		t.equal(econ.sectors[i].growth_rate, before_growth[i],
			"sector growth_rate is read, not mutated, by _update_sectors")


func _test_sector_shares_stay_normalized(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var econ := state.country.economy
	for _i in range(6):
		EconomySimScript.update(state)
	var gdp_total := 0.0
	var emp_total := 0.0
	for s in econ.sectors:
		gdp_total += s.gdp_share
		emp_total += s.employment_share
	t.near(gdp_total, 1.0, 0.0005, "sector gdp_share sums to 1.0 after repeated pulses")
	t.near(emp_total, 1.0, 0.0005, "sector employment_share sums to 1.0 after repeated pulses")


func _test_sector_growth_shifts_aligned_faction_power(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var econ := state.country.economy
	var services := econ.sector_by_id("services")
	t.truth(services != null, "ardenia has a 'services' sector")
	if services == null:
		return
	t.truth(not services.aligned_faction_ids.is_empty(), "services sector has an aligned faction")
	if services.aligned_faction_ids.is_empty():
		return
	var faction_id: String = services.aligned_faction_ids[0]
	var faction: Faction = null
	for f in state.country.factions:
		if f.id == faction_id:
			faction = f
	t.truth(faction != null, "aligned faction resolves in state.country.factions")
	if faction == null:
		return
	var before_power := faction.power
	services.growth_rate = 0.20

	EconomySimScript.update(state)

	t.truth(faction.power > before_power,
		"a fast-growing sector's aligned faction gains power")


func _test_fiscal_baseline_seeds_active_budget_and_reflects_size(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	t.equal(state.active_budget, null, "no active_budget before the first economy pulse")

	EconomySimScript.update(state)

	t.truth(state.active_budget != null, "EconomySim seeds active_budget via BudgetSim.ensure_budget_state")
	if state.active_budget == null:
		return
	t.near(_sum(state.active_budget.allocations), state.country.economy.structural_expenditure,
		0.5, "active_budget's total tracks structural_expenditure")


func _test_fiscal_baseline_resyncs_active_budget_on_drift(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	BudgetSimScript.ensure_budget_state(state)
	var before_total := _sum(state.active_budget.allocations)
	t.truth(before_total > 0.0, "seeded active_budget has a positive total")

	state.country.economy.structural_growth_rate = 1.20
	EconomySimScript.update(state)

	var after_total := _sum(state.active_budget.allocations)
	t.truth(after_total > before_total,
		"active_budget's allocations total grows to match the new (larger) structural_expenditure")
	t.near(after_total, state.country.economy.structural_expenditure, 0.5,
		"resynced active_budget total tracks the drifted structural_expenditure")


func _test_fiscal_baseline_counts_trade_revenue_only_for_trade_treaties(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var other_id := ""
	for c in state.world:
		other_id = c.id
		break
	t.truth(other_id != "", "campaign has at least one world country to relate to")
	if other_id == "":
		return
	var rel: Country.BilateralRelation = state.country.get_relation(other_id)
	t.truth(rel != null, "player country has a relation to a world country")
	if rel == null:
		return
	rel.trade_volume = 1000.0
	rel.treaties = [{"type": "trade"}, {"type": "defense"}]

	EconomySimScript.update(state)

	t.near(state.country.economy.trade_revenue_contribution, 1000.0 * EconomySimScript.TRADE_CUSTOMS_RATE,
		0.0001, "trade_revenue_contribution counts a trade-treatied relation's volume once")


func _test_fiscal_baseline_ignores_relations_without_a_trade_treaty(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var other_id := ""
	for c in state.world:
		other_id = c.id
		break
	if other_id == "":
		return
	var rel: Country.BilateralRelation = state.country.get_relation(other_id)
	if rel == null:
		return
	rel.trade_volume = 1000.0
	rel.treaties = [{"type": "defense"}]

	EconomySimScript.update(state)

	t.equal(state.country.economy.trade_revenue_contribution, 0.0,
		"a relation with only a non-trade treaty contributes no trade revenue")


func _test_inflation_drifts_toward_anchor_from_above(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var econ := state.country.economy
	econ.structural_inflation = 0.30
	econ.budget.revenue = 1000.0
	econ.budget.expenditure = 1000.0
	econ.spending_trend = econ.structural_expenditure

	EconomySimScript.update(state)

	t.truth(econ.structural_inflation < 0.30, "inflation moves down toward the anchor from above")
	t.truth(econ.structural_inflation > EconomySimScript.INFLATION_ANCHOR,
		"one month's reversion pull doesn't overshoot the anchor")


func _test_inflation_pushed_up_by_deficit_and_overheating(t, content: Dictionary) -> void:
	var calm: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var hot: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(calm != null and hot != null, "both campaigns build")
	if calm == null or hot == null:
		return

	for s in [calm, hot]:
		var econ: Economy = s.country.economy
		econ.structural_inflation = EconomySimScript.INFLATION_ANCHOR
		econ.budget.revenue = 1000.0
		econ.budget.expenditure = 1000.0
		econ.spending_trend = econ.structural_expenditure

	hot.country.economy.budget.expenditure = 1500.0
	hot.country.economy.structural_expenditure += hot.country.economy.gdp * 0.05

	EconomySimScript.update(calm)
	EconomySimScript.update(hot)

	t.truth(hot.country.economy.structural_inflation > calm.country.economy.structural_inflation,
		"a deficit plus a fresh stimulus pushes inflation higher than a balanced, neutral economy")


func _test_inflation_bounded_at_structural_max(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var econ := state.country.economy
	econ.structural_inflation = EconomySimScript.STRUCTURAL_INFLATION_MAX
	econ.budget.revenue = 100.0
	econ.budget.expenditure = 1000.0
	econ.structural_expenditure += econ.gdp

	for _i in range(3):
		EconomySimScript.update(state)

	t.truth(econ.structural_inflation <= EconomySimScript.STRUCTURAL_INFLATION_MAX + 0.0000001,
		"structural_inflation never exceeds STRUCTURAL_INFLATION_MAX")


func _test_modifiers_apply_once_per_pulse_not_accumulated(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	_add_modifier(state, "gdp_growth", 0.01)

	EconomySimScript.update(state)
	var growth_after_one := state.country.economy.growth_rate
	var structural_after_one := state.country.economy.structural_growth_rate

	EconomySimScript.update(state)
	var structural_after_two := state.country.economy.structural_growth_rate

	t.near(state.country.economy.growth_rate, structural_after_two + 0.01, 0.0001,
		"growth_rate == structural_growth_rate + modifier magnitude, not compounded")
	t.truth(absf(state.country.economy.growth_rate - growth_after_one) < 0.05,
		"repeated pulses don't blow up growth_rate from a re-applied modifier")


func _test_institutional_modifier_is_dampened_by_capacity_and_stability(t, content: Dictionary) -> void:
	var weak: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var strong: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(weak != null and strong != null, "both campaigns build")
	if weak == null or strong == null:
		return

	_add_modifier(weak, "bureaucratic_capacity", -0.75)
	weak.stability_value = 0.0
	_add_modifier(strong, "bureaucratic_capacity", 0.25)
	strong.stability_value = 1.0

	for s in [weak, strong]:
		_add_modifier(s, "gdp_growth", 0.10, true, "")

	EconomySimScript.update(weak)
	EconomySimScript.update(strong)

	t.truth(strong.country.economy.growth_rate > weak.country.economy.growth_rate,
		"an institutional modifier delivers more effect under high capacity/stability than low")


func _test_non_institutional_modifier_ignores_capacity(t, content: Dictionary) -> void:
	var weak: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var strong: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(weak != null and strong != null, "both campaigns build")
	if weak == null or strong == null:
		return

	_add_modifier(weak, "bureaucratic_capacity", -0.75)
	weak.stability_value = 0.0
	_add_modifier(strong, "bureaucratic_capacity", 0.25)
	strong.stability_value = 1.0

	for s in [weak, strong]:
		_add_modifier(s, "gdp_growth", 0.10, false)

	EconomySimScript.update(weak)
	EconomySimScript.update(strong)

	t.near(weak.country.economy.growth_rate, strong.country.economy.growth_rate, 0.0001,
		"a non-institutional modifier's effect never depends on capacity/stability")


func _test_gdp_compounds_from_growth_over_several_months(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var econ := state.country.economy
	econ.growth_rate = 0.12
	econ.structural_growth_rate = 0.12
	econ.sectors = []
	var gdp0 := econ.gdp

	var expected := gdp0
	for _i in range(6):
		expected *= (1.0 + 0.12 / 12.0)
		EconomySimScript.update(state)
		econ.growth_rate = 0.12
		econ.structural_growth_rate = 0.12

	t.near(econ.gdp, expected, 0.01, "gdp compounds monthly_growth = growth_rate/12 six times")
	t.truth(econ.gdp > gdp0, "gdp grew overall under sustained positive growth")


func _test_gdp_shrinks_under_negative_growth(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var econ := state.country.economy
	econ.sectors = []
	econ.growth_rate = -0.24
	econ.structural_growth_rate = -0.24
	var gdp0 := econ.gdp

	EconomySimScript.update(state)

	t.truth(econ.gdp < gdp0, "gdp shrinks under sustained negative growth")


static func _passive_months(state: GameState, months: int) -> void:
	for _i in range(months):
		EconomySimScript.update(state)


func _test_sustained_deficit_raises_debt(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var econ := state.country.economy
	econ.structural_expenditure *= 1.25
	econ.spending_trend = econ.structural_expenditure
	var debt0 := econ.public_debt_pct
	_passive_months(state, 36)
	t.truth(econ.public_debt_pct > debt0 + 0.10,
		"three years of a large deficit raise debt/GDP by more than 10 points (%.3f -> %.3f)" % [debt0, econ.public_debt_pct])


func _test_sustained_surplus_lowers_debt(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var econ := state.country.economy
	econ.structural_revenue *= 1.30
	var debt0 := econ.public_debt_pct
	_passive_months(state, 36)
	t.truth(econ.public_debt_pct < debt0,
		"three years of surplus pay the debt down (%.3f -> %.3f)" % [debt0, econ.public_debt_pct])


func _test_debt_ratio_moves_gradually(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var econ := state.country.economy
	econ.structural_expenditure *= 1.25
	econ.spending_trend = econ.structural_expenditure
	var debt0 := econ.public_debt_pct
	EconomySimScript.update(state)
	t.truth(absf(econ.public_debt_pct - debt0) < 0.01,
		"a single month moves debt/GDP by less than one point: no instant punishment")


func _test_interest_is_part_of_the_bill_and_rises_with_debt(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var econ := state.country.economy
	t.truth(econ.debt_service > 0.0, "a country carrying debt pays interest from the start")
	EconomySimScript.update(state)
	t.near(econ.budget.expenditure,
		econ.structural_expenditure + EconomySimScript._modifiers_sum(state, "budget_expenditure") + econ.debt_service,
		0.001, "interest is a line inside total expenditure")
	econ.public_debt_pct = 0.40
	econ.inflation = 0.03
	var low := econ.market_interest_rate()
	econ.public_debt_pct = 1.20
	var high := econ.market_interest_rate()
	t.truth(high > low, "the market charges a heavily indebted state more (%.3f vs %.3f)" % [high, low])
	econ.inflation = 0.30
	t.truth(econ.market_interest_rate() > high, "runaway inflation adds its own risk premium")


func _test_effective_rate_reprices_slowly(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var econ := state.country.economy
	var paid0 := econ.effective_interest_rate
	econ.public_debt_pct = 1.50
	EconomySimScript.update(state)
	t.truth(econ.effective_interest_rate > paid0, "the rate paid starts moving toward the market rate")
	t.truth(econ.effective_interest_rate < econ.market_interest_rate(),
		"but one month reprices only a slice of the debt")


func _test_opening_deficit_matches_authored_figures(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var econ := state.country.economy
	t.near(econ.structural_expenditure + econ.debt_service, econ.budget.expenditure, 0.01,
		"primary spending plus interest equals the authored opening expenditure")


func _test_stimulus_lifts_growth_then_fades(t, content: Dictionary) -> void:
	var calm: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var hot: GameState = GameFactoryScript.new_campaign(content, _base_config())
	hot.country.economy.structural_expenditure *= 1.15
	EconomySimScript.update(calm)
	EconomySimScript.update(hot)
	var early := hot.country.economy.growth_rate - calm.country.economy.growth_rate
	t.truth(early > 0.005, "new spending lifts growth (+%.4f)" % early)
	_passive_months(calm, 60)
	_passive_months(hot, 60)
	var late := hot.country.economy.growth_rate - calm.country.economy.growth_rate
	t.truth(late < early * 0.25, "five years on, the boost has mostly worn off (%.4f vs %.4f)" % [late, early])
	t.truth(hot.country.economy.public_debt_pct > calm.country.economy.public_debt_pct + 0.05,
		"but the debt it ran up is still there")


func _test_austerity_contracts_growth_and_raises_unemployment(t, content: Dictionary) -> void:
	var calm: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var cut: GameState = GameFactoryScript.new_campaign(content, _base_config())
	cut.country.economy.structural_expenditure *= 0.80
	_passive_months(calm, 12)
	_passive_months(cut, 12)
	t.truth(cut.country.economy.growth_rate < calm.country.economy.growth_rate,
		"deep cuts slow growth in the short run")
	t.truth(cut.country.economy.unemployment > calm.country.economy.unemployment,
		"and cost jobs: austerity is not free")


func _test_unemployment_heals_toward_natural_rate_not_floor(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var econ := state.country.economy
	var start := econ.unemployment
	_passive_months(state, 360)
	t.truth(econ.unemployment < start, "a passive labour market slowly heals (%.3f -> %.3f)" % [start, econ.unemployment])
	t.truth(absf(econ.unemployment - econ.natural_unemployment) < 0.015,
		"it settles near its natural rate (%.3f vs %.3f)" % [econ.unemployment, econ.natural_unemployment])
	t.truth(econ.unemployment > 0.05, "and never drifts to the floor on its own")


func _test_better_workforce_lowers_natural_rate(t, content: Dictionary) -> void:
	var base: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var skilled: GameState = GameFactoryScript.new_campaign(content, _base_config())
	_add_modifier(skilled, "workforce_quality", 0.3)
	EconomySimScript.update(base)
	EconomySimScript.update(skilled)
	t.truth(skilled.country.economy.natural_unemployment < base.country.economy.natural_unemployment,
		"a better-trained workforce lowers the natural rate of unemployment")


func _test_anchor_slips_when_inflation_runs_away(t, content: Dictionary) -> void:
	t.truth(EconomySimScript.anchor_credibility(0.03) > EconomySimScript.anchor_credibility(0.30),
		"the anchor holds near target and loses its grip under runaway inflation")
	t.truth(EconomySimScript.anchor_credibility(1.0) >= EconomySimScript.ANCHOR_MIN_CREDIBILITY,
		"but never loses it entirely")


func _test_high_inflation_costs_more_than_a_growth_swing(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var econ := state.country.economy
	econ.inflation = 0.03
	var tame := StabilitySim.economic_signal(state)
	econ.inflation = 0.40
	var wild := StabilitySim.economic_signal(state)
	econ.inflation = 0.03
	econ.growth_rate += 0.03
	var boom := StabilitySim.economic_signal(state)
	t.truth(tame - wild > (boom - tame) * 4.0,
		"40%% inflation hurts far more than three points of growth help (%.3f vs %.3f)" % [tame - wild, boom - tame])


func _test_balance_sheet_survives_save_and_reload(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	state.country.economy.structural_expenditure *= 1.1
	_passive_months(state, 7)
	var econ := state.country.economy
	var copy := Economy.from_dict(econ.to_dict())
	t.near(copy.effective_interest_rate, econ.effective_interest_rate, 1e-9, "effective interest rate round-trips")
	t.near(copy.debt_service, econ.debt_service, 1e-6, "debt service round-trips")
	t.near(copy.spending_trend, econ.spending_trend, 1e-6, "spending trend round-trips (a reload cannot reset a stimulus)")
	t.near(copy.fiscal_impulse, econ.fiscal_impulse, 1e-9, "fiscal impulse round-trips")
	t.near(copy.natural_unemployment, econ.natural_unemployment, 1e-9, "natural unemployment round-trips")


func _test_long_run_stays_bounded(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var econ := state.country.economy
	econ.structural_expenditure *= 1.30
	var ok := true
	for _i in range(480):
		EconomySimScript.update(state)
		for v in [econ.gdp, econ.inflation, econ.unemployment, econ.public_debt_pct, econ.debt_service, econ.growth_rate]:
			if not is_finite(float(v)):
				ok = false
	t.truth(ok, "forty years of heavy deficit spending never produce a non-finite figure")
	t.truth(econ.public_debt_pct <= EconomySimScript.MAX_DEBT_PCT, "debt stays inside its safety bound")
	t.truth(econ.inflation <= 1.0 and econ.unemployment <= 0.50, "prices and jobs stay bounded")


func _initialize() -> void:
	var t = TestSupportScript.new()

	var content: Dictionary = ContentRepositoryScript.load_all()
	t.truth(not content.has("error"), "content loads for the economy tests")

	if not content.has("error"):
		_test_workforce_quality_responds_to_modifiers(t, content)
		_test_workforce_quality_clamps_to_unit_range(t, content)
		_test_bureaucratic_capacity_responds_to_modifiers(t, content)

		_test_sectors_evolve_not_fixed(t, content)
		_test_sector_shares_stay_normalized(t, content)
		_test_sector_growth_shifts_aligned_faction_power(t, content)

		_test_fiscal_baseline_seeds_active_budget_and_reflects_size(t, content)
		_test_fiscal_baseline_resyncs_active_budget_on_drift(t, content)
		_test_fiscal_baseline_counts_trade_revenue_only_for_trade_treaties(t, content)
		_test_fiscal_baseline_ignores_relations_without_a_trade_treaty(t, content)

		_test_inflation_drifts_toward_anchor_from_above(t, content)
		_test_inflation_pushed_up_by_deficit_and_overheating(t, content)
		_test_inflation_bounded_at_structural_max(t, content)

		_test_modifiers_apply_once_per_pulse_not_accumulated(t, content)
		_test_institutional_modifier_is_dampened_by_capacity_and_stability(t, content)
		_test_non_institutional_modifier_ignores_capacity(t, content)

		_test_gdp_compounds_from_growth_over_several_months(t, content)
		_test_gdp_shrinks_under_negative_growth(t, content)

		_test_sustained_deficit_raises_debt(t, content)
		_test_sustained_surplus_lowers_debt(t, content)
		_test_debt_ratio_moves_gradually(t, content)
		_test_interest_is_part_of_the_bill_and_rises_with_debt(t, content)
		_test_effective_rate_reprices_slowly(t, content)
		_test_opening_deficit_matches_authored_figures(t, content)
		_test_stimulus_lifts_growth_then_fades(t, content)
		_test_austerity_contracts_growth_and_raises_unemployment(t, content)
		_test_unemployment_heals_toward_natural_rate_not_floor(t, content)
		_test_better_workforce_lowers_natural_rate(t, content)
		_test_anchor_slips_when_inflation_runs_away(t, content)
		_test_high_inflation_costs_more_than_a_growth_swing(t, content)
		_test_balance_sheet_survives_save_and_reload(t, content)
		_test_long_run_stays_bounded(t, content)

	quit(t.finish())
