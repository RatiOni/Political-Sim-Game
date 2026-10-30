class_name RegionScene
extends RefCounted

## One region's picture as data: where everything stands (seeded from the
## region id, so a place keeps its streets all campaign) and how it is doing
## (read from the live figures, so the same town fills up, lights up, boards
## up or burns). `RegionBake` paints the still parts from this, `RegionLife`
## the moving ones. Coordinates are scene pixels.

enum Land { HIGHLAND, PASS, BASIN, INDUSTRY, FRONTIER, PLAIN, TRADE, FOOTHILL, COAST }
enum Build { COTTAGE, TOWNHOUSE, SHOP, BLOCK, WAREHOUSE, CHURCH, BARN, CIVIC, PLANT }

## Terrain character per region, from `content/lore/ardenia_map_bible.md`.
const LAND_OF := {
	"anera": Land.HIGHLAND, "karsen": Land.PASS, "vashtera": Land.BASIN,
	"zavost": Land.INDUSTRY, "darev": Land.FRONTIER, "sela": Land.PLAIN,
	"kelvet": Land.TRADE, "orvena": Land.FOOTHILL, "vetrenka": Land.COAST,
}

var region: Dictionary
var id := ""
var land := Land.PLAIN
var rng := RandomNumberGenerator.new()

# Size and the horizontal bands of the picture, top to bottom.
var cols := 400
var h := 200
var horizon := 100   # where the sky meets the land
var ground := 140    # building line: the back of the pavement
var road_top := 146
var road_h := 22
var front := 172     # the near kerb; below it, water or verge

# Condition, 0..1.
var development := 0.5
var reach := 0.5
var pressure := 0.0
var unemployment := 0.1
var population := 0.5
var trouble := 0.0
var works_running := true
var paved := true
var programme := false
var program_id := ""
## The capital stands out: the largest skyline, towers, the busiest street.
var capital := false
## Set by the bake: open sky per column, for the day grade.
var sky_mask: Image
var front_top := PackedInt32Array()   # per column, top of the street buildings
## Mid-ground high-rises: {x, w, h}. Their number grows with the city.
var towers: Array[Dictionary] = []

# Layout.
var buildings: Array[Dictionary] = []
var lamps: Array[int] = []
var chimneys: Array[Dictionary] = []
var lit_windows: Array[Vector2i] = []
var tv_windows: Array[Vector2i] = []
## Window cells that change one at a time: lit ones that go dark, dark ones
## that light up. Set by the bake.
var blink_lit: Array[Rect2i] = []
var blink_dark: Array[Rect2i] = []
var stars: Array[Vector3] = []
var clouds: Array[Dictionary] = []
var people: Array[Dictionary] = []
var cars: Array[Dictionary] = []
var boats: Array[Dictionary] = []
var fires: Array[Dictionary] = []
var beacons: Array[Vector2i] = []
var flag_at := Vector2i(-1, -1)
var crane_at := -1
var searchlight_at := Vector2i(-1, -1)
var mill_at := Vector2i(-1, -1)
var water_top := -1
## The newsreel subject: one strong landmark at the centre of the frame.
var landmark := ""
var landmark_x := 0
var clock_at := Vector2i(-1, -1)

const LANDMARK_OF := {
	Land.BASIN: "parliament", Land.INDUSTRY: "works", Land.COAST: "lighthouse",
	Land.FRONTIER: "watchtower", Land.PLAIN: "silos", Land.HIGHLAND: "monastery",
	Land.PASS: "viaduct", Land.TRADE: "clocktower", Land.FOOTHILL: "fortress",
}


static func f(region_data: Dictionary, key: String, fallback: float = 0.0) -> float:
	return clampf(float(region_data.get(key, fallback)), 0.0, 1.0)


## A stable per-feature roll: the same window stays boarded as long as the
## figures that board it hold, instead of re-rolling every bake.
func roll(a: int, b: int = 0, c: int = 0) -> float:
	return float(hash([id, a, b, c]) % 10007) / 10007.0


