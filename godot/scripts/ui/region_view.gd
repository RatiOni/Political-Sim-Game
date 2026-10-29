class_name RegionView
extends Control

## A living pixel view of one region — its land, its town, its weather and
## its mood — in the manner of a 2D city builder rather than a diagram.
##
## THREE THINGS ARE KEPT APART ON PURPOSE:
##
## 1. **Layout** is seeded from the region id. A place keeps the same hills,
##    the same street and the same buildings for the whole campaign. Rolling
##    the layout again on every repaint would flicker instead of telling a
##    story.
## 2. **Condition** comes from the live figures — development, population,
##    unemployment, pressure, state reach, control. Those move slowly, so the
##    same town visibly builds up, lights up, boards up or burns.
## 3. **Motion** is a frame counter. Smoke drifts, lamps and windows flicker,
##    traffic runs, the flag waves, water shimmers, fire gutters.
##
## PERFORMANCE: everything static is baked once into a small `ImageTexture`
## at one image pixel per scene pixel, then blown up with nearest-neighbour
## filtering. Only the moving parts are drawn per frame. Without that, a
## full-scene redraw at this resolution would cost tens of thousands of
## `draw_rect` calls every frame for no visible gain.

const MAX_COLS := 560        # bound on scene width, in scene-pixels
const MIN_W := 220
const HORIZON_F := 0.52      # ground line, as a fraction of scene height
const FPS := 8.0             # pixel art wants a slow, deliberate cadence

enum Land { HIGHLAND, PASS, BASIN, INDUSTRY, FRONTIER, PLAIN, TRADE, FOOTHILL, COAST }

## Terrain character per region, from `content/lore/ardenia_map_bible.md`.
const LAND_OF := {
	"anera": Land.HIGHLAND, "karsen": Land.PASS, "vashtera": Land.BASIN,
	"zavost": Land.INDUSTRY, "darev": Land.FRONTIER, "sela": Land.PLAIN,
	"kelvet": Land.TRADE, "orvena": Land.FOOTHILL, "vetrenka": Land.COAST,
}

enum Build { COTTAGE, TOWNHOUSE, SHOP, BLOCK, WAREHOUSE, CHURCH, BARN }

var _region: Dictionary = {}
var _rng := RandomNumberGenerator.new()

var _scale := 2
var _cols := 320
var _virt_h := 180
var _horizon := 108
var _ground := 120
var _origin := Vector2.ZERO

var _static_tex: ImageTexture
var _baked_key := ""

# Layout, rebuilt only when the region or the size changes.
var _buildings: Array = []
var _chimneys: Array = []       # [{x, y}] smoke sources
var _lamps: Array = []
var _trees: Array = []
var _vehicles: Array = []
var _clouds: Array = []
var _flag_at := Vector2i(-1, -1)
var _fires: Array = []

var _frame := 0
var _clock := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(0, 300)


func show_region(region: Dictionary) -> void:
	_region = region
	queue_redraw()


func _process(delta: float) -> void:
	if _region.is_empty() or not is_visible_in_tree():
		return
	_clock += delta
	var step := int(_clock * FPS)
	if step != _frame:
		_frame = step
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


# --- geometry helpers ---------------------------------------------------

