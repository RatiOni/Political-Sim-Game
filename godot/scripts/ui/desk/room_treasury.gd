class_name RoomTreasury
extends RefCounted

## The budget desk's room: the counting hall of the Ministry of Finance.
## A tall hall under high arched windows. The year's figures hang on the great
## board at the far wall (revenue, spending and the balance as rows of lit
## cells, the deficit pulsing in alarm); ledgers fill the two-tier galleries
## as far as revenue covers spending; the vault door stands at the right with
## its guard. Rows of clerks under green-shaded lamps recede across the tiled
## floor, a clerk carries a ledger down the aisle, and the near counter holds
## the adding machines, abacus and ledger stacks of the trade.
##
## data: revenue, spending (millions, forecast for the plan before the house
## or the default plan), balance (revenue - spending; negative = deficit).

const FLOOR := 232.0                     # where the far wall meets the floor
const GALLERY := 166.0                   # the gallery walkway
const VP := Vector2(320, 118)            # vanishing point of the floor
const SHADE := Color(0.22, 0.40, 0.27)   # the green lamp shades
const NIGHT := Color(0.08, 0.11, 0.19)   # the sky through the high windows
const BOARD := Rect2(196, 26, 248, 132)
const TIMBER := Color(0.44, 0.41, 0.37)  # oak, kept off the rust that alarm snaps to
const RUST := Color(0.42, 0.25, 0.18)    # a few old calf bindings
## The clerks' coats: black, navy and grey, so faces and shirt fronts read.
const COATS := [Color(0.12, 0.12, 0.13), Color(0.18, 0.21, 0.30), Color(0.32, 0.32, 0.33), Color(0.14, 0.16, 0.20)]


## What the room shows, read from the app snapshot.
static func data_from(snapshot: Dictionary) -> Dictionary:
	var model: Dictionary = snapshot.get("budget", {})
	var preview: Variant = model.get("pending_preview")
	if not (preview is Dictionary) or (preview as Dictionary).is_empty():
		preview = model.get("default_preview", {})
	var p: Dictionary = preview if preview is Dictionary else {}
	var revenue := float(p.get("forecast_revenue", 0.0))
	if revenue <= 0.0:
		for source in model.get("revenue_sources", []):
			if source is Dictionary:
				revenue += float(source.get("value", 0.0))
	var spending := float(p.get("total", revenue))
	return {
		"revenue": revenue,
		"spending": spending,
		"balance": float(p.get("forecast_balance", revenue - spending)),
	}


static func paint(v: DeskView, t: float, d: Dictionary) -> void:
	var revenue := maxf(0.0, float(d.get("revenue", 0.0)))
	var spending := maxf(0.0, float(d.get("spending", 0.0)))
	var scale := maxf(1.0, maxf(revenue, spending))
	_hall(v, t)
	_ledgers(v, t, revenue / scale if revenue > 0.0 else 0.6)
	_board(v, t, revenue / scale, spending / scale, float(d.get("balance", revenue - spending)) / scale)
	_cabinets(v, t)
	_vault(v, t)
	_floor(v)
	_pendants(v, t)
	_desk_row(v, t, 254.0, 0.72, 0.28, 0)
	_desk_row(v, t, 298.0, 1.05, 0.12, 1)
	_walker(v, t)
	_desk_row(v, t, 360.0, 1.5, 0.0, 2)
	_counter(v, t)
	v.label(Vector2(BOARD.position.x + 4, 12), "THE BOARD · FISCAL YEAR")
	v.label(Vector2(maxf(48.0, v.left + 8.0), 20), "LEDGERS", Vector2(90, 46))
	v.label(Vector2(492, 70), "THE VAULT", Vector2(520, 106))
	v.label(Vector2(maxf(12.0, v.left + 8.0), 414), "COUNTING HALL")


static func _span(v: DeskView, step: float, offset: float) -> Array:
	var out := []
	var first := int(floorf((v.left - offset - step) / step))
	for i in range(first, first + int((v.right - v.left) / step) + 3):
		out.append(offset + i * step)
	return out


