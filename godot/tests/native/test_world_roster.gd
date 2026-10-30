extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")

const ORIGINAL_IDS := ["ardenia", "krasova", "merova", "nueva_costa", "qadir", "solheim", "terand", "valmora", "veldoria"]
const NEW_IDS := ["aldermark", "azhara", "beyta", "borynia", "brisca", "columbria", "drevnia", "hanlin", "haravan",
	"ilmar", "kalvia", "marisca", "nordhaven", "ozmara", "sahrun", "selenne", "temirsk", "turaz", "ulgar",
	"valcourt", "yaskar", "zelvany"]
const BLOC_ROSTERS := {
	"concert": ["aldermark", "brisca", "kalvia", "nordhaven", "nueva_costa", "selenne", "solheim", "valcourt"],
	"meridian": ["aldermark", "brisca", "columbria", "nordhaven", "nueva_costa", "solheim", "valcourt"],
	"union": ["krasova", "ulgar", "zelvany"],
}
const AXIS_ROLE_EXCEPTIONS := {"@labour": ["terand"]}
const UNHELD_ROLE_EXCEPTIONS := {
	"@agrarian": ["aldermark", "azhara", "beyta", "brisca", "columbria", "marisca", "solheim", "terand", "valcourt"],
	"@establishment": ["ardenia", "borynia", "brisca", "columbria", "drevnia", "haravan", "ilmar", "kalvia",
		"krasova", "marisca", "nordhaven", "nueva_costa", "ozmara", "qadir", "selenne", "temirsk", "terand",
		"turaz", "ulgar", "veldoria", "yaskar", "zelvany", "beyta"],
}
const STORY_RELATIONS := [
	["zelvany", "krasova", 0.5, 1.0], ["kalvia", "krasova", -1.0, -0.3], ["haravan", "turaz", -1.0, -0.5],
	["ilmar", "ozmara", -1.0, -0.3], ["haravan", "krasova", 0.3, 1.0], ["borynia", "krasova", -1.0, -0.2],
	["nordhaven", "krasova", -1.0, -0.3], ["brisca", "columbria", 0.5, 1.0], ["drevnia", "marisca", -1.0, -0.3],
	["aldermark", "valcourt", 0.5, 1.0], ["temirsk", "hanlin", 0.2, 1.0], ["temirsk", "krasova", 0.2, 1.0],
]


static func _countries() -> Dictionary:
	return ContentRepository.load_all().get("countries", {})


static func _state(seed: int = 424242) -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": seed})
	state.rng = SimRng.from_seed(seed)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	return state


static func _sorted(a: Array) -> Array:
	var out := a.duplicate()
	out.sort()
	return out


func _test_thirty_one_countries_load(t) -> void:
	var ids: Array = _countries().keys()
	var expected: Array = ORIGINAL_IDS + NEW_IDS
	t.equal(_sorted(ids), _sorted(expected), "the world holds the nine original countries and the twenty-two new ones")


func _test_each_new_country_is_authored(t) -> void:
	var all := _countries()
	for id in NEW_IDS:
		var c: Dictionary = all.get(id, {})
		var meta: Dictionary = c.get("meta", {})
		var factions: Array = c.get("factions", [])
		var agenda: Dictionary = c.get("agenda", {})
		t.truth(String(c.get("name", "")) != "" and String(meta.get("short_description", "")).length() > 80,
			"%s has a name and a description" % id)
		t.truth(DiplomacySim.REGIME_FAMILY.has(String(c.get("regime_type", ""))), "%s has a known regime" % id)
		t.truth(factions.size() >= 3 and factions.size() <= 5, "%s has three to five factions" % id)
		t.truth(String(c.get("default_player", {}).get("name", "")) != "", "%s has a leader" % id)
		t.truth(String(meta.get("capital", "")) != "", "%s has a capital" % id)
		t.truth(WorldSim.AGGRESSION.has(String(agenda.get("type", ""))), "%s declares a known agenda" % id)
		for key in ["rival", "ally"]:
			var other := String(agenda.get(key, ""))
			t.truth(other == "" or (all.has(other) and other != id), "%s %s names a real country" % [id, key])
		var risk := float(meta.get("civil_war_risk", -1.0))
		t.truth(risk >= 0.0 and risk <= 1.0, "%s has a civil-war risk" % id)
		var economy: Dictionary = c.get("economy", {})
		t.truth(float(economy.get("gdp", 0.0)) > 0.0 and int(c.get("population", 0)) > 0, "%s has an economy" % id)
		for f in factions:
			t.truth(String(f.get("role", "")).begins_with("@"), "%s faction %s declares a role" % [id, f.get("id")])


