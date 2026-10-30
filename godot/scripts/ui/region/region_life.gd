class_name RegionLife
extends RefCounted

## Everything in a region picture that moves, drawn every frame on continuous
## time. Positions snap to the scene-pixel grid so the art stays crisp, but
## they advance smoothly between snaps — a car glides a pixel at a time at
## frame rate instead of jumping three pixels at 8 fps. Light (lamps, fire,
## headlights, searchlights) is soft on purpose: drawn as translucent cones
## and pools over the hard-edged scene, it is what makes it read as evening.

const COATS: Array[Color] = [
	Color(0.28, 0.25, 0.22), Color(0.16, 0.18, 0.24), Color(0.36, 0.30, 0.22),
	Color(0.22, 0.24, 0.20), Color(0.40, 0.18, 0.15), Color(0.50, 0.48, 0.44),
]
const CAR_TONES: Array[Color] = [
	Color(0.45, 0.16, 0.13), Color(0.20, 0.30, 0.42), Color(0.55, 0.53, 0.48),
	Color(0.24, 0.32, 0.22), Color(0.50, 0.42, 0.20),
]
const SKIN := Color(0.62, 0.50, 0.40)
## People are faceless pictograms in one flat tone, read by posture.
const FIGURE := Color(0.62, 0.59, 0.52)
const FIGURE_H := 14.0
const LAMP := Color(1.0, 0.80, 0.48)

var canvas: CanvasItem
var origin := Vector2.ZERO
var px := 2.0
## The camera: drift and push-in applied to everything drawn.
var base := Transform2D.IDENTITY
## 1 at night, 0 by day (`DayCycle`): night-only light fades with it.
var night := 1.0


func _blk(x: float, y: float, w: float, h: float, c: Color) -> void:
	# Not snapped: the source moves continuously and the ASCII pass does the
	# quantising, so motion steps gradually through the shading ramp.
	canvas.draw_rect(Rect2(origin + Vector2(x, y) * px, Vector2(w, h) * px), c, true)


func _glow(x: float, y: float, r: float, c: Color, strength: float) -> void:
	return   # bloom dropped at the owner's request; callers keep their call sites
	strength *= 0.15 + 0.85 * night
	for i in 4:
		var k := 1.0 - i / 4.0
		var col := c
		col.a = strength * 0.25 * (1.0 - k * 0.6)
		canvas.draw_circle(origin + Vector2(x, y) * px, r * k * px, col)


## A soft beam: full strength at the source, fading to nothing at the far edge.
func _beam(from: Vector2, a: Vector2, b: Vector2, c: Color, strength: float) -> void:
	return   # soft light beams dropped along with the bloom
	var near := c
	near.a = strength * (0.1 + 0.9 * night)
	var far := c
	far.a = 0.0
	canvas.draw_polygon(PackedVector2Array([origin + from * px, origin + a * px, origin + b * px]),
		PackedColorArray([near, far, far]))


## A block drawn behind the street: columns where a building rises above
## its top are left out, so the train passes behind spires, not over them.
func _behind(s: RegionScene, x: float, y: float, w: float, h: float, c: Color) -> void:
	if s.front_top.is_empty():
		_blk(x, y, w, h, c)
		return
	for i in int(w):
		var col := int(x) + i
		if col < 0 or col >= s.cols:
			continue
		var clip := minf(h, float(s.front_top[col]) - y)
		if clip > 0.0:
			_blk(col, y, 1, clip, c)


