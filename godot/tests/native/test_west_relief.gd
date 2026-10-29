extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const SLOT := "test_west_relief"


static func _state(seed: int = 424242) -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": seed})
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


static func _building(state: GameState) -> GasContract:
	state.player.political_capital = 200.0
	EnergyActions.act(state, "gas_second_line")
	return state.foreign.gas


static func _force(state: GameState, event_id: String, target := "") -> void:
	var s := Situation.new()
	s.event_id = event_id
	s.arrived_turn = state.turn
	s.deadline_turn = state.turn + EventsSim.DECISION_WINDOW_MONTHS
	s.target_country_id = target
	state.pending_situations.append(s)


func _test_the_offer_needs_a_line_with_time_left_to_save(t) -> void:
	var state := _state()
	t.truth(not EventsSim.condition_met(state, "west_relief_open"), "no line, no offer")
	var g := _building(state)
	t.truth(EventsSim.condition_met(state, "west_relief_open"), "a line under construction draws the Concert's offer")
	state.turn = g.second_line_started + GasSim.SECOND_LINE_MONTHS - GasSim.FAST_TRACK_MONTHS - 1
	t.truth(EventsSim.condition_met(state, "west_relief_open"), "with more than eighteen months left it still pays to accelerate")
	state.turn += 1
	t.truth(not EventsSim.condition_met(state, "west_relief_open"), "with exactly eighteen left there is nothing to save")
	state.turn = g.second_line_started
	state.foreign.reached["union_observer"] = state.turn
	t.truth(not EventsSim.condition_met(state, "west_relief_open"), "and never for a Union observer")
	state.foreign.reached.erase("union_observer")
	state.foreign.reached.erase("concert_application")
	t.truth(not EventsSim.condition_met(state, "west_relief_open"), "nor for a state that has not applied")


func _test_accepting_opens_the_line_eighteen_months_early(t) -> void:
	var state := _state()
	var g := _building(state)
	var started := g.second_line_started
	var west := ForeignArcs.resolve_target(state, "__western__")
	_force(state, "concert_energy_offer", west)
	var k0 := _score(state, g.supplier_id)
	t.truth(EventActions.resolve(state, "concert_energy_offer", "accept").get("ok", false), "the offer can be accepted")
	t.equal(g.second_line_months_saved, GasSim.FAST_TRACK_MONTHS, "the build is shortened")
	t.equal(GasSim.second_line_months(g), GasSim.SECOND_LINE_MONTHS - GasSim.FAST_TRACK_MONTHS, "to thirty months")
	t.near(_score(state, g.supplier_id), k0 + ForeignArcs.WEST_RELIEF_HOSTILITY, 1e-9, "and the supplier takes it as hostile")
	var due: Array = state.scheduled_events.filter(func(r: Dictionary) -> bool: return r["event_id"] == "concert_energy_conditions")
	t.equal(due.size(), 1, "the Concert's conditions are set in motion")
	t.equal(int(due[0]["due_turn"]), state.turn + 6, "six months out")
	state.scheduled_events.clear()
	var notes: Array[String] = []
	state.turn = started + GasSim.second_line_months(g) - 1
	GasSim._advance_projects(state, notes)
	t.equal(g.second_line_volume, 0.0, "a month before the shortened date the line is still shut")
	state.turn += 1
	GasSim._advance_projects(state, notes)
	t.truth(g.second_line_volume > 0.0, "on the shortened date it opens")


func _test_the_line_opens_on_the_real_calendar(t) -> void:
	var state := _state()
	var g := _building(state)
	g.second_line_months_saved = GasSim.FAST_TRACK_MONTHS
	var opened := -1
	for _m in range(GasSim.SECOND_LINE_MONTHS):
		NativeGameScript.next_month(state)
		if opened < 0 and g.second_line_volume > 0.0:
			opened = state.turn
	t.equal(opened - g.second_line_started, GasSim.SECOND_LINE_MONTHS - GasSim.FAST_TRACK_MONTHS, "calendar-true, the fast-tracked line opens after thirty months")