func _test_relations_agree_in_both_directions(t) -> void:
	var all := _countries()
	var disagreements := 0
	for a in all:
		var rels: Dictionary = all[a].get("default_relations", {})
		for b in rels:
			t.truth(all.has(b), "%s's relation with %s names a real country" % [a, b])
			t.truth(float(rels[b]["trade_volume"]) <= DiplomacySim.TRADE_CEILING, "%s-%s trade sits under the ceiling" % [a, b])
			var back: Variant = all.get(b, {}).get("default_relations", {}).get(a)
			if back is Dictionary and (not is_equal_approx(float(back["score"]), float(rels[b]["score"]))
					or not is_equal_approx(float(back["trade_volume"]), float(rels[b]["trade_volume"]))):
				disagreements += 1
	t.equal(disagreements, 0, "no pair of countries remembers its relationship two ways")
	var state := _state()
	for row in STORY_RELATIONS:
		var a := state.world_country(String(row[0]))
		var score: float = (a.relations[String(row[1])] as Country.BilateralRelation).score
		t.truth(score >= float(row[2]) and score <= float(row[3]), "%s and %s start where the story puts them (%.2f)" % [row[0], row[1], score])


func _test_rivalries_are_mutual_where_the_story_says(t) -> void:
	var all := _countries()
	for pair in [["haravan", "turaz"], ["ilmar", "ozmara"]]:
		t.equal(all[pair[0]]["agenda"].get("rival"), pair[1], "%s's rival is %s" % pair)
		t.equal(all[pair[1]]["agenda"].get("rival"), pair[0], "and %s's rival is %s" % [pair[1], pair[0]])
	t.equal(all["zelvany"]["agenda"].get("ally"), "krasova", "Zelvany is Krasova's client")
	t.equal(all["haravan"]["agenda"].get("ally"), "krasova", "Haravan is allied to Krasova")
	t.equal(all["krasova"]["agenda"].get("rival"), "ardenia", "Krasova's rival is still Ardenia")
	t.equal(all["krasova"]["agenda"].get("backs"), "vetrenka", "Krasova still backs Vetrenka")


func _test_a_campaign_holds_the_whole_world(t) -> void:
	var state := _state()
	t.equal(state.world.size(), 30, "a campaign carries thirty foreign states")
	t.equal(StateValidator.validate(state), PackedStringArray(), "the thirty-one-country state validates")
	t.truth(state.world_country("sahrun").civil_war_risk >= 0.5, "Sahrun opens close to civil war")
	t.truth(state.world_country("kalvia").civil_war_risk < 0.1, "Kalvia does not")


func _test_bloc_rosters_seed_and_hold(t) -> void:
	var state := _state()
	for bloc in BLOC_ROSTERS:
		t.equal(_sorted(state.foreign.members.get(bloc, [])), BLOC_ROSTERS[bloc], "%s opens with its roster" % bloc)
	t.truth(not ("ozmara" in state.foreign.members["concert"]), "Ozmara courts the Concert without a seat")
	state.month = 1
	OrientationSim.monthly(state)
	for bloc in BLOC_ROSTERS:
		var members: Array = state.foreign.members.get(bloc, [])
		for id in BLOC_ROSTERS[bloc]:
			t.truth(id in members, "%s keeps %s at the first new year" % [bloc, id])
	for id in state.foreign.members["union"]:
		t.truth(not (id in state.foreign.members["concert"]) and not (id in state.foreign.members["meridian"]),
			"%s sits on one side only" % id)
	t.truth(not ("ozmara" in state.foreign.members["concert"]), "Ozmara is still a candidate a year in")


