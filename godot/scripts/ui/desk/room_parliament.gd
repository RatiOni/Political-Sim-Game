class_name RoomParliament
extends RefCounted

## The legislation desk's room: the National Assembly seen from the press
## gallery. A high back wall of arched windows over the public gallery, the
## Speaker under a lit canopy with the clerks and the mace before him, and
## benches climbing in a hemicycle toward us, every seat filled by a delegate
## in a muted wash of their party's colour, government on the left. When a
## division is called the members voting aye rise and the board counts.
##
## data: factions (snapshot rows: seats, color, in_coalition), bill (title or
## ""), division (true while a vote is being taken), ayes (0..1 share).

const CENTRE := Vector2(320, 196)   # the rostrum, at the far end of the floor
const ROWS := 5
const INNER := 100.0
const STEP := 41.0
const SQUASH := 0.66                # seen from above: circles read as ellipses
const WIDEN := 1.42                 # wide, so the tiers read as long curved rows
const ARC_FROM := PI * 0.09
const ARC_TO := PI * 0.91
const AISLES := 3                   # stairs dividing the benches into blocks
const AISLE_GAP := 0.06             # radians
const PITCH := 10.5                 # a member's width on the bench, at u = 1
const WINDOWS := [64.0, 146.0, 228.0, 412.0, 494.0]
const BOARD := Rect2(548, 46, 72, 96)

const GLASS := Color(0.07, 0.08, 0.10)
const PANEL := Color(0.10, 0.10, 0.12)
const DARK_WOOD := Color(0.11, 0.10, 0.11)
const BROWN := Color(0.44, 0.34, 0.20)   # wood, kept off the converter's red
const MAHOGANY := Color(0.17, 0.17, 0.19)   # darker wood: darkened ochre snaps to olive, rust to alarm-red
const TIER := Color(0.06, 0.055, 0.05)       # the tier floors, kept dark behind the members
const DESK_FACE := Color(0.14, 0.12, 0.11)
const DESK_TOP := Color(0.70, 0.62, 0.48)
const SUIT := Color(0.30, 0.29, 0.28)
const SKIN_LIT := Color(0.86, 0.72, 0.56)
const COLUMN := Color(0.43, 0.41, 0.37)    # pale stone-grey, clear of the olive the converter makes of brown


## What the room shows, read from the app snapshot.
static func data_from(snapshot: Dictionary) -> Dictionary:
	var model: Dictionary = snapshot.get("legislation", {})
	var pending: Variant = model.get("pending")
	var ayes := 0.5
	var preview: Variant = model.get("pending_preview")
	if preview is Dictionary and float(preview.get("seats_total", 0)) > 0.0:
		ayes = float(preview.get("votes_for", 0)) / float(preview.get("seats_total", 1))
	return {
		"factions": snapshot.get("factions", []),
		"bill": str(pending.get("name", "")) if pending is Dictionary else "",
		"division": pending is Dictionary,
		"ayes": ayes,
	}


static func paint(v: DeskView, t: float, d: Dictionary) -> void:
	var division := bool(d.get("division", false))
	var ayes := float(d.get("ayes", 0.0))
	_wall(v, t)
	_gallery(v, t)
	_chandeliers(v, t)
	_board(v, t, division, ayes)
	_floor(v)
	_rostrum(v, t)
	_benches(v, t, _seat_colours(d.get("factions", [])), division, ayes)
	_well(v, t)
	_press_rail(v, t)
	v.label(Vector2(368, 128), "THE ROSTRUM", Vector2(346, 150))
	v.label(Vector2(16, 410), "PRESS GALLERY · FIXED")
	v.label(Vector2(16, 140), "PUBLIC GALLERY", Vector2(40, 152))
	if String(d.get("bill", "")) != "":
		v.label(Vector2(470, 38), "ORDER OF THE DAY", Vector2(548, 50))


# --- the back wall ------------------------------------------------------

