class_name RegionStreet
extends RegionBake

## The street and the near ground of a region picture: pavement, kerbs, the
## road (asphalt or dirt), street furniture, and the band nearest the eye —
## quay and water, or the country itself (border strip, fields, a goods
## siding, hill walls and pines). Split out of `RegionBake`, whose palette
## and primitives it inherits.


static func street(img: Image, s: RegionScene) -> void:
	fill(img, 0, s.ground, s.cols, s.road_top - s.ground, PAVEMENT)
	fill(img, 0, s.ground, s.cols, 1, PAVEMENT.darkened(0.35))          # foot of the walls
	for jx in range(0, s.cols, 8):
		fill(img, jx, s.ground + 1, 1, s.road_top - s.ground - 1, PAVEMENT.darkened(0.25))
	# The kerb: a pale edge stone over its own shadow.
	fill(img, 0, s.road_top - 2, s.cols, 1, KERB.lightened(0.12))
	fill(img, 0, s.road_top - 1, s.cols, 1, KERB.darkened(0.25))
	if s.paved:
		_asphalt(img, s)
	elif s.land == RegionScene.Land.COAST:
		_setts(img, s)
	else:
		_dirt_road(img, s)
	fill(img, 0, s.front, s.cols, 1, KERB.lightened(0.12))
	fill(img, 0, s.front + 1, s.cols, 1, KERB.darkened(0.25))
	# Lamp posts on a footing with a swan-neck arm; benches and bins.
	var post := IRON
	for lx in s.lamps:
		fill(img, lx - 1, s.ground - 3, 4, 3, post)                   # footing
		fill(img, lx, s.ground - 26, 2, 26, post)
		fill(img, lx, s.ground - 27, 5, 2, post)                      # arm
		fill(img, lx + 3, s.ground - 25, 3, 2, IRON.lightened(0.45))  # lantern housing
		fill(img, lx - 1, s.ground - 28, 4, 1, post)                  # finial
		if s.roll(lx, 9) < 0.3:
			fill(img, lx + 8, s.road_top - 6, 9, 2, BOARD.lightened(0.2))
			fill(img, lx + 8, s.road_top - 9, 9, 1, BOARD.lightened(0.1))
			fill(img, lx + 8, s.road_top - 4, 1, 2, IRON)
			fill(img, lx + 16, s.road_top - 4, 1, 2, IRON)
		elif s.roll(lx, 10) < 0.25:
			fill(img, lx + 6, s.road_top - 7, 4, 5, Color(0.14, 0.20, 0.16))
			fill(img, lx + 5, s.road_top - 8, 6, 1, Color(0.20, 0.28, 0.22))
	for kx in s.kiosks:
		_kiosk(img, s, kx)
	if s.tram:
		# The overhead wire over the rails, slung between span poles on the
		# near kerb; the tram's pantograph rides it.
		var wire := s.road_top + s.road_h / 2 - 24
		var poles: Array[int] = []
		for px in range(24, s.cols + 60, 60):
			poles.append(px)
			fill(img, px, wire - 2, 2, s.front - wire + 2, IRON.lightened(0.12))
			fill(img, px - 1, wire - 3, 4, 1, IRON.lightened(0.3))
		for i in poles.size() - 1:
			for wx in range(poles[i] + 2, poles[i + 1]):
				var t := float(wx - poles[i]) / 60.0
				dot(img, wx, wire + int(2.0 * 4.0 * t * (1.0 - t)), IRON.lightened(0.45))
	# Old towns keep wooden poles and a sagging wire.
	if not s.paved:
		var poles: Array[int] = []
		for px in range(20, s.cols, 64):
			poles.append(px)
			fill(img, px, s.ground - 34, 2, 34, BOARD)
			fill(img, px - 4, s.ground - 33, 10, 2, BOARD)
			dot(img, px - 3, s.ground - 34, KERB)
			dot(img, px + 4, s.ground - 34, KERB)
		for i in poles.size() - 1:
			var a := poles[i] + 1
			var z := poles[i + 1] + 1
			for wx in range(a, z):
				var t := float(wx - a) / float(z - a)
				dot(img, wx, s.ground - 33 + int(6.0 * 4.0 * t * (1.0 - t)), IRON.lightened(0.15))