func _test_the_map_reads_every_country(t) -> void:
	var game = NativeGameScript.new()
	var result: Dictionary = game.new_campaign({"country_id": "ardenia", "background_id": "none",
		"difficulty_id": "normal", "opening_role": "government", "seed": 424242})
	var snap: Dictionary = result.get("snapshot", {})
	var ids: Array = []
	for row in snap.get("diplomacy", []):
		ids.append(String(row.get("id", "")))
		t.truth(String(row.get("name", "")) != "", "the snapshot names %s" % row.get("id"))
	var expected: Array = ORIGINAL_IDS + NEW_IDS
	expected.erase("ardenia")
	t.equal(_sorted(ids), _sorted(expected), "the snapshot lists all thirty foreign states for the map")
	var memberships: Dictionary = snap.get("foreign", {}).get("map", {}).get("memberships", {})
	for bloc in BLOC_ROSTERS:
		for id in BLOC_ROSTERS[bloc]:
			t.truth(bloc in memberships.get(id, []), "the map sees %s in %s" % [id, bloc])
	game.free()


static func _shell(data: Dictionary) -> GameState:
	var state := GameState.new()
	state.country = Country.from_json(data, true)
	return state


static func _role_keys(option: Dictionary) -> Array:
	var keys: Array = []
	var effects: Dictionary = option.get("effects", {})
	for field in ["faction_loyalty_deltas", "faction_power_deltas"]:
		for key in effects.get(field, {}):
			if not keys.has(key):
				keys.append(String(key))
	return keys


static func _acts_without_factions(option: Dictionary) -> bool:
	var effects: Dictionary = option.get("effects", {})
	for field in ["gdp_growth_delta", "unemployment_delta", "inflation_delta", "budget_revenue_delta",
			"budget_expenditure_delta", "one_time_debt_pct_delta"]:
		if absf(float(effects.get(field, 0.0))) > 0.0:
			return true
	return not effects.get("modifiers", []).is_empty() or not option.get("relation_deltas", {}).is_empty() \
		or float(option.get("pc_cost", 0.0)) != 0.0 or option.get("follow_up") != null or option.get("on_apply") != null


func _test_roles_resolve_in_every_country(t) -> void:
	var all := _countries()
	var unheld := {}
	var wrong_sign := []
	for id in all:
		var state := _shell(all[id])
		for role in EffectBundle.ROLE_AXIS:
			var f := EffectBundle.resolve_faction(state, role)
			var axis: Array = EffectBundle.ROLE_AXIS[role]
			if f == null:
				if not unheld.has(role):
					unheld[role] = []
				(unheld[role] as Array).append(id)
			elif not axis.is_empty():
				var value: float = f.ideology.economic if axis[0] == "economic" else f.ideology.social
				if value * float(axis[1]) <= 0.0 and not AXIS_ROLE_EXCEPTIONS.get(role, []).has(id):
					wrong_sign.append("%s %s" % [id, role])
	t.equal(wrong_sign, [], "every axis role lands on a sign-correct faction in every country")
	for role in EffectBundle.ROLE_AXIS:
		var expected: Array = UNHELD_ROLE_EXCEPTIONS.get(role, []) + AXIS_ROLE_EXCEPTIONS.get(role, [])
		t.equal(_sorted(unheld.get(role, [])), _sorted(expected), "%s resolves everywhere except its listed exceptions" % role)


func _test_no_situation_option_is_a_silent_no_op(t) -> void:
	var all := _countries()
	var catalog: Dictionary = ContentRepository.load_all().get("catalogs", {}).get("events", {})
	var bespoke: Array = catalog.get("ardenia_only_events", [])
	var home := _shell(all["ardenia"])
	var silent := []
	var checked := 0
	for event in catalog.get("events", []):
		if bespoke.has(event.get("id")):
			continue
		for option in event.get("options", []):
			if _acts_without_factions(option) or not _lands(home, option):
				continue
			checked += 1
			for id in all:
				if not _lands(_shell(all[id]), option):
					silent.append("%s %s/%s" % [id, event.get("id"), option.get("id")])
	t.truth(checked > 0, "some options act only through factions (%d)" % checked)
	t.equal(silent, [], "an option that acts in Ardenia acts in every country")


static func _lands(state: GameState, option: Dictionary) -> bool:
	for key in _role_keys(option):
		if EffectBundle.resolve_faction(state, key) != null:
			return true
	return false


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_thirty_one_countries_load(t)
	_test_each_new_country_is_authored(t)
	_test_relations_agree_in_both_directions(t)
	_test_rivalries_are_mutual_where_the_story_says(t)
	_test_a_campaign_holds_the_whole_world(t)
	_test_bloc_rosters_seed_and_hold(t)
	_test_the_map_reads_every_country(t)
	_test_roles_resolve_in_every_country(t)
	_test_no_situation_option_is_a_silent_no_op(t)
	quit(t.finish())
