class_name CityHarbour
extends RefCounted

## The harbour towns, Kelvet and Vetrenka, seen from the promenade across the
## basin: the far quay with its row of houses and warehouses, gantry cranes
## and container stacks, the landmark, a ship alongside; the water with its
## boats and the broken columns of every light laid on it; and the
## promenade in the foreground, its railing, lamps, benches and people.
##
##   kelvet    the trading port: the customs house clock tower, three gantry
##             cranes working, a container ship alongside, the quayside tram
##   vetrenka  the contested coast: a lighthouse on the breakwater, two old
##             cranes, fishing boats, a patrol boat when the line is tense

const CX := RegionCity.CX
const SHORE := 196.0      # the far quay, where its buildings stand
const WATER_TOP := 204.0
const RAIL := 244.0
const PROM := 256.0
const TRAM_Y := 276.0
const ANCHORS := {"site": SHORE, "back": SHORE - 1.0, "far": TRAM_Y, "near": TRAM_Y, "front": 294.0, "works_x": 200.0}
const KELVET_CRANES := [118.0, 560.0, 652.0]
const VETRENKA_CRANES := [130.0, 236.0]


static func paint(v: DeskView, t: float, d: Dictionary, k: Dictionary) -> void:
	var kelvet := String(d["id"]) == "kelvet"
	var spec := RegionCity.spec_of(String(d["id"]))
	RegionCity.sky(v, t, d, k, SHORE)
	RegionCity.skyline(v, t, d, k, SHORE, false, 0.8 if kelvet else 0.55)
	var lights := []
	if kelvet:
		lights.append_array(_customs_house(v, t, k))
	RegionCity.row(v, t, d, k, spec, SHORE)
	_quay(v, t, d, k, kelvet)
	for x: float in (KELVET_CRANES if kelvet else VETRENKA_CRANES):
		var paint_c := Color(0.58, 0.32, 0.18) if kelvet else Color(0.40, 0.40, 0.38)
		lights.append_array(_crane(v, t, k, x, paint_c, kelvet or x == VETRENKA_CRANES[0]))
	_water(v, t, k)
	if kelvet:
		lights.append_array(_ship(v, k, 432.0))
	else:
		lights.append_array(_breakwater(v, t, k))
	lights.append_array(_quay_lamps(v, k))
	_reflections(v, t, lights)
	if not k["lit"]:
		var span: Vector2 = Vector2(CX - 62.0, CX + 62.0) if kelvet else Vector2(566.0, 586.0)
		_mirror(v, t, k, span.x, span.y)
	_boats(v, t, d, k, kelvet)
	_promenade(v, t, d, k, kelvet)
	RegionProjects.back(v, t, d, k, ANCHORS)
	_trouble(v, t, d, k)
	RegionProjects.front(v, t, d, k, ANCHORS)
	_near(v, t, d, k)
	if kelvet:
		v.label(Vector2(410, 22), "KELVET CUSTOMS HOUSE", Vector2(CX + 10, 46))
	else:
		v.label(Vector2(470, 80), "VETRENKA LIGHT", Vector2(570, 112))


# --- the far quay -----------------------------------------------------------

static func _quay(v: DeskView, t: float, d: Dictionary, k: Dictionary, kelvet: bool) -> void:
	var face: Color = (k["stone"] as Color).darkened(0.2)
	v.rect(v.left, SHORE, v.right - v.left, WATER_TOP - SHORE, face)
	v.rect(v.left, SHORE, v.right - v.left, 2, face.lightened(0.3))
	for x: float in CityKit.span(v, 18.0):
		v.rect(x, SHORE + 3, 1, WATER_TOP - SHORE - 3, face.darkened(0.3))
	# Container stacks along the quay edge.
	var stacks := [[18.0, 3], [176.0, 2], [470.0, 1]] if kelvet else [[300.0, 2], [450.0, 1]]
	var seed: int = d["seed"]
	for st in stacks:
		for col in 3:
			for lvl in int(st[1]) - (col % 2):
				var x: float = float(st[0]) + col * 23.0
				var y := SHORE - 10.0 - lvl * 10.0
				var c: Color = CityKit.LIVERY[posmod(int(x) * 3 + lvl + seed, 5)]
				c = c.lerp(CityKit.dim(c, 0.4), k["n"])
				v.rect(x, y, 22, 9.5, c)
				v.rect(x, y, 22, 1.2, c.lightened(0.2))
				for rx in range(int(x + 3), int(x + 22), 4):
					v.rect(rx, y + 2, 1, 7, c.darkened(0.25))
	# Dockers about the quay.
	for i in 4:
		var x := fposmod(CityKit.roll(seed, i, 440) * 900.0 + t * 4.0 * (1.0 if i % 2 == 0 else -1.0), v.right - v.left) + v.left
		v.figure(x, SHORE - 1, CityKit.HI_VIS.darkened(0.2) if i % 2 == 0 else CityKit.coat(k, i), "walk", t + i, 12.0)