## A paved road: worn lanes, repair patches, drains, a zebra crossing in
## front of the landmark, and tram rails or a centre line.
static func _asphalt(img: Image, s: RegionScene) -> void:
	var mid := s.road_top + s.road_h / 2
	fill(img, 0, s.road_top, s.cols, s.road_h, ROAD)
	for lane in [s.road_top + 3, mid + 3]:                          # tyre-polished lanes
		fill(img, 0, lane + 1, s.cols, 1, ROAD.lightened(0.05))
		fill(img, 0, lane + 5, s.cols, 1, ROAD.lightened(0.05))
	for i in int(s.cols / 70):                                      # repair patches
		var px := int(s.roll(i, 31) * s.cols)
		var py := s.road_top + 2 + int(s.roll(i, 32) * (s.road_h - 6))
		fill(img, px, py, 10 + int(s.roll(i, 33) * 16), 3, ROAD.lightened(0.07) if i % 2 else ROAD.darkened(0.3))
	if s.tram:
		# The tram runs down the crown of the road: two steel rails with
		# sleepers set in the setts, in place of the centre line.
		fill(img, 0, mid - 3, s.cols, 6, ROAD.lightened(0.04))
		for sx in range(0, s.cols, 5):
			fill(img, sx, mid - 2, 2, 4, ROAD.lightened(0.10))
		fill(img, 0, mid - 3, s.cols, 1, KERB.lightened(0.15))
		fill(img, 0, mid + 2, s.cols, 1, KERB.lightened(0.15))
	else:
		for dx in range(4, s.cols, 18):
			fill(img, dx, mid, 9, 1, MARKING)
	for mx in range(30, s.cols, 110):               # drains and manholes
		fill(img, mx, s.road_top + 1, 5, 2, IRON)
		for k in range(mx, mx + 5, 2):
			dot(img, k, s.road_top + 1, KERB.darkened(0.4))
		fill(img, mx + 52, s.front - 5, 6, 2, IRON.lightened(0.1))
	# The crossing: seen from the side its stripes are bars lying along the
	# road, stacked from the far kerb to the near one; a beacon post each side.
	var zx := s.landmark_x - 14 if s.landmark != "works" else int(s.cols * 0.33)
	for row in range(s.road_top + 1, s.front - 1, 4):
		fill(img, zx, row, 28, 2, KERB.lightened(0.25))
	for bx in [zx - 4, zx + 29]:
		fill(img, bx, s.road_top - 12, 1, 11, IRON.lightened(0.3))
		fill(img, bx - 1, s.road_top - 15, 3, 3, GOLD)


## An unmade road: two wheel ruts worn dark, a crown of grass between them,
## puddles holding the sky, stones, and rough verges.
static func _dirt_road(img: Image, s: RegionScene) -> void:
	fill(img, 0, s.road_top, s.cols, s.road_h, DIRT)
	var mid := s.road_top + s.road_h / 2
	for rut in [s.road_top + 5, mid + 5]:
		fill(img, 0, rut, s.cols, 2, DIRT.darkened(0.4))
		fill(img, 0, rut + 2, s.cols, 1, DIRT.lightened(0.12))
	for gx in range(0, s.cols, 3):                                  # the grassy crown
		if s.roll(gx, 41) < 0.55:
			fill(img, gx, mid - 1 - int(s.roll(gx, 42) * 2.0), 1, 2, LAND.lightened(0.18))
	for i in int(s.cols / 60):                                      # puddles
		var px := int(s.roll(i, 43) * s.cols)
		var py := (s.road_top + 4) if i % 2 == 0 else (mid + 4)
		var pw := 10 + int(s.roll(i, 44) * 14)
		fill(img, px + 2, py, pw - 4, 1, WATER.lightened(0.10))
		fill(img, px, py + 1, pw, 2, WATER.lightened(0.04))
		fill(img, px + 1, py + 1, pw / 3, 1, SKY_LOW.lightened(0.25))   # the sky in it
	for i in int(s.cols / 8):                                       # stones
		dot(img, int(s.roll(i, 45) * s.cols), s.road_top + 1 + int(s.roll(i, 46) * (s.road_h - 2)), DIRT.lightened(0.3))
	for edge in [s.road_top, s.front - 2]:                          # ragged verges
		for gx in range(0, s.cols, 2):
			if s.roll(gx, edge) < 0.5:
				fill(img, gx, edge, 1, 1 + int(s.roll(gx, edge + 1) * 2.0), LAND.lightened(0.15))


