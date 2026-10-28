extends SceneTree

const PREVIEW := "res://../.scratch/tile_atlas_%d_preview.png"
const PREVIEW_PX := 32


func _init() -> void:
	for tile_px in TileArt.SIZES:
		var atlas := TileArt.build_atlas(tile_px)
		atlas.save_png(ProjectSettings.globalize_path(TileArt.atlas_png(tile_px)))
		var file := FileAccess.open(TileArt.atlas_json(tile_px), FileAccess.WRITE)
		file.store_string(JSON.stringify(TileArt.index(), "\t", false) + "\n")
		file.close()
		var preview := atlas.duplicate() as Image
		var factor := PREVIEW_PX / tile_px
		preview.resize(atlas.get_width() * factor, atlas.get_height() * factor, Image.INTERPOLATE_NEAREST)
		preview.save_png(ProjectSettings.globalize_path(PREVIEW % tile_px))
	quit()
