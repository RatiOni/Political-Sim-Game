extends SceneTree

## Standalone headless test for Task 4 unit A: native persistence.
## Run via:
##   Godot --headless --path godot --script res://tests/native/test_native_persistence.gd
##
## Covers exactly the brief's cases: exact save/load round trip including RNG
## continuity, corrupt-JSON rejection, unsupported-version rejection, slot-regex
## rejection (traversal + overlong names), and interrupted-write survival via
## the .tmp-ignore / .bak-recovery protocol. Unit A adds: required-subtree
## rejection (empty state, country:null, wrong-typed containers, missing rng),
## missing-main .bak recovery, dual-corruption reporting, and validator range
## checks (dates, ministers, civil-war risk, relation bounds) asserted both
## directly and through a save→load→validate chain. Test states come from
## GameFactory.new_campaign, mirroring test_game_factory.gd's setup.

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")
const GameFactoryScript = preload("res://scripts/native/state/game_factory.gd")
const StateValidatorScript = preload("res://scripts/native/state/state_validator.gd")
const SaveStoreScript = preload("res://scripts/native/state/save_store.gd")

const FIXED_SEED := 424242
const SLOT_PREFIX := "t4test-"
const SAVES_DIR := "user://saves"


static func _base_config() -> Dictionary:
	return {
		"country_id": "ardenia",
		"background_id": "none",
		"difficulty_id": "normal",
		"opening_role": "contextual",
		"seed": FIXED_SEED,
	}


func _new_test_state(content: Dictionary) -> GameState:
	return GameFactoryScript.new_campaign(content, _base_config())


static func _slot_path(slot: String, suffix: String) -> String:
	return "%s/%s.json%s" % [SAVES_DIR, slot, suffix]


static func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.flush()
	f.close()


## Deep save/load comparison. Ints, strings, bools, nulls, array order, and
## dict key sets must match bit-exactly; ints and whole floats compare
## numerically (the JSON boundary erases the int/float distinction inside
## schemaless Dictionaries like campaign_meta); float pairs must agree within
## tight repr noise (see the deviation note in the report — Godot's JSON
## float printing is not bit-exact for arbitrary doubles).
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
		for k in (a as Dictionary).keys():
			if not (b as Dictionary).has(k):
				return false
			if not _values_match(a[k], b[k]):
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


static func _wipe_slot(slot: String) -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := _slot_path(slot, suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _test_round_trip(t, content: Dictionary) -> void:
	var slot := SLOT_PREFIX + "roundtrip"
	_wipe_slot(slot)
	var state: GameState = _new_test_state(content)
	t.truth(state != null, "roundtrip: factory builds a campaign state")
	if state == null:
		return

	# Advance the RNG before saving so continuity has a non-trivial stream.
	for i in range(10):
		state.rng.next_u32()
	var before: Dictionary = state.to_dict()

	var saved: Dictionary = SaveStoreScript.save_slot(slot, state)
	t.truth(saved.get("ok", false), "roundtrip: save_slot reports ok")
	if not saved.get("ok", false):
		return

	var loaded_result: Dictionary = SaveStoreScript.load_slot(slot)
	t.truth(loaded_result.get("ok", false), "roundtrip: load_slot reports ok")
	if not loaded_result.get("ok", false):
		return
	var loaded: GameState = loaded_result.get("state")
	t.truth(loaded != null and loaded != state, "roundtrip: load builds a fresh GameState object")
	if loaded == null:
		return

	t.equal(loaded.year, state.year, "roundtrip: year survives")
	t.equal(loaded.player.name, state.player.name, "roundtrip: player name survives")
	t.equal(loaded.country.id, "ardenia", "roundtrip: player country survives")
	t.equal(loaded.world.size(), state.world.size(), "roundtrip: world size survives")
	t.equal(loaded.to_dict()["rng"], before["rng"], "roundtrip: rng snapshot survives")
	t.equal(typeof(loaded.year), TYPE_INT, "roundtrip: typed ints come back as ints (year)")
	t.equal(typeof(loaded.country.population), TYPE_INT,
		"roundtrip: typed ints come back as ints (population)")
	t.equal(typeof(loaded.country.factions[0].seats), TYPE_INT,
		"roundtrip: typed ints come back as ints (seats)")
	t.truth(_values_match(before, loaded.to_dict()),
		"roundtrip: save/load round-trips every field (floats within JSON repr noise)")

	var errors := StateValidatorScript.validate(loaded)
	t.equal(errors.size(), 0, "roundtrip: loaded state validates (%s)" % [errors])

	# RNG continuity: the restored stream must continue identically.
	var expected: Array = []
	for i in range(25):
		expected.append(state.rng.next_u32())
	var actual: Array = []
	for i in range(25):
		actual.append(loaded.rng.next_u32())
	t.equal(actual, expected, "roundtrip: restored RNG continues the identical sequence")


func _test_corrupt_json_rejected(t) -> void:
	var slot := SLOT_PREFIX + "corrupt"
	_wipe_slot(slot)
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)
	_write_text(_slot_path(slot, ""), "{{{ this is not json !!!")
	t.truth(not FileAccess.file_exists(_slot_path(slot, ".bak")),
		"corrupt: precondition holds (no .bak present)")
	var result: Dictionary = SaveStoreScript.load_slot(slot)
	t.truth(not result.get("ok", true), "corrupt: corrupt main file with no .bak is rejected")
	t.truth(result.has("error"), "corrupt: rejection carries an error message")


