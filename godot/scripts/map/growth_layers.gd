class_name GrowthLayers
extends RefCounted

const TOWN_CEILING := 40
const CAPITAL_CEILING := 120
const TOWN_SCALE := 0.2216
const TOWN_EXPONENT := 2.0 / 3.0
const CAPITAL_FACTOR := 1.35
const CAPITAL_CITY_WEIGHT := 2.0
const TOWN_RADIUS := 12
const FARM_REACH_BASE := 14.0
const FARM_REACH_SPAN := 10.0
const TOWER_DEVELOPMENT := 0.6
const TOWER_EVERY := 6
const FARM_FLOOR := 0.05
const FARM_CEILING := 0.6
const FARM_SLOPE := 0.55
const LIGHT_DEVELOPMENT_WEIGHT := 0.85
const LIGHT_POPULATION_WEIGHT := 0.1
const LIGHT_POPULATION_SCALE := 2000.0
const FALLOW_WEIGHT := 0.9
const BUILDABLE: Array[String] = ["sand", "grass", "farm", "fallow", "forest", "hills"]
const ARABLE: Array[String] = ["grass", "farm", "fallow"]
const ROAD_TIER_STEPS: Array[float] = [0.35, 0.65]
const PROGRAMME_ROAD_BONUS := 0.1
const TROUBLE_FLOOR := 0.5
const BARRICADE_TROUBLE := 0.7
const SECOND_BARRICADE_TROUBLE := 0.85
const INSURGENCY_WEIGHT := 0.3
const CIVIL_WAR_WEIGHT := 0.3
const VETRENKA_TROUBLE := {"routed": 0.1, "talks_failed": 0.1, "partitioned_contested": 0.1}
const SMOKE_SHARE := 0.8
const PLUME_RISE: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -2)]
const MAX_SMOKE := 20
const ROUTE_KINDS: Array[String] = ["road", "rail"]
const RAIL_DEVELOPMENT := 0.5
const HAMLET_FIRST_POPULATION := 500.0
const HAMLET_POPULATION_STEP := 250.0
const MAX_HAMLETS := 6
const HAMLET_HOUSES := 3
const HAMLET_SPACING := 6
const HAMLET_SALT := 5

static var _memo: Dictionary = {}


static func town_tiles(population_k: float, is_capital: bool) -> int:
	var base := maxf(1.0, TOWN_SCALE * pow(maxf(0.0, population_k), TOWN_EXPONENT))
	if is_capital:
		return mini(CAPITAL_CEILING, roundi(base * CAPITAL_FACTOR))
	return mini(TOWN_CEILING, roundi(base))


static func lit_share(development: float, population_k: float) -> float:
	var people := clampf(population_k / LIGHT_POPULATION_SCALE, 0.0, 1.0)
	return clampf(clampf(development, 0.0, 1.0) * LIGHT_DEVELOPMENT_WEIGHT + people * LIGHT_POPULATION_WEIGHT, 0.0, 1.0)


static func farm_share(development: float) -> float:
	return clampf(FARM_FLOOR + FARM_SLOPE * development, FARM_FLOOR, FARM_CEILING)


static func farm_reach(development: float) -> float:
	return FARM_REACH_BASE + FARM_REACH_SPAN * clampf(development, 0.0, 1.0)


static func fallow_share(development: float, pressure: float) -> float:
	return clampf(pressure, 0.0, 1.0) * (1.0 - clampf(development, 0.0, 1.0)) * FALLOW_WEIGHT


static func cell_less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


static func hash_order(cells: Array, salt: int = 0) -> Array[Vector2i]:
	var keys := PackedInt64Array()
	var span := TileBaker.GRID.x * TileBaker.GRID.y
	for cell in cells:
		keys.append(TileBaker.cell_hash(cell, salt) * span + cell.y * TileBaker.GRID.x + cell.x)
	keys.sort()
	var ordered: Array[Vector2i] = []
	for key in keys:
		var index := key % span
		ordered.append(Vector2i(index % TileBaker.GRID.x, index / TileBaker.GRID.x))
	return ordered