## A faceless figure in one tone: head, torso, legs. `stride` -1 stands,
## 0/1 are the two walking steps; `arms_up` raises both arms (a marshaller,
## a protester with fists up).
func pictogram(x: float, foot: float, tone: Color, stride: int, arms_up: bool = false) -> void:
	var y := foot - FIGURE_H
	_blk(x, y, 3, 3, tone)                       # head
	_blk(x - 0.5, y + 4, 4, 5, tone)             # torso
	if arms_up:
		_blk(x - 2, y - 1, 1, 6, tone)
		_blk(x + 4, y - 1, 1, 6, tone)
	else:
		_blk(x - 1.5, y + 4, 1, 4, tone)
		_blk(x + 3.5, y + 4, 1, 4, tone)
	match stride:
		0:
			_blk(x - 1, y + 9, 1.5, 5, tone)
			_blk(x + 2.5, y + 9, 1.5, 5, tone)
		1:
			_blk(x, y + 9, 1.5, 5, tone)
			_blk(x + 1.5, y + 9, 1.5, 5, tone)
		_:
			_blk(x, y + 9, 1.5, 5, tone)
			_blk(x + 2, y + 9, 1.5, 5, tone)


func draw(s: RegionScene, t: float) -> void:
	_sky_shift(s, t)
	_stars(s, t)
	_clouds(s, t)
	_haze(s, t)
	_birds(s, t)
	_searchlight(s, t)
	_landmark(s, t)
	_mill(s, t)
	_beacons(s, t)
	_windows(s, t)
	_smoke(s, t)
	_flag(s, t)
	_crane(s, t)
	_lamps(s, t)
	_people(s, t)
	_cars(s, t)
	RegionProjects.draw(self, s, t)
	_fires(s, t)
	_water(s, t)


## The sky's colour drifts over a minute or so: from cold night blue toward a
## warmer haze, deeper ember when the region is in trouble.
func _sky_shift(s: RegionScene, t: float) -> void:
	var k := 0.5 + 0.5 * sin(t * 0.06)
	var warm := Color(0.45, 0.22, 0.10) if s.trouble > 0.5 else Color(0.30, 0.26, 0.30)
	var tint := Color(0.08, 0.12, 0.22).lerp(warm, k)
	tint.a = 0.10
	canvas.draw_rect(Rect2(origin, Vector2(s.cols, s.horizon) * px), tint, true)


## Layers of low haze along the horizon, sliding at different speeds: the
## atmospheric depth between the town and the hills.
func _haze(s: RegionScene, t: float) -> void:
	for layer in 3:
		var y := s.horizon - 14.0 + layer * 9.0
		for i in 6:
			var x := fposmod(i * s.cols / 5.0 + t * (1.5 + layer), s.cols + 120.0) - 60.0
			var col := Color(0.55, 0.55, 0.60, 0.035) if s.trouble < 0.5 else Color(0.50, 0.30, 0.18, 0.05)
			canvas.draw_set_transform_matrix(base * Transform2D(0.0, Vector2(1.0, 0.18), 0.0, origin + Vector2(x, y) * px))
			canvas.draw_circle(Vector2.ZERO, 60.0 * px, col)
	canvas.draw_set_transform_matrix(base)


func _stars(s: RegionScene, t: float) -> void:
	for st in s.stars:
		var a := (0.35 + 0.35 * sin(t * 1.3 + st.z * 3.0)) * night
		_blk(st.x, st.y, 1, 1, Color(0.85, 0.87, 0.95, a))


func _clouds(s: RegionScene, t: float) -> void:
	# Long, low banks of overlapping translucent ellipses, lit faintly from
	# below by the town (or by fire). Many weak blobs, so no single disc shows.
	var tone := Color(0.40, 0.43, 0.52) if s.trouble < 0.5 else Color(0.30, 0.16, 0.10)
	for c in s.clouds:
		var w := float(c["w"])
		var cx := fposmod(float(c["x"]) + t * float(c["speed"]), s.cols + w * 2.0) - w
		var cy := float(c["y"])
		for i in 9:
			var col := tone
			col.a = 0.035
			var bx := cx + w * (i / 8.0)
			var by := cy + sin(i * 2.3 + float(c["x"])) * 1.5
			canvas.draw_set_transform_matrix(base * Transform2D(0.0, Vector2(1.0, 0.35), 0.0, origin + Vector2(bx, by) * px))
			canvas.draw_circle(Vector2.ZERO, w * (0.16 + 0.06 * sin(i * 1.9)) * px, col)
		canvas.draw_set_transform_matrix(base)


