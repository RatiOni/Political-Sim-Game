extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const TEST_SLOT := "test_pixel_map"

var t = TestSupportScript.new()


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int = 3) -> void:
	for _i in range(count):
		await process_frame


func _wipe_slot() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := "user://saves/%s.json%s" % [TEST_SLOT, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _click(map: Control, local: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = map.global_position + local
	root.push_input(click)
	var release := click.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release)


func _run() -> void:
	_wipe_slot()
	root.size = Vector2i(1920, 1080)
	root.get_node("GameFlow").start_mode = "new"
	root.get_node("GameFlow").pending_seed = 424242
	var app: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	app.save_slot = TEST_SLOT
	root.add_child(app)
	await _frames()
	var map = app.find_child("ArdeniaMap", true, false)
	var geo := MapGeometry.load_world()

	t.truth(not map.unavailable, "the map data loads")
	t.equal(map.terrain_layer.get_used_cells().size(), 168 * 100, "the terrain layer fills the 168 x 100 grid")
	t.truth(map.growth_layer is TileMapLayer, "a growth layer exists for later tasks")
	for city in geo.cities:
		t.equal(map.region_at(map.map_to_local(city["point"])), city["region"], "%s hit-tests to %s" % [city["name"], city["region"]])
	t.equal(map.region_at(map.map_to_local(Vector2(0.02, 0.5))), "", "a sea point belongs to no region")
	t.truth(map.local_to_map(map.map_to_local(Vector2(0.3, 0.7))).distance_to(Vector2(0.3, 0.7)) < 1e-4, "map and local coordinates invert")
	t.equal(map.polygons.size(), 9, "nine region polygons come from the outlines")
	t.equal(map.terrain_layer.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "terrain tiles use nearest filtering")
	t.equal(map.lines_rect.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "the line overlay uses nearest filtering")

	var picked: Array[String] = []
	map.region_selected.connect(func(id: String) -> void: picked.append(id))
	var tavri: Vector2 = geo.cities.filter(func(c: Dictionary) -> bool: return c["name"] == "Tavri")[0]["point"]
	_click(map, map.map_to_local(tavri))
	await _frames(2)
	t.equal(picked, ["kelvet"] as Array[String], "a click on Tavri selects Kelvet")

	var day_texture: Texture2D = map.atlas_texture()
	map.set_dusk(true)
	t.truth(map.atlas_texture() != day_texture, "dusk swaps the atlas texture")
	map.set_dusk(false)
	t.equal(map.atlas_texture(), day_texture, "day restores the day atlas")

	root.size = Vector2i(1280, 720)
	await _frames()
	var capital: Vector2 = geo.cities.filter(func(c: Dictionary) -> bool: return c["capital"])[0]["point"]
	t.equal(map.region_at(map.map_to_local(capital)), "vashtera", "the capital still hit-tests after a resize to 1280 x 720")
	app.queue_free()
	await _frames()

	var broken = (load("res://scenes/map/ardenia_map.tscn") as PackedScene).instantiate()
	broken.tiles_path = "res://data/map/baked/missing_tiles.json"
	root.add_child(broken)
	await _frames()
	t.truth(broken.unavailable, "a missing tile file marks the map unavailable")
	var notice: Label = broken.find_child("Unavailable", true, false)
	t.truth(notice != null and notice.visible and notice.text == "Map data unavailable", "the map says its data is unavailable")
	t.equal(broken.region_at(Vector2(100, 100)), "", "an unavailable map hit-tests nothing")
	broken.queue_free()
	_wipe_slot()
	await _frames()
	quit(t.finish())
