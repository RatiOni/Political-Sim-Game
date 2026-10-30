class_name CityKit
extends RefCounted

## The shared kit for the regional city scenes (`RegionCity`): the time-of-day
## tones and the street furniture every town is built from — facades with
## their windows, lamp posts and their pools of light, cars, buses, trams,
## lorries, fires and smoke. Everything draws through a `DeskView`, in the
## same large deliberate shapes as the desk rooms, so a town and the
## parliament chamber read as one game once the converter has printed them.

## Window grid of a facade, in authoring units: storey height, window size
## and spacing. Big enough that a window is two cells across in the panel.
const STOREY := 16.0
const WIN := Vector2(6, 9)
const BAY := 11.0
const OLIVE := Color(0.26, 0.30, 0.18)
const POLICE := Color(0.13, 0.16, 0.26)
const HI_VIS := Color(0.95, 0.58, 0.14)
const SIREN_BLUE := Color(0.35, 0.55, 1.0)
const LIVERY := [Color(0.58, 0.20, 0.15), Color(0.22, 0.30, 0.44), Color(0.34, 0.38, 0.26),
	Color(0.52, 0.46, 0.30), Color(0.40, 0.40, 0.42), Color(0.16, 0.16, 0.18)]


## A stable 0..1 roll per feature: the same window stays lit, the same shop
## stays shuttered, for as long as the figures that decide it hold.
static func roll(s: int, a: int, b: int = 0) -> float:
	return float(absi(hash([s, a, b])) % 10007) / 10007.0


## x positions every `step` from `offset`, covering the visible span.
static func span(v: DeskView, step: float, offset: float = 0.0) -> Array:
	var out := []
	var first := int(floorf((v.left - offset) / step)) - 1
	for i in range(first, first + int((v.right - v.left) / step) + 3):
		out.append(offset + i * step)
	return out


