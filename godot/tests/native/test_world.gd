extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const Polls = preload("res://tests/native/test_polls.gd")


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
	t.equal(krasova, {"objective": "undermine", "target": "ardenia"}, "Krasova, the core successor state, presses Ardenia")
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
	_set_score(state, "krasova", "ardenia", -0.9)
	var plan := WorldSim.national_interest(state, _c(state, "krasova"))
	t.equal(plan["objective"], "court", "a bottomed-out rivalry is not worth the month")
	t.truth(plan["target"] != "ardenia", "so the hegemon courts someone else")


func _test_krasova_presses_while_vetrenka_is_contested(t) -> void:
	var state := _state()
	_set_score(state, "krasova", "ardenia", -0.9)
	state.campaign_meta["vetrenka_status"] = "retaken"
	t.equal(WorldSim.national_interest(state, _c(state, "krasova")), {"objective": "undermine", "target": "ardenia"},
		"a reconquered Vetrenka keeps its backer pressing however bad relations are")
	state.campaign_meta["vetrenka_status"] = "settled"
	_set_score(state, "krasova", "ardenia", -0.5)
	t.equal(WorldSim.national_interest(state, _c(state, "krasova"))["objective"], "court",
		"a settlement cools the backer's grudge sooner")
	var other := _state()
	_set_score(other, "krasova", "ardenia", -0.5)
	t.equal(WorldSim.national_interest(other, _c(other, "krasova"))["objective"], "undermine",
		"while an unsettled line keeps it pressing at the same depth")


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
		_world_month(state)
	for item in state.monthly_news:
		if item["key"] == "world_deliberates":
			t.truth(String(item["text"]).contains("weighing"), "a leak carries its marker")
			for c in state.world:
				if item["fields"]["actor"] == c.name:
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
	t.truth(notes[-1].contains("feud") or notes[-1].contains("axis"), "and their end is reported")


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
	_c(state, "krasova").plan = {"objective": "undermine", "target": "", "matures_turn": 3}
	t.truth(not StateValidator.validate(state).is_empty(), "a hostile plan needs a target")
	_c(state, "krasova").plan = {"objective": "consolidate", "target": "", "matures_turn": 3, "foreshadowed": "yes"}
	t.truth(not StateValidator.validate(state).is_empty(), "a plan's leak flag is a flag")
	_c(state, "krasova").plan = {"objective": "consolidate", "target": "", "matures_turn": 3, "last_acted_turn": 99}
	t.truth(not StateValidator.validate(state).is_empty(), "a plan cannot have acted in the future")
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
			Polls.budget_policy(state, 0.0)
			NativeGameScript.next_month(state)
			for c in state.world:
				if int(c.plan.get("last_acted_turn", -1)) == state.turn:
					acted += 1
			if not _bounded(state):
				ok = false
				break
		t.truth(ok, "120 months with the world acting stay finite and bounded (%s)" % role)
		t.truth(acted >= state.world.size() * 20, "and the world kept acting (%d actions, %s)" % [acted, role])


static func _sign_defence_pact(state: GameState, partner: String) -> void:
	var pact := {"id": "defense_%s_0" % partner, "type": "defense", "name": "Pact", "parties": ["ardenia", partner], "turns_active": 0}
	(state.country.relations[partner] as Country.BilateralRelation).treaties.append(pact.duplicate(true))
	(_c(state, partner).relations["ardenia"] as Country.BilateralRelation).treaties.append(pact.duplicate(true))


