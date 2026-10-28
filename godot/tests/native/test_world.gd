extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")


static func _state(role: String = "contextual", seed: int = 515151) -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": seed})
	state.rng = SimRng.from_seed(seed)
	BudgetSim.ensure_budget_state(state)
	return state


static func _c(state: GameState, id: String) -> Country:
	return state.country if id == state.country.id else state.world_country(id)


static func _score(state: GameState, a: String, b: String) -> float:
	return (_c(state, a).relations[b] as Country.BilateralRelation).score


static func _set_score(state: GameState, a: String, b: String, score: float) -> void:
	(_c(state, a).relations[b] as Country.BilateralRelation).score = score
	(_c(state, b).relations[a] as Country.BilateralRelation).score = score


static func _world_month(state: GameState) -> Array[String]:
	state.turn += 1
	return WorldSim.monthly(state)


func _test_each_agenda_reads_its_national_interest(t) -> void:
	var state := _state()
	var krasova := WorldSim.national_interest(state, _c(state, "krasova"))
	t.equal(krasova, {"objective": "undermine", "target": "veldoria"}, "a hegemon presses its authored rival")
	t.equal(WorldSim.national_interest(state, _c(state, "terand")),
		{"objective": "undermine", "target": "solheim"}, "a revanchist presses the country it holds a grudge against")
	var solheim := WorldSim.national_interest(state, _c(state, "solheim"))
	t.equal(solheim["target"], "nueva_costa", "a trader works with its ally")
	t.equal(solheim["objective"], "trade", "and seeks a trade pact while none stands")
	t.equal(WorldSim.national_interest(state, _c(state, "merova")),
		{"objective": "court", "target": "veldoria"}, "a reformer courts its ally")
	_c(state, "valmora").stability = 0.5
	t.equal(WorldSim.national_interest(state, _c(state, "valmora"))["objective"], "consolidate",
		"a shaky survivor turns inward")
	_c(state, "valmora").stability = 0.8
	t.equal(WorldSim.national_interest(state, _c(state, "valmora")),
		{"objective": "court", "target": "solheim"}, "a steady survivor shelters under its patron")
	_c(state, "krasova").in_civil_war = true
	t.equal(WorldSim.national_interest(state, _c(state, "krasova"))["objective"], "consolidate",
		"a country at war with itself has no foreign policy")
	t.equal(WorldSim.national_interest(state, _c(state, "veldoria"))["target"], "ardenia",
		"Veldoria's chosen partner is the player")
	t.equal(WorldSim.national_interest(state, _c(state, "veldoria"))["objective"], "court",
		"and no foreign power signs a treaty on the player's behalf")


func _test_a_hegemon_with_a_spent_rivalry_tends_its_sphere(t) -> void:
	var state := _state()
	_set_score(state, "krasova", "veldoria", -0.9)
	var plan := WorldSim.national_interest(state, _c(state, "krasova"))
	t.equal(plan["objective"], "court", "a bottomed-out rivalry is not worth the month")
	t.truth(plan["target"] != "veldoria", "so the hegemon courts someone else")


func _test_an_ideologue_presses_its_rival(t) -> void:
	var state := _state()
	_c(state, "merova").agenda = {"type": "ideologue", "rival": "qadir"}
	t.equal(WorldSim.national_interest(state, _c(state, "merova")),
		{"objective": "undermine", "target": "qadir"}, "an ideologue condemns the other camp")
	_c(state, "merova").agenda = {}
	t.equal(WorldSim.agenda_type(_c(state, "merova")), "reformer",
		"an undeclared agenda falls back on the regime's habit")


func _test_a_sanctioning_power_outranks_everything(t) -> void:
	var state := _state()
	(state.country.relations["veldoria"] as Country.BilateralRelation).sanctioned = true
	(_c(state, "veldoria").relations["ardenia"] as Country.BilateralRelation).sanctioned = true
	t.equal(WorldSim.national_interest(state, _c(state, "veldoria")),
		{"objective": "undermine", "target": "ardenia"}, "even a friendly trader turns on whoever sanctions it")


