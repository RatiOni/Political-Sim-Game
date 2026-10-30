class_name CityLandmarks
extends RefCounted

## Each inland region's landmark, the subject of its street (see
## `RegionCity`). Floodlit stone by night, mid stone by day: always the
## brightest, cleanest mass in the frame, like the rostrum in the chamber.
##
##   vashtera  the Assembly's dome over its colonnade; factory stacks beyond
##   karsen    the rail viaduct across the pass, a train passing behind the
##             spires of three churches
##   zavost    the works: stacks, sawtooth hall, cooling tower, pipe bridge
##   darev     the frontier watchtower in its wired compound, the border fence
##   orvena    the citadel on its hill above the town
##   sela      grain elevators and a windmill among the fields
##   anera     the hills, and the monastery on its crag
##   kostrel   Rovets: the domed covered market, the co-operative water tower,
##             vineyards and orchards running out over the steppe

const CX := RegionCity.CX
const G := RegionCity.GROUND
const H := RegionCity.HORIZON
const LABELS := {
	"vashtera": [Vector2(470, 40), "THE ASSEMBLY", Vector2(400, 70)],
	"karsen": [Vector2(560, 104), "KARSEN VIADUCT", Vector2(600, 124)],
	"zavost": [Vector2(470, 92), "ZAVOST WORKS", Vector2(470, 120)],
	"darev": [Vector2(420, 78), "BORDER POST", Vector2(384, 104)],
	"orvena": [Vector2(470, 50), "ORVENA CITADEL", Vector2(440, 70)],
	"sela": [Vector2(420, 90), "GRAIN ELEVATORS", Vector2(404, 104)],
	"anera": [Vector2(430, 34), "MONASTERY OF ST ANER", Vector2(392, 52)],
	"kostrel": [Vector2(470, 70), "ROVETS COVERED MARKET", Vector2(400, 96)],
}


## Floodlit stone: warm and lit at night, mid stone by day.
static func stone(k: Dictionary) -> Color:
	return Color(0.50, 0.48, 0.42).lerp(Color(0.46, 0.40, 0.31), k["n"])


## Behind the far skyline: mountains, hills, fields.
static func far(v: DeskView, t: float, d: Dictionary, k: Dictionary) -> void:
	match String(d["id"]):
		"karsen": _peaks(v, d, k, 72.0)
		"anera", "darev": _hills(v, t, d, k)
		"orvena": _peaks(v, d, k, 110.0)


## The ground between the far city and the street, and anything that stands
## behind the street row.
static func behind(v: DeskView, t: float, d: Dictionary, k: Dictionary) -> void:
	var id := String(d["id"])
	var ground: Color = (k["far"] as Color).lerp(k["paving"], 0.35)
	if id in ["sela", "anera", "darev", "orvena", "kostrel"]:
		ground = (k["land"] as Color)
	v.rect(v.left, H, v.right - v.left, G - H, ground)
	match id:
		"vashtera": _parliament(v, t, d, k)
		"karsen": _viaduct(v, t, d, k)
		"zavost": _works(v, t, d, k)
		"darev": _frontier(v, t, d, k)
		"orvena": _citadel(v, t, d, k)
		"sela": _fields(v, t, d, k)
		"anera": _crag(v, t, d, k)
		"kostrel": _market(v, t, d, k)
	var l: Array = LABELS.get(id, [])
	if not l.is_empty():
		v.label(l[0], l[1], l[2])


## Over the street: what stands on the road or the pavement.
static func front(v: DeskView, t: float, d: Dictionary, k: Dictionary) -> void:
	match String(d["id"]):
		"darev": _checkpoint(v, t, d, k)
		"vashtera": _steps(v, k)


# --- far ground ---------------------------------------------------------

static func _peaks(v: DeskView, d: Dictionary, k: Dictionary, top: float) -> void:
	var rock: Color = (k["haze"] as Color).lerp(k["sky_low"], 0.35)
	var snow := Color(0.62, 0.62, 0.62).lerp(Color(0.22, 0.23, 0.28), k["n"])
	for x: float in CityKit.span(v, 120.0, 20.0):
		var i := int(roundf(x / 120.0))
		var peak := top + CityKit.roll(int(d["seed"]), i, 300) * 40.0
		var px := x + 40.0 + CityKit.roll(int(d["seed"]), i, 301) * 40.0
		v.poly(PackedVector2Array([Vector2(x - 40, H), Vector2(px, peak), Vector2(x + 170, H)]), rock)
		v.poly(PackedVector2Array([Vector2(px - 14, peak + 12), Vector2(px, peak), Vector2(px + 17, peak + 12), Vector2(px + 4, peak + 9)]), snow)


## Hill ground, `depth` 0 far .. 1 near. By night the hills stay a shade
## above the sky's darkness, greener than it, so a ridge still reads.
static func hill(k: Dictionary, depth: float) -> Color:
	var day: Color = (k["haze"] as Color).lerp(k["land"], depth * 0.9)
	var night := Color(0.075, 0.09, 0.095).lerp(Color(0.10, 0.12, 0.09), depth)
	return day.lerp(night, k["n"])


## The moonlit or daylit rim along a ridge line.
static func rim(k: Dictionary, c: Color) -> Color:
	return c.lightened(0.18).lerp(Color(0.20, 0.22, 0.24), k["n"])


