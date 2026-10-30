class_name RoomRecords
extends RefCounted

## The records desk's room: the state archive, a vaulted reading room seen
## straight down its central aisle. Towering stacks run away on both sides in
## one-point perspective under ribbed vaulting, a catwalk rides along them at
## mid height, and rolling ladders lean on the shelves; the more history the
## campaign has made, the more of the shelves carry boxes. In the foreground an
## archivist turns pages under the reading lamp, a clerk works the card index,
## and a trolley of files is wheeled slowly up and down the aisle.
##
## data: fill (0..1, how much of the archive holds records — grows with the
## months, budgets and elections in the snapshot's history).

const SHADE := Color(0.22, 0.36, 0.26)
## Oak and buckram: kept off the rust end of the palette, which is the alarm.
const OAK := Color(0.40, 0.36, 0.25)
const RUNNER := Color(0.1, 0.1, 0.09)
## The room in its own 3-D units, projected by `_p`: x across the aisle,
## y up (eye height 0), z away from the viewer.
const VP := Vector2(320, 188)
const HALF := 260.0           # the aisle's half-width, shelf face to shelf face
const FLOOR_Y := -150.0
const TOP_Y := 112.0          # the top of the stacks, where the vault springs
const CROWN_Y := 250.0
const NEAR_Z := 0.7
const BACK_Z := 4.3
const BAYS := [0.7, 0.92, 1.18, 1.5, 1.9, 2.4, 3.0, 3.65, 4.3]
const LEVELS := 10
const LEVEL_H := 26.0
const CAT_Y := -28.0          # the catwalk deck
const CAT_W := 38.0
const MAN := 44.0             # a person's height in room units
## History that fills the whole archive (records, weighted).
const FULL := 260.0
## Shelves the archive inherited before the campaign began.
const INHERITED := 0.4


## What the room shows, read from the app snapshot.
static func data_from(snapshot: Dictionary) -> Dictionary:
	var history: Dictionary = snapshot.get("history", {})
	var records: float = float(history.get("economy", []).size()) \
		+ 12.0 * history.get("budgets", []).size() \
		+ 24.0 * history.get("elections", []).size()
	return {"fill": clampf(records / FULL, 0.0, 1.0)}


static func paint(v: DeskView, t: float, d: Dictionary) -> void:
	var fill := INHERITED + (1.0 - INHERITED) * clampf(float(d.get("fill", 0.0)), 0.0, 1.0)
	v.rect(v.left, 0, v.right - v.left, DeskView.SPACE.y, DeskView.INK)
	_vault(v)
	_back_wall(v, t)
	_floor(v)
	for side: float in [-1.0, 1.0]:
		_stacks(v, side, fill)
	_lamps(v, t)
	_ladder(v, t, -1.0, 2.75, 0.0)
	_far_people(v, t)
	_trolley(v, t)
	for side: float in [-1.0, 1.0]:
		_catwalk(v, t, side)
	_ladder(v, t, 1.0, lerpf(1.3, 2.2, _ease_cycle(t, 46.0)), 1.0)
	_floor_boxes(v)
	_card_index(v, t)
	_reading_desk(v, t)
	v.label(Vector2(24, 26), "THE STACKS", _p(-HALF, 70, 1.9))
	v.label(Vector2(540, 120), "MEZZANINE", _p(HALF - 20, CAT_Y + 30, 1.5))
	v.label(Vector2(26, 300), "CARD INDEX", Vector2(90, 330))
	v.label(Vector2(470, 404), "READING ROOM", Vector2(440, 360))


# --- geometry -----------------------------------------------------------

static func _p(x: float, y: float, z: float) -> Vector2:
	return VP + Vector2(x, -y) / z


static func _quad(v: DeskView, a: Vector2, b: Vector2, c: Vector2, e: Vector2, col: Color) -> void:
	v.poly(PackedVector2Array([a, b, c, e]), col)


## A flat face toward the viewer at depth z.
static func _face(v: DeskView, x0: float, x1: float, y0: float, y1: float, z: float, col: Color) -> void:
	var a := _p(x0, y1, z)
	var b := _p(x1, y0, z)
	v.rect(a.x, a.y, b.x - a.x, b.y - a.y, col)