func _rect(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(_origin + Vector2(x, y) * _scale, Vector2(w, h) * _scale)


func _blk(x: float, y: float, w: float, h: float, color: Color) -> void:
	draw_rect(_rect(x, y, w, h), color, true)


static func _fill(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	var r := Rect2i(x, y, w, h).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if r.size.x > 0 and r.size.y > 0:
		img.fill_rect(r, color)


func _land_kind() -> int:
	return LAND_OF.get(String(_region.get("id", "")), Land.PLAIN)


func _f(key: String, fallback: float = 0.0) -> float:
	return clampf(float(_region.get(key, fallback)), 0.0, 1.0)


## How bad things are, in one number: it darkens the sky, empties the
## windows and eventually sets the place alight.
func _trouble() -> float:
	var t := maxf(_f("pressure"), _f("insurgency"))
	if bool(_region.get("civil_war", false)):
		t += 0.25
	return clampf(t, 0.0, 1.0)


# --- draw ---------------------------------------------------------------

func _draw() -> void:
	if _region.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), UiPalette.TRACK, true)
		return

	# Chunky pixels on purpose, and a bounded canvas: at scale 1 the scene
	# was ~1460 cells wide and the bake cost more than the picture is worth.
	# Scale has to satisfy both the height and the width cap, or a wide
	# panel hits MAX_COLS and the scene sits letterboxed inside it.
	_scale = clampi(int(size.y / 150.0), 2, 4)
	_scale = maxi(_scale, int(ceil(size.x / float(MAX_COLS))))
	_virt_h = maxi(80, int(size.y / _scale))
	_cols = clampi(int(size.x / _scale), MIN_W, MAX_COLS)
	_horizon = int(_virt_h * HORIZON_F)
	_ground = int(_virt_h * 0.74)
	var used := Vector2(_cols * _scale, _virt_h * _scale)
	_origin = Vector2(((size.x - used.x) * 0.5), (size.y - used.y) * 0.5).floor()

	var key := "%s|%d|%d|%.2f|%.2f|%.2f|%.2f|%s" % [
		_region.get("id", ""), _cols, _virt_h, _f("development"), _f("state_reach"),
		snappedf(_f("pressure"), 0.05), snappedf(_f("unemployment"), 0.05),
		_region.get("active_program") != null]
	if key != _baked_key or _static_tex == null:
		_baked_key = key
		_build_layout()
		_bake_static()

	if _static_tex != null:
		draw_texture_rect(_static_tex, Rect2(_origin, used), false)

	_draw_motion()


# --- layout (seeded, stable) --------------------------------------------

func _build_layout() -> void:
	_rng.seed = hash(String(_region.get("id", "region")))
	_buildings.clear()
	_chimneys.clear()
	_lamps.clear()
	_trees.clear()
	_vehicles.clear()
	_clouds.clear()
	_fires.clear()
	_flag_at = Vector2i(-1, -1)

	var land := _land_kind()
	var development := _f("development")
	var population := clampf(float(_region.get("population", 1000.0)) / 3000.0, 0.15, 1.0)
	var built := clampf(development * 0.65 + population * 0.35, 0.0, 1.0)

	# Clouds drift, so they are layout not decoration.
	for i in 5:
		_clouds.append({
			"x": _rng.randf() * _cols,
			"y": 10.0 + _rng.randf() * (_horizon * 0.45),
			"w": _rng.randi_range(18, 40),
			"speed": 0.8 + _rng.randf() * 1.2,
		})

	# The town. A street of plots filled left to right; what goes on each
	# plot depends on how developed the place is and what kind of place it is.
	var x := 6
	var civic_done := false
	while x < _cols - 24:
		var kind := _pick_building(land, built, civic_done)
		var w := 0
		match kind:
			Build.COTTAGE: w = _rng.randi_range(14, 20)
			Build.TOWNHOUSE: w = _rng.randi_range(16, 24)
			Build.SHOP: w = _rng.randi_range(18, 26)
			Build.BLOCK: w = _rng.randi_range(24, 34)
			Build.WAREHOUSE: w = _rng.randi_range(30, 44)
			Build.CHURCH: w = _rng.randi_range(22, 28)
			Build.BARN: w = _rng.randi_range(22, 30)
		var storeys := 1
		match kind:
			Build.COTTAGE, Build.BARN: storeys = 1
			Build.SHOP: storeys = 2
			Build.TOWNHOUSE: storeys = 2 + (1 if _rng.randf() < development else 0)
			Build.BLOCK: storeys = 4 + int(_rng.randf() * 3.0 * development)
			Build.WAREHOUSE: storeys = 1
			Build.CHURCH: storeys = 2
		# Jitter the height: without it a street of cottages is one flat
		# fence, which is what a low-development region looked like.
		var h := 10 + storeys * 9 + _rng.randi_range(-3, 5)
		_buildings.append({
			"x": x, "w": w, "h": h, "kind": kind, "storeys": storeys,
			"tint": _rng.randi_range(0, 2),
		})
		if kind in [Build.COTTAGE, Build.TOWNHOUSE] and _rng.randf() < 0.6:
			_chimneys.append({"x": x + w - 5, "y": _ground - h - 6, "kind": "house"})
		# Mostly terraced, occasionally a yard or a gap between clusters, so
		# the town has hamlets rather than one unbroken row.
		x += w + (_rng.randi_range(14, 30) if _rng.randf() < 0.22 else _rng.randi_range(2, 7))

	# One civic building, centred, only where the state actually reaches.
	if _f("state_reach") > 0.4:
		var cw := 34
		var cx := int(_cols * 0.5) - cw / 2
		var ch := 40
		_buildings.append({"x": cx, "w": cw, "h": ch, "kind": -1, "storeys": 2, "tint": 0})
		_flag_at = Vector2i(cx + cw / 2, _ground - ch - 16)

	# Industry: a plant with real chimneys on the right.
	if land == Land.INDUSTRY or development > 0.7:
		var fx := _cols - 70
		_buildings.append({"x": fx, "w": 58, "h": 34, "kind": -2, "storeys": 1, "tint": 0})
		for s in 3:
			_chimneys.append({"x": fx + 8 + s * 18, "y": _ground - 34 - 22, "kind": "stack"})

	_buildings.sort_custom(func(a, b): return int(a["x"]) < int(b["x"]))

	# Street furniture.
	var spacing := 34
	var lx := 12
	while lx < _cols - 8:
		_lamps.append(lx)
		lx += spacing + _rng.randi_range(-6, 6)
	for i in int(_cols / 38):
		_trees.append({"x": _rng.randi_range(4, maxi(5, _cols - 6)), "h": _rng.randi_range(8, 13)})

	# Traffic: more of it where there is work.
	var cars := 1 + int((1.0 - _f("unemployment")) * development * 4.0)
	for i in cars:
		_vehicles.append({
			"x": _rng.randf() * _cols,
			"speed": (10.0 + _rng.randf() * 14.0) * (1.0 if _rng.randf() < 0.5 else -1.0),
			"tone": _rng.randi_range(0, 2),
		})

	# Fires only once it is genuinely bad, so they keep their meaning.
	if _trouble() > 0.72:
		for i in 1 + int(_trouble() * 2.0):
			_fires.append({"x": _rng.randi_range(20, maxi(21, _cols - 20)), "scale": _rng.randf()})


