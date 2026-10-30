class_name RoomForeign
extends RefCounted

## The diplomacy desk's room: the Ministry of Foreign Affairs. The great
## world map fills the far wall, every known government pinned — friends in
## warm light, hostile powers in alarm — and an aide points out the latest.
## Below it the long negotiating table runs toward the viewer, delegations
## seated down both sides among papers and water carafes, two chandeliers
## overhead. Flags stand in a row along the west wall beside the doorway a
## courier comes in by; behind glass on the east side the cable room's
## teleprinters feed out paper under the world-time clocks.
##
## data: relations (one per foreign government: id, tone -1 hostile /
## 0 neutral / +1 friendly).

const FLOOR := 236.0
const VP := Vector2(320, 150)
const MAP := Rect2(156, 30, 328, 142)
const HOME := Vector2(0.5, 0.3)          # Ardenia, on the map's own 0..1 grid
const TIMBER := Color(0.44, 0.41, 0.37)  # dark oak, kept off the alarm's rust
const CARPET := Color(0.07, 0.09, 0.15)
const GLASS := Color(0.1, 0.13, 0.2)
## Where foreign governments are pinned, all on land.
const PINS := [
	Vector2(0.45, 0.24), Vector2(0.58, 0.2), Vector2(0.56, 0.36), Vector2(0.47, 0.38),
	Vector2(0.64, 0.3), Vector2(0.72, 0.2), Vector2(0.8, 0.3), Vector2(0.53, 0.56),
	Vector2(0.56, 0.7), Vector2(0.15, 0.24), Vector2(0.19, 0.62), Vector2(0.86, 0.74),
	Vector2(0.88, 0.24), Vector2(0.64, 0.13), Vector2(0.44, 0.31), Vector2(0.1, 0.36),
]
## The continents, as simple outlines on the map's own 0..1 grid.
const LANDS := [
	[Vector2(0.04, 0.14), Vector2(0.12, 0.08), Vector2(0.22, 0.10), Vector2(0.28, 0.16), Vector2(0.27, 0.26),
		Vector2(0.22, 0.33), Vector2(0.17, 0.42), Vector2(0.11, 0.44), Vector2(0.07, 0.36), Vector2(0.05, 0.26)],
	[Vector2(0.16, 0.50), Vector2(0.22, 0.49), Vector2(0.27, 0.56), Vector2(0.26, 0.68), Vector2(0.22, 0.80),
		Vector2(0.19, 0.90), Vector2(0.16, 0.82), Vector2(0.14, 0.68), Vector2(0.13, 0.57)],
	[Vector2(0.40, 0.16), Vector2(0.46, 0.10), Vector2(0.55, 0.08), Vector2(0.66, 0.06), Vector2(0.78, 0.08),
		Vector2(0.90, 0.12), Vector2(0.95, 0.20), Vector2(0.93, 0.30), Vector2(0.86, 0.36), Vector2(0.80, 0.40),
		Vector2(0.72, 0.38), Vector2(0.66, 0.44), Vector2(0.60, 0.42), Vector2(0.54, 0.45), Vector2(0.48, 0.44),
		Vector2(0.43, 0.38), Vector2(0.41, 0.30)],
	[Vector2(0.47, 0.50), Vector2(0.54, 0.48), Vector2(0.61, 0.52), Vector2(0.63, 0.62), Vector2(0.60, 0.74),
		Vector2(0.56, 0.84), Vector2(0.52, 0.90), Vector2(0.49, 0.80), Vector2(0.47, 0.68), Vector2(0.45, 0.58)],
	[Vector2(0.80, 0.66), Vector2(0.88, 0.63), Vector2(0.94, 0.68), Vector2(0.93, 0.78), Vector2(0.86, 0.82),
		Vector2(0.80, 0.78), Vector2(0.78, 0.71)],
	[Vector2(0.32, 0.30), Vector2(0.35, 0.28), Vector2(0.36, 0.33), Vector2(0.33, 0.35)],
	[Vector2(0.70, 0.55), Vector2(0.74, 0.53), Vector2(0.75, 0.58), Vector2(0.71, 0.60)],
	[Vector2(0.30, 0.72), Vector2(0.34, 0.70), Vector2(0.33, 0.77)],
]
## National borders inked across the land.
const BORDERS := [
	[Vector2(0.52, 0.09), Vector2(0.53, 0.20), Vector2(0.50, 0.26)], [Vector2(0.535, 0.30), Vector2(0.58, 0.32), Vector2(0.60, 0.42)],
	[Vector2(0.62, 0.07), Vector2(0.60, 0.18), Vector2(0.66, 0.26), Vector2(0.70, 0.39)],
	[Vector2(0.75, 0.08), Vector2(0.76, 0.22), Vector2(0.84, 0.30), Vector2(0.86, 0.36)],
	[Vector2(0.53, 0.20), Vector2(0.60, 0.18)], [Vector2(0.41, 0.27), Vector2(0.47, 0.30)],
	[Vector2(0.485, 0.33), Vector2(0.50, 0.44)], [Vector2(0.76, 0.22), Vector2(0.94, 0.20)],
	[Vector2(0.06, 0.27), Vector2(0.16, 0.30), Vector2(0.22, 0.33)], [Vector2(0.15, 0.09), Vector2(0.16, 0.30)],
	[Vector2(0.46, 0.62), Vector2(0.62, 0.60)], [Vector2(0.54, 0.48), Vector2(0.53, 0.62)],
	[Vector2(0.48, 0.76), Vector2(0.59, 0.74)], [Vector2(0.14, 0.66), Vector2(0.26, 0.64)],
	[Vector2(0.86, 0.63), Vector2(0.85, 0.82)],
]
## Ardenia itself, picked out in cream around HOME.
const ARDENIA := [Vector2(0.48, 0.27), Vector2(0.52, 0.26), Vector2(0.535, 0.30), Vector2(0.52, 0.335), Vector2(0.485, 0.33), Vector2(0.47, 0.30)]
const SEA := Color(0.07, 0.10, 0.19)
const LAND := Color(0.27, 0.28, 0.19)
const COAST := Color(0.75, 0.70, 0.58)
const BORDER := Color(0.16, 0.15, 0.12)
const LEATHER := Color(0.22, 0.09, 0.08)
const TABLE_TOP := Color(0.11, 0.09, 0.08)
const TABLE_EDGE := Color(0.62, 0.52, 0.38)
const OURS := Color(0.70, 0.20, 0.16)
const THEIRS := Color(0.30, 0.40, 0.62)
const PLACES := 5
const FLAGS := [
	Color(0.42, 0.22, 0.2), Color(0.25, 0.3, 0.42), Color(0.55, 0.5, 0.36),
	Color(0.28, 0.36, 0.28), Color(0.5, 0.46, 0.42), Color(0.36, 0.24, 0.3),
]
## The table in perspective: far end and near end, each (left x, right x, y).
const FAR := Vector3(288, 352, 252)
const NEAR := Vector3(200, 440, 370)


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
	_hall(v)
	_map(v, t, d.get("relations", []))
	_flags(v, t)
	_doorway(v)
	_cable_room(v, t)
	_floor(v)
	_aides(v, t)
	_table(v, t)
	_courier(v, t)
	_foreground(v, t)
	_chandeliers(v, t)
	v.label(Vector2(MAP.position.x, 16), "SITUATION MAP · FOREIGN CAPITALS")
	v.label(Vector2(290, 412), "THE TABLE", Vector2(320, 330))
	v.label(Vector2(540, 52), "CABLE ROOM", Vector2(566, 110))


