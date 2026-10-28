class_name MapBaker
extends RefCounted

const RESOLUTION := Vector2i(1344, 800)
const MAX_HEIGHT_M := 1800.0
const SEA_REGION := 255
const FOREIGN_REGION := 254
const SEED := 1993
const BORDER_SMOOTHING_PASSES := 4
const SNOW_LINE := 0.78
const ROCK_SLOPE := 0.9
const FOREST_BAND := Vector2(0.28, 0.62)
const MIN_SHARED_BORDER_PIXELS := 8
const CHAIN_REACH_HALF_PIXELS := 3
const MIN_CHAIN_POINTS := 6
const BORDER_SAMPLE_STEP := 4
const NATIONAL_FRAGMENT_SHARE := 0.05


static func _noise(frequency: float, octaves: int, seed_offset: int, type := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = SEED + seed_offset
	n.noise_type = type
	n.frequency = frequency
	n.fractal_octaves = octaves
	return n


static func northern_edge(u: float) -> float:
	return 0.13 + 0.04 * sin(u * 6.0) + 0.03 * sin(u * 13.0 + 1.3) + 0.04 * u


static func southern_edge(u: float) -> float:
	return (0.86 + 0.03 * sin(u * 9.0) if u < 0.55 else 0.86 - (u - 0.55) * 0.42) + 0.02 * sin(u * 23.0 + 2.0)


static func coastline(v: float) -> float:
	return 0.07 + (v - 0.15) * 0.16 + 0.025 * sin(v * 17.0)


static func eastern_edge(v: float) -> float:
	return 0.95 - absf(v - 0.42) * 0.25


static func is_sea(u: float, v: float, warp: float) -> bool:
	return u < coastline(v) + warp


static func is_ardenia(u: float, v: float, warp: float) -> bool:
	return v > northern_edge(u) + warp and v < southern_edge(u) + warp \
		and not is_sea(u, v, warp) and u < eastern_edge(v) + warp


static func bake_height(_geo: MapGeometry) -> Image:
	var img := Image.create_empty(RESOLUTION.x, RESOLUTION.y, false, Image.FORMAT_RF)
	var ridged := _noise(0.012, 6, 1, FastNoiseLite.TYPE_PERLIN)
	ridged.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var hills := _noise(0.006, 5, 2)
	var warp := _noise(0.02, 3, 3)
	for y in RESOLUTION.y:
		var v := float(y) / RESOLUTION.y
		for x in RESOLUTION.x:
			var u := float(x) / RESOLUTION.x
			var w := warp.get_noise_2d(x, y) * 0.02
			if is_sea(u, v, w):
				img.set_pixel(x, y, Color(-40.0 - (coastline(v) - u) * 900.0, 0, 0))
				continue
			var crest := exp(-pow((v - northern_edge(u) - 0.01) / 0.075, 2.0))
			var lesser := exp(-pow((v - 0.84) / 0.07, 2.0)) * maxf(0.0, 1.0 - absf(u - 0.33) * 2.4)
			var lowland := exp(-pow(Vector2((u - 0.16) * 1.2, v - 0.55).length() / 0.16, 2.0))
			var plain := exp(-pow(Vector2((u - 0.58) * 0.9, v - 0.55).length() / 0.18, 2.0))
			var r := (ridged.get_noise_2d(x, y) + 1.0) * 0.5
			var h := 0.12 + crest * (0.18 + 0.82 * r) + lesser * 0.35 * r + hills.get_noise_2d(x, y) * 0.08 - lowland * 0.08 - plain * 0.06
			img.set_pixel(x, y, Color(clampf(h, 0.01, 1.0) * MAX_HEIGHT_M, 0, 0))
	return img


static func bake_regions(geo: MapGeometry, height: Image) -> Image:
	var img := Image.create_empty(RESOLUTION.x, RESOLUTION.y, false, Image.FORMAT_R8)
	var warp_u := _noise(0.004, 3, 11)
	var warp_v := _noise(0.004, 3, 13)
	var warp := _noise(0.02, 3, 3)
	for y in RESOLUTION.y:
		var v := float(y) / RESOLUTION.y
		for x in RESOLUTION.x:
			var u := float(x) / RESOLUTION.x
			var w := warp.get_noise_2d(x, y) * 0.02
			var index := SEA_REGION
			if not is_sea(u, v, w):
				index = FOREIGN_REGION
				if is_ardenia(u, v, w):
					index = _nearest_seed(geo, Vector2(u + warp_u.get_noise_2d(x, y) * 0.08, v + warp_v.get_noise_2d(x, y) * 0.08),
						height.get_pixel(x, y).r)
			img.set_pixel(x, y, Color8(index, 0, 0))
	return _absorb_fragments(img, geo.region_ids.size())


static func _components(data: PackedByteArray, region_count: int) -> Array[PackedInt32Array]:
	var w := RESOLUTION.x
	var h := RESOLUTION.y
	var seen := PackedByteArray()
	seen.resize(w * h)
	var found: Array[PackedInt32Array] = []
	for start in w * h:
		if seen[start] or data[start] >= region_count:
			continue
		var members := PackedInt32Array([start])
		seen[start] = 1
		var head := 0
		while head < members.size():
			var p := members[head]
			head += 1
			var x := p % w
			for q in [p - 1 if x > 0 else -1, p + 1 if x < w - 1 else -1, p - w, p + w]:
				if q >= 0 and q < w * h and not seen[q] and data[q] == data[start]:
					seen[q] = 1
					members.append(q)
		found.append(members)
	return found


static func _absorb_fragments(img: Image, region_count: int) -> Image:
	var data := img.get_data()
	var w := RESOLUTION.x
	var largest := {}
	var components := _components(data, region_count)
	for members in components:
		var index := data[members[0]]
		if members.size() > largest.get(index, PackedInt32Array()).size():
			largest[index] = members
	for members in components:
		var index := data[members[0]]
		if largest[index] == members:
			continue
		var votes := {}
		for p in members:
			for q in [p - 1, p + 1, p - w, p + w]:
				if q >= 0 and q < data.size() and data[q] != index and data[q] < region_count:
					votes[data[q]] = int(votes.get(data[q], 0)) + 1
		var winner := index
		for candidate in votes:
			if winner == index or votes[candidate] > votes[winner]:
				winner = candidate
		for p in members:
			data[p] = winner
	return Image.create_from_data(RESOLUTION.x, RESOLUTION.y, false, Image.FORMAT_R8, data)


static func _nearest_seed(geo: MapGeometry, p: Vector2, elevation_m: float) -> int:
	var best := 0
	var best_d := INF
	for i in geo.region_ids.size():
		var s: Vector2 = geo.seeds[geo.region_ids[i]]
		var d := Vector2((p.x - s.x) * 1.25, p.y - s.y).length() * (1.0 + elevation_m / MAX_HEIGHT_M * 0.15) / float(geo.weights.get(geo.region_ids[i], 1.0))
		if d < best_d:
			best_d = d
			best = i
	return best


static func index_at(regions: Image, pixel: Vector2i) -> int:
	return int(round(regions.get_pixelv(pixel).r * 255.0))


static func region_at_map(regions: Image, geo: MapGeometry, p: Vector2) -> String:
	var px := Vector2i(clampi(int(p.x * RESOLUTION.x), 0, RESOLUTION.x - 1), clampi(int(p.y * RESOLUTION.y), 0, RESOLUTION.y - 1))
	var index := index_at(regions, px)
	return geo.region_ids[index] if index < geo.region_ids.size() else ""


static func encode_control(base: int, overlay: int, blend: int) -> float:
	return Terrain3DUtil.as_float(Terrain3DUtil.enc_base(base) | Terrain3DUtil.enc_overlay(overlay) | Terrain3DUtil.enc_blend(blend))


static func base_material_at(control: Image, pixel: Vector2i) -> int:
	return Terrain3DUtil.get_base(Terrain3DUtil.as_uint(control.get_pixelv(pixel).r))


static func bake_control(height: Image, regions: Image, geo: MapGeometry) -> Image:
	var img := Image.create_empty(RESOLUTION.x, RESOLUTION.y, false, Image.FORMAT_RF)
	var moisture := _noise(0.01, 4, 21)
	var fields := _noise(0.06, 2, 31)
	for y in RESOLUTION.y:
		for x in RESOLUTION.x:
			var h := height.get_pixel(x, y).r / MAX_HEIGHT_M
			var slope := _slope(height, x, y)
			var material := "grass"
			if h <= 0.0:
				material = "sand"
			elif h < 0.03:
				material = "sand"
			elif h > SNOW_LINE:
				material = "snow"
			elif slope > ROCK_SLOPE:
				material = "rock"
			elif h > FOREST_BAND.x and h < FOREST_BAND.y and moisture.get_noise_2d(x, y) > -0.1:
				material = "forest"
			elif h < 0.25 and fields.get_noise_2d(x, y) > 0.15:
				material = "farmland"
			img.set_pixel(x, y, Color(encode_control(MapAssets.material_id(material), 0, 0), 0, 0))
	_paint_routes(img, geo)
	return img


static func _slope(height: Image, x: int, y: int) -> float:
	var x1 := mini(x + 1, height.get_width() - 1)
	var y1 := mini(y + 1, height.get_height() - 1)
	var metres_per_pixel := 12.5
	var dx := (height.get_pixel(x1, y).r - height.get_pixel(x, y).r) / metres_per_pixel
	var dy := (height.get_pixel(x, y1).r - height.get_pixel(x, y).r) / metres_per_pixel
	return Vector2(dx, dy).length()


static func _paint_routes(img: Image, geo: MapGeometry) -> void:
	var road := MapAssets.material_id("road")
	for route in geo.routes:
		if route["kind"] == "pipeline":
			continue
		var points: PackedVector2Array = route["points"]
		for i in range(points.size() - 1):
			var a := points[i] * Vector2(RESOLUTION)
			var b := points[i + 1] * Vector2(RESOLUTION)
			for s in range(int(a.distance_to(b)) + 1):
				var p := Vector2i(a.lerp(b, float(s) / maxf(1.0, a.distance_to(b))))
				for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)]:
					var q: Vector2i = p + d
					if q.x < RESOLUTION.x and q.y < RESOLUTION.y:
						var current := Terrain3DUtil.as_uint(img.get_pixelv(q).r)
						img.set_pixelv(q, Color(encode_control(Terrain3DUtil.get_base(current), road, 180), 0, 0))