static func _wall(v: DeskView, t: float) -> void:
	v.rect(v.left, 0, v.right - v.left, 200, DeskView.WALL.darkened(0.5))
	# Coffered ceiling and a dentilled cornice.
	v.rect(v.left, 0, v.right - v.left, 22, DeskView.WALL.darkened(0.7))
	for x in range(int(v.left) - 8, int(v.right) + 8, 40):
		v.line(Vector2(x, 0), Vector2(x, 14), DeskView.STONE.darkened(0.45), 1.5)
	v.line(Vector2(v.left, 14), Vector2(v.right, 14), DeskView.STONE.darkened(0.25), 2.0)
	for x in range(int(v.left), int(v.right), 7):
		v.rect(x, 16, 3.5, 3, DeskView.STONE.darkened(0.3))
	v.line(Vector2(v.left, 21), Vector2(v.right, 21), DeskView.STONE, 2.0)
	# Pilasters between the windows, with capitals and bases.
	for x in [v.left + 2.0, 22.0, 105.0, 187.0, 269.0, 371.0, 453.0, 535.0, v.right - 8.0]:
		v.rect(x, 22, 8, 124, DeskView.STONE.darkened(0.35))
		v.line(Vector2(x + 2, 30), Vector2(x + 2, 140), DeskView.STONE.darkened(0.15), 1.5)
		v.rect(x - 2, 22, 12, 4, DeskView.STONE.darkened(0.1))
		v.rect(x - 2, 142, 12, 4, DeskView.STONE.darkened(0.1))
	for cx in WINDOWS:
		_window(v, cx, t)
	# The string course the gallery hangs from.
	v.line(Vector2(v.left, 146), Vector2(v.right, 146), DeskView.STONE.darkened(0.1), 2.0)


static func _window(v: DeskView, cx: float, t: float) -> void:
	var w := 21.0
	var top := 52.0
	var bottom := 134.0
	var arch := PackedVector2Array()
	for k in 13:
		var a := PI + PI * k / 12.0
		arch.append(Vector2(cx + cos(a) * w, top + sin(a) * w))
	arch.append(Vector2(cx + w, bottom))
	arch.append(Vector2(cx - w, bottom))
	v.poly(arch, GLASS)
	# Night beyond: a few far lights in the panes, steady.
	for k in 5:
		var px := cx - 16 + fmod(cx * 0.37 + k * 7.3, 32.0)
		var py := 60.0 + fmod(cx * 0.71 + k * 13.1, 66.0)
		v.rect(px, py, 1.5, 1.5, DeskView.METAL.darkened(0.4))
	# Frame, mullions, transoms and the radiating arch bars.
	var frame := DeskView.STONE.darkened(0.05)
	for k in 12:
		var a0 := PI + PI * k / 12.0
		var a1 := PI + PI * (k + 1) / 12.0
		v.line(Vector2(cx + cos(a0) * w, top + sin(a0) * w), Vector2(cx + cos(a1) * w, top + sin(a1) * w), frame, 2.0)
	for a in [PI * 1.25, PI * 1.5, PI * 1.75]:
		v.line(Vector2(cx, top), Vector2(cx + cos(a) * w, top + sin(a) * w), frame, 1.5)
	v.line(Vector2(cx - w, top), Vector2(cx - w, bottom), frame, 2.0)
	v.line(Vector2(cx + w, top), Vector2(cx + w, bottom), frame, 2.0)
	v.line(Vector2(cx, top), Vector2(cx, bottom), frame, 1.5)
	for y in [top, 80.0, 107.0]:
		v.line(Vector2(cx - w, y), Vector2(cx + w, y), frame, 1.5)
	v.rect(cx - w - 3, bottom, w * 2 + 6, 4, DeskView.STONE)        # sill
	v.rect(cx - 3, top - w - 5, 6, 5, DeskView.STONE)                # keystone


