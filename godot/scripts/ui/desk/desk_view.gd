class_name DeskView
extends Control

## A desk's own room — the treasury hall, the foreign ministry, the chamber —
## drawn the way the region scenes are: a smooth picture painted every frame,
## shown only through `AsciiConvert`, with small uppercase annotations laid
## over the finished cells like labels on a reconnaissance photograph.
##
## A room is a painter: `static func paint(v: DeskView, t: float, d: Dictionary)`
## that draws in a 640 x 420 authoring space (`SPACE`) with the helpers
## below. The view fits that space to its own *height* and centres it, so a
## room never crops vertically. On a panel wider than 640:420 the visible
## span runs from `left` to `right` (left < 0, right > 640): the core
## composition stays inside 0..640 and backdrop elements (walls, windows,
## shelving, rows of people) should repeat across left..right so the edges
## are never empty.
## Everything a painter knows about the game arrives in `data`; painters
## never read the app or the snapshot themselves.

const SPACE := Vector2(640, 420)
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
## The authoring space fitted to the control. Rooms keep `SPACE`; a wider
## picture (the regional city scenes) sets its own.
var space := SPACE
## The converter laid over the picture, once the view is in the tree.
var ascii: AsciiConvert

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
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	ascii = AsciiConvert.cover(self, palette)
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
	# Fit the height, but never crop the core composition by more than 60
	# units a side: a tall narrow room letterboxes instead (dark bands).
	_scale = minf(size.y / space.y, size.x / (space.x - 80.0))
	_origin = ((size - space * _scale) * 0.5).floor()
	left = -_origin.x / _scale
	right = space.x + _origin.x / _scale
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


## Faces and hands; dimmed with the figure's own tone (see `_skin`).
const SKIN := Color(0.80, 0.66, 0.50)
const HAIR := [Color(0.12, 0.10, 0.09), Color(0.30, 0.24, 0.18), Color(0.52, 0.50, 0.47)]
## Hair seen from behind is the whole head, so it runs lighter than the room.
const HAIR_BACK := [Color(0.08, 0.07, 0.07), Color(0.13, 0.11, 0.10), Color(0.50, 0.50, 0.50), Color(0.10, 0.09, 0.08), Color(0.62, 0.56, 0.44)]
const CHAIR := Color(0.13, 0.11, 0.10)


