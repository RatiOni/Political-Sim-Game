class_name RegionProjects
extends RefCounted

## The visible work of a regional programme, drawn per frame by `RegionLife`.
## Each programme looks like what it is, so the picture tells you which one
## is running without reading the panel:
##   industrial_recovery       crane, welding sparks, a lorry of steel
##   public_works              roadworks: cones, an excavator, a roller, crews
##   administrative_deployment officials' cars and a queue at the state office
##   customs_enforcement       a checkpoint whose barrier lifts for a lorry queue
##   security_stabilisation    a sandbagged post and patrols with flashing lights

const HI_VIS := Color(0.95, 0.55, 0.12)
const STEEL := Color(0.42, 0.44, 0.48)
const OLIVE := Color(0.22, 0.26, 0.16)
const BLACK_CAR := Color(0.07, 0.07, 0.08)
const SANDBAG := Color(0.45, 0.40, 0.28)


static func draw(l: RegionLife, s: RegionScene, t: float) -> void:
	match s.program_id:
		"industrial_recovery": _industry(l, s, t)
		"public_works": _roadworks(l, s, t)
		"administrative_deployment": _offices(l, s, t)
		"customs_enforcement": _checkpoint(l, s, t)
		"security_stabilisation": _patrols(l, s, t)


static func _lane_y(s: RegionScene, lane: int) -> float:
	return float(s.road_top + 3 + lane * int(s.road_h * 0.45))


## A figure on foot; `vest` paints it as a road crew or soldier.
static func _figure(l: RegionLife, x: float, foot: float, coat: Color, t: float, walking: bool, phase: float) -> void:
	var y := foot - 10.0
	l._blk(x, y, 2, 2, RegionLife.SKIN.darkened(0.3))
	l._blk(x - 0.5, y + 2, 3, 4, coat)
	var step := int(t * 6.0 + phase) % 2 if walking else 0
	l._blk(x - float(step), y + 6, 1, 4, Color(0.1, 0.1, 0.12))
	l._blk(x + 1.0 + float(step), y + 6, 1, 4, Color(0.1, 0.1, 0.12))


static func _lorry(l: RegionLife, x: float, y: float, cab: Color, load: Color) -> void:
	l._blk(x, y - 6, 22, 9, load)
	l._blk(x + 22, y - 4, 8, 7, cab)
	l._blk(x + 25, y - 3, 4, 2, Color(0.10, 0.12, 0.16))
	for wx in [x + 3.0, x + 15.0, x + 25.0]:
		l._blk(wx, y + 3, 3, 3, Color(0.04, 0.04, 0.05))


static func _industry(l: RegionLife, s: RegionScene, t: float) -> void:
	var x := float(s.crane_at)
	var top := float(s.ground - 52)
	# Welding on the frame: a white flash, then sparks falling and cooling.
	for site in 3:
		var sx := x + 4.0 + site * 9.0
		var sy := top + 10.0 + site * 14.0
		var on := sin(t * 5.0 + site * 2.1) > 0.4
		if on:
			l._glow(sx, sy, 7.0, Color(0.75, 0.85, 1.0), 0.9)
			l._blk(sx, sy, 1, 1, Color(1, 1, 1))
		for k in 5:
			var age := fposmod(t * 1.4 + k * 0.2 + site, 1.0)
			l._blk(sx + (k - 2) * age * 3.0, sy + age * age * 18.0, 1, 1, Color(1.0, 0.75, 0.3, 1.0 - age))
	# A lorry of girders waiting by the site.
	_lorry(l, x + 34.0, float(s.ground - 3), Color(0.55, 0.20, 0.14), Color(0.16, 0.16, 0.18))
	for k in 3:
		l._blk(x + 35.0, float(s.ground - 10 - k * 2), 20, 1, STEEL)


