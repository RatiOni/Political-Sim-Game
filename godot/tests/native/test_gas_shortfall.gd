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


static func _short(state: GameState, shortfall: float, severity: float) -> void:
	state.foreign.gas.last_flow = {"shortfall": shortfall, "severity": severity}


func _test_exposure_shapes_the_regional_shortfall(t) -> void:
	var state := _state()
	_short(state, 0.2, 0.2)
	t.near(GasSim.region_shortfall(state, "zavost"), 0.3, 0.000001, "industrial Zavost feels half again the national shortfall")
	t.near(GasSim.region_shortfall(state, "vashtera"), 0.2, 0.000001, "an unlisted region feels the national figure")
	t.near(GasSim.region_shortfall(state, "vetrenka"), 0.0, 0.000001, "territory outside state control is not on Ardenia's network")
	_short(state, 0.9, 0.9)
	t.near(GasSim.region_shortfall(state, "zavost"), 1.0, 0.000001, "and no region is more than wholly short")
	var supply := GasSim.supply_by_region(state)
	t.equal(supply.size(), state.regions.size(), "the map gets a supply ratio for every region")
	t.truth(supply.values().all(func(v) -> bool: return float(v) >= 0.0 and float(v) <= 1.0), "each within 0..1")


func _test_a_shortfall_raises_heating_hardship(t) -> void:
	var calm := _state()
	var cold := _state()
	_short(cold, 0.4, 0.4)
	for _i in range(6):
		HouseholdsSim.simulate(calm)
		HouseholdsSim.simulate(cold)
	t.truth(HouseholdsSim.regional_hardship(cold, "zavost") > HouseholdsSim.regional_hardship(calm, "zavost") + 0.05,
		"six cold months raise hardship in Zavost")
	t.truth(HouseholdsSim.regional_confidence(cold, "zavost") < HouseholdsSim.regional_confidence(calm, "zavost"),
		"and cost household confidence")


func _test_a_shortfall_idles_zavost_and_darev(t) -> void:
	var calm := _state()
	var cold := _state()
	_short(cold, 0.4, 0.4)
	for _i in range(6):
		RegionsSim.simulate(calm)
		RegionsSim.simulate(cold)
	for id in ["zavost", "darev"]:
		t.truth((cold.regions[id] as RegionState).unemployment > (calm.regions[id] as RegionState).unemployment,
			"%s's plants lay workers off without gas" % id)
	t.near((cold.regions["vashtera"] as RegionState).unemployment, (calm.regions["vashtera"] as RegionState).unemployment, 0.000001,
		"the capital loses no industrial jobs")
	t.truth((cold.regions["vashtera"] as RegionState).state_reach < (calm.regions["vashtera"] as RegionState).state_reach,
		"but the state reaches less of it")


func _test_growth_reads_shortfall_and_price(t) -> void:
	var state := _state()
	_short(state, 0.5, 0.5)
	t.near(GasSim.growth_effect(state), -0.03, 0.000001, "a severe shortfall costs three points of annualised growth")
	_short(state, 0.0, 0.0)
	state.foreign.gas.price = GasSim.union_cap(state.foreign.gas)
	t.near(GasSim.growth_effect(state), 0.003, 0.000001, "gas 30% under the reference lifts growth")
	state.foreign.gas.price = 60.0
	t.near(GasSim.growth_effect(state), -0.002, 0.000001, "and dear gas drags it")
	state.foreign.gas.price = 50.0
	EconomySim._apply_headline_stats(state)
	var normal := state.country.economy.growth_rate
	_short(state, 0.5, 0.5)
	EconomySim._apply_headline_stats(state)
	t.near(normal - state.country.economy.growth_rate, 0.03, 0.000001, "the economy books it")


func _test_stability_counts_the_cold(t) -> void:
	var state := _state()
	_short(state, 0.5, 0.25)
	t.near(float(StabilitySim.stability_breakdown(state)["Energy supply"]), -0.025, 0.000001, "a shortfall is a named stability drag weighted by severity")
	_short(state, 0.0, 0.0)
	t.near(float(StabilitySim.stability_breakdown(state)["Energy supply"]), 0.0, 0.000001, "full supply costs nothing")


func _test_storage_buffers_a_real_winter(t) -> void:
	var bare := _state()
	var stored := _state()
	for s in [bare, stored]:
		while s.month != 12:
			NativeGameScript.next_month(s)
	stored.foreign.gas.storage_target = 1.0
	stored.foreign.gas.storage_capacity = 1.0
	stored.foreign.gas.storage = 1.0
	var hardship := HouseholdsSim.regional_hardship(bare, "zavost")
	for s in [bare, stored]:
		s.foreign.gas.cut = 0.4
		s.foreign.gas.cut_until = s.turn + 12
		NativeGameScript.next_month(s)
	t.equal(bare.month, 1, "the cut lands in January")
	t.truth(GasSim.national_severity(stored) < GasSim.national_severity(bare), "storage softens the winter cut")
	t.truth(HouseholdsSim.regional_hardship(bare, "zavost") > hardship, "and the unbuffered winter hurts Zavost's households at once")


func _test_effects_vanish_at_full_supply_and_read_severity(t) -> void:
	var state := _state()
	_short(state, 0.0, 0.0)
	for id in ["zavost", "vashtera"]:
		t.near(GasSim.heating_hardship(state, id) + GasSim.reach_loss(state, id) + GasSim.industry_jobs_loss(state, id), 0.0, 0.000001, "full supply leaves %s untouched" % id)
	t.near(GasSim.stability_drag(state), 0.0, 0.000001, "full supply drags nothing")
	_short(state, 0.02, 0.01)
	t.near(GasSim.heating_hardship(state, "vashtera"), 0.0025, 0.000001, "the slightest shortfall is already felt")
	t.near(GasSim.stability_drag(state), 0.001, 0.000001, "and already drags")
	_short(state, 0.4, 0.2)
	t.near(GasSim.heating_hardship(state, "vashtera"), 0.05, 0.000001, "hardship follows the season-weighted severity, not the raw gap")
	t.near(GasSim.reach_loss(state, "vashtera"), 0.03, 0.000001, "and so does state reach")
	t.near(GasSim.industry_jobs_loss(state, "zavost"), 0.018, 0.000001, "and so do the plants")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_exposure_shapes_the_regional_shortfall(t)
	_test_a_shortfall_raises_heating_hardship(t)
	_test_a_shortfall_idles_zavost_and_darev(t)
	_test_growth_reads_shortfall_and_price(t)
	_test_stability_counts_the_cold(t)
	_test_storage_buffers_a_real_winter(t)
	_test_effects_vanish_at_full_supply_and_read_severity(t)
	quit(t.finish())