func _test_openings_are_staggered_then_paced(t) -> void:
	var state := _state()
	var acted := {}
	var gaps_ok := true
	var quiet_opening := true
	for _m in range(60):
		_world_month(state)
		for c in state.world:
			var last := int(c.plan.get("last_acted_turn", -1))
			if last != state.turn:
				continue
			if state.turn <= 2:
				quiet_opening = false
			if acted.has(c.id):
				var gap: int = state.turn - int(acted[c.id])
				if gap < WorldSim.PLAN_MIN_MONTHS or gap > WorldSim.PLAN_MIN_MONTHS + WorldSim.PLAN_SPREAD_MONTHS - 1:
					gaps_ok = false
			acted[c.id] = state.turn
	t.truth(quiet_opening, "nobody acts in the first two months")
	t.equal(acted.size(), state.world.size(), "every country acts")
	t.truth(gaps_ok, "and each acts again every three to five months")


func _test_plans_leak_before_hostile_and_trade_moves(t) -> void:
	var state := _state()
	var leaked := {}
	for _m in range(24):
		for line in _world_month(state):
			if line.contains("weighing"):
				for c in state.world:
					if line.begins_with(c.name):
						leaked[c.id] = true
	t.truth(leaked.has("krasova") and leaked.has("terand"), "hostile plans are foreshadowed")
	t.truth(not leaked.has("merova"), "courtesies are not")


func _test_a_defence_pact_shelves_about_half_of_hostile_moves(t) -> void:
	var state := _state()
	var shelved := 0
	var trials := 400
	var krasova := _c(state, "krasova")
	for _i in range(trials):
		if WorldSim.hostile_action(state, krasova, state.country, []) == "shelved":
			shelved += 1
	t.equal(shelved, 0, "without a pact nothing is shelved")
	(state.country.relations["veldoria"] as Country.BilateralRelation).treaties.append(
		{"id": "defense_veldoria_0", "type": "defense", "name": "Pact", "parties": ["ardenia", "veldoria"], "turns_active": 0})
	(_c(state, "veldoria").relations["ardenia"] as Country.BilateralRelation).treaties.append(
		{"id": "defense_veldoria_0", "type": "defense", "name": "Pact", "parties": ["ardenia", "veldoria"], "turns_active": 0})
	_set_score(state, "krasova", "ardenia", 0.0)
	for _i in range(trials):
		if WorldSim.hostile_action(state, krasova, state.country, []) == "shelved":
			shelved += 1
		_set_score(state, "krasova", "ardenia", 0.0)
	t.truth(shelved > trials * 0.4 and shelved < trials * 0.6, "a pact holder sees about half of hostile moves shelved (%d/%d)" % [shelved, trials])


func _test_actions_change_relations_both_ways(t) -> void:
	var state := _state()
	var before := _score(state, "krasova", "veldoria")
	var outcome := WorldSim.hostile_action(state, _c(state, "krasova"), _c(state, "veldoria"), [])
	t.truth(outcome in ["condemned", "undermined"], "a hostile move lands")
	t.truth(_score(state, "krasova", "veldoria") < before, "and sours the relationship")
	t.near(_score(state, "veldoria", "krasova"), _score(state, "krasova", "veldoria"), 1e-9, "as seen from both capitals")
	var player_before := _score(state, "merova", "ardenia")
	WorldSim.cooperative_action(state, _c(state, "merova"), state.country, [])
	t.truth(_score(state, "merova", "ardenia") > player_before, "courting the player warms the relationship")
	t.truth((state.country.relations["merova"] as Country.BilateralRelation).treaties.is_empty(),
		"but never binds the player to a treaty")


