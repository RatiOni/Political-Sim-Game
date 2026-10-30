class_name RegionProjects
extends RefCounted

## The visible work of a regional programme, drawn into the city scene in the
## same large shapes as the rest of it. Each programme looks like what it is,
## so the picture says which one is running without reading the panel:
##   industrial_recovery       a tower crane over a scaffolded building, welding
##                             sparks, a lorry of girders
##   public_works              roadworks: cones, a flashing barrier, an
##                             excavator digging, a roller, a crew in vests
##   administrative_deployment a banner on the state office, a queue at its door,
##                             officials' black cars at the kerb
##   customs_enforcement       a booth and a barrier lifting for a lorry queue
##   security_stabilisation    a sandbagged post, armoured cars with flashing
##                             lights, a foot patrol
##
## `a` holds the scene's anchors (see `RegionCity.ANCHORS` and
## `CityHarbour.ANCHORS`): where buildings stand ("site"), the far pavement
## ("back"), the two lanes ("far", "near") and the near pavement ("front").

const STEEL := Color(0.46, 0.47, 0.50)
const BLACK_CAR := Color(0.08, 0.08, 0.09)
const SANDBAG := Color(0.48, 0.42, 0.30)
const LABELS := {
	"industrial_recovery": "INDUSTRIAL RECOVERY", "public_works": "PUBLIC WORKS",
	"administrative_deployment": "STATE OFFICE", "customs_enforcement": "CUSTOMS",
	"security_stabilisation": "SECURITY POST",
}


static func anchors() -> Dictionary:
	return {"site": RegionCity.GROUND, "back": RegionCity.ROAD_TOP - 1.0, "far": RegionCity.LANE_FAR,
		"near": RegionCity.LANE_NEAR, "front": 292.0}


## Behind the traffic: what stands on the building line and the far pavement.
static func back(v: DeskView, t: float, d: Dictionary, k: Dictionary, a: Dictionary = {}) -> void:
	if a.is_empty():
		a = anchors()
	match String(d.get("program", "")):
		"industrial_recovery": _industry(v, t, k, a)
		"administrative_deployment": _offices(v, t, k, a)


## In the road and on the near pavement.
static func front(v: DeskView, t: float, d: Dictionary, k: Dictionary, a: Dictionary = {}) -> void:
	if a.is_empty():
		a = anchors()
	match String(d.get("program", "")):
		"public_works": _roadworks(v, t, k, a)
		"customs_enforcement": _checkpoint(v, t, k, a)
		"security_stabilisation": _patrols(v, t, d, k, a)