## A horizontal surface at height y between depths z0 and z1.
static func _flat(v: DeskView, x0: float, x1: float, y: float, z0: float, z1: float, col: Color) -> void:
	_quad(v, _p(x0, y, z0), _p(x1, y, z0), _p(x1, y, z1), _p(x0, y, z1), col)


## A wall face at x between depths z0 and z1, from y0 up to y1.
static func _side(v: DeskView, x: float, y0: float, y1: float, z0: float, z1: float, col: Color) -> void:
	_quad(v, _p(x, y0, z0), _p(x, y0, z1), _p(x, y1, z1), _p(x, y1, z0), col)


## Further away is darker: the far wall sinks into the dark.
static func _dim(c: Color, z: float) -> Color:
	return c.darkened(clampf((z - 0.7) / 4.6, 0.0, 0.72))


## A stable pseudo-random rank 0..1, so filling is scattered but never
## flickers between frames.
static func _order(n: int) -> float:
	return fposmod(sin(n * 12.9898) * 43758.5453, 1.0)


## 0..1..0 over `period` seconds, eased at both ends and resting there.
static func _ease_cycle(t: float, period: float) -> float:
	var tri := absf(fposmod(t / period, 1.0) * 2.0 - 1.0)
	return smoothstep(0.12, 0.88, tri)


# --- the room -----------------------------------------------------------

## The barrel vault over the aisle: transverse ribs at each bay and
## longitudinal ribs running straight to the vanishing point.
static func _vault(v: DeskView) -> void:
	v.rect(v.left, 0, v.right - v.left, VP.y, DeskView.WALL.darkened(0.7))
	var rib := DeskView.STONE.darkened(0.2)
	for k in 9:
		var a := PI * (k + 0.5) / 9.0
		var x := -HALF * cos(a)
		var y := TOP_Y + (CROWN_Y - TOP_Y) * sin(a)
		v.line(_p(x, y, NEAR_Z), _p(x, y, BACK_Z), DeskView.STONE.darkened(0.6), 1.5)
	for z in BAYS:
		var prev := _p(-HALF, TOP_Y, z)
		for s in range(1, 17):
			var a := PI * s / 16.0
			var nxt := _p(-HALF * cos(a), TOP_Y + (CROWN_Y - TOP_Y) * sin(a), z)
			v.line(prev, nxt, _dim(rib, z), 2.5)
			prev = nxt
	for z in BAYS:
		for k in 9:
			var a := PI * (k + 0.5) / 9.0
			var r := _p(-HALF * cos(a), TOP_Y + (CROWN_Y - TOP_Y) * sin(a), z)
			v.rect(r.x - 1.5, r.y - 1.5, 3, 3, _dim(DeskView.PAPER.darkened(0.3), z))
	# The cornice the vault springs from, with a moulding beneath.
	for side: float in [-1.0, 1.0]:
		var x: float = side * HALF
		v.line(_p(x, TOP_Y, NEAR_Z), _p(x, TOP_Y, BACK_Z), DeskView.STONE.darkened(0.05), 3.0)
		v.line(_p(x, TOP_Y - 7, NEAR_Z), _p(x, TOP_Y - 7, BACK_Z), DeskView.STONE.darkened(0.4), 1.5)