func _pick_building(land: int, built: float, civic_done: bool) -> int:
	var roll := _rng.randf()
	match land:
		Land.INDUSTRY, Land.FRONTIER:
			if roll < 0.3 * built: return Build.BLOCK
			if roll < 0.5: return Build.WAREHOUSE
			if roll < 0.7: return Build.TOWNHOUSE
			return Build.COTTAGE
		Land.PLAIN:
			if roll < 0.3: return Build.BARN
			if roll < 0.45 and built > 0.5: return Build.SHOP
			return Build.COTTAGE
		Land.TRADE:
			if roll < 0.4: return Build.SHOP
			if roll < 0.55: return Build.WAREHOUSE
			return Build.TOWNHOUSE
		Land.BASIN:
			if roll < 0.35 * built: return Build.BLOCK
			if roll < 0.6: return Build.TOWNHOUSE
			if roll < 0.72: return Build.SHOP
			return Build.COTTAGE
		Land.HIGHLAND, Land.PASS, Land.FOOTHILL:
			if roll < 0.12: return Build.CHURCH
			if roll < 0.3 and built > 0.6: return Build.TOWNHOUSE
			return Build.COTTAGE
		_:
			if roll < 0.2: return Build.SHOP
			if roll < 0.5: return Build.TOWNHOUSE
			return Build.COTTAGE


# --- static bake --------------------------------------------------------

func _bake_static() -> void:
	var img := Image.create(_cols, _virt_h, false, Image.FORMAT_RGBA8)
	var pal := MapPalette.DAY
	var trouble := _trouble()
	var land := _land_kind()

	_bake_sky(img, trouble)
	_bake_backdrop(img, land, trouble)
	_bake_ground(img, land)
	_bake_trees(img)
	for b in _buildings:
		_bake_building(img, b, land)
	_bake_street(img, land)
	if _region.get("active_program") != null:
		_bake_scaffold(img)
	if trouble > 0.45:
		_bake_barricades(img, trouble)
	_static_tex = ImageTexture.create_from_image(img)