static func _industry(v: DeskView, t: float, k: Dictionary, a: Dictionary) -> void:
	var site: float = a["site"]
	var x: float = a.get("works_x", 100.0)
	var crane := Color(0.85, 0.62, 0.16).lerp(Color(0.34, 0.25, 0.08), k["n"] * 0.8)
	# Scaffolding up the face of the building going up.
	var pole: Color = STEEL.lerp(CityKit.dim(STEEL, 0.45), k["n"])
	for px in range(int(x - 6), int(x + 76), 13):
		v.rect(px, site - 92, 1.5, 92, pole)
	for py in range(int(site - 90), int(site), 15):
		v.rect(x - 6, py, 82, 1.5, pole)
		v.rect(x - 6, py + 1.5, 82, 2, (k["roof"] as Color).lightened(0.15))   # the boards
	# The tower crane: lattice mast, jib, counter-jib, the trolley and hook.
	var top := site - 150.0
	var mx := x + 90.0
	v.line(Vector2(mx, site), Vector2(mx, top), crane, 2.0)
	v.line(Vector2(mx + 7, site), Vector2(mx + 7, top), crane, 2.0)
	for y in range(int(top), int(site), 10):
		v.line(Vector2(mx, y), Vector2(mx + 7, y + 10), crane, 1.0)
	v.rect(mx - 110, top - 4, 150, 4, crane)
	v.line(Vector2(mx + 3, top - 18), Vector2(mx - 100, top - 4), crane, 1.0)
	v.line(Vector2(mx + 3, top - 18), Vector2(mx + 38, top - 4), crane, 1.0)
	v.rect(mx + 1, top - 18, 4, 14, crane)
	v.rect(mx + 22, top, 16, 10, (k["metal"] as Color).lightened(0.2))     # counterweight
	v.rect(mx - 2, top, 10, 8, crane.darkened(0.2))
	v.rect(mx, top + 2, 5, 4, DeskView.LAMP.darkened(0.2) if k["lit"] else k["glass"])
	var run := mx - 90.0 + 60.0 * (0.5 - 0.5 * cos(t * 0.25))
	var drop := 40.0 + 30.0 * (0.5 - 0.5 * cos(t * 0.25 + 1.0))
	v.rect(run - 3, top, 6, 3, crane.darkened(0.2))
	v.line(Vector2(run, top + 3), Vector2(run, top + drop), pole.lightened(0.3), 1.0)
	v.rect(run - 14, top + drop, 28, 3, STEEL.lerp(CityKit.dim(STEEL, 0.5), k["n"]))
	if k["lit"]:
		v.rect(mx + 2, top - 20, 2, 2, DeskView.ALARM if int(t * 1.2) % 2 == 0 else DeskView.ALARM.darkened(0.6))
	# Welding on the frame: a white flash, then sparks falling and cooling.
	for site_i in 3:
		var sx := x + 12.0 + site_i * 22.0
		var sy := site - 70.0 + site_i * 18.0
		if sin(t * 5.0 + site_i * 2.1) > 0.4:
			CityKit.glow(v, Vector2(sx, sy), 10.0, Color(0.75, 0.85, 1.0), 2.0)
			v.rect(sx - 1, sy - 1, 2, 2, Color(1, 1, 1))
		for i in 5:
			var age := fposmod(t * 1.4 + i * 0.2 + site_i, 1.0)
			v.rect(sx + (i - 2) * age * 4.0, sy + age * age * 22.0, 1.5, 1.5, Color(1.0, 0.75, 0.3, 1.0 - age))
	v.label(Vector2(x - 10, top - 26), LABELS["industrial_recovery"], Vector2(mx, top - 18))


