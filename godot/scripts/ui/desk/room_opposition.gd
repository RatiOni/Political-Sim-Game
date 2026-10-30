class_name RoomOpposition
extends RefCounted

## The opposition desk's room: the party headquarters press room seen from
## the back of the hall. The leader speaks at a lit podium on a low stage, the
## shadow cabinet standing in a line behind them before a blank campaign
## banner, stage lamps hanging from a truss overhead; rows of seated reporters
## face the stage, camera crews stand at their tripods in the aisles with
## their cables snaking back across the floor, and now and then a press camera
## flashes.
##
## data: credibility (0..1), support (the player's party polling share),
## shadow (shadow ministers named), active (true while the player is in
## opposition). Interest — credibility and polling together — fills the seats
## and brings the cameras and flashes.

## The hall in its own 3-D units, projected by `_p`: x across, y up (eye
## height 0), z away from the viewer.
const VP := Vector2(320, 122)
const FLOOR_Y := -220.0
const STAGE_Y := -195.0       # the stage deck
const STAGE_Z := 1.55         # the stage's front edge
const BACK_Z := 2.1           # the back wall
const HALL := 700.0           # the hall's half-width
const MAN := 64.0             # a standing person, in room units
const ROWS := [1.44, 1.3, 1.18, 1.07, 0.97, 0.88, 0.8, 0.73]
## Seat blocks between the aisles: [x0, x1].
const BLOCKS := [[-560.0, -300.0], [-250.0, -45.0], [45.0, 250.0], [300.0, 560.0]]
const SEAT := 40.0
const OAK := Color(0.40, 0.36, 0.25)
const FLASH := Color(1.0, 0.98, 0.9)


## What the room shows, read from the app snapshot.
static func data_from(snapshot: Dictionary) -> Dictionary:
	var model: Dictionary = snapshot.get("opposition", {})
	var party := str(snapshot.get("player", {}).get("party_id", ""))
	var support := 0.2
	for f in snapshot.get("factions", []):
		if f is Dictionary and str(f.get("id", "")) == party:
			support = float(f.get("support", support))
	var shadows: Variant = model.get("shadow_cabinet", [])
	return {
		"credibility": float(model.get("credibility", 0.5)),
		"support": support,
		"shadow": shadows.size() if shadows is Array else 0,
		"active": bool(model.get("active", true)),
	}


## How full the press room is, 0..1: half credibility, half polling (a
## party at 40 % reads as a full house).
static func interest(d: Dictionary) -> float:
	var cred := clampf(float(d.get("credibility", 0.5)), 0.0, 1.0)
	var poll := clampf(float(d.get("support", 0.2)) / 0.4, 0.0, 1.0)
	return 0.5 * cred + 0.5 * poll


static func paint(v: DeskView, t: float, d: Dictionary) -> void:
	var fill := interest(d)
	v.rect(v.left, 0, v.right - v.left, DeskView.SPACE.y, DeskView.INK)
	_hall(v, t)
	_backdrop(v)
	_truss(v, t)
	_stage(v, t, int(d.get("shadow", 0)))
	_floor(v)
	_press(v, t, fill)
	v.label(Vector2(392, 150), "THE PODIUM", _p(24, -160, 1.63))
	v.label(Vector2(470, 100), "SHADOW CABINET", _p(196, -150, 1.95))
	v.label(Vector2(16, 270), "PRESS", _p(-420, -185, 1.18))


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


## Nearer is brighter: the stage end of the hall sits a step back in the dark.
static func _dim(c: Color, z: float) -> Color:
	return c.darkened(clampf((z - 0.85) / 3.0, 0.0, 0.5))


## Stable 0..1 noise per integer pair, so seats and flashes never reshuffle.
static func _hash(a: float, b: float) -> float:
	var s := sin(a * 12.9898 + b * 78.233) * 43758.5453
	return s - floorf(s)


# --- the room -----------------------------------------------------------

