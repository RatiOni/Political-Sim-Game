class_name RoomSituation
extends RefCounted

## The situation desk's room: the cabinet crisis room at night. A large wall
## screen carries a thin-line map of the country with a pulsing marker for
## every open situation; status boards flank it with live readouts, the Prime
## Minister stands before it pointing with aides at hand, rows of duty
## officers sit at consoles running back toward the screen, a wall clock
## turns, and a small red lamp blinks above the screen while something must
## be decided this month.
##
## data: markers (one {seed, urgent} per pending situation, at most eight),
## urgent (true when any situation is due this month).

const SCREEN := Rect2(160, 52, 320, 166)
const FLOOR := 226.0
const VANISH := Vector2(320, 120)
## Console rows, far to near: desk-top y and how large things read there.
const ROWS := [[260.0, 0.72], [312.0, 0.96], [376.0, 1.24]]
const BOARDS := [Rect2(12, 66, 130, 152), Rect2(498, 66, 130, 152)]
const CLOCK := Vector2(78, 44)

const GLASS := Color(0.09, 0.12, 0.20)
const GRID := Color(0.18, 0.24, 0.34)
const TRACE := Color(0.88, 0.85, 0.74)
const CONSOLE := Color(0.22, 0.23, 0.25)

## The country's silhouette, normalised to the screen's map area.
const OUTLINE := [
	Vector2(0.04, 0.50), Vector2(0.12, 0.30), Vector2(0.10, 0.16), Vector2(0.24, 0.10),
	Vector2(0.32, 0.20), Vector2(0.44, 0.04), Vector2(0.56, 0.14), Vector2(0.66, 0.06),
	Vector2(0.80, 0.12), Vector2(0.84, 0.30), Vector2(0.96, 0.38), Vector2(0.90, 0.56),
	Vector2(0.94, 0.72), Vector2(0.80, 0.80), Vector2(0.74, 0.96), Vector2(0.60, 0.86),
	Vector2(0.48, 0.96), Vector2(0.40, 0.84), Vector2(0.26, 0.90), Vector2(0.18, 0.74),
	Vector2(0.08, 0.70),
]
## Internal boundaries between the regions, drawn faint.
const BORDERS := [
	[Vector2(0.32, 0.20), Vector2(0.36, 0.44), Vector2(0.18, 0.74)],
	[Vector2(0.36, 0.44), Vector2(0.58, 0.46), Vector2(0.66, 0.06)],
	[Vector2(0.58, 0.46), Vector2(0.60, 0.86)],
	[Vector2(0.36, 0.44), Vector2(0.40, 0.84)],
]
## The river, wandering south-east to the coast.
const RIVER := [Vector2(0.20, 0.18), Vector2(0.28, 0.34), Vector2(0.42, 0.52), Vector2(0.50, 0.70), Vector2(0.48, 0.96)]
## The ceasefire line, drawn dashed across the east.
const LINE := [Vector2(0.70, 0.10), Vector2(0.72, 0.40), Vector2(0.80, 0.60), Vector2(0.86, 0.76)]
const CITIES := [Vector2(0.46, 0.40), Vector2(0.22, 0.56), Vector2(0.64, 0.30), Vector2(0.54, 0.80), Vector2(0.82, 0.46)]
## Inland points a marker may sit on; a situation keeps its own by seed.
const SITES := [
	Vector2(0.30, 0.40), Vector2(0.52, 0.30), Vector2(0.70, 0.36), Vector2(0.44, 0.62),
	Vector2(0.62, 0.70), Vector2(0.26, 0.66), Vector2(0.78, 0.56), Vector2(0.56, 0.48),
]


