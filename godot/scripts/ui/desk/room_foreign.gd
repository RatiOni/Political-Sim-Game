class_name RoomForeign
extends RefCounted

## The diplomacy desk's room: the Ministry of Foreign Affairs. Delegations sit
## either side of the long negotiating table beneath the great world map,
## where every known government is pinned — friends in warm light, hostile
## powers in alarm. Flags stand in a row along the west wall; behind the glass
## on the east side the cable room's teleprinters feed out paper, and a
## courier brings a folder in from the corridor.
##
## data: relations (one per foreign government: id, tone -1 hostile /
## 0 neutral / +1 friendly).

const FLOOR := 150.0
const MAP := Rect2(150, 18, 340, 88)
const HOME := Vector2(0.5, 0.3)          # Ardenia, on the map's own 0..1 grid
## Where foreign governments are pinned, all on land.
const PINS := [
	Vector2(0.45, 0.24), Vector2(0.58, 0.2), Vector2(0.56, 0.36), Vector2(0.47, 0.38),
	Vector2(0.64, 0.3), Vector2(0.72, 0.2), Vector2(0.8, 0.3), Vector2(0.53, 0.56),
	Vector2(0.56, 0.7), Vector2(0.15, 0.24), Vector2(0.19, 0.62), Vector2(0.86, 0.74),
	Vector2(0.88, 0.24), Vector2(0.64, 0.13), Vector2(0.44, 0.31), Vector2(0.1, 0.36),
]
const COASTS := [
	[Vector2(0.05, 0.15), Vector2(0.18, 0.1), Vector2(0.26, 0.2), Vector2(0.22, 0.38), Vector2(0.16, 0.45),
		Vector2(0.2, 0.55), Vector2(0.24, 0.7), Vector2(0.2, 0.9), Vector2(0.15, 0.75), Vector2(0.12, 0.55),
		Vector2(0.08, 0.4), Vector2(0.05, 0.15)],
	[Vector2(0.42, 0.18), Vector2(0.5, 0.1), Vector2(0.65, 0.07), Vector2(0.82, 0.12), Vector2(0.94, 0.2),
		Vector2(0.9, 0.36), Vector2(0.8, 0.42), Vector2(0.7, 0.4), Vector2(0.62, 0.46), Vector2(0.55, 0.4),
		Vector2(0.48, 0.43), Vector2(0.43, 0.33), Vector2(0.42, 0.18)],
	[Vector2(0.47, 0.48), Vector2(0.58, 0.48), Vector2(0.62, 0.6), Vector2(0.58, 0.78), Vector2(0.53, 0.88),
		Vector2(0.5, 0.72), Vector2(0.46, 0.6), Vector2(0.47, 0.48)],
	[Vector2(0.8, 0.68), Vector2(0.9, 0.66), Vector2(0.93, 0.78), Vector2(0.84, 0.82), Vector2(0.8, 0.68)],
]
const FLAGS := [
	Color(0.42, 0.22, 0.2), Color(0.25, 0.3, 0.42), Color(0.55, 0.5, 0.36),
	Color(0.28, 0.36, 0.28), Color(0.5, 0.46, 0.42), Color(0.36, 0.24, 0.3),
]


## What the room shows, read from the app snapshot.
static func data_from(snapshot: Dictionary) -> Dictionary:
	var relations: Array = []
	for row in snapshot.get("diplomacy", []):
		if not (row is Dictionary):
			continue
		# The snapshot's status words are bands of this same score.
		var score := float(row.get("score", 0.0))
		var tone := 0
		if score <= -0.3 or bool(row.get("sanctioned", false)):
			tone = -1
		elif score > 0.3:
			tone = 1
		relations.append({"id": str(row.get("id", row.get("name", ""))), "tone": tone})
	return {"relations": relations}


static func paint(v: DeskView, t: float, d: Dictionary) -> void:
	_hall(v, t)
	_map(v, t, d.get("relations", []))
	_flags(v, t)
	_cable_room(v, t)
	_table(v, t)
	_courier(v, t)
	v.label(Vector2(MAP.position.x, 14), "SITUATION MAP · FOREIGN CAPITALS")
	v.label(Vector2(286, 236), "THE TABLE", Vector2(318, 190))
	v.label(Vector2(512, 126), "CABLE ROOM", Vector2(546, 176))


