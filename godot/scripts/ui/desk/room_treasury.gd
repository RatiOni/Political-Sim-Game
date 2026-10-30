class_name RoomTreasury
extends RefCounted

## The budget desk's room: the counting hall of the Ministry of Finance.
## Clerks sit in two long rows of desks under green-shaded lamps; the year's
## figures hang on the great board at the far wall (revenue, spending and the
## balance as rows of lit cells); ledgers fill the shelves as far as revenue
## covers spending; the vault door stands at the right.
##
## data: revenue, spending (millions, forecast for the plan before the house
## or the default plan), balance (revenue - spending; negative = deficit).

const FLOOR := 150.0
const SHADE := Color(0.22, 0.36, 0.26)   # the green lamp shades
const NIGHT := Color(0.09, 0.12, 0.2)    # the sky through the high windows


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
	_ledgers(v, revenue / scale if revenue > 0.0 else 0.6)
	_board(v, t, revenue / scale, spending / scale, float(d.get("balance", revenue - spending)) / scale)
	_vault(v, t)
	_desks(v, t)
	v.label(Vector2(200, 15), "THE BOARD · FISCAL YEAR")
	v.label(Vector2(30, 24), "LEDGERS", Vector2(60, 40))
	v.label(Vector2(512, 22), "THE VAULT", Vector2(552, 52))
	v.label(Vector2(20, 236), "COUNTING HALL", Vector2(84, 214))


static func _hall(v: DeskView, t: float) -> void:
	v.rect(v.left, 0, v.right - v.left, 240, DeskView.WALL.darkened(0.5))
	# High windows between pilasters, night beyond; a cornice in one line.
	var first := int(floorf((v.left - 40.0) / 80.0))
	for i in range(first, first + int((v.right - v.left) / 80.0) + 2):
		var x := 40.0 + i * 80.0
		v.rect(x - 4, 8, 6, FLOOR - 8, DeskView.STONE.darkened(0.35))
		v.rect(x + 18, 24, 24, 70, NIGHT)
		v.line(Vector2(x + 30, 24), Vector2(x + 30, 94), DeskView.STONE.darkened(0.45))
		v.line(Vector2(x + 18, 58), Vector2(x + 42, 58), DeskView.STONE.darkened(0.45))
		v.poly(PackedVector2Array([Vector2(x + 18, 24), Vector2(x + 30, 14), Vector2(x + 42, 24)]), DeskView.STONE.darkened(0.4))
	v.line(Vector2(v.left, 8), Vector2(v.right, 8), DeskView.STONE, 2.0)
	v.line(Vector2(v.left, 112), Vector2(v.right, 112), DeskView.STONE.darkened(0.35))
	# Pendant lamps over the hall: single warm cells that breathe.
	for i in range(first, first + int((v.right - v.left) / 80.0) + 2):
		var x := 80.0 + i * 80.0
		var pulse := 0.85 + 0.15 * sin(t * 0.7 + i * 1.9)
		v.line(Vector2(x, 8), Vector2(x, 30), DeskView.METAL.darkened(0.45))
		v.rect(x - 2, 30, 4, 4, DeskView.LAMP * Color(pulse, pulse, pulse))
	v.rect(v.left, FLOOR, v.right - v.left, 240 - FLOOR, DeskView.WALL.darkened(0.7))
	v.line(Vector2(v.left, FLOOR), Vector2(v.right, FLOOR), DeskView.STONE.darkened(0.2))


## Shelves of ledgers on the left wall, filled bottom-up as far as the year's
## revenue covers its spending: a deficit year leaves the top shelves bare.
static func _ledgers(v: DeskView, fill: float) -> void:
	var x0 := 20.0
	var w := 136.0
	var shelves := 5
	var cap := 26
	v.rect(x0 - 3, 34, w + 6, 112, DeskView.INK)
	v.line(Vector2(x0 - 3, 34), Vector2(x0 - 3, 146), DeskView.WOOD.lightened(0.1))
	v.line(Vector2(x0 + w + 3, 34), Vector2(x0 + w + 3, 146), DeskView.WOOD.lightened(0.1))
	var spines := int(round(clampf(fill, 0.0, 1.0) * shelves * cap))
	var tones := [DeskView.WOOD, DeskView.STONE.darkened(0.15), DeskView.PAPER.darkened(0.5), DeskView.WOOD.lightened(0.15)]
	for s in shelves:
		var base := 144.0 - s * 22.0           # bottom shelf first
		v.line(Vector2(x0 - 3, base + 1), Vector2(x0 + w + 3, base + 1), DeskView.WOOD.lightened(0.25))
		for k in cap:
			if s * cap + k >= spines:
				return
			var tall := 14.0 + fposmod(sin((s * cap + k) * 7.13) * 31.7, 4.0)
			v.rect(x0 + k * 5.2, base - tall, 4, tall, tones[(k * 3 + s) % tones.size()])


