class_name RegionCity
extends RefCounted

## One region's town, painted like a desk room: an exterior street diorama of
## large, clear vector shapes printed by the converter at its defaults.
##
## Seen from across the street: sky (stars and a moon by night, a muted
## overcast blue by day), a far skyline in haze, then the street's own row of
## buildings broken by the region's landmark (`CityLandmarks`), the road with
## its traffic, and the near pavement with its lamps and passers-by. Harbour
## towns (Kelvet, Vetrenka) are seen instead from the promenade across the
## water (`CityHarbour`).
##
## Three things are kept apart on purpose:
## 1. **Layout** — every building, window and lamp is a stable roll on the
##    region id, so a place keeps its streets all campaign.
## 2. **Condition** — the live figures decide how built up, lit, busy,
##    shuttered or angry the same street is.
## 3. **Motion** — traffic, walkers, smoke and fire run on continuous time.
##
## data (see `data_from`): id, development, reach, pressure, unemployment,
## population (relative size), trouble, program, control, night.

const SIZE := Vector2(720, 300)
const CX := 360.0
## The street, top to bottom.
const HORIZON := 182.0
const GROUND := 228.0
const ROAD_TOP := 236.0
const LANE_FAR := 251.0
const LANE_NEAR := 265.0
const KERB := 268.0
const WIRE := 190.0
const BLOCK := 96.0

## Per region: the gaps the street row leaves for its landmark, the storey
## range (scaled by development), roof types, and whether a tram runs.
const SPECS := {
	"vashtera": {"gaps": [[232.0, 488.0]], "lo": 3, "hi": 7, "roofs": ["mansard", "flat", "block", "mansard"], "tram": true},
	"karsen": {"gaps": [[222.0, 278.0], [330.0, 390.0], [446.0, 502.0]], "lo": 3, "hi": 5, "roofs": ["pitched", "flat", "mansard"], "trees": true, "skyline": 0.7},
	"zavost": {"gaps": [[214.0, 520.0]], "lo": 3, "hi": 6, "roofs": ["block", "flat", "block"]},
	"darev": {"gaps": [[262.0, 470.0]], "lo": 2, "hi": 4, "roofs": ["pitched", "flat"], "skyline": 0.0},
	"orvena": {"gaps": [], "lo": 2, "hi": 3, "roofs": ["pitched", "pitched", "flat"], "trees": true, "cap": 74.0, "skyline": 0.55},
	"sela": {"gaps": [[270.0, 470.0]], "lo": 1, "hi": 3, "roofs": ["pitched", "pitched", "flat"], "trees": true, "dirt": true, "skyline": 0.4},
	"anera": {"gaps": [[318.0, 404.0]], "lo": 2, "hi": 3, "roofs": ["pitched"], "trees": true, "dirt": true, "cap": 66.0, "skyline": 0.0},
	"kostrel": {"gaps": [[248.0, 472.0]], "lo": 1, "hi": 3, "roofs": ["pitched", "flat", "pitched"], "trees": true, "skyline": 0.35},
	# Harbour towns: the row stands on the far quay (see `CityHarbour`).
	"kelvet": {"gaps": [[290.0, 430.0]], "lo": 2, "hi": 4, "roofs": ["flat", "mansard", "pitched"]},
	"vetrenka": {"gaps": [[536.0, 616.0]], "lo": 1, "hi": 3, "roofs": ["pitched", "pitched", "flat"]},
}
## Any region without its own entry (a new region before it is authored)
## still gets an ordinary street of its own, seeded from its id.
const TOWN := {"gaps": [], "lo": 2, "hi": 4, "roofs": ["flat", "pitched"], "trees": true}


static func is_harbour(id: String) -> bool:
	return id in ["kelvet", "vetrenka"]


static func spec_of(id: String) -> Dictionary:
	return SPECS.get(id, TOWN)


static func _f(region: Dictionary, key: String, fallback: float = 0.0) -> float:
	return clampf(float(region.get(key, fallback)), 0.0, 1.0)


