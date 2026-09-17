extends SceneTree

## Standalone headless test for Phase 2 Task 7: EconomySim (the monthly
## economy — workforce quality, bureaucratic capacity, sectors, structural
## fiscal baseline, organic inflation, modifiers onto headline stats,
## compound GDP).
## Run via:
##   Godot --headless --path godot --script res://tests/native/test_economy_sim.gd
##
## Checks the ported logic on its own terms (task-7-brief.md: no
## oracle/parity comparison against Python is required or wanted) — workforce
## quality and bureaucratic capacity respond to modifiers; sectors evolve
## (not fixed) and stay normalized; the structural fiscal baseline reflects
## `active_budget`'s size once it exists and reallocates it on drift;
## inflation drifts toward the anchor, pushed by deficit/overheating,
## bounded at STRUCTURAL_INFLATION_MAX; modifiers apply exactly once per
## pulse with no accumulation across repeated calls; GDP compounds from
## growth correctly over several months.

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
	m.hold_duration = -1   # holds forever, so current_value() == magnitude immediately
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


# ── Workforce quality / bureaucratic capacity ────────────────────────────

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


# ── Sectors ───────────────────────────────────────────────────────────────

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

	# growth_rate values themselves are untouched by _update_sectors.
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
	services.growth_rate = 0.20   # strong positive growth this pulse

	EconomySimScript.update(state)

	t.truth(faction.power > before_power,
		"a fast-growing sector's aligned faction gains power")


# ── Structural fiscal baseline / active_budget sync ──────────────────────

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

	# Force a large positive structural growth so the monthly drift is
	# unmistakable rather than lost in normal small-percentage movement.
	state.country.economy.structural_growth_rate = 1.20   # +10%/month
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


# ── Organic inflation ─────────────────────────────────────────────────────

func _test_inflation_drifts_toward_anchor_from_above(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var econ := state.country.economy
	econ.structural_inflation = 0.30
	econ.budget.revenue = 1000.0
	econ.budget.expenditure = 1000.0   # balanced budget: no deficit push
	econ.growth_rate = EconomySimScript.TREND_GROWTH   # no overheat push

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
		econ.structural_inflation = EconomySimScript.INFLATION_ANCHOR   # start exactly at anchor
		econ.budget.revenue = 1000.0
		econ.budget.expenditure = 1000.0
		econ.growth_rate = EconomySimScript.TREND_GROWTH

	hot.country.economy.budget.expenditure = 1500.0   # large deficit
	hot.country.economy.growth_rate = EconomySimScript.TREND_GROWTH + 0.10   # overheating

	EconomySimScript.update(calm)
	EconomySimScript.update(hot)

	t.truth(hot.country.economy.structural_inflation > calm.country.economy.structural_inflation,
		"deficit + overheating pushes structural_inflation higher than a balanced, on-trend economy")


func _test_inflation_bounded_at_structural_max(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var econ := state.country.economy
	econ.structural_inflation = EconomySimScript.STRUCTURAL_INFLATION_MAX
	econ.budget.revenue = 100.0
	econ.budget.expenditure = 1000.0   # enormous deficit ratio (clamped to 1.5 internally)
	econ.growth_rate = EconomySimScript.TREND_GROWTH + 1.0   # enormous overheat

	for _i in range(3):
		EconomySimScript.update(state)

	t.truth(econ.structural_inflation <= EconomySimScript.STRUCTURAL_INFLATION_MAX + 0.0000001,
		"structural_inflation never exceeds STRUCTURAL_INFLATION_MAX")


# ── Modifiers apply exactly once per pulse ───────────────────────────────

func _test_modifiers_apply_once_per_pulse_not_accumulated(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	_add_modifier(state, "gdp_growth", 0.01)

	EconomySimScript.update(state)
	var growth_after_one := state.country.economy.growth_rate
	var structural_after_one := state.country.economy.structural_growth_rate

	# A second call with the same still-active modifier (simulating a
	# save/reload replaying this pulse against the same state) must land on
	# the same effective growth_rate, not a doubled one — current_value() is
	# recomputed fresh, never accumulated, and _apply_modifiers_to_headline_stats
	# assigns with `=`, not `+=`.
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

	# bureaucratic_capacity is itself recomputed fresh from BASE + modifiers
	# every pulse (_update_bureaucratic_capacity runs before the headline-stat
	# phase), so driving it to the extremes must go through a
	# "bureaucratic_capacity" modifier, not a direct field assignment (that
	# would just be overwritten). stability_value has no such phase in
	# EconomySim, so it's safe to set directly.
	_add_modifier(weak, "bureaucratic_capacity", -0.75)     # -> ~0.0 after clamping
	weak.stability_value = 0.0
	_add_modifier(strong, "bureaucratic_capacity", 0.25)    # -> 1.0 after clamping
	strong.stability_value = 1.0

	for s in [weak, strong]:
		_add_modifier(s, "gdp_growth", 0.10, true, "")   # institutional, no portfolio

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
		_add_modifier(s, "gdp_growth", 0.10, false)   # NOT institutional

	EconomySimScript.update(weak)
	EconomySimScript.update(strong)

	t.near(weak.country.economy.growth_rate, strong.country.economy.growth_rate, 0.0001,
		"a non-institutional modifier's effect never depends on capacity/stability")


# ── GDP compounding ───────────────────────────────────────────────────────

func _test_gdp_compounds_from_growth_over_several_months(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var econ := state.country.economy
	econ.growth_rate = 0.12   # fixed 12%/yr for a predictable compounding check
	econ.structural_growth_rate = 0.12
	econ.sectors = []   # isolate GDP compounding from sector-driven growth drift
	var gdp0 := econ.gdp

	var expected := gdp0
	for _i in range(6):
		expected *= (1.0 + 0.12 / 12.0)
		EconomySimScript.update(state)
		# Re-pin growth_rate/structural_growth_rate each pulse since
		# _apply_modifiers_to_headline_stats recomputes growth_rate from
		# structural_growth_rate + modifiers (0 here) every call, and with no
		# sectors, structural_growth_rate never drifts on its own — but pin
		# explicitly for test clarity/robustness regardless.
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

	quit(t.finish())