## What the room shows, read from the app snapshot.
static func data_from(snapshot: Dictionary) -> Dictionary:
	var rows: Variant = snapshot.get("situations", [])
	if not (rows is Array) or rows.is_empty():
		rows = snapshot.get("decisions", [])
	var markers: Array = []
	var urgent := false
	if rows is Array:
		for row in rows:
			if not (row is Dictionary) or markers.size() >= SITES.size():
				continue
			var due := int(row.get("months_left", 1)) <= 0
			urgent = urgent or due
			markers.append({"seed": absi(str(row.get("event_id", markers.size())).hash()), "urgent": due})
	return {"markers": markers, "urgent": urgent}


static func paint(v: DeskView, t: float, d: Dictionary) -> void:
	var urgent := bool(d.get("urgent", false))
	_ceiling(v, t)
	_wall(v)
	for i in BOARDS.size():
		_board(v, t, BOARDS[i], i)
	_clock(v, t)
	_screen(v, t, d.get("markers", []))
	_alarm(v, t, urgent)
	_floor(v)
	_command(v, t)
	for r in ROWS.size():
		_console_row(v, t, r)
	_foreground(v, t)
	v.label(Vector2(486, 46), "WALL SCREEN", Vector2(466, 60))
	v.label(Vector2(16, 412), "DUTY OFFICERS", Vector2(60, 384))
	v.label(Vector2(196, 244), "THE PRIME MINISTER", Vector2(184, 230))


# --- architecture -----------------------------------------------------------

static func _ceiling(v: DeskView, t: float) -> void:
	v.rect(v.left, 0, v.right - v.left, 34, DeskView.INK)
	# Ceiling lights in perspective: three rows of panels, breathing softly.
	for row in 3:
		var y := 4.0 + row * 9.0
		var w := 18.0 + row * 6.0
		var gap := 64.0 + row * 14.0
		var breathe := 0.86 + 0.14 * sin(t * 0.5 + row * 1.3)
		var lamp := DeskView.PAPER.darkened(0.35 - row * 0.1) * Color(breathe, breathe, breathe)
		var first := int(floorf((v.left - 320.0) / gap)) - 1
		for i in range(first, first + int((v.right - v.left) / gap) + 3):
			var x := 320.0 + i * gap - w * 0.5
			v.rect(x, y, w, 3, lamp)
	# Two cable trays along the wall head, with hangers and a sagging bundle.
	for y in [30.0, 36.0]:
		v.line(Vector2(v.left, y), Vector2(v.right, y), DeskView.METAL.darkened(0.25), 2.0)
	for x in range(int(v.left) + 6, int(v.right), 26):
		v.line(Vector2(x, 23), Vector2(x, 36), DeskView.METAL.darkened(0.45), 1.5)
	for k in range(int(floorf(v.left / 52.0)), int(ceilf(v.right / 52.0)) + 1):
		var a := Vector2(k * 52.0, 38)
		var b := Vector2(k * 52.0 + 52.0, 38)
		var mid := (a + b) * 0.5 + Vector2(0, 5)
		v.line(a, mid, DeskView.STONE.darkened(0.45), 1.5)
		v.line(mid, b, DeskView.STONE.darkened(0.45), 1.5)


static func _wall(v: DeskView) -> void:
	v.rect(v.left, 38, v.right - v.left, FLOOR - 38, DeskView.WALL.darkened(0.55))
	# Acoustic panelling in a fine grid.
	for x in range(int(v.left), int(v.right), 32):
		v.line(Vector2(x, 42), Vector2(x, FLOOR - 4), DeskView.WALL.darkened(0.25), 1.5)
	for y in [104.0, 166.0]:
		v.line(Vector2(v.left, y), Vector2(v.right, y), DeskView.WALL.darkened(0.25), 1.5)
	# The skirting and a rail of conduit just above it.
	v.rect(v.left, FLOOR - 6, v.right - v.left, 6, DeskView.WALL.darkened(0.1))
	v.line(Vector2(v.left, FLOOR - 10), Vector2(v.right, FLOOR - 10), DeskView.METAL.darkened(0.35), 1.5)


