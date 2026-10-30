class_name MapDetails
extends RefCounted

## Presentation-only detail layered over the baked map: the canon towns from
## `content/lore/geography.py` that the world file does not carry, the secondary
## road net, harbours, lakes, marsh, and the terrain dressing (woodland density,
## field patchwork) that turns flat kind fields into countryside. Nothing here
## feeds the simulation or the baked tiles; it only changes what is drawn.

const KIND_SEA := 1
const KIND_SHALLOWS := 2
const KIND_GRASS := 4
const KIND_FARM := 5
const KIND_FALLOW := 6
const KIND_FOREST := 7
const KIND_HILLS := 8
const KIND_RIVER := 11
const LAND_KINDS: Array[int] = [3, 4, 5, 6, 7, 8]

## Canon towns (geography.py CITIES not in the world file). `coast` snaps the
## point onto the shore so a port really sits on the water.
const TOWNS: Array[Dictionary] = [
	{"name": "Ostrena", "point": Vector2(0.262, 0.300), "coast": true, "harbour": true},
	{"name": "Kavor", "point": Vector2(0.388, 0.272)},
	{"name": "Karvel", "point": Vector2(0.505, 0.130)},
	{"name": "Lestara", "point": Vector2(0.528, 0.272)},
	{"name": "Ordel", "point": Vector2(0.365, 0.415)},
	{"name": "Rovets", "point": Vector2(0.640, 0.565)},
	{"name": "Meradin", "point": Vector2(0.905, 0.405)},
	{"name": "Azren", "point": Vector2(0.935, 0.300)},
]

## Ports on the existing city list (by name).
const HARBOUR_CITIES: Array[String] = ["Tavri", "Selvara"]

## Secondary roads: the country's ordinary road net between the trunk routes.
const ROADS: Array = [
	# The east: Duvinsk to Darev and out to the frontier towns.
	[Vector2(0.705, 0.385), Vector2(0.785, 0.365), Vector2(0.865, 0.325)],
	[Vector2(0.865, 0.325), Vector2(0.885, 0.37), Vector2(0.905, 0.405)],
	[Vector2(0.865, 0.325), Vector2(0.90, 0.305), Vector2(0.935, 0.300)],
	# The Sela's plain road, under the southern hills.
	[Vector2(0.865, 0.325), Vector2(0.80, 0.45), Vector2(0.72, 0.53), Vector2(0.640, 0.565), Vector2(0.515, 0.620)],
	[Vector2(0.465, 0.415), Vector2(0.50, 0.52), Vector2(0.515, 0.620)],
	[Vector2(0.515, 0.620), Vector2(0.45, 0.66), Vector2(0.37, 0.705), Vector2(0.29, 0.745), Vector2(0.205, 0.705)],
	# The north: the pass roads and the plateau.
	[Vector2(0.545, 0.215), Vector2(0.505, 0.130)],
	[Vector2(0.545, 0.215), Vector2(0.60, 0.27), Vector2(0.65, 0.33), Vector2(0.705, 0.385)],
	[Vector2(0.415, 0.255), Vector2(0.48, 0.225), Vector2(0.545, 0.215)],
	[Vector2(0.415, 0.255), Vector2(0.44, 0.33), Vector2(0.465, 0.415)],
	# The west: the closed road into Vetrenka, the coast road south, the tail.
	[Vector2(0.415, 0.255), Vector2(0.388, 0.272), Vector2(0.355, 0.30), Vector2(0.320, 0.330)],
	[Vector2(0.320, 0.330), Vector2(0.29, 0.31), Vector2(0.265, 0.300)],
	[Vector2(0.318, 0.468), Vector2(0.285, 0.55), Vector2(0.245, 0.63), Vector2(0.205, 0.705)],
	[Vector2(0.205, 0.705), Vector2(0.16, 0.765), Vector2(0.12, 0.81), Vector2(0.085, 0.815)],
	[Vector2(0.318, 0.468), Vector2(0.38, 0.53), Vector2(0.515, 0.620)],
]

## Lesser rivers, all falling from high ground toward the western sea: the
## Orvena water down from the Anera highlands to the Selvara bay, the eastern
## river that drains the Darev steppe into the Kesla, and a short torrent off
## the southern hills across the Kelvet tail.
const RIVERS: Array = [
	[Vector2(0.405, 0.195), Vector2(0.395, 0.27), Vector2(0.375, 0.35), Vector2(0.345, 0.425), Vector2(0.315, 0.455), Vector2(0.285, 0.465)],
	[Vector2(0.925, 0.225), Vector2(0.86, 0.265), Vector2(0.78, 0.32), Vector2(0.69, 0.43), Vector2(0.60, 0.46), Vector2(0.52, 0.47), Vector2(0.443, 0.48)],
	[Vector2(0.275, 0.815), Vector2(0.215, 0.80), Vector2(0.16, 0.785), Vector2(0.105, 0.775)],
]

