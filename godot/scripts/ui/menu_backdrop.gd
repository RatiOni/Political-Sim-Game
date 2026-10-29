class_name MenuBackdrop
extends Control

## The title screen: Vashtera across the water at dusk, framed like a newsreel
## still — a low horizon, the parliament dome and its spire as the one strong
## subject, ridges in haze behind, works smoke drifting, the city's lights
## shattered into streaks on the bay. It is drawn as a smooth picture and
## shown through `AsciiConvert`, which turns every frame into glyphs.
##
## Deterministic by construction: the skyline comes from a fixed seed, so the
## title screen is the same place every launch; only time moves it.

const SEED := 19930601   # Ardenia, June 1993
const HORIZON := 0.66

var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _ascii: AsciiConvert
var _blocks: Array[Dictionary] = []
var _lights: Array[Vector3] = []
var _stars: Array[Vector3] = []
var _built_for := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_ascii = AsciiConvert.cover(self, "dusk")
	_ascii.set_water_from(HORIZON + 0.012)


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()


## The title reveal ends on this: the whole picture burns white and settles.
func burst() -> void:
	if _ascii != null:
		_ascii.burst(Vector2(0.5, HORIZON - 0.12), 2.8)


func _layout() -> void:
	_built_for = size
	_rng.seed = SEED
	_blocks.clear()
	_lights.clear()
	_stars.clear()
	var horizon := size.y * HORIZON
	var x := size.x * 0.22
	while x < size.x * 0.80:
		var w := _rng.randf_range(10.0, 34.0)
		var centre := 1.0 - absf((x - size.x * 0.5) / (size.x * 0.3))
		var h := _rng.randf_range(12.0, 30.0) + centre * _rng.randf_range(20.0, 70.0)
		_blocks.append({"x": x, "w": w, "h": h})
		for wy in range(int(horizon - h + 5), int(horizon - 3), 6):
			for wx in range(int(x + 3), int(x + w - 3), 5):
				if _rng.randf() < 0.32:
					_lights.append(Vector3(wx, wy, _rng.randf() * TAU))
		x += w + (_rng.randf_range(2.0, 14.0) if _rng.randf() < 0.3 else 0.0)
	for i in 120:
		_stars.append(Vector3(_rng.randf() * size.x, _rng.randf() * horizon * 0.55, _rng.randf() * TAU))


