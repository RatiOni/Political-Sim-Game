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

func _test_a_valve_threat_reaches_the_government_the_month_it_is_made(t) -> void:
	var state := _state()
	var g := state.foreign.gas
	var supplier := state.world_country(g.supplier_id)
	while state.month != 11:
		NativeGameScript.next_month(state)
	state.pending_situations.clear()
	state.scheduled_events.clear()
	g.arrears = 120.0
	g.last_demand_turn = state.turn - GasSim.THREAT_AFTER_DEMAND
	g.last_cut_turn = -1
	g.threat = {}
	state.foreign.powers[g.supplier_id] = {"dependence": 1.0, "commitment": 0.0, "leverage": 0.9}
	var notes: Array[String] = []
	GasSim.coerce(state, supplier, notes)
	t.truth(not g.threat.is_empty(), "sanity: the supplier names a date")
	EventsSim._deliver_follow_ups(state, notes)
	var arrived: Array = state.pending_situations.filter(func(s: Situation) -> bool: return s.event_id == "valve_threat")
	t.equal(arrived.size(), 1, "the threat is on the desk the same month")
	t.equal((arrived[0] as Situation).target_country_id, g.supplier_id, "and it is about the supplier")


func _test_a_threat_against_the_opposition_is_not_its_desk(t) -> void:
	var state := _state("opposition")
	var g := state.foreign.gas
	state.turn = 20
	g.arrears = 120.0
	g.last_demand_turn = state.turn - GasSim.THREAT_AFTER_DEMAND
	state.month = 11
	state.foreign.powers[g.supplier_id] = {"dependence": 1.0, "commitment": 0.0, "leverage": 0.9}
	var notes: Array[String] = []
	GasSim.coerce(state, state.world_country(g.supplier_id), notes)
	t.truth(not g.threat.is_empty(), "sanity: the supplier threatens the AI government too")
	t.equal(state.scheduled_events.filter(func(r: Dictionary) -> bool: return r["event_id"] == "valve_threat").size(), 0, "but the opposition is not handed the decision")


func _test_paying_before_the_date_defuses_the_valve(t) -> void:
	var state := _state()
	var g := state.foreign.gas
	g.arrears = 120.0
	g.threat = {"turn": state.turn, "due": state.turn + 1, "share": 0.3}
	_force(state, "valve_threat", g.supplier_id)
	var result := EventActions.resolve(state, "valve_threat", "pay_down")
	t.truth(result.get("ok", false), "the government can pay (%s)" % result.get("error", ""))
	t.truth(g.arrears < GasSim.ARREARS_DEMAND * GasSim.DEFUSED_SHARE, "the arrears fall below the line that defuses the threat (%.1f)" % g.arrears)
	t.near(g.arrears, 120.0 - 2.0 * EnergyActions.ARREARS_TRANCHE, 1e-6, "in whole tranches, and no more than needed")
	state.turn += 1
	var notes: Array[String] = []
	GasSim._mature_threat(state, notes)
	t.equal(g.cut, 0.0, "and the named date passes with the gas flowing")


func _test_paying_never_exceeds_three_tranches(t) -> void:
	var state := _state()
	var g := state.foreign.gas
	g.arrears = 400.0
	_force(state, "valve_threat", g.supplier_id)
	EventActions.resolve(state, "valve_threat", "pay_down")
	t.near(g.arrears, 400.0 - float(ForeignArcs.VALVE_TRANCHES) * EnergyActions.ARREARS_TRANCHE, 1e-6, "a crisis payment is capped at three tranches")


func _test_the_cargo_option_is_the_energy_desks_cargo(t) -> void:
	var state := _state()
	var g := state.foreign.gas
	_force(state, "valve_threat", g.supplier_id)
	state.player.political_capital = 0.0
	var refused := EventActions.resolve(state, "valve_threat", "buy_cargo")
	t.truth(not refused.get("ok", true), "with no capital the cargo is refused before anything happens")
	t.equal(refused.get("error", ""), EnergyActions.reason_for(state, "gas_spot_purchase"), "in the energy desk's own words")
	t.equal(g.spot_pending, 0.0, "and nothing is bought")
	state.player.political_capital = 50.0
	t.truth(EventActions.resolve(state, "valve_threat", "buy_cargo").get("ok", false), "with capital it goes through")
	t.near(g.spot_pending, EnergyActions.SPOT_VOLUME, 1e-9, "and a cargo is on its way")
	t.near(state.player.political_capital, 50.0 - float(EnergyActions.COSTS["gas_spot_purchase"]), 1e-9, "charged once, by the energy desk")