func _test_unsupported_version_rejected(t, content: Dictionary) -> void:
	var slot := SLOT_PREFIX + "badversion"
	_wipe_slot(slot)
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)
	var state: GameState = _new_test_state(content)
	var payload := {"version": 999, "state": state.to_dict()}
	_write_text(_slot_path(slot, ""), JSON.stringify(payload))
	var result: Dictionary = SaveStoreScript.load_slot(slot)
	t.truth(not result.get("ok", true), "version: unsupported version with no .bak is rejected")
	t.truth(result.has("error"), "version: rejection carries an error message")


func _test_required_subtrees_rejected(t, content: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)

	# An empty state object: player/country are REQUIRED, so this must fail.
	var empty_slot := SLOT_PREFIX + "empty-state"
	_wipe_slot(empty_slot)
	_write_text(_slot_path(empty_slot, ""), JSON.stringify({"version": 1, "state": {}}))
	var empty_result: Dictionary = SaveStoreScript.load_slot(empty_slot)
	t.truth(not empty_result.get("ok", true), "required: {'state':{}} is rejected (player/country required)")
	t.truth(empty_result.has("error"), "required: rejection carries an error message")

	# country:null on an otherwise valid state.
	var null_slot := SLOT_PREFIX + "null-country"
	_wipe_slot(null_slot)
	var null_state: GameState = _new_test_state(content)
	var null_dict: Dictionary = null_state.to_dict()
	null_dict["country"] = null
	_write_text(_slot_path(null_slot, ""), JSON.stringify({"version": 1, "state": null_dict}))
	var null_result: Dictionary = SaveStoreScript.load_slot(null_slot)
	t.truth(not null_result.get("ok", true), "required: country:null is rejected")
	t.truth(null_result.has("error"), "required: country:null rejection carries an error message")

	# A present-but-wrongly-typed container must reject, not load empty.
	var type_slot := SLOT_PREFIX + "world-type"
	_wipe_slot(type_slot)
	var type_state: GameState = _new_test_state(content)
	var type_dict: Dictionary = type_state.to_dict()
	type_dict["world"] = {}
	_write_text(_slot_path(type_slot, ""), JSON.stringify({"version": 1, "state": type_dict}))
	var type_result: Dictionary = SaveStoreScript.load_slot(type_slot)
	t.truth(not type_result.get("ok", true), "required: 'world':{} is rejected (wrong container type)")
	t.truth(type_result.has("error"), "required: wrong-type rejection carries an error message")

	# A save without the rng key is corruption, not an old schema: every
	# writer includes it, so loading must fail rather than fork a seed-0
	# stream.
	var rng_slot := SLOT_PREFIX + "no-rng"
	_wipe_slot(rng_slot)
	var rng_state: GameState = _new_test_state(content)
	var rng_dict: Dictionary = rng_state.to_dict()
	rng_dict.erase("rng")
	_write_text(_slot_path(rng_slot, ""), JSON.stringify({"version": 1, "state": rng_dict}))
	var rng_result: Dictionary = SaveStoreScript.load_slot(rng_slot)
	t.truth(not rng_result.get("ok", true), "required: rng-key-stripped save is rejected")
	t.truth(rng_result.has("error"), "required: missing-rng rejection carries an error message")