static func _boundary_edges(regions: Image) -> Dictionary:
	var data := regions.get_data()
	var w := RESOLUTION.x
	var edges := {}
	for y in RESOLUTION.y - 1:
		for x in w - 1:
			var a := data[y * w + x]
			for q in [Vector2i(x + 1, y), Vector2i(x, y + 1)]:
				var b := data[q.y * w + q.x]
				if a == b:
					continue
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not edges.has(key):
					edges[key] = []
				edges[key].append((Vector2(x, y) + Vector2(q) + Vector2.ONE) * 0.5 / Vector2(RESOLUTION))
	return edges


static func trace_borders(regions: Image, geo: MapGeometry) -> Dictionary:
	var vetrenka := geo.region_ids.find("vetrenka")
	var national_points := PackedVector2Array()
	var internal: Array = []
	var ceasefire: Array = []
	var edges := _boundary_edges(regions)
	for key: Vector2i in edges:
		var inside := key.y < geo.region_ids.size()
		if key == Vector2i(FOREIGN_REGION, SEA_REGION):
			continue
		if not inside:
			national_points.append_array(PackedVector2Array(edges[key]))
			continue
		for line in _chain(PackedVector2Array(edges[key])):
			var smooth := _smooth(line)
			if key.x == vetrenka or key.y == vetrenka:
				ceasefire.append(smooth)
			else:
				internal.append(smooth)
	return {"national": [_join_national(_chain(national_points))], "internal": internal, "ceasefire": ceasefire}