static func kind_at(tiles: Dictionary, cell: Vector2i) -> String:
	if not TileBaker.in_grid(cell):
		return ""
	return TileArt.KINDS[tiles["kinds"][cell.y * TileBaker.GRID.x + cell.x]]


static func _remember(key: Array, build: Callable) -> Variant:
	if not _memo.has(key):
		_memo[key] = build.call()
	return _memo[key]


static func cells_for_town(center: Vector2i, count: int, tiles: Dictionary, blocked: Dictionary = {}, claimed: Dictionary = {}) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in _town_candidates(center, tiles):
		if out.size() >= count:
			break
		if not blocked.has(TileBaker.region_at_tile(tiles, cell)) and not claimed.has(cell):
			out.append(cell)
	return out


static func _town_candidates(center: Vector2i, tiles: Dictionary) -> Array:
	return _remember(["town", center, tiles.hash()], func() -> Array:
		var candidates: Array[Vector2i] = []
		for dy in range(-TOWN_RADIUS, TOWN_RADIUS + 1):
			for dx in range(-TOWN_RADIUS, TOWN_RADIUS + 1):
				var cell := center + Vector2i(dx, dy)
				if kind_at(tiles, cell) in BUILDABLE and TileBaker.region_at_tile(tiles, cell) < MapBaker.FOREIGN_REGION:
					candidates.append(cell)
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := (a - center).length_squared()
			var db := (b - center).length_squared()
			return da < db or (da == db and cell_less(a, b)))
		return candidates)


static func hamlet_count(population_k: float) -> int:
	if population_k < HAMLET_FIRST_POPULATION:
		return 0
	return mini(MAX_HAMLETS, 1 + floori((population_k - HAMLET_FIRST_POPULATION) / HAMLET_POPULATION_STEP))


static func _hamlet_houses(population_k: float, index: int) -> int:
	var past := population_k - HAMLET_FIRST_POPULATION - index * HAMLET_POPULATION_STEP
	return clampi(1 + floori(past * HAMLET_HOUSES / HAMLET_POPULATION_STEP), 1, HAMLET_HOUSES)


static func hamlet_sites(region: int, geo: MapGeometry, tiles: Dictionary) -> Array:
	return _all_hamlet_sites(geo, tiles).get(region, [])


static func _all_hamlet_sites(geo: MapGeometry, tiles: Dictionary) -> Dictionary:
	return _remember(["hamlets", geo.cities.hash(), tiles.hash()], func() -> Dictionary:
		var near := {}
		for city in geo.cities:
			var centre := Vector2i(Vector2(city["point"]) * Vector2(TileBaker.GRID))
			for dy in range(-TOWN_RADIUS - 1, TOWN_RADIUS + 2):
				for dx in range(-TOWN_RADIUS - 1, TOWN_RADIUS + 2):
					near[centre + Vector2i(dx, dy)] = true
		var land := {}
		for y in TileBaker.GRID.y:
			for x in TileBaker.GRID.x:
				var cell := Vector2i(x, y)
				var region := TileBaker.region_at_tile(tiles, cell)
				if region < geo.region_ids.size() and not near.has(cell) and kind_at(tiles, cell) in BUILDABLE:
					if not land.has(region):
						land[region] = []
					land[region].append(cell)
		var out := {}
		for region in land:
			var sites: Array[Vector2i] = []
			for cell in hash_order(land[region], HAMLET_SALT):
				if sites.size() >= MAX_HAMLETS:
					break
				if _beyond(cell, sites, HAMLET_SPACING):
					sites.append(cell)
			out[region] = sites
		return out)


static func _beyond(cell: Vector2i, others: Array[Vector2i], gap: int) -> bool:
	for other in others:
		if maxi(absi(cell.x - other.x), absi(cell.y - other.y)) <= gap:
			return false
	return true


