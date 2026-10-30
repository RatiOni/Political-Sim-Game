extends Control
class_name ArdeniaMap

signal region_selected(region_id: String)

const BORDERS_PATH := "res://data/map/baked/borders.json"
const UNAVAILABLE_TEXT := "Map data unavailable"
const OVERVIEW := TileArt.HALF
const DETAIL := TileArt.CELL
const HOVER_WIDTH := 1.0
const SELECTION_WIDTH := 2.0
const DRAG_THRESHOLD := 4.0
const BUTTON_SIZE := Vector2(44, 44)
const BUTTON_MARGIN := 8.0
const DUSK_LABEL := "NITE"
const DAY_LABEL := "DAY"
const ZOOM_IN_KEYS: Array[Key] = [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]
const ZOOM_OUT_KEYS: Array[Key] = [KEY_MINUS, KEY_KP_SUBTRACT]
const CORNERS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]

var tiles_path := TileBaker.TILES_PATH
var regions: Dictionary = {}
var polygons: Dictionary = {}
var selected_id := ""
var hovered_id := ""
var unavailable := false
var tile_px := OVERVIEW
var zoom := 1
var terrain_layer := TileMapLayer.new()
var growth_layer := TileMapLayer.new()
var smoke_layer := TileMapLayer.new()
## What the player sees: the tile layers rendered as a living character grid.
var ascii := AsciiTerrain.new()
var smoke_desired: Dictionary = {}
var growth_desired: Dictionary = {}
var growth_tween: Tween
var smoke_timer := Timer.new()
var smoke_frame := 0
var last_changed_cells := 0
var lines_builds := 0
var unknown_warnings := 0
var lines_rect := TextureRect.new()
var routes_rect := TextureRect.new()
var routes_builds := 0
var zoom_in_button := Button.new()
var zoom_out_button := Button.new()
var dusk_button := Button.new()
var _sea := ColorRect.new()
var _physical := Node2D.new()
var _canvas := Node2D.new()
const RESTLESS_PRESSURE := 0.35
const PROTEST_PRESSURE := 0.6
var _highlight := Node2D.new()
var _labels := MapLabels.new()
var _notice := Label.new()
var _geo: MapGeometry
var _tiles: Dictionary = {}
var _outlines: Dictionary = {}
var _cells: Dictionary = {}
var _centres: Dictionary = {}
var _country := Rect2()
var _tilesets: Dictionary = {}
var _day_textures: Dictionary = {}
var _dusk_textures: Dictionary = {}
var _lines: Dictionary = {}
var _covered: Dictionary = {}
var _locked_rails: Dictionary = {}
var _routes_key := []
var _dusk := false
var _warned_ids: Dictionary = {}
var _growth_started := false
var _user_zoomed := false
var _screen_scale := 1.0
var _base := Vector2.ZERO
var _origin := Vector2.ZERO
var _focus := Vector2(0.5, 0.5)
var _press_at := Vector2.ZERO
var _pressing := false
var _dragging := false


static func level_zoom(physical_width: float, px: int) -> int:
	return maxi(1, floori(physical_width / (TileBaker.GRID.x * px)))