func _bake_sky(img: Image, trouble: float) -> void:
	var pal := MapPalette.DAY
	# Clear and cold when calm, low and brown when not.
	var top: Color = pal[MapPalette.SEA].lerp(pal[MapPalette.ROCK_DARK], trouble)
	var low: Color = pal[MapPalette.SHALLOWS].lerp(pal[MapPalette.GOLD_DARK], trouble)
	var bands := 7
	for b in bands:
		var t := float(b) / float(bands - 1)
		var c := top.lerp(low, t)
		var y0 := int(_horizon * float(b) / bands)
		var y1 := int(_horizon * float(b + 1) / bands)
		_fill(img, 0, y0, _cols, y1 - y0, c)
		# Dither the seam so the step reads as texture, not as banding.
		if b + 1 < bands:
			var c2 := top.lerp(low, minf(1.0, t + 1.0 / bands))
			for x in range((b % 2) * 2, _cols, 4):
				_fill(img, x, y1 - 1, 1, 1, c2)


## Distant landform, characteristic of the region.
func _bake_backdrop(img: Image, land: int, trouble: float) -> void:
	var pal := MapPalette.DAY
	match land:
		Land.HIGHLAND, Land.PASS:
			_bake_ridge(img, int(_horizon * 0.42), 22, pal[MapPalette.ROCK], true)
			_bake_ridge(img, int(_horizon * 0.26), 16, pal[MapPalette.ROCK_DARK], land == Land.HIGHLAND)
		Land.FOOTHILL:
			_bake_ridge(img, int(_horizon * 0.22), 12, pal[MapPalette.HILL_DARK], false)
		Land.BASIN, Land.INDUSTRY, Land.FRONTIER:
			_bake_ridge(img, int(_horizon * 0.16), 10, pal[MapPalette.ROCK_DARK], false)
		Land.COAST:
			pass
		_:
			_bake_ridge(img, int(_horizon * 0.12), 8, pal[MapPalette.HILL_DARK], false)
	# A treeline along the horizon, so the land does not end in a hard rule.
	var tone: Color = pal[MapPalette.FOREST_DARK]
	for x in range(0, _cols, 3):
		var h := 4 + ((x * 7919) % 5)
		_fill(img, x, _horizon - h, 3, h, tone)


func _bake_ridge(img: Image, rise: int, amplitude: int, color: Color, capped: bool) -> void:
	# Summits first, slopes between them: a per-column random walk averages
	# out into a flat band and reads as a wall rather than as mountains.
	var base := _horizon - rise
	var xs: Array[int] = []
	var ys: Array[int] = []
	var spacing := maxi(26, _cols / 7)
	var x := -spacing / 2
	while x < _cols + spacing:
		xs.append(x)
		ys.append(base - _rng.randi_range(0, amplitude))
		x += spacing + _rng.randi_range(-6, 8)
	for i in range(xs.size() - 1):
		var x0 := xs[i]
		var x1 := xs[i + 1]
		var saddle := maxi(ys[i], ys[i + 1]) + _rng.randi_range(5, 11)
		for col in range(x0, x1):
			if col < 0 or col >= _cols:
				continue
			var t := float(col - x0) / maxf(1.0, float(x1 - x0))
			var y := int(round(lerpf(float(ys[i]), float(saddle), minf(1.0, t * 2.0)))) if t < 0.5 \
				else int(round(lerpf(float(saddle), float(ys[i + 1]), (t - 0.5) * 2.0)))
			y = mini(y, _horizon - 1)
			_fill(img, col, y, 1, _horizon - y, color)
			if capped and y < base - amplitude * 0.55:
				_fill(img, col, y, 1, 2 + int((base - amplitude * 0.55 - y) * 0.4), MapPalette.DAY[MapPalette.SNOW])


