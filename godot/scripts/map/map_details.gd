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
	{"name": "Ostrena", "point": Vector2(0.08, 0.25), "coast": true, "harbour": true},
	{"name": "Kavor", "point": Vector2(0.245, 0.355)},
	{"name": "Karvel", "point": Vector2(0.455, 0.19)},
	{"name": "Lestara", "point": Vector2(0.535, 0.31)},
	{"name": "Ordel", "point": Vector2(0.28, 0.42)},
	{"name": "Rovets", "point": Vector2(0.53, 0.71)},
	{"name": "Meradin", "point": Vector2(0.925, 0.69)},
	{"name": "Azren", "point": Vector2(0.94, 0.49)},
]

## Ports on the existing city list (by name).
const HARBOUR_CITIES: Array[String] = ["Tavri"]

## Secondary roads: the country's ordinary road net between the trunk routes.
const ROADS: Array = [
	[Vector2(0.74, 0.40), Vector2(0.765, 0.51), Vector2(0.85, 0.58)],
	[Vector2(0.85, 0.58), Vector2(0.89, 0.65), Vector2(0.925, 0.69)],
	[Vector2(0.85, 0.58), Vector2(0.90, 0.52), Vector2(0.94, 0.49)],
	[Vector2(0.85, 0.58), Vector2(0.70, 0.66), Vector2(0.53, 0.71), Vector2(0.42, 0.68)],
	[Vector2(0.585, 0.475), Vector2(0.56, 0.60), Vector2(0.53, 0.71)],
	[Vector2(0.48, 0.28), Vector2(0.455, 0.19)],
	[Vector2(0.48, 0.28), Vector2(0.535, 0.31)],
	[Vector2(0.48, 0.28), Vector2(0.60, 0.30), Vector2(0.74, 0.40)],
	[Vector2(0.29, 0.31), Vector2(0.38, 0.265), Vector2(0.48, 0.28)],
	[Vector2(0.29, 0.31), Vector2(0.245, 0.355)],
	[Vector2(0.245, 0.355), Vector2(0.17, 0.35), Vector2(0.12, 0.33)],
	[Vector2(0.12, 0.33), Vector2(0.08, 0.25)],
	[Vector2(0.27, 0.53), Vector2(0.24, 0.66), Vector2(0.23, 0.82)],
	[Vector2(0.27, 0.53), Vector2(0.35, 0.62), Vector2(0.42, 0.68)],
]

## Water bodies: [centre, radius in tiles]. A hydro reservoir on the upper
## Kesla (Karsen's hydro stations), a highland tarn, a steppe lake in Darev.
const LAKES: Array = [
	[Vector2(0.51, 0.243), Vector2(3.2, 1.8)],
	[Vector2(0.355, 0.235), Vector2(2.4, 1.6)],
	[Vector2(0.78, 0.71), Vector2(3.0, 1.8)],
	[Vector2(0.64, 0.58), Vector2(1.8, 1.2)],
]
## Reed marsh: the Kesla delta below Tavri and a wet bend in the Sela.
const MARSHES: Array = [
	[Vector2(0.17, 0.855), Vector2(6.0, 3.0)],
	[Vector2(0.35, 0.735), Vector2(4.5, 2.2)],
	[Vector2(0.46, 0.655), Vector2(3.0, 1.6)],
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
			if clear and not _in_any(Vector2(cell), LAKES) and not _in_any(Vector2(cell), MARSHES):
				out.append((Vector2(cell) + Vector2(0.5, 0.5)) / Vector2(TileBaker.GRID))
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
			if kind in LAND_KINDS:
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