## What the scene shows, read from one region row of the snapshot.
static func data_from(region: Dictionary) -> Dictionary:
	var id := String(region.get("id", ""))
	var population := 0.5
	if region.has("population_share"):
		population = clampf(float(region["population_share"]) / 0.22 * 0.9, 0.15, 1.3)
	var program := ""
	if region.get("active_program") is Dictionary:
		program = String((region["active_program"] as Dictionary).get("program_id", ""))
	var pressure := _f(region, "pressure")
	return {
		"id": id,
		"seed": absi(hash(id)),
		"development": _f(region, "development", 0.5),
		"reach": _f(region, "state_reach", 0.5),
		"pressure": pressure,
		"unemployment": _f(region, "unemployment", 0.1),
		"population": population,
		"trouble": clampf(maxf(pressure, _f(region, "insurgency")) + (0.25 if bool(region.get("civil_war", false)) else 0.0), 0.0, 1.0),
		"program": program,
		"control": String(region.get("control", "full")),
	}


## The mood the figures put the street in.
static func mood(d: Dictionary) -> String:
	var trouble := float(d.get("trouble", 0.0))
	if trouble >= 0.65:
		return "unrest"
	if trouble >= 0.35:
		return "restless"
	return "calm"


static func paint(v: DeskView, t: float, d: Dictionary) -> void:
	if d.is_empty():
		return
	var k := CityKit.tones(float(d.get("night", 0.0)))
	if is_harbour(String(d["id"])):
		CityHarbour.paint(v, t, d, k)
		return
	var spec := spec_of(String(d["id"]))
	sky(v, t, d, k, HORIZON)
	CityLandmarks.far(v, t, d, k)
	var far_scale := float(spec.get("skyline", 1.0))
	if far_scale > 0.0:
		skyline(v, t, d, k, HORIZON, String(d["id"]) == "vashtera", far_scale)
	CityLandmarks.behind(v, t, d, k)
	row(v, t, d, k, spec)
	street(v, t, d, k, spec)
	CityLandmarks.front(v, t, d, k)
	RegionProjects.back(v, t, d, k)
	traffic(v, t, d, k, spec)
	unrest(v, t, d, k)
	RegionProjects.front(v, t, d, k)
	pavement(v, t, d, k, spec)


# --- sky ----------------------------------------------------------------

static func sky(v: DeskView, t: float, d: Dictionary, k: Dictionary, base: float) -> void:
	var top: Color = k["sky_top"]
	var low: Color = k["sky_low"]
	var bands := 10
	for i in bands:
		var y := base * i / bands
		v.rect(v.left, y, v.right - v.left, base / bands + 1, top.lerp(low, pow(float(i) / (bands - 1), 1.6)))
	var n: float = k["n"]
	var trouble := float(d["trouble"])
	if n > 0.3:
		var a := (n - 0.3) / 0.7
		for x: float in CityKit.span(v, 17.0, 5.0):
			var i := int(x / 17.0)
			if CityKit.roll(int(d["seed"]), i, 1) > 0.55 * (1.0 - trouble * 0.6):
				continue
			var y := 6.0 + CityKit.roll(int(d["seed"]), i, 2) * base * 0.62
			var tw := 0.6 + 0.4 * sin(t * (0.6 + CityKit.roll(i, 3)) + i)
			var star := DeskView.PAPER * Color(tw, tw, tw, a)
			var s := 1.2 if CityKit.roll(i, 4) < 0.8 else 2.0
			v.rect(x + CityKit.roll(i, 5) * 10.0, y, s, s, star)
		# The moon: a lit disc with the sky's own dark eating a crescent.
		var m := Vector2(SIZE.x * 0.80, 34)
		v.disc(m, 10, DeskView.PAPER.darkened(0.05) * Color(1, 1, 1, a))
		v.disc(m + Vector2(4.5, -2.5), 9.0, top.lerp(low, 0.1))
	if n < 0.7:
		# Low overcast cloud drifting across, darker underneath.
		var a := 1.0 - n / 0.7
		var cloud := low.lightened(0.10) * Color(1, 1, 1, a)
		var under := low.darkened(0.06) * Color(1, 1, 1, a)
		for i in 7:
			var cx := fposmod(CityKit.roll(int(d["seed"]), i, 9) * 1400.0 + t * (1.2 + i * 0.25), (v.right - v.left) + 200.0) + v.left - 100.0
			var cy := 22.0 + CityKit.roll(int(d["seed"]), i, 10) * base * 0.45
			var w := 50.0 + CityKit.roll(int(d["seed"]), i, 11) * 70.0
			v.rect(cx - w * 0.5, cy, w, 7, under)
			v.rect(cx - w * 0.45, cy - 4, w * 0.9, 5, cloud)
			v.rect(cx - w * 0.25, cy - 8, w * 0.4, 5, cloud)