## The back wall and the slivers of side wall either side: panelling,
## pilasters, a cornice, sconces and the exit doors.
static func _hall(v: DeskView, t: float) -> void:
	var z := BACK_Z
	var wall := DeskView.WALL.darkened(0.3)
	_face(v, -HALL, HALL, FLOOR_Y, 330, z, wall)
	# Side walls receding toward us.
	for side: float in [-1.0, 1.0]:
		var x: float = side * HALL
		_quad(v, _p(x, FLOOR_Y, z), _p(x, FLOOR_Y, 0.7), _p(x, 330, 0.7), _p(x, 330, z), DeskView.WALL.darkened(0.45))
		for k in 4:
			var zz: float = [2.1, 1.75, 1.45, 1.2][k]
			v.line(_p(x, FLOOR_Y, zz), _p(x, 330, zz), DeskView.STONE.darkened(0.5), 2.0)
			var glow := 0.85 + 0.15 * sin(t * 0.5 + k * 1.3 + side)
			var s := _p(x, 40, zz + 0.12)
			v.rect(s.x - 1.5, s.y, 3, 3, DeskView.LAMP * Color(glow, glow, glow))
	# Panelling: a dado rail, a picture rail and a cornice across the back.
	for y: float in [-120.0, 250.0]:
		v.line(_p(-HALL, y, z), _p(HALL, y, z), DeskView.STONE.darkened(0.35), 1.5)
	v.line(_p(-HALL, 300, z), _p(HALL, 300, z), DeskView.STONE.darkened(0.05), 3.0)
	v.line(_p(-HALL, 290, z), _p(HALL, 290, z), DeskView.STONE.darkened(0.45), 1.5)
	for k in range(-6, 7):
		var x := k * 100.0
		if absf(x) < 450.0:
			continue
		_face(v, x - 14, x + 14, FLOOR_Y, 290, z, DeskView.STONE.darkened(0.48))
		v.line(_p(x - 14, FLOOR_Y, z), _p(x - 14, 290, z), DeskView.STONE.darkened(0.2), 1.5)
	# Exit doors either side of the stage, a small lit plate over one.
	for x: float in [-640.0, 560.0]:
		_face(v, x, x + 80, STAGE_Y, -40, z, OAK.darkened(0.6))
		_face(v, x + 8, x + 72, STAGE_Y, -50, z, DeskView.INK)
	var ex := _p(590, -24, z)
	v.rect(ex.x, ex.y, 6, 2.5, DeskView.ALARM)


## The campaign backdrop: a long banner of blank cell stripes over a
## step-and-repeat board, with flags on poles to either side.
static func _backdrop(v: DeskView) -> void:
	var z := BACK_Z
	# The board behind the line-up, its emblem repeated as small dots.
	_face(v, -400, 400, STAGE_Y, 70, z, DeskView.WALL.darkened(0.55))
	for r in 5:
		for c in 15:
			var x := -370.0 + c * 53.0 + (26.0 if r % 2 == 1 else 0.0)
			if x > 380.0:
				continue
			var y := 40.0 - r * 50.0
			var p := _p(x, y, z)
			v.rect(p.x - 1.5, p.y - 1, 3, 3, DeskView.STONE.darkened(0.1))
	for sx in range(-400, 401, 160):
		v.line(_p(sx, STAGE_Y, z), _p(sx, 70, z), DeskView.WALL.darkened(0.2), 1.5)
	v.line(_p(-400, 70, z), _p(400, 70, z), DeskView.METAL.darkened(0.1), 1.5)
	# A slogan strap across the board, again only stripes of cells.
	_face(v, -300, 300, 22, 50, z, DeskView.STONE.darkened(0.3))
	var sx := -280.0
	var sk := 0
	while sx < 270.0:
		var sw := 14.0 + 30.0 * _hash(sk, 8.0)
		_face(v, sx, minf(sx + sw, 280.0), 30, 42, z, DeskView.PAPER.darkened(0.3))
		sx += sw + 10.0
		sk += 1
	# The banner: cream cloth, its lettering only stripes of cells.
	_face(v, -430, 430, 110, 222, z, DeskView.PAPER.darkened(0.12))
	_face(v, -430, 430, 110, 118, z, DeskView.ALARM.darkened(0.25))
	_face(v, -430, 430, 214, 222, z, DeskView.ALARM.darkened(0.25))
	var ink := DeskView.INK.lightened(0.12)
	v.disc(_p(-360, 166, z), 34.0 / z, ink)
	v.disc(_p(-360, 166, z), 20.0 / z, DeskView.PAPER.darkened(0.12))
	var x := -300.0
	var k := 0
	while x < 380.0:
		var w := 22.0 + 46.0 * _hash(k, 2.0)
		_face(v, x, minf(x + w, 390.0), 176, 200, z, ink)
		x += w + 12.0 + (24.0 if _hash(k, 5.0) > 0.7 else 0.0)
		k += 1
	_face(v, -300, 120, 132, 146, z, ink.lightened(0.2))
	for xx: float in [-425.0, 425.0]:
		v.line(_p(xx, 222, z), _p(xx, 300, z), DeskView.METAL.darkened(0.2), 1.5)
	# Flags on poles, hanging in folds.
	for side: float in [-1.0, 1.0]:
		var px: float = side * 480.0
		v.line(_p(px, STAGE_Y, z - 0.05), _p(px, 200, z - 0.05), DeskView.METAL.lightened(0.15), 2.0)
		v.disc(_p(px, 204, z - 0.05), 3.0, DeskView.LAMP.darkened(0.25))
		for f in 4:
			var fx := px - side * (6.0 + f * 9.0)
			var tone := DeskView.STONE.darkened(0.05) if f % 2 == 0 else DeskView.STONE.darkened(0.4)
			_face(v, minf(fx, fx - side * 9.0), maxf(fx, fx - side * 9.0), 40.0 + f * 6.0, 190, z - 0.05, tone)


