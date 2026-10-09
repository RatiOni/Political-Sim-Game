extends SceneTree

## Task 10 contract tests. Production scripts do not exist yet: this file is
## deliberately written before them to pin the native monthly behaviour.
const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")
const GameFactoryScript = preload("res://scripts/native/state/game_factory.gd")
const RegionsSimScript = preload("res://scripts/native/sim/regions_sim.gd")
const HouseholdsSimScript = preload("res://scripts/native/sim/households_sim.gd")
const StabilitySimScript = preload("res://scripts/native/sim/stability_sim.gd")
const MonthlyDigestScript = preload("res://scripts/native/presentation/monthly_digest.gd")


func _state(content: Dictionary) -> GameState:
	var state: GameState = GameFactoryScript.new_campaign(content, {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "contextual", "seed": 424242,
	})
	RegionsSimScript.ensure_region_states(state)
	HouseholdsSimScript.ensure_households(state)
	return state


func _test_stability_directions_and_bounds(t, content: Dictionary) -> void:
	var good := _state(content)
	var bad := _state(content)
	good.country.economy.growth_rate = 0.12
	good.country.economy.unemployment = 0.03
	good.country.economy.inflation = 0.01
	bad.country.economy.growth_rate = -0.12
	bad.country.economy.unemployment = 0.40
	bad.country.economy.inflation = 0.60
	for h in good.households.values():
		h.confidence = 0.90
		h.hardship = 0.05
	for h in bad.households.values():
		h.confidence = 0.10
		h.hardship = 0.95
	for region in bad.regions.values():
		region.pressure = 1.0
	StabilitySimScript.update_approval(good)
	StabilitySimScript.update_stability(good)
	StabilitySimScript.update_approval(bad)
	StabilitySimScript.update_stability(bad)
	t.truth(good.player.approval > bad.player.approval, "approval follows real economic and household conditions")
	t.truth(good.stability_value > bad.stability_value, "stability follows economy, households and regional pressure")
	for state in [good, bad]:
		state.player.approval = 0.0
		state.stability_value = 1.0
		for month in range(120):
			StabilitySimScript.update_approval(state)
			StabilitySimScript.update_stability(state)
		t.truth(state.player.approval >= 0.0 and state.player.approval <= 1.0, "approval remains bounded")
		t.truth(state.stability_value >= 0.0 and state.stability_value <= 1.0, "stability remains bounded")


func _test_opposition_contract(t, content: Dictionary) -> void:
	var left := _state(content)
	var right := _state(content)
	left.player.in_government = false
	right.player.in_government = false
	for faction in left.country.factions:
		faction.loyalty = -1.0
	for faction in right.country.factions:
		faction.loyalty = 1.0
	for minister in left.ministers:
		minister.loyalty = 0.0
	for minister in right.ministers:
		minister.loyalty = 1.0
	StabilitySimScript.update_approval(left)
	StabilitySimScript.update_approval(right)
	StabilitySimScript.update_stability(left)
	StabilitySimScript.update_stability(right)
	t.near(left.player.approval, right.player.approval, 0.000001, "opposition approval neutralises player-relative loyalty")
	t.near(left.stability_value, right.stability_value, 0.000001, "opposition stability neutralises stale cabinet and player loyalty")


func _test_digest_is_pure_and_material(t, content: Dictionary) -> void:
	var state := _state(content)
	var before: Dictionary = MonthlyDigestScript.capture(state)
	var baseline := state.to_dict()
	t.equal(MonthlyDigestScript.build(state, before), [], "quiet digest is empty")
	t.equal(state.to_dict(), baseline, "digest readers never mutate the campaign")
	state.country.economy.inflation = 0.60
	for h in state.households.values():
		h.hardship = 0.95
		h.confidence = 0.05
	StabilitySimScript.update_approval(state)
	StabilitySimScript.update_stability(state)
	var lines: Array[String] = MonthlyDigestScript.build(state, before)
	t.truth(not lines.is_empty(), "material monthly movement produces a digest")


func _initialize() -> void:
	var t = TestSupportScript.new()
	var content: Dictionary = ContentRepositoryScript.load_all()
	t.truth(not content.has("error"), "content loads for stability and digest")
	if not content.has("error"):
		_test_stability_directions_and_bounds(t, content)
		_test_opposition_contract(t, content)
		_test_digest_is_pure_and_material(t, content)
	quit(t.finish())