static func _hall(v: DeskView, t: float) -> void:
	v.rect(v.left, 0, v.right - v.left, 240, DeskView.WALL.darkened(0.5))
	var first := int(floorf((v.left - 48.0) / 96.0))
	for i in range(first, first + int((v.right - v.left) / 96.0) + 2):
		var x := 48.0 + i * 96.0
		v.rect(x - 3, 8, 6, FLOOR - 8, DeskView.STONE.darkened(0.45))
	v.line(Vector2(v.left, 8), Vector2(v.right, 8), DeskView.STONE, 2.0)
	v.line(Vector2(v.left, 112), Vector2(v.right, 112), DeskView.STONE.darkened(0.35))
	v.rect(v.left, FLOOR, v.right - v.left, 240 - FLOOR, DeskView.WALL.darkened(0.7))
	v.line(Vector2(v.left, FLOOR), Vector2(v.right, FLOOR), DeskView.STONE.darkened(0.2))
	# The carpet runner the delegations walk in on.
	v.rect(v.left, 228, v.right - v.left, 3, DeskView.WOOD.darkened(0.5))


## The map is the room's bright thing: thin coasts on a dark board, a faint
## graticule, and a pin for every government — threads run home to each.
static func _map(v: DeskView, t: float, relations: Array) -> void:
	var o := MAP.position
	var s := MAP.size
	v.rect(o.x - 4, o.y - 4, s.x + 8, s.y + 8, DeskView.METAL.darkened(0.45))
	v.rect(o.x, o.y, s.x, s.y, DeskView.INK)
	for k in range(1, 10):
		v.line(o + Vector2(s.x * k / 10.0, 0), o + Vector2(s.x * k / 10.0, s.y), DeskView.WALL.darkened(0.1))
	for k in range(1, 4):
		v.line(o + Vector2(0, s.y * k / 4.0), o + Vector2(s.x, s.y * k / 4.0), DeskView.WALL.darkened(0.1))
	for coast in COASTS:
		for k in range(1, coast.size()):
			v.line(o + coast[k - 1] * s, o + coast[k] * s, DeskView.PAPER)
	var home := o + HOME * s
	var used := {}
	for row in relations.slice(0, PINS.size()):
		var slot := absi(hash(str(row.get("id", "")))) % PINS.size()
		while used.has(slot):
			slot = (slot + 1) % PINS.size()
		used[slot] = true
		var p: Vector2 = o + PINS[slot] * s
		var tone := int(row.get("tone", 0))
		v.line(home, p, DeskView.STONE.darkened(0.35))
		var c := DeskView.PAPER.darkened(0.45)
		if tone > 0:
			c = DeskView.LAMP
		elif tone < 0:
			var pulse := 0.8 + 0.2 * sin(t * 1.2 + slot)
			c = DeskView.ALARM * Color(pulse, pulse, pulse)
		v.rect(p.x - 2, p.y - 2, 4, 4, c)
	v.rect(home.x - 3, home.y - 3, 6, 6, DeskView.PAPER)


## Flags along the west wall, a gap now and then where a door stands.
static func _flags(v: DeskView, t: float) -> void:
	var first := int(floorf((v.left - 20.0) / 24.0))
	for i in range(first, 6):
		if posmod(i, 7) == 6:
			continue
		var x := 8.0 + i * 24.0
		v.line(Vector2(x, FLOOR - 2), Vector2(x, 44), DeskView.STONE.darkened(0.2))
		v.rect(x - 2, FLOOR - 4, 5, 3, DeskView.STONE.darkened(0.3))
		v.rect(x - 1, 41, 3, 3, DeskView.STONE)
		# Hanging furled in still air, stirring a little now and then.
		var sway := sin(t * 0.7 + i * 1.3) * 1.5
		v.poly(PackedVector2Array([Vector2(x + 1, 46), Vector2(x + 9, 47 + sway), Vector2(x + 7, 74 + sway), Vector2(x + 1, 72)]),
			FLAGS[posmod(i * 5, FLAGS.size())].darkened(0.3))


