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
## Architectural linework: pale dressed stone for copings and string
## courses, near-black for the shadow under a cornice. Both sit in a
## different palette band from any wall, so the line survives the converter.
const TRIM := Color(0.62, 0.58, 0.50)
const SHADOW := Color(0.03, 0.03, 0.035)
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
	_land(img, s)
	# The viaduct stands far back: the middle distance passes in front of it.
	var far_landmark := s.landmark == "viaduct"
	if far_landmark:
		_landmark(img, s)
	_mid(img, s)
	_towers(img, s)
	_harbour(img, s)
	if not far_landmark:
		_landmark(img, s)
	var behind := img.get_data()
	for b in s.buildings:
		_building(img, s, b)
	_chimney_stacks(img, s)
	s.front_top = _front_top(img, behind, s)
	_street(img, s)
	_foreground(img, s)
	if s.crane_at >= 0:
		_scaffold(img, s)
	if s.trouble > 0.45:
		_barricades(img, s)
	_reflections(img, s)
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


## The far skyline on the horizon: the most distant layer, sparse and dark —
## flat silhouettes with setbacks and masts, a few lights. Its lights thin
## out with the economy.
static func _skyline(img: Image, s: RegionScene) -> void:
	var density := _density(s)
	var tone := SKYLINE.darkened(0.15)
	var x := 0
	while x < s.cols:
		var w := s.rng.randi_range(5, 16)
		var hgt := int(s.rng.randf_range(3.0, 8.0 + 22.0 * density * density))
		if s.rng.randf() < 0.3:
			hgt = s.rng.randi_range(1, 3)
		var top := s.horizon - hgt
		fill(img, x, top, w, hgt, tone)
		if hgt > 12 and w > 8 and s.rng.randf() < 0.5:   # a setback crown
			fill(img, x + 2, top - 4, w - 4, 4, tone)
			top -= 4
		if hgt > 10 and s.rng.randf() < 0.35:            # a mast
			fill(img, x + w / 2, top - 7, 1, 7, tone)
		for wy in range(s.horizon - hgt + 2, s.horizon - 1, 3):
			for wx in range(x + 1, x + w - 2, 3):
				if s.rng.randf() < 0.14 * density * (1.0 - s.unemployment):
					fill(img, wx, wy, 2, 1, LIT.darkened(0.5))
		x += w + (s.rng.randi_range(2, 10) if s.rng.randf() < 0.25 else 0)


static func _density(s: RegionScene) -> float:
	return clampf(s.development * 0.7 + s.population * 0.45 + (0.15 if s.capital else 0.0), 0.1, 1.0)


## Tones for the converter's glyph classes (luma x gain 1.35): above ~0.13
## a cell prints solid, 0.09..0.13 as a 2x2 point, darker as a dot or
## nothing. Middle-distance masses sit in the point band, so they print as a
## dithered grid; their linework is lifted into the solid band.
const MID_BODY := Color(0.09, 0.09, 0.105)
const MID_LINE := Color(0.30, 0.30, 0.33)
const MID_GLASS := Color(0.025, 0.028, 0.035)


static func _even(x: int) -> int:
	return x - (x & 1)