## The end wall: an arched window between two doors.
static func _back_wall(v: DeskView, t: float) -> void:
	var z := BACK_Z
	var pts := PackedVector2Array([_p(-HALF, FLOOR_Y, z), _p(HALF, FLOOR_Y, z)])
	for s in range(0, 17):
		var a := PI * s / 16.0
		pts.append(_p(HALF * cos(a), TOP_Y + (CROWN_Y - TOP_Y) * sin(a), z))
	v.poly(pts, DeskView.WALL.darkened(0.35))
	# The tall window, its light a cold dim grey, mullioned and arched.
	var glass := DeskView.PAPER.darkened(0.62)
	var win := PackedVector2Array([_p(-70, -40, z), _p(70, -40, z)])
	for s in range(0, 13):
		var a := PI * s / 12.0
		win.append(_p(70 * cos(a), 150 + 70 * sin(a), z))
	v.poly(win, glass)
	var bar := DeskView.WALL.darkened(0.5)
	for x: float in [-35.0, 0.0, 35.0]:
		v.line(_p(x, -40, z), _p(x, 150 + 70 * sin(acos(x / 70.0)), z), bar, 2.0)
	for y: float in [10.0, 60.0, 110.0, 150.0]:
		v.line(_p(-70, y, z), _p(70, y, z), bar, 2.0)
	v.rect(_p(-78, -46, z).x, _p(0, -40, z).y, 156 / z, 2.5, DeskView.STONE.darkened(0.1))
	# Doors either side, one with a small lit exit plate.
	for x: float in [-190.0, 130.0]:
		_face(v, x, x + 60, FLOOR_Y, -40, z, OAK.darkened(0.55))
		_face(v, x + 6, x + 54, FLOOR_Y, -46, z, DeskView.INK)
	var ex := _p(150, -28, z)
	v.rect(ex.x, ex.y, 5, 2, DeskView.ALARM)
	var pulse := 0.85 + 0.15 * sin(t * 0.5)
	var lamp := _p(0, -60, z)
	v.rect(lamp.x - 1, lamp.y, 3, 2, DeskView.LAMP.darkened(0.3) * Color(pulse, pulse, pulse))


## The floor: stone tiles in perspective with a runner down the aisle.
static func _floor(v: DeskView) -> void:
	v.rect(v.left, VP.y, v.right - v.left, DeskView.SPACE.y - VP.y, DeskView.WALL.darkened(0.6))
	var zs := [0.58, 0.68, 0.8, 0.95, 1.13, 1.36, 1.65, 2.0, 2.45, 3.0, 3.65, 4.3]
	var col := 0
	for x in range(-int(HALF), int(HALF), 52):
		for k in zs.size() - 1:
			if (col + k) % 2 == 0:
				_flat(v, x, x + 52, FLOOR_Y, zs[k], zs[k + 1], _dim(DeskView.STONE.darkened(0.56), zs[k]))
		col += 1
	var joint := DeskView.STONE.darkened(0.3)
	for x in range(-int(HALF), int(HALF) + 1, 52):
		v.line(_p(x, FLOOR_Y, 0.55), _p(x, FLOOR_Y, BACK_Z), DeskView.STONE.darkened(0.35), 1.5)
	for z in zs:
		v.line(_p(-HALF, FLOOR_Y, z), _p(HALF, FLOOR_Y, z), _dim(joint.darkened(0.25), z), 1.5)
	# The runner, worn darker, with a border line each side.
	_flat(v, -44, 44, FLOOR_Y, 0.55, BACK_Z, RUNNER)
	for x: float in [-38.0, 38.0]:
		v.line(_p(x, FLOOR_Y, 0.55), _p(x, FLOOR_Y, BACK_Z), OAK.darkened(0.2), 1.5)


