class_name RoomRecords
extends RefCounted

## The records desk's room: the state archive. A wall of tall stacks faces the
## reading room, broken by one aisle that recedes into the dark; the more
## history the campaign has made, the more of their shelves carry boxes. An
## archivist turns pages under the reading lamp, a clerk works the card index,
## and a trolley of files is wheeled slowly along the floor.
##
## data: fill (0..1, how much of the archive holds records — grows with the
## months, budgets and elections in the snapshot's history).

const FLOOR := 160.0
const SHADE := Color(0.22, 0.36, 0.26)
const AISLE := Rect2(40, 18, 180, 142)   # the opening into the receding aisle
const VP := Vector2(130, 92)             # where the aisle vanishes
## History that fills the whole archive (records, weighted).
const FULL := 260.0


## What the room shows, read from the app snapshot.
static func data_from(snapshot: Dictionary) -> Dictionary:
	var history: Dictionary = snapshot.get("history", {})
	var records: float = float(history.get("economy", []).size()) \
		+ 12.0 * history.get("budgets", []).size() \
		+ 24.0 * history.get("elections", []).size()
	return {"fill": clampf(records / FULL, 0.0, 1.0)}


static func paint(v: DeskView, t: float, d: Dictionary) -> void:
	var fill := clampf(float(d.get("fill", 0.0)), 0.0, 1.0)
	v.rect(v.left, 0, v.right - v.left, 240, DeskView.WALL.darkened(0.55))
	_stack_wall(v, t, fill)
	_aisle(v, fill)
	v.rect(v.left, FLOOR, v.right - v.left, 240 - FLOOR, DeskView.WALL.darkened(0.72))
	v.line(Vector2(v.left, FLOOR), Vector2(v.right, FLOOR), DeskView.STONE.darkened(0.25))
	_card_index(v, t)
	_reading_desk(v, t)
	_trolley(v, t)
	v.label(Vector2(44, 12), "THE STACKS", Vector2(110, 60))
	v.label(Vector2(470, 118), "CARD INDEX", Vector2(500, 132))
	v.label(Vector2(300, 236), "READING ROOM", Vector2(350, 196))


## The face of the stacks, shelf units repeated across the whole wall. A shelf
## carries boxes if its place in the archive's order falls under `fill`.
static func _stack_wall(v: DeskView, t: float, fill: float) -> void:
	var first := int(floorf((v.left - 40.0) / 40.0))
	for i in range(first, first + int((v.right - v.left) / 40.0) + 2):
		var x := i * 40.0
		if x + 40.0 > AISLE.position.x and x < AISLE.end.x:
			continue
		v.rect(x, 14, 2, FLOOR - 14, DeskView.STONE.darkened(0.5))
		for s in 7:
			var base := 34.0 + s * 18.0
			v.rect(x, base, 40, 2, DeskView.STONE.darkened(0.55))
			if _order(i * 7 + s) < fill:
				_boxes(v, x + 3, base, 34.0, 12.0, i * 7 + s, 0.45)
	# Hanging lamps along the stacks: single warm cells, breathing.
	var lamp_first := int(floorf(v.left / 160.0))
	for i in range(lamp_first, lamp_first + int((v.right - v.left) / 160.0) + 2):
		var x := 20.0 + i * 160.0
		if x > AISLE.position.x and x < AISLE.end.x:
			continue
		var pulse := 0.85 + 0.15 * sin(t * 0.6 + i * 2.0)
		v.line(Vector2(x, 0), Vector2(x, 8), DeskView.METAL.darkened(0.45))
		v.rect(x - 2, 8, 4, 3, DeskView.LAMP * Color(pulse, pulse, pulse))
	v.line(Vector2(v.left, 14), Vector2(v.right, 14), DeskView.STONE.darkened(0.2), 2.0)