static func _roadworks(v: DeskView, t: float, k: Dictionary, a: Dictionary) -> void:
	var y: float = a["near"]
	var x0 := RegionCity.CX + 70.0
	var amber := CityKit.HI_VIS
	# The closed lane: barrier boards, cones and a flashing lamp.
	for i in 6:
		v.rect(x0 - 26 + i * 4.0, y - 12, 4, 3, amber if i % 2 == 0 else DeskView.PAPER.darkened(0.1))
	v.rect(x0 - 25, y - 9, 1.5, 9, STEEL)
	v.rect(x0 - 3, y - 9, 1.5, 9, STEEL)
	if sin(t * 6.0) > 0.0:
		v.rect(x0 - 15, y - 16, 4, 3, amber)
		CityKit.glow(v, Vector2(x0 - 13, y - 15), 14.0, amber, 1.5)
	for i in 8:
		var cx := x0 + 4.0 + i * 15.0
		v.poly(PackedVector2Array([Vector2(cx - 3, y), Vector2(cx, y - 9), Vector2(cx + 3, y)]), amber)
		v.rect(cx - 1.8, y - 5, 3.6, 1.5, DeskView.PAPER)
	# The excavator: tracks, cab, and an arm that digs and lifts.
	var ex := x0 + 24.0
	var yellow := Color(0.86, 0.66, 0.16).lerp(Color(0.40, 0.30, 0.08), k["n"] * 0.7)
	v.rect(ex, y - 6, 30, 6, Color(0.10, 0.10, 0.10))
	v.rect(ex + 4, y - 20, 20, 14, yellow)
	v.rect(ex + 7, y - 18, 8, 7, k["glass"] if not k["lit"] else DeskView.LAMP.darkened(0.4))
	var dig := 0.5 + 0.5 * sin(t * 0.9)
	var shoulder := Vector2(ex + 24, y - 16)
	var elbow := Vector2(ex + 44, y - 34 + dig * 8.0)
	var bucket := elbow + Vector2(10, 12 + dig * 14.0)
	v.line(shoulder, elbow, yellow, 3.0)
	v.line(elbow, bucket, yellow.darkened(0.1), 2.5)
	v.poly(PackedVector2Array([bucket + Vector2(-4, 0), bucket + Vector2(5, -2), bucket + Vector2(4, 6)]), Color(0.30, 0.24, 0.16))
	# Spoil heap, and the roller crawling over fresh asphalt.
	v.poly(PackedVector2Array([Vector2(ex + 50, y), Vector2(ex + 60, y - 7), Vector2(ex + 72, y)]), Color(0.32, 0.25, 0.18).lerp(Color(0.10, 0.08, 0.06), k["n"]))
	var rx := x0 + 90.0 + sin(t * 0.3) * 12.0
	v.rect(x0 + 80, y - 1, 46, 1.5, Color(0.04, 0.04, 0.05))
	v.rect(rx, y - 13, 16, 9, yellow)
	v.disc(Vector2(rx - 2, y - 5), 5, STEEL.darkened(0.2))
	v.disc(Vector2(rx + 14, y - 4), 4, Color(0.06, 0.06, 0.06))
	# The crew in vests, one leaning on a shovel.
	for i in 3:
		var fx := x0 + 10.0 + i * 22.0
		var bob := floorf(maxf(0.0, sin(t * 3.0 + i)) * 1.5)
		v.figure(fx, a["front"] - 4.0 - bob, amber.darkened(0.05), "stand", t, 18.0)
	v.label(Vector2(x0 - 30, y - 34), LABELS["public_works"], Vector2(x0 - 13, y - 17))


static func _offices(v: DeskView, t: float, k: Dictionary, a: Dictionary) -> void:
	var site: float = a["site"]
	var door := RegionCity.CX - 220.0
	# The banner across the office front and its flag.
	v.rect(door - 30, site - 52, 64, 10, DeskView.LAMP.darkened(0.25 + 0.25 * k["n"]))
	v.rect(door - 26, site - 48, 56, 2, Color(0.30, 0.10, 0.08))
	v.rect(door - 10, site - 18, 20, 18, (k["walls"][0] as Color).darkened(0.6))
	if k["lit"]:
		v.rect(door - 8, site - 16, 16, 14, DeskView.LAMP.darkened(0.1))
	# A queue at the door, shuffling forward; clerks crossing with files.
	for i in 9:
		var shuffle := fposmod(t * 0.4 + i * 0.37, 1.0) * 1.2
		v.figure(door + 14.0 + i * 8.0 + shuffle, a["back"], CityKit.coat(k, i), "stand", t, 13.0)
	for i in 2:
		var dir := 1.0 if i == 0 else -1.0
		var cx := door - 60.0 + fposmod(t * 6.0 * dir + i * 80.0, 140.0)
		v.figure(cx, a["back"] + 1.0, Color(0.18, 0.20, 0.26), "walk", t, 13.0)
		v.rect(cx + 1, a["back"] - 7, 3, 4, DeskView.PAPER)
	# Officials' cars parked at the far kerb.
	for i in 2:
		CityKit.car(v, k, door + 30.0 + i * 30.0, a["far"], -1.0, BLACK_CAR, 24.0)
	v.label(Vector2(door - 40, site - 70), LABELS["administrative_deployment"], Vector2(door, site - 52))


