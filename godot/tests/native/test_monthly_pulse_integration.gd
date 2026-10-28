extends SceneTree

## End-to-end proof that NativeGame runs the real Phase 2 sequence exactly
## once at a calendar month rollover, including save/load continuation.
const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const BudgetSimScript = preload("res://scripts/native/sim/budget_sim.gd")
const PoliticalCapitalScript = preload("res://scripts/native/sim/political_capital.gd")
const MinistriesSimScript = preload("res://scripts/native/sim/ministries_sim.gd")
const EconomySimScript = preload("res://scripts/native/sim/economy_sim.gd")
const RegionsSimScript = preload("res://scripts/native/sim/regions_sim.gd")
const HouseholdsSimScript = preload("res://scripts/native/sim/households_sim.gd")
const StabilitySimScript = preload("res://scripts/native/sim/stability_sim.gd")
const MonthlyDigestScript = preload("res://scripts/native/presentation/monthly_digest.gd")

const SAVES_DIR := "user://saves"
const SLOT_PREFIX := "t10pulse_"


func _config() -> Dictionary:
	return {"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal", "opening_role": "contextual", "seed": 424242}


static func _slot_path(slot: String, suffix: String) -> String:
	return "%s/%s.json%s" % [SAVES_DIR, slot, suffix]


