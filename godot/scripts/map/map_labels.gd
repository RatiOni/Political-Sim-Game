class_name MapLabels
extends Node2D

const REGION_FONT := "res://assets/pixel/kenney_pixel.ttf"
const CITY_FONT := "res://assets/pixel/kenney_mini.ttf"
const CITY_SIZE := 8
const MARKER := 3
const CITY_GAP := 3
const REGION_LIFT := 6
const PIXEL_FONT_MIN := 16
const OUTLINE: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]

var region_points: Dictionary = {}
var cities: Array[Dictionary] = []
var to_physical: Callable
var region_size := 8
var city_scale := 1
static var _fonts: Dictionary = {}
## The terminal face, like the rest of the desk; the pixel fonts above stay
## loadable through `crisp` for anything still drawn in tiles.
var _region_font: Font = mono()
var _city_font: Font = mono()
## Monospace stops being readable below these sizes, whatever the zoom.
const REGION_MIN := 16
const CITY_MIN := 13


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
	var region_font := _region_font
	var label_size := maxi(REGION_MIN, region_size)
	for id in region_points:
		var text := " ".join(String(id).to_upper().split(""))
		var at: Vector2 = to_physical.call(region_points[id])
		var width := region_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
		_outlined(region_font, (at - Vector2(width / 2.0, REGION_LIFT * label_size / 16.0)).round(), text, label_size, UiPalette.TEXT)
	var city_size := maxi(CITY_MIN, CITY_SIZE * city_scale)
	for city in cities:
		var dot: Vector2 = (to_physical.call(city["point"]) as Vector2).round()
		var marker := float(MARKER * city_scale + (4 if city["capital"] else 2))
		var corner := (dot - Vector2(marker, marker) / 2.0).round()
		var colour := MapPalette.DAY[MapPalette.GOLD if city["capital"] else MapPalette.WALL]
		draw_rect(Rect2(corner - Vector2.ONE, Vector2(marker, marker) + Vector2.ONE * 2), MapPalette.DAY[MapPalette.INK])
		draw_rect(Rect2(corner, Vector2(marker, marker)), colour)
		var baseline := corner + Vector2(marker + CITY_GAP * city_scale, marker / 2.0 + _city_font.get_ascent(city_size) / 2.0)
		_outlined(_city_font, baseline.round(), String(city["name"]), city_size + (2 if city["capital"] else 0), MapPalette.DAY[MapPalette.GOLD if city["capital"] else MapPalette.SNOW])


func _outlined(font: Font, at: Vector2, text: String, font_size: int, colour: Color) -> void:
	for d in OUTLINE:
		draw_string(font, at + d, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, MapPalette.DAY[MapPalette.INK])
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
