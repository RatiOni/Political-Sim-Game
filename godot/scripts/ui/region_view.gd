class_name RegionView
extends Control

## A living view of one region by day or night (`DayCycle`) — its land, its town, its people
## and its mood — in the manner of a 2D city builder rather than a diagram.
##
## THREE THINGS ARE KEPT APART ON PURPOSE (see `RegionScene`):
## 1. **Layout** is seeded from the region id, so a place keeps the same
##    ridges, street and buildings for the whole campaign.
## 2. **Condition** comes from the live figures, so the same town visibly
##    builds up, lights up, boards up or burns.
## 3. **Motion** runs on continuous time every frame (`RegionLife`), so smoke
##    curls, traffic glides and fire flickers smoothly.
##
## PERFORMANCE: the still picture is baked once per change of condition into
## one texture at one image pixel per scene pixel (`RegionBake`), then scaled
## up nearest-neighbour. Only moving things are drawn per frame.

const MAX_COLS := 1000   # bound on scene width, in scene pixels
## Landmarks and towers are authored in scene pixels; below this many rows
## they no longer fit under the frame, so the scale gives way to keep it.
const MIN_ROWS := 200
const MIN_W := 240
const SOLID_FROM := 0.07
const SEAM := 0.8
const TONE_WEIGHT := 3.0

var _region: Dictionary = {}
var _scene: RegionScene
var _life := RegionLife.new()
var _static_tex: ImageTexture
var _baked_key := ""
var _scale := 2
var _origin := Vector2.ZERO
var _clock := 0.0
var _ascii: AsciiConvert
var _grade: ColorRect


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(0, 300)


func _ready() -> void:
	clip_contents = true
	# What reaches the screen is the ASCII conversion of the picture below.
	# Day grade first (over the finished frame), then the ASCII conversion.
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	_grade = ColorRect.new()
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grade.material = ShaderMaterial.new()
	(_grade.material as ShaderMaterial).shader = preload("res://shaders/day_grade.gdshader")
	add_child(_grade)
	_ascii = AsciiConvert.cover(self)
	# Print for legibility: the dim middle of the picture becomes flat tiles
	# instead of a screen of dots, and the dark gutter outlines a change of
	# colour rather than meshing every surface.
	_ascii.set_shape(SOLID_FROM, SEAM, TONE_WEIGHT, true)


func show_region(region: Dictionary) -> void:
	_region = region
	queue_redraw()


func _process(delta: float) -> void:
	if _region.is_empty() or not is_visible_in_tree():
		return
	_clock += delta
	var m := _grade.material as ShaderMaterial
	m.set_shader_parameter("daylight", DayCycle.daylight())

	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if _region.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), UiPalette.TRACK, true)
		return
	# Two screen pixels per scene pixel: fine enough for windows, people and
	# lettering, coarse enough to stay pixel art. A very wide panel scales up
	# rather than baking past MAX_COLS.
	_scale = maxi(1, mini(maxi(2, int(ceil(size.x / float(MAX_COLS)))), int(size.y / MIN_ROWS)))
	var cols := clampi(int(size.x / _scale), MIN_W, MAX_COLS)
	var rows := maxi(MIN_ROWS, int(size.y / _scale))
	var used := Vector2(cols, rows) * _scale
	_origin = ((size - used) * 0.5).floor()

	var key := "%s|%d|%d|%.2f|%.2f|%.2f|%.2f|%.2f|%s|%s|%.2f" % [
		_region.get("id", ""), cols, rows, snappedf(RegionScene.f(_region, "development"), 0.02),
		snappedf(RegionScene.f(_region, "state_reach"), 0.05), snappedf(RegionScene.f(_region, "pressure"), 0.05),
		snappedf(RegionScene.f(_region, "unemployment"), 0.02), snappedf(RegionScene.f(_region, "insurgency"), 0.05),
		str(_region.get("active_program", {}).get("program_id", "") if _region.get("active_program") is Dictionary else ""), _region.get("control", "full"),
		snappedf(float(_region.get("population_share", 0.0)), 0.005)]
	if key != _baked_key or _static_tex == null:
		_baked_key = key
		var before := _scene
		_scene = RegionScene.new()
		_scene.setup(_region, cols, rows)
		_static_tex = ImageTexture.create_from_image(RegionBake.bake(_scene))
		var m := _grade.material as ShaderMaterial
		m.set_shader_parameter("sky_mask", ImageTexture.create_from_image(_scene.sky_mask))
		m.set_shader_parameter("horizon_v", float(_scene.horizon) / _scene.h)
		m.set_shader_parameter("water_v", float(_scene.water_top) / _scene.h if _scene.water_top >= 0 else 2.0)
		m.set_shader_parameter("scene_rect", Vector4(_origin.x / size.x, _origin.y / size.y, used.x / size.x, used.y / size.y))
		_frame_scene(before, used)

	# The camera holds still. A push-in at a fractional scale doubled odd
	# scene pixels and a drift slid every edge across the converter's cells,
	# so the whole picture crawled; the life in the street is the motion.
	var camera := Transform2D.IDENTITY
	draw_set_transform_matrix(camera)
	draw_texture_rect(_static_tex, Rect2(_origin, used), false)
	_life.canvas = self
	_life.origin = _origin
	_life.px = _scale
	_life.base = camera
	_life.night = 1.0 - DayCycle.daylight()
	_life.draw(_scene, _clock)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Per-scene palette and water rows, and the big-moment burst when the same
## place changes for the worse in a way you should not miss: fire breaks out,
## or the state loses control of it.
func _frame_scene(before: RegionScene, used: Vector2) -> void:
	if _ascii == null:
		return
	var palette := "night"
	if _scene.trouble > 0.6:
		palette = "fire"
	elif _scene.water_top >= 0:
		palette = "sea"
	_ascii.set_palette(palette)
	var water := 2.0
	if _scene.water_top >= 0:
		water = (_origin.y + _scene.water_top * _scale) / maxf(1.0, size.y)
	_ascii.set_water_from(water)
	if before == null or before.id != _scene.id:
		return
	var lost := String(before.region.get("control", "full")) != String(_scene.region.get("control", "full"))
	if (_scene.fires.size() > 0 and before.fires.is_empty()) or lost:
		var at := Vector2(0.5, 0.6)
		if not _scene.fires.is_empty():
			at = (_origin + Vector2(float(_scene.fires[0]["x"]), _scene.ground) * _scale) / size
		_ascii.burst(at)
