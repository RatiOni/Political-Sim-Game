extends Control
class_name ArdeniaMap

signal region_selected(region_id: String)

# Matches ui/widgets_ardenia_map.py: normalized authoring space is not square geography.
const MAP_ASPECT := 1.68

var geography: Dictionary = {}
var regions: Dictionary = {}
var polygons: Dictionary = {}
var selected_id := ""
var hovered_id := ""
var _transform := Transform2D.IDENTITY
var _label_boxes: Array[Rect2] = []

func _ready() -> void:
	var file := FileAccess.open("res://data/ardenia_map.json", FileAccess.READ)
	if file == null:
		push_error("Ardenia map data could not be opened.")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Ardenia map data must be a JSON object.")
		return
	geography = parsed
	resized.connect(_rebuild_geometry)
	mouse_exited.connect(func(): hovered_id = ""; queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	_rebuild_geometry()

func apply_snapshot(values: Array, selection: String) -> void:
	regions.clear()
	for region in values:
		if region is Dictionary and region.has("id"):
			regions[str(region["id"])] = region.duplicate(true)
	selected_id = selection if polygons.has(selection) else ""
	queue_redraw()

func select_region(region_id: String) -> void:
	if not polygons.has(region_id):
		return
	selected_id = region_id
	queue_redraw()
	region_selected.emit(region_id)

func _rebuild_geometry() -> void:
	# One canonical projection for drawing AND pointer hit tests; no geometry changes.
	var width := maxf(1.0, minf(size.x - 48.0, (size.y - 36.0) * MAP_ASPECT))
	var extent := Vector2(width, width / MAP_ASPECT)
	_transform = Transform2D(Vector2(extent.x / 100.0, 0), Vector2(0, extent.y / 100.0), (size - extent) / 2.0)
	polygons.clear()
	for region in geography.get("regions", []):
		polygons[region["id"]] = _points(region["points"])
	queue_redraw()

func _point(value: Array) -> Vector2:
	return _transform * Vector2(float(value[0]), float(value[1]))

func _points(values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in values:
		result.append(_point(point))
	return result

func region_at(position: Vector2) -> String:
	for id in polygons:
		if Geometry2D.is_point_in_polygon(position, polygons[id]):
			return id
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var id := region_at(event.position)
		if id != hovered_id:
			hovered_id = id
			queue_redraw()
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

func _color(token: String) -> Color:
	return get_theme_color(token, "ArdeniaMap")

func _border(points: PackedVector2Array, color: Color, width: float) -> void:
	if points.size() < 2:
		return
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, color, width, true)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _color("sea"))
	if geography.is_empty():
		return
	for neighbor in geography.get("neighbors", []):
		draw_colored_polygon(_points(neighbor["points"]), _color("neighbor"))
	for id in polygons:
		# Pressure is already calculated in Python; only colour interpolation lives here.
		var fill := _color("neighbor")
		if regions.has(id) and regions[id].has("pressure"):
			fill = _color("low_pressure").lerp(_color("high_pressure"), clampf(float(regions[id]["pressure"]), 0.0, 1.0))
		draw_colored_polygon(polygons[id], fill)
		_border(polygons[id], _color("border"), 1.0)
	_border(_points(geography.get("outline", [])), _color("border"), 2.0)
	for route in geography.get("routes", []):
		draw_polyline(_points(route["points"]), _color("rail" if route.get("kind") == "rail" else "road"), 1.3, true)
	var ceasefire := _points(geography.get("ceasefire_line", []))
	for index in range(ceasefire.size() - 1):
		draw_dashed_line(ceasefire[index], ceasefire[index + 1], _color("ceasefire"), 2.8, 6.0, true, true)
	if polygons.has(hovered_id) and hovered_id != selected_id:
		_border(polygons[hovered_id], _color("hover"), 2.0)
	if polygons.has(selected_id):
		_border(polygons[selected_id], _color("selection"), 3.0)
	var font := get_theme_default_font()
	_label_boxes.clear()
	for label in geography.get("labels", []):
		if str(label["name"]).is_empty():
			continue
		var is_region := polygons.has(label["id"])
		_draw_label(font, str(label["name"]), _point(label["point"]), 16 if is_region else 13, _color("ink" if is_region else "context_ink"))
	for city in geography.get("cities", []):
		var point := _point(city["point"])
		var capital: bool = city.get("capital", false)
		draw_circle(point, 4.0 if capital else 2.6, _color("selection" if capital else "ink"))
		if capital:
			draw_arc(point, 7.0, 0, TAU, 24, _color("selection"), 1.2, true)
		# National cities always labelled; regional city names disclosed at roomy sizes.
		if city.get("importance") == "national" or size.y >= 480:
			for offset in [Vector2(0, 22), Vector2(0, -12), Vector2(44, 14), Vector2(-44, 14)]:
				if _draw_label(font, str(city["name"]), point + offset, 14, _color("ink"), true):
					break
	if has_focus():
		draw_style_box(get_theme_stylebox("focus", "ArdeniaMap"), Rect2(Vector2(2, 2), size - Vector2(4, 4)))

func _draw_label(font: Font, text: String, center: Vector2, font_size: int, color: Color, avoid_overlap := false) -> bool:
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var position := center - Vector2(extent.x / 2.0, 0)
	position.x = clampf(position.x, 6.0, maxf(6.0, size.x - extent.x - 6.0))
	var bounds := Rect2(position - Vector2(0, font.get_ascent(font_size)), extent).grow(2)
	if avoid_overlap:
		for previous in _label_boxes:
			if bounds.intersects(previous):
				return false
	_label_boxes.append(bounds)
	draw_string_outline(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, _color("sea"))
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	return true
