class_name TileBaker
extends RefCounted

const GRID := Vector2i(168, 100)
const TILE := 8
const TILES_PATH := "res://data/map/baked/tiles.json"
const NOISE_SEED := 7
const NOISE_FREQUENCY := 0.08
const SNOW_HEIGHT := 0.80
const MOUNTAIN_HEIGHT := 0.6
const UPLAND_HEIGHT := 0.42
const FOOTHILL_HEIGHT := 0.3
const FARM_HEIGHT := 0.17
const SAND_HEIGHT := 0.05
const FARM_RADIUS := 9.0
const OPEN_SEA_RADIUS := 5
const ORTHOGONAL: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const SHALLOW_REACH: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]


static func bake(height: Image, regions: Image, geo: MapGeometry) -> Dictionary:
	var noise := FastNoiseLite.new()
	noise.seed = NOISE_SEED
	noise.frequency = NOISE_FREQUENCY
	var count := GRID.x * GRID.y
	var region_ids := PackedByteArray()
	var kinds: Array[String] = []
	region_ids.resize(count)
	for ty in GRID.y:
		for tx in GRID.x:
			var region := _region_sample(regions, tx, ty)
			region_ids[ty * GRID.x + tx] = region
			kinds.append(_land_kind(region, _height_sample(height, tx, ty), noise, tx, ty, geo))
	var land := kinds.duplicate()
	_add_shallows(kinds)
	_add_open_sea(kinds, land)
	_add_sand(kinds, height)
	_add_river(kinds, geo)
	var out_kinds := PackedByteArray()
	var variants := PackedByteArray()
	out_kinds.resize(count)
	variants.resize(count)
	for ty in GRID.y:
		for tx in GRID.x:
			var i := ty * GRID.x + tx
			out_kinds[i] = TileArt.KINDS.find(kinds[i])
			variants[i] = int(_hash(tx, ty) * TileArt.VARIANTS) % TileArt.VARIANTS
	return {"grid": [GRID.x, GRID.y], "kinds": out_kinds, "regions": region_ids, "variants": variants}


static func region_at_tile(data: Dictionary, cell: Vector2i) -> int:
	var regions: PackedByteArray = data.get("regions", PackedByteArray())
	var index := cell.y * GRID.x + cell.x
	if not _in_grid(cell) or index >= regions.size():
		return MapBaker.SEA_REGION
	return regions[index]