## The middle distance: a row of silhouettes standing on the building line,
## between the far skyline and the street, printed as a dot grid with crisp
## roof lines. Blocks and water towers in a town; low gables in the country.
static func _mid(img: Image, s: RegionScene) -> void:
	var urban := s.land in [RegionScene.Land.BASIN, RegionScene.Land.INDUSTRY, RegionScene.Land.TRADE,
		RegionScene.Land.COAST, RegionScene.Land.FRONTIER]
	var density := _density(s)
	var x := s.rng.randi_range(0, 12)
	while x < s.cols:
		var w := s.rng.randi_range(12, 30) if urban else s.rng.randi_range(10, 18)
		var hgt := int(s.rng.randf_range(18.0, 26.0 + 34.0 * density)) if urban else s.rng.randi_range(12, 20)
		hgt = mini(hgt, s.ground - s.horizon + 30)
		var top := s.ground - hgt
		fill(img, x, top, w, hgt, MID_BODY)
		if urban:
			fill(img, x - 1, top - 2, w + 2, 2, MID_LINE)            # roof line
			if s.rng.randf() < 0.35:                                # water tower
				var tx := _even(x + s.rng.randi_range(2, maxi(2, w - 9)))
				fill(img, tx, top - 10, 8, 6, MID_LINE)
				fill(img, tx + 2, top - 12, 4, 2, MID_LINE)
				fill(img, tx, top - 4, 2, 2, MID_LINE)
				fill(img, tx + 6, top - 4, 2, 2, MID_LINE)
			elif s.rng.randf() < 0.4:                              # mast
				fill(img, _even(x + w - 6), top - 12, 2, 10, MID_LINE)
				fill(img, _even(x + w - 8), top - 9, 6, 1, MID_LINE)
			for wy in range(top + 3, s.ground - 4, 5):
				for wx in range(_even(x + 2), x + w - 3, 4):
					if s.rng.randf() < 0.12 * density * (1.0 - s.unemployment):
						fill(img, wx, wy, 2, 3, LIT.darkened(0.3))
		else:
			var half := w / 2 + 1
			for i in half:
				var inset := half - 1 - i
				fill(img, x - 1 + inset, top - half + i, w + 2 - 2 * inset, 1, MID_BODY)
				fill(img, x - 1 + inset, top - half + i, 2, 1, MID_LINE)   # the lit slope
			if s.rng.randf() < 0.3:
				fill(img, _even(x + w / 3), top + 4, 2, 3, LIT.darkened(0.3))
		x += w + (s.rng.randi_range(6, 30) if s.rng.randf() < (0.3 if urban else 0.55) else s.rng.randi_range(0, 3))


## High-rises between the far skyline and the street: slabs printed as a dot
## grid, edged with crisp parapets and setback ledges, carrying a dense grid
## of window cells — most dark, some lit — and on some a mast and an
## aviation light.
static func _towers(img: Image, s: RegionScene) -> void:
	var lit_p := 0.40 * (1.0 - s.unemployment) * (0.6 + s.development * 0.5)
	for tw in s.towers:
		var x := _even(int(tw["x"]))
		var w := int(tw["w"]) + (int(tw["w"]) & 1)
		var hgt := int(tw["h"])
		var top := s.ground - hgt
		# Setback: the upper third steps in, if the tower is tall enough.
		var step_y := top + hgt / 3 if hgt > 50 and w > 14 else top
		var inset := 2 if step_y > top else 0
		fill(img, x, step_y, w, s.ground - step_y, MID_BODY)
		fill(img, x + inset, top, w - inset * 2, step_y - top, MID_BODY)
		if step_y > top:
			fill(img, x - 1, step_y - 2, w + 2, 2, MID_LINE)             # ledge at the setback
		fill(img, x + inset - 1, top - 2, w - inset * 2 + 2, 2, MID_LINE)   # parapet
		fill(img, x + inset, top, 2, step_y - top, MID_LINE.darkened(0.2))   # moonlit edge
		fill(img, x, step_y, 2, s.ground - step_y, MID_LINE.darkened(0.2))
		for wy in range(top + 2, s.ground - 4, 5):
			var l := x + (inset if wy < step_y else 0) + 4
			var r := x + w - (inset if wy < step_y else 0) - 2
			for wx in range(l, r, 4):
				var rect := Rect2i(wx, wy, 2, 3)
				if s.rng.randf() < lit_p:
					fill(img, wx, wy, 2, 3, LIT_COOL.darkened(0.1) if s.rng.randf() < 0.3 else LIT)
					if s.rng.randf() < 0.08:
						s.blink_lit.append(rect)
				else:
					fill(img, wx, wy, 2, 3, MID_GLASS)
					if s.rng.randf() < 0.03:
						s.blink_dark.append(rect)
		var mid := _even(x + w / 2)
		if bool(tw["crown"]):
			fill(img, mid - 4, top - 6, 8, 4, MID_LINE.darkened(0.2))         # plant room
			fill(img, mid, top - 18, 2, 12, MID_LINE)                         # mast
			fill(img, mid - 2, top - 13, 6, 1, MID_LINE)
			s.beacons.append(Vector2i(mid, top - 19))
		elif s.rng.randf() < 0.5:
			fill(img, x + inset + 2, top - 6, 6, 4, MID_LINE.darkened(0.2))   # stair hut
			fill(img, _even(x + w - inset - 4), top - 10, 2, 8, MID_LINE)     # aerial
			fill(img, x + w - inset - 7, top - 8, 6, 1, MID_LINE)