func _birds(s: RegionScene, t: float) -> void:
	if s.trouble > 0.4:
		return
	var cycle := fposmod(t, 45.0)
	if cycle > 20.0:
		return
	for i in 5:
		var bx := cycle * (s.cols + 40.0) / 20.0 - 20.0 - i * 6.0 + absf(i - 2.0) * 3.0
		var by := s.horizon * 0.35 + sin(cycle * 0.6 + i) * 3.0 + absf(i - 2.0) * 3.0
		var flap := 1.0 if sin(t * 9.0 + i * 1.3) > 0.0 else 0.0
		var ink := Color(0.10, 0.10, 0.13)
		_blk(bx, by, 1, 1, ink)
		_blk(bx - 1, by - flap, 1, 1, ink)
		_blk(bx + 1, by - flap, 1, 1, ink)


## Motion that belongs to the frame's subject: the lighthouse beam turning,
## a train crossing the viaduct, the clock keeping time.
func _landmark(s: RegionScene, t: float) -> void:
	var cx := float(s.landmark_x)
	match s.landmark:
		"lighthouse":
			var lamp := Vector2(cx, s.ground - 102)
			var turn := t * 0.6
			var side := cos(turn)
			if absf(side) > 0.05:
				var tip := lamp + Vector2(side * s.cols * 0.7, -6.0)
				_beam(lamp, tip + Vector2(0, -14), tip + Vector2(0, 14), Color(1.0, 0.95, 0.80), 0.30 * absf(side))
			_glow(lamp.x, lamp.y, 6.0, Color(1, 0.95, 0.8), 0.9)
		"viaduct":
			var deck := float(s.horizon - 20)
			var x := fposmod(t * 22.0, s.cols + 220.0) - 200.0
			_behind(s, x + 170, deck - 9, 26, 9, Color(0.16, 0.16, 0.17))
			_behind(s, x + 190, deck - 13, 4, 4, Color(0.16, 0.16, 0.17))
			_behind(s, x + 192, deck - 7, 3, 3, Color(1.0, 0.9, 0.6))
			for car in 6:
				var c := x + car * 28.0
				_behind(s, c, deck - 8, 25, 8, Color(0.30, 0.22, 0.16))
				for w in range(2, 22, 5):
					_behind(s, c + w, deck - 6, 3, 3, Color(1.0, 0.80, 0.45, 0.9))
			for i in 8:
				var age := fposmod(t * 0.4 + i / 8.0, 1.0)
				var col := Color(0.70, 0.70, 0.72, (1.0 - age) * 0.35)
				canvas.draw_circle(origin + Vector2(x + 192 - age * 40.0, deck - 14 - age * 26.0) * px, (2.0 + age * 7.0) * px, col)
		"clocktower":
			var face := Vector2(s.clock_at)
			var hands := [[t * 0.02, 5.0], [t * 0.24, 7.5]]
			for hand in hands:
				var a: float = hand[0] - PI * 0.5
				for r in range(0, int(hand[1])):
					_blk(face.x + cos(a) * r, face.y + sin(a) * r, 1, 1, Color(0.12, 0.11, 0.10))


func _searchlight(s: RegionScene, t: float) -> void:
	if s.searchlight_at.x < 0:
		return
	var head := Vector2(s.searchlight_at) + Vector2(3, -8)
	var angle := PI * 0.5 + sin(t * 0.35) * 1.0
	var reach := s.horizon * 1.2
	var dir := Vector2(cos(angle), -absf(sin(angle))) * reach
	var side := dir.orthogonal().normalized() * reach * 0.12
	_beam(head, head + dir - side, head + dir + side, Color(0.95, 0.95, 0.80), 0.22)
	_glow(head.x, head.y, 3.0, Color(1, 1, 0.85), 1.0)


func _mill(s: RegionScene, t: float) -> void:
	if s.mill_at.x < 0:
		return
	var hub := Vector2(s.mill_at) + Vector2(0, -22)
	for k in 4:
		var a := t * 0.9 + k * PI * 0.5
		for r in range(2, 14):
			_blk(hub.x + cos(a) * r, hub.y + sin(a) * r, 1, 1, Color(0.30, 0.28, 0.24))
	_blk(hub.x - 1, hub.y - 1, 2, 2, Color(0.40, 0.36, 0.30))


