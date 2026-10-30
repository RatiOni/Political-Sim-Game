class_name RoomOpposition
extends RefCounted

## The opposition desk's room: the party headquarters press room seen from
## the back of the hall. The leader speaks at a lit podium on a low stage,
## the shadow cabinet standing in a line behind them under a blank campaign
## banner; rows of seated reporters face the stage, camera crews stand at
## their tripods, and now and then a press camera flashes.
##
## data: credibility (0..1), support (the player's party polling share),
## shadow (shadow ministers named), active (true while the player is in
## opposition). Interest — credibility and polling together — fills the seats.

const STAGE_Y := 148.0          # the stage edge; the floor runs below it
const ROWS := [176.0, 204.0, 236.0]
const AISLE := Vector2(300, 342)


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
	_hall(v, t)
	_stage(v, t, int(d.get("shadow", 0)))
	_press(v, t, interest(d))
	v.label(Vector2(384, 104), "THE PODIUM", Vector2(338, 124))
	v.label(Vector2(470, 160), "PRESS", Vector2(452, 186))


## Stable 0..1 noise per integer pair, so seats and flashes never reshuffle.
static func _hash(a: float, b: float) -> float:
	var s := sin(a * 12.9898 + b * 78.233) * 43758.5453
	return s - floorf(s)


static func _hall(v: DeskView, t: float) -> void:
	v.rect(v.left, 0, v.right - v.left, 240, DeskView.WALL.darkened(0.55))
	# Ceiling line and wall panelling, repeated to the panel edges.
	v.line(Vector2(v.left, 12), Vector2(v.right, 12), DeskView.STONE.darkened(0.2), 2.0)
	v.line(Vector2(v.left, 120), Vector2(v.right, 120), DeskView.STONE.darkened(0.45))
	var first := int(floorf((v.left - 20.0) / 64.0))
	for i in range(first, first + int((v.right - v.left) / 64.0) + 2):
		var x := 20.0 + i * 64.0
		v.line(Vector2(x, 12), Vector2(x, STAGE_Y), DeskView.STONE.darkened(0.25))
		# A wall sconce in every other bay: one warm cell.
		if i % 2 == 0 and (x < 130.0 or x > 500.0):
			var glow := 0.85 + 0.15 * sin(t * 0.6 + i * 1.3)
			v.rect(x + 30, 62, 3, 3, DeskView.LAMP * Color(glow, glow, glow))
	# The campaign banner: one long blank strip of cloth, hemmed in colour.
	v.rect(150, 34, 340, 16, DeskView.STONE.darkened(0.15))
	v.rect(150, 34, 340, 3, DeskView.ALARM.darkened(0.35))
	v.rect(150, 47, 340, 3, DeskView.ALARM.darkened(0.35))
	for x in [150.0, 488.0]:
		v.line(Vector2(x + 1, 12), Vector2(x + 1, 34), DeskView.METAL.darkened(0.4))


static func _stage(v: DeskView, t: float, shadow: int) -> void:
	v.rect(v.left, STAGE_Y, v.right - v.left, 240 - STAGE_Y, DeskView.WALL.darkened(0.72))
	v.rect(150, 138, 340, 10, DeskView.WALL.darkened(0.45))
	v.line(Vector2(150, 138), Vector2(490, 138), DeskView.METAL.darkened(0.2))
	# The shadow cabinet stands in a line behind the leader, a little apart.
	var count := clampi(shadow if shadow > 0 else 4, 2, 8)
	for i in count:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := 320.0 + side * (36.0 + floorf(i / 2.0) * 24.0) - 2.0
		var sway := 0.5 * sin(t * 0.4 + i * 2.1)
		v.figure(x + sway, 136, DeskView.FIGURE.darkened(0.1), "stand", t, 18.0)
	# A stage lamp on the ceiling rail, trained on the podium.
	v.line(Vector2(280, 14), Vector2(360, 14), DeskView.METAL.darkened(0.2))
	v.rect(314, 14, 8, 5, DeskView.METAL)
	v.rect(316, 19, 4, 2, DeskView.LAMP)
	# The leader at the microphone, gesturing in slow turns: the hero.
	var phase := fmod(t * 0.25, 1.0)
	var pose := "point" if phase < 0.45 else ("arms_up" if phase < 0.6 else "stand")
	v.figure(317, 138, DeskView.PAPER.lightened(0.2), pose, t, 22.0)
	v.rect(308, 124, 24, 24, DeskView.WOOD)
	v.rect(308, 124, 24, 2, DeskView.WOOD.lightened(0.4))
	v.line(Vector2(326, 124), Vector2(323, 118), DeskView.METAL)
	v.rect(322, 116, 3, 3, DeskView.METAL.lightened(0.3))
	v.rect(312, 132, 3, 3, DeskView.LAMP)


static func _press(v: DeskView, t: float, fill: float) -> void:
	var share := 0.2 + 0.75 * fill
	for r in ROWS.size():
		var y: float = ROWS[r]
		var near := 0.85 + 0.3 * r / float(ROWS.size() - 1)
		var step := 13.0 * near
		var first := int(floorf((v.left + 10.0) / step))
		for k in range(first, first + int((v.right - v.left) / step)):
			var x := k * step
			if x > AISLE.x - 6 and x < AISLE.y:
				continue
			if _hash(k, r) < share:
				var shift := 1.0 if sin(t * 0.6 + k * 1.9 + r * 3.7) > 0.97 else 0.0
				v.figure(x, y - shift, DeskView.FIGURE, "sit", t, 16.0 * near)
			else:
				v.rect(x - 1, y - 6 * near, 7 * near, 2, DeskView.METAL.darkened(0.5))
	# Camera crews on tripods along the aisle and the walls, more as
	# interest grows.
	var crews := [Vector2(284, 172), Vector2(372, 172), Vector2(110, 162), Vector2(540, 162), Vector2(-150, 166), Vector2(800, 166)]
	var n := 2 + int(round(fill * 4.0))
	for i in mini(n, crews.size()):
		_camera(v, t, crews[i], i)
	# Press flashes: a brief bright cell over the seats, easing back.
	var flashes := 2 + int(fill * 6.0)
	for i in flashes:
		var period := 2.6 + _hash(i, 7.0) * 3.4
		var local := fmod(t + _hash(i, 3.0) * period, period)
		if local > 0.4:
			continue
		var row := i % ROWS.size()
		var fx := 320.0 + (_hash(i, 11.0) - 0.5) * (500.0 + row * 300.0)
		var k := 1.0 if local < 0.045 else 1.0 - (local - 0.045) / 0.355
		var c := DeskView.FIGURE.lerp(Color(1, 0.97, 0.88), k * k)
		v.rect(fx, ROWS[row] - 20, 4, 4, c)


static func _camera(v: DeskView, t: float, at: Vector2, i: int) -> void:
	var legs := DeskView.METAL
	v.line(at + Vector2(0, -14), at + Vector2(-6, 0), legs)
	v.line(at + Vector2(0, -14), at + Vector2(6, 0), legs)
	v.line(at + Vector2(0, -14), at, legs)
	var pan := 0.8 * sin(t * 0.3 + i * 1.7)
	v.rect(at.x - 5 + pan, at.y - 20, 11, 6, DeskView.METAL.lightened(0.15))
	v.rect(at.x + 6 + pan, at.y - 19, 3, 4, DeskView.METAL)
	if i % 2 == 0:
		v.rect(at.x - 4 + pan, at.y - 22, 2, 2, DeskView.ALARM)   # tally light
	v.figure(at.x - 13, at.y, DeskView.FIGURE.darkened(0.1), "stand", t, 19.0)
