extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const SLOT := "test_foreign_situations"


static func _state(role: String = "government", seed: int = 424242) -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": seed})
	state.rng = SimRng.from_seed(seed)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	return state


static func _wipe() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := "user://saves/%s.json%s" % [SLOT, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


static func _score(state: GameState, id: String) -> float:
	return (state.country.relations[id] as Country.BilateralRelation).score


static func _set_score(state: GameState, id: String, value: float) -> void:
	DiplomacySim.shift(state, id, value - _score(state, id))


static func _force(state: GameState, event_id: String, target := "") -> Situation:
	var s := Situation.new()
	s.event_id = event_id
	s.arrived_turn = state.turn
	s.deadline_turn = state.turn + EventsSim.DECISION_WINDOW_MONTHS
	s.target_country_id = target
	state.pending_situations.append(s)
	state.event_fire_history[event_id] = state.turn
	return s


static func _rejects(t, state: GameState, fragment: String, label: String) -> void:
	var errors := StateValidator.validate(state)
	t.truth(Array(errors).any(func(e) -> bool: return String(e).contains(fragment)), label)


func _test_every_sentinel_names_a_live_country(t) -> void:
	var state := _state()
	t.equal(ForeignArcs.resolve_target(state, "__supplier__"), state.foreign.gas.supplier_id, "the supplier is the gas contract's supplier")
	t.equal(ForeignArcs.resolve_target(state, "__western__"), String(ForeignSim.power("concert")["anchor"]), "the West is the Concert's anchor")
	t.equal(ForeignArcs.resolve_target(state, "__union_anchor__"), String(ForeignSim.power("union")["anchor"]), "the Union is its anchor")
	var rival := ForeignArcs.resolve_target(state, "__rival__")
	t.truth(rival != "" and DiplomacySim.is_rival_of_player(state, state.world_country(rival)), "the rival is a country whose rival is the player")
	var warmest := ForeignArcs.resolve_target(state, "__warmest__")
	for key in state.country.relations:
		t.truth(_score(state, warmest) >= _score(state, String(key)), "nobody is warmer than the warmest (%s)" % key)
	t.equal(ForeignArcs.resolve_target(state, "__nobody__"), "", "an unknown sentinel names nobody")


func _test_the_war_and_the_coup_sentinels_read_the_world(t) -> void:
	var state := _state()
	for c in state.world:
		c.in_civil_war = false
		c.stability = 0.8
		c.civil_war_risk = 0.0
	t.equal(ForeignArcs.resolve_target(state, "__in_civil_war__"), "", "no war, no warring neighbour")
	t.equal(ForeignArcs.resolve_target(state, "__fragile__"), "", "no fragile state, no coup")
	var a := state.world_country(ForeignArcs.resolve_target(state, "__western__"))
	a.in_civil_war = true
	t.equal(ForeignArcs.resolve_target(state, "__in_civil_war__"), a.id, "a country at war with itself is found")
	a.in_civil_war = false
	a.regime_type = "parliamentary_democracy"
	a.stability = ForeignArcs.COUP_STABILITY
	t.equal(ForeignArcs.resolve_target(state, "__fragile__"), "", "at exactly the coup line a state holds")
	a.stability = ForeignArcs.COUP_STABILITY - 0.01
	t.equal(ForeignArcs.resolve_target(state, "__fragile__"), a.id, "just below it a state is ripe for a coup")
	a.civil_war_risk = ForeignArcs.COUP_MAX_WAR_RISK
	t.equal(ForeignArcs.resolve_target(state, "__fragile__"), "", "a state sliding into civil war is left to its war")
	a.civil_war_risk = 0.0
	a.regime_type = "authoritarian"
	t.equal(ForeignArcs.resolve_target(state, "__fragile__"), "", "an autocracy does not have a coup")


func _test_the_concert_foe_is_cold_to_the_west_and_unsanctioned(t) -> void:
	var state := _state()
	var west := state.world_country(ForeignArcs.resolve_target(state, "__western__"))
	for c in state.world:
		if c != west:
			DiplomacySim.shift_between(c, west, 0.5 - c.get_relation(west.id).score)
	t.equal(ForeignArcs.resolve_target(state, "__concert_foe__"), "", "no one cold to the Concert, no coalition")
	var foe: Country = null
	for c in state.world:
		if c != west and c.id != ForeignArcs.resolve_target(state, "__union_anchor__"):
			foe = c
			break
	foe.get_relation(west.id).score = ForeignArcs.CONCERT_FOE_LINE
	west.get_relation(foe.id).score = ForeignArcs.CONCERT_FOE_LINE
	t.equal(ForeignArcs.resolve_target(state, "__concert_foe__"), "", "at exactly the line it is not yet a foe")
	DiplomacySim.shift_between(foe, west, -0.01)
	t.equal(ForeignArcs.resolve_target(state, "__concert_foe__"), foe.id, "just below it the Concert wants it sanctioned")
	(state.country.relations[foe.id] as Country.BilateralRelation).sanctioned = true
	t.equal(ForeignArcs.resolve_target(state, "__concert_foe__"), "", "and not once Ardenia already sanctions it")


func _test_a_declared_target_is_fixed_on_arrival_and_follows_on(t) -> void:
	var state := _state()
	var event := {"id": "probe", "target": "__supplier__", "options": [{"id": "a", "relation_deltas": {"__supplier__": -0.1}}]}
	t.equal(EventsSim._diplomatic_target(state, event), state.foreign.gas.supplier_id, "a declared target resolves on arrival")
	var legacy := {"id": "probe", "options": [{"id": "a", "relation_deltas": {"__coolest__": -0.1}}]}
	t.equal(EventsSim._diplomatic_target(state, legacy), EventsSim._worst_relation(state, INF), "an undeclared target keeps the old inference")
	var s := Situation.new()
	s.target_country_id = state.foreign.gas.supplier_id
	var before := _score(state, s.target_country_id)
	EventsSim.apply_option(state, event, event["options"][0], s, false)
	t.near(_score(state, s.target_country_id), before - 0.1, 1e-9, "a sentinel delta lands on the situation's own target")
	t.truth("__supplier__" in EventsSim.TARGET_KEYS, "the new sentinels are target keys")
	for key in ForeignArcs.TARGETS:
		t.truth(key in EventsSim.TARGET_KEYS, "%s is a target key" % key)


func _test_data_gates_speak_with_the_action_layers_voice(t) -> void:
	var state := _state()
	state.player.political_capital = 0.0
	var energy := {"requires": {"energy_verb": "gas_spot_purchase"}}
	t.equal(EventsSim.gate_reason(state, energy), EnergyActions.reason_for(state, "gas_spot_purchase"), "an energy gate gives the energy desk's reason")
	t.truth(EventsSim.gate_reason(state, energy) != "", "and it refuses a government with no capital")
	state.player.political_capital = 200.0
	t.equal(EventsSim.gate_reason(state, energy), "", "and opens once the action is possible")
	var orientation := {"requires": {"orientation_verb": "isf_renegotiate"}}
	t.equal(EventsSim.gate_reason(state, orientation), OrientationActions.reason_for(state, "isf_renegotiate"), "an orientation gate gives the orientation desk's reason")
	var target := ForeignArcs.resolve_target(state, "__western__")
	_set_score(state, target, 0.5)
	var diplomacy := {"requires": {"diplomacy_verb": "impose_sanctions"}}
	t.equal(EventsSim.gate_reason(state, diplomacy, target), DiplomacyActions.reason_for(state, "impose_sanctions", target), "a diplomacy gate judges the situation's own target")
	t.equal(EventActions.option_reason(state, diplomacy, target), DiplomacyActions.reason_for(state, "impose_sanctions", target), "and refuses to sanction a friend, through the event desk too")
	t.truth(EventActions.option_reason(state, diplomacy, target) != "", "a friend is refused")
	t.equal(EventsSim.gate_reason(state, {"requires": {"background": "economist"}}), "Only open to a leader with the economist background.", "old gates are unchanged")


func _test_a_triggered_situation_arrives_this_month_and_never_goes_stale(t) -> void:
	var state := _state()
	state.turn = 10
	var event := EventsSim.event_by_id("bank_run").duplicate(true)
	ForeignArcs.schedule(state, "bank_run", "krasova")
	t.equal(state.scheduled_events[-1], {"event_id": "bank_run", "due_turn": 10, "target_country_id": "krasova"}, "a trigger is due this very month")
	var notes: Array[String] = []
	EventsSim._deliver_follow_ups(state, notes)
	t.equal(state.pending_situations.size(), 1, "and is delivered at once")
	t.equal(state.pending_situations[0].target_country_id, "krasova", "about the country that triggered it")
	state.pending_situations.clear()
	EventsSim._by_id["stale_probe"] = event.merged({"id": "stale_probe", "stale_after": 1}, true)
	state.scheduled_events.append({"event_id": "stale_probe", "due_turn": 9, "target_country_id": ""})
	EventsSim._deliver_follow_ups(state, notes)
	t.equal(state.pending_situations.size(), 1, "one month late is still on time")
	state.pending_situations.clear()
	state.scheduled_events.append({"event_id": "stale_probe", "due_turn": 8, "target_country_id": ""})
	EventsSim._deliver_follow_ups(state, notes)
	t.equal(state.pending_situations.size(), 0, "two months late it is dropped")
	t.equal(state.scheduled_events.size(), 0, "and leaves no row behind")
	EventsSim._by_id.erase("stale_probe")


func _test_targets_must_name_real_countries(t) -> void:
	var state := _state()
	t.equal(StateValidator.validate(state).size(), 0, "sanity: a fresh campaign is valid")
	_force(state, "bank_run", "atlantis")
	_rejects(t, state, "targets unknown country", "a situation aimed at no real country is rejected")
	state.pending_situations.clear()
	state.scheduled_events.append({"event_id": "bank_run", "due_turn": 3, "target_country_id": "atlantis"})
	_rejects(t, state, "targets unknown country", "so is a follow-up aimed at no real country")
	state.scheduled_events.clear()
	_force(state, "bank_run", "")
	t.equal(StateValidator.validate(state).size(), 0, "an untargeted situation is fine")


func _test_a_refused_gate_changes_nothing(t) -> void:
	var state := _state()
	state.player.political_capital = 200.0
	var target := ForeignArcs.resolve_target(state, "__western__")
	_set_score(state, target, 0.5)
	var event := EventsSim.event_by_id("bank_run").merged({"id": "gate_probe", "options": [
		{"id": "hit", "pc_cost": 10.0, "requires": {"diplomacy_verb": "impose_sanctions"},
			"relation_deltas": {"__western__": -0.3}, "effects": {}}]}, true)
	EventsSim._by_id["gate_probe"] = event
	_force(state, "gate_probe", target)
	var result := EventActions.resolve(state, "gate_probe", "hit")
	t.truth(not result["ok"], "a refused gate is refused")
	t.equal(String(result.get("error", "")), DiplomacyActions.reason_for(state, "impose_sanctions", target), "for the reason its own target gives")
	t.equal(state.player.political_capital, 200.0, "and costs no capital")
	t.near(_score(state, target), 0.5, 1e-9, "and moves no relation")
	t.equal(state.pending_situations.size(), 1, "and leaves the situation waiting")
	t.equal(state.event_history.size(), 0, "and records no decision")
	EventsSim._by_id.erase("gate_probe")


func _probe_event(id: String, handler: String) -> Dictionary:
	return EventsSim.event_by_id("bank_run").merged({"id": id, "default_option_id": "go",
		"options": [{"id": "go", "on_apply": handler, "effects": {}}]}, true)


func _test_a_handler_hears_its_situations_target(t) -> void:
	var state := _state()
	var heard: Array[String] = []
	ForeignArcs.probes["probe_hear"] = func(_s: GameState, target: String) -> String:
		heard.append(target)
		return "heard %s" % target
	var event := _probe_event("hear_probe", "probe_hear")
	EventsSim._by_id["hear_probe"] = event
	var s := _force(state, "hear_probe", "krasova")
	var note := EventsSim.apply_option(state, event, event["options"][0], s, false)
	t.equal(heard, ["krasova"] as Array[String], "a handler is told the situation's own target")
	t.equal(note, "heard krasova", "and its line is the option's note")
	ForeignArcs.probes.erase("probe_hear")
	EventsSim._by_id.erase("hear_probe")


func _test_a_trigger_made_mid_month_reaches_the_desk_that_month(t) -> void:
	var state := _state()
	ForeignArcs.probes["probe_trigger"] = func(st: GameState, _target: String) -> String:
		ForeignArcs.schedule(st, "bank_run", "krasova")
		return ""
	EventsSim._by_id["trigger_probe"] = _probe_event("trigger_probe", "probe_trigger")
	var s := _force(state, "trigger_probe")
	s.deadline_turn = state.turn
	state.event_fire_history.erase("bank_run")
	NativeGameScript.next_month(state)
	var arrived := state.pending_situations.filter(func(p: Situation) -> bool: return p.event_id == "bank_run")
	t.equal(arrived.size(), 1, "a trigger fired during the month's close is on the desk when the month closes")
	t.equal(arrived[0].arrived_turn if arrived.size() > 0 else -1, state.turn, "it arrives in the month that triggered it")
	t.equal(state.scheduled_events.filter(func(r) -> bool: return r["event_id"] == "bank_run").size(), 0, "and leaves nothing waiting for next month")
	ForeignArcs.probes.erase("probe_trigger")
	EventsSim._by_id.erase("trigger_probe")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_every_sentinel_names_a_live_country(t)
	_test_the_war_and_the_coup_sentinels_read_the_world(t)
	_test_the_concert_foe_is_cold_to_the_west_and_unsanctioned(t)
	_test_a_declared_target_is_fixed_on_arrival_and_follows_on(t)
	_test_data_gates_speak_with_the_action_layers_voice(t)
	_test_a_triggered_situation_arrives_this_month_and_never_goes_stale(t)
	_test_targets_must_name_real_countries(t)
	_test_a_refused_gate_changes_nothing(t)
	_test_a_handler_hears_its_situations_target(t)
	_test_a_trigger_made_mid_month_reaches_the_desk_that_month(t)
	quit(t.finish())
