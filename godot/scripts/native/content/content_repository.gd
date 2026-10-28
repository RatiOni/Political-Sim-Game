class_name ContentRepository
extends RefCounted


const DEFAULT_ROOT := "res://data/native/"


static func _fail(message: String) -> Dictionary:
	push_error("ContentRepository: %s" % message)
	return {"error": message}


static func _load_json_file(path: String):
	if not FileAccess.file_exists(path):
		return {"__error__": "missing file: %s" % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"__error__": "could not open file: %s" % path}
	var text := file.get_as_text()
	var parsed = JSON.parse_string(text)
	if parsed == null and text.strip_edges() != "null":
		return {"__error__": "malformed JSON in file: %s" % path}
	if not (parsed is Dictionary or parsed is Array):
		return {"__error__": "malformed JSON in file: %s" % path}
	return parsed


static func _find_duplicate_id(value, context: String) -> String:
	if value is Array:
		var seen := {}
		for item in value:
			if item is Dictionary and item.has("id"):
				var item_id = item["id"]
				if seen.has(item_id):
					return "duplicate id '%s' in %s" % [str(item_id), context]
				seen[item_id] = true
			var nested := _find_duplicate_id(item, context)
			if nested != "":
				return nested
	elif value is Dictionary:
		for key in value.keys():
			var nested := _find_duplicate_id(value[key], "%s.%s" % [context, str(key)])
			if nested != "":
				return nested
	return ""


static var _shipped_cache: Dictionary = {}


static func load_all(root: String = DEFAULT_ROOT) -> Dictionary:
	if root == DEFAULT_ROOT:
		if _shipped_cache.is_empty():
			var loaded := _load_uncached(root)
			if loaded.has("error"):
				return loaded
			_freeze(loaded)
			_shipped_cache = loaded
		return _shipped_cache
	return _load_uncached(root)


static func _freeze(value) -> void:
	if value is Dictionary:
		for v in value.values():
			_freeze(v)
		(value as Dictionary).make_read_only()
	elif value is Array:
		for v in value:
			_freeze(v)
		(value as Array).make_read_only()


static func _load_uncached(root: String) -> Dictionary:
	var manifest_path := root.path_join("catalog_manifest.json")
	var manifest = _load_json_file(manifest_path)
	if manifest is Dictionary and manifest.has("__error__"):
		return _fail(manifest["__error__"])
	if not (manifest is Dictionary) or not manifest.has("files"):
		return _fail("catalog_manifest.json is missing its 'files' list")

	var countries := {}
	var catalogs := {}
	var lore := {}

	for rel_path in manifest["files"]:
		var full_path: String = root.path_join(rel_path)
		var data = _load_json_file(full_path)
		if data is Dictionary and data.has("__error__"):
			return _fail(data["__error__"])

		var dup := _find_duplicate_id(data, rel_path)
		if dup != "":
			return _fail(dup)

		var parts: PackedStringArray = rel_path.split("/")
		if parts.size() != 2:
			return _fail("unexpected manifest path shape: %s" % rel_path)
		var group: String = parts[0]
		var name: String = parts[1].get_basename()

		match group:
			"countries":
				if not (data is Dictionary):
					return _fail("country file '%s' does not contain a JSON object" % rel_path)
				var country_dict: Dictionary = data
				var inner_id: Variant = country_dict.get("id", null)
				if not (inner_id is String):
					return _fail("country file '%s' has a missing or non-string inner id" % rel_path)
				var inner_str := String(inner_id)
				for existing_key in countries.keys():
					var existing: Dictionary = countries[existing_key]
					if String(existing.get("id", "")) == inner_str:
						return _fail("duplicate country id '%s' (from %s)" % [inner_str, rel_path])
				if inner_str != name:
					return _fail("country file '%s' inner id '%s' does not match filename stem '%s'" % [rel_path, inner_str, name])
				if countries.has(name):
					return _fail("duplicate country id '%s' (from %s)" % [name, rel_path])
				countries[name] = data
			"catalogs":
				catalogs[name] = data
			"lore":
				lore[name] = data
			_:
				return _fail("unknown catalog group '%s' for %s" % [group, rel_path])

	return {
		"countries": countries,
		"catalogs": catalogs,
		"lore": lore,
		"manifest": manifest,
	}