static func _hills(v: DeskView, t: float, d: Dictionary, k: Dictionary) -> void:
	for layer in 3:
		var tone := hill(k, layer * 0.5)
		var base := 70.0 + layer * 34.0
		var pts := PackedVector2Array([Vector2(v.left, H + 10)])
		var ridge := PackedVector2Array()
		var x := v.left
		while x <= v.right + 8.0:
			var p := Vector2(x, base + sin(x * 0.011 + layer * 2.0) * 16.0 + sin(x * 0.029 + layer) * 7.0)
			pts.append(p)
			ridge.append(p)
			x += 8.0
		pts.append(Vector2(v.right + 8.0, H + 10))
		v.poly(pts, tone)
		for i in range(1, ridge.size()):
			v.line(ridge[i - 1], ridge[i], rim(k, tone), 1.5)
		if layer > 0:
			# Stands of pine along the slope, big enough to print as trees.
			for px: float in CityKit.span(v, 22.0, layer * 7.0):
				if CityKit.roll(int(d["seed"]), int(px), layer) < 0.4:
					var py := base + sin(px * 0.011 + layer * 2.0) * 16.0 + sin(px * 0.029 + layer) * 7.0 + 6.0
					v.poly(PackedVector2Array([Vector2(px - 6, py + 16), Vector2(px, py - 6), Vector2(px + 6, py + 16)]), tone.darkened(0.4))


# --- Vashtera ---------------------------------------------------------------

static func _parliament(v: DeskView, t: float, d: Dictionary, k: Dictionary) -> void:
	var s := stone(k)
	var shade := s.darkened(0.45)
	# Works stacks on the far edge of the capital, smoking when there is work.
	for x: float in [618.0, 640.0, 92.0]:
		v.rect(x, H - 64, 9, 64, (k["far"] as Color).lightened(0.1))
		v.rect(x, H - 58, 9, 2, DeskView.ALARM.darkened(0.45))
		if float(d["unemployment"]) < 0.2:
			CityKit.puffs(v, Vector2(x + 4, H - 66), 0.6, t + x, (k["haze"] as Color).lightened(0.15), 5)
	# Floodlight cones from the forecourt at night.
	if k["lit"]:
		for fx: float in [262.0, 458.0]:
			v.poly(PackedVector2Array([Vector2(fx - 3, G), Vector2(fx + 3, G), Vector2(CX + (fx - CX) * 0.2 + 30, 60), Vector2(CX + (fx - CX) * 0.2 - 30, 60)]),
				Color(1.0, 0.85, 0.6, 0.05))
	# The wings and the portico.
	v.rect(CX - 120, 160, 240, 56, s.darkened(0.08))
	v.rect(CX - 124, 156, 248, 5, s.lightened(0.12))
	for wx in range(int(CX - 112), int(CX + 112), 14):
		if absf(wx - CX) < 66:
			continue
		_window(v, k, wx, 168, 7, 13, wx)
		_window(v, k, wx, 190, 7, 13, wx + 1)
	v.rect(CX - 64, 160, 128, 56, shade)                                  # the recess
	for c in range(int(CX - 60), int(CX + 60), 12):
		v.rect(c, 162, 6, 52, s.lightened(0.15))                          # columns
		v.rect(c + 4, 162, 2, 52, s.darkened(0.2))
	v.rect(CX - 68, 150, 136, 10, s.lightened(0.05))                      # entablature
	v.poly(PackedVector2Array([Vector2(CX - 70, 150), Vector2(CX, 128), Vector2(CX + 70, 150)]), s)
	v.poly(PackedVector2Array([Vector2(CX - 54, 147), Vector2(CX, 134), Vector2(CX + 54, 147)]), s.darkened(0.25))
	# The drum, its windows, the dome, its ribs, the lantern and the flag.
	v.rect(CX - 44, 104, 88, 24, s.lightened(0.04))
	v.rect(CX - 47, 102, 94, 3, s.lightened(0.2))
	for c in range(int(CX - 38), int(CX + 38), 11):
		_window(v, k, c, 108, 5, 14, c * 3)
	var dome := PackedVector2Array()
	for i in 17:
		var a := PI + PI * i / 16.0
		dome.append(Vector2(CX + cos(a) * 42.0, 102 + sin(a) * 38.0))
	v.poly(dome, s.lightened(0.1))
	for rib: float in [-0.75, -0.4, 0.0, 0.4, 0.75]:
		var pts := PackedVector2Array()
		for i in 9:
			var y := 102.0 - 38.0 * sin(PI * 0.5 * i / 8.0)
			var half := 42.0 * cos(PI * 0.5 * i / 8.0)
			pts.append(Vector2(CX + rib * half, y))
		for i in range(1, pts.size()):
			v.line(pts[i - 1], pts[i], s.darkened(0.22), 1.2)
	v.rect(CX - 42, 99, 9, 3, s.lightened(0.3))                            # the lit shoulder
	v.rect(CX - 6, 52, 12, 13, s.lightened(0.15))
	v.rect(CX - 3, 55, 6, 7, DeskView.LAMP.darkened(0.15) if k["lit"] else k["glass"])
	v.rect(CX - 8, 50, 16, 2, s.lightened(0.3))
	v.rect(CX - 0.6, 26, 1.2, 24, k["metal"])
	_flag(v, t, Vector2(CX + 0.6, 27), Color(0.62, 0.18, 0.14))