func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	if _built_for != size:
		_layout()
	var t := _clock
	var horizon := size.y * HORIZON
	var w := size.x

	# Sky: deep navy overhead falling to a burnt dusk at the horizon, its warmth
	# breathing slowly.
	var warm := 0.5 + 0.5 * sin(t * 0.05)
	_vgrad(0.0, horizon, Color(0.03, 0.05, 0.11), Color(0.42, 0.19, 0.08).lerp(Color(0.55, 0.26, 0.10), warm))
	for st in _stars:
		draw_rect(Rect2(st.x, st.y, 1.5, 1.5), Color(0.9, 0.9, 1.0, 0.25 + 0.3 * sin(t * 1.1 + st.z * 4.0)), true)
	# The moon, with a faint halo.
	var moon := Vector2(w * 0.18, size.y * 0.16)
	for r in [40.0, 26.0, 16.0]:
		draw_circle(moon, r, Color(0.7, 0.72, 0.8, 0.05))
	draw_circle(moon, 10.0, Color(0.88, 0.86, 0.78))

	# Cloud banks drifting east.
	for i in 5:
		var cx := fposmod(i * w * 0.27 + t * (4.0 + i), w + 400.0) - 200.0
		var cy := size.y * (0.12 + 0.07 * i)
		draw_set_transform(Vector2(cx, cy), 0.0, Vector2(1.0, 0.22))
		for k in 4:
			draw_circle(Vector2(k * 60.0, sin(k * 1.7 + i) * 20.0), 90.0, Color(0.50, 0.30, 0.24, 0.025))
		draw_set_transform(Vector2.ZERO)

	# Ridges in haze: the far one paler, the near one darker.
	_ridge(horizon - size.y * 0.12, size.y * 0.10, Color(0.20, 0.17, 0.20), 3)
	_ridge(horizon - size.y * 0.04, size.y * 0.05, Color(0.11, 0.10, 0.12), 7)
	for k in 3:
		draw_rect(Rect2(0, horizon - 24.0 + k * 8.0, w, 10.0), Color(0.60, 0.32, 0.18, 0.04), true)

	# The capital in silhouette, the parliament at its heart.
	var ink := Color(0.07, 0.065, 0.075)
	for b in _blocks:
		draw_rect(Rect2(float(b["x"]), horizon - float(b["h"]), float(b["w"]), float(b["h"])), ink, true)
	var dome := Vector2(w * 0.5, horizon - 70.0)
	draw_rect(Rect2(dome.x - 60.0, horizon - 52.0, 120.0, 52.0), ink.lightened(0.05), true)
	draw_circle(dome, 28.0, ink.lightened(0.08))
	draw_rect(Rect2(dome.x - 2.0, dome.y - 70.0, 4.0, 46.0), ink.lightened(0.08), true)
	draw_rect(Rect2(dome.x - 26.0, dome.y + 8.0, 52.0, 4.0), Color(0.55, 0.42, 0.28), true)
	for c in range(-50, 51, 14):
		draw_rect(Rect2(dome.x + c - 2.0, horizon - 44.0, 4.0, 36.0), Color(0.42, 0.34, 0.26), true)
	var beacon := 0.5 + 0.5 * sin(t * 2.2)
	draw_circle(Vector2(dome.x, dome.y - 70.0), 2.5, Color(0.95, 0.35, 0.2, 0.4 + 0.6 * beacon))
	for l in _lights:
		var a := 0.55 + 0.45 * sin(t * 0.4 + l.z * 5.0)
		draw_rect(Rect2(l.x, l.y, 2.0, 3.0), Color(0.98, 0.76, 0.42, a), true)

	# Works chimneys on the right, smoke rolling up and away.
	for s in 2:
		var sx := w * (0.74 + s * 0.03)
		draw_rect(Rect2(sx, horizon - 96.0, 6.0, 96.0), ink, true)
		for i in 14:
			var age := fposmod(t * 0.05 + float(i) / 14.0 + s * 0.3, 1.0)
			var p := Vector2(sx + 3.0 + age * 140.0 + sin(age * 5.0 + i) * 8.0, horizon - 98.0 - age * 150.0)
			draw_circle(p, 5.0 + age * 34.0, Color(0.40, 0.36, 0.36, (1.0 - age) * 0.22))

	# The bay: dark water, the city's lights broken into drifting streaks.
	_vgrad(horizon, size.y, Color(0.10, 0.09, 0.12), Color(0.02, 0.03, 0.05))
	for l in _lights:
		if int(l.z * 10.0) % 2 != 0:
			continue
		var depth := horizon - l.y
		for row in 6:
			var y := horizon + depth * 0.6 + row * 6.0
			var wob := sin(t * 1.3 + row * 1.1 + l.x * 0.05) * (2.0 + row * 1.5)
			var len := 4.0 + 3.0 * sin(t * 1.7 + row + l.x)
			draw_rect(Rect2(l.x + wob, y, len, 1.5), Color(0.95, 0.72, 0.40, 0.45 * (1.0 - row / 6.0)), true)
	for row in range(0, int(size.y - horizon), 5):
		var y := horizon + row
		var k := float(row) / maxf(1.0, size.y - horizon)
		var wx := fposmod(w * 0.5 + sin(t * 0.7 + row * 0.4) * 30.0, w)
		draw_rect(Rect2(wx - 40.0 * (1.0 + k), y, 80.0 * (1.0 + k), 1.5), Color(0.6, 0.45, 0.35, 0.12 * (1.0 - k)), true)


func _vgrad(y0: float, y1: float, top: Color, low: Color) -> void:
	draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(size.x, y0), Vector2(size.x, y1), Vector2(0, y1)]),
		PackedColorArray([top, top, low, low]))


## A silhouette from summed sines with a fixed seed: irregular, natural, stable.
func _ridge(base: float, amp: float, color: Color, salt: int) -> void:
	var pts := PackedVector2Array([Vector2(0, size.y * HORIZON + 1.0)])
	var x := 0.0
	while x <= size.x + 8.0:
		var y := base - amp * (0.55 + 0.25 * sin(x * 0.006 + salt) + 0.15 * sin(x * 0.019 + salt * 2.0) + 0.05 * sin(x * 0.07 + salt))
		pts.append(Vector2(x, y))
		x += 8.0
	pts.append(Vector2(size.x, size.y * HORIZON + 1.0))
	draw_colored_polygon(pts, color)
