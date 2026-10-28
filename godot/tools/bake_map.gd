extends SceneTree

const OUT_DIR := "res://data/map/baked"
const COORD_DECIMALS := 100000.0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var geo := MapGeometry.load_world()
	var height := MapBaker.bake_height(geo)
	var regions := MapBaker.bake_regions(geo, height)
	height.save_exr(OUT_DIR + "/height.exr", true)
	regions.save_png(OUT_DIR + "/region_ids.png")
	var borders := MapBaker.trace_borders(regions, geo)
	var doc := {}
	for kind in ["national", "internal", "ceasefire"]:
		doc[kind] = borders[kind].map(_points)
	var outlines := {}
	var rings := MapBaker.trace_outlines(regions, geo)
	for id in rings:
		outlines[id] = _points(rings[id])
	doc["outlines"] = outlines
	if not TileBaker.save(TileBaker.bake(height, regions, geo), OUT_DIR + "/tiles.json"):
		quit(1)
		return
	var file := FileAccess.open(OUT_DIR + "/borders.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(doc))
	file.close()
	quit(0)


static func _points(line: PackedVector2Array) -> Array:
	var out := []
	for p in line:
		out.append([roundf(p.x * COORD_DECIMALS) / COORD_DECIMALS, roundf(p.y * COORD_DECIMALS) / COORD_DECIMALS])
	return out