func _bake_ground(img: Image, land: int) -> void:
	var pal := MapPalette.DAY
	var a: Color = pal[MapPalette.GRASS]
	var b: Color = pal[MapPalette.GRASS_DARK]
	match land:
		Land.HIGHLAND, Land.PASS, Land.FOOTHILL:
			a = pal[MapPalette.HILL]
			b = pal[MapPalette.HILL_DARK]
		Land.PLAIN, Land.TRADE:
			a = pal[MapPalette.FARM]
			b = pal[MapPalette.FARM_DARK]
		Land.INDUSTRY, Land.FRONTIER:
			a = pal[MapPalette.ROCK]
			b = pal[MapPalette.ROCK_DARK]
	_fill(img, 0, _horizon, _cols, _virt_h - _horizon, b)
		# Texture by sparse tufts, not a per-pixel checkerboard: the checker
	# cost ~50k fills per bake and read as noise at this scale anyway.
	var tufts := int(_cols * (_virt_h - _horizon) / 36)
	for i in tufts:
		var tx := _rng.randi_range(0, maxi(1, _cols - 2))
		var ty := _rng.randi_range(_horizon, _virt_h - 1)
		_fill(img, tx, ty, 2, 1, a)

	if land == Land.PLAIN or land == Land.TRADE:
		for strip in range(5):
			var y := _ground + 6 + strip * 9
			if y < _virt_h:
				_fill(img, 0, y, _cols, 3, pal[MapPalette.FARM_GREEN] if strip % 2 == 0 else pal[MapPalette.FARM_DARK])
	if land == Land.BASIN:
		_fill(img, 0, _virt_h - 16, _cols, 10, pal[MapPalette.RIVER])
	if land == Land.COAST:
		_fill(img, 0, _virt_h - 26, _cols, 26, pal[MapPalette.SEA])
		_fill(img, 0, _virt_h - 28, _cols, 2, pal[MapPalette.SAND])

	# The street. A dirt track when the place is poor, a kerbed and marked
	# road once it is not — the surface is one of the clearest tells of how
	# much has been spent here.
	var paved := _f("development") >= 0.55
	var road: Color = pal[MapPalette.ROCK_DARK] if paved else pal[MapPalette.ROAD]
	var verge := int(_virt_h * 0.055)
	_fill(img, 0, _ground, _cols, verge, pal[MapPalette.ROCK] if paved else pal[MapPalette.SAND_DARK])
	_fill(img, 0, _ground + verge, _cols, int(_virt_h * 0.12), road)
	if not paved:
		var rut := _ground + verge + int(_virt_h * 0.04)
		for rx in range(0, _cols, 7):
			_fill(img, rx, rut, 5, 1, pal[MapPalette.SAND_DARK])
			_fill(img, rx + 2, rut + int(_virt_h * 0.045), 5, 1, pal[MapPalette.SAND_DARK])
	if paved:
		_fill(img, 0, _ground + verge, _cols, 1, pal[MapPalette.SNOW_SHADE])
		_fill(img, 0, _ground + verge + int(_virt_h * 0.12) - 1, _cols, 1, pal[MapPalette.ROCK])
		var mid := _ground + verge + int(_virt_h * 0.06)
		for dx in range(4, _cols, 16):
			_fill(img, dx, mid, 7, 1, pal[MapPalette.GOLD_DARK])


