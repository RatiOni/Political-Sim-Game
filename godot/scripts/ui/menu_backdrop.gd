class_name MenuBackdrop
extends Control

## The title screen's scene, drawn rather than painted: a dithered dusk sky
## over the northern ridges, the Kesla plain, and a lit capital on the
## horizon. Everything is blocks of `MapPalette.DUSK` on an 8 px grid, so the
## menu is the same world the map is.
##
## Deterministic by construction — the skyline comes from a fixed seed, so the
## title screen is the same picture every launch.

const CELL := 8
const SEED := 19930601   # Ardenia, June 1993

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var cols := int(ceil(size.x / CELL))
	var rows := int(ceil(size.y / CELL))
	if cols <= 0 or rows <= 0:
		return
	_rng.seed = SEED

	var pal := MapPalette.DUSK
	draw_rect(Rect2(Vector2.ZERO, size), UiPalette.WINDOW, true)

	# Sky: three dusk bands, dithered where they meet so the step reads as
	# deliberate texture instead of a seam.
	var horizon := int(rows * 0.74)
	var bands := [pal[MapPalette.DEEP_SEA], pal[MapPalette.SEA], pal[MapPalette.WAVE]]
	for row in horizon:
		var t := float(row) / maxf(1.0, float(horizon))
		var band := mini(bands.size() - 1, int(t * bands.size()))
		for col in cols:
			var color: Color = bands[band]
			if _dither(col, row) and band + 1 < bands.size():
				color = bands[band + 1]
			draw_rect(Rect2(col * CELL, row * CELL, CELL, CELL), color, true)

	# A few stars in the upper band only.
	for _i in 28:
		var sx := _rng.randi_range(0, maxi(0, cols - 1))
		var sy := _rng.randi_range(0, maxi(0, int(horizon * 0.45)))
		draw_rect(Rect2(sx * CELL + 3, sy * CELL + 3, 2, 2), pal[MapPalette.SNOW_SHADE], true)

	# Northern ridges: three layers receding into haze, the far ones paler and
	# taller, so the north reads as mountains rather than hills.
	_ridge(cols, horizon, 6, 0.46, pal[MapPalette.ROCK], true)
	_ridge(cols, horizon, 5, 0.32, pal[MapPalette.ROCK_DARK], true)
	_ridge(cols, horizon, 4, 0.18, pal[MapPalette.HILL_DARK], false)

	_capital(cols, horizon, pal)
	_plain(cols, rows, horizon, pal)


## Checkerboard dither on the cell grid — the cheapest texture that still
## reads as deliberate at 8 px.
func _dither(col: int, row: int) -> bool:
	return (col + row) % 2 == 0


## One mountain layer. `rise` is its height as a fraction of the sky, so the
## far layers sit highest and the near ones overlap them.
func _ridge(cols: int, horizon: int, amplitude: int, rise: float, color: Color, capped: bool) -> void:
	var base := horizon - int(horizon * rise)
	var peak := base
	for col in cols:
		# Random walk, clamped — mountains, not a sawtooth.
		peak += _rng.randi_range(-1, 1)
		peak = clampi(peak, base - amplitude, base + amplitude)
		for row in range(peak, horizon):
			draw_rect(Rect2(col * CELL, row * CELL, CELL, CELL), color, true)
		# Snow on the tallest cells only, so the caps mean altitude.
		if capped and peak <= base - amplitude + 1:
			draw_rect(Rect2(col * CELL, peak * CELL, CELL, CELL), MapPalette.DUSK[MapPalette.SNOW_SHADE], true)


## The Kesla plain: fields rather than a lawn. Blocks of farm and grass on a
## coarse grid, a river running to the coast, and a road to the capital.
func _plain(cols: int, rows: int, horizon: int, pal: PackedColorArray) -> void:
	var field_w := 7
	var field_h := 3
	for row in range(horizon, rows):
		for col in cols:
			# Fields are blocks, not per-cell noise, so the land reads as
			# worked rather than static.
			var fx := col / field_w
			var fy := (row - horizon) / field_h
			var kind := (fx * 7 + fy * 13 + SEED) % 5
			var ground: Color = pal[MapPalette.GRASS_DARK]
			match kind:
				0, 1:
					ground = pal[MapPalette.FARM_DARK] if _dither(col, row) else pal[MapPalette.FARM]
				2:
					ground = pal[MapPalette.GRASS] if _dither(col, row) else pal[MapPalette.GRASS_DARK]
				3:
					ground = pal[MapPalette.FARM_GREEN]
				_:
					ground = pal[MapPalette.GRASS_DARK]
			draw_rect(Rect2(col * CELL, row * CELL, CELL, CELL), ground, true)

	# The Kesla, widening as it nears the viewer.
	var river_col := float(cols) * 0.30
	for row in range(horizon, rows):
		var depth := float(row - horizon) / maxf(1.0, float(rows - horizon))
		river_col -= 0.55
		var width := 1 + int(depth * 3.0)
		for w in width:
			var col := int(river_col) + w
			if col >= 0 and col < cols:
				draw_rect(Rect2(col * CELL, row * CELL, CELL, CELL), pal[MapPalette.RIVER], true)

	# A road from the foreground up to the capital on the horizon.
	var road_col := float(cols) * 0.62
	for row in range(horizon, rows):
		road_col += 0.42
		var col := int(road_col)
		if col >= 0 and col < cols:
			draw_rect(Rect2(col * CELL, row * CELL, CELL, CELL), pal[MapPalette.ROAD], true)


## A low skyline on the horizon with lit windows — Vashtera at dusk.
func _capital(cols: int, horizon: int, pal: PackedColorArray) -> void:
	var start := int(cols * 0.56)
	var span := maxi(8, int(cols * 0.18))
	for i in span:
		var col := start + i
		if col >= cols:
			break
		var tall := _rng.randi_range(1, 3)
		if i == int(span * 0.4):
			tall = 5   # one tower, so the skyline has a subject
		for row in range(horizon - tall, horizon):
			draw_rect(Rect2(col * CELL, row * CELL, CELL, CELL), pal[MapPalette.WALL], true)
			if _rng.randf() < 0.45:
				draw_rect(Rect2(col * CELL + 2, row * CELL + 2, 3, 3), MapPalette.DAY[MapPalette.LIT], true)
