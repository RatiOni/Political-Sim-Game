extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")


static func _state() -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "contextual", "seed": 424242})
	BudgetSim.ensure_budget_state(state)
	return state


static func _national(state: GameState) -> float:
	var total := 0.0
	for r in state.regions.values():
		total += (r as RegionState).population
	return total


func _initialize() -> void:
	var t = TestSupportScript.new()

	var s := _state()
	t.near(_national(s), 8500.0, 1.0, "regions are seeded with Ardenia's 8.5 million people")
	t.near(RegionsSim.population_weight(s, "vashtera"), 0.22, 0.001, "seeded shares match the authored weights")
	for r in s.regions.values():
		t.truth((r as RegionState).development > 0.0 and (r as RegionState).development < 1.0, "%s starts partly developed" % (r as RegionState).id)
	t.truth((s.regions["vashtera"] as RegionState).development > (s.regions["anera"] as RegionState).development,
		"the capital starts more developed than the absent-state highlands")

	var natural := _state()
	var n0 := _national(natural)
	for _i in range(12):
		RegionsSim.simulate(natural)
	t.truth(_national(natural) > n0, "the country grows by natural increase")
	t.near(_national(natural), n0 * (1.0 + RegionsSim.NATURAL_GROWTH_PER_YEAR), n0 * 0.002,
		"and only by natural increase: migration moves people, it does not create them")

	var move := _state()
	(move.regions["zavost"] as RegionState).unemployment = 0.30
	(move.regions["sela"] as RegionState).unemployment = 0.04
	var z0 := RegionsSim.population_weight(move, "zavost")
	var se0 := RegionsSim.population_weight(move, "sela")
	for _i in range(24):
		RegionsSim.simulate(move)
		(move.regions["zavost"] as RegionState).unemployment = 0.30
		(move.regions["sela"] as RegionState).unemployment = 0.04
	t.truth(RegionsSim.population_weight(move, "zavost") < z0, "people leave a region without work")
	t.truth(RegionsSim.population_weight(move, "sela") > se0, "and move to one with jobs")

	var served := _state()
	var neglected := _state()
	for m in neglected.ministries.values():
		(m as MinistryState).delivery = 0.2
	for _i in range(60):
		RegionsSim.simulate(served)
		RegionsSim.simulate(neglected)
		for m in neglected.ministries.values():
			(m as MinistryState).delivery = 0.2
	t.truth((served.regions["sela"] as RegionState).development > (neglected.regions["sela"] as RegionState).development,
		"a state that delivers develops its regions; a failing one does not")

	var war := _state()
	var d0 := (war.regions["orvena"] as RegionState).development
	war.civil_war = true
	war.insurgency_pressure = 0.9
	for _i in range(36):
		RegionsSim.simulate(war)
	t.truth((war.regions["orvena"] as RegionState).development < d0, "war undoes development")

	var held := _state()
	var v0 := RegionsSim.population_weight(held, "vetrenka")
	(held.regions["vetrenka"] as RegionState).unemployment = 0.02
	for _i in range(24):
		RegionsSim.simulate(held)
		(held.regions["vetrenka"] as RegionState).unemployment = 0.02
	t.truth(RegionsSim.population_weight(held, "vetrenka") <= v0 + 1e-6, "nobody migrates across the ceasefire line toward opportunity")

	var feedback := _state()
	var reach0 := (feedback.regions["darev"] as RegionState).state_reach
	(feedback.regions["darev"] as RegionState).development = 0.95
	for _i in range(24):
		RegionsSim.simulate(feedback)
		(feedback.regions["darev"] as RegionState).development = 0.95
	var plain := _state()
	for _i in range(24):
		RegionsSim.simulate(plain)
	t.truth((feedback.regions["darev"] as RegionState).state_reach > (plain.regions["darev"] as RegionState).state_reach,
		"a developed region is easier for the state to reach")

	var long := _state()
	var ok := true
	for _i in range(480):
		RegionsSim.simulate(long)
		for r in long.regions.values():
			var region := r as RegionState
			if not is_finite(region.population) or region.population <= 0.0 or region.development < 0.0 or region.development > 1.0:
				ok = false
	t.truth(ok, "forty years keep population positive and development within 0..1")

	var saved := _state()
	(saved.regions["kelvet"] as RegionState).population = 612.5
	(saved.regions["kelvet"] as RegionState).development = 0.41
	var copy := GameState.from_dict(saved.to_dict())
	t.near((copy.regions["kelvet"] as RegionState).population, 612.5, 1e-9, "population round-trips")
	t.near((copy.regions["kelvet"] as RegionState).development, 0.41, 1e-9, "development round-trips")
	(saved.regions["kelvet"] as RegionState).development = 1.4
	t.truth(StateValidator.validate(saved).size() > 0, "an impossible development level is rejected")

	var game = load("res://scripts/native/native_game.gd").new()
	game.new_campaign({"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "contextual", "seed": 7})
	var row: Dictionary = game.snapshot()["regions"][0]
	t.truth(row.has("population") and row.has("development"), "the snapshot carries population and development for the map")
	game.free()
	quit(t.finish())