func _bake_building(img: Image, b: Dictionary, land: int) -> void:
	var pal := MapPalette.DAY
	var x := int(b["x"])
	var w := int(b["w"])
	var h := int(b["h"])
	var kind := int(b["kind"])
	var top := _ground - h
	var development := _f("development")

	if kind == -1:
		_bake_civic(img, x, w, h)
		return
	if kind == -2:
		_bake_plant(img, x, w, h)
		return

	var walls: Array = [pal[MapPalette.WALL], pal[MapPalette.SNOW_SHADE], pal[MapPalette.SAND]]
	var wall: Color = walls[int(b["tint"])]
	if development < 0.35:
		wall = pal[MapPalette.SAND_DARK]   # daub and plaster, still legible
	_fill(img, x, top, w, h, wall)
	# A shaded side, so the block has mass.
	_fill(img, x + w - 2, top, 2, h, wall.darkened(0.3))

	match kind:
		Build.COTTAGE, Build.BARN:
			# Pitched roof.
			for i in int(w / 2):
				_fill(img, x + i, top - int(w / 2) + i, 1, int(w / 2) - i, pal[MapPalette.ROOF])
				_fill(img, x + w - 1 - i, top - int(w / 2) + i, 1, int(w / 2) - i, pal[MapPalette.ROOF])
			if kind == Build.BARN:
				_fill(img, x + int(w * 0.35), top + 4, int(w * 0.3), h - 4, pal[MapPalette.TRUNK])
		Build.CHURCH:
			var sx := x + int(w * 0.5) - 3
			_fill(img, sx, top - 24, 6, 24, wall)
			for i in 4:
				_fill(img, sx + i, top - 30 + i, 6 - i * 2, 6, pal[MapPalette.ROOF])
			_fill(img, sx + 2, top - 36, 2, 7, pal[MapPalette.GOLD])
			_fill(img, sx, top - 34, 6, 2, pal[MapPalette.GOLD])
		Build.SHOP:
			_fill(img, x, top, w, 4, pal[MapPalette.ROOF])
			# Awning and a sign board above the shopfront.
			var ay := _ground - 14
			for i in range(0, w, 4):
				_fill(img, x + i, ay, 2, 3, pal[MapPalette.CEASEFIRE])
				_fill(img, x + i + 2, ay, 2, 3, pal[MapPalette.SNOW])
			_fill(img, x + 3, top + 6, w - 6, 4, pal[MapPalette.GOLD_DARK])
		_:
			_fill(img, x, top, w, 4, pal[MapPalette.ROOF])

	# Door at street level.
	var dx := x + int(w * 0.5) - 2
	_fill(img, dx, _ground - 9, 5, 9, pal[MapPalette.TRUNK])

	# Windows: a grid per storey. State is baked (lit / dark / boarded);
	# the flicker on top of it is drawn per frame.
	var unemployment := _f("unemployment")
	var trouble := _trouble()
	var storeys := int(b["storeys"])
	for s in storeys:
		var wy := _ground - 11 - s * 9 - 7
		if wy < top + 5:
			break
		for wx in range(x + 3, x + w - 5, 6):
			var roll := _rng.randf()
			var c: Color = pal[MapPalette.LIT]
			if roll < unemployment * 0.9:
				c = pal[MapPalette.TRUNK]            # boarded
			elif roll < unemployment * 0.9 + trouble * 0.45:
				c = pal[MapPalette.ROCK_DARK]        # dark
			_fill(img, wx, wy, 3, 4, c)


func _bake_civic(img: Image, x: int, w: int, h: int) -> void:
	var pal := MapPalette.DAY
	var top := _ground - h
	_fill(img, x, top, w, h, pal[MapPalette.SNOW_SHADE])
	_fill(img, x - 2, top, w + 4, 5, pal[MapPalette.SNOW])
	# A pediment and columns: the state should look like the state.
	for i in int(w / 2):
		_fill(img, x + int(w / 2) - i, top - 8 + int(i * 0.5), 1, 8, pal[MapPalette.SNOW])
		_fill(img, x + int(w / 2) + i, top - 8 + int(i * 0.5), 1, 8, pal[MapPalette.SNOW])
	for c in range(x + 4, x + w - 4, 7):
		_fill(img, c, top + 8, 3, h - 16, pal[MapPalette.SNOW])
	_fill(img, x, _ground - 8, w, 8, pal[MapPalette.ROCK_DARK])
	_fill(img, x + int(w / 2) - 3, _ground - 12, 7, 12, pal[MapPalette.TRUNK])
	# Flagpole; the flag itself waves, so it is drawn per frame.
	_fill(img, x + int(w / 2), top - 24, 1, 18, pal[MapPalette.ROCK_DARK])


func _bake_plant(img: Image, x: int, w: int, h: int) -> void:
	var pal := MapPalette.DAY
	var top := _ground - h
	_fill(img, x, top, w, h, pal[MapPalette.ROCK_DARK])
	# Saw-tooth roof — the reason a factory reads as a factory.
	for i in range(0, w, 10):
		for j in 6:
			_fill(img, x + i + j, top - 6 + j, 1, 6 - j, pal[MapPalette.WALL])
	for s in 3:
		var sx := x + 8 + s * 18
		_fill(img, sx, top - 22, 5, 24, pal[MapPalette.WALL])
		_fill(img, sx - 1, top - 23, 7, 2, pal[MapPalette.ROCK])
	# A lit shop floor when the works are running.
	var running := _f("unemployment") < 0.18
	for wx in range(x + 4, x + w - 6, 8):
		_fill(img, wx, top + 12, 5, 6, pal[MapPalette.LIT] if running else pal[MapPalette.ROCK])