static func _steps(v: DeskView, k: Dictionary) -> void:
	var s := stone(k)
	for i in 4:
		var half := 70.0 + i * 12.0
		v.rect(CX - half, 216 + i * 4, half * 2, 4, s.darkened(0.05 + i * 0.07))
		v.rect(CX - half, 216 + i * 4, half * 2, 1, s.lightened(0.15))


# --- Karsen ---------------------------------------------------------------

static func _viaduct(v: DeskView, t: float, d: Dictionary, k: Dictionary) -> void:
	var body: Color = (k["far"] as Color).lerp(k["stone"], 0.45)
	var coping := body.lightened(0.3)
	var deck := 124.0
	# Arched bays: a pier and a spandrel pierced by a round arch.
	for x: float in CityKit.span(v, 60.0, 10.0):
		v.rect(x, deck, 12, G - deck, body)
		v.rect(x, deck, 3, G - deck, coping.darkened(0.2))
		var arch := PackedVector2Array([Vector2(x + 12, deck), Vector2(x + 60, deck), Vector2(x + 60, deck + 30)])
		for i in 13:
			var a := PI * i / 12.0
			arch.append(Vector2(x + 36 + cos(a) * 24.0, deck + 30 - sin(a) * 22.0))
		v.poly(arch, body)
		v.rect(x + 12, deck + 60, 48, 6, body)                             # the tie course
	v.rect(v.left, deck - 3, v.right - v.left, 11, body)
	v.rect(v.left, deck - 5, v.right - v.left, 2.5, coping)
	# The train crossing the pass, lit carriages by night.
	var w := v.right - v.left
	var x0 := fposmod(t * 26.0 + 640.0, w + 420.0) + v.left - 30.0
	var car := Color(0.30, 0.34, 0.30).lerp(Color(0.10, 0.12, 0.11), k["n"])
	for c in 6:
		var x := x0 - c * 46.0
		v.rect(x, deck - 19, 43, 14, car if c > 0 else Color(0.50, 0.20, 0.14).lerp(Color(0.18, 0.08, 0.06), k["n"]))
		v.rect(x, deck - 20, 43, 1.5, car.lightened(0.2))
		if c == 0:
			v.rect(x + 34, deck - 16, 7, 5, k["glass"])
			v.rect(x + 42, deck - 10, 2, 2, DeskView.LAMP)
			if k["lit"]:
				v.poly(PackedVector2Array([Vector2(x + 44, deck - 10), Vector2(x + 110, deck - 18), Vector2(x + 110, deck - 2)]), Color(1, 0.86, 0.6, 0.09))
		else:
			for wx in range(int(x + 4), int(x + 40), 8):
				v.rect(wx, deck - 16, 5, 5, DeskView.LAMP.darkened(0.2) if k["lit"] else k["glass"])
	# Three churches stand in front of it: gothic, domed, gothic.
	_church(v, t, k, 250.0, 64.0, "spire")
	_church(v, t, k, CX, 52.0, "onion")
	_church(v, t, k, 474.0, 78.0, "spire")


static func _church(v: DeskView, t: float, k: Dictionary, x: float, top: float, kind: String) -> void:
	var s := stone(k).darkened(0.12)
	v.rect(x - 24, 170, 48, G - 170, s)
	v.poly(PackedVector2Array([Vector2(x - 27, 170), Vector2(x, 152), Vector2(x + 27, 170)]), k["roof"])
	_arched(v, k, x - 15, 182, 8, 20)
	_arched(v, k, x + 7, 182, 8, 20)
	v.rect(x - 5, G - 18, 10, 18, s.darkened(0.5))
	if kind == "spire":
		v.rect(x - 9, 104, 18, G - 104, s.lightened(0.06))
		v.rect(x + 5, 104, 4, G - 104, s.darkened(0.25))
		v.poly(PackedVector2Array([Vector2(x - 11, 104), Vector2(x, top), Vector2(x + 11, 104)]), (k["roof"] as Color).lightened(0.15))
		v.disc(Vector2(x, 120), 5, DeskView.PAPER.darkened(0.2 + 0.25 * k["n"]))
		v.line(Vector2(x, 120), Vector2(x, 117), Color(0.1, 0.1, 0.1), 1.0)
		_arched(v, k, x - 3, 132, 6, 12)
		v.rect(x - 0.6, top - 9, 1.2, 9, k["metal"])
		v.rect(x - 3, top - 7, 6, 1.2, k["metal"])
	else:
		v.rect(x - 14, 118, 28, 52, s.lightened(0.06))
		v.poly(PackedVector2Array([Vector2(x - 16, 118), Vector2(x - 17, 104), Vector2(x - 10, 92), Vector2(x, top + 8), Vector2(x + 10, 92),
			Vector2(x + 17, 104), Vector2(x + 16, 118)]), Color(0.36, 0.42, 0.40).lerp(Color(0.14, 0.17, 0.17), k["n"]))
		v.rect(x - 0.6, top - 4, 1.2, 12, DeskView.LAMP.darkened(0.3))
		v.rect(x - 3, top, 6, 1.2, DeskView.LAMP.darkened(0.3))
		for wx: float in [x - 9.0, x + 3.0]:
			_arched(v, k, wx, 132, 6, 14)