## Coffered ceiling, cornice with dentils, high arched windows between
## pilasters, a string course and the dark lower wall.
static func _hall(v: DeskView, t: float) -> void:
	var w := v.right - v.left
	v.rect(v.left, 0, w, FLOOR, DeskView.WALL.darkened(0.45))
	v.rect(v.left, 0, w, 9, DeskView.INK)
	for x: float in _span(v, 16.0, 0.0):
		v.rect(x + 3, 2, 10, 5, DeskView.WALL.darkened(0.15))
	v.rect(v.left, 9, w, 2, DeskView.STONE)
	for x: float in _span(v, 6.0, 0.0):
		v.rect(x, 12, 3, 2.5, DeskView.STONE.darkened(0.35))
	for x: float in _span(v, 80.0, 0.0):
		# The window: an arch over three tiers of panes, night beyond.
		var wx := x + 22.0
		v.rect(wx - 2, 30, 40, 72, DeskView.STONE.darkened(0.5))
		v.rect(wx, 34, 36, 66, NIGHT)
		v.poly(PackedVector2Array([Vector2(wx - 2, 30), Vector2(wx + 6, 21), Vector2(wx + 18, 17), Vector2(wx + 30, 21), Vector2(wx + 38, 30)]), DeskView.STONE.darkened(0.5))
		v.poly(PackedVector2Array([Vector2(wx, 32), Vector2(wx + 7, 24), Vector2(wx + 18, 20.5), Vector2(wx + 29, 24), Vector2(wx + 36, 32)]), NIGHT)
		v.line(Vector2(wx + 18, 21), Vector2(wx + 18, 100), DeskView.STONE.darkened(0.4), 1.5)
		for y: float in [46.0, 62.0, 78.0]:
			v.line(Vector2(wx, y), Vector2(wx + 36, y), DeskView.STONE.darkened(0.4), 1.5)
		v.rect(wx - 4, 100, 44, 3, DeskView.STONE.darkened(0.25))
		# Distant lights of the capital in the lowest panes, fixed per window.
		var glim := absi(int(x * 7.0)) % 5
		v.rect(wx + 4 + glim * 2, 92, 2, 2, DeskView.LAMP.darkened(0.25))
		v.rect(wx + 24 + glim, 89, 2, 2, DeskView.PAPER.darkened(0.3))
		# The pilaster between windows, with base and capital.
		v.rect(x - 4, 16, 8, FLOOR - 16, DeskView.STONE.darkened(0.42))
		v.rect(x - 6, 16, 12, 4, DeskView.STONE.darkened(0.2))
		v.rect(x - 6, FLOOR - 6, 12, 6, DeskView.STONE.darkened(0.3))
		v.line(Vector2(x - 1, 22), Vector2(x - 1, FLOOR - 8), DeskView.STONE.darkened(0.55), 1.5)
	v.rect(v.left, 106, w, 3, DeskView.STONE.darkened(0.2))
	v.rect(v.left, 109, w, 2, DeskView.INK)
	# Wainscot panels on the lower wall.
	for x: float in _span(v, 40.0, 0.0):
		v.rect(x + 6, 186, 28, 38, DeskView.WALL.darkened(0.3))
		v.line(Vector2(x + 6, 186), Vector2(x + 34, 186), TIMBER.darkened(0.2), 1.5)
	v.rect(v.left, 180, w, 2, TIMBER.darkened(0.15))


