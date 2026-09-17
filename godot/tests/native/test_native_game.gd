extends SceneTree

## Standalone headless test for Task 4 unit B: the NativeGame state owner.
## Run via:
##   Godot --headless --path godot --script res://tests/native/test_native_game.gd
##
## Covers exactly the brief's case: start seed 424242, advance one day, save,
## replace in-memory state with a second campaign, load, assert full
## restoration including RNG state (a fixed number of rng draws before save
## continues identically after load). Plus the surrounding contract:
## side-effect-free _ready, snapshot shape/deep-copy semantics, the
## single-operation in-flight guard, invalid-campaign keeps-old-state, and
## self-cleaning test slots (never the real slot names).

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")

const FIXED_SEED := 424242
const SLOT_PREFIX := "t4btest-"
const SAVES_DIR := "user://saves"


static func _base_config(seed: int = FIXED_SEED) -> Dictionary:
	return {
		"country_id": "ardenia",
		"background_id": "none",
		"difficulty_id": "normal",
		"opening_role": "contextual",
		"seed": seed,
	}


static func _slot_path(slot: String, suffix: String) -> String:
	return "%s/%s.json%s" % [SAVES_DIR, slot, suffix]


static func _wipe_slot(slot: String) -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := _slot_path(slot, suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _test_ready_side_effect_free(t) -> void:
	var game = NativeGameScript.new()
	t.equal(game.snapshot(), {}, "a fresh NativeGame holds no campaign until new_campaign")
	var advanced: Dictionary = game.advance_day()
	t.truth(not advanced.get("ok", true), "advance_day with no campaign reports ok=false")
	var saved: Dictionary = game.save(SLOT_PREFIX + "nosuch")
	t.truth(not saved.get("ok", true), "save with no campaign reports ok=false")
	var loaded: Dictionary = game.load(SLOT_PREFIX + "missing-slot")
	t.truth(not loaded.get("ok", true), "load of a missing slot reports ok=false")
	game.free()


func _test_new_campaign_snapshot_shape(t) -> void:
	var game = NativeGameScript.new()
	var result: Dictionary = game.new_campaign(_base_config())
	t.truth(result.get("ok", false), "new_campaign reports ok for the Ardenia config")
	if not result.get("ok", false):
		game.free()
		return
	var snap: Dictionary = game.snapshot()
	for key in ["date", "player", "headline", "economy", "factions",
			"regions", "decisions", "digest", "dispatches", "reform"]:
		t.truth(snap.has(key), "snapshot carries '%s'" % key)
	var date: Dictionary = snap.get("date", {})
	t.equal(date.get("year"), 1993, "campaign opens in 1993")
	t.equal(date.get("month"), 3, "campaign opens in March")
	t.equal(date.get("day"), 1, "campaign opens on day 1")
	t.equal(date.get("day_index"), 0, "campaign opens at day_index 0")
	t.truth(str(date.get("text", "")).length() > 0, "date carries display text")
	var player: Dictionary = snap.get("player", {})
	t.truth(str(player.get("name", "")).length() > 0, "player carries a name")
	t.truth(str(player.get("title", "")).length() > 0, "player carries a title")
	t.truth(player.has("approval") and player.has("political_capital"),
		"player carries approval and political_capital")
	var economy: Dictionary = snap.get("economy", {})
	for key in ["growth", "unemployment", "inflation", "debt", "revenue", "expenditure"]:
		t.truth(economy.has(key), "economy carries '%s'" % key)
	t.truth((snap.get("factions", []) as Array).size() > 0, "factions are non-empty")
	t.truth(snap.get("regions") is Array, "regions is an array")
	t.equal(snap.get("decisions", [1]), [], "decisions open empty")
	t.equal(snap.get("digest", [1]), [], "digest opens empty")
	t.equal(snap.get("dispatches", [1]), [], "dispatches open empty")
	var reform: Dictionary = snap.get("reform", {})
	t.truth(reform.get("active") == null, "no reform objective is active at campaign start")
	t.equal(reform.get("objectives", [1]), [], "no reform objectives are listed yet")
	game.free()


func _test_snapshot_is_deep_duplicated(t) -> void:
	var game = NativeGameScript.new()
	game.new_campaign(_base_config())
	var snap: Dictionary = game.snapshot()
	(snap["player"] as Dictionary)["approval"] = 999.0
	(snap["date"] as Dictionary)["day"] = 99
	(snap["factions"] as Array).clear()
	var fresh: Dictionary = game.snapshot()
	t.truth(float((fresh["player"] as Dictionary)["approval"]) != 999.0,
		"mutating a returned snapshot does not leak into live state (player)")
	t.truth(int((fresh["date"] as Dictionary)["day"]) != 99,
		"mutating a returned snapshot does not leak into live state (date)")
	t.truth(not (fresh["factions"] as Array).is_empty(),
		"mutating a returned snapshot does not leak into live state (factions)")
	game.free()


func _test_round_trip_with_rng_continuity(t) -> void:
	var slot := SLOT_PREFIX + "roundtrip"
	_wipe_slot(slot)
	var game = NativeGameScript.new()
	t.truth(game.new_campaign(_base_config()).get("ok", false),
		"roundtrip: seed-424242 campaign starts")
	var advanced: Dictionary = game.advance_day()
	t.truth(advanced.get("ok", false), "roundtrip: one day advances")
	t.equal(game.snapshot()["date"]["day_index"], 1,
		"roundtrip: day_index is 1 after one advance")

	# Move the stream to a non-trivial point, then save.
	for i in range(5):
		game._state.rng.next_u32()
	t.truth(game.save(slot).get("ok", false), "roundtrip: save reports ok")
	var before: Dictionary = game.snapshot()
	# The continuation the restored stream must replay exactly.
	var expected: Array = []
	for i in range(10):
		expected.append(game._state.rng.next_u32())

	# Replace the in-memory state with a second, different campaign.
	t.truth(game.new_campaign(_base_config(777)).get("ok", false),
		"roundtrip: a second campaign replaces in-memory state")
	t.equal(game.snapshot()["date"]["day_index"], 0,
		"roundtrip: the second campaign really replaced the first")

	var loaded: Dictionary = game.load(slot)
	t.truth(loaded.get("ok", false), "roundtrip: load reports ok")
	var after: Dictionary = game.snapshot()
	t.equal(after, before, "roundtrip: load restores the full snapshot")
	t.equal(after["date"]["day_index"], 1,
		"roundtrip: the restored campaign is back on day_index 1")
	var actual: Array = []
	for i in range(10):
		actual.append(game._state.rng.next_u32())
	t.equal(actual, expected,
		"roundtrip: the restored RNG continues the identical sequence")
	game.free()


func _test_failed_load_keeps_current_state(t) -> void:
	var game = NativeGameScript.new()
	game.new_campaign(_base_config())
	game.advance_day()
	game.advance_day()
	var before: Dictionary = game.snapshot()
	var loaded: Dictionary = game.load(SLOT_PREFIX + "definitely-absent")
	t.truth(not loaded.get("ok", true), "load of a missing slot reports ok=false")
	t.equal(game.snapshot(), before,
		"a failed load leaves the current in-memory campaign untouched")
	game.free()


func _test_invalid_campaign_keeps_old_state(t) -> void:
	var game = NativeGameScript.new()
	t.truth(game.new_campaign(_base_config()).get("ok", false),
		"invalid: a valid campaign starts first")
	var before: Dictionary = game.snapshot()
	var fatal_messages: Array = []
	game.fatal_error.connect(func(message: String) -> void: fatal_messages.append(message))
	var bad := _base_config()
	bad["country_id"] = "krasova"
	var result: Dictionary = game.new_campaign(bad)
	t.truth(not result.get("ok", true),
		"invalid: a non-Ardenia config reports ok=false")
	t.equal(fatal_messages.size(), 0,
		"invalid: a recoverable mid-game rejection emits no fatal_error")
	t.equal(game.snapshot(), before,
		"invalid: the old campaign survives a rejected new_campaign")
	game.free()


func _test_in_flight_guard(t) -> void:
	var game = NativeGameScript.new()
	game.new_campaign(_base_config())
	# Containers, not rebound locals: lambdas capture locals by value, so
	# only in-place mutation (append / key-set) is visible outside.
	var emissions: Array = []
	var inner: Dictionary = {}
	# A pre-set flag (not is_empty-after-assignment): the nested call below
	# runs DURING the outer emit, so any flag set by the nested result is
	# still unset when the nested handler runs — checking it there would
	# recurse without bound.
	var nested_done := [false]
	game.state_changed.connect(func(_snap: Dictionary) -> void:
		emissions.append(1)
		if not nested_done[0]:
			nested_done[0] = true
			inner["result"] = game.advance_day()
	)
	var day_before: int = (game.snapshot()["date"] as Dictionary)["day_index"]
	var outer: Dictionary = game.advance_day()
	t.truth(outer.get("ok", false), "guard: the outer advance_day succeeds")
	# The guard covers the emit itself: a subscriber that calls back in is
	# refused with ok=false (no second emission, no state change) instead of
	# recursing into the half-observed outer operation.
	t.equal(emissions.size(), 1, "guard: one emission total; the refused nested call emits nothing")
	var inner_result: Dictionary = inner.get("result", {})
	t.truth(not inner_result.get("ok", true),
		"guard: a reentrant call during the emit is refused with ok=false")
	t.truth(inner_result.has("error"),
		"guard: the reentrant refusal carries an error")
	t.equal((game.snapshot()["date"] as Dictionary)["day_index"], day_before + 1,
		"guard: exactly one day advanced (outer only; nested call changed nothing)")
	# The guard itself still rejects true overlap: with _busy held, any op
	# is refused without touching state.
	game._busy = true
	var before: Dictionary = game.snapshot()
	var refused: Dictionary = game.advance_day()
	t.truth(not refused.get("ok", true),
		"guard: a second call while one runs is rejected with ok=false")
	t.truth(refused.has("error"), "guard: the rejection carries an error")
	t.equal(game.snapshot(), before,
		"guard: the rejected call leaves live state untouched")
	game._busy = false
	game.free()


func _test_state_changed_on_lifecycle(t) -> void:
	var slot := SLOT_PREFIX + "signals"
	_wipe_slot(slot)
	var game = NativeGameScript.new()
	var seen: Array = []
	game.state_changed.connect(func(snap: Dictionary) -> void: seen.append(snap))
	game.new_campaign(_base_config())
	t.equal(seen.size(), 1, "new_campaign emits state_changed once")
	game.advance_day()
	t.equal(seen.size(), 2, "advance_day emits state_changed once")
	game.save(slot)
	t.equal(seen.size(), 2, "save emits no state_changed")
	game.advance_day()
	game.load(slot)
	t.equal(seen.size(), 4, "load emits state_changed once (plus the second advance)")
	t.truth(seen[0].has("date") and seen[0].has("reform"),
		"emitted snapshots carry the UI shape")
	game.free()


func _test_fresh_bad_config_emits_fatal(t) -> void:
	var game = NativeGameScript.new()
	var fatal_messages: Array = []
	game.fatal_error.connect(func(message: String) -> void: fatal_messages.append(message))
	var bad := _base_config()
	bad["country_id"] = "krasova"
	var result: Dictionary = game.new_campaign(bad)
	t.truth(not result.get("ok", true),
		"fatal-path: a bad config on an empty game reports ok=false")
	t.truth(result.has("error"), "fatal-path: the rejection carries an error")
	t.equal(fatal_messages.size(), 1,
		"fatal-path: failure with no live campaign emits fatal_error once")
	t.equal(game.snapshot(), {},
		"fatal-path: state stays null (empty snapshot) after the fatal rejection")
	game.free()


func _test_failed_validation_load_keeps_state_no_fatal(t) -> void:
	var slot := SLOT_PREFIX + "badworld"
	_wipe_slot(slot)
	var game = NativeGameScript.new()
	t.truth(game.new_campaign(_base_config()).get("ok", false),
		"badworld: a valid campaign starts first")
	game.advance_day()
	var before: Dictionary = game.snapshot()
	t.truth(game.save(slot).get("ok", false), "badworld: the valid campaign saves")
	# Craft a validator-failing save: an otherwise-valid payload whose world
	# is empty (StateValidator requires a non-empty world).
	var path := _slot_path(slot, "")
	var reader := FileAccess.open(path, FileAccess.READ)
	var payload = JSON.parse_string(reader.get_as_text())
	reader.close()
	(payload["state"] as Dictionary)["world"] = []
	var writer := FileAccess.open(path, FileAccess.WRITE)
	writer.store_string(JSON.stringify(payload))
	writer.flush()
	writer.close()
	var fatal_messages: Array = []
	game.fatal_error.connect(func(message: String) -> void: fatal_messages.append(message))
	var result: Dictionary = game.load(slot)
	t.truth(not result.get("ok", true),
		"badworld: loading a validator-failing save reports ok=false")
	t.truth(result.has("error"), "badworld: the rejection carries an error")
	t.equal(fatal_messages.size(), 0,
		"badworld: a failed load never emits fatal_error")
	t.equal(game.snapshot(), before,
		"badworld: the live campaign survives byte-identical")
	game.free()
	_wipe_slot(slot)


func _test_reentrant_advance_from_handler_refused(t) -> void:
	var game = NativeGameScript.new()
	game.new_campaign(_base_config())
	var calls: Array = []
	var inner: Dictionary = {}
	var entered := [false]
	game.state_changed.connect(func(_snap: Dictionary) -> void:
		calls.append(1)
		if not entered[0]:
			entered[0] = true
			inner["result"] = game.advance_day()
	)
	var day_before: int = (game.snapshot()["date"] as Dictionary)["day_index"]
	var outer: Dictionary = game.advance_day()
	t.truth(outer.get("ok", false), "reentrant: the outer advance_day succeeds")
	var inner_result: Dictionary = inner.get("result", {})
	t.truth(not inner_result.get("ok", true),
		"reentrant: advance_day from inside a state_changed handler is refused")
	t.truth(inner_result.has("error"),
		"reentrant: the refusal carries an error")
	t.equal(calls.size(), 1,
		"reentrant: the refused nested call emits nothing further")
	t.equal((game.snapshot()["date"] as Dictionary)["day_index"], day_before + 1,
		"reentrant: only the outer advance moved the calendar")
	game.free()


static func _write_repo_file(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()


static func _wipe_repo_tree(root: String) -> void:
	# Best-effort recursive wipe of a temp user:// tree (self-cleaning).
	var dir := DirAccess.open(root)
	if dir == null:
		return
	for entry in dir.get_files():
		DirAccess.remove_absolute(root.path_join(entry))
	for entry in dir.get_directories():
		_wipe_repo_tree(root.path_join(entry))
		DirAccess.remove_absolute(root.path_join(entry))
	DirAccess.remove_absolute(root)


func _test_country_inner_id_consistency(t) -> void:
	var root := "user://t4btest-country-id/"
	_wipe_repo_tree(root)
	_write_repo_file(root.path_join("catalog_manifest.json"),
		'{"schema_version": 1, "files": ["countries/ardenia.json", "countries/krasova.json"]}')
	_write_repo_file(root.path_join("countries/ardenia.json"),
		'{"id": "ardenia", "name": "Ardenia"}')
	# Inner id does not match the filename stem.
	_write_repo_file(root.path_join("countries/krasova.json"),
		'{"id": "not_krasova", "name": "Krasova"}')
	var mismatched: Dictionary = ContentRepositoryScript.load_all(root)
	t.truth(mismatched.has("error"),
		"country-id: a countries/ file whose inner id mismatches its stem is rejected")
	# The same stem listed twice must error, not silently overwrite.
	_write_repo_file(root.path_join("countries/krasova.json"),
		'{"id": "krasova", "name": "Krasova"}')
	_write_repo_file(root.path_join("catalog_manifest.json"),
		'{"schema_version": 1, "files": ["countries/ardenia.json", "countries/ardenia.json"]}')
	var duplicated: Dictionary = ContentRepositoryScript.load_all(root)
	t.truth(duplicated.has("error"),
		"country-id: a duplicate country id across files is rejected, not overwritten")
	_write_repo_file(root.path_join("catalog_manifest.json"),
		'{"schema_version": 1, "files": ["countries/ardenia.json", "countries/krasova.json"]}')
	var ok_result: Dictionary = ContentRepositoryScript.load_all(root)
	t.truth(not ok_result.has("error"),
		"country-id: matching inner ids load cleanly")
	_wipe_repo_tree(root)


func _initialize() -> void:
	var t = TestSupportScript.new()

	_test_ready_side_effect_free(t)
	_test_new_campaign_snapshot_shape(t)
	_test_snapshot_is_deep_duplicated(t)
	_test_round_trip_with_rng_continuity(t)
	_test_failed_load_keeps_current_state(t)
	_test_invalid_campaign_keeps_old_state(t)
	_test_in_flight_guard(t)
	_test_state_changed_on_lifecycle(t)
	_test_fresh_bad_config_emits_fatal(t)
	_test_failed_validation_load_keeps_state_no_fatal(t)
	_test_reentrant_advance_from_handler_refused(t)
	_test_country_inner_id_consistency(t)

	for slot in [SLOT_PREFIX + "roundtrip", SLOT_PREFIX + "signals",
			SLOT_PREFIX + "nosuch", SLOT_PREFIX + "missing-slot",
			SLOT_PREFIX + "definitely-absent", SLOT_PREFIX + "badworld"]:
		_wipe_slot(slot)
	_wipe_repo_tree("user://t4btest-country-id/")
	var residue := false
	for slot in [SLOT_PREFIX + "roundtrip", SLOT_PREFIX + "signals",
			SLOT_PREFIX + "nosuch", SLOT_PREFIX + "missing-slot",
			SLOT_PREFIX + "definitely-absent", SLOT_PREFIX + "badworld"]:
		for suffix in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(_slot_path(slot, suffix)):
				residue = true
	if DirAccess.open("user://t4btest-country-id/") != null:
		residue = true
	t.truth(not residue, "cleanup: no test slot residue remains in user://saves/")

	quit(t.finish())