func setup(region_data: Dictionary, width: int, height: int) -> void:
	region = region_data
	id = String(region.get("id", "region"))
	land = LAND_OF.get(id, Land.PLAIN)
	cols = width
	h = height
	horizon = int(h * 0.50)
	ground = int(h * 0.70)
	road_top = ground + maxi(5, int(h * 0.035))
	road_h = maxi(14, int(h * 0.12))
	front = road_top + road_h
	development = f(region, "development", 0.5)
	reach = f(region, "state_reach", 0.5)
	pressure = f(region, "pressure")
	unemployment = f(region, "unemployment", 0.1)
	capital = id == "vashtera"
	# Size is relative to the nation: a region's share of the population,
	# scaled so today's capital sits near 0.9. Growth (or decline) shows.
	if region.has("population_share"):
		population = clampf(float(region["population_share"]) / 0.22 * 0.9, 0.15, 1.3)
	else:
		population = clampf(float(region.get("population", 1000.0)) / 3000.0, 0.15, 1.0)
	trouble = clampf(maxf(pressure, f(region, "insurgency")) + (0.25 if bool(region.get("civil_war", false)) else 0.0), 0.0, 1.0)
	works_running = unemployment < 0.18
	paved = development >= 0.55
	programme = region.get("active_program") != null
	if programme and region["active_program"] is Dictionary:
		program_id = String((region["active_program"] as Dictionary).get("program_id", ""))
	water_top = front + 4 if land in [Land.COAST, Land.BASIN] else -1
	_layout()


func _layout() -> void:
	rng.seed = hash(id)
	_sky()
	_town()
	_street()
	_crowd()
	_traffic()
	if land == Land.COAST:
		for i in 3:
			boats.append({"x": rng.randf_range(0.1, 0.9) * cols, "w": rng.randi_range(14, 26), "phase": rng.randf() * TAU})
	if trouble > 0.72:
		# The event at the heart of the frame: a great blaze, then smaller ones.
		fires.append({"x": landmark_x - 4, "size": 2.4})
		for i in 1 + int(trouble * 2.0):
			fires.append({"x": rng.randi_range(30, maxi(31, cols - 30)), "size": 0.6 + rng.randf() * 0.6})


func _sky() -> void:
	var count := int(cols * 0.12 * (1.0 - trouble))
	for i in count:
		stars.append(Vector3(rng.randf() * cols, rng.randf() * horizon * 0.8, rng.randf() * TAU))
	for i in 4:
		clouds.append({"x": rng.randf() * cols, "y": 8.0 + rng.randf() * horizon * 0.4,
			"w": rng.randi_range(30, 70), "speed": 1.0 + rng.randf() * 2.0})


func _town() -> void:
	var built := clampf(development * 0.65 + population * 0.35, 0.0, 1.0)
	# A civic hall in the middle where the state reaches; works on the right
	# in industrial country or anywhere rich enough.
	landmark = LANDMARK_OF.get(land, "")
	landmark_x = int(cols * 0.5)
	# The civic hall stands aside so the landmark owns the centre of frame.
	var civic_x := int(cols * 0.26) - 22
	var civic_done := reach <= 0.4
	var plant_x := cols + 1000
	if land == Land.INDUSTRY or development > 0.7:
		plant_x = cols - 96
	var x := 4
	while x < cols - 20:
		if not civic_done and x + 26 > civic_x:
			var cx := maxi(x, civic_x)
			_add(cx, 44, Build.CIVIC, 3)
			flag_at = Vector2i(cx + 22, ground - 52 - 18)
			x = cx + 47
			civic_done = true
			continue
		if x + 30 > plant_x:
			_add(plant_x, 88, Build.PLANT, 1)
			for s in 3:
				chimneys.append({"x": plant_x + 14 + s * 24, "y": ground - 40 - 30, "kind": "stack"})
				beacons.append(Vector2i(plant_x + 16 + s * 24, ground - 40 - 31))
			break
		var kind := _pick(built)
		var w := 0
		var storeys := 1
		match kind:
			Build.COTTAGE: w = rng.randi_range(16, 22)
			Build.TOWNHOUSE:
				w = rng.randi_range(18, 26)
				storeys = 2 + (1 if rng.randf() < development else 0)
			Build.SHOP:
				w = rng.randi_range(22, 30)
				storeys = 2
			Build.BLOCK:
				w = rng.randi_range(26, 38)
				storeys = 4 + int(rng.randf() * 3.5 * development)
			Build.WAREHOUSE: w = rng.randi_range(34, 50)
			Build.CHURCH:
				w = rng.randi_range(24, 30)
				storeys = 2
			Build.BARN: w = rng.randi_range(24, 32)
		_add(x, w, kind, storeys)
		if kind in [Build.COTTAGE, Build.TOWNHOUSE] and rng.randf() < 0.7:
			var b: Dictionary = buildings[-1]
			chimneys.append({"x": x + w - 6, "y": ground - int(b["h"]) - int(w * 0.45) + 1, "kind": "house"})
		x += w + (rng.randi_range(10, 24) if rng.randf() < 0.2 else rng.randi_range(1, 4))
	if programme and program_id in ["industrial_recovery", ""]:
		crane_at = 12
	_towers()
	match land:
		Land.FRONTIER: searchlight_at = Vector2i(landmark_x - 3, ground - 48)
		Land.PLAIN: mill_at = Vector2i(landmark_x + 70, horizon + 8)
	if landmark == "works":
		for k in 3:
			chimneys.append({"x": landmark_x - 40 + k * 22 + 4, "y": ground - 128, "kind": "stack"})
			beacons.append(Vector2i(landmark_x - 40 + k * 22 + 3, ground - 126))