## Two tiers of ledger shelving on the west wall with a railed gallery and
## ladders; filled bottom-up as far as the year's revenue covers spending,
## so a deficit year leaves the top shelves bare.
static func _ledgers(v: DeskView, t: float, fill: float) -> void:
	var x0 := v.left - 4.0
	var x1 := 186.0
	v.rect(x0, 112, x1 - x0 + 4, FLOOR - 112, DeskView.INK)
	var bases := [228.0, 208.0, 188.0, 162.0, 144.0, 126.0]
	var per := int((x1 - x0) / 8.0)
	var spines := int(round(clampf(fill, 0.0, 1.0) * bases.size() * per))
	var tones := [TIMBER, NIGHT.lightened(0.2), DeskView.PAPER.darkened(0.45), TIMBER.lightened(0.18), SHADE, RUST, DeskView.STONE.lightened(0.1)]
	for s in bases.size():
		var base: float = bases[s]
		v.rect(x0, base, x1 - x0, 2.5, DeskView.PAPER.darkened(0.45))
		for k in per:
			if s * per + k >= spines:
				break
			var n := s * per + k
			var tall := 13.0 + fposmod(sin(n * 7.13) * 31.7, 4.0)
			var x := x1 - 8.0 - k * 8.0
			if fposmod(n, 11.0) == 5.0:
				continue                      # a gap where one is out
			v.rect(x, base - tall, 5.5, tall, (tones[(k * 3 + s) % tones.size()] as Color).darkened(0.3))
			if n % 3 == 0:
				v.rect(x + 1.5, base - tall + 3, 2.5, 2.5, DeskView.PAPER.darkened(0.25))
	# Uprights.
	for x: float in _span(v, 46.0, 0.0):
		if x < x1:
			v.rect(x - 1, 112, 3, FLOOR - 112, TIMBER.darkened(0.1))
	v.rect(x1, 112, 4, FLOOR - 112, TIMBER)
	# The gallery: walkway, balusters and handrail.
	v.rect(x0, GALLERY, x1 - x0 + 4, 4, TIMBER.lightened(0.1))
	v.rect(x0, GALLERY + 4, x1 - x0 + 4, 2, DeskView.INK)
	v.rect(x0, GALLERY - 16, x1 - x0 + 4, 2, TIMBER.lightened(0.2))
	for x: float in _span(v, 7.0, 0.0):
		if x < x1:
			v.rect(x, GALLERY - 14, 1.5, 14, TIMBER.darkened(0.05))
	# Ladders, one on each tier.
	_ladder(v, Vector2(126, FLOOR), Vector2(140, GALLERY + 6))
	_ladder(v, Vector2(64, GALLERY), Vector2(74, 116))
	# An archivist on the gallery reaching for a ledger now and then.
	var reach := sin(t * 0.35) > 0.3
	v.figure(98, GALLERY, DeskView.FIGURE.darkened(0.3), "arms_up" if reach else "stand", t, 20.0)


static func _ladder(v: DeskView, foot: Vector2, top: Vector2) -> void:
	var tone := DeskView.PAPER.darkened(0.1)
	for side: float in [0.0, 11.0]:
		var o := Vector2(side, 0)
		v.poly(PackedVector2Array([foot + o, foot + o + Vector2(2.5, 0), top + o + Vector2(2.5, 0), top + o]), tone)
	var rungs := int((foot.y - top.y) / 8.0)
	for k in range(1, rungs + 1):
		var p := foot.lerp(top, float(k) / (rungs + 1))
		v.rect(p.x, p.y, 13, 2, tone)


## The great board: a pediment with the hall clock, then three rows of cells
## (revenue and spending against the larger of the two, and the balance —
## warm in surplus, a slow alarm pulse in deficit) and a ticker at its foot.
static func _board(v: DeskView, t: float, rev: float, spend: float, bal: float) -> void:
	var o := BOARD.position
	var s := BOARD.size
	v.rect(o.x - 6, o.y - 4, s.x + 12, s.y + 10, DeskView.STONE.darkened(0.25))
	v.rect(o.x - 3, o.y - 1, s.x + 6, s.y + 4, DeskView.METAL.darkened(0.15))
	v.rect(o.x, o.y + 2, s.x, s.y - 2, DeskView.INK)
	# Pediment and clock.
	var c := Vector2(o.x + s.x * 0.5, o.y - 6)
	v.poly(PackedVector2Array([Vector2(c.x - 40, o.y - 4), Vector2(c.x, o.y - 18), Vector2(c.x + 40, o.y - 4)]), DeskView.STONE.darkened(0.25))
	v.disc(c, 11, DeskView.METAL)
	v.disc(c, 9, DeskView.PAPER.darkened(0.15))
	var hour := t * 0.004 + 1.1
	v.line(c, c + Vector2(sin(hour), -cos(hour)) * 5.0, DeskView.INK, 2.0)
	v.line(c, c + Vector2(sin(hour * 12.0), -cos(hour * 12.0)) * 7.5, DeskView.INK, 1.5)
	# Header: a row of flap characters spelling nothing in particular.
	for k in 22:
		v.rect(o.x + 10 + k * 7, o.y + 9, 5, 5, DeskView.PAPER.darkened(0.55 if k % 6 == 5 else 0.3))
	v.rect(o.x + 6, o.y + 19, s.x - 12, 1.5, DeskView.METAL.darkened(0.3))
	var rows := [
		[clampf(rev, 0.0, 1.0), DeskView.PAPER],
		[clampf(spend, 0.0, 1.0), DeskView.METAL.lightened(0.25)],
	]
	var deficit := bal < 0.0
	var bal_tone := DeskView.ALARM if deficit else DeskView.LAMP
	if deficit:
		var pulse := 0.8 + 0.2 * (0.5 + 0.5 * sin(t * 0.9))
		bal_tone = bal_tone * Color(pulse, pulse, pulse)
	rows.append([clampf(absf(bal), 0.0, 1.0), bal_tone])
	for r in rows.size():
		var y := o.y + 30.0 + r * 28.0
		# A caption of flaps stands for the row's name.
		for k in 4:
			v.rect(o.x + 8 + k * 6, y + 2, 4, 6, DeskView.PAPER.darkened(0.4))
		var lit := int(round(float(rows[r][0]) * 24.0))
		if r == 2 and absf(bal) > 0.0:
			lit = maxi(1, lit)
		for k in 24:
			var tone: Color = rows[r][1] if k < lit else DeskView.WALL.darkened(0.1)
			v.rect(o.x + 40 + k * 8.0, y, 6, 10, tone)
		v.line(Vector2(o.x + 38, y + 14), Vector2(o.x + s.x - 8, y + 14), DeskView.WALL, 1.5)
	# Scale ticks and the ticker: figures flipping as clerks call them in.
	for k in 7:
		v.rect(o.x + 40 + k * 32.0, o.y + 110, 1.5, 4, DeskView.METAL.darkened(0.2))
	for k in 34:
		var on := sin(t * 0.5 + k * 2.3) > 0.5
		v.rect(o.x + 8 + k * 7, o.y + 120, 4, 4, DeskView.PAPER.darkened(0.3 if on else 0.75))
	# Two lamps on brackets light the board from below.
	for x: float in [o.x - 14, o.x + s.x + 10]:
		v.rect(x, o.y + 60, 4, 2, DeskView.METAL.darkened(0.2))
		v.rect(x + 1, o.y + 54, 3, 6, DeskView.METAL.darkened(0.35))
		v.rect(x + 1, o.y + 52, 2, 2, DeskView.LAMP)