# --- Zavost ---------------------------------------------------------------

static func _works(v: DeskView, t: float, d: Dictionary, k: Dictionary) -> void:
	var running := float(d["unemployment"]) < 0.18
	var brick := Color(0.40, 0.28, 0.22).lerp(Color(0.17, 0.12, 0.10), k["n"])
	var steel: Color = (k["metal"] as Color).lightened(0.2)
	# The cooling tower, a waisted shell.
	var tower := PackedVector2Array()
	for i in 13:
		var y := 104.0 + i * (G - 104.0) / 12.0
		tower.append(Vector2(474 - (34.0 - 15.0 * sin(i / 12.0 * PI * 0.8)), y))
	for i in range(12, -1, -1):
		var y := 104.0 + i * (G - 104.0) / 12.0
		tower.append(Vector2(474 + (34.0 - 15.0 * sin(i / 12.0 * PI * 0.8)), y))
	v.poly(tower, stone(k).darkened(0.1))
	if running:
		CityKit.puffs(v, Vector2(474, 98), 1.4, t, (k["haze"] as Color).lightened(0.25), 8)
	# Four stacks with their bands, smoking when the works run.
	for i in 4:
		var x := 236.0 + i * 30.0
		var top := 40.0 + (i % 2) * 14.0
		v.rect(x, top, 12, G - top, brick)
		v.rect(x + 9, top, 3, G - top, brick.darkened(0.35))
		for band: float in [top + 6, top + 20]:
			v.rect(x - 1, band, 14, 3, DeskView.PAPER.darkened(0.35 + 0.3 * k["n"]))
		if k["lit"]:
			v.rect(x + 4, top - 2, 3, 2, DeskView.ALARM if int(t * 1.5 + i) % 2 == 0 else DeskView.ALARM.darkened(0.6))
		if running:
			CityKit.puffs(v, Vector2(x + 6, top - 4), 0.9, t + i * 2.3, (k["haze"] as Color).lightened(0.1), 6)
	# The pipe bridge across the site.
	v.rect(206, 150, 316, 4, steel)
	v.rect(206, 156, 316, 2, steel.darkened(0.3))
	for x in range(214, 520, 46):
		v.rect(x, 150, 3, G - 150, steel.darkened(0.2))
	# The sawtooth hall, its north lights glowing with the furnace inside.
	var hall := Color(0.30, 0.29, 0.28).lerp(Color(0.11, 0.11, 0.12), k["n"])
	v.rect(220, 176, 216, G - 176, hall)
	for x in range(220, 436, 27):
		v.poly(PackedVector2Array([Vector2(x, 176), Vector2(x, 160), Vector2(x + 27, 176)]), hall.lightened(0.08))
		var glass: Color = DeskView.LAMP.darkened(0.25) if (k["lit"] and running) else k["glass"]
		v.rect(x + 1, 162, 3, 13, glass)
	for x in range(228, 430, 14):
		v.rect(x, 186, 8, 10, Color(0.95, 0.55, 0.22) if (k["lit"] and running) else (k["glass"] as Color))
	# The great door: the furnace glow and sparks, or shut.
	var door := Rect2(300, 200, 44, G - 200)
	if running:
		v.rect(door.position.x, door.position.y, door.size.x, door.size.y, Color(0.95, 0.50, 0.18))
		v.rect(door.position.x + 6, door.position.y + 8, door.size.x - 12, door.size.y - 8, Color(1.0, 0.78, 0.40))
		CityKit.glow(v, door.get_center(), 36.0, Color(1.0, 0.55, 0.2), 1.0 + k["n"])
		for i in 8:
			var age := fposmod(t * 0.9 + i * 0.13, 1.0)
			v.rect(door.get_center().x + (i - 4) * 4.0 * age, door.position.y + 4 - age * 18.0 + age * age * 30.0, 1.5, 1.5, DeskView.LAMP * Color(1, 1, 1, 1.0 - age))
	else:
		v.rect(door.position.x, door.position.y, door.size.x, door.size.y, hall.darkened(0.3))
		for y in range(int(door.position.y + 3), int(G), 4):
			v.rect(door.position.x, y, door.size.x, 1, hall.lightened(0.1))
	# The gate, its sign and the wall along the street.
	v.rect(206, G - 14, 316, 14, brick.darkened(0.1))
	v.rect(206, G - 15, 316, 2, brick.lightened(0.2))
	v.rect(450, G - 26, 40, 8, DeskView.PAPER.darkened(0.3))
	v.rect(454, G - 23, 32, 2, brick)


# --- Darev ----------------------------------------------------------------