static func _roadworks(l: RegionLife, s: RegionScene, t: float) -> void:
	var y := _lane_y(s, 1)
	var x0 := float(s.cols) * 0.58
	# A closed lane: cones and a striped barrier with a turning amber beacon.
	for k in 7:
		var cx := x0 + k * 9.0
		l._blk(cx, y + 1, 3, 4, HI_VIS)
		l._blk(cx, y + 2, 3, 1, Color(0.95, 0.92, 0.85))
	for k in 6:
		l._blk(x0 - 14.0 + k * 3.0, y - 2, 3, 2, HI_VIS if k % 2 == 0 else Color(0.95, 0.92, 0.85))
	if sin(t * 6.0) > 0.0:
		l._glow(x0 - 8.0, y - 4, 6.0, HI_VIS, 0.8)
	# The excavator: tracks, cab, and an arm that digs and lifts.
	var ex := x0 + 14.0
	l._blk(ex, y + 3, 18, 3, Color(0.10, 0.10, 0.10))
	l._blk(ex + 2, y - 5, 12, 8, Color(0.85, 0.65, 0.15))
	l._blk(ex + 4, y - 4, 4, 3, Color(0.10, 0.12, 0.16))
	var dig := 0.5 + 0.5 * sin(t * 0.9)
	var elbow := Vector2(ex + 22.0, y - 12.0 + dig * 4.0)
	var bucket := elbow + Vector2(6.0, 4.0 + dig * 8.0)
	for k in 6:
		var a := Vector2(ex + 12.0, y - 4.0).lerp(elbow, k / 5.0)
		l._blk(a.x, a.y, 2, 2, Color(0.80, 0.60, 0.14))
	for k in 4:
		var b := elbow.lerp(bucket, k / 3.0)
		l._blk(b.x, b.y, 1.5, 1.5, Color(0.75, 0.55, 0.12))
	l._blk(bucket.x - 2, bucket.y, 5, 3, Color(0.30, 0.24, 0.16))
	# A roller crawling back and forth on fresh asphalt.
	var rx := x0 + 34.0 + sin(t * 0.3) * 10.0
	l._blk(x0 + 30.0, y + 5, 40, 1, Color(0.04, 0.04, 0.05))
	l._blk(rx, y - 3, 10, 6, Color(0.85, 0.65, 0.15))
	l._blk(rx - 4, y - 1, 6, 6, STEEL.darkened(0.2))
	# The crew in vests, one digging.
	for k in 3:
		var fx := x0 + 4.0 + k * 16.0
		var foot := float(s.ground + 2) - floorf(maxf(0.0, sin(t * 3.0 + k)) * 1.0)
		_figure(l, fx, foot, HI_VIS, t, false, k)


static func _offices(l: RegionLife, s: RegionScene, t: float) -> void:
	if s.flag_at.x < 0:
		return
	var door := float(s.flag_at.x - 22 + 20)
	# A banner across the hall and a second flag beside the first.
	l._blk(door - 18.0, float(s.ground - 40), 40, 4, Color(0.89, 0.60, 0.23))
	l._blk(door - 16.0, float(s.ground - 39), 36, 1, Color(0.30, 0.10, 0.08))
	# A queue at the door, shuffling forward; clerks crossing with files.
	for k in 8:
		var shuffle := fposmod(t * 0.8 + k, 1.0) * 0.8
		_figure(l, door - 6.0 - k * 4.0 + shuffle, float(s.ground + 2), RegionLife.COATS[k % 6], t, false, k)
	for k in 2:
		var cx := fposmod(door + t * 9.0 * (1.0 if k == 0 else -1.0) + k * 60.0, float(s.cols))
		_figure(l, cx, float(s.ground + 4), Color(0.18, 0.20, 0.26), t, true, k)
		l._blk(cx + 2.0, float(s.ground - 4), 2, 3, Color(0.85, 0.82, 0.72))
	# Officials' cars parked at the kerb.
	var y := _lane_y(s, 0)
	for k in 2:
		var x := door + 14.0 + k * 22.0
		l._blk(x, y, 18, 5, BLACK_CAR)
		l._blk(x + 4, y - 3, 10, 3, BLACK_CAR.lightened(0.1))
		l._blk(x + 1, y + 1, 1, 1, Color(0.89, 0.60, 0.23))