# --- the far city -----------------------------------------------------------

## Two layers of silhouettes standing on `base`: a hazy far one and a nearer
## dark one with scattered lit windows. The capital raises towers with
## blinking aircraft lights. Returns the lights it lit, for reflections.
static func skyline(v: DeskView, t: float, d: Dictionary, k: Dictionary, base: float, capital: bool, scale: float = 1.0) -> Array:
	var lights := []
	var seed: int = d["seed"]
	var dev := float(d["development"])
	var tall := (18.0 + 46.0 * dev * float(d["population"])) * scale
	for layer in 2:
		var step := (22.0 if layer == 0 else 30.0) * scale
		var tone: Color = k["haze"] if layer == 0 else k["far"]
		for x: float in CityKit.span(v, step, layer * 9.0):
			var i := int(roundf(x / step))
			var r := CityKit.roll(seed, i, 20 + layer)
			if layer == 1 and r < 0.25:
				continue
			var w := step * (0.7 + 0.5 * CityKit.roll(seed, i, 22 + layer))
			var h := (10.0 * scale + r * tall) * (1.0 if layer == 0 else 0.8)
			if capital and layer == 1 and r > 0.82:
				h = tall * 1.9
			v.rect(x, base - h, w, h, tone)
			if capital and layer == 1 and h > tall * 1.5:
				v.rect(x + w * 0.5 - 0.6, base - h - 14, 1.2, 14, tone)
				if int(t * 1.2 + i) % 2 == 0 and k["lit"]:
					v.rect(x + w * 0.5 - 1, base - h - 15, 2, 2, DeskView.ALARM)
			if layer == 1 and k["lit"]:
				var cols := int(w / (6.0 * scale))
				var rows := int((h - 4.0) / (8.0 * scale))
				for cy in rows:
					for cx in cols:
						if CityKit.roll(seed, i * 97 + cx, cy) < 0.18 + 0.2 * dev:
							var p := Vector2(x + 2 + cx * 6.0 * scale, base - h + 4 + cy * 8.0 * scale)
							var c := DeskView.LAMP.darkened(0.25 + 0.3 * CityKit.roll(cx, cy, i))
							v.rect(p.x, p.y, 2.2 * scale, 2.6 * scale, c)
							lights.append([p, c])
	return lights


# --- the street row ---------------------------------------------------------

