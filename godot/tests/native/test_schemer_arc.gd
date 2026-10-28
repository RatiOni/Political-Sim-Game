extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")

const ARC := ["a_schemer_stirs", "a_schemer_confronted", "a_schemer_moves",
	"a_schemer_triumphant", "party_leadership_challenge"]


static func _state(role: String = "contextual") -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	state.player.political_capital = 500.0
	return state


static func _schemer(state: GameState) -> Minister:
	for m in state.ministers:
		if m.trait_id == "schemer":
			return m
	return null


static func _arm(state: GameState) -> Minister:
	var m := _schemer(state)
	m.ambition = 0.95
	m.loyalty = 0.20
	return m


static func _force(state: GameState, event_id: String) -> void:
	var s := Situation.new()
	s.event_id = event_id
	s.arrived_turn = state.turn
	s.deadline_turn = state.turn + EventsSim.DECISION_WINDOW_MONTHS
	state.pending_situations.append(s)


static func _decide(state: GameState, event_id: String, option_id: String) -> Dictionary:
	_force(state, event_id)
	return EventActions.resolve(state, event_id, option_id)


static func _scheduled(state: GameState, event_id: String) -> Dictionary:
	for row in state.scheduled_events:
		if row["event_id"] == event_id:
			return row
	return {}


static func _own_dominant_wing(state: GameState) -> Faction.Wing:
	for f in state.country.factions:
		if f.id == state.player.faction_id:
			return f.dominant_wing()
	return null


func _test_a_schemer_grows_more_dangerous_each_month(t) -> void:
	var state := _state()
	var m := _schemer(state)
	t.truth(m != null, "Ardenia's opening cabinet contains a schemer")
	if m == null:
		return
	var threat0 := m.threat_level()
	for _i in range(24):
		CabinetSim.monthly(state)
	t.truth(m.threat_level() > threat0 + 0.1,
		"two years later the schemer is markedly more dangerous (%.2f -> %.2f)" % [threat0, m.threat_level()])
	t.truth(m.ambition <= 1.0 and m.loyalty >= 0.0, "within bounds")


func _test_a_loyalist_holds_their_floor(t) -> void:
	var state := _state()
	var m: Minister = state.ministers[0]
	m.trait_id = "loyalist"
	m.loyalty = 0.40
	CabinetSim.monthly(state)
	t.truth(m.loyalty >= Minister.trait_effect("loyalist", "loyalty_floor"),
		"a loyalist's loyalty never sits below their floor")


func _test_the_arc_opens_only_when_the_danger_is_real(t) -> void:
	var state := _state()
	t.truth(not EventsSim.condition_met(state, "schemer_plotting"), "not on day one")
	_arm(state)
	t.truth(EventsSim.condition_met(state, "schemer_plotting"), "but once the schemer's threat passes one half")
	var opp := _state("opposition")
	_arm(opp)
	t.truth(not EventsSim.condition_met(opp, "schemer_plotting"), "and never for a leader out of office")


func _test_the_whole_arc_is_playable(t) -> void:
	var held := EventsSim.unplayable_events()
	var missing: Array = []
	for id in ARC:
		if id in held:
			missing.append(id)
	t.equal(missing, [], "every step of the schemer arc and the challenge can now fire")


func _test_confronting_early_leads_to_a_reckoning(t) -> void:
	var state := _state()
	_arm(state)
	t.truth(_decide(state, "a_schemer_stirs", "confront").get("ok", false), "the government confronts")
	var row := _scheduled(state, "a_schemer_confronted")
	t.equal(int(row.get("due_turn", -1)), state.turn + 2, "and the reckoning comes two months later")


func _test_buying_off_keeps_them_but_loyal(t) -> void:
	var state := _state()
	var m := _arm(state)
	var count := state.ministers.size()
	t.truth(_decide(state, "a_schemer_confronted", "buy_off").get("ok", false), "the schemer is bought off")
	t.near(m.loyalty, 0.55, 1e-9, "their loyalty rises by 0.35")
	t.equal(state.ministers.size(), count, "and they keep their post")
	m.loyalty = 0.80
	_decide(state, "a_schemer_confronted", "buy_off")
	t.near(m.loyalty, 0.95, 1e-9, "but bought loyalty never exceeds 0.95")


func _test_demanding_resignation_removes_them(t) -> void:
	var state := _state()
	var m := _arm(state)
	_decide(state, "a_schemer_confronted", "demand_resignation")
	t.truth(not state.ministers.has(m), "the schemer leaves the cabinet")
	t.equal(_schemer(state), null, "and no schemer remains")


func _test_waiting_lets_them_move(t) -> void:
	var state := _state()
	_arm(state)
	_decide(state, "a_schemer_stirs", "wait")
	t.equal(int(_scheduled(state, "a_schemer_moves").get("due_turn", -1)), state.turn + 3,
		"waiting gives the schemer three months")