## One run of stacks. Each bay and level carries a row of box spines facing
## the aisle if its place in the archive's order falls under `fill`.
static func _stacks(v: DeskView, side: float, fill: float) -> void:
	var face := side * HALF
	var lip := side * (HALF - 12.0)
	_side(v, face, FLOOR_Y, TOP_Y, NEAR_Z, BACK_Z, DeskView.WALL.darkened(0.78))
	var tones := [DeskView.STONE.darkened(0.15), OAK, DeskView.PAPER.darkened(0.45), DeskView.STONE.lightened(0.05), OAK.darkened(0.3), DeskView.WOOD]
	for b in BAYS.size() - 1:
		var z0: float = BAYS[b]
		var z1: float = BAYS[b + 1]
		for l in LEVELS:
			var y0 := FLOOR_Y + 6.0 + l * LEVEL_H
			var n := int(b * 31 + l * 7 + (0 if side < 0 else 500))
			if _order(n) < fill:
				var spines := 7
				for s in spines:
					if _order(n * 13 + s) < 0.1:
						continue
					var za := lerpf(z0, z1, (s + 0.12) / spines)
					var zb := lerpf(z0, z1, (s + 0.92) / spines)
					var hh := LEVEL_H * (0.62 + 0.25 * _order(n * 7 + s * 3))
					var tone: Color = tones[(n + s) % tones.size()]
					_side(v, face, y0, y0 + hh, za, zb, _dim(tone.darkened(0.5), za))
					var mid := _p(face, y0 + hh * 0.62, (za + zb) * 0.5)
					if absf(_p(face, 0, za).x - _p(face, 0, zb).x) > 5.0:
						v.rect(mid.x - 1, mid.y, 2, 2.5, _dim(DeskView.PAPER.lightened(0.2), za * 0.8))
			# The shelf plank: its top surface and its front lip.
			_quad(v, _p(face, y0, z0), _p(lip, y0, z0), _p(lip, y0, z1), _p(face, y0, z1), _dim(DeskView.STONE.darkened(0.62), z0))
			v.line(_p(lip, y0, z0), _p(lip, y0, z1), _dim(DeskView.METAL.lightened(0.1), z0), 1.5)
		# The upright at the front of each bay.
		v.line(_p(lip, FLOOR_Y, z0), _p(lip, TOP_Y, z0), _dim(DeskView.METAL.darkened(0.05), z0), 2.5)
		var tag := _p(lip, FLOOR_Y + LEVEL_H * 4.5, z0)
		v.rect(tag.x - 1.5, tag.y, 3, 4, _dim(DeskView.PAPER, z0))
	# Plinth along the floor.
	_side(v, lip, FLOOR_Y, FLOOR_Y + 6, NEAR_Z, BACK_Z, OAK.darkened(0.45))


## A mezzanine walkway along the stacks at mid height, railed.
static func _catwalk(v: DeskView, t: float, side: float) -> void:
	var edge := side * (HALF - CAT_W)
	var face := side * HALF
	_quad(v, _p(face, CAT_Y, NEAR_Z), _p(edge, CAT_Y, NEAR_Z), _p(edge, CAT_Y, BACK_Z), _p(face, CAT_Y, BACK_Z), DeskView.METAL.darkened(0.6))
	_side(v, edge, CAT_Y - 7, CAT_Y, NEAR_Z, BACK_Z, DeskView.METAL.darkened(0.35))
	# Someone walks the left mezzanine, slowly, end to end.
	if side < 0:
		var z := lerpf(1.25, 3.3, _ease_cycle(t + 9.0, 64.0))
		var foot := _p(side * (HALF - 20), CAT_Y, z)
		var h := MAN / z
		v.figure(foot.x - h * 0.12, foot.y, DeskView.FIGURE.darkened(0.1), "walk", t, h)
	var rail := DeskView.METAL.lightened(0.05)
	for y: float in [CAT_Y + 34.0, CAT_Y + 18.0]:
		var top := _p(edge, y, NEAR_Z)
		var far := _p(edge, y, BACK_Z)
		v.line(top, far, rail.darkened(0.15 if y > CAT_Y + 20.0 else 0.35), 2.0)
	var z := NEAR_Z
	while z < BACK_Z:
		v.line(_p(edge, CAT_Y, z), _p(edge, CAT_Y + 34, z), _dim(rail.darkened(0.2), z), 1.5)
		z *= 1.13
	# The stair down at the near end, and the deck's support brackets.
	for zz: float in [1.18, 1.9, 3.0]:
		v.line(_p(edge, CAT_Y - 7, zz), _p(face, CAT_Y - 34, zz), _dim(DeskView.METAL.darkened(0.3), zz), 1.5)


## Pendant lamps down the aisle on long cords: the shades dark, the lit
## points single bright cells, breathing slowly.
static func _lamps(v: DeskView, t: float) -> void:
	var i := 0
	for z: float in [1.3, 2.05, 3.05]:
		for x: float in [-118.0, 118.0]:
			var top := _p(x, TOP_Y + (CROWN_Y - TOP_Y) * sin(acos(x / HALF)), z)
			var bulb := _p(x, 58, z)
			v.line(top, bulb, _dim(DeskView.METAL.darkened(0.3), z), 1.5)
			var w := 26.0 / z
			v.poly(PackedVector2Array([bulb + Vector2(-w * 0.35, -w * 0.5), bulb + Vector2(w * 0.35, -w * 0.5), bulb + Vector2(w, 0), bulb + Vector2(-w, 0)]),
				_dim(SHADE.lightened(0.1), z))
			v.rect(bulb.x - w, bulb.y - 1, w * 2, 1.5, _dim(DeskView.METAL.lightened(0.2), z))
			var pulse := 0.82 + 0.18 * sin(t * 0.55 + i * 1.7)
			v.rect(bulb.x - 1.5, bulb.y + 0.5, 3, 3, DeskView.LAMP * Color(pulse, pulse, pulse))
			i += 1


