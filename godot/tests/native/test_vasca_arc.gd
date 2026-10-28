extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")

const ARC := ["vasca_stirs", "vasca_crackdown_works", "vasca_crackdown_fails",
	"vasca_amnesty_holds", "vasca_regroups", "vasca_emboldened", "vasca_last_stand"]


static func _state(seed: int = 424242, role: String = "contextual") -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": seed})
	state.rng = SimRng.from_seed(seed)
	state.player.political_capital = 500.0
	state.turn = 12
	return state


static func _decide(state: GameState, event_id: String, option_id: String) -> Dictionary:
	var s := Situation.new()
	s.event_id = event_id
	s.arrived_turn = state.turn
	s.deadline_turn = state.turn + EventsSim.DECISION_WINDOW_MONTHS
	state.pending_situations.append(s)
	return EventActions.resolve(state, event_id, option_id)


static func _scheduled(state: GameState, event_id: String) -> Dictionary:
	for row in state.scheduled_events:
		if row["event_id"] == event_id:
			return row
	return {}


static func _set_security(state: GameState, quality: float, stability: float) -> void:
	for m in state.ministers:
		if m.portfolio in ["Interior", "Defense"]:
			m.competence = quality
			m.loyalty = quality
			m.trait_id = ""
	state.stability_value = stability


static func _crackdown_success_rate(quality: float, stability: float) -> float:
	var wins := 0
	for seed in range(40):
		var state := _state(1000 + seed)
		_set_security(state, quality, stability)
		_decide(state, "vasca_stirs", "crackdown")
		if not _scheduled(state, "vasca_crackdown_works").is_empty():
			wins += 1
	return wins / 40.0


static func _amnesty_hold_rate(approval: float) -> float:
	var holds := 0
	for seed in range(40):
		var state := _state(2000 + seed)
		state.player.approval = approval
		_decide(state, "vasca_stirs", "amnesty")
		if not _scheduled(state, "vasca_amnesty_holds").is_empty():
			holds += 1
	return holds / 40.0


func _test_the_west_stirs_only_for_a_weak_government(t) -> void:
	var state := _state()
	state.stability_value = 0.80
	state.player.approval = 0.60
	state.civil_war_risk = 0.10
	t.truth(not EventsSim.condition_met(state, "vasca_stirring"), "not while the government looks strong")
	state.player.approval = 0.45
	t.truth(EventsSim.condition_met(state, "vasca_stirring"), "but once approval slips")
	state.turn = 3
	t.truth(not EventsSim.condition_met(state, "vasca_stirring"), "never in the opening months")
	var opp := _state(424242, "opposition")
	opp.player.approval = 0.30
	t.truth(not EventsSim.condition_met(opp, "vasca_stirring"), "and never for a leader out of office")


func _test_the_whole_arc_is_playable(t) -> void:
	var held := EventsSim.unplayable_events()
	var missing: Array = []
	for id in ARC:
		if id in held:
			missing.append(id)
	t.equal(missing, [], "every step of the Vasca arc can now fire")


func _test_crackdown_success_depends_on_real_security(t) -> void:
	var strong := _crackdown_success_rate(0.95, 0.85)
	var weak := _crackdown_success_rate(0.25, 0.30)
	t.truth(strong > weak + 0.3,
		"capable security services win far more often than broken ones (%.2f vs %.2f)" % [strong, weak])


func _test_a_failed_crackdown_inflames_the_west(t) -> void:
	var state := _state()
	_set_security(state, 0.0, 0.0)
	var p0 := state.insurgency_pressure
	_decide(state, "vasca_stirs", "crackdown")
	if _scheduled(state, "vasca_crackdown_fails").is_empty():
		t.truth(false, "sanity: a hopeless crackdown should fail with this seed")
		return
	t.near(state.insurgency_pressure, minf(1.0, p0 + 0.30), 1e-9, "a failed sweep adds insurgency pressure")
	t.equal(int(_scheduled(state, "vasca_crackdown_fails")["due_turn"]), state.turn + 2, "and the reckoning comes in two months")


func _test_a_general_leading_in_person_does_better(t) -> void:
	var led := 0
	var plain := 0
	for seed in range(40):
		var a := _state(3000 + seed)
		_set_security(a, 0.40, 0.40)
		a.campaign_meta["background"] = "former_general"
		_decide(a, "vasca_stirs", "lead_it")
		if not _scheduled(a, "vasca_crackdown_works").is_empty():
			led += 1
		var b := _state(3000 + seed)
		_set_security(b, 0.40, 0.40)
		_decide(b, "vasca_stirs", "crackdown")
		if not _scheduled(b, "vasca_crackdown_works").is_empty():
			plain += 1
	t.truth(led > plain, "a former general who goes west himself succeeds more often (%d vs %d of 40)" % [led, plain])


