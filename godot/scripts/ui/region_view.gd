class_name RegionView
extends Control

## A pixel vignette of one region: its land, its town, and how it is doing.
##
## Two things are deliberately separated:
##
## * **Layout is seeded from the region id**, so a place keeps the same hills,
##   the same street and the same buildings for the whole campaign. Re-rolling
##   the layout every repaint would make the picture flicker instead of tell a
##   story.
## * **Appearance is driven by live figures** — development, population,
##   unemployment, pressure, state reach, control. Those move slowly, so the
##   same town visibly builds up, lights up, boards up or burns as the
##   campaign runs.
##
## Drawn on a fixed virtual grid and scaled by whole numbers only, so it stays
## in the map's 8 px idiom at any panel size.

## Rows are fixed; columns follow the panel's aspect so the picture fills
## its frame instead of sitting letterboxed in it.
const GRID_Y := 56
const GRID_X_MIN := 96
const HORIZON := 34     # ground starts here, in grid rows

enum Land { HIGHLAND, PASS, BASIN, INDUSTRY, FRONTIER, PLAIN, TRADE, FOOTHILL, COAST }

## Terrain character per region, from `content/lore/ardenia_map_bible.md`.
## Unknown ids fall back to the central plain rather than drawing nothing.
const LAND_OF := {
	"anera": Land.HIGHLAND,
	"karsen": Land.PASS,
	"vashtera": Land.BASIN,
	"zavost": Land.INDUSTRY,
	"darev": Land.FRONTIER,
	"sela": Land.PLAIN,
	"kelvet": Land.TRADE,
	"orvena": Land.FOOTHILL,
	"vetrenka": Land.COAST,
}

var _region: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _cell := 4
var _cols := 140
var _origin := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 300)


func show_region(region: Dictionary) -> void:
	_region = region
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


# --- grid helpers -------------------------------------------------------

func _px(gx: float, gy: float, w: float = 1.0, h: float = 1.0) -> Rect2:
	return Rect2(_origin + Vector2(gx * _cell, gy * _cell), Vector2(w * _cell, h * _cell))


func _blk(gx: float, gy: float, w: float, h: float, color: Color) -> void:
	draw_rect(_px(gx, gy, w, h), color, true)


func _draw() -> void:
	_cell = maxi(1, int(size.y / GRID_Y))
	_cols = maxi(GRID_X_MIN, int(size.x / _cell))
	var used := Vector2(_cols * _cell, GRID_Y * _cell)
	_origin = ((size - used) * 0.5).floor()

	if _region.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), UiPalette.TRACK, true)
		return

	# One stable stream per region: same town every frame, every session.
	_rng.seed = hash(String(_region.get("id", "region")))

	var development := clampf(float(_region.get("development", 0.5)), 0.0, 1.0)
	var pressure := clampf(float(_region.get("pressure", 0.0)), 0.0, 1.0)
	var unemployment := clampf(float(_region.get("unemployment", 0.0)), 0.0, 1.0)
	var reach := clampf(float(_region.get("state_reach", 0.5)), 0.0, 1.0)
	var insurgency := clampf(float(_region.get("insurgency", 0.0)), 0.0, 1.0)
	var at_war := bool(_region.get("civil_war", false))
	var land: int = LAND_OF.get(String(_region.get("id", "")), Land.PLAIN)

	# Trouble is the one number the whole picture leans on: it darkens the
	# sky, dims the windows and eventually sets the place alight.
	var trouble := clampf(maxf(pressure, insurgency) + (0.25 if at_war else 0.0), 0.0, 1.0)

	draw_rect(Rect2(Vector2.ZERO, size), UiPalette.WINDOW, true)
	_sky(trouble)
	_land(land, trouble)
	_town(land, development, pressure, unemployment, reach, trouble)
	if trouble > 0.45:
		_unrest(trouble, at_war)
	_vignette()


# --- sky ----------------------------------------------------------------