## A gantry crane on the quay: legs, the machinery house, the boom with its
## trolley running out and back, a box rising and falling on the cable.
static func _crane(v: DeskView, t: float, k: Dictionary, x: float, paint_c: Color, working: bool) -> Array:
	var c := paint_c.lerp(CityKit.dim(paint_c, 0.45), k["n"])
	var hi := c.lightened(0.18)
	v.line(Vector2(x - 18, SHORE + 2), Vector2(x - 11, 64), c, 3.5)
	v.line(Vector2(x + 18, SHORE + 2), Vector2(x + 11, 64), c, 3.5)
	v.line(Vector2(x - 16, 140), Vector2(x + 16, 140), c, 2.5)
	v.line(Vector2(x - 14, 140), Vector2(x + 12, 94), c, 1.5)
	v.line(Vector2(x + 14, 140), Vector2(x - 12, 94), c, 1.5)
	v.line(Vector2(x - 12, 94), Vector2(x + 12, 94), c, 2.0)
	v.rect(x - 16, 56, 30, 12, hi)
	v.rect(x - 12, 59, 7, 5, DeskView.LAMP.darkened(0.2) if k["lit"] else k["glass"])
	v.rect(x - 56, 50, 136, 5, c)                                   # the boom
	v.line(Vector2(x, 24), Vector2(x + 78, 51), c, 1.5)              # stays
	v.line(Vector2(x, 24), Vector2(x - 54, 51), c, 1.5)
	v.rect(x - 2.5, 24, 5, 26, c)                                    # the A-frame
	var cycle := fposmod(t * 0.1 + x * 0.01, 1.0) if working else 0.3
	var run := x - 36.0 + 100.0 * (0.5 - 0.5 * cos(cycle * TAU))
	var drop := 30.0 + 70.0 * absf(sin(cycle * TAU))
	v.rect(run - 5, 55, 10, 5, hi)
	v.line(Vector2(run, 60), Vector2(run, 60 + drop), (k["metal"] as Color).lightened(0.35), 1.2)
	var box: Color = CityKit.LIVERY[posmod(int(x), 4)]
	v.rect(run - 11, 60 + drop, 22, 9.5, box.lerp(CityKit.dim(box, 0.4), k["n"]))
	var lights := []
	if k["lit"]:
		var blink := int(t * 1.1 + x) % 2 == 0
		v.rect(x - 1, 21, 2.5, 2.5, DeskView.ALARM if blink else DeskView.ALARM.darkened(0.6))
		for tip: float in [x - 56.0, x + 78.0]:
			v.rect(tip, 47, 2.5, 2.5, DeskView.ALARM)
		CityKit.pool(v, Vector2(x, SHORE + 1), 30, 3, (k["stone"] as Color).lerp(Color(0.40, 0.32, 0.20), 0.6))
		lights.append([Vector2(x - 8, 61), DeskView.LAMP])
	return lights


