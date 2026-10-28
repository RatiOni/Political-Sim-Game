extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const WATER := ["deep_sea", "sea", "shallows"]
const LOWER_LAND_ROW := 60


func _initialize() -> void:
	var t = TestSupportScript.new()
	var geo := MapGeometry.load_world()
	var height: Image = load("res://data/map/baked/height.exr").get_image()
	var regions: Image = load("res://data/map/baked/region_ids.png").get_image()
	var data := TileBaker.bake(height, regions, geo)
	var again := TileBaker.bake(height, regions, geo)
	t.equal(data["kinds"], again["kinds"], "two bakes give identical kinds")
	t.equal(data["variants"], again["variants"], "two bakes give identical variants")
	t.equal(data["regions"], again["regions"], "two bakes give identical regions")

	var cells := TileBaker.GRID.x * TileBaker.GRID.y
	t.equal(data["grid"], [168, 100], "the grid is 168 by 100")
	t.equal(data["kinds"].size(), cells, "one kind per tile")
	t.equal(data["regions"].size(), cells, "one region per tile")
	t.equal(data["variants"].size(), cells, "one variant per tile")

	var kinds: PackedByteArray = data["kinds"]
	var invalid := 0
	for k in kinds:
		if k >= TileArt.KINDS.size():
			invalid += 1
	t.equal(invalid, 0, "every kind index is valid")
	for v in data["variants"]:
		if v >= TileArt.VARIANTS:
			invalid += 1
	t.equal(invalid, 0, "every variant index is valid")

	for c in geo.cities:
		var cell := Vector2i(Vector2(c["point"]) * Vector2(TileBaker.GRID))
		t.equal(TileBaker.region_at_tile(data, cell), geo.region_ids.find(c["region"]), "%s's tile is in %s" % [c["name"], c["region"]])
		t.truth(_kind(data, cell) not in WATER, "%s's tile is land" % c["name"])

	var snow_top := 0
	var snow_low := 0
	var shallows_bad := 0
	var sand_bad := 0
	var land := 0
	var counts := {}
	for y in TileBaker.GRID.y:
		for x in TileBaker.GRID.x:
			var kind := _kind(data, Vector2i(x, y))
			counts[kind] = counts.get(kind, 0) + 1
			if kind not in WATER:
				land += 1
			if kind == "snow":
				if y < TileBaker.GRID.y / 4:
					snow_top += 1
				if y >= LOWER_LAND_ROW:
					snow_low += 1
			if kind == "shallows" and not _open_sea_within(data, x, y, 4):
				shallows_bad += 1
			if kind == "sand" and not _touches(data, x, y, ["shallows"]):
				sand_bad += 1
	t.truth(snow_top > 0, "snow lies in the top quarter")
	t.equal(snow_low, 0, "no snow below row 60")
	t.equal(shallows_bad, 0, "every shallows tile lies within 4 tiles of open sea")
	t.equal(sand_bad, 0, "every sand tile neighbours shallows")

	var forest: float = counts.get("forest", 0) / float(land)
	var farm: float = counts.get("farm", 0) / float(land)
	var high: float = (counts.get("mountain", 0) + counts.get("snow", 0)) / float(land)
	t.truth(forest >= 0.10 and forest <= 0.30, "forest share %.3f is 0.10-0.30" % forest)
	t.truth(farm >= 0.06 and farm <= 0.25, "farm share %.3f is 0.06-0.25" % farm)
	t.truth(high >= 0.08 and high <= 0.25, "mountain and snow share %.3f is 0.08-0.25" % high)

	var wrong := 0
	for cell in TileBaker.line_tiles(geo.kesla):
		var kind := _kind(data, cell)
		if kind != "river" and kind not in WATER:
			wrong += 1
	t.equal(wrong, 0, "the Kesla is river wherever it is not sea")

	t.equal(TileBaker.load_tiles("res://data/map/baked/missing_tiles.json"), {}, "a missing tile file loads as empty")
	var path := "user://tiles_test.json"
	TileBaker.save(data, path)
	var loaded := TileBaker.load_tiles(path)
	t.equal(loaded["kinds"], data["kinds"], "saved kinds round-trip")
	t.equal(loaded["regions"], data["regions"], "saved regions round-trip")
	t.equal(loaded["variants"], data["variants"], "saved variants round-trip")
	DirAccess.remove_absolute(path)
	var committed := TileBaker.load_tiles()
	t.equal(committed.get("kinds", PackedByteArray()), data["kinds"], "the committed tiles match a fresh bake")
	quit(t.finish())


func _kind(data: Dictionary, cell: Vector2i) -> String:
	return TileArt.KINDS[data["kinds"][cell.y * TileBaker.GRID.x + cell.x]]


func _touches(data: Dictionary, x: int, y: int, names: Array) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = Vector2i(x, y) + d
		if n.x >= 0 and n.y >= 0 and n.x < TileBaker.GRID.x and n.y < TileBaker.GRID.y and _kind(data, n) in names:
			return true
	return false


func _open_sea_within(data: Dictionary, x: int, y: int, reach: int) -> bool:
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var n := Vector2i(x + dx, y + dy)
			if n.x >= 0 and n.y >= 0 and n.x < TileBaker.GRID.x and n.y < TileBaker.GRID.y and _kind(data, n) in ["sea", "deep_sea"]:
				return true
	return false
