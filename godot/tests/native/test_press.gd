extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const SLOT := "test_press_slice"


static func _state(role: String = "contextual", seed: int = 717171) -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": seed})
	state.rng = SimRng.from_seed(seed)
	BudgetSim.ensure_budget_state(state)
	return state


static func _sample(template: String) -> Dictionary:
	var fields := {}
	var regex := RegEx.create_from_string("\\{(\\w+)\\}")
	for m in regex.search_all(template):
		fields[m.get_string(1)] = "Sample%s" % m.get_string(1).capitalize().replace(" ", "")
	return fields


func _test_a_dispatch_is_voiced_and_recorded(t) -> void:
	var state := _state()
	var text := Voice.say(state, "world_axis", {"a": "Solheim", "b": "Nueva Costa"})
	t.truth(text in (Voice.templates()["world_axis"] as Array).map(func(v): return String(v).format({"a": "Solheim", "b": "Nueva Costa"})),
		"a dispatch is one of its authored variants")
	t.truth(not text.contains("{"), "with every field filled")
	t.equal(state.monthly_news[-1], {"key": "world_axis", "fields": {"a": "Solheim", "b": "Nueva Costa"}, "text": text},
		"and is recorded as structured news")


func _test_variants_are_local_and_deterministic(t) -> void:
	var a := _state()
	var b := _state()
	var rng_before := a.rng.to_dict()
	var seen := {}
	for i in range(24):
		var ta := Voice.say(a, "vote_passed", {"bill": "X", "vfor": 60, "vagainst": 40, "threshold": 51})
		var tb := Voice.say(b, "vote_passed", {"bill": "X", "vfor": 60, "vagainst": 40, "threshold": 51})
		t.truth(ta == tb, "the same turn, key and position give the same words (%d)" % i)
		seen[ta] = true
	t.truth(seen.size() >= 3, "while successive dispatches vary (%d variants seen)" % seen.size())
	Press.front_page(a)
	t.equal(a.rng.to_dict(), rng_before, "and the voice never draws on the campaign stream")
	var differs := false
	for i in range(8):
		if Voice.variant_index(7, "vote_passed", i, 4) != Voice.variant_index(0, "vote_passed", i, 4):
			differs = true
	t.truth(differs, "a different month reads differently")


func _test_every_dispatch_carries_its_marker(t) -> void:
	var markers := Voice.markers()
	var missing: Array[String] = []
	for key in Voice.templates():
		if not markers.has(key):
			missing.append("%s (no marker)" % key)
			continue
		for template in Voice.templates()[key]:
			var fields := _sample(String(template))
			var marker := String(markers[key]).format(fields)
			if String(template).format(fields).findn(marker) < 0:
				missing.append(key)
	t.equal(missing, [] as Array[String], "every variant of every dispatch carries its stable marker")


func _test_every_headline_formats_with_its_fields(t) -> void:
	var samples: Dictionary = ContentRepository.load_all()["catalogs"]["press_templates"]["sample_fields"]
	var broken: Array[String] = []
	for key in Press.headlines():
		var fields: Dictionary = samples.get(key, {})
		for template in Press.headlines()[key] + Press.leads().get(key, []):
			if String(template).format(fields).contains("{"):
				broken.append(key)
	t.equal(broken, [] as Array[String], "every headline and lead fills from its documented fields")


func _test_the_front_page_leads_with_the_most_dramatic_story(t) -> void:
	var state := _state()
	Voice.say(state, "world_deliberates", {"actor": "Krasova", "actor_leader": "K", "target": "Veldoria"})
	Voice.say(state, "world_civil_war_out", {"country": "Valmora", "leader": "V"})
	Voice.say(state, "world_deepen", {"actor": "Merova", "actor_leader": "M", "target": "Veldoria", "target_leader": "L"})
	Voice.record(state, "unheadlined_note", {}, "A plain brief.")
	var page := Press.front_page(state, {"approval": 0.5}, {"approval": 0.52})
	t.equal(page["masthead"], "The Vashtera Herald", "the masthead is the country's own paper")
	t.truth(String(page["lead"]["headline"]).contains("VALMORA"), "a neighbour's civil war leads the paper")
	t.equal(page["lead"]["headline"], String(page["lead"]["headline"]).to_upper(), "in capitals")
	t.equal(page["headlines"].size(), 2, "the lesser stories follow as headlines")
	t.truth(String(page["headlines"][0]).contains("MEROVA"), "in order of drama")
	t.equal(page["briefs"], ["A plain brief."], "and everything else runs as a brief")
	t.equal(page["numbers"], [{"approval": 0.5}, {"approval": 0.52}], "with the month's numbers")
	t.equal(page["dateline"], "%s %d" % [Press.MONTHS[state.month - 1], state.year], "dated with the month and year")
	state.country.paper = ""
	t.equal(Press.front_page(state)["masthead"], "The Ardenia Herald", "a country without a paper gets a Herald")