## Harbour cranes standing behind the waterfront: the coast's working skyline.
static func _harbour(img: Image, s: RegionScene) -> void:
	if s.land != RegionScene.Land.COAST:
		return
	var steel := IRON.lightened(0.32)
	for k in 2:
		var x := int(s.cols * (0.18 + 0.52 * k + s.rng.randf() * 0.12))
		var g := s.ground
		var deck := g - 58
		for leg in [x, x + 16]:
			fill(img, leg, deck, 2, g - deck, steel)
		for y in range(deck + 6, g, 10):                # cross bracing
			for d in 8:
				dot(img, x + 2 + d * 2, y + d, steel)
		fill(img, x - 2, deck, 22, 3, steel)            # portal beam
		fill(img, x + 2, deck - 10, 12, 10, steel)      # machinery house
		fill(img, x + 4, deck - 7, 3, 2, LIT.darkened(0.2))
		var boom := deck - 12
		fill(img, x - 34, boom, 76, 2, steel)           # the boom
		for bx in range(x - 32, x + 40, 4):             # lattice under it
			dot(img, bx, boom + 2, steel)
			dot(img, bx + 1, boom + 3, steel)
		fill(img, x + 7, boom - 16, 2, 16, steel)       # A-frame
		for d in 16:                                    # stays to the boom ends
			dot(img, x + 7 - d * 41 / 16, boom - 16 + d, steel)
			dot(img, x + 8 + d * 33 / 16, boom - 16 + d, steel)
		fill(img, x - 26, boom + 2, 1, 22, steel)       # hoist cable
		fill(img, x - 28, boom + 24, 5, 3, steel)
		s.beacons.append(Vector2i(x + 7, boom - 17))


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
			# Far off, so it prints as a dot grid; its coping, piers' lit
			# faces and arch rings are the crisp lines.
			var deck := s.horizon - 20
			var body := Color(0.095, 0.09, 0.085)
			var line := Color(0.34, 0.32, 0.29)
			fill(img, 0, deck, s.cols, 6, body)
			fill(img, 0, deck - 2, s.cols, 2, line)                           # coping
			for px in range(0, s.cols, 6):                                     # parapet posts
				fill(img, px, deck - 4, 2, 2, line)
			# Two tiers of round arches on piers every 34 px, the spandrels
			# solid above each curve and open below it.
			var tier2 := deck + 30
			for ax in range(0, s.cols, 34):
				fill(img, ax, deck + 6, 8, s.ground - deck - 6, body)
				fill(img, ax, deck + 6, 2, s.ground - deck - 6, line.darkened(0.25))
				for top in [deck + 6, tier2 + 3]:
					for dx in 26:
						var off := float(dx) - 12.5
						var drop := 13 - int(sqrt(maxf(0.0, 169.0 - off * off)))
						fill(img, ax + 8 + dx, top, 1, 3 + drop, body)
						fill(img, ax + 8 + dx, top + 3 + drop, 1, 2, line.darkened(0.15))   # the arch ring
			fill(img, 0, tier2, s.cols, 3, body)                               # the lower deck
			fill(img, 0, tier2, s.cols, 2, line.darkened(0.15))
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
			# The hill prints as a dark dot grid with a lit crest, so the
			# walls stand on it instead of on a flat grey mound.
			var hill := Color(0.08, 0.095, 0.065)
			for x in range(cx - 130, cx + 130):
				if x < 0 or x >= s.cols:
					continue
				# A flat-crowned hill, so the walls have ground under all of them.
				var y := int(g - 30 - 40.0 * (1.0 - pow(absf(x - cx) / 130.0, 6.0)))
				fill(img, x, y, 1, g - y, hill)
				fill(img, x, y, 1, 2, LAND.lightened(0.28))
				if (x * 7) % 23 < 2 and y < g - 34:                 # scrub on the slope
					fill(img, x, y + 5 + (x * 13) % 9, 2, 2, PINE.lightened(0.2))
			for k in 6:                                              # the switchback path up
				var py := g - 34 - k * 6
				var px0 := cx - 100 + (k % 2) * 30 + k * 6
				fill(img, px0, py, 34, 1, LAND.lightened(0.22))
			var top := g - 68
			var wall_c := stone.darkened(0.1)
			fill(img, cx - 70, top - 24, 140, 24, wall_c)
			fill(img, cx - 74, top, 150, 6, stone.darkened(0.35))   # footing
			fill(img, cx - 70, top - 24, 140, 2, SHADOW)             # shadow under the wall-walk
			for k in range(cx - 70, cx + 70, 8):
				fill(img, k, top - 28, 4, 4, wall_c)
			for k in range(cx - 62, cx + 62, 12):                   # arrow slits
				fill(img, k, top - 17, 2, 6, SHADOW)
			fill(img, cx - 34, top - 14, 8, 14, SHADOW)              # the gate
			fill(img, cx - 33, top - 16, 6, 2, SHADOW)
			for tx in [cx - 74, cx - 8, cx + 62]:
				fill(img, tx, top - 48, 14, 48, stone)
				fill(img, tx + 11, top - 48, 3, 48, stone.darkened(0.3))
				fill(img, tx - 1, top - 50, 16, 2, TRIM)
				for k in range(tx, tx + 14, 4):
					fill(img, k, top - 54, 2, 4, stone)
				_window(img, s, tx + 5, top - 38, 3, 6, tx)
				fill(img, tx + 5, top - 22, 2, 5, SHADOW)


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
	fill(img, x, top, 1, hgt, wall.lightened(0.14))             # moonlit edge
	fill(img, x + w - 3, top, 3, hgt, wall.darkened(0.35))      # shaded flank
	fill(img, x, s.ground - 3, w, 3, wall.darkened(0.25))       # plinth
	if s.trouble > 0.5 and s.roll(x, 7) < s.trouble - 0.3:
		# Posters and slogans on the wall.
		fill(img, x + 2 + int(s.roll(x, 8) * (w - 8)), s.ground - 12, 5, 4, ALARM.darkened(0.2))

	if bool(b["flat"]):
		# Parapet: a pale coping overhanging a pixel, its shadow on the wall.
		fill(img, x - 1, top - 3, w + 2, 2, TRIM)
		fill(img, x, top - 1, w, 1, wall.darkened(0.1))
		fill(img, x, top, w, 2, SHADOW)
		_roof_kit(img, s, x, w, top - 3, kind)
	else:
		var half := w / 2 + 1
		# Row i from the ridge down widens by a pixel each side; alternate
		# rows read as courses of tile, the left slope catching the moon.
		for i in half:
			var row_tone := ROOF.darkened(0.25) if i % 2 == 0 else ROOF
			var inset := half - 1 - i
			fill(img, x - 1 + inset, top - half + i, w + 2 - 2 * inset, 1, row_tone)
			dot(img, x - 1 + inset, top - half + i, ROOF.lightened(0.3))
		fill(img, x + w / 2 - 1, top - half, 2, 1, ROOF.lightened(0.3))
		fill(img, x - 1, top, w + 2, 1, ROOF.darkened(0.55))      # eaves shadow
	if kind == RegionScene.Build.CHURCH:
		var sx := x + w / 2 - 4
		fill(img, sx, top - 30, 8, 30, wall)
		fill(img, sx, top - 30, 1, 30, wall.lightened(0.14))
		fill(img, sx + 6, top - 30, 2, 30, wall.darkened(0.35))
		fill(img, sx - 1, top - 31, 10, 1, TRIM)
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
		fill(img, x + 3, s.ground - 15, w - 6, 1, wall.lightened(0.2))   # lintel
		_window_row(img, s, x, w, top + 4, x, 3, 3, 5)
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
		fill(img, dx - 1, s.ground - 11, 7, 1, wall.lightened(0.2))   # door hood
		fill(img, dx, s.ground - 10, 5, 10, BOARD.darkened(0.2))
		fill(img, dx + 1, s.ground - 9, 3, 1, LIT.darkened(0.4))   # fanlight
		fill(img, dx - 1, s.ground - 1, 7, 1, KERB)

	# Upper floors: a dense grid of window cells for blocks, sashes for
	# houses, each storey divided by a string course.
	var block := kind == RegionScene.Build.BLOCK
	var storeys := int(b["storeys"])
	for st in storeys:
		var wy := s.ground - 18 - st * 10 - (4 if kind == RegionScene.Build.SHOP else 0)
		if wy < top + 3:
			break
		if st > 0:
			fill(img, x, wy + 7, w - 3, 2, wall.lerp(TRIM, 0.6))   # string course
		if block:
			_window_row(img, s, x, w, wy, x * 31 + st, 2, 5, 4)
		else:
			_window_row(img, s, x, w, wy, x * 31 + st, 4, 5, 8)
	if block and storeys >= 3 and w >= 26 and s.roll(x, 11) < 0.6:
		_fire_escape(img, s, x + (w - 12) / 2 + (3 if s.roll(x, 12) < 0.5 else -3), top, storeys)