## Filing cabinets under the board, a card drawer pulled out now and then.
static func _cabinets(v: DeskView, t: float) -> void:
	for k in 8:
		var x := 200.0 + k * 30.0
		v.rect(x, 184, 27, FLOOR - 184, DeskView.METAL.darkened(0.5))
		v.rect(x, 184, 27, 2, DeskView.METAL.darkened(0.2))
		var open := 1 if sin(t * 0.2 + k * 2.4) > 0.8 else 0
		for r in 4:
			var y := 189.0 + r * 10.5
			var out := 3.0 if r == (k % 4) and open == 1 else 0.0
			v.rect(x + 2, y + out * 0.3, 23, 8.5, DeskView.METAL.darkened(0.38))
			v.rect(x + 10, y + 2, 7, 2, DeskView.PAPER.darkened(0.35))
			v.rect(x + 12, y + 5, 3, 1.5, DeskView.METAL.lightened(0.1))
	# A stool and a waste-paper basket.
	v.rect(442, 214, 14, 2.5, DeskView.METAL.darkened(0.1))
	v.rect(444, 216, 2, 16, DeskView.METAL.darkened(0.3))
	v.rect(452, 216, 2, 16, DeskView.METAL.darkened(0.3))


static func _vault(v: DeskView, t: float) -> void:
	var c := Vector2(522, 176)
	# The stone surround with keystone, then the steel door.
	v.rect(c.x - 52, c.y - 60, 104, FLOOR - c.y + 60, DeskView.STONE.darkened(0.3))
	v.rect(c.x - 46, c.y - 54, 92, FLOOR - c.y + 54, DeskView.INK)
	v.poly(PackedVector2Array([Vector2(c.x - 8, c.y - 60), Vector2(c.x + 8, c.y - 60), Vector2(c.x + 5, c.y - 50), Vector2(c.x - 5, c.y - 50)]), DeskView.STONE.darkened(0.1))
	v.disc(c, 42, DeskView.METAL.darkened(0.2))
	v.disc(c, 37, DeskView.METAL.darkened(0.45))
	v.disc(c, 26, DeskView.METAL.darkened(0.35))
	for k in 16:
		var a := k * TAU / 16.0
		v.rect(c.x + cos(a) * 39.5 - 1.5, c.y + sin(a) * 39.5 - 1.5, 3, 3, DeskView.METAL.lightened(0.1))
	# The wheel, turning very slowly, and the dial beside it.
	var spin := t * 0.1
	for k in 3:
		var a := spin + k * PI / 3.0
		var off := Vector2(cos(a), sin(a)) * 20.0
		v.line(c - off, c + off, DeskView.METAL.lightened(0.2), 2.5)
		v.disc(c + off, 2.5, DeskView.METAL.lightened(0.2))
		v.disc(c - off, 2.5, DeskView.METAL.lightened(0.2))
	v.disc(c, 6, DeskView.METAL.lightened(0.1))
	v.disc(c, 2, DeskView.INK)
	v.disc(c + Vector2(0, -32), 4, DeskView.PAPER.darkened(0.35))
	# Hinges, the bar rail in front, and the guard on his watch.
	v.rect(c.x - 50, c.y - 30, 6, 12, DeskView.METAL.darkened(0.1))
	v.rect(c.x - 50, c.y + 18, 6, 12, DeskView.METAL.darkened(0.1))
	v.rect(c.x - 58, FLOOR - 22, 116, 2, DeskView.METAL.darkened(0.15))
	for k in 6:
		v.rect(c.x - 56 + k * 22.4, FLOOR - 22, 2, 22, DeskView.METAL.darkened(0.3))
	var shift := 1.0 if sin(t * 0.3) > 0.85 else 0.0
	v.figure(c.x + 58 + shift, FLOOR + 2, DeskView.FIGURE.darkened(0.2), "stand", t, 28.0)
	v.rect(c.x + 66 + shift, FLOOR - 32, 1.5, 24, DeskView.METAL.darkened(0.1))


