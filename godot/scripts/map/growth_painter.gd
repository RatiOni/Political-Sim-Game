class_name GrowthPainter
extends RefCounted

const FLIP_SECONDS := 1.0
const SMOKE_CYCLE_SECONDS := 0.4
const SMOKE_FRAMES := 3
const SMOKE_SECONDS := SMOKE_CYCLE_SECONDS / SMOKE_FRAMES
const PLUME_ROLES: Array[String] = ["fire", "smoke_mid", "smoke_top"]
const NONE := Vector2i(-1, -1)


static func apply(map: ArdeniaMap, all_targets: Dictionary, overlay: Dictionary, animate: bool) -> void:
	map.growth_desired = _desired(all_targets, overlay)
	map.smoke_desired = _smoke_cells(overlay)
	_paint_smoke(map)
	_sync_smoke(map)
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


static func step_smoke(map: ArdeniaMap) -> void:
	map.smoke_frame = (map.smoke_frame + 1) % SMOKE_FRAMES
	_paint_smoke(map)


static func paint(map: ArdeniaMap, cell: Vector2i) -> void:
	var coords := _coords(map, cell)
	if coords == NONE:
		map.growth_layer.erase_cell(cell)
	else:
		map.growth_layer.set_cell(cell, 0, coords)


static func _paint_smoke(map: ArdeniaMap) -> void:
	for cell in map.smoke_layer.get_used_cells():
		if not map.smoke_desired.has(cell):
			map.smoke_layer.erase_cell(cell)
	for cell in map.smoke_desired:
		var entry: Dictionary = map.smoke_desired[cell]
		var at: Array = TileArt.index()["%s_%d" % [entry["role"], (map.smoke_frame + entry["phase"]) % SMOKE_FRAMES]]
		map.smoke_layer.set_cell(cell, 0, Vector2i(at[0], at[1]))


static func _smoke_cells(overlay: Dictionary) -> Dictionary:
	var out := {}
	for role in range(PLUME_ROLES.size() - 1, -1, -1):
		for signs in overlay["trouble"].values():
			for base in signs["smoke"]:
				var column := GrowthLayers.plume(base)
				if role < column.size():
					out[column[role]] = {"role": PLUME_ROLES[role], "phase": GrowthLayers.stable_hash(base) % SMOKE_FRAMES}
	return out


static func _sync_smoke(map: ArdeniaMap) -> void:
	if map.smoke_desired.is_empty():
		map.smoke_timer.stop()
	elif map.smoke_timer.is_stopped() and map.is_inside_tree():
		map.smoke_timer.start()


static func _coords(map: ArdeniaMap, cell: Vector2i) -> Vector2i:
	if not map.growth_desired.has(cell):
		return NONE
	var entry: Dictionary = map.growth_desired[cell]
	var sprite: String = entry["sprite"]
	if entry["lit"] and map.is_dusk():
		sprite = "house_lit"
	var at: Array = TileArt.index()[sprite]
	return Vector2i(at[0], at[1])


static func _desired(all_targets: Dictionary, overlay: Dictionary) -> Dictionary:
	var out := {}
	for cell in overlay["routes"]:
		out[cell] = {"sprite": overlay["routes"][cell], "lit": false}
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
		var signs: Dictionary = overlay["trouble"].get(region_id, {})
		if not signs.get("dim", false):
			for cell in targets["lit_cells"]:
				out[cell]["lit"] = true
		for cell in signs.get("barricade", []):
			out[cell] = {"sprite": "barricade", "lit": false}
	return out