## A small figure, `h` tall when standing, feet at `foot`, in `tone`
## (clothes) with a face in `skin` (default: a skin tone dimmed to match
## `tone`, so a far grey figure does not grow a glowing head). Head, a
## shoulder line wider than the head, darker trousers with a gap between the
## legs: enough to read as a person at three or four cells wide.
## Poses: "stand", "walk" (two steps by `t`), "sit" (at a desk, legs hidden),
## "arms_up", "point" (one arm out toward +x), "seated" (on a chair seen from
## the front: chair back behind the shoulders, knees and shins), "back"
## (standing, seen from behind: all hair, no face), "sit_back" (seated, seen
## from behind: head and shoulders over a chair back).
func figure(x: float, foot: float, tone: Color = FIGURE, pose: String = "stand", t: float = 0.0, h: float = 18.0, skin: Color = Color(0, 0, 0, 0)) -> void:
	var u := h / 18.0
	var y := foot - h
	if pose == "seated" or pose == "sit_back":
		y = foot - 14.0 * u if pose == "seated" else foot - 13.0 * u
	var face := skin if skin.a > 0.0 else _skin(tone)
	var hair: Color = HAIR[posmod(int(x * 0.37 + h), HAIR.size())]
	hair = hair.darkened(clampf(0.5 - tone.get_luminance(), 0.0, 0.4))
	var legs := tone.darkened(0.38)
	var chair := CHAIR.lerp(tone.darkened(0.7), 0.3)
	if pose == "seated":
		rect(x - 3 * u, y + 3 * u, 10 * u, 9 * u, chair)            # chair back
	var back := pose == "back" or pose == "sit_back"
	if back:
		hair = (HAIR_BACK[posmod(int(x * 0.53 + h * 3.0), HAIR_BACK.size())] as Color).darkened(clampf(0.45 - tone.get_luminance(), 0.0, 0.3))
		rect(x + 1 * u, y + 3.6 * u, 2 * u, 1.6 * u, face)              # the nape
	# Head: a face with a cap of hair, or all hair from behind.
	rect(x, y, 4 * u, 4 * u, hair if back else face)
	if not back and h >= 22.0:
		rect(x, y, 4 * u, 1.3 * u, hair)
	# Shoulders run wider than the head; the torso narrows under them.
	rect(x - 2.5 * u, y + 5 * u, 9 * u, 2 * u, tone)
	rect(x - 1 * u, y + 7 * u, 6 * u, 5 * u, tone)
	if back:
		# Seen from behind we face the room's light: a rim along the crown
		# and the shoulders keeps a dark head legible on a dark room.
		rect(x + 0.5 * u, y - 0.2 * u, 3 * u, 1.1 * u, hair.lightened(0.4))
		rect(x - 2 * u, y + 5 * u, 8 * u, 1 * u, tone.lightened(0.28))
	match pose:
		"arms_up":
			rect(x - 3 * u, y - 2 * u, 1.5 * u, 8 * u, tone)
			rect(x + 5.5 * u, y - 2 * u, 1.5 * u, 8 * u, tone)
			rect(x - 3 * u, y - 3 * u, 1.5 * u, 1.2 * u, face)
			rect(x + 5.5 * u, y - 3 * u, 1.5 * u, 1.2 * u, face)
		"point":
			rect(x - 2.5 * u, y + 5 * u, 1.5 * u, 6 * u, tone)
			rect(x + 5 * u, y + 5.5 * u, 7 * u, 1.5 * u, tone)
			rect(x + 12 * u, y + 5.5 * u, 1.5 * u, 1.5 * u, face)
		"sit_back":
			pass
		_:
			rect(x - 2.5 * u, y + 5 * u, 1.5 * u, 6 * u, tone.darkened(0.12))
			rect(x + 5 * u, y + 5 * u, 1.5 * u, 6 * u, tone.darkened(0.12))
			if not back and h >= 22.0:
				rect(x - 2.5 * u, y + 11 * u, 1.5 * u, 1.2 * u, face)
				rect(x + 5 * u, y + 11 * u, 1.5 * u, 1.2 * u, face)
	match pose:
		"sit":
			return
		"sit_back":
			rect(x - 3 * u, y + 9.5 * u, 10 * u, 3.5 * u, chair)       # chair back
			return
		"seated":
			rect(x - 1.5 * u, y + 11.5 * u, 7 * u, 2 * u, legs)        # lap, knees
			rect(x - 0.5 * u, y + 13.5 * u, 2 * u, 4.5 * u, legs)
			rect(x + 2.5 * u, y + 13.5 * u, 2 * u, 4.5 * u, legs)
			rect(x - 3 * u, y + 12 * u, 1.2 * u, 6 * u, chair)
			rect(x + 5.8 * u, y + 12 * u, 1.2 * u, 6 * u, chair)
			return
	var step := (int(t * 3.0) % 2) if pose == "walk" else -1
	match step:
		0:
			rect(x - 1 * u, y + 12 * u, 2 * u, 6 * u, legs)
			rect(x + 3 * u, y + 12 * u, 2 * u, 6 * u, legs)
		1:
			rect(x + 0.2 * u, y + 12 * u, 2 * u, 6 * u, legs)
			rect(x + 2 * u, y + 12 * u, 2 * u, 6 * u, legs.darkened(0.2))
		_:
			rect(x - 0.3 * u, y + 12 * u, 2 * u, 6 * u, legs)
			rect(x + 2.7 * u, y + 12 * u, 2 * u, 6 * u, legs)


## A face tone matched to how lit the figure's clothes are.
static func _skin(tone: Color) -> Color:
	var k := clampf(tone.get_luminance() / 0.55, 0.3, 1.2)
	return Color(SKIN.r * k, SKIN.g * k, SKIN.b * k)


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
