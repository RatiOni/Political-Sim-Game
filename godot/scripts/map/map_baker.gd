class_name MapBaker
extends RefCounted

const RESOLUTION := Vector2i(1344, 800)
const MAX_HEIGHT_M := 1800.0
const SEA_REGION := 255
const FOREIGN_REGION := 254
const SEED := 1993
const BORDER_SMOOTHING_PASSES := 4
const MIN_SHARED_BORDER_PIXELS := 8
const CHAIN_REACH_HALF_PIXELS := 3
const MIN_CHAIN_POINTS := 6
const BORDER_SAMPLE_STEP := 4
const NATIONAL_FRAGMENT_SHARE := 0.05
# The land mask is displaced by a domain warp whose amplitude is about two
# tiles. At a wavelength near the tile size that can only alias into a one-tile
# battlement along the frontier, so the frequency is kept well below it and the
# warp bulges the coast instead of serrating it.
const MASK_WARP_FREQUENCY := 0.006
const MASK_WARP_AMPLITUDE := 0.02


static func _noise(frequency: float, octaves: int, seed_offset: int, type := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = SEED + seed_offset
	n.noise_type = type
	n.frequency = frequency
	n.fractal_octaves = octaves
	return n


# The silhouette is deliberately not one smooth family of sines. Each frontier
# has its own history, so each gets a different hand:
#   north — a mountain wall with passes: folded, with salients and a lost valley.
#   east  — the Krasovan line, surveyed under the Union: genuinely straight,
#           two segments meeting at one awkward corner, and never warped.
#   south — a wandering lowland edge west of the ruled Merova survey line.
#   west  — a worked coast: a headland, the Orvena bay, the Kesla estuary.
# The profiles are authored in the original 1993 survey frame ("old u"). The
# east was then drawn out to make room for Kostrel: west of STRETCH_FROM the
# country only slides a little toward the sea, east of it every distance grows
# by STRETCH_GAIN, so the Krasovan line now stands near the map's edge.
const EAST_CORNER_V := 0.46
const EAST_NORTH_TOP := 0.900
const EAST_CORNER_U := 0.962
const EAST_SOUTH_BOTTOM := 0.840
const MEROVA_SURVEY_U := 0.70
const STRETCH_FROM := 0.55
const STRETCH_SHIFT := -0.015
const STRETCH_GAIN := 1.092

static var _edge_cache := {}


static func _mask_warp() -> FastNoiseLite:
	return _noise(MASK_WARP_FREQUENCY, 3, 3)


static func _edge_noise(offset: int, octaves: int) -> FastNoiseLite:
	var key := Vector2i(offset, octaves)
	if not _edge_cache.has(key):
		_edge_cache[key] = _noise(1.0, octaves, offset)
	return _edge_cache[key]


static func _fold(offset: int, t: float, scale: float, octaves: int = 3) -> float:
	# A folded (ridged) sample: creases rather than bulges. Note what the
	# octaves cost: with lacunarity 2 the third octave creases at four times
	# `scale`, and folding doubles that again — so three octaves at scale 9
	# put a crease every eighth of a `scale` unit. Pass fewer octaves on any
	# edge where that lands below one tile.
	return absf(_edge_noise(offset, octaves).get_noise_1d(t * scale)) * 2.0 - 0.5


## Survey frame -> map: the west slides, the east is drawn out.
static func stretch_u(old_u: float) -> float:
	if old_u <= STRETCH_FROM:
		return old_u + STRETCH_SHIFT
	return STRETCH_FROM + STRETCH_SHIFT + (old_u - STRETCH_FROM) * STRETCH_GAIN


## Map -> survey frame, the inverse of stretch_u.
static func survey_u(u: float) -> float:
	if u <= STRETCH_FROM + STRETCH_SHIFT:
		return u - STRETCH_SHIFT
	return STRETCH_FROM + (u - STRETCH_FROM - STRETCH_SHIFT) / STRETCH_GAIN


static func northern_edge(map_u: float) -> float:
	var u := survey_u(map_u)
	var base := 0.125 + 0.052 * u
	# One single-octave fold, for the same reason as the coast below: these
	# edges run the long axis, so a three-octave fold at scale 7 creased every
	# three tiles and one at scale 10 every two — under the floor the tile grid
	# can draw, which it rendered as a sawtooth. Scale 7 at one octave creases
	# roughly every twelve tiles; the second fold's weight folds into the first.
	var fold := _fold(21, u, 7.0, 1) * 0.038
	var passes := -0.030 * exp(-pow((u - 0.30) / 0.045, 2.0)) 		- 0.022 * exp(-pow((u - 0.52) / 0.035, 2.0)) 		- 0.026 * exp(-pow((u - 0.80) / 0.055, 2.0))
	var lost_valley := 0.052 * exp(-pow((u - 0.645) / 0.034, 2.0))
	return base + fold + passes + lost_valley


static func southern_edge(map_u: float) -> float:
	var u := survey_u(map_u)
	if u >= MEROVA_SURVEY_U:
		return 0.845 - (u - MEROVA_SURVEY_U) * 0.56
	var base := 0.878 - 0.050 * exp(-pow((u - 0.44) / 0.10, 2.0))
	return base + _fold(23, u, 7.0, 1) * 0.020 + sin(u * 13.0 + 2.0) * 0.008


static func coastline(v: float) -> float:
	var base := 0.072 + (v - 0.15) * 0.145
	# One fold, and a coarse single-octave one. The coast runs along the short
	# axis — a hundred tiles — so anything finer creased every row and a half,
	# well under the tile floor, and the grid could only draw that as a ±1 tile
	# wobble in and out of the sea. The headland, bay and estuary are Gaussians.
	var crinkle := _fold(24, v, 6.0, 1) * 0.021
	var headland := -0.044 * exp(-pow((v - 0.215) / 0.042, 2.0))
	# The Orvena bay cuts deep enough to leave a waist behind it: the only
	# land route from Vetrenka's coast to the south is a few tiles wide.
	var bay := 0.062 * exp(-pow((v - 0.400) / 0.055, 2.0))
	var estuary := 0.030 * exp(-pow((v - 0.845) / 0.035, 2.0))
	return stretch_u(base + crinkle + headland + bay + estuary)


static func eastern_edge(v: float) -> float:
	var u: float
	if v <= EAST_CORNER_V:
		u = EAST_NORTH_TOP + (v / EAST_CORNER_V) * (EAST_CORNER_U - EAST_NORTH_TOP)
	else:
		u = EAST_CORNER_U - ((v - EAST_CORNER_V) / (1.0 - EAST_CORNER_V)) * (EAST_CORNER_U - EAST_SOUTH_BOTTOM)
	return stretch_u(u)


# The edge profiles are sampled a million times a bake and each costs a fistful
# of noise octaves, so they are tabulated once per column and row.
static var _north_lut := PackedFloat32Array()
static var _south_lut := PackedFloat32Array()
static var _coast_lut := PackedFloat32Array()
static var _east_lut := PackedFloat32Array()


static func _tabulate() -> void:
	if not _north_lut.is_empty():
		return
	for x in RESOLUTION.x:
		var u := float(x) / RESOLUTION.x
		_north_lut.append(northern_edge(u))
		_south_lut.append(southern_edge(u))
	for y in RESOLUTION.y:
		var v := float(y) / RESOLUTION.y
		_coast_lut.append(coastline(v))
		_east_lut.append(eastern_edge(v))


static func is_sea(u: float, v: float, warp: float) -> bool:
	_tabulate()
	return u < _coast_lut[clampi(int(v * RESOLUTION.y), 0, RESOLUTION.y - 1)] + warp


static func is_ardenia(u: float, v: float, warp: float) -> bool:
	_tabulate()
	var col := clampi(int(u * RESOLUTION.x), 0, RESOLUTION.x - 1)
	var row := clampi(int(v * RESOLUTION.y), 0, RESOLUTION.y - 1)
	# The eastern line takes no warp: a surveyed border is straight or it is
	# not a surveyed border.
	return v > _north_lut[col] + warp and v < _south_lut[col] + warp \
		and u >= _coast_lut[row] + warp and u < _east_lut[row]


static func bake_height(_geo: MapGeometry) -> Image:
	var img := Image.create_empty(RESOLUTION.x, RESOLUTION.y, false, Image.FORMAT_RF)
	var ridged := _noise(0.012, 6, 1, FastNoiseLite.TYPE_PERLIN)
	ridged.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var hills := _noise(0.006, 5, 2)
	var warp := _mask_warp()
	for y in RESOLUTION.y:
		var v := float(y) / RESOLUTION.y
		for x in RESOLUTION.x:
			var u := float(x) / RESOLUTION.x
			var w := warp.get_noise_2d(x, y) * MASK_WARP_AMPLITUDE
			if is_sea(u, v, w):
				img.set_pixel(x, y, Color(-40.0 - (coastline(v) - u) * 900.0, 0, 0))
				continue
			var su := survey_u(u)
			var crest := exp(-pow((v - northern_edge(u) - 0.01) / 0.075, 2.0))
			var lesser := exp(-pow((v - 0.84) / 0.07, 2.0)) * maxf(0.0, 1.0 - absf(su - 0.33) * 2.4)
			var lowland := exp(-pow(Vector2((su - 0.16) * 1.2, v - 0.55).length() / 0.16, 2.0))
			var plain := exp(-pow(Vector2((su - 0.58) * 0.9, v - 0.55).length() / 0.18, 2.0))
			var r := (ridged.get_noise_2d(x, y) + 1.0) * 0.5
			var h := 0.12 + crest * (0.18 + 0.82 * r) + lesser * 0.35 * r + hills.get_noise_2d(x, y) * 0.08 - lowland * 0.08 - plain * 0.06
			img.set_pixel(x, y, Color(clampf(h, 0.01, 1.0) * MAX_HEIGHT_M, 0, 0))
	return img


# Internal borders are not drawn between the regions; they are what is left
# over when each region grows outward across the country it can actually
# administer. Crossing a ridge, a river or the ceasefire line is expensive, so
# the places where two growths meet are the ridgelines, the Kesla and the
# front — which is where real provincial borders sit.
const COARSE := 4
const RIDGE_COST := 14.0
const RIVER_COST := 9.0
const FRONT_COST := 26.0
# The wander field is deliberately LOW frequency and strong. High-frequency
# noise averages out along a Dijkstra path and leaves the boundary straight;
# only broad cheap valleys and broad expensive country bend it.
const WANDER := 2.4
const WANDER_FREQUENCY := 0.005
const BORDER_CROOK := 5.0
# The crook displaces by up to five coarse cells, which is two and a half
# tiles. At the old 0.024 that was a jog every five tiles — at the drawn scale
# that is per-tile jitter, not a jog. Broad enough and the eye reads one crook.
const CROOK_FREQUENCY := 0.007
# A coarse cell is half a tile, so a 3x3 majority cannot see a one-tile step at
# all. Radius two spans two and a half tiles: it shaves single-cell protrusions
# and notches and collapses runs of alternating single steps into one longer,
# regular step — a line rather than a sawtooth. The region is a broad blob, so
# there is no narrow neck for the wider kernel to bite through.
const MAJORITY_RADIUS := 2
const MAJORITY_PASSES := 3
const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
# Eight-way travel. Four-way growth meets along axis-aligned staircases — the
# L1 metric's equidistance locus — which is exactly the gridded look we are
# trying to lose. The country is broad east-to-west, so an east-west step
# carries less political reach than a north-south one.
const TRAVEL: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]
const TRAVEL_COST: Array[float] = [1.25, 1.25, 1.0, 1.0, 1.60, 1.60, 1.60, 1.60]


