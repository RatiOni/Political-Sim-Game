extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const SLOT := "test_elections_slice"


static func _state(role: String = "government", seed: int = 818181) -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": seed})
	state.rng = SimRng.from_seed(seed)
	BudgetSim.ensure_budget_state(state)
	state.player.political_capital = 120.0
	return state


static func _faction(state: GameState, id: String) -> Faction:
	for f in state.country.factions:
		if f.id == id:
			return f
	return null


static func _total_seats(state: GameState) -> int:
	var total := 0
	for f in state.country.factions:
		total += f.seats
	return total


static func _make_landslide(state: GameState, winner_id: String) -> void:
	for f in state.country.factions:
		f.support = 0.70 if f.id == winner_id else 0.05
	for region in state.regions.values():
		var r: RegionState = region
		for key in r.party_support:
			r.party_support[key] = 0.70 if key == winner_id else 0.05


static func _rival_id(state: GameState) -> String:
	for f in state.country.factions:
		if f.id != state.player.faction_id and f.seats > 0:
			return f.id
	return ""


func _test_the_count_is_deterministic(t) -> void:
	var a := _state()
	var b := GameState.from_dict(a.to_dict())
	t.equal(Elections.tally(a), Elections.tally(b), "the same country gives the same count")
	var rng_before := a.rng.to_dict()
	Elections.tally(a)
	t.equal(a.rng.to_dict(), rng_before, "and counting draws nothing from the campaign stream")
	var ra := Elections.hold(a, false)
	var rb := Elections.hold(b, false)
	t.equal(ra.to_dict(), rb.to_dict(), "and the same election result")


func _test_seats_follow_the_largest_remainder(t) -> void:
	t.equal(Elections.allocate_seats({"a": 50.0, "b": 30.0, "c": 20.0}, 10), {"a": 5, "b": 3, "c": 2}, "proportional seats")
	t.equal(Elections.allocate_seats({"a": 45.0, "b": 35.0, "c": 20.0}, 7), {"a": 3, "b": 3, "c": 1},
		"the largest remainders take the leftover seats")
	var below := Elections.allocate_seats({"a": 97.5, "b": 2.5}, 100)
	t.equal(below["b"], 0, "a party under the threshold wins nothing")
	t.equal(below["a"], 100, "and its share goes to those above it")
	var state := _state()
	var total := _total_seats(state)
	Elections.hold(state, false)
	t.equal(_total_seats(state), total, "an election fills exactly the chamber")


func _test_who_can_vote_depends_on_who_governs_the_ground(t) -> void:
	var state := _state()
	state.regions["vetrenka"].control = "separatist"
	state.regions["anera"].control = "limited"
	var count := Elections.tally(state)
	t.equal(float(count["regional_access"]["vetrenka"]), 0.0, "separatist Vetrenka has no poll")
	t.equal(float(count["regional_turnout"]["vetrenka"]), 0.0, "and casts no ballot")
	t.truth(float(count["regional_access"]["anera"]) < float(count["regional_access"]["vashtera"]),
		"a limited region has less access than an administered one")
	t.truth(float(count["regional_turnout"]["anera"]) < float(count["regional_turnout"]["vashtera"]),
		"and casts fewer ballots")
	state.regions["vetrenka"].control = "state"
	t.truth(float(Elections.tally(state)["regional_access"]["vetrenka"]) > 0.0, "a returned Vetrenka votes again")


func _test_a_credible_platform_flips_a_close_election(t) -> void:
	var probe := _state("opposition")
	var own_id := probe.player.faction_id
	var ruling_id := probe.ruling_faction_id
	var flipped := false
	for step in range(0, 60):
		var empty := _state("opposition")
		var platform := _state("opposition")
		for s in [empty, platform]:
			var shift := -0.06 + step * 0.002
			_faction(s, own_id).support = _faction(s, ruling_id).support + shift
		for bill in ["minimum_wage_act", "education_modernisation_act", "press_freedom_act"]:
			OppositionActions.add_pledge(platform, bill)
		for portfolio in CabinetActions.CORE_PORTFOLIOS:
			OppositionActions.appoint_shadow(platform, portfolio)
		platform.opposition.credibility = 0.95
		for p in platform.opposition.pledges:
			p["campaigns"] = 3
		var lost := Elections.hold(empty, false)
		var won := Elections.hold(platform, false)
		if not lost.player_in_government and won.player_in_government:
			flipped = true
			t.truth(int(won.final_seats[own_id]) > int(lost.final_seats[own_id]), "the platform is worth seats")
			break
	t.truth(flipped, "in a close race a credible, staffed, campaigned platform wins what an empty one loses")
	var kept := _state("opposition")
	var broken := _state("opposition")
	for s in [kept, broken]:
		OppositionActions.add_pledge(s, "minimum_wage_act")
		OppositionActions.add_pledge(s, "education_modernisation_act")
		OppositionSim.take_office(s)
	for p in kept.opposition.pledges:
		p["status"] = "delivered"
	var kept_result := Elections.hold(kept, false)
	var broken_result := Elections.hold(broken, false)
	t.truth(float(kept_result.vote_share[kept.player.faction_id]) > float(broken_result.vote_share[broken.player.faction_id]),
		"a government that kept its promises polls better than one that broke them")
	t.equal(int(broken_result.mandate["broken"]), 2, "and the broken ones are named in the result")