static func _floor(v: DeskView) -> void:
	v.rect(v.left, FLOOR, v.right - v.left, 420 - FLOOR, DeskView.WALL.darkened(0.7))
	# Floor tiles in perspective: rows close up toward the wall, seams run
	# to the vanishing point above the screen.
	var y := FLOOR
	var step := 6.0
	while y < 420.0:
		v.line(Vector2(v.left, y), Vector2(v.right, y), DeskView.STONE.darkened(0.48), 1.5)
		y += step
		step *= 1.32
	for k in range(-14, 15):
		var bottom := Vector2(320 + k * 64.0, 420)
		var top := VANISH.lerp(bottom, (FLOOR - VANISH.y) / (420.0 - VANISH.y))
		v.line(top, bottom, DeskView.STONE.darkened(0.48), 1.5)


# --- the wall screen ---------------------------------------------------------

static func _screen(v: DeskView, t: float, markers: Array) -> void:
	var s := SCREEN
	v.rect(s.position.x - 6, s.position.y - 6, s.size.x + 12, s.size.y + 12, CONSOLE.darkened(0.3))
	v.rect(s.position.x - 2, s.position.y - 2, s.size.x + 4, s.size.y + 4, DeskView.METAL)
	v.rect(s.position.x, s.position.y, s.size.x, s.size.y, GLASS)
	# A grid with a degree scale along the edges.
	for k in range(1, 12):
		var gx := s.position.x + k * s.size.x / 12.0
		v.line(Vector2(gx, s.position.y + 14), Vector2(gx, s.end.y - 2), GRID, 1.5)
		v.rect(gx - 1, s.end.y - 6, 2, 4, GRID.lightened(0.3))
	for k in range(1, 6):
		var gy := s.position.y + 14 + k * (s.size.y - 14) / 6.0
		v.line(Vector2(s.position.x + 2, gy), Vector2(s.end.x - 2, gy), GRID, 1.5)
		v.rect(s.position.x + 2, gy - 1, 4, 2, GRID.lightened(0.3))
	# Header strip: title cells and a running count.
	v.line(Vector2(s.position.x, s.position.y + 12), Vector2(s.end.x, s.position.y + 12), DeskView.METAL.darkened(0.2), 1.5)
	for k in 9:
		v.rect(s.position.x + 6 + k * 7, s.position.y + 4, 5, 4, TRACE.darkened(0.25))
	for k in 6:
		var on := int(t * 2.0 + k) % 7 != 0
		v.rect(s.end.x - 52 + k * 8, s.position.y + 4, 5, 4, DeskView.LAMP.darkened(0.15) if on else GRID)
	# The country: outline in a bright trace, regions, river, cities.
	var n := OUTLINE.size()
	for i in n:
		v.line(_on_map(OUTLINE[i]), _on_map(OUTLINE[(i + 1) % n]), TRACE, 2.0)
	for b in BORDERS:
		for i in b.size() - 1:
			_dashed(v, _on_map(b[i]), _on_map(b[i + 1]), DeskView.STONE.lightened(0.15), 5)
	for i in RIVER.size() - 1:
		v.line(_on_map(RIVER[i]), _on_map(RIVER[i + 1]), GRID.lightened(0.45), 1.5)
	for i in LINE.size() - 1:
		_dashed(v, _on_map(LINE[i]), _on_map(LINE[i + 1]), DeskView.LAMP.darkened(0.2), 4)
	for c in CITIES:
		var p := _on_map(c)
		v.rect(p.x - 1.5, p.y - 1.5, 3, 3, TRACE)
	var capital := _on_map(CITIES[0])
	v.line(capital + Vector2(-4, -4), capital + Vector2(4, -4), TRACE, 1.5)
	v.line(capital + Vector2(-4, 4), capital + Vector2(4, 4), TRACE, 1.5)
	# A scan line sweeping slowly down the screen.
	var sweep := s.position.y + 14 + fmod(t * 7.0, s.size.y - 16)
	v.line(Vector2(s.position.x + 2, sweep), Vector2(s.end.x - 2, sweep), GRID.lightened(0.2), 1.5)
	_markers(v, t, markers)