func _test_crushing_late_costs_stability(t) -> void:
	var state := _state()
	var m := _arm(state)
	var stab0 := state.stability_value
	_decide(state, "a_schemer_moves", "crush_late")
	t.truth(not state.ministers.has(m), "a late crackdown still removes them")
	t.near(state.stability_value, maxf(0.05, stab0 - 0.04), 1e-9, "but shakes the government")


func _test_exposing_removes_them(t) -> void:
	var state := _state()
	var m := _arm(state)
	_decide(state, "a_schemer_moves", "expose")
	t.truth(not state.ministers.has(m), "exposure ends their career")


func _test_too_late_emboldens_the_party_and_escalates(t) -> void:
	var state := _state()
	var m := _arm(state)
	var wing := _own_dominant_wing(state)
	var loyalty0 := wing.loyalty
	_decide(state, "a_schemer_moves", "too_late")
	t.truth(state.ministers.has(m), "the schemer stays, stronger")
	t.near(wing.loyalty, maxf(-1.0, loyalty0 - 0.15), 1e-9, "their allies in your party are emboldened")
	t.truth(not _scheduled(state, "a_schemer_triumphant").is_empty(), "and they come for the leadership")


func _test_the_triumphant_schemer_forces_a_challenge(t) -> void:
	var state := _state()
	_arm(state)
	_decide(state, "a_schemer_triumphant", "fight_it_out")
	t.equal(int(_scheduled(state, "party_leadership_challenge").get("due_turn", -1)), state.turn + 1,
		"an open fight brings a formal leadership challenge next month")


func _test_a_departed_schemer_makes_later_steps_quiet(t) -> void:
	var state := _state()
	var m := _arm(state)
	state.ministers.erase(m)
	var count := state.ministers.size()
	var r := _decide(state, "a_schemer_moves", "expose")
	t.truth(r.get("ok", false), "a later step still resolves when its subject has left")
	t.equal(state.ministers.size(), count, "and touches nobody else")


func _test_facing_down_cows_the_wing(t) -> void:
	var state := _state()
	var wing := _own_dominant_wing(state)
	var l0 := wing.loyalty
	_decide(state, "party_leadership_challenge", "face_down")
	t.near(wing.loyalty, maxf(-1.0, l0 - 0.08), 1e-9, "facing it down leaves the wing cowed but resentful")


func _test_accommodating_moves_the_leader_toward_the_wing(t) -> void:
	var state := _state()
	var wing := _own_dominant_wing(state)
	var econ0 := state.player.ideology_economic
	var l0 := wing.loyalty
	_decide(state, "party_leadership_challenge", "accommodate")
	t.near(state.player.ideology_economic, econ0 + (wing.ideology.economic - econ0) * 0.15, 1e-9,
		"accommodation moves the leader 15% of the way toward the wing")
	t.near(wing.loyalty, minf(1.0, l0 + 0.25), 1e-9, "and wins the wing back")


func _test_purging_weakens_the_wing_and_the_party(t) -> void:
	var state := _state()
	var party: Faction = null
	for f in state.country.factions:
		if f.id == state.player.faction_id:
			party = f
	var wing := party.dominant_wing()
	var s0 := wing.strength
	var stab0 := state.stability_value
	var others := {}
	for w in party.wings:
		if w != wing:
			others[w] = w.loyalty
	_decide(state, "party_leadership_challenge", "purge")
	t.truth(wing.strength < s0, "the purged wing loses ground")
	var all_down := true
	for w in others:
		if w.loyalty > others[w] - 0.10 + 1e-9:
			all_down = false
	t.truth(all_down, "every wing of the party loses loyalty")
	t.near(state.stability_value, maxf(0.05, stab0 - 0.05), 1e-9, "and the government is shaken")


func _test_a_government_that_never_engages_ends_up_challenged(t) -> void:
	var state := _state()
	state.player.political_capital = 0.0
	_arm(state)
	_force(state, "a_schemer_stirs")
	var reached := false
	for _i in range(24):
		state.turn += 1
		EventsSim.monthly(state)
		for s in state.pending_situations:
			if s.event_id == "party_leadership_challenge":
				reached = true
		if reached:
			break
	t.truth(reached, "a government that lets every step lapse is eventually challenged for the leadership")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_a_schemer_grows_more_dangerous_each_month(t)
	_test_a_loyalist_holds_their_floor(t)
	_test_the_arc_opens_only_when_the_danger_is_real(t)
	_test_the_whole_arc_is_playable(t)
	_test_confronting_early_leads_to_a_reckoning(t)
	_test_buying_off_keeps_them_but_loyal(t)
	_test_demanding_resignation_removes_them(t)
	_test_waiting_lets_them_move(t)
	_test_crushing_late_costs_stability(t)
	_test_exposing_removes_them(t)
	_test_too_late_emboldens_the_party_and_escalates(t)
	_test_the_triumphant_schemer_forces_a_challenge(t)
	_test_a_departed_schemer_makes_later_steps_quiet(t)
	_test_facing_down_cows_the_wing(t)
	_test_accommodating_moves_the_leader_toward_the_wing(t)
	_test_purging_weakens_the_wing_and_the_party(t)
	_test_a_government_that_never_engages_ends_up_challenged(t)
	quit(t.finish())