## Trees sit behind the frontage. Drawn after the buildings they swallowed
## them, which is what made the poorer towns unreadable.
func _bake_trees(img: Image) -> void:
	var pal := MapPalette.DAY
	for t in _trees:
		var tx := int(t["x"])
		var th := int(t["h"])
		_fill(img, tx, _ground - th, 2, th, pal[MapPalette.TRUNK])
		_fill(img, tx - 4, _ground - th - 2, 10, 7, pal[MapPalette.FOREST])
		_fill(img, tx - 3, _ground - th - 6, 8, 5, pal[MapPalette.FOREST_DARK])


func _bake_street(img: Image, land: int) -> void:
	var pal := MapPalette.DAY
	for lx in _lamps:
		_fill(img, lx, _ground - 20, 1, 20, pal[MapPalette.ROCK_DARK])
		_fill(img, lx - 2, _ground - 22, 5, 2, pal[MapPalette.ROCK_DARK])
	# Telegraph poles with a wire, receding along the street.
	for px in range(18, _cols, 70):
		_fill(img, px, _ground - 26, 2, 26, pal[MapPalette.TRUNK])
		_fill(img, px - 4, _ground - 26, 10, 1, pal[MapPalette.TRUNK])
		if px + 70 < _cols:
			_fill(img, px, _ground - 24, 70, 1, pal[MapPalette.ROCK_DARK])


func _bake_scaffold(img: Image) -> void:
	var pal := MapPalette.DAY
	var x := 14
	var h := 48
	var top := _ground - h
	for row in 6:
		_fill(img, x, top + row * 8, 22, 1, pal[MapPalette.GOLD_DARK])
	_fill(img, x, top, 1, h, pal[MapPalette.GOLD_DARK])
	_fill(img, x + 21, top, 1, h, pal[MapPalette.GOLD_DARK])
	# Crane mast; the jib swings, so it is drawn per frame.
	_fill(img, x + 10, top - 26, 2, 26, pal[MapPalette.GOLD_DARK])


func _bake_barricades(img: Image, trouble: float) -> void:
	var pal := MapPalette.DAY
	var bars := int(lerpf(1.0, 4.0, trouble))
	for i in bars:
		var bx := 30 + i * int(_cols / maxi(1, bars + 1))
		if bx >= _cols - 14:
			break
		_fill(img, bx, _ground - 7, 16, 7, pal[MapPalette.TRUNK])
		_fill(img, bx + 2, _ground - 11, 12, 4, pal[MapPalette.ROCK_DARK])
		_fill(img, bx + 5, _ground - 14, 3, 3, pal[MapPalette.CEASEFIRE])


# --- motion -------------------------------------------------------------