static func trace_outlines(regions: Image, geo: MapGeometry) -> Dictionary:
	var edges := _boundary_edges(regions)
	var out := {}
	for i in geo.region_ids.size():
		var points := PackedVector2Array()
		for key: Vector2i in edges:
			if key.x == i or key.y == i:
				points.append_array(PackedVector2Array(edges[key]))
		var longest := PackedVector2Array()
		for line in _chain(points):
			if line.size() > longest.size():
				longest = line
		var ring := _smooth(longest)
		ring.append(ring[0])
		out[geo.region_ids[i]] = ring
	return out


static func adjacent_pairs(regions: Image, geo: MapGeometry) -> Dictionary:
	var pairs := {}
	var edges := _boundary_edges(regions)
	for key: Vector2i in edges:
		if key.y < geo.region_ids.size() and edges[key].size() >= MIN_SHARED_BORDER_PIXELS:
			var names := [geo.region_ids[key.x], geo.region_ids[key.y]]
			names.sort()
			pairs["%s|%s" % names] = true
	return pairs


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i((p * Vector2(RESOLUTION) * 2.0).round())


static func _chain(points: PackedVector2Array) -> Array[PackedVector2Array]:
	var grid := {}
	for p in points:
		grid[_cell(p)] = p
	var lines: Array[PackedVector2Array] = []
	while not grid.is_empty():
		var start: Vector2i = grid.keys()[0]
		var line := PackedVector2Array([grid[start]])
		grid.erase(start)
		var current := start
		while true:
			var next := Vector2i(-1, -1)
			var best := INF
			for dy in range(-CHAIN_REACH_HALF_PIXELS, CHAIN_REACH_HALF_PIXELS + 1):
				for dx in range(-CHAIN_REACH_HALF_PIXELS, CHAIN_REACH_HALF_PIXELS + 1):
					var c := current + Vector2i(dx, dy)
					var d := Vector2(dx, dy).length()
					if grid.has(c) and d < best:
						best = d
						next = c
			if next.x < 0:
				break
			line.append(grid[next])
			grid.erase(next)
			current = next
		if line.size() >= MIN_CHAIN_POINTS:
			lines.append(line)
	return lines


