class_name MapWorld
extends Node3D

const BAKED_DIR := "res://data/map/baked/"
const TEXTURE_UV_SCALE := 0.08
const TINTS := {
	"grass": Color(0.7, 1.35, 0.75),
	"forest": Color(0.45, 0.8, 0.5),
	"farmland": Color(1.15, 1.1, 0.7),
}
const SEA_LEVEL_Y := -2.0
const SEA_FLOOR_M := -10.0
const SEA_COLOR := Color(0.08, 0.22, 0.32)
const CAMERA_HEIGHT_M := 6000.0
const CAMERA_FAR_M := 12000.0
const DAY_ENERGY := 1.2
const DUSK_ENERGY := 0.35
const DAY_COLOR := Color(1.0, 1.0, 1.0)
const DUSK_COLOR := Color(1.0, 0.72, 0.5)
const SUN_ROTATION_DEG := Vector3(-55.0, 25.0, 0.0)

var terrain: Terrain3D
var camera: Camera3D
var sun: DirectionalLight3D
var environment_node: WorldEnvironment
var sea: MeshInstance3D
var geometry: MapGeometry


func build(geo: MapGeometry) -> bool:
	var height := _load_baked("height.exr")
	var control := _load_baked("control.exr")
	if height == null or control == null:
		push_error("MapWorld: baked terrain data is missing; run the map baker")
		return false
	control.convert(Image.FORMAT_RF)
	height.convert(Image.FORMAT_RF)
	geometry = geo
	_build_camera(geo)
	_build_light()
	_build_environment()
	_build_sea(geo)
	_build_terrain(geo, height, control)
	return true


func set_dusk(on: bool) -> void:
	sun.light_energy = DUSK_ENERGY if on else DAY_ENERGY
	sun.light_color = DUSK_COLOR if on else DAY_COLOR


func world_point_at(screen: Vector2, viewport_size: Vector2) -> Vector3:
	var span_z := camera.size
	var span_x := camera.size * viewport_size.x / viewport_size.y
	var offset := screen / viewport_size - Vector2(0.5, 0.5)
	return Vector3(camera.global_position.x + offset.x * span_x, 0.0, camera.global_position.z + offset.y * span_z)


func _load_baked(file: String) -> Image:
	var path := BAKED_DIR + file
	if not FileAccess.file_exists(path):
		return null
	return Image.load_from_file(path)


func _build_camera(geo: MapGeometry) -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = geo.extent_m.y
	camera.far = CAMERA_FAR_M
	add_child(camera)
	camera.position = Vector3(0.0, CAMERA_HEIGHT_M, 0.0)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	camera.current = true


func _build_light() -> void:
	sun = DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = SUN_ROTATION_DEG
	set_dusk(false)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SEA_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.66, 0.75)
	env.ambient_light_energy = 0.5
	env.glow_enabled = true
	environment_node = WorldEnvironment.new()
	environment_node.environment = env
	add_child(environment_node)


func _build_sea(geo: MapGeometry) -> void:
	var plane := PlaneMesh.new()
	plane.size = geo.extent_m * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = SEA_COLOR
	material.roughness = 0.15
	material.metallic = 0.3
	plane.material = material
	sea = MeshInstance3D.new()
	sea.mesh = plane
	add_child(sea)
	sea.position = Vector3(0.0, SEA_LEVEL_Y, 0.0)


func _build_assets() -> Terrain3DAssets:
	var assets := Terrain3DAssets.new()
	var list: Array[Terrain3DTextureAsset] = []
	for i in MapAssets.MATERIALS.size():
		var paths := MapAssets.texture_paths(MapAssets.MATERIALS[i])
		var asset := Terrain3DTextureAsset.new()
		asset.name = MapAssets.MATERIALS[i]
		asset.id = i
		asset.albedo_texture = load(paths["albedo_height"])
		asset.normal_texture = load(paths["normal_rough"])
		asset.uv_scale = TEXTURE_UV_SCALE
		asset.albedo_color = TINTS.get(MapAssets.MATERIALS[i], Color.WHITE)
		list.append(asset)
	assets.set_texture_list(list)
	return assets


func _build_terrain(geo: MapGeometry, height: Image, control: Image) -> void:
	terrain = Terrain3D.new()
	add_child(terrain)
	terrain.assets = _build_assets()
	var spacing := geo.extent_m.x / float(MapBaker.RESOLUTION.x)
	terrain.vertex_spacing = spacing
	terrain.set_camera(camera)
	var region_m := float(terrain.get_region_size()) * spacing
	var map_origin := Vector2(-geo.extent_m.x / 2.0, -geo.extent_m.y / 2.0)
	var canvas_origin := (map_origin / region_m).floor() * region_m
	var pad_px := Vector2i(((map_origin - canvas_origin) / spacing).round())
	var canvas_px := Vector2i((Vector2(pad_px + MapBaker.RESOLUTION) / float(terrain.get_region_size())).ceil() * float(terrain.get_region_size()))
	var padded_height := _padded(height, canvas_px, pad_px, SEA_FLOOR_M)
	var padded_control := _padded(control, canvas_px, pad_px, 0.0)
	terrain.data.import_images([padded_height, padded_control, null], Vector3(canvas_origin.x, 0.0, canvas_origin.y), 0.0, 1.0)


func _padded(source: Image, canvas_px: Vector2i, offset_px: Vector2i, fill: float) -> Image:
	var canvas := Image.create_empty(canvas_px.x, canvas_px.y, false, Image.FORMAT_RF)
	canvas.fill(Color(fill, 0.0, 0.0))
	canvas.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), offset_px)
	return canvas