## Roof furniture on a flat roof: what makes a block read as a city block.
static func _roof_kit(img: Image, s: RegionScene, x: int, w: int, roof: int, kind: int) -> void:
	var steel := IRON.lightened(0.3)
	if kind != RegionScene.Build.BLOCK:
		if w > 20:                                                # vent boxes
			fill(img, x + 3, roof - 2, 4, 2, IRON.lightened(0.2))
			fill(img, x + w - 9, roof - 3, 3, 3, IRON.lightened(0.2))
		return
	if s.roll(x, 1) < 0.55:
		# A timber water tower: legs, a hooped barrel, a conical cap.
		var tx := x + 3 + int(s.roll(x, 13) * maxf(0.0, w - 16))
		fill(img, tx + 1, roof - 4, 1, 4, IRON)
		fill(img, tx + 6, roof - 4, 1, 4, IRON)
		fill(img, tx + 1, roof - 3, 6, 1, IRON)
		fill(img, tx, roof - 11, 8, 7, Color(0.30, 0.22, 0.16))
		fill(img, tx, roof - 11, 1, 7, Color(0.40, 0.31, 0.22))
		fill(img, tx, roof - 9, 8, 1, IRON)
		fill(img, tx, roof - 6, 8, 1, IRON)
		fill(img, tx + 1, roof - 13, 6, 2, Color(0.22, 0.17, 0.13))
		fill(img, tx + 3, roof - 14, 2, 1, Color(0.22, 0.17, 0.13))
	else:
		# A stair hut with a dark door.
		var hx := x + 3
		fill(img, hx, roof - 6, 9, 6, IRON.lightened(0.24))
		fill(img, hx - 1, roof - 7, 11, 1, IRON.lightened(0.36))
		fill(img, hx + 2, roof - 4, 3, 4, DARK_GLASS)
	# Chimney stacks and an aerial on the far end.
	if s.roll(x, 14) < 0.6:
		var cx := x + w / 2 + 1
		fill(img, cx, roof - 5, 3, 5, Color(0.30, 0.18, 0.14))
		fill(img, cx - 1, roof - 6, 5, 1, Color(0.40, 0.26, 0.20))
	var ax := x + w - 7
	fill(img, ax, roof - 13, 1, 13, steel)
	fill(img, ax - 3, roof - 11, 7, 1, steel)
	fill(img, ax - 2, roof - 8, 5, 1, steel)