func _test_appealing_to_the_west_moves_both_capitals(t) -> void:
	var state := _state()
	var g := state.foreign.gas
	var west := ForeignArcs.resolve_target(state, "__western__")
	_force(state, "valve_threat", g.supplier_id)
	var s0 := _score(state, g.supplier_id)
	var w0 := _score(state, west)
	EventActions.resolve(state, "valve_threat", "appeal_west")
	t.near(_score(state, west), w0 + ForeignArcs.WEST_APPEAL, 1e-9, "the West hears the appeal")
	t.near(_score(state, g.supplier_id), s0 - 0.05, 1e-9, "and the supplier hears it too")


func _test_calling_the_bluff_is_the_default_and_costs_nothing(t) -> void:
	var state := _state()
	var event := EventsSim.event_by_id("valve_threat")
	t.equal(String(event["default_option_id"]), "call_bluff", "doing nothing is the default")
	var option := EventsSim.option_by_id(event, "call_bluff")
	t.equal(option.get("requires", null), null, "and it is never gated")
	t.equal(option.get("follow_up", null), null, "and starts nothing that would draw on the stream")
	t.equal(int(event.get("stale_after", -1)), 1, "a threat a month stale is never delivered")


func _test_the_transit_dispute_needs_a_cold_supplier_and_uncoded_fees(t) -> void:
	var state := _state()
	state.turn = ForeignArcs.GAS_SITUATION_TURN
	var supplier := state.foreign.gas.supplier_id
	_set_score(state, supplier, ForeignArcs.TRANSIT_WARMTH)
	t.truth(not EventsSim.condition_met(state, "transit_dispute_ripe"), "at exactly the line there is no dispute")
	t.truth(EventsSim.condition_met(state, "transit_windfall_due"), "the fees flow instead")
	_set_score(state, supplier, ForeignArcs.TRANSIT_WARMTH - 0.01)
	t.truth(EventsSim.condition_met(state, "transit_dispute_ripe"), "just colder and the fees are disputed")
	t.truth(not EventsSim.condition_met(state, "transit_windfall_due"), "and no windfall arrives")
	state.turn = ForeignArcs.GAS_SITUATION_TURN - 1
	t.truth(not EventsSim.condition_met(state, "transit_dispute_ripe"), "not in the first year")
	state.turn = ForeignArcs.GAS_SITUATION_TURN
	state.foreign.gas.concessions.append("transit")
	t.truth(not EventsSim.condition_met(state, "transit_dispute_ripe"), "and not once the fees are conceded")
	t.truth(not EventsSim.condition_met(state, "transit_windfall_due"), "when there are no fees to collect either")
	state.foreign.gas.concessions.clear()
	state.player.in_government = false
	t.truth(not EventsSim.condition_met(state, "transit_dispute_ripe"), "and never for the opposition")


func _test_conceding_the_fees_is_the_renegotiation(t) -> void:
	var state := _state()
	var g := state.foreign.gas
	state.player.political_capital = 100.0
	_force(state, "transit_dispute", g.supplier_id)
	var price := g.price
	t.truth(EventActions.resolve(state, "transit_dispute", "concede_fees").get("ok", false), "the fees can be conceded")
	t.truth("transit" in g.concessions, "the contract records the concession")
	t.near(g.price, maxf(g.reference_price * EnergyActions.PRICE_FLOOR_SHARE, price * float(EnergyActions.PRICE_CUTS["gas_renegotiate_transit"])), 1e-9, "at the renegotiation's own price")