func _init() -> void:
	_build_nodes()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_notify_transform(true)
	resized.connect(_layout)
	get_viewport().size_changed.connect(_layout)
	mouse_exited.connect(func(): hovered_id = ""; _redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	unavailable = not _load()
	_notice.visible = unavailable
	_physical.visible = not unavailable
	zoom_in_button.visible = not unavailable
	zoom_out_button.visible = not unavailable
	dusk_button.visible = not unavailable
	_layout()
	_paint_growth()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready() and not unavailable:
		_place()


func _build_nodes() -> void:
	clip_contents = true
	_sea.color = MapPalette.DAY[MapPalette.INK]
	_sea.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sea.show_behind_parent = true
	_sea.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_sea)
	_physical.show_behind_parent = true
	_physical.name = "Physical"
	add_child(_physical)
	_physical.add_child(_canvas)
	for layer in [terrain_layer, growth_layer, smoke_layer]:
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_canvas.add_child(layer)
	# The tile layers stay the model the growth painter and tests work on;
	# `ascii` draws them, so they are kept but not shown.
	for layer in [terrain_layer, growth_layer, smoke_layer]:
		layer.self_modulate = Color(1, 1, 1, 0)
	_canvas.add_child(ascii)
	terrain_layer.name = "Terrain"
	growth_layer.name = "Growth"
	smoke_layer.name = "Smoke"
	routes_rect.name = "Routes"
	lines_rect.name = "Lines"
	for rect in [routes_rect, lines_rect]:
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas.add_child(rect)
	_highlight.draw.connect(_draw_highlight)
	_canvas.add_child(_highlight)
	smoke_timer.name = "SmokeTimer"
	smoke_timer.wait_time = GrowthPainter.SMOKE_SECONDS
	smoke_timer.timeout.connect(func() -> void: GrowthPainter.step_smoke(self))
	add_child(smoke_timer)

	_labels.name = "Labels"
	_physical.add_child(_labels)
	_notice.name = "Unavailable"
	_notice.text = UNAVAILABLE_TEXT
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notice.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_notice)
	_build_zoom_button(zoom_in_button, "ZoomIn", "+", "Zoom in to detail (+ or mouse wheel)", zoom_in)
	_build_zoom_button(zoom_out_button, "ZoomOut", "-", "Zoom out to the overview (- or mouse wheel)", zoom_out)
	_build_zoom_button(dusk_button, "Dusk", DUSK_LABEL, "Skip ahead to day or night (the cycle runs on its own)", func() -> void:
		DayCycle.skip()
		set_dusk(DayCycle.is_night()))
	dusk_button.add_theme_font_size_override("font_size", 16)


func _build_zoom_button(button: Button, id: String, label: String, tip: String, action: Callable) -> void:
	button.name = id
	button.text = label
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = BUTTON_SIZE
	button.size = BUTTON_SIZE
	button.add_theme_font_override("font", MapLabels.crisp(MapLabels.REGION_FONT))
	button.add_theme_font_size_override("font_size", 32)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = MapPalette.DAY[MapPalette.INK if state != "hover" else MapPalette.ROCK_DARK]
		box.border_color = MapPalette.DAY[MapPalette.GOLD_DARK if state == "disabled" else MapPalette.GOLD]
		box.set_border_width_all(2)
		box.anti_aliasing = false
		button.add_theme_stylebox_override(state, box)
	button.add_theme_color_override("font_color", MapPalette.DAY[MapPalette.SNOW])
	button.add_theme_color_override("font_disabled_color", MapPalette.DAY[MapPalette.ROCK])
	button.pressed.connect(func(): action.call())
	add_child(button)


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
	if not _fill_terrain():
		push_error("ArdeniaMap: the tile file holds no Ardenian cells")
		return false
	ascii.build(self, _tiles)
	_centres = _region_centres()
	_labels.cities = _geo.cities
	_labels.region_points = _centres
	_labels.to_physical = _map_to_physical
	return true


static func _source(tileset: TileSet) -> TileSetAtlasSource:
	return tileset.get_source(tileset.get_source_id(0)) as TileSetAtlasSource


func _fill_terrain() -> bool:
	var cells := TileArt.index()
	var kinds: PackedByteArray = _tiles["kinds"]
	var variants: PackedByteArray = _tiles["variants"]
	var country := PackedVector2Array()
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
				country.append(Vector2(x, y))
	if country.is_empty():
		return false
	var bounds := Rect2(country[0], Vector2.ONE)
	for p in country:
		bounds = bounds.expand(p).expand(p + Vector2.ONE)
	_country = Rect2(bounds.position / Vector2(TileBaker.GRID), bounds.size / Vector2(TileBaker.GRID))
	return true


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


## Day and night follow the shared clock as time passes.
func _process(_delta: float) -> void:
	if not unavailable and DayCycle.is_night() != _dusk:
		set_dusk(not _dusk)


func is_dusk() -> bool:
	return _dusk


