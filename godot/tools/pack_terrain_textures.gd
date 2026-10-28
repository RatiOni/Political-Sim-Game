extends SceneTree

const SOURCE := "D:/Political Sim Game/.worktrees/godot-native-sim/.scratch/downloads/polyhaven"
const TARGET := "res://assets/terrain"
const SIZE := 1024
const MATERIALS := ["grass", "forest", "farmland", "rock", "snow", "sand", "road"]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(TARGET)
	for material in MATERIALS:
		_write(material, "albedo_height", _pack(_load(material, "albedo"), _load(material, "height")))
		_write(material, "normal_rough", _pack(_load(material, "normal"), _load(material, "roughness")))
	quit(0)


func _load(material: String, map: String) -> Image:
	for ext in ["png", "jpg"]:
		var path := "%s/%s/%s.%s" % [SOURCE, material, map, ext]
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			img.convert(Image.FORMAT_RGBA8)
			img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
			return img
	push_error("missing %s %s" % [material, map])
	return Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)


func _pack(rgb: Image, alpha_source: Image) -> Image:
	var out := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var c := rgb.get_pixel(x, y)
			c.a = alpha_source.get_pixel(x, y).r
			out.set_pixel(x, y, c)
	return out


func _write(material: String, kind: String, img: Image) -> void:
	img.save_png("%s/%s_%s.png" % [TARGET, material, kind])