## Tiled floor in perspective: lines run to the vanishing point and the
## courses widen toward the viewer.
static func _floor(v: DeskView) -> void:
	var w := v.right - v.left
	v.rect(v.left, FLOOR, w, 420 - FLOOR, DeskView.WALL.darkened(0.7))
	var ys: Array[float] = [FLOOR + 2.0]
	var step := 7.0
	while ys[-1] < 420.0:
		ys.append(ys[-1] + step)
		step *= 1.3
	var lit := DeskView.WALL.darkened(0.58)
	for r in ys.size() - 1:
		var f0 := (ys[r] - VP.y) / (420.0 - VP.y)
		var f1 := (ys[r + 1] - VP.y) / (420.0 - VP.y)
		for c in range(-14, 14):
			if posmod(r + c, 2) != 0:
				continue
			var a := c * 120.0
			var b := (c + 1) * 120.0
			if VP.x + b * f1 < v.left or VP.x + a * f1 > v.right:
				continue
			v.poly(PackedVector2Array([Vector2(VP.x + a * f0, ys[r]), Vector2(VP.x + b * f0, ys[r]),
				Vector2(VP.x + b * f1, ys[r + 1]), Vector2(VP.x + a * f1, ys[r + 1])]), lit)
	v.rect(v.left, FLOOR, w, 3, DeskView.STONE.darkened(0.15))


## Pendant lamps hanging into the hall, clear of the board.
static func _pendants(v: DeskView, t: float) -> void:
	for x: float in _span(v, 230.0, 90.0):
		if x > BOARD.position.x - 20 and x < BOARD.end.x + 20:
			continue
		v.line(Vector2(x, 0), Vector2(x, 196), DeskView.METAL.darkened(0.45), 1.5)
		v.poly(PackedVector2Array([Vector2(x - 9, 204), Vector2(x - 4, 196), Vector2(x + 4, 196), Vector2(x + 9, 204)]), DeskView.METAL.darkened(0.25))
		var p := 0.88 + 0.12 * sin(t * 0.6 + x)
		v.rect(x - 1.5, 204, 3, 3, DeskView.LAMP * Color(p, p, p))


## One row of paired desks across the hall at a given depth: `s` scales the
## desks and clerks, `dim` darkens the row with distance.
static func _desk_row(v: DeskView, t: float, top: float, s: float, dim: float, row: int) -> void:
	var step := 128.0 * s
	var off := (64.0 if row % 2 == 1 else 0.0) * s
	for x: float in _span(v, step, VP.x + off - 40.0 * s):
		_desk(v, t, x, top, s, dim, int(round(x / step)) + row * 7)