static func _frontier(v: DeskView, t: float, d: Dictionary, k: Dictionary) -> void:
	var wire: Color = (k["metal"] as Color).lightened(0.35)
	# The strip and the fence along the line, in both directions.
	v.rect(v.left, 196, v.right - v.left, 14, (k["land"] as Color).lightened(0.08))
	for x: float in CityKit.span(v, 16.0):
		v.rect(x, 186, 1.5, 26, wire.darkened(0.2))
	for y: float in [190.0, 197.0, 204.0]:
		v.line(Vector2(v.left, y), Vector2(v.right, y), wire.darkened(0.3), 1.0)
	for x: float in CityKit.span(v, 6.0):
		v.rect(x, 183 + fposmod(x, 4.0), 3, 1.2, wire)
	var conc := stone(k).darkened(0.12)
	# The searchlight, sweeping the strip at night.
	var head := Vector2(CX, 86)
	if k["lit"]:
		var a := sin(t * 0.35) * 0.9
		var far := head + Vector2(sin(a), cos(a)) * 300.0
		var side := Vector2(cos(a), -sin(a)) * 46.0
		v.poly(PackedVector2Array([head + Vector2(-2, 0), head + Vector2(2, 0), far + side, far - side]), Color(0.70, 0.80, 1.0, 0.07))
		CityKit.pool(v, Vector2(clampf(far.x, v.left, v.right), 205), 40, 6, Color(0.70, 0.80, 1.0, 0.09))
	# The tower: a tapering shaft, the glazed cabin, the searchlight on top.
	v.poly(PackedVector2Array([Vector2(CX - 7, 122), Vector2(CX + 7, 122), Vector2(CX + 12, G), Vector2(CX - 12, G)]), conc)
	v.poly(PackedVector2Array([Vector2(CX + 3, 122), Vector2(CX + 7, 122), Vector2(CX + 12, G), Vector2(CX + 6, G)]), conc.darkened(0.3))
	for y in range(130, int(G), 14):
		v.rect(CX - 9, y, 18, 1.2, conc.darkened(0.25))
	v.rect(CX - 24, 98, 48, 24, conc.lightened(0.04))
	for i in 4:
		var wx := CX - 20 + i * 11.0
		v.rect(wx, 102, 8, 11, DeskView.LAMP.darkened(0.15) if k["lit"] else k["glass"])
		v.rect(wx, 102, 8, 2, k["glint"])
	v.rect(CX - 27, 121, 54, 3, conc.lightened(0.2))
	v.rect(CX - 28, 94, 56, 5, conc.darkened(0.35))
	v.rect(CX - 6, 86, 12, 8, (k["metal"] as Color).lightened(0.3))
	v.rect(CX - 3, 88, 6, 4, DeskView.PAPER if k["lit"] else DeskView.PAPER.darkened(0.4))
	v.rect(CX + 22, 66, 1.2, 28, k["metal"])
	_flag(v, t, Vector2(CX + 23.2, 67), Color(0.62, 0.18, 0.14))
	# The compound wall at its foot, crowned with wire, and its gate.
	v.rect(272, 208, 176, 20, conc.darkened(0.1))
	v.rect(272, 207, 176, 2, conc.lightened(0.15))
	for x in range(272, 448, 16):
		v.rect(x, 209, 1, 19, conc.darkened(0.35))
	for x in range(272, 448, 5):
		v.disc(Vector2(x, 205), 2.0, wire.darkened(0.15))
	v.rect(CX - 14, 210, 28, 18, Color(0.07, 0.07, 0.07))
	for x in range(int(CX - 14), int(CX + 14), 4):
		v.rect(x, 210, 1.2, 18, wire.darkened(0.2))


static func _checkpoint(v: DeskView, t: float, d: Dictionary, k: Dictionary) -> void:
	# A barrier across the far lane by its booth; a sentry each side.
	var bx := CX + 140.0
	var booth := Color(0.36, 0.38, 0.30).lerp(Color(0.14, 0.15, 0.12), k["n"])
	v.rect(bx - 22, RegionCity.ROAD_TOP - 26, 16, 26, booth)
	v.rect(bx - 24, RegionCity.ROAD_TOP - 28, 20, 3, booth.lightened(0.2))
	v.rect(bx - 19, RegionCity.ROAD_TOP - 20, 10, 7, DeskView.LAMP.darkened(0.15) if k["lit"] else k["glass"])
	v.rect(bx - 2, RegionCity.ROAD_TOP - 12, 4, 12, booth.darkened(0.3))
	for i in 10:
		v.rect(bx + i * 5.0, RegionCity.ROAD_TOP - 11, 5, 3, DeskView.ALARM.darkened(0.1) if i % 2 == 0 else DeskView.PAPER.darkened(0.2))
	for dx: float in [-40.0, 62.0]:
		v.figure(bx + dx, RegionCity.ROAD_TOP - 1, CityKit.OLIVE.lightened(0.15), "stand", t, 15.0)
		v.rect(bx + dx + 5, RegionCity.ROAD_TOP - 13, 1.2, 9, Color(0.1, 0.1, 0.1))


# --- Orvena ---------------------------------------------------------------

