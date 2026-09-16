extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const FIXTURE_DIRECTORY = "res://data/native/fixtures/"

func _load_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	return JSON.parse_string(file.get_as_text())

func _initialize() -> void:
	var t = TestSupportScript.new()
	t.equal("Ardenia", "Ardenia", "equal compares exact values")
	t.near(1.0, 1.001, 0.01, "near accepts values within tolerance")
	t.truth(true, "truth accepts true")

	var manifest = _load_json(FIXTURE_DIRECTORY + "manifest.json")
	t.truth(manifest is Dictionary, "fixture manifest parses")
	if manifest is Dictionary:
		var fixtures: Dictionary = manifest.get("fixtures", {})
		var fixture_ids: Array = fixtures.keys()
		fixture_ids.sort()
		var roles: Array = []
		for fixture_id in fixture_ids:
			var specification: Dictionary = fixtures[fixture_id]
			var fixture = _load_json(FIXTURE_DIRECTORY + specification.get("file", ""))
			t.truth(fixture is Dictionary, "%s parses" % fixture_id)
			if fixture is Dictionary:
				var player: Dictionary = fixture.get("player", {})
				var expected_role: bool = specification.get("player_in_government", false)
				t.equal(player.get("in_government"), expected_role,
					"%s preserves in_government" % fixture_id)
				t.equal(fixture.get("campaign_meta", {}).get("seed"), 424242,
					"%s preserves seed" % fixture_id)
				for state_key in specification.get("state_keys", []):
					t.truth(fixture.has(state_key),
						"%s contains state key %s" % [fixture_id, state_key])
				roles.append(expected_role)
		t.truth(roles.has(true) and roles.has(false),
			"fixtures cover government and opposition")
	quit(t.finish())