static func _decade_against_ardenia(seed: int, pact: bool, outreach := false) -> Dictionary:
	var state := _state("government", seed)
	if pact:
		_sign_defence_pact(state, "veldoria")
	var krasova := _c(state, "krasova")
	var out := {"hostile": 0, "shelved": 0, "warned": 0, "lowest": 1.0, "final": 0.0, "harm": 0.0, "feud": false}
	var warned_for := -1
	for _m in range(120):
		if outreach:
			_max_outreach(state)
		NativeGameScript.close_month(state)
		var plan := krasova.plan
		if plan.get("objective") == "undermine" and plan.get("target") == "ardenia" \
				and bool(plan.get("foreshadowed", false)) and warned_for != int(plan["matures_turn"]):
			warned_for = int(plan["matures_turn"])
			out["warned"] += 1
		if int(plan.get("last_acted_turn", -1)) == state.turn:
			match String(plan.get("last_outcome", "")):
				"condemned", "undermined":
					out["hostile"] += 1
				"shelved":
					out["shelved"] += 1
		for entry in state.foreign.hostile_log:
			if int(entry["turn"]) == state.turn and String(entry["actor"]) == "krasova":
				out["harm"] -= float(entry["relation"]) + float(entry["economy"]) + float(entry["stability"])
		out["feud"] = bool(out["feud"]) or state.world_arcs.get("ardenia|krasova", "") == "feud"
		out["lowest"] = minf(out["lowest"], _score(state, "krasova", "ardenia"))
	out["final"] = _score(state, "krasova", "ardenia")
	return out


func _test_krasova_acts_against_ardenia_across_a_decade(t) -> void:
	for seed in [515151, 7, 99]:
		var plain := _decade_against_ardenia(seed, false)
		var covered := _decade_against_ardenia(seed, true)
		t.truth(plain["hostile"] > 0, "seed %d: Krasova moves against Ardenia (%d hostile moves; relations low %.2f, final %.2f)" % [
			seed, plain["hostile"], plain["lowest"], plain["final"]])
		t.truth(plain["warned"] > 0, "seed %d: and its threats are foreshadowed (%d warnings)" % [seed, plain["warned"]])
		t.equal(plain["shelved"], 0, "seed %d: without a pact nothing is shelved" % seed)
		t.truth(covered["shelved"] > 0, "seed %d: a defence pact shelves some of them (%d shelved, %d landed)" % [
			seed, covered["shelved"], covered["hostile"]])


static func _max_outreach(state: GameState) -> void:
	state.player.political_capital = 140.0
	DiplomacyActions.act(state, "hold_summit", "krasova")
	for _i in range(3):
		DiplomacyActions.act(state, "improve_relations", "krasova")


func _test_maximum_outreach_cannot_buy_off_krasova(t) -> void:
	for seed in [515151, 7, 99]:
		var state := _state("government", seed)
		var highest := -1.0
		var open_months := 0
		for _m in range(120):
			_max_outreach(state)
			NativeGameScript.close_month(state)
			if String(state.campaign_meta.get("vetrenka_status", "")) != "settled":
				open_months += 1
				highest = maxf(highest, _score(state, "krasova", "ardenia"))
		t.truth(open_months > 0 and highest < 0.0,
			"seed %d: ten years of maximum outreach keep Krasova below zero while Vetrenka is open (high %.2f)" % [seed, highest])


func _test_neglect_still_makes_a_feud_that_breathes(t) -> void:
	for seed in [515151, 7, 99]:
		var state := _state("government", seed)
		var feud := false
		var pinned := 0
		for _m in range(120):
			NativeGameScript.close_month(state)
			feud = feud or state.world_arcs.get("ardenia|krasova", "") == "feud"
			if _score(state, "krasova", "ardenia") <= -0.999:
				pinned += 1
		t.truth(feud, "seed %d: an unattended Krasova still becomes a feud" % seed)
		t.truth(pinned < 24, "seed %d: but the feud is not pinned at -1.00 (%d months there)" % [seed, pinned])


func _test_a_settled_vetrenka_lets_relations_warm_to_the_higher_cap(t) -> void:
	var state := _state("government", 515151)
	state.campaign_meta["vetrenka_status"] = "settled"
	var highest := -1.0
	for _m in range(120):
		_max_outreach(state)
		NativeGameScript.close_month(state)
		highest = maxf(highest, _score(state, "krasova", "ardenia"))
	t.truth(highest > 0.0 and highest <= DiplomacySim.SETTLED_CAUSE_WARMTH_CAP + 1e-9,
		"after a settlement Krasova can be warmed, up to the settled cap (high %.2f)" % highest)


