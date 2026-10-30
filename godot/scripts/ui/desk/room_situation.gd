class_name RoomSituation
extends RefCounted

## The situation desk's room: the cabinet crisis room at night. A large wall
## screen carries a thin-line map of the country with a pulsing marker for
## every open situation; duty officers sit at rows of desks with small lit
## consoles, the Prime Minister stands pointing at the screen, a wall clock
## turns, and a small red lamp blinks above the screen while something must
## be decided this month.
##
## data: markers (one {seed, urgent} per pending situation, at most eight),
## urgent (true when any situation is due this month).

const SCREEN := Rect2(180, 18, 280, 92)
const ROWS := [168.0, 198.0, 234.0]
const AISLE := Vector2(296, 344)
## The country's silhouette, normalised to the screen's map area.
const OUTLINE := [
	Vector2(0.04, 0.50), Vector2(0.12, 0.30), Vector2(0.10, 0.16), Vector2(0.24, 0.10),
	Vector2(0.32, 0.20), Vector2(0.44, 0.04), Vector2(0.56, 0.14), Vector2(0.66, 0.06),
	Vector2(0.80, 0.12), Vector2(0.84, 0.30), Vector2(0.96, 0.38), Vector2(0.90, 0.56),
	Vector2(0.94, 0.72), Vector2(0.80, 0.80), Vector2(0.74, 0.96), Vector2(0.60, 0.86),
	Vector2(0.48, 0.96), Vector2(0.40, 0.84), Vector2(0.26, 0.90), Vector2(0.18, 0.74),
	Vector2(0.08, 0.70),
]
## The ceasefire line, drawn dashed across the east.
const LINE := [Vector2(0.70, 0.10), Vector2(0.72, 0.40), Vector2(0.80, 0.60), Vector2(0.86, 0.76)]
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
	_room(v, t)
	_screen(v, t, d.get("markers", []))
	_clock(v, t)
	if bool(d.get("urgent", false)) and fmod(t, 1.0) < 0.5:
		v.rect(SCREEN.position.x - 2, 8, 5, 4, DeskView.ALARM)
	_officers(v, t)
	v.label(Vector2(476, 66), "WALL SCREEN", Vector2(462, 62))
	v.label(Vector2(470, 150), "DUTY OFFICERS", Vector2(450, 186))


static func _room(v: DeskView, t: float) -> void:
	v.rect(v.left, 0, v.right - v.left, 240, DeskView.WALL.darkened(0.6))
	v.line(Vector2(v.left, 10), Vector2(v.right, 10), DeskView.STONE.darkened(0.3), 2.0)
	v.line(Vector2(v.left, 126), Vector2(v.right, 126), DeskView.STONE.darkened(0.35))
	v.rect(v.left, 126, v.right - v.left, 114, DeskView.WALL.darkened(0.75))
	# Status boards along the walls, repeated to the panel edges: grids of
	# small cells, a few of them lit and changing slowly.
	var first := int(floorf((v.left - 20.0) / 90.0))
	for i in range(first, first + int((v.right - v.left) / 90.0) + 2):
		var x := 20.0 + i * 90.0
		if (x > SCREEN.position.x - 70 and x < SCREEN.end.x + 10) or absf(x + 28 - 560.0) < 60.0:
			continue
		v.rect(x, 34, 56, 50, DeskView.INK)
		v.line(Vector2(x, 34), Vector2(x + 56, 34), DeskView.METAL.darkened(0.4))
		v.line(Vector2(x, 84), Vector2(x + 56, 84), DeskView.METAL.darkened(0.4))
		for k in 12:
			var cx := x + 5 + (k % 4) * 13
			var cy := 42.0 + floorf(k / 4.0) * 14
			var lit := sin(t * 0.15 + i * 2.3 + k * 1.1) > 0.55
			v.rect(cx, cy, 8, 2, DeskView.LAMP.darkened(0.25) if lit else DeskView.WALL)


