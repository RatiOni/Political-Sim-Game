extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")


static func _state() -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	return state


static func _between(a: Country, b: Country, score: float) -> void:
	(a.relations[b.id] as Country.BilateralRelation).score = score
	(b.relations[a.id] as Country.BilateralRelation).score = score


static func _in(state: GameState, bloc_id: String, country_id: String) -> bool:
	return country_id in state.foreign.members.get(bloc_id, [])


func _test_democratic_traders_drift_into_the_concert(t) -> void:
	var state := _state()
	var veldoria := DiplomacySim.world_country(state, "veldoria")
	veldoria.stability = 0.7
	_between(veldoria, DiplomacySim.world_country(state, "solheim"), 0.6)
	state.month = 5
	OrientationSim.monthly(state)
	t.truth(not _in(state, "concert", "veldoria"), "blocs take members only at the turn of the year")
	state.month = 1
	var notes := OrientationSim.monthly(state)
	t.truth(_in(state, "concert", "veldoria"), "a stable democratic trader warm to Solheim joins the Concert")
	t.truth(notes.any(func(n: String) -> bool: return n.contains(veldoria.name) and n.contains("joins")), "and the world hears of it")


func _test_the_meridian_takes_only_steady_concert_members(t) -> void:
	var state := _state()
	var veldoria := DiplomacySim.world_country(state, "veldoria")
	veldoria.stability = 0.47
	_between(veldoria, DiplomacySim.world_country(state, "solheim"), 0.6)
	state.month = 1
	OrientationSim.monthly(state)
	t.truth(_in(state, "concert", "veldoria"), "steady enough for the Concert")
	t.truth(not _in(state, "meridian", "veldoria"), "but not for the alliance")


func _test_krasovan_clients_join_the_union(t) -> void:
	var state := _state()
	var terand := DiplomacySim.world_country(state, "terand")
	terand.stability = 0.6
	_between(terand, DiplomacySim.world_country(state, "krasova"), 0.4)
	state.month = 1
	OrientationSim.monthly(state)
	t.truth(_in(state, "union", "terand"), "a revanchist warm to Krasova joins the Union")
	t.truth(not _in(state, "concert", "terand"), "and sits in no Western bloc")


func _test_members_who_turn_cold_walk_away(t) -> void:
	var state := _state()
	var terand := DiplomacySim.world_country(state, "terand")
	var krasova := DiplomacySim.world_country(state, "krasova")
	terand.stability = 0.6
	_between(terand, krasova, 0.4)
	state.month = 1
	OrientationSim.monthly(state)
	_between(terand, krasova, -0.6)
	var notes := OrientationSim.monthly(state)
	t.truth(not _in(state, "union", "terand"), "a member that turns on the anchor leaves the bloc")
	t.truth(notes.any(func(n: String) -> bool: return n.contains(terand.name) and n.contains("leaves")), "and the world hears of it")


func _test_an_anchor_never_leaves_its_bloc(t) -> void:
	var state := _state()
	DiplomacySim.world_country(state, "solheim").stability = 0.05
	DiplomacySim.world_country(state, "krasova").stability = 0.05
	state.month = 1
	OrientationSim.monthly(state)
	t.truth(_in(state, "concert", "solheim") and _in(state, "meridian", "solheim"), "Solheim anchors the Western blocs through any crisis")
	t.truth(_in(state, "union", "krasova"), "Krasova anchors the Union through any crisis")


func _test_no_country_sits_on_both_sides(t) -> void:
	var state := _state()
	var veldoria := DiplomacySim.world_country(state, "veldoria")
	(state.foreign.members["union"] as Array).append("veldoria")
	veldoria.stability = 0.7
	_between(veldoria, DiplomacySim.world_country(state, "solheim"), 0.6)
	_between(veldoria, DiplomacySim.world_country(state, "krasova"), 0.6)
	state.month = 1
	OrientationSim.monthly(state)
	t.truth(not (_in(state, "concert", "veldoria") and _in(state, "union", "veldoria")), "no country is in the Union and the Concert at once")
	t.equal(StateValidator.validate(state).size(), 0, "and the bloc map stays valid")
	t.truth(not _in(state, "concert", "ardenia") and not _in(state, "union", "ardenia"), "the player is never listed as an AI member")


func _test_fit_respects_prerequisite_and_rival_bloc(t) -> void:
	var state := _state()
	var veldoria := DiplomacySim.world_country(state, "veldoria")
	veldoria.stability = 0.7
	_between(veldoria, DiplomacySim.world_country(state, "solheim"), 0.6)
	t.truth(not OrientationSim.bloc_fits(state, veldoria, ForeignSim.bloc("meridian")), "the alliance needs Concert membership first")
	t.truth(OrientationSim.bloc_fits(state, veldoria, ForeignSim.bloc("concert")), "while the Concert would take it")
	(state.foreign.members["union"] as Array).append("veldoria")
	t.truth(not OrientationSim.bloc_fits(state, veldoria, ForeignSim.bloc("concert")), "a Union member does not fit the Concert")
	t.truth(OrientationSim.bloc_rejects(state, veldoria, ForeignSim.bloc("concert")), "and a Union member is rejected by it")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_democratic_traders_drift_into_the_concert(t)
	_test_the_meridian_takes_only_steady_concert_members(t)
	_test_krasovan_clients_join_the_union(t)
	_test_members_who_turn_cold_walk_away(t)
	_test_an_anchor_never_leaves_its_bloc(t)
	_test_no_country_sits_on_both_sides(t)
	_test_fit_respects_prerequisite_and_rival_bloc(t)
	quit(t.finish())