## Boxes along one shelf, `w` wide and up to `h` tall, in dim archive tones.
static func _boxes(v: DeskView, x: float, base: float, w: float, h: float, n: int, dim: float = 0.0) -> void:
	var tones := [DeskView.STONE.darkened(0.25 + dim), DeskView.WOOD.darkened(0.1 + dim), DeskView.PAPER.darkened(0.55 + dim * 0.6)]
	var cx := x
	var k := 0
	while cx < x + w - 3:
		var bw := 4.0 + fposmod(sin((n * 17 + k) * 3.7) * 9.0, 3.0)
		var bh := h - fposmod(sin((n * 13 + k) * 5.3) * 7.0, 3.0)
		v.rect(cx, base - bh, minf(bw, x + w - cx), bh, tones[(n + k) % tones.size()])
		cx += bw + 1.0
		k += 1


## One aisle receding between two runs of shelving to a lit back wall. Every
## height on the near face runs straight toward the vanishing point.
static func _aisle(v: DeskView, fill: float) -> void:
	var a := AISLE
	var reach := 0.8                          # how far down the aisle we see
	v.rect(a.position.x, a.position.y, a.size.x, a.size.y, DeskView.INK)
	var far_l := lerpf(a.position.x, VP.x, reach)
	var far_r := lerpf(a.end.x, VP.x, reach)
	var far_top := lerpf(a.position.y, VP.y, reach)
	var far_bot := lerpf(a.end.y, VP.y, reach)
	v.rect(far_l, far_top, far_r - far_l, far_bot - far_top, DeskView.WALL.darkened(0.2))
	v.rect(VP.x - 2, far_top + 4, 4, 3, DeskView.LAMP.darkened(0.15))
	v.poly(PackedVector2Array([Vector2(a.position.x, a.end.y), Vector2(a.end.x, a.end.y), Vector2(far_r, far_bot), Vector2(far_l, far_bot)]),
		DeskView.WALL.darkened(0.45))
	for side in [-1, 1]:
		var nx: float = a.position.x if side < 0 else a.end.x
		for k in 8:
			var f := reach * (1.0 - pow(0.7, k)) / (1.0 - pow(0.7, 8))
			var f2 := reach * (1.0 - pow(0.7, k + 1)) / (1.0 - pow(0.7, 8))
			var p := lerpf(nx, VP.x, f)
			var p2 := lerpf(nx, VP.x, f2)
			v.line(Vector2(p, lerpf(a.position.y, VP.y, f)), Vector2(p, lerpf(a.end.y, VP.y, f)), DeskView.METAL.darkened(0.5))
			for s in 7:
				var level := 34.0 + s * 18.0
				var y := lerpf(level, VP.y, f)
				var y2 := lerpf(level, VP.y, f2)
				v.line(Vector2(p, y + 1), Vector2(p2, y2 + 1), DeskView.METAL.darkened(0.55))
				if _order(1000 + side * 100 + k * 7 + s) >= fill:
					continue
				var hh := 11.0 * (1.0 - f)
				v.poly(PackedVector2Array([Vector2(p, y - hh), Vector2(p2, y2 - 11.0 * (1.0 - f2)), Vector2(p2, y2), Vector2(p, y)]),
					DeskView.STONE.darkened(0.45 + 0.05 * k))


## A stable pseudo-random rank 0..1 for a shelf, so filling is scattered but
## never flickers between frames.
static func _order(n: int) -> float:
	return fposmod(sin(n * 12.9898) * 43758.5453, 1.0)