static func dim(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


## Day and night values. The converter's gain lifts everything, so like the
## rooms most of the picture stays under ~0.3 and only the subject and the
## lights go higher. Day is a muted overcast blue with mid walls and dark
## glass, never white; night walls are cool greys, so they print as the
## rooms' blue-grey rather than drifting to olive.
const DAY := {
	"sky_top": Color(0.11, 0.155, 0.24), "sky_low": Color(0.19, 0.235, 0.30),
	"haze": Color(0.17, 0.20, 0.25), "far": Color(0.15, 0.165, 0.20),
	"roof": Color(0.21, 0.13, 0.11), "stone": Color(0.30, 0.29, 0.27),
	"glass": Color(0.045, 0.055, 0.075), "glint": Color(0.19, 0.24, 0.32),
	"road": Color(0.10, 0.10, 0.11), "paving": Color(0.20, 0.19, 0.18), "kerb": Color(0.33, 0.31, 0.28),
	"metal": Color(0.14, 0.15, 0.16), "land": Color(0.17, 0.20, 0.13), "water": Color(0.10, 0.15, 0.21),
}
const NIGHT := {
	"sky_top": Color(0.02, 0.025, 0.06), "sky_low": Color(0.07, 0.075, 0.13),
	"haze": Color(0.065, 0.07, 0.11), "far": Color(0.035, 0.04, 0.065),
	"roof": Color(0.09, 0.07, 0.07), "stone": Color(0.20, 0.19, 0.18),
	"glass": Color(0.035, 0.04, 0.055), "glint": Color(0.06, 0.07, 0.10),
	"road": Color(0.07, 0.07, 0.085), "paving": Color(0.13, 0.13, 0.15), "kerb": Color(0.22, 0.22, 0.24),
	"metal": Color(0.14, 0.14, 0.15), "land": Color(0.05, 0.06, 0.05), "water": Color(0.025, 0.04, 0.08),
}
const DAY_WALLS := [Color(0.30, 0.285, 0.27), Color(0.25, 0.25, 0.27), Color(0.32, 0.30, 0.27),
	Color(0.23, 0.25, 0.30), Color(0.33, 0.24, 0.20)]
const NIGHT_WALLS := [Color(0.14, 0.14, 0.16), Color(0.12, 0.12, 0.14), Color(0.16, 0.15, 0.14),
	Color(0.11, 0.12, 0.16), Color(0.15, 0.13, 0.12)]
const DAY_COATS := [Color(0.09, 0.09, 0.10), Color(0.14, 0.19, 0.30), Color(0.40, 0.36, 0.28),
	Color(0.38, 0.15, 0.12), Color(0.17, 0.22, 0.16), Color(0.50, 0.48, 0.44)]
const NIGHT_COATS := [Color(0.34, 0.32, 0.30), Color(0.28, 0.34, 0.45), Color(0.54, 0.49, 0.40),
	Color(0.50, 0.26, 0.20), Color(0.32, 0.38, 0.30), Color(0.60, 0.57, 0.52)]


## The scene's tones at night amount `n` (0 full day .. 1 full night).
static func tones(n: float) -> Dictionary:
	var out := {"n": n, "lit": n > 0.45}
	for key in DAY:
		out[key] = (DAY[key] as Color).lerp(NIGHT[key], n)
	var walls: Array = []
	var coats: Array = []
	for i in DAY_WALLS.size():
		walls.append((DAY_WALLS[i] as Color).lerp(NIGHT_WALLS[i], n))
	for i in DAY_COATS.size():
		coats.append((DAY_COATS[i] as Color).lerp(NIGHT_COATS[i], n))
	out["walls"] = walls
	out["coats"] = coats
	return out


static func wall(k: Dictionary, i: int) -> Color:
	var walls: Array = k["walls"]
	return walls[posmod(i, walls.size())]


static func coat(k: Dictionary, i: int) -> Color:
	var coats: Array = k["coats"]
	return coats[posmod(i, coats.size())]


## A soft glow: three nested translucent discs.
static func glow(v: DeskView, at: Vector2, r: float, c: Color, strength: float = 1.0) -> void:
	for i in 3:
		v.disc(at, r * (1.0 - i * 0.3), Color(c.r, c.g, c.b, 0.07 * strength * (i + 1)))


## An ellipse of light on the ground.
static func pool(v: DeskView, centre: Vector2, rx: float, ry: float, c: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(centre + Vector2(cos(a) * rx, sin(a) * ry))
	v.poly(pts, c)


## One building on the street line `base`. `kind`: "flat", "pitched",
## "mansard", "block" (a modern slab). `lit` is the share of windows lit at
## night; `shut` shutters the ground floor; `boarded` the share of upper
## windows boarded up.
static func facade(v: DeskView, k: Dictionary, x: float, w: float, h: float, base: float, seed: int,
		kind: String = "flat", lit: float = 0.6, shut: bool = false, boarded: float = 0.0, t: float = 0.0) -> void:
	var c := wall(k, seed)
	var top := base - h
	v.rect(x, top, w, h, c)
	v.rect(x + w - 3, top, 3, h, c.darkened(0.3))                        # the shaded return
	match kind:
		"pitched":
			var ridge := minf(w * 0.42, 22.0)
			v.poly(PackedVector2Array([Vector2(x - 2, top), Vector2(x + w * 0.5, top - ridge), Vector2(x + w + 2, top)]), k["roof"])
			v.line(Vector2(x - 2, top), Vector2(x + w * 0.5, top - ridge), (k["roof"] as Color).lightened(0.25), 1.5)
			if roll(seed, 7) < 0.7:
				var cx := x + w * 0.72
				v.rect(cx, top - ridge * 0.75, 4, ridge * 0.75, c.darkened(0.2))
		"mansard":
			v.poly(PackedVector2Array([Vector2(x - 1, top), Vector2(x + 4, top - 10), Vector2(x + w - 4, top - 10), Vector2(x + w + 1, top)]), k["roof"])
			for dx in range(int(x + 7), int(x + w - 8), int(BAY)):
				v.rect(dx, top - 8, 5, 6, k["glass"])
		"block":
			v.rect(x - 1, top - 3, w + 2, 3, c.darkened(0.25))
		_:
			v.rect(x - 1.5, top - 3, w + 3, 3, c.lightened(0.18))            # cornice
	# Upper floors: a regular grid of windows.
	var floors := int((h - 18.0) / STOREY)
	var cols := int((w - 6.0) / BAY)
	var x0 := x + (w - cols * BAY) * 0.5 + (BAY - WIN.x) * 0.5
	for f in floors:
		var wy := top + 6.0 + f * STOREY
		for i in cols:
			var wx := x0 + i * BAY
			_window(v, k, wx, wy, seed, f * 31 + i, lit, boarded, t)
	# Ground floor: a shop front or a door.
	var gy := base - 14.0
	if kind != "block" and w >= 22.0 and roll(seed, 3) < 0.65:
		_shopfront(v, k, x + 3, gy, w - 9, seed, shut, t)
	else:
		v.rect(x + w * 0.5 - 4, base - 12, 8, 12, c.darkened(0.55))
		if k["lit"] and roll(seed, 5) < 0.5:
			v.rect(x + w * 0.5 - 3, base - 11, 6, 3, DeskView.LAMP.darkened(0.3))


static func _window(v: DeskView, k: Dictionary, wx: float, wy: float, seed: int, i: int, lit: float, boarded: float, t: float) -> void:
	var r := roll(seed, 100 + i)
	if r < boarded:
		v.rect(wx, wy, WIN.x, WIN.y, Color(0.22, 0.17, 0.12))
		v.line(Vector2(wx, wy + 1), Vector2(wx + WIN.x, wy + WIN.y - 1), Color(0.40, 0.31, 0.20), 1.5)
		return
	if k["lit"] and r < lit:
		var warm := DeskView.LAMP.darkened(0.08 + 0.3 * roll(seed, 200 + i))
		# A few rooms are lit by a television: cool, and slowly changing.
		if roll(seed, 300 + i) < 0.08:
			var flick := 0.75 + 0.25 * sin(t * 1.7 + i)
			warm = Color(0.50, 0.62, 0.85) * Color(flick, flick, flick)
		v.rect(wx, wy, WIN.x, WIN.y, warm)
		v.rect(wx, wy + WIN.y * 0.45, WIN.x, 1.0, warm.darkened(0.35))   # the transom
	else:
		v.rect(wx, wy, WIN.x, WIN.y, k["glass"])
		v.rect(wx, wy, WIN.x, 2, k["glint"])
	v.rect(wx - 0.5, wy + WIN.y, WIN.x + 1, 1.2, (k["stone"] as Color).darkened(0.1))   # sill


static func _shopfront(v: DeskView, k: Dictionary, x: float, y: float, w: float, seed: int, shut: bool, t: float) -> void:
	var awning: Color = LIVERY[posmod(seed, 4)]
	v.rect(x - 1, y - 3, w + 2, 3, awning.lerp(dim(awning, 0.4), k["n"]))
	if shut:
		var grey := (k["metal"] as Color).lightened(0.25)
		v.rect(x, y, w, 14, grey)
		for yy in range(int(y + 2), int(y + 14), 3):
			v.rect(x, yy, w, 1, grey.darkened(0.35))
		return
	if k["lit"]:
		var on := DeskView.LAMP.darkened(0.15)
		v.rect(x, y + 1, w, 12, on)
		v.rect(x + 2, y + 6, w * 0.5, 7, on.darkened(0.45))               # counter and goods
		v.rect(x + w * 0.6, y + 3, 2, 10, on.darkened(0.5))
	else:
		v.rect(x, y + 1, w, 12, k["glass"])
		v.rect(x, y + 1, w, 2, k["glint"])
		v.rect(x + 2, y + 8, w - 4, 5, awning.darkened(0.5))


## A street lamp, foot on the kerb, head `h` above it, with its cone and pool
## of light at night. `on` false leaves it a dead post.
static func lamp(v: DeskView, k: Dictionary, x: float, foot: float, h: float, on: bool, t: float) -> void:
	var post := (k["metal"] as Color).lightened(0.15)
	v.rect(x - 1, foot - h, 2.2, h, post)
	v.rect(x - 2.5, foot - 4, 5, 4, post)
	v.line(Vector2(x, foot - h), Vector2(x + 7, foot - h - 2), post, 1.5)
	var head := Vector2(x + 8, foot - h - 1)
	if k["lit"] and on:
		var breathe := 0.94 + 0.06 * sin(t * 0.8 + x)
		pool(v, Vector2(head.x, foot + 2), 24, 5, (k["paving"] as Color).lerp(Color(0.36, 0.28, 0.17), 0.7))
		pool(v, Vector2(head.x, foot + 2), 13, 2.8, Color(0.44, 0.34, 0.20))
		v.rect(head.x - 4, head.y - 2, 8, 3, DeskView.LAMP * Color(breathe, breathe, breathe))
		v.rect(head.x - 2.5, head.y + 1, 5, 1.5, DeskView.LAMP.darkened(0.3))
	else:
		v.rect(head.x - 4, head.y - 2, 8, 3, post.lightened(0.2))


## A car, wheels on `y`, nose toward `dir`.
static func car(v: DeskView, k: Dictionary, x: float, y: float, dir: float, tone: Color, length: float = 22.0) -> void:
	var body := tone.lerp(dim(tone, 0.45), k["n"] * 0.7)
	v.rect(x, y - 9, length, 6, body)
	var cab0 := x + length * (0.22 if dir > 0 else 0.30)
	v.poly(PackedVector2Array([Vector2(cab0, y - 9), Vector2(cab0 + 3, y - 14), Vector2(cab0 + length * 0.42, y - 14), Vector2(cab0 + length * 0.48 + 2, y - 9)]), body.darkened(0.15))
	v.rect(cab0 + 3, y - 13, length * 0.18, 3.5, k["glint"] if not k["lit"] else Color(0.10, 0.10, 0.12))
	v.rect(cab0 + 4 + length * 0.2, y - 13, length * 0.18, 3.5, k["glint"] if not k["lit"] else Color(0.10, 0.10, 0.12))
	for wx: float in [x + 5.0, x + length - 5.0]:
		v.disc(Vector2(wx, y - 2.5), 2.6, Color(0.04, 0.04, 0.05))
		v.disc(Vector2(wx, y - 2.5), 1.0, Color(0.35, 0.35, 0.36))
	_lights(v, k, x, y - 7, length, dir)


static func _lights(v: DeskView, k: Dictionary, x: float, y: float, length: float, dir: float) -> void:
	var nose := x + length if dir > 0 else x
	var tail := x if dir > 0 else x + length
	v.rect(tail - 1, y, 2, 2, Color(0.75, 0.15, 0.10) if k["lit"] else Color(0.45, 0.14, 0.10))
	v.rect(nose - 1, y, 2, 2, DeskView.LAMP if k["lit"] else DeskView.PAPER.darkened(0.3))
	if k["lit"]:
		v.poly(PackedVector2Array([Vector2(nose, y), Vector2(nose, y + 2), Vector2(nose + dir * 30, y + 6), Vector2(nose + dir * 30, y - 3)]),
			Color(0.75, 0.85, 1.0, 0.06))


## A bus or a tram: a long box with a row of windows, lit inside at night,
## a few heads in the windows. A tram carries a pole to the overhead wire.
static func coach(v: DeskView, k: Dictionary, x: float, y: float, dir: float, length: float, livery: Color, tram: bool, wire: float) -> void:
	var body := livery.lerp(dim(livery, 0.5), k["n"] * 0.6)
	var cream := Color(0.70, 0.66, 0.56).lerp(Color(0.30, 0.28, 0.24), k["n"])
	var top := y - 19.0
	v.rect(x, top, length, 16, body)
	v.rect(x, top + 11, length, 2, cream)
	v.rect(x + 1, top - 2, length - 2, 2, body.darkened(0.25))
	var inside: Color = DeskView.LAMP.darkened(0.2) if k["lit"] else k["glass"]
	for wx in range(int(x + 4), int(x + length - 6), 9):
		v.rect(wx, top + 3, 7, 6, inside)
		if roll(int(x), wx) < 0.5:
			v.rect(wx + 2, top + 5, 3, 4, dim(DeskView.FIGURE, 0.35))
	if tram:
		v.line(Vector2(x + length * 0.5, top - 2), Vector2(x + length * 0.5 - dir * 10, wire), k["metal"], 1.2)
		for wx: float in [x + 8.0, x + 14.0, x + length - 14.0, x + length - 8.0]:
			v.disc(Vector2(wx, y - 2), 2.0, Color(0.04, 0.04, 0.05))
	else:
		for wx: float in [x + 7.0, x + length - 8.0]:
			v.disc(Vector2(wx, y - 2.5), 3.0, Color(0.04, 0.04, 0.05))
			v.disc(Vector2(wx, y - 2.5), 1.2, Color(0.35, 0.35, 0.36))
	_lights(v, k, x, y - 6, length, dir)


static func lorry(v: DeskView, k: Dictionary, x: float, y: float, dir: float, cab: Color, load: Color) -> void:
	var cab_x := x + 26.0 if dir > 0 else x
	var box_x := x if dir > 0 else x + 10.0
	v.rect(box_x, y - 17, 26, 13, load.lerp(dim(load, 0.45), k["n"] * 0.7))
	v.rect(box_x, y - 17, 26, 1.5, load.lightened(0.15))
	v.rect(cab_x, y - 13, 10, 9, cab.lerp(dim(cab, 0.5), k["n"] * 0.6))
	v.rect(cab_x + (5 if dir > 0 else 1), y - 12, 4, 4, Color(0.10, 0.11, 0.13))
	for wx: float in [x + 5.0, x + 18.0, x + 31.0]:
		v.disc(Vector2(wx, y - 2.5), 2.8, Color(0.04, 0.04, 0.05))
	_lights(v, k, x, y - 7, 36.0, dir)


## A fire: flickering tongues over a hot core, a glow round it, and a column
## of smoke leaning away on the wind.
static func fire(v: DeskView, x: float, foot: float, size: float, t: float, smoke: bool = true) -> void:
	glow(v, Vector2(x, foot - 6 * size), 22.0 * size, Color(1.0, 0.55, 0.2), 1.4)
	for i in 5:
		var ph := t * (5.0 + i) + i * 1.7
		var hgt := (10.0 + 5.0 * sin(ph)) * size * (1.0 - absf(i - 2) * 0.2)
		var cx := x + (i - 2) * 3.0 * size
		v.poly(PackedVector2Array([Vector2(cx - 3 * size, foot), Vector2(cx + sin(ph * 0.7) * 2.0, foot - hgt),
			Vector2(cx + 3 * size, foot)]), Color(0.86, 0.32, 0.10) if i % 2 == 0 else Color(0.95, 0.55, 0.16))
	v.poly(PackedVector2Array([Vector2(x - 4 * size, foot), Vector2(x, foot - 7 * size - 2 * sin(t * 9.0)), Vector2(x + 4 * size, foot)]), DeskView.LAMP.lightened(0.2))
	if smoke:
		puffs(v, Vector2(x, foot - 14 * size), size * 1.3, t, Color(0.30, 0.28, 0.27))


## Rising smoke: discs that drift up and sideways, grow and thin.
static func puffs(v: DeskView, from: Vector2, size: float, t: float, c: Color, count: int = 7) -> void:
	for i in count:
		var age := fposmod(t * 0.12 + i / float(count), 1.0)
		var p := from + Vector2(age * 34.0 * size + sin(t * 0.4 + i) * 2.0, -age * 70.0 * size)
		v.disc(p, (3.0 + age * 9.0) * size, Color(c.r, c.g, c.b, 0.55 * (1.0 - age)))


## A burning barrel with a few people round it, hands out to the heat.
static func barrel(v: DeskView, k: Dictionary, x: float, foot: float, t: float, h: float = 18.0) -> void:
	v.rect(x - 4, foot - 9, 8, 9, Color(0.22, 0.17, 0.13))
	v.rect(x - 4, foot - 6, 8, 1, Color(0.12, 0.09, 0.07))
	fire(v, x, foot - 9, 0.45, t, true)
	for dx: float in [-14.0, 11.0]:
		v.figure(x + dx, foot, coat(k, int(dx)), "stand", t, h)


## A placard on its pole over a protester's head.
static func placard(v: DeskView, x: float, top: float, t: float, i: int) -> void:
	var bob := sin(t * 2.0 + i) * 1.2
	v.rect(x + 1.5, top - 4 + bob, 1.2, 8, Color(0.30, 0.22, 0.15))
	v.rect(x - 4, top - 14 + bob, 13, 9, DeskView.PAPER.darkened(0.12))
	v.rect(x - 2, top - 11 + bob, 9, 1.5, DeskView.ALARM.darkened(0.2))
	v.rect(x - 2, top - 8 + bob, 6, 1.5, Color(0.18, 0.16, 0.14))


## A policeman in riot kit: helmet, and a shield held across the body.
static func riot_officer(v: DeskView, x: float, foot: float, h: float, t: float, i: int) -> void:
	var u := h / 18.0
	var shuffle := 1.0 if sin(t * 0.7 + i * 1.3) > 0.85 else 0.0
	v.figure(x + shuffle, foot, POLICE, "stand", t, h)
	v.rect(x - 0.5 * u + shuffle, foot - h - 1 * u, 5 * u, 2 * u, Color(0.10, 0.11, 0.16))        # helmet
	v.rect(x + 0.5 * u + shuffle, foot - h + 1.2 * u, 3 * u, 0.8 * u, Color(0.45, 0.50, 0.58))    # visor
	v.rect(x - 4 * u + shuffle, foot - h + 5 * u, 7 * u, 11 * u, Color(0.42, 0.46, 0.52))        # shield
	v.rect(x - 3.5 * u + shuffle, foot - h + 6 * u, 6 * u, 1 * u, Color(0.62, 0.64, 0.66))


## A van or car with a light bar flashing blue and red.
static func siren(v: DeskView, x: float, y: float, t: float, i: int = 0) -> void:
	var blue := sin(t * 9.0 + i) > 0.0
	var c := SIREN_BLUE if blue else Color(1.0, 0.25, 0.2)
	v.rect(x - 3, y - 2, 6, 2.5, c)
	glow(v, Vector2(x, y - 1), 16.0, c, 1.3)
