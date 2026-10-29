extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const SLOT := "test_opposition_slice"


static func _state(role: String = "opposition", seed: int = 616161) -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": seed})
	state.rng = SimRng.from_seed(seed)
	BudgetSim.ensure_budget_state(state)
	state.player.political_capital = 120.0
	return state


static func _until_bill(state: GameState) -> void:
	for _m in range(12):
		if state.opposition.government_bill != null:
			return
		state.turn += 1
		OppositionSim.monthly(state)


static func _divide(state: GameState) -> Array[String]:
	state.turn += 1
	return OppositionSim.monthly(state)


func _test_the_government_runs_a_programme(t) -> void:
	var state := _state()
	t.truth(not state.player.in_government, "the campaign opens in opposition")
	state.turn = 1
	OppositionSim.monthly(state)
	t.truth(state.opposition.government_bill == null, "the government's first month is quiet")
	_until_bill(state)
	var bill := state.opposition.government_bill
	t.truth(bill != null, "then the government brings a bill")
	t.equal(bill.proposed_by, state.ruling_faction_id, "sponsored by the ruling party")
	t.truth(bill.tier != "executive_order", "through parliament, not by decree")
	t.truth(StateValidator.validate(state).is_empty(), "and the record validates")
	var notes := _divide(state)
	t.truth(state.opposition.government_bill == null, "the division comes the month after")
	t.truth(state.law_history.any(func(l: Law) -> bool: return l.id == bill.id and l.votes_for + l.votes_against > 0),
		"through the shared legislative pipeline")
	t.truth(notes.any(func(l: String) -> bool: return l.contains(bill.name)), "and the result is reported")
	var governing := _state("government")
	governing.turn = 6
	OppositionSim.monthly(governing)
	t.truth(governing.opposition.government_bill == null, "a governing player has no rival programme")


func _test_material_pressure_shapes_the_programme(t) -> void:
	var calm := _state()
	var alarmed := _state()
	alarmed.country.economy.inflation = 0.12
	var calm_bill := OppositionSim.choose_bill(calm)
	var alarmed_bill := OppositionSim.choose_bill(alarmed)
	t.truth(OppositionSim.material_relief(alarmed, alarmed_bill) > 0.0, "a government facing inflation answers it")
	var anti_inflation: Law = null
	for law in LawActions.catalog_laws():
		if law.tier != "executive_order" and float(law.effects.get("inflation_delta", 0.0)) < 0.0:
			anti_inflation = law
	t.truth(OppositionSim.pressure_score(alarmed, anti_inflation) > OppositionSim.pressure_score(calm, anti_inflation),
		"inflation raises the priority of a bill that fights it (calm choice %s, alarmed %s)" % [calm_bill.id, alarmed_bill.id])


func _test_a_failed_bill_is_not_retried_at_once(t) -> void:
	var state := _state()
	_until_bill(state)
	var first := state.opposition.government_bill.id
	_divide(state)
	state.turn = state.opposition.next_bill_turn - 1
	_until_bill(state)
	t.truth(state.opposition.government_bill.id != first, "the government moves on to new business")


func _test_responses_are_declared_once_and_move_votes(t) -> void:
	var a := _state()
	_until_bill(a)
	var b := GameState.from_dict(a.to_dict())
	var pc := a.player.political_capital
	t.truth(OppositionActions.respond(a, "support").get("ok", false), "the opposition can back the bill")
	t.near(a.player.political_capital, pc - 4.0, 1e-9, "at a price in political capital")
	t.truth(not OppositionActions.respond(a, "oppose").get("ok", true), "but only declares once")
	OppositionActions.respond(b, "oppose")
	var supported := LawActions.projection(a, a.opposition.government_bill)
	var opposed := LawActions.projection(b, b.opposition.government_bill)
	t.truth(int(supported["votes_for"]) > int(opposed["votes_for"]), "backing it brings more votes than opposing it")
	var governing := _state("government")
	t.truth(not OppositionActions.respond(governing, "support").get("ok", true), "a government cannot respond to itself")
	t.truth(not OppositionActions.respond(_state(), "support").get("ok", true), "nor can anyone respond to no bill")


