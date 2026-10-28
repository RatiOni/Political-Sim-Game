class_name TileArt
extends RefCounted

const CELL := 8
const VARIANTS := 4
const COLUMNS := 16
const KINDS: Array[String] = ["deep_sea", "sea", "shallows", "sand", "grass", "farm", "fallow", "forest", "hills", "mountain", "snow", "river"]
const SPRITES: Array[String] = ["house", "house_lit", "tower", "capital", "tree", "crops", "road", "paved", "rail", "barricade", "smoke_0", "smoke_1", "smoke_2"]
const ATLAS_PNG := "res://data/map/tile_atlas.png"
const ATLAS_JSON := "res://data/map/tile_atlas.json"
const MICRO_SHEET := "res://assets/pixel/kenney_micro_roguelike.png"
const MICRO_BACKGROUND := Color8(34, 35, 35)
const FOREIGN_DIM := 0.2

const KENNEY := {
	"house": [Vector2i(5, 7), [MapPalette.ROOF, MapPalette.ROOF, MapPalette.INK, MapPalette.WALL]],
	"house_lit": [Vector2i(5, 7), [MapPalette.ROOF, MapPalette.ROOF, MapPalette.LIT, MapPalette.WALL]],
	"tower": [Vector2i(6, 7), [MapPalette.ROCK_DARK, MapPalette.ROCK, MapPalette.WALL]],
	"tree": [Vector2i(4, 5), [MapPalette.TRUNK, MapPalette.TRUNK, MapPalette.FOREST_DARK, MapPalette.FOREST]],
	"crops": [Vector2i(5, 4), [MapPalette.FARM_GREEN, MapPalette.FARM_GREEN, MapPalette.FARM]],
	"barricade": [Vector2i(12, 2), [MapPalette.ROAD, MapPalette.ROAD, MapPalette.CEASEFIRE]],
}

const DRAWN_LEGEND := {
	"g": MapPalette.GOLD, "d": MapPalette.GOLD_DARK, "r": MapPalette.ROAD, "k": MapPalette.ROCK_DARK,
	"l": MapPalette.ROCK_LIGHT, "m": MapPalette.ROCK, "#": MapPalette.RAIL,
}

const DRAWN := {
	"capital": ["...g....", "..gdg...", ".g.d.g..", "gdddddg.", ".g.d.g..", "..gdg...", "...g....", "........"],
	"road": ["........", "........", "........", "........", "........", "rr.rr.rr", "........", "........"],
	"paved": ["........", "........", "........", "kkkkkkkk", "kllkkllk", "kkkkkkkk", "........", "........"],
	"rail": ["........", "#..#..#.", "########", "#..#..#.", "........", "........", "........", "........"],
	"smoke_0": ["........", "........", "........", "........", "...ll...", "..llll..", "..lmll..", "...ll..."],
	"smoke_1": ["........", "........", "....ll..", "...llll.", "...lmll.", "....ll..", "........", "........"],
	"smoke_2": ["...mm...", "..mllm..", "...mm...", "........", "........", "........", "........", "........"],
}


static func variant_key(kind: String, variant: int) -> String:
	return "%s_%d" % [kind, variant]


static func foreign_key(kind: String, variant: int) -> String:
	return "foreign_%s_%d" % [kind, variant]


static func cell_names() -> Array[String]:
	var names: Array[String] = []
	for kind in KINDS:
		for v in VARIANTS:
			names.append(variant_key(kind, v))
	names.append_array(SPRITES)
	for kind in KINDS:
		for v in VARIANTS:
			names.append(foreign_key(kind, v))
	return names


static func index() -> Dictionary:
	var out := {}
	var names := cell_names()
	for i in names.size():
		out[names[i]] = [i % COLUMNS, i / COLUMNS]
	return out