## The lighting truss across the front of the stage, its lamps trained
## down on the podium: dark cans, each with one bright lens.
static func _truss(v: DeskView, t: float) -> void:
	var z := 1.8
	var steel := DeskView.METAL.lightened(0.05)
	var top := 206.0
	var low := 186.0
	v.line(_p(-560, top, z), _p(560, top, z), steel, 2.0)
	v.line(_p(-560, low, z), _p(560, low, z), steel, 2.0)
	var x := -560.0
	var k := 0
	while x < 560.0:
		var a := _p(x, top if k % 2 == 0 else low, z)
		var b := _p(x + 28.0, low if k % 2 == 0 else top, z)
		v.line(a, b, steel.darkened(0.25), 1.5)
		x += 28.0
		k += 1
	for side: float in [-1.0, 1.0]:
		v.line(_p(side * 560.0, top, z), _p(side * 560.0, 340, z), steel.darkened(0.3), 1.5)
	for i in 10:
		var lx := -470.0 + i * 104.0
		var c := _p(lx, low - 6.0, z)
		var aim := -0.35 * signf(lx) if absf(lx) > 60.0 else 0.0
		v.line(_p(lx, low, z), c, steel, 1.5)
		v.poly(PackedVector2Array([c + Vector2(-5, -2), c + Vector2(5, -2), c + Vector2(5 + aim * 6.0, 9), c + Vector2(-5 + aim * 6.0, 9)]), DeskView.METAL.darkened(0.35))
		var pulse := 0.9 + 0.1 * sin(t * 0.4 + i * 0.9)
		v.rect(c.x - 2 + aim * 6.0, c.y + 9, 4, 3, DeskView.LAMP * Color(pulse, pulse, pulse))
	# Cables hanging off the truss in loose loops.
	for lx: float in [-330.0, 180.0, 420.0]:
		var prev := _p(lx, low, z)
		for s in range(1, 7):
			var f := s / 6.0
			var nxt := _p(lx + f * 50.0, low - sin(f * PI) * 36.0, z)
			v.line(prev, nxt, DeskView.INK.lightened(0.15), 1.5)
			prev = nxt