## A rolling ladder hooked to its rail on the shelves; `rider` puts a clerk
## on the rungs.
static func _ladder(v: DeskView, t: float, side: float, z: float, rider: float) -> void:
	var face := side * (HALF - 12.0)
	var foot := side * (HALF - 62.0)
	var wood := _dim(DeskView.PAPER.darkened(0.25), z)
	v.line(_p(face, 74, NEAR_Z), _p(face, 74, BACK_Z), _dim(DeskView.METAL.darkened(0.2), 1.6), 1.5)
	for dz: float in [-0.05, 0.05]:
		v.line(_p(foot, FLOOR_Y, z + dz), _p(face, 74, z + dz), wood, 2.5)
	for k in range(1, 14):
		var f := k / 14.0
		var x := lerpf(foot, face, f)
		var y := lerpf(FLOOR_Y, 74.0, f)
		v.line(_p(x, y, z - 0.05), _p(x, y, z + 0.05), wood.darkened(0.2), 1.5)
	for dz: float in [-0.05, 0.05]:
		v.disc(_p(foot, FLOOR_Y + 3, z + dz), 3.0 / z, _dim(DeskView.METAL, z))
	if rider > 0.0:
		var f := 0.38
		var p := _p(lerpf(foot, face, f) - side * 10.0, lerpf(FLOOR_Y, 74.0, f), z)
		var reach := sin(t * 0.3) > 0.2
		v.figure(p.x - 6, p.y, DeskView.FIGURE.lightened(0.1), "arms_up" if reach else "stand", t, MAN / z)


## Two distant figures crossing the far end of the aisle.
static func _far_people(v: DeskView, t: float) -> void:
	var z := 3.8
	var x := lerpf(-150.0, 120.0, _ease_cycle(t, 80.0))
	var p := _p(x, FLOOR_Y, z)
	v.figure(p.x, p.y, _dim(DeskView.FIGURE, z), "walk", t, MAN / z)
	var q := _p(-200, FLOOR_Y, 3.2)
	v.figure(q.x, q.y, _dim(DeskView.FIGURE, 3.2), "point" if sin(t * 0.2) > 0.0 else "stand", t, MAN / 3.2)


## A trolley of files wheeled slowly up and down the aisle.
static func _trolley(v: DeskView, t: float) -> void:
	var s := _ease_cycle(t, 72.0)
	var z := lerpf(1.75, 3.3, s)
	var moving := s > 0.0 and s < 1.0
	var x0 := 70.0
	var x1 := 126.0
	var steel := _dim(DeskView.METAL.lightened(0.1), z)
	# The clerk pushes from the far side.
	var p := _p(98, FLOOR_Y, z + 0.18)
	v.figure(p.x - 4, p.y, _dim(DeskView.FIGURE.darkened(0.05), z), "walk" if moving else "stand", t, MAN / (z + 0.18))
	for y: float in [-142.0, -118.0, -96.0]:
		_flat(v, x0, x1, y, z, z + 0.12, steel.darkened(0.25))
		_face(v, x0, x1, y - 2, y, z, steel)
	for x: float in [x0, x1]:
		v.line(_p(x, FLOOR_Y + 4, z), _p(x, -96, z), steel, 2.0)
	for k in 6:
		var bx := x0 + 2 + k * 9.0
		var hh := 14.0 + 4.0 * _order(k + 40)
		_face(v, bx, bx + 8, -118, -118 + hh, z, _dim([DeskView.PAPER.darkened(0.3), OAK, DeskView.STONE][k % 3], z))
		_face(v, bx, bx + 8, -96, -96 + hh * 0.8, z, _dim([DeskView.STONE.lightened(0.1), DeskView.PAPER.darkened(0.4)][k % 2], z))
	for x: float in [x0 + 4, x1 - 4]:
		v.disc(_p(x, FLOOR_Y + 4, z), 4.0 / z, DeskView.INK)