static func _desk(v: DeskView, t: float, x: float, top: float, s: float, dim: float, i: int) -> void:
	var w := 84.0 * s
	var h := 28.0 * s
	var u := h / 18.0
	for k in 2:
		var cx := x + 12 * s + k * 50 * s
		var shift := 1.0 if sin(t * 0.45 + i * 2.7 + k * 1.3) > 0.94 else 0.0
		var coat: Color = COATS[posmod(i * 2 + k, COATS.size())]
		v.figure(cx, top + 6 * u - shift, coat.darkened(dim), "sit", t, h, DeskView.SKIN.darkened(dim))
		# The white shirt front and, when writing, a pen hand on the ledger.
		v.rect(cx + 1.2 * u, top - 7 * u - shift, 1.6 * u, 2.5 * u, DeskView.PAPER.darkened(dim))
	var wood := TIMBER.darkened(dim * 0.8)
	v.rect(x, top, w, 3 * s, wood.lightened(0.25))
	v.rect(x + 2 * s, top + 3 * s, w - 4 * s, 14 * s, Color(0.10, 0.08, 0.07))
	# The lamp's warm pool on the desk top, under the shade.
	v.rect(x + w - 34 * s, top - 0.5 * s, 30 * s, 3 * s, DeskView.LAMP.darkened(0.35 + dim * 0.5))
	v.rect(x + 2 * s, top + 3 * s, w - 4 * s, 1.5, DeskView.INK)
	for k in 2:
		v.rect(x + 8 * s + k * 50 * s, top + 7 * s, 14 * s, 6 * s, wood.darkened(0.5))
		v.rect(x + 14 * s + k * 50 * s, top + 9 * s, 2 * s, 2 * s, DeskView.METAL.darkened(dim))
	v.rect(x + 3 * s, top + 17 * s, 3 * s, 8 * s, wood.darkened(0.55))
	v.rect(x + w - 6 * s, top + 17 * s, 3 * s, 8 * s, wood.darkened(0.55))
	# Open ledgers, an adding machine or an abacus between the places.
	for k in 2:
		var lx := x + 8 * s + k * 50 * s
		v.rect(lx, top - 2 * s, 16 * s, 2 * s, DeskView.PAPER.darkened(0.2 + dim))
		v.rect(lx + 7.5 * s, top - 2 * s, 1, 2 * s, DeskView.WALL)
	var mx := x + 32 * s
	if i % 2 == 0:
		v.rect(mx, top - 6 * s, 12 * s, 6 * s, DeskView.METAL.darkened(0.25 + dim))
		v.rect(mx + 2 * s, top - 8 * s, 8 * s, 2 * s, DeskView.METAL.darkened(0.1 + dim))
		var crank := sin(t * 1.4 + i) > 0.6
		v.rect(mx + 12 * s, top - (9 if crank else 5) * s, 2 * s, 4 * s, DeskView.METAL.darkened(dim))
	else:
		v.rect(mx, top - 9 * s, 14 * s, 9 * s, TIMBER.darkened(0.1 + dim))
		v.rect(mx + 1.5 * s, top - 7.5 * s, 11 * s, 6 * s, DeskView.INK)
		for r in 3:
			var bead := fposmod(i * 3.0 + r * 5.0, 4.0)
			v.rect(mx + (2 + bead) * s, top - (7 - r * 2) * s, 3 * s, 1.5 * s, DeskView.PAPER.darkened(0.25 + dim))
	# The green-shaded lamp, its bulb one breathing warm cell.
	var lx2 := x + w - 16 * s
	var pulse := 0.88 + 0.12 * sin(t * 0.8 + i * 1.7)
	v.rect(lx2 + 3 * s, top - 10 * s, 1.5 * s, 10 * s, DeskView.METAL.darkened(0.25 + dim))
	v.poly(PackedVector2Array([Vector2(lx2 - 4 * s, top - 10 * s), Vector2(lx2 + 10 * s, top - 10 * s), Vector2(lx2 + 7 * s, top - 15 * s), Vector2(lx2 - 1 * s, top - 15 * s)]), SHADE.darkened(dim))
	v.rect(lx2 + 1 * s, top - 10 * s, 4 * s, 2 * s, DeskView.LAMP * Color(pulse, pulse, pulse))
	# Ledgers stacked at the desk's end.
	for k in 3:
		v.rect(x + 2 * s, top - (k + 1) * 3 * s, 10 * s, 2.5 * s, [TIMBER.lightened(0.2), SHADE.darkened(0.2), DeskView.PAPER.darkened(0.4)][k].darkened(dim))