## The great board: three rows of cells, revenue and spending against the
## larger of the two, and the balance — warm when in surplus, alarm when not.
static func _board(v: DeskView, t: float, rev: float, spend: float, bal: float) -> void:
	var x0 := 196.0
	v.rect(x0, 22, 252, 86, DeskView.INK)
	v.line(Vector2(x0, 22), Vector2(x0 + 252, 22), DeskView.METAL)
	v.line(Vector2(x0, 108), Vector2(x0 + 252, 108), DeskView.METAL)
	v.line(Vector2(x0, 22), Vector2(x0, 108), DeskView.METAL.darkened(0.3))
	v.line(Vector2(x0 + 252, 22), Vector2(x0 + 252, 108), DeskView.METAL.darkened(0.3))
	var rows := [
		[clampf(rev, 0.0, 1.0), DeskView.PAPER],
		[clampf(spend, 0.0, 1.0), DeskView.METAL.lightened(0.1)],
	]
	var deficit := bal < 0.0
	var bal_tone := DeskView.ALARM if deficit else DeskView.LAMP
	if deficit:
		var pulse := 0.85 + 0.15 * sin(t * 1.1)
		bal_tone = bal_tone * Color(pulse, pulse, pulse)
	rows.append([clampf(absf(bal), 0.0, 1.0), bal_tone])
	for r in rows.size():
		var y := 32.0 + r * 22.0
		# A caption of dashes stands for the row's name, like a flap board.
		for k in 3:
			v.rect(x0 + 8 + k * 7, y + 2, 5, 3, DeskView.PAPER.darkened(0.45))
		var lit := int(round(float(rows[r][0]) * 24.0))
		if r == 2 and absf(bal) > 0.0:
			lit = maxi(1, lit)
		for k in 24:
			var tone: Color = rows[r][1] if k < lit else DeskView.WALL.darkened(0.2)
			v.rect(x0 + 40 + k * 8.4, y, 6, 6, tone)
	# The ticker along the board's foot: figures flipping as clerks call them in.
	for k in 30:
		var on := sin(t * 0.6 + k * 2.3) > 0.55
		v.rect(x0 + 8 + k * 8, 99, 4, 3, DeskView.PAPER.darkened(0.35 if on else 0.75))


static func _vault(v: DeskView, t: float) -> void:
	var c := Vector2(560, 100)
	v.rect(c.x - 46, c.y - 52, 92, 102, DeskView.STONE.darkened(0.35))
	v.rect(c.x - 40, c.y - 46, 80, 96, DeskView.INK)
	v.disc(c, 36, DeskView.METAL.darkened(0.35))
	v.disc(c, 30, DeskView.METAL.darkened(0.55))
	# Bolts round the rim, then a wheel turning very slowly.
	for k in 12:
		var a := k * TAU / 12.0
		v.rect(c.x + cos(a) * 33 - 1.5, c.y + sin(a) * 33 - 1.5, 3, 3, DeskView.METAL)
	var spin := t * 0.12
	for k in 3:
		var a := spin + k * PI / 3.0
		var off := Vector2(cos(a), sin(a)) * 18.0
		v.line(c - off, c + off, DeskView.METAL.lightened(0.1), 2.0)
	v.disc(c, 5, DeskView.METAL)
	# Hinges on the frame, and the guard who stands his watch beside it.
	v.rect(c.x - 44, c.y - 30, 4, 10, DeskView.METAL.darkened(0.2))
	v.rect(c.x - 44, c.y + 20, 4, 10, DeskView.METAL.darkened(0.2))
	var shift := 1.0 if sin(t * 0.4) > 0.8 else 0.0
	v.figure(c.x + 52 + shift, FLOOR + 4, DeskView.FIGURE.darkened(0.25), "stand", t, 18.0)


## Two long rows of desks repeated across the hall, a clerk at every place
## and a green-shaded lamp between each pair; one clerk carries a ledger down
## the aisle between the rows.
static func _desks(v: DeskView, t: float) -> void:
	var first := int(floorf((v.left - 90.0) / 90.0))
	var count := int((v.right - v.left) / 90.0) + 3
	_desk_row(v, t, first, count, 168.0, 15.0, 0.25, 0)
	var walker := _glide(t, 110.0, 500.0, 140.0)
	var carry := DeskView.FIGURE.darkened(0.05)
	v.figure(walker.x, 194, carry, "walk" if walker.y > 0.0 else "stand", t, 16.0)
	v.rect(walker.x + 5, 183, 5, 4, DeskView.WOOD.lightened(0.2))
	_desk_row(v, t, first, count, 214.0, 20.0, 0.0, 45)


static func _desk_row(v: DeskView, t: float, first: int, count: int, top: float, h: float, dim: float, offset: int) -> void:
	for i in range(first, first + count):
		var x := float(offset) + i * 90.0
		var tone := DeskView.FIGURE.darkened(dim + 0.1 * fposmod(i, 2.0))
		for k in 2:
			var cx := x + 10 + k * 40
			var shift := 1.0 if sin(t * 0.5 + i * 2.7 + k * 1.3) > 0.94 else 0.0
			v.figure(cx, top + 2 - shift, tone, "sit", t, h)
			v.rect(cx - 2, top - 2, 8, 2, DeskView.PAPER.darkened(0.3 + dim))
		v.rect(x, top, 74, 2, DeskView.WOOD.darkened(0.25 + dim))
		v.rect(x, top + 2, 74, 2 + h * 0.3, DeskView.WOOD.darkened(0.6 + dim))
		# The lamp between the pair: stem, green shade, a breathing warm cell.
		var lx := x + 31
		var pulse := 0.85 + 0.15 * sin(t * 0.9 + i * 1.7 + offset)
		v.line(Vector2(lx + 2, top), Vector2(lx + 2, top - 8), DeskView.METAL.darkened(0.3))
		v.poly(PackedVector2Array([Vector2(lx - 3, top - 8), Vector2(lx + 7, top - 8), Vector2(lx + 5, top - 13), Vector2(lx - 1, top - 13)]), SHADE.darkened(dim))
		v.rect(lx, top - 7, 4, 3, DeskView.LAMP * Color(pulse, pulse, pulse))


## An eased ping-pong between `a` and `b` over `period` seconds, pausing at
## each end. Returns (x, moving): moving is 0 during the pauses.
static func _glide(t: float, a: float, b: float, period: float) -> Vector2:
	var tri := absf(fposmod(t / period, 1.0) * 2.0 - 1.0)
	var s := smoothstep(0.15, 0.85, tri)
	return Vector2(lerpf(a, b, s), 1.0 if s > 0.0 and s < 1.0 else 0.0)