static func _screen(v: DeskView, t: float, markers: Array) -> void:
	var s := SCREEN
	v.rect(s.position.x, s.position.y, s.size.x, s.size.y, DeskView.INK)
	for p in [[s.position, Vector2(s.end.x, s.position.y)], [Vector2(s.position.x, s.end.y), s.end],
			[s.position, Vector2(s.position.x, s.end.y)], [Vector2(s.end.x, s.position.y), s.end]]:
		v.line(p[0], p[1], DeskView.METAL)
	# A faint grid, then the country in a thin bright line: the room's hero.
	for k in range(1, 7):
		var gx := s.position.x + k * s.size.x / 7.0
		v.line(Vector2(gx, s.position.y + 2), Vector2(gx, s.end.y - 2), DeskView.WALL.darkened(0.1))
	for k in range(1, 3):
		var gy := s.position.y + k * s.size.y / 3.0
		v.line(Vector2(s.position.x + 2, gy), Vector2(s.end.x - 2, gy), DeskView.WALL.darkened(0.1))
	var n := OUTLINE.size()
	for i in n:
		v.line(_on_map(OUTLINE[i]), _on_map(OUTLINE[(i + 1) % n]), DeskView.PAPER.darkened(0.1))
	for i in LINE.size() - 1:
		var a := _on_map(LINE[i])
		var b := _on_map(LINE[i + 1])
		for k in 4:
			v.line(a.lerp(b, k / 4.0), a.lerp(b, (k + 0.5) / 4.0), DeskView.STONE)
	# A scan line sweeping slowly down the screen.
	var sweep := s.position.y + 2 + fmod(t * 6.0, s.size.y - 4)
	v.line(Vector2(s.position.x + 2, sweep), Vector2(s.end.x - 2, sweep), DeskView.STONE.darkened(0.2))
	var used: Array[int] = []
	for m in markers:
		var seed := int(m.get("seed", 0))
		var site := seed % SITES.size()
		while used.has(site) and used.size() < SITES.size():
			site = (site + 1) % SITES.size()   # two situations never share a marker
		used.append(site)
		var at := _on_map(SITES[site])
		var tone := DeskView.ALARM if bool(m.get("urgent", false)) else DeskView.LAMP
		var pulse := fmod(t * 0.5 + (seed % 97) / 97.0, 1.0)
		var r := 2.0 + pulse * 7.0
		var ring := tone.darkened(0.3 + 0.6 * pulse)
		v.line(at + Vector2(-r, -r), at + Vector2(r, -r), ring)
		v.line(at + Vector2(-r, r), at + Vector2(r, r), ring)
		v.line(at + Vector2(-r, -r), at + Vector2(-r, r), ring)
		v.line(at + Vector2(r, -r), at + Vector2(r, r), ring)
		v.rect(at.x - 1.5, at.y - 1.5, 3, 3, tone)


static func _on_map(p: Vector2) -> Vector2:
	var area := Rect2(SCREEN.position + Vector2(40, 8), Vector2(SCREEN.size.x - 80, SCREEN.size.y - 16))
	return area.position + p * area.size


static func _clock(v: DeskView, t: float) -> void:
	var c := Vector2(560, 46)
	var prev := Vector2.ZERO
	for k in 17:
		var a := TAU * k / 16.0
		var p := c + Vector2(cos(a), sin(a)) * 11.0
		if k > 0:
			v.line(prev, p, DeskView.METAL)
		prev = p
	var minute := TAU * fmod(t / 60.0, 1.0) - PI * 0.5
	var hour := TAU * (0.12 + t / 3600.0) - PI * 0.5
	v.line(c, c + Vector2(cos(minute), sin(minute)) * 9.0, DeskView.PAPER.darkened(0.2))
	v.line(c, c + Vector2(cos(hour), sin(hour)) * 6.0, DeskView.PAPER.darkened(0.2))


static func _officers(v: DeskView, t: float) -> void:
	# The Prime Minister on the floor before the screen, pointing at it, with
	# two aides a step behind.
	var lean := 0.6 * sin(t * 0.35)
	v.figure(150 + lean, 142, DeskView.PAPER, "point", t, 22.0)
	v.figure(128, 142, DeskView.FIGURE.darkened(0.1), "stand", t, 19.0)
	v.figure(112, 144, DeskView.FIGURE.darkened(0.15), "stand", t, 18.0)
	for r in ROWS.size():
		var y: float = ROWS[r]
		var near := 1.0 + 0.3 * r / float(ROWS.size() - 1)
		var step := 30.0 * near
		var first := int(floorf((v.left + 10.0) / step))
		for k in range(first, first + int((v.right - v.left) / step)):
			var x := k * step
			if x > AISLE.x - 20 and x < AISLE.y:
				continue
			# The desk with its console, and the officer seated at it.
			v.rect(x - 6, y - 10 * near, 22 * near, 3, DeskView.METAL.darkened(0.35))
			v.rect(x + 6, y - 16 * near, 8 * near, 6 * near, DeskView.METAL.darkened(0.15))
			var blink := sin(t * 0.4 + k * 1.7 + r * 2.9) > -0.6
			v.rect(x + 8, y - 14 * near, 3, 2, DeskView.LAMP if blink else DeskView.WALL)
			var shift := 1.0 if sin(t * 0.5 + k * 2.3 + r) > 0.96 else 0.0
			v.figure(x, y + 2 - shift, DeskView.FIGURE, "sit", t, 16.0 * near)