func _test_an_amendment_pulls_the_bill_toward_you(t) -> void:
	var state := _state()
	_until_bill(state)
	var law := LawActions.canonical(state.opposition.government_bill)
	var original := law.to_dict()
	OppositionActions.apply_amendment(state, law)
	var before := Vector2(original["ideology_economic"] - state.player.ideology_economic,
		original["ideology_social"] - state.player.ideology_social).length()
	var after := Vector2(law.ideology_economic - state.player.ideology_economic,
		law.ideology_social - state.player.ideology_social).length()
	t.truth(after < before, "an amended bill sits closer to the opposition")
	var softer := true
	for key in OppositionActions.SOFTENED_EFFECTS:
		if absf(float(original["effects"].get(key, 0.0))) > 0.0 \
				and absf(float(law.effects[key])) >= absf(float(original["effects"][key])):
			softer = false
	t.truth(softer, "and its material effects are softened")
	t.truth(OppositionActions.respond(state, "amend").get("ok", false), "the amendment can be offered")
	_divide(state)
	t.truth(state.law_history[-1].ideology_economic != float(original["ideology_economic"])
		or state.law_history[-1].ideology_social != float(original["ideology_social"]),
		"and the division is on the amended text")


func _test_a_platform_of_at_most_three_pledges(t) -> void:
	var state := _state()
	var ids := ["minimum_wage_act", "education_modernisation_act", "press_freedom_act", "land_reform_act"]
	for i in range(3):
		t.truth(OppositionActions.add_pledge(state, ids[i]).get("ok", false), "pledge %d is published" % (i + 1))
	t.truth(not OppositionActions.add_pledge(state, ids[3]).get("ok", true), "a fourth is refused")
	t.truth(not OppositionActions.add_pledge(_state(), "emergency_price_controls").get("ok", true), "decrees cannot be pledged")
	var again := _state()
	OppositionActions.add_pledge(again, ids[0])
	t.truth(not OppositionActions.add_pledge(again, ids[0]).get("ok", true), "nor the same policy twice")
	t.truth(not OppositionActions.add_pledge(_state("government"), ids[0]).get("ok", true), "a government has no manifesto to write")


func _test_campaigning_builds_support_and_credibility_with_a_cooldown(t) -> void:
	var state := _state()
	OppositionActions.add_pledge(state, "minimum_wage_act")
	var own := OppositionSim.own_party(state)
	var support := own.support
	var cred := state.opposition.credibility
	t.truth(OppositionActions.campaign(state, "minimum_wage_act").get("ok", false), "the party campaigns on its pledge")
	t.truth(own.support > support and state.opposition.credibility > cred, "support and credibility rise")
	t.truth(not OppositionActions.campaign(state, "minimum_wage_act").get("ok", true), "the same pledge rests for a while")
	state.turn += OppositionActions.CAMPAIGN_COOLDOWN
	t.truth(OppositionActions.campaign(state, "minimum_wage_act").get("ok", false), "then can be campaigned on again")
	var unstaffed := _state()
	var staffed := _state()
	for s in [unstaffed, staffed]:
		OppositionActions.add_pledge(s, "minimum_wage_act")
	OppositionActions.appoint_shadow(staffed, "Economy")
	staffed.opposition.shadow_for("Economy").competence = 0.95
	staffed.opposition.shadow_for("Economy").loyalty = 0.95
	var c0 := unstaffed.opposition.credibility
	var c1 := staffed.opposition.credibility
	OppositionActions.campaign(unstaffed, "minimum_wage_act")
	OppositionActions.campaign(staffed, "minimum_wage_act")
	t.truth(staffed.opposition.credibility - c1 > unstaffed.opposition.credibility - c0,
		"an able shadow minister makes the campaign more credible")


func _test_dropping_an_advertised_pledge_costs_more(t) -> void:
	var quiet := _state()
	var loud := _state()
	for s in [quiet, loud]:
		OppositionActions.add_pledge(s, "minimum_wage_act")
	OppositionActions.campaign(loud, "minimum_wage_act")
	var q0 := quiet.opposition.credibility
	var l0 := loud.opposition.credibility
	OppositionActions.drop_pledge(quiet, "minimum_wage_act")
	OppositionActions.drop_pledge(loud, "minimum_wage_act")
	t.truth(quiet.opposition.credibility < q0, "dropping a pledge costs credibility")
	t.truth(l0 - loud.opposition.credibility > q0 - quiet.opposition.credibility, "more for a promise people heard")


func _test_consistency_with_your_promises(t) -> void:
	var a := _state()
	_until_bill(a)
	var bill_id := a.opposition.government_bill.id
	OppositionActions.add_pledge(a, bill_id)
	var b := GameState.from_dict(a.to_dict())
	var c0 := a.opposition.credibility
	OppositionActions.respond(a, "support")
	OppositionActions.respond(b, "oppose")
	t.truth(a.opposition.credibility > c0, "backing the bill you promised is consistent")
	t.truth(b.opposition.credibility < c0, "opposing it is not")