func _test_the_windfall_can_fund_storage(t) -> void:
	var state := _state()
	state.player.political_capital = 100.0
	_force(state, "transit_windfall", "")
	t.truth(EventActions.resolve(state, "transit_windfall", "fund_storage").get("ok", false), "the windfall can start storage")
	t.equal(state.foreign.gas.storage_started, state.turn, "and the storage programme begins")
	var again := _state()
	_force(again, "transit_windfall", "")
	var debt := again.country.economy.public_debt_pct
	EventActions.resolve(again, "transit_windfall", "bank_it")
	t.near(again.country.economy.public_debt_pct, debt - 0.001, 1e-9, "banking it pays down a little debt")

func _test_the_valve_threat_closes_the_month_it_is_made(t) -> void:
	var state := _state()
	var g := state.foreign.gas
	while state.month != 10:
		NativeGameScript.next_month(state)
	state.pending_situations.clear()
	state.scheduled_events.clear()
	g.arrears = 120.0
	g.last_demand_turn = state.turn + 1 - GasSim.THREAT_AFTER_DEMAND
	g.last_cut_turn = -1
	g.threat = {}
	state.foreign.powers[g.supplier_id] = {"dependence": 1.0, "commitment": 0.0, "leverage": 0.9}
	NativeGameScript.next_month(state)
	t.truth(not g.threat.is_empty() and int(g.threat.get("turn", -1)) == state.turn, "sanity: the supplier names a date while the month closes")
	var arrived: Array = state.pending_situations.filter(func(s: Situation) -> bool: return s.event_id == "valve_threat")
	t.equal(arrived.size(), 1, "the foreign desk runs before the situations desk, so the threat lands this month")


func _test_paying_stops_at_the_line(t) -> void:
	var state := _state()
	var g := state.foreign.gas
	g.arrears = 80.0
	_force(state, "valve_threat", g.supplier_id)
	EventActions.resolve(state, "valve_threat", "pay_down")
	t.near(g.arrears, 0.0, 1e-6, "arrears left exactly at the line still owe a tranche")


func _test_a_failed_review_puts_the_fund_on_the_desk_in_the_review_month(t) -> void:
	var state := _state()
	while state.month != 12:
		NativeGameScript.next_month(state)
	state.pending_situations.clear()
	state.scheduled_events.clear()
	state.country.economy.inflation = 0.5
	NativeGameScript.next_month(state)
	t.equal(state.month, 1, "sanity: January, a review month")
	t.equal(String(state.foreign.isf["last_result"]), "failed", "sanity: the review fails")
	t.truth(state.pending_situations.any(func(s: Situation) -> bool: return s.event_id == "isf_review_crisis"), "the crisis is on the desk in the review month")
	var passed := _state()
	while passed.month != 12:
		NativeGameScript.next_month(passed)
	passed.pending_situations.clear()
	passed.scheduled_events.clear()
	passed.country.economy.inflation = 0.0
	passed.country.economy.budget.expenditure = passed.country.economy.budget.revenue
	NativeGameScript.next_month(passed)
	t.equal(String(passed.foreign.isf["last_result"]), "passed", "sanity: a disciplined government passes")
	t.truth(not passed.pending_situations.any(func(s: Situation) -> bool: return s.event_id == "isf_review_crisis"), "and no crisis follows a pass")


func _test_renegotiating_from_the_crisis_is_the_orientation_desks_renegotiation(t) -> void:
	var state := _state()
	state.foreign.isf["suspended"] = true
	state.player.political_capital = 100.0
	_force(state, "isf_review_crisis", "")
	var held := int(state.foreign.isf["renegotiations"])
	t.truth(EventActions.resolve(state, "isf_review_crisis", "renegotiate").get("ok", false), "the fund can be renegotiated from the crisis")
	t.equal(int(state.foreign.isf["renegotiations"]), held + 1, "the ledger records it")
	t.equal(String(EventsSim.event_by_id("isf_review_crisis")["default_option_id"]), "blame_the_fund", "blaming the fund is the default")


func _test_the_delegation_needs_an_application_and_no_union_step(t) -> void:
	var state := _state()
	t.truth(state.foreign.reached.has("concert_application"), "sanity: Ardenia has applied")
	t.truth(EventsSim.condition_met(state, "concert_delegation_due"), "the Concert sends a delegation to an applicant")
	state.foreign.reached["union_observer"] = state.turn
	t.truth(not EventsSim.condition_met(state, "concert_delegation_due"), "but not to a Union observer")
	state.foreign.reached.erase("union_observer")
	state.foreign.reached["concert_agreement"] = state.turn
	t.truth(not EventsSim.condition_met(state, "concert_delegation_due"), "nor once the agreement is signed")


