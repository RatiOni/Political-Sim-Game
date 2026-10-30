class_name AsciiConvert
extends ColorRect

## Lays the colour-ASCII converter (`shaders/ascii_convert.gdshader`) over a
## picture control: the control keeps drawing a smooth source, and this node
## turns every frame of it into glyphs. Add it as the picture's last child.
##
## Each scene picks one restrained palette — a colour-reduced print, never
## neon. `burst()` is the big-moment effect: every cell burns to cream, a
## shockwave ring runs out from the event, and the image fades back down the
## shading ramp.

const SHADER := preload("res://shaders/ascii_convert.gdshader")

const PALETTES := {
	"night": [
		Color("1a2340"), Color("3a4c66"), Color("55626e"), Color("6d6a62"), Color("b39f78"),
		Color("e4dbc0"), Color("d79a4c"), Color("8a4a34"), Color("5a5e3c"), Color("8f8a7a"),
		Color("2c3a52"), Color("a08c5a"),
	],
	"fire": [
		Color("d2742e"), Color("9c4a24"), Color("5e1d16"), Color("9e916a"), Color("e6dcc2"),
		Color("6e6862"), Color("38322e"), Color("c79a4c"), Color("461410"), Color("b8a47e"),
		Color("524c48"), Color("f0c878"),
	],
	"sea": [
		Color("16223c"), Color("35567a"), Color("5c6870"), Color("b09c78"), Color("e2dac4"),
		Color("4a6a72"), Color("d39a50"), Color("0e1828"), Color("98a6ae"), Color("8a7c62"),
		Color("7a4a36"), Color("27405e"),
	],
	"dusk": [
		Color("1c2440"), Color("3a4a6c"), Color("5a5a6a"), Color("b49a78"), Color("e8dcc0"),
		Color("d89048"), Color("8c4630"), Color("4e2a2a"), Color("2a3350"), Color("9a8a70"),
		Color("6a5a4c"), Color("f0c070"),
	],
}

var _tween: Tween


static func cover(target: Control, palette: String = "night") -> AsciiConvert:
	# A fresh copy of what is drawn so far, so two converted pictures on one
	# screen never read each other's stale pixels.
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	target.add_child(copy)
	var node := AsciiConvert.new()
	target.add_child(node)
	node.set_palette(palette)
	return node


func _init() -> void:
	name = "AsciiConvert"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("ramp", ImageTexture.create_from_image(AsciiRamp.strip()))
	mat.set_shader_parameter("ramp_count", float(AsciiRamp.ROWS.size()))
	material = mat
	resized.connect(func() -> void: _param("size_px", size))


func _param(key: String, value: Variant) -> void:
	(material as ShaderMaterial).set_shader_parameter(key, value)


func set_palette(palette: String) -> void:
	var colours: Array = PALETTES.get(palette, PALETTES["night"])
	var packed := PackedVector3Array()
	for c in colours:
		packed.append(Vector3(c.r, c.g, c.b))
	while packed.size() < 16:
		packed.append(packed[0])
	_param("palette", packed)
	_param("palette_size", colours.size())


## Local UV row from which the picture is water, drawn in streaks. >1 = none.
func set_water_from(uv_y: float) -> void:
	_param("water_from", uv_y)


func set_gain(gain: float) -> void:
	_param("gain", gain)


## The big-moment effect, centred on `at` (local UV).
func burst(at: Vector2 = Vector2(0.5, 0.5), seconds: float = 2.4) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_param("ring_at", at)
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(func(v: float) -> void: _param("flash", v), 1.0, 0.0, seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_method(func(v: float) -> void: _param("ring_radius", v), 4.0, size.length(), seconds * 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.chain().tween_callback(func() -> void: _param("ring_radius", -1.0))