func _test_stalling_halves_the_saving_or_costs_the_west(t) -> void:
	var state := _state()
	var g := _building(state)
	g.second_line_months_saved = GasSim.FAST_TRACK_MONTHS
	_force(state, "concert_energy_conditions", ForeignArcs.resolve_target(state, "__western__"))
	t.equal(String(EventsSim.event_by_id("concert_energy_conditions")["default_option_id"]), "stall", "stalling is the default")
	EventActions.resolve(state, "concert_energy_conditions", "stall")
	t.equal(g.second_line_months_saved, int(GasSim.FAST_TRACK_MONTHS * ForeignArcs.STALLED_SHARE), "a stalled state keeps half the saving")
	var open := _state()
	var h := _building(open)
	h.second_line_months_saved = GasSim.FAST_TRACK_MONTHS
	h.second_line_volume = 2.0
	var west := ForeignArcs.resolve_target(open, "__western__")
	_force(open, "concert_energy_conditions", west)
	var w0 := _score(open, west)
	EventActions.resolve(open, "concert_energy_conditions", "stall")
	t.equal(h.second_line_months_saved, GasSim.FAST_TRACK_MONTHS, "an open line cannot be un-built")
	t.near(_score(open, west), w0 + ForeignArcs.STALLED_OPEN_WEST - 0.04, 1e-9, "so the West takes it out in goodwill")


func _test_a_restarted_line_gains_nothing_from_a_stall(t) -> void:
	var state := _state()
	var g := _building(state)
	g.second_line_months_saved = 0
	_force(state, "concert_energy_conditions", ForeignArcs.resolve_target(state, "__western__"))
	EventActions.resolve(state, "concert_energy_conditions", "stall")
	t.equal(g.second_line_months_saved, 0, "a line restarted after shelving was never fast-tracked, so a stall saves nothing")
	t.equal(StateValidator.validate(state).size(), 0, "and the contract stays valid")


func _test_shelving_the_line_forgets_the_saving(t) -> void:
	var state := _state()
	var g := _building(state)
	g.second_line_months_saved = GasSim.FAST_TRACK_MONTHS
	g.last_renegotiated = -1
	state.player.political_capital = 200.0
	var r := EnergyActions.act(state, "gas_renegotiate_policy")
	t.truth(r.get("ok", false), "the line can be shelved (%s)" % r.get("error", ""))
	t.equal(g.second_line_months_saved, 0, "and the Concert's saving goes with it")
	t.equal(StateValidator.validate(state).size(), 0, "leaving a valid contract")


func _test_the_saving_round_trips_and_validates(t) -> void:
	_wipe()
	var state := _state()
	var g := _building(state)
	g.second_line_months_saved = 9
	t.truth(SaveStore.save_slot(SLOT, state).get("ok", false), "the contract saves")
	var loaded: Dictionary = SaveStore.load_slot(SLOT)
	t.equal((loaded["state"] as GameState).foreign.gas.second_line_months_saved, 9, "the saving survives a binary save")
	_wipe()
	t.equal(StateValidator.validate(state).size(), 0, "a nine-month saving on a building line is valid")
	g.second_line_months_saved = GasSim.FAST_TRACK_MONTHS
	t.equal(StateValidator.validate(state).size(), 0, "so is the Concert's full eighteen")
	var old := g.to_dict()
	old.erase("second_line_months_saved")
	t.equal(GasContract.from_dict(old).second_line_months_saved, 0, "an old save loads with no saving")
	g.second_line_months_saved = GasSim.FAST_TRACK_MONTHS + 1
	t.truth(Array(StateValidator.validate(state)).any(func(e) -> bool: return String(e).contains("second line saving")), "a saving beyond the Concert's offer is rejected")
	g.second_line_months_saved = -1
	t.truth(Array(StateValidator.validate(state)).any(func(e) -> bool: return String(e).contains("second line saving")), "so is a negative one")
	g.second_line_months_saved = 9
	g.second_line_started = -1
	t.truth(Array(StateValidator.validate(state)).any(func(e) -> bool: return String(e).contains("second line saving")), "and a saving on a line nobody is building")
	g.second_line_months_saved = 0
	t.equal(StateValidator.validate(state).size(), 0, "no saving, no line, no error")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_the_offer_needs_a_line_with_time_left_to_save(t)
	_test_accepting_opens_the_line_eighteen_months_early(t)
	_test_the_line_opens_on_the_real_calendar(t)
	_test_stalling_halves_the_saving_or_costs_the_west(t)
	_test_a_restarted_line_gains_nothing_from_a_stall(t)
	_test_shelving_the_line_forgets_the_saving(t)
	_test_the_saving_round_trips_and_validates(t)
	quit(t.finish())