static func _customs_house(v: DeskView, t: float, k: Dictionary) -> Array:
	var s := CityLandmarks.stone(k)
	v.rect(CX - 62, 116, 124, SHORE - 116, s.darkened(0.08))
	v.rect(CX - 66, 112, 132, 5, s.lightened(0.15))
	var lights := []
	for row in 4:
		for x in range(int(CX - 54), int(CX + 54), 13):
			if absf(x - CX + 3) < 16:
				continue
			var wy := 122.0 + row * 17.0
			if k["lit"] and CityKit.roll(x, row) < 0.75:
				v.rect(x, wy, 7, 10, DeskView.LAMP.darkened(0.15))
				if row == 3:
					lights.append([Vector2(x + 3, wy + 5), DeskView.LAMP])
			else:
				v.rect(x, wy, 7, 10, k["glass"])
				v.rect(x, wy, 7, 2, k["glint"])
	# The clock tower: the dial, a copper cap and a finial.
	v.rect(CX - 14, 48, 28, 64, s)
	v.rect(CX + 8, 48, 6, 64, s.darkened(0.3))
	v.rect(CX - 16, 46, 32, 3, s.lightened(0.2))
	for y: float in [86.0, 100.0]:
		v.rect(CX - 4, y, 8, 10, DeskView.LAMP.darkened(0.3) if k["lit"] else k["glass"])
	var dial := Vector2(CX, 64)
	v.disc(dial, 9, DeskView.PAPER.darkened(0.1 + 0.15 * k["n"]))
	var hours := TAU * fposmod(t / 720.0 + 0.3, 1.0)
	var mins := TAU * fposmod(t / 60.0, 1.0)
	v.line(dial, dial + Vector2(sin(hours), -cos(hours)) * 5.0, Color(0.1, 0.1, 0.1), 1.5)
	v.line(dial, dial + Vector2(sin(mins), -cos(mins)) * 7.5, Color(0.1, 0.1, 0.1), 1.2)
	v.poly(PackedVector2Array([Vector2(CX - 15, 46), Vector2(CX - 9, 26), Vector2(CX + 9, 26), Vector2(CX + 15, 46)]), Color(0.36, 0.44, 0.40).lerp(Color(0.14, 0.17, 0.17), k["n"]))
	v.rect(CX - 0.6, 12, 1.2, 14, k["metal"])
	v.rect(CX - 12, 168, 24, SHORE - 168, s.darkened(0.5))
	if k["lit"]:
		v.rect(CX - 10, 172, 20, 6, DeskView.LAMP.darkened(0.3))
	return lights


# --- the water --------------------------------------------------------------

static func _water(v: DeskView, t: float, k: Dictionary) -> void:
	var water: Color = k["water"]
	var bands := 6
	for i in bands:
		var y := WATER_TOP + (RAIL - WATER_TOP) * i / bands
		v.rect(v.left, y, v.right - v.left, (RAIL - WATER_TOP) / bands + 1, water.lerp(water.lightened(0.08), float(i) / bands))
	# The swell: long low lines drifting slowly.
	for row in 6:
		var y := WATER_TOP + 5 + row * 6.0
		for x: float in CityKit.span(v, 70.0, row * 23.0):
			var dx := fposmod(t * (2.0 + row * 0.4), 70.0)
			v.rect(x + dx, y, 16 + row * 2.0, 1.0, water.lightened(0.12 + row * 0.015))


static func _ship(v: DeskView, k: Dictionary, x: float) -> Array:
	var hull := Color(0.20, 0.20, 0.22).lerp(Color(0.09, 0.09, 0.10), k["n"])
	var boot := Color(0.50, 0.20, 0.15).lerp(Color(0.22, 0.09, 0.07), k["n"])
	var white := Color(0.58, 0.56, 0.50).lerp(Color(0.28, 0.27, 0.25), k["n"])
	v.poly(PackedVector2Array([Vector2(x - 6, 172), Vector2(x + 196, 172), Vector2(x + 186, 210), Vector2(x + 8, 210)]), hull)
	v.rect(x + 4, 204, 184, 6, boot)
	v.rect(x - 6, 170, 202, 2.5, hull.lightened(0.3))
	for col in 7:
		for lvl in 2:
			var c: Color = CityKit.LIVERY[(col + lvl * 3) % 5]
			c = c.lerp(CityKit.dim(c, 0.4), k["n"])
			v.rect(x + 40 + col * 21.0, 160 - lvl * 10.0, 20, 9.5, c)
			v.rect(x + 40 + col * 21.0, 160 - lvl * 10.0, 20, 1.2, c.lightened(0.2))
	v.rect(x + 4, 122, 30, 48, white)
	v.rect(x + 2, 120, 34, 3, white.lightened(0.15))
	v.rect(x + 22, 108, 8, 12, boot)
	var lights := []
	for row in 3:
		for c in 4:
			var p := Vector2(x + 8 + c * 7.0, 128 + row * 13.0)
			if k["lit"] and CityKit.roll(row, c, 5) < 0.75:
				v.rect(p.x, p.y, 4.5, 5, DeskView.LAMP.darkened(0.1))
			else:
				v.rect(p.x, p.y, 4.5, 5, k["glass"])
	if k["lit"]:
		lights.append([Vector2(x + 20, 156), DeskView.LAMP])
		lights.append([Vector2(x + 190, 172), DeskView.ALARM])
	return lights