static func _markers(v: DeskView, t: float, markers: Array) -> void:
	var used: Array[int] = []
	for m in markers:
		var seed := int(m.get("seed", 0))
		var site := seed % SITES.size()
		while used.has(site) and used.size() < SITES.size():
			site = (site + 1) % SITES.size()   # two situations never share a marker
		used.append(site)
		var at := _on_map(SITES[site])
		var urgent := bool(m.get("urgent", false))
		var tone := DeskView.ALARM if urgent else DeskView.LAMP
		var pulse := fmod(t * 0.5 + (seed % 97) / 97.0, 1.0)
		var r := 3.0 + pulse * 8.0
		var ring := tone.darkened(0.25 + 0.6 * pulse)
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			v.line(at + c * r, at + c * r - Vector2(c.x * 3, 0), ring, 1.5)
			v.line(at + c * r, at + c * r - Vector2(0, c.y * 3), ring, 1.5)
		v.rect(at.x - 2.5, at.y - 2.5, 5, 5, tone)
		# A callout: leader line to a small block of data rows.
		var side := 1.0 if at.x < SCREEN.end.x - 70 else -1.0
		var tag := at + Vector2(side * 14, -10)
		v.line(at + Vector2(side * 3, -3), tag, tone.darkened(0.3), 1.5)
		var tx := tag.x if side > 0 else tag.x - 26
		v.rect(tx, tag.y - 4, 26, 2, tone.darkened(0.1))
		v.rect(tx, tag.y, 18 + (seed % 7), 1.5, TRACE.darkened(0.3))


static func _on_map(p: Vector2) -> Vector2:
	var area := Rect2(SCREEN.position + Vector2(56, 22), Vector2(SCREEN.size.x - 112, SCREEN.size.y - 32))
	return area.position + p * area.size


static func _dashed(v: DeskView, a: Vector2, b: Vector2, c: Color, dashes: int) -> void:
	for k in dashes:
		v.line(a.lerp(b, k / float(dashes)), a.lerp(b, (k + 0.5) / float(dashes)), c, 1.5)


static func _alarm(v: DeskView, t: float, urgent: bool) -> void:
	# The alarm lamp's housing over the screen; lit about once a second.
	var c := Vector2(320, 40)
	v.rect(c.x - 7, c.y - 3, 14, 7, CONSOLE)
	v.rect(c.x - 4, c.y - 1, 8, 4, DeskView.ALARM if urgent and fmod(t, 1.0) < 0.5 else DeskView.WALL)


# --- boards and the clock ----------------------------------------------------

static func _board(v: DeskView, t: float, b: Rect2, which: int) -> void:
	v.rect(b.position.x - 3, b.position.y - 3, b.size.x + 6, b.size.y + 6, CONSOLE.darkened(0.3))
	v.rect(b.position.x, b.position.y, b.size.x, b.size.y, DeskView.INK)
	var x0 := b.position.x + 6
	var w := b.size.x - 12
	# 1. Meters: horizontal bars easing toward slowly drifting values.
	for k in 6:
		var y := b.position.y + 8 + k * 7.0
		var level := 0.5 + 0.35 * sin(t * 0.12 + k * 1.7 + which * 2.3)
		v.rect(x0, y, 4, 3, TRACE.darkened(0.4))
		v.rect(x0 + 8, y, (w - 8) * level, 3, DeskView.PAPER.darkened(0.35) if k % 3 else DeskView.LAMP.darkened(0.2))
	# 2. A grid of status lamps, a few changing.
	var gy := b.position.y + 56
	v.line(Vector2(x0, gy - 4), Vector2(x0 + w, gy - 4), DeskView.METAL.darkened(0.35), 1.5)
	for k in 24:
		var cx := x0 + (k % 8) * (w / 8.0)
		var cy := gy + floorf(k / 8.0) * 8
		var lit := sin(t * 0.2 + k * 1.31 + which * 4.1) > 0.25
		v.rect(cx, cy, 8, 4, DeskView.LAMP.darkened(0.25) if lit else DeskView.WALL)
	# 3. A trace that scrolls slowly left.
	var ty := b.position.y + 108.0
	v.line(Vector2(x0, ty - 16), Vector2(x0 + w, ty - 16), DeskView.METAL.darkened(0.35), 1.5)
	v.line(Vector2(x0, ty + 10), Vector2(x0 + w, ty + 10), GRID, 1.5)
	var prev := Vector2.ZERO
	for k in 25:
		var u := k / 24.0
		var phase := u * 9.0 + t * 0.6 + which * 3.0
		var p := Vector2(x0 + u * w, ty - sin(phase) * 5.0 - sin(phase * 2.7) * 3.0)
		if k > 0:
			v.line(prev, p, TRACE.darkened(0.15), 1.5)
		prev = p
	# 4. Teleprinter rows, the newest line growing.
	for k in 3:
		var y := b.position.y + 126 + k * 8.0
		var span := w * (0.45 + 0.4 * absf(sin(k * 2.1 + which)))
		if k == 2:
			span = w * fmod(t * 0.08 + which * 0.4, 1.0)
		v.rect(x0, y, span, 2, DeskView.PAPER.darkened(0.45))


