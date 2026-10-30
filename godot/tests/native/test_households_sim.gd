extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")
const GameFactoryScript = preload("res://scripts/native/state/game_factory.gd")
const RegionsSimScript = preload("res://scripts/native/sim/regions_sim.gd")
const BudgetSimScript = preload("res://scripts/native/sim/budget_sim.gd")
const HouseholdsSimScript = preload("res://scripts/native/sim/households_sim.gd")


func _campaign(content: Dictionary, country_id: String = "ardenia") -> GameState:
	var state: GameState = GameFactoryScript.new_campaign(content, {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "contextual", "seed": 424242,
	})
	if country_id != "ardenia":
		for actor in state.world:
			if actor.id == country_id:
				state.country = actor
				break
	RegionsSimScript.ensure_region_states(state)
	return state


func _seeded(content: Dictionary) -> GameState:
	var state := _campaign(content)
	HouseholdsSimScript.ensure_households(state)
	return state


func _test_seeding(t, content: Dictionary) -> void:
	var state := _campaign(content)
	var before := state.to_dict()
	t.equal(HouseholdsSimScript.national_confidence(state), 0.5, "empty confidence fallback")
	t.equal(HouseholdsSimScript.national_real_income(state), 1.0, "empty real-income fallback")
	t.equal(HouseholdsSimScript.national_living_cost(state), 1.0, "empty living-cost fallback")
	t.equal(HouseholdsSimScript.national_hardship(state), 0.0, "empty hardship fallback")
	t.equal(HouseholdsSimScript.national_service_access(state), 0.0, "empty service fallback")
	t.equal(HouseholdsSimScript.regional_confidence(state, "vashtera"), 0.0, "empty regional fallback")
	t.equal(HouseholdsSimScript.hardest_hit(state).size(), 0, "empty hardest-hit list")
	t.equal(state.to_dict(), before, "aggregate readers never seed or mutate an empty ledger")
	HouseholdsSimScript.ensure_households(state)
	t.equal(state.households.size(), 60, "six groups in ten regions")
	var shares: Dictionary = content["catalogs"]["household_groups"]["regional_shares"]
	var repeat := _seeded(content)
	for rid in shares:
		for gid in shares[rid]:
			var key: String = "%s:%s" % [rid, gid]
			t.truth(state.households.has(key), "stable household key " + key)
			if not state.households.has(key):
				continue
			var h: HouseholdGroupState = state.households[key]
			t.equal(h.id, key, "record id " + key)
			t.equal(h.region_id, rid, "region id " + key)
			t.equal(h.group_id, gid, "group id " + key)
			t.near(h.population_share, float(shares[rid][gid]), 0.000001, "authored share " + key)
			t.equal(h.to_dict(), repeat.households[key].to_dict(), "deterministic seed " + key)
	var preserved: HouseholdGroupState = state.households["vashtera:urban_workers"]
	preserved.nominal_income_index = 1.23
	preserved.living_cost_index = 1.44
	preserved.real_income_index = 0.85
	preserved.last_real_income_index = 0.83
	preserved.employment_security = 0.37
	preserved.service_access = 0.61
	preserved.hardship = 0.56
	preserved.confidence = 0.29
	var history := preserved.to_dict()
	state.households.erase("darev:pensioners")
	HouseholdsSimScript.ensure_households(state)
	t.equal(state.households.size(), 60, "missing record backfilled")
	t.truth(state.households[preserved.id] == preserved, "existing object retained")
	t.equal(preserved.to_dict(), history, "all accumulated history retained")
	before = state.to_dict()
	HouseholdsSimScript.ensure_households(state)
	t.equal(state.to_dict(), before, "repeated ensure is idempotent")
	var no_regions := _campaign(content)
	no_regions.regions.clear()
	HouseholdsSimScript.ensure_households(no_regions)
	t.truth(no_regions.households.is_empty(), "no invented regions in household seeding")
	for country in content["countries"]:
		var country_id: String = String(country)
		if country_id == "ardenia":
			continue
		var foreign := _campaign(content, country_id)
		HouseholdsSimScript.ensure_households(foreign)
		HouseholdsSimScript.simulate(foreign)
		t.truth(foreign.households.is_empty(), "foreign ledger stays empty: " + country_id)
	var lazy := _campaign(content)
	HouseholdsSimScript.simulate(lazy)
	t.equal(lazy.households.size(), 60, "simulate seeds after regions exist")
	t.truth(lazy.households["vashtera:urban_workers"].living_cost_index != 1.0,
		"first simulate also applies the monthly pulse")


