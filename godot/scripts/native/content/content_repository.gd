class_name ContentRepository
extends RefCounted

## Loads the exported native content tree (godot/data/native/**) into one
## in-memory Dictionary, keyed by catalog. This is the JSON I/O boundary for
## Task 2's game systems — it does NOT build campaign/game state, it only
## exposes raw content by id.
##
## Layout of the returned Dictionary on success:
##   {
##     "countries": { "<country_id>": <country dict>, ... },   # 9 entries
##     "catalogs":  { "<catalog_name>": <catalog data>, ... },
##     "lore":      { "<lore_name>": <lore data>, ... },
##     "manifest":  <parsed catalog_manifest.json>,
##   }
##
## On any failure (missing file, malformed JSON, duplicate id within a
## catalog) the whole load is rejected — no partial data — and the return
## value is instead { "error": "<message>" }. The error is also pushed via
## push_error so it shows up in test/CI logs.

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


## Recursively scans loaded content for duplicate ids: any Array whose
## elements are Dictionaries with an "id" key must not repeat an id value
## within that same array. Scoped to each array independently, so option
## ids inside one event, faction ids inside one country, etc. are each
## their own namespace — exactly matching how the exporter and Task 2's
## consumers key things.
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


static func load_all(root: String = DEFAULT_ROOT) -> Dictionary:
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
