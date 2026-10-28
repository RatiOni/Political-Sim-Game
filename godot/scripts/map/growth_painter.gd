class_name GrowthPainter
extends RefCounted

const FLIP_SECONDS := 1.0
const NONE := Vector2i(-1, -1)


static func apply(map: ArdeniaMap, all_targets: Dictionary, animate: bool) -> void:
	map.growth_desired = _desired(all_targets)
	if map.growth_tween != null and map.growth_tween.is_valid():
		map.growth_tween.kill()
	var changed: Array[Vector2i] = []
	var cells := {}
	for cell in map.growth_layer.get_used_cells():
		cells[cell] = true
	for cell in map.growth_desired:
		cells[cell] = true
	for cell in cells:
		if map.growth_layer.get_cell_atlas_coords(cell) != _coords(map, cell):
			changed.append(cell)
	if not animate or changed.is_empty() or not map.is_inside_tree():
		for cell in changed:
			paint(map, cell)
		return
	var ordered := GrowthLayers.hash_order(changed, 3)
	var flipped := {"count": 0}
	map.growth_tween = map.create_tween()
	map.growth_tween.tween_method(func(progress: float) -> void:
		var due := mini(ordered.size(), ceili(progress * ordered.size()))
		while flipped["count"] < due:
			paint(map, ordered[flipped["count"]])
			flipped["count"] += 1, 0.0, 1.0, FLIP_SECONDS)


static func refresh_lights(map: ArdeniaMap) -> void:
	for cell in map.growth_desired:
		if map.growth_desired[cell]["lit"] and map.growth_layer.get_cell_atlas_coords(cell) != NONE:
			paint(map, cell)


static func paint(map: ArdeniaMap, cell: Vector2i) -> void:
	var coords := _coords(map, cell)
	if coords == NONE:
		map.growth_layer.erase_cell(cell)
	else:
		map.growth_layer.set_cell(cell, 0, coords)


static func _coords(map: ArdeniaMap, cell: Vector2i) -> Vector2i:
	if not map.growth_desired.has(cell):
		return NONE
	var entry: Dictionary = map.growth_desired[cell]
	var sprite: String = "house_lit" if entry["lit"] and map.is_dusk() else entry["sprite"]
	var at: Array = TileArt.index()[sprite]
	return Vector2i(at[0], at[1])


static func _desired(all_targets: Dictionary) -> Dictionary:
	var out := {}
	for region_id in all_targets:
		var targets: Dictionary = all_targets[region_id]
		for cell in targets["farm_cells"]:
			out[cell] = {"sprite": TileArt.variant_key("farm", GrowthLayers.stable_hash(cell) % TileArt.VARIANTS), "lit": false}
		for cell in targets["fallow_cells"]:
			out[cell] = {"sprite": TileArt.variant_key("fallow", GrowthLayers.stable_hash(cell) % TileArt.VARIANTS), "lit": false}
		for cell in targets["town_cells"]:
			out[cell] = {"sprite": "house", "lit": false}
		for cell in targets["tower_cells"]:
			out[cell] = {"sprite": "tower", "lit": false}
		for cell in targets["capital_cells"]:
			out[cell] = {"sprite": "capital", "lit": false}
		for cell in targets["lit_cells"]:
			out[cell]["lit"] = true
	return out