func _test_directions(t, content: Dictionary) -> void:
	for driver in ["inflation", "growth", "unemployment", "reach", "agriculture"]:
		var low := _seeded(content)
		var high := _seeded(content)
		if driver == "inflation":
			low.country.economy.inflation = 0.0
			high.country.economy.inflation = 0.60
		elif driver == "growth":
			low.country.economy.growth_rate = -0.20
			high.country.economy.growth_rate = 0.20
		elif driver == "agriculture":
			low.country.economy.sector_by_id("agriculture").growth_rate = -0.20
			high.country.economy.sector_by_id("agriculture").growth_rate = 0.20
		elif driver == "unemployment":
			low.regions["vashtera"].unemployment = 0.03
			high.regions["vashtera"].unemployment = 0.40
		else:
			low.regions["vashtera"].state_reach = 0.10
			high.regions["vashtera"].state_reach = 0.95
		for month in range(6):
			HouseholdsSimScript.simulate(low)
			HouseholdsSimScript.simulate(high)
		var a: HouseholdGroupState = low.households["vashtera:urban_workers"]
		var b: HouseholdGroupState = high.households[a.id]
		if driver == "inflation":
			t.truth(b.living_cost_index > a.living_cost_index, "inflation raises living costs")
			t.truth(b.nominal_income_index > a.nominal_income_index, "income partly indexes to inflation")
			t.truth(b.real_income_index < a.real_income_index, "prices outrun indexed wages")
			t.truth(b.hardship > a.hardship and b.confidence < a.confidence, "inflation hardship and confidence")
		elif driver == "growth":
			t.truth(b.nominal_income_index > a.nominal_income_index and b.real_income_index > a.real_income_index,
				"growth improves nominal and real income")
			t.truth(b.hardship < a.hardship and b.confidence > a.confidence, "growth eases hardship and improves confidence")
		elif driver == "unemployment":
			t.truth(b.employment_security < a.employment_security, "local unemployment erodes security")
			t.truth(b.nominal_income_index < a.nominal_income_index, "local unemployment erodes income")
			t.truth(b.hardship > a.hardship and b.confidence < a.confidence, "unemployment hardship and confidence")
		elif driver == "reach":
			t.truth(b.service_access > a.service_access, "state reach improves services")
			t.truth(b.hardship < a.hardship and b.confidence > a.confidence, "reach eases hardship and improves confidence")
		else:
			t.truth(high.households["vashtera:rural_households"].real_income_index >
				low.households["vashtera:rural_households"].real_income_index, "rural income reads agriculture growth")
			t.equal(b.real_income_index, a.real_income_index, "agriculture does not replace urban growth")
	var fallback := _seeded(content)
	fallback.country.economy.sectors.clear()
	HouseholdsSimScript.simulate(fallback)
	t.truth(fallback.households["vashtera:rural_households"].real_income_index > 0.0,
		"missing agriculture uses the national growth fallback")


func _test_services(t, content: Dictionary) -> void:
	var low := _seeded(content)
	var high := _seeded(content)
	for state in [low, high]:
		BudgetSimScript.ensure_budget_state(state)
		for portfolio in ["Finance", "Interior"]:
			var m := MinistryState.new()
			m.portfolio = portfolio
			m.delivery = 0.2 if state == low else 1.0
			state.ministries[portfolio] = m
	t.truth(HouseholdsSimScript.welfare_delivery(high) > HouseholdsSimScript.welfare_delivery(low),
		"welfare depends on real ministries")
	t.truth(HouseholdsSimScript.education_delivery(high) > HouseholdsSimScript.education_delivery(low),
		"education depends on real ministries")
	for month in range(12):
		HouseholdsSimScript.simulate(low)
		HouseholdsSimScript.simulate(high)
	t.truth(high.households["vashtera:pensioners"].employment_security >
		low.households["vashtera:pensioners"].employment_security, "pensioner security follows welfare delivery")
	t.truth(high.households["vashtera:insecure_households"].nominal_income_index >
		low.households["vashtera:insecure_households"].nominal_income_index, "welfare improves dependent income indexation")
	var original_delivery: float = HouseholdsSimScript.welfare_delivery(high)
	high.active_budget.allocations["health_and_welfare"] *= 0.5
	t.truth(HouseholdsSimScript.welfare_delivery(high) < original_delivery, "budget envelope constrains welfare")
	high.regions["vetrenka"].state_reach = 1.0
	for month in range(24):
		HouseholdsSimScript.simulate(high)
	for h in high.households.values():
		if h.region_id == "vetrenka":
			t.truth(h.service_access <= 0.15 + 0.000001, "separatist service cap: " + h.id)
	t.equal(high.regions["vetrenka"].control, "separatist", "households never change territorial control")


