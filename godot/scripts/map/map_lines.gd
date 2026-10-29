class_name MapLines
extends RefCounted

const AROUND: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
const DASH_PERIOD := 4
const DASH_ON := 3
const DOT_PERIOD := 3
const DOT_ON := 2
const TIE_SPACING := 3
const CEASEFIRE_PERIOD := 6
const CEASEFIRE_ON := 3


static func canvas_size(tile_px: int) -> Vector2i:
	return TileBaker.GRID * tile_px


static func _blank(tile_px: int) -> Image:
	var size := canvas_size(tile_px)
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func build(tiles: Dictionary, geo: MapGeometry, palette: PackedColorArray, tile_px: int = TileBaker.TILE) -> Image:
	var img := _blank(tile_px)
	var count := geo.region_ids.size()
	var inside := func(r: int) -> bool: return r < count
	var foreign := func(r: int) -> bool: return r == MapBaker.FOREIGN_REGION
	_internal_borders(img, tiles, count, palette[MapPalette.GOLD], tile_px)
	_ring(img, tiles, foreign, inside, palette[MapPalette.GOLD], tile_px)
	_ring(img, tiles, inside, foreign, palette[MapPalette.GOLD_DARK], tile_px)
	_ceasefire(img, geo.ceasefire, palette[MapPalette.CEASEFIRE], tile_px)
	return img


static func routes(geo: MapGeometry, palette: PackedColorArray, tile_px: int = TileBaker.TILE, covered: Dictionary = {}, locked_rails: Dictionary = {}) -> Image:
	var img := _blank(tile_px)
	for i in geo.routes.size():
		var route: Dictionary = geo.routes[i]
		if route["kind"] == "road":
			_road(img, route["points"], palette[MapPalette.ROAD], tile_px, covered)
		elif route["kind"] == "rail" and not locked_rails.has(i):
			_rail(img, route["points"], palette[MapPalette.RAIL], tile_px, covered)
	return img


static func _region(tiles: Dictionary, pixel: Vector2i, tile_px: int) -> int:
	return TileBaker.region_at_tile(tiles, Vector2i(floori(pixel.x / float(tile_px)), floori(pixel.y / float(tile_px))))


static func _perimeter(cell: Vector2i, tile_px: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var origin := cell * tile_px
	for y in tile_px:
		for x in tile_px:
			if x == 0 or y == 0 or x == tile_px - 1 or y == tile_px - 1:
				out.append(origin + Vector2i(x, y))
	return out


static func _touches(tiles: Dictionary, cell: Vector2i, wanted: Callable) -> bool:
	for d in AROUND:
		if wanted.call(TileBaker.region_at_tile(tiles, cell + d)):
			return true
	return false


static func _ring(img: Image, tiles: Dictionary, own: Callable, other: Callable, colour: Color, tile_px: int) -> void:
	for cy in TileBaker.GRID.y:
		for cx in TileBaker.GRID.x:
			var cell := Vector2i(cx, cy)
			if not own.call(TileBaker.region_at_tile(tiles, cell)) or not _touches(tiles, cell, other):
				continue
			for p in _perimeter(cell, tile_px):
				for d in AROUND:
					if other.call(_region(tiles, p + d, tile_px)):
						img.set_pixelv(p, colour)
						break


static func _internal_borders(img: Image, tiles: Dictionary, count: int, colour: Color, tile_px: int) -> void:
	for cy in TileBaker.GRID.y:
		for cx in TileBaker.GRID.x:
			var cell := Vector2i(cx, cy)
			var own := TileBaker.region_at_tile(tiles, cell)
			if own >= count:
				continue
			for side in TileBaker.SIDES:
				var other := TileBaker.region_at_tile(tiles, cell + side)
				if other < count and other > own:
					_dashed_edge(img, cell, side, colour, tile_px)


static func _dashed_edge(img: Image, cell: Vector2i, side: Vector2i, colour: Color, tile_px: int) -> void:
	var origin := cell * tile_px
	var far := tile_px - 1
	for k in tile_px:
		var p := origin + (Vector2i(far if side.x > 0 else 0, k) if side.x != 0 else Vector2i(k, far if side.y > 0 else 0))
		if (p.x + p.y) % DASH_PERIOD < DASH_ON:
			img.set_pixelv(p, colour)


static func _route_cells(points: PackedVector2Array) -> Array[Vector2i]:
	return TileBaker.line_tiles(points).filter(TileBaker.in_grid)


static func _road(img: Image, points: PackedVector2Array, colour: Color, tile_px: int, covered: Dictionary) -> void:
	var row := tile_px * 5 / 8
	for cell in _route_cells(points):
		if covered.has(cell):
			continue
		for x in tile_px:
			if x % DOT_PERIOD < DOT_ON:
				img.set_pixelv(cell * tile_px + Vector2i(x, row), colour)


static func _rail(img: Image, points: PackedVector2Array, colour: Color, tile_px: int, covered: Dictionary) -> void:
	var row := tile_px * 2 / 8
	for cell in _route_cells(points):
		if covered.has(cell):
			continue
		for x in tile_px:
			var origin := cell * tile_px
			img.set_pixelv(origin + Vector2i(x, row), colour)
			if x % TIE_SPACING == 0:
				img.set_pixelv(origin + Vector2i(x, row - 1), colour)
				img.set_pixelv(origin + Vector2i(x, row + 1), colour)


static func _ceasefire(img: Image, points: PackedVector2Array, colour: Color, tile_px: int) -> void:
	var rows := [tile_px * 3 / 8, tile_px * 4 / 8] if tile_px >= 8 else [tile_px / 2]
	for cell in _route_cells(points):
		for row in rows:
			for x in tile_px:
				var p := cell * tile_px + Vector2i(x, row)
				if p.x % CEASEFIRE_PERIOD < CEASEFIRE_ON:
					img.set_pixelv(p, colour)
