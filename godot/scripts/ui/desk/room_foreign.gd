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
## The table in perspective: far end and near end, each (left x, right x, y).
const FAR := Vector3(272, 368, 254)
const NEAR := Vector3(150, 490, 372)


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


## The map is the room's bright thing: thin coasts on a dark board, a
## graticule, and a pin for every government — threads run home to each.
static func _map(v: DeskView, t: float, relations: Array) -> void:
	var o := MAP.position
	var s := MAP.size
	v.rect(o.x - 8, o.y - 8, s.x + 16, s.y + 16, DeskView.STONE.darkened(0.2))
	v.rect(o.x - 4, o.y - 4, s.x + 8, s.y + 8, DeskView.METAL.darkened(0.1))
	v.rect(o.x, o.y, s.x, s.y, DeskView.INK)
	for k in range(1, 12):
		var x := o.x + s.x * k / 12.0
		v.line(Vector2(x, o.y), Vector2(x, o.y + s.y), DeskView.WALL.darkened(0.05), 1.5)
	for k in range(1, 6):
		var y := o.y + s.y * k / 6.0
		v.line(Vector2(o.x, y), Vector2(o.x + s.x, y), DeskView.WALL.darkened(0.05), 1.5)
	# Graduation ticks on the frame.
	for k in 25:
		v.rect(o.x + s.x * k / 24.0 - 0.75, o.y - 4, 1.5, 3, DeskView.PAPER.darkened(0.4))
	for coast in COASTS:
		for k in range(1, coast.size()):
			v.line(o + coast[k - 1] * s, o + coast[k] * s, DeskView.PAPER.darkened(0.05), 2.0)
	# Shipping lanes, dashed, across the oceans.
	for k in 14:
		var a := Vector2(0.27 + k * 0.012, 0.3 + k * 0.006)
		if k % 2 == 0:
			v.line(o + a * s, o + (a + Vector2(0.008, 0.004)) * s, DeskView.STONE.darkened(0.2), 1.5)
	var home := o + HOME * s
	var used := {}
	for row in relations.slice(0, PINS.size()):
		var slot := absi(hash(str(row.get("id", "")))) % PINS.size()
		while used.has(slot):
			slot = (slot + 1) % PINS.size()
		used[slot] = true
		var p: Vector2 = o + PINS[slot] * s
		var tone := int(row.get("tone", 0))
		v.line(home, p, DeskView.STONE.lightened(0.05), 1.5)
		var c := DeskView.PAPER.darkened(0.4)
		if tone > 0:
			c = DeskView.LAMP
		elif tone < 0:
			var pulse := 0.8 + 0.2 * (0.5 + 0.5 * sin(t * 0.9 + slot))
			c = DeskView.ALARM * Color(pulse, pulse, pulse)
		v.rect(p.x - 3, p.y - 3, 6, 6, c)
		v.rect(p.x + 3.5, p.y - 1, 6, 1.5, DeskView.PAPER.darkened(0.55))
	v.disc(home, 5, DeskView.PAPER.darkened(0.2))
	v.rect(home.x - 2.5, home.y - 2.5, 5, 5, DeskView.PAPER)
	# The legend card and the compass rose in the corners.
	v.rect(o.x + 6, o.y + s.y - 26, 46, 20, DeskView.WALL.darkened(0.2))
	for k in 3:
		v.rect(o.x + 10, o.y + s.y - 22 + k * 6, 3, 3, [DeskView.LAMP, DeskView.PAPER.darkened(0.4), DeskView.ALARM.darkened(0.2)][k])
		v.rect(o.x + 16, o.y + s.y - 21.5 + k * 6, 30, 1.5, DeskView.PAPER.darkened(0.5))
	var rose := o + Vector2(s.x - 20, s.y - 20)
	v.line(rose + Vector2(0, -12), rose + Vector2(0, 12), DeskView.PAPER.darkened(0.3), 1.5)
	v.line(rose + Vector2(-12, 0), rose + Vector2(12, 0), DeskView.PAPER.darkened(0.3), 1.5)
	v.poly(PackedVector2Array([rose + Vector2(0, -12), rose + Vector2(3, 0), rose + Vector2(-3, 0)]), DeskView.PAPER.darkened(0.15))
	# The plaque beneath.
	v.rect(o.x + s.x * 0.5 - 30, o.y + s.y + 10, 60, 6, DeskView.LAMP.darkened(0.55))


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