static func _wipe_slot(slot: String) -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := _slot_path(slot, suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


static func _without_calendar(state: GameState) -> Dictionary:
	var data := state.to_dict()
	for key in ["year", "month", "day", "day_index"]:
		data.erase(key)
	return data


static func _values_match(a: Variant, b: Variant) -> bool:
	var a_num := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var b_num := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	if a_num and b_num:
		if typeof(a) == TYPE_INT and typeof(b) == TYPE_INT:
			return a == b
		var scale := maxf(1.0, maxf(absf(float(a)), absf(float(b))))
		return absf(float(a) - float(b)) <= 1e-9 * scale
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for key in (a as Dictionary).keys():
			if not (b as Dictionary).has(key) or not _values_match(a[key], b[key]):
				return false
		return true
	if a is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in range((a as Array).size()):
			if not _values_match(a[i], b[i]):
				return false
		return true
	return a == b


static func _run_reference_rollover(state: GameState) -> void:
	var before: Dictionary = MonthlyDigestScript.capture(state)
	assert(Calendar.advance_day(state))
	state.turn += 1
	BudgetSimScript.process_fiscal_year(state)
	PoliticalCapitalScript.regenerate(state)
	MinistriesSimScript.simulate(state)
	DiplomacySim.monthly(state)
	EconomySimScript.update(state)
	RegionsSimScript.simulate(state)
	HouseholdsSimScript.simulate(state)
	CabinetSim.monthly(state)
	StabilitySimScript.update_approval(state)
	StabilitySimScript.update_stability(state)
	var crisis_notes := CrisisSim.monthly(state)
	Modifiers.age_all(state)
	var situation_notes := EventsSim.monthly(state)
	state.monthly_digest = MonthlyDigestScript.build(state, before)
	state.monthly_digest.append_array(crisis_notes)
	state.monthly_digest.append_array(situation_notes)


func _test_full_monthly_pulse(t) -> void:
	var game = NativeGameScript.new()
	t.truth(game.new_campaign(_config()).get("ok", false), "campaign starts")
	var opening: Dictionary = game.snapshot()
	t.equal(opening["date"]["turn"], 0, "campaign opens before any monthly pulses")
	t.equal(opening["digest"], [], "campaign opens with no completed report")
	var ordinary_before := _without_calendar(game._state)
	var ordinary: Dictionary = game.advance_day()
	t.truth(ordinary.get("ok", false) and not ordinary.get("month_rolled", true), "ordinary day advances without a monthly pulse")
	t.equal(_without_calendar(game._state), ordinary_before, "ordinary day has no monthly simulation side effects")

	game._state.day = 31
	var modifier := Modifier.new()
	modifier.id = "pulse-age"
	modifier.source = "Pulse test"
	modifier.target = "approval_bias"
	modifier.magnitude = 0.01
	modifier.age = 7
	game._state.modifiers.append(modifier)
	var expected := GameState.from_dict(game._state.to_dict())
	_run_reference_rollover(expected)
	var rollover: Dictionary = game.advance_day()
	t.truth(rollover.get("ok", false) and rollover.get("month_rolled", false), "month boundary advances")
	t.truth(_values_match(game._state.to_dict(), expected.to_dict()), "rollover executes every monthly phase once in the specified order")
	var after: Dictionary = game.snapshot()
	t.equal(after["date"]["turn"], 1, "month rollover increments the turn exactly once")
	t.equal(game._state.modifiers[0].age, 8, "modifier ages exactly once at rollover")
	t.truth((after.get("budget", {}) as Dictionary).size() > 0, "snapshot exposes active budget read model")
	t.truth((after.get("ministries", {}) as Dictionary).size() > 0, "snapshot exposes committed ministries")
	t.truth((after.get("households", {}) as Dictionary).size() > 0, "snapshot exposes national household summary")
	t.equal(game._state.households.size(), 54, "monthly pulse simulated all Ardenian household records")
	t.equal(game._state.regions.size(), 9, "monthly pulse retained regional state")
	t.truth(after.has("digest"), "snapshot exposes completed digest")
	var headline: Dictionary = after.get("headline", {})
	t.truth(headline.has("value"), "snapshot headline exposes numeric stability beside its label")
	if headline.has("value"):
		t.near(float(headline["value"]), game._state.stability_value, 0.000001, "headline stability value matches live state")
	var detached := game.snapshot()
	if (detached.get("headline", {}) as Dictionary).has("value"):
		detached["headline"]["value"] = -1.0
	detached["households"].clear()
	var fresh := game.snapshot()
	t.near(float(fresh["headline"].get("value", -1.0)), game._state.stability_value, 0.000001, "snapshot stability value is detached from live state")
	t.truth(not fresh["households"].is_empty(), "nested snapshot read models are detached")
	var age_after_rollover: int = game._state.modifiers[0].age
	var turn_after_rollover: int = game._state.turn
	game.advance_day()
	t.equal(game._state.modifiers[0].age, age_after_rollover, "modifier does not age again on the next ordinary day")
	t.equal(game._state.turn, turn_after_rollover, "monthly turn does not repeat on the next ordinary day")
	game.free()


func _test_january_budget_once(t) -> void:
	var pending_game = NativeGameScript.new()
	t.truth(pending_game.new_campaign(_config()).get("ok", false), "pending-budget campaign starts")
	pending_game._state.year = 1993
	pending_game._state.month = 12
	pending_game._state.day = 31
	var inherited := BudgetSimScript.ensure_budget_state(pending_game._state)
	var pending := AnnualBudget.from_dict(inherited.to_dict())
	pending.year = 1994
	pending.status = "approved"
	pending.source = "player_proposal"
	pending_game._state.pending_budget = pending
	t.truth(pending_game.advance_day().get("month_rolled", false), "approved pending budget reaches January")
	t.equal(pending_game._state.active_budget.source, "player_proposal", "approved pending budget activates on 1 January")
	t.equal(pending_game._state.budget_history.size(), 1, "pending budget activates exactly once")
	pending_game.advance_day()
	t.equal(pending_game._state.budget_history.size(), 1, "pending budget does not activate again on 2 January")
	pending_game.free()

	var continuing_game = NativeGameScript.new()
	t.truth(continuing_game.new_campaign(_config()).get("ok", false), "continuing-budget campaign starts")
	continuing_game._state.year = 1993
	continuing_game._state.month = 12
	continuing_game._state.day = 31
	BudgetSimScript.ensure_budget_state(continuing_game._state)
	t.truth(continuing_game.advance_day().get("month_rolled", false), "missing budget reaches January")
	t.equal(continuing_game._state.active_budget.source, "continuing", "missing plan creates the continuing budget on 1 January")
	t.equal(continuing_game._state.budget_history.size(), 1, "continuing budget activates exactly once")
	continuing_game.advance_day()
	t.equal(continuing_game._state.budget_history.size(), 1, "continuing budget does not activate again on 2 January")
	continuing_game.free()


func _test_same_seed_replay(t) -> void:
	var left = NativeGameScript.new()
	var right = NativeGameScript.new()
	t.truth(left.new_campaign(_config()).get("ok", false), "left replay campaign starts")
	t.truth(right.new_campaign(_config()).get("ok", false), "right replay campaign starts")
	left._state.day = 31
	right._state.day = 31
	left.advance_day()
	right.advance_day()
	t.equal(left.snapshot(), right.snapshot(), "same seed and inputs replay the identical monthly pulse")
	left.free()
	right.free()


func _test_save_load_rollover(t) -> void:
	var before_slot := SLOT_PREFIX + "before"
	var after_slot := SLOT_PREFIX + "after"
	_wipe_slot(before_slot)
	_wipe_slot(after_slot)

	var source = NativeGameScript.new()
	t.truth(source.new_campaign(_config()).get("ok", false), "pre-rollover save campaign starts")
	source._state.day = 31
	var control = NativeGameScript.new()
	control._state = GameState.from_dict(source._state.to_dict())
	t.truth(source.save(before_slot).get("ok", false), "NativeGame saves immediately before rollover")
	var resumed = NativeGameScript.new()
	t.truth(resumed.load(before_slot).get("ok", false), "NativeGame loads the pre-rollover save")
	t.truth(resumed.advance_day().get("month_rolled", false), "loaded pre-rollover save runs one pulse")
	t.truth(control.advance_day().get("month_rolled", false), "uninterrupted control runs one pulse")
	t.equal(resumed._state.turn, 1, "loaded pre-rollover save increments turn once")
	t.truth(_values_match(resumed.snapshot(), control.snapshot()), "save/load before rollover continues to the same snapshot")

	var completed_snapshot := resumed.snapshot()
	var completed_digest: Array[String] = resumed._state.monthly_digest.duplicate()
	t.truth(resumed.save(after_slot).get("ok", false), "NativeGame saves after completed rollover")
	var reloaded = NativeGameScript.new()
	t.truth(reloaded.load(after_slot).get("ok", false), "NativeGame loads the post-rollover save")
	t.equal(reloaded._state.turn, 1, "post-rollover load preserves completed turn")
	t.equal(reloaded._state.monthly_digest, completed_digest, "post-rollover load preserves completed digest")
	t.truth(_values_match(reloaded.snapshot(), completed_snapshot), "post-rollover load preserves the full snapshot")
	var side_effects_before := _without_calendar(reloaded._state)
	var next_day := reloaded.advance_day()
	t.truth(not next_day.get("month_rolled", true), "first day after loaded rollover is ordinary")
	t.truth(_values_match(_without_calendar(reloaded._state), side_effects_before), "post-rollover load does not run a second pulse")

	for game in [source, control, resumed, reloaded]:
		game.free()
	_wipe_slot(before_slot)
	_wipe_slot(after_slot)


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_full_monthly_pulse(t)
	_test_january_budget_once(t)
	_test_same_seed_replay(t)
	_test_save_load_rollover(t)
	quit(t.finish())