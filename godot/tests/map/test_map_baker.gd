extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const CANON_BORDERS := {
	"anera": ["vashtera", "sela", "vetrenka"],
	"karsen": ["anera", "vashtera", "zavost"],
	"vashtera": ["karsen", "zavost", "sela", "orvena"],
	"zavost": ["karsen", "vashtera", "sela", "darev", "kostrel"],
	"darev": ["zavost", "kostrel"],
	"sela": ["vashtera", "zavost", "kostrel", "kelvet", "orvena"],
	"kostrel": ["sela", "darev", "zavost"],
	"kelvet": ["sela", "orvena"],
	"orvena": ["anera", "vashtera", "sela", "kelvet", "vetrenka"],
	"vetrenka": ["anera", "orvena"],
}
## Pairs the canon table lists from one side only that the map draws anyway.
## Together with the canon pairs these are every internal border, exactly.
const DRAWN_ONE_SIDED := ["anera|karsen", "anera|orvena", "anera|vashtera"]
const COASTAL := ["kelvet", "orvena", "vetrenka"]


func _initialize() -> void:
	var t = TestSupportScript.new()
	var geo := MapGeometry.load_world()
	var height := MapBaker.bake_height(geo)
	t.equal(Vector2i(height.get_width(), height.get_height()), MapBaker.RESOLUTION, "the heightmap is the baked resolution")
	t.equal(MapBaker.bake_height(geo).get_data(), height.get_data(), "baking is deterministic")

	var west_sea := height.get_pixel(5, MapBaker.RESOLUTION.y / 2).r
	t.truth(west_sea <= 0.0, "the far west is sea")
	var ridge := _max_row(height, int(MapBaker.RESOLUTION.y * 0.17))
	var plain := _max_row(height, int(MapBaker.RESOLUTION.y * 0.60))
	t.truth(ridge > plain * 2.0, "the northern wall stands far above the plains (%.0f m vs %.0f m)" % [ridge, plain])
	t.truth(ridge <= MapBaker.MAX_HEIGHT_M, "and never exceeds the height ceiling")
	var southern := 0.0
	for x in range(int(MapBaker.RESOLUTION.x * 0.12), int(MapBaker.RESOLUTION.x * 0.45)):
		var row := int((MapBaker.southern_edge(float(x) / MapBaker.RESOLUTION.x) - 0.04) * MapBaker.RESOLUTION.y)
		southern = maxf(southern, height.get_pixel(x, row).r)
	var basin := 0.0
	for x in range(int(MapBaker.RESOLUTION.x * 0.40), int(MapBaker.RESOLUTION.x * 0.60)):
		basin = maxf(basin, height.get_pixel(x, int(MapBaker.RESOLUTION.y * 0.48)).r)
	t.truth(southern > basin * 2.0 and southern < ridge * 0.8, "a lower southern range stands between the basin and the northern wall (%.0f m)" % southern)

	var regions := MapBaker.bake_regions(geo, height)
	for id in geo.region_ids:
		t.equal(MapBaker.region_at_map(regions, geo, geo.seeds[id]), id, "%s's seed lies inside %s" % [id, id])
	for c in geo.cities:
		t.equal(MapBaker.region_at_map(regions, geo, c["point"]), c["region"], "%s lies in %s" % [c["name"], c["region"]])
	t.equal(MapBaker.region_at_map(regions, geo, Vector2(0.01, 0.5)), "", "the sea belongs to no region")
	for id in geo.region_ids:
		t.truth(_is_contiguous(regions, geo.region_ids.find(id)), "%s is one connected territory" % id)

	var borders := MapBaker.trace_borders(regions, geo)
	t.truth(borders["national"].size() >= 1, "the national border is traced")
	t.truth(borders["internal"].size() >= 8, "every internal border is traced")
	t.truth(borders["ceasefire"].size() >= 1, "the ceasefire line is traced separately from ordinary borders")
	var line: PackedVector2Array = borders["national"][0]
	t.truth(line[0].distance_to(line[line.size() - 1]) < 0.01, "the national border closes on itself")
	t.truth(_max_turn(line) < deg_to_rad(80.0), "borders are smooth curves, not pixel staircases")

	var outlines := MapBaker.trace_outlines(regions, geo)
	t.equal(outlines.size(), 10, "every region has an outline")
	for id in geo.region_ids:
		var ring: PackedVector2Array = outlines.get(id, PackedVector2Array())
		t.truth(ring.size() > 3 and ring[0] == ring[ring.size() - 1], "%s's outline is a closed ring" % id)
		t.truth(Geometry2D.is_point_in_polygon(geo.seeds[id], ring), "%s's seed lies inside its outline" % id)

	var pairs := MapBaker.adjacent_pairs(regions, geo)
	for pair in _canon_pairs(true):
		t.truth(pairs.has(pair), "canon adjacency %s is present" % pair)
	for pair in _canon_pairs(false):
		t.truth(not pairs.has(pair), "%s do not touch, as the canon says" % pair)
	var drawn: Array = _canon_pairs(true) + DRAWN_ONE_SIDED
	drawn.sort()
	var found: Array = pairs.keys()
	found.sort()
	t.equal(found, drawn, "the map draws exactly the expected internal borders")
	t.equal(_coastal(regions, geo), COASTAL, "only Vetrenka, Orvena and Kelvet touch the sea")
	quit(t.finish())


static func _coastal(regions: Image, geo: MapGeometry) -> Array:
	var data := regions.get_data()
	var w := MapBaker.RESOLUTION.x
	var found := {}
	for y in range(1, MapBaker.RESOLUTION.y - 1):
		for x in range(1, w - 1):
			var a := data[y * w + x]
			if a >= geo.region_ids.size():
				continue
			for q in [y * w + x + 1, y * w + x - 1, (y + 1) * w + x, (y - 1) * w + x]:
				if data[q] == MapBaker.SEA_REGION:
					found[geo.region_ids[a]] = true
	var out := found.keys()
	out.sort()
	return out


static func _max_row(img: Image, y: int) -> float:
	var best := -INF
	for x in img.get_width():
		best = maxf(best, img.get_pixel(x, y).r)
	return best


static func _is_contiguous(img: Image, index: int) -> bool:
	var start := Vector2i(-1, -1)
	var count := 0
	for y in img.get_height():
		for x in img.get_width():
			if int(round(img.get_pixel(x, y).r * 255.0)) == index:
				count += 1
				if start.x < 0:
					start = Vector2i(x, y)
	if count == 0:
		return false
	var seen := {start: true}
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height() or seen.has(q):
				continue
			if int(round(img.get_pixel(q.x, q.y).r * 255.0)) == index:
				seen[q] = true
				stack.append(q)
	return seen.size() == count


static func _max_turn(line: PackedVector2Array) -> float:
	var worst := 0.0
	for i in range(1, line.size() - 1):
		var a := (line[i] - line[i - 1]).normalized()
		var b := (line[i + 1] - line[i]).normalized()
		worst = maxf(worst, absf(a.angle_to(b)) if a != Vector2.ZERO and b != Vector2.ZERO else 0.0)
	return absf(worst)


static func _canon_pairs(required: bool) -> Array[String]:
	var ids: Array = CANON_BORDERS.keys()
	ids.sort()
	var out: Array[String] = []
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: String = ids[i]
			var b: String = ids[j]
			var listed := int(b in CANON_BORDERS[a]) + int(a in CANON_BORDERS[b])
			if (required and listed == 2) or (not required and listed == 0):
				out.append("%s|%s" % [a, b])
	return out