func _test_world_trade_pacts_are_signed_once(t) -> void:
	var state := _state()
	_set_score(state, "solheim", "nueva_costa", 0.5)
	var signed := false
	for _i in range(40):
		if WorldSim.cooperative_action(state, _c(state, "solheim"), _c(state, "nueva_costa"), []) == "trade_pact":
			signed = true
	t.truth(signed, "friendly traders sign a pact")
	var rel: Country.BilateralRelation = _c(state, "solheim").relations["nueva_costa"]
	t.equal(rel.treaties.size(), 1, "exactly once")
	t.equal((_c(state, "nueva_costa").relations["solheim"] as Country.BilateralRelation).treaties.size(), 1, "on both sides")
	t.truth(rel.trade_volume > 0.0, "and trade begins")
	t.equal(WorldSim.national_interest(state, _c(state, "solheim"))["objective"], "court",
		"once the pact stands the trader simply keeps the friendship warm")


func _test_a_sanctioned_country_never_courts_its_sanctioner(t) -> void:
	var state := _state()
	(state.country.relations["merova"] as Country.BilateralRelation).sanctioned = true
	var before := _score(state, "merova", "ardenia")
	t.equal(WorldSim.cooperative_action(state, _c(state, "merova"), state.country, []), "refused",
		"a stale friendly plan is dropped")
	t.near(_score(state, "merova", "ardenia"), before, 1e-9, "and nothing changes")


func _test_world_relations_drift_by_camp(t) -> void:
	var state := _state()
	_set_score(state, "solheim", "merova", 0.0)
	_set_score(state, "krasova", "solheim", 0.0)
	for c in state.world:
		c.plan = {"objective": "consolidate", "target": "", "matures_turn": 9999, "last_acted_turn": -1, "foreshadowed": false}
	for _m in range(12):
		_world_month(state)
	t.truth(_score(state, "solheim", "merova") > 0.0, "democracies warm to one another")
	t.truth(_score(state, "krasova", "solheim") < 0.0, "and cool toward autocracies")
	t.near(_score(state, "merova", "solheim"), _score(state, "solheim", "merova"), 1e-9, "symmetrically")


func _test_named_arcs_form_dissolve_and_persist(t) -> void:
	var state := _state()
	for c in state.world:
		c.plan = {"objective": "consolidate", "target": "", "matures_turn": 9999, "last_acted_turn": -1, "foreshadowed": false}
	_set_score(state, "solheim", "nueva_costa", 0.8)
	var pact := {"id": "trade_solheim_nueva_costa", "type": "trade", "name": "Pact", "parties": ["solheim", "nueva_costa"], "turns_active": 0}
	(_c(state, "solheim").relations["nueva_costa"] as Country.BilateralRelation).treaties.append(pact.duplicate(true))
	(_c(state, "nueva_costa").relations["solheim"] as Country.BilateralRelation).treaties.append(pact.duplicate(true))
	_set_score(state, "krasova", "veldoria", -0.85)
	var notes: Array[String] = []
	WorldSim.update_arcs(state, notes)
	t.equal(state.world_arcs.get("nueva_costa|solheim", ""), "axis", "close trading partners become an axis")
	t.equal(state.world_arcs.get("krasova|veldoria", ""), "feud", "deep hostility hardens into a feud")
	t.truth(notes.any(func(l): return l.contains("axis")) and notes.any(func(l): return l.contains("feud")), "and the world hears of both")
	var count := notes.size()
	WorldSim.update_arcs(state, notes)
	t.equal(notes.size(), count, "an arc is announced once")
	var reloaded := GameState.from_dict(state.to_dict())
	t.equal(reloaded.world_arcs, state.world_arcs, "arcs survive save and reload")
	_set_score(state, "solheim", "nueva_costa", 0.2)
	_set_score(state, "krasova", "veldoria", -0.1)
	WorldSim.update_arcs(state, notes)
	t.truth(state.world_arcs.is_empty(), "arcs dissolve when the conditions reverse")
	t.truth(notes[-1].contains("no more"), "and their end is reported")