## The street's own buildings, block by block across the visible span. Each
## 96-unit block holds two to four buildings decided by stable rolls; the
## region's gaps stay open for its landmark.
static func row(v: DeskView, t: float, d: Dictionary, k: Dictionary, spec: Dictionary, base: float = GROUND) -> void:
	var seed: int = d["seed"]
	var dev := float(d["development"])
	var unemployment := float(d["unemployment"])
	var trouble := float(d["trouble"])
	var lit := clampf(0.3 + 0.4 * dev + 0.15 * float(d["reach"]) - 0.25 * trouble, 0.12, 0.85)
	var boarded := clampf((trouble - 0.4) * 0.5 + maxf(0.0, unemployment - 0.18) * 1.2, 0.0, 0.45)
	var roofs: Array = spec.get("roofs", ["flat"])
	var lo := int(spec.get("lo", 2))
	var hi := int(spec.get("hi", 4))
	var cap := float(spec.get("cap", 999.0))
	var first := int(floorf(v.left / BLOCK)) - 1
	for b in range(first, first + int((v.right - v.left) / BLOCK) + 3):
		var count := 2 + int(CityKit.roll(seed, b, 40) * 2.6)
		var weights := []
		var total := 0.0
		for j in count:
			var wt := 0.6 + CityKit.roll(seed, b, 41 + j)
			weights.append(wt)
			total += wt
		var x := b * BLOCK
		for j in count:
			var w: float = BLOCK * float(weights[j]) / total
			var bs := absi(hash([seed, b, j]))
			var gap := 2.0 if CityKit.roll(bs, 1) < 0.85 else 8.0
			if CityKit.roll(bs, 2) < 0.25 * (1.0 - clampf(float(d["population"]), 0.0, 1.0)):
				_lot(v, k, x, w, bs, base)                               # an empty lot
			elif not _in_gap(spec, x, x + w):
				var storeys := lo + int(roundf(CityKit.roll(bs, 3) * (hi - lo) * (0.35 + 0.65 * dev)))
				var h := minf(18.0 + storeys * CityKit.STOREY, cap)
				var kind: String = roofs[posmod(bs, roofs.size())]
				var shut := CityKit.roll(bs, 4) < unemployment * 2.4
				CityKit.facade(v, k, x + gap * 0.5, w - gap, h, base, bs, kind, lit, shut, boarded, t)
			x += w


static func _in_gap(spec: Dictionary, a: float, b: float) -> bool:
	for g in spec.get("gaps", []):
		if b > float(g[0]) and a < float(g[1]):
			return true
	return false


static func _lot(v: DeskView, k: Dictionary, x: float, w: float, s: int, base: float) -> void:
	var wall_c := CityKit.wall(k, s).darkened(0.25)
	v.rect(x, base - 12, w, 12, wall_c)
	v.rect(x, base - 12, w, 1.5, wall_c.lightened(0.2))
	if CityKit.roll(s, 9) < 0.5:
		v.rect(x + 6, base - 22, 22, 12, DeskView.PAPER.darkened(0.45))   # a hoarding
		v.rect(x + 8, base - 20, 14, 2, DeskView.ALARM.darkened(0.4))


# --- the street -------------------------------------------------------------

static func street(v: DeskView, t: float, d: Dictionary, k: Dictionary, spec: Dictionary) -> void:
	var w := v.right - v.left
	var paved: bool = not spec.get("dirt", false) or float(d["development"]) >= 0.6
	v.rect(v.left, GROUND, w, ROAD_TOP - GROUND, k["paving"])
	v.rect(v.left, ROAD_TOP - 2, w, 2, k["kerb"])
	var road: Color = k["road"] if paved else (k["land"] as Color).darkened(0.25)
	v.rect(v.left, ROAD_TOP, w, KERB - ROAD_TOP, road)
	if paved:
		for x: float in CityKit.span(v, 30.0):
			v.rect(x, 257.5, 14, 1.5, (k["kerb"] as Color).darkened(0.1))   # the centre line
	else:
		for x: float in CityKit.span(v, 9.0):
			for lane in 3:
				v.rect(x + lane * 3.0, ROAD_TOP + 5 + lane * 10.0, 5, 1.2, road.lightened(0.12))   # ruts and stones
	if spec.get("tram", false) and paved:
		for y: float in [LANE_NEAR - 0.5, LANE_NEAR + 2.5]:
			v.rect(v.left, y, w, 1, (k["kerb"] as Color).lightened(0.1))
		v.line(Vector2(v.left, WIRE), Vector2(v.right, WIRE), k["metal"], 1.0)
		for x: float in CityKit.span(v, 150.0, 40.0):
			v.rect(x, WIRE - 4, 2, GROUND + 4 - WIRE, k["metal"])
	# The near kerb and the near pavement.
	v.rect(v.left, KERB, w, 3, k["kerb"])
	v.rect(v.left, KERB + 3, w, SIZE.y - KERB - 3, (k["paving"] as Color).darkened(0.05))
	for x: float in CityKit.span(v, 26.0):
		v.rect(x, KERB + 3, 1, SIZE.y - KERB - 3, (k["paving"] as Color).darkened(0.3))
	v.rect(v.left, 286, w, 1, (k["paving"] as Color).darkened(0.3))
	# People on the far pavement, small with the distance.
	var walkers := int(4 + float(d["population"]) * 10 + float(d["development"]) * 6)
	if k["lit"]:
		walkers = int(walkers * 0.6)
	for i in walkers:
		var r := CityKit.roll(int(d["seed"]), i, 60)
		var dir := 1.0 if r < 0.5 else -1.0
		var sp := (5.0 + 5.0 * CityKit.roll(i, 61)) * dir
		var x := fposmod(r * 2000.0 + sp * t, w + 40.0) + v.left - 20.0
		v.figure(x, ROAD_TOP - 1, CityKit.coat(k, i), "walk", t + i, 13.0)


