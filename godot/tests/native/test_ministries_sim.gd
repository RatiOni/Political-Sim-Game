extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")
const GameFactoryScript = preload("res://scripts/native/state/game_factory.gd")
const MinistriesSimScript = preload("res://scripts/native/sim/ministries_sim.gd")

const FIXED_SEED := 424242
const ALL_PORTFOLIOS: Array[String] = ["Finance", "Interior", "Foreign Affairs", "Defense", "Economy", "Justice"]


static func _base_config() -> Dictionary:
	return {
		"country_id": "ardenia",
		"background_id": "none",
		"difficulty_id": "normal",
		"opening_role": "contextual",
		"seed": FIXED_SEED,
	}


static func _synthetic_budget(year: int) -> AnnualBudget:
	var b := AnnualBudget.new()
	b.year = year
	b.status = "active"
	b.allocations = {
		"state_administration": 100.0,
		"foreign_affairs": 50.0,
		"justice_and_policing": 80.0,
		"national_defense": 120.0,
		"infrastructure": 90.0,
		"industry_and_jobs": 60.0,
		"education": 100.0,
		"health_and_welfare": 200.0,
	}
	return b


static func _clear_ministers(state: GameState) -> void:
	state.ministers = []


static func _assign_minister(state: GameState, portfolio: String, competence: float,
		loyalty: float, faction_id: String = "not-the-ruling-party") -> void:
	var m := Minister.new()
	m.id = "test-" + portfolio
	m.name = "Test Minister"
	m.portfolio = portfolio
	m.faction_id = faction_id
	m.competence = competence
	m.loyalty = loyalty
	m.ambition = 0.0
	state.ministers.append(m)


static func _population_pressure(state: GameState, content: Dictionary) -> float:
	var profiles: Dictionary = content["catalogs"]["regions_and_programs"]["region_profiles"]
	var weighted := 0.0
	var total := 0.0
	for key in state.regions:
		var weight := 1.0
		var profile: Variant = profiles.get(String(key), {})
		if profile is Dictionary:
			weight = float((profile as Dictionary).get("population_weight", 1.0))
		weighted += (state.regions[key] as RegionState).pressure * weight
		total += weight
	return weighted / total if total > 0.0 else 0.0


