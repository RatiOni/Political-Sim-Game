class_name RoomParliament
extends RefCounted

## The legislation desk's room: the National Assembly seen from the press
## gallery. Benches climb in a hemicycle around the rostrum, every seat filled
## by a delegate in a muted wash of their party's colour, government on the
## left. When a division is called the members voting aye rise.
##
## data: factions (snapshot rows: seats, color, in_coalition), bill (title or
## ""), division (true while a vote is being taken), ayes (0..1 share).

const CENTRE := Vector2(320, 120)   # the rostrum, at the far end of the floor
const ROWS := 6
const INNER := 70.0
const STEP := 26.0
const SQUASH := 0.6                 # seen from above: circles read as ellipses
const WIDEN := 1.7                  # the floor fills the wide panel
const ARC_FROM := PI * 0.05
const ARC_TO := PI * 0.95


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
	_hall(v, t)
	var seats := _seat_colours(d.get("factions", []))
	_gallery(v, t)
	_rostrum(v, t)
	_benches(v, t, seats, bool(d.get("division", false)), float(d.get("ayes", 0.0)))
	_board(v, t, d)
	v.label(Vector2(372, 104), "THE ROSTRUM", Vector2(342, 112))
	v.label(Vector2(16, 18), "PRESS GALLERY · FIXED")
	if String(d.get("bill", "")) != "":
		v.label(Vector2(476, 40), "ORDER OF THE DAY")


static func _hall(v: DeskView, t: float) -> void:
	v.rect(v.left, 0, v.right - v.left, 240, DeskView.WALL.darkened(0.45))
	# Tall windows behind the chamber, night beyond; a slow lamp pulse inside.
	var first := int(floorf((v.left - 40.0) / 84.0))
	for i in range(first, first + int((v.right - v.left) / 84.0) + 2):
		var x := 40.0 + i * 84.0
		v.rect(x, 26, 30, 86, DeskView.INK)
		v.line(Vector2(x + 15, 26), Vector2(x + 15, 112), DeskView.STONE.darkened(0.3))
		v.line(Vector2(x, 69), Vector2(x + 30, 69), DeskView.STONE.darkened(0.3))
		v.poly(PackedVector2Array([Vector2(x, 26), Vector2(x + 15, 14), Vector2(x + 30, 26)]), DeskView.STONE.darkened(0.2))
	# Cornice and pilasters: the building's bones, in thin lines.
	v.line(Vector2(v.left, 10), Vector2(v.right, 10), DeskView.STONE, 2.0)
	v.line(Vector2(v.left, 122), Vector2(v.right, 122), DeskView.STONE.darkened(0.2))
	for i in range(first, first + int((v.right - v.left) / 84.0) + 3):
		v.rect(16.0 + i * 84.0, 10, 6, 112, DeskView.STONE.darkened(0.15))
	# Chandeliers: a few lamp cells that breathe very softly.
	for x in [180.0, 460.0]:
		v.line(Vector2(x, 10), Vector2(x, 34), DeskView.METAL.darkened(0.3))
		var pulse := 0.85 + 0.15 * sin(t * 0.8 + x)
		for k in 5:
			v.rect(x - 12 + k * 6, 36, 2, 2, DeskView.LAMP * Color(pulse, pulse, pulse))


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
		var c: Color = colours[i].lerp(DeskView.FIGURE, 0.45)
		for s in int(sorted[i].get("seats", 0)):
			out.append(c)
	if out.is_empty():
		for s in 100:
			out.append(DeskView.FIGURE)
	return out


