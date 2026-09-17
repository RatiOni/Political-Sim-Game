class_name SaveStore
extends RefCounted

## Native-only campaign persistence: GameState <-> JSON files under
## user://saves/. No Python save compatibility (PLAN.md global constraint: no
## existing players).
##
## Atomic replace protocol: each save serializes to <slot>.json.tmp first;
## the previous live revision (if any) then moves aside to <slot>.json.bak,
## and only then does the .tmp take the .json name. A crash at any point
## leaves either the old or the new revision intact at the live path — never
## a half-written file. Loads never consult .tmp; a corrupt or
## version-mismatched main file falls back to .bak when it parses and its
## version matches.

const SAVE_FORMAT_VERSION := 1
const SAVES_DIR := "user://saves"
const SLOT_PATTERN := "^[a-z0-9_-]{1,48}$"

static var _slot_regex: RegEx = null


static func is_valid_slot(slot: String) -> bool:
	if _slot_regex == null:
		_slot_regex = RegEx.new()
		_slot_regex.compile(SLOT_PATTERN)
	return _slot_regex.search(slot) != null


static func save_slot(slot: String, state: GameState) -> Dictionary:
	# Reject, never sanitize-and-proceed: anything outside the charset could
	# be a path traversal attempt.
	if not is_valid_slot(slot):
		return {"ok": false, "error": "invalid slot name '%s' (must match %s)" % [slot, SLOT_PATTERN]}
	if state == null:
		return {"ok": false, "error": "cannot save a null GameState"}
	if DirAccess.make_dir_recursive_absolute(SAVES_DIR) != OK:
		return {"ok": false, "error": "could not create saves directory '%s'" % SAVES_DIR}
	var payload := {"version": SAVE_FORMAT_VERSION, "state": state.to_dict()}
	var main_path := _path_for(slot, "")
	var tmp_path := _path_for(slot, ".tmp")
	var bak_path := _path_for(slot, ".bak")
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "could not open '%s' for writing" % tmp_path}
	file.store_string(JSON.stringify(payload))
	file.flush()
	file.close()
	if FileAccess.file_exists(main_path):
		if DirAccess.rename_absolute(main_path, bak_path) != OK:
			DirAccess.remove_absolute(tmp_path)
			return {"ok": false, "error": "could not archive previous save to '%s'" % bak_path}
	if DirAccess.rename_absolute(tmp_path, main_path) != OK:
		return {"ok": false, "error": "could not publish save to '%s'" % main_path}
	return {"ok": true, "path": main_path}


static func load_slot(slot: String) -> Dictionary:
	if not is_valid_slot(slot):
		return {"ok": false, "error": "invalid slot name '%s' (must match %s)" % [slot, SLOT_PATTERN]}
	var main_path := _path_for(slot, "")
	if not FileAccess.file_exists(main_path):
		return {"ok": false, "error": "no save found in slot '%s'" % slot}
	var main_result := _load_file(main_path)
	if main_result.get("ok", false):
		return main_result
	var bak_path := _path_for(slot, ".bak")
	if FileAccess.file_exists(bak_path):
		var bak_result := _load_file(bak_path)
		if bak_result.get("ok", false):
			return bak_result
	return {"ok": false, "error": "save in slot '%s' is unreadable (main: %s)" %
		[slot, main_result.get("error", "unknown error")]}


static func _load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "could not open '%s'" % path}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {"ok": false, "error": "corrupt JSON in '%s'" % path}
	# Godot parses every JSON number as float, so version 1 arrives as 1.0 —
	# accept any whole-number form, reject anything else (never guess).
	if not _version_matches(parsed.get("version")):
		return {"ok": false, "error": "unsupported save version in '%s'" % path}
	var state_data: Variant = parsed.get("state")
	if not (state_data is Dictionary):
		return {"ok": false, "error": "missing 'state' object in '%s'" % path}
	var state := GameState.from_dict(state_data)
	if state == null:
		return {"ok": false, "error": "malformed campaign state in '%s'" % path}
	return {"ok": true, "state": state}


static func _version_matches(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return v == SAVE_FORMAT_VERSION
	if typeof(v) == TYPE_FLOAT and v == floorf(v):
		return int(v) == SAVE_FORMAT_VERSION
	return false


static func _path_for(slot: String, suffix: String) -> String:
	return "%s/%s.json%s" % [SAVES_DIR, slot, suffix]
