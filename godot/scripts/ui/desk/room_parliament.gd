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

const CENTRE := Vector2(320, 198)   # the rostrum, at the far end of the floor
const ROWS := 7
const INNER := 92.0
const STEP := 31.0
const SQUASH := 0.74                # seen from above: circles read as ellipses
const WIDEN := 1.14
const ARC_FROM := PI * 0.025
const ARC_TO := PI * 0.975
const AISLES := 3                   # stairs dividing the benches into blocks
const AISLE_GAP := 0.06             # radians
const WINDOWS := [64.0, 146.0, 228.0, 412.0, 494.0]
const BOARD := Rect2(548, 46, 72, 96)

const GLASS := Color(0.07, 0.08, 0.10)
const PANEL := Color(0.10, 0.10, 0.12)
const DARK_WOOD := Color(0.11, 0.10, 0.11)
const BROWN := Color(0.44, 0.34, 0.20)   # wood, kept off the converter's red
const MAHOGANY := Color(0.17, 0.17, 0.19)   # darker wood: darkened ochre snaps to olive, rust to alarm-red


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
	_well(v, t)
	_benches(v, t, _seat_colours(d.get("factions", [])), division, ayes)
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
	# The chamber floor outside the benches: panelled walls with doors.
	v.rect(v.left, 200, v.right - v.left, 220, DeskView.WALL.darkened(0.72))
	v.line(Vector2(v.left, 200), Vector2(v.right, 200), BROWN.lightened(0.1), 2.0)
	for side in [-1.0, 1.0]:
		var x: float = 320.0 + side * 296.0 - 14.0
		v.rect(x, 226, 28, 54, DARK_WOOD)
		v.rect(x + 3, 230, 22, 50, DeskView.INK)
		v.rect(x + 3, 230, 22, 2, DeskView.LAMP.darkened(0.35))   # lit transom
		v.line(Vector2(x + 14, 232), Vector2(x + 14, 280), DARK_WOOD, 1.5)


static func _rostrum(v: DeskView, t: float) -> void:
	# The Speaker's canopy, the hero of the room: lit wood under a crest.
	v.rect(282, 86, 76, 114, DARK_WOOD)
	v.poly(PackedVector2Array([Vector2(276, 90), Vector2(320, 64), Vector2(364, 90)]), BROWN)
	v.line(Vector2(276, 90), Vector2(364, 90), DeskView.PAPER.darkened(0.25), 2.0)
	v.rect(314, 70, 12, 12, DeskView.PAPER.darkened(0.15))          # the crest
	v.rect(317, 73, 6, 6, BROWN)
	v.rect(290, 96, 60, 72, DeskView.PAPER.darkened(0.3))           # lit back panel
	for x in [298.0, 310.0, 330.0, 342.0]:
		v.line(Vector2(x, 100), Vector2(x, 164), DeskView.PAPER.darkened(0.5), 1.5)
	v.rect(304, 110, 32, 46, MAHOGANY)            # chair back
	var lamp := 0.9 + 0.1 * sin(t * 0.7)
	v.rect(285, 96, 3, 3, DeskView.LAMP * Color(lamp, lamp, lamp))
	v.rect(352, 96, 3, 3, DeskView.LAMP * Color(lamp, lamp, lamp))
	# The Speaker, gesturing slowly.
	var speaking := sin(t * 0.8) > 0.2
	v.figure(314, 174, DeskView.PAPER.lightened(0.15), "point" if speaking else "stand", t, 36.0)
	# The dais, its panelled front, and the clerks' table at its foot.
	v.rect(268, 160, 104, 24, BROWN.lightened(0.05))
	v.rect(268, 160, 104, 2.5, DeskView.PAPER.darkened(0.3))
	for x in range(274, 368, 16):
		v.rect(x, 166, 12, 14, MAHOGANY)
	for i in 3:
		var x := 286.0 + i * 26.0
		v.figure(x, 196, DeskView.FIGURE.darkened(0.05), "sit", t, 20.0)
	v.rect(272, 192, 96, 8, BROWN.lightened(0.1))
	v.rect(272, 192, 96, 2, DeskView.PAPER.darkened(0.35))
	# Clerks' reading lamps and a page that turns now and then.
	v.rect(282, 189, 2, 3, DeskView.LAMP)
	v.rect(356, 189, 2, 3, DeskView.LAMP)
	var turn := fmod(t * 0.25, 1.0)
	v.rect(330, 190, 7, 2, DeskView.PAPER)
	if turn < 0.15:
		v.line(Vector2(330, 190), Vector2(330 + 7 * cos(turn * PI / 0.15), 186), DeskView.PAPER, 1.5)