## Boxes waiting on the floor by the right-hand stacks.
static func _floor_boxes(v: DeskView) -> void:
	for pile: Vector3 in [Vector3(150, 1.32, 3)]:
		_box_pile(v, pile.x, pile.y, int(pile.z))


static func _box_pile(v: DeskView, x0: float, z: float, count: int) -> void:
	for k in count:
		var y := FLOOR_Y + k * 18.0
		var x := x0 + (k % 2) * 6.0
		_flat(v, x, x + 40, y + 17, z, z + 0.15, _dim(DeskView.STONE.darkened(0.5), z))
		_face(v, x, x + 40, y, y + 17, z, _dim(DeskView.STONE.darkened(0.3), z))
		v.line(_p(x, y + 17, z), _p(x + 40, y + 17, z), _dim(DeskView.PAPER.darkened(0.3), z), 1.5)
		_face(v, x + 16, x + 28, y + 7, y + 11, z, _dim(DeskView.PAPER, z))


## The steel card-index cabinets: a grid of small drawers with paper labels;
## a clerk draws one out, reads, and slides it home again.
static func _card_index(v: DeskView, t: float) -> void:
	# A second, older cabinet further back.
	var zb := 1.4
	_face(v, -250, -150, FLOOR_Y, -60, zb, _dim(DeskView.METAL.darkened(0.55), zb))
	for r in 5:
		for c in 4:
			var dx := -246 + c * 24.0
			var dy := -146 + r * 17.0
			_face(v, dx, dx + 21, dy, dy + 14, zb, _dim(DeskView.METAL.darkened(0.38), zb))
			_face(v, dx + 7, dx + 14, dy + 8, dy + 11, zb, _dim(DeskView.PAPER.darkened(0.3), zb))
	var z := 0.98
	var x0 := -252.0
	var x1 := -118.0
	var top := -62.0
	_flat(v, x0, x1, top, z, z + 0.16, DeskView.METAL.darkened(0.25))
	_side(v, x1, FLOOR_Y, top, z, z + 0.16, DeskView.METAL.darkened(0.6))
	_face(v, x0, x1, FLOOR_Y, top, z, DeskView.METAL.darkened(0.75))
	var open := smoothstep(0.0, 1.0, clampf(sin(t * 0.22) * 1.7, 0.0, 1.0))
	for r in 6:
		for c in 5:
			var dx := x0 + 4 + c * 26.0
			var dy := FLOOR_Y + 6 + r * 14.0
			var dz := z
			if r == 3 and c == 4 and open > 0.0:
				dz = z - 0.09 * open
				_flat(v, dx + 2, dx + 22, dy + 12, dz, z, DeskView.PAPER.darkened(0.15))
				_side(v, dx + 24, dy, dy + 12, dz, z, DeskView.METAL.darkened(0.55))
			_face(v, dx, dx + 24, dy, dy + 12, dz, DeskView.METAL.darkened(0.7))
			_face(v, dx + 8, dx + 16, dy + 6, dy + 10, dz, DeskView.PAPER.darkened(0.3))
			_face(v, dx + 11, dx + 13, dy + 2, dy + 4, dz, DeskView.METAL.lightened(0.3))
	# A box of cards on top.
	_face(v, -200, -170, top, top + 10, z + 0.06, OAK)
	var foot := _p(-102, FLOOR_Y, 1.06)
	v.figure(foot.x, foot.y, DeskView.FIGURE, "point" if open > 0.5 else "stand", t, MAN / 1.06)