static func _checkpoint(v: DeskView, t: float, k: Dictionary, a: Dictionary) -> void:
	var y: float = a["far"]
	var bx := RegionCity.CX + 236.0
	var booth := Color(0.54, 0.52, 0.46).lerp(Color(0.20, 0.19, 0.17), k["n"])
	v.rect(bx - 24, y - 30, 16, 26, booth)
	v.rect(bx - 26, y - 32, 20, 3, booth.darkened(0.3))
	v.rect(bx - 21, y - 25, 10, 8, DeskView.LAMP.darkened(0.1) if k["lit"] else k["glass"])
	if k["lit"]:
		CityKit.pool(v, Vector2(bx - 16, y), 30, 5, Color(1, 0.9, 0.7, 0.14))
	# The arm lifts for a few seconds, then drops for the next inspection.
	var cycle := fposmod(t, 9.0)
	var lift := clampf(minf(cycle - 6.0, 9.0 - cycle) * 2.0, 0.0, 1.0)
	v.rect(bx - 2, y - 14, 4, 12, STEEL.darkened(0.3))
	var dir := Vector2(cos(-lift * 1.3), sin(-lift * 1.3))
	for i in 9:
		var p := Vector2(bx, y - 12) + dir * i * 5.0
		v.rect(p.x, p.y - 1.5, 5, 3, DeskView.ALARM.darkened(0.1) if i % 2 == 0 else DeskView.PAPER.darkened(0.15))
	# A queue of lorries; the front one creeps through when the arm is up.
	for i in 4:
		var creep := lift * 8.0 if i == 0 else 0.0
		CityKit.lorry(v, k, bx - 48.0 - i * 42.0 + creep, y, 1.0, CityKit.LIVERY[i], Color(0.34, 0.32, 0.28))
	var walk := bx - 80.0 + sin(t * 0.25) * 40.0
	v.figure(walk, a["back"], Color(0.20, 0.26, 0.36), "walk", t, 13.0)
	v.label(Vector2(bx - 40, y - 52), LABELS["customs_enforcement"], Vector2(bx - 16, y - 32))


static func _patrols(v: DeskView, t: float, d: Dictionary, k: Dictionary, a: Dictionary) -> void:
	var olive: Color = CityKit.OLIVE.lerp(CityKit.OLIVE.lightened(0.1), k["n"])
	# The sandbagged post on the near pavement, a soldier behind it.
	var px := RegionCity.CX - 140.0
	var foot: float = a["front"]
	v.figure(px + 10, foot - 2, olive.lightened(0.1), "stand", t, 20.0)
	for row in 3:
		for i in 6 - row:
			v.rect(px + row * 4.0 + i * 8.0, foot - 6.0 - row * 5.0, 8, 5, SANDBAG.lerp(CityKit.dim(SANDBAG, 0.45), k["n"]).darkened(0.12 * ((i + row) % 2)))
	# Armoured cars on both lanes, roof lights flashing.
	var w := v.right - v.left
	for i in 2:
		var dir := 1.0 if i == 0 else -1.0
		var x := fposmod(t * 14.0 * dir + i * w * 0.5 + 360.0, w + 80.0) + v.left - 40.0
		var y: float = a["near"] if i == 0 else a["far"]
		v.rect(x, y - 12, 38, 9, olive)
		v.rect(x + 8, y - 18, 18, 6, olive.lightened(0.1))
		v.rect(x + 12, y - 16, 8, 2.5, Color(0.08, 0.09, 0.10))
		CityKit.siren(v, x + 17, y - 19, t, i)
		for wx: float in [x + 6.0, x + 19.0, x + 32.0]:
			v.disc(Vector2(wx, y - 3), 3.0, Color(0.04, 0.04, 0.05))
	# A foot patrol in step along the far pavement.
	for i in 4:
		var x := fposmod(t * 6.0 + i * 9.0 + 520.0, w + 40.0) + v.left - 20.0
		v.figure(x, a["back"], olive.lightened(0.15), "walk", t, 13.0)
	v.label(Vector2(px - 20, foot - 46), LABELS["security_stabilisation"], Vector2(px + 14, foot - 22))