static func _clock(v: DeskView, t: float) -> void:
	var c := CLOCK
	v.disc(c, 15, DeskView.METAL.darkened(0.2))
	v.disc(c, 13, DeskView.PAPER.darkened(0.15))
	for k in 12:
		var a := TAU * k / 12.0
		var dir := Vector2(cos(a), sin(a))
		v.line(c + dir * 9.5, c + dir * 12.0, DeskView.INK, 1.5)
	var minute := TAU * fmod(t / 60.0, 1.0) - PI * 0.5
	var hour := TAU * (0.12 + t / 3600.0) - PI * 0.5
	v.line(c, c + Vector2(cos(minute), sin(minute)) * 10.0, DeskView.INK, 1.5)
	v.line(c, c + Vector2(cos(hour), sin(hour)) * 6.5, DeskView.INK, 2.0)
	# A date counter on the right, its last digit ticking.
	for k in 6:
		var on := k < 5 or int(t * 0.5) % 2 == 0
		v.rect(546 + k * 9, 42, 6, 9, DeskView.LAMP.darkened(0.2) if on else DeskView.WALL)


# --- people and consoles ------------------------------------------------------

static func _command(v: DeskView, t: float) -> void:
	# The Prime Minister before the screen, pointing at it, aides at hand.
	var lean := 0.8 * sin(t * 0.3)
	v.figure(176 + lean, 252, DeskView.PAPER, "point", t, 40.0)
	v.figure(146, 252, DeskView.FIGURE.darkened(0.05), "stand", t, 37.0)
	v.figure(124, 254, DeskView.FIGURE.darkened(0.15), "stand", t, 36.0)
	var walk := 0.5 - 0.5 * cos(t * 0.2)
	v.figure(430 + walk * 34.0, 252, DeskView.FIGURE.darkened(0.1), "walk", t * 0.6, 36.0)
	v.rect(434 + walk * 34.0 + 6, 228, 6, 8, DeskView.PAPER.darkened(0.1))   # a folder


## Half the width of the central aisle at height `y`, widening toward us.
static func _aisle(y: float) -> float:
	return 14.0 + (y - FLOOR) * 0.28


