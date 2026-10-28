extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const WATER := ["deep_sea", "sea", "shallows"]
const BASE_POPULATION := 200.0
const BASE_DEVELOPMENT := 0.3

var t = TestSupportScript.new()


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int = 3) -> void:
	for _i in range(count):
		await process_frame


func _rows(geo: MapGeometry, population: float, development: float, pressure: float = 0.1) -> Array:
	var rows: Array = []
	for id in geo.region_ids:
		rows.append({"id": id, "population": population, "development": development, "pressure": pressure, "control": "full"})
	return rows


func _kind(tiles: Dictionary, cell: Vector2i) -> String:
	return TileArt.KINDS[tiles["kinds"][cell.y * TileBaker.GRID.x + cell.x]]


func _count_sprite(map: ArdeniaMap, sprite: String) -> int:
	var coords := Vector2i(TileArt.index()[sprite][0], TileArt.index()[sprite][1])
	var total := 0
	for cell in map.growth_layer.get_used_cells():
		if map.growth_layer.get_cell_atlas_coords(cell) == coords:
			total += 1
	return total


func _check_curves() -> void:
	var previous := 0
	for pop in [0.0, 10.0, 50.0, 100.0, 400.0, 1000.0, 5000.0, 100000.0]:
		var n := GrowthLayers.town_tiles(pop, false)
		t.truth(n >= previous and n <= 40, "town_tiles(%d) = %d is monotonic and bounded" % [pop, n])
		previous = n
	t.equal(GrowthLayers.town_tiles(50.0, false), 3, "50k people fill 3 tiles")
	t.equal(GrowthLayers.town_tiles(400.0, false), 12, "400k people fill 12 tiles")
	t.truth(absi(GrowthLayers.town_tiles(1000.0, true) - 30) <= 1, "the capital at 1,000k fills about 30 tiles")
	t.equal(GrowthLayers.town_tiles(1.0e9, true), 120, "the capital ceiling is 120")
	t.equal(GrowthLayers.town_tiles(1.0e9, false), 40, "the default ceiling is 40")
	t.truth(GrowthLayers.farm_share(0.9) >= GrowthLayers.farm_share(0.2), "development grows the farm share")
	t.near(GrowthLayers.farm_share(-1.0), 0.05, 1e-6, "farm share floors at 0.05")
	t.near(GrowthLayers.farm_share(5.0), 0.6, 1e-6, "farm share caps at 0.6")
	t.truth(GrowthLayers.farm_reach(0.9) > GrowthLayers.farm_reach(0.2), "development widens the fields")
	t.truth(GrowthLayers.lit_share(0.9, 500.0) >= GrowthLayers.lit_share(0.2, 500.0), "development grows the lit share")
	t.truth(GrowthLayers.lit_share(0.5, 2000.0) >= GrowthLayers.lit_share(0.5, 100.0), "population grows the lit share")
	t.truth(GrowthLayers.lit_share(5.0, 1.0e9) <= 1.0 and GrowthLayers.lit_share(-1.0, 0.0) >= 0.0, "lit share stays within 0..1")
	t.truth(GrowthLayers.fallow_share(0.1, 0.9) > 0.0, "pressure with low development leaves fields fallow")
	t.equal(GrowthLayers.fallow_share(0.1, 0.0), 0.0, "no pressure leaves no field fallow")


func _check_cells(geo: MapGeometry, tiles: Dictionary) -> void:
	for city in geo.cities:
		var centre := Vector2i(Vector2(city["point"]) * Vector2(TileBaker.GRID))
		var cells := GrowthLayers.cells_for_town(centre, 30, tiles)
		t.equal(cells, GrowthLayers.cells_for_town(centre, 30, tiles), "%s's cells are deterministic" % city["name"])
		t.equal(cells.size(), 30, "%s gets all 30 cells" % city["name"])
		t.truth((cells[0] - centre).length() <= 3.0, "%s grows outward from beside its own tile" % city["name"])
		var clean := true
		for c in cells:
			clean = clean and _kind(tiles, c) not in WATER and _kind(tiles, c) != "river" and TileBaker.region_at_tile(tiles, c) < MapBaker.FOREIGN_REGION
		t.truth(clean, "%s's cells are dry Ardenian land" % city["name"])
		t.equal(GrowthLayers.cells_for_town(centre, 12, tiles), cells.slice(0, 12), "%s's smaller town is a prefix of its larger one" % city["name"])
	_check_spill(geo, tiles)
	var row := {"id": "vashtera", "population": 1500.0, "development": 0.8, "pressure": 0.1, "control": "full"}
	var targets := GrowthLayers.targets(row, geo, tiles)
	for key in ["town_cells", "lit_cells", "farm_cells", "fallow_cells"]:
		t.truth(targets.has(key), "targets carry %s" % key)
	var town: Array = targets["town_cells"]
	var seen := {}
	for c in town + targets["farm_cells"]:
		seen[c] = true
	t.equal(seen.size(), town.size() + targets["farm_cells"].size(), "town and farm cells never overlap")
	t.truth(targets["lit_cells"].all(func(c: Vector2i) -> bool: return c in town), "lit cells are town cells")
	t.truth(targets["fallow_cells"].all(func(c: Vector2i) -> bool: return c in targets["farm_cells"]), "fallow cells are farm cells")
	t.truth(targets["tower_cells"].size() > 0, "a developed region raises towers")
	var low := GrowthLayers.targets({"id": "vashtera", "population": 1500.0, "development": 0.3, "pressure": 0.1, "control": "full"}, geo, tiles)
	t.equal(low["tower_cells"].size(), 0, "an undeveloped region raises no towers")
	var bigger := GrowthLayers.targets({"id": "vashtera", "population": 4500.0, "development": 0.8, "pressure": 0.1, "control": "full"}, geo, tiles)
	t.truth(bigger["town_cells"].size() > town.size(), "more people fill more town cells")
	t.equal(targets, GrowthLayers.targets(row, geo, tiles), "targets are deterministic")


