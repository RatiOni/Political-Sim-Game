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
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(get_value("display/fullscreen")) \
			else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	_apply_ui_scale()


func _apply_ui_scale() -> void:
	if not is_inside_tree():
		return
	var window := get_tree().root
	window.content_scale_factor = fitting_scale(float(get_value("display/ui_scale")), Vector2(window.size))


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
