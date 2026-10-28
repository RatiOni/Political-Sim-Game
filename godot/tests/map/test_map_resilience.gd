extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const MAP_SCENE := "res://scenes/map/ardenia_map.tscn"
const MONTHS := 24
const MAX_CELLS_PER_MONTH := 600
const WATCHDOG_SECONDS := 150.0

var t = TestSupportScript.new()


func _initialize() -> void:
	create_timer(WATCHDOG_SECONDS).timeout.connect(func() -> void:
		push_error("map resilience test exceeded %d seconds" % int(WATCHDOG_SECONDS))
		quit(1))
	_run.call_deferred()


func _frames(count: int = 2) -> void:
	for _i in range(count):
		await process_frame


func _rows(geo: MapGeometry, month: int) -> Array:
	var rows: Array = []
	for id in geo.region_ids:
		rows.append({
			"id": id,
			"population": 150.0 + month * 12.0,
			"development": 0.2 + month * 0.03,
			"pressure": 0.3 + 0.015 * month + 0.05 * (month % 3),
			"control": "full",
			"insurgency": 0.0,
			"civil_war": month >= 18,
		})
	return rows


func _fresh_map() -> ArdeniaMap:
	var map := (load(MAP_SCENE) as PackedScene).instantiate() as ArdeniaMap
	map.size = Vector2(1500, 900)
	root.add_child(map)
	return map


func _growth_cells(map: ArdeniaMap) -> Dictionary:
	var out := {}
	for cell in map.growth_layer.get_used_cells():
		out[cell] = map.growth_layer.get_cell_atlas_coords(cell)
	return out


func _check_unknown_ids(map: ArdeniaMap, geo: MapGeometry) -> void:
	var rows := _rows(geo, 6)
	rows.append({"id": "atlantis", "population": 900.0, "development": 0.9, "pressure": 0.9, "control": "full"})
	rows.append({"id": "", "population": 1.0})
	map.apply_snapshot(_rows(geo, 6), "vashtera")
	var reference := _growth_cells(map)
	map.apply_snapshot(rows, "atlantis")
	await _frames()
	t.truth(not map.unavailable, "an unknown region id does not break the map")
	t.truth(not map.regions.has("atlantis"), "an unknown region id is not kept")
	t.equal(map.regions.size(), geo.region_ids.size(), "every known region still applies")
	t.equal(map.selected_id, "", "an unknown selection id is dropped")
	t.equal(_growth_cells(map), reference, "unknown rows leave the growth layer as the known rows alone paint it")
	var warned := map.unknown_warnings
	map.apply_snapshot(rows, "")
	map.apply_snapshot(rows, "")
	t.equal(map.unknown_warnings, warned, "each unknown region id is warned about once")
	t.equal(warned, 2, "both unknown ids were warned about")


func _check_budget(geo: MapGeometry) -> void:
	var map := _fresh_map()
	await _frames()
	map.apply_snapshot(_rows(geo, 0), "vashtera")
	var worst := 0
	var total := 0
	for month in range(1, MONTHS + 1):
		map.apply_snapshot(_rows(geo, month), "vashtera")
		worst = maxi(worst, map.last_changed_cells)
		total += map.last_changed_cells
		await create_timer(GrowthPainter.FLIP_SECONDS + 0.1).timeout
	print("worst month: %d cells, mean %d" % [worst, total / MONTHS])
	t.truth(worst <= MAX_CELLS_PER_MONTH, "no month flips more than %d growth cells (worst %d)" % [MAX_CELLS_PER_MONTH, worst])
	t.truth(worst > 0, "growth does flip cells over 24 months")
	map.apply_snapshot(_rows(geo, MONTHS), "vashtera")
	t.equal(map.last_changed_cells, 0, "an identical snapshot flips nothing")
	map.queue_free()


func _check_no_rebuilds(map: ArdeniaMap, geo: MapGeometry) -> void:
	map.apply_snapshot(_rows(geo, 12), "vashtera")
	map.set_dusk(false)
	await _frames()
	var builds := map.lines_builds
	var texture := map.lines_rect.texture
	for _i in range(30):
		map.queue_redraw()
		map._redraw()
		await process_frame
	t.equal(map.lines_builds, builds, "redrawing never rebuilds the line image")
	map.apply_snapshot(_rows(geo, 12), "karsen")
	map.apply_snapshot(_rows(geo, 12), "kelvet")
	map.hovered_id = "zavost"
	map._redraw()
	t.equal(map.lines_builds, builds, "changing selection or hover does not rebuild the line image")
	t.equal(map.lines_rect.texture, texture, "the line texture object is reused")
	map.set_dusk(true)
	var dusk_builds := map.lines_builds
	t.equal(dusk_builds, builds + 1, "dusk builds the line image once")
	map.set_dusk(false)
	map.set_dusk(true)
	map.set_dusk(false)
	t.equal(map.lines_builds, dusk_builds, "toggling back and forth reuses the cached line images")


func _run() -> void:
	var geo := MapGeometry.load_world()
	var map := _fresh_map()
	await _frames()
	t.truth(not map.unavailable, "the map loads")
	await _check_unknown_ids(map, geo)
	await _check_budget(geo)
	await _check_no_rebuilds(map, geo)
	map.queue_free()
	await _frames()
	quit(t.finish())
