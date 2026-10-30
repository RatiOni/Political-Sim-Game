class_name MapLines
extends RefCounted

const AROUND: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
const DASH_PERIOD := 4
const DASH_ON := 3
## Trunk routes that hug the Kesla are drawn this many tiles off the water.
const BANK_TILES := 2.5
const RIVER_REACH := 6.0


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
	_ceasefire(img, geo.ceasefire, palette[MapPalette.CEASEFIRE], tile_px, palette[MapPalette.INK])
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


## Everything built across the land: rail, the Zovar pipeline, the road net,
## bridges where they cross the Kesla, harbours and the scatter of villages.
## Drawn as true polylines (a dark casing under a light core) so they read
## over the character grid at every zoom. `tiles` adds the coast-dependent
## detail (harbours, villages) when given.
static func routes(geo: MapGeometry, palette: PackedColorArray, tile_px: int = TileBaker.TILE, covered: Dictionary = {}, locked_rails: Dictionary = {}, tiles: Dictionary = {}) -> Image:
	var img := _blank(tile_px)
	var s := tile_px / 4.0
	var dusk := palette[MapPalette.GRASS] != MapPalette.DAY[MapPalette.GRASS]
	# Growth upgrades the trunk routes cell by cell (`covered`): an improved
	# road loses its dirt-brown edge for a dark kerb, a highway brightens, and
	# a barricade breaks the line. Cells are looked up on the route's own
	# geometry even where the drawing bows away from the river.
	var state := func(p: Vector2) -> String: return String(covered.get(Vector2i((p / tile_px).floor()), ""))
	var plain := func(p: Vector2) -> bool: return state.call(p) != ""
	var laid := func(p: Vector2) -> bool: return state.call(p) == "" or state.call(p) == "barricade"
	var barred := func(p: Vector2) -> bool: return state.call(p) == "barricade"
	var unpaved := func(p: Vector2) -> bool: return not state.call(p).begins_with("paved")
	var none := func(_p: Vector2) -> bool: return false
	var pale := palette[MapPalette.WALL]
	var ties := palette[MapPalette.SNOW_SHADE]
	if not tiles.is_empty():
		for v in MapDetails.villages(tiles, geo):
			var at := _px(v, tile_px)
			_dab(img, at, 1.4 * s, palette[MapPalette.INK], none)
			_dab(img, at, 0.8 * s, _tone(Color8(196, 170, 120), dusk), none)
	# The pipeline first: everything else crosses over it.
	var amber := _tone(Color8(236, 150, 48), dusk)
	for route in geo.routes:
		if route["kind"] == "pipeline":
			var line := _pxs(route["points"], tile_px)
			_stroke(img, line, 1.2 * s, palette[MapPalette.INK], 0.0, 0.0, none)
			_stroke(img, line, 0.6 * s, amber, 4.0 * s, 6.0 * s, none)
			for p in route["points"]:
				_dab(img, _px(p, tile_px), 1.8 * s, palette[MapPalette.INK], none)
				_dab(img, _px(p, tile_px), 1.0 * s, amber, none)
	var crossings: Array = []
	for i in geo.routes.size():
		var route: Dictionary = geo.routes[i]
		if route["kind"] != "rail" or locked_rails.has(i):
			continue
		var bowed := _off_river(route["points"], geo, -1.0)
		var line := _pxs(bowed[0], tile_px)
		var base := _pxs(bowed[1], tile_px)
		_ticks(img, line, 1.8 * s, palette[MapPalette.RAIL], 4.0 * s, plain, base)
		_ticks(img, line, 1.8 * s, palette[MapPalette.INK], 4.0 * s, laid, base)
		_stroke(img, line, 1.2 * s, palette[MapPalette.RAIL], 0.0, 0.0, plain, base)
		_stroke(img, line, 1.2 * s, palette[MapPalette.INK], 0.0, 0.0, laid, base)
		_stroke(img, line, 0.5 * s, ties, 3.0 * s, 6.0 * s, barred, base)
		for c in _crossings(line, geo, tile_px, 1.3 * s):
			_bridge(img, c[0], c[1], c[2], pale, palette[MapPalette.INK], s)
	# Bridges follow their road, so rail closures never touch road pixels.
	for road in MapDetails.ROADS:
		var line := _pxs(PackedVector2Array(road), tile_px)
		_stroke(img, line, 1.0 * s, palette[MapPalette.INK], 0.0, 0.0, none)
		_stroke(img, line, 0.5 * s, _tone(Color8(176, 150, 104), dusk), 0.0, 0.0, none)
		crossings.append_array(_crossings(line, geo, tile_px, 1.0 * s))
	for route in geo.routes:
		if route["kind"] != "road":
			continue
		var bowed := _off_river(route["points"], geo, 1.0)
		var line := _pxs(bowed[0], tile_px)
		var base := _pxs(bowed[1], tile_px)
		_stroke(img, line, 1.3 * s, palette[MapPalette.ROAD], 0.0, 0.0, plain, base)
		_stroke(img, line, 1.5 * s, palette[MapPalette.INK], 0.0, 0.0, laid, base)
		_stroke(img, line, 0.5 * s, _tone(Color8(214, 188, 132), dusk), 0.0, 0.0, barred, base)
		_stroke(img, line, 0.7 * s, _tone(Color8(240, 226, 190), dusk), 0.0, 0.0, unpaved, base)
		crossings.append_array(_crossings(line, geo, tile_px, 1.4 * s))
	for c in crossings:
		_bridge(img, c[0], c[1], c[2], pale, palette[MapPalette.INK], s)
	if not tiles.is_empty():
		for harbour in MapDetails.harbours(tiles, geo):
			_harbour(img, _px(harbour[0], tile_px), harbour[1], pale, palette[MapPalette.INK], s)
	return img