static func _breakwater(v: DeskView, t: float, k: Dictionary) -> Array:
	var s: Color = (k["stone"] as Color).darkened(0.05)
	v.poly(PackedVector2Array([Vector2(480, 218), Vector2(508, 208), Vector2(v.right + 4, 208), Vector2(v.right + 4, 220), Vector2(480, 220)]), s)
	v.rect(508, 207, v.right - 504, 2, s.lightened(0.25))
	for x in range(512, int(v.right), 12):
		v.rect(x, 210, 1, 9, s.darkened(0.3))
	var x := 576.0
	for i in 10:
		var y := 112.0 + i * 9.6
		var half := 7.0 + i * 0.7
		v.rect(x - half, y, half * 2, 9.6, (Color(0.62, 0.58, 0.52) if i % 2 == 0 else Color(0.55, 0.22, 0.16)).lerp(Color(0.28, 0.24, 0.22), k["n"]))
		v.rect(x + half - 3, y, 3, 9.6, Color(0, 0, 0, 0.25))
	v.rect(x - 9, 98, 18, 14, (k["metal"] as Color).lightened(0.25))
	v.rect(x - 12, 96, 24, 3, (k["metal"] as Color).lightened(0.4))
	v.poly(PackedVector2Array([Vector2(x - 9, 96), Vector2(x, 86), Vector2(x + 9, 96)]), (k["metal"] as Color).lightened(0.2))
	v.rect(x - 2.5, 190, 5, 18, Color(0.08, 0.08, 0.08))
	var lights := []
	var lamp := Vector2(x, 104)
	if k["lit"]:
		var a := t * 0.9
		var reach := 170.0 * cos(a)
		v.rect(x - 5, 100, 10, 8, DeskView.PAPER)
		var spread := 10.0 * absf(sin(a)) + 2.0
		v.poly(PackedVector2Array([lamp, lamp + Vector2(reach, -spread), lamp + Vector2(reach, spread)]), Color(0.75, 0.85, 1.0, 0.08))
		lights.append([lamp, DeskView.LAMP])
	else:
		v.rect(x - 5, 100, 10, 8, k["glass"])
	return lights


## Small lamps along the far quay edge: the main source of reflections.
static func _quay_lamps(v: DeskView, k: Dictionary) -> Array:
	var lights := []
	for x: float in CityKit.span(v, 64.0, 34.0):
		v.rect(x, SHORE - 22, 1.5, 22, k["metal"])
		var head := Vector2(x + 0.75, SHORE - 23)
		if k["lit"]:
			v.rect(head.x - 2.5, head.y - 1.5, 5, 3, DeskView.LAMP)
			lights.append([head, DeskView.LAMP])
		else:
			v.rect(head.x - 2.5, head.y - 1.5, 5, 3, (k["metal"] as Color).lightened(0.3))
	return lights


## Every light on the far side laid on the water as a broken column of
## dashes that sways with the swell.
static func _reflections(v: DeskView, t: float, lights: Array) -> void:
	for l in lights:
		var p: Vector2 = l[0]
		var c: Color = l[1]
		for i in 7:
			var y := WATER_TOP + 3.0 + i * 5.0
			if y > RAIL - 3:
				break
			var sway := sin(t * 1.4 + y * 0.35 + p.x) * (1.0 + i * 0.5)
			var w := 7.0 - i * 0.6
			v.rect(p.x - w * 0.5 + sway, y, w, 1.6, Color(c.r, c.g, c.b, 0.75 - i * 0.09))