static func _gallery(v: DeskView, t: float) -> void:
	# The public gallery: two rows of spectators behind a balustrade.
	v.rect(v.left, 146, v.right - v.left, 54, PANEL)
	var first := int(floorf(v.left / 11.0))
	for row in 2:
		var foot := 160.0 + row * 7.0
		var tone := DeskView.FIGURE.darkened(0.62 - row * 0.1)
		for i in range(first, first + int((v.right - v.left) / 11.0) + 1):
			var x := 3.0 + i * 11.0 + row * 5.5 + sin(i * 12.9 + row) * 1.5
			if absf(x - 320.0) < 40.0 or fmod(absf(i * 7.0 + row * 3.0), 9.0) < 1.0:
				continue
			var bob := 1.0 if sin(t * 0.45 + i * 1.3 + row * 2.0) > 0.93 else 0.0
			v.figure(x, foot - bob, tone, "sit", t, 12.0 - row)
	# Balustrade: rails and turned balusters.
	v.rect(v.left, 168, v.right - v.left, 3, DeskView.STONE.darkened(0.05))
	v.rect(v.left, 183, v.right - v.left, 2.5, DeskView.STONE.darkened(0.2))
	for x in range(int(v.left), int(v.right), 8):
		v.rect(x, 171, 2, 12, DeskView.STONE.darkened(0.35))
	# Wainscot below the gallery, down to the floor.
	v.rect(v.left, 185, v.right - v.left, 15, DARK_WOOD)
	for x in range(int(v.left), int(v.right), 24):
		v.line(Vector2(x, 187), Vector2(x, 199), MAHOGANY, 1.5)


static func _chandeliers(v: DeskView, t: float) -> void:
	for i in 4:
		var x: float = [104.0, 236.0, 404.0, 536.0][i]
		var drop: float = [62.0, 50.0, 50.0, 62.0][i]
		v.line(Vector2(x, 22), Vector2(x, drop - 10), DeskView.METAL.darkened(0.35), 1.5)
		var breathe := 0.87 + 0.13 * sin(t * 0.6 + i * 1.9)
		var lamp := DeskView.LAMP * Color(breathe, breathe, breathe)
		# Two tiers of arms, a lit candle-bulb at each tip.
		for tier in 2:
			var y := drop - 6 + tier * 9.0
			var span := 18.0 - tier * 7.0
			v.line(Vector2(x - span, y + 2), Vector2(x + span, y + 2), DeskView.METAL.darkened(0.15), 1.5)
			for k in 5 - tier * 2:
				var px := x - span + k * span * 2.0 / maxf(1.0, 4 - tier * 2)
				v.rect(px - 1, y - 1, 2, 2, lamp)
		v.rect(x - 2, drop + 8, 4, 5, DeskView.METAL.darkened(0.2))


static func _board(v: DeskView, t: float, division: bool, ayes: float) -> void:
	# The division board on the right wall: ayes fill as the vote is counted.
	var b := BOARD
	v.rect(b.position.x - 3, b.position.y - 3, b.size.x + 6, b.size.y + 6, DeskView.STONE.darkened(0.2))
	v.rect(b.position.x, b.position.y, b.size.x, b.size.y, DeskView.INK)
	v.line(Vector2(b.position.x + 2, b.position.y + 12), Vector2(b.end.x - 2, b.position.y + 12), DeskView.METAL.darkened(0.2), 1.5)
	v.line(Vector2(b.position.x + b.size.x * 0.5, b.position.y + 14), Vector2(b.position.x + b.size.x * 0.5, b.end.y - 4), DeskView.METAL.darkened(0.3), 1.5)
	# Header cells: "DIVISION" lamp strip.
	for k in 8:
		var on := division and int(t * 1.0) % 2 == 0
		v.rect(b.position.x + 6 + k * 8, b.position.y + 4, 5, 4, DeskView.LAMP.darkened(0.1) if on else DeskView.WALL)
	var lit_ayes := int(round(ayes * 30.0)) if division else 0
	var lit_noes := (30 - lit_ayes) if division else 0
	for side in 2:
		var lit := lit_ayes if side == 0 else lit_noes
		for i in 30:
			var cx := b.position.x + 5 + side * 36 + (i % 5) * 6
			var cy := b.end.y - 9 - floorf(i / 5.0) * 12
			v.rect(cx, cy, 4, 8, DeskView.LAMP if i < lit else DeskView.WALL.darkened(0.2))
	# The division bell lamp, only while a vote is called.
	if division and fmod(t, 1.0) < 0.5:
		v.rect(b.position.x + b.size.x * 0.5 - 4, b.position.y - 10, 8, 5, DeskView.ALARM)