func _test_missing_main_recovers_bak(t, content: Dictionary) -> void:
	var slot := SLOT_PREFIX + "missing-main"
	_wipe_slot(slot)

	var empty: Dictionary = SaveStoreScript.load_slot(slot)
	t.truth(not empty.get("ok", true), "missing: empty slot is rejected")
	t.truth(str(empty.get("error", "")).contains("no save found"),
		"missing: empty slot still reports 'no save found'")

	# Revision A, then revision B (which archives A as .bak).
	var state_a: GameState = _new_test_state(content)
	state_a.turn = 2
	t.truth(SaveStoreScript.save_slot(slot, state_a).get("ok", false),
		"missing: revision A saves")
	var state_b: GameState = _new_test_state(content)
	state_b.turn = 7
	t.truth(SaveStoreScript.save_slot(slot, state_b).get("ok", false),
		"missing: revision B saves (A archived as .bak)")

	# Crash between the two publish renames: the live path is absent while
	# the previous revision waits in .bak.
	DirAccess.remove_absolute(_slot_path(slot, ""))
	t.truth(not FileAccess.file_exists(_slot_path(slot, "")),
		"missing: precondition holds (main deleted)")
	t.truth(FileAccess.file_exists(_slot_path(slot, ".bak")),
		"missing: precondition holds (.bak survives)")
	var recovered: Dictionary = SaveStoreScript.load_slot(slot)
	t.truth(recovered.get("ok", false), "missing: load recovers the .bak revision when main is absent")
	if recovered.get("ok", false):
		var recovered_state: GameState = recovered.get("state")
		t.equal(recovered_state.turn, 2, "missing: .bak recovery restores revision A (turn 2)")


func _test_dual_corruption_rejected(t) -> void:
	var slot := SLOT_PREFIX + "dual-corrupt"
	_wipe_slot(slot)
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)
	_write_text(_slot_path(slot, ""), "{{{ main is garbage")
	_write_text(_slot_path(slot, ".bak"), "{{{ bak is garbage")
	var result: Dictionary = SaveStoreScript.load_slot(slot)
	t.truth(not result.get("ok", true), "dual: main + .bak both corrupt is rejected")
	var message := str(result.get("error", ""))
	t.truth(message.contains("main:"), "dual: rejection cites the main reason")
	t.truth(message.contains(".bak:"), "dual: rejection cites the .bak reason too")


func _test_validator_date_ranges(t, content: Dictionary) -> void:
	var base: GameState = _new_test_state(content)
	t.equal(StateValidatorScript.validate(base).size(), 0,
		"dates: factory state validates (precondition)")

	var bad_month: GameState = _new_test_state(content)
	bad_month.month = 13
	t.truth(StateValidatorScript.validate(bad_month).size() > 0,
		"dates: validator flags month=13")

	var bad_day: GameState = _new_test_state(content)
	bad_day.day = 0
	t.truth(StateValidatorScript.validate(bad_day).size() > 0,
		"dates: validator flags day=0")

	var bad_index: GameState = _new_test_state(content)
	bad_index.day_index = -1
	t.truth(StateValidatorScript.validate(bad_index).size() > 0,
		"dates: validator flags a negative day_index")

	var bad_turn: GameState = _new_test_state(content)
	bad_turn.turn = -1
	t.truth(StateValidatorScript.validate(bad_turn).size() > 0,
		"dates: validator flags a negative turn")

	# Full save→load→validate chain: SaveStore itself does not validate, so
	# the load succeeds and the chain rejection lands at the validate step
	# (the same step NativeGame.load enforces).
	var slot := SLOT_PREFIX + "bad-date"
	_wipe_slot(slot)
	var chained: GameState = _new_test_state(content)
	chained.month = 13
	t.truth(SaveStoreScript.save_slot(slot, chained).get("ok", false),
		"dates: out-of-range-date state still saves")
	var loaded: Dictionary = SaveStoreScript.load_slot(slot)
	t.truth(loaded.get("ok", false),
		"dates: out-of-range-date save still loads (SaveStore does not validate)")
	if loaded.get("ok", false):
		var errors := StateValidatorScript.validate(loaded.get("state"))
		t.truth(errors.size() > 0,
			"dates: save→load→validate chain rejects month=13 (%s)" % [errors])