func _test_embracing_the_conditions_counts_toward_the_agreement_and_caps(t) -> void:
	var state := _state()
	state.player.political_capital = 100.0
	state.foreign.western_qualifying_months = 10
	_force(state, "concert_delegation", ForeignArcs.resolve_target(state, "__western__"))
	EventActions.resolve(state, "concert_delegation", "embrace")
	t.equal(state.foreign.western_qualifying_months, 10 + ForeignArcs.DELEGATION_MONTHS, "the conditions count as months of discipline")
	state.foreign.western_qualifying_months = OrientationActions.QUALIFYING_MONTHS_FOR_AGREEMENT - 1
	_force(state, "concert_delegation", ForeignArcs.resolve_target(state, "__western__"))
	EventActions.resolve(state, "concert_delegation", "embrace")
	t.equal(state.foreign.western_qualifying_months, OrientationActions.QUALIFYING_MONTHS_FOR_AGREEMENT, "but never past what the agreement needs")


func _test_the_union_invites_only_a_tolerable_neighbour(t) -> void:
	var state := _state()
	var anchor := ForeignArcs.resolve_target(state, "__union_anchor__")
	_set_score(state, anchor, OrientationActions.OBSERVER_WARMTH)
	t.truth(EventsSim.condition_met(state, "union_invites"), "at exactly the observer line the Union invites")
	_set_score(state, anchor, OrientationActions.OBSERVER_WARMTH - 0.01)
	t.truth(not EventsSim.condition_met(state, "union_invites"), "just colder and it does not")
	_set_score(state, anchor, 0.0)
	state.foreign.union_left_turn = state.turn
	state.turn += OrientationActions.UNION_REJOIN_MONTHS - 1
	t.truth(not EventsSim.condition_met(state, "union_invites"), "a country that walked out waits out the bar")
	state.turn += 1
	t.truth(EventsSim.condition_met(state, "union_invites"), "and is invited again the month it ends")
	state.foreign.reached["union_observer"] = state.turn
	t.truth(not EventsSim.condition_met(state, "union_invites"), "an observer is not invited twice")


func _test_accepting_the_invitation_takes_observer_status(t) -> void:
	var state := _state()
	state.player.political_capital = 100.0
	_force(state, "union_invitation", ForeignArcs.resolve_target(state, "__union_anchor__"))
	t.truth(EventActions.resolve(state, "union_invitation", "accept_observer").get("ok", false), "the invitation can be accepted")
	t.truth(state.foreign.reached.has("union_observer"), "and Ardenia is an observer")


func _test_union_pressure_lands_on_members_and_compliance_cools_the_west(t) -> void:
	var state := _state()
	t.truth(not EventsSim.condition_met(state, "union_member_pressed"), "a non-member is not pressed")
	state.foreign.reached["union_member"] = state.turn
	t.truth(EventsSim.condition_met(state, "union_member_pressed"), "a member is")
	var west := ForeignArcs.resolve_target(state, "__western__")
	var anchor := ForeignArcs.resolve_target(state, "__union_anchor__")
	_force(state, "union_pressure", anchor)
	var w0 := _score(state, west)
	var a0 := _score(state, anchor)
	EventActions.resolve(state, "union_pressure", "comply")
	t.near(_score(state, west), w0 + ForeignArcs.COMPLY_WEST, 1e-9, "complying costs the West")
	t.near(_score(state, anchor), a0 + 0.03, 1e-9, "and pleases the Union")
	t.equal(String(EventsSim.event_by_id("union_pressure")["default_option_id"]), "comply", "a member that looks away complies")