func _beacons(s: RegionScene, t: float) -> void:
	if fposmod(t, 2.0) > 1.0:
		return
	for b in s.beacons:
		_blk(b.x, b.y, 2, 1, Color(1.0, 0.25, 0.18))
		_glow(b.x + 1, b.y, 4.0, Color(1.0, 0.2, 0.15), 0.6)


## Televisions flicker blue; a few lights go on and off as people move about.
func _windows(s: RegionScene, t: float) -> void:
	for i in s.tv_windows.size():
		var w := s.tv_windows[i]
		var k := 0.5 + 0.5 * sin(t * 7.0 + i * 3.1) * sin(t * 2.3 + i)
		_blk(w.x, w.y, 4, 6, Color(0.55, 0.70, 1.0, 0.25 + 0.45 * k))
	# One window at a time changes: every few seconds a different lit one goes
	# dark and a different dark one lights up, as people go about the night.
	for slot in 2:
		var n := s.blink_lit.size()
		if n > 0:
			var r := s.blink_lit[(int(t / (2.3 + slot * 1.1)) * 37 + slot * 101) % n]
			_blk(r.position.x, r.position.y, r.size.x, r.size.y, Color(0.05, 0.06, 0.08))
		var m := s.blink_dark.size()
		if m > 0:
			var r := s.blink_dark[(int(t / (3.1 + slot * 1.7)) * 53 + slot * 17) % m]
			_blk(r.position.x, r.position.y, r.size.x, r.size.y, Color(1.0, 0.76, 0.40).darkened(0.1 * slot))


func _smoke(s: RegionScene, t: float) -> void:
	for c in s.chimneys:
		var stack := String(c["kind"]) == "stack"
		if stack and not s.works_running:
			continue
		if not stack and s.development < 0.2:
			continue
		var puffs := 10 if stack else 6
		var reach := 46.0 if stack else 18.0
		for i in puffs:
			var age := fposmod(t * (0.16 if stack else 0.22) + float(i) / puffs, 1.0)
			var x := float(c["x"]) + age * reach * 0.55 + sin(age * 6.0 + i) * 2.0
			var y := float(c["y"]) - age * reach
			var col := Color(0.55, 0.55, 0.56) if stack else Color(0.42, 0.40, 0.40)
			col.a = (1.0 - age) * (0.42 if stack else 0.30)
			canvas.draw_circle(origin + Vector2(x, y) * px, (1.0 + age * (6.0 if stack else 3.0)) * px, col)


func _flag(s: RegionScene, t: float) -> void:
	if s.flag_at.x < 0:
		return
	var separatist := String(s.region.get("control", "full")) == "separatist"
	var cloth := Color(0.83, 0.30, 0.22) if separatist else Color(0.89, 0.60, 0.23)
	for c in 14:
		var wave := sin(t * 4.0 - c * 0.55) * (c / 14.0) * 1.6
		var shade := cloth.darkened(0.25 * (0.5 + 0.5 * sin(t * 4.0 - c * 0.55 + 1.2)))
		_blk(s.flag_at.x + 1 + c, s.flag_at.y + wave, 1, 8, shade)


func _crane(s: RegionScene, t: float) -> void:
	if s.crane_at < 0:
		return
	var top := s.ground - 52 - 34
	var trolley := s.crane_at + 15 + 22.0 + sin(t * 0.25) * 18.0
	_blk(s.crane_at - 6, top, 62, 2, Color(0.89, 0.60, 0.23))
	_blk(trolley - 1, top + 2, 3, 1, Color(0.6, 0.4, 0.15))
	var sway := sin(t * 1.4) * 2.0
	for k in 14:
		_blk(trolley + sway * k / 14.0, top + 3 + k, 1, 1, Color(0.4, 0.4, 0.4))
	_blk(trolley + sway - 3, top + 17, 7, 4, Color(0.30, 0.20, 0.10))


