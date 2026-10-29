class_name UiPalette
extends RefCounted

## The dashboard's colours: a Third Bloc-style control-room terminal.
## Mirrored in `theme/ardenia_theme.tres`; change one, change the other.

# Surfaces: control-room glass. Panels are outlined, not filled; the
# frame line is what separates them (see `TerminalFrame`).
static var WINDOW := Color(0.043, 0.051, 0.043)  # the room
static var PANEL := Color(0.051, 0.059, 0.051)   # panel glass
static var RAISED := Color(0.09, 0.10, 0.09)     # hovered rows
static var EDGE := Color(0.39, 0.40, 0.37)       # frame lines
static var TRACK := Color(0.16, 0.17, 0.15)      # empty gauge cells

# Ink: cream values, dim keys.
static var TEXT := Color(0.90, 0.88, 0.81)
static var TEXT_DIM := Color(0.55, 0.55, 0.50)
static var TEXT_FAINT := Color(0.36, 0.36, 0.33)

# State. Amber says "this is the live thing"; red is reserved for alarm.
static var GOLD := Color(0.89, 0.60, 0.23)       # amber
static var GOLD_DARK := Color(0.55, 0.36, 0.13)
static var GOOD := Color(0.56, 0.66, 0.38)
static var WARN := Color(0.89, 0.60, 0.23)
static var BAD := Color(0.83, 0.32, 0.25)

## Party colours in the content are web hex (`#3b7dd8`) and look wrong beside
## VGA tiles. Snap each to the nearest of a party-safe set taken from the same
## 32 colours, so the assembly reads as part of the same picture.
static var PARTY := PackedColorArray([
	Color8(232, 184, 56),   # gold
	Color8(56, 112, 176),   # river blue
	Color8(208, 40, 40),    # red
	Color8(108, 152, 64),   # grass
	Color8(176, 64, 48),    # roof rust
	Color8(148, 136, 124),  # pale rock
	Color8(168, 148, 72),   # farm ochre
	Color8(112, 100, 92),   # rock
])


## Nearest party colour to a `#rrggbb` string, by squared RGB distance.
## Unknown or empty input falls back to pale rock rather than black, so a
## faction with no authored colour still reads as a faction.
static func party_color(hex: String) -> Color:
	return PARTY[_nearest_index(hex, {})]


## Distinct colour per party, in the order given.
##
## Nearest-match alone is not enough: Ardenia authors two reds (`#d9534f`
## Social Democrats, `#c0392b` Workers' Front) that snap to the same VGA
## entry and then read as one bloc in the chamber. Each party takes its
## nearest colour that is still free, so the assembly is always countable.
static func party_colors(hexes: Array) -> Array:
	var taken := {}
	var out: Array = []
	for hex in hexes:
		var index := _nearest_index(String(hex), taken)
		taken[index] = true
		out.append(PARTY[index])
	return out


static func _nearest_index(hex: String, taken: Dictionary) -> int:
	var want := Color(hex) if hex.is_valid_html_color() else Color(PARTY[5])
	var best := -1
	var best_d := INF
	for i in PARTY.size():
		if taken.has(i):
			continue
		var c := PARTY[i]
		var d := (c.r - want.r) ** 2 + (c.g - want.g) ** 2 + (c.b - want.b) ** 2
		if d < best_d:
			best_d = d
			best = i
	# More parties than colours: fall back to reuse rather than crash.
	return best if best >= 0 else 5


## Colour for a 0..1 reading where higher is better (approval, reach).
static func good_scale(value: float) -> Color:
	if value >= 0.55:
		return GOOD
	return WARN if value >= 0.35 else BAD


## Colour for a reading where higher is worse (unemployment, debt), against
## the thresholds the caller considers ordinary and alarming.
static func risk_scale(value: float, ordinary: float, alarming: float) -> Color:
	if value <= ordinary:
		return GOOD
	return WARN if value <= alarming else BAD