func _test_ensure_ministries_seeds_every_core_portfolio(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	t.truth(state.ministries.is_empty(),
		"GameFactory leaves ministries unset (documented lazy-seed scope, see ministries_sim.gd header)")

	var ministries: Dictionary = MinistriesSimScript.ensure_ministries(state)
	t.equal(ministries.keys().size(), ALL_PORTFOLIOS.size(), "one ministry per CORE_PORTFOLIO")
	for portfolio in ALL_PORTFOLIOS:
		t.truth(ministries.has(portfolio), "ministries contains %s" % portfolio)
		var ministry: MinistryState = ministries.get(portfolio)
		if ministry == null:
			continue
		t.equal(ministry.portfolio, portfolio, "%s ministry has correct portfolio field" % portfolio)
		t.equal(ministry.delivery, 1.0, "%s seeds at full delivery" % portfolio)
		t.equal(ministry.backlog, 0.0, "%s seeds with no backlog" % portfolio)
		t.equal(ministry.months_overloaded, 0, "%s seeds with no overload history" % portfolio)
		t.equal(ministry.baseline_funding, 0.0, "%s baseline_funding is 0 with no active_budget" % portfolio)
	t.truth(ministries is Dictionary and ministries == state.ministries,
		"ensure_ministries returns the state's own dict")


func _test_ensure_ministries_reflects_real_funding_once_budgeted(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	state.active_budget = _synthetic_budget(state.year)

	var ministries: Dictionary = MinistriesSimScript.ensure_ministries(state)
	var finance: MinistryState = ministries["Finance"]
	var interior: MinistryState = ministries["Interior"]
	var economy: MinistryState = ministries["Economy"]
	t.near(finance.baseline_funding, 300.0, 0.001, "Finance baseline sums education+health_and_welfare")
	t.near(interior.baseline_funding, 100.0, 0.001, "Interior baseline is state_administration alone")
	t.near(economy.baseline_funding, 150.0, 0.001, "Economy baseline sums infrastructure+industry_and_jobs")


func _test_ensure_ministries_backfills_without_clobbering_existing(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	state.active_budget = _synthetic_budget(state.year)
	MinistriesSimScript.ensure_ministries(state)

	var interior: MinistryState = state.ministries["Interior"]
	interior.backlog = 2.0
	state.ministries.erase("Justice")
	t.truth(not state.ministries.has("Justice"), "sanity: Justice removed")

	var ministries: Dictionary = MinistriesSimScript.ensure_ministries(state)
	t.truth(ministries.has("Justice"), "backfill re-adds the missing portfolio")
	t.equal(state.ministries["Interior"].backlog, 2.0, "backfill does not touch an existing ministry's state")


func _test_capacity_responds_to_funding_ratio(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	state.active_budget = _synthetic_budget(state.year)
	var ministries: Dictionary = MinistriesSimScript.ensure_ministries(state)
	var interior: MinistryState = ministries["Interior"]

	var at_baseline: Array = MinistriesSimScript.operating_capacity(state, interior)
	t.near(float(at_baseline[2]), 1.0, 0.001, "funding_ratio is 1.0 at baseline")

	state.active_budget.allocations["state_administration"] = 150.0
	var above: Array = MinistriesSimScript.operating_capacity(state, interior)
	t.near(float(above[2]), 1.5, 0.001, "funding_ratio reflects the raised allocation")
	t.truth(float(above[0]) > float(at_baseline[0]), "capacity rises with a higher funding ratio")

	state.active_budget.allocations["state_administration"] = 50.0
	var below: Array = MinistriesSimScript.operating_capacity(state, interior)
	t.near(float(below[2]), 0.5, 0.001, "funding_ratio reflects the lowered allocation")
	t.truth(float(below[0]) < float(at_baseline[0]), "capacity falls with a lower funding ratio")


func _test_capacity_responds_to_minister_quality_and_handles_absence(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	state.active_budget = _synthetic_budget(state.year)
	var ministries: Dictionary = MinistriesSimScript.ensure_ministries(state)
	var interior: MinistryState = ministries["Interior"]

	_clear_ministers(state)
	var no_minister: Array = MinistriesSimScript.operating_capacity(state, interior)
	t.truth(no_minister[0] != null, "operating_capacity does not crash with no minister assigned")

	_clear_ministers(state)
	_assign_minister(state, "Interior", 0.0, 0.0)
	var bad_minister: Array = MinistriesSimScript.operating_capacity(state, interior)

	_clear_ministers(state)
	_assign_minister(state, "Interior", 1.0, 1.0)
	var good_minister: Array = MinistriesSimScript.operating_capacity(state, interior)

	t.truth(float(bad_minister[0]) < float(no_minister[0]),
		"a bad minister gives less capacity than no minister at all (fallback quality 0.35 beats 0.0)")
	t.truth(float(no_minister[0]) < float(good_minister[0]),
		"no minister gives less capacity than a fully competent, loyal one")


func _test_minister_quality_ignores_faction_affiliation(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	state.active_budget = _synthetic_budget(state.year)
	var ministries: Dictionary = MinistriesSimScript.ensure_ministries(state)
	var interior: MinistryState = ministries["Interior"]

	_clear_ministers(state)
	_assign_minister(state, "Interior", 0.7, 0.6, "totally-made-up-faction-id")
	var capacity_a: Array = MinistriesSimScript.operating_capacity(state, interior)

	_clear_ministers(state)
	_assign_minister(state, "Interior", 0.7, 0.6, state.player.faction_id)
	var capacity_b: Array = MinistriesSimScript.operating_capacity(state, interior)

	t.near(float(capacity_a[0]), float(capacity_b[0]), 0.0001,
		"capacity depends only on the assigned minister's own competence/loyalty, not their faction")


func _test_capacity_responds_to_bureaucratic_capacity(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	state.active_budget = _synthetic_budget(state.year)
	var ministries: Dictionary = MinistriesSimScript.ensure_ministries(state)
	var interior: MinistryState = ministries["Interior"]
	_clear_ministers(state)
	_assign_minister(state, "Interior", 0.6, 0.6)

	state.country.bureaucratic_capacity = 0.25
	var low: Array = MinistriesSimScript.operating_capacity(state, interior)
	state.country.bureaucratic_capacity = 1.0
	var high: Array = MinistriesSimScript.operating_capacity(state, interior)

	t.truth(float(low[0]) < float(high[0]), "capacity rises with bureaucratic capacity")


func _test_capacity_responds_to_stability(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	state.active_budget = _synthetic_budget(state.year)
	var ministries: Dictionary = MinistriesSimScript.ensure_ministries(state)
	var interior: MinistryState = ministries["Interior"]
	_clear_ministers(state)
	_assign_minister(state, "Interior", 0.6, 0.6)

	state.stability_value = 0.0
	var low: Array = MinistriesSimScript.operating_capacity(state, interior)
	state.stability_value = 1.0
	var high: Array = MinistriesSimScript.operating_capacity(state, interior)

	t.truth(float(low[0]) < float(high[0]), "capacity rises with government stability")


func _test_workload_sources_on_a_fresh_campaign(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var expected_rp := (_population_pressure(state, content) - 0.45) * 0.90
	for portfolio in ALL_PORTFOLIOS:
		var breakdown: Dictionary = MinistriesSimScript.workload_breakdown(state, portfolio)
		t.near(float(breakdown.get("ordinary administration", -1.0)), MinistriesSimScript.BASE_WORKLOAD, 0.0001,
			"%s ordinary administration matches BASE_WORKLOAD" % portfolio)
		if portfolio == "Interior":
			t.equal(breakdown.size(), 2, "Interior also carries the seeded regional-pressure source")
			t.near(float(breakdown.get("regional pressure", -1.0)), expected_rp, 0.0001,
				"Interior regional pressure matches the seeded mean pressure")
		else:
			t.equal(breakdown.size(), 1, "%s has only the ordinary-administration source on a fresh campaign" % portfolio)


func _test_workload_counts_treaties_and_sanctions_for_foreign_affairs_only(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var relation_ids: Array = state.country.relations.keys()
	t.truth(not relation_ids.is_empty(), "sanity: the player country has relations")
	if relation_ids.is_empty():
		return
	relation_ids.sort()
	var rel_a: Country.BilateralRelation = state.country.relations[relation_ids[0]]
	rel_a.sanctioned = true
	rel_a.treaties = [{"type": "trade"}, {"type": "defense"}]

	var fa_breakdown: Dictionary = MinistriesSimScript.workload_breakdown(state, "Foreign Affairs")
	t.near(float(fa_breakdown.get("treaties", -1.0)), 2.0 * 0.10, 0.0001, "two treaties cost 0.10 each")
	t.near(float(fa_breakdown.get("sanctions", -1.0)), 1.0 * 0.22, 0.0001, "one sanctioned relation costs 0.22")

	var interior_breakdown: Dictionary = MinistriesSimScript.workload_breakdown(state, "Interior")
	t.truth(not interior_breakdown.has("treaties"), "treaties workload is Foreign-Affairs-only")
	t.truth(not interior_breakdown.has("sanctions"), "sanctions workload is Foreign-Affairs-only")


func _test_workload_counts_debt_administration_for_finance_only(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	state.country.economy.loans = [{"amount": 10.0}, {"amount": 20.0}, {"amount": 5.0}]

	var finance_breakdown: Dictionary = MinistriesSimScript.workload_breakdown(state, "Finance")
	t.near(float(finance_breakdown.get("debt administration", -1.0)), 3.0 * 0.12, 0.0001,
		"three loans cost 0.12 each")
	var justice_breakdown: Dictionary = MinistriesSimScript.workload_breakdown(state, "Justice")
	t.truth(not justice_breakdown.has("debt administration"), "debt administration workload is Finance-only")


func _test_workload_counts_civil_war_crisis_load_per_portfolio(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	state.civil_war = true
	for portfolio in ALL_PORTFOLIOS:
		var breakdown: Dictionary = MinistriesSimScript.workload_breakdown(state, portfolio)
		var expected: float = MinistriesSimScript.CIVIL_WAR_CRISIS_LOAD.get(portfolio, 0.0)
		t.near(float(breakdown.get("civil war", -1.0)), expected,
			0.0001, "%s civil-war crisis load matches the authored table" % portfolio)


func _test_workload_counts_regional_pressure_for_interior_above_threshold(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var r1 := RegionState.new()
	r1.id = "r1"
	r1.pressure = 0.6
	var r2 := RegionState.new()
	r2.id = "r2"
	r2.pressure = 0.8
	state.regions = {"r1": r1, "r2": r2}

	var interior_breakdown: Dictionary = MinistriesSimScript.workload_breakdown(state, "Interior")
	t.near(float(interior_breakdown.get("regional pressure", -1.0)), (0.70 - 0.45) * 0.90, 0.0001,
		"regional pressure above the 0.45 threshold adds workload")

	var economy_breakdown: Dictionary = MinistriesSimScript.workload_breakdown(state, "Economy")
	t.truth(not economy_breakdown.has("regional pressure"), "regional pressure workload is Interior-only")


func _test_workload_counts_active_regional_programmes(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var definitions: Dictionary = content["catalogs"]["regions_and_programs"]["regional_programs"]
	var programme_id: String = String(definitions.keys()[0])
	var definition: Dictionary = definitions[programme_id]
	var programme := RegionState.RegionalProgram.new()
	programme.id = "workload-programme"
	programme.program_id = programme_id
	programme.region_id = "anera"
	state.regional_programs = [programme]
	var owner: String = String(definition["portfolio"])
	var breakdown: Dictionary = MinistriesSimScript.workload_breakdown(state, owner)
	t.near(float(breakdown.get("regional programmes", 0.0)), 0.48, 0.0001,
		"an active programme adds 0.48 workload to its owning portfolio")
	for portfolio in ALL_PORTFOLIOS:
		if portfolio != owner:
			t.truth(not MinistriesSimScript.workload_breakdown(state, portfolio).has("regional programmes"),
				"programme workload stays with its owning portfolio: " + portfolio)

func _test_workload_ignores_regional_pressure_below_threshold(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var r1 := RegionState.new()
	r1.id = "r1"
	r1.pressure = 0.2
	state.regions = {"r1": r1}

	var interior_breakdown: Dictionary = MinistriesSimScript.workload_breakdown(state, "Interior")
	t.truth(not interior_breakdown.has("regional pressure"), "pressure at/under 0.45 adds no workload")


func _test_simulate_recovers_backlog_gradually_when_capacity_exceeds_workload(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	state.country.bureaucratic_capacity = 1.0
	state.stability_value = 1.0
	_clear_ministers(state)
	_assign_minister(state, "Interior", 1.0, 1.0)
	state.active_budget = _synthetic_budget(state.year)
	state.active_budget.allocations["state_administration"] = 100.0
	var ministries: Dictionary = MinistriesSimScript.ensure_ministries(state)
	var interior: MinistryState = ministries["Interior"]
	var workload := 0.65 + (_population_pressure(state, content) - 0.45) * 0.90
	interior.backlog = 3.0
	interior.months_overloaded = 2

	MinistriesSimScript.simulate(state)

	var recovered: float = minf(3.0, (1.45 - workload) * 0.22)
	t.near(interior.capacity, 1.45, 0.01, "capacity matches the hand-computed value")
	t.near(interior.workload, workload, 0.0001, "workload is ordinary administration plus seeded regional pressure")
	t.near(interior.backlog, 3.0 - recovered, 0.001,
		"backlog clears by only the bounded recovered share, not instantly to zero")
	t.truth(interior.backlog > 2.5, "a large backlog does not clear in a single turn even with spare capacity")
	t.equal(interior.delivery, 1.0, "delivery is full once served demand meets capacity")
	t.equal(interior.months_overloaded, 1, "months_overloaded decrements by one turn of non-overload")


func _test_simulate_grows_backlog_and_months_overloaded_when_capacity_falls_short(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	state.country.bureaucratic_capacity = 1.0
	state.stability_value = 1.0
	_clear_ministers(state)
	_assign_minister(state, "Defense", 1.0, 1.0)
	state.active_budget = _synthetic_budget(state.year)
	state.active_budget.allocations["national_defense"] = 120.0
	state.civil_war = true
	var ministries: Dictionary = MinistriesSimScript.ensure_ministries(state)
	var defense: MinistryState = ministries["Defense"]
	defense.backlog = 1.0
	defense.months_overloaded = 0

	MinistriesSimScript.simulate(state)

	t.near(defense.capacity, 1.45, 0.01, "capacity matches the hand-computed value")
	t.near(defense.workload, 1.65, 0.0001, "workload includes the civil-war crisis load")
	t.near(defense.backlog, 1.0 + defense.workload - defense.capacity, 0.001, "backlog grows by exactly the shortfall")
	t.equal(defense.months_overloaded, 1, "months_overloaded increments while overloaded")
	t.truth(defense.delivery < 1.0, "delivery is degraded while overloaded")


func _test_simulate_clamps_backlog_at_max(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	state.country.bureaucratic_capacity = 1.0
	state.stability_value = 1.0
	_clear_ministers(state)
	_assign_minister(state, "Defense", 1.0, 1.0)
	state.active_budget = _synthetic_budget(state.year)
	state.active_budget.allocations["national_defense"] = 120.0
	state.civil_war = true
	var ministries: Dictionary = MinistriesSimScript.ensure_ministries(state)
	var defense: MinistryState = ministries["Defense"]
	defense.backlog = MinistriesSimScript.MAX_BACKLOG - 0.1

	MinistriesSimScript.simulate(state)

	t.equal(defense.backlog, MinistriesSimScript.MAX_BACKLOG, "backlog never exceeds MAX_BACKLOG")


func _test_simulate_updates_workload_breakdown_snapshot(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	state.civil_war = true
	MinistriesSimScript.simulate(state)
	var defense: MinistryState = state.ministries["Defense"]
	t.truth(defense.workload_breakdown.has("civil war"), "simulate() persists the workload breakdown onto the ministry")
	t.near(float(defense.workload_breakdown.get("civil war", -1.0)), 1.00, 0.0001,
		"persisted breakdown matches Defense's crisis load")


func _test_funding_curve_has_three_zones(t, _content: Dictionary) -> void:
	var f := func(r: float) -> float: return MinistriesSimScript.funding_factor(r)
	t.truth(f.call(0.30) < f.call(0.60) * 0.6,
		"below the operating minimum a department loses capacity fast (%.2f at 30%%)" % f.call(0.30))
	t.near(f.call(1.0), 1.0, 1e-9, "full funding is full capacity")
	t.truth(f.call(1.5) - f.call(1.0) < f.call(1.0) - f.call(0.6),
		"money above full funding buys less than money below it")
	t.truth(f.call(2.0) - f.call(1.5) < f.call(1.5) - f.call(1.0), "and keeps buying less")
	t.truth(f.call(10.0) <= 1.0 + MinistriesSimScript.MAX_FUNDING_BONUS, "with a firm ceiling")
	t.truth(f.call(0.0) >= 0.0, "and no negative capacity")


func _test_starved_ministry_delivers_materially_less(t, content: Dictionary) -> void:
	var funded: GameState = GameFactoryScript.new_campaign(content, _base_config())
	var starved: GameState = GameFactoryScript.new_campaign(content, _base_config())
	for s in [funded, starved]:
		BudgetSim.ensure_budget_state(s)
		MinistriesSimScript.ensure_ministries(s)
	for key in starved.active_budget.allocations.keys():
		starved.active_budget.allocations[key] = float(starved.active_budget.allocations[key]) * 0.40
	MinistriesSimScript.simulate(funded)
	MinistriesSimScript.simulate(starved)
	var a: MinistryState = funded.ministries["Interior"]
	var b: MinistryState = starved.ministries["Interior"]
	t.truth(b.capacity < a.capacity * 0.6,
		"a department on 40%% of its budget has well under 60%% of the capacity (%.2f vs %.2f)" % [b.capacity, a.capacity])
	t.truth(b.delivery < a.delivery, "and delivers less")


func _test_good_minister_cannot_rescue_a_starved_department(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	_clear_ministers(state)
	_assign_minister(state, "Defense", 1.0, 1.0)
	state.active_budget = _synthetic_budget(state.year)
	var ministries: Dictionary = MinistriesSimScript.ensure_ministries(state)
	var defense: MinistryState = ministries["Defense"]
	var starved_best := MinistriesSimScript.operating_capacity(state, defense)
	state.active_budget.allocations["national_defense"] = float(state.active_budget.allocations["national_defense"]) * 0.30
	starved_best = MinistriesSimScript.operating_capacity(state, defense)
	_clear_ministers(state)
	_assign_minister(state, "Defense", 0.5, 0.5)
	state.active_budget = _synthetic_budget(state.year)
	var funded_average := MinistriesSimScript.operating_capacity(state, defense)
	t.truth(float(starved_best[0]) < float(funded_average[0]),
		"the best possible minister on 30%% funding does worse than an ordinary one fully funded (%.2f vs %.2f)" % [float(starved_best[0]), float(funded_average[0])])


func _test_flat_money_falls_behind_a_growing_economy(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	BudgetSim.ensure_budget_state(state)
	MinistriesSimScript.ensure_ministries(state)
	var frozen := state.active_budget.allocations.duplicate()
	MinistriesSimScript.simulate(state)
	var ratio0: float = (state.ministries["Finance"] as MinistryState).funding_ratio
	for _i in range(60):
		state.active_budget.allocations = frozen.duplicate()
		MinistriesSimScript.simulate(state)
	var ratio5: float = (state.ministries["Finance"] as MinistryState).funding_ratio
	t.truth(ratio5 < ratio0 - 0.05,
		"five years of unchanged money is a real cut once the economy has grown (%.3f -> %.3f)" % [ratio0, ratio5])
	t.truth(ratio5 < 1.0, "so no ministry drifts into permanent free surplus capacity")


func _initialize() -> void:
	var t = TestSupportScript.new()

	var content: Dictionary = ContentRepositoryScript.load_all()
	t.truth(not content.has("error"), "content loads for the ministries tests")

	if not content.has("error"):
		_test_ensure_ministries_seeds_every_core_portfolio(t, content)
		_test_ensure_ministries_reflects_real_funding_once_budgeted(t, content)
		_test_ensure_ministries_backfills_without_clobbering_existing(t, content)

		_test_capacity_responds_to_funding_ratio(t, content)

		_test_capacity_responds_to_minister_quality_and_handles_absence(t, content)
		_test_minister_quality_ignores_faction_affiliation(t, content)

		_test_capacity_responds_to_bureaucratic_capacity(t, content)
		_test_capacity_responds_to_stability(t, content)

		_test_workload_sources_on_a_fresh_campaign(t, content)
		_test_workload_counts_treaties_and_sanctions_for_foreign_affairs_only(t, content)
		_test_workload_counts_debt_administration_for_finance_only(t, content)
		_test_workload_counts_civil_war_crisis_load_per_portfolio(t, content)
		_test_workload_counts_regional_pressure_for_interior_above_threshold(t, content)
		_test_workload_counts_active_regional_programmes(t, content)
		_test_workload_ignores_regional_pressure_below_threshold(t, content)

		_test_simulate_recovers_backlog_gradually_when_capacity_exceeds_workload(t, content)
		_test_simulate_grows_backlog_and_months_overloaded_when_capacity_falls_short(t, content)
		_test_simulate_clamps_backlog_at_max(t, content)
		_test_simulate_updates_workload_breakdown_snapshot(t, content)
		_test_funding_curve_has_three_zones(t, content)
		_test_starved_ministry_delivers_materially_less(t, content)
		_test_good_minister_cannot_rescue_a_starved_department(t, content)
		_test_flat_money_falls_behind_a_growing_economy(t, content)

	quit(t.finish())