func _test_amnesty_holds_more_often_for_a_popular_government(t) -> void:
	var popular := _amnesty_hold_rate(0.80)
	var disliked := _amnesty_hold_rate(0.15)
	t.truth(popular > disliked + 0.15,
		"goodwill makes surrender look like sense (%.2f vs %.2f)" % [popular, disliked])


func _test_downplaying_emboldens_the_west(t) -> void:
	var state := _state()
	var p0 := state.insurgency_pressure
	_decide(state, "vasca_stirs", "downplay")
	t.near(state.insurgency_pressure, minf(1.0, p0 + 0.15), 1e-9, "looking away adds pressure")
	t.equal(int(_scheduled(state, "vasca_emboldened").get("due_turn", -1)), state.turn + 4, "and Vasca grows bolder in four months")


func _test_each_ending_is_recorded_and_moves_pressure(t) -> void:
	var cases := [
		["vasca_crackdown_works", "public_trial", "captured", -0.45],
		["vasca_last_stand", "storm_it", "dead", -0.40],
		["vasca_last_stand", "negotiate_exit", "exiled", -0.35],
		["vasca_amnesty_holds", "formalise", "isolated", -0.25],
		["vasca_last_stand", "let_it_lie", "unresolved", 0.10],
	]
	for c in cases:
		var state := _state()
		state.insurgency_pressure = 0.50
		_decide(state, c[0], c[1])
		t.equal(state.campaign_meta.get("vasca_status", ""), c[2], "%s/%s ends the arc as '%s'" % [c[0], c[1], c[2]])
		t.near(state.insurgency_pressure, clampf(0.50 + float(c[3]), 0.0, 1.0), 1e-9,
			"and moves insurgency pressure by %+.2f" % c[3])


func _test_an_ended_arc_never_reopens(t) -> void:
	var state := _state()
	state.player.approval = 0.20
	t.truth(EventsSim.condition_met(state, "vasca_stirring"), "sanity: a weak government invites trouble")
	_decide(state, "vasca_last_stand", "negotiate_exit")
	t.truth(not EventsSim.condition_met(state, "vasca_stirring"), "once Vasca's fate is settled the west does not stir again")


func _test_insurgency_feeds_unrest(t) -> void:
	var calm := _state()
	var hot := _state()
	hot.insurgency_pressure = 0.80
	t.truth(StabilitySim._unrest(hot) > StabilitySim._unrest(calm),
		"an insurgency in the west is unrest the government feels")


func _test_same_seed_same_outcome(t) -> void:
	var a := _state(77)
	var b := _state(77)
	_decide(a, "vasca_stirs", "crackdown")
	_decide(b, "vasca_stirs", "crackdown")
	t.equal(a.scheduled_events, b.scheduled_events, "the same campaign seed gives the same operation outcome")


func _test_insurgency_survives_save_and_reload(t) -> void:
	var state := _state()
	state.insurgency_pressure = 0.37
	state.campaign_meta["vasca_status"] = "exiled"
	var copy := GameState.from_dict(state.to_dict())
	t.near(copy.insurgency_pressure, 0.37, 1e-9, "insurgency pressure round-trips")
	t.equal(copy.campaign_meta.get("vasca_status", ""), "exiled", "and so does Vasca's fate")
	state.insurgency_pressure = 1.5
	t.truth(StateValidator.validate(state).size() > 0, "an impossible insurgency level is rejected")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_the_west_stirs_only_for_a_weak_government(t)
	_test_the_whole_arc_is_playable(t)
	_test_crackdown_success_depends_on_real_security(t)
	_test_a_failed_crackdown_inflames_the_west(t)
	_test_a_general_leading_in_person_does_better(t)
	_test_amnesty_holds_more_often_for_a_popular_government(t)
	_test_downplaying_emboldens_the_west(t)
	_test_each_ending_is_recorded_and_moves_pressure(t)
	_test_an_ended_arc_never_reopens(t)
	_test_insurgency_feeds_unrest(t)
	_test_same_seed_same_outcome(t)
	_test_insurgency_survives_save_and_reload(t)
	quit(t.finish())