static func bake_regions(geo: MapGeometry, height: Image) -> Image:
	var gw := RESOLUTION.x / COARSE
	var gh := RESOLUTION.y / COARSE
	var owner := _crook(_grow_regions(geo, height, gw, gh), gw, gh)
	var data := PackedByteArray()
	data.resize(RESOLUTION.x * RESOLUTION.y)
	var warp := _mask_warp()
	for y in RESOLUTION.y:
		var v := float(y) / RESOLUTION.y
		for x in RESOLUTION.x:
			var u := float(x) / RESOLUTION.x
			var w := warp.get_noise_2d(x, y) * MASK_WARP_AMPLITUDE
			var index := SEA_REGION
			if not is_sea(u, v, w):
				index = FOREIGN_REGION
				if is_ardenia(u, v, w):
					index = owner[(y / COARSE) * gw + (x / COARSE)]
			data[y * RESOLUTION.x + x] = index
	var img := Image.create_from_data(RESOLUTION.x, RESOLUTION.y, false, Image.FORMAT_R8, data)
	return _absorb_fragments(img, geo.region_ids.size())


static func _crook(owner: PackedByteArray, gw: int, gh: int) -> PackedByteArray:
	# Terrain growth gives the border the right route; this displacement gives
	# it the small crooks and jogs a surveyed-then-argued-over line actually
	# has. It moves only where the internal map is read, never the coast or the
	# frontier. A majority pass afterwards removes any cell left stranded, so
	# no boundary speckles at tile size.
	var crook_u := _noise(CROOK_FREQUENCY, 2, 11)
	var crook_v := _noise(CROOK_FREQUENCY, 2, 13)
	var out := PackedByteArray()
	out.resize(owner.size())
	for gy in gh:
		for gx in gw:
			var x := gx * COARSE
			var y := gy * COARSE
			var sx := clampi(gx + int(crook_u.get_noise_2d(x, y) * BORDER_CROOK), 0, gw - 1)
			var sy := clampi(gy + int(crook_v.get_noise_2d(x, y) * BORDER_CROOK), 0, gh - 1)
			out[gy * gw + gx] = owner[sy * gw + sx]
	for pass_index in MAJORITY_PASSES:
		out = _majority(out, gw, gh)
	return out