func set_dusk(on: bool) -> void:
	if unavailable:
		return
	_dusk = on
	dusk_button.text = DAY_LABEL if on else DUSK_LABEL
	for px in _tilesets:
		_source(_tilesets[px]).texture = _dusk_textures[px] if on else _day_textures[px]
	ascii.set_dusk(on)
	_apply_lines()
	GrowthPainter.refresh_lights(self)


func _apply_lines() -> void:
	var key := Vector2i(tile_px, int(_dusk))
	if not _lines.has(key):
		lines_builds += 1
		_lines[key] = ImageTexture.create_from_image(MapLines.build(_tiles, _geo, _palette(), tile_px))
	lines_rect.texture = _lines[key]
	lines_rect.size = Vector2(MapLines.canvas_size(tile_px))
	_apply_routes()


func _palette() -> PackedColorArray:
	return MapPalette.DUSK if _dusk else MapPalette.DAY


func _apply_routes() -> void:
	var key := [tile_px, _dusk, _covered.hash(), _locked_rails.hash()]
	if key == _routes_key:
		return
	_routes_key = key
	routes_builds += 1
	var image := MapLines.routes(_geo, _palette(), tile_px, _covered, _locked_rails)
	if routes_rect.texture is ImageTexture and Vector2i(routes_rect.texture.get_size()) == image.get_size():
		(routes_rect.texture as ImageTexture).update(image)
	else:
		routes_rect.texture = ImageTexture.create_from_image(image)
	routes_rect.size = Vector2(image.get_size())


func screen_transform() -> Transform2D:
	return get_viewport().get_final_transform() * get_global_transform_with_canvas()


func physical_size() -> Vector2:
	return size * screen_transform().get_scale().x


func default_tile_px() -> int:
	var panel := physical_size()
	var detail := Vector2(TileBaker.GRID * DETAIL * level_zoom(panel.x, DETAIL))
	# Judge by the country, not the whole grid: the sea and foreign margin may
	# crop (the map pans) as long as Ardenia itself fits at the sharper level.
	return DETAIL if (_country.size * detail).x <= panel.x and (_country.size * detail).y <= panel.y else OVERVIEW


func _layout() -> void:
	zoom_in_button.position = Vector2(size.x - BUTTON_SIZE.x - BUTTON_MARGIN, BUTTON_MARGIN)
	zoom_out_button.position = zoom_in_button.position + Vector2(0, BUTTON_SIZE.y + BUTTON_MARGIN / 2.0)
	dusk_button.position = zoom_out_button.position + Vector2(0, BUTTON_SIZE.y + BUTTON_MARGIN / 2.0)
	if unavailable or not is_inside_tree():
		return
	_set_level(tile_px if _user_zoomed else default_tile_px())


func _set_level(px: int) -> void:
	if px != tile_px or terrain_layer.tile_set == null:
		tile_px = px
		terrain_layer.tile_set = _tilesets[tile_px]
		growth_layer.tile_set = _tilesets[tile_px]
		smoke_layer.tile_set = _tilesets[tile_px]
		_apply_lines()
	zoom = level_zoom(physical_size().x, tile_px)
	_canvas.scale = Vector2(zoom, zoom)
	ascii.set_level(tile_px, tile_px * zoom * screen_transform().get_scale().x)
	_labels.region_size = 2 * tile_px * zoom
	_labels.city_scale = zoom
	zoom_in_button.disabled = tile_px == DETAIL
	zoom_out_button.disabled = tile_px == OVERVIEW
	_place()


func canvas_extent() -> Vector2:
	return Vector2(TileBaker.GRID * tile_px * zoom)


