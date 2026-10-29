class_name GasSim
extends RefCounted


const PAYMENT_SHARE := 0.85
const WINTER_WEIGHT := 1.5
const UNION_PRICE_SHARE := 0.7


static func catalog() -> Dictionary:
	var data: Variant = ContentRepository.load_all().get("catalogs", {}).get("energy", {})
	return data if data is Dictionary else {}


static func season_weight(month: int) -> float:
	var weights: Array = catalog().get("season", [])
	return float(weights[month - 1]) if weights.size() == 12 else 1.0


static func line(key: String, fields: Dictionary = {}) -> String:
	return String(catalog().get("lines", {}).get(key, key)).format(fields)


static func gas(state: GameState) -> GasContract:
	return null if state.foreign == null else state.foreign.gas


static func is_active(state: GameState) -> bool:
	var g := gas(state)
	return g != null and g.is_active()


static func union_member(state: GameState) -> bool:
	return state.foreign != null and state.foreign.reached.has("union_member")


static func union_cap(g: GasContract) -> float:
	return g.reference_price * UNION_PRICE_SHARE


static func ensure(state: GameState) -> bool:
	var g := state.foreign.gas
	if g.is_active():
		return false
	var raw: Variant = catalog().get("contracts", {}).get(state.country.id, null)
	if not (raw is Dictionary):
		return false
	var row: Dictionary = raw
	if state.world_country(String(row.get("supplier_id", ""))) == null:
		return false
	g.supplier_id = String(row["supplier_id"])
	g.price = float(row["price"])
	g.reference_price = g.price
	g.annual_demand = float(row["annual_demand"])
	g.contracted_volume = float(row["contracted_volume"])
	g.arrears = float(row["arrears"])
	g.term_end = int(row["term_end"])
	g.take_or_pay = float(row["take_or_pay"])
	g.paid.clear()
	for _i in range(GasContract.PAID_MONTHS):
		g.paid.append(g.price * g.contracted_volume * PAYMENT_SHARE / float(GasContract.PAID_MONTHS))
	write_share(state)
	return true


static func write_share(state: GameState) -> void:
	var g := state.foreign.gas
	if not g.is_active() or not (g.supplier_id in ForeignSim.power_ids()):
		return
	var total := g.contracted_volume + g.second_line_volume
	state.foreign.gas_share[g.supplier_id] = 0.0 if total <= 0.0 else clampf(g.contracted_volume / total, 0.0, 1.0)


static func cap_to_union(state: GameState) -> void:
	var g := state.foreign.gas
	if g.is_active():
		g.price = minf(g.price, union_cap(g))
