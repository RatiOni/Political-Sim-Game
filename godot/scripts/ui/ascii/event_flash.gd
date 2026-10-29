class_name EventFlash
extends Control

## A newsreel title card for a national moment (an election): the screen
## burns to cream, a shockwave runs out, a headline surfaces from a wall of
## rolling capitals with the result beneath it, then the card fades and the
## desk returns. Drawn as a smooth card and shown through `AsciiConvert`.
## It never takes input, so the game carries on underneath.

const HOLD := 4.6
const FADE := 0.9

var headline := "ELECTION"
var lines: Array[String] = []
var _clock := 0.0
var _ascii: AsciiConvert


static func show_on(host: Control, title: String, details: Array[String]) -> EventFlash:
	var card := EventFlash.new()
	card.headline = title
	card.lines = details
	host.add_child(card)
	return card


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	z_index = 100
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	var reveal := TitleReveal.new()
	reveal.word = headline
	reveal.cols = maxi(headline.length() + 6, 15)
	reveal.font_size = 64
	reveal.position = Vector2(0, size.y * 0.30)
	reveal.size = Vector2(size.x, 64 * 3.4)
	add_child(reveal)
	_ascii = AsciiConvert.cover(self, "dusk")
	_ascii.burst(Vector2(0.5, 0.42), 2.2)


func _process(delta: float) -> void:
	_clock += delta
	if _clock > HOLD:
		modulate.a = clampf(1.0 - (_clock - HOLD) / FADE, 0.0, 1.0)
	if _clock > HOLD + FADE:
		queue_free()
	queue_redraw()


func _draw() -> void:
	# The card: a dark print with a vignette and a slow light passing across,
	# so even the still frame breathes under the converter.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.06), true)
	var sweep := fposmod(_clock * 0.25, 1.4) - 0.2
	draw_set_transform(Vector2(size.x * sweep, size.y * 0.45), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, size.x * 0.35, Color(0.45, 0.32, 0.20, 0.10))
	draw_set_transform(Vector2.ZERO)
	var font := get_theme_font("font", "Label")
	var y := size.y * 0.30 + 64 * 3.6
	for i in lines.size():
		var appear := clampf((_clock - 2.4 - i * 0.35) / 0.4, 0.0, 1.0)
		if appear <= 0.0:
			continue
		var text := lines[i].to_upper()
		var fs := 26 if i == 0 else 20
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2((size.x - w) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(0.93, 0.88, 0.74, appear) if i == 0 else Color(0.80, 0.62, 0.36, appear))
		y += fs * 1.6
	for k in 2:   # newsreel rules above and below the result
		var ry := size.y * (0.27 if k == 0 else 0.80)
		draw_rect(Rect2(size.x * 0.25, ry, size.x * 0.5, 2.0), Color(0.6, 0.5, 0.35, 0.6), true)
