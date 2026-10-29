class_name PixelChart
extends Control

## A DOS-plotter chart: stepped lines and blocky bars on a ruled field.
## No curves, no anti-aliasing, no gradients — it has to sit beside an 8 px
## tile map without looking like it came from a different program.
##
## Two modes, set by `plot_lines` or `plot_bars`. Both share the axis, the
## gridlines and the zero rule.

const PAD_L := 52
const PAD_R := 10
const PAD_T := 10
const PAD_B := 22

var title: String = ""
var _lines: Array = []       # [{name, color, points: Array[float]}]
var _bars: Array = []        # [float]
var _bar_labels: Array = []
var _x_labels: Array = []
var _y_min := 0.0
var _y_max := 1.0
var _format := "%.0f%%"
var _zero_rule := false
var _font: Font
var _font_size := 13


func _init() -> void:
	custom_minimum_size = Vector2(0, 150)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_font = get_theme_font("font", "Label")
	_font_size = 13


## `series` is [{name, color, points}]. Points are plotted left to right,
## oldest first. Pass `format` for the axis labels, e.g. "%.1f%%".
func plot_lines(series: Array, x_labels: Array, format: String = "%.0f%%", pad: float = 0.1) -> void:
	_lines = series
	_bars = []
	_x_labels = x_labels
	_format = format
	var lo := INF
	var hi := -INF
	for s in series:
		for p in s.get("points", []):
			lo = minf(lo, float(p))
			hi = maxf(hi, float(p))
	if lo == INF:
		lo = 0.0
		hi = 1.0
	_apply_range(lo, hi, pad)
	_zero_rule = _y_min < 0.0 and _y_max > 0.0
	queue_redraw()


## Signed bars — a deficit drops below the zero rule.
func plot_bars(values: Array, labels: Array, format: String = "%.0f") -> void:
	_bars = values
	_lines = []
	_bar_labels = labels
	_format = format
	var lo := 0.0
	var hi := 0.0
	for v in values:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	_apply_range(lo, hi, 0.15)
	_zero_rule = true
	queue_redraw()


func _apply_range(lo: float, hi: float, pad: float) -> void:
	if is_equal_approx(lo, hi):
		hi = lo + maxf(1.0, absf(lo) * 0.1)
	var span := hi - lo
	_y_min = lo - span * pad
	_y_max = hi + span * pad
	# Keep zero on the axis when the data straddles it, so the zero rule
	# means what it looks like it means.
	if lo >= 0.0 and _y_min < 0.0:
		_y_min = 0.0


func _field() -> Rect2:
	return Rect2(PAD_L, PAD_T, maxf(10.0, size.x - PAD_L - PAD_R), maxf(10.0, size.y - PAD_T - PAD_B))


func _y_at(value: float) -> float:
	var f := _field()
	var t := (value - _y_min) / maxf(0.0001, _y_max - _y_min)
	return f.position.y + f.size.y * (1.0 - clampf(t, 0.0, 1.0))


func _draw() -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	var f := _field()
	draw_rect(f, UiPalette.TRACK, true)

	var empty := _lines.is_empty() and _bars.is_empty()
	if empty:
		draw_string(_font, f.position + Vector2(8, f.size.y * 0.5), "No record yet.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, UiPalette.TEXT_FAINT)
		_frame(f)
		return

	# Horizontal gridlines, dotted so they stay behind the data.
	for i in 5:
		var value := lerpf(_y_min, _y_max, float(i) / 4.0)
		var y := roundf(_y_at(value))
		for x in range(int(f.position.x), int(f.position.x + f.size.x), 4):
			draw_rect(Rect2(x, y, 2, 1), UiPalette.EDGE, true)
		draw_string(_font, Vector2(2, y + 4), _format % value,
			HORIZONTAL_ALIGNMENT_RIGHT, PAD_L - 6, _font_size, UiPalette.TEXT_FAINT)

	if _zero_rule:
		var zy := roundf(_y_at(0.0))
		draw_rect(Rect2(f.position.x, zy, f.size.x, 1), UiPalette.TEXT_DIM, true)

	if not _bars.is_empty():
		_draw_bars(f)
	else:
		_draw_lines(f)

	_frame(f)
	if not title.is_empty():
		draw_string(_font, Vector2(PAD_L, PAD_T - 1), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, UiPalette.TEXT_DIM)


func _draw_bars(f: Rect2) -> void:
	var n := _bars.size()
	var slot := f.size.x / float(n)
	var w := maxf(3.0, slot - 3.0)
	var zero := _y_at(0.0)
	for i in n:
		var v := float(_bars[i])
		var y := _y_at(v)
		var x := f.position.x + slot * i + (slot - w) * 0.5
		var top := minf(y, zero)
		var height := maxf(1.0, absf(zero - y))
		draw_rect(Rect2(roundf(x), roundf(top), roundf(w), roundf(height)),
			UiPalette.GOOD if v >= 0.0 else UiPalette.BAD, true)
		if i < _bar_labels.size() and (n <= 12 or i % 2 == 0):
			draw_string(_font, Vector2(roundf(x) - 4, size.y - 6), str(_bar_labels[i]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, UiPalette.TEXT_FAINT)


func _draw_lines(f: Rect2) -> void:
	for s in _lines:
		var points: Array = s.get("points", [])
		if points.is_empty():
			continue
		var color: Color = s.get("color", UiPalette.GOLD)
		var step := f.size.x / maxf(1.0, float(points.size() - 1))
		var prev := Vector2.ZERO
		for i in points.size():
			var x := f.position.x + step * i
			var y := _y_at(float(points[i]))
			var at := Vector2(roundf(x), roundf(y))
			if i > 0:
				_step_line(prev, at, color)
			# Sparse series (one point per election) are mostly long flat
			# runs, so the samples need a visible marker or the chart reads
			# as a stack of rectangles rather than as data.
			if points.size() <= 12:
				draw_rect(Rect2(at.x - 2, at.y - 2, 5, 5), UiPalette.WINDOW, true)
				draw_rect(Rect2(at.x - 2, at.y - 2, 5, 5), color, false, 1.0)
				draw_rect(Rect2(at.x - 1, at.y - 1, 3, 3), color, true)
			elif points.size() <= 48:
				draw_rect(Rect2(at.x - 1, at.y - 1, 2, 2), color, true)
			prev = at

	# Series key, bottom left.
	var kx := f.position.x
	for s in _lines:
		var name := String(s.get("name", ""))
		if name.is_empty():
			continue
		var color: Color = s.get("color", UiPalette.GOLD)
		draw_rect(Rect2(kx, size.y - 13, 6, 6), color, true)
		draw_string(_font, Vector2(kx + 9, size.y - 6), name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, UiPalette.TEXT_DIM)
		kx += 9 + _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x + 12


## A plotter draws in steps, not diagonals: horizontal run then vertical jump.
func _step_line(from: Vector2, to: Vector2, color: Color) -> void:
	var x0 := minf(from.x, to.x)
	var w := maxf(1.0, absf(to.x - from.x))
	draw_rect(Rect2(x0, from.y, w, 1), color, true)
	var y0 := minf(from.y, to.y)
	var h := maxf(1.0, absf(to.y - from.y))
	draw_rect(Rect2(to.x, y0, 1, h), color, true)


func _frame(f: Rect2) -> void:
	draw_rect(f, UiPalette.EDGE, false, 1.0)
