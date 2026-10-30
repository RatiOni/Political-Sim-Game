extends SceneTree

## Kostrel, the tenth region, end to end: a map region with its canon borders,
## a sim region with households and party support, a line in an election's
## regional breakdown, and population shares that still sum to one.

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_map(t)
	_test_sim(t)
	quit(t.finish())


func _test_map(t) -> void:
	var geo := MapGeometry.load_world()
	t.truth(geo.region_ids.has("kostrel"), "the world file defines Kostrel")
	var rovets: Array = geo.cities.filter(func(c: Dictionary) -> bool: return c["name"] == "Rovets")
	t.equal(rovets.size(), 1, "Rovets is a city on the map")
	t.equal(String(rovets[0]["region"]) if not rovets.is_empty() else "", "kostrel", "and it is Kostrel's city")
	var regions: Image = load("res://data/map/baked/region_ids.png").get_image()
	regions.convert(Image.FORMAT_R8)
	var pairs := MapBaker.adjacent_pairs(regions, geo)
	var kostrel_pairs: Array = pairs.keys().filter(func(p: String) -> bool: return p.split("|").has("kostrel"))
	kostrel_pairs.sort()
	t.equal(kostrel_pairs, ["darev|kostrel", "kostrel|sela", "kostrel|zavost"], "the baked map gives Kostrel exactly its canon borders")
	t.truth(not pairs.has("darev|sela"), "Kostrel now stands between the Sela and Darev")
	t.equal(MapBaker.region_at_map(regions, geo, geo.seeds["kostrel"]), "kostrel", "Kostrel's seed lies inside it")
	var south := 0.0
	var data := regions.get_data()
	var index := geo.region_ids.find("kostrel")
	for i in data.size():
		if data[i] == index:
			south = maxf(south, float(i / MapBaker.RESOLUTION.x) / MapBaker.RESOLUTION.y)
	t.truth(south > 0.85, "Kostrel is a southern lobe reaching well below the Sela (%.2f)" % south)


func _test_sim(t) -> void:
	var content := ContentRepository.load_all()
	var profiles: Dictionary = content["catalogs"]["regions_and_programs"]["region_profiles"]
	var total := 0.0
	for id in profiles:
		total += float(profiles[id]["population_weight"])
	t.near(total, 1.0, 1e-9, "authored population weights still sum to one")

	var state: GameState = GameFactory.new_campaign(content, {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	RegionsSim.ensure_region_states(state)
	HouseholdsSim.ensure_households(state)
	t.equal(state.regions.size(), 10, "a campaign seeds ten regions")
	var kostrel: RegionState = state.regions.get("kostrel")
	t.truth(kostrel != null, "Kostrel is a sim region")
	if kostrel == null:
		return
	t.equal(kostrel.control, "state", "Kostrel is administered by the state")
	t.equal(kostrel.issue_id, "orchard_credit", "and has its own defining issue")
	var support := 0.0
	var top := ""
	for id in kostrel.party_support:
		support += float(kostrel.party_support[id])
	t.near(support, 1.0, 1e-6, "Kostrel's party support is a full distribution")
	t.truth(float(kostrel.party_support["agrarian_union"]) > float(state.regions["vashtera"].party_support["agrarian_union"]) * 3.0,
		"and it leans agrarian")
	var groups := 0
	var share := 0.0
	for key in state.households:
		var h: HouseholdGroupState = state.households[key]
		if h.region_id == "kostrel":
			groups += 1
			share += h.population_share
	t.equal(groups, 6, "Kostrel has six household groups")
	t.near(share, 1.0, 1e-6, "whose shares cover its people")
	var weights := 0.0
	for id in state.regions:
		weights += RegionsSim.population_weight(state, id)
	t.near(weights, 1.0, 1e-6, "live population shares sum to one")
	t.truth(RegionsSim.population_weight(state, "kostrel") > 0.0, "Kostrel has people")

	var result := Elections.hold(state, false)
	t.truth(result.regional_vote_share.has("kostrel"), "an election counts Kostrel's vote")
	t.truth(float(result.regional_turnout.get("kostrel", 0.0)) > 0.0, "and Kostrel turns out")
	var lines := "\n".join(Elections.report(state, result))
	t.truth(lines.contains("Kostrel —"), "the election report names Kostrel's winner")
