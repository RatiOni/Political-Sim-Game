class_name MapLabels
extends Node2D

## Every word on the map, laid out so nothing overprints anything else. Each
## redraw places, in turn: place markers, the capital and city names, region
## names, status badges, then (zoomed in) town names. Every label
## tries a few slots around its anchor and takes the first free one; a name
## that cannot fit shrinks, and a city or town label that still cannot fit is
## left out rather than drawn over something that matters more.

const REGION_FONT := "res://assets/pixel/kenney_pixel.ttf"
const CITY_FONT := "res://assets/pixel/kenney_mini.ttf"
const CITY_SIZE := 8
const MARKER := 3
const CITY_GAP := 3
const PIXEL_FONT_MIN := 16
const OUTLINE: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
const BADGE_GAP := 4.0
## Breathing room kept around every placed label.
const PAD := 2.0
## Name positions to try, in line heights from the centroid, nearest first.
const NAME_OFFSETS: Array[Vector2] = [
	Vector2(0, 0), Vector2(0, -0.8), Vector2(0, 0.8), Vector2(-1.5, 0), Vector2(1.5, 0),
	Vector2(-1.5, -0.8), Vector2(1.5, -0.8), Vector2(-1.5, 0.8), Vector2(1.5, 0.8),
	Vector2(0, -1.6), Vector2(0, 1.6), Vector2(-3, 0), Vector2(3, 0), Vector2(0, -2.4), Vector2(0, 2.4),
]

var region_points: Dictionary = {}
var cities: Array[Dictionary] = []
## Smaller canon towns: a dot always, a name only when zoomed in.
var towns: Array[Dictionary] = []
var to_physical: Callable
var region_size := 8
## Region id -> [[word, colour], ...], drawn next to the region's name.
var status: Dictionary = {}
var city_scale := 1
## Zoomed in: town names are shown.
var detail := false
## The visible panel in this node's (physical) space; labels stay inside it.
var bounds := Rect2()
## Areas no label may cover (the map's buttons).
var blocked: Array[Rect2] = []
## Physical point -> region id, so names and badges stay in their region.
var region_of: Callable
static var _fonts: Dictionary = {}
## The terminal face, like the rest of the desk; the pixel fonts above stay
## loadable through `crisp` for anything still drawn in tiles.
var _region_font: Font = mono()
var _city_font: Font = mono()
## Monospace stops being readable below these sizes, whatever the zoom.
const REGION_MIN := 16
const CITY_MIN := 13
const TOWN_SIZE := 12

var _taken: Array[Rect2] = []
## Labels the last redraw had to place over something (0 when the layout is
## clean); dropped city and town names are counted in `dropped` instead.
var collisions := 0
var dropped := 0


static func mono() -> Font:
	if not _fonts.has("mono"):
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "Monospace"])
		_fonts["mono"] = font
	return _fonts["mono"]


static func crisp(path: String) -> FontFile:
	if _fonts.has(path):
		return _fonts[path]
	var font := (load(path) as FontFile).duplicate() as FontFile
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.generate_mipmaps = false
	font.oversampling = 1.0
	_fonts[path] = font
	return font


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	if not to_physical.is_valid():
		return
	_taken = blocked.duplicate()
	collisions = 0
	dropped = 0
	var city_size := maxi(CITY_MIN, CITY_SIZE * city_scale)
	var marks: Array = []
	for city in cities:
		var marker := float(MARKER * city_scale + (4 if city["capital"] else 2))
		var colour := MapPalette.DAY[MapPalette.GOLD if city["capital"] else MapPalette.WALL]
		marks.append([city, _marker(city["point"], marker, colour)])
	var town_marks: Array = []
	for town in towns:
		town_marks.append([town, _marker(town["point"], float(1 + city_scale) + 1.0, MapPalette.DAY[MapPalette.ROCK_LIGHT])])
	# Cities first: their names are short and pinned to a dot, while region
	# names and badges can move around them.
	marks.sort_custom(func(a: Array, b: Array) -> bool: return bool(a[0]["capital"]) and not bool(b[0]["capital"]))
	for mark in marks:
		var city: Dictionary = mark[0]
		var capital := bool(city["capital"])
		var colour := MapPalette.DAY[MapPalette.GOLD if capital else MapPalette.SNOW]
		_place_beside(String(city["name"]), mark[1], city_size + (2 if capital else 0), colour, capital)
	var names := {}
	for id in region_points:
		var placed: Variant = _place_region(String(id), to_physical.call(region_points[id]))
		if placed != null:
			names[id] = placed
	for id in names:
		_place_badges(status.get(id, []), names[id], String(id))
	if detail:
		for mark in town_marks:
			_place_beside(String(mark[0]["name"]), mark[1], TOWN_SIZE, MapPalette.DAY[MapPalette.ROCK_LIGHT], false)