## A harbour street in old setts: grey stones in staggered courses, worn
## smooth and pale along the two wheel tracks.
static func _setts(img: Image, s: RegionScene) -> void:
	var stone := Color(0.13, 0.13, 0.14)
	fill(img, 0, s.road_top, s.cols, s.road_h, stone)
	for ry in range(s.road_top + 2, s.front, 3):
		fill(img, 0, ry, s.cols, 1, stone.darkened(0.45))
		for jx in range((ry / 3) % 2 * 3, s.cols, 6):
			dot(img, jx, ry - 1, stone.darkened(0.45))
	var mid := s.road_top + s.road_h / 2
	for track in [s.road_top + 5, mid + 5]:
		fill(img, 0, track, s.cols, 2, stone.lightened(0.12))


## A newspaper kiosk: a green box with a lit hatch, a striped awning and a
## sign on the roof, standing on the kerb.
static func _kiosk(img: Image, s: RegionScene, x: int) -> void:
	var foot := s.road_top - 1
	var green := Color(0.16, 0.28, 0.22)
	fill(img, x, foot - 15, 13, 15, green)
	fill(img, x + 11, foot - 15, 2, 15, green.darkened(0.4))
	fill(img, x, foot - 15, 1, 15, green.lightened(0.3))
	fill(img, x + 2, foot - 11, 8, 5, LIT.darkened(0.1))          # the hatch
	for k in 4:
		fill(img, x + 2 + k * 2, foot - 7, 1, 1, WALLS[k].lightened(0.3))   # papers on the counter
	for k in range(0, 15, 3):
		fill(img, x - 1 + k, foot - 17, 2, 2, ALARM.darkened(0.15))
		fill(img, x + 1 + k, foot - 17, 1, 2, TRIM)
	fill(img, x + 1, foot - 21, 11, 4, Color(0.10, 0.09, 0.08))   # the roof sign
	for k in range(x + 2, x + 11, 2):
		dot(img, k, foot - 19, GOLD)


static func foreground(img: Image, s: RegionScene) -> void:
	if s.water_top < 0:
		_near_ground(img, s)
		return
	# The quay wall: dressed stone courses down to the water.
	fill(img, 0, s.front + 2, s.cols, s.water_top - s.front - 2, KERB.darkened(0.35))
	for bx in range(0, s.cols, 6):
		dot(img, bx, s.front + 3, KERB.darkened(0.55))
	gradient(img, 0, s.water_top, s.cols, s.h, WATER.lightened(0.08), WATER, 5)
	fill(img, 0, s.water_top, s.cols, 1, WATER.darkened(0.4))         # the waterline
	if s.land == RegionScene.Land.BASIN:
		# Embankment railing: a two-pixel top rail on posts, lamps' bollards.
		for rx in range(0, s.cols, 5):
			fill(img, rx, s.front - 5, 1, 4, IRON.lightened(0.3))
		fill(img, 0, s.front - 6, s.cols, 2, IRON.lightened(0.38))
		for bx in range(14, s.cols, 60):
			fill(img, bx, s.front - 4, 3, 4, IRON.lightened(0.2))
	else:
		for px in range(40, s.cols, 90):               # piers on piles
			fill(img, px, s.water_top - 2, 30, 2, BOARD.lightened(0.1))
			fill(img, px, s.water_top, 30, 1, BOARD.darkened(0.3))
			for k in range(px, px + 30, 7):
				fill(img, k, s.water_top + 1, 2, 9, BOARD.darkened(0.4))
			for k in 3:                                # bollards and a coil of rope
				fill(img, px + 4 + k * 10, s.water_top - 5, 3, 3, IRON.lightened(0.25))
			fill(img, px + 22, s.water_top - 4, 4, 2, BOARD.lightened(0.4))


## The near ground where there is no water: a verge, a footpath the walkers
## of lane 3 use, and a band of whatever the country is made of.
static func _near_ground(img: Image, s: RegionScene) -> void:
	var y0 := s.front + 2
	gradient(img, 0, y0, s.cols, s.h, LAND.lightened(0.05), LAND.darkened(0.45), 4)
	var path := s.front + 9
	fill(img, 0, path, s.cols, 4, DIRT.darkened(0.15))               # the footpath
	fill(img, 0, path, s.cols, 1, DIRT.lightened(0.1))
	for gx in range(0, s.cols, 2):                                    # grass at its edges
		if s.roll(gx, 51) < 0.6:
			fill(img, gx, path - 1 - int(s.roll(gx, 52) * 3.0), 1, 2, LAND.lightened(0.3))
		if s.roll(gx, 53) < 0.4:
			dot(img, gx, path + 4, LAND.lightened(0.22))
	var band := path + 5
	match s.land:
		RegionScene.Land.FRONTIER: _frontier_ground(img, s, band)
		RegionScene.Land.PLAIN: _fields(img, s, band)
		RegionScene.Land.INDUSTRY, RegionScene.Land.TRADE: _siding(img, s, band)
		_: _upland_ground(img, s, band)