## Parquet in perspective, a carpet under the table.
static func _floor(v: DeskView) -> void:
	var w := v.right - v.left
	v.rect(v.left, FLOOR, w, 420 - FLOOR, DeskView.WALL.darkened(0.62))
	var ys: Array[float] = [FLOOR]
	var step := 6.0
	while ys[-1] < 420.0:
		ys.append(ys[-1] + step)
		step *= 1.28
	var lit := DeskView.WALL.darkened(0.3)
	for r in ys.size() - 1:
		var f0 := (ys[r] - VP.y) / (420.0 - VP.y)
		var f1 := (ys[r + 1] - VP.y) / (420.0 - VP.y)
		for c in range(-16, 16):
			if posmod(r + c, 2) != 0:
				continue
			var a := c * 90.0
			var b := (c + 1) * 90.0
			if VP.x + b * f1 < v.left or VP.x + a * f1 > v.right:
				continue
			v.poly(PackedVector2Array([Vector2(VP.x + a * f0, ys[r]), Vector2(VP.x + b * f0, ys[r]),
				Vector2(VP.x + b * f1, ys[r + 1]), Vector2(VP.x + a * f1, ys[r + 1])]), lit)
	v.poly(PackedVector2Array([Vector2(FAR.x - 46, FAR.z - 12), Vector2(FAR.y + 46, FAR.z - 12),
		Vector2(NEAR.y + 120, 420), Vector2(NEAR.x - 120, 420)]), CARPET)
	v.poly(PackedVector2Array([Vector2(FAR.x - 40, FAR.z - 9), Vector2(FAR.y + 40, FAR.z - 9),
		Vector2(NEAR.y + 106, 420), Vector2(NEAR.x - 106, 420)]), CARPET.darkened(0.3))
	v.poly(PackedVector2Array([Vector2(FAR.x - 36, FAR.z - 7), Vector2(FAR.y + 36, FAR.z - 7),
		Vector2(NEAR.y + 96, 420), Vector2(NEAR.x - 96, 420)]), CARPET)


## Under the map: an aide points out the latest pin; another waits by the
## chairman's place with a folder.
static func _aides(v: DeskView, t: float) -> void:
	var pointing := sin(t * 0.3) > -0.2
	v.figure(210, FLOOR + 2, DeskView.FIGURE.darkened(0.15), "point" if pointing else "stand", t, 26.0)
	if pointing:
		v.line(Vector2(222, FLOOR - 15), Vector2(236, 170), DeskView.STONE.lightened(0.1), 1.5)
	v.figure(420, FLOOR + 2, DeskView.FIGURE.darkened(0.25), "stand", t, 25.0)
	v.rect(427, FLOOR - 15, 6, 7, DeskView.PAPER.darkened(0.25))


