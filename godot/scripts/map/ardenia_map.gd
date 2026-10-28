extends Control
class_name ArdeniaMap

signal region_selected(region_id: String)

const NATIVE := Vector2(MapLines.SIZE)
const BORDERS_PATH := "res://data/map/baked/borders.json"
const UNAVAILABLE_TEXT := "Map data unavailable"
const HOVER_WIDTH := 1.0
const SELECTION_WIDTH := 2.0
const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const CORNERS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]

var tiles_path := TileBaker.TILES_PATH
var regions: Dictionary = {}
var polygons: Dictionary = {}
var selected_id := ""
var hovered_id := ""
var unavailable := false
var terrain_layer := TileMapLayer.new()
var growth_layer := TileMapLayer.new()
var lines_rect := TextureRect.new()
var _sea := ColorRect.new()
var _canvas := Node2D.new()
var _highlight := Node2D.new()
var _labels := MapLabels.new()
var _notice := Label.new()
var _geo: MapGeometry
var _tiles: Dictionary = {}
var _outlines: Dictionary = {}
var _cells: Dictionary = {}
var _scale := 1.0
var _offset := Vector2.ZERO
var _day_texture: Texture2D
var _dusk_texture: Texture2D
var _lines: Dictionary = {}
var _dusk := false
var _weight := 1


func _init() -> void:
	_build_nodes()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(_layout)
	mouse_exited.connect(func(): hovered_id = ""; _redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	unavailable = not _load()
	_notice.visible = unavailable
	_canvas.visible = not unavailable
	_labels.visible = not unavailable
	_layout()


func _build_nodes() -> void:
	_sea.color = MapPalette.DAY[MapPalette.INK]
	_sea.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sea.show_behind_parent = true
	_sea.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_sea)
	_canvas.show_behind_parent = true
	add_child(_canvas)
	for layer in [terrain_layer, growth_layer]:
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_canvas.add_child(layer)
	terrain_layer.name = "Terrain"
	growth_layer.name = "Growth"
	lines_rect.name = "Lines"
	lines_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	lines_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines_rect.size = NATIVE
	_canvas.add_child(lines_rect)
	_highlight.draw.connect(_draw_highlight)
	_canvas.add_child(_highlight)
	_labels.name = "Labels"
	_labels.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_labels)
	_notice.name = "Unavailable"
	_notice.text = UNAVAILABLE_TEXT
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notice.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_notice)


func _load() -> bool:
	_geo = MapGeometry.load_world()
	_tiles = TileBaker.load_tiles(tiles_path)
	var tileset := TileArt.load_tileset()
	var borders: Variant = JSON.parse_string(FileAccess.get_file_as_string(BORDERS_PATH))
	if _geo == null or _tiles.is_empty() or tileset == null or not (borders is Dictionary) or not (borders.get("outlines") is Dictionary):
		push_error("ArdeniaMap: map data unavailable")
		return false
	_outlines = borders["outlines"]
	terrain_layer.tile_set = tileset
	growth_layer.tile_set = tileset
	_fill_terrain()
	_day_texture = atlas_texture()
	_dusk_texture = ImageTexture.create_from_image(TileArt.dusk_atlas(_day_texture.get_image()))
	_labels.cities = _geo.cities
	_labels.region_points = _region_centres()
	_labels.to_local = map_to_local
	return true


func _fill_terrain() -> void:
	var cells := TileArt.index()
	var kinds: PackedByteArray = _tiles["kinds"]
	var variants: PackedByteArray = _tiles["variants"]
	for id in _geo.region_ids:
		_cells[id] = {}
	for y in TileBaker.GRID.y:
		for x in TileBaker.GRID.x:
			var i := y * TileBaker.GRID.x + x
			var region := TileBaker.region_at_tile(_tiles, Vector2i(x, y))
			var kind := TileArt.KINDS[kinds[i]]
			var key := TileArt.foreign_key(kind, variants[i]) if region == MapBaker.FOREIGN_REGION else TileArt.variant_key(kind, variants[i])
			terrain_layer.set_cell(Vector2i(x, y), 0, Vector2i(cells[key][0], cells[key][1]))
			if region < _geo.region_ids.size():
				_cells[_geo.region_ids[region]][Vector2i(x, y)] = true


func _region_centres() -> Dictionary:
	var out := {}
	for id in _cells:
		var sum := Vector2.ZERO
		for cell in _cells[id]:
			sum += Vector2(cell) + Vector2(0.5, 0.5)
		out[id] = sum / maxf(1.0, _cells[id].size()) / Vector2(TileBaker.GRID)
	return out