## Draw a square place marker and reserve its footprint.
func _marker(point: Vector2, side: float, colour: Color) -> Rect2:
	var dot: Vector2 = (to_physical.call(point) as Vector2).round()
	var corner := (dot - Vector2(side, side) / 2.0).round()
	var rect := Rect2(corner, Vector2(side, side))
	draw_rect(rect.grow(1), MapPalette.DAY[MapPalette.INK])
	draw_rect(rect, colour)
	_taken.append(rect.grow(1))
	return rect


func _text_rect(font: Font, baseline: Vector2, text: String, size: int) -> Rect2:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return Rect2(baseline.x - 1, baseline.y - font.get_ascent(size) - 1, width + 2, font.get_ascent(size) + font.get_descent(size) + 2)


## How badly a rect collides: overlap with placed labels plus area off-panel.
func _clash(rect: Rect2, off_panel := true) -> float:
	var score := 0.0
	for other in _taken:
		var cut := rect.intersection(other)
		score += cut.get_area()
	if off_panel and bounds.has_area():
		score += rect.get_area() - rect.intersection(bounds).get_area()
	return score


## The region's name, centred on its area centroid where it fits: letter-
## spaced close by, else plain and nudged, else a size smaller. A spot that
## spills out of the region costs as much as one that collides.
func _place_region(id: String, at: Vector2) -> Variant:
	var size := maxi(REGION_MIN, region_size)
	var spaced := " ".join(id.to_upper().split(""))
	var variants := [[spaced, size], [id.to_upper(), size], [id.to_upper(), size - 2]]
	var line := _region_font.get_height(size)
	var best: Array = []
	var best_score := INF
	var tries: Array = []
	# Letter-spaced near the centroid first, so most names share one style;
	# then the plain name anywhere nearby, then one size smaller.
	for offset in NAME_OFFSETS.slice(0, 5):
		tries.append([variants[0], offset])
	for variant in variants.slice(1):
		for offset in NAME_OFFSETS:
			tries.append([variant, offset])
	for attempt in tries:
		var variant: Array = attempt[0]
		var offset: Vector2 = attempt[1]
		var text: String = variant[0]
		var font_size: int = variant[1]
		var width := _region_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var baseline := (at + Vector2(-width / 2.0 + offset.x * line, _region_font.get_ascent(font_size) / 2.0 + offset.y * line)).round()
		var rect := _text_rect(_region_font, baseline, text, font_size)
		var score := _clash(rect.grow(PAD)) + _spill(rect, id)
		if score < best_score:
			best_score = score
			best = [baseline, text, font_size, rect]
		if best_score == 0.0:
			break
	if bounds.has_area() and not bounds.has_point(at) and _clash((best[3] as Rect2), false) > 0.0:
		# Panned so the region's heart is off screen and its name would
		# land on another label: leave it to the region that is in view.
		return null
	collisions += 1 if _clash((best[3] as Rect2), false) > 0.0 else 0
	_outlined(_region_font, best[0], best[1], best[2], UiPalette.TEXT)
	_taken.append((best[3] as Rect2).grow(PAD))
	return best[3]


## Area of `rect` judged to lie outside region `id` (five sample points).
func _spill(rect: Rect2, id: String) -> float:
	if not region_of.is_valid():
		return 0.0
	var inset := rect.grow(-2.0)
	var outside := 0
	for p in [inset.position, inset.end, Vector2(inset.position.x, inset.end.y), Vector2(inset.end.x, inset.position.y), inset.get_center()]:
		outside += 0 if String(region_of.call(p)) == id else 1
	return rect.get_area() * outside / 5.0