## An iron fire escape down the face of a block: a landing at every floor
## above the street, a railing, a ladder slanting down to the next.
static func _fire_escape(img: Image, s: RegionScene, fx: int, top: int, storeys: int) -> void:
	var iron := IRON
	var rail := IRON.lightened(0.04)
	for st in range(1, storeys):
		var py := s.ground - 18 - st * 10 + 7
		if py - 4 < top + 2:
			break
		fill(img, fx, py, 12, 2, iron)                       # landing
		fill(img, fx, py - 4, 12, 1, rail)                   # railing
		for k in [0, 5, 11]:
			fill(img, fx + k, py - 4, 1, 4, rail)
		if st > 1:                                           # ladder to the landing below
			for d in 9:
				fill(img, fx + 1 + d, py + 2 + d, 2, 1, rail)
	# The drop ladder hangs above the pavement.
	fill(img, fx + 9, s.ground - 18, 1, 6, rail)
	fill(img, fx + 11, s.ground - 18, 1, 6, rail)


static func _window_row(img: Image, s: RegionScene, x: int, w: int, wy: int, key: int,
		ww: int = 4, wh: int = 6, step: int = 7) -> void:
	var count := maxi(1, (w - 6) / step)
	var start := _even(x + (w - 3 - count * step) / 2 + (step - ww) / 2 + 1)
	for i in count:
		_window(img, s, start + i * step, wy, ww, wh, key * 13 + i)


