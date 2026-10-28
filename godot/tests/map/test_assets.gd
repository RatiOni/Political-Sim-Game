extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")


func _initialize() -> void:
	var t = TestSupportScript.new()
	t.equal(MapAssets.MATERIALS.size(), 7, "seven terrain materials")
	for material in MapAssets.MATERIALS:
		var paths := MapAssets.texture_paths(material)
		for key in ["albedo_height", "normal_rough"]:
			t.truth(ResourceLoader.exists(paths[key]), "%s %s exists" % [material, key])
			var tex: Texture2D = load(paths[key])
			t.truth(tex != null and tex.get_width() == 1024, "%s %s is a 1K texture" % [material, key])
			t.truth(tex != null and tex.get_image().detect_alpha() != Image.ALPHA_NONE, "%s %s carries its packed alpha channel" % [material, key])
	for path in MapAssets.TOWN_MODELS + MapAssets.TREE_MODELS + [MapAssets.CHECKPOINT_MODEL]:
		t.truth(ResourceLoader.exists(path), "model %s exists" % path)
	t.truth(MapAssets.TOWN_MODELS.size() >= 10, "enough building variety for a town")
	t.truth(MapAssets.TREE_MODELS.size() >= 4, "enough tree variety for a forest")
	var credits := FileAccess.get_file_as_string("res://assets/CREDITS.md")
	for needle in ["Poly Haven", "CC0", "Kenney", "Terrain3D", "MIT"]:
		t.truth(credits.contains(needle), "credits name %s" % needle)
	quit(t.finish())