func _test_western_aid_needs_a_strained_treasury_and_comes_with_conditions(t) -> void:
	var state := _state()
	var limit := float(OrientationSim.isf_targets(state)["deficit"])
	state.foreign.isf["suspended"] = false
	var budget := state.country.economy.budget
	budget.expenditure = budget.revenue
	t.truth(not EventsSim.condition_met(state, "western_aid_offered"), "a balanced, compliant treasury gets no aid offer")
	state.foreign.isf["suspended"] = true
	t.truth(EventsSim.condition_met(state, "western_aid_offered"), "a suspended programme does")
	state.foreign.reached["union_member"] = state.turn
	t.truth(not EventsSim.condition_met(state, "western_aid_offered"), "a Union member does not")
	state.foreign.reached.erase("union_member")
	state.foreign.isf["suspended"] = false
	budget.expenditure = budget.revenue + limit * state.country.economy.gdp + 1.0
	t.truth(EventsSim.condition_met(state, "western_aid_offered"), "nor does a deficit above the fund's target go unnoticed")
	_force(state, "western_aid_strings", ForeignArcs.resolve_target(state, "__western__"))
	var debt := state.country.economy.public_debt_pct
	EventActions.resolve(state, "western_aid_strings", "accept_aid")
	t.near(state.country.economy.public_debt_pct, debt - 0.004, 1e-9, "the aid relieves debt")
	var row: Array = state.scheduled_events.filter(func(r: Dictionary) -> bool: return r["event_id"] == "aid_conditions_due")
	t.equal(row.size(), 1, "and its conditions are set in motion")
	t.equal(int(row[0]["due_turn"]), state.turn + 6, "six months out")
	t.equal(String(row[0]["target_country_id"]), ForeignArcs.resolve_target(state, "__western__"), "owed to the same capital")


func _test_a_spending_freeze_is_a_timed_cut(t) -> void:
	var state := _state()
	state.player.political_capital = 100.0
	_force(state, "isf_review_crisis")
	var mods0 := state.modifiers.size()
	EventActions.resolve(state, "isf_review_crisis", "spending_freeze")
	t.equal(state.modifiers.size(), mods0 + 1, "the freeze is a modifier")
	var m: Modifier = state.modifiers[-1]
	t.equal(m.id, "isf_spending_freeze", "named for the freeze")
	t.equal(m.target, "budget_expenditure", "on spending")
	t.near(m.magnitude, -40.0, 1e-9, "cutting it")
	t.equal(m.hold_duration, 12, "for a year")
	t.near(state.player.political_capital, 94.0, 1e-9, "at a political price")


func _test_the_aid_conditions_are_delivered_or_clawed_back(t) -> void:
	var state := _state()
	var west := ForeignArcs.resolve_target(state, "__western__")
	state.player.political_capital = 100.0
	_force(state, "aid_conditions_due", west)
	var w0 := _score(state, west)
	EventActions.resolve(state, "aid_conditions_due", "deliver")
	t.near(_score(state, west), w0 + 0.04, 1e-9, "delivering pleases the donors")
	t.near(state.player.political_capital, 92.0, 1e-9, "and costs capital")
	state = _state()
	west = ForeignArcs.resolve_target(state, "__western__")
	_force(state, "aid_conditions_due", west)
	w0 = _score(state, west)
	var debt := state.country.economy.public_debt_pct
	EventActions.resolve(state, "aid_conditions_due", "stall")
	t.near(_score(state, west), w0 - 0.06, 1e-9, "stalling cools the donors")
	t.near(state.country.economy.public_debt_pct, debt + 0.002, 1e-9, "and half the aid is clawed back")
	t.equal(String(EventsSim.event_by_id("aid_conditions_due")["default_option_id"]), "stall", "stalling is the default")


func _test_playing_both_sides_moves_both_capitals(t) -> void:
	var state := _state()
	var west := ForeignArcs.resolve_target(state, "__western__")
	var anchor := ForeignArcs.resolve_target(state, "__union_anchor__")
	state.player.political_capital = 100.0
	_force(state, "union_invitation", anchor)
	var w0 := _score(state, west)
	var a0 := _score(state, anchor)
	EventActions.resolve(state, "union_invitation", "play_both_sides")
	t.near(_score(state, west), w0 + ForeignArcs.PLAY_WEST, 1e-9, "the West grows attentive")
	t.near(_score(state, anchor), a0 - 0.05, 1e-9, "the Union notices")
	t.near(state.player.political_capital, 95.0, 1e-9, "and it costs capital")


