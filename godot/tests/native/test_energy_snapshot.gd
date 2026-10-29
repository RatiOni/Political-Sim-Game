extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")


static func _state() -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	return state


func _test_the_snapshot_carries_the_contract(t) -> void:
	var energy: Dictionary = NativeGameScript._build_snapshot(_state())["foreign"]["energy"]
	t.truth(energy.get("active", false), "the desk sees an active contract")
	t.equal(String(energy["supplier"]), "Krasova", "named by its supplier")
	t.equal((energy["steps"] as Array).size(), EnergyActions.VERBS.size(), "with every energy operation")
	t.equal(int(energy["months_to_renewal"]), 22, "and the months until renewal")


func _test_the_map_gets_the_gas_supply(t) -> void:
	var state := _state()
	state.foreign.gas.last_flow = {"shortfall": 0.4, "severity": 0.4}
	var supply: Dictionary = NativeGameScript._build_snapshot(state)["foreign"]["map"]["gas_supply"]
	t.equal(supply.size(), state.regions.size(), "every region has a supply ratio")
	t.near(float(supply["zavost"]), 0.4, 0.000001, "Zavost shows its deeper shortfall")
	t.near(float(supply["vashtera"]), 0.6, 0.000001, "the capital the national one")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_the_snapshot_carries_the_contract(t)
	_test_the_map_gets_the_gas_supply(t)
	quit(t.finish())