## Water bodies: [centre, radius in tiles]. The hydro reservoir on the upper
## Kesla, the plateau lakes of Karsen, the coastal lagoon behind the Selvara
## bay, a reservoir under the Sela hills, a mountain lake in the Kelvet tail
## and a steppe lake in Darev.
const LAKES: Array = [
	[Vector2(0.553, 0.150), Vector2(3.0, 1.6)],
	[Vector2(0.488, 0.135), Vector2(2.2, 1.4)],
	[Vector2(0.612, 0.232), Vector2(2.0, 1.3)],
	[Vector2(0.282, 0.515), Vector2(2.6, 1.8)],
	[Vector2(0.590, 0.615), Vector2(2.2, 1.2)],
	[Vector2(0.200, 0.835), Vector2(1.8, 1.2)],
	[Vector2(0.755, 0.455), Vector2(2.8, 1.6)],
]
## Reed marsh: the Kesla delta by Tavri, the coastal wetland behind the
## Selvara lagoon, and a wet bend of the Kesla below the capital.
const MARSHES: Array = [
	[Vector2(0.175, 0.735), Vector2(4.5, 2.2)],
	[Vector2(0.285, 0.565), Vector2(4.5, 2.6)],
	[Vector2(0.395, 0.585), Vector2(3.0, 1.6)],
]
## Protected woodland: forest kept whole in the Kelvet hills, the Anera
## highlands and the Sela uplands.
const PARKS: Array = [
	[Vector2(0.235, 0.805), Vector2(5.5, 2.4)],
	[Vector2(0.435, 0.205), Vector2(4.0, 2.0)],
	[Vector2(0.430, 0.700), Vector2(4.5, 2.0)],
]
## Old fortresses: the Karvel pass fort, the Kavor monastery walls, the
## Meradin frontier citadel and the sea fort on the cape of the tail.
const FORTS: Array[Vector2] = [
	Vector2(0.495, 0.112), Vector2(0.398, 0.243), Vector2(0.925, 0.395), Vector2(0.080, 0.808),
]

const VILLAGE_SPACING := 5
const VILLAGE_CLEARANCE := 5.0
const VILLAGE_SHARE := 0.22


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i((p * Vector2(TileBaker.GRID)).floor())


static func kind_at(tiles: Dictionary, cell: Vector2i) -> int:
	if not TileBaker.in_grid(cell):
		return 0
	return (tiles["kinds"] as PackedByteArray)[cell.y * TileBaker.GRID.x + cell.x]


static func is_home(tiles: Dictionary, cell: Vector2i) -> bool:
	return TileBaker.region_at_tile(tiles, cell) < MapBaker.FOREIGN_REGION


static func is_water(kind: int) -> bool:
	return kind <= KIND_SHALLOWS or kind == KIND_RIVER


## The nearest home land cell touching the sea, as a map point at its centre.
static func coast_snap(tiles: Dictionary, p: Vector2) -> Vector2:
	var start := cell_of(p)
	var best := start
	var best_d := INF
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var c := start + Vector2i(dx, dy)
			if not is_home(tiles, c) or is_water(kind_at(tiles, c)):
				continue
			var shore := false
			for side in TileBaker.SIDES:
				shore = shore or (TileBaker.in_grid(c + side) and kind_at(tiles, c + side) <= KIND_SHALLOWS)
			var d := Vector2(dx, dy).length_squared()
			if shore and d < best_d:
				best_d = d
				best = c
	return (Vector2(best) + Vector2(0.5, 0.5)) / Vector2(TileBaker.GRID)


## Seaward direction from a shore point (unit vector, tile space).
static func seaward(tiles: Dictionary, p: Vector2) -> Vector2:
	var start := cell_of(p)
	var sum := Vector2.ZERO
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var c := start + Vector2i(dx, dy)
			if TileBaker.in_grid(c) and kind_at(tiles, c) <= KIND_SHALLOWS:
				sum += Vector2(dx, dy).normalized() if dx != 0 or dy != 0 else Vector2.ZERO
	return sum.normalized() if sum != Vector2.ZERO else Vector2.LEFT