static func build_atlas() -> Image:
	var names := cell_names()
	var rows := ceili(float(names.size()) / COLUMNS)
	var atlas := Image.create_empty(COLUMNS * CELL, rows * CELL, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	var sheet: Image = load(MICRO_SHEET).get_image()
	sheet.convert(Image.FORMAT_RGBA8)
	var kind_count := KINDS.size() * VARIANTS
	var foreign_start := kind_count + SPRITES.size()
	for i in names.size():
		var origin := Vector2i(i % COLUMNS, i / COLUMNS) * CELL
		if i < kind_count:
			_blit(atlas, ground(KINDS[i / VARIANTS], i % VARIANTS), origin)
		elif i >= foreign_start:
			var k := i - foreign_start
			_blit_foreign(atlas, ground(KINDS[k / VARIANTS], k % VARIANTS), origin)
		elif KENNEY.has(names[i]):
			_blit(atlas, recolour(sheet, KENNEY[names[i]][0], KENNEY[names[i]][1]), origin)
		else:
			_blit(atlas, drawn(DRAWN[names[i]]), origin)
	return atlas


static func load_tileset() -> TileSet:
	var texture: Texture2D = load(ATLAS_PNG)
	if texture == null:
		return null
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(CELL, CELL)
	for coords in index().values():
		source.create_tile(Vector2i(coords[0], coords[1]))
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(CELL, CELL)
	tileset.add_source(source)
	return tileset


static func _blit(atlas: Image, cell: PackedInt32Array, origin: Vector2i) -> void:
	for p in CELL * CELL:
		if cell[p] >= 0:
			atlas.set_pixelv(origin + Vector2i(p % CELL, p / CELL), MapPalette.DAY[cell[p]])

static func _blit_foreign(atlas: Image, cell: PackedInt32Array, origin: Vector2i) -> void:
	for p in CELL * CELL:
		var day := MapPalette.DAY[cell[p]]
		atlas.set_pixelv(origin + Vector2i(p % CELL, p / CELL), MapPalette.FOREIGN[MapPalette.nearest_foreign(day.darkened(FOREIGN_DIM))])


static func dusk_atlas(day: Image) -> Image:
	var to_dusk := {}
	for i in MapPalette.DAY.size():
		to_dusk[MapPalette.DAY[i].to_rgba32()] = MapPalette.DUSK[i]
	for i in MapPalette.FOREIGN.size():
		to_dusk[MapPalette.FOREIGN[i].to_rgba32()] = MapPalette.FOREIGN_DUSK[i]
	var out := day.duplicate() as Image
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a > 0.0:
				out.set_pixel(x, y, to_dusk.get(c.to_rgba32(), c))
	return out



static func recolour(sheet: Image, at: Vector2i, ramp: Array) -> PackedInt32Array:
	var source: Array[Color] = []
	var tones := {}
	for p in CELL * CELL:
		var c := sheet.get_pixelv(at * CELL + Vector2i(p % CELL, p / CELL))
		source.append(c)
		if c.a > 0.5 and not c.is_equal_approx(MICRO_BACKGROUND):
			tones[c.to_rgba32()] = c.get_luminance()
	var ranked: Array = tones.keys()
	ranked.sort_custom(func(a: int, b: int) -> bool: return tones[a] < tones[b] or (tones[a] == tones[b] and a < b))
	var out := PackedInt32Array()
	for c in source:
		var rank := ranked.find(c.to_rgba32())
		out.append(-1 if rank < 0 else int(ramp[rank * ramp.size() / ranked.size()]))
	return out


static func drawn(rows: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for y in CELL:
		for x in CELL:
			out.append(int(DRAWN_LEGEND.get(rows[y][x], -1)))
	return out


static func _hash(x: int, y: int, s: int = 0) -> float:
	var n := (x * 73856093) ^ (y * 19349663) ^ (s * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	return float((n >> 8) & 0xFFFF) / 65535.0


static func ground(kind: String, variant: int) -> PackedInt32Array:
	var salt := KINDS.find(kind) * 16 + variant
	var v := variant * 0.25 + 0.125
	var out := PackedInt32Array()
	for y in CELL:
		for x in CELL:
			out.append(_ground_pixel(kind, variant, v, x, y, _hash(x + salt * CELL, y, 3)))
	return out


static func _wave(x: int, v: float, threshold: float) -> bool:
	return (x + int(v * 8)) % 8 < 3 and v > threshold


static func _ground_pixel(kind: String, variant: int, v: float, x: int, y: int, h: float) -> int:
	match kind:
		"deep_sea":
			if y == 3 and _wave(x, v, 0.8):
				return MapPalette.SEA
			return MapPalette.DEEP_SEA if h > 0.08 else MapPalette.SEA
		"sea":
			if y == 3 and _wave(x, v, 0.6):
				return MapPalette.WAVE
			return MapPalette.DEEP_SEA if variant % 2 == 0 or h > 0.2 else MapPalette.SEA
		"shallows":
			if y == 4 and _wave(x, v, 0.5):
				return MapPalette.WAVE
			return MapPalette.SHALLOWS if h > 0.15 else MapPalette.SEA
		"sand":
			return MapPalette.SAND if h > 0.2 else MapPalette.SAND_DARK
		"farm":
			return _field(variant, x, y, [MapPalette.FARM, MapPalette.FARM_GREEN], MapPalette.FARM_DARK)
		"fallow":
			return _field(variant, x, y, [MapPalette.FARM_DARK, MapPalette.SAND_DARK], MapPalette.TRUNK)
		"forest":
			return _forest(variant, x, y)
		"hills":
			if (y == 5 and x > 1 and x < 7) or (y == 4 and x > 2 and x < 6):
				return MapPalette.HILL_DARK
			return MapPalette.HILL if h > 0.25 else MapPalette.GRASS_DARK
		"mountain":
			return _peak(x, y, false, h)
		"snow":
			return _peak(x, y, true, h)
		"river":
			if absi(x - 3) <= 1 or (absi(y - 3) <= 1 and x > 1 and x < 6):
				return MapPalette.RIVER
	return MapPalette.GRASS if h > 0.18 else (MapPalette.GRASS_DARK if h > 0.06 else MapPalette.GRASS_LIGHT)


static func _field(variant: int, x: int, y: int, crops: Array, furrow: int) -> int:
	if x == 7 or y == 7:
		return MapPalette.GRASS_DARK
	var checkered := variant % 2 == 1
	var stripe := (y + (x if checkered else 0)) % 2 == 0
	var crop: int = crops[variant / 2]
	return crop if stripe else furrow


const TREE := [[0, 0, 0, 1, 1, 0, 0, 0], [0, 0, 1, 1, 1, 1, 0, 0], [0, 1, 1, 1, 1, 1, 1, 0], [0, 0, 0, 2, 2, 0, 0, 0]]


static func _forest(variant: int, x: int, y: int) -> int:
	var top := 1 if variant % 2 == 0 else 3
	if y < top or y >= top + 4:
		return MapPalette.FOREST_DARK
	var t: int = TREE[y - top][(x + variant * 2) % 8]
	return MapPalette.FOREST if t == 1 else (MapPalette.TRUNK if t == 2 else MapPalette.FOREST_DARK)


static func _peak(x: int, y: int, snowcap: bool, h: float) -> int:
	if y < 1 or absi(x - 4) > y / 2 or (y == 7 and not snowcap):
		return MapPalette.ROCK if h < 0.1 else MapPalette.ROCK_DARK
	if snowcap and y < 5:
		return MapPalette.SNOW if x <= 4 else MapPalette.SNOW_SHADE
	return MapPalette.ROCK if x >= 4 else MapPalette.ROCK_LIGHT
