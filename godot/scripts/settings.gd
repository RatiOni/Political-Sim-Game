extends Node

## The player's preferences: display, the music and effects levels below the
## master, and autosave. One file between sessions, applied at start. Master
## volume and mute stay with `Ambience`, which already owns them. Campaign
## state never lives here, and preferences never live in a save.

signal changed(key: String)

const PATH := "user://settings.cfg"
const UI_SCALES: Array[float] = [1.0, 1.15, 1.3]
## The smallest layout the dashboard is built for; a scale that would leave
## less than this is not used.
const MIN_LAYOUT := Vector2(1280, 720)
const DEFAULTS := {
	"display/fullscreen": false,
	"display/ui_scale": 1.0,
	"audio/music": 0.8,
	"audio/effects": 0.8,
	"gameplay/autosave": true,
}

var path := PATH
var _values := {}
var _applied_scale := 1.0


func _ready() -> void:
	load_from_disk()
	apply_all()
	get_tree().root.size_changed.connect(_apply_ui_scale)


func load_from_disk() -> void:
	_values = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	for key: String in DEFAULTS:
		var parts := key.split("/")
		var stored: Variant = config.get_value(parts[0], parts[1], DEFAULTS[key])
		if DEFAULTS[key] is float and (stored is float or stored is int):
			_values[key] = float(stored)
		elif typeof(stored) == typeof(DEFAULTS[key]):
			_values[key] = stored


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_error("Unknown setting '%s'" % key)
		return
	_values[key] = value
	var config := ConfigFile.new()
	for stored_key: String in _values:
		var parts := stored_key.split("/")
		config.set_value(parts[0], parts[1], _values[stored_key])
	config.save(path)
	apply_all()
	changed.emit(key)


func apply_all() -> void:
	_set_bus_volume(&"Music", float(get_value("audio/music")))
	_set_bus_volume(&"Effects", float(get_value("audio/effects")))
	if DisplayServer.get_name() != "headless":
		var mode := window_mode_change(DisplayServer.window_get_mode())
		if mode != -1:
			DisplayServer.window_set_mode(mode)
	_apply_ui_scale()


## What apply_all does to a window currently in `current`: -1 leaves it alone.
func window_mode_change(current: int) -> int:
	return next_window_mode(current, bool(get_value("display/fullscreen")))


## Only crosses the fullscreen boundary, so a maximized window stays maximized.
## -1 means leave the window alone.
static func next_window_mode(current: int, want_fullscreen: bool) -> int:
	var fs := current == DisplayServer.WINDOW_MODE_FULLSCREEN or current == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if want_fullscreen and not fs:
		return DisplayServer.WINDOW_MODE_FULLSCREEN
	if not want_fullscreen and fs:
		return DisplayServer.WINDOW_MODE_WINDOWED
	return -1


func _apply_ui_scale() -> void:
	if not is_inside_tree():
		return
	var window := get_tree().root
	var scale := fitting_scale(float(get_value("display/ui_scale")), Vector2(window.size))
	# Only write what changed from what we last applied, so another owner of
	# the factor is never overwritten by a preference left at 100%.
	if not is_equal_approx(scale, _applied_scale):
		_applied_scale = scale
		window.content_scale_factor = scale


## The largest scale, up to the one chosen, that still leaves the dashboard
## its minimum layout.
static func fitting_scale(chosen: float, window_size: Vector2) -> float:
	var best := 1.0
	for scale in UI_SCALES:
		if scale <= chosen + 0.001 and window_size.x / scale >= MIN_LAYOUT.x \
				and window_size.y / scale >= MIN_LAYOUT.y:
			best = maxf(best, scale)
	return best


static func _set_bus_volume(bus: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(AudioBuses.ensure(bus))
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(index, linear <= 0.0)