func _test_a_government_that_enacts_your_pledge(t) -> void:
	var law := LawActions.catalog_laws()[0]
	var backed := _state()
	var undercut := _state()
	var silent := _state()
	for s in [backed, undercut, silent]:
		OppositionActions.add_pledge(s, law.id)
		law.proposed_by = s.ruling_faction_id
	backed.opposition.response = "support"
	undercut.opposition.response = "oppose"
	var silent_before := silent.opposition.credibility
	OppositionSim.note_bill_result(backed, law, true)
	OppositionSim.note_bill_result(undercut, law, true)
	OppositionSim.note_bill_result(silent, law, true)
	t.equal(silent.opposition.pledge_for(law.id)["status"], "adopted", "a pledge passed while you stayed silent is still adopted")
	t.near(silent.opposition.credibility, silent_before, 1e-9, "but earns you nothing")
	t.equal(backed.opposition.pledge_for(law.id)["status"], "adopted", "a pledge you helped pass is adopted")
	t.equal(undercut.opposition.pledge_for(law.id)["status"], "undercut", "one passed over your opposition is undercut")
	t.truth(backed.opposition.credibility > undercut.opposition.credibility, "and only the first helps you")


func _test_a_shadow_cabinet_takes_office(t) -> void:
	var state := _state()
	t.truth(OppositionActions.appoint_shadow(state, "Finance").get("ok", false), "a shadow chancellor is named")
	var shadow := state.opposition.shadow_for("Finance")
	t.equal(shadow.faction_id, state.player.faction_id, "from the player's own party")
	var first := shadow.name
	OppositionActions.appoint_shadow(state, "Finance")
	t.equal(state.opposition.shadow_cabinet.size(), 1, "a reshuffle replaces rather than adds")
	var promoted := state.opposition.shadow_for("Finance")
	t.truth(promoted.name != first or promoted.id != shadow.id, "with a new face")
	OppositionActions.add_pledge(state, "minimum_wage_act")
	_until_bill(state)
	var bill := state.opposition.government_bill
	var notes := OppositionSim.take_office(state)
	t.truth(state.player.in_government, "an election victory puts the player in office")
	t.equal(state.player.title, "Prime Minister", "under the country's government title")
	t.equal(state.ruling_faction_id, state.player.faction_id, "at the head of the government")
	t.truth(state.ministers.any(func(m: Minister) -> bool: return m.id == promoted.id and m.portfolio == "Finance"),
		"the shadow chancellor becomes chancellor")
	t.truth(state.opposition.shadow_cabinet.is_empty(), "and the shadow cabinet is wound up")
	t.truth(state.opposition.government_bill == null and state.law_history[-1].id == bill.id
		and state.law_history[-1].status == "lapsed", "the outgoing government's bill lapses")
	t.truth(notes.any(func(l: String) -> bool: return l.contains("lapses")), "and the report says so")
	t.equal(state.opposition.mandate_start_turn, state.turn, "the platform becomes a mandate")
	t.equal(StateValidator.validate(state), PackedStringArray(), "the new government validates")


func _test_promises_kept_and_broken_feed_the_next_election(t) -> void:
	var kept := _state()
	var broken := _state()
	for s in [kept, broken]:
		OppositionActions.add_pledge(s, "minimum_wage_act")
		OppositionActions.add_pledge(s, "education_modernisation_act")
		OppositionSim.take_office(s)
	for law in LawActions.catalog_laws():
		if law.id in ["minimum_wage_act", "education_modernisation_act"]:
			law.proposed_by = kept.player.faction_id
			OppositionSim.note_bill_result(kept, law, true)
	t.truth(OppositionSim.electoral_edge(kept) > OppositionSim.electoral_edge(broken), "a delivered mandate is an electoral asset")
	var verdict := OppositionSim.judge_mandate(broken)
	t.equal(verdict["broken"], 2, "undelivered promises are judged broken")
	t.truth(OppositionSim.electoral_edge(broken) < 0.0, "and broken promises are a liability")
	var empty := _state()
	var platform := _state()
	OppositionActions.add_pledge(platform, "minimum_wage_act")
	OppositionActions.appoint_shadow(platform, "Economy")
	OppositionActions.campaign(platform, "minimum_wage_act")
	t.truth(OppositionSim.electoral_edge(platform) > OppositionSim.electoral_edge(empty),
		"a staffed, campaigned platform mobilises better than none")


