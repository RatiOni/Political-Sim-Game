class_name MapLines
extends RefCounted

const TILE := TileBaker.TILE
const SIZE := Vector2i(TileBaker.GRID.x * TILE, TileBaker.GRID.y * TILE)
const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const AROUND: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
const DASH_PERIOD := 4
const DASH_ON := 3
const CEASEFIRE_PERIOD := 6
const CEASEFIRE_ON := 3
const CEASEFIRE_ROWS: Array[int] = [3, 4]


static func build(tiles: Dictionary, geo: MapGeometry, palette: PackedColorArray, weight: int = 1) -> Image:
	var img := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var count := geo.region_ids.size()
	var inside := func(r: int) -> bool: return r < count
	var foreign := func(r: int) -> bool: return r == MapBaker.FOREIGN_REGION
	_internal_borders(img, tiles, count, palette[MapPalette.GOLD], weight)
	_ring(img, tiles, foreign, inside, palette[MapPalette.GOLD], weight)
	_ring(img, tiles, inside, foreign, palette[MapPalette.GOLD_DARK], weight)
	for route in geo.routes:
		if route["kind"] in ["road", "rail"]:
			_stamp(img, route["points"], TileArt.drawn(TileArt.DRAWN[route["kind"]]), palette, weight)
	_ceasefire(img, geo.ceasefire, palette[MapPalette.CEASEFIRE], weight)
	return img


static func _region(tiles: Dictionary, pixel: Vector2i) -> int:
	return TileBaker.region_at_tile(tiles, Vector2i(floori(pixel.x / float(TILE)), floori(pixel.y / float(TILE))))


static func _perimeter(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var origin := cell * TILE
	for y in TILE:
		for x in TILE:
			if x == 0 or y == 0 or x == TILE - 1 or y == TILE - 1:
				out.append(origin + Vector2i(x, y))
	return out


static func _touches(tiles: Dictionary, cell: Vector2i, wanted: Callable) -> bool:
	for d in AROUND:
		if wanted.call(TileBaker.region_at_tile(tiles, cell + d)):
			return true
	return false


static func _ring(img: Image, tiles: Dictionary, own: Callable, other: Callable, colour: Color, weight: int) -> void:
	for cy in TileBaker.GRID.y:
		for cx in TileBaker.GRID.x:
			var cell := Vector2i(cx, cy)
			if not own.call(TileBaker.region_at_tile(tiles, cell)) or not _touches(tiles, cell, other):
				continue
			for p in _perimeter(cell):
				for d in AROUND:
					if other.call(_region(tiles, p + d)):
						_put(img, p, colour, weight)
						break


static func _internal_borders(img: Image, tiles: Dictionary, count: int, colour: Color, weight: int) -> void:
	for cy in TileBaker.GRID.y:
		for cx in TileBaker.GRID.x:
			var cell := Vector2i(cx, cy)
			var own := TileBaker.region_at_tile(tiles, cell)
			if own >= count:
				continue
			for side in SIDES:
				var other := TileBaker.region_at_tile(tiles, cell + side)
				if other < count and other > own:
					_dashed_edge(img, cell, side, colour, weight)


static func _dashed_edge(img: Image, cell: Vector2i, side: Vector2i, colour: Color, weight: int) -> void:
	var origin := cell * TILE
	for k in TILE:
		var p: Vector2i
		if side.x != 0:
			p = origin + Vector2i(TILE - 1 if side.x > 0 else 0, k)
		else:
			p = origin + Vector2i(k, TILE - 1 if side.y > 0 else 0)
		if ((p.x + p.y) / weight) % DASH_PERIOD < DASH_ON:
			_put(img, p, colour, weight)


static func _stamp(img: Image, points: PackedVector2Array, pattern: PackedInt32Array, palette: PackedColorArray, weight: int) -> void:
	for cell in TileBaker.line_tiles(points):
		if not Rect2i(Vector2i.ZERO, TileBaker.GRID).has_point(cell):
			continue
		for p in TILE * TILE:
			if pattern[p] >= 0:
				_put(img, cell * TILE + Vector2i(p % TILE, p / TILE), palette[pattern[p]], weight)


static func _ceasefire(img: Image, points: PackedVector2Array, colour: Color, weight: int) -> void:
	for cell in TileBaker.line_tiles(points):
		if not Rect2i(Vector2i.ZERO, TileBaker.GRID).has_point(cell):
			continue
		for row in CEASEFIRE_ROWS:
			for x in TILE:
				var p := cell * TILE + Vector2i(x, row)
				if (p.x / weight) % CEASEFIRE_PERIOD < CEASEFIRE_ON:
					_put(img, p, colour, weight)


static func _put(img: Image, p: Vector2i, colour: Color, weight: int) -> void:
	img.fill_rect(Rect2i(p, Vector2i(weight, weight)).intersection(Rect2i(Vector2i.ZERO, SIZE)), colour)