func _test_validator_minister_and_ranges(t, content: Dictionary) -> void:
	var base: GameState = _new_test_state(content)
	t.truth(base.ministers.size() > 0, "ranges: factory cabinet is non-empty (precondition)")

	var bad_loyalty: GameState = _new_test_state(content)
	bad_loyalty.ministers[0].loyalty = 999.0
	t.truth(StateValidatorScript.validate(bad_loyalty).size() > 0,
		"ranges: validator flags minister loyalty 999")

	var bad_trait: GameState = _new_test_state(content)
	bad_trait.ministers[0].trait_id = "archmage"
	t.truth(StateValidatorScript.validate(bad_trait).size() > 0,
		"ranges: validator flags an unknown minister trait")

	var bad_risk: GameState = _new_test_state(content)
	bad_risk.civil_war_risk = 1.5
	t.truth(StateValidatorScript.validate(bad_risk).size() > 0,
		"ranges: validator flags civil_war_risk outside 0..1")

	var bad_rel: GameState = _new_test_state(content)
	var rel_keys: Array = bad_rel.country.relations.keys()
	t.truth(rel_keys.size() > 0, "ranges: factory state wires relations (precondition)")
	if rel_keys.size() > 0:
		bad_rel.country.relations[rel_keys[0]].score = 5.0
		t.truth(StateValidatorScript.validate(bad_rel).size() > 0,
			"ranges: validator flags a relation score outside -1..1")


func _test_slot_regex_rejected(t, content: Dictionary) -> void:
	var state: GameState = _new_test_state(content)
	var evil_49: String = SLOT_PREFIX + "x".repeat(42)
	t.equal(evil_49.length(), 49, "regex: overlong fixture name is really 49 chars")
	var bad_slots := ["../evil", "..", "UPPER", "has space", "", evil_49,
		"semi;colon", "dot.name", "/absolute", "back\\slash", "wild*card"]
	for slot in bad_slots:
		var saved: Dictionary = SaveStoreScript.save_slot(slot, state)
		t.truth(not saved.get("ok", true), "regex: save_slot rejects '%s'" % slot)
		var loaded: Dictionary = SaveStoreScript.load_slot(slot)
		t.truth(not loaded.get("ok", true), "regex: load_slot rejects '%s'" % slot)
	t.truth(not FileAccess.file_exists("user://evil.json"),
		"regex: traversal attempt wrote nothing outside the saves dir")
	t.truth(SaveStoreScript.is_valid_slot(SLOT_PREFIX + "ok_1-2"),
		"regex: a normal slot name is accepted")
	t.truth(SaveStoreScript.is_valid_slot(SLOT_PREFIX + "x".repeat(41)),
		"regex: a 48-char slot name is accepted")


func _test_interrupted_write_survival(t, content: Dictionary) -> void:
	var slot := SLOT_PREFIX + "interrupted"
	_wipe_slot(slot)

	# Revision A, then revision B (which archives A as .bak).
	var state_a: GameState = _new_test_state(content)
	t.truth(SaveStoreScript.save_slot(slot, state_a).get("ok", false),
		"interrupted: revision A saves")
	var state_b: GameState = _new_test_state(content)
	state_b.turn = 7
	state_b.year = 1995
	t.truth(SaveStoreScript.save_slot(slot, state_b).get("ok", false),
		"interrupted: revision B saves (A archived as .bak)")
	t.truth(FileAccess.file_exists(_slot_path(slot, ".bak")),
		"interrupted: precondition holds (.bak exists after second save)")

	# Case 1: a leftover .tmp from a crashed write must be ignored.
	_write_text(_slot_path(slot, ".tmp"), "{{{ partial write")
	var recovered: Dictionary = SaveStoreScript.load_slot(slot)
	t.truth(recovered.get("ok", false), "interrupted: load succeeds despite a leftover .tmp")
	if recovered.get("ok", false):
		var recovered_state: GameState = recovered.get("state")
		t.equal(recovered_state.turn, 7, "interrupted: .tmp ignored, main revision B loads")

	# Case 2: a corrupt main file falls back to the .bak revision.
	_write_text(_slot_path(slot, ""), "garbage{{{")
	DirAccess.remove_absolute(_slot_path(slot, ".tmp"))
	var fallback: Dictionary = SaveStoreScript.load_slot(slot)
	t.truth(fallback.get("ok", false), "interrupted: load recovers from .bak when main is corrupt")
	if fallback.get("ok", false):
		var fallback_state: GameState = fallback.get("state")
		t.equal(fallback_state.turn, state_a.turn,
			"interrupted: .bak recovery restores revision A (turn %d)" % state_a.turn)

	# Case 3: a version-mismatched main file falls back to the .bak revision.
	var mismatch := {"version": 999, "state": state_b.to_dict()}
	_write_text(_slot_path(slot, ""), JSON.stringify(mismatch))
	var versioned: Dictionary = SaveStoreScript.load_slot(slot)
	t.truth(versioned.get("ok", false), "interrupted: load recovers from .bak when main has an unsupported version")
	if versioned.get("ok", false):
		var versioned_state: GameState = versioned.get("state")
		t.equal(versioned_state.turn, state_a.turn,
			"interrupted: version fallback restores revision A (turn %d)" % state_a.turn)