static func _span(v: DeskView, step: float, offset: float) -> Array:
	var out := []
	var first := int(floorf((v.left - offset - step) / step))
	for i in range(first, first + int((v.right - v.left) / step) + 3):
		out.append(offset + i * step)
	return out


## Coffered ceiling, cornice and dentils, panelled walls between pilasters,
## a picture rail and a dado.
static func _hall(v: DeskView) -> void:
	var w := v.right - v.left
	v.rect(v.left, 0, w, FLOOR, DeskView.WALL.darkened(0.45))
	v.rect(v.left, 0, w, 10, DeskView.INK)
	for x: float in _span(v, 20.0, 0.0):
		v.rect(x + 3, 2, 14, 6, DeskView.WALL.darkened(0.12))
		v.rect(x + 8, 4, 4, 2, DeskView.STONE.darkened(0.4))
	v.rect(v.left, 10, w, 2.5, DeskView.STONE)
	for x: float in _span(v, 6.0, 0.0):
		v.rect(x, 13.5, 3, 2.5, DeskView.STONE.darkened(0.35))
	v.rect(v.left, 18, w, 1.5, DeskView.STONE.darkened(0.3))
	for x: float in _span(v, 72.0, 12.0):
		# Raised panels, tall above the dado and short below it.
		v.rect(x + 8, 28, 56, 150, DeskView.WALL.darkened(0.3))
		v.line(Vector2(x + 8, 28), Vector2(x + 64, 28), DeskView.STONE.darkened(0.45), 1.5)
		v.line(Vector2(x + 8, 28), Vector2(x + 8, 178), DeskView.STONE.darkened(0.45), 1.5)
		v.rect(x + 8, 194, 56, 34, DeskView.WALL.darkened(0.3))
		v.line(Vector2(x + 8, 194), Vector2(x + 64, 194), DeskView.STONE.darkened(0.5), 1.5)
		v.rect(x - 4, 20, 8, FLOOR - 20, DeskView.STONE.darkened(0.42))
		v.rect(x - 6, 20, 12, 5, DeskView.STONE.darkened(0.15))
		v.rect(x - 6, FLOOR - 8, 12, 8, DeskView.STONE.darkened(0.3))
		v.line(Vector2(x, 26), Vector2(x, FLOOR - 9), DeskView.STONE.darkened(0.6), 1.5)
	v.rect(v.left, 184, w, 3, DeskView.STONE.darkened(0.25))
	v.rect(v.left, FLOOR - 4, w, 4, DeskView.STONE.darkened(0.35))


