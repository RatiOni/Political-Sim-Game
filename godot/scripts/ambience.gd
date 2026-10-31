extends Node

## Music and place. One industrial drone plays under the whole game; over it
## each scene keeps its own looping bed — a ministry's room tone, the chamber's
## murmur, a street sized to its town, a harbour's water — crossfaded as the
## player moves, with a crowd rising over a street in trouble.
##
## Like `UiSfx`, everything is synthesised here; there are no audio assets.
## Every loop is rendered once on a worker thread at start-up and cached.
## Loops are seamless by construction: tones are fitted to whole cycles of the
## loop, noise is filtered twice round it, and one-off sounds wrap their tails
## back to the start.

const MIX_RATE := 22050
const MUSIC_SECONDS := 24.0
const BED_SECONDS := 12.0
const MUSIC_DB := -22.0
const BED_DB := -9.0
const CROWD_DB := -10.0
const SILENT_DB := -60.0
const FADE_SECONDS := 2.5
const TARGET_RMS := 0.16

const SCENES := [
	"desk", "treasury", "parliament", "foreign", "situation", "records", "opposition",
	"town", "city", "metropolis", "town_harbour", "city_harbour", "metropolis_harbour",
]

var _music: AudioStreamPlayer
var _crowd: AudioStreamPlayer
var _beds: Array[AudioStreamPlayer] = []
var _active := 0
var _scene := ""
var _crowd_level := 0.0
var _cache := {}
var _rendering := {}
var _tweens := {}

## The player's master volume (0..1) and mute, applied to the Master bus so the
## UI sounds follow too, and kept in `SETTINGS_PATH` between sessions.
const SETTINGS_PATH := "user://audio.cfg"
signal settings_changed
var volume := 0.8
var muted := false


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		volume = clampf(float(config.get_value("audio", "volume", volume)), 0.0, 1.0)
		muted = bool(config.get_value("audio", "muted", muted))
	_apply_settings()
	if DisplayServer.get_name() == "headless":
		return
	_music = _player()
	_crowd = _player()
	for _index in range(2):
		_beds.append(_player())
	for id in ["music", "crowd"] + SCENES:
		_request(id)


func _player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = &"Master"
	player.volume_db = SILENT_DB
	add_child(player)
	return player


## The scene on screen: "menu" (music alone), "desk" (the minister's office),
## a desk room (`SCENES`) or a street from `scene_for_region`. `unrest` (0..1)
## raises a crowd over the bed.
func set_scene(scene: String, unrest: float = 0.0) -> void:
	if _beds.is_empty():
		return
	_set_crowd(unrest)
	if scene == _scene:
		return
	_scene = scene
	_request(scene)


func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	_save_settings()


func set_muted(value: bool) -> void:
	muted = value
	_save_settings()


func _save_settings() -> void:
	_apply_settings()
	var config := ConfigFile.new()
	config.set_value("audio", "volume", volume)
	config.set_value("audio", "muted", muted)
	config.save(SETTINGS_PATH)
	settings_changed.emit()


func _apply_settings() -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(bus, muted or volume <= 0.0)


## A street sized to its region: population is `RegionCity.data_from`'s.
static func scene_for_region(population: float, harbour: bool) -> String:
	var size := "metropolis" if population >= 0.9 else ("city" if population >= 0.45 else "town")
	return size + ("_harbour" if harbour else "")


func _set_crowd(unrest: float) -> void:
	var level := clampf((unrest - 0.35) / 0.4, 0.0, 1.0)
	if is_equal_approx(level, _crowd_level):
		return
	_crowd_level = level
	if _crowd.stream != null:
		_fade(_crowd, _crowd_db())


func _crowd_db() -> float:
	return CROWD_DB + linear_to_db(_crowd_level) if _crowd_level > 0.01 else SILENT_DB


func _request(id: String) -> void:
	if _cache.has(id):
		_on_rendered(id)
		return
	if not (id == "music" or id == "crowd" or id in SCENES):
		_crossfade(null)
		return
	if _rendering.has(id):
		return
	_rendering[id] = true
	WorkerThreadPool.add_task(func() -> void:
		call_deferred("_store", id, to_stream(render(id))))


