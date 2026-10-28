extends SceneTree


const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")

const EXPECTED_COUNTRY_IDS := [
	"ardenia", "krasova", "merova", "nueva_costa", "qadir",
	"solheim", "terand", "valmora", "veldoria",
]

const EXPECTED_ARDENIA_BLOC_IDS := [
	"ag_grange", "ag_leftout",
	"ld_bar", "ld_circle", "ld_return",
	"nc_line", "nc_parish", "nc_square",
	"sd_reform", "sd_works",
	"wf_nostalgics", "wf_shopfloor",
]


static func _is_empty(data) -> bool:
	if data is Array:
		return data.is_empty()
	if data is Dictionary:
		return data.is_empty()
	return data == null


func _write_test_file(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()


func _test_duplicate_rejection(t) -> void:
	var root := "user://content_repository_dup_test/"
	_write_test_file(root.path_join("catalog_manifest.json"),
		'{"schema_version": 1, "files": ["catalogs/dup.json"]}')
	_write_test_file(root.path_join("catalogs/dup.json"),
		'[{"id": "a", "name": "one"}, {"id": "a", "name": "two"}]')

	var result: Dictionary = ContentRepositoryScript.load_all(root)
	t.truth(result.has("error"), "duplicate id within a catalog is rejected")

	DirAccess.remove_absolute(root.path_join("catalog_manifest.json"))
	DirAccess.remove_absolute(root.path_join("catalogs/dup.json"))
	DirAccess.remove_absolute(root.path_join("catalogs"))
	DirAccess.remove_absolute(root)


func _test_missing_file_rejection(t) -> void:
	var root := "user://content_repository_missing_test/"
	_write_test_file(root.path_join("catalog_manifest.json"),
		'{"schema_version": 1, "files": ["catalogs/does_not_exist.json"]}')

	var result: Dictionary = ContentRepositoryScript.load_all(root)
	t.truth(result.has("error"), "a manifest entry with no file on disk is rejected, not silently skipped")

	DirAccess.remove_absolute(root.path_join("catalog_manifest.json"))
	DirAccess.remove_absolute(root)


func _initialize() -> void:
	var t = TestSupportScript.new()

	var repo: Dictionary = ContentRepositoryScript.load_all()
	t.truth(not repo.has("error"), "load_all() succeeds against the real exported content")

	if not repo.has("error"):
		var countries: Dictionary = repo.get("countries", {})
		var country_ids: Array = countries.keys()
		country_ids.sort()
		t.equal(country_ids, EXPECTED_COUNTRY_IDS, "all nine countries are present")

		for country_id in EXPECTED_COUNTRY_IDS:
			var country: Dictionary = countries.get(country_id, {})
			var factions: Array = country.get("factions", [])
			t.truth(not factions.is_empty(), "%s has at least one faction" % country_id)

		var ardenia: Dictionary = countries.get("ardenia", {})
		var bloc_ids: Array = []
		for faction in ardenia.get("factions", []):
			for wing in faction.get("wings", []):
				t.equal(wing.get("kind"), "bloc", "%s wing %s is a bloc" % [faction.get("id"), wing.get("id")])
				bloc_ids.append(wing.get("id"))
		bloc_ids.sort()
		t.equal(bloc_ids, EXPECTED_ARDENIA_BLOC_IDS, "all twelve Ardenian blocs load, one per faction's wings")

		var manifest: Dictionary = repo.get("manifest", {})
		for rel_path in manifest.get("files", []):
			var parts: PackedStringArray = String(rel_path).split("/")
			var group: String = parts[0]
			var name: String = parts[1].get_basename()
			var bucket: Dictionary = repo.get(group, {})
			var data = bucket.get(name)
			t.truth(not _is_empty(data), "%s is non-empty" % rel_path)

	_test_duplicate_rejection(t)
	_test_missing_file_rejection(t)

	quit(t.finish())