## One window, whose state is the town's condition in miniature: lit, dark,
## a blue television flicker (animated later), or boarded. No halo: the cell
## is crisp, and the lit ones carry the night on their own.
static func _window(img: Image, s: RegionScene, wx: int, wy: int, w: int, h: int, key: int) -> void:
	var r := s.roll(key, wx, wy)
	var boarded := s.unemployment * 0.85 + s.trouble * 0.2
	var dark := boarded + 0.22 + s.trouble * 0.35 - s.development * 0.18
	fill(img, wx - 1, wy + h, w + 2, 1, KERB.darkened(0.2))   # sill
	if r < boarded:
		fill(img, wx, wy, w, h, BOARD)
		fill(img, wx, wy + 1, w, 1, BOARD.lightened(0.2))
		fill(img, wx, wy + h - 2, w, 1, BOARD.lightened(0.2))
		return
	if r < dark:
		fill(img, wx, wy, w, h, DARK_GLASS)
		fill(img, wx, wy, 1, 1, DARK_GLASS.lightened(0.3))       # a glint of moon
		if s.roll(key, 5) < 0.05:
			s.blink_dark.append(Rect2i(wx, wy, w, h))
		return
	var tone := LIT_COOL if s.roll(key, 1) < 0.18 else LIT.darkened(s.roll(key, 2) * 0.35)
	fill(img, wx, wy, w, h, tone)
	fill(img, wx - 1, wy - 1, w + 2, 1, tone.darkened(0.75))   # lintel shadow
	if w >= 4:
		fill(img, wx + w / 2, wy, 1, h, tone.darkened(0.4))     # mullion
	fill(img, wx, wy + h / 2, w, 1, tone.darkened(0.3))          # transom
	if s.roll(key, 3) < 0.3:
		fill(img, wx, wy, maxi(1, w / 2), h, tone.darkened(0.55))   # drawn curtain
	if w >= 4 and s.roll(key, 4) < 0.12:
		s.tv_windows.append(Vector2i(wx, wy))
	elif s.roll(key, 6) < 0.08:
		s.blink_lit.append(Rect2i(wx, wy, w, h))
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