func _draw_motion() -> void:
	var pal := MapPalette.DAY
	var t := _frame
	var trouble := _trouble()

	# Clouds drift and wrap.
	for c in _clouds:
		var cx := fposmod(float(c["x"]) + t * float(c["speed"]) * 0.25, float(_cols + 60)) - 30.0
		var w := int(c["w"])
		var y := float(c["y"])
		var tone: Color = pal[MapPalette.SNOW_SHADE] if trouble < 0.5 else pal[MapPalette.ROCK]
		_blk(cx, y, w, 3, tone)
		_blk(cx + 4, y - 3, w - 10, 3, tone)

	# Chimney and stack smoke: puffs rise, widen and drift.
	var running := _f("unemployment") < 0.18
	for c in _chimneys:
		var is_stack := String(c["kind"]) == "stack"
		if is_stack and not running:
			continue
		if not is_stack and _f("development") < 0.2:
			continue
		# Small puffs that grow and fade out as they climb. Opaque blocks
		# that only grow read as white slabs, not as smoke.
		var puffs := 8 if is_stack else 5
		var reach := 26.0 if is_stack else 13.0
		for i in puffs:
			var phase := (t + i * 2) % (puffs * 2)
			var k := float(phase) / float(puffs * 2)
			var rise := k * reach
			var w := 2.0 + k * 3.0
			var tone: Color = pal[MapPalette.SNOW_SHADE] if is_stack else pal[MapPalette.ROCK]
			tone.a = (1.0 - k) * (0.8 if is_stack else 0.55)
			_blk(float(c["x"]) + rise * 0.45, float(c["y"]) - rise, w, w, tone)

	# Traffic along the street.
	for v in _vehicles:
		var vx := fposmod(float(v["x"]) + t * float(v["speed"]) * 0.12, float(_cols + 24)) - 12.0
		var tones: Array = [pal[MapPalette.CEASEFIRE], pal[MapPalette.RIVER], pal[MapPalette.SNOW_SHADE]]
		var body: Color = tones[int(v["tone"])]
		var y := _ground + int(_virt_h * 0.085)
		_blk(vx, y, 9, 4, body)
		_blk(vx + 2, y - 3, 5, 3, body.lightened(0.2))
		_blk(vx + 1, y + 4, 2, 1, pal[MapPalette.INK])
		_blk(vx + 6, y + 4, 2, 1, pal[MapPalette.INK])

	# Lamps come on at dusk — here, when the mood is dark.
	if trouble > 0.35 or _f("development") > 0.6:
		for i in _lamps.size():
			var flicker := (t + i * 5) % 23 != 0     # an occasional blink
			if flicker:
				_blk(_lamps[i] - 1, _ground - 23, 3, 2, pal[MapPalette.LIT])

	# A few windows flicker, so the town looks inhabited rather than printed.
	for b in _buildings:
		if int(b["kind"]) < 0:
			continue
		var seed_x := int(b["x"])
		if (t + seed_x) % 7 != 0:
			continue
		var wy := _ground - 18
		_blk(seed_x + 3 + ((seed_x + t) % maxi(1, int(b["w"]) - 8)), wy, 3, 4, pal[MapPalette.ROCK_DARK])

	# The flag waves.
	if _flag_at.x >= 0:
		var wave: int = [0, 1, 2, 1][t % 4]
		var flag: Color = pal[MapPalette.GOLD] if String(_region.get("control", "full")) != "separatist" else pal[MapPalette.CEASEFIRE]
		_blk(_flag_at.x + 1, _flag_at.y + wave * 0.5, 12, 7, flag)
		_blk(_flag_at.x + 1, _flag_at.y + 7 + wave * 0.5, 12 - wave * 2, 1, flag.darkened(0.3))

	# The crane jib swings over the site.
	if _region.get("active_program") != null:
		var swing: int = [0, 2, 4, 2][t % 4]
		_blk(24, _ground - 48 - 26 + swing, 26, 2, pal[MapPalette.GOLD])
		_blk(44 + swing, _ground - 48 - 24 + swing, 1, 10, pal[MapPalette.GOLD_DARK])
		_blk(42 + swing, _ground - 48 - 14 + swing, 5, 4, pal[MapPalette.TRUNK])

	# Water shimmer.
	if _land_kind() == Land.COAST:
		for row in 5:
			var y := _virt_h - 24 + row * 4
			for x in range((t * 2 + row * 7) % 14, _cols, 14):
				_blk(x, y, 4, 1, pal[MapPalette.SHALLOWS])

	# Fire guttering.
	for f in _fires:
		var fx := int(f["x"])
		var tall := 5 + ((t + int(float(f["scale"]) * 7.0)) % 4)
		_blk(fx, _ground - tall, 4, tall, pal[MapPalette.CEASEFIRE])
		_blk(fx + 1, _ground - tall - 3, 2, 3, pal[MapPalette.GOLD])
		for i in 5:
			var phase := (t + i * 2) % 12
			_blk(fx + 1 + phase * 0.5, _ground - tall - 4 - phase * 2.0, 3, 2, pal[MapPalette.ROCK_DARK])

	# Birds, occasionally, when things are calm.
	if trouble < 0.4:
		var bt := t % 90
		if bt < 30:
			for i in 3:
				var bx := bt * 3.0 + i * 7.0
				var by := 24.0 + sin((bt + i * 3) * 0.4) * 3.0 + i * 4.0
				var flap := (t + i) % 2
				_blk(bx, by, 1, 1, UiPalette.TEXT_DIM)
				_blk(bx + 1, by - flap, 1, 1, UiPalette.TEXT_DIM)
				_blk(bx + 2, by, 1, 1, UiPalette.TEXT_DIM)

	draw_rect(Rect2(_origin, Vector2(_cols, _virt_h) * _scale), UiPalette.EDGE, false, 1.0)