static func _stage(v: DeskView, t: float, shadow: int) -> void:
	# The deck, its front face, and the steps down the middle.
	_flat(v, -HALL, HALL, STAGE_Y, STAGE_Z, BACK_Z, DeskView.WALL.darkened(0.42))
	for x in range(-600, 601, 100):
		v.line(_p(x, STAGE_Y, STAGE_Z), _p(x, STAGE_Y, BACK_Z), DeskView.WALL.darkened(0.15), 1.5)
	# Speaker stacks at either side.
	for side: float in [-1.0, 1.0]:
		var sx: float = side * 560.0
		_face(v, sx - 40, sx + 40, STAGE_Y, -80, 1.95, DeskView.INK.lightened(0.1))
		for r in 3:
			var c := _p(sx, STAGE_Y + 22 + r * 36.0, 1.95)
			v.disc(c, 6.0, DeskView.METAL.darkened(0.45))
			v.rect(c.x - 1, c.y - 1, 2, 2, DeskView.METAL.lightened(0.2))
	# The shadow cabinet stands in a line behind the leader, a little apart.
	var count := clampi(shadow if shadow > 0 else 4, 2, 8)
	for i in count:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * (110.0 + floorf(i / 2.0) * 72.0)
		var sway := 1.2 * sin(t * 0.35 + i * 2.1)
		var p := _p(x + sway, STAGE_Y, 1.95)
		var h := MAN * 1.1 / 1.95
		v.figure(p.x - h * 0.12, p.y, DeskView.FIGURE.darkened(0.12), "stand", t, h)
	# The leader at the microphones, gesturing in slow turns: the hero.
	var phase := fposmod(t * 0.12, 1.0)
	var pose := "point" if phase < 0.4 else ("arms_up" if phase < 0.55 else "stand")
	# The pool of light the truss throws on the deck around them.
	_flat(v, -70, 70, STAGE_Y, 1.62, 1.86, DeskView.STONE.darkened(0.1))
	var lp := _p(0, STAGE_Y, 1.72)
	var lh := MAN * 1.18 / 1.72
	v.figure(lp.x - lh * 0.12, lp.y, DeskView.PAPER.lightened(0.45), pose, t, lh)
	# The podium, its emblem plate catching the lamps.
	var pz := 1.63
	_flat(v, -30, 30, -158, pz, pz + 0.06, OAK.lightened(0.1))
	_face(v, -30, 30, STAGE_Y, -158, pz, OAK.darkened(0.35))
	_face(v, -26, 26, STAGE_Y + 4, -150, pz, OAK.darkened(0.15))
	v.disc(_p(0, -164, pz), 9.0 / pz, DeskView.PAPER.darkened(0.1))
	v.disc(_p(0, -164, pz), 5.0 / pz, DeskView.ALARM.darkened(0.2))
	# A bouquet of press microphones on goosenecks.
	for m in 5:
		var mx := -16.0 + m * 8.0
		var base := _p(mx * 0.5, -158, pz)
		var head := _p(mx * 1.3, -150 + (m % 2) * 4.0, pz - 0.04)
		v.line(base, head, DeskView.METAL.darkened(0.1), 1.5)
		v.rect(head.x - 1.5, head.y - 2, 3, 3, [DeskView.METAL.lightened(0.2), DeskView.PAPER, DeskView.STONE.lightened(0.2)][m % 3])
	# The stage front, lit along its lip, and the steps down the middle.
	_face(v, -HALL, HALL, FLOOR_Y, STAGE_Y, STAGE_Z, DeskView.WALL.darkened(0.55))
	v.line(_p(-HALL, STAGE_Y, STAGE_Z), _p(HALL, STAGE_Y, STAGE_Z), DeskView.PAPER.darkened(0.35), 2.0)
	for s in 3:
		var sz := STAGE_Z - 0.04 * (s + 1)
		var sy := STAGE_Y - 8.0 * (s + 1)
		_face(v, -36, 36, FLOOR_Y, sy, sz, DeskView.WALL.darkened(0.3 + s * 0.08))
		v.line(_p(-36, sy, sz), _p(36, sy, sz), DeskView.STONE.darkened(0.15), 1.5)


## The hall floor: dark carpet, its seam lines running to the stage.
static func _floor(v: DeskView) -> void:
	var near := 0.66
	_flat(v, -HALL, HALL, FLOOR_Y, near, STAGE_Z - 0.12, DeskView.WALL.darkened(0.5))
	_flat(v, -40, 40, FLOOR_Y, near, STAGE_Z - 0.12, DeskView.WALL.darkened(0.25))
	for x: float in [-280.0, 280.0]:
		_flat(v, x - 22, x + 22, FLOOR_Y, near, STAGE_Z - 0.04, DeskView.WALL.darkened(0.32))
	for x in range(-560, 561, 140):
		v.line(_p(x, FLOOR_Y, near), _p(x, FLOOR_Y, STAGE_Z), DeskView.WALL.darkened(0.2), 1.5)


## The seats, the reporters in them, the camera crews and their cables, and
## the flashes. Rows fill toward the stage first as interest grows.
static func _press(v: DeskView, t: float, fill: float) -> void:
	var share := 0.25 + 0.72 * fill
	var crews := _crew_spots(fill)
	_cables(v, crews)
	var photographers := 3 + int(fill * 9.0)
	var shooter := 0
	for r in ROWS.size():
		var z: float = ROWS[r]
		# Crews standing in the aisles at this depth draw with the row.
		for c in crews:
			if absf(c.y - z) < 0.06:
				_camera(v, t, c.x, c.y, int(c.x * 7.0 + c.y * 13.0))
		for block in BLOCKS:
			var x: float = block[0]
			var k := 0
			while x + SEAT <= block[1] + 1.0:
				var n := r * 37 + k + int(block[0])
				var taken := _hash(n, r) < share * (1.0 - 0.06 * r)
				_seat(v, t, x, z, taken, n)
				if taken and _hash(n, 9.0) < 0.18 and shooter < photographers:
					_flash(v, t, x + SEAT * 0.5, z, shooter)
					shooter += 1
				x += SEAT
				k += 1