## A clerk carrying a ledger down the aisle between the middle and near rows.
static func _walker(v: DeskView, t: float) -> void:
	var g := _glide(t, 70.0, 560.0, 120.0)
	var foot := 342.0
	v.figure(g.x, foot, DeskView.FIGURE.darkened(0.05), "walk" if g.y > 0.0 else "stand", t, 32.0)
	v.rect(g.x + 7, foot - 22, 8, 6, TIMBER.lightened(0.25))
	v.rect(g.x + 7, foot - 20, 8, 1.5, DeskView.PAPER.darkened(0.2))


## The near counter, in silhouette across the foot of the frame: an adding
## machine, a telephone, a big abacus, stacked ledgers and a stamp rack.
static func _counter(v: DeskView, t: float) -> void:
	var w := v.right - v.left
	var top := 398.0
	v.rect(v.left, top, w, 420 - top, TIMBER.darkened(0.75))
	v.rect(v.left, top, w, 2.5, TIMBER.lightened(0.05))
	v.rect(v.left, top + 7, w, 1.5, DeskView.INK)
	for x: float in _span(v, 300.0, 40.0):
		# Adding machine with a paper roll creeping up.
		v.rect(x, top - 14, 30, 14, DeskView.METAL.darkened(0.3))
		v.rect(x + 3, top - 20, 22, 6, DeskView.METAL.darkened(0.15))
		for r in 3:
			for c in 5:
				v.rect(x + 4 + c * 5, top - 12 + r * 4, 3, 2.5, DeskView.PAPER.darkened(0.5))
		var roll := fposmod(t * 0.8, 14.0)
		v.rect(x + 9, top - 20 - roll, 8, roll, DeskView.PAPER.darkened(0.1))
		v.rect(x + 30, top - 12, 4, 3, DeskView.METAL.darkened(0.1))
		# Telephone.
		v.rect(x + 52, top - 7, 16, 7, DeskView.INK.lightened(0.08))
		v.rect(x + 50, top - 12, 20, 4, DeskView.INK.lightened(0.12))
		v.disc(Vector2(x + 60, top - 4), 2.5, DeskView.METAL.darkened(0.3))
		# The big abacus.
		v.rect(x + 96, top - 26, 54, 26, TIMBER.darkened(0.15))
		v.rect(x + 99, top - 23, 48, 20, DeskView.INK)
		for r in 4:
			var y := top - 20 + r * 5.0
			v.line(Vector2(x + 99, y + 1), Vector2(x + 147, y + 1), DeskView.METAL.darkened(0.4), 1.0)
			var slide := 6.0 * (0.5 + 0.5 * sin(t * 0.25 + r * 1.9))
			for b in 4:
				v.rect(x + 101 + b * 5 + (slide if b == 3 else 0.0), y - 0.5, 4, 3.5, TIMBER.lightened(0.3))
			for b in 3:
				v.rect(x + 132 + b * 5, y - 0.5, 4, 3.5, TIMBER.lightened(0.15))
		# Stacked ledgers and a stamp rack.
		for k in 5:
			v.rect(x + 176 + (k % 2) * 2, top - 6 - k * 6, 30, 5, [TIMBER.lightened(0.15), SHADE.darkened(0.15), DeskView.STONE][k % 3])
			v.rect(x + 176 + (k % 2) * 2, top - 4 - k * 6, 30, 1, DeskView.PAPER.darkened(0.35))
		v.rect(x + 232, top - 4, 34, 4, TIMBER.darkened(0.1))
		for k in 5:
			v.rect(x + 235 + k * 6, top - 14, 2, 10, DeskView.METAL.darkened(0.3))
			v.rect(x + 233.5 + k * 6, top - 17, 5, 3, TIMBER.lightened(0.2))


## An eased ping-pong between `a` and `b` over `period` seconds, pausing at
## each end. Returns (x, moving): moving is 0 during the pauses.
static func _glide(t: float, a: float, b: float, period: float) -> Vector2:
	var tri := absf(fposmod(t / period, 1.0) * 2.0 - 1.0)
	var s := smoothstep(0.15, 0.85, tri)
	return Vector2(lerpf(a, b, s), 1.0 if s > 0.0 and s < 1.0 else 0.0)