func _check_spill(geo: MapGeometry, tiles: Dictionary) -> void:
	var spilled := false
	for city in geo.cities:
		var centre := Vector2i(Vector2(city["point"]) * Vector2(TileBaker.GRID))
		var own := geo.region_ids.find(city["region"])
		var cells := GrowthLayers.cells_for_town(centre, 120, tiles)
		var across := {}
		for c in cells:
			var r := TileBaker.region_at_tile(tiles, c)
			t.truth(r < MapBaker.FOREIGN_REGION and _kind(tiles, c) not in WATER and _kind(tiles, c) != "river", "%s spills only onto dry Ardenian land" % city["name"])
			if r != own:
				across[r] = true
		spilled = spilled or not across.is_empty()
		for r in across:
			var fenced := GrowthLayers.cells_for_town(centre, 120, tiles, {r: true})
			t.truth(fenced.all(func(c: Vector2i) -> bool: return TileBaker.region_at_tile(tiles, c) != r), "%s keeps out of blocked region %d" % [city["name"], r])
	t.truth(spilled, "a town at a region edge gets cells across it")
	var rows := _rows(geo, 600.0, 0.5)
	var plan := GrowthLayers.all_targets(rows, geo, tiles)
	var seen := {}
	var total := 0
	for id in plan:
		for c in plan[id]["town_cells"]:
			seen[c] = true
			total += 1
	t.equal(seen.size(), total, "two towns never share a cell")
	rows[geo.region_ids.find("vetrenka")]["control"] = "separatist"
	var fenced_plan := GrowthLayers.all_targets(rows, geo, tiles)
	var vetrenka := geo.region_ids.find("vetrenka")
	var intruders := 0
	for id in fenced_plan:
		if id == "vetrenka":
			continue
		for c in fenced_plan[id]["town_cells"]:
			if TileBaker.region_at_tile(tiles, c) == vetrenka:
				intruders += 1
	t.equal(intruders, 0, "no town spills into a separatist region")
	var small := GrowthLayers.all_targets(_rows(geo, 400.0, 0.5), geo, tiles)
	var large := GrowthLayers.all_targets(_rows(geo, 1200.0, 0.5), geo, tiles)
	for id in small:
		t.truth(large[id]["town_cells"].size() >= 2 * small[id]["town_cells"].size(), "%s: tripled population at least doubles its town (%d to %d)" % [id, small[id]["town_cells"].size(), large[id]["town_cells"].size()])
	for pop in [50.0, 150.0, 300.0, 600.0]:
		t.truth(GrowthLayers.town_tiles(pop * 3.0, false) >= 2 * GrowthLayers.town_tiles(pop, false), "town_tiles at %dk tripled at least doubles" % pop)

func _run() -> void:
	var geo := MapGeometry.load_world()
	var tiles := TileBaker.load_tiles()
	_check_curves()
	_check_cells(geo, tiles)

	root.size = Vector2i(1920, 1080)
	var map: ArdeniaMap = (load("res://scenes/map/ardenia_map.tscn") as PackedScene).instantiate()
	root.add_child(map)
	await _frames()
	t.equal(map.growth_layer.get_used_cells().size(), 0, "nothing grows before a snapshot")

	map.apply_snapshot(_rows(geo, BASE_POPULATION, BASE_DEVELOPMENT), "")
	var before := map.growth_layer.get_used_cells().size()
	var houses := _count_sprite(map, "house")
	t.truth(before > 0 and houses > 0, "the first snapshot paints towns and fields at once")
	t.truth(_count_sprite(map, "capital") == 1, "the capital carries one capital marker")
	t.equal(_count_sprite(map, "house_lit"), 0, "no lights burn by day")

	map.apply_snapshot(_rows(geo, BASE_POPULATION * 3.0, 0.9), "")
	t.equal(map.growth_layer.get_used_cells().size(), before, "a later snapshot starts flipping, not jumping")
	await create_timer(1.6).timeout
	var after := map.growth_layer.get_used_cells().size()
	t.truth(after > before, "tripled population and development paint more cells (%d to %d)" % [before, after])
	t.truth(_count_sprite(map, "house") > houses, "more houses stand")
	t.truth(_count_sprite(map, "tower") > 0, "towers rise at high development")

	map.apply_snapshot(_rows(geo, BASE_POPULATION * 3.0, 0.9), "")
	t.equal(map.growth_layer.get_used_cells().size(), after, "an unchanged snapshot changes nothing")

	var town_total := _count_sprite(map, "house") + _count_sprite(map, "tower") + _count_sprite(map, "capital")
	map.set_dusk(true)
	var lit := _count_sprite(map, "house_lit")
	var expected := GrowthLayers.lit_share(0.9, BASE_POPULATION * 3.0)
	t.truth(lit > 0, "dusk lights the houses")
	t.truth(absf(float(lit) / float(town_total) - expected) < 0.12, "about the lit share burns (%d of %d against %.2f)" % [lit, town_total, expected])
	map.set_dusk(false)
	t.equal(_count_sprite(map, "house_lit"), 0, "day puts the lights out")

	map.apply_snapshot(_rows(geo, BASE_POPULATION, BASE_DEVELOPMENT), "")
	await create_timer(1.6).timeout
	t.equal(map.growth_layer.get_used_cells().size(), before, "shrinking regions clear their cells again")

	map.queue_free()
	await _frames()
	quit(t.finish())
