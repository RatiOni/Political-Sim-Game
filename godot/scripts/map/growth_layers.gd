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


static func stable_hash(cell: Vector2i, salt: int = 0) -> int:
	return ((cell.x * 73856093) ^ (cell.y * 19349663) ^ (salt * 83492791)) & 0x7fffffff


static func hash_order(cells: Array, salt: int = 0) -> Array[Vector2i]:
	var ordered: Array[Vector2i] = []
	ordered.assign(cells)
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ha := stable_hash(a, salt)
		var hb := stable_hash(b, salt)
		return ha < hb or (ha == hb and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	return ordered


static func kind_at(tiles: Dictionary, cell: Vector2i) -> String:
	if cell.x < 0 or cell.y < 0 or cell.x >= TileBaker.GRID.x or cell.y >= TileBaker.GRID.y:
		return ""
	return TileArt.KINDS[tiles["kinds"][cell.y * TileBaker.GRID.x + cell.x]]


static func cells_for_town(center: Vector2i, count: int, tiles: Dictionary, blocked: Dictionary = {}, claimed: Dictionary = {}) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for dy in range(-TOWN_RADIUS, TOWN_RADIUS + 1):
		for dx in range(-TOWN_RADIUS, TOWN_RADIUS + 1):
			var cell := center + Vector2i(dx, dy)
			var region := TileBaker.region_at_tile(tiles, cell)
			if kind_at(tiles, cell) in BUILDABLE and region < MapBaker.FOREIGN_REGION and not blocked.has(region) and not claimed.has(cell):
				candidates.append(cell)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (a - center).length_squared()
		var db := (b - center).length_squared()
		return da < db or (da == db and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	var out: Array[Vector2i] = []
	out.assign(candidates.slice(0, count))
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
			elif stable_hash(cell, 2) % TOWER_EVERY == 0:
				entry["towers"].append(cell)
			else:
				entry["houses"].append(cell)
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
		"lit_cells": hash_order(towns["houses"], 1).slice(0, lit_count),
		"farm_cells": farm,
		"fallow_cells": farm.slice(farm.size() - fallow_count),
	}


static func _farm_cells(region: int, occupied: Dictionary, centres: Array, development: float, tiles: Dictionary) -> Array[Vector2i]:
	var reach := {}
	var limit := farm_reach(development)
	var span := ceili(limit)
	for centre in centres:
		for dy in range(-span, span + 1):
			for dx in range(-span, span + 1):
				var cell: Vector2i = centre + Vector2i(dx, dy)
				var distance := Vector2(dx, dy).length()
				if distance > limit or occupied.has(cell) or kind_at(tiles, cell) not in ARABLE or TileBaker.region_at_tile(tiles, cell) != region:
					continue
				if not reach.has(cell) or distance < reach[cell]:
					reach[cell] = distance
	var ordered: Array = reach.keys()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return reach[a] < reach[b] or (reach[a] == reach[b] and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	var out: Array[Vector2i] = []
	out.assign(ordered.slice(0, roundi(ordered.size() * farm_share(development))))
	return out
