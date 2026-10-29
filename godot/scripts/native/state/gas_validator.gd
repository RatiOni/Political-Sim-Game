class_name GasValidator
extends RefCounted


static func validate(state: GameState, errors: Array[String]) -> void:
	var g := state.foreign.gas
	if g == null:
		errors.append("gas contract is missing")
		return
	for field in GasContract.FLOAT_FIELDS:
		var x := float(g.get(field))
		if not is_finite(x) or x < 0.0:
			errors.append("gas %s is impossible" % field)
	for field in ["take_or_pay", "cut", "sabotage"]:
		if float(g.get(field)) > 1.0:
			errors.append("gas %s is above one" % field)
	if not g.is_active():
		return
	if state.world_country(g.supplier_id) == null:
		errors.append("gas supplier '%s' is unknown" % g.supplier_id)
	if g.price <= 0.0:
		errors.append("gas price must be positive")
	if g.storage > g.storage_capacity + 0.000001 or g.storage_capacity > g.storage_target + 0.000001:
		errors.append("gas storage exceeds its capacity")
	for field in ["cut_until", "last_cut_turn", "last_demand_turn", "storage_started", "second_line_started", "last_renegotiated"]:
		var at := int(g.get(field))
		if at < -1 or (field != "cut_until" and at > state.turn):
			errors.append("gas %s is out of time" % field)
	for field in ["demands", "threats", "cuts"]:
		if int(g.get(field)) < 0:
			errors.append("gas %s is negative" % field)
	if not g.threat.is_empty():
		var made := int(g.threat.get("turn", -1))
		if made < 0 or made > state.turn or int(g.threat.get("due", -1)) <= made \
				or not StateValidator._foreign_unit(g.threat.get("share", -1.0)):
			errors.append("gas threat is impossible")
	if g.paid.size() > GasContract.PAID_MONTHS or g.paid.any(func(p: float) -> bool: return not is_finite(p) or p < 0.0):
		errors.append("gas payment history is impossible")
	for c in g.concessions:
		if not (c in GasSim.catalog().get("concessions", [])):
			errors.append("unknown gas concession '%s'" % c)
	if state.foreign.reached.has("union_member") and g.price > GasSim.union_cap(g) + 0.000001:
		errors.append("gas price breaks the Union cap")