func _test_a_quiet_month_says_so(t) -> void:
	var state := _state()
	var page := Press.front_page(state)
	t.equal(page["lead"]["headline"], "A QUIET MONTH IN ARDENIA", "a quiet month makes a quiet front page")
	t.truth(String(page["lead"]["body"]) != "", "with a few lines of copy")
	t.truth(page["headlines"].is_empty() and page["briefs"].is_empty(), "and nothing else")


func _test_secondary_headlines_are_capped(t) -> void:
	var state := _state()
	for i in range(8):
		Voice.say(state, "world_deepen", {"actor": "A%d" % i, "actor_leader": "L", "target": "B", "target_leader": "M"})
	var page := Press.front_page(state)
	t.equal(page["headlines"].size(), Press.MAX_SECONDARY_HEADLINES, "at most four headlines under the lead")
	t.equal(page["briefs"].size(), 8 - 1 - Press.MAX_SECONDARY_HEADLINES, "the rest become briefs")


func _test_the_monthly_report_carries_the_front_page(t) -> void:
	var game = NativeGameScript.new()
	game.new_campaign({"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "contextual", "seed": 717171})
	for _m in range(8):
		NativeGameScript.close_month(game._state)
	var snap: Dictionary = game.snapshot()
	t.truth(String(snap["dispatches"][0]).begins_with("The Vashtera Herald"), "the dispatch column opens with the masthead")
	t.truth(snap["dispatches"].size() >= 2, "and carries the lead story")
	t.equal(snap["front_page"], game._state.front_page, "the snapshot holds the whole front page")
	t.truth(game._state.monthly_news.is_empty(), "the month's news is spent once printed")
	t.truth(game.save(SLOT).get("ok", false), "the front page is saved")
	var printed: Dictionary = game._state.front_page.duplicate(true)
	game.load(SLOT)
	t.equal(game._state.front_page, printed, "and reloads unchanged")
	game.free()
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute("user://saves/%s.json%s" % [SLOT, suffix])
	var old := _state().to_dict()
	old.erase("monthly_news")
	old.erase("front_page")
	var legacy := GameState.from_dict(old)
	t.truth(legacy != null and legacy.front_page.is_empty(), "an older save loads without a paper")


func _test_the_world_and_parliament_speak_through_the_voice(t) -> void:
	var state := _state()
	var keys := {}
	for _m in range(14):
		state.turn += 1
		WorldSim.monthly(state)
	for item in state.monthly_news:
		keys[item["key"]] = true
	t.truth(keys.has("world_deliberates"), "foreign plans leak as voiced dispatches")
	t.truth(keys.keys().any(func(k): return String(k) in ["world_undermine", "world_condemn", "world_deepen", "world_court_player", "world_trade_pact"]),
		"and foreign moves are reported as dispatches")
	var opp := _state("opposition")
	for _m in range(4):
		opp.turn += 1
		OppositionSim.monthly(opp)
	t.truth(opp.monthly_news.any(func(i): return i["key"] in ["vote_passed", "vote_failed"]),
		"a government division is reported in the voice of the chamber")


func _test_a_government_bill_makes_the_paper(t) -> void:
	var state := _state("opposition")
	Voice.record(state, "government_bill", {"bill": "Minimum Wage Act", "party": "National Conservatives"}, "A bill.")
	Voice.say(state, "world_deepen", {"actor": "Merova", "actor_leader": "M", "target": "Veldoria", "target_leader": "L"})
	var page := Press.front_page(state)
	t.truth(String(page["lead"]["headline"]).contains("MINIMUM WAGE ACT"), "a government bill awaiting your answer leads the paper")
	t.truth(Press.DRAMA["government_bill"] > Press.DRAMA["world_deepen"], "above foreign courtesies")


func _test_missing_pools_and_bad_press_records_are_refused(t) -> void:
	var state := _state()
	t.equal(Voice.say(state, "no_such_dispatch", {}), "", "an unknown dispatch says nothing")
	t.truth(state.monthly_news.is_empty(), "and records nothing")
	var bad := GameState.from_dict(state.to_dict())
	bad.monthly_news.append({"key": "", "fields": {}, "text": "x"})
	t.truth(not StateValidator.validate(bad).is_empty(), "a news item needs a key")
	bad = GameState.from_dict(state.to_dict())
	bad.front_page = {"masthead": "M"}
	t.truth(not StateValidator.validate(bad).is_empty(), "a front page needs every part")
	bad = GameState.from_dict(state.to_dict())
	bad.front_page = Press.front_page(bad)
	t.truth(StateValidator.validate(bad).is_empty(), "a real front page validates")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_a_dispatch_is_voiced_and_recorded(t)
	_test_variants_are_local_and_deterministic(t)
	_test_every_dispatch_carries_its_marker(t)
	_test_every_headline_formats_with_its_fields(t)
	_test_the_front_page_leads_with_the_most_dramatic_story(t)
	_test_a_quiet_month_says_so(t)
	_test_secondary_headlines_are_capped(t)
	_test_the_monthly_report_carries_the_front_page(t)
	_test_the_world_and_parliament_speak_through_the_voice(t)
	_test_a_government_bill_makes_the_paper(t)
	_test_missing_pools_and_bad_press_records_are_refused(t)
	quit(t.finish())