## Seats fill the hemicycle wedge by wedge, so each party holds one sector
## from the front bench to the back, the way real chambers seat blocs.
static func _benches(v: DeskView, t: float, seats: Array, division: bool, ayes: float) -> void:
	var per_row: Array[int] = []
	var total_len := 0.0
	for r in ROWS:
		total_len += INNER + r * STEP
	for r in ROWS:
		per_row.append(maxi(4, int(round(seats.size() * (INNER + r * STEP) / total_len))))
	# The floor, then each tier's bench rail, far to near.
	v.rect(v.left, 122, v.right - v.left, 118, DeskView.WALL.darkened(0.6))
	for r in ROWS:
		var radius := INNER + r * STEP
		var prev := Vector2.ZERO
		for k in 25:
			var a := lerpf(ARC_FROM, ARC_TO, k / 24.0)
			var p := CENTRE + Vector2(cos(a) * (radius + 6) * WIDEN, sin(a) * (radius + 6) * SQUASH)
			if k > 0:
				v.line(prev, p, DeskView.WOOD.lightened(0.15), 2.0)
			prev = p
	var standing := int(seats.size() * ayes) if division else 0
	for r in ROWS:
		var radius := INNER + r * STEP
		var n: int = per_row[r]
		for k in n:
			var frac := (k + 0.5) / n
			var a := lerpf(ARC_FROM, ARC_TO, frac)
			var p := CENTRE + Vector2(cos(a) * radius * WIDEN, sin(a) * radius * SQUASH)
			var index := clampi(int(frac * seats.size()), 0, seats.size() - 1)
			var tone: Color = seats[index]
			var rise := division and index < standing
			# Ambient life: a member now and then shifts in their seat.
			var shift := 1.0 if sin(t * 0.7 + r * 3.1 + k * 1.7) > 0.97 else 0.0
			var near := 0.8 + 0.4 * r / float(ROWS - 1)   # nearer tiers read larger
			v.figure(p.x - 2, p.y + 2 - shift, tone, "stand" if rise else "sit", t, (18.0 if rise else 13.0) * near)


static func _rostrum(v: DeskView, t: float) -> void:
	v.rect(290, 96, 60, 28, DeskView.WOOD)
	v.rect(290, 96, 60, 2, DeskView.WOOD.lightened(0.3))
	v.rect(306, 82, 28, 14, DeskView.WOOD.lightened(0.1))
	# The speaker, gesturing slowly; the clerks at their table below.
	var speaking := sin(t * 0.9) > 0.0
	v.figure(316, 96, DeskView.PAPER, "point" if speaking else "stand", t, 18.0)
	v.rect(330, 84, 2, 2, DeskView.LAMP)
	for x in [298.0, 334.0]:
		v.figure(x, 124, DeskView.FIGURE.darkened(0.15), "sit", t, 10.0)


static func _gallery(v: DeskView, t: float) -> void:
	# The public gallery: a dotted mass along the balcony rail.
	v.line(Vector2(v.left, 122), Vector2(v.right, 122), DeskView.METAL.darkened(0.2), 2.0)
	var first := int(floorf(v.left / 9.0))
	for i in range(first, first + int((v.right - v.left) / 9.0) + 1):
		var x := 6.0 + i * 9.0 + sin(i * 12.9) * 2.0
		var bob := 1.0 if sin(t * 0.5 + i) > 0.95 else 0.0
		v.rect(x, 114 - bob, 3, 3, DeskView.FIGURE.darkened(0.45))


static func _board(v: DeskView, t: float, d: Dictionary) -> void:
	# The division board on the right wall: ayes fill as the vote is counted.
	var x := 560.0
	v.rect(x, 44, 64, 64, DeskView.INK)
	v.line(Vector2(x, 44), Vector2(x + 64, 44), DeskView.METAL)
	v.line(Vector2(x, 108), Vector2(x + 64, 108), DeskView.METAL)
	var division := bool(d.get("division", false))
	var lit := int(float(d.get("ayes", 0.0)) * 20.0) if division else 0
	for i in 20:
		var cx := x + 6 + (i % 5) * 12
		var cy := 52.0 + floorf(i / 5.0) * 13
		v.rect(cx, cy, 6, 6, DeskView.LAMP if i < lit else DeskView.WALL)
	if division and int(t * 1.0) % 2 == 0:
		v.rect(x + 28, 36, 8, 4, DeskView.LAMP)