func _store(id: String, stream: AudioStreamWAV) -> void:
	_cache[id] = stream
	_rendering.erase(id)
	if id == "music" or id == "crowd" or id == _scene:
		_on_rendered(id)


func _on_rendered(id: String) -> void:
	var stream: AudioStreamWAV = _cache[id]
	if id == "music":
		_music.stream = stream
		_music.play()
		_fade(_music, MUSIC_DB)
	elif id == "crowd":
		_crowd.stream = stream
		_crowd.play()
		_fade(_crowd, _crowd_db())
	elif id == _scene and _beds[_active].stream != stream:
		_crossfade(stream)


func _crossfade(stream: AudioStreamWAV) -> void:
	var old := _beds[_active]
	if old.playing:
		_fade(old, SILENT_DB, true)
	if stream == null:
		return
	_active = 1 - _active
	var next := _beds[_active]
	next.stream = stream
	next.volume_db = SILENT_DB
	# Start anywhere in the loop so returning to a room never replays its opening.
	next.play(randf() * stream.get_length())
	_fade(next, BED_DB)


func _fade(player: AudioStreamPlayer, db: float, stop_after: bool = false) -> void:
	var running: Tween = _tweens.get(player)
	if running != null and running.is_valid():
		running.kill()
	var tween := create_tween()
	tween.tween_property(player, "volume_db", db, FADE_SECONDS)
	if stop_after:
		tween.tween_callback(player.stop)
	_tweens[player] = tween


# --- rendering ----------------------------------------------------------

## One seamless loop as raw samples; empty for an unknown id.
static func render(id: String) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var b := PackedFloat32Array()
	b.resize(int((MUSIC_SECONDS if id == "music" else BED_SECONDS) * MIX_RATE))
	match id.trim_suffix("_harbour"):
		"music": b = _music_loop(b, rng)
		"crowd": b = _crowd_loop(b, rng)
		"desk":
			b = _noise(b, rng, 1.0, 40.0, 400.0)
			b = _hum(b, 50.0, 0.25, 4)
			b = _clock(b, 0.5)
			b = _scatter(b, rng, 2, 0.6, _typing)
			b = _scatter(b, rng, 1, 0.35, _phone)
		"treasury":
			b = _noise(b, rng, 1.0, 40.0, 450.0)
			b = _hum(b, 50.0, 0.2, 4)
			b = _scatter(b, rng, 4, 0.8, _typing)
			b = _scatter(b, rng, 1, 0.5, _phone)
			b = _murmur(b, rng, 2, 0.35)
		"parliament":
			b = _noise(b, rng, 0.6, 60.0, 500.0)
			b = _murmur(b, rng, 10, 1.6)
			b = _scatter(b, rng, 1, 1.2, _gavel)
			b = _scatter(b, rng, 3, 0.5, _cough)
		"foreign":
			b = _noise(b, rng, 0.8, 40.0, 400.0)
			b = _hum(b, 50.0, 0.3, 4)
			b = _scatter(b, rng, 3, 0.7, _teletype)
			b = _static(b, rng, 0.25)
			b = _scatter(b, rng, 1, 0.3, _beeps)
		"situation":
			b = _noise(b, rng, 1.0, 100.0, 1500.0)
			b = _hum(b, 50.0, 0.4, 5)
			b = _scatter(b, rng, 3, 0.9, _radio)
			b = _static(b, rng, 0.4)
			b = _scatter(b, rng, 2, 0.4, _beeps)
		"records":
			b = _noise(b, rng, 0.6, 30.0, 250.0)
			b = _clock(b, 0.9)
			b = _scatter(b, rng, 3, 0.5, _rustle)
			b = _scatter(b, rng, 1, 0.6, _drawer)
		"opposition":
			b = _noise(b, rng, 0.5, 40.0, 300.0)
			b = _rain(b, rng, 1.2)
			b = _clock(b, 0.6)
			b = _murmur(b, rng, 3, 0.5)
			b = _scatter(b, rng, 1, 0.5, _typing)
		"town":
			b = _noise(b, rng, 1.0, 150.0, 700.0, 2, 0.7)
			b = _scatter(b, rng, 6, 0.5, _bird)
			b = _scatter(b, rng, 1, 0.5, _church_bell)
			b = _scatter(b, rng, 1, 0.4, _car)
			b = _murmur(b, rng, 2, 0.2)
		"city":
			b = _noise(b, rng, 1.0, 30.0, 250.0, 1, 0.3)
			b = _scatter(b, rng, 3, 0.8, _car)
			b = _scatter(b, rng, 1, 0.4, _horn)
			b = _murmur(b, rng, 5, 0.6)
			b = _scatter(b, rng, 2, 0.2, _bird)
		"metropolis":
			b = _noise(b, rng, 1.3, 30.0, 250.0, 1, 0.3)
			b = _hum(b, 100.0, 0.2, 3)
			b = _scatter(b, rng, 6, 0.8, _car)
			b = _scatter(b, rng, 3, 0.5, _horn)
			b = _scatter(b, rng, 1, 0.5, _tram_bell)
			b = _murmur(b, rng, 10, 0.8)
		_:
			return PackedFloat32Array()
	if id.ends_with("_harbour"):
		b = _noise(b, rng, 1.2, 80.0, 900.0, 3, 0.9)
		b = _noise(b, rng, 0.4, 2000.0, 6000.0, 3, 0.9)
		b = _scatter(b, rng, 3, 0.5, _gull)
		b = _scatter(b, rng, 1, 0.5, _ship_horn)
	return b


