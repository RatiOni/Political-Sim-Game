class_name MapPalette
extends RefCounted

enum {
	DEEP_SEA, SEA, WAVE, SHALLOWS, SAND, SAND_DARK, GRASS, GRASS_DARK, GRASS_LIGHT,
	FARM, FARM_DARK, FARM_GREEN, FOREST, FOREST_DARK, TRUNK, HILL, HILL_DARK,
	ROCK, ROCK_DARK, ROCK_LIGHT, SNOW, SNOW_SHADE, RIVER, GOLD, GOLD_DARK, CEASEFIRE,
	ROOF, WALL, ROAD, RAIL, LIT, INK,
}

const EMISSIVE: Array[int] = [LIT, GOLD, GOLD_DARK, CEASEFIRE]
const DUSK_TINT := Vector3(0.38, 0.36, 0.6)

static var DAY := PackedColorArray([
	Color8(16, 36, 88), Color8(28, 60, 124), Color8(56, 96, 160), Color8(48, 104, 152),
	Color8(212, 188, 120), Color8(184, 156, 96),
	Color8(84, 132, 52), Color8(64, 108, 44), Color8(108, 152, 64),
	Color8(168, 148, 72), Color8(136, 112, 56), Color8(96, 124, 48),
	Color8(36, 84, 40), Color8(24, 60, 32), Color8(72, 52, 28),
	Color8(116, 112, 64), Color8(88, 84, 52),
	Color8(112, 100, 92), Color8(80, 72, 68), Color8(148, 136, 124),
	Color8(232, 236, 244), Color8(176, 188, 208),
	Color8(56, 112, 176), Color8(232, 184, 56), Color8(152, 104, 24), Color8(208, 40, 40),
	Color8(176, 64, 48), Color8(220, 208, 184), Color8(120, 88, 56), Color8(40, 36, 40),
	Color8(255, 220, 96), Color8(8, 8, 16),
])

static var DUSK := _dusk_of(DAY)

static var FOREIGN := PackedColorArray([
	Color8(20, 22, 22), Color8(34, 38, 36), Color8(48, 52, 48), Color8(62, 66, 60),
	Color8(76, 80, 72), Color8(90, 94, 84), Color8(108, 110, 100), Color8(132, 134, 124),
	Color8(164, 164, 156), Color8(200, 200, 194),
])

static var FOREIGN_DUSK := _dusk_of(FOREIGN, [])


static func _dusk_of(day: PackedColorArray, emissive: Array[int] = EMISSIVE) -> PackedColorArray:
	var out := PackedColorArray()
	for i in day.size():
		var c := day[i]
		out.append(c if i in emissive else Color8(roundi(c.r8 * DUSK_TINT.x), roundi(c.g8 * DUSK_TINT.y), roundi(c.b8 * DUSK_TINT.z)))
	return out


static func nearest_foreign(c: Color) -> int:
	var lum := c.get_luminance()
	var best := 0
	for i in FOREIGN.size():
		if absf(FOREIGN[i].get_luminance() - lum) < absf(FOREIGN[best].get_luminance() - lum):
			best = i
	return best
