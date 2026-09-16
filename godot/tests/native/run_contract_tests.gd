extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const FIXTURE_DIRECTORY = "res://data/native/fixtures/"
const EXPECTED_FIXTURE_IDS := [
	"campaign_government_seed_424242",
	"campaign_opposition_seed_424242",
]
const EXPECTED_FIXTURE_ROLES := {
	"campaign_government_seed_424242": {
		"opening_role": "government",
		"in_government": true,
	},
	"campaign_opposition_seed_424242": {
		"opening_role": "opposition",
		"in_government": false,
	},
}

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
		t.equal(fixture_ids, EXPECTED_FIXTURE_IDS, "fixture ids are the frozen known set")
		var roles: Array = []
		for fixture_id in fixture_ids:
			var specification: Dictionary = fixtures[fixture_id]
			var expected: Dictionary = EXPECTED_FIXTURE_ROLES.get(fixture_id, {})
			var opening_role: String = specification.get("opening_role", "")
			var expected_opening_role: String = expected.get("opening_role", "")
			var expected_in_government: bool = expected.get("in_government", false)
			t.equal(opening_role, expected_opening_role,
				"%s names its opening role" % fixture_id)
			var fixture = _load_json(FIXTURE_DIRECTORY + specification.get("file", ""))
			t.truth(fixture is Dictionary, "%s parses" % fixture_id)
			if fixture is Dictionary:
				var player: Dictionary = fixture.get("player", {})
				t.equal(specification.get("player_in_government"), expected_in_government,
					"%s manifest role matches known fixture" % fixture_id)
				t.equal(player.get("in_government"), expected_in_government,
					"%s preserves in_government" % fixture_id)
				t.equal(fixture.get("campaign_meta", {}).get("seed"), 424242,
					"%s preserves seed" % fixture_id)
				for state_key in specification.get("state_keys", []):
					t.truth(fixture.has(state_key),
						"%s contains state key %s" % [fixture_id, state_key])
				roles.append(expected_in_government)
		t.equal(roles, [true, false], "fixtures cover government and opposition")
	quit(t.finish())