func _test_a_pact_does_not_shield_you_from_your_partner(t) -> void:
	var state := _state()
	_sign_defence_pact(state, "veldoria")
	var shelved := 0
	for _i in range(200):
		if WorldSim.hostile_action(state, _c(state, "veldoria"), state.country, []) == "shelved":
			shelved += 1
		_set_score(state, "veldoria", "ardenia", 0.0)
	t.equal(shelved, 0, "a defence pact never shelves the partner's own hostile moves")


func _test_outreach_never_provokes_krasova(t) -> void:
	for seed in [515151, 7, 99]:
		var neglect := _decade_against_ardenia(seed, false)
		var courted := _decade_against_ardenia(seed, false, true)
		t.truth(float(courted["harm"]) <= float(neglect["harm"]),
			"seed %d: courting Krasova never makes it more hostile (harm %.3f courted, %.3f neglected)" % [seed, courted["harm"], neglect["harm"]])
		t.truth(float(courted["final"]) > float(neglect["final"]),
			"seed %d: courted relations end warmer (%.2f vs %.2f)" % [seed, courted["final"], neglect["final"]])
		t.truth(bool(neglect["feud"]), "seed %d: neglect still becomes a feud" % seed)
		t.truth(int(courted["hostile"]) + int(courted["shelved"]) >= 1, "seed %d: but the rivalry stays alive" % seed)


func _test_a_warmer_rival_waits_longer(t) -> void:
	t.truth(WorldSim.press_interval(-0.1) > WorldSim.press_interval(-0.7), "the warmer the relationship, the longer a rival waits between provocations")
	var state := _state()
	state.turn = 40
	_set_score(state, "krasova", "ardenia", -0.3)
	_c(state, "krasova").plan = {"objective": "court", "target": "qadir", "matures_turn": 40, "last_acted_turn": 39,
		"foreshadowed": false, "last_pressed_turn": 39}
	t.equal(WorldSim.national_interest(state, _c(state, "krasova"))["objective"], "court", "a rival that has just pressed tends its sphere")
	_c(state, "krasova").plan["last_pressed_turn"] = 0
	t.equal(WorldSim.national_interest(state, _c(state, "krasova")), {"objective": "undermine", "target": "ardenia"},
		"and presses again once its patience runs out")


func _test_one_plan_one_warning(t) -> void:
	var state := _state()
	state.turn = 20
	var krasova := _c(state, "krasova")
	for c in state.world:
		c.plan = {"objective": "consolidate", "target": "", "matures_turn": 9999, "last_acted_turn": -1, "foreshadowed": false}
	krasova.plan = {"objective": "undermine", "target": "ardenia", "matures_turn": 22, "last_acted_turn": -1, "foreshadowed": false}
	_world_month(state)
	_world_month(state)
	var carried := krasova.plan.duplicate()
	carried["objective"] = "undermine"
	carried["target"] = "ardenia"
	carried["matures_turn"] = state.turn + 2
	carried["foreshadowed"] = false
	krasova.plan = carried
	_world_month(state)
	_world_month(state)
	var warnings := state.monthly_news.filter(func(i): return i["key"] == "world_deliberates" and i["fields"]["actor"] == krasova.name)
	t.equal(warnings.size(), 1, "back-to-back plans against the same target leak once, not twice")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_each_agenda_reads_its_national_interest(t)
	_test_a_hegemon_with_a_spent_rivalry_tends_its_sphere(t)
	_test_krasova_presses_while_vetrenka_is_contested(t)
	_test_krasova_acts_against_ardenia_across_a_decade(t)
	_test_maximum_outreach_cannot_buy_off_krasova(t)
	_test_neglect_still_makes_a_feud_that_breathes(t)
	_test_a_settled_vetrenka_lets_relations_warm_to_the_higher_cap(t)
	_test_a_pact_does_not_shield_you_from_your_partner(t)
	_test_outreach_never_provokes_krasova(t)
	_test_a_warmer_rival_waits_longer(t)
	_test_one_plan_one_warning(t)
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
