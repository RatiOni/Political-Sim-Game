class_name SaveStore
extends RefCounted


const SAVE_FORMAT_VERSION := 1
const SAVES_DIR := "user://saves"
const SLOT_PATTERN := "^[a-z0-9_-]{1,48}$"
const AUTOSAVE_SLOT := "autosave"
const MANUAL_SLOTS: Array[String] = ["slot_1", "slot_2", "slot_3"]
## The single slot the game used before slots existed.
const LEGACY_SLOT := "godot_slice"

static var _slot_regex: RegEx = null


static func is_valid_slot(slot: String) -> bool:
	if _slot_regex == null:
		_slot_regex = RegEx.new()
		_slot_regex.compile(SLOT_PATTERN)
	return _slot_regex.search(slot) != null


static func save_slot(slot: String, state: GameState, meta: Dictionary = {}) -> Dictionary:
	if not is_valid_slot(slot):
		return {"ok": false, "error": "invalid slot name '%s' (must match %s)" % [slot, SLOT_PATTERN]}
	if state == null:
		return {"ok": false, "error": "cannot save a null GameState"}
	if DirAccess.make_dir_recursive_absolute(SAVES_DIR) != OK:
		return {"ok": false, "error": "could not create saves directory '%s'" % SAVES_DIR}
	var payload := {"version": SAVE_FORMAT_VERSION, "meta": meta, "state": state.to_dict()}
	var main_path := _path_for(slot, "")
	var tmp_path := _path_for(slot, ".tmp")
	var bak_path := _path_for(slot, ".bak")
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "could not open '%s' for writing" % tmp_path}
	file.store_var(payload)
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
	var bak_path := _path_for(slot, ".bak")
	if not FileAccess.file_exists(main_path):
		if FileAccess.file_exists(bak_path):
			var bak_only := _load_file(bak_path)
			if bak_only.get("ok", false):
				return bak_only
		return {"ok": false, "error": "no save found in slot '%s'" % slot}
	var main_result := _load_file(main_path)
	if main_result.get("ok", false):
		return main_result
	if FileAccess.file_exists(bak_path):
		var bak_result := _load_file(bak_path)
		if bak_result.get("ok", false):
			return bak_result
		return {"ok": false, "error": "save in slot '%s' is unreadable (main: %s; .bak: %s)" %
			[slot, main_result.get("error", "unknown error"), bak_result.get("error", "unknown error")]}
	return {"ok": false, "error": "save in slot '%s' is unreadable (main: %s)" %
		[slot, main_result.get("error", "unknown error")]}


static func _read_payload(path: String) -> Variant:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	if bytes[0] == 0x7B or bytes[0] == 0x20 or bytes[0] == 0x0A or bytes[0] == 0x0D or bytes[0] == 0x09:
		var json := JSON.new()
		if json.parse(bytes.get_string_from_utf8()) == OK:
			return json.data
	var file := FileAccess.open(path, FileAccess.READ)
	return null if file == null else file.get_var()


static func _load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "could not open '%s'" % path}
	var parsed: Variant = _read_payload(path)
	file.close()
	if not (parsed is Dictionary):
		return {"ok": false, "error": "corrupt save in '%s'" % path}
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


## The slots a player sees: autosave, the three manual slots, and the old
## single save if one is on disk.
static func player_slots() -> Array[String]:
	var slots: Array[String] = [AUTOSAVE_SLOT]
	slots.append_array(MANUAL_SLOTS)
	if FileAccess.file_exists(_path_for(LEGACY_SLOT, "")):
		slots.append(LEGACY_SLOT)
	return slots


static func slot_label(slot: String) -> String:
	if slot == AUTOSAVE_SLOT:
		return "Autosave"
	if slot == LEGACY_SLOT:
		return "Earlier save"
	if slot.begins_with("slot_"):
		return "Slot %s" % slot.trim_prefix("slot_")
	return slot.capitalize()


## What a slot holds, for a list: whose campaign, its date, when it was saved.
## A save written before labels existed reports empty strings, not an error.
static func slot_info(slot: String) -> Dictionary:
	var path := _path_for(slot, "")
	if not is_valid_slot(slot) or not FileAccess.file_exists(path):
		return {"slot": slot, "exists": false}
	var info := {"slot": slot, "exists": true, "saved_unix": FileAccess.get_modified_time(path),
		"date_text": "", "leader": ""}
	var parsed: Variant = _read_payload(path)
	if parsed is Dictionary and (parsed as Dictionary).get("meta") is Dictionary:
		var meta: Dictionary = parsed["meta"]
		info["date_text"] = String(meta.get("date_text", ""))
		info["leader"] = String(meta.get("leader", ""))
	return info


static func most_recent_slot(slots: Array[String]) -> String:
	var best := ""
	var best_time := -1
	for slot in slots:
		var info := slot_info(slot)
		if bool(info["exists"]) and int(info["saved_unix"]) > best_time:
			best = slot
			best_time = int(info["saved_unix"])
	return best
