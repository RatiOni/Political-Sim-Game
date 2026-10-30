class_name RegionBake
extends RefCounted

## Paints the still parts of a `RegionScene` into one image, one image pixel
## per scene pixel. It is an evening scene on purpose — the control-room look
## is low light, and at night a town's condition shows in which windows are
## lit. Everything that moves is `RegionLife`'s.
##
## Cost: fills are rows and rects, never a per-pixel pass over the canvas,
## so a bake at ~800x200 stays in the tens of milliseconds.

const SKY_TOP := Color(0.025, 0.035, 0.07)
const SKY_LOW := Color(0.10, 0.12, 0.18)
const SKY_EMBER := Color(0.30, 0.13, 0.07)
const RIDGE_FAR := Color(0.15, 0.16, 0.22)
const RIDGE_NEAR := Color(0.08, 0.09, 0.11)
const SNOW := Color(0.62, 0.65, 0.72)
const SKYLINE := Color(0.07, 0.075, 0.095)
const LAND := Color(0.06, 0.075, 0.05)
const FIELD := Color(0.13, 0.12, 0.06)
const PINE := Color(0.035, 0.07, 0.045)
const PAVEMENT := Color(0.17, 0.165, 0.155)
const KERB := Color(0.30, 0.29, 0.27)
const ROAD := Color(0.075, 0.075, 0.085)
const DIRT := Color(0.16, 0.12, 0.08)
const MARKING := Color(0.55, 0.48, 0.26)
const WATER := Color(0.03, 0.06, 0.10)
const IRON := Color(0.09, 0.09, 0.10)
const LIT := Color(1.0, 0.76, 0.40)
const LIT_COOL := Color(0.78, 0.84, 0.90)
const BOARD := Color(0.20, 0.13, 0.08)
const DARK_GLASS := Color(0.05, 0.06, 0.08)
const ROOF := Color(0.24, 0.12, 0.09)
const GOLD := Color(0.89, 0.60, 0.23)
const ALARM := Color(0.83, 0.30, 0.22)
## Night walls: lit from the street, so quiet but readable.
const WALLS: Array[Color] = [
	Color(0.38, 0.35, 0.30), Color(0.30, 0.31, 0.33), Color(0.36, 0.29, 0.22),
	Color(0.30, 0.18, 0.14), Color(0.25, 0.26, 0.26),
]

const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


static func bake(s: RegionScene) -> Image:
	var img := Image.create_empty(s.cols, s.h, false, Image.FORMAT_RGBA8)
	s.rng.seed = hash([s.id, "bake"])
	_sky(img, s)
	var sky := img.get_data()
	_ridges(img, s)
	_skyline(img, s)
	_towers(img, s)
	_land(img, s)
	_landmark(img, s)
	var behind := img.get_data()
	for b in s.buildings:
		_building(img, s, b)
	s.front_top = _front_top(img, behind, s)
	_street(img, s)
	_foreground(img, s)
	if s.crane_at >= 0:
		_scaffold(img, s)
	if s.trouble > 0.45:
		_barricades(img, s)
	s.sky_mask = _sky_mask(img, sky, s)
	return img


## Where open sky remains in each column after everything is painted: the
## day grade turns exactly these pixels into day sky and nothing else.
## One pixel per column, value = sky bottom / height.
static func _sky_mask(img: Image, sky: PackedByteArray, s: RegionScene) -> Image:
	var done := img.get_data()
	var mask := Image.create_empty(s.cols, 1, false, Image.FORMAT_L8)
	for x in s.cols:
		var y := 0
		while y < s.horizon:
			var i := (y * s.cols + x) * 4
			if done[i] != sky[i] or done[i + 1] != sky[i + 1] or done[i + 2] != sky[i + 2]:
				break
			y += 1
		mask.set_pixel(x, 0, Color(float(y) / s.h, 0, 0))
	return mask


## Per column, the highest row the street buildings painted: anything the
## life layer draws behind them (the train on the viaduct) hides below it.
static func _front_top(img: Image, behind: PackedByteArray, s: RegionScene) -> PackedInt32Array:
	var done := img.get_data()
	var top := PackedInt32Array()
	top.resize(s.cols)
	for x in s.cols:
		var y := 0
		while y < s.ground:
			var i := (y * s.cols + x) * 4
			if done[i] != behind[i] or done[i + 1] != behind[i + 1] or done[i + 2] != behind[i + 2]:
				break
			y += 1
		top[x] = y
	return top


# --- primitives ----------------------------------------------------------

