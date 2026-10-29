@tool
class_name StatBar
extends Control

## A DOS-style segmented readout: label, figure, and a track of discrete
## blocks. Blocks, not a smooth fill — a continuous bar beside an 8 px tile
## map reads as a different era.
##
## Per the dashboard convention (CLAUDE.md), a bar is only for a bounded 0..1
## value where higher is better. Use `set_figure` for growth / inflation /
## debt, which get a figure and a trend glyph and no track.

const SEGMENTS := 12
const SEG_W := 6
const SEG_H := 10
const GAP := 2
const ROW_H := 34

@export var label_text: String = "Metric":
	set(value):
		label_text = value
		queue_redraw()

## 0..1. Negative means "no track" — figure-only mode.
@export_range(-1.0, 1.0) var value: float = -1.0:
	set(v):
		value = v
		queue_redraw()

@export var figure_text: String = "—":
	set(v):
		figure_text = v
		queue_redraw()

## -1 falling, 0 steady, +1 rising. Drawn as a pixel arrow beside the figure.
@export_range(-1, 1) var trend: int = 0:
	set(v):
		trend = v
		queue_redraw()

## When true a rising trend is bad (unemployment, inflation, debt) and the
## glyph colours accordingly.
@export var rising_is_bad: bool = false

@export var fill_color: Color = UiPalette.GOLD:
	set(v):
		fill_color = v
		queue_redraw()

var _font: Font
var _font_size := 14


func _init() -> void:
	custom_minimum_size = Vector2(0, ROW_H)


func _ready() -> void:
	_font = get_theme_font("font", "Label")
	_font_size = get_theme_font_size("font_size", "Label")


func _draw() -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	var w := size.x
	var baseline := float(_font_size)

	# Label left, figure right — one row, tabular, never reflowing.
	draw_string(_font, Vector2(0, baseline), label_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, UiPalette.TEXT_DIM)

	var fig_w := _font.get_string_size(figure_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x
	var trend_w := 10.0 if trend != 0 else 0.0
	draw_string(_font, Vector2(w - fig_w - trend_w, baseline), figure_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, UiPalette.TEXT)

	if trend != 0:
		_draw_trend(Vector2(w - trend_w + 2, baseline - 6))

	if value < 0.0:
		return

	# Track: one unlit block per segment, lit blocks up to the value.
	var lit := int(round(clampf(value, 0.0, 1.0) * SEGMENTS))
	var top := baseline + 6
	for i in SEGMENTS:
		var x := float(i * (SEG_W + GAP))
		var rect := Rect2(x, top, SEG_W, SEG_H)
		draw_rect(rect, UiPalette.TRACK, true)
		if i < lit:
			draw_rect(rect, fill_color, true)
		else:
			# A one-pixel ghost keeps the empty track legible on dark panel.
			draw_rect(Rect2(x, top + SEG_H - 1, SEG_W, 1), UiPalette.EDGE, true)


## A 5x5 pixel chevron — no font glyph, so it stays crisp at any scale.
func _draw_trend(at: Vector2) -> void:
	var rising := trend > 0
	var bad := rising == rising_is_bad
	var col := UiPalette.BAD if bad else UiPalette.GOOD
	for row in 3:
		var width := 1 + row * 2
		var x := at.x + (5 - width) * 0.5
		var y := at.y + (row if rising else 2 - row) * 2.0
		draw_rect(Rect2(x, y, width, 2), col, true)


## Figure-only row: no track, for unbounded or lower-is-better readings.
func set_figure(label: String, figure: String, direction: int = 0, bad_when_rising: bool = false) -> void:
	label_text = label
	figure_text = figure
	trend = direction
	rising_is_bad = bad_when_rising
	value = -1.0
	custom_minimum_size.y = 22


## Bounded 0..1 row with a track.
func set_meter(label: String, amount: float, figure: String, color: Color) -> void:
	label_text = label
	value = clampf(amount, 0.0, 1.0)
	figure_text = figure
	fill_color = color
	custom_minimum_size.y = ROW_H