func _test_household_confidence_judges_the_sitting_party(t) -> void:
	var content := _state()
	var hurting := _state()
	HouseholdsSim.ensure_households(content)
	HouseholdsSim.ensure_households(hurting)
	t.truth(not content.households.is_empty(), "Ardenia's households are counted")
	for g in content.households.values():
		(g as HouseholdGroupState).confidence = 0.85
	for g in hurting.households.values():
		(g as HouseholdGroupState).confidence = 0.15
	var a := Elections.tally(content)
	var b := Elections.tally(hurting)
	t.truth(float(a["vote_share"][content.ruling_faction_id]) > float(b["vote_share"][hurting.ruling_faction_id]),
		"confident households re-elect a government; struggling ones punish it")


func _test_a_government_that_loses_goes_into_opposition(t) -> void:
	var state := _state("government")
	LawActions.propose(state, "minimum_wage_act")
	var rival := _rival_id(state)
	_make_landslide(state, rival)
	var result := Elections.hold(state, false)
	t.truth(result.player_lost_office and not state.player.in_government, "losing the election loses office")
	t.equal(state.player.title, "Opposition Leader", "the player now leads the opposition")
	t.equal(state.ruling_faction_id, rival, "the winner governs")
	t.truth(state.pending_law == null and state.law_history[-1].status == "lapsed", "the player's own bill lapses")
	var coalition := state.coalition_faction_ids()
	t.truth(state.ministers.size() == CabinetActions.CORE_PORTFOLIOS.size()
		and state.ministers.all(func(m: Minister) -> bool: return m.faction_id in coalition),
		"the new government fills every post from its own coalition")
	t.equal(StateValidator.validate(state), PackedStringArray(), "and the new order validates")
	for _m in range(4):
		NativeGameScript.close_month(state)
	t.truth(state.opposition.government_bill != null or not state.law_history.is_empty(), "the new government legislates")


func _test_an_opposition_that_wins_takes_office_with_its_team(t) -> void:
	var state := _state("opposition")
	OppositionActions.appoint_shadow(state, "Finance")
	var shadow_id := state.opposition.shadow_for("Finance").id
	var outgoing := state.ministers.map(func(m: Minister) -> String: return m.id)
	for _m in range(3):
		NativeGameScript.close_month(state)
	var had_bill := state.opposition.government_bill != null
	_make_landslide(state, state.player.faction_id)
	var result := Elections.hold(state, false)
	t.truth(result.player_gained_office and state.player.in_government, "winning from opposition takes office")
	t.equal(state.player.title, "Prime Minister", "under the government's title")
	t.truth(state.ministers.any(func(m: Minister) -> bool: return m.id == shadow_id and m.portfolio == "Finance"),
		"the shadow chancellor becomes chancellor")
	t.truth(not state.ministers.any(func(m: Minister) -> bool: return m.id in outgoing),
		"no outgoing minister survives, even in a post without a shadow")
	t.equal(state.ministers.size(), CabinetActions.CORE_PORTFOLIOS.size(), "every post is filled")
	var coalition := state.coalition_faction_ids()
	t.truth(state.ministers.all(func(m: Minister) -> bool: return m.faction_id in coalition),
		"by the new coalition")
	t.truth(state.opposition.government_bill == null, "the outgoing government's business lapses")
	if had_bill:
		t.equal(state.law_history[-1].status, "lapsed", "and is recorded as lapsed")
	t.equal(StateValidator.validate(state), PackedStringArray(), "the new government validates")


func _test_elections_come_on_schedule(t) -> void:
	var state := _state()
	t.equal(Elections.months_until(state), Elections.TERM_MONTHS, "a campaign opens at the start of a term")
	var held: Array[int] = []
	for _m in range(Elections.TERM_MONTHS * 2):
		NativeGameScript.close_month(state)
		if not state.election_history.is_empty() and state.election_history[-1].turn == state.turn:
			held.append(state.turn)
	t.equal(held, [Elections.TERM_MONTHS, Elections.TERM_MONTHS * 2] as Array[int], "the country votes when each term ends")
	t.equal(state.last_election_turn, Elections.TERM_MONTHS * 2, "and the clock restarts")


