extends SceneTree

const PREVIEW := "res://../.scratch/tile_atlas_4x.png"
const PREVIEW_SCALE := 4


func _init() -> void:
	var atlas := TileArt.build_atlas()
	atlas.save_png(ProjectSettings.globalize_path(TileArt.ATLAS_PNG))
	var file := FileAccess.open(TileArt.ATLAS_JSON, FileAccess.WRITE)
	file.store_string(JSON.stringify(TileArt.index(), "\t", false) + "\n")
	file.close()
	var preview := atlas.duplicate() as Image
	preview.resize(atlas.get_width() * PREVIEW_SCALE, atlas.get_height() * PREVIEW_SCALE, Image.INTERPOLATE_NEAREST)
	preview.save_png(ProjectSettings.globalize_path(PREVIEW))
	quit()