static func _checkpoint(l: RegionLife, s: RegionScene, t: float) -> void:
	var y := _lane_y(s, 0)
	var bx := float(s.cols) * 0.78
	# The booth with its floodlight.
	l._blk(bx - 12.0, y - 16, 10, 16, Color(0.55, 0.53, 0.48))
	l._blk(bx - 10.0, y - 13, 6, 4, Color(0.95, 0.85, 0.55))
	l._blk(bx - 13.0, y - 18, 12, 2, Color(0.30, 0.30, 0.32))
	l._beam(Vector2(bx - 7.0, y - 18), Vector2(bx - 30.0, y + 8), Vector2(bx + 20.0, y + 8), Color(0.95, 0.92, 0.80), 0.10)
	# The barrier lifts for a few seconds, then drops for the next inspection.
	var cycle := fposmod(t, 9.0)
	var lift := clampf(minf(cycle - 6.0, 9.0 - cycle) * 2.0, 0.0, 1.0)
	l._blk(bx, y - 6, 2, 8, Color(0.20, 0.20, 0.22))
	for k in 12:
		var a := Vector2(bx + 1.0, y - 5.0) + Vector2(cos(-lift * 1.3), sin(-lift * 1.3)) * k * 2.5
		l._blk(a.x, a.y, 2.5, 1.5, Color(0.83, 0.30, 0.22) if k % 2 == 0 else Color(0.95, 0.92, 0.85))
	# A queue of lorries; the front one creeps through when the arm is up.
	for k in 4:
		var creep := lift * 6.0 if k == 0 else 0.0
		_lorry(l, bx - 48.0 - k * 34.0 + creep, y + 2.0, [Color(0.20, 0.30, 0.42), Color(0.45, 0.16, 0.13), Color(0.24, 0.32, 0.22), Color(0.50, 0.42, 0.20)][k], Color(0.30, 0.28, 0.24))
	# The inspector walks the line.
	var walk := bx - 50.0 + sin(t * 0.25) * 30.0
	_figure(l, walk, float(s.ground + 2), Color(0.20, 0.26, 0.34), t, true, 0.0)


static func _patrols(l: RegionLife, s: RegionScene, t: float) -> void:
	# The sandbagged post, a soldier behind it.
	var px := float(s.landmark_x) + 40.0
	var foot := float(s.ground + 2)
	_figure(l, px + 6.0, foot - 2.0, OLIVE, t, false, 0.0)
	for row in 2:
		for k in 5 - row:
			l._blk(px + row * 2.0 + k * 4.0, foot - 4.0 - row * 3.0, 4, 3, SANDBAG.darkened(0.15 * ((k + row) % 2)))
	# Armoured cars, roof lights flashing blue and red.
	for k in 2:
		var dir := 1.0 if k == 0 else -1.0
		var x := fposmod(t * 12.0 * dir + k * float(s.cols) * 0.5, float(s.cols) + 40.0) - 20.0
		var y := _lane_y(s, k)
		l._blk(x, y - 2, 26, 7, OLIVE)
		l._blk(x + 6, y - 6, 12, 4, OLIVE.lightened(0.1))
		l._blk(x + 9, y - 5, 6, 2, Color(0.08, 0.09, 0.10))
		var blue := sin(t * 9.0 + k) > 0.0
		l._blk(x + 11, y - 8, 2, 2, Color(0.30, 0.50, 1.0) if blue else Color(1.0, 0.25, 0.2))
		l._glow(x + 12, y - 8, 9.0, Color(0.30, 0.50, 1.0) if blue else Color(1.0, 0.25, 0.2), 0.55)
		for wx in [x + 3.0, x + 11.0, x + 19.0]:
			l._blk(wx, y + 4, 4, 3, Color(0.04, 0.04, 0.05))
	# A foot patrol in step.
	for k in 4:
		var x := fposmod(float(s.cols) * 0.2 + t * 7.0 + k * 6.0, float(s.cols) + 20.0) - 10.0
		_figure(l, x, foot + 2.0, OLIVE, t, true, 0.0)