func _ripe_neighbour(state: GameState) -> Country:
	for c in state.world:
		c.in_civil_war = false
		c.stability = 0.8
		c.civil_war_risk = 0.0
	var c := state.world_country(ForeignArcs.resolve_target(state, "__warmest__"))
	c.regime_type = "hybrid_regime"
	c.stability = 0.2
	return c


func _test_a_coup_happens_whatever_ardenia_says(t) -> void:
	for option in ["recognise", "condemn", "wait_and_see"]:
		var state := _state()
		var c := _ripe_neighbour(state)
		t.truth(EventsSim.condition_met(state, "neighbour_coup_ripe"), "sanity: a fragile neighbour")
		_force(state, "neighbour_coup", c.id)
		state.player.political_capital = 100.0
		EventActions.resolve(state, "neighbour_coup", option)
		t.equal(c.regime_type, ForeignArcs.COUP_REGIME, "%s: the generals hold the capital" % option)
		t.near(c.stability, ForeignArcs.COUP_ORDER, 1e-9, "%s: and impose their order" % option)
		t.truth(not EventsSim.condition_met(state, "neighbour_coup_ripe"), "%s: and the same country has no second coup" % option)
	var state := _state()
	var c := _ripe_neighbour(state)
	c.stability = 0.29
	_force(state, "neighbour_coup", c.id)
	EventActions.resolve(state, "neighbour_coup", "wait_and_see")
	t.near(c.stability, ForeignArcs.COUP_ORDER, 1e-9, "a neighbour just under the line is lifted to the generals' order")


func _test_condemning_a_coup_pleases_the_west(t) -> void:
	var state := _state()
	var c := _ripe_neighbour(state)
	var west := ForeignArcs.resolve_target(state, "__western__")
	_force(state, "neighbour_coup", c.id)
	var w0 := _score(state, west)
	var c0 := _score(state, c.id)
	EventActions.resolve(state, "neighbour_coup", "condemn")
	t.near(_score(state, c.id), c0 - 0.08, 1e-9, "the junta hears the condemnation")
	t.near(_score(state, west), w0 + ForeignArcs.COUP_CONDEMN_WEST + (0.0 if c.id != west else -0.08), 1e-9, "and the West approves")


func _test_joining_a_coalition_is_a_real_sanction_on_the_target(t) -> void:
	var state := _state()
	var west := ForeignArcs.resolve_target(state, "__western__")
	var foe := ForeignArcs.resolve_target(state, "__rival__")
	var foe_c := state.world_country(foe)
	DiplomacySim.shift_between(foe_c, state.world_country(west), -1.0)
	t.equal(ForeignArcs.resolve_target(state, "__concert_foe__"), foe, "sanity: the rival is the Concert's foe")
	state.player.political_capital = 100.0
	_force(state, "sanctions_coalition", foe)
	var w0 := _score(state, west)
	t.truth(EventActions.resolve(state, "sanctions_coalition", "join").get("ok", false), "Ardenia can join (%s)" % EventActions.option_reason(state, EventsSim.option_by_id(EventsSim.event_by_id("sanctions_coalition"), "join"), foe))
	t.truth((state.country.relations[foe] as Country.BilateralRelation).sanctioned, "the target is sanctioned, by the diplomacy desk")
	t.near(state.player.political_capital, 100.0 - float(DiplomacyActions.COSTS["impose_sanctions"]), 1e-9, "charged once")
	t.near(_score(state, west), w0 + ForeignArcs.SANCTIONS_WEST, 1e-9, "and the Concert is grateful")
	t.equal(String(EventsSim.event_by_id("sanctions_coalition")["default_option_id"]), "abstain", "abstaining is the default")


func _test_an_arms_offer_needs_a_threat(t) -> void:
	var state := _state()
	var rival := ForeignArcs.resolve_target(state, "__rival__")
	state.insurgency_pressure = 0.0
	_set_score(state, rival, ForeignArcs.ARMS_RIVAL_LINE + 0.01)
	t.truth(not EventsSim.condition_met(state, "arms_offer_open"), "no insurgency and a tolerable rival, no arms offer")
	_set_score(state, rival, ForeignArcs.ARMS_RIVAL_LINE)
	t.truth(EventsSim.condition_met(state, "arms_offer_open"), "a rival at the line brings one")
	_set_score(state, rival, 0.0)
	state.insurgency_pressure = ForeignArcs.ARMS_INSURGENCY
	t.truth(EventsSim.condition_met(state, "arms_offer_open"), "so does an insurgency at its line")
	_force(state, "arms_offer", ForeignArcs.resolve_target(state, "__warmest__"))
	state.player.political_capital = 100.0
	EventActions.resolve(state, "arms_offer", "buy")
	t.near(state.insurgency_pressure, ForeignArcs.ARMS_INSURGENCY - ForeignArcs.ARMS_CALM, 1e-9, "the arms quieten the insurgency")