## The border strip: a concrete-post wire fence, warning signs, anti-tank
## hedgehogs in the grass, and a sandbagged pit.
static func _frontier_ground(img: Image, s: RegionScene, y: int) -> void:
	# Close to the eye, so drawn big: posts three pixels wide with cranked
	# tops, wire bright enough to print as a line, steel hedgehogs in front.
	var post := Color(0.42, 0.42, 0.39)
	var wire := IRON.lightened(0.5)
	for fx in range(6, s.cols, 24):
		fill(img, fx, y - 3, 3, 15, post)
		fill(img, fx + 2, y - 3, 1, 15, post.darkened(0.35))
		fill(img, fx + 3, y - 5, 2, 2, post)                          # the cranked top
	for row in 3:
		fill(img, 0, y - 1 + row * 4, s.cols, 1, wire.darkened(0.12 * row))
	for k in range(0, s.cols, 4):                                     # a coil along the top
		fill(img, k, y - 4 + (k / 4) % 2, 2, 1, wire)
	for sx in range(66, s.cols, 150):                                 # warning signs
		fill(img, sx, y - 2, 8, 7, Color(0.78, 0.74, 0.64))
		fill(img, sx + 1, y, 6, 2, ALARM)
	for hx in range(30, s.cols, 64):                                  # hedgehogs
		var hy := y + 2 + int(s.roll(hx, 61) * 3.0)
		var steel := IRON.lightened(0.38)
		for d in 11:
			fill(img, hx + d, hy + d, 2, 1, steel)
			fill(img, hx + 10 - d, hy + d, 2, 1, steel.darkened(0.3))
		fill(img, hx + 3, hy + 5, 7, 2, steel.lightened(0.1))
	var bx := s.landmark_x + 74
	for row in 3:                                                     # the sandbagged pit
		for k in 8 - row:
			fill(img, bx + row * 3 + k * 6, y + 9 - row * 4, 6, 4, Color(0.45, 0.40, 0.28).darkened(0.2 * ((k + row) % 2)))
	fill(img, bx + 16, y - 6, 2, 4, IRON)                             # the gun on its mount
	fill(img, bx + 16, y - 6, 14, 2, IRON.lightened(0.25))


## Arable land up to the road: furrows, ripe strips and stubble, round
## bales and a scarecrow.
static func _fields(img: Image, s: RegionScene, y: int) -> void:
	var x := 0
	var strip := 0
	while x < s.cols:
		var w := 60 + int(s.roll(strip, 71) * 80)
		var ripe := strip % 3 != 1
		var tone := Color(0.30, 0.25, 0.10) if ripe else Color(0.16, 0.12, 0.08)
		fill(img, x, y, w, s.h - y, tone)
		# Crop rows slanting away from the eye, two pixels wide so they
		# survive the converter as a hatch rather than averaging to flat.
		for ry in range(y, s.h):
			var off := (s.h - ry) * 2
			for fx in range(x + (off % 7), x + w - 1, 7):
				fill(img, fx, ry, 2, 1, tone.lightened(0.35) if ripe else tone.darkened(0.45))
		fill(img, x + w - 1, y, 1, s.h - y, LAND.darkened(0.2))      # the boundary
		if ripe and s.roll(strip, 72) < 0.6:                          # round bales
			for b in 2:
				var bx := x + 10 + b * 22 + int(s.roll(strip, 73 + b) * 10)
				fill(img, bx, y + 4, 7, 6, GOLD.darkened(0.25))
				fill(img, bx + 1, y + 3, 5, 1, GOLD.darkened(0.15))
				fill(img, bx + 5, y + 4, 2, 6, GOLD.darkened(0.5))
		x += w
		strip += 1
	var sc := int(s.cols * 0.82)                                      # a scarecrow
	fill(img, sc, y - 6, 1, 14, BOARD)
	fill(img, sc - 4, y - 3, 9, 1, BOARD)
	fill(img, sc - 1, y - 9, 3, 3, Color(0.55, 0.45, 0.25))
	fill(img, sc - 2, y - 2, 5, 5, Color(0.28, 0.22, 0.30))


