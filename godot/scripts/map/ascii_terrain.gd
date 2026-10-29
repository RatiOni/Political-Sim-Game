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
	mat.set_shader_parameter("grid", Vector2(TileBaker.GRID))
	material = mat


## Bake the static terrain once and start following the growth layers.
func build(map: ArdeniaMap, tiles: Dictionary) -> void:
	_map = map
	var index := TileArt.index()
	for key in index:
		_names_by_coords[Vector2i(index[key][0], index[key][1])] = key
	var kinds: PackedByteArray = tiles["kinds"]
	var variants: PackedByteArray = tiles["variants"]
	_base = Image.create_empty(TileBaker.GRID.x, TileBaker.GRID.y, false, Image.FORMAT_RGBA8)
	for y in TileBaker.GRID.y:
		for x in TileBaker.GRID.x:
			var i := y * TileBaker.GRID.x + x
			var home := TileBaker.region_at_tile(tiles, Vector2i(x, y)) != MapBaker.FOREIGN_REGION
			_base.set_pixel(x, y, Color8(kinds[i], (variants[i] * 64 + TileBaker.cell_hash(Vector2i(x, y))) % 256, 0, 255 if home else 0))
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
	size = Vector2(TileBaker.GRID * tile_px)
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
	if code == 0 or not Rect2i(Vector2i.ZERO, image.get_size()).has_point(cell):
		return
	var c := image.get_pixel(cell.x, cell.y)
	c.b8 = code
	image.set_pixel(cell.x, cell.y, c)