## Low saws breathing between a dark and an open filter, a sub, distant
## machinery, a factory pulse, and struck sheet metal ringing out.
static func _music_loop(b: PackedFloat32Array, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := b.size()
	var saws := PackedFloat32Array()
	saws.resize(n)
	for hz in [55.0, 55.22, 82.5, 110.3]:
		var f := _fit(hz, n)
		var start := rng.randf()
		for i in n:
			saws[i] += 2.0 * fmod(start + f * i / MIX_RATE, 1.0) - 1.0
	var dark := _unit(_lowpass(saws, 160.0))
	var open := _unit(_lowpass(saws, 900.0))
	for i in n:
		var breath := 0.5 + 0.5 * sin(TAU * i / n)
		b[i] += dark[i] * (1.0 - 0.6 * breath) + open[i] * 0.45 * breath
	b = _hum(b, 55.0, 0.5, 1)
	b = _noise(b, rng, 0.15, 60.0, 200.0, 3, 0.6)
	b = _noise(b, rng, 0.12, 300.0, 1800.0, 2, 0.8)
	for pulse in 8:
		b = _add_at(b, _tone([48.0, 96.0], 0.6, 0.15), int(pulse * 3.0 * MIX_RATE), 0.3 if pulse % 2 == 0 else 0.18)
	b = _add_at(b, _tone(_plate(150.0), 8.0, 4.0), int(2.0 * MIX_RATE), 0.8)
	b = _add_at(b, _tone(_plate(97.0), 8.0, 4.0), int(13.0 * MIX_RATE), 0.6)
	b = _add_at(b, _tone(_plate(610.0), 4.0, 2.0), int(19.0 * MIX_RATE), 0.25)
	return b


## A crowd in the street: many voices, a chant on the beat, whistles.
static func _crowd_loop(b: PackedFloat32Array, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := b.size()
	b = _murmur(b, rng, 14, 1.0, 0.85)
	var chant := _unit(_band(_white(rng, n), 200.0, 1000.0))
	var beat := _fit(1.5, n)
	for i in n:
		b[i] += chant[i] * 0.9 * pow(0.5 + 0.5 * sin(TAU * beat * i / MIX_RATE), 3.0)
	return _scatter(b, rng, 3, 0.3, func(_r: RandomNumberGenerator) -> PackedFloat32Array: return _sweep(2500.0, 3000.0, 0.4, 1))


# --- layers (each returns the buffer it was given, added to) -------------

static func _noise(b: PackedFloat32Array, rng: RandomNumberGenerator, gain: float, low: float, high: float, swells: int = 0, depth: float = 0.0) -> PackedFloat32Array:
	var n := b.size()
	var band := _unit(_band(_white(rng, n), low, high))
	for i in n:
		b[i] += band[i] * gain * (1.0 - depth * (0.5 + 0.5 * sin(TAU * swells * i / n)))
	return b


static func _hum(b: PackedFloat32Array, hz: float, gain: float, harmonics: int) -> PackedFloat32Array:
	var n := b.size()
	var f := _fit(hz, n)
	for i in n:
		var v := 0.0
		for k in range(1, harmonics + 1):
			v += sin(TAU * f * k * i / MIX_RATE) / k
		b[i] += v * gain
	return b


static func _clock(b: PackedFloat32Array, gain: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	for second in int(b.size() / MIX_RATE):
		b = _add_at(b, _click(rng, 0.006, 4000.0), second * MIX_RATE, gain * (1.0 if second % 2 == 0 else 0.7))
	return b


## Voices: a buzz and breath, speaking in syllables and pausing in phrases.
static func _murmur(b: PackedFloat32Array, rng: RandomNumberGenerator, voices: int, gain: float, duty: float = 0.6) -> PackedFloat32Array:
	var n := b.size()
	var band := _unit(_band(_white(rng, n), 250.0, 1400.0))
	for _v in voices:
		b = _add_at(b, _voice(rng, n, band, 4.0, duty), rng.randi() % n, gain / sqrt(voices))
	return b


static func _static(b: PackedFloat32Array, rng: RandomNumberGenerator, gain: float) -> PackedFloat32Array:
	b = _noise(b, rng, gain, 1500.0, 6000.0)
	return _scatter(b, rng, 30, gain * 2.0, func(r: RandomNumberGenerator) -> PackedFloat32Array: return _click(r, 0.004, 6000.0))


static func _rain(b: PackedFloat32Array, rng: RandomNumberGenerator, gain: float) -> PackedFloat32Array:
	b = _noise(b, rng, gain, 1000.0, 8000.0)
	return _scatter(b, rng, 200, gain * 0.5, func(r: RandomNumberGenerator) -> PackedFloat32Array: return _click(r, 0.01, 6000.0))


static func _scatter(b: PackedFloat32Array, rng: RandomNumberGenerator, count: int, gain: float, make: Callable) -> PackedFloat32Array:
	for _index in count:
		b = _add_at(b, make.call(rng), rng.randi() % b.size(), gain)
	return b


## Adds `event` at `at`, wrapping its tail round to the loop's start.
static func _add_at(b: PackedFloat32Array, event: PackedFloat32Array, at: int, gain: float) -> PackedFloat32Array:
	var n := b.size()
	for i in event.size():
		b[(at + i) % n] += event[i] * gain
	return b


# --- one-off sounds -------------------------------------------------------

static func _typing(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var keys := rng.randi_range(8, 24)
	var out := PackedFloat32Array()
	out.resize(int((keys * 0.2 + 1.0) * MIX_RATE))
	var at := 0
	for _k in keys:
		out = _add_at(out, _click(rng, 0.015, rng.randf_range(1500.0, 3000.0)), at, rng.randf_range(0.6, 1.0))
		at += int(rng.randf_range(0.08, 0.2) * MIX_RATE)
	if rng.randf() < 0.5:
		out = _add_at(out, _tone([2100.0, 4200.0], 0.6, 0.25), at, 0.3)
	return out


static func _teletype(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var keys := rng.randi_range(15, 30)
	var out := PackedFloat32Array()
	out.resize(int((keys * 0.11 + 0.2) * MIX_RATE))
	for k in keys:
		out = _add_at(out, _click(rng, 0.012, 2500.0), int((k * 0.1 + rng.randf_range(0.0, 0.01)) * MIX_RATE), 1.0)
	return out


static func _phone(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	return _repeat(_repeat(_tone([440.0, 480.0], 0.4, 1000.0), 2, 0.6), 2, 3.0)


static func _beeps(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	return _repeat(_tone([1000.0], 0.12, 1000.0), 2, 0.25)


static func _radio(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var m := int(rng.randf_range(1.5, 3.0) * MIX_RATE)
	var band := _unit(_band(_white(rng, m), 500.0, 2500.0))
	var out := _voice(rng, m, band, 5.0, 0.9)
	out = _add_at(out, _click(rng, 0.03, 5000.0), 0, 0.8)
	return _add_at(out, _click(rng, 0.03, 5000.0), m - int(0.03 * MIX_RATE), 0.8)


static func _gavel(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var knock := _tone([180.0, 420.0], 0.25, 0.05)
	knock = _add_at(knock, _click(rng, 0.01, 3000.0), 0, 0.6)
	return _repeat(knock, 2, 0.35)


static func _cough(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var m := int(0.25 * MIX_RATE)
	var burst := _unit(_band(_white(rng, m), 300.0, 1500.0))
	for i in m:
		burst[i] *= exp(-float(i) / (0.08 * MIX_RATE))
	return _repeat(burst, rng.randi_range(1, 2), 0.3)


static func _rustle(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var m := int(0.4 * MIX_RATE)
	var y := _unit(_band(_white(rng, m), 2000.0, 8000.0))
	for i in m:
		y[i] *= sin(PI * i / m) * (0.5 + 0.5 * sin(TAU * 30.0 * i / MIX_RATE))
	return y


static func _drawer(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var slide := _rustle(rng)
	return _add_at(slide, _tone([60.0, 90.0], 0.4, 0.08), slide.size() - 1, 1.0)


static func _bird(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var low := rng.randf_range(2800.0, 3600.0)
	return _repeat(_sweep(low, low * 1.4, 0.07, 1), rng.randi_range(2, 4), 0.12)


static func _gull(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var high := rng.randf_range(1600.0, 1900.0)
	return _repeat(_sweep(high, high * 0.62, 0.35, 3), 3, 0.47)


static func _car(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var seconds := rng.randf_range(2.5, 4.5)
	var m := int(seconds * MIX_RATE)
	var road := _unit(_lowpass(_white(rng, m), 700.0))
	var engine := rng.randf_range(60.0, 90.0)
	var phase := 0.0
	for i in m:
		var t := float(i) / m
		phase += engine * (1.06 - 0.12 * t) / MIX_RATE
		road[i] = (road[i] + 0.6 * sin(TAU * phase) + 0.3 * sin(TAU * phase * 2.0)) * pow(sin(PI * t), 3.0)
	return road


static func _horn(rng: RandomNumberGenerator) -> PackedFloat32Array:
	return _repeat(_tone([392.0, 494.0, 784.0, 988.0], rng.randf_range(0.25, 0.5), 1000.0), rng.randi_range(1, 2), 0.6)


static func _tram_bell(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	return _repeat(_tone([1180.0, 2950.0, 4300.0], 1.2, 0.35), 2, 0.3)


static func _church_bell(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	return _tone([196.0, 392.0, 466.0, 588.0, 784.0, 1040.0], 6.0, 1.5)


static func _ship_horn(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	return _tone([73.0, 146.0, 219.0, 292.0], 2.5, 1000.0, 0.1)


# --- primitives -----------------------------------------------------------

## Sum of partials, sharp attack, exponential decay (`decay` seconds; a
## large decay is a held tone), short release at the end.
static func _tone(partials: Array, seconds: float, decay: float, attack: float = 0.005) -> PackedFloat32Array:
	var m := int(seconds * MIX_RATE)
	var y := PackedFloat32Array()
	y.resize(m)
	for i in m:
		var t := float(i) / MIX_RATE
		var v := 0.0
		for k in partials.size():
			v += sin(TAU * partials[k] * t) / (k + 1)
		y[i] = v * minf(1.0, t / attack) * exp(-t / decay) * minf(1.0, (seconds - t) * 20.0)
	return _peak1(y)


## Struck sheet metal: inharmonic plate partials.
static func _plate(hz: float) -> Array:
	return [hz, hz * 2.76, hz * 5.4, hz * 8.93, hz * 13.3]


static func _sweep(from_hz: float, to_hz: float, seconds: float, harmonics: int) -> PackedFloat32Array:
	var m := int(seconds * MIX_RATE)
	var y := PackedFloat32Array()
	y.resize(m)
	var phase := 0.0
	for i in m:
		var t := float(i) / m
		phase += lerpf(from_hz, to_hz, t) / MIX_RATE
		var v := 0.0
		for k in range(1, harmonics + 1):
			v += sin(TAU * phase * k) / k
		y[i] = v * sin(PI * t)
	return _peak1(y)


static func _click(rng: RandomNumberGenerator, seconds: float, hz: float) -> PackedFloat32Array:
	var m := maxi(1, int(seconds * MIX_RATE))
	var y := _white(rng, m)
	for i in m:
		y[i] *= exp(-4.0 * i / m)
	return _peak1(_band(y, hz * 0.3, hz))


static func _voice(rng: RandomNumberGenerator, m: int, band: PackedFloat32Array, rate: float, duty: float) -> PackedFloat32Array:
	var y := PackedFloat32Array()
	y.resize(m)
	var pitch := rng.randf_range(95.0, 230.0)
	var drift := rng.randf_range(0.0, TAU)
	var offset := rng.randi() % band.size()
	var smooth := 1.0 - exp(-TAU * 10.0 / MIX_RATE)
	var tract := 1.0 - exp(-TAU * 900.0 / MIX_RATE)
	var edge := 0.08 * MIX_RATE
	var target := 0.0
	var next := 0
	var env := 0.0
	var phase := 0.0
	var buzz := 0.0
	for i in m:
		if i >= next:
			next = i + int(rng.randf_range(0.5, 1.5) * MIX_RATE / rate)
			target = rng.randf_range(0.4, 1.0) if rng.randf() < duty else 0.0
		env += smooth * (target - env)
		phase = fmod(phase + pitch * (1.0 + 0.1 * sin(0.7 * i / MIX_RATE + drift) + 0.15 * target) / MIX_RATE, 1.0)
		buzz += tract * (2.0 * phase - 1.0 - buzz)
		var fade := minf(1.0, mini(i, m - 1 - i) / edge)
		y[i] = (0.45 * buzz + 0.55 * band[(i + offset) % band.size()]) * env * fade
	return y


static func _repeat(event: PackedFloat32Array, times: int, gap_seconds: float) -> PackedFloat32Array:
	var step := int(gap_seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(step * (times - 1) + event.size())
	for t in times:
		out = _add_at(out, event, t * step, 1.0)
	return out


static func _white(rng: RandomNumberGenerator, m: int) -> PackedFloat32Array:
	var y := PackedFloat32Array()
	y.resize(m)
	for i in m:
		y[i] = rng.randf_range(-1.0, 1.0)
	return y


## One-pole low-pass run twice round the loop, so its end meets its start.
static func _lowpass(x: PackedFloat32Array, hz: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * hz / MIX_RATE)
	var y := PackedFloat32Array()
	y.resize(x.size())
	var s := 0.0
	for _pass in 2:
		for i in x.size():
			s += a * (x[i] - s)
			y[i] = s
	return y


static func _band(x: PackedFloat32Array, low: float, high: float) -> PackedFloat32Array:
	var y := _lowpass(x, high)
	var under := _lowpass(y, low)
	for i in y.size():
		y[i] -= under[i]
	return y


## A frequency nudged to a whole number of cycles in `n` samples.
static func _fit(hz: float, n: int) -> float:
	var seconds := float(n) / MIX_RATE
	return roundf(hz * seconds) / seconds


static func _unit(x: PackedFloat32Array) -> PackedFloat32Array:
	var sum := 0.0
	for v in x:
		sum += v * v
	var rms := sqrt(sum / maxi(1, x.size()))
	if rms > 0.0:
		for i in x.size():
			x[i] /= rms
	return x


static func _peak1(x: PackedFloat32Array) -> PackedFloat32Array:
	var peak := 0.0
	for v in x:
		peak = maxf(peak, absf(v))
	if peak > 0.0:
		for i in x.size():
			x[i] /= peak
	return x


## Samples to a looping 16-bit stream, levelled to a common loudness
## without clipping. Null for an empty render.
static func to_stream(b: PackedFloat32Array) -> AudioStreamWAV:
	if b.is_empty():
		return null
	var sum := 0.0
	var peak := 0.0
	for v in b:
		sum += v * v
		peak = maxf(peak, absf(v))
	var rms := sqrt(sum / b.size())
	var scale := minf(TARGET_RMS / maxf(rms, 1e-6), 0.95 / maxf(peak, 1e-6)) * 32767.0
	var pcm := PackedByteArray()
	pcm.resize(b.size() * 2)
	for i in b.size():
		pcm.encode_s16(i * 2, int(b[i] * scale))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = pcm
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = b.size()
	return stream
