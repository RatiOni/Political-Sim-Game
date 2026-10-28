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


func _check_levels() -> void:
	t.equal(ArdeniaMap.choose_level(Vector2(2688, 1600)), Vector2i(8, 2), "a huge panel takes 8 px tiles at 2x")
	t.equal(ArdeniaMap.choose_level(Vector2(1344, 800)), Vector2i(8, 1), "an exact native panel takes 8 px tiles at 1x")
	t.equal(ArdeniaMap.choose_level(Vector2(1344, 799)), Vector2i(4, 1), "a panel just short of native drops to 4 px tiles")
	t.equal(ArdeniaMap.choose_level(Vector2(1251, 535)), Vector2i(4, 1), "the 1920 x 1080 panel takes 4 px tiles at 1x")
	t.equal(ArdeniaMap.choose_level(Vector2(1400, 799)), Vector2i(4, 1), "a wide but short panel takes 4 px tiles at 1x")
	t.equal(ArdeniaMap.choose_level(Vector2(883, 311)), Vector2i(4, 1), "a panel smaller than every level falls back to 4 px at 1x")


func _drag(map: Control, from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = map.global_position + from
	root.push_input(press)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = map.global_position + to
	motion.relative = to - from
	root.push_input(motion)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	release.position = map.global_position + to
	root.push_input(release)


func _check_pan(map: Control, capital: Vector2) -> void:
	var selected: String = map.selected_id
	var before: Vector2 = map.map_to_local(capital)
	var centre := map.size / 2.0
	_drag(map, centre, centre + Vector2(0, 60))
	await _frames(2)
	_drag(map, centre, centre + Vector2(0, -40))
	await _frames(2)
	var after: Vector2 = map.map_to_local(capital)
	t.truth(after.y != before.y and after.x == before.x, "dragging pans the tall map vertically only")
	t.equal(map.region_at(after), "vashtera", "the capital hit-tests after a pan")
	t.equal(map.selected_id, selected, "a drag does not select a region")
	t.truth(map.local_to_map(map.map_to_local(Vector2(0.4, 0.6))).distance_to(Vector2(0.4, 0.6)) < 1e-4, "map and local coordinates invert after a pan")
	_drag(map, centre, centre + Vector2(0, 5000))
	await _frames(2)
	t.equal(map.map_to_local(Vector2.ZERO).y, 0.0, "panning is clamped at the top edge")
	var ring: PackedVector2Array = map.polygons["vashtera"]
	t.truth(Geometry2D.is_point_in_polygon(map.map_to_local(capital), ring), "polygons follow the pan")
	map.select_region("karsen")
	var north: float = map.map_to_local(Vector2.ZERO).y
	map.select_region("kelvet")
	var south: float = map.map_to_local(Vector2.ZERO).y
	t.truth(south < north, "selecting a southern region pans the map up")
	t.truth(Rect2(Vector2.ZERO, map.size).has_point(map.map_to_local(Vector2(0.23, 0.82))), "the selected region is in view")


func _run() -> void:
	_check_levels()
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
	t.equal(Vector2i(map.tile_px, map.zoom), Vector2i(4, 1), "the compact panel uses 4 px tiles at 1x")
	t.truth(map.canvas_extent().y > map.size.y, "the compact map is taller than its panel and pans")
	await _check_pan(map, capital)
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
