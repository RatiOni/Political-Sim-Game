class_name AsciiTerrain
extends ColorRect

## The map's visible surface: Ardenia as an animated character grid
## (`shaders/ascii_terrain.gdshader`). It is a *view* of the tile layers, not
## a replacement: `ArdeniaMap` still fills the terrain, growth and smoke
## TileMapLayers (tests and the growth painter work on those), and this node
## re-reads them a few times a second into a one-texel-per-tile data texture.
## The animation itself is all in the shader, so it runs at frame rate.

const SHADER := preload("res://shaders/ascii_terrain.gdshader")
const REFRESH_SECONDS := 0.2
## Every glyph is drawn at exactly this many screen pixels, whatever the
## zoom: crisp, legible characters, with more of them as the map grows.
const GLYPH_PX := Vector2(6, 8)
## Tiles of mirrored, dimmed surroundings drawn around the grid so a panel
## wider than the map shows more sea and frontier instead of empty bands.
const PAD := Vector2i(96, 48)

const OVERLAY := {
	"house": 3, "house_lit": 4, "tower": 5, "capital": 6, "barricade": 7,
	"road": 8, "road_v": 9, "road_d1": 10, "road_d2": 11,
	"paved": 12, "paved_v": 13, "paved_d1": 14, "paved_d2": 15,
	"rail": 16, "rail_v": 17, "rail_d1": 18, "rail_d2": 19,
}

var _map: ArdeniaMap
var _base: Image
var _data: ImageTexture
var _names_by_coords: Dictionary = {}
var _last_key := -1


func _init() -> void:
	name = "Ascii"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("glyphs", ImageTexture.create_from_image(AsciiGlyphs.strip()))
	mat.set_shader_parameter("glyph_count", float(AsciiGlyphs.ROWS.size()))
	mat.set_shader_parameter("grid", Vector2(TileBaker.GRID + PAD * 2))
	material = mat


## Bake the static terrain once and start following the growth layers.
func build(map: ArdeniaMap, tiles: Dictionary) -> void:
	_map = map
	var index := TileArt.index()
	for key in index:
		_names_by_coords[Vector2i(index[key][0], index[key][1])] = key
	var kinds: PackedByteArray = tiles["kinds"]
	var variants: PackedByteArray = tiles["variants"]
	var grid := TileBaker.GRID
	var home_count := map._geo.region_ids.size() if map._geo != null else MapBaker.FOREIGN_REGION
	_base = Image.create_empty(grid.x + PAD.x * 2, grid.y + PAD.y * 2, false, Image.FORMAT_RGBA8)
	for y in _base.get_height():
		for x in _base.get_width():
			# Outside the grid, mirror it back in; Ardenia's own land never
			# repeats, so mirrored home cells are drawn as foreign ground.
			var sx := _reflect(x - PAD.x, grid.x)
			var sy := _reflect(y - PAD.y, grid.y)
			var i := sy * grid.x + sx
			var region := TileBaker.region_at_tile(tiles, Vector2i(sx, sy))
			var inside := x - PAD.x == sx and y - PAD.y == sy
			var home := region != MapBaker.FOREIGN_REGION and (inside or region >= home_count)
			var kind := kinds[i]
			if not inside and (kind == MapDetails.KIND_FARM or kind == MapDetails.KIND_FALLOW):
				# Mirrored fields would read as stray stripes beyond the frontier.
				kind = MapDetails.KIND_GRASS
			if x < PAD.x:
				# The only sea is west: open water all the way out.
				kind = 0
				home = true
			_base.set_pixel(x, y, Color8(kind, (variants[i] * 64 + TileBaker.cell_hash(Vector2i(sx, sy))) % 256, 0, 255 if home else 0))
	MapDetails.dress(_base, tiles, PAD)
	_data = ImageTexture.create_from_image(_base)
	(material as ShaderMaterial).set_shader_parameter("cells", _data)
	var timer := Timer.new()
	timer.wait_time = REFRESH_SECONDS
	timer.autostart = true
	timer.timeout.connect(refresh)
	add_child(timer)
	refresh()


## Match the tile level and on-screen zoom. Zooming in reveals more
## characters, not fatter ones.
func set_level(tile_px: int, screen_px_per_tile: float) -> void:
	position = -Vector2(PAD * tile_px)
	size = Vector2((TileBaker.GRID + PAD * 2) * tile_px)
	(material as ShaderMaterial).set_shader_parameter("sub", Vector2.ONE * screen_px_per_tile / GLYPH_PX)


func set_dusk(on: bool) -> void:
	(material as ShaderMaterial).set_shader_parameter("dusk", 1.0 if on else 0.0)


func refresh() -> void:
	if _map == null or _base == null:
		return
	var growth := _map.growth_layer.get_used_cells()
	var smoke := _map.smoke_layer.get_used_cells()
	var key := hash([growth, smoke.size()])
	for cell in growth:
		key = hash([key, _map.growth_layer.get_cell_atlas_coords(cell)])
	if key == _last_key:
		return
	_last_key = key
	var image := _base.duplicate() as Image
	for cell in growth:
		_mark(image, cell, overlay_code(_names_by_coords.get(_map.growth_layer.get_cell_atlas_coords(cell), "")))
	for cell in smoke:
		_mark(image, cell, overlay_code(_names_by_coords.get(_map.smoke_layer.get_cell_atlas_coords(cell), "")))
	_data.update(image)


static func overlay_code(sprite: String) -> int:
	if OVERLAY.has(sprite):
		return OVERLAY[sprite]
	if sprite.begins_with("farm_"):
		return 1
	if sprite.begins_with("fallow_"):
		return 2
	if sprite.begins_with("fire_"):
		return 20
	if sprite.begins_with("smoke_mid_"):
		return 21
	if sprite.begins_with("smoke_top_"):
		return 22
	return 0


static func _mark(image: Image, cell: Vector2i, code: int) -> void:
	if code == 0 or not Rect2i(Vector2i.ZERO, TileBaker.GRID).has_point(cell):
		return
	if code >= 8 and code <= 19:
		# Routes are drawn as continuous lines by `MapLines.routes`, which
		# reads the same growth state; a glyph copy would double them.
		return
	var at := cell + PAD
	var c := image.get_pixelv(at)
	if code == 1:
		# Farmed land keeps its patchwork: some blocks show as green crop.
		var block := Vector2i(floori((cell.x + (cell.y / 2) % 2 * 2) / 3.0), cell.y / 2)
		if float(TileBaker.cell_hash(block, 67)) / TileBaker.HASH_MASK < 0.4:
			c.r8 = MapDetails.KIND_FARM
			c.g8 = 230
			code = 0
	c.b8 = code
	image.set_pixelv(at, c)


static func _reflect(v: int, n: int) -> int:
	if v < 0:
		v = -v - 1
	if v >= n:
		v = 2 * n - v - 1
	return clampi(v, 0, n - 1)