static func _hamlet_cells(population_k: float, region: int, geo: MapGeometry, tiles: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var sites := hamlet_sites(region, geo, tiles)
	for i in mini(hamlet_count(population_k), sites.size()):
		var houses := _hamlet_houses(population_k, i)
		for cell in [sites[i]] + TileBaker.SIDES.map(func(side: Vector2i) -> Vector2i: return sites[i] + side):
			if houses > 0 and TileBaker.region_at_tile(tiles, cell) == region and kind_at(tiles, cell) in BUILDABLE:
				out.append(cell)
				houses -= 1
	return out


static func targets(row: Dictionary, geo: MapGeometry, tiles: Dictionary) -> Dictionary:
	return all_targets([row], geo, tiles).get(String(row.get("id", "")), {})


static func all_targets(rows: Array, geo: MapGeometry, tiles: Dictionary) -> Dictionary:
	var by_id := {}
	var separatist := {}
	for row in rows:
		by_id[String(row["id"])] = row
		if String(row.get("control", "")) == "separatist":
			separatist[geo.region_ids.find(String(row["id"]))] = true
	var towns := {}
	var claimed := {}
	for city in _cities_in_claim_order(geo):
		var region_id: String = city["region"]
		if not by_id.has(region_id):
			continue
		var region := geo.region_ids.find(region_id)
		var blocked := separatist.duplicate()
		blocked.erase(region)
		var row: Dictionary = by_id[region_id]
		var share := _city_share(city, geo)
		var cells := cells_for_town(Vector2i(Vector2(city["point"]) * Vector2(TileBaker.GRID)), town_tiles(float(row.get("population", 0.0)) * share, city["capital"]), tiles, blocked, claimed)
		if not towns.has(region_id):
			towns[region_id] = {"cells": [] as Array[Vector2i], "houses": [] as Array[Vector2i], "towers": [] as Array[Vector2i], "capitals": [] as Array[Vector2i], "centres": [] as Array[Vector2i]}
		var entry: Dictionary = towns[region_id]
		entry["centres"].append(Vector2i(Vector2(city["point"]) * Vector2(TileBaker.GRID)))
		for cell in cells:
			claimed[cell] = true
			entry["cells"].append(cell)
			if city["capital"] and cell == cells[0]:
				entry["capitals"].append(cell)
			elif TileBaker.cell_hash(cell, 2) % TOWER_EVERY == 0:
				entry["towers"].append(cell)
			else:
				entry["houses"].append(cell)
	for region_id in by_id:
		var region := geo.region_ids.find(region_id)
		if region < 0:
			continue
		if not towns.has(region_id):
			towns[region_id] = {"cells": [] as Array[Vector2i], "houses": [] as Array[Vector2i], "towers": [] as Array[Vector2i], "capitals": [] as Array[Vector2i], "centres": [] as Array[Vector2i]}
		var hamlets := _hamlet_cells(float(by_id[region_id].get("population", 0.0)), region, geo, tiles)
		towns[region_id]["hamlets"] = hamlets
		for cell in hamlets:
			claimed[cell] = true
			towns[region_id]["cells"].append(cell)
			towns[region_id]["houses"].append(cell)
	var out := {}
	for region_id in towns:
		out[region_id] = _region_targets(by_id[region_id], geo.region_ids.find(region_id), towns[region_id], claimed, tiles)
	return out


static func _cities_in_claim_order(geo: MapGeometry) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	for city in geo.cities:
		if city["capital"]:
			ordered.append(city)
	for city in geo.cities:
		if not city["capital"]:
			ordered.append(city)
	return ordered


static func _city_share(city: Dictionary, geo: MapGeometry) -> float:
	var total := 0.0
	for other in geo.cities:
		if other["region"] == city["region"]:
			total += CAPITAL_CITY_WEIGHT if other["capital"] else 1.0
	return (CAPITAL_CITY_WEIGHT if city["capital"] else 1.0) / total


static func _region_targets(row: Dictionary, region: int, towns: Dictionary, claimed: Dictionary, tiles: Dictionary) -> Dictionary:
	var population := float(row.get("population", 0.0))
	var development := float(row.get("development", 0.0))
	var pressure := float(row.get("pressure", 0.0))
	var farm := _farm_cells(region, claimed, towns["centres"], development, tiles)
	var fallow_count := roundi(farm.size() * fallow_share(development, pressure))
	var lit_count := mini(towns["houses"].size(), roundi(towns["cells"].size() * lit_share(development, population)))
	return {
		"town_cells": towns["cells"],
		"tower_cells": towns["towers"] if development >= TOWER_DEVELOPMENT else [] as Array[Vector2i],
		"capital_cells": towns["capitals"],
		"hamlet_cells": towns["hamlets"],
		"lit_cells": hash_order(towns["houses"], 1).slice(0, lit_count),
		"farm_cells": farm,
		"fallow_cells": farm.slice(farm.size() - fallow_count),
	}


static func _farm_cells(region: int, occupied: Dictionary, centres: Array, development: float, tiles: Dictionary) -> Array[Vector2i]:
	var limit := farm_reach(development)
	var reachable: Array[Vector2i] = []
	for entry in _farm_candidates(region, centres, tiles):
		if entry[1] > limit:
			break
		if not occupied.has(entry[0]):
			reachable.append(entry[0])
	var out: Array[Vector2i] = []
	out.assign(reachable.slice(0, roundi(reachable.size() * farm_share(development))))
	return out


static func _farm_candidates(region: int, centres: Array, tiles: Dictionary) -> Array:
	return _remember(["farm", region, centres, tiles.hash()], func() -> Array:
		var reach := {}
		var limit := farm_reach(1.0)
		var span := ceili(limit)
		for centre in centres:
			for dy in range(-span, span + 1):
				for dx in range(-span, span + 1):
					var cell: Vector2i = centre + Vector2i(dx, dy)
					var distance := Vector2(dx, dy).length()
					if distance > limit or kind_at(tiles, cell) not in ARABLE or TileBaker.region_at_tile(tiles, cell) != region:
						continue
					if not reach.has(cell) or distance < reach[cell]:
						reach[cell] = distance
		var ordered: Array = reach.keys()
		ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return reach[a] < reach[b] or (reach[a] == reach[b] and cell_less(a, b)))
		return ordered.map(func(cell: Vector2i) -> Array: return [cell, reach[cell]]))