func _place() -> void:
	var screen := screen_transform()
	_screen_scale = screen.get_scale().x
	var physical_origin := screen.origin
	_base = physical_origin - physical_origin.round()
	_physical.scale = Vector2.ONE / _screen_scale
	_physical.position = -_base / _screen_scale
	var panel := size * _screen_scale
	var extent := canvas_extent()
	var wanted := Vector2.ZERO
	for axis in 2:
		if extent[axis] <= panel[axis]:
			wanted[axis] = roundf(_base[axis] + (panel[axis] - extent[axis]) / 2.0)
		else:
			var free := roundf(_base[axis] + panel[axis] / 2.0 - _focus[axis] * extent[axis])
			wanted[axis] = clampf(free, ceilf(_base[axis] + panel[axis] - extent[axis]), floorf(_base[axis]))
	_origin = wanted
	_focus = (_base + panel / 2.0 - _origin) / extent
	_canvas.position = _origin
	polygons.clear()
	for id in _outlines:
		var ring := PackedVector2Array()
		for p in _outlines[id]:
			ring.append(map_to_local(Vector2(float(p[0]), float(p[1]))))
		polygons[String(id)] = ring
	_redraw()


func _map_to_physical(p: Vector2) -> Vector2:
	return _origin + p * canvas_extent()


func map_to_local(p: Vector2) -> Vector2:
	return _physical.position + _map_to_physical(p) / _screen_scale


func local_to_map(p: Vector2) -> Vector2:
	return ((p - _physical.position) * _screen_scale - _origin) / canvas_extent()


func pan_by(delta: Vector2) -> void:
	if unavailable:
		return
	_focus -= delta * _screen_scale / canvas_extent()
	_place()


func centre_on(map_point: Vector2) -> void:
	if unavailable:
		return
	_focus = map_point
	_place()


func zoom_in(anchor: Variant = null) -> void:
	_zoom_to(DETAIL, anchor)


func zoom_out(anchor: Variant = null) -> void:
	_zoom_to(OVERVIEW, anchor)


func _zoom_to(px: int, anchor: Variant) -> void:
	if unavailable or px == tile_px:
		return
	var at: Vector2 = anchor if anchor is Vector2 else (map_to_local(_centres[selected_id]) if _centres.has(selected_id) else size / 2.0)
	var held := local_to_map(at)
	_user_zoomed = true
	_set_level(px)
	_focus = held + (_base + size * _screen_scale / 2.0 - (at - _physical.position) * _screen_scale) / canvas_extent()
	_place()


func _redraw() -> void:
	queue_redraw()
	_highlight.queue_redraw()
	_labels.queue_redraw()


func apply_snapshot(values: Array, selection: String) -> void:
	regions.clear()
	for region in values:
		if not (region is Dictionary and region.has("id")):
			continue
		var id := str(region["id"])
		if _geo == null or _geo.region_ids.has(id):
			regions[id] = region.duplicate(true)
		elif not _warned_ids.has(id):
			_warned_ids[id] = true
			unknown_warnings += 1
			push_warning("ArdeniaMap: ignoring unknown region id '%s'" % id)
	selected_id = selection if polygons.has(selection) else ""
	_labels.status = status_tags(regions)
	_paint_growth()
	_redraw()


func _paint_growth() -> void:
	if unavailable or _geo == null or terrain_layer.tile_set == null or regions.is_empty():
		return
	var targets := GrowthLayers.all_targets(regions.values(), _geo, _tiles)
	var overlay := GrowthLayers.overlay(regions.values(), _geo, _tiles, targets)
	_cover_routes(overlay["covered"], overlay["locked_rails"])
	GrowthPainter.apply(self, targets, overlay, _growth_started)
	_growth_started = true


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
	elif event is InputEventMouseButton:
		_on_button(event)
	elif event is InputEventKey and event.pressed and (event.keycode in ZOOM_IN_KEYS or event.keycode in ZOOM_OUT_KEYS):
		if event.keycode in ZOOM_IN_KEYS:
			zoom_in()
		else:
			zoom_out()
		accept_event()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		var ids := polygons.keys()
		if ids.is_empty():
			return
		var direction := -1 if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up") else 1
		select_region(ids[posmod(ids.find(selected_id) + direction, ids.size())])
		accept_event()


func _on_motion(event: InputEventMouseMotion) -> void:
	if _pressing and (_dragging or event.position.distance_to(_press_at) > DRAG_THRESHOLD):
		pan_by(event.relative if _dragging else event.position - _press_at)
		_dragging = true
		accept_event()
		return
	var id := region_at(event.position)
	if id != hovered_id:
		hovered_id = id
		_redraw()