static func _reading_desk(v: DeskView, t: float) -> void:
	var top := 186.0
	var shift := 1.0 if sin(t * 0.4) > 0.9 else 0.0
	v.figure(312, top + 3 - shift, DeskView.FIGURE, "sit", t, 24.0)
	v.rect(290, top, 140, 3, DeskView.WOOD.darkened(0.25))
	v.rect(290, top + 3, 140, 8, DeskView.WOOD.darkened(0.6))
	v.rect(294, top + 11, 3, 24, DeskView.WOOD.darkened(0.5))
	v.rect(423, top + 11, 3, 24, DeskView.WOOD.darkened(0.5))
	# The open volume; every few seconds a page lifts and turns, eased.
	var spine := Vector2(350, top)
	v.rect(331, top - 4, 18, 4, DeskView.PAPER)
	v.rect(351, top - 4, 18, 4, DeskView.PAPER)
	var cycle := fposmod(t, 9.0)
	if cycle < 2.0:
		var a := PI * smoothstep(0.0, 2.0, cycle)
		var tip := spine + Vector2(cos(a) * 18.0, -sin(a) * 14.0)
		v.poly(PackedVector2Array([spine, spine + Vector2(0, -2), tip + Vector2(0, -2), tip]), DeskView.PAPER.lightened(0.1))
	# The reading lamp: the room's one bright thing.
	var pulse := 0.88 + 0.12 * sin(t * 0.7)
	v.line(Vector2(398, top), Vector2(398, top - 14), DeskView.METAL.darkened(0.2))
	v.poly(PackedVector2Array([Vector2(388, top - 14), Vector2(408, top - 14), Vector2(403, top - 22), Vector2(393, top - 22)]), SHADE)
	v.rect(391, top - 13, 14, 4, DeskView.LAMP * Color(pulse, pulse, pulse))
	v.rect(372, top - 1, 46, 1, DeskView.PAPER.darkened(0.2))
	# Stacked volumes waiting their turn.
	for k in 3:
		v.rect(414, top - 4 - k * 4, 12, 3, [DeskView.WOOD.darkened(0.3), DeskView.STONE.darkened(0.3), DeskView.WOOD.darkened(0.15)][k])


## The steel card-index cabinet: a grid of small drawers with paper labels; a clerk
## draws one out, reads, and slides it home again.
static func _card_index(v: DeskView, t: float) -> void:
	var x0 := 460.0
	var y0 := 128.0
	var cols := 5
	var rows := 5
	v.rect(x0 - 4, y0 - 4, cols * 24 + 8, rows * 14 + 8 + 28, DeskView.WALL.darkened(0.2))
	var open := smoothstep(0.0, 1.0, clampf(sin(t * 0.25) * 1.6, 0.0, 1.0))
	for r in rows:
		for c in cols:
			var x := x0 + c * 24.0
			var y := y0 + r * 14.0
			var out := open if (r == 2 and c == 1) else 0.0
			if out > 0.0:
				# Pulled toward us: the cards show above its front.
				v.rect(x + 2, y - 1, 18, 3 + out * 3, DeskView.PAPER.darkened(0.2))
				y += out * 4.0
			v.rect(x + 1, y + 1, 21, 12, DeskView.METAL.darkened(0.62))
			v.rect(x + 8, y + 4, 7, 3, DeskView.PAPER.darkened(0.3))
	var reading := open > 0.5
	v.figure(436, 208, DeskView.FIGURE.darkened(0.15), "point" if reading else "stand", t, 20.0)


## A trolley of files wheeled slowly to and fro along the front of the room.
static func _trolley(v: DeskView, t: float) -> void:
	var g := _glide(t, 20.0, 230.0, 110.0)
	var x := g.x
	v.figure(x - 14, 228, DeskView.FIGURE.darkened(0.1), "walk" if g.y > 0.0 else "stand", t, 18.0)
	v.line(Vector2(x - 6, 216), Vector2(x, 216), DeskView.METAL.darkened(0.2))
	v.rect(x, 214, 34, 3, DeskView.METAL.darkened(0.25))
	v.rect(x, 222, 34, 2, DeskView.METAL.darkened(0.4))
	v.line(Vector2(x + 2, 214), Vector2(x + 2, 226), DeskView.METAL.darkened(0.3))
	v.line(Vector2(x + 32, 214), Vector2(x + 32, 226), DeskView.METAL.darkened(0.3))
	_boxes(v, x + 2, 214, 30.0, 9.0, 7)
	for wx in [x + 4, x + 30]:
		v.disc(Vector2(wx, 228), 2.5, DeskView.METAL.darkened(0.1))


static func _glide(t: float, a: float, b: float, period: float) -> Vector2:
	var tri := absf(fposmod(t / period, 1.0) * 2.0 - 1.0)
	var s := smoothstep(0.15, 0.85, tri)
	return Vector2(lerpf(a, b, s), 1.0 if s > 0.0 and s < 1.0 else 0.0)