func _test_the_election_is_reported(t) -> void:
	var state := _state()
	state.turn = Elections.TERM_MONTHS - 1
	NativeGameScript.close_month(state)
	var winner: Faction = _faction(state, state.ruling_faction_id)
	t.truth(String(state.front_page["lead"]["headline"]).contains(winner.name.to_upper()), "the election leads the paper")
	t.truth(state.monthly_digest.any(func(l: String) -> bool: return l.begins_with("GENERAL ELECTION")), "the report carries the result")
	t.truth(state.monthly_digest.any(func(l: String) -> bool: return l.begins_with("Regions:") and l.contains("Vashtera")),
		"and a line of regional results")


func _test_results_persist_and_old_saves_load(t) -> void:
	var state := _state()
	Elections.hold(state, false)
	var reloaded := GameState.from_dict(state.to_dict())
	t.equal(reloaded.to_dict()["election_history"], state.to_dict()["election_history"], "results round-trip")
	t.equal(reloaded.last_election_turn, state.last_election_turn, "and so does the term clock")
	var game = NativeGameScript.new()
	game._state = state
	t.truth(game.save(SLOT).get("ok", false) and game.load(SLOT).get("ok", false), "through a real save and load")
	t.equal(game._state.election_history[-1].to_dict(), state.election_history[-1].to_dict(), "unchanged")
	game.free()
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute("user://saves/%s.json%s" % [SLOT, suffix])
	var old := _state().to_dict()
	old.erase("election_history")
	old.erase("last_election_turn")
	var legacy := GameState.from_dict(old)
	t.truth(legacy != null and legacy.election_history.is_empty() and legacy.last_election_turn == 0, "an older save starts a fresh term")


func _test_the_validator_rejects_impossible_results(t) -> void:
	var state := _state()
	Elections.hold(state, false)
	t.truth(StateValidator.validate(state).is_empty(), "a real result validates")
	var cases := {
		"turnout above one": func(r: ElectionResult) -> void: r.turnout = 1.5,
		"seats that do not fill the chamber": func(r: ElectionResult) -> void: r.final_seats[r.final_seats.keys()[0]] += 7,
		"a vote share above one": func(r: ElectionResult) -> void: r.vote_share[r.vote_share.keys()[0]] = 1.4,
		"an unknown region": func(r: ElectionResult) -> void: r.regional_access["atlantis"] = 0.5,
		"an unknown ruling party": func(r: ElectionResult) -> void: r.ruling_faction_id = "nobody",
		"a result from the future": func(r: ElectionResult) -> void: r.turn = 999,
	}
	for label in cases:
		var bad := GameState.from_dict(state.to_dict())
		(cases[label] as Callable).call(bad.election_history[-1])
		t.truth(not StateValidator.validate(bad).is_empty(), "the validator rejects %s" % label)


static func _bounded(state: GameState) -> bool:
	var econ := state.country.economy
	for v in [state.player.approval, state.stability_value, state.civil_war_risk, state.opposition.credibility]:
		if not is_finite(v) or v < 0.0 or v > 1.0:
			return false
	for v in [econ.gdp, econ.inflation, econ.unemployment, econ.public_debt_pct, state.player.political_capital]:
		if not is_finite(v):
			return false
	return econ.gdp > 0.0 and econ.inflation < 0.5 and econ.public_debt_pct < 3.0 and StateValidator.validate(state).is_empty()


func _test_twenty_years_of_elections_stay_bounded(t) -> void:
	for role in ["government", "opposition"]:
		var state := _state(role)
		var ok := true
		for _m in range(240):
			NativeGameScript.close_month(state)
			if not _bounded(state):
				ok = false
				t.equal(StateValidator.validate(state), PackedStringArray(), "%s journey broke at turn %d" % [role, state.turn])
				break
		var changes := 0
		for r in state.election_history:
			if r.player_lost_office or r.player_gained_office:
				changes += 1
		t.truth(ok, "twenty years from %s stay finite, bounded and valid" % role)
		t.truth(state.election_history.size() >= 4, "with at least four elections (%d, %d changes of office)" % [state.election_history.size(), changes])
		var totals_ok := state.election_history.all(func(r: ElectionResult) -> bool:
			var total := 0
			for v in r.final_seats.values():
				total += int(v)
			return total == _total_seats(state) and r.turnout > 0.2 and r.turnout < 0.95)
		t.truth(totals_ok, "and every result fills the chamber on a plausible turnout")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_the_count_is_deterministic(t)
	_test_seats_follow_the_largest_remainder(t)
	_test_who_can_vote_depends_on_who_governs_the_ground(t)
	_test_a_credible_platform_flips_a_close_election(t)
	_test_household_confidence_judges_the_sitting_party(t)
	_test_a_government_that_loses_goes_into_opposition(t)
	_test_an_opposition_that_wins_takes_office_with_its_team(t)
	_test_elections_come_on_schedule(t)
	_test_the_election_is_reported(t)
	_test_results_persist_and_old_saves_load(t)
	_test_the_validator_rejects_impossible_results(t)
	_test_twenty_years_of_elections_stay_bounded(t)
	quit(t.finish())