static func line_tiles(points: PackedVector2Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for s in points.size() - 1:
		var a := Vector2(points[s].x * GRID.x, points[s].y * GRID.y)
		var b := Vector2(points[s + 1].x * GRID.x, points[s + 1].y * GRID.y)
		var steps := int(ceil(a.distance_to(b) * 2.0))
		for k in steps + 1:
			var p := Vector2i(a.lerp(b, float(k) / maxf(steps, 1)).floor())
			if out.is_empty() or out[-1] != p:
				out.append(p)
	return out


static func save(data: Dictionary, path: String = TILES_PATH) -> bool:
	var doc := {"grid": data["grid"]}
	for key in ["kinds", "regions", "variants"]:
		doc[key] = Marshalls.raw_to_base64(data[key])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write tile file: %s" % path)
		return false
	file.store_string(JSON.stringify(doc))
	file.close()
	return true


static func load_tiles(path: String = TILES_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("tile file missing: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not _is_well_formed(parsed):
		push_error("tile file malformed: %s" % path)
		return {}
	var doc: Dictionary = parsed
	var out := {"grid": [int(doc["grid"][0]), int(doc["grid"][1])]}
	for key in ["kinds", "regions", "variants"]:
		out[key] = Marshalls.base64_to_raw(doc[key])
	if not _is_consistent(out):
		push_error("tile file inconsistent: %s" % path)
		return {}
	return out


static func _is_consistent(data: Dictionary) -> bool:
	if data["grid"] != [GRID.x, GRID.y]:
		return false
	for key in ["kinds", "regions", "variants"]:
		if data[key].size() != GRID.x * GRID.y:
			return false
	for k in data["kinds"]:
		if k >= TileArt.KINDS.size():
			return false
	return true


static func _is_well_formed(doc: Dictionary) -> bool:
	if not doc.get("grid") is Array or doc["grid"].size() != 2:
		return false
	for key in ["kinds", "regions", "variants"]:
		if not doc.get(key) is String:
			return false
	return true


static func _height_sample(height: Image, tx: int, ty: int) -> float:
	var sum := 0.0
	for k in 4:
		sum += height.get_pixel(tx * TILE + 2 + (k % 2) * 4, ty * TILE + 2 + (k / 2) * 4).r
	return sum / 4.0 / MapBaker.MAX_HEIGHT_M


static func _region_sample(regions: Image, tx: int, ty: int) -> int:
	return int(round(regions.get_pixel(tx * TILE + TILE / 2, ty * TILE + TILE / 2).r * 255.0))


static func _hash(x: int, y: int, salt: int = 0) -> float:
	var n := (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	return float((n >> 8) & 0xFFFF) / 65535.0


static func _near_city(geo: MapGeometry, tx: int, ty: int) -> bool:
	for c in geo.cities:
		var p: Vector2 = c["point"]
		if Vector2(tx, ty).distance_to(Vector2(p.x * GRID.x, p.y * GRID.y)) < FARM_RADIUS:
			return true
	return false


static func _land_kind(region: int, h: float, noise: FastNoiseLite, tx: int, ty: int, geo: MapGeometry) -> String:
	if region == MapBaker.SEA_REGION:
		return "sea"
	if h > SNOW_HEIGHT:
		return "snow"
	if h > MOUNTAIN_HEIGHT:
		return "mountain"
	if h > UPLAND_HEIGHT:
		return "forest" if noise.get_noise_2d(tx, ty) > -0.25 else "hills"
	if h > FOOTHILL_HEIGHT:
		return "forest" if noise.get_noise_2d(tx, ty) > 0.05 else "hills"
	if h < FARM_HEIGHT and _near_city(geo, tx, ty) and noise.get_noise_2d(tx + 50, ty) > -0.35:
		return "farm"
	if noise.get_noise_2d(tx + 99, ty) > 0.30:
		return "forest"
	return "grass"


static func _in_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < GRID.x and cell.y < GRID.y


static func _add_shallows(kinds: Array[String]) -> void:
	for ty in GRID.y:
		for tx in GRID.x:
			var i := ty * GRID.x + tx
			if kinds[i] != "sea":
				continue
			for d in SHALLOW_REACH:
				var n := Vector2i(tx, ty) + d
				if _in_grid(n) and kinds[n.y * GRID.x + n.x] not in ["sea", "shallows"]:
					kinds[i] = "shallows"
					break


static func _add_open_sea(kinds: Array[String], land: Array[String]) -> void:
	for ty in GRID.y:
		for tx in GRID.x:
			var i := ty * GRID.x + tx
			if kinds[i] == "sea" and not _land_within(land, tx, ty, OPEN_SEA_RADIUS):
				kinds[i] = "deep_sea"


static func _land_within(land: Array[String], tx: int, ty: int, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var n := Vector2i(tx + dx, ty + dy)
			if _in_grid(n) and land[n.y * GRID.x + n.x] != "sea":
				return true
	return false


static func _add_sand(kinds: Array[String], height: Image) -> void:
	for ty in GRID.y:
		for tx in GRID.x:
			var i := ty * GRID.x + tx
			if kinds[i] not in ["grass", "farm"] or _height_sample(height, tx, ty) >= SAND_HEIGHT:
				continue
			for d in ORTHOGONAL:
				var n := Vector2i(tx, ty) + d
				if _in_grid(n) and kinds[n.y * GRID.x + n.x] == "shallows":
					kinds[i] = "sand"
					break


static func _add_river(kinds: Array[String], geo: MapGeometry) -> void:
	for cell in line_tiles(geo.kesla):
		var i := cell.y * GRID.x + cell.x
		if _in_grid(cell) and kinds[i] not in ["deep_sea", "sea", "shallows"]:
			kinds[i] = "river"
