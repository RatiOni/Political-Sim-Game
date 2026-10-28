class_name MapGeometry
extends RefCounted

const WORLD_PATH := "res://data/map/ardenia_world.json"

var extent_m := Vector2.ZERO
var region_ids: Array[String] = []
var seeds: Dictionary = {}
var weights: Dictionary = {}
var cities: Array[Dictionary] = []
var routes: Array[Dictionary] = []
var ceasefire := PackedVector2Array()
var kesla := PackedVector2Array()


static func load_world(path: String = WORLD_PATH) -> MapGeometry:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("MapGeometry: %s is not a JSON object" % path)
		return null
	var data: Dictionary = parsed
	for key in ["extent_m", "regions", "cities", "routes", "ceasefire", "kesla"]:
		if not data.has(key):
			push_error("MapGeometry: %s is missing '%s'" % [path, key])
			return null
	var geo := MapGeometry.new()
	geo.extent_m = Vector2(float(data["extent_m"][0]), float(data["extent_m"][1]))
	for id in data["regions"]:
		geo.region_ids.append(String(id))
		geo.seeds[String(id)] = _vec(data["regions"][id])
	for id in data.get("weights", {}):
		geo.weights[String(id)] = float(data["weights"][id])
	for c in data["cities"]:
		geo.cities.append({"name": String(c["name"]), "region": String(c["region"]),
			"point": _vec(c["point"]), "capital": bool(c.get("capital", false))})
	for r in data["routes"]:
		geo.routes.append({"kind": String(r["kind"]), "points": _line(r["points"])})
	geo.ceasefire = _line(data["ceasefire"])
	geo.kesla = _line(data["kesla"])
	return geo


func map_to_world(p: Vector2) -> Vector3:
	return Vector3((p.x - 0.5) * extent_m.x, 0.0, (p.y - 0.5) * extent_m.y)


func world_to_map(w: Vector3) -> Vector2:
	return Vector2(w.x / extent_m.x + 0.5, w.z / extent_m.y + 0.5)


static func _vec(v: Array) -> Vector2:
	return Vector2(float(v[0]), float(v[1]))


static func _line(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(_vec(p))
	return out