func _test_the_opposition_events_are_playable(t) -> void:
	t.equal(EventsSim.unplayable_events(), [] as Array[String], "every authored situation can now play")
	var state := _state()
	state.turn = 10
	t.truth(not EventsSim.condition_met(state, "government_in_retreat"), "a government that has lost nothing has not retreated")
	state.opposition.last_government_defeat_turn = 9
	t.truth(EventsSim.condition_met(state, "government_in_retreat"), "after a defeat on the floor it has")
	t.truth(EventsSim.condition_met(state, "by_election_opening"), "a seated opposition can contest a by-election")
	t.truth(not EventsSim.condition_met(_state("government"), "by_election_opening"), "a government does not")
	var strong := _state()
	var weak := _state()
	OppositionSim.own_party(strong).support = 0.6
	OppositionSim.ruling_party(strong).support = 0.2
	OppositionSim.own_party(weak).support = 0.1
	OppositionSim.ruling_party(weak).support = 0.5
	var seats := OppositionSim.own_party(strong).seats
	var total := 0
	for f in strong.country.factions:
		total += f.seats
	Arcs.run(strong, "by_election_local_push")
	t.equal(OppositionSim.own_party(strong).seats, seats + 1, "a strong opposition takes the seat")
	var after := 0
	for f in strong.country.factions:
		after += f.seats
	t.equal(after, total, "from the government, not from thin air")
	var cred := weak.opposition.credibility
	var weak_seats := OppositionSim.own_party(weak).seats
	Arcs.run(weak, "by_election_national_push")
	t.equal(OppositionSim.own_party(weak).seats, weak_seats, "a weak opposition that nationalises the contest loses it")
	t.truth(weak.opposition.credibility < cred, "and pays for the overreach")
	var claim := _state()
	var offer := _state()
	var s0 := OppositionSim.own_party(claim).support
	Arcs.run(claim, "opposition_claims_retreat")
	Arcs.run(offer, "opposition_offers_alternative")
	t.truth(OppositionSim.own_party(claim).support - s0 > OppositionSim.own_party(offer).support - s0,
		"claiming the retreat is the quicker gain")
	t.truth(offer.opposition.credibility > claim.opposition.credibility, "publishing the alternative the stronger claim to office")


func _test_opposition_state_persists_and_validates(t) -> void:
	var state := _state()
	OppositionActions.add_pledge(state, "minimum_wage_act")
	OppositionActions.campaign(state, "minimum_wage_act")
	OppositionActions.appoint_shadow(state, "Justice")
	_until_bill(state)
	OppositionActions.respond(state, "amend")
	var reloaded := GameState.from_dict(state.to_dict())
	t.equal(reloaded.to_dict()["opposition"], state.to_dict()["opposition"], "the whole opposition record round-trips")
	t.truth(StateValidator.validate(reloaded).is_empty(), "and validates")
	var game = NativeGameScript.new()
	game._state = state
	t.truth(game.save(SLOT).get("ok", false), "it survives a real save")
	t.truth(game.load(SLOT).get("ok", false), "and load")
	t.equal(game._state.opposition.to_dict(), state.opposition.to_dict(), "unchanged")
	game.free()
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute("user://saves/%s.json%s" % [SLOT, suffix])
	var old := state.to_dict()
	old.erase("opposition")
	var legacy := GameState.from_dict(old)
	t.truth(legacy != null and legacy.opposition.pledges.is_empty() and is_equal_approx(legacy.opposition.credibility, 0.5),
		"an older save starts with an empty platform")
	var bad := GameState.from_dict(state.to_dict())
	bad.opposition.credibility = 1.5
	t.truth(not StateValidator.validate(bad).is_empty(), "impossible credibility is rejected")
	bad = GameState.from_dict(state.to_dict())
	for id in ["education_modernisation_act", "press_freedom_act", "land_reform_act"]:
		bad.opposition.pledges.append({"bill_id": id, "status": "pledged", "campaigns": 0})
	t.truth(not StateValidator.validate(bad).is_empty(), "a fourth pledge is rejected")
	bad = GameState.from_dict(state.to_dict())
	bad.opposition.pledges[0]["status"] = "forgotten"
	t.truth(not StateValidator.validate(bad).is_empty(), "an unknown pledge status is rejected")
	bad = GameState.from_dict(state.to_dict())
	bad.opposition.response = "filibuster"
	t.truth(not StateValidator.validate(bad).is_empty(), "an unknown response is rejected")
	bad = GameState.from_dict(state.to_dict())
	bad.player.in_government = true
	t.truth(not StateValidator.validate(bad).is_empty(), "a rival government bill under the player's own government is rejected")