static func _boats(v: DeskView, t: float, d: Dictionary, k: Dictionary, kelvet: bool) -> void:
	var w := v.right - v.left
	# A tug crossing the basin, its wake behind it.
	var tx := fposmod(t * 9.0 + 300.0, w + 200.0) + v.left - 100.0
	var tug := Color(0.48, 0.22, 0.16).lerp(Color(0.22, 0.10, 0.08), k["n"])
	v.poly(PackedVector2Array([Vector2(tx, 222), Vector2(tx + 44, 222), Vector2(tx + 39, 232), Vector2(tx + 4, 232)]), tug)
	v.rect(tx + 10, 209, 18, 13, Color(0.58, 0.56, 0.50).lerp(Color(0.28, 0.27, 0.25), k["n"]))
	v.rect(tx + 14, 212, 4, 4, DeskView.LAMP if k["lit"] else k["glass"])
	v.rect(tx + 20, 212, 4, 4, DeskView.LAMP if k["lit"] else k["glass"])
	v.rect(tx + 21, 202, 4, 7, Color(0.12, 0.12, 0.12))
	CityKit.puffs(v, Vector2(tx + 23, 200), 0.4, t, (k["haze"] as Color).lightened(0.2), 4)
	for i in 4:
		v.rect(tx - 12 - i * 14.0, 231 + i * 0.5, 11 - i * 2.0, 1.4, (k["water"] as Color).lightened(0.35 - i * 0.07))
	# Small boats at their moorings by the promenade, rocking.
	var count := 3 if kelvet else 6
	for i in count:
		var bx := 40.0 + i * (620.0 / count) + CityKit.roll(int(d["seed"]), i, 400) * 30.0
		var by := 234.0
		var rock := sin(t * 1.1 + i * 1.7) * 1.4
		var hull := Color(0.56, 0.52, 0.44).lerp(Color(0.26, 0.25, 0.22), k["n"])
		v.poly(PackedVector2Array([Vector2(bx, by + rock), Vector2(bx + 34, by - rock), Vector2(bx + 29, by + 8 - rock), Vector2(bx + 5, by + 8 + rock)]), hull)
		v.rect(bx + 5, by + 4, 24, 2, Color(0.30, 0.42, 0.50).lerp(Color(0.14, 0.18, 0.22), k["n"]))
		v.rect(bx + 18, by - 7, 9, 7, hull.darkened(0.2))
		v.line(Vector2(bx + 12, by), Vector2(bx + 12 + rock, by - 28), (k["metal"] as Color).lightened(0.35), 1.2)
		if k["lit"]:
			v.rect(bx + 11 + rock, by - 29, 2.5, 2.5, DeskView.LAMP)
	# The patrol boat when the line is tense.
	if not kelvet and float(d["trouble"]) >= 0.35:
		var px := fposmod(-t * 12.0 + 400.0, w + 160.0) + v.left - 80.0
		var grey := Color(0.36, 0.38, 0.36).lerp(Color(0.18, 0.19, 0.18), k["n"])
		v.poly(PackedVector2Array([Vector2(px, 220), Vector2(px + 56, 220), Vector2(px + 49, 230), Vector2(px + 5, 230)]), grey)
		v.rect(px + 16, 208, 22, 12, grey.lightened(0.1))
		v.rect(px + 20, 211, 14, 3, Color(0.08, 0.09, 0.10))
		v.rect(px + 26, 203, 1.2, 5, Color(0.1, 0.1, 0.1))
		CityKit.siren(v, px + 27, 202, t)
		for i in 4:
			v.rect(px + 58 + i * 13.0, 229, 10 - i * 1.5, 1.4, (k["water"] as Color).lightened(0.3 - i * 0.06))


# --- the promenade ---------------------------------------------------------

static func _promenade(v: DeskView, t: float, d: Dictionary, k: Dictionary, kelvet: bool) -> void:
	var w := v.right - v.left
	var paving: Color = k["paving"]
	v.rect(v.left, RAIL + 9, w, 300 - RAIL - 9, paving)
	for x: float in CityKit.span(v, 26.0):
		v.rect(x, PROM, 1, 300 - PROM, paving.darkened(0.3))
	v.rect(v.left, 286, w, 1, paving.darkened(0.3))
	# The quayside railing over the water.
	var rail: Color = (k["metal"] as Color).lightened(0.25)
	v.rect(v.left, RAIL, w, 2.5, rail)
	v.rect(v.left, RAIL + 5, w, 1.5, rail.darkened(0.2))
	for x: float in CityKit.span(v, 12.0):
		v.rect(x, RAIL, 1.8, 10, rail.darkened(0.15))
	v.rect(v.left, RAIL + 9, w, 3, k["kerb"])
	if kelvet and float(d["development"]) >= 0.45 and RegionCity.mood(d) != "unrest":
		for y: float in [TRAM_Y - 0.5, TRAM_Y + 2.5]:
			v.rect(v.left, y, w, 1, (k["kerb"] as Color).lightened(0.1))
		var x := fposmod(-t * 15.0 + 500.0, w + 260.0) + v.left - 130.0
		CityKit.coach(v, k, x, TRAM_Y + 2, -1.0, 64.0, Color(0.30, 0.42, 0.50), true, TRAM_Y - 34.0)
	# Benches with someone watching the water.
	var seed: int = d["seed"]
	for x: float in CityKit.span(v, 130.0, 70.0):
		var i := int(roundf(x / 130.0))
		v.rect(x, 264, 30, 3, (k["roof"] as Color).lightened(0.25))
		v.rect(x + 2, 267, 2, 5, rail.darkened(0.3))
		v.rect(x + 26, 267, 2, 5, rail.darkened(0.3))
		if CityKit.roll(seed, i, 410) < 0.6:
			v.figure(x + 6, 271, CityKit.coat(k, i), "sit_back", t, 16.0)
		if CityKit.roll(seed, i, 411) < 0.4:
			v.figure(x + 18, 271, CityKit.coat(k, i + 2), "sit_back", t, 16.0)