func _test_task10_digest_and_household_boundary(t, content: Dictionary) -> void:
	var state: GameState = _new_test_state(content)
	t.truth(state != null, "task10: factory builds a campaign state")
	if state == null:
		return
	state.monthly_digest = ["A completed monthly report."]
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var restored := GameState.from_dict(saved)
	t.truth(restored != null, "task10: digest roundtrip parses")
	if restored != null:
		t.equal(restored.monthly_digest, state.monthly_digest, "task10: completed digest roundtrips exactly")
	var legacy: Dictionary = state.to_dict()
	legacy.erase("monthly_digest")
	var old_save := GameState.from_dict(legacy)
	t.truth(old_save != null, "task10: old save without digest still loads")
	if old_save != null:
		t.equal(old_save.monthly_digest, [], "task10: missing digest defaults empty")
	var bad_digest: Dictionary = state.to_dict()
	bad_digest["monthly_digest"] = [42]
	t.equal(GameState.from_dict(bad_digest), null, "task10: non-string digest entry is rejected")
	var bad_digest_container: Dictionary = state.to_dict()
	bad_digest_container["monthly_digest"] = {}
	t.equal(GameState.from_dict(bad_digest_container), null, "task10: non-array digest is rejected")
	var malformed_household: Dictionary = state.to_dict()
	malformed_household["households"] = {"bad": {}}
	t.equal(GameState.from_dict(malformed_household), null, "task10: present malformed household record is rejected")
	var wrong_type_household: Dictionary = state.to_dict()
	wrong_type_household["households"] = {"bad": null}
	t.equal(GameState.from_dict(wrong_type_household), null, "task10: present null household entry is rejected")
	var h := HouseholdGroupState.new()
	h.id = "test:group"
	h.group_id = "group"
	h.region_id = "test"
	h.population_share = 1.0
	h.hardship = INF
	state.households[h.id] = h
	var errors := StateValidatorScript.validate(state)
	t.truth(not errors.is_empty(), "task10: validator rejects non-finite in-memory household data")

func _initialize() -> void:
	var t = TestSupportScript.new()

	var content: Dictionary = ContentRepositoryScript.load_all()
	t.truth(not content.has("error"), "content loads for the persistence tests")

	if not content.has("error"):
		_test_round_trip(t, content)
		_test_corrupt_json_rejected(t)
		_test_unsupported_version_rejected(t, content)
		_test_slot_regex_rejected(t, content)
		_test_interrupted_write_survival(t, content)
		_test_required_subtrees_rejected(t, content)
		_test_missing_main_recovers_bak(t, content)
		_test_dual_corruption_rejected(t)
		_test_validator_date_ranges(t, content)
		_test_validator_minister_and_ranges(t, content)
		_test_task10_digest_and_household_boundary(t, content)

	for slot in [SLOT_PREFIX + "roundtrip", SLOT_PREFIX + "corrupt",
			SLOT_PREFIX + "badversion", SLOT_PREFIX + "interrupted",
			SLOT_PREFIX + "empty-state", SLOT_PREFIX + "null-country",
			SLOT_PREFIX + "world-type", SLOT_PREFIX + "no-rng",
			SLOT_PREFIX + "missing-main", SLOT_PREFIX + "dual-corrupt",
			SLOT_PREFIX + "bad-date"]:
		_wipe_slot(slot)
	var residue := false
	for slot in [SLOT_PREFIX + "roundtrip", SLOT_PREFIX + "corrupt",
			SLOT_PREFIX + "badversion", SLOT_PREFIX + "interrupted",
			SLOT_PREFIX + "empty-state", SLOT_PREFIX + "null-country",
			SLOT_PREFIX + "world-type", SLOT_PREFIX + "no-rng",
			SLOT_PREFIX + "missing-main", SLOT_PREFIX + "dual-corrupt",
			SLOT_PREFIX + "bad-date"]:
		for suffix in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(_slot_path(slot, suffix)):
				residue = true
	t.truth(not residue, "cleanup: no test slot residue remains in user://saves/")

	quit(t.finish())