static func towns(tiles: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for town in TOWNS:
		var point: Vector2 = town["point"]
		if town.get("coast", false):
			point = coast_snap(tiles, point)
		out.append({"name": String(town["name"]), "point": point, "harbour": bool(town.get("harbour", false))})
	return out


## Every harbour on the map: [shore point, seaward unit vector].
static func harbours(tiles: Dictionary, geo: MapGeometry) -> Array:
	var out: Array = []
	for city in geo.cities:
		if HARBOUR_CITIES.has(String(city["name"])):
			var shore := coast_snap(tiles, city["point"])
			out.append([shore, seaward(tiles, shore)])
	for town in towns(tiles):
		if town["harbour"]:
			out.append([town["point"], seaward(tiles, town["point"])])
	return out


## Small unnamed villages: a deterministic scatter over open home land,
## clear of the named places so they read as countryside texture.
static func villages(tiles: Dictionary, geo: MapGeometry) -> PackedVector2Array:
	var places: Array[Vector2] = []
	for city in geo.cities:
		places.append(Vector2(city["point"]) * Vector2(TileBaker.GRID))
	for town in TOWNS:
		places.append(Vector2(town["point"]) * Vector2(TileBaker.GRID))
	var streams := river_cells()
	var out := PackedVector2Array()
	for by in range(0, TileBaker.GRID.y, VILLAGE_SPACING):
		for bx in range(0, TileBaker.GRID.x, VILLAGE_SPACING):
			var block := Vector2i(bx, by)
			if float(TileBaker.cell_hash(block, 31)) / TileBaker.HASH_MASK > VILLAGE_SHARE:
				continue
			var h := TileBaker.cell_hash(block, 37)
			var cell := block + Vector2i(1 + h % (VILLAGE_SPACING - 2), 1 + (h / 7) % (VILLAGE_SPACING - 2))
			var kind := kind_at(tiles, cell)
			if not is_home(tiles, cell) or not (kind in [KIND_GRASS, KIND_FARM, KIND_FALLOW, KIND_HILLS]):
				continue
			var clear := true
			for p in places:
				clear = clear and p.distance_to(Vector2(cell)) > VILLAGE_CLEARANCE
			if clear and not _in_any(Vector2(cell), LAKES) and not _in_any(Vector2(cell), MARSHES) and not streams.has(cell):
				out.append((Vector2(cell) + Vector2(0.5, 0.5)) / Vector2(TileBaker.GRID))
	return out


## Every cell the lesser rivers run through.
static func river_cells() -> Dictionary:
	var out := {}
	for river in RIVERS:
		for cell in TileBaker.line_tiles(PackedVector2Array(river)):
			out[cell] = true
	return out


static func _in_ellipse(cell: Vector2, centre: Vector2, radius: Vector2) -> float:
	var c := centre * Vector2(TileBaker.GRID)
	var d := (cell + Vector2(0.5, 0.5) - c) / radius
	return d.length()


static func _in_any(cell: Vector2, shapes: Array) -> bool:
	for shape in shapes:
		if _in_ellipse(cell, shape[0], shape[1]) <= 1.0:
			return true
	return false


## Dress the shader's data image (R kind, G variant) in place. `offset` is
## where grid cell (0, 0) sits in the image.
static func dress(image: Image, tiles: Dictionary, offset: Vector2i) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.14
	var grid := TileBaker.GRID
	var streams := river_cells()
	for y in grid.y:
		for x in grid.x:
			var cell := Vector2i(x, y)
			if not is_home(tiles, cell):
				continue
			var kind := kind_at(tiles, cell)
			var out := kind
			var variant := -1
			var h := float(TileBaker.cell_hash(cell, 53)) / TileBaker.HASH_MASK
			if kind == KIND_FOREST:
				# Thin the fringes: woods get denser toward their hearts.
				if _neighbours(tiles, cell, KIND_FOREST) < 6 and h < 0.45:
					out = KIND_GRASS if h < 0.3 else KIND_HILLS
			elif kind == KIND_GRASS:
				var n := noise.get_noise_2d(x, y)
				if n > 0.42 or (n > 0.3 and h < 0.4):
					out = KIND_FOREST
			elif kind == KIND_FARM:
				# Field patchwork: staggered blocks of crop, green crop and fallow.
				var block := Vector2i(floori((x + (y / 2) % 2 * 2) / 3.0), y / 2)
				var pick := float(TileBaker.cell_hash(block, 61)) / TileBaker.HASH_MASK
				if pick < 0.18:
					out = KIND_FALLOW
				elif pick < 0.26:
					out = KIND_GRASS
				else:
					variant = 40 if pick < 0.62 else 230
			if kind in LAND_KINDS and _shape_depth(Vector2(cell), PARKS) <= 1.0 and kind != KIND_FARM:
				# Protected woods stay whole: no thinned fringe, no clearings.
				out = KIND_FOREST
			if streams.has(cell) and not is_water(kind):
				# A lesser river runs down from the heights, so it cuts
				# mountain and snow as well as the lowland it reaches.
				out = KIND_RIVER
			elif kind in LAND_KINDS:
				var lake := _shape_depth(Vector2(cell), LAKES)
				if lake <= 1.0:
					out = KIND_SEA if lake < 0.6 else KIND_SHALLOWS
				elif _shape_depth(Vector2(cell), MARSHES) <= 1.0:
					out = KIND_SHALLOWS if h < 0.42 else (KIND_GRASS if h < 0.8 else KIND_FALLOW)
			if out == kind and variant < 0:
				continue
			var c := image.get_pixelv(cell + offset)
			c.r8 = out
			if variant >= 0:
				c.g8 = variant
			image.set_pixelv(cell + offset, c)


static func _shape_depth(cell: Vector2, shapes: Array) -> float:
	var best := INF
	for shape in shapes:
		best = minf(best, _in_ellipse(cell, shape[0], shape[1]))
	return best


static func _neighbours(tiles: Dictionary, cell: Vector2i, kind: int) -> int:
	var n := 0
	for d in MapLines.AROUND:
		n += 1 if kind_at(tiles, cell + d) == kind else 0
	return n