## The long table runs from the far wall toward the viewer: chairs and seated
## delegates down both sides, papers, carafes and lamps along its length.
static func _table(v: DeskView, t: float) -> void:
	# The chairman's high-backed chair and the chairman at the far end.
	var cx := (FAR.x + FAR.y) * 0.5
	v.rect(cx - 9, FAR.z - 34, 18, 34, TIMBER.darkened(0.35))
	v.rect(cx - 7, FAR.z - 37, 14, 3, TIMBER.darkened(0.1))
	v.figure(cx - 3, FAR.z + 6, DeskView.FIGURE.darkened(0.05), "sit", t, 20.0)
	# The top, its near edge and legs.
	var top := PackedVector2Array([Vector2(FAR.x, FAR.z), Vector2(FAR.y, FAR.z), Vector2(NEAR.y, NEAR.z), Vector2(NEAR.x, NEAR.z)])
	v.poly(top, TIMBER.darkened(0.82))
	v.poly(PackedVector2Array([Vector2(FAR.x + 5, FAR.z + 1), Vector2(FAR.y - 5, FAR.z + 1), Vector2(NEAR.y - 14, NEAR.z - 2), Vector2(NEAR.x + 14, NEAR.z - 2)]), TIMBER.darkened(0.74))
	v.rect(NEAR.x, NEAR.z, NEAR.y - NEAR.x, 10, TIMBER.darkened(0.65))
	v.rect(NEAR.x, NEAR.z, NEAR.y - NEAR.x, 2, TIMBER.darkened(0.15))
	v.rect(NEAR.x + 6, NEAR.z + 10, 6, 32, TIMBER.darkened(0.7))
	v.rect(NEAR.y - 12, NEAR.z + 10, 6, 32, TIMBER.darkened(0.7))
	# The baize runner down the centre.
	v.poly(PackedVector2Array([Vector2(cx - 12, FAR.z + 2), Vector2(cx + 12, FAR.z + 2), Vector2(cx + 40, NEAR.z - 3), Vector2(cx - 40, NEAR.z - 3)]), Color(0.12, 0.17, 0.13))
	# Down both sides, far to near: papers, glasses, then chair and delegate.
	var seats := 5
	for k in seats:
		var f := (k + 0.6) / (seats + 0.2)
		var y := lerpf(FAR.z, NEAR.z, f)
		var s := lerpf(0.75, 1.55, f)
		var lx := lerpf(FAR.x, NEAR.x, f)
		var rx := lerpf(FAR.y, NEAR.y, f)
		for side in 2:
			var edge := lx if side == 0 else rx
			var dir := 1.0 if side == 0 else -1.0
			var px := edge + dir * 8 * s - (0.0 if side == 0 else 14 * s)
			v.rect(px, y - 4 * s, 14 * s, 4 * s, DeskView.PAPER.darkened(0.2))
			v.rect(px + 2 * s, y - 3 * s, 8 * s, 1.0, DeskView.WALL)
			v.rect(px + (16 * s if side == 0 else -5 * s), y - 7 * s, 3 * s, 5 * s, GLASS.lightened(0.35))
		# A carafe and a lamp on the runner, alternating.
		var cy := y - 2 * s
		if k % 2 == 0:
			v.rect(cx - 2.5 * s, cy - 12 * s, 5 * s, 12 * s, GLASS.lightened(0.45))
			v.rect(cx - 1.5 * s, cy - 15 * s, 3 * s, 3 * s, GLASS.lightened(0.3))
			v.rect(cx - 1.5 * s, cy - 8 * s, 3 * s, 2, DeskView.PAPER.darkened(0.1))
		else:
			var p := 0.88 + 0.12 * sin(t * 0.7 + k)
			v.rect(cx - 0.75 * s, cy - 12 * s, 1.5 * s, 12 * s, DeskView.METAL.darkened(0.1))
			v.poly(PackedVector2Array([Vector2(cx - 6 * s, cy - 12 * s), Vector2(cx + 6 * s, cy - 12 * s), Vector2(cx + 3 * s, cy - 17 * s), Vector2(cx - 3 * s, cy - 17 * s)]), Color(0.22, 0.4, 0.27))
			v.rect(cx - 1.5 * s, cy - 12 * s, 3 * s, 2 * s, DeskView.LAMP * Color(p, p, p))
	for k in seats:
		var f := (k + 0.6) / (seats + 0.2)
		var y := lerpf(FAR.z, NEAR.z, f)
		var s := lerpf(0.75, 1.55, f)
		var h := 22.0 * s
		var u := h / 18.0
		for side in 2:
			var edge := lerpf(FAR.x, NEAR.x, f) if side == 0 else lerpf(FAR.y, NEAR.y, f)
			var dir := -1.0 if side == 0 else 1.0
			var fx := edge + dir * 14 * s - 2 * u
			var tone := DeskView.FIGURE.lightened(0.08).darkened(0.08 * side + 0.15 * (1.0 - f))
			# The high back stands outside the delegate.
			var bx := edge + dir * 26 * s - 3 * s
			v.rect(bx, y - 30 * s, 6 * s, 34 * s, TIMBER.darkened(0.5))
			v.rect(bx - 1 * s, y - 32 * s, 8 * s, 3 * s, TIMBER.darkened(0.15))
			v.rect(bx, y + 4 * s, 2 * s, 10 * s, TIMBER.darkened(0.6))
			var shift := 1.0 if sin(t * 0.45 + k * 2.1 + side * 1.4) > 0.93 else 0.0
			var pose := "sit"
			if side == 1 and k == 2 and sin(t * 0.35) > 0.4:
				pose = "point"
			v.figure(fx, y + 6 * u - shift, tone, pose, t, h)


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