# --- the floor ------------------------------------------------------------

static func _floor(v: DeskView) -> void:
	# The chamber floor outside the benches: dark, so the tiers read on it.
	v.rect(v.left, 200, v.right - v.left, 220, DeskView.INK)
	v.line(Vector2(v.left, 200), Vector2(v.right, 200), BROWN.lightened(0.1), 2.0)


static func _rostrum(v: DeskView, t: float) -> void:
	# The Speaker's canopy, the hero of the room: a dark oak frame around a
	# lit panel, so the Speaker reads as a clean silhouette against it.
	var oak := Color(0.12, 0.10, 0.09)
	v.rect(280, 82, 80, 118, oak)
	v.poly(PackedVector2Array([Vector2(272, 88), Vector2(320, 58), Vector2(368, 88)]), oak)
	v.poly(PackedVector2Array([Vector2(282, 86), Vector2(320, 63), Vector2(358, 86)]), COLUMN.darkened(0.2))
	v.line(Vector2(272, 88), Vector2(368, 88), DeskView.PAPER.darkened(0.15), 2.0)
	v.line(Vector2(274, 94), Vector2(366, 94), COLUMN, 1.5)
	# The crest: a gilt shield in the pediment.
	v.rect(314, 69, 12, 12, DeskView.LAMP.darkened(0.25))
	v.rect(316, 71, 8, 6, DeskView.ALARM.darkened(0.35))
	v.rect(319, 81, 2, 3, DeskView.LAMP.darkened(0.25))
	# Fluted columns either side of the panel.
	for x: float in [282.0, 350.0]:
		v.rect(x, 96, 8, 74, COLUMN)
		v.line(Vector2(x + 2.5, 98), Vector2(x + 2.5, 168), COLUMN.lightened(0.25), 1.0)
		v.line(Vector2(x + 5.5, 98), Vector2(x + 5.5, 168), oak, 1.0)
		v.rect(x - 1, 95, 10, 3, DeskView.PAPER.darkened(0.3))
	var lit := 0.94 + 0.06 * sin(t * 0.5)
	v.rect(292, 98, 56, 70, DeskView.PAPER.darkened(0.28) * Color(lit, lit, lit))
	for x: float in [301.0, 339.0]:
		v.line(Vector2(x, 102), Vector2(x, 164), DeskView.PAPER.darkened(0.45), 1.0)
	# The Speaker's tall chair, and the Speaker in a black gown, wigged.
	var leather := Color(0.36, 0.13, 0.10)
	v.rect(307, 112, 26, 54, leather)
	v.rect(309, 108, 22, 5, leather.lightened(0.1))
	v.rect(308, 112, 24, 1.5, DeskView.LAMP.darkened(0.3))
	var nod := 1.0 if sin(t * 0.7) > 0.8 else 0.0
	var speaking := sin(t * 0.8) > 0.35
	v.figure(316, 168 + nod, Color(0.09, 0.09, 0.10), "point" if speaking else "sit", t, 34.0, DeskView.SKIN)
	v.rect(315, 134 + nod, 10, 3, DeskView.PAPER.lightened(0.1))      # wig and bands
	v.rect(318.5, 148 + nod, 3, 4, DeskView.PAPER.lightened(0.1))
	# Two brass sconces on the columns.
	for x: float in [280.0, 358.0]:
		var p := 0.88 + 0.12 * sin(t * 0.6 + x)
		v.rect(x, 108, 3, 4, DeskView.LAMP * Color(p, p, p))
	# The dais and its panelled front.
	v.rect(266, 166, 108, 20, COLUMN.darkened(0.35))
	v.rect(266, 166, 108, 2.5, DeskView.PAPER.darkened(0.2))
	for x in range(272, 368, 16):
		v.rect(x, 171, 12, 11, oak)
		v.rect(x + 1, 172, 10, 1, COLUMN)