func _test_the_validator_rejects_impossible_world_state(t) -> void:
	var state := _state()
	t.truth(StateValidator.validate(state).is_empty(), "a fresh world validates")
	state.world_arcs["krasova|veldoria"] = "romance"
	t.truth(not StateValidator.validate(state).is_empty(), "an unknown arc kind is rejected")
	state.world_arcs = {"atlantis|krasova": "feud"}
	t.truth(not StateValidator.validate(state).is_empty(), "an arc naming an unknown country is rejected")
	state.world_arcs = {}
	_c(state, "krasova").plan = {"objective": "invade", "target": "", "matures_turn": 3}
	t.truth(not StateValidator.validate(state).is_empty(), "an unknown plan objective is rejected")
	_c(state, "krasova").plan = {"objective": "undermine", "target": "krasova", "matures_turn": 3}
	t.truth(not StateValidator.validate(state).is_empty(), "a country cannot plan against itself")
	_c(state, "krasova").plan = {}
	var old := state.to_dict()
	old.erase("world_arcs")
	var legacy := GameState.from_dict(old)
	t.truth(legacy != null and legacy.world_arcs.is_empty(), "an older save loads with no arcs")


func _test_reloads_replay_the_world_exactly(t) -> void:
	var a := _state()
	var b := _state()
	for _m in range(10):
		_world_month(a)
		_world_month(b)
	var reloaded := GameState.from_dict(a.to_dict())
	for _m in range(26):
		_world_month(a)
		_world_month(reloaded)
		_world_month(b)
	t.truth(a.to_dict() == b.to_dict(), "one seed, one history")
	t.truth(a.to_dict() == reloaded.to_dict(), "a reload continues the same history")


static func _bounded(state: GameState) -> bool:
	var econ := state.country.economy
	for v in [state.player.approval, state.stability_value, state.civil_war_risk, state.insurgency_pressure]:
		if not is_finite(v) or v < 0.0 or v > 1.0:
			return false
	for v in [econ.gdp, econ.inflation, econ.unemployment, econ.public_debt_pct, state.player.political_capital]:
		if not is_finite(v):
			return false
	if econ.inflation > 0.5 or econ.unemployment > 0.6 or econ.public_debt_pct > 3.0 or econ.gdp <= 0.0:
		return false
	for c in state.world:
		if not is_finite(c.stability) or c.stability < 0.0 or c.stability > 1.0:
			return false
		for rel in c.relations.values():
			var r: Country.BilateralRelation = rel
			if not is_finite(r.score) or absf(r.score) > 1.0 or not is_finite(r.trade_volume) or r.trade_volume > DiplomacySim.TRADE_CEILING:
				return false
	return StateValidator.validate(state).is_empty()


func _test_a_decade_of_the_living_world_stays_bounded(t) -> void:
	for role in ["government", "opposition"]:
		var state := _state(role)
		var ok := true
		var acted := 0
		for _m in range(120):
			NativeGameScript.close_month(state)
			for c in state.world:
				if int(c.plan.get("last_acted_turn", -1)) == state.turn:
					acted += 1
			if not _bounded(state):
				ok = false
				break
		t.truth(ok, "120 months with the world acting stay finite and bounded (%s)" % role)
		t.truth(acted >= state.world.size() * 20, "and the world kept acting (%d actions, %s)" % [acted, role])


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_each_agenda_reads_its_national_interest(t)
	_test_a_hegemon_with_a_spent_rivalry_tends_its_sphere(t)
	_test_an_ideologue_presses_its_rival(t)
	_test_a_sanctioning_power_outranks_everything(t)
	_test_openings_are_staggered_then_paced(t)
	_test_plans_leak_before_hostile_and_trade_moves(t)
	_test_a_defence_pact_shelves_about_half_of_hostile_moves(t)
	_test_actions_change_relations_both_ways(t)
	_test_world_trade_pacts_are_signed_once(t)
	_test_a_sanctioned_country_never_courts_its_sanctioner(t)
	_test_world_relations_drift_by_camp(t)
	_test_named_arcs_form_dissolve_and_persist(t)
	_test_the_validator_rejects_impossible_world_state(t)
	_test_reloads_replay_the_world_exactly(t)
	_test_a_decade_of_the_living_world_stays_bounded(t)
	quit(t.finish())