func _test_the_rival_presses_its_interests_after_pressing_ardenia(t) -> void:
	var state := _state()
	state.turn = 30
	var rival := ForeignArcs.resolve_target(state, "__rival__")
	_set_score(state, rival, ForeignArcs.INTERESTS_LINE)
	state.foreign.hostile_log.clear()
	t.truth(not EventsSim.condition_met(state, "rival_presses_interests"), "no recent move, no demand")
	state.foreign.hostile_log.append({"turn": state.turn - ForeignArcs.INTERESTS_MEMORY, "actor": rival, "relation": -0.05, "economy": 0.0, "stability": 0.0})
	t.truth(EventsSim.condition_met(state, "rival_presses_interests"), "a move a year ago still counts")
	state.foreign.hostile_log[0]["turn"] = state.turn - ForeignArcs.INTERESTS_MEMORY - 1
	t.truth(not EventsSim.condition_met(state, "rival_presses_interests"), "a move older than that does not")
	state.foreign.hostile_log[0]["turn"] = state.turn
	_set_score(state, rival, ForeignArcs.INTERESTS_LINE + 0.01)
	t.truth(not EventsSim.condition_met(state, "rival_presses_interests"), "a rival warmer than the line makes no demand")


func _test_the_refugee_flow_is_about_the_warring_neighbour(t) -> void:
	var state := _state()
	for c in state.world:
		c.in_civil_war = false
	var war := state.world_country(ForeignArcs.resolve_target(state, "__western__"))
	war.in_civil_war = true
	var notes: Array[String] = []
	EventsSim._arrive(state, EventsSim.event_by_id("refugee_crisis"), "", notes)
	var s: Situation = state.pending_situations[-1]
	t.equal(s.target_country_id, war.id, "the refugees come from the country at war")
	var before := _score(state, war.id)
	state.player.political_capital = 100.0
	EventActions.resolve(state, "refugee_crisis", "open_borders")
	t.near(_score(state, war.id), before + 0.05, 1e-9, "and opening the border is felt there")


func _test_no_foreign_event_names_a_country(t) -> void:
	var ids := {}
	for c in ContentRepository.load_all().get("countries", {}):
		ids[String(c)] = true
	for id in ForeignArcs.EVENT_IDS + ["refugee_crisis"]:
		var e := EventsSim.event_by_id(id)
		t.truth(not e.is_empty(), "%s exists" % id)
		t.truth(not ids.has(String(e.get("target", ""))), "%s declares no literal target" % id)
		for o in e.get("options", []):
			for key in o.get("relation_deltas", {}):
				t.truth(String(key) in EventsSim.TARGET_KEYS, "%s/%s moves only a sentinel (%s)" % [id, o["id"], key])
		t.truth(not (id in ContentRepository.load_all()["catalogs"]["events"]["ardenia_only_events"]), "%s is not bespoke content" % id)


func _answer(event_id: String, option: String, target_sentinel: String) -> Dictionary:
	var state := _state()
	if event_id == "neighbour_coup":
		_ripe_neighbour(state)
	if event_id == "rival_interests" or event_id == "arms_offer":
		_set_score(state, ForeignArcs.resolve_target(state, "__rival__"), -0.2)
	var target := ForeignArcs.resolve_target(state, target_sentinel)
	var west := ForeignArcs.resolve_target(state, "__western__")
	var rival := ForeignArcs.resolve_target(state, "__rival__")
	state.player.political_capital = 100.0
	_force(state, event_id, target)
	var w0 := _score(state, west)
	var r0 := _score(state, rival)
	EventActions.resolve(state, event_id, option)
	return {"west": _score(state, west) - w0, "rival": _score(state, rival) - r0,
		"pc": 100.0 - state.player.political_capital, "distinct": west != rival and target != west}