## The map is the room's bright thing: khaki continents on a navy sea with a
## faint graticule, national borders inked across the land, Ardenia picked
## out in cream, and a pin for every government with a thread run home.
static func _map(v: DeskView, t: float, relations: Array) -> void:
	var o := MAP.position
	var s := MAP.size
	# A gilt frame on a dark mount, two picture lamps over it.
	v.rect(o.x - 9, o.y - 9, s.x + 18, s.y + 18, Color(0.12, 0.10, 0.09))
	v.rect(o.x - 5, o.y - 5, s.x + 10, s.y + 10, DeskView.LAMP.darkened(0.45))
	v.rect(o.x - 3, o.y - 3, s.x + 6, s.y + 6, Color(0.12, 0.10, 0.09))
	v.rect(o.x, o.y, s.x, s.y, SEA)
	for k in range(1, 12):
		var x := o.x + s.x * k / 12.0
		v.line(Vector2(x, o.y + 1), Vector2(x, MAP.end.y - 1), SEA.lightened(0.1), 1.0)
	for k in range(1, 6):
		var y := o.y + s.y * k / 6.0
		v.line(Vector2(o.x + 1, y), Vector2(MAP.end.x - 1, y), SEA.lightened(0.1), 1.0)
	# Land, then its coasts, then the borders across it.
	for land in LANDS:
		v.poly(_on_map(land), LAND)
	for land in LANDS:
		var pts := _on_map(land)
		for k in pts.size():
			v.line(pts[k], pts[(k + 1) % pts.size()], COAST, 1.5)
	for border in BORDERS:
		var pts := _on_map(border)
		for k in range(1, pts.size()):
			v.line(pts[k - 1], pts[k], BORDER, 1.0)
	v.poly(_on_map(ARDENIA), DeskView.PAPER.darkened(0.1))
	# Pins and threads.
	var home := o + HOME * s
	var used := {}
	for row in relations.slice(0, PINS.size()):
		var slot := absi(hash(str(row.get("id", "")))) % PINS.size()
		while used.has(slot):
			slot = (slot + 1) % PINS.size()
		used[slot] = true
		var p: Vector2 = o + PINS[slot] * s
		var tone := int(row.get("tone", 0))
		v.line(home, p, DeskView.LAMP.darkened(0.55), 1.0)
		var c := DeskView.PAPER.darkened(0.15)
		if tone > 0:
			c = DeskView.LAMP
		elif tone < 0:
			var pulse := 0.75 + 0.25 * (0.5 + 0.5 * sin(t * 0.9 + slot))
			c = DeskView.ALARM * Color(pulse, pulse, pulse)
		v.rect(p.x - 0.75, p.y + 1, 1.5, 4, DeskView.INK)
		v.rect(p.x - 4, p.y - 5, 8, 7, DeskView.INK)
		v.rect(p.x - 3, p.y - 4, 6, 5, c)
	v.rect(home.x - 3, home.y - 3, 6, 6, DeskView.ALARM.darkened(0.1))
	v.rect(home.x - 1.5, home.y - 1.5, 3, 3, DeskView.PAPER)
	# The title cartouche, the legend card and the compass rose.
	v.rect(o.x + s.x * 0.64, o.y + s.y - 26, 48, 22, DeskView.PAPER.darkened(0.25))
	for k in 3:
		v.rect(o.x + s.x * 0.64 + 4, o.y + s.y - 22 + k * 6, 4, 4, [DeskView.LAMP, DeskView.PAPER.darkened(0.15), DeskView.ALARM][k])
		v.rect(o.x + s.x * 0.64 + 11, o.y + s.y - 20.5 + k * 6, 32, 1.5, Color(0.14, 0.18, 0.30))
	var rose := o + Vector2(s.x - 20, s.y - 20)
	v.line(rose + Vector2(0, -12), rose + Vector2(0, 12), DeskView.PAPER.darkened(0.2), 1.5)
	v.line(rose + Vector2(-12, 0), rose + Vector2(12, 0), DeskView.PAPER.darkened(0.2), 1.5)
	v.poly(PackedVector2Array([rose + Vector2(0, -13), rose + Vector2(3, 0), rose + Vector2(-3, 0)]), DeskView.PAPER)
	# Picture lamps on the frame top, their light falling on the map.
	for x: float in [o.x + s.x * 0.25, o.x + s.x * 0.75]:
		var glow := 0.9 + 0.1 * sin(t * 0.5 + x)
		v.rect(x - 9, o.y - 13, 18, 4, DeskView.LAMP.darkened(0.35))
		v.rect(x - 7, o.y - 9, 14, 1.5, DeskView.LAMP * Color(glow, glow, glow))
		v.line(Vector2(x, o.y - 13), Vector2(x, o.y - 18), DeskView.LAMP.darkened(0.45), 1.5)
	# The plaque beneath.
	v.rect(o.x + s.x * 0.5 - 30, o.y + s.y + 10, 60, 6, DeskView.LAMP.darkened(0.4))


