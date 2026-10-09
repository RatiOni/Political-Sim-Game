extends SceneTree

## End-to-end proof that NativeGame runs the real Phase 2 sequence exactly
## once at a calendar month rollover.
const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")


func _config() -> Dictionary:
	return {"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal", "opening_role": "contextual", "seed": 424242}


func _advance_to_rollover(game) -> Dictionary:
	var result := {}
	while true:
		result = game.advance_day()
		if result.get("month_rolled", false):
			return result
	return result


func _test_full_monthly_pulse(t) -> void:
	var game = NativeGameScript.new()
	t.truth(game.new_campaign(_config()).get("ok", false), "campaign starts")
	var before: Dictionary = game.snapshot()
	t.equal(before["date"]["turn"], 0, "campaign opens before any monthly pulses")
	t.equal(before["digest"], [], "campaign opens with no completed report")
	var ordinary: Dictionary = game.advance_day()
	t.truth(ordinary.get("ok", false) and not ordinary.get("month_rolled", true), "ordinary day advances without a monthly pulse")
	t.equal(game.snapshot()["date"]["turn"], 0, "ordinary day does not increment the monthly turn")
	var rollover := _advance_to_rollover(game)
	t.truth(rollover.get("ok", false) and rollover.get("month_rolled", false), "month boundary advances")
	var after: Dictionary = game.snapshot()
	t.equal(after["date"]["turn"], 1, "month rollover increments the turn exactly once")
	t.truth((after.get("budget", {}) as Dictionary).size() > 0, "snapshot exposes active budget read model")
	t.truth((after.get("ministries", {}) as Dictionary).size() > 0, "snapshot exposes committed ministries")
	t.truth((after.get("households", {}) as Dictionary).size() > 0, "snapshot exposes national household summary")
	t.equal(game._state.households.size(), 54, "monthly pulse simulated all Ardenian household records")
	t.equal(game._state.regions.size(), 9, "monthly pulse retained regional state")
	t.truth(game._state.ministries.size() > 0, "monthly pulse ran ministries")
	t.truth(after.has("digest"), "snapshot exposes completed digest")
	var stable := game.snapshot()
	t.equal(after, stable, "snapshot reads do not re-run monthly simulation")
	game.free()


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_full_monthly_pulse(t)
	quit(t.finish())
