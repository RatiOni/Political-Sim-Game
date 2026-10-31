class_name StatusNotice
extends Node

## One line of feedback for what the player just did: in the header for a few
## seconds, green or red, then gone; the footer keeps the last one. The header
## used to keep only a message's last word, so "SAVED / READY" showed "READY"
## and a save looked like nothing had happened.

var seconds := 3.0
var _header: Label
var _footer: Label
var _timer := Timer.new()


func bind(header: Label, footer: Label) -> void:
	_header = header
	_footer = footer
	_timer.one_shot = true
	_timer.timeout.connect(func() -> void: _header.text = "")
	add_child(_timer)
	_header.text = ""
	_footer.text = "MINISTERIAL WIRE"


func say(message: String, failed: bool = false) -> void:
	_header.text = message
	_header.add_theme_color_override("font_color", UiPalette.BAD if failed else UiPalette.GOOD)
	_footer.text = "MINISTERIAL WIRE  /  %s" % message
	_timer.start(seconds)