static func _trouble(v: DeskView, t: float, d: Dictionary, k: Dictionary) -> void:
	var m := RegionCity.mood(d)
	if m == "calm":
		return
	var seed: int = d["seed"]
	if m == "restless":
		for i in 7:
			var x := CX + 120.0 + i * 9.0
			v.figure(x, 280.0 + (i % 2) * 2.0, CityKit.coat(k, i), "stand", t, 21.0)
			if i % 3 == 0:
				CityKit.placard(v, x, 280.0 - 21.0, t, i)
		return
	# A warehouse burning on the far quay, its fire doubled in the water.
	CityKit.fire(v, 250.0, SHORE - 2, 1.5, t)
	for i in 6:
		var y := WATER_TOP + 3 + i * 5.0
		v.rect(242 + sin(t * 2.0 + i) * 2.0, y, 16 - i * 2.0, 1.6, Color(0.95, 0.5, 0.2, 0.7 - i * 0.1))
	for i in 26:
		var x := CX - 160.0 + CityKit.roll(seed, i, 420) * 190.0
		var foot := 272.0 + CityKit.roll(seed, i, 421) * 14.0
		var pose := "arms_up" if sin(t * 1.3 + i * 2.1) > 0.6 else "stand"
		v.figure(x, foot, CityKit.coat(k, i), pose, t, 21.0)
		if CityKit.roll(seed, i, 422) < 0.3:
			CityKit.placard(v, x, foot - 21.0, t, i)
	for i in 8:
		CityKit.riot_officer(v, CX + 60.0 + i * 12.0, 274.0 + (i % 2) * 10.0, 22.0, t, i)


static func _near(v: DeskView, t: float, d: Dictionary, k: Dictionary) -> void:
	var seed: int = d["seed"]
	var reach := float(d["reach"])
	for x: float in CityKit.span(v, 120.0, 30.0):
		var i := int(roundf(x / 120.0))
		var on := CityKit.roll(seed, i, 430) < 0.35 + reach * 0.75 - (0.3 if RegionCity.mood(d) == "unrest" else 0.0)
		CityKit.lamp(v, k, x, RAIL + 10, 58.0, on, t)
		v.rect(x + 54, 282, 7, 9, (k["metal"] as Color).lightened(0.1))      # a bollard
		v.rect(x + 53, 281, 9, 2, (k["metal"] as Color).lightened(0.25))
	var w := v.right - v.left
	var walkers := int(5 + float(d["population"]) * 10)
	if k["lit"]:
		walkers = int(walkers * 0.6)
	for i in walkers:
		var r := CityKit.roll(seed, i, 431)
		var dir := 1.0 if r < 0.5 else -1.0
		var sp := (8.0 + 6.0 * CityKit.roll(i, 432)) * dir
		var x := fposmod(r * 2500.0 + sp * t, w + 60.0) + v.left - 30.0
		var foot := 289.0 + CityKit.roll(i, 433) * 10.0
		v.figure(x, foot, CityKit.coat(k, i + 3), "walk", t + i * 0.3, 25.0 + (foot - 289.0) * 0.5)
	if RegionCity.mood(d) != "calm":
		CityKit.barrel(v, k, RegionCity.SIZE.x * 0.14, 296.0, t, 26.0)


## By day the water carries the landmark's mass instead: a darker band
## under it, broken by the swell.
static func _mirror(v: DeskView, t: float, k: Dictionary, x0: float, x1: float) -> void:
	var water: Color = k["water"]
	for i in 8:
		var y := WATER_TOP + 2.0 + i * 4.5
		var sway := sin(t * 1.2 + i * 0.9) * (1.0 + i * 0.4)
		v.rect(x0 + sway + i * 0.8, y, x1 - x0 - i * 1.6, 2.2, water.darkened(0.35 - i * 0.03))
