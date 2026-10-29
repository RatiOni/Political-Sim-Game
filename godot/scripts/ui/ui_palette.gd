class_name UiPalette
extends RefCounted

## The dashboard's colours, drawn from the same VGA set as the map
## (`MapPalette.DAY`) so chrome and cartography cannot drift apart.
## Indices below are into that array — never hardcode a hex here that the
## map does not already use, or the two art directions split again.

# Surfaces: a dark ramp under the map's ink, wide enough that a panel reads
# as a panel. Four steps, each a clear value apart.
static var WINDOW := Color8(8, 8, 16)        # MapPalette INK — the room
static var PANEL := Color8(20, 22, 34)       # card surface
static var RAISED := Color8(32, 34, 50)      # controls, hovered rows
static var EDGE := Color8(72, 76, 100)       # hairline borders
static var TRACK := Color8(14, 14, 24)       # behind a bar fill

# Ink
static var TEXT := Color8(232, 236, 244)     # MapPalette SNOW
static var TEXT_DIM := Color8(176, 188, 208) # MapPalette SNOW_SHADE
static var TEXT_FAINT := Color8(120, 124, 148)

# Accent + state. GOLD and the ceasefire red are literally the map's.
static var GOLD := Color8(232, 184, 56)      # MapPalette GOLD
static var GOLD_DARK := Color8(152, 104, 24) # MapPalette GOLD_DARK
static var GOOD := Color8(108, 152, 64)      # MapPalette GRASS_LIGHT
static var WARN := Color8(232, 184, 56)
static var BAD := Color8(208, 40, 40)        # MapPalette CEASEFIRE

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
