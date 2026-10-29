extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const SLOT := "test_orientation_snapshot"


static func _state() -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	state.player.political_capital = 500.0
	return state


static func _wipe() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := "user://saves/%s.json%s" % [SLOT, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _test_the_snapshot_carries_the_orientation_desk(t) -> void:
	var foreign: Dictionary = NativeGameScript._build_snapshot(_state()).get("foreign", {})
	t.equal((foreign.get("powers", []) as Array).size(), ForeignSim.power_ids().size(), "every power is on the desk")
	t.equal((foreign.get("steps", []) as Array).size(), OrientationActions.VERBS.size(), "and every orientation step")
	t.truth((foreign.get("isf", {}) as Dictionary).has("deficit_target"), "with the ISF's next targets")
	var held: Array = (foreign["steps"] as Array).filter(func(s: Dictionary) -> bool: return bool(s["held"]))
	t.truth(held.any(func(s: Dictionary) -> bool: return s["verb"] == "concert_application"), "the standing application shows as held")
	t.truth(held.all(func(s: Dictionary) -> bool: return String(s["disabled_reason"]) == ""), "and a held step carries no refusal")


func _test_the_map_learns_who_sits_in_which_bloc(t) -> void:
	var state := _state()
	state.foreign.reached["union_observer"] = 0
	state.foreign.reached["union_member"] = 0
	var memberships: Dictionary = NativeGameScript._build_snapshot(state)["foreign"]["map"]["memberships"]
	t.truth("union" in memberships["ardenia"], "Ardenia's Union membership is published for the map")
	t.truth("concert" in memberships["solheim"], "as is each world country's")
	t.truth(not ("concert" in memberships["ardenia"]), "an application is not membership")


func _test_the_game_takes_orientation_steps(t) -> void:
	var game: Node = NativeGameScript.new()
	game._state = _state()
	var result: Dictionary = game.orientation_act("meridian_partnership")
	t.truth(result.get("ok", false), "a step can be taken through the game")
	var steps: Array = result["snapshot"]["foreign"]["steps"]
	t.truth(steps.any(func(s: Dictionary) -> bool: return s["verb"] == "meridian_partnership" and s["held"]), "and the returned snapshot shows it held")
	t.truth(not game.orientation_act("meridian_partnership").get("ok", true), "a step cannot be taken twice")
	game.free()


func _test_a_refused_step_changes_nothing(t) -> void:
	var game: Node = NativeGameScript.new()
	game._state = _state()
	var state: GameState = game._state
	var capital := state.player.political_capital
	var reached := state.foreign.reached.duplicate(true)
	var powers := state.foreign.powers.duplicate(true)
	var result: Dictionary = game.orientation_act("meridian_guarantee")
	t.truth(not result.get("ok", true), "a step out of reach is refused")
	t.equal(state.player.political_capital, capital, "a refusal costs no political capital")
	t.equal(state.foreign.reached, reached, "a refusal reaches no milestone")
	t.equal(state.foreign.powers, powers, "a refusal moves no commitment")
	game.free()


func _test_a_save_without_a_ledger_is_seeded_on_load(t) -> void:
	_wipe()
	var state := _state()
	state.foreign = ForeignState.new()
	SaveStore.save_slot(SLOT, state)
	var game: Node = NativeGameScript.new()
	t.truth(game.load(SLOT).get("ok", false), "a save without a foreign ledger loads")
	t.truth(game._state.foreign.seeded and game._state.foreign.reached.has("isf_programme"), "and is seeded with the canon obligations")
	game.free()
	_wipe()


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_the_snapshot_carries_the_orientation_desk(t)
	_test_the_map_learns_who_sits_in_which_bloc(t)
	_test_the_game_takes_orientation_steps(t)
	_test_a_refused_step_changes_nothing(t)
	_test_a_save_without_a_ledger_is_seeded_on_load(t)
	quit(t.finish())