static func _citadel(v: DeskView, t: float, d: Dictionary, k: Dictionary) -> void:
	var ground := hill(k, 0.8)
	var pts := PackedVector2Array([Vector2(110, G)])
	for i in 25:
		var x := 110.0 + i * 500.0 / 24.0
		var r := absf(x - CX) / 250.0
		pts.append(Vector2(x, 112.0 + 116.0 * pow(r, 2.4)))
	pts.append(Vector2(610, G))
	v.poly(pts, ground)
	for i in range(2, pts.size() - 1):
		v.line(pts[i - 1], pts[i], rim(k, ground), 1.5)
	for i in 5:
		var y := 136.0 + i * 16.0
		var x0 := 250.0 - i * 18.0 + (i % 2) * 120.0
		v.line(Vector2(x0, y), Vector2(x0 + 110, y + 8), rim(k, ground), 1.5)
	var s := stone(k)
	v.rect(262, 84, 196, 30, s.darkened(0.06))
	v.rect(258, 112, 204, 6, s.darkened(0.3))
	for x in range(262, 458, 9):
		v.rect(x, 78, 5, 6, s.darkened(0.06))
	for x in range(272, 452, 16):
		v.rect(x, 94, 2, 8, s.darkened(0.5))
	v.poly(PackedVector2Array([Vector2(296, 114), Vector2(296, 100), Vector2(304, 94), Vector2(312, 100), Vector2(312, 114)]), s.darkened(0.55))
	for tx: float in [258.0, CX - 11.0, 444.0]:
		var top := 56.0 if tx == CX - 11.0 else 64.0
		v.rect(tx, top, 22, 114 - top, s)
		v.rect(tx + 17, top, 5, 114 - top, s.darkened(0.3))
		v.rect(tx - 2, top - 2, 26, 3, s.lightened(0.2))
		for c in 3:
			v.rect(tx + c * 8.5, top - 8, 5, 6, s)
		_window(v, k, tx + 8, top + 12, 5, 9, int(tx))
	v.rect(CX - 0.6, 30, 1.2, 26, k["metal"])
	_flag(v, t, Vector2(CX + 0.6, 31), Color(0.62, 0.18, 0.14))
	if k["lit"]:
		for fx: float in [300.0, 420.0]:
			v.poly(PackedVector2Array([Vector2(fx - 2, 120), Vector2(fx + 2, 120), Vector2(fx + 30, 50), Vector2(fx - 30, 50)]), Color(1.0, 0.85, 0.6, 0.05))


# --- Sela -----------------------------------------------------------------

static func _fields(v: DeskView, t: float, d: Dictionary, k: Dictionary) -> void:
	var wheat := Color(0.50, 0.44, 0.27).lerp(Color(0.13, 0.12, 0.08), k["n"])
	var plough := Color(0.30, 0.24, 0.18).lerp(Color(0.08, 0.07, 0.06), k["n"])
	for band in 4:
		var y := H + band * 10.0
		for x: float in CityKit.span(v, 140.0, band * 37.0):
			var c := wheat if CityKit.roll(int(x), band) < 0.5 else plough
			v.rect(x, y, 140, 10, c)
			for fx in range(int(x), int(x + 140), 9):
				v.rect(fx, y + 3, 5, 1, c.darkened(0.25))
		v.rect(v.left, y, v.right - v.left, 1.2, (k["land"] as Color).darkened(0.3))   # the hedge
	# A windmill on the rise, its sails turning.
	var hub := Vector2(150, 132)
	var mill := Color(0.36, 0.30, 0.24).lerp(Color(0.12, 0.10, 0.09), k["n"])
	v.poly(PackedVector2Array([Vector2(140, H + 2), Vector2(144, 136), Vector2(156, 136), Vector2(160, H + 2)]), mill)
	v.poly(PackedVector2Array([Vector2(142, 138), Vector2(150, 126), Vector2(158, 138)]), (k["roof"] as Color))
	for i in 4:
		var a := t * 0.5 + i * PI * 0.5
		var tip := hub + Vector2(cos(a), sin(a)) * 30.0
		v.line(hub, tip, (k["stone"] as Color).lightened(0.1), 1.5)
		var side := Vector2(-sin(a), cos(a)) * 4.0
		v.poly(PackedVector2Array([hub + (tip - hub) * 0.3, tip, tip + side, hub + (tip - hub) * 0.3 + side]), (k["stone"] as Color).darkened(0.05))
	if k["lit"]:
		v.rect(148, 150, 4, 5, DeskView.LAMP.darkened(0.2))
	# The elevators: four bins, the headhouse and its leg.
	var bin := stone(k).darkened(0.05)
	for i in 4:
		var x := 286.0 + i * 25.0
		v.rect(x, 120, 23, G - 120, bin)
		v.rect(x + 17, 120, 6, G - 120, bin.darkened(0.3))
		v.poly(PackedVector2Array([Vector2(x, 120), Vector2(x + 11.5, 110), Vector2(x + 23, 120)]), bin.lightened(0.12))
		for y in range(130, int(G), 18):
			v.rect(x, y, 23, 1.2, bin.darkened(0.2))
	v.rect(390, 92, 26, G - 92, bin.lightened(0.04))
	v.rect(410, 92, 6, G - 92, bin.darkened(0.3))
	v.rect(388, 88, 30, 5, bin.darkened(0.2))
	_window(v, k, 396, 100, 7, 9, 7)
	_window(v, k, 396, 150, 7, 9, 8)
	v.line(Vector2(416, 110), Vector2(468, 200), (k["metal"] as Color).lightened(0.3), 2.0)
	v.rect(456, 196, 30, G - 196, (k["roof"] as Color).lightened(0.1))
	v.label(Vector2(170, 100), "THE MILL", hub)


# --- Anera ----------------------------------------------------------------