## Working ground: a goods siding on ballast, a rake of wagons, containers
## where it is a trading town, and a coal heap.
static func _siding(img: Image, s: RegionScene, y: int) -> void:
	fill(img, 0, y + 6, s.cols, 4, Color(0.15, 0.14, 0.13))         # ballast
	for sx in range(0, s.cols, 4):
		fill(img, sx, y + 7, 2, 3, BOARD.darkened(0.4))               # sleepers
	fill(img, 0, y + 7, s.cols, 1, KERB.lightened(0.1))               # rails
	fill(img, 0, y + 9, s.cols, 1, KERB)
	var trade := s.land == RegionScene.Land.TRADE
	var boxes: Array[Color] = [Color(0.40, 0.18, 0.12), Color(0.18, 0.30, 0.40), Color(0.32, 0.30, 0.20), Color(0.24, 0.32, 0.22)]
	var x := 20 + int(s.roll(81) * 40)
	var k := 0
	while x < s.cols - 40:
		if s.roll(k, 82) < 0.7:
			var tone: Color = boxes[k % 4] if trade else Color(0.30, 0.20, 0.15).darkened(0.2 * (k % 2))
			fill(img, x, y - 8, 34, 14, tone)
			fill(img, x, y - 8, 34, 2, tone.lightened(0.3))
			fill(img, x + 32, y - 8, 2, 14, tone.darkened(0.4))
			for rib in range(x + 5, x + 31, 6 if trade else 8):
				fill(img, rib, y - 6, 2, 11, tone.darkened(0.35))
			fill(img, x + 12, y - 5, 10, 9, tone.darkened(0.55))          # the sliding door
			fill(img, x - 1, y + 5, 36, 2, Color(0.08, 0.08, 0.08))       # the underframe
			for wx in [x + 2, x + 8, x + 22, x + 28]:
				fill(img, wx, y + 6, 4, 3, Color(0.05, 0.05, 0.05))
				dot(img, wx + 1, y + 7, IRON.lightened(0.3))
			if trade and s.roll(k, 83) < 0.5:                         # a second box stacked on top
				fill(img, x + 2, y - 17, 30, 9, boxes[(k + 2) % 4].darkened(0.1))
				fill(img, x + 2, y - 17, 30, 1, TRIM.darkened(0.2))
				for rib in range(x + 5, x + 30, 5):
					fill(img, rib, y - 16, 1, 8, boxes[(k + 2) % 4].darkened(0.4))
			x += 36
		else:
			x += 50
		k += 1
	if not trade:
		var cx := int(s.cols * 0.15)
		for r in 8:                                                     # the coal heap
			fill(img, cx - 20 + r * 2, y - 2 - r, 40 - r * 4, 1, Color(0.09, 0.09, 0.10) if r % 2 else Color(0.06, 0.06, 0.07))


## Hill country: a dry-stone wall, boulders, and the dark crowns of pines
## standing close to the eye.
static func _upland_ground(img: Image, s: RegionScene, y: int) -> void:
	var stone := Color(0.34, 0.33, 0.30)
	for wx in range(0, s.cols, 5):                                    # the wall
		var sh := int(s.roll(wx, 91) * 2.0)
		fill(img, wx, y + 1 - sh, 5, 6 + sh, stone.darkened(0.15 * ((wx / 5) % 2)))
		fill(img, wx, y + 1 - sh, 4, 1, stone.lightened(0.25))
		fill(img, wx + 4, y + 2 - sh, 1, 5 + sh, SHADOW)
	for i in int(s.cols / 90):                                        # boulders
		var bx := int(s.roll(i, 92) * s.cols)
		fill(img, bx, y + 10, 9, 5, stone.darkened(0.2))
		fill(img, bx + 1, y + 9, 6, 1, stone.lightened(0.15))
	# Pines standing close to the eye: three tiers each, lit on the left.
	for i in int(s.cols / 110) + 2:
		var px := int(s.roll(i, 93) * s.cols)
		var foot := s.h + 2
		for tier in 3:
			var ty := foot - 30 + tier * 8
			for r in 12:
				var half := 2 + r * (3 + tier) / 6
				fill(img, px - half, ty + r, half * 2, 1, PINE.lightened(0.04))
				fill(img, px - half, ty + r, maxi(1, half / 2), 1, Color(0.12, 0.22, 0.10))
		fill(img, px - 1, foot - 6, 3, 6, BOARD.darkened(0.3))