static func _table(v: DeskView, t: float) -> void:
	var top := 172.0
	# The far delegation, facing us; one of them is making a point.
	for k in 6:
		var x := 186.0 + k * 50.0
		var shift := 1.0 if sin(t * 0.45 + k * 2.1) > 0.93 else 0.0
		var pose := "point" if k == 2 and sin(t * 0.35) > 0.5 else "sit"
		v.figure(x, top + 1 - shift, DeskView.FIGURE.darkened(0.05), pose, t, 22.0)
	v.rect(166, top, 308, 3, DeskView.WOOD.darkened(0.25))
	v.rect(166, top + 3, 308, 8, DeskView.WOOD.darkened(0.6))
	v.rect(170, top + 11, 3, 18, DeskView.WOOD.darkened(0.5))
	v.rect(467, top + 11, 3, 18, DeskView.WOOD.darkened(0.5))
	for k in 6:
		v.rect(184.0 + k * 50.0, top - 1, 8, 2, DeskView.PAPER.darkened(0.3))
	for x in [270.0, 370.0]:
		var pulse := 0.85 + 0.15 * sin(t * 0.8 + x)
		v.line(Vector2(x + 1, top), Vector2(x + 1, top - 6), DeskView.METAL.darkened(0.2))
		v.rect(x - 1, top - 9, 4, 3, DeskView.LAMP * Color(pulse, pulse, pulse))
	# The near delegation, backs to us, in shadow.
	for k in 6:
		var x := 210.0 + k * 50.0
		var shift := 1.0 if sin(t * 0.5 + k * 1.4 + 3.0) > 0.94 else 0.0
		v.figure(x, 208 - shift, DeskView.FIGURE.darkened(0.4), "sit", t, 24.0)


static func _courier(v: DeskView, t: float) -> void:
	var g := _glide(t, -70.0, 150.0, 80.0)
	var tone := DeskView.FIGURE.darkened(0.1)
	v.figure(g.x, 226, tone, "walk" if g.y > 0.0 else "stand", t, 18.0)
	v.rect(g.x + 5, 214, 6, 5, DeskView.PAPER.darkened(0.1))


## Teleprinters behind glass, repeated to the panel's east edge: each with its
## operator, a winking carriage lamp and a paper strip creeping to the floor.
static func _cable_room(v: DeskView, t: float) -> void:
	v.line(Vector2(500, 112), Vector2(500, 236), DeskView.METAL.darkened(0.2))
	v.line(Vector2(504, 112), Vector2(504, 236), DeskView.METAL.darkened(0.5))
	var count := int((v.right - 520.0) / 64.0) + 1
	for i in count:
		var m := 530.0 + i * 64.0
		# World-time clocks above, their hands turning very slowly.
		var c := Vector2(m + 12, 64)
		v.disc(c, 13, DeskView.STONE)
		v.disc(c, 11, DeskView.INK)
		var a := t * 0.05 + i * 1.7
		v.line(c, c + Vector2(cos(a), sin(a)) * 6.0, DeskView.PAPER, 2.0)
		v.line(c, c + Vector2(cos(a * 12.0), sin(a * 12.0)) * 9.0, DeskView.PAPER.darkened(0.2))
		var shift := 1.0 if sin(t * 0.6 + i * 2.2) > 0.9 else 0.0
		v.figure(m - 10, 190 - shift, DeskView.FIGURE.darkened(0.2), "sit", t, 16.0)
		v.rect(m, 176, 24, 14, DeskView.METAL.darkened(0.35))
		v.rect(m + 2, 172, 20, 4, DeskView.METAL.darkened(0.2))
		v.line(Vector2(m + 3, 190), Vector2(m + 3, 222), DeskView.METAL.darkened(0.45))
		v.line(Vector2(m + 21, 190), Vector2(m + 21, 222), DeskView.METAL.darkened(0.45))
		if int(t * 2.0 + i) % 3 == 0:
			v.rect(m + 18, 178, 2, 2, DeskView.LAMP)
		var strip := fposmod(t * 1.2 + i * 13.0, 40.0)
		v.rect(m + 10, 186, 4, 4 + strip, DeskView.PAPER.darkened(0.15))


static func _glide(t: float, a: float, b: float, period: float) -> Vector2:
	var tri := absf(fposmod(t / period, 1.0) * 2.0 - 1.0)
	var s := smoothstep(0.15, 0.85, tri)
	return Vector2(lerpf(a, b, s), 1.0 if s > 0.0 and s < 1.0 else 0.0)