static func _crag(v: DeskView, t: float, d: Dictionary, k: Dictionary) -> void:
	var rock := hill(k, 0.6)
	v.poly(PackedVector2Array([Vector2(250, G), Vector2(300, 96), Vector2(330, 72), Vector2(390, 66), Vector2(420, 84), Vector2(470, G)]), rock)
	v.poly(PackedVector2Array([Vector2(390, 66), Vector2(420, 84), Vector2(470, G), Vector2(436, G)]), rock.darkened(0.25))
	for seg in [[Vector2(250, G), Vector2(300, 96)], [Vector2(300, 96), Vector2(330, 72)], [Vector2(330, 72), Vector2(390, 66)], [Vector2(390, 66), Vector2(420, 84)]]:
		v.line(seg[0], seg[1], rim(k, rock), 2.0)
	for i in 6:
		var y := 120.0 + i * 18.0
		v.line(Vector2(CX - 20 + (i % 2) * 40, y), Vector2(CX + 20 - (i % 2) * 40, y + 18), rim(k, rock), 1.5)
	var s := stone(k)
	v.rect(326, 44, 70, 24, s.darkened(0.05))
	v.rect(322, 40, 78, 5, (k["roof"] as Color).lightened(0.1))
	for x in range(332, 392, 10):
		_window(v, k, x, 50, 4, 8, x)
	v.rect(388, 18, 16, 50, s)
	v.rect(400, 18, 4, 50, s.darkened(0.3))
	v.poly(PackedVector2Array([Vector2(386, 18), Vector2(396, 4), Vector2(406, 18)]), Color(0.36, 0.42, 0.40).lerp(Color(0.14, 0.17, 0.17), k["n"]))
	_arched(v, k, 393, 24, 6, 10)
	v.rect(395.4, -2, 1.2, 7, DeskView.LAMP.darkened(0.3))
	# The village square below: a shrine and its candle.
	v.rect(CX - 8, 196, 16, 32, s.darkened(0.15))
	v.poly(PackedVector2Array([Vector2(CX - 11, 196), Vector2(CX, 186), Vector2(CX + 11, 196)]), k["roof"])
	var flick := 0.8 + 0.2 * sin(t * 7.0)
	v.rect(CX - 2, 204, 4, 6, DeskView.LAMP * Color(flick, flick, flick))
	if k["lit"]:
		CityKit.glow(v, Vector2(CX, 207), 14.0, DeskView.LAMP, 1.0)


# --- Kostrel ----------------------------------------------------------------