func _test_every_neighbour_answer_has_its_real_cost(t) -> void:
	var abstain := _answer("sanctions_coalition", "abstain", "__rival__")
	t.near(float(abstain["west"]), -0.03, 1e-9, "abstaining cools the West")
	var oppose := _answer("sanctions_coalition", "speak_against", "__rival__")
	t.near(float(oppose["west"]), -0.06, 1e-9, "speaking against cools it more")
	var arms := _answer("arms_offer", "buy", "__warmest__")
	t.truth(arms["distinct"], "sanity: the arms come from a third capital")
	t.near(float(arms["rival"]), -0.04, 1e-9, "the rival hears about the arms")
	t.near(float(arms["pc"]), 5.0, 1e-9, "the arms cost 5 capital")
	var ack := _answer("rival_interests", "acknowledge", "__rival__")
	t.truth(ack["distinct"], "sanity: the rival is not the West")
	t.near(float(ack["west"]), -0.04, 1e-9, "acknowledging the note cools the West")
	t.near(float(ack["rival"]), 0.08, 1e-9, "and warms the rival")
	t.near(float(ack["pc"]), 0.0, 1e-9, "acknowledging costs no capital")
	var pub := _answer("rival_interests", "take_it_to_the_concert", "__rival__")
	t.near(float(pub["west"]), 0.04, 1e-9, "publishing the note warms the West")
	t.near(float(pub["rival"]), -0.06, 1e-9, "and cools the rival")
	t.near(float(pub["pc"]), 8.0, 1e-9, "publishing costs 8 capital")
	t.near(float(_answer("neighbour_coup", "recognise", "__fragile__")["pc"]), 0.0, 1e-9, "recognising costs no capital")
	t.near(float(_answer("neighbour_coup", "condemn", "__fragile__")["pc"]), 4.0, 1e-9, "condemning costs 4 capital")


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
	_test_a_valve_threat_reaches_the_government_the_month_it_is_made(t)
	_test_a_threat_against_the_opposition_is_not_its_desk(t)
	_test_paying_before_the_date_defuses_the_valve(t)
	_test_paying_never_exceeds_three_tranches(t)
	_test_the_cargo_option_is_the_energy_desks_cargo(t)
	_test_appealing_to_the_west_moves_both_capitals(t)
	_test_calling_the_bluff_is_the_default_and_costs_nothing(t)
	_test_the_transit_dispute_needs_a_cold_supplier_and_uncoded_fees(t)
	_test_conceding_the_fees_is_the_renegotiation(t)
	_test_the_windfall_can_fund_storage(t)
	_test_the_valve_threat_closes_the_month_it_is_made(t)
	_test_paying_stops_at_the_line(t)
	_test_a_failed_review_puts_the_fund_on_the_desk_in_the_review_month(t)
	_test_renegotiating_from_the_crisis_is_the_orientation_desks_renegotiation(t)
	_test_the_delegation_needs_an_application_and_no_union_step(t)
	_test_embracing_the_conditions_counts_toward_the_agreement_and_caps(t)
	_test_the_union_invites_only_a_tolerable_neighbour(t)
	_test_accepting_the_invitation_takes_observer_status(t)
	_test_union_pressure_lands_on_members_and_compliance_cools_the_west(t)
	_test_western_aid_needs_a_strained_treasury_and_comes_with_conditions(t)
	_test_a_spending_freeze_is_a_timed_cut(t)
	_test_the_aid_conditions_are_delivered_or_clawed_back(t)
	_test_playing_both_sides_moves_both_capitals(t)
	_test_a_coup_happens_whatever_ardenia_says(t)
	_test_condemning_a_coup_pleases_the_west(t)
	_test_joining_a_coalition_is_a_real_sanction_on_the_target(t)
	_test_an_arms_offer_needs_a_threat(t)
	_test_the_rival_presses_its_interests_after_pressing_ardenia(t)
	_test_the_refugee_flow_is_about_the_warring_neighbour(t)
	_test_no_foreign_event_names_a_country(t)
	_test_every_neighbour_answer_has_its_real_cost(t)
	quit(t.finish())
