class_name RegionLandmark
extends RegionBake

## Each region's landmark, the subject at the centre of its frame. Split out
## of `RegionBake`, whose palette and primitives it inherits.


## One landmark at the centre of frame, standing behind the street so the
## front row overlaps its foot. Floodlit stone, lit windows, a silhouette you
## could name from a newsreel still.
static func draw(img: Image, s: RegionScene) -> void:
	var cx := s.landmark_x
	var g := s.ground
	var stone := Color(0.46, 0.44, 0.40)
	var dark := Color(0.10, 0.10, 0.12)
	match s.landmark:
		"parliament":
			fill(img, cx - 84, g - 66, 168, 66, stone)
			fill(img, cx - 88, g - 70, 176, 5, stone.lightened(0.2))
			for c in range(cx - 80, cx + 80, 9):
				fill(img, c, g - 62, 4, 50, stone.lightened(0.25))
				fill(img, c + 3, g - 62, 1, 50, stone.darkened(0.25))
			# The drum, the dome and its lantern stay well under the frame
			# top, even with the camera's push-in.
			fill(img, cx - 40, g - 88, 80, 18, stone.lightened(0.08))
			fill(img, cx - 42, g - 90, 84, 2, TRIM)
			for c in range(cx - 36, cx + 36, 8):
				_window(img, s, c, g - 85, 3, 9, c * 7)
			_dome(img, cx, g - 90, 26, stone.lightened(0.15))
			for y in range(3, 26):                                       # ribs on the dome
				var half := sqrt(float(26 * 26 - (26 - y) * (26 - y)))
				for rib in [-0.6, -0.2, 0.2, 0.6]:
					dot(img, cx + int(rib * half), g - 116 + y, stone.darkened(0.18))
			fill(img, cx - 5, g - 122, 10, 7, stone.lightened(0.2))     # the lantern
			fill(img, cx - 3, g - 120, 2, 4, LIT.darkened(0.2))
			fill(img, cx + 1, g - 120, 2, 4, LIT.darkened(0.2))
			fill(img, cx - 6, g - 123, 12, 1, TRIM)
			fill(img, cx, g - 130, 1, 8, IRON.lightened(0.4))
			s.flag_at = Vector2i(cx, g - 130)
			# Floodlight wash at the foot of the colonnade.
			for y in range(g - 66, g):
				for x in range(cx - 84, cx + 84, 1):
					if (x + y) % 3 == 0:
						blend(img, x, y, LIT, 0.10 * float(y - (g - 66)) / 66.0)
		"works":
			for k in 3:
				var sx := cx - 40 + k * 22
				fill(img, sx, g - 126, 9, 126, Color(0.30, 0.29, 0.28))
				fill(img, sx + 6, g - 126, 3, 126, Color(0.20, 0.19, 0.19))
				for band in [g - 120, g - 100]:
					fill(img, sx, band, 9, 2, ALARM.darkened(0.35))
			# A cooling tower: a waisted hyperbolic shell.
			var tx := cx + 62
			for y in 84:
				var k := float(y) / 84.0
				var half := int(26.0 - 10.0 * sin(k * PI * 0.85))
				fill(img, tx - half, g - 84 + y, half * 2, 1, Color(0.34, 0.33, 0.31).darkened(0.25 * k))
				fill(img, tx + half - 5, g - 84 + y, 5, 1, Color(0.22, 0.22, 0.22))
			fill(img, cx - 70, g - 40, 110, 40, Color(0.18, 0.18, 0.19))
			for wx in range(cx - 66, cx + 36, 7):
				fill(img, wx, g - 30, 4, 6, LIT.darkened(0.15) if s.works_running else DARK_GLASS)
		"lighthouse":
			for y in 96:
				var half := int(lerpf(5.0, 9.0, float(y) / 96.0))
				var band := (y / 12) % 2 == 0
				fill(img, cx - half, g - 96 + y, half * 2, 1, Color(0.80, 0.76, 0.68) if band else ALARM.darkened(0.2))
			fill(img, cx - 8, g - 108, 16, 12, IRON.lightened(0.2))
			fill(img, cx - 5, g - 106, 10, 8, LIT)
			fill(img, cx - 9, g - 110, 18, 2, IRON.lightened(0.35))
			s.beacons.append(Vector2i(cx - 1, g - 113))
		"watchtower":
			# A border tower in cast concrete, standing in its own cleared
			# ground: a tapering shaft, a glazed cabin, a searchlight on the roof.
			var top := s.searchlight_at.y + 17
			var conc := Color(0.40, 0.40, 0.37)
			for y in range(top, g):
				var half := 5 + (y - top) * 4 / maxi(1, g - top)
				fill(img, cx - half, y, half * 2, 1, conc)
				fill(img, cx + half - 3, y, 3, 1, conc.darkened(0.35))
				dot(img, cx - half, y, conc.lightened(0.25))
				if (y - top) % 12 == 0:
					fill(img, cx - half, y, half * 2, 1, conc.darkened(0.2))   # formwork joint
			for y in range(top + 6, g - 4, 3):                                  # the ladder
				fill(img, cx - 2, y, 3, 1, IRON)
			fill(img, cx - 2, g - 12, 5, 12, SHADOW)                              # the door
			fill(img, cx - 17, top - 18, 34, 18, conc.lightened(0.05))           # the cabin
			fill(img, cx + 13, top - 18, 4, 18, conc.darkened(0.3))
			for wx in range(cx - 15, cx + 13, 6):
				fill(img, wx, top - 15, 5, 7, LIT.darkened(0.15) if s.roll(wx, 21) < 0.7 else LIT_COOL.darkened(0.3))
				fill(img, wx + 5, top - 15, 1, 7, conc.darkened(0.4))
			fill(img, cx - 19, top, 38, 2, TRIM)                                 # the floor slab
			fill(img, cx - 20, top - 21, 40, 3, Color(0.16, 0.16, 0.17))        # the roof slab
			fill(img, cx - 20, top - 21, 40, 1, TRIM)
			fill(img, cx - 5, top - 27, 10, 6, IRON.lightened(0.3))              # searchlight housing
			fill(img, cx - 2, top - 26, 4, 3, Color(0.95, 0.92, 0.80))
			fill(img, cx + 14, top - 31, 1, 10, IRON.lightened(0.4))             # flagpole
			s.flag_at = Vector2i(cx + 14, top - 31)
			s.beacons.append(Vector2i(cx - 19, top - 22))
			# The compound wall under it, its coil of wire, and the old fence
			# that runs off along the line in both directions.
			var cl := s.clearing
			fill(img, cl.x, g - 15, cl.y - cl.x, 15, Color(0.30, 0.30, 0.29))
			fill(img, cl.x, g - 15, cl.y - cl.x, 1, TRIM.darkened(0.2))
			for k in range(cl.x, cl.y, 10):
				fill(img, k, g - 14, 1, 14, Color(0.22, 0.22, 0.22))             # panel seams
			for k in range(cl.x, cl.y, 3):
				dot(img, k, g - 17 + (k / 3) % 2, IRON.lightened(0.35))         # razor wire
				dot(img, k + 1, g - 18 + (k / 3 + 1) % 2 * 2, IRON.lightened(0.25))
			fill(img, cx - 9, g - 15, 18, 15, SHADOW)                             # the gate
			for k in range(cx - 9, cx + 9, 3):
				fill(img, k, g - 15, 1, 15, IRON.lightened(0.3))
			for fx in range(0, s.cols, 9):
				if fx < cl.x or fx >= cl.y:
					fill(img, fx, g - 12, 1, 9, IRON.lightened(0.25))
			for wire in 3:
				fill(img, 0, g - 11 + wire * 3, cl.x, 1, IRON.lightened(0.12))
				fill(img, cl.y, g - 11 + wire * 3, s.cols - cl.y, 1, IRON.lightened(0.12))
		"silos":
			for k in 4:
				var sx := cx - 52 + k * 26
				fill(img, sx, g - 92, 22, 92, Color(0.52, 0.50, 0.44))
				fill(img, sx + 16, g - 92, 6, 92, Color(0.38, 0.36, 0.32))
				for r in 8:   # conical cap, point upward
					var inset := 7 - r
					fill(img, sx + inset, g - 100 + r, 22 - 2 * inset, 1, Color(0.44, 0.42, 0.38))
			fill(img, cx + 54, g - 120, 14, 120, Color(0.40, 0.38, 0.34))
			fill(img, cx + 57, g - 112, 5, 5, LIT.darkened(0.2))
		"monastery":
			# A crag rising behind the town, the monastery seated on its crown.
			var crown := s.horizon - int(s.horizon * 0.25)
			var ys := ridge(s, float(crown) + 8.0, 6.0, 0.6)
			for x in range(cx - 120, cx + 120):
				if x < 0 or x >= s.cols:
					continue
				var k := absf(x - cx) / 120.0
				var y := int(lerpf(ys[x], float(g), k * k))
				fill(img, x, y, 1, g - y, RIDGE_NEAR.lightened(0.18))
				if x % 3 == 0:
					dot(img, x, y, RIDGE_NEAR.lightened(0.45))
			var top := int(ys[clampi(cx, 0, s.cols - 1)]) + 2
			fill(img, cx - 34, top - 26, 68, 26, stone)
			fill(img, cx - 6, top - 60, 12, 34, stone.lightened(0.05))
			for i in 8:
				var inset := (7 - i) * 3 / 4
				fill(img, cx - 6 + inset, top - 72 + i * 2, 12 - inset * 2, 2, ROOF)
			for c in range(cx - 28, cx + 28, 8):
				_window(img, s, c, top - 20, 3, 6, c * 3)
			_window(img, s, cx - 2, top - 50, 4, 7, 991)
		"viaduct":
			# Far off, so it prints as a dot grid; its coping, piers' lit
			# faces and arch rings are the crisp lines.
			var deck := s.horizon - 20
			var body := Color(0.15, 0.12, 0.095)
			var line := Color(0.42, 0.35, 0.27)
			fill(img, 0, deck, s.cols, 6, body)
			fill(img, 0, deck - 2, s.cols, 2, line)                           # coping
			for px in range(0, s.cols, 6):                                     # parapet posts
				fill(img, px, deck - 4, 2, 2, line)
			# Two tiers of round arches on piers every 34 px, the spandrels
			# solid above each curve and open below it.
			var tier2 := deck + 30
			for ax in range(0, s.cols, 34):
				fill(img, ax, deck + 6, 8, s.ground - deck - 6, body)
				fill(img, ax, deck + 6, 2, s.ground - deck - 6, line.darkened(0.25))
				for top in [deck + 6, tier2 + 3]:
					for dx in 26:
						var off := float(dx) - 12.5
						var drop := 13 - int(sqrt(maxf(0.0, 169.0 - off * off)))
						fill(img, ax + 8 + dx, top, 1, 3 + drop, body)
						fill(img, ax + 8 + dx, top + 3 + drop, 1, 2, line.darkened(0.15))   # the arch ring
			fill(img, 0, tier2, s.cols, 3, body)                               # the lower deck
			fill(img, 0, tier2, s.cols, 2, line.darkened(0.15))
		"clocktower":
			var th := mini(g - 26, 120)
			fill(img, cx - 12, g - th, 24, th, stone)
			fill(img, cx + 6, g - th, 6, th, stone.darkened(0.3))
			for i in 10:
				var inset := 9 - i
				fill(img, cx - 12 + inset, g - th - 20 + i * 2, 24 - 2 * inset, 2, ROOF)
			s.clock_at = Vector2i(cx, g - th + 18)
			_dome(img, cx, g - th + 27, 9, Color(0.90, 0.86, 0.72))
			for wy in range(g - th + 40, g - 10, 14):
				_window(img, s, cx - 2, wy, 4, 7, wy)
		"fortress":
			# The hill prints as a dark dot grid with a lit crest, so the
			# walls stand on it instead of on a flat grey mound.
			var hill := Color(0.08, 0.095, 0.065)
			for x in range(cx - 130, cx + 130):
				if x < 0 or x >= s.cols:
					continue
				# A flat-crowned hill, so the walls have ground under all of them.
				var y := int(g - 30 - 40.0 * (1.0 - pow(absf(x - cx) / 130.0, 6.0)))
				fill(img, x, y, 1, g - y, hill)
				fill(img, x, y, 1, 2, LAND.lightened(0.28))
				if (x * 7) % 23 < 2 and y < g - 34:                 # scrub on the slope
					fill(img, x, y + 5 + (x * 13) % 9, 2, 2, PINE.lightened(0.2))
			for k in 6:                                              # the switchback path up
				var py := g - 34 - k * 6
				var px0 := cx - 100 + (k % 2) * 30 + k * 6
				fill(img, px0, py, 34, 1, LAND.lightened(0.22))
			var top := g - 68
			var wall_c := stone.darkened(0.1)
			fill(img, cx - 70, top - 24, 140, 24, wall_c)
			fill(img, cx - 74, top, 150, 6, stone.darkened(0.35))   # footing
			fill(img, cx - 70, top - 24, 140, 2, SHADOW)             # shadow under the wall-walk
			for k in range(cx - 70, cx + 70, 8):
				fill(img, k, top - 28, 4, 4, wall_c)
			for k in range(cx - 62, cx + 62, 12):                   # arrow slits
				fill(img, k, top - 17, 2, 6, SHADOW)
			fill(img, cx - 34, top - 14, 8, 14, SHADOW)              # the gate
			fill(img, cx - 33, top - 16, 6, 2, SHADOW)
			for tx in [cx - 74, cx - 8, cx + 62]:
				fill(img, tx, top - 48, 14, 48, stone)
				fill(img, tx + 11, top - 48, 3, 48, stone.darkened(0.3))
				fill(img, tx - 1, top - 50, 16, 2, TRIM)
				for k in range(tx, tx + 14, 4):
					fill(img, k, top - 54, 2, 4, stone)
				_window(img, s, tx + 5, top - 38, 3, 6, tx)
				fill(img, tx + 5, top - 22, 2, 5, SHADOW)


## A filled half-disc, lit on its left shoulder.
static func _dome(img: Image, cx: int, base: int, r: int, tone: Color) -> void:
	for y in r:
		var half := int(sqrt(float(r * r - (r - y) * (r - y))))
		fill(img, cx - half, base - r + y, half * 2, 1, tone.darkened(0.1 * float(y) / r))
		fill(img, cx - half, base - r + y, maxi(1, half / 3), 1, tone.lightened(0.15))