## Cars, buses, lorries and the tram, two lanes in opposite directions.
## Busier with people, money and work; stopped dead by a riot.
static func traffic(v: DeskView, t: float, d: Dictionary, k: Dictionary, spec: Dictionary) -> void:
	var w := v.right - v.left
	var dev := float(d["development"])
	var busy := float(d["population"]) * (0.4 + 0.6 * dev) * (1.0 - float(d["unemployment"]))
	var count := 2 + int(busy * 7.0)
	if mood(d) == "unrest":
		count = 1
	var industrial := String(d["id"]) in ["zavost", "darev", "sela", "karsen"]
	for i in count:
		var lane := i % 2
		var dir := 1.0 if lane == 1 else -1.0
		var y := LANE_NEAR if lane == 1 else LANE_FAR
		var r := CityKit.roll(int(d["seed"]), i, 70)
		var sp := (22.0 + 14.0 * CityKit.roll(i, 71)) * dir
		var x := fposmod(r * 3000.0 + sp * t, w + 120.0) + v.left - 60.0
		var tone: Color = CityKit.LIVERY[posmod(i * 7 + int(d["seed"]), CityKit.LIVERY.size())]
		var kind := CityKit.roll(int(d["seed"]), i, 72)
		if dev > 0.45 and kind < 0.15:
			CityKit.coach(v, k, x, y, dir, 46.0, Color(0.55, 0.42, 0.18), false, WIRE)
		elif industrial and kind < 0.45:
			CityKit.lorry(v, k, x, y, dir, tone, Color(0.36, 0.34, 0.30))
		else:
			CityKit.car(v, k, x, y, dir, tone, 20.0 + 5.0 * CityKit.roll(i, 73))
	if spec.get("tram", false) and dev >= 0.45 and mood(d) != "unrest":
		var x := fposmod(t * 16.0 + 560.0, w + 260.0) + v.left - 130.0
		CityKit.coach(v, k, x, LANE_NEAR + 2, 1.0, 64.0, Color(0.62, 0.22, 0.16), true, WIRE)


