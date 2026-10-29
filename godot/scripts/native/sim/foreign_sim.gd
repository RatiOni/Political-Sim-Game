class_name ForeignSim
extends RefCounted


const UNION_LOCKS := ["concert_agreement", "meridian_guarantee"]
const UNION_LOCKED_BLOCS := ["concert", "meridian"]


static func catalog() -> Dictionary:
	var data: Variant = ContentRepository.load_all().get("catalogs", {}).get("foreign_orientation", {})
	return data if data is Dictionary else {}


static func _ids(section: String) -> Array[String]:
	var out: Array[String] = []
	for row in catalog().get(section, []):
		out.append(String(row.get("id", "")))
	return out


static func _row(section: String, id: String) -> Dictionary:
	for row in catalog().get(section, []):
		if String(row.get("id", "")) == id:
			return row
	return {}


static func power_ids() -> Array[String]:
	return _ids("powers")


static func milestone_ids() -> Array[String]:
	return _ids("milestones")


static func bloc_ids() -> Array[String]:
	return _ids("blocs")


static func power(id: String) -> Dictionary:
	return _row("powers", id)


static func milestone(id: String) -> Dictionary:
	return _row("milestones", id)


static func bloc(id: String) -> Dictionary:
	return _row("blocs", id)


static func milestone_name(id: String) -> String:
	return String(milestone(id).get("name", id))


static func ensure(state: GameState) -> void:
	var f := state.foreign
	if f.seeded:
		return
	for p in catalog().get("powers", []):
		f.gas_share[String(p["id"])] = float(p.get("gas_share", 0.0))
	for m in catalog().get("milestones", []):
		if bool(m.get("starts_reached", false)):
			f.reached[String(m["id"])] = state.turn
	for b in catalog().get("blocs", []):
		var ids: Array = []
		for country_id in b.get("seed_members", []):
			if state.world_country(String(country_id)) != null:
				ids.append(String(country_id))
		f.members[String(b["id"])] = ids
	f.isf = ForeignState.default_isf()
	f.seeded = true