static func _on_map(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in pts:
		out.append(MAP.position + p * MAP.size)
	return out


## Flags along the west wall on staffs with finials and weighted bases.
static func _flags(v: DeskView, t: float) -> void:
	for x: float in _span(v, 22.0, 2.0):
		if x > 136.0:
			break
		if x > 54.0 and x < 112.0:
			continue                          # the doorway
		var sway := sin(t * 0.5 + x * 0.13) * 1.5
		v.rect(x - 0.75, 50, 2, FLOOR - 50, DeskView.STONE.lightened(0.1))
		v.poly(PackedVector2Array([Vector2(x - 2.5, 50), Vector2(x + 0.5, 42), Vector2(x + 3.5, 50)]), DeskView.LAMP.darkened(0.45))
		v.rect(x - 5, FLOOR - 5, 12, 5, DeskView.STONE.darkened(0.2))
		var f: Color = FLAGS[posmod(int(x / 22.0) * 5, FLAGS.size())]
		v.poly(PackedVector2Array([Vector2(x + 1, 54), Vector2(x + 12, 55 + sway), Vector2(x + 11, 70 + sway),
			Vector2(x + 14, 92 + sway), Vector2(x + 1, 96)]), f.darkened(0.2))
		v.line(Vector2(x + 4, 56), Vector2(x + 4, 94), f.lightened(0.15), 1.5)


## The doorway on the west wall: architrave, pediment and a lit corridor.
static func _doorway(v: DeskView) -> void:
	var x0 := 62.0
	var x1 := 106.0
	v.rect(x0 - 6, 108, x1 - x0 + 12, FLOOR - 108, DeskView.STONE.darkened(0.2))
	v.poly(PackedVector2Array([Vector2(x0 - 10, 108), Vector2((x0 + x1) * 0.5, 94), Vector2(x1 + 10, 108)]), DeskView.STONE.darkened(0.15))
	v.rect(x0 - 10, 108, x1 - x0 + 20, 3, DeskView.STONE.lightened(0.05))
	v.rect(x0, 114, x1 - x0, FLOOR - 114, DeskView.WALL.darkened(0.1))
	# The corridor beyond, receding: its far door and a ceiling lamp.
	v.rect(x0 + 14, 140, 16, 44, DeskView.PAPER.darkened(0.5))
	v.rect(x0 + 21, 160, 2, 2, DeskView.INK)
	v.poly(PackedVector2Array([Vector2(x0, FLOOR), Vector2(x0 + 14, 184), Vector2(x0 + 30, 184), Vector2(x1, FLOOR)]), DeskView.STONE.darkened(0.25))
	v.rect((x0 + x1) * 0.5 - 1.5, 120, 3, 3, DeskView.LAMP)
	# The door leaf folded back against the jamb.
	v.rect(x1 - 6, 114, 6, FLOOR - 114, TIMBER.darkened(0.3))
	v.rect(x1 - 5, 170, 2, 3, DeskView.LAMP.darkened(0.4))


## Teleprinters behind a glazed partition on the east side, two rows deep:
## each with its operator, a winking carriage lamp and a paper strip creeping
## to the floor, under a row of world-time clocks.
static func _cable_room(v: DeskView, t: float) -> void:
	var x0 := 504.0
	var w := v.right - x0 + 4
	v.rect(x0, 60, w, FLOOR - 60, GLASS)
	v.rect(x0, 186, w, FLOOR - 186, GLASS.darkened(0.3))
	var count := int(w / 30.0) + 1
	for i in count:
		var c := Vector2(x0 + 18 + i * 30, 78)
		v.disc(c, 9, DeskView.STONE.darkened(0.1))
		v.disc(c, 7, DeskView.INK)
		var a := t * 0.02 + i * 1.7
		v.line(c, c + Vector2(sin(a), -cos(a)) * 4.0, DeskView.PAPER, 1.5)
		v.line(c, c + Vector2(sin(a * 12.0), -cos(a * 12.0)) * 6.0, DeskView.PAPER.darkened(0.25), 1.5)
		v.rect(c.x - 6, 90, 12, 2, DeskView.PAPER.darkened(0.55))
	# Shelves of cable files along the back.
	v.rect(x0, 100, w, 2, DeskView.METAL.darkened(0.3))
	for k in int(w / 5.0):
		v.rect(x0 + 2 + k * 5, 103 + fposmod(k * 3.7, 3.0), 3, 12, DeskView.PAPER.darkened(0.5 + 0.1 * (k % 3)))
	v.rect(x0, 116, w, 2, DeskView.METAL.darkened(0.3))
	_printers(v, t, x0 + 10, 180.0, 0.75, 0.3, int(w / 40.0) + 1)
	_printers(v, t, x0 + 26, 226.0, 1.0, 0.1, int(w / 52.0) + 1)
	# The glazing: frame, transom and mullions over everything behind.
	var mull := DeskView.METAL.darkened(0.05)
	v.rect(x0 - 4, 56, 6, FLOOR - 56, mull)
	v.rect(x0, 56, w, 4, mull)
	v.rect(x0, 140, w, 2.5, mull)
	v.rect(x0, 196, w, 3, mull)
	for x: float in _span(v, 26.0, x0):
		if x > x0:
			v.rect(x - 0.75, 60, 1.5, FLOOR - 60, mull.darkened(0.2))
	# A pale sheen across two panes.
	v.line(Vector2(x0 + 6, 132), Vector2(x0 + 20, 66), GLASS.lightened(0.12), 1.5)


static func _printers(v: DeskView, t: float, x0: float, foot: float, s: float, dim: float, count: int) -> void:
	var step := 52.0 * s
	for i in count:
		var m := x0 + i * step
		var shift := 1.0 if sin(t * 0.55 + i * 2.2 + s) > 0.92 else 0.0
		v.figure(m - 9 * s, foot - 14 * s - shift, DeskView.FIGURE.darkened(dim + 0.1), "sit", t, 20.0 * s)
		v.rect(m, foot - 30 * s, 26 * s, 16 * s, DeskView.METAL.darkened(0.3 + dim))
		v.rect(m + 2 * s, foot - 34 * s, 22 * s, 4 * s, DeskView.METAL.darkened(0.1 + dim))
		v.rect(m + 4 * s, foot - 26 * s, 18 * s, 4 * s, DeskView.INK)
		v.rect(m + 2 * s, foot - 14 * s, 3 * s, 14 * s, DeskView.METAL.darkened(0.5 + dim))
		v.rect(m + 21 * s, foot - 14 * s, 3 * s, 14 * s, DeskView.METAL.darkened(0.5 + dim))
		if int(t * 1.5 + i * 1.3) % 4 == 0:
			v.rect(m + 20 * s, foot - 28 * s, 2.5, 2.5, DeskView.LAMP)
		var strip := fposmod(t * 1.1 + i * 13.0, 26.0 * s)
		v.rect(m + 11 * s, foot - 36 * s - minf(strip, 8.0 * s), 5 * s, minf(strip, 8.0 * s), DeskView.PAPER.darkened(0.15 + dim))
		v.rect(m + 11 * s, foot - 14 * s, 4 * s, strip * 0.5, DeskView.PAPER.darkened(0.2 + dim))
		v.rect(m + 11 * s, foot - 1.5, 7 * s, 1.5, DeskView.PAPER.darkened(0.35 + dim))


## A dark polished floor with a border-lined rug under the table.
static func _floor(v: DeskView) -> void:
	var w := v.right - v.left
	v.rect(v.left, FLOOR, w, 420 - FLOOR, Color(0.07, 0.06, 0.06))
	var y := FLOOR + 4.0
	var step := 7.0
	while y < 420.0:
		v.line(Vector2(v.left, y), Vector2(v.right, y), Color(0.085, 0.08, 0.075), 1.0)
		y += step
		step *= 1.3
	var rug := PackedVector2Array([Vector2(FAR.x - 50, FAR.z - 14), Vector2(FAR.y + 50, FAR.z - 14),
		Vector2(NEAR.y + 130, 420), Vector2(NEAR.x - 130, 420)])
	v.poly(rug, CARPET)
	_outline(v, PackedVector2Array([Vector2(FAR.x - 44, FAR.z - 11), Vector2(FAR.y + 44, FAR.z - 11),
		Vector2(NEAR.y + 116, 420), Vector2(NEAR.x - 116, 420)]), CARPET.lightened(0.25), 1.5)


static func _outline(v: DeskView, pts: PackedVector2Array, c: Color, width: float) -> void:
	for k in pts.size():
		v.line(pts[k], pts[(k + 1) % pts.size()], c, width)


## Under the map: an aide points out the latest pin; another waits by the
## chairman's place with a folder.
static func _aides(v: DeskView, t: float) -> void:
	var pointing := sin(t * 0.3) > -0.2
	v.figure(206, FLOOR + 2, Color(0.20, 0.22, 0.28), "point" if pointing else "stand", t, 30.0, DeskView.SKIN)
	if pointing:
		v.line(Vector2(222, FLOOR - 21), Vector2(240, 160), DeskView.PAPER.darkened(0.2), 1.0)
	v.figure(424, FLOOR + 2, Color(0.30, 0.29, 0.28), "stand", t, 29.0, DeskView.SKIN)
	v.rect(431, FLOOR - 17, 6, 8, DeskView.PAPER.darkened(0.1))


## Where place `k` of `PLACES` sits down the table: (depth 0..1, y, scale).
static func _place(k: int) -> Vector3:
	var f := (k + 0.55) / (PLACES + 0.1)
	return Vector3(f, lerpf(FAR.z, NEAR.z, f), lerpf(0.8, 1.55, f))


## The long table runs from the far wall toward the viewer: the chairman at
## its head, delegations seated down both sides — ours on the left in navy,
## theirs on the right in grey — each behind a pad, a glass and a small flag,
## with carafes and lamps down the centre.
static func _table(v: DeskView, t: float) -> void:
	var cx := (FAR.x + FAR.y) * 0.5
	# The chairman's high-backed chair at the head.
	v.rect(cx - 10, FAR.z - 38, 20, 38, LEATHER)
	v.rect(cx - 12, FAR.z - 41, 24, 4, DeskView.LAMP.darkened(0.45))
	v.figure(cx - 2, FAR.z + 3, Color(0.16, 0.16, 0.18), "sit", t, 24.0, DeskView.SKIN)
	# Delegates far to near, drawn before the table so its edge cuts their laps.
	for k in PLACES:
		var pl := _place(k)
		for side in 2:
			_delegate(v, t, k, side, pl)
	# The top: dark polished wood with a lit edge down each side.
	var top := PackedVector2Array([Vector2(FAR.x, FAR.z), Vector2(FAR.y, FAR.z), Vector2(NEAR.y, NEAR.z), Vector2(NEAR.x, NEAR.z)])
	v.poly(top, TABLE_TOP)
	v.line(Vector2(FAR.x, FAR.z), Vector2(NEAR.x, NEAR.z), TABLE_EDGE, 2.5)
	v.line(Vector2(FAR.y, FAR.z), Vector2(NEAR.y, NEAR.z), TABLE_EDGE, 2.5)
	v.line(Vector2(FAR.x, FAR.z), Vector2(FAR.y, FAR.z), TABLE_EDGE, 1.5)
	# A sheen of the chandeliers down the polish.
	v.poly(PackedVector2Array([Vector2(cx - 3, FAR.z + 2), Vector2(cx + 3, FAR.z + 2), Vector2(cx + 12, NEAR.z - 2), Vector2(cx - 12, NEAR.z - 2)]), TABLE_TOP.lightened(0.12))
	v.rect(NEAR.x, NEAR.z, NEAR.y - NEAR.x, 9, TABLE_TOP.lightened(0.05))
	v.rect(NEAR.x, NEAR.z, NEAR.y - NEAR.x, 2, TABLE_EDGE)
	v.rect(NEAR.x + 8, NEAR.z + 9, 6, 40, TABLE_TOP)
	v.rect(NEAR.y - 14, NEAR.z + 9, 6, 40, TABLE_TOP)
	# Each place: a pad of papers, a glass and the delegation's table flag.
	for k in PLACES:
		var pl := _place(k)
		var s := pl.z
		var lx := lerpf(FAR.x, NEAR.x, pl.x)
		var rx := lerpf(FAR.y, NEAR.y, pl.x)
		for side in 2:
			var dir := 1.0 if side == 0 else -1.0
			var edge := lx if side == 0 else rx
			var px := edge + dir * 6 * s - (0.0 if side == 0 else 13 * s)
			v.rect(px, pl.y - 3 * s, 13 * s, 3.5 * s, DeskView.PAPER)
			v.rect(px + 2 * s, pl.y - 2 * s, 8 * s, 0.8 * s, DeskView.WALL)
			v.rect(px + (15 * s if side == 0 else -4 * s), pl.y - 6 * s, 2.5 * s, 5 * s, GLASS.lightened(0.45))
			if k % 2 == 0:
				var fx := edge + dir * 26 * s
				v.rect(fx, pl.y - 12 * s, 1, 12 * s, DeskView.METAL)
				v.rect(fx + (0.0 if side == 0 else -6 * s), pl.y - 12 * s, 6 * s, 4 * s, OURS if side == 0 else THEIRS)
		# Down the centre: a carafe, then a green-shaded lamp, alternating.
		var cy := pl.y - 2 * s
		if k % 2 == 0:
			v.rect(cx - 2.5 * s, cy - 11 * s, 5 * s, 11 * s, GLASS.lightened(0.5))
			v.rect(cx - 1.5 * s, cy - 14 * s, 3 * s, 3 * s, GLASS.lightened(0.35))
			v.rect(cx - 1.5 * s, cy - 6 * s, 3 * s, 2, DeskView.PAPER.darkened(0.05))
		else:
			var p := 0.88 + 0.12 * sin(t * 0.7 + k)
			v.rect(cx - 0.75 * s, cy - 12 * s, 1.5 * s, 12 * s, DeskView.METAL.darkened(0.1))
			v.poly(PackedVector2Array([Vector2(cx - 6 * s, cy - 12 * s), Vector2(cx + 6 * s, cy - 12 * s), Vector2(cx + 3 * s, cy - 17 * s), Vector2(cx - 3 * s, cy - 17 * s)]), Color(0.22, 0.4, 0.27))
			v.rect(cx - 4 * s, cy - 12 * s, 8 * s, 1.5 * s, DeskView.LAMP * Color(p, p, p))


## One delegate at place `k`: a high-backed chair outside the table edge and
## the delegate in it, facing across; now and then one leans in to speak.
static func _delegate(v: DeskView, t: float, k: int, side: int, pl: Vector3) -> void:
	var s := pl.z
	var h := 26.0 * s
	var u := h / 18.0
	var edge := lerpf(FAR.x, NEAR.x, pl.x) if side == 0 else lerpf(FAR.y, NEAR.y, pl.x)
	var dir := -1.0 if side == 0 else 1.0
	var fx := edge + dir * 9 * s - 2 * u
	var bx := edge + dir * 11 * s - 7 * s
	v.rect(bx, pl.y - 22 * s, 14 * s, 22 * s, LEATHER)
	v.rect(bx - 1 * s, pl.y - 24 * s, 16 * s, 2.5 * s, DeskView.LAMP.darkened(0.5))
	var coats := [Color(0.16, 0.20, 0.32), Color(0.22, 0.24, 0.34)] if side == 0 else [Color(0.40, 0.40, 0.40), Color(0.32, 0.31, 0.30)]
	var coat: Color = coats[k % 2]
	var shift := 1.0 if sin(t * 0.45 + k * 2.1 + side * 1.4) > 0.93 else 0.0
	var speaking := (side == 1 and k == 2 and sin(t * 0.35) > 0.4) or (side == 0 and k == 3 and sin(t * 0.35 + 3.0) > 0.5)
	var lean := -dir * 2.0 * s if speaking else 0.0
	v.figure(fx + lean, pl.y + 3 * u - shift, coat, "point" if speaking and side == 0 else "sit", t, h, DeskView.SKIN)
	if speaking and side == 1:
		# Facing back across the table: the arm reaches toward our side.
		v.rect(fx + lean - 7 * u, pl.y - 12 * u, 6 * u, 1.5 * u, coat)
		v.rect(fx + lean - 8.5 * u, pl.y - 12 * u, 1.5 * u, 1.5 * u, DeskView.SKIN)


static func _courier(v: DeskView, t: float) -> void:
	var g := _glide(t, 84.0, 236.0, 70.0)
	var foot := 262.0
	v.figure(g.x, foot, DeskView.FIGURE.lightened(0.05), "walk" if g.y > 0.0 else "stand", t, 28.0)
	v.rect(g.x + 6, foot - 19, 8, 6, DeskView.PAPER.darkened(0.05))
	v.rect(g.x + 6, foot - 19, 8, 1.5, DeskView.ALARM.darkened(0.3))


## Two chandeliers hanging into the room, every candle one lit point.
static func _chandeliers(v: DeskView, t: float) -> void:
	var brass := DeskView.LAMP.darkened(0.45)
	for c: Vector2 in [Vector2(132, 198), Vector2(514, 198)]:
		v.rect(c.x - 0.75, 0, 1.5, c.y - 40, DeskView.METAL.darkened(0.2))
		v.disc(c + Vector2(0, -40), 4, brass)
		v.rect(c.x - 2, c.y - 40, 4, 48, brass)
		v.disc(c + Vector2(0, 10), 6, brass)
		for tier in 3:
			var y := c.y - 26 + tier * 13.0
			var half := 14.0 + tier * 11.0
			v.poly(PackedVector2Array([Vector2(c.x - half, y), Vector2(c.x + half, y), Vector2(c.x + half - 3, y + 3), Vector2(c.x - half + 3, y + 3)]), brass)
			var n := 3 + tier * 2
			for k in n:
				var x := c.x - half + 2 + k * (2.0 * half - 4.0) / (n - 1)
				var p := 0.85 + 0.15 * sin(t * 0.8 + k * 1.7 + tier + c.x)
				v.rect(x - 1.25, y - 6, 2.5, 6, DeskView.PAPER.darkened(0.1))
				v.rect(x - 1.25, y - 9, 2.5, 3, DeskView.LAMP * Color(p, p, p))
				v.rect(x - 0.75, y + 3, 1.5, 4, DeskView.PAPER.darkened(0.35))


static func _glide(t: float, a: float, b: float, period: float) -> Vector2:
	var tri := absf(fposmod(t / period, 1.0) * 2.0 - 1.0)
	var s := smoothstep(0.15, 0.85, tri)
	return Vector2(lerpf(a, b, s), 1.0 if s > 0.0 and s < 1.0 else 0.0)


## The near corners: a stenographer at her side desk on the west, a globe
## and an attaché waiting on the east.
static func _foreground(v: DeskView, t: float) -> void:
	# Side desk with typewriter, a reading lamp and the stenographer.
	var top := 352.0
	var tap := 1.0 if sin(t * 2.0) > 0.4 else 0.0
	v.figure(70, top + 16, DeskView.FIGURE.darkened(0.1), "sit", t, 36.0)
	v.rect(30, top, 104, 4, TIMBER.darkened(0.1))
	v.rect(34, top + 4, 96, 26, TIMBER.darkened(0.65))
	v.rect(40, top + 9, 26, 8, TIMBER.darkened(0.45))
	v.rect(98, top + 9, 26, 8, TIMBER.darkened(0.45))
	v.rect(50, top + 12, 6, 2, DeskView.METAL)
	v.rect(108, top + 12, 6, 2, DeskView.METAL)
	v.rect(36, top + 30, 5, 38, TIMBER.darkened(0.7))
	v.rect(124, top + 30, 5, 38, TIMBER.darkened(0.7))
	v.rect(64, top - 10 - tap, 30, 10 + tap, DeskView.METAL.darkened(0.25))
	v.rect(68, top - 18, 22, 8, DeskView.PAPER.darkened(0.05))
	for k in 5:
		v.rect(67 + k * 5, top - 4, 3, 2, DeskView.PAPER.darkened(0.45))
	v.rect(102, top - 6, 18, 6, DeskView.PAPER.darkened(0.3))
	v.rect(103, top - 9, 16, 3, DeskView.PAPER.darkened(0.45))
	v.rect(40, top - 18, 2, 18, DeskView.METAL.darkened(0.2))
	v.poly(PackedVector2Array([Vector2(33, top - 18), Vector2(49, top - 18), Vector2(45, top - 25), Vector2(37, top - 25)]), Color(0.22, 0.4, 0.27))
	v.rect(39, top - 18, 4, 2, DeskView.LAMP)
	# The globe on its stand, turning very slowly, and the waiting attaché.
	var g := Vector2(566, 322)
	v.rect(g.x - 2, g.y + 20, 4, 50, TIMBER.darkened(0.3))
	v.poly(PackedVector2Array([Vector2(g.x - 18, g.y + 74), Vector2(g.x + 18, g.y + 74), Vector2(g.x + 6, g.y + 66), Vector2(g.x - 6, g.y + 66)]), TIMBER.darkened(0.3))
	v.disc(g, 22, GLASS.lightened(0.15))
	for k in 3:
		var off := fposmod(t * 1.2 + k * 14.0, 42.0) - 21.0
		var half := sqrt(maxf(0.0, 22.0 * 22.0 - off * off)) * 0.45
		if half > 2.0:
			v.rect(g.x + off - 2, g.y - half, 5, half * 1.6, DeskView.PAPER.darkened(0.35))
	v.line(g + Vector2(-26, -10), g + Vector2(26, 10), DeskView.LAMP.darkened(0.4), 2.0)
	v.poly(PackedVector2Array([g + Vector2(-25, 4), g + Vector2(-22, 14), g + Vector2(0, 24), g + Vector2(22, 14), g + Vector2(25, 4), g + Vector2(23, 4), g + Vector2(0, 21), g + Vector2(-23, 4)]), DeskView.LAMP.darkened(0.45))
	var shift := 1.0 if sin(t * 0.25) > 0.85 else 0.0
	v.figure(602 + shift, 404, DeskView.FIGURE.darkened(0.2), "stand", t, 40.0)
	v.rect(612 + shift, 378, 9, 10, DeskView.PAPER.darkened(0.2))