## Towers behind the street. A city earns them by size and modernisation;
## the capital always has a cluster around its centre.
func _towers() -> void:
	var count := int(population * development * 7.0) + (4 if capital else 0)
	var spread := cols * (0.42 if capital else 0.6)
	for i in count:
		var x := int(landmark_x + (rng.randf() - 0.5) * spread)
		if absi(x - landmark_x) < 34:
			x += 70 if x >= landmark_x else -70
		var tall := (40.0 + 60.0 * population * development) * (1.25 if capital else 1.0)
		towers.append({"x": x, "w": rng.randi_range(12, 22), "h": mini(int(tall * rng.randf_range(0.55, 1.0)), ground - 24),
			"crown": rng.randf() < 0.4})


func _add(x: int, w: int, kind: int, storeys: int) -> void:
	var height := 12 + storeys * 10 + rng.randi_range(-2, 5)
	match kind:
		Build.WAREHOUSE, Build.BARN: height = 20 + rng.randi_range(0, 6)
		Build.CIVIC: height = 52
		Build.PLANT: height = 40
	buildings.append({"x": x, "w": w, "h": height, "kind": kind, "storeys": storeys,
		"tint": rng.randi_range(0, 4), "flat": kind in [Build.BLOCK, Build.SHOP, Build.WAREHOUSE] or rng.randf() < 0.2})


func _pick(built: float) -> int:
	var r := rng.randf()
	match land:
		Land.INDUSTRY, Land.FRONTIER:
			if r < 0.32 * built: return Build.BLOCK
			if r < 0.5: return Build.WAREHOUSE
			if r < 0.72: return Build.TOWNHOUSE
			return Build.COTTAGE
		Land.PLAIN:
			if r < 0.28: return Build.BARN
			if r < 0.44 and built > 0.45: return Build.SHOP
			return Build.COTTAGE
		Land.TRADE:
			if r < 0.4: return Build.SHOP
			if r < 0.55: return Build.WAREHOUSE
			return Build.TOWNHOUSE
		Land.BASIN:
			if r < (0.4 + (0.25 if capital else 0.0)) * built: return Build.BLOCK
			if r < 0.62: return Build.TOWNHOUSE
			if r < 0.78: return Build.SHOP
			return Build.COTTAGE
		Land.HIGHLAND, Land.PASS, Land.FOOTHILL:
			if r < 0.1: return Build.CHURCH
			if r < 0.32 and built > 0.55: return Build.TOWNHOUSE
			return Build.COTTAGE
	if r < 0.22: return Build.SHOP
	if r < 0.52: return Build.TOWNHOUSE
	return Build.COTTAGE


func _street() -> void:
	var x := 10 + rng.randi_range(0, 10)
	while x < cols - 6:
		lamps.append(x)
		x += 42 + rng.randi_range(-8, 8)


## People on the pavement: more where there is life, a crowd where there is
## anger. Walkers keep their own pace and direction; idlers stand and shift.
func _crowd() -> void:
	var count := int(4 + population * 14 + development * 8) + (10 if capital else 0)
	for i in count:
		var dir := 1.0 if rng.randf() < 0.5 else -1.0
		people.append({"x": rng.randf() * cols, "speed": dir * rng.randf_range(6.0, 11.0),
			"lane": rng.randi_range(0, 2), "coat": rng.randi_range(0, 5), "idle": rng.randf() < 0.2,
			"phase": rng.randf() * TAU})
	if trouble > 0.5:
		var centre := cols * (0.3 + rng.randf() * 0.4)
		for i in int(8 + trouble * 22):
			people.append({"x": centre + rng.randf_range(-40, 40), "speed": 0.0, "lane": rng.randi_range(0, 2),
				"coat": rng.randi_range(0, 5), "idle": true, "protest": true,
				"placard": rng.randf() < 0.35, "phase": rng.randf() * TAU})


func _traffic() -> void:
	var count := 1 + int((1.0 - unemployment) * development * 5.0 * maxf(population, 0.5)) + (3 if capital else 0)
	for i in count:
		var lane := i % 2
		var bus := development > 0.45 and rng.randf() < 0.18
		cars.append({"x": rng.randf() * cols, "lane": lane,
			"speed": (18.0 + rng.randf() * 16.0) * (1.0 if lane == 0 else -1.0),
			"tone": rng.randi_range(0, 4), "len": 30 if bus else rng.randi_range(14, 18), "bus": bus})