## The reading desk: the archivist, the open volume, and the lamp — the
## room's one bright thing.
static func _reading_desk(v: DeskView, t: float) -> void:
	var zf := 0.9
	var zb := 1.1
	var o := -90.0           # the desk sits square in the aisle
	var x0 := 40.0 + o
	var x1 := 236.0 + o
	var top := -104.0
	var wood := OAK
	# The archivist, seated behind the desk; now and then they lean in.
	var lean := 1.5 if sin(t * 0.4) > 0.85 else 0.0
	var seat := _p(112 + o, top + 2, zb + 0.12)
	v.figure(seat.x, seat.y + lean, DeskView.FIGURE.lightened(0.08), "sit", t, MAN / (zb + 0.12))
	_flat(v, x0, x1, top, zf, zb, wood.darkened(0.35))
	_face(v, x0, x1, top - 6, top, zf, wood.darkened(0.15))
	v.line(_p(x0, top, zf), _p(x1, top, zf), DeskView.PAPER.darkened(0.2), 2.0)
	_face(v, x0 + 4, x1 - 4, FLOOR_Y, top - 6, zf, wood.darkened(0.72))
	for x: float in [x0 + 10.0, x1 - 38.0]:
		_face(v, x, x + 28, top - 30, top - 10, zf, wood.darkened(0.4))
		_face(v, x + 11, x + 17, top - 21, top - 18, zf, DeskView.METAL.lightened(0.2))
	# The lamp's pool on the desk top: a lighter patch, not a glow.
	_flat(v, 130 + o, 230 + o, top, zf + 0.04, zb - 0.02, wood.lightened(0.15))
	# The open volume; every few seconds a page lifts and turns, eased.
	_flat(v, 92 + o, 120 + o, top, zf + 0.05, zb - 0.05, DeskView.PAPER)
	_flat(v, 122 + o, 150 + o, top, zf + 0.05, zb - 0.05, DeskView.PAPER.darkened(0.1))
	var spine := _p(121 + o, top, zf + 0.05)
	var cycle := fposmod(t, 9.0)
	if cycle < 2.2:
		var a := PI * smoothstep(0.0, 2.2, cycle)
		var tip := _p(121 + o + cos(a) * 28.0, top + sin(a) * 22.0, zf + 0.05)
		var tip_b := _p(121 + o + cos(a) * 28.0, top + sin(a) * 22.0, zb - 0.05)
		v.poly(PackedVector2Array([spine, tip, tip_b, _p(121 + o, top, zb - 0.05)]), DeskView.PAPER.lightened(0.15))
	# Volumes stacked waiting, and loose sheets.
	for k in 4:
		_face(v, 48 + o + k * 2.0, 84 + o, top + k * 6.0, top + k * 6.0 + 5, zf + 0.08, [wood.lightened(0.2), DeskView.STONE.lightened(0.1), DeskView.PAPER.darkened(0.35), wood.darkened(0.1)][k])
	_flat(v, 160 + o, 184 + o, top, zf + 0.02, zf + 0.08, DeskView.PAPER.darkened(0.05))
	# The reading lamp: brass stem, green shade, a hot bar of light beneath.
	var pulse := 0.92 + 0.08 * sin(t * 0.7)
	var base := _p(206 + o, top, zf + 0.1)
	var head := _p(206 + o, top + 44, zf + 0.1)
	v.rect(base.x - 9, base.y - 3, 18, 3, DeskView.METAL.lightened(0.1))
	v.line(base, head, DeskView.METAL.lightened(0.25), 2.0)
	v.poly(PackedVector2Array([head + Vector2(-34, 0), head + Vector2(24, 0), head + Vector2(16, -14), head + Vector2(-26, -14)]), SHADE.lightened(0.12))
	v.rect(head.x - 28, head.y - 14, 46, 2, SHADE.lightened(0.35))
	v.rect(head.x - 32, head.y, 54, 4, DeskView.LAMP * Color(pulse, pulse, pulse))
	# The empty reading chair on our side of the desk.
	var cz := 0.78
	_face(v, 150 + o, 196 + o, top + 2, top + 30, cz, wood.darkened(0.62))
	_face(v, 154 + o, 192 + o, top + 6, top + 26, cz, wood.darkened(0.45))
	for x: float in [150.0 + o, 190.0 + o]:
		_face(v, x, x + 6, FLOOR_Y, top + 2, cz, wood.darkened(0.65))