static func _well(v: DeskView, t: float) -> void:
	# The well of the house: a tiled floor running toward us, the Table of
	# the House with the mace upon it, and an usher pacing slowly.
	var c := DeskView.STONE.darkened(0.55)
	for y in [212.0, 228.0, 248.0, 272.0]:
		var half := INNER * WIDEN * sqrt(maxf(0.0, 1.0 - pow((y - CENTRE.y) / (INNER * SQUASH), 2.0)))
		v.line(Vector2(320 - half, y), Vector2(320 + half, y), c, 1.5)
	for k in range(-4, 5):
		var a := PI * 0.5 + k * 0.17
		v.line(CENTRE + Vector2(k * 12.0, 4), CENTRE + Vector2(cos(a), sin(a)) * Vector2(INNER * WIDEN, INNER * SQUASH), c, 1.5)
	v.rect(286, 216, 68, 14, BROWN)
	v.rect(286, 216, 68, 2.5, BROWN.lightened(0.35))
	v.rect(290, 230, 3, 8, DARK_WOOD)
	v.rect(347, 230, 3, 8, DARK_WOOD)
	v.line(Vector2(296, 218), Vector2(338, 214), DeskView.LAMP, 2.0)  # the mace
	v.rect(336, 212, 5, 4, DeskView.LAMP)
	v.rect(300, 220, 8, 5, DeskView.PAPER.darkened(0.2))               # dispatch boxes
	v.rect(332, 220, 8, 5, DeskView.PAPER.darkened(0.2))
	var pace := 0.5 - 0.5 * cos(t * 0.18)
	v.figure(250 + pace * 130.0, 252, DeskView.FIGURE.darkened(0.2), "walk", t * 0.6, 22.0)


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
		# A muted wash: the chamber reads by bloc, never as a flag parade.
		var c: Color = colours[i].lerp(DeskView.FIGURE, 0.4)
		for s in int(sorted[i].get("seats", 0)):
			out.append(c)
	if out.is_empty():
		for s in 100:
			out.append(DeskView.FIGURE)
	return out


## The angle of a seat at `frac` across the arc, leaving the aisles clear.
static func _angle(frac: float) -> float:
	var usable := (ARC_TO - ARC_FROM) - AISLES * AISLE_GAP
	var block := mini(int(frac * (AISLES + 1)), AISLES)
	return ARC_TO - frac * usable - block * AISLE_GAP   # government on the left


static func _on_arc(a: float, radius: float) -> Vector2:
	return CENTRE + Vector2(cos(a) * radius * WIDEN, sin(a) * radius * SQUASH)


static func _band(v: DeskView, r0: float, r1: float, c: Color) -> void:
	var pts := PackedVector2Array()
	for k in 33:
		pts.append(_on_arc(lerpf(ARC_FROM - 0.02, ARC_TO + 0.02, k / 32.0), r1))
	for k in 33:
		pts.append(_on_arc(lerpf(ARC_TO + 0.02, ARC_FROM - 0.02, k / 32.0), r0))
	v.poly(pts, c)


static func _arc_line(v: DeskView, radius: float, c: Color, width: float) -> void:
	var prev := Vector2.ZERO
	for k in 41:
		var p := _on_arc(lerpf(ARC_FROM - 0.02, ARC_TO + 0.02, k / 40.0), radius)
		if k > 0:
			v.line(prev, p, c, width)
		prev = p


## Seats fill the hemicycle wedge by wedge, so each party holds one sector
## from the front bench to the back, the way real chambers seat blocs.
## Tiers are drawn far to near: a tier's riser, its members, then the desk
## in front of them, which the next tier's members overlap.
static func _benches(v: DeskView, t: float, seats: Array, division: bool, ayes: float) -> void:
	var per_row: Array[int] = []
	var total_len := 0.0
	for r in ROWS:
		total_len += INNER + r * STEP
	for r in ROWS:
		per_row.append(maxi(4, int(round(seats.size() * (INNER + r * STEP) / total_len))))
	var standing := int(seats.size() * ayes) if division else 0
	for r in ROWS:
		var radius := INNER + r * STEP
		var near := r / float(ROWS - 1)
		_band(v, radius - STEP + 9, radius + 9, DeskView.WALL.darkened(0.55 - near * 0.15))   # the tier floor
		var n: int = per_row[r]
		var h := 20.0 + near * 14.0
		for k in n:
			var frac := (k + 0.5) / n
			var p := _on_arc(_angle(frac), radius)
			var index := clampi(int(frac * seats.size()), 0, seats.size() - 1)
			var tone: Color = seats[index]
			var rise := division and index < standing
			# Ambient life: a member now and then shifts in their seat.
			var shift := 1.0 if sin(t * 0.6 + r * 3.1 + k * 1.7) > 0.96 else 0.0
			var w := 4.0 * h / 18.0
			if rise:
				v.figure(p.x - w * 0.5, p.y + 4 - shift, tone, "stand", t, h * 1.25)
			else:
				v.figure(p.x - w * 0.5, p.y + 4 + h * 0.33 - shift, tone, "sit", t, h)
		# The bench desk: a dark face under a lit rail.
		_band(v, radius + 4, radius + 9, DARK_WOOD)
		_arc_line(v, radius + 4, BROWN.lightened(0.3 + near * 0.1), 1.5 + near)
		# Reading lamps on the desks, one per few seats.
		for k in range(1, n, 3):
			var p := _on_arc(_angle((k + 0.0) / n), radius + 4)
			v.rect(p.x, p.y - 2, 1.5 + near, 1.5 + near, DeskView.LAMP.darkened(0.3))
	# The aisle stairs, cut through every tier.
	for i in AISLES:
		var a := ARC_FROM + (i + 1) * (ARC_TO - ARC_FROM - AISLES * AISLE_GAP) / (AISLES + 1) + i * AISLE_GAP + AISLE_GAP * 0.5
		var pts := PackedVector2Array([_on_arc(a - AISLE_GAP * 0.35, INNER - 12), _on_arc(a + AISLE_GAP * 0.35, INNER - 12),
				_on_arc(a + AISLE_GAP * 0.4, INNER + (ROWS - 1) * STEP + 12), _on_arc(a - AISLE_GAP * 0.4, INNER + (ROWS - 1) * STEP + 12)])
		v.poly(pts, DeskView.WALL.darkened(0.45))
		for s in ROWS * 2:
			var rad := INNER - 8 + s * STEP * 0.5
			v.line(_on_arc(a - AISLE_GAP * 0.35, rad), _on_arc(a + AISLE_GAP * 0.35, rad), DeskView.STONE.darkened(0.3), 1.5)


