class_name TitleReveal
extends Control

## A word surfacing from a wall of random capitals: the wall rolls, each of
## the word's letters in turn flickers, locks and brightens to cream, then the
## wall sinks back to a faint texture and `revealed` fires. Laid over the
## title label (whose own text is hidden), so layout and tests still see a
## plain Label with the word in it.

signal revealed

const ALPHABET := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const ROLL_SECONDS := 0.07
const LETTER_GAP := 0.22
const START := 0.35
## How long after the word is found the wall keeps rolling before it freezes.
const SETTLE_SECONDS := 1.5

var word := "ARDENIA"
var font_size := 52
var rows := 3
var cols := 15
var _clock := 0.0
var _rng := RandomNumberGenerator.new()
var _wall := PackedStringArray()
var _rolled_at := -1.0
var _done := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 1993


func _process(delta: float) -> void:
	_clock += delta
	var finish := START + word.length() * LETTER_GAP + 0.5
	# Once the word is found and the wall has faded, it stops rolling: letters
	# changing forever beside the game's name read as unfinished.
	var settled := _clock >= finish + SETTLE_SECONDS
	if not settled and _clock - _rolled_at >= ROLL_SECONDS:
		_rolled_at = _clock
		_wall.resize(rows * cols)
		for i in _wall.size():
			_wall[i] = ALPHABET[_rng.randi_range(0, ALPHABET.length() - 1)]
	if not _done and _clock >= finish:
		_done = true
		revealed.emit()
	queue_redraw()
	if settled:
		set_process(false)


func _draw() -> void:
	if _wall.is_empty():
		return
	var font := get_theme_font("font", "Label")
	var advance := font.get_char_size("M".unicode_at(0), font_size).x
	var line := font_size * 1.05
	var origin := (size - Vector2(advance * cols, line * rows)) * 0.5
	var finish := START + word.length() * LETTER_GAP + 0.5
	# The wall is bright while the word is found, then sinks to a faint texture.
	var wall_alpha := clampf(_clock / START, 0.0, 1.0) * lerpf(0.55, 0.10, clampf((_clock - finish + 0.3) / 1.2, 0.0, 1.0))
	var word_start := (cols - word.length()) / 2
	for r in rows:
		for c in cols:
			var at := origin + Vector2(c * advance, r * line + font.get_ascent(font_size))
			var in_word := r == rows / 2 and c >= word_start and c < word_start + word.length()
			if in_word:
				var k := c - word_start
				var lit := clampf((_clock - START - k * LETTER_GAP) / 0.35, 0.0, 1.0)
				if lit > 0.0:
					var glyph := word[k] if lit >= 0.6 else _wall[r * cols + c]
					draw_string(font, at, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
						UiPalette.TEXT_DIM.lerp(Color(0.95, 0.92, 0.82), lit))
					continue
			var tone := UiPalette.TEXT_FAINT
			tone.a = wall_alpha
			draw_string(font, at, _wall[r * cols + c], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tone)