static func fill(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	var r := Rect2i(x, y, w, h).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x > 0 and r.size.y > 0:
		img.fill_rect(r, c)


static func dot(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func blend(img: Image, x: int, y: int, c: Color, a: float) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, img.get_pixel(x, y).lerp(c, a))


## Vertical gradient in bands, the seams ordered-dithered so it reads as a
## smooth fall of light, not as stripes.
static func gradient(img: Image, x: int, y0: int, w: int, y1: int, top: Color, low: Color, bands: int) -> void:
	var span := maxi(1, y1 - y0)
	for b in bands:
		var t := float(b) / float(maxi(1, bands - 1))
		var a := y0 + span * b / bands
		var z := y0 + span * (b + 1) / bands
		fill(img, x, a, w, z - a, top.lerp(low, t))
		if b + 1 < bands:
			var next := top.lerp(low, minf(1.0, t + 1.0 / float(bands - 1)))
			for dy in 2:
				for dx in range(0, w):
					if BAYER[((z - 2 + dy) % 4) * 4 + (dx % 4)] < 5 + dy * 5:
						dot(img, x + dx, z - 2 + dy, next)


# --- sky and distance ----------------------------------------------------

static func _sky(img: Image, s: RegionScene) -> void:
	var low := SKY_LOW.lerp(SKY_EMBER, s.trouble * 0.85)
	gradient(img, 0, 0, s.cols, s.horizon, SKY_TOP, low, 12)
	if s.trouble < 0.6:
		var mx := int(s.cols * (0.15 + s.roll(1) * 0.7))
		var my := int(s.horizon * 0.22)
		for dy in range(-9, 10):
			for dx in range(-9, 10):
				var d := Vector2(dx, dy).length()
				if d < 4.5:
					dot(img, mx + dx, my + dy, Color(0.88, 0.86, 0.78) if d < 3.6 or (dx + dy) % 3 != 0 else Color(0.70, 0.68, 0.62))
				elif d < 9.0:
					blend(img, mx + dx, my + dy, Color(0.5, 0.55, 0.65), 0.10 * (1.0 - (d - 4.5) / 4.5))


## Midpoint-displaced silhouettes: summits and saddles at every scale, which
## is what makes a ridge read as a mountain range and not a wall.
static func ridge(s: RegionScene, base: float, amp: float, rough: float) -> PackedFloat32Array:
	var n := 1
	while n < s.cols:
		n *= 2
	var ys := PackedFloat32Array()
	ys.resize(n + 1)
	ys[0] = base - s.rng.randf() * amp
	ys[n] = base - s.rng.randf() * amp
	var step := n
	var spread := amp
	while step > 1:
		var half := step / 2
		for i in range(half, n, step):
			ys[i] = (ys[i - half] + ys[i + half]) * 0.5 + s.rng.randf_range(-spread, spread)
		step = half
		spread *= rough
	return ys


static func _ridges(img: Image, s: RegionScene) -> void:
	var tall := s.land in [RegionScene.Land.HIGHLAND, RegionScene.Land.PASS]
	var amp := 0.34 if tall else (0.18 if s.land == RegionScene.Land.FOOTHILL else 0.10)
	if s.land == RegionScene.Land.COAST:
		amp = 0.05
	for layer in 2:
		var base := s.horizon - s.horizon * (0.18 if layer == 0 else 0.06)
		var ys := ridge(s, base, s.horizon * amp * (1.0 if layer == 0 else 0.55), 0.62)
		var tone := RIDGE_FAR if layer == 0 else RIDGE_NEAR
		for x in s.cols:
			var y := clampi(int(ys[x]), 0, s.horizon)
			fill(img, x, y, 1, s.horizon - y, tone)
			# Moonlit edge on the slopes that face up-left.
			if x > 0 and ys[x] < ys[x - 1]:
				dot(img, x, y, tone.lightened(0.35))
			# Snow on the summits only: a cap a few pixels deep, never a band.
			var snowline := base - s.horizon * amp * 0.62
			if tall and layer == 0 and ys[x] < snowline:
				var cap := mini(7, 1 + int((snowline - ys[x]) * 0.5))
				fill(img, x, y, 1, cap, SNOW.darkened(0.3 if ys[x] >= ys[maxi(0, x - 1)] else 0.0))


## A far town on the horizon: low blocks with a scatter of lit windows. It
## gives the picture depth, and its lights thin out with the economy.
static func _skyline(img: Image, s: RegionScene) -> void:
	var density := clampf(s.development * 0.7 + s.population * 0.45 + (0.15 if s.capital else 0.0), 0.1, 1.0)
	var x := 0
	while x < s.cols:
		var w := s.rng.randi_range(4, 14)
		var hgt := int(s.rng.randf_range(3.0, 8.0 + 22.0 * density * density))
		if s.rng.randf() < 0.3:
			hgt = s.rng.randi_range(1, 3)
		fill(img, x, s.horizon - hgt, w, hgt, SKYLINE)
		for wy in range(s.horizon - hgt + 2, s.horizon - 1, 3):
			for wx in range(x + 1, x + w - 1, 2):
				if s.rng.randf() < 0.18 * density * (1.0 - s.unemployment):
					dot(img, wx, wy, LIT.darkened(0.45))
		if hgt > 16 and s.rng.randf() < 0.3:
			fill(img, x + w / 2, s.horizon - hgt - 5, 1, 5, SKYLINE)
		x += w + (s.rng.randi_range(2, 10) if s.rng.randf() < 0.25 else 0)


## High-rises between the far skyline and the street, window grids lit by
## occupancy; some carry a crown and an aviation light.
static func _towers(img: Image, s: RegionScene) -> void:
	for tw in s.towers:
		var x := int(tw["x"])
		var w := int(tw["w"])
		var hgt := int(tw["h"])
		var top := s.ground - hgt
		var body := SKYLINE.lightened(0.10)
		fill(img, x, top, w, hgt, body)
		fill(img, x + w - 2, top, 2, hgt, body.darkened(0.3))
		for wy in range(top + 3, s.ground - 3, 4):
			for wx in range(x + 2, x + w - 3, 3):
				var lit := s.rng.randf() < 0.45 * (1.0 - s.unemployment) * (0.6 + s.development * 0.5)
				dot(img, wx, wy, LIT_COOL.darkened(0.2) if lit and s.rng.randf() < 0.3 else (LIT if lit else DARK_GLASS))
		if bool(tw["crown"]):
			fill(img, x + 2, top - 4, w - 4, 4, body.lightened(0.05))
			fill(img, x + w / 2, top - 14, 1, 10, IRON.lightened(0.2))
			s.beacons.append(Vector2i(x + w / 2, top - 14))


static func _land(img: Image, s: RegionScene) -> void:
	gradient(img, 0, s.horizon, s.cols, s.ground, LAND.darkened(0.3), LAND, 4)
	match s.land:
		RegionScene.Land.PLAIN, RegionScene.Land.TRADE:
			for row in range(s.horizon + 3, s.ground - 2, 3):
				var tone := FIELD if (row / 3) % 2 == 0 else FIELD.darkened(0.3)
				fill(img, 0, row, s.cols, 1, tone)
		RegionScene.Land.HIGHLAND, RegionScene.Land.PASS, RegionScene.Land.FOOTHILL:
			# Pines climbing the slope behind the town.
			for i in int(s.cols / 4):
				var px := s.rng.randi_range(0, s.cols)
				var py := s.rng.randi_range(s.horizon - 2, s.ground - 8)
				var ph := s.rng.randi_range(5, 10)
				for r in ph:
					fill(img, px - r / 3, py + r, 1 + 2 * (r / 3), 1, PINE.lightened(0.15 * s.rng.randf()))
		RegionScene.Land.INDUSTRY:
			# Gantries and tanks of the wider works on the skyline.
			for i in 4:
				var tx := s.rng.randi_range(0, s.cols)
				fill(img, tx, s.horizon - 12, 10, 12, SKYLINE.lightened(0.1))
				fill(img, tx + 1, s.horizon - 13, 8, 1, SKYLINE.lightened(0.25))
	if s.mill_at.x >= 0:
		var m := s.mill_at
		for r in 22:
			fill(img, m.x - r / 6, m.y - 22 + r, 1 + r / 3, 1, Color(0.14, 0.13, 0.12))


# --- the newsreel subject ---------------------------------------------------

## One landmark at the centre of frame, standing behind the street so the
## front row overlaps its foot. Floodlit stone, lit windows, a silhouette you
## could name from a newsreel still.
static func _landmark(img: Image, s: RegionScene) -> void:
	var cx := s.landmark_x
	var g := s.ground
	var stone := Color(0.46, 0.44, 0.40)
	var dark := Color(0.10, 0.10, 0.12)
	match s.landmark:
		"parliament":
			fill(img, cx - 84, g - 66, 168, 66, stone)
			fill(img, cx - 88, g - 70, 176, 5, stone.lightened(0.2))
			for c in range(cx - 80, cx + 80, 9):
				fill(img, c, g - 62, 4, 50, stone.lightened(0.25))
				fill(img, c + 3, g - 62, 1, 50, stone.darkened(0.25))
			fill(img, cx - 40, g - 92, 80, 22, stone.lightened(0.08))
			for c in range(cx - 36, cx + 36, 8):
				_window(img, s, c, g - 88, 3, 10, c * 7)
			_dome(img, cx, g - 92, 30, stone.lightened(0.15))
			fill(img, cx - 4, g - 128, 8, 8, stone.lightened(0.2))
			fill(img, cx, g - 140, 1, 12, IRON.lightened(0.4))
			s.flag_at = Vector2i(cx, g - 140)
			# Floodlight wash at the foot of the colonnade.
			for y in range(g - 66, g):
				for x in range(cx - 84, cx + 84, 1):
					if (x + y) % 3 == 0:
						blend(img, x, y, LIT, 0.10 * float(y - (g - 66)) / 66.0)
		"works":
			for k in 3:
				var sx := cx - 40 + k * 22
				fill(img, sx, g - 126, 9, 126, Color(0.30, 0.29, 0.28))
				fill(img, sx + 6, g - 126, 3, 126, Color(0.20, 0.19, 0.19))
				for band in [g - 120, g - 100]:
					fill(img, sx, band, 9, 2, ALARM.darkened(0.35))
			# A cooling tower: a waisted hyperbolic shell.
			var tx := cx + 62
			for y in 84:
				var k := float(y) / 84.0
				var half := int(26.0 - 10.0 * sin(k * PI * 0.85))
				fill(img, tx - half, g - 84 + y, half * 2, 1, Color(0.34, 0.33, 0.31).darkened(0.25 * k))
				fill(img, tx + half - 5, g - 84 + y, 5, 1, Color(0.22, 0.22, 0.22))
			fill(img, cx - 70, g - 40, 110, 40, Color(0.18, 0.18, 0.19))
			for wx in range(cx - 66, cx + 36, 7):
				fill(img, wx, g - 30, 4, 6, LIT.darkened(0.15) if s.works_running else DARK_GLASS)
		"lighthouse":
			for y in 96:
				var half := int(lerpf(5.0, 9.0, float(y) / 96.0))
				var band := (y / 12) % 2 == 0
				fill(img, cx - half, g - 96 + y, half * 2, 1, Color(0.80, 0.76, 0.68) if band else ALARM.darkened(0.2))
			fill(img, cx - 8, g - 108, 16, 12, IRON.lightened(0.2))
			fill(img, cx - 5, g - 106, 10, 8, LIT)
			fill(img, cx - 9, g - 110, 18, 2, IRON.lightened(0.35))
			s.beacons.append(Vector2i(cx - 1, g - 113))
		"watchtower":
			var top := s.searchlight_at.y
			for leg in [cx - 10, cx + 8]:
				fill(img, leg, top, 2, g - top, IRON.lightened(0.18))
			for y in range(top, g, 8):
				for d in 8:
					dot(img, cx - 9 + d * 17 / 8, y + d, IRON.lightened(0.12))
			fill(img, cx - 14, top - 14, 28, 14, IRON.lightened(0.22))
			fill(img, cx - 16, top - 16, 32, 2, KERB)
			fill(img, cx - 10, top - 10, 20, 4, LIT.darkened(0.3))
			for fx in range(0, s.cols, 9):
				fill(img, fx, g - 12, 1, 9, IRON.lightened(0.25))
			for wire in 3:
				fill(img, 0, g - 11 + wire * 3, s.cols, 1, IRON.lightened(0.12))
		"silos":
			for k in 4:
				var sx := cx - 52 + k * 26
				fill(img, sx, g - 92, 22, 92, Color(0.52, 0.50, 0.44))
				fill(img, sx + 16, g - 92, 6, 92, Color(0.38, 0.36, 0.32))
				for r in 8:   # conical cap, point upward
					var inset := 7 - r
					fill(img, sx + inset, g - 100 + r, 22 - 2 * inset, 1, Color(0.44, 0.42, 0.38))
			fill(img, cx + 54, g - 120, 14, 120, Color(0.40, 0.38, 0.34))
			fill(img, cx + 57, g - 112, 5, 5, LIT.darkened(0.2))
		"monastery":
			# A crag rising behind the town, the monastery seated on its crown.
			var crown := s.horizon - int(s.horizon * 0.25)
			var ys := ridge(s, float(crown) + 8.0, 6.0, 0.6)
			for x in range(cx - 120, cx + 120):
				if x < 0 or x >= s.cols:
					continue
				var k := absf(x - cx) / 120.0
				var y := int(lerpf(ys[x], float(g), k * k))
				fill(img, x, y, 1, g - y, RIDGE_NEAR.lightened(0.18))
				if x % 3 == 0:
					dot(img, x, y, RIDGE_NEAR.lightened(0.45))
			var top := int(ys[clampi(cx, 0, s.cols - 1)]) + 2
			fill(img, cx - 34, top - 26, 68, 26, stone)
			fill(img, cx - 6, top - 60, 12, 34, stone.lightened(0.05))
			for i in 8:
				var inset := (7 - i) * 3 / 4
				fill(img, cx - 6 + inset, top - 72 + i * 2, 12 - inset * 2, 2, ROOF)
			for c in range(cx - 28, cx + 28, 8):
				_window(img, s, c, top - 20, 3, 6, c * 3)
			_window(img, s, cx - 2, top - 50, 4, 7, 991)
		"viaduct":
			var deck := s.horizon - 20
			fill(img, 0, deck, s.cols, 4, stone.darkened(0.2))
			fill(img, 0, deck - 1, s.cols, 1, stone.lightened(0.1))
			for ax in range(0, s.cols, 34):
				fill(img, ax, deck + 4, 8, s.ground - deck - 4, stone.darkened(0.35))
				for r in 13:
					var w := int(sqrt(float(169 - r * r)))
					fill(img, ax + 8, deck + 4 + r, 26 - 2 * (13 - w), 1, stone.darkened(0.35))
		"clocktower":
			var th := mini(g - 26, 120)
			fill(img, cx - 12, g - th, 24, th, stone)
			fill(img, cx + 6, g - th, 6, th, stone.darkened(0.3))
			for i in 10:
				var inset := 9 - i
				fill(img, cx - 12 + inset, g - th - 20 + i * 2, 24 - 2 * inset, 2, ROOF)
			s.clock_at = Vector2i(cx, g - th + 18)
			_dome(img, cx, g - th + 27, 9, Color(0.90, 0.86, 0.72))
			for wy in range(g - th + 40, g - 10, 14):
				_window(img, s, cx - 2, wy, 4, 7, wy)
		"fortress":
			for x in range(cx - 130, cx + 130):
				if x < 0 or x >= s.cols:
					continue
				# A flat-crowned hill, so the walls have ground under all of them.
				var y := int(g - 30 - 40.0 * (1.0 - pow(absf(x - cx) / 130.0, 6.0)))
				fill(img, x, y, 1, g - y, LAND.lightened(0.12))
			var top := g - 68
			fill(img, cx - 70, top - 24, 140, 24, stone.darkened(0.1))
			fill(img, cx - 74, top, 150, 6, stone.darkened(0.35))   # footing
			for k in range(cx - 70, cx + 70, 8):
				fill(img, k, top - 28, 4, 4, stone.darkened(0.1))
			for tx in [cx - 74, cx - 8, cx + 62]:
				fill(img, tx, top - 48, 14, 48, stone)
				for k in range(tx, tx + 14, 4):
					fill(img, k, top - 52, 2, 4, stone)
				_window(img, s, tx + 5, top - 38, 3, 6, tx)


## A filled half-disc, lit on its left shoulder.
static func _dome(img: Image, cx: int, base: int, r: int, tone: Color) -> void:
	for y in r:
		var half := int(sqrt(float(r * r - (r - y) * (r - y))))
		fill(img, cx - half, base - r + y, half * 2, 1, tone.darkened(0.1 * float(y) / r))
		fill(img, cx - half, base - r + y, maxi(1, half / 3), 1, tone.lightened(0.15))


# --- buildings -----------------------------------------------------------

static func _building(img: Image, s: RegionScene, b: Dictionary) -> void:
	var kind := int(b["kind"])
	match kind:
		RegionScene.Build.CIVIC: _civic(img, s, b)
		RegionScene.Build.PLANT: _plant(img, s, b)
		_: _house(img, s, b)


static func _house(img: Image, s: RegionScene, b: Dictionary) -> void:
	var x := int(b["x"])
	var w := int(b["w"])
	var hgt := int(b["h"])
	var kind := int(b["kind"])
	var top := s.ground - hgt
	var wall: Color = WALLS[int(b["tint"])]
	if s.development < 0.35:
		wall = wall.lerp(Color(0.26, 0.22, 0.17), 0.6)
	fill(img, x, top, w, hgt, wall)
	fill(img, x + w - 3, top, 3, hgt, wall.darkened(0.35))      # shaded flank
	fill(img, x, s.ground - 3, w, 3, wall.darkened(0.25))       # plinth
	fill(img, x, top, w, 1, wall.lightened(0.18))               # cornice catch-light
	if s.trouble > 0.5 and s.roll(x, 7) < s.trouble - 0.3:
		# Posters and slogans on the wall.
		fill(img, x + 2 + int(s.roll(x, 8) * (w - 8)), s.ground - 12, 5, 4, ALARM.darkened(0.2))

	var roof_top := top
	if bool(b["flat"]):
		fill(img, x - 1, top - 2, w + 2, 2, wall.lightened(0.1))
		if kind == RegionScene.Build.BLOCK:
			if s.roll(x, 1) < 0.5:  # water tank on legs
				var tx := x + 4
				fill(img, tx, top - 10, 7, 6, IRON.lightened(0.2))
				fill(img, tx + 1, top - 4, 1, 2, IRON)
				fill(img, tx + 5, top - 4, 1, 2, IRON)
			var ax := x + w - 8
			fill(img, ax, top - 12, 1, 10, IRON.lightened(0.3))      # aerial
			fill(img, ax - 2, top - 10, 5, 1, IRON.lightened(0.3))
			fill(img, ax - 1, top - 7, 3, 1, IRON.lightened(0.3))
	else:
		var half := w / 2 + 1
		# Row i from the ridge down widens by a pixel each side; alternate
		# rows read as courses of tile.
		for i in half:
			var row_tone := ROOF.darkened(0.25) if i % 2 == 0 else ROOF
			var inset := half - 1 - i
			fill(img, x - 1 + inset, top - half + i, w + 2 - 2 * inset, 1, row_tone)
		fill(img, x + w / 2 - 1, top - half, 2, 1, ROOF.lightened(0.3))
		roof_top = top - half
	if kind == RegionScene.Build.CHURCH:
		var sx := x + w / 2 - 4
		fill(img, sx, top - 30, 8, 30, wall)
		fill(img, sx + 6, top - 30, 2, 30, wall.darkened(0.35))
		for i in 6:   # spire: narrow at the tip, widening down to the tower
			var inset := (5 - i) * 2 / 3
			fill(img, sx + inset, top - 42 + i * 2, 8 - inset * 2, 2, ROOF)
		fill(img, sx + 3, top - 50, 2, 8, GOLD.darkened(0.2))
		fill(img, sx + 1, top - 47, 6, 1, GOLD.darkened(0.2))
		_window(img, s, sx + 2, top - 24, 4, 6, x)   # the lit belfry
	if kind == RegionScene.Build.BARN:
		fill(img, x + w / 3, s.ground - 16, w / 3, 16, BOARD)
		for k in range(0, 16, 4):
			fill(img, x + w / 3, s.ground - 16 + k, w / 3, 1, BOARD.darkened(0.3))
		return
	if kind == RegionScene.Build.WAREHOUSE:
		fill(img, x + 4, s.ground - 14, w - 8, 14, IRON.lightened(0.15))
		for k in range(0, 14, 2):
			fill(img, x + 4, s.ground - 14 + k, w - 8, 1, IRON.lightened(0.05))
		_window_row(img, s, x, w, top + 4, x)
		return

	# Ground floor: a shopfront or a door with a step.
	if kind == RegionScene.Build.SHOP:
		var open := s.roll(x, 3) > s.unemployment * 1.8
		var sw := w - 6
		if open:
			fill(img, x + 3, s.ground - 12, sw, 9, LIT.darkened(0.1))
			for gx in range(x + 5, x + 3 + sw - 2, 4):     # goods in the window
				fill(img, gx, s.ground - 6, 2, 3, WALLS[int(s.roll(gx) * 5)].lightened(0.2))
			fill(img, x + 3 + sw / 2, s.ground - 12, 1, 9, wall.darkened(0.3))
		else:
			fill(img, x + 3, s.ground - 12, sw, 9, Color(0.20, 0.20, 0.21))
			for k in range(0, 9, 2):
				fill(img, x + 3, s.ground - 12 + k, sw, 1, Color(0.14, 0.14, 0.15))
		var awning := ALARM.darkened(0.3) if int(b["tint"]) % 2 == 0 else Color(0.18, 0.32, 0.26)
		for i in range(0, w, 4):
			fill(img, x + i, s.ground - 15, 2, 3, awning)
			fill(img, x + i + 2, s.ground - 15, 2, 3, awning.lightened(0.35))
		fill(img, x + 3, s.ground - 20, w - 6, 4, Color(0.10, 0.09, 0.08))
		for i in range(x + 5, x + w - 5, 2):                  # the sign's lettering
			if s.roll(i, 4) < 0.7:
				dot(img, i, s.ground - 18, LIT if open else KERB)
	else:
		var dx := x + w / 2 - 2
		fill(img, dx, s.ground - 10, 5, 10, BOARD.darkened(0.2))
		fill(img, dx + 1, s.ground - 9, 3, 1, LIT.darkened(0.4))   # fanlight
		fill(img, dx - 1, s.ground - 1, 7, 1, KERB)

	var storeys := int(b["storeys"])
	for st in storeys:
		var wy := s.ground - 18 - st * 10 - (4 if kind == RegionScene.Build.SHOP else 0)
		if wy < top + 3:
			break
		_window_row(img, s, x, w, wy, x * 31 + st)
		if kind == RegionScene.Build.BLOCK and st % 2 == 1:
			fill(img, x + 2, wy + 7, w - 5, 1, IRON.lightened(0.35))   # balcony rail
			for k in range(x + 2, x + w - 3, 3):
				dot(img, k, wy + 8, IRON.lightened(0.25))


static func _window_row(img: Image, s: RegionScene, x: int, w: int, wy: int, key: int) -> void:
	var step := 7
	var count := maxi(1, (w - 6) / step)
	var start := x + (w - 3 - count * step) / 2 + 2
	for i in count:
		_window(img, s, start + i * step, wy, 4, 6, key * 13 + i)


## One window, whose state is the town's condition in miniature: lit and
## glowing, dark, a blue television flicker (animated later), or boarded.
static func _window(img: Image, s: RegionScene, wx: int, wy: int, w: int, h: int, key: int) -> void:
	var r := s.roll(key, wx, wy)
	var boarded := s.unemployment * 0.85 + s.trouble * 0.2
	var dark := boarded + 0.22 + s.trouble * 0.35 - s.development * 0.18
	fill(img, wx - 1, wy + h, w + 2, 1, KERB.darkened(0.2))   # sill
	if r < boarded:
		fill(img, wx, wy, w, h, BOARD)
		fill(img, wx, wy + 1, w, 1, BOARD.lightened(0.2))
		fill(img, wx, wy + 4, w, 1, BOARD.lightened(0.2))
		return
	if r < dark:
		fill(img, wx, wy, w, h, DARK_GLASS)
		dot(img, wx, wy, DARK_GLASS.lightened(0.25))
		return
	var tone := LIT_COOL if s.roll(key, 1) < 0.18 else LIT.darkened(s.roll(key, 2) * 0.35)
	# A soft halo on the wall around a lit pane.
	for dy in range(-1, h + 1):
		for dx in range(-1, w + 1):
			blend(img, wx + dx, wy + dy, tone, 0.22)
	fill(img, wx, wy, w, h, tone)
	fill(img, wx + w / 2, wy, 1, h, tone.darkened(0.4))         # mullion
	if s.roll(key, 3) < 0.3:
		fill(img, wx, wy, w / 2, h, tone.darkened(0.55))        # drawn curtain
	if s.roll(key, 4) < 0.12:
		s.tv_windows.append(Vector2i(wx, wy))
	s.lit_windows.append(Vector2i(wx + w / 2, wy + h / 2))


static func _civic(img: Image, s: RegionScene, b: Dictionary) -> void:
	var x := int(b["x"])
	var w := int(b["w"])
	var top := s.ground - int(b["h"])
	var stone := Color(0.50, 0.49, 0.46)
	fill(img, x, top, w, int(b["h"]), stone)
	fill(img, x - 3, top, w + 6, 5, stone.lightened(0.2))
	for i in 12:
		var inset := int((11 - i) * (w + 6) / 24.0)
		fill(img, x - 3 + inset, top - 12 + i, w + 6 - 2 * inset, 1, stone.lightened(0.12 if i % 3 else 0.25))
	for c in range(x + 3, x + w - 3, 6):
		fill(img, c, top + 7, 3, int(b["h"]) - 15, stone.lightened(0.28))
		fill(img, c + 2, top + 7, 1, int(b["h"]) - 15, stone.darkened(0.2))
	for c in range(x + 6, x + w - 6, 6):
		_window(img, s, c, top + 12, 2, 8, c)
	for st in 4:
		fill(img, x - 2 - st * 2, s.ground - 2 - st * 2, w + 4 + st * 4, 2, stone.darkened(0.1 * st))
	fill(img, x + w / 2 - 3, s.ground - 14, 7, 12, LIT.darkened(0.35))
	fill(img, x + w / 2, top - 30, 1, 20, IRON.lightened(0.3))          # flagpole
	# Banners either side of the door.
	for bx in [x + 6, x + w - 9]:
		fill(img, bx, top + 8, 3, 14, GOLD.darkened(0.35))


static func _plant(img: Image, s: RegionScene, b: Dictionary) -> void:
	var x := int(b["x"])
	var w := int(b["w"])
	var top := s.ground - int(b["h"])
	var body := Color(0.16, 0.16, 0.17)
	fill(img, x, top, w, int(b["h"]), body)
	for i in range(0, w, 12):
		for j in 8:
			fill(img, x + i + j, top - 8 + j, 1, 8 - j, Color(0.26, 0.26, 0.27))
		fill(img, x + i + 7, top - 7, 1, 7, LIT.darkened(0.5) if s.works_running else DARK_GLASS)
	for k in 3:
		var sx := x + 12 + k * 24
		fill(img, sx, top - 30, 6, 32, Color(0.28, 0.27, 0.26))
		fill(img, sx + 4, top - 30, 2, 32, Color(0.20, 0.19, 0.19))
		for band in [top - 26, top - 18]:
			fill(img, sx, band, 6, 1, ALARM.darkened(0.4))
	for wx in range(x + 4, x + w - 6, 7):
		fill(img, wx, top + 12, 5, 7, LIT.darkened(0.15) if s.works_running else DARK_GLASS)
		if s.works_running:
			s.lit_windows.append(Vector2i(wx + 2, top + 15))
	# Pipework and a tank beside the shed.
	fill(img, x - 10, s.ground - 18, 9, 18, Color(0.22, 0.22, 0.23))
	fill(img, x - 10, s.ground - 19, 9, 1, KERB)
	fill(img, x - 2, top + 6, 2, int(b["h"]) - 6, IRON.lightened(0.2))


# --- street and foreground -----------------------------------------------

static func _street(img: Image, s: RegionScene) -> void:
	fill(img, 0, s.ground, s.cols, s.road_top - s.ground, PAVEMENT)
	for jx in range(0, s.cols, 8):
		fill(img, jx, s.ground, 1, s.road_top - s.ground, PAVEMENT.darkened(0.25))
	fill(img, 0, s.road_top - 1, s.cols, 1, KERB)
	var surface := ROAD if s.paved else DIRT
	fill(img, 0, s.road_top, s.cols, s.road_h, surface)
	var mid := s.road_top + s.road_h / 2
	if s.paved:
		for dx in range(4, s.cols, 18):
			fill(img, dx, mid, 9, 1, MARKING)
		for mx in range(30, s.cols, 110):               # drains
			fill(img, mx, s.road_top + 2, 4, 1, IRON)
	else:
		for rx in range(0, s.cols, 6):
			fill(img, rx, mid - 3, 4, 1, DIRT.darkened(0.3))
			fill(img, rx + 3, mid + 3, 4, 1, DIRT.darkened(0.3))
	fill(img, 0, s.front, s.cols, 2, KERB)
	# Lamp posts, benches and bins along the pavement.
	for lx in s.lamps:
		fill(img, lx, s.ground - 26, 1, 26, IRON.lightened(0.25))
		fill(img, lx, s.ground - 26, 5, 1, IRON.lightened(0.25))
		fill(img, lx + 3, s.ground - 25, 3, 2, IRON.lightened(0.45))
		if s.roll(lx, 9) < 0.3:
			fill(img, lx + 8, s.road_top - 4, 8, 1, BOARD.lightened(0.2))
			fill(img, lx + 8, s.road_top - 3, 1, 2, IRON)
			fill(img, lx + 15, s.road_top - 3, 1, 2, IRON)
		elif s.roll(lx, 10) < 0.25:
			fill(img, lx + 6, s.road_top - 5, 3, 4, Color(0.14, 0.20, 0.16))
	# Old towns keep wooden poles and a sagging wire.
	if not s.paved:
		var poles: Array[int] = []
		for px in range(20, s.cols, 64):
			poles.append(px)
			fill(img, px, s.ground - 34, 2, 34, BOARD)
			fill(img, px - 4, s.ground - 33, 10, 1, BOARD)
		for i in poles.size() - 1:
			var a := poles[i] + 1
			var z := poles[i + 1] + 1
			for wx in range(a, z):
				var t := float(wx - a) / float(z - a)
				dot(img, wx, s.ground - 33 + int(6.0 * 4.0 * t * (1.0 - t)), IRON.lightened(0.15))


static func _foreground(img: Image, s: RegionScene) -> void:
	if s.water_top < 0:
		gradient(img, 0, s.front + 2, s.cols, s.h, LAND, LAND.darkened(0.5), 4)
		for i in int(s.cols / 5):
			var gx := s.rng.randi_range(0, s.cols)
			var gy := s.rng.randi_range(s.front + 3, s.h - 1)
			fill(img, gx, gy, 1, 2, LAND.lightened(0.25))
		for fx in range(0, s.cols, 5):                 # a low fence
			fill(img, fx, s.front + 3, 1, 5, BOARD.darkened(0.2))
		fill(img, 0, s.front + 4, s.cols, 1, BOARD.darkened(0.3))
		return
	fill(img, 0, s.front + 2, s.cols, s.water_top - s.front - 2, KERB.darkened(0.35))
	gradient(img, 0, s.water_top, s.cols, s.h, WATER.lightened(0.08), WATER, 5)
	if s.land == RegionScene.Land.BASIN:
		for rx in range(0, s.cols, 4):                 # embankment railing
			fill(img, rx, s.front - 5, 1, 4, IRON.lightened(0.3))
		fill(img, 0, s.front - 5, s.cols, 1, IRON.lightened(0.35))
	else:
		for px in range(40, s.cols, 90):               # pier piles
			fill(img, px, s.water_top - 1, 30, 2, BOARD)
			for k in range(px, px + 30, 7):
				fill(img, k, s.water_top + 1, 2, 8, BOARD.darkened(0.4))


static func _scaffold(img: Image, s: RegionScene) -> void:
	var x := s.crane_at
	var top := s.ground - 52
	for row in range(0, 52, 8):
		fill(img, x, top + row, 26, 1, GOLD.darkened(0.45))
	for col in [x, x + 12, x + 25]:
		fill(img, col, top, 1, 52, GOLD.darkened(0.45))
	fill(img, x + 14, top - 34, 3, 34, GOLD.darkened(0.3))      # crane mast
	for k in range(0, 34, 4):
		dot(img, x + 15, top - 34 + k, GOLD.darkened(0.55))


static func _barricades(img: Image, s: RegionScene) -> void:
	var bars := int(lerpf(1.0, 4.0, s.trouble))
	for i in bars:
		var bx := 30 + i * int(s.cols / (bars + 1))
		var y := s.road_top + 2
		for t in 3:                                      # a stack of tyres
			fill(img, bx + t * 5, y + 6, 5, 4, Color(0.05, 0.05, 0.05))
			dot(img, bx + t * 5 + 2, y + 7, Color(0.15, 0.15, 0.15))
		fill(img, bx - 2, y + 3, 20, 2, BOARD.lightened(0.1))
		fill(img, bx + 4, y, 2, 6, BOARD)
		fill(img, bx + 10, y + 1, 9, 2, ALARM.darkened(0.15))