static func _smooth(line: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, line.size() - 1, BORDER_SAMPLE_STEP):
		out.append(line[i])
	out.append(line[line.size() - 1])
	for pass_index in BORDER_SMOOTHING_PASSES:
		if out.size() < 3:
			return out
		var next := PackedVector2Array([out[0]])
		for i in out.size() - 1:
			next.append(out[i] * 0.75 + out[i + 1] * 0.25)
			next.append(out[i] * 0.25 + out[i + 1] * 0.75)
		next.append(out[out.size() - 1])
		out = next
	return out


static func _join_national(lines: Array) -> PackedVector2Array:
	var longest := 0
	for line: PackedVector2Array in lines:
		longest = maxi(longest, line.size())
	var remaining := lines.filter(func(line: PackedVector2Array) -> bool: return line.size() >= longest * NATIONAL_FRAGMENT_SHARE)
	var ring: PackedVector2Array = remaining.pop_back()
	while not remaining.is_empty():
		var tail := ring[ring.size() - 1]
		var best := 0
		var best_d := INF
		var flip := false
		for i in remaining.size():
			var seg: PackedVector2Array = remaining[i]
			if tail.distance_to(seg[0]) < best_d:
				best_d = tail.distance_to(seg[0])
				best = i
				flip = false
			if tail.distance_to(seg[seg.size() - 1]) < best_d:
				best_d = tail.distance_to(seg[seg.size() - 1])
				best = i
				flip = true
		var chosen: PackedVector2Array = remaining.pop_at(best)
		if flip:
			chosen.reverse()
		ring.append_array(chosen)
	ring.append(ring[0])
	return _smooth(ring)
