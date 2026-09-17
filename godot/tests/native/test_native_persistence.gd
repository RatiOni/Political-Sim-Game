extends SceneTree

## Standalone headless test for Task 4 unit A: native persistence.
## Run via:
##   Godot --headless --path godot --script res://tests/native/test_native_persistence.gd
##
## Covers exactly the brief's cases: exact save/load round trip including RNG
## continuity, corrupt-JSON rejection, unsupported-version rejection, slot-regex
## rejection (traversal + overlong names), and interrupted-write survival via
## the .tmp-ignore / .bak-recovery protocol. Test states come from
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

	for slot in [SLOT_PREFIX + "roundtrip", SLOT_PREFIX + "corrupt",
			SLOT_PREFIX + "badversion", SLOT_PREFIX + "interrupted"]:
		_wipe_slot(slot)
	var residue := false
	for slot in [SLOT_PREFIX + "roundtrip", SLOT_PREFIX + "corrupt",
			SLOT_PREFIX + "badversion", SLOT_PREFIX + "interrupted"]:
		for suffix in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(_slot_path(slot, suffix)):
				residue = true
	t.truth(not residue, "cleanup: no test slot residue remains in user://saves/")

	quit(t.finish())