static func _well(v: DeskView, t: float) -> void:
	# The well of the house: a green carpet before the dais, the clerks at
	# their table, the Table of the House with the mace, an usher pacing.
	var carpet := Color(0.11, 0.13, 0.10)
	v.poly(PackedVector2Array([Vector2(262, 186), Vector2(378, 186), Vector2(408, 252), Vector2(232, 252)]), carpet)
	v.poly(PackedVector2Array([Vector2(270, 190), Vector2(370, 190), Vector2(396, 248), Vector2(244, 248)]), carpet.darkened(0.3))
	# The clerks, wigged, behind their table.
	for i in 3:
		var x := 291.0 + i * 24.0
		var bob := 1.0 if sin(t * 0.5 + i * 2.2) > 0.9 else 0.0
		v.figure(x, 206 + bob, Color(0.10, 0.10, 0.11), "sit", t, 19.0, DeskView.SKIN)
		v.rect(x, 187 + bob, 4, 1.5, DeskView.PAPER)
	v.rect(278, 199, 84, 4, COLUMN)
	v.rect(278, 199, 84, 1.5, DeskView.PAPER.darkened(0.15))
	v.rect(282, 203, 76, 6, Color(0.12, 0.10, 0.09))
	# Papers on the clerks' table, one turned now and then.
	v.rect(286, 197, 8, 2, DeskView.PAPER)
	v.rect(346, 197, 8, 2, DeskView.PAPER)
	var turn := fmod(t * 0.25, 1.0)
	if turn < 0.15:
		v.line(Vector2(312, 198), Vector2(312 + 6 * cos(turn * PI / 0.15), 194), DeskView.PAPER, 1.5)
	else:
		v.rect(308, 197, 8, 2, DeskView.PAPER.darkened(0.1))
	# The Table of the House: dispatch boxes and the gilt mace.
	v.rect(288, 222, 64, 9, COLUMN.darkened(0.3))
	v.rect(288, 222, 64, 2, DESK_TOP)
	v.rect(292, 231, 3, 8, Color(0.12, 0.10, 0.09))
	v.rect(345, 231, 3, 8, Color(0.12, 0.10, 0.09))
	v.rect(296, 218, 9, 5, DeskView.PAPER.darkened(0.25))
	v.rect(335, 218, 9, 5, DeskView.PAPER.darkened(0.25))
	v.line(Vector2(306, 221), Vector2(334, 219), DeskView.LAMP, 2.5)
	v.rect(331, 216, 5, 5, DeskView.LAMP)
	var pace := 0.5 - 0.5 * cos(t * 0.18)
	v.figure(248 + pace * 136.0, 252, Color(0.12, 0.12, 0.13), "walk", t * 0.6, 22.0, DeskView.SKIN)


# --- the benches ----------------------------------------------------------

static func _seat_colours(factions: Array) -> Array:
	var sorted := factions.duplicate()
	sorted.sort_custom(func(a, b):
		var ca := bool(a.get("in_coalition", false))
		var cb := bool(b.get("in_coalition", false))
		if ca != cb:
			return ca
		return int(a.get("seats", 0)) > int(b.get("seats", 0)))
	var hexes: Array = []
	for f in sorted:
		hexes.append(String(f.get("color", "")))
	var colours := UiPalette.party_colors(hexes)
	var out: Array = []
	for i in sorted.size():
		# Party coats, a little muted so the chamber reads by bloc.
		var c: Color = colours[i].lerp(SUIT, 0.3)
		for s in int(sorted[i].get("seats", 0)):
			out.append(c)
	if out.is_empty():
		for s in 100:
			out.append(DeskView.FIGURE)
	return out


static func _on_arc(a: float, radius: float) -> Vector2:
	return CENTRE + Vector2(cos(a) * radius * WIDEN, sin(a) * radius * SQUASH)


## Screen distance per radian along the arc at angle `a`.
static func _speed(a: float, radius: float) -> float:
	return radius * Vector2(sin(a) * WIDEN, cos(a) * SQUASH).length()


