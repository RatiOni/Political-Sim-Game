extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")


func _initialize() -> void:
	var t = TestSupportScript.new()
	t.equal(MapPalette.DAY.size(), 32, "the day palette has 32 colours")
	t.equal(MapPalette.DUSK.size(), 32, "the dusk palette has 32 colours")
	t.truth(MapPalette.DUSK[MapPalette.GRASS].get_luminance() < MapPalette.DAY[MapPalette.GRASS].get_luminance(), "grass darkens at dusk")
	t.equal(MapPalette.DUSK[MapPalette.LIT], MapPalette.DAY[MapPalette.LIT], "lit windows keep their glow at dusk")
	t.truth(MapPalette.FOREIGN.size() > 1, "a foreign grey ramp exists")
	t.equal(MapPalette.FOREIGN_DUSK.size(), MapPalette.FOREIGN.size(), "the foreign ramp has a dusk twin")
	for c in MapPalette.FOREIGN:
		t.truth(c.s < 0.2, "foreign colour %s is greyed" % c.to_html(false))
	t.equal(TileArt.halve(TileArt.ground("river", 0)).size(), 16, "halving an 8 px cell gives 4 x 4")
	t.truth(is_same(TileArt.index(), TileArt.index()), "the tile index is built once and reused")
	for tile_px in TileArt.SIZES:
		_check_atlas(t, tile_px)
	quit(t.finish())


func _stray(image: Image, palette: PackedColorArray) -> int:
	var allowed := {}
	for c in palette:
		allowed[c.to_rgba32()] = true
	var stray := 0
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if p.a > 0.0 and not allowed.has(p.to_rgba32()):
				stray += 1
	return stray


func _check_atlas(t, tile_px: int) -> void:
	var atlas := TileArt.build_atlas(tile_px)
	t.equal(atlas.get_data(), TileArt.build_atlas(tile_px).get_data(), "the %d px atlas builds byte-identically" % tile_px)
	t.equal(atlas.get_size(), Vector2i(TileArt.COLUMNS * tile_px, ceili(TileArt.cell_names().size() / float(TileArt.COLUMNS)) * tile_px), "the %d px atlas has %d px cells" % [tile_px, tile_px])
	var committed := Image.new()
	committed.load(TileArt.atlas_png(tile_px))
	committed.convert(atlas.get_format())
	t.equal(committed.get_data(), atlas.get_data(), "the committed %d px atlas matches the code" % tile_px)
	t.equal(_stray(atlas, MapPalette.DAY + MapPalette.FOREIGN), 0, "every opaque %d px atlas pixel is a day or foreign palette colour" % tile_px)
	t.equal(_stray(TileArt.dusk_atlas(atlas), MapPalette.DUSK + MapPalette.FOREIGN_DUSK), 0, "every opaque %d px dusk atlas pixel is a dusk palette colour" % tile_px)

	var cells: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TileArt.atlas_json(tile_px)))
	var missing: Array[String] = []
	for kind in TileArt.KINDS:
		for v in TileArt.VARIANTS:
			if not cells.has(TileArt.variant_key(kind, v)):
				missing.append(TileArt.variant_key(kind, v))
			if not cells.has(TileArt.foreign_key(kind, v)):
				missing.append(TileArt.foreign_key(kind, v))
	for sprite in TileArt.SPRITES:
		if not cells.has(sprite):
			missing.append(sprite)
	t.equal(missing, [] as Array[String], "the %d px atlas index names every kind variant and sprite" % tile_px)

	var tileset := TileArt.load_tileset(tile_px)
	t.truth(tileset != null, "the %d px tile set loads" % tile_px)
	if tileset != null:
		t.equal(tileset.tile_size, Vector2i(tile_px, tile_px), "tiles are %d x %d" % [tile_px, tile_px])
		t.equal(tileset.get_source_count(), 1, "one %d px atlas source" % tile_px)
