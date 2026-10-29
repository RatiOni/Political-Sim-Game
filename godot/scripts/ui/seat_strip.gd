@tool
class_name SeatStrip
extends Control

## The National Assembly as seats, not as a sentence. One pixel block per
## seat, laid out in rows and coloured by party, with a gold majority mark.
## A glance should answer "can the government carry a vote" before any
## number is read.

const SEAT := 7
const GAP := 2
const ROW_GAP := 3

var _rows: Array = []          # [{color, seats, name, in_coalition}]
var _total := 0
var _coalition := 0
var _font: Font
var _font_size := 13


func _ready() -> void:
	_font = get_theme_font("font", "Label")
	_font_size = get_theme_font_size("font_size", "Label")


## `factions` are snapshot rows: name, seats, color (web hex), in_coalition.
func set_factions(factions: Array) -> void:
	_rows.clear()
	_total = 0
	_coalition = 0
	var sorted := factions.duplicate()
	# Government first, then by size: the chamber reads left to right as
	# "who governs, and by how much".
	sorted.sort_custom(func(a, b):
		var ca := bool(a.get("in_coalition", false))
		var cb := bool(b.get("in_coalition", false))
		if ca != cb:
			return ca
		return int(a.get("seats", 0)) > int(b.get("seats", 0)))
	var hexes: Array = []
	for faction in sorted:
		hexes.append(String(faction.get("color", "")))
	var colors := UiPalette.party_colors(hexes)
	for i in sorted.size():
		var faction: Dictionary = sorted[i]
		var seats := int(faction.get("seats", 0))
		if seats <= 0:
			continue
		var in_coalition := bool(faction.get("in_coalition", false))
		_rows.append({
			"color": colors[i],
			"seats": seats,
			"name": String(faction.get("name", "—")),
			"in_coalition": in_coalition,
		})
		_total += seats
		if in_coalition:
			_coalition += seats
	_update_height()
	queue_redraw()


func _update_height() -> void:
	var per_row := _seats_per_row()
	var seat_rows := 0 if per_row <= 0 else int(ceil(float(_total) / per_row))
	var chamber_h := seat_rows * (SEAT + GAP) + 10
	var legend_h := _rows.size() * (_font_size + 7)
	custom_minimum_size.y = chamber_h + legend_h + 6


func _seats_per_row() -> int:
	return maxi(1, int(size.x) / (SEAT + GAP))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_height()
		queue_redraw()


func _draw() -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	if _total <= 0:
		draw_string(_font, Vector2(0, _font_size), "Awaiting assembly figures.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, UiPalette.TEXT_FAINT)
		return

	var per_row := _seats_per_row()
	var majority := _total / 2 + 1
	var index := 0

	# The chamber. Seats run in party order so each party is one solid block.
	# Government seats are filled, opposition seats are hollow — a tint or a
	# gold cap would vanish on the gold party, and the governing bloc has to
	# be countable whatever colours the content authors chose.
	for row in _rows:
		for _i in int(row["seats"]):
			var rx := index % per_row
			var ry := index / per_row
			var at := Vector2(rx * (SEAT + GAP), ry * (SEAT + GAP))
			var rect := Rect2(at, Vector2(SEAT, SEAT))
			if bool(row["in_coalition"]):
				draw_rect(rect, row["color"], true)
			else:
				draw_rect(rect, UiPalette.WINDOW, true)
				draw_rect(rect, row["color"], false, 1.0)
			index += 1

	var seat_rows := int(ceil(float(_total) / per_row))
	var chamber_bottom := seat_rows * (SEAT + GAP)

	# Majority mark: a gold tick under the seat that carries the chamber.
	var mx := (majority - 1) % per_row
	var my := (majority - 1) / per_row
	if my < seat_rows:
		draw_rect(Rect2(mx * (SEAT + GAP), my * (SEAT + GAP) + SEAT, SEAT, 2), UiPalette.GOLD, true)

	var y := chamber_bottom + 10.0
	var carried := _coalition >= majority
	var verdict := "%d of %d · majority %d" % [_coalition, _total, majority]
	draw_string(_font, Vector2(0, y), verdict, HORIZONTAL_ALIGNMENT_LEFT, -1,
		_font_size, UiPalette.GOOD if carried else UiPalette.BAD)
	y += _font_size + 7

	# Legend: swatch, party, seats — swatch filled or hollow to match the
	# chamber, so the legend teaches the chamber's notation.
	for row in _rows:
		var swatch := Rect2(Vector2(0, y - _font_size + 3), Vector2(SEAT, SEAT))
		if bool(row["in_coalition"]):
			draw_rect(swatch, row["color"], true)
		else:
			draw_rect(swatch, row["color"], false, 1.0)
		var name_col: Color = UiPalette.TEXT if bool(row["in_coalition"]) else UiPalette.TEXT_DIM
		var seats_text := str(int(row["seats"]))
		var seats_w := _font.get_string_size(seats_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x
		var name_w := size.x - (SEAT + 6) - seats_w - 6
		draw_string(_font, Vector2(SEAT + 6, y), _fit(String(row["name"]), name_w),
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, name_col)
		draw_string(_font, Vector2(size.x - seats_w, y), seats_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, name_col)
		y += _font_size + 7


## Trim to an ellipsis on a whole character. `draw_string`'s own width clip
## cuts mid-glyph, which looked like a rendering fault ("National Conservativ").
func _fit(text: String, width: float) -> String:
	if _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x <= width:
		return text
	var out := text
	while out.length() > 1:
		out = out.substr(0, out.length() - 1)
		if _font.get_string_size(out + ".", HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x <= width:
			return out.strip_edges() + "."
	return out