## The aisle whose gap holds angle `a`, or -1.
static func _aisle_at(a: float) -> int:
	for i in AISLES:
		if absf(a - _aisle_angle(i)) < AISLE_GAP * 0.5:
			return i
	return -1


static func _aisle_angle(i: int) -> float:
	return ARC_FROM + (ARC_TO - ARC_FROM) * (i + 1) / float(AISLES + 1)


## A band of constant screen height `h` hanging under the arc at `radius`.
static func _strip(v: DeskView, radius: float, a0: float, a1: float, h: float, c: Color) -> void:
	var pts := PackedVector2Array()
	var n := 24
	for k in n + 1:
		pts.append(_on_arc(lerpf(a0, a1, k / float(n)), radius))
	for k in n + 1:
		pts.append(_on_arc(lerpf(a1, a0, k / float(n)), radius) + Vector2(0, h))
	v.poly(pts, c)


static func _arc_line(v: DeskView, radius: float, a0: float, a1: float, c: Color, width: float, dy: float = 0.0) -> void:
	var prev := Vector2.ZERO
	for k in 25:
		var p := _on_arc(lerpf(a0, a1, k / 24.0), radius) + Vector2(0, dy)
		if k > 0:
			v.line(prev, p, c, width)
		prev = p


## The hemicycle as continuous tiers climbing toward us. Each tier is a row
## of members, shoulder to shoulder, behind one long curved desk; tiers are
## drawn far to near so each desk covers its own members' laps. Seats are
## coloured by party wedge, government on the left; aisles of steps cut the
## tiers into blocks.
static func _benches(v: DeskView, t: float, seats: Array, division: bool, ayes: float) -> void:
	var standing := ayes if division else 0.0
	for r in ROWS:
		var radius := INNER + r * STEP
		var near := r / float(ROWS - 1)
		var u := 1.2 + near * 0.55
		var desk_h := 5.0 + near * 3.0
		# The tier floor, dark, so heads and shoulders stand out on it.
		_strip(v, radius - STEP * 0.75, ARC_FROM - 0.02, ARC_TO + 0.02, STEP * 0.75 * SQUASH + 3.0, TIER)
		# Members along the arc, stepping by screen distance.
		var a := ARC_FROM + 0.004
		var k := 0
		while a < ARC_TO:
			var aisle := _aisle_at(a)
			if aisle >= 0:
				a = _aisle_angle(aisle) + AISLE_GAP * 0.5 + 0.002
				continue
			var frac := (ARC_TO - a) / (ARC_TO - ARC_FROM)
			var index := clampi(int(frac * seats.size()), 0, seats.size() - 1)
			var shift := 1.0 if sin(t * 0.6 + r * 3.1 + k * 1.7) > 0.97 else 0.0
			_member(v, _on_arc(a, radius), u, seats[index], frac < standing, shift, r * 131 + k)
			a += (PITCH * u) / _speed(a, radius)
			k += 1
		# The long desk of each block: a lit top edge over a panelled face.
		for block in AISLES + 1:
			var a0 := ARC_FROM if block == 0 else _aisle_angle(block - 1) + AISLE_GAP * 0.5
			var a1 := ARC_TO if block == AISLES else _aisle_angle(block) - AISLE_GAP * 0.5
			_strip(v, radius, a0, a1, desk_h, DESK_FACE)
			_strip(v, radius, a0, a1, 2.2 + near, DESK_TOP.darkened(0.2 * (1.0 - near)))
			_arc_line(v, radius, a0, a1, DeskView.INK, 1.0, desk_h)
			# Panel joints, papers and reading lamps along the desk.
			var steps := int((a1 - a0) * radius / 20.0)
			for s in range(1, steps):
				var q := _on_arc(lerpf(a0, a1, s / float(steps)), radius)
				v.line(q + Vector2(0, 3), q + Vector2(0, desk_h - 1), DESK_FACE.lightened(0.15), 1.0)
				match (s + r) % 4:
					0:
						v.rect(q.x - 2, q.y - 1.5, 4 + near * 2, 1.5, DeskView.PAPER)
					2:
						var glow := 0.85 + 0.15 * sin(t * 0.7 + s + r)
						v.rect(q.x, q.y - 3, 1.5 + near, 2 + near, DeskView.LAMP * Color(glow, glow, glow))
	# The aisle stairs, cut through every tier.
	for i in AISLES:
		var a := _aisle_angle(i)
		var w := AISLE_GAP * 0.42
		var outer := INNER + (ROWS - 1) * STEP + 12
		v.poly(PackedVector2Array([_on_arc(a - w, INNER - 14), _on_arc(a + w, INNER - 14),
				_on_arc(a + w, outer), _on_arc(a - w, outer)]), Color(0.10, 0.09, 0.09))
		for s in ROWS * 2 + 1:
			var rad := INNER - 12 + s * STEP * 0.5
			v.line(_on_arc(a - w, rad), _on_arc(a + w, rad), DeskView.STONE.darkened(0.15 if s % 2 == 0 else 0.45), 1.0)


