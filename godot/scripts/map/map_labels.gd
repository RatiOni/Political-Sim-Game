class_name MapLabels
extends Control

const REGION_FONT := "res://assets/pixel/kenney_pixel.ttf"
const CITY_FONT := "res://assets/pixel/kenney_mini.ttf"
const REGION_SIZE := 16
const CITY_SIZE := 8
const MARKER := 3
const CITY_GAP := 3
const REGION_LIFT := 6
const OUTLINE: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]

var region_points: Dictionary = {}
var cities: Array[Dictionary] = []
var to_local: Callable
var zoom := 1
var _region_font := _crisp(REGION_FONT)
var _city_font := _crisp(CITY_FONT)


static func _crisp(path: String) -> FontFile:
	var font := (load(path) as FontFile).duplicate() as FontFile
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.generate_mipmaps = false
	return font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	if not to_local.is_valid():
		return
	for id in region_points:
		var text := String(id).to_upper()
		var at: Vector2 = to_local.call(region_points[id])
		var width := _region_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, REGION_SIZE * zoom).x
		_outlined(_region_font, (at - Vector2(width / 2.0, REGION_LIFT * zoom)).round(), text, REGION_SIZE * zoom, MapPalette.DAY[MapPalette.SNOW])
	for city in cities:
		var dot: Vector2 = (to_local.call(city["point"]) as Vector2).round()
		var marker := float(MARKER * zoom)
		var colour := MapPalette.DAY[MapPalette.GOLD if city["capital"] else MapPalette.WALL]
		draw_rect(Rect2(dot - Vector2(marker, marker) / 2.0 - Vector2.ONE * zoom, Vector2(marker, marker) + Vector2.ONE * zoom * 2), MapPalette.DAY[MapPalette.INK])
		draw_rect(Rect2(dot - Vector2(marker, marker) / 2.0, Vector2(marker, marker)), colour)
		var baseline := dot + Vector2(marker / 2.0 + CITY_GAP * zoom, _city_font.get_ascent(CITY_SIZE * zoom) / 2.0)
		_outlined(_city_font, baseline.round(), String(city["name"]), CITY_SIZE * zoom, MapPalette.DAY[MapPalette.WALL])


func _outlined(font: Font, at: Vector2, text: String, font_size: int, colour: Color) -> void:
	for d in OUTLINE:
		draw_string(font, at + d * zoom, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, MapPalette.DAY[MapPalette.INK])
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