## Brick stacks on the pitched roofs, where `RegionLife` puffs the smoke.
static func _chimney_stacks(img: Image, s: RegionScene) -> void:
	for c in s.chimneys:
		if String(c["kind"]) != "house":
			continue
		var cx := int(c["x"])
		var cy := int(c["y"])
		fill(img, cx - 1, cy, 4, 8, Color(0.30, 0.18, 0.14))
		fill(img, cx - 1, cy, 1, 8, Color(0.40, 0.26, 0.20))
		fill(img, cx - 2, cy - 1, 6, 2, Color(0.22, 0.14, 0.11))
		fill(img, cx, cy - 3, 1, 2, Color(0.30, 0.18, 0.14))      # a chimney pot


## Trams run on the capital's and the trading towns' paved streets.
static func _has_tram(s: RegionScene) -> bool:
	return s.paved and (s.capital or s.land in [RegionScene.Land.TRADE, RegionScene.Land.COAST])


static func _street(img: Image, s: RegionScene) -> void:
	fill(img, 0, s.ground, s.cols, s.road_top - s.ground, PAVEMENT)
	fill(img, 0, s.ground, s.cols, 1, PAVEMENT.darkened(0.35))          # foot of the walls
	for jx in range(0, s.cols, 8):
		fill(img, jx, s.ground + 1, 1, s.road_top - s.ground - 1, PAVEMENT.darkened(0.25))
	# The kerb: a pale edge stone over its own shadow.
	fill(img, 0, s.road_top - 2, s.cols, 1, KERB.lightened(0.12))
	fill(img, 0, s.road_top - 1, s.cols, 1, KERB.darkened(0.25))
	var surface := ROAD if s.paved else DIRT
	fill(img, 0, s.road_top, s.cols, s.road_h, surface)
	var mid := s.road_top + s.road_h / 2
	if s.paved:
		if _has_tram(s):
			# The tram runs down the crown of the road: two steel rails with
			# sleepers set in the setts, in place of the centre line.
			fill(img, 0, mid - 3, s.cols, 6, ROAD.lightened(0.04))
			for sx in range(0, s.cols, 5):
				fill(img, sx, mid - 2, 2, 4, ROAD.lightened(0.10))
			fill(img, 0, mid - 3, s.cols, 1, KERB.lightened(0.15))
			fill(img, 0, mid + 2, s.cols, 1, KERB.lightened(0.15))
		else:
			for dx in range(4, s.cols, 18):
				fill(img, dx, mid, 9, 1, MARKING)
		for mx in range(30, s.cols, 110):               # drains
			fill(img, mx, s.road_top + 1, 5, 2, IRON)
			for k in range(mx, mx + 5, 2):
				dot(img, k, s.road_top + 1, KERB.darkened(0.4))
	else:
		for rx in range(0, s.cols, 6):
			fill(img, rx, mid - 3, 4, 1, DIRT.darkened(0.3))
			fill(img, rx + 3, mid + 3, 4, 1, DIRT.darkened(0.3))
	fill(img, 0, s.front, s.cols, 1, KERB.lightened(0.12))
	fill(img, 0, s.front + 1, s.cols, 1, KERB.darkened(0.25))
	# Lamp posts on a footing with a swan-neck arm; benches and bins.
	var post := IRON
	for lx in s.lamps:
		fill(img, lx - 1, s.ground - 3, 4, 3, post)                   # footing
		fill(img, lx, s.ground - 26, 2, 26, post)
		fill(img, lx, s.ground - 27, 5, 2, post)                      # arm
		fill(img, lx + 3, s.ground - 25, 3, 2, IRON.lightened(0.45))  # lantern housing
		fill(img, lx - 1, s.ground - 28, 4, 1, post)                  # finial
		if s.roll(lx, 9) < 0.3:
			fill(img, lx + 8, s.road_top - 6, 9, 2, BOARD.lightened(0.2))
			fill(img, lx + 8, s.road_top - 9, 9, 1, BOARD.lightened(0.1))
			fill(img, lx + 8, s.road_top - 4, 1, 2, IRON)
			fill(img, lx + 16, s.road_top - 4, 1, 2, IRON)
		elif s.roll(lx, 10) < 0.25:
			fill(img, lx + 6, s.road_top - 7, 4, 5, Color(0.14, 0.20, 0.16))
			fill(img, lx + 5, s.road_top - 8, 6, 1, Color(0.20, 0.28, 0.22))
	if s.paved and _has_tram(s):
		# The overhead wire, slung from pole to pole.
		for i in s.lamps.size() - 1:
			var a := s.lamps[i] + 1
			var z := s.lamps[i + 1] + 1
			for wx in range(a, z):
				var t := float(wx - a) / float(maxi(1, z - a))
				dot(img, wx, s.ground - 30 + int(3.0 * 4.0 * t * (1.0 - t)), IRON.lightened(0.35))
	# Old towns keep wooden poles and a sagging wire.
	if not s.paved:
		var poles: Array[int] = []
		for px in range(20, s.cols, 64):
			poles.append(px)
			fill(img, px, s.ground - 34, 2, 34, BOARD)
			fill(img, px - 4, s.ground - 33, 10, 2, BOARD)
			dot(img, px - 3, s.ground - 34, KERB)
			dot(img, px + 4, s.ground - 34, KERB)
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
		# A post-and-rail fence: posts two pixels wide, two rails.
		for fx in range(0, s.cols, 10):
			fill(img, fx, s.front + 3, 2, 7, BOARD)
			dot(img, fx, s.front + 3, BOARD.lightened(0.3))
		fill(img, 0, s.front + 4, s.cols, 1, BOARD.lightened(0.1))
		fill(img, 0, s.front + 7, s.cols, 1, BOARD.darkened(0.2))
		return
	# The quay wall: dressed stone courses down to the water.
	fill(img, 0, s.front + 2, s.cols, s.water_top - s.front - 2, KERB.darkened(0.35))
	for bx in range(0, s.cols, 6):
		dot(img, bx, s.front + 3, KERB.darkened(0.55))
	gradient(img, 0, s.water_top, s.cols, s.h, WATER.lightened(0.08), WATER, 5)
	fill(img, 0, s.water_top, s.cols, 1, WATER.darkened(0.4))         # the waterline
	if s.land == RegionScene.Land.BASIN:
		# Embankment railing: a two-pixel top rail on posts, lamps' bollards.
		for rx in range(0, s.cols, 5):
			fill(img, rx, s.front - 5, 1, 4, IRON.lightened(0.3))
		fill(img, 0, s.front - 6, s.cols, 2, IRON.lightened(0.38))
		for bx in range(14, s.cols, 60):
			fill(img, bx, s.front - 4, 3, 4, IRON.lightened(0.2))
	else:
		for px in range(40, s.cols, 90):               # piers on piles
			fill(img, px, s.water_top - 2, 30, 2, BOARD.lightened(0.1))
			fill(img, px, s.water_top, 30, 1, BOARD.darkened(0.3))
			for k in range(px, px + 30, 7):
				fill(img, k, s.water_top + 1, 2, 9, BOARD.darkened(0.4))


## The street mirrored in the water as broken horizontal streaks: walls as
## dim smears, lit windows as warm dashes, stretched and fading with depth.
## Moving shimmer on top is `RegionLife._water`'s.
static func _reflections(img: Image, s: RegionScene) -> void:
	if s.water_top < 0:
		return
	var depth := s.h - s.water_top
	for y in range(s.water_top + 2, s.h, 2):
		var k := float(y - s.water_top) / float(depth)
		var src_y := clampi(s.ground - 4 - int((y - s.water_top) * 2.2), 0, s.h - 1)
		var x := s.rng.randi_range(0, 6)
		while x < s.cols:
			var run := s.rng.randi_range(2, 10)
			for dx in run:
				var px := x + dx
				if px >= s.cols:
					break
				var c := img.get_pixel(px, src_y)
				var under := img.get_pixel(px, y)
				var bright := c.r > 0.6 and c.r > c.b + 0.2
				var a := (0.75 if bright else 0.22) * (1.0 - k * 0.7)
				img.set_pixel(px, y, under.lerp(c, a))
			x += run + s.rng.randi_range(1, 6)


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