static func _majority(owner: PackedByteArray, gw: int, gh: int) -> PackedByteArray:
	var out := owner.duplicate()
	var r := MAJORITY_RADIUS
	for gy in range(r, gh - r):
		for gx in range(r, gw - r):
			var i := gy * gw + gx
			var votes := {}
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var who := owner[(gy + dy) * gw + gx + dx]
					votes[who] = int(votes.get(who, 0)) + 1
			var best := owner[i]
			for who: int in votes:
				if votes[who] > votes[best] or (votes[who] == votes[best] and who < best):
					best = who
			out[i] = best
	return out


static func _travel_cost(geo: MapGeometry, height: Image, gw: int, gh: int) -> PackedFloat32Array:
	var cost := PackedFloat32Array()
	cost.resize(gw * gh)
	var grain := _noise(WANDER_FREQUENCY, 2, 31)
	var warp := _mask_warp()
	for gy in gh:
		for gx in gw:
			var x := gx * COARSE + COARSE / 2
			var y := gy * COARSE + COARSE / 2
			var u := float(x) / RESOLUTION.x
			var v := float(y) / RESOLUTION.y
			if not is_ardenia(u, v, warp.get_noise_2d(x, y) * MASK_WARP_AMPLITUDE):
				cost[gy * gw + gx] = -1.0
				continue
			var elevation := clampf(height.get_pixel(x, y).r / MAX_HEIGHT_M, 0.0, 1.0)
			cost[gy * gw + gx] = 1.0 + elevation * elevation * RIDGE_COST \
				+ (grain.get_noise_2d(x, y) + 1.0) * WANDER
	_add_barrier(cost, geo.kesla, gw, gh, RIVER_COST)
	_add_barrier(cost, geo.ceasefire, gw, gh, FRONT_COST)
	return cost


