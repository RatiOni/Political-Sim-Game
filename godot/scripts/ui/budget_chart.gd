class_name BudgetChart
extends Control

## Composition chart for budget lines. Fixed height (set in the scene),
## clips to its rect, so changing values never resizes the panel.
## Only positive values are plotted; negative lines are left to the table.

enum Mode { DONUT, PIE, BARS, STACKED }
const MODE_NAMES := ["DONUT", "PIE", "BARS", "STACKED BAR"]

## Muted, mutually distinct inks that sit on near-black glass.
const COLORS := [
	Color(0.89, 0.60, 0.23), Color(0.45, 0.62, 0.66), Color(0.56, 0.66, 0.38),
	Color(0.70, 0.45, 0.40), Color(0.62, 0.55, 0.72), Color(0.78, 0.72, 0.48),
	Color(0.42, 0.50, 0.42), Color(0.60, 0.60, 0.56),
]

var mode: Mode = Mode.DONUT:
	set(value):
		mode = value
		queue_redraw()

var _items: Array[Dictionary] = []
var _total := 0.0


func _ready() -> void:
	clip_contents = true


## items: [{name: String, value: float}]
func set_items(items: Array) -> void:
	_items.clear()
	_total = 0.0
	for item: Dictionary in items:
		var value := float(item.get("value", 0.0))
		if value > 0.0:
			_items.append({"name": String(item.get("name", "")).to_upper(), "value": value})
			_total += value
	queue_redraw()


static func color_for(index: int) -> Color:
	return COLORS[index % COLORS.size()]


func _draw() -> void:
	if _items.is_empty() or _total <= 0.0:
		_text(Vector2(4, 18), "NO DATA", UiPalette.TEXT_FAINT)
		return
	match mode:
		Mode.PIE, Mode.DONUT:
			_draw_round(mode == Mode.DONUT)
		Mode.BARS:
			_draw_bars()
		Mode.STACKED:
			_draw_stacked()


func _draw_round(donut: bool) -> void:
	var radius := minf(size.y, size.x * 0.4) * 0.5 - 4.0
	var center := Vector2(radius + 4.0, size.y * 0.5)
	var angle := -PI * 0.5
	for i in _items.size():
		var sweep := TAU * float(_items[i]["value"]) / _total
		var points := PackedVector2Array([center])
		var steps := maxi(2, int(sweep * 24.0))
		for s in steps + 1:
			points.append(center + Vector2.from_angle(angle + sweep * s / steps) * radius)
		draw_colored_polygon(points, color_for(i))
		angle += sweep
	if donut:
		draw_circle(center, radius * 0.55, UiPalette.PANEL)
		_text(center + Vector2(-radius * 0.45, 5), "%.0f M" % _total, UiPalette.TEXT)
	_draw_legend(center.x + radius + 12.0)


func _draw_legend(x: float) -> void:
	var row_h := minf(18.0, size.y / _items.size())
	var y := (size.y - row_h * _items.size()) * 0.5
	for i in _items.size():
		draw_rect(Rect2(x, y + row_h * 0.5 - 4.0, 8, 8), color_for(i))
		_row_text(x + 14.0, y, row_h, i)
		y += row_h


func _draw_bars() -> void:
	var row_h := minf(28.0, size.y / _items.size())
	var label_w := size.x * 0.42
	var largest := 0.0
	for item in _items:
		largest = maxf(largest, float(item["value"]))
	for i in _items.size():
		var y := row_h * i
		var pct := 100.0 * float(_items[i]["value"]) / _total
		_text(Vector2(0, y + row_h * 0.5 + 5), _clip(String(_items[i]["name"]), label_w), UiPalette.TEXT_DIM)
		var bar_w := (size.x - label_w - 52.0) * float(_items[i]["value"]) / largest
		draw_rect(Rect2(label_w, y + row_h * 0.2, bar_w, row_h * 0.6), color_for(i))
		_text(Vector2(label_w + bar_w + 4.0, y + row_h * 0.5 + 5), "%.1f%%" % pct, UiPalette.TEXT)


func _draw_stacked() -> void:
	var bar_h := minf(24.0, size.y * 0.25)
	var x := 0.0
	for i in _items.size():
		var w := size.x * float(_items[i]["value"]) / _total
		draw_rect(Rect2(x, 0, w, bar_h), color_for(i))
		x += w
	# Legend in two columns beneath the bar.
	var rows := ceili(_items.size() / 2.0)
	var row_h := minf(18.0, (size.y - bar_h - 6.0) / rows)
	for i in _items.size():
		var col_x := (i % 2) * size.x * 0.5
		var y := bar_h + 6.0 + row_h * (i / 2)
		draw_rect(Rect2(col_x, y + row_h * 0.5 - 4.0, 8, 8), color_for(i))
		_row_text(col_x + 14.0, y, row_h, i, size.x * 0.5 - 18.0)


func _row_text(x: float, y: float, row_h: float, i: int, width: float = -1.0) -> void:
	var pct := 100.0 * float(_items[i]["value"]) / _total
	var avail := (size.x - x) if width < 0.0 else width
	var tail := " %.1f%%" % pct
	var name_w := avail - _font().get_string_size(tail, HORIZONTAL_ALIGNMENT_LEFT, -1, _size()).x
	_text(Vector2(x, y + row_h * 0.5 + 5), _clip(String(_items[i]["name"]), name_w) + tail, UiPalette.TEXT_DIM)


func _clip(text: String, width: float) -> String:
	var font := _font()
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _size()).x <= width:
		return text
	while text.length() > 1 and font.get_string_size(text + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, _size()).x > width:
		text = text.substr(0, text.length() - 1)
	return text + "…"


func _text(pos: Vector2, text: String, color: Color) -> void:
	draw_string(_font(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _size(), color)


func _font() -> Font:
	return get_theme_default_font()


func _size() -> int:
	return 13
