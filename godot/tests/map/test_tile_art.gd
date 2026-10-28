extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")


func _initialize() -> void:
	var t = TestSupportScript.new()
	t.equal(MapPalette.DAY.size(), 32, "the day palette has 32 colours")
	t.equal(MapPalette.DUSK.size(), 32, "the dusk palette has 32 colours")
	t.truth(MapPalette.DUSK[MapPalette.GRASS].get_luminance() < MapPalette.DAY[MapPalette.GRASS].get_luminance(), "grass darkens at dusk")
	t.equal(MapPalette.DUSK[MapPalette.LIT], MapPalette.DAY[MapPalette.LIT], "lit windows keep their glow at dusk")
	t.equal(MapPalette.nearest(MapPalette.DAY[MapPalette.ROOF]), MapPalette.ROOF, "a palette colour is its own nearest")

	var atlas := TileArt.build_atlas()
	t.equal(atlas.get_data(), TileArt.build_atlas().get_data(), "the atlas builds byte-identically")
	var allowed := {}
	for c in MapPalette.DAY:
		allowed[c.to_rgba32()] = true
	var stray := 0
	for y in atlas.get_height():
		for x in atlas.get_width():
			var p := atlas.get_pixel(x, y)
			if p.a > 0.0 and not allowed.has(p.to_rgba32()):
				stray += 1
	t.equal(stray, 0, "every opaque atlas pixel is a day palette colour")

	var cells: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TileArt.ATLAS_JSON))
	var missing: Array[String] = []
	for kind in TileArt.KINDS:
		for v in TileArt.VARIANTS:
			if not cells.has(TileArt.variant_key(kind, v)):
				missing.append(TileArt.variant_key(kind, v))
	for sprite in TileArt.SPRITES:
		if not cells.has(sprite):
			missing.append(sprite)
	t.equal(missing, [] as Array[String], "the atlas index names every kind variant and sprite")

	var tileset := TileArt.load_tileset()
	t.truth(tileset != null, "the tile set loads")
	if tileset != null:
		t.equal(tileset.tile_size, Vector2i(8, 8), "tiles are 8x8")
		t.equal(tileset.get_source_count(), 1, "one atlas source")
	quit(t.finish())