## The status badges sit as one row beside the name, else under or over it,
## kept inside the region where they can be; when no row fits anywhere they
## stack into a column instead.
func _place_badges(tags: Array, name: Rect2, id: String) -> void:
	if tags.is_empty():
		return
	var size := CITY_MIN
	var h := _city_font.get_height(size) + 2.0
	var widths: Array[float] = []
	for tag in tags:
		widths.append(_city_font.get_string_size(String(tag[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 8.0)
	var best := Vector2.ZERO
	var best_score := INF
	var best_column := false
	for column in [false, true]:
		var extent := _badge_extent(widths, h, column)
		for slot in _badge_slots(name, extent):
			var rect := Rect2(slot, extent)
			var score := _clash(rect.grow(PAD)) + _spill(rect, id) * 0.25
			if score < best_score:
				best_score = score
				best = slot
				best_column = column
			if score == 0.0:
				break
		if best_score == 0.0 or tags.size() == 1:
			break
	var placed := Rect2(best, _badge_extent(widths, h, best_column))
	collisions += 1 if _clash(placed, false) > 0.0 else 0
	_taken.append(placed.grow(PAD))
	var at := best
	for i in tags.size():
		var colour: Color = tags[i][1]
		var box := Rect2(at.round(), Vector2(widths[i], h))
		draw_rect(box.grow(1), MapPalette.DAY[MapPalette.INK])
		draw_rect(box, Color(colour, 0.25))
		draw_rect(box, colour, false, 1.0)
		draw_string(_city_font, (box.position + Vector2(4, 1 + _city_font.get_ascent(size))).round(), String(tags[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour.lightened(0.3))
		at += Vector2(0, h + 3.0) if best_column else Vector2(widths[i] + BADGE_GAP, 0)


func _badge_extent(widths: Array[float], h: float, column: bool) -> Vector2:
	if column:
		return Vector2(widths.max(), widths.size() * (h + 3.0) - 3.0)
	var total := -BADGE_GAP
	for w in widths:
		total += w + BADGE_GAP
	return Vector2(total, h)


func _badge_slots(name: Rect2, extent: Vector2) -> Array[Vector2]:
	var centre := name.get_center().x - extent.x / 2.0
	var middle := name.get_center().y - extent.y / 2.0
	var slots: Array[Vector2] = [
		Vector2(centre, name.end.y + 2.0),
		Vector2(name.end.x + 6.0, middle),
		Vector2(name.position.x - extent.x - 6.0, middle),
		Vector2(centre, name.position.y - extent.y - 2.0),
	]
	for row in [name.end.y + 2.0, name.position.y - extent.y - 2.0, name.end.y + extent.y + 6.0]:
		for shift in [-0.5, 0.5, -1.0, 1.0]:
			slots.append(Vector2(centre + shift * extent.x, row))
	return slots


## A place name beside its marker: right, left, above or below. When no slot
## is free the name is dropped, unless `force` (the capital).
func _place_beside(text: String, dot: Rect2, size: int, colour: Color, force: bool) -> void:
	var width := _city_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var ascent := _city_font.get_ascent(size)
	var mid := dot.get_center().y + ascent / 2.0 - 1.0
	var gap := CITY_GAP * city_scale + 1.0
	var slots := [
		Vector2(dot.end.x + gap, mid),
		Vector2(dot.position.x - gap - width, mid),
		Vector2(dot.get_center().x - width / 2.0, dot.position.y - 3.0),
		Vector2(dot.get_center().x - width / 2.0, dot.end.y + ascent + 2.0),
	]
	var best := Vector2.INF
	var best_score := INF
	for slot in slots:
		var score := _clash(_text_rect(_city_font, slot.round(), text, size).grow(1))
		if score < best_score:
			best_score = score
			best = slot.round()
		if score == 0.0:
			break
	if best_score > 0.0 and not force:
		dropped += 1
		return
	collisions += 1 if _clash(_text_rect(_city_font, best, text, size), false) > 0.0 else 0
	_outlined(_city_font, best, text, size, colour)
	_taken.append(_text_rect(_city_font, best, text, size).grow(1))


func _outlined(font: Font, at: Vector2, text: String, font_size: int, colour: Color) -> void:
	for d in OUTLINE:
		draw_string(font, at + d, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, MapPalette.DAY[MapPalette.INK])
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