## Rovets, the market town of the southern steppe: vineyards and orchards on
## the rise behind it, the wine co-operative under its water tower, and the
## domed covered market with stalls spilling out in front.
static func _market(v: DeskView, t: float, d: Dictionary, k: Dictionary) -> void:
	var soil := Color(0.30, 0.25, 0.18).lerp(Color(0.08, 0.07, 0.06), k["n"])
	var vine := Color(0.20, 0.26, 0.13).lerp(Color(0.06, 0.08, 0.05), k["n"])
	v.rect(v.left, H, v.right - v.left, G - H, soil)
	for row in 6:
		var y := H + 4 + row * 7.0
		for x: float in CityKit.span(v, 12.0, row * 3.0):
			v.rect(x, y, 9, 3.5, vine)
			v.rect(x + 1, y - 2, 1, 2, vine.lightened(0.15))                   # the stakes
	# Poplars along the horizon, orchard trees on the rise.
	var leaf: Color = (k["land"] as Color).darkened(0.05)
	for x: float in CityKit.span(v, 46.0, 20.0):
		if CityKit.roll(int(d["seed"]), int(x), 500) < 0.5:
			v.rect(x - 4, H - 34, 8, 34, leaf.darkened(0.2))
			v.disc(Vector2(x, H - 34), 4, leaf.darkened(0.2))
		else:
			v.disc(Vector2(x, H - 6), 9, leaf)
			v.disc(Vector2(x - 6, H - 2), 6, leaf.darkened(0.15))
	var s := stone(k)
	# The co-operative: a long low shed, its barrels, and the water tower.
	var shed := Color(0.34, 0.27, 0.20).lerp(Color(0.14, 0.11, 0.09), k["n"])
	v.rect(252, 192, 66, G - 192, shed)
	v.poly(PackedVector2Array([Vector2(249, 192), Vector2(285, 180), Vector2(321, 192)]), k["roof"])
	v.rect(262, 202, 22, G - 202, shed.darkened(0.45))
	if k["lit"]:
		v.rect(264, 204, 18, 8, DeskView.LAMP.darkened(0.35))
	for bx: float in [292.0, 302.0, 297.0]:
		var by := G - 7.0 if bx != 297.0 else G - 14.0
		v.rect(bx - 4, by, 8, 7, Color(0.36, 0.22, 0.14).lerp(Color(0.14, 0.09, 0.06), k["n"]))
		v.rect(bx - 4, by + 2, 8, 1, (k["metal"] as Color).lightened(0.2))
	var steel: Color = (k["metal"] as Color).lightened(0.25)
	for lx: float in [272.0, 298.0]:
		v.line(Vector2(lx, G - 36), Vector2(lx + (285.0 - lx) * 0.25, 112), steel, 2.0)
	v.line(Vector2(274, 150), Vector2(296, 150), steel, 1.5)
	v.line(Vector2(274, 150), Vector2(294, 118), steel, 1.0)
	v.rect(268, 88, 34, 26, s.darkened(0.1))
	v.rect(296, 88, 6, 26, s.darkened(0.35))
	v.poly(PackedVector2Array([Vector2(266, 88), Vector2(285, 76), Vector2(304, 88)]), (k["roof"] as Color).lightened(0.1))
	v.rect(274, 98, 22, 5, CityKit.LIVERY[0].lerp(CityKit.dim(CityKit.LIVERY[0], 0.45), k["n"]))   # the co-op's painted band
	# The covered market: a long arcaded hall, a drum and dome over the crossing.
	var cx := 398.0
	v.rect(cx - 72, 168, 144, G - 168, s.darkened(0.06))
	v.rect(cx - 76, 164, 152, 5, s.lightened(0.15))
	for i in 6:
		var ax := cx - 64 + i * 22.0
		var open: Color = DeskView.LAMP.darkened(0.15) if k["lit"] else (k["glass"] as Color)
		v.rect(ax, 186, 16, G - 186, open)
		v.disc(Vector2(ax + 8, 186), 8, open)
		if k["lit"]:
			v.rect(ax + 2, G - 12, 12, 4, DeskView.LAMP.darkened(0.55))           # the stalls inside
	v.rect(cx - 30, 134, 60, 30, s)
	v.rect(cx - 33, 132, 66, 3, s.lightened(0.2))
	for wx in range(int(cx - 24), int(cx + 24), 10):
		_arched(v, k, wx, 140, 5, 14)
	var dome := PackedVector2Array()
	for i in 17:
		var a := PI + PI * i / 16.0
		dome.append(Vector2(cx + cos(a) * 30.0, 132 + sin(a) * 28.0))
	v.poly(dome, Color(0.36, 0.44, 0.40).lerp(Color(0.16, 0.19, 0.18), k["n"]))
	v.rect(cx - 29, 129, 8, 3, Color(0.50, 0.58, 0.52).lerp(Color(0.24, 0.27, 0.25), k["n"]))
	v.rect(cx - 4, 96, 8, 8, s.lightened(0.1))
	v.rect(cx - 0.6, 84, 1.2, 12, k["metal"])
	for ex: float in [cx - 72.0, cx + 60.0]:
		v.rect(ex, 150, 12, 18, s)
		v.poly(PackedVector2Array([Vector2(ex - 1, 150), Vector2(ex + 6, 140), Vector2(ex + 13, 150)]), k["roof"])
	# Stalls on the square in front: striped awnings, fruit, a few customers.
	var produce := [Color(0.62, 0.18, 0.14), Color(0.40, 0.20, 0.36), Color(0.70, 0.56, 0.20), Color(0.30, 0.42, 0.18)]
	for i in 4:
		var sx := cx - 70 + i * 38.0
		var aw: Color = [DeskView.ALARM, Color(0.30, 0.40, 0.52)][i % 2]
		aw = aw.lerp(CityKit.dim(aw, 0.45), k["n"])
		for j in 4:
			v.rect(sx + j * 7.0, G - 22, 7, 4, aw if j % 2 == 0 else DeskView.PAPER.darkened(0.25 + 0.4 * k["n"]))
		v.rect(sx, G - 18, 1.2, 18, k["metal"])
		v.rect(sx + 27, G - 18, 1.2, 18, k["metal"])
		v.rect(sx + 1, G - 9, 26, 3, (k["roof"] as Color).lightened(0.2))
		for j in 6:
			var p: Color = produce[(i + j) % produce.size()]
			v.rect(sx + 2 + j * 4.0, G - 12, 3, 3, p.lerp(CityKit.dim(p, 0.5), k["n"]))
		v.figure(sx + 12 + sin(t * 0.3 + i) * 3.0, G - 1, CityKit.coat(k, i + 1), "stand", t, 13.0)


# --- shared details --------------------------------------------------------

## A window lit warm at night, dark glass with a sky glint by day.
static func _window(v: DeskView, k: Dictionary, x: float, y: float, w: float, h: float, s: int) -> void:
	if k["lit"] and CityKit.roll(s, 77) < 0.8:
		v.rect(x, y, w, h, DeskView.LAMP.darkened(0.1 + 0.25 * CityKit.roll(s, 78)))
	else:
		v.rect(x, y, w, h, k["glass"])
		v.rect(x, y, w, 2, k["glint"])


## A round-headed window.
static func _arched(v: DeskView, k: Dictionary, x: float, y: float, w: float, h: float) -> void:
	var c: Color = DeskView.LAMP.darkened(0.25) if k["lit"] else (k["glass"] as Color)
	v.rect(x, y + w * 0.5, w, h - w * 0.5, c)
	v.disc(Vector2(x + w * 0.5, y + w * 0.5), w * 0.5, c)


static func _flag(v: DeskView, t: float, at: Vector2, c: Color) -> void:
	var pts := PackedVector2Array()
	for i in 6:
		pts.append(at + Vector2(i * 3.0, sin(t * 2.0 - i * 0.8) * 1.2 * i / 5.0))
	for i in range(5, -1, -1):
		pts.append(at + Vector2(i * 3.0, 9.0 + sin(t * 2.0 - i * 0.8) * 1.2 * i / 5.0))
	v.poly(pts, c)