## Clear and cold when the region is calm; brown and low when it is not.
func _sky(trouble: float) -> void:
	var pal := MapPalette.DAY
	var calm_top := pal[MapPalette.SEA]
	var calm_low := pal[MapPalette.SHALLOWS]
	var foul_top: Color = pal[MapPalette.ROCK_DARK]
	var foul_low: Color = pal[MapPalette.GOLD_DARK]
	var top := calm_top.lerp(foul_top, trouble)
	var low := calm_low.lerp(foul_low, trouble)
	var bands := 5
	for b in bands:
		var t := float(b) / float(bands - 1)
		var color := top.lerp(low, t)
		var y0 := int(HORIZON * float(b) / bands)
		var y1 := int(HORIZON * float(b + 1) / bands)
		_blk(0, y0, _cols, y1 - y0, color)
		# Dither the seam between bands.
		for x in range(0, _cols, 2):
			if b + 1 < bands:
				_blk(x + (b % 2), y1 - 1, 1, 1, top.lerp(low, minf(1.0, t + 1.0 / bands)))


# --- land ---------------------------------------------------------------

func _land(land: int, trouble: float) -> void:
	var pal := MapPalette.DAY
	var ground: Color = pal[MapPalette.GRASS]
	var ground_dark: Color = pal[MapPalette.GRASS_DARK]
	match land:
		Land.HIGHLAND, Land.PASS, Land.FOOTHILL:
			ground = pal[MapPalette.HILL]
			ground_dark = pal[MapPalette.HILL_DARK]
		Land.PLAIN, Land.TRADE:
			ground = pal[MapPalette.FARM]
			ground_dark = pal[MapPalette.FARM_DARK]
		Land.INDUSTRY, Land.FRONTIER:
			ground = pal[MapPalette.ROCK]
			ground_dark = pal[MapPalette.ROCK_DARK]

	# Distant landform on the skyline, characteristic of the region.
	match land:
		Land.HIGHLAND, Land.PASS:
			_peaks(3, 16, pal[MapPalette.ROCK], true)
			_peaks(1, 10, pal[MapPalette.ROCK_DARK], land == Land.HIGHLAND)
		Land.FOOTHILL:
			_peaks(2, 8, pal[MapPalette.HILL_DARK], false)
		Land.BASIN, Land.INDUSTRY:
			_peaks(2, 6, pal[MapPalette.ROCK_DARK], false)
		Land.COAST:
			pass   # the sea takes this side instead
		_:
			_peaks(1, 4, pal[MapPalette.HILL_DARK], false)

	# The ground itself.
	for row in range(HORIZON, GRID_Y):
		for col in range(_cols):
			var c := ground_dark if (col + row) % 2 == 0 else ground
			_blk(col, row, 1, 1, c)

	match land:
		Land.COAST:
			# Sea along the foreground, a shoreline the town sits above.
			for row in range(GRID_Y - 12, GRID_Y):
				var depth := float(row - (GRID_Y - 12)) / 12.0
				var water: Color = pal[MapPalette.SHALLOWS].lerp(pal[MapPalette.SEA], depth)
				for col in range(_cols):
					_blk(col, row, 1, 1, water)
				if row == GRID_Y - 12:
					for col in range(0, _cols, 3):
						_blk(col, row, 2, 1, pal[MapPalette.SAND])
		Land.PLAIN, Land.TRADE:
			# Field strips, so grain country looks farmed.
			for strip in range(6):
				var y := HORIZON + 4 + strip * 3
				if y >= GRID_Y:
					break
				var tone: Color = pal[MapPalette.FARM_GREEN] if strip % 2 == 0 else pal[MapPalette.FARM_DARK]
				_blk(0, y, _cols, 2, tone)
		Land.BASIN:
			# The Kesla, crossing in front of the capital.
			var y := GRID_Y - 9
			for col in range(_cols):
				var wob := int(sin(col * 0.18) * 1.5)
				_blk(col, y + wob, 1, 4, pal[MapPalette.RIVER])