func _test_aggregates(t, content: Dictionary) -> void:
	var state := _seeded(content)
	var sim = HouseholdsSimScript.new()
	var readers := {"hardship": "national_hardship", "confidence": "national_confidence",
		"real_income_index": "national_real_income", "living_cost_index": "national_living_cost",
		"service_access": "national_service_access"}
	for attr in readers:
		for h in state.households.values():
			h.set(attr, 0.0)
		state.households["vashtera:urban_workers"].set(attr, 1.0)
		t.near(sim.call(readers[attr], state), 0.055, 0.000001,
			"authored population and group-share weighting: " + attr)
	t.near(HouseholdsSimScript.regional_hardship(state, "vashtera"), 0.25, 0.000001, "regional hardship uses group shares")
	t.near(HouseholdsSimScript.regional_confidence(state, "vashtera"), 0.25, 0.000001, "regional confidence uses group shares")
	t.near(HouseholdsSimScript.regional_service_access(state, "vashtera"), 0.25, 0.000001, "regional services use group shares")
	t.equal(HouseholdsSimScript.regional_hardship(state, "missing"), 0.0, "unknown region reader fallback")
	var before := state.to_dict()
	var ranked: Array = HouseholdsSimScript.hardest_hit(state, 3)
	t.equal(ranked.size(), 3, "hardest-hit limit")
	t.equal(ranked[0].id, "vashtera:urban_workers", "hardest-hit descending order")
	t.equal(HouseholdsSimScript.hardest_hit(state, 0).size(), 0, "zero hardest-hit limit")
	for reader in readers.values():
		sim.call(reader, state)
	t.equal(state.to_dict(), before, "populated aggregate readers are pure")
	state.households.clear()
	var zero := HouseholdGroupState.new()
	zero.id = "unknown:test"
	zero.region_id = "unknown"
	zero.population_share = 1.0
	state.households[zero.id] = zero
	t.equal(HouseholdsSimScript.national_hardship(state), 0.0, "unknown regions contribute no authored weight")


func _assert_household_roundtrip(t, actual: HouseholdGroupState, expected: HouseholdGroupState, label: String) -> void:
	var fields := expected.to_dict()
	for field in fields:
		if fields[field] is float:
			t.near(float(actual.get(field)), float(fields[field]), 0.0000000001, label + ":" + field)
		else:
			t.equal(actual.get(field), fields[field], label + ":" + field)


func _test_history_bounds_and_roundtrip(t, content: Dictionary) -> void:
	var state := _seeded(content)
	var h: HouseholdGroupState = state.households["vashtera:urban_workers"]
	h.real_income_index = 0.87
	HouseholdsSimScript.simulate(state)
	t.equal(h.last_real_income_index, 0.87, "previous real income captured before updating")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var restored := GameState.from_dict(saved)
	t.truth(restored != null, "GameState household roundtrip succeeds")
	if restored == null:
		return
	t.equal(restored.households.size(), 60, "roundtrip retains all households")
	for key in state.households:
		_assert_household_roundtrip(t, restored.households[key], state.households[key], "all household fields roundtrip: " + key)
	HouseholdsSimScript.simulate(state)
	HouseholdsSimScript.simulate(restored)
	for key in state.households:
		_assert_household_roundtrip(t, restored.households[key], state.households[key], "reload continues identically: " + key)
	var orphan: HouseholdGroupState = state.households["darev:pensioners"]
	var orphan_before := orphan.to_dict()
	state.regions.erase("darev")
	HouseholdsSimScript.simulate(state)
	t.equal(orphan.to_dict(), orphan_before, "missing region skips its saved households")
	for extremes in [[5.0, -5.0], [-5.0, 5.0]]:
		state.country.economy.inflation = extremes[0]
		state.country.economy.growth_rate = extremes[1]
		for month in range(48):
			HouseholdsSimScript.simulate(state)
		for item in state.households.values():
			t.truth(item.nominal_income_index >= 0.45 and item.nominal_income_index <= 2.50, "nominal bound " + item.id)
			t.truth(item.living_cost_index >= 0.65 and item.living_cost_index <= 3.50, "cost bound " + item.id)
			t.truth(item.real_income_index >= 0.35 and item.real_income_index <= 2.00, "real-income bound " + item.id)
			for attr in ["employment_security", "service_access", "hardship", "confidence"]:
				t.truth(item.get(attr) >= 0.0 and item.get(attr) <= 1.0, "unit bound " + item.id + ":" + attr)


func _initialize() -> void:
	var t = TestSupportScript.new()
	var content: Dictionary = ContentRepositoryScript.load_all()
	t.truth(not content.has("error"), "household content loads")
	if not content.has("error"):
		_test_seeding(t, content)
		_test_directions(t, content)
		_test_services(t, content)
		_test_aggregates(t, content)
		_test_history_bounds_and_roundtrip(t, content)
	quit(t.finish())