static func _add_barrier(cost: PackedFloat32Array, line: PackedVector2Array, gw: int, gh: int, extra: float) -> void:
	for s in line.size() - 1:
		var a := line[s] * Vector2(gw, gh)
		var b := line[s + 1] * Vector2(gw, gh)
		var steps := int(ceil(a.distance_to(b) * 2.0)) + 1
		for k in steps + 1:
			var p := a.lerp(b, float(k) / steps)
			# A one-cell barrier is stepped over diagonally and ignored, so the
			# band is three cells wide.
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var c := Vector2i(p.round()) + Vector2i(dx, dy)
					if c.x >= 0 and c.y >= 0 and c.x < gw and c.y < gh and cost[c.y * gw + c.x] > 0.0:
						cost[c.y * gw + c.x] = maxf(cost[c.y * gw + c.x], 1.0 + extra)


static func _grow_regions(geo: MapGeometry, height: Image, gw: int, gh: int) -> PackedByteArray:
	var cost := _travel_cost(geo, height, gw, gh)
	var count := geo.region_ids.size()
	var owner := PackedByteArray()
	var best := PackedFloat32Array()
	owner.resize(gw * gh)
	best.resize(gw * gh)
	for i in gw * gh:
		owner[i] = 255
		best[i] = INF
	var heap_cost := PackedFloat32Array()
	var heap_cell := PackedInt32Array()
	for i in count:
		# A long region (the Sela's plain, the coastal tail) grows from its seed
		# and from any extra anchors along its length, so it keeps its shape.
		var starts: Array = [geo.seeds[geo.region_ids[i]]]
		starts.append_array(geo.anchors.get(geo.region_ids[i], []))
		for s: Vector2 in starts:
			var c := Vector2i(clampi(int(s.x * gw), 0, gw - 1), clampi(int(s.y * gh), 0, gh - 1))
			var index := c.y * gw + c.x
			best[index] = 0.0
			owner[index] = i
			_heap_push(heap_cost, heap_cell, 0.0, index * 16 + i)
	while not heap_cell.is_empty():
		var top := _heap_pop(heap_cost, heap_cell)
		var d: float = top[0]
		var cell: int = top[1] / 16
		var who: int = top[1] % 16
		if d > best[cell] or owner[cell] != who:
			continue
		var cx := cell % gw
		var cy := cell / gw
		var pace: float = 1.0 / float(geo.weights.get(geo.region_ids[who], 1.0))
		for k in TRAVEL.size():
			var step: Vector2i = TRAVEL[k]
			var nx := cx + step.x
			var ny := cy + step.y
			if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
				continue
			var n := ny * gw + nx
			if cost[n] < 0.0:
				continue
			var nd: float = d + cost[n] * TRAVEL_COST[k] * pace
			if nd < best[n]:
				best[n] = nd
				owner[n] = who
				_heap_push(heap_cost, heap_cell, nd, n * 16 + who)
	_fill_unclaimed(owner, cost, gw, gh, count)
	return owner


