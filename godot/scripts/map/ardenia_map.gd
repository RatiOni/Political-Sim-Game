extends Control
class_name ArdeniaMap

signal region_selected(region_id: String)

const BORDERS_PATH := "res://data/map/baked/borders.json"
const UNAVAILABLE_TEXT := "Map data unavailable"
const HOVER_WIDTH := 1.0
const SELECTION_WIDTH := 2.0
const DRAG_THRESHOLD := 4.0
const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const CORNERS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]

var tiles_path := TileBaker.TILES_PATH
var regions: Dictionary = {}
var polygons: Dictionary = {}
var selected_id := ""
var hovered_id := ""
var unavailable := false
var tile_px := TileArt.CELL
var zoom := 1
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
var _centres: Dictionary = {}
var _tilesets: Dictionary = {}
var _day_textures: Dictionary = {}
var _dusk_textures: Dictionary = {}
var _lines: Dictionary = {}
var _dusk := false
var _offset := Vector2.ZERO
var _focus := Vector2(0.5, 0.5)
var _press_at := Vector2.ZERO
var _pressing := false
var _dragging := false


static func choose_level(panel: Vector2) -> Vector2i:
	for px in TileArt.SIZES:
		var canvas := Vector2(TileBaker.GRID * px)
		var k := floori(minf(panel.x / canvas.x, panel.y / canvas.y))
		if k >= 1:
			return Vector2i(px, k)
	return Vector2i(TileArt.SIZES[-1], 1)


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
	clip_contents = true
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
	for px in TileArt.SIZES:
		var tileset := TileArt.load_tileset(px)
		if tileset == null:
			push_error("ArdeniaMap: the %d px tile set is missing" % px)
			return false
		_tilesets[px] = tileset
		_day_textures[px] = _source(tileset).texture
		_dusk_textures[px] = ImageTexture.create_from_image(TileArt.dusk_atlas(_day_textures[px].get_image()))
	var borders: Variant = JSON.parse_string(FileAccess.get_file_as_string(BORDERS_PATH))
	if _geo == null or _tiles.is_empty() or not (borders is Dictionary) or not (borders.get("outlines") is Dictionary):
		push_error("ArdeniaMap: map data unavailable")
		return false
	_outlines = borders["outlines"]
	_fill_terrain()
	_centres = _region_centres()
	_labels.cities = _geo.cities
	_labels.region_points = _centres
	_labels.to_local = map_to_local
	return true


static func _source(tileset: TileSet) -> TileSetAtlasSource:
	return tileset.get_source(tileset.get_source_id(0)) as TileSetAtlasSource


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
	return _source(terrain_layer.tile_set).texture


func set_dusk(on: bool) -> void:
	if unavailable:
		return
	_dusk = on
	for px in _tilesets:
		_source(_tilesets[px]).texture = _dusk_textures[px] if on else _day_textures[px]
	_apply_lines()


func _apply_lines() -> void:
	if unavailable:
		return
	var key := Vector2i(tile_px, int(_dusk))
	if not _lines.has(key):
		_lines[key] = ImageTexture.create_from_image(MapLines.build(_tiles, _geo, MapPalette.DUSK if _dusk else MapPalette.DAY, tile_px))
	lines_rect.texture = _lines[key]
	lines_rect.size = Vector2(MapLines.canvas_size(tile_px))


func _layout() -> void:
	var level := choose_level(size)
	if unavailable:
		return
	if level.x != tile_px or terrain_layer.tile_set == null:
		tile_px = level.x
		terrain_layer.tile_set = _tilesets[tile_px]
		growth_layer.tile_set = _tilesets[tile_px]
		_apply_lines()
	zoom = level.y
	_canvas.scale = Vector2(zoom, zoom)
	_labels.zoom = zoom
	_place()


func canvas_extent() -> Vector2:
	return Vector2(TileBaker.GRID * tile_px * zoom)


func _place() -> void:
	var extent := canvas_extent()
	var wanted := (size / 2.0 - _focus * extent).round()
	for axis in 2:
		if extent[axis] <= size[axis]:
			wanted[axis] = roundf((size[axis] - extent[axis]) / 2.0)
		else:
			wanted[axis] = clampf(wanted[axis], size[axis] - extent[axis], 0.0)
	_offset = wanted
	_focus = (size / 2.0 - _offset) / extent
	_canvas.position = _offset
	polygons.clear()
	for id in _outlines:
		var ring := PackedVector2Array()
		for p in _outlines[id]:
			ring.append(map_to_local(Vector2(float(p[0]), float(p[1]))))
		polygons[String(id)] = ring
	_redraw()


func pan_by(delta: Vector2) -> void:
	if unavailable:
		return
	_focus -= delta / canvas_extent()
	_place()


func centre_on(map_point: Vector2) -> void:
	if unavailable:
		return
	_focus = map_point
	_place()


func _redraw() -> void:
	queue_redraw()
	_highlight.queue_redraw()
	_labels.queue_redraw()


func map_to_local(p: Vector2) -> Vector2:
	return _offset + p * canvas_extent()


func local_to_map(p: Vector2) -> Vector2:
	return (p - _offset) / canvas_extent()


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
	centre_on(_centres[region_id])
	region_selected.emit(region_id)


func region_at(position: Vector2) -> String:
	if unavailable:
		return ""
	var cell := Vector2i((local_to_map(position) * Vector2(TileBaker.GRID)).floor())
	var index := TileBaker.region_at_tile(_tiles, cell)
	return _geo.region_ids[index] if index < _geo.region_ids.size() else ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_motion(event)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_on_left_button(event)
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		var ids := polygons.keys()
		if ids.is_empty():
			return
		var direction := -1 if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up") else 1
		select_region(ids[posmod(ids.find(selected_id) + direction, ids.size())])
		accept_event()


func _on_motion(event: InputEventMouseMotion) -> void:
	if _pressing and (_dragging or event.position.distance_to(_press_at) > DRAG_THRESHOLD):
		if not _dragging:
			pan_by(event.position - _press_at)
		else:
			pan_by(event.relative)
		_dragging = true
		accept_event()
		return
	var id := region_at(event.position)
	if id != hovered_id:
		hovered_id = id
		_redraw()


func _on_left_button(event: InputEventMouseButton) -> void:
	if event.pressed:
		grab_focus()
		_pressing = true
		_dragging = false
		_press_at = event.position
	else:
		if _pressing and not _dragging:
			select_region(region_at(event.position))
		_pressing = false
		_dragging = false
	accept_event()


func _draw() -> void:
	if has_focus():
		draw_style_box(get_theme_stylebox("focus", "ArdeniaMap"), Rect2(Vector2(2, 2), size - Vector2(4, 4)))


func _draw_highlight() -> void:
	if _cells.has(hovered_id) and hovered_id != selected_id:
		_outline(_cells[hovered_id], HOVER_WIDTH, MapPalette.DAY[MapPalette.ROCK_LIGHT])
	if _cells.has(selected_id):
		_outline(_cells[selected_id], SELECTION_WIDTH, MapPalette.DAY[MapPalette.SNOW])


func _outline(cells: Dictionary, width: float, colour: Color) -> void:
	var tile := float(tile_px)
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