## One member: a face over a shoulder line in party colour, a head taller
## when standing for the ayes in a division.
static func _member(v: DeskView, p: Vector2, u: float, coat: Color, rise: bool, shift: float, n: int) -> void:
	var up := (5.0 * u if rise else 0.0) + shift
	var x := p.x - 2.0 * u
	var y := p.y - 11.0 * u - up
	v.rect(x, y, 4 * u, 4 * u, SKIN_LIT)
	if n % 7 != 0:                                   # one in seven bald
		v.rect(x, y, 4 * u, 1.4 * u, DeskView.HAIR[n % 3])
	v.rect(x - 1.5 * u, y + 5 * u, 7 * u, 6 * u + up, coat)
	v.rect(x + 1.2 * u, y + 5 * u, 1.6 * u, 1.6 * u, DeskView.PAPER.darkened(0.1))   # shirt front


# --- our side of the chamber ---------------------------------------------

static func _press_rail(v: DeskView, t: float) -> void:
	# Our vantage: the press gallery's parapet across the foot of the frame,
	# reporters at desks in the corners nearest us.
	v.rect(v.left, 392, v.right - v.left, 28, Color(0.10, 0.09, 0.09))
	v.rect(v.left, 392, v.right - v.left, 3, DeskView.STONE.lightened(0.05))
	v.rect(v.left, 395, v.right - v.left, 1.5, DeskView.INK)
	for x in range(int(v.left) - 4, int(v.right) + 8, 9):
		v.rect(x, 398, 4, 13, DeskView.STONE.darkened(0.35))
	v.rect(v.left, 411, v.right - v.left, 2.5, DeskView.STONE.darkened(0.1))
	v.rect(v.left, 413, v.right - v.left, 7, DeskView.INK)
	for side in 2:
		var s := -1.0 if side == 0 else 1.0
		var base := 320.0 + s * 268.0
		var lean := 1.0 if sin(t * 0.3 + side * 2.0) > 0.5 else 0.0
		v.figure(base - s * 4.0 - 3.0, 394 + lean, Color(0.22, 0.24, 0.30) if side == 0 else Color(0.30, 0.26, 0.22), "sit", t, 40.0, DeskView.SKIN)
		v.rect(base - 46, 376, 92, 16, DESK_FACE)
		v.rect(base - 46, 376, 92, 2.5, DESK_TOP)
		var x := base - s * 26.0
		var typing := 1.0 if sin(t * 2.0 + side) > 0.0 else 0.0
		v.rect(x - 8, 368 - typing, 16, 8 + typing, DeskView.METAL.darkened(0.15))
		v.rect(x - 6, 362, 12, 6, DeskView.PAPER)
		var flick := 0.85 + 0.15 * sin(t * 0.5 + side)
		var lx := base + s * 30.0
		v.rect(lx - 3, 360, 8, 3, Color(0.22, 0.40, 0.27))
		v.rect(lx, 363, 2, 13, DeskView.METAL.darkened(0.3))
		v.rect(lx - 1, 363, 4, 2, DeskView.LAMP * Color(flick, flick, flick))