func _on_button(event: InputEventMouseButton) -> void:
	if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_in(event.position)
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_out(event.position)
	elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		grab_focus()
		_pressing = true
		_dragging = false
		_press_at = event.position
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if _pressing and not _dragging:
			select_region(region_at(event.position))
		_pressing = false
		_dragging = false
	else:
		return
	accept_event()


func _draw() -> void:
	if has_focus():
		draw_style_box(get_theme_stylebox("focus", "ArdeniaMap"), Rect2(Vector2(2, 2), size - Vector2(4, 4)))


## What is happening in each region, as short words under its name:
## the running programme, unrest, armed conflict, lost control.
static func status_tags(rows: Dictionary) -> Dictionary:
	var tags := {}
	for id in rows:
		var row: Dictionary = rows[id]
		var list: Array = []
		var program: Variant = row.get("active_program")
		if program is Dictionary:
			list.append([String(program.get("short_name", "Programme")).to_upper(), UiPalette.GOLD])
		if String(row.get("control", "")) == "separatist":
			list.append(["SEPARATIST", MapPalette.DAY[MapPalette.ROCK_LIGHT]])
		elif bool(row.get("civil_war", false)) or float(row.get("insurgency", 0.0)) > 0.4:
			list.append(["CONFLICT", UiPalette.BAD])
		elif float(row.get("pressure", 0.0)) > PROTEST_PRESSURE:
			list.append(["UNREST", UiPalette.BAD])
		elif float(row.get("pressure", 0.0)) > RESTLESS_PRESSURE:
			list.append(["RESTLESS", UiPalette.WARN])
		tags[id] = list
	return tags


## A translucent wash over troubled regions; calm ones stay clean so the
## colour itself means "trouble here".
func _draw_pressure() -> void:
	var tile := float(tile_px)
	for id in _cells:
		var row: Dictionary = regions.get(id, {})
		var pressure := float(row.get("pressure", 0.0))
		var colour: Color
		if String(row.get("control", "")) == "separatist":
			colour = Color(0.05, 0.05, 0.07, 0.35)
		elif pressure > RESTLESS_PRESSURE:
			colour = UiPalette.risk_scale(pressure, RESTLESS_PRESSURE, PROTEST_PRESSURE)
			colour.a = lerpf(0.12, 0.30, inverse_lerp(RESTLESS_PRESSURE, 1.0, pressure))
		else:
			continue
		for cell in _cells[id]:
			_highlight.draw_rect(Rect2(Vector2(cell) * tile, Vector2(tile, tile)), colour)


func _draw_highlight() -> void:
	_draw_pressure()
	if _cells.has(hovered_id) and hovered_id != selected_id:
		_outline(_cells[hovered_id], HOVER_WIDTH, MapPalette.DAY[MapPalette.ROCK_LIGHT])
	if _cells.has(selected_id):
		_outline(_cells[selected_id], SELECTION_WIDTH, MapPalette.DAY[MapPalette.SNOW])


func _outline(cells: Dictionary, width: float, colour: Color) -> void:
	var tile := float(tile_px)
	for cell in cells:
		var origin := Vector2(cell) * tile
		for side in TileBaker.SIDES:
			if cells.has(cell + side):
				continue
			var at := origin + Vector2(tile - width if side.x > 0 else 0.0, tile - width if side.y > 0 else 0.0)
			var extent := Vector2(width if side.x != 0 else tile, width if side.y != 0 else tile)
			_highlight.draw_rect(Rect2(at, extent), colour)
		for corner in CORNERS:
			if cells.has(cell + Vector2i(corner.x, 0)) and cells.has(cell + Vector2i(0, corner.y)) and not cells.has(cell + corner):
				var at := origin + Vector2(tile - width if corner.x > 0 else 0.0, tile - width if corner.y > 0 else 0.0)
				_highlight.draw_rect(Rect2(at, Vector2(width, width)), colour)


func _cover_routes(covered: Dictionary, locked_rails: Dictionary) -> void:
	_covered = covered
	_locked_rails = locked_rails
	_apply_routes()