## Restless streets gather knots of people and placards; unrest fills the
## road with a crowd facing a police line, a car burning between them.
static func unrest(v: DeskView, t: float, d: Dictionary, k: Dictionary) -> void:
	var m := mood(d)
	if m == "calm":
		return
	var seed: int = d["seed"]
	if m == "restless":
		for i in 7:
			var x := CX + 150.0 + i * 7.0 + CityKit.roll(seed, i, 80) * 4.0
			var foot := ROAD_TOP - 1.0 + (i % 2) * 2.0
			v.figure(x, foot, CityKit.coat(k, i + 2), "stand", t, 14.0)
			if i % 3 == 0:
				CityKit.placard(v, x, foot - 14.0, t, i)
		return
	# The burning car, a crowd in the road, the line facing it.
	var wreck := CX - 210.0
	v.rect(wreck, LANE_FAR - 9, 24, 6, Color(0.10, 0.09, 0.09))
	v.rect(wreck + 5, LANE_FAR - 14, 12, 5, Color(0.07, 0.07, 0.07))
	CityKit.fire(v, wreck + 12, LANE_FAR - 9, 1.1, t)
	var crowd := 22 + int(float(d["trouble"]) * 18.0)
	for i in crowd:
		var x := CX - 150.0 + CityKit.roll(seed, i, 81) * 190.0
		var foot := LANE_FAR - 4.0 + CityKit.roll(seed, i, 82) * 18.0
		var pose := "arms_up" if sin(t * 1.3 + i * 2.1) > 0.6 else "stand"
		var h := 15.0 + (foot - LANE_FAR) * 0.2
		v.figure(x, foot, CityKit.coat(k, i), pose, t, h)
		if CityKit.roll(seed, i, 83) < 0.3:
			CityKit.placard(v, x, foot - h, t, i)
	for i in 9:
		var x := CX + 80.0 + i * 10.0
		CityKit.riot_officer(v, x, LANE_FAR + 2.0 + (i % 2) * 9.0, 17.0, t, i)
	# The van behind the line.
	var vx := CX + 190.0
	v.rect(vx, LANE_FAR - 22, 44, 19, CityKit.POLICE.lightened(0.15))
	v.rect(vx + 32, LANE_FAR - 18, 10, 7, Color(0.10, 0.11, 0.14))
	for wx: float in [vx + 8.0, vx + 34.0]:
		v.disc(Vector2(wx, LANE_FAR - 2.5), 3.0, Color(0.04, 0.04, 0.05))
	CityKit.siren(v, vx + 22, LANE_FAR - 23, t)


## The near pavement: lamps and their pools, street trees, the people who
## pass close to us, a brazier where people have nowhere warmer to be.
static func pavement(v: DeskView, t: float, d: Dictionary, k: Dictionary, spec: Dictionary) -> void:
	var seed: int = d["seed"]
	var reach := float(d["reach"])
	var trees: bool = spec.get("trees", false)
	for x: float in CityKit.span(v, 120.0, 30.0):
		var i := int(roundf(x / 120.0))
		var on := CityKit.roll(seed, i, 90) < 0.35 + reach * 0.75 - (0.3 if mood(d) == "unrest" else 0.0)
		CityKit.lamp(v, k, x, KERB + 4, 64.0, on, t)
		if trees:
			_tree(v, k, x + 60.0, KERB + 5, i, t)
	var walkers := int(5 + float(d["population"]) * 10)
	if k["lit"]:
		walkers = int(walkers * 0.6)
	var w := v.right - v.left
	for i in walkers:
		var r := CityKit.roll(seed, i, 91)
		var dir := 1.0 if r < 0.5 else -1.0
		var sp := (9.0 + 6.0 * CityKit.roll(i, 92)) * dir
		var x := fposmod(r * 2500.0 + sp * t, w + 60.0) + v.left - 30.0
		var foot := 289.0 + CityKit.roll(i, 93) * 10.0
		v.figure(x, foot, CityKit.coat(k, i + 3), "walk", t + i * 0.3, 25.0 + (foot - 289.0) * 0.5)
	# Men with no work to go to, standing about.
	var idle := int(float(d["unemployment"]) * 30.0)
	for i in mini(idle, 6):
		var x := 60.0 + CityKit.roll(seed, i, 94) * 600.0
		v.figure(x, 294.0, CityKit.coat(k, i), "stand", t, 26.0)
	if mood(d) != "calm":
		CityKit.barrel(v, k, SIZE.x * 0.16, 296.0, t, 26.0)


static func _tree(v: DeskView, k: Dictionary, x: float, foot: float, i: int, t: float) -> void:
	var leaf := (k["land"] as Color).darkened(0.1)
	v.rect(x - 1.5, foot - 30, 3, 30, Color(0.18, 0.13, 0.10).lerp(Color(0.06, 0.05, 0.04), k["n"]))
	var sway := sin(t * 0.6 + i) * 0.8
	v.disc(Vector2(x + sway, foot - 40), 12, leaf)
	v.disc(Vector2(x - 8 + sway, foot - 33), 8, leaf.darkened(0.15))
	v.disc(Vector2(x + 8 + sway, foot - 34), 9, leaf.darkened(0.1))
	v.disc(Vector2(x - 3 + sway, foot - 46), 6, leaf.lightened(0.12))