## A mountain silhouette. Summits are placed first and the slopes run between
## them, because a per-column random walk averages out into a flat band — it
## reads as a wall, not as peaks.
func _peaks(amplitude: int, lift: int, color: Color, capped: bool) -> void:
	var base := HORIZON - lift
	var summits: Array[int] = []
	var xs: Array[int] = []
	var spacing := maxi(9, _cols / 7)
	var x := -spacing / 2
	while x < _cols + spacing:
		xs.append(x)
		summits.append(base - _rng.randi_range(0, maxi(1, amplitude * 2)))
		x += spacing + _rng.randi_range(-2, 3)

	for i in range(xs.size() - 1):
		var x0 := xs[i]
		var x1 := xs[i + 1]
		var y0 := summits[i]
		var y1 := summits[i + 1]
		var saddle := maxi(y0, y1) + _rng.randi_range(2, 4)
		for col in range(x0, x1):
			if col < 0 or col >= _cols:
				continue
			# Up to the saddle, then down to the next summit: two slopes per
			# span gives a ridgeline instead of a sawtooth.
			var t := float(col - x0) / maxf(1.0, float(x1 - x0))
			var y := int(round(lerpf(float(y0), float(saddle), minf(1.0, t * 2.0)))) if t < 0.5 \
				else int(round(lerpf(float(saddle), float(y1), (t - 0.5) * 2.0)))
			y = mini(y, HORIZON - 1)
			_blk(col, y, 1, HORIZON - y, color)
			if capped and y <= base - amplitude:
				_blk(col, y, 1, 1 + int((base - amplitude - y) * 0.5), MapPalette.DAY[MapPalette.SNOW])


# --- the town -----------------------------------------------------------

## Buildings scale with development and population; their state shows how the
## people in them are doing.
func _town(land: int, development: float, pressure: float, unemployment: float,
		reach: float, trouble: float) -> void:
	var pal := MapPalette.DAY
	var ground_y := GRID_Y - (22 if land == Land.COAST else 16)

	# The street the town stands on: dirt when poor, paved once developed.
	var road: Color = pal[MapPalette.ROAD] if development < 0.55 else pal[MapPalette.ROCK_DARK]
	_blk(0, ground_y + 10, _cols, 2, road)

	# How much town there is. Development builds upward, population outward.
	var population := clampf(float(_region.get("population", 1000.0)) / 3000.0, 0.15, 1.0)
	# Density, not a fixed count: the grid widens with the panel, and a count
	# tuned for a narrow frame leaves a wide one half empty.
	var built := clampf(development * 0.65 + population * 0.35, 0.0, 1.0)
	var count := int(lerpf(5.0, 20.0, built) * (float(_cols) / 140.0))
	var x := 4
	for i in count:
		if x >= _cols - 6:
			break
		var w := _rng.randi_range(4, 7)
		# Taller where the state is present and the place is developed.
		var tall := 3 + int(_rng.randf() * lerpf(2.0, 9.0, development))
		var y := ground_y + 10 - tall
		var wall: Color = pal[MapPalette.WALL] if development > 0.4 else pal[MapPalette.TRUNK]
		_blk(x, y, w, tall, wall)
		_blk(x, y, w, 1, pal[MapPalette.ROOF])
		_windows(x, y, w, tall, unemployment, trouble)
		x += w + _rng.randi_range(1, 3)

	# A civic building with a flag once the state actually reaches here.
	if reach > 0.45:
		var cx := int(_cols * 0.5) - 5
		var ch := 10 + int(reach * 5.0)
		var cy := ground_y + 10 - ch
		_blk(cx, cy, 11, ch, pal[MapPalette.SNOW_SHADE])
		_blk(cx, cy, 11, 1, pal[MapPalette.ROOF])
		_blk(cx + 5, cy - 5, 1, 5, pal[MapPalette.ROCK_DARK])
		var flag: Color = pal[MapPalette.GOLD] if String(_region.get("control", "full")) != "separatist" else pal[MapPalette.CEASEFIRE]
		_blk(cx + 6, cy - 5, 4, 3, flag)
		for wx in range(cx + 1, cx + 10, 3):
			_blk(wx, cy + 3, 2, 3, pal[MapPalette.LIT] if trouble < 0.5 else pal[MapPalette.ROCK_DARK])

	# Industry: chimneys that only exist in a developed industrial region, and
	# only smoke when there is work.
	if land == Land.INDUSTRY or development > 0.7:
		var fx := _cols - 26
		var fh := 14
		var fy := ground_y + 10 - fh
		_blk(fx, fy + 4, 18, fh - 4, pal[MapPalette.ROCK_DARK])
		for stack in 2:
			var sx := fx + 3 + stack * 9
			_blk(sx, fy - 6, 3, 10, pal[MapPalette.WALL])
			if unemployment < 0.18:
				_plume(sx + 1, fy - 7, 5, pal[MapPalette.SNOW_SHADE])

	# Scaffolding where a programme is running — visible construction.
	if _region.get("active_program") != null:
		var sx := 10
		var sy := ground_y - 2
		for row in 6:
			_blk(sx, sy + row * 2, 10, 1, pal[MapPalette.GOLD_DARK])
		_blk(sx, sy, 1, 12, pal[MapPalette.GOLD_DARK])
		_blk(sx + 9, sy, 1, 12, pal[MapPalette.GOLD_DARK])