static func road_tier(development: float, programme_active: bool) -> int:
	var effective := development + (PROGRAMME_ROAD_BONUS if programme_active else 0.0)
	var tier := 0
	for step in ROAD_TIER_STEPS:
		tier += 1 if effective >= step else 0
	return tier


static func route_suffix(step: Vector2i) -> String:
	var sx := signi(step.x)
	var sy := signi(step.y)
	if sy == 0:
		return ""
	if sx == 0:
		return "_v"
	return "_d1" if sx == sy else "_d2"


static func trouble(row: Dictionary) -> float:
	var pressure := float(row.get("pressure", 0.0))
	if pressure < TROUBLE_FLOOR:
		return 0.0
	var extra := float(row.get("insurgency", 0.0)) * INSURGENCY_WEIGHT
	extra += CIVIL_WAR_WEIGHT if bool(row.get("civil_war", false)) else 0.0
	extra += float(VETRENKA_TROUBLE.get(String(row.get("vetrenka_status", "")), 0.0))
	return clampf(pressure + extra, 0.0, 1.0)


static func trouble_cells(row: Dictionary, town_cells: Array, route_cells: Array = []) -> Dictionary:
	var out := {"smoke": [] as Array[Vector2i], "barricade": [] as Array[Vector2i], "dim": false}
	var level := trouble(row)
	if level <= TROUBLE_FLOOR or town_cells.is_empty():
		return out
	out["dim"] = true
	var smoke_count := clampi(roundi(town_cells.size() * SMOKE_SHARE * (level - TROUBLE_FLOOR) / TROUBLE_FLOOR), 1, MAX_SMOKE)
	out["smoke"].assign(hash_order(town_cells, 4).slice(0, smoke_count))
	if level > BARRICADE_TROUBLE and String(row.get("control", "")) != "separatist":
		var barricades := 2 if level > SECOND_BARRICADE_TROUBLE else 1
		out["barricade"].assign(_nearest_to(route_cells, town_cells).slice(0, barricades))
	return out


