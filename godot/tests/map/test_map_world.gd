extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const VIEW_SIZE := Vector2(1344, 800)
const NORTHERN_RIDGE := Vector2(0.48, 0.16)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t = TestSupportScript.new()
	var scene: PackedScene = load("res://scenes/map/map_world.tscn")
	t.truth(scene != null, "the map world scene exists")
	if scene == null:
		quit(t.finish())
		return
	var view := SubViewport.new()
	view.size = Vector2i(VIEW_SIZE)
	root.add_child(view)
	var world: MapWorld = scene.instantiate()
	view.add_child(world)
	await process_frame
	await process_frame

	var geo := MapGeometry.load_world()
	t.truth(world.build(geo), "the world builds from the baked data")
	t.truth(world.terrain.data.get_region_count() > 0, "terrain regions exist")
	t.equal(world.terrain.assets.get_texture_count(), 7, "one texture per terrain material")
	t.equal(world.camera.projection, Camera3D.PROJECTION_ORTHOGONAL, "the camera is orthographic")
	t.near(world.camera.size, geo.extent_m.y, 0.01, "the camera frames the whole country")

	var capital: Dictionary = geo.cities.filter(func(c): return c["capital"])[0]
	var capital_height: float = world.terrain.data.get_height(geo.map_to_world(capital["point"]))
	var ridge_height: float = world.terrain.data.get_height(geo.map_to_world(NORTHERN_RIDGE))
	t.truth(capital_height > 0.0, "the capital is above sea level")
	t.truth(capital_height < ridge_height, "the capital lies below the northern ridge")

	var centre := geo.world_to_map(world.world_point_at(VIEW_SIZE / 2.0, VIEW_SIZE))
	t.near(centre.distance_to(Vector2(0.5, 0.5)), 0.0, 0.01, "the screen centre is the map centre")

	world.set_dusk(false)
	var day_energy := world.sun.light_energy
	world.set_dusk(true)
	t.truth(world.sun.light_energy < day_energy, "dusk dims the sun")
	quit(t.finish())