func _lamps(s: RegionScene, t: float) -> void:
	if s.development < 0.25 and s.trouble < 0.35:
		return
	for i in s.lamps.size():
		var lx := float(s.lamps[i]) + 4.0
		var head := Vector2(lx, s.ground - 23)
		var flicker := 1.0
		if s.trouble > 0.5 and i % 4 == 1:
			flicker = 0.0 if sin(t * 13.0 + i) > 0.6 else 1.0   # a dying tube
		var strength := (0.16 + 0.02 * sin(t * 3.0 + i)) * flicker * night
		_beam(head, Vector2(lx - 11, s.road_top + 3), Vector2(lx + 11, s.road_top + 3), LAMP, strength)
		var pool := LAMP
		pool.a = 0.10 * flicker * night
		canvas.draw_set_transform_matrix(base * Transform2D(0.0, Vector2(1.0, 0.3), 0.0, origin + Vector2(lx, s.road_top) * px))
		canvas.draw_circle(Vector2.ZERO, 12.0 * px, pool)
		canvas.draw_set_transform_matrix(base)
		_blk(lx - 1, s.ground - 24, 3, 2, LAMP if flicker > 0.0 else Color(0.3, 0.3, 0.3))


## Figures on the pavement. A four-frame stride keyed to distance travelled,
## so feet never slide; protesters stand, sway and raise placards.
func _people(s: RegionScene, t: float) -> void:
	for p in s.people:
		var lane := int(p["lane"])
		var foot := float(s.ground + 2 + lane * 2)
		var x := float(p["x"])
		var dist := 0.0
		if not bool(p["idle"]):
			dist = t * float(p["speed"])
			x = fposmod(x + dist, s.cols + 20.0) - 10.0
		var bob := 0.0
		if bool(p.get("protest", false)):
			bob = floorf(0.5 + 0.5 * sin(t * 4.0 + float(p["phase"])))
		var stride := int(absf(dist) / 1.5) % 4
		var y := foot - FIGURE_H - bob
		var protest := bool(p.get("protest", false))
		pictogram(x, foot - bob, FIGURE, (stride % 2) if not bool(p["idle"]) else -1, protest and int(p["coat"]) % 3 == 0)
		if bool(p.get("placard", false)):
			var lift := floorf(1.5 + 1.5 * sin(t * 2.5 + float(p["phase"])))
			_blk(x + 1, y - 6 - lift, 1, 7, Color(0.30, 0.22, 0.14))
			_blk(x - 2, y - 10 - lift, 7, 4, Color(0.85, 0.82, 0.72))


func _cars(s: RegionScene, t: float) -> void:
	for c in s.cars:
		var length := float(c["len"])
		var x := fposmod(float(c["x"]) + t * float(c["speed"]), s.cols + length * 2.0) - length
		var forward := float(c["speed"]) > 0.0
		var y := float(s.road_top + 3 + int(c["lane"]) * int(s.road_h * 0.45))
		var body: Color = CAR_TONES[int(c["tone"])]
		var nose := x + length if forward else x
		var reach := 26.0 * (1.0 if forward else -1.0)
		_beam(Vector2(nose, y + 3), Vector2(nose + reach, y - 1), Vector2(nose + reach, y + 8), LAMP, 0.18 * night)
		if bool(c["bus"]):
			_blk(x, y - 6, length, 10, Color(0.62, 0.50, 0.22))
			for wx in range(2, int(length) - 3, 4):
				_blk(x + wx, y - 5, 3, 3, Color(1.0, 0.85, 0.55, 0.9))
		else:
			_blk(x, y, length, 5, body)
			_blk(x + length * 0.25, y - 3, length * 0.5, 3, body.lightened(0.15))
			_blk(x + length * 0.3, y - 2, length * 0.4, 2, Color(0.10, 0.12, 0.16))
		var tail := x if forward else x + length - 1
		_blk(tail, y + 1, 1, 2, Color(1.0, 0.2, 0.15))
		_blk(nose - (1.0 if forward else 0.0), y + 1, 1, 2, Color(1.0, 0.92, 0.7))
		# Wheels with a hub that turns with the distance covered.
		var spin := int(absf(t * float(c["speed"])) / 2.0) % 2
		for wx in [x + 2.0, x + length - 5.0]:
			_blk(wx, y + 4, 3, 3, Color(0.04, 0.04, 0.05))
			_blk(wx + spin, y + 5, 1, 1, Color(0.45, 0.45, 0.45))