static func _nearest_to(candidates: Array, towns: Array) -> Array[Vector2i]:
	var gap := {}
	for cell in candidates:
		var best := 1 << 30
		for town in towns:
			best = mini(best, (cell - town).length_squared())
		gap[cell] = best
	var ordered: Array[Vector2i] = []
	ordered.assign(candidates)
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return gap[a] < gap[b] or (gap[a] == gap[b] and cell_less(a, b)))
	return ordered


static func overlay(rows: Array, geo: MapGeometry, tiles: Dictionary, targets: Dictionary) -> Dictionary:
	var by_id := {}
	for row in rows:
		by_id[String(row["id"])] = row
	var routes := {}
	var open := {}
	var occupied := {}
	for region_id in targets:
		for key in ["town_cells", "farm_cells"]:
			for cell in targets[region_id][key]:
				occupied[cell] = true
	var locked := locked_rails(geo, tiles, by_id)
	for step in _route_walk(geo, tiles, by_id):
		var row: Dictionary = by_id[step["region"]]
		var sprite := "" if locked.has(step["route"]) else _route_sprite(step, row)
		if sprite != "":
			routes[step["cell"]] = sprite
		if not occupied.has(step["cell"]):
			if not open.has(step["region"]):
				open[step["region"]] = {}
			open[step["region"]][step["cell"]] = true
	var out_trouble := {}
	var covered := routes.duplicate()
	for region_id in targets:
		var plan: Dictionary = targets[region_id]
		var houses: Array = plan["town_cells"].filter(func(c: Vector2i) -> bool: return c not in plan["tower_cells"] and c not in plan["capital_cells"])
		out_trouble[region_id] = trouble_cells(by_id[region_id], houses, open.get(region_id, {}).keys())
		for cell in out_trouble[region_id]["barricade"]:
			covered[cell] = "barricade"
	return {"routes": routes, "trouble": out_trouble, "covered": covered, "locked_rails": locked}


static func locked_rails(geo: MapGeometry, tiles: Dictionary, by_id: Dictionary) -> Dictionary:
	var out := {}
	for i in geo.routes.size():
		if geo.routes[i]["kind"] != "rail":
			continue
		for cell in TileBaker.line_tiles(geo.routes[i]["points"]):
			var region := TileBaker.region_at_tile(tiles, cell)
			if region >= geo.region_ids.size() or not by_id.has(geo.region_ids[region]):
				continue
			var row: Dictionary = by_id[geo.region_ids[region]]
			if String(row.get("control", "")) != "separatist" and float(row.get("development", 0.0)) < RAIL_DEVELOPMENT:
				out[i] = true
				break
	return out


static func _route_sprite(step: Dictionary, row: Dictionary) -> String:
	if step["kind"] == "rail":
		return "rail" + step["suffix"]
	var tier := road_tier(float(row.get("development", 0.0)), row.get("active_program") != null)
	return "" if tier == 0 else ("road" if tier == 1 else "paved") + step["suffix"]


static func _route_walk(geo: MapGeometry, tiles: Dictionary, by_id: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kind in ROUTE_KINDS:
		for index in geo.routes.size():
			var route: Dictionary = geo.routes[index]
			if route["kind"] != kind:
				continue
			var cells := TileBaker.line_tiles(route["points"])
			for i in cells.size():
				var region := TileBaker.region_at_tile(tiles, cells[i])
				if region >= geo.region_ids.size():
					continue
				var region_id := geo.region_ids[region]
				if not by_id.has(region_id) or String(by_id[region_id].get("control", "")) == "separatist":
					continue
				var step := cells[mini(i + 1, cells.size() - 1)] - cells[maxi(i - 1, 0)]
				out.append({"cell": cells[i], "region": region_id, "kind": kind, "route": index, "suffix": route_suffix(step)})
	return out


static func plume(base: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [base]
	for rise in PLUME_RISE:
		if TileBaker.in_grid(base + rise):
			out.append(base + rise)
	return out