static func _fill_unclaimed(owner: PackedByteArray, cost: PackedFloat32Array, gw: int, gh: int, count: int) -> void:
	# Coarse cells the growth never reached (an isolated sliver cut off by the
	# coast warp) take the label of the nearest cell that was reached, so no
	# full-resolution Ardenian pixel is left without a region.
	var queue := PackedInt32Array()
	for i in gw * gh:
		if owner[i] < count:
			queue.append(i)
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		var px := p % gw
		for step: Vector2i in SIDES:
			var nx := px + step.x
			var ny := p / gw + step.y
			if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
				continue
			var n := ny * gw + nx
			if owner[n] >= count:
				owner[n] = owner[p]
				queue.append(n)


static func _heap_push(keys: PackedFloat32Array, values: PackedInt32Array, key: float, value: int) -> void:
	keys.append(key)
	values.append(value)
	var i := keys.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if keys[parent] <= keys[i]:
			break
		_heap_swap(keys, values, i, parent)
		i = parent


static func _heap_pop(keys: PackedFloat32Array, values: PackedInt32Array) -> Array:
	var out := [keys[0], values[0]]
	var last := keys.size() - 1
	_heap_swap(keys, values, 0, last)
	keys.remove_at(last)
	values.remove_at(last)
	var i := 0
	while true:
		var small := i
		for child in [i * 2 + 1, i * 2 + 2]:
			if child < keys.size() and keys[child] < keys[small]:
				small = child
		if small == i:
			break
		_heap_swap(keys, values, i, small)
		i = small
	return out


static func _heap_swap(keys: PackedFloat32Array, values: PackedInt32Array, a: int, b: int) -> void:
	var k := keys[a]
	var v := values[a]
	keys[a] = keys[b]
	values[a] = values[b]
	keys[b] = k
	values[b] = v


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
		if winner == index:
			# An islet the coast cut loose: it touches no other region, so
			# there is nothing to absorb it into. The sea takes it back, and
			# every region stays one connected territory.
			winner = SEA_REGION
		for p in members:
			data[p] = winner
	return Image.create_from_data(RESOLUTION.x, RESOLUTION.y, false, Image.FORMAT_R8, data)


static func index_at(regions: Image, pixel: Vector2i) -> int:
	return int(round(regions.get_pixelv(pixel).r * 255.0))


static func region_at_map(regions: Image, geo: MapGeometry, p: Vector2) -> String:
	var px := Vector2i(clampi(int(p.x * RESOLUTION.x), 0, RESOLUTION.x - 1), clampi(int(p.y * RESOLUTION.y), 0, RESOLUTION.y - 1))
	var index := index_at(regions, px)
	return geo.region_ids[index] if index < geo.region_ids.size() else ""


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