static func _press_rail(v: DeskView, t: float) -> void:
	# Our own vantage: the press gallery wraps the back of the hemicycle, its
	# stone parapet following the outer tier, reporters at desks in the
	# corners nearest us.
	var outer := INNER + (ROWS - 1) * STEP + 9
	var deck := PackedVector2Array()
	for k in 41:
		deck.append(_on_arc(PI * k / 40.0, outer + 22))
	deck.append(Vector2(v.left - 40, 440))
	deck.append(Vector2(v.right + 40, 440))
	v.poly(deck, DARK_WOOD.darkened(0.3))
	_band(v, outer + 10, outer + 22, DeskView.STONE.darkened(0.3))
	_arc_line(v, outer + 10, DeskView.STONE.lightened(0.1), 2.0)
	_arc_line(v, outer + 22, DeskView.STONE.darkened(0.05), 1.5)
	for k in 70:
		var a := lerpf(0.0, PI, k / 69.0)
		v.line(_on_arc(a, outer + 12), _on_arc(a, outer + 20), DeskView.STONE.darkened(0.55), 1.5)
	# The press desks: a ledge with typewriters, notebooks and a lamp each.
	for side in 2:
		var s := -1.0 if side == 0 else 1.0
		var base := 320.0 + s * 300.0
		v.poly(PackedVector2Array([Vector2(base - s * 10, 330), Vector2(base - s * 150, 420), Vector2(base + s * 60, 420), Vector2(base + s * 60, 330)]), DeskView.STONE.darkened(0.15))
		v.line(Vector2(base - s * 10, 330), Vector2(base - s * 150, 420), BROWN.lightened(0.2), 2.0)
		for i in 3:
			var x := base - s * (24.0 + i * 38.0)
			var y := 344.0 + i * 24.0
			v.rect(x - 7, y - 6, 14, 6, DeskView.METAL.darkened(0.1))          # typewriter
			v.rect(x - 5, y - 11, 10, 5, DeskView.PAPER)                        # its page
			var flick := 0.85 + 0.15 * sin(t * 0.5 + i * 2.0 + side)
			v.rect(x + s * 12, y - 9, 2, 2, DeskView.LAMP * Color(flick, flick, flick))
			v.line(Vector2(x + s * 12, y - 7), Vector2(x + s * 12, y), DeskView.METAL.darkened(0.3), 1.5)
	var lean := 0.5 - 0.5 * cos(t * 0.3)
	var typing := 1.0 if sin(t * 2.0) > 0.0 else 0.0
	v.figure(28, 420 + lean * 2.0, DeskView.FIGURE.darkened(0.05), "stand", t, 44.0)
	v.figure(70, 400 + typing, DeskView.FIGURE.darkened(0.12), "sit", t, 40.0)
	v.figure(560, 400, DeskView.FIGURE.darkened(0.12), "sit", t, 40.0)
	v.figure(604, 420, DeskView.FIGURE.darkened(0.05), "point" if sin(t * 0.25) > 0.6 else "stand", t, 44.0)
	v.rect(v.left, 412, v.right - v.left, 8, DeskView.INK)
	v.line(Vector2(v.left, 412), Vector2(v.right, 412), DeskView.STONE.darkened(0.2), 2.0)