func atlas_texture() -> Texture2D:
	if terrain_layer.tile_set == null:
		return null
	return (terrain_layer.tile_set.get_source(0) as TileSetAtlasSource).texture


func set_dusk(on: bool) -> void:
	if unavailable:
		return
	(terrain_layer.tile_set.get_source(0) as TileSetAtlasSource).texture = _dusk_texture if on else _day_texture
	_dusk = on
	_apply_lines()


func _apply_lines() -> void:
	if unavailable:
		return
	var key := Vector2i(_weight, int(_dusk))
	if not _lines.has(key):
		_lines[key] = ImageTexture.create_from_image(MapLines.build(_tiles, _geo, MapPalette.DUSK if _dusk else MapPalette.DAY, _weight))
	lines_rect.texture = _lines[key]


func _layout() -> void:
	var fit := minf(size.x / NATIVE.x, size.y / NATIVE.y)
	_scale = floorf(fit) if fit >= 1.0 else maxf(fit, 0.01)
	_offset = ((size - NATIVE * _scale) / 2.0).round()
	_canvas.position = _offset
	_canvas.scale = Vector2(_scale, _scale)
	_labels.zoom = maxi(1, int(_scale))
	_weight = 1 if _scale >= 1.0 else ceili(1.0 / _scale)
	_apply_lines()
	polygons.clear()
	for id in _outlines:
		var ring := PackedVector2Array()
		for p in _outlines[id]:
			ring.append(map_to_local(Vector2(float(p[0]), float(p[1]))))
		polygons[String(id)] = ring
	_redraw()


func _redraw() -> void:
	queue_redraw()
	_highlight.queue_redraw()
	_labels.queue_redraw()


func map_to_local(p: Vector2) -> Vector2:
	return _offset + p * NATIVE * _scale


func local_to_map(p: Vector2) -> Vector2:
	return (p - _offset) / (NATIVE * _scale)


func _point(value: Array) -> Vector2:
	return map_to_local(Vector2(float(value[0]), float(value[1])) / 100.0)


func apply_snapshot(values: Array, selection: String) -> void:
	regions.clear()
	for region in values:
		if region is Dictionary and region.has("id"):
			regions[str(region["id"])] = region.duplicate(true)
	selected_id = selection if polygons.has(selection) else ""
	_redraw()


func select_region(region_id: String) -> void:
	if not polygons.has(region_id):
		return
	selected_id = region_id
	_redraw()
	region_selected.emit(region_id)


func region_at(position: Vector2) -> String:
	if unavailable:
		return ""
	var m := local_to_map(position)
	var cell := Vector2i((m * Vector2(TileBaker.GRID)).floor())
	var index := TileBaker.region_at_tile(_tiles, cell)
	return _geo.region_ids[index] if index < _geo.region_ids.size() else ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var id := region_at(event.position)
		if id != hovered_id:
			hovered_id = id
			_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		grab_focus()
		select_region(region_at(event.position))
		accept_event()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		var ids := polygons.keys()
		if ids.is_empty():
			return
		var direction := -1 if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up") else 1
		select_region(ids[posmod(ids.find(selected_id) + direction, ids.size())])
		accept_event()


func _draw() -> void:
	if has_focus():
		draw_style_box(get_theme_stylebox("focus", "ArdeniaMap"), Rect2(Vector2(2, 2), size - Vector2(4, 4)))


func _draw_highlight() -> void:
	if _cells.has(hovered_id) and hovered_id != selected_id:
		_outline(_cells[hovered_id], HOVER_WIDTH * _weight, MapPalette.DAY[MapPalette.SNOW])
	if _cells.has(selected_id):
		_outline(_cells[selected_id], SELECTION_WIDTH * _weight, MapPalette.DAY[MapPalette.GOLD])


func _outline(cells: Dictionary, width: float, colour: Color) -> void:
	var tile := float(TileBaker.TILE)
	for cell in cells:
		var origin := Vector2(cell) * tile
		for side in SIDES:
			if cells.has(cell + side):
				continue
			var at := origin + Vector2(tile - width if side.x > 0 else 0.0, tile - width if side.y > 0 else 0.0)
			var extent := Vector2(width if side.x != 0 else tile, width if side.y != 0 else tile)
			_highlight.draw_rect(Rect2(at, extent), colour)
		for corner in CORNERS:
			if cells.has(cell + Vector2i(corner.x, 0)) and cells.has(cell + Vector2i(0, corner.y)) and not cells.has(cell + corner):
				var at := origin + Vector2(tile - width if corner.x > 0 else 0.0, tile - width if corner.y > 0 else 0.0)
				_highlight.draw_rect(Rect2(at, Vector2(width, width)), colour)