## A seat seen from behind; if taken, a reporter in it, now and then
## shifting or bending to a notebook.
static func _seat(v: DeskView, t: float, x: float, z: float, taken: bool, n: int) -> void:
	var col := _dim(DeskView.FIGURE.darkened(0.22), z)
	var back := DeskView.WALL.darkened(0.2)
	if taken:
		var shift := 1.0 if sin(t * 0.5 + n * 1.9) > 0.96 else 0.0
		var h := MAN * 0.62 / z
		var p := _p(x + SEAT * 0.5, FLOOR_Y, z + 0.02)
		var tone := col.darkened(0.15) if _hash(n, 4.0) < 0.35 else col
		v.figure(p.x - h * 0.12, p.y + shift, tone, "sit", t, h)
	# The chair back covers the lower torso.
	_face(v, x + 5, x + SEAT - 5, FLOOR_Y + 14, FLOOR_Y + 27, z, back)
	v.line(_p(x + 5, FLOOR_Y + 27, z), _p(x + SEAT - 5, FLOOR_Y + 27, z), _dim(DeskView.METAL.darkened(0.2), z), 1.5)
	for lx: float in [x + 8, x + SEAT - 10]:
		_face(v, lx, lx + 2.5, FLOOR_Y, FLOOR_Y + 14, z, back)


## Camera positions in the aisles, more as interest grows: (x, z).
static func _crew_spots(fill: float) -> Array:
	var spots := [Vector2(-280, 1.07), Vector2(280, 1.18), Vector2(-280, 1.44), Vector2(280, 1.44), Vector2(280, 0.88), Vector2(-280, 0.8)]
	return spots.slice(0, 2 + int(round(fill * 4.0)))


## Power and signal cables from each tripod, laid back along the floor
## toward us in slow curves.
static func _cables(v: DeskView, crews: Array) -> void:
	var col := DeskView.METAL.darkened(0.55)
	for c in crews:
		var prev := _p(c.x + 8.0, FLOOR_Y, c.y)
		for s in range(1, 9):
			var f := s / 8.0
			var z := lerpf(c.y, 0.6, f)
			var nxt := _p(c.x + 8.0 + sin(f * 5.0 + c.x) * 22.0 + f * 30.0 * signf(c.x + 1.0), FLOOR_Y, z)
			v.line(prev, nxt, col, 2.0)
			prev = nxt


## A crew at a tripod camera: the operator behind it, a red tally light.
static func _camera(v: DeskView, t: float, x: float, z: float, i: int) -> void:
	var legs := _dim(DeskView.METAL, z)
	var head := _p(x, -112, z)
	for dx: float in [-16.0, 0.0, 16.0]:
		v.line(head, _p(x + dx, FLOOR_Y, z + (0.03 if dx == 0.0 else -0.01)), legs, 1.5)
	var pan := 1.0 * sin(t * 0.25 + i * 1.7)
	var w := 26.0 / z
	var hh := 13.0 / z
	v.rect(head.x - w * 0.5 + pan, head.y - hh, w, hh, _dim(DeskView.METAL.lightened(0.1), z))
	v.rect(head.x + w * 0.5 + pan, head.y - hh * 0.8, w * 0.3, hh * 0.6, _dim(DeskView.METAL.darkened(0.2), z))
	v.rect(head.x - w * 0.5 + pan, head.y - hh - 2, w * 0.4, 2, _dim(DeskView.METAL.darkened(0.3), z))
	v.rect(head.x - w * 0.5 + pan + 2, head.y - hh + 2, 2, 2, DeskView.ALARM)
	var p := _p(x - 22, FLOOR_Y, z + 0.03)
	var h := MAN / (z + 0.03)
	v.figure(p.x - h * 0.2, p.y, _dim(DeskView.FIGURE.darkened(0.15), z), "point", t, h)


## A photographer's camera raised over a seat. Each one fires on its own
## slow rhythm: two or three frames at full white, then eases back.
static func _flash(v: DeskView, t: float, x: float, z: float, i: int) -> void:
	var p := _p(x, FLOOR_Y + MAN * 0.62 + 6.0, z)
	var period := 3.2 + _hash(i, 7.0) * 4.5
	var local := fposmod(t + _hash(i, 3.0) * period, period)
	var body := _dim(DeskView.METAL.darkened(0.25), z)
	v.rect(p.x - 5, p.y - 3, 10, 5, body)
	var k := 0.0
	if local < 0.045:
		k = 1.0
	elif local < 0.6:
		k = 1.0 - smoothstep(0.045, 0.6, local)
	if k > 0.0:
		v.rect(p.x - 4, p.y - 9, 8, 6, DeskView.METAL.lerp(FLASH, k))