## Lit, dark or boarded. Unemployment empties windows; trouble puts them out.
func _windows(x: int, y: int, w: int, h: int, unemployment: float, trouble: float) -> void:
	var pal := MapPalette.DAY
	for wy in range(y + 2, y + h - 1, 3):
		for wx in range(x + 1, x + w - 1, 2):
			var roll := _rng.randf()
			var color: Color = pal[MapPalette.LIT]
			if roll < unemployment * 0.9:
				color = pal[MapPalette.TRUNK]        # boarded
			elif roll < unemployment * 0.9 + trouble * 0.5:
				color = pal[MapPalette.ROCK_DARK]    # dark
			_blk(wx, wy, 1, 1, color)


# --- trouble ------------------------------------------------------------

func _unrest(trouble: float, at_war: bool) -> void:
	var pal := MapPalette.DAY
	var ground_y := GRID_Y - 6

	# Barricades across the street.
	var bars := int(lerpf(1.0, 4.0, trouble))
	for i in bars:
		var bx := 16 + i * int(_cols / maxi(1, bars + 1))
		if bx >= _cols - 8:
			break
		_blk(bx, ground_y - 3, 7, 3, pal[MapPalette.TRUNK])
		_blk(bx + 1, ground_y - 5, 5, 2, pal[MapPalette.ROCK_DARK])

	# Fire only once it is genuinely bad, so it keeps its meaning.
	if at_war or trouble > 0.75:
		var fx := int(_cols * 0.32)
		var fy := ground_y - 14
		_blk(fx, fy, 3, 4, pal[MapPalette.CEASEFIRE])
		_blk(fx + 1, fy - 2, 2, 3, pal[MapPalette.GOLD])
		_plume(fx + 1, fy - 4, 7, pal[MapPalette.ROCK_DARK])


## A rising column that narrows and drifts.
func _plume(x: int, y: int, height: int, color: Color) -> void:
	for i in height:
		var drift := int(i * 0.6)
		var w := maxi(1, 3 - i / 3)
		_blk(x + drift, y - i * 2, w, 2, color)


## A dark border so the vignette reads as a framed picture, not a background.
func _vignette() -> void:
	var frame := Rect2(_origin, Vector2(_cols * _cell, GRID_Y * _cell))
	draw_rect(frame, UiPalette.EDGE, false, 1.0)