func _test_opposition_years_replay_and_stay_bounded(t) -> void:
	var a := _state()
	var b := _state()
	var bills := 0
	for _m in range(60):
		NativeGameScript.close_month(a)
		NativeGameScript.close_month(b)
		if a.opposition.government_bill != null and a.opposition.bill_introduced_turn == a.turn:
			bills += 1
	t.truth(a.to_dict() == b.to_dict(), "one seed, one opposition term")
	t.truth(bills >= 6, "the government kept legislating (%d bills in five years)" % bills)
	var reloaded := GameState.from_dict(a.to_dict())
	var ok := true
	for _m in range(60):
		NativeGameScript.close_month(a)
		NativeGameScript.close_month(reloaded)
		ok = ok and StateValidator.validate(a).is_empty() and is_finite(a.opposition.credibility)
	t.truth(a.to_dict() == reloaded.to_dict(), "a reload continues the same term")
	t.truth(ok, "and ten years of opposition stay valid")


func _test_the_read_model_explains_every_choice(t) -> void:
	var state := _state()
	OppositionActions.add_pledge(state, "minimum_wage_act")
	OppositionActions.appoint_shadow(state, "Finance")
	var model := OppositionActions.read_model(state)
	var options: Array = model["pledge_options"]
	t.truth(options.size() >= 8 and not options.any(func(o): return o["id"] == "emergency_price_controls"),
		"every parliamentary bill is offered as a pledge, never a decree")
	var pledged: Dictionary = options.filter(func(o): return o["id"] == "minimum_wage_act")[0]
	t.truth(not pledged["eligible"] and String(pledged["disabled_reason"]) != "", "a pledged bill says why it cannot be pledged again")
	t.equal(model["portfolios"].size(), CabinetActions.CORE_PORTFOLIOS.size(), "every shadow post is listed")
	var finance: Dictionary = model["portfolios"].filter(func(p): return p["portfolio"] == "Finance")[0]
	t.truth(String(finance["holder"]) != "" and finance["eligible"], "with its holder, and can be reshuffled")
	t.truth(not OppositionActions.read_model(_state("government"))["portfolios"][0]["eligible"], "a government names no shadow team")


func _test_ai_governments_choose_from_the_saved_stream(t) -> void:
	var first := {}
	for seed in [1, 2, 3, 4, 5, 6, 7, 8]:
		var a := _state("opposition", seed)
		var b := _state("opposition", seed)
		var pick_a := OppositionSim.choose_bill(a)
		var pick_b := OppositionSim.choose_bill(b)
		t.equal(pick_a.id, pick_b.id, "seed %d: the same stream makes the same choice" % seed)
		first[pick_a.id] = true
	t.truth(first.size() >= 2, "different campaigns see different government programmes (%d first bills)" % first.size())
	var calm := _state("opposition", 1)
	var top := OppositionSim.ranked_bills(calm)
	t.truth(top.size() <= OppositionSim.PROGRAMME_SHORTLIST and top.has(OppositionSim.choose_bill(_state("opposition", 1)).id),
		"the choice always comes from the government's own shortlist")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_the_government_runs_a_programme(t)
	_test_material_pressure_shapes_the_programme(t)
	_test_a_failed_bill_is_not_retried_at_once(t)
	_test_responses_are_declared_once_and_move_votes(t)
	_test_an_amendment_pulls_the_bill_toward_you(t)
	_test_a_platform_of_at_most_three_pledges(t)
	_test_campaigning_builds_support_and_credibility_with_a_cooldown(t)
	_test_dropping_an_advertised_pledge_costs_more(t)
	_test_consistency_with_your_promises(t)
	_test_a_government_that_enacts_your_pledge(t)
	_test_a_shadow_cabinet_takes_office(t)
	_test_promises_kept_and_broken_feed_the_next_election(t)
	_test_the_opposition_events_are_playable(t)
	_test_opposition_state_persists_and_validates(t)
	_test_opposition_years_replay_and_stay_bounded(t)
	_test_the_read_model_explains_every_choice(t)
	_test_ai_governments_choose_from_the_saved_stream(t)
	quit(t.finish())