static func _tone(c: Color, dusk: bool) -> Color:
	return Color(c.r * 0.55, c.g * 0.52, c.b * 0.72) if dusk else c


static func _px(p: Vector2, tile_px: int) -> Vector2:
	return p * Vector2(TileBaker.GRID * tile_px)


static func _pxs(points: PackedVector2Array, tile_px: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(_px(p, tile_px))
	return out


## Trunk routes that run beside the Kesla are pushed onto one bank (`side`
## +1 or -1 of the river's flow), easing back in to the towns that sit on the
## water, so road, rail and river stay three separate lines. Returns
## [drawn points, the matching points on the route's own line].
static func _off_river(points: PackedVector2Array, geo: MapGeometry, side: float) -> Array:
	var grid := Vector2(TileBaker.GRID)
	var river := PackedVector2Array()
	for k in geo.kesla:
		river.append(k * grid)
	var towns: Array[Vector2] = []
	for city in geo.cities:
		towns.append(Vector2(city["point"]) * grid)
	var out := PackedVector2Array()
	var base := PackedVector2Array()
	var shared := 0
	for p in points:
		for k in geo.kesla:
			shared += 1 if k.distance_to(p) < 0.004 else 0
	if shared < 2:
		# Only the routes laid along the river itself move; the rest
		# simply cross it.
		return [points, points]
	for i in points.size() - 1:
		var a := points[i] * grid
		var b := points[i + 1] * grid
		var n := maxi(1, ceili(a.distance_to(b)))
		for k in n + (1 if i == points.size() - 2 else 0):
			var p := a.lerp(b, float(k) / n)
			base.append(p / grid)
			out.append(_bank(p, river, towns, side) / grid)
	return [out, base]


static func _bank(p: Vector2, river: PackedVector2Array, towns: Array[Vector2], side: float) -> Vector2:
	var best_d := INF
	var q := Vector2.ZERO
	var normal := Vector2.ZERO
	for j in river.size() - 1:
		var c := Geometry2D.get_closest_point_to_segment(p, river[j], river[j + 1])
		if c.distance_to(p) < best_d:
			best_d = c.distance_to(p)
			q = c
			normal = (river[j + 1] - river[j]).normalized().orthogonal() * side
	var depth := (p - q).dot(normal)
	if depth >= BANK_TILES or best_d > RIVER_REACH:
		return p
	var near := INF
	for t in towns:
		near = minf(near, t.distance_to(p))
	var ease := clampf((near - 1.0) / 4.0, 0.0, 1.0)
	var fade := 1.0 - smoothstep(BANK_TILES, RIVER_REACH, best_d)
	return p + normal * (BANK_TILES - depth) * ease * fade


## Bridges: every place a drawn route crosses the Kesla, away from the towns
## that sit on the river (their own markers cover the crossing there).
static func _crossings(line: PackedVector2Array, geo: MapGeometry, tile_px: int, half: float) -> Array:
	var out: Array = []
	var river := _pxs(geo.kesla, tile_px)
	var clear := 2.5 * tile_px
	for i in line.size() - 1:
		for j in river.size() - 1:
			var hit: Variant = Geometry2D.segment_intersects_segment(line[i], line[i + 1], river[j], river[j + 1])
			if hit == null:
				continue
			var near_town := false
			for city in geo.cities:
				near_town = near_town or _px(city["point"], tile_px).distance_to(hit) < clear
			if not near_town:
				out.append([hit, (line[i + 1] - line[i]).normalized(), half])
	return out


static func _bridge(img: Image, at: Vector2, along: Vector2, half: float, deck: Color, ink: Color, s: float) -> void:
	var across := along.orthogonal()
	var reach := 3.5 * s
	var side := half + 1.0 * s
	# Two parapets with a dark edge outside each: a bridge reads as "=".
	for k in range(-int(reach * 2), int(reach * 2) + 1):
		var p := at + along * (k / 2.0)
		for edge in [-1.0, 1.0]:
			_put(img, p + across * edge * (side + 1.0), ink)
			_put(img, p + across * edge * side, deck)


static func _harbour(img: Image, shore: Vector2, sea: Vector2, deck: Color, ink: Color, s: float) -> void:
	var tip := shore + sea * 7.0 * s
	var head := sea.orthogonal()
	var pier := PackedVector2Array([shore, tip])
	var arm := PackedVector2Array([tip - head * 3.0 * s, tip + head * 3.0 * s])
	var mole := PackedVector2Array([shore + head * 5.0 * s, shore + head * 5.0 * s + sea * 4.0 * s - head * 1.5 * s])
	var none := func(_p: Vector2) -> bool: return false
	for line in [pier, arm, mole]:
		_stroke(img, line, 1.2 * s, ink, 0.0, 0.0, none)
	for line in [pier, arm, mole]:
		_stroke(img, line, 0.5 * s, deck, 0.0, 0.0, none)
	# The harbour light.
	_dab(img, tip + sea * 2.5 * s, 1.0 * s, Color8(255, 220, 96), none)


static func _put(img: Image, p: Vector2, colour: Color) -> void:
	var at := Vector2i(p.floor())
	if at.x >= 0 and at.y >= 0 and at.x < img.get_width() and at.y < img.get_height():
		img.set_pixelv(at, colour)


## A filled disk of radius `r` pixels around `p` (at least the pixel itself).
static func _dab(img: Image, p: Vector2, r: float, colour: Color, skip: Callable, probe: Variant = null) -> void:
	if skip.call(p if probe == null else probe):
		return
	if r < 0.75:
		_put(img, p, colour)
		return
	for y in range(floori(p.y - r), ceili(p.y + r) + 1):
		for x in range(floori(p.x - r), ceili(p.x + r) + 1):
			if Vector2(x + 0.5, y + 0.5).distance_squared_to(p) <= r * r:
				_put(img, Vector2(x, y), colour)


## A polyline of dabs; `period` > 0 dashes it with `on` pixels lit per period.
## `skip` is asked about the matching point on `base` when one is given.
static func _stroke(img: Image, line: PackedVector2Array, r: float, colour: Color, on: float, period: float, skip: Callable, base: PackedVector2Array = PackedVector2Array()) -> void:
	if base.is_empty():
		base = line
	var walked := 0.0
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var length := a.distance_to(b)
		var steps := maxi(1, ceili(length * 2.0))
		for k in steps + 1:
			var d := walked + length * k / steps
			if period > 0.0 and fmod(d, period) >= on:
				continue
			var t := float(k) / steps
			_dab(img, a.lerp(b, t), r, colour, skip, base[i].lerp(base[i + 1], t))
		walked += length


## Short strokes across a line every `period` pixels (rail sleepers, wire).
static func _ticks(img: Image, line: PackedVector2Array, half: float, colour: Color, period: float, skip: Callable, base: PackedVector2Array = PackedVector2Array()) -> void:
	if base.is_empty():
		base = line
	var walked := 0.0
	var next := period / 2.0
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var length := a.distance_to(b)
		var across := (b - a).normalized().orthogonal()
		while next <= walked + length:
			var t := (next - walked) / maxf(length, 0.001)
			var p := a.lerp(b, t)
			if not skip.call(base[i].lerp(base[i + 1], t)):
				for w in range(-int(half * 2), int(half * 2) + 1):
					_put(img, p + across * (w / 2.0), colour)
			next += period
		walked += length


## The ceasefire is a front, not a border: a dark band with red dashes and
## wire ticks, and a barrier wherever a road runs into it.
static func _ceasefire(img: Image, points: PackedVector2Array, colour: Color, tile_px: int, ink: Color) -> void:
	var s := tile_px / 4.0
	var line := _pxs(points, tile_px)
	var none := func(_p: Vector2) -> bool: return false
	_stroke(img, line, 1.8 * s, ink, 0.0, 0.0, none)
	_stroke(img, line, 0.9 * s, colour, 3.0 * s, 5.0 * s, none)
	_ticks(img, line, 1.6 * s, colour, 5.0 * s, none)
	for road in MapDetails.ROADS:
		var path := _pxs(PackedVector2Array(road), tile_px)
		for i in path.size() - 1:
			for j in line.size() - 1:
				var hit: Variant = Geometry2D.segment_intersects_segment(path[i], path[i + 1], line[j], line[j + 1])
				if hit != null:
					_dab(img, hit, 2.8 * s, ink, none)
					_dab(img, hit, 1.8 * s, colour, none)
					_dab(img, hit, 0.7 * s, Color8(240, 236, 228), none)