func _fires(s: RegionScene, t: float) -> void:
	for f in s.fires:
		var fx := float(f["x"])
		var size := float(f["size"])
		var base := float(s.ground)
		_glow(fx + 3, base - 8, 34.0 * size, Color(1.0, 0.45, 0.15), 0.55 + 0.15 * sin(t * 7.0 + fx))
		for j in 7:
			var flick := 0.5 + 0.5 * sin(t * (9.0 + j * 1.3) + j * 2.1 + fx)
			var tall := (6.0 + 9.0 * flick) * size
			var col := Color(0.95, 0.30, 0.10).lerp(Color(1.0, 0.85, 0.35), float(j % 3) / 2.0)
			_blk(fx + j, base - tall, 1, tall, col)
		for e in 6:
			var age := fposmod(t * 0.7 + e / 6.0 + fx * 0.01, 1.0)
			_blk(fx + 3 + sin(age * 9.0 + e) * 4.0, base - 14 - age * 34.0, 1, 1, Color(1.0, 0.7, 0.3, 1.0 - age))
		for i in 8:
			var age := fposmod(t * 0.12 + i / 8.0, 1.0)
			var col := Color(0.08, 0.07, 0.07, (1.0 - age) * 0.55)
			canvas.draw_circle(origin + Vector2(fx + 3 + age * 20.0 + sin(age * 5.0 + i) * 3.0, base - 18 - age * 70.0) * px, (3.0 + age * 9.0) * px, col)


## Lights shattered into horizontal streaks on dark water, as in a harbour at
## night: every lit window and lamp throws a broken, wobbling line below.
func _water(s: RegionScene, t: float) -> void:
	if s.water_top < 0:
		return
	var depth := s.h - s.water_top
	var sources: Array[Vector2] = []
	for lx in s.lamps:
		sources.append(Vector2(lx + 4, 0))
	for i in range(0, s.lit_windows.size(), 2):
		sources.append(Vector2(s.lit_windows[i].x, 1))
	for src in sources:
		var lamp := src.y < 0.5
		for row in range(1, depth, 2):
			var k := float(row) / depth
			var wob := sin(t * 1.6 + row * 0.9 + src.x * 0.3) * (1.0 + k * 3.0)
			var w := (3.0 if lamp else 2.0) + sin(t * 2.2 + row * 1.3 + src.x) * 1.5
			if w < 1.0:
				continue
			var col := LAMP
			col.a = (0.55 if lamp else 0.28) * (1.0 - k) * (0.25 + 0.75 * night)
			_blk(src.x + wob - w * 0.5, s.water_top + row, w, 1, col)
	for b in s.boats:
		var bx := fposmod(float(b["x"]) + t * 1.5, s.cols + 40.0) - 20.0
		var bob := floorf(sin(t * 1.1 + float(b["phase"])) * 1.2)
		var by := s.water_top + depth * 0.45 + bob
		var bw := float(b["w"])
		_blk(bx, by, bw, 3, Color(0.22, 0.20, 0.18))
		_blk(bx + 1, by + 3, bw - 2, 1, Color(0.12, 0.11, 0.10))
		_blk(bx + bw * 0.3, by - 4, bw * 0.35, 4, Color(0.32, 0.30, 0.27))
		_blk(bx + bw * 0.35, by - 3, 2, 2, Color(1.0, 0.8, 0.45))
		_blk(bx + bw * 0.6, by - 12, 1, 8, Color(0.28, 0.26, 0.24))