static func _console_row(v: DeskView, t: float, r: int) -> void:
	var y: float = ROWS[r][0]
	var s: float = ROWS[r][1]
	var gap := _aisle(y)
	var pitch := 46.0 * s
	for side in [-1.0, 1.0]:
		var inner: float = 320.0 + side * gap
		var outer: float = v.left - 10 if side < 0 else v.right + 10
		var x0: float = minf(inner, outer)
		var x1: float = maxf(inner, outer)
		# The long desk: a sloped console face, its top edge lit.
		v.rect(x0, y - 4 * s, x1 - x0, 12 * s, CONSOLE)
		v.rect(x0, y - 4 * s, x1 - x0, 2, DeskView.METAL.lightened(0.1))
		v.rect(x0, y + 8 * s, x1 - x0, 3 * s, CONSOLE.darkened(0.4))
		# Monitors and officers, stepping out from the aisle.
		var k := 0
		var x: float = inner + side * pitch * 0.55
		while (side < 0 and x > v.left - 20) or (side > 0 and x < v.right + 20):
			_station(v, t, x, y, s, r * 31 + k * (1 if side > 0 else 7))
			x += side * pitch
			k += 1


static func _station(v: DeskView, t: float, x: float, y: float, s: float, id: int) -> void:
	# The monitor: a box on the desk with a small lit screen and a lamp.
	var mw := 20.0 * s
	var mh := 15.0 * s
	v.rect(x - mw * 0.5, y - 4 * s - mh, mw, mh, CONSOLE.lightened(0.08))
	v.rect(x - mw * 0.5 + 2, y - 4 * s - mh + 2, mw - 4, mh - 5, GLASS)
	var flick := sin(t * 0.35 + id * 1.9) > -0.7
	v.rect(x - mw * 0.5 + 4, y - 4 * s - mh + 4, (mw - 8) * (0.4 + 0.5 * absf(sin(id * 0.7))), 1.5, TRACE.darkened(0.2) if flick else GRID)
	v.rect(x - mw * 0.5 + 4, y - 4 * s - mh + 7, (mw - 8) * 0.6, 1.5, TRACE.darkened(0.45))
	v.rect(x + mw * 0.5 - 4, y - 7 * s, 2, 2, DeskView.LAMP if (id % 3) else DeskView.LAMP.darkened(0.4))
	# The officer, seen from behind, in a chair a little nearer than the desk.
	var shift := 1.0 if sin(t * 0.5 + id * 2.3) > 0.95 else 0.0
	var h := 30.0 * s
	v.rect(x - 8 * s, y + 6 * s, 16 * s, 16 * s, DeskView.WALL.darkened(0.2))   # chair back
	v.figure(x - 2 * s, y - 3 * s + h - shift, DeskView.FIGURE.darkened(0.12 - s * 0.1), "sit", t, h)


static func _foreground(v: DeskView, t: float) -> void:
	# Nearest us: a cable run along the floor, the duty desk's corner with a
	# telephone, a stack of papers and a lamp, and a runner crossing.
	v.rect(v.left, 404, v.right - v.left, 16, DeskView.INK)
	v.line(Vector2(v.left, 404), Vector2(v.right, 404), DeskView.METAL.darkened(0.2), 2.0)
	for x in range(int(v.left), int(v.right), 20):
		v.rect(x, 406, 10, 3, DeskView.WALL)
	v.rect(v.right - 120, 396, 130, 24, CONSOLE.darkened(0.2))
	v.rect(v.right - 120, 396, 130, 2.5, DeskView.METAL.lightened(0.1))
	v.rect(v.right - 104, 388, 14, 8, DeskView.METAL.darkened(0.3))           # telephone
	v.rect(v.right - 106, 386, 18, 3, DeskView.METAL.darkened(0.1))
	for k in 4:
		v.rect(v.right - 80, 392 - k * 2.0, 18, 1.5, DeskView.PAPER.darkened(k * 0.05))
	var breathe := 0.86 + 0.14 * sin(t * 0.45)
	v.line(Vector2(v.right - 40, 396), Vector2(v.right - 34, 380), DeskView.METAL, 1.5)
	v.rect(v.right - 40, 378, 10, 4, DeskView.LAMP * Color(breathe, breathe, breathe))
	var cross := 0.5 - 0.5 * cos(t * 0.16)
	v.figure(300 + cross * 30.0, 404, DeskView.FIGURE.darkened(0.3), "walk", t * 0.5, 44.0)
