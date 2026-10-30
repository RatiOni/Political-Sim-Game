class_name DeskView
extends Control

## A desk's own room — the treasury hall, the foreign ministry, the chamber —
## drawn the way the region scenes are: a smooth picture painted every frame,
## shown only through `AsciiConvert`, with small uppercase annotations laid
## over the finished cells like labels on a reconnaissance photograph.
##
## A room is a painter: `static func paint(v: DeskView, t: float, d: Dictionary)`
## that draws in a 640 x 240 authoring space (`SPACE`) with the helpers
## below. The view fits that space to its own *height* and centres it, so a
## room never crops vertically. On a panel wider than 640:240 the visible
## span runs from `left` to `right` (left < 0, right > 640): the core
## composition stays inside 0..640 and backdrop elements (walls, windows,
## shelving, rows of people) should repeat across left..right so the edges
## are never empty.
## Everything a painter knows about the game arrives in `data`; painters
## never read the app or the snapshot themselves.

const SPACE := Vector2(640, 240)
## Painters draw in these tones and the converter snaps them to its palette.
const INK := Color(0.05, 0.05, 0.06)      # the room's darkness
const WALL := Color(0.16, 0.16, 0.17)
const STONE := Color(0.30, 0.29, 0.27)
const METAL := Color(0.42, 0.43, 0.44)
const WOOD := Color(0.30, 0.20, 0.13)
const PAPER := Color(0.78, 0.75, 0.66)
const FIGURE := Color(0.62, 0.59, 0.52)
const LAMP := Color(1.0, 0.78, 0.42)
const ALARM := Color(0.85, 0.25, 0.18)

var painter: Callable
var data: Dictionary = {}
var palette := "night"

## Visible authoring x at the panel's left and right edges (see above).
var left := 0.0
var right := 640.0

var _clock := 0.0
var _scale := 1.0
var _origin := Vector2.ZERO
var _labels: Array = []
var _overlay: Control


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	custom_minimum_size = Vector2(0, 220)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	AsciiConvert.cover(self, palette)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_labels)
	add_child(_overlay)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), INK, true)
	_scale = size.y / SPACE.y
	_origin = Vector2((size.x - SPACE.x * _scale) * 0.5, 0.0)
	left = -_origin.x / _scale
	right = SPACE.x + _origin.x / _scale
	_labels.clear()
	if painter.is_valid():
		painter.call(self, _clock, data)


# --- helpers, all in authoring space ------------------------------------

func at(p: Vector2) -> Vector2:
	return _origin + p * _scale


func rect(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(at(Vector2(x, y)), Vector2(w, h) * _scale), c, true)


func line(a: Vector2, b: Vector2, c: Color, width: float = 1.0) -> void:
	draw_line(at(a), at(b), c, maxf(1.0, width * _scale))


func poly(points: PackedVector2Array, c: Color) -> void:
	var out := PackedVector2Array()
	for p in points:
		out.append(at(p))
	draw_colored_polygon(out, c)


func disc(centre: Vector2, r: float, c: Color) -> void:
	draw_circle(at(centre), r * _scale, c)


## A faceless figure in one tone, `h` tall, feet at `foot`. Poses:
## "stand", "walk" (two steps by `t`), "sit" (at a desk, legs hidden),
## "arms_up", "point" (one arm out toward +x).
func figure(x: float, foot: float, tone: Color = FIGURE, pose: String = "stand", t: float = 0.0, h: float = 18.0) -> void:
	var u := h / 18.0
	var y := foot - h
	rect(x, y, 4 * u, 4 * u, tone)                          # head
	rect(x - 1 * u, y + 5 * u, 6 * u, 7 * u, tone)          # torso
	match pose:
		"arms_up":
			rect(x - 3 * u, y - 2 * u, 1.5 * u, 8 * u, tone)
			rect(x + 5.5 * u, y - 2 * u, 1.5 * u, 8 * u, tone)
		"point":
			rect(x - 2.5 * u, y + 5 * u, 1.5 * u, 6 * u, tone)
			rect(x + 5 * u, y + 5.5 * u, 7 * u, 1.5 * u, tone)
		_:
			rect(x - 2.5 * u, y + 5 * u, 1.5 * u, 6 * u, tone)
			rect(x + 5 * u, y + 5 * u, 1.5 * u, 6 * u, tone)
	if pose == "sit":
		return
	var step := (int(t * 3.0) % 2) if pose == "walk" else -1
	match step:
		0:
			rect(x - 0.5 * u, y + 12 * u, 2 * u, 6 * u, tone)
			rect(x + 3 * u, y + 12 * u, 2 * u, 6 * u, tone)
		1:
			rect(x + 0.5 * u, y + 12 * u, 2 * u, 6 * u, tone)
			rect(x + 1.8 * u, y + 12 * u, 2 * u, 6 * u, tone)
		_:
			rect(x, y + 12 * u, 2 * u, 6 * u, tone)
			rect(x + 2.5 * u, y + 12 * u, 2 * u, 6 * u, tone)


## A small uppercase annotation, drawn crisp over the converted picture.
## `to` (optional) draws a one-pixel leader line to the thing it names.
func label(where: Vector2, text: String, to: Vector2 = Vector2(-1, -1)) -> void:
	_labels.append([where, text.to_upper(), to])


func _draw_labels() -> void:
	var font := get_theme_font("font", "Label")
	var fs := 10
	for item in _labels:
		var p := at(item[0]).round()
		if item[2].x >= 0.0:
			var target := at(item[2]).round()
			_overlay.draw_line(p + Vector2(0, 2), target, UiPalette.TEXT_DIM, 1.0)
		_overlay.draw_rect(Rect2(p + Vector2(-2, -fs), Vector2(font.get_string_size(item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 4, fs + 3)), INK, true)
		_overlay.draw_string(font, p, item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.TEXT_DIM)
