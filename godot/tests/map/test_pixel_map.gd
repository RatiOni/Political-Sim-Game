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
	t.equal(ArdeniaMap.level_zoom(1251, 4), 1, "a 1251 px panel shows the overview at 1x")
	t.equal(ArdeniaMap.level_zoom(1344, 4), 2, "a 1344 px panel shows the overview at 2x")
	t.equal(ArdeniaMap.level_zoom(1251, 8), 1, "detail never drops below 1x")
	t.equal(ArdeniaMap.level_zoom(2700, 8), 2, "a 2700 px panel shows detail at 2x")


func _wheel(map: Control, local: Vector2, up: bool) -> void:
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = map.global_position + local
	root.push_input(wheel)


func _key(keycode: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.pressed = true
	root.push_input(key)


func _check_zoom(map: Control) -> void:
	t.equal(map.tile_px, 4, "the 1920 x 1080 panel opens on the overview")
	var centre: Vector2 = map.size / 2.0
	var held: Vector2 = map.local_to_map(centre)
	_wheel(map, centre, true)
	await _frames(2)
	t.equal(map.tile_px, 8, "the wheel zooms in to 8 px detail")
	t.truth(map.local_to_map(centre).distance_to(held) < 1.0 / 168.0, "zooming keeps the point under the cursor in place")
	t.truth(map.canvas_extent().x > map.size.x, "the detail map overflows the panel and pans")
	_wheel(map, centre, false)
	await _frames(2)
	t.equal(map.tile_px, 4, "the wheel zooms back out to the overview")
	map.grab_focus()
	_key(KEY_EQUAL)
	await _frames(2)
	t.equal(map.tile_px, 8, "+ zooms in")
	t.truth(map.zoom_in_button.disabled and not map.zoom_out_button.disabled, "only zoom out is offered at detail")
	map.select_region("zavost")
	var zavost: Vector2 = map._centres["zavost"]
	var before: Vector2 = map.map_to_local(zavost)
	_key(KEY_MINUS)
	await _frames(2)
	t.equal(map.tile_px, 4, "- zooms out")
	t.truth(map.map_to_local(zavost).distance_to(before) < 8.0 or map.canvas_extent().x <= map.size.x, "zooming out keeps the selected region in place where the map can pan")
	map.zoom_in_button.pressed.emit()
	t.equal(map.tile_px, 8, "the zoom-in button zooms in")
	t.equal(map.region_at(map.map_to_local(zavost)), "zavost", "hit testing follows the zoom level")
	map.zoom_out_button.pressed.emit()
	t.equal(map.tile_px, 4, "the zoom-out button zooms out")
	for button in [map.zoom_in_button, map.zoom_out_button]:
		t.truth(button.size.y >= 44.0 and Rect2(Vector2.ZERO, map.size).encloses(Rect2(button.position, button.size)), "%s is a 44 px target inside the map" % button.name)


func _physical_tile(map: Control) -> Vector2:
	var screen: Transform2D = map.screen_transform()
	var a: Vector2 = screen * map.map_to_local(Vector2.ZERO)
	var b: Vector2 = screen * map.map_to_local(Vector2(1.0 / 168.0, 1.0 / 100.0))
	return b - a


func _is_whole(v: Vector2) -> bool:
	return absf(v.x - roundf(v.x)) < 1e-3 and absf(v.y - roundf(v.y)) < 1e-3


func _check_physical(map: Control, capital: Vector2) -> void:
	root.content_scale_factor = 2.0 / 3.0
	await _frames()
	var scale: float = map.screen_transform().get_scale().x
	t.near(scale, 2.0 / 3.0, 1e-4, "the window scales the map control by 2/3")
	var tile := _physical_tile(map)
	t.truth(_is_whole(tile) and tile.x == tile.y and tile.x >= 4.0, "a tile covers a whole number of physical pixels (%s)" % tile)
	t.truth(_is_whole(map.screen_transform() * map.map_to_local(Vector2.ZERO)), "the map origin lands on a physical pixel")
	t.equal(map.region_at(map.map_to_local(capital)), "vashtera", "the capital hit-tests under a 2/3 content scale")
	t.truth(map.local_to_map(map.map_to_local(Vector2(0.4, 0.6))).distance_to(Vector2(0.4, 0.6)) < 1e-4, "coordinates invert under a 2/3 content scale")
	map.zoom_in()
	await _frames()
	t.truth(_is_whole(_physical_tile(map)) and _physical_tile(map).x == 8.0 * map.zoom, "detail tiles are 8k physical pixels under a 2/3 content scale")
	t.equal(map.region_at(map.map_to_local(capital)), "vashtera", "the capital hit-tests at detail under a 2/3 content scale")
	map.zoom_out()
	root.content_scale_factor = 1.0
	await _frames()


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
	await _check_zoom(map)

	root.size = Vector2i(1280, 720)
	await _frames()
	var capital: Vector2 = geo.cities.filter(func(c: Dictionary) -> bool: return c["capital"])[0]["point"]
	t.equal(map.region_at(map.map_to_local(capital)), "vashtera", "the capital still hit-tests after a resize to 1280 x 720")
	t.equal(Vector2i(map.tile_px, map.zoom), Vector2i(4, 1), "the compact panel keeps the overview at 1x")
	t.truth(map.canvas_extent().y > map.size.y, "the compact map is taller than its panel and pans")
	await _check_pan(map, capital)
	await _check_physical(map, capital)
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
