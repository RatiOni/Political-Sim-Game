extends SceneTree

const GOVERNMENT_FIXTURE := "res://data/native/fixtures/campaign_government_seed_424242.json"


func _load_fixture() -> Dictionary:
	var source := FileAccess.open(GOVERNMENT_FIXTURE, FileAccess.READ)
	if source == null:
		push_error("Unable to open oracle fixture: %s" % GOVERNMENT_FIXTURE)
		return {}
	var parsed: Variant = JSON.parse_string(source.get_as_text())
	if not parsed is Dictionary:
		push_error("Oracle fixture is not a JSON object: %s" % GOVERNMENT_FIXTURE)
		return {}
	return parsed


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		push_error("Usage: emit_fixture_snapshot.gd -- <output-path>")
		quit(2)
		return
	var fixture := _load_fixture()
	if fixture.is_empty():
		quit(1)
		return
	var output := FileAccess.open(arguments[0], FileAccess.WRITE)
	if output == null:
		push_error("Unable to write native snapshot: %s" % arguments[0])
		quit(2)
		return
	output.store_string(JSON.stringify(fixture, "", true) + "\n")
	output.close()
	print("NATIVE SNAPSHOT", arguments[0])
	quit(0)
