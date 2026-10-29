class_name ForeignState
extends RefCounted


var powers: Dictionary = {}
var gas_share: Dictionary = {}
var reached: Dictionary = {}
var members: Dictionary = {}
var isf: Dictionary = default_isf()
var western_qualifying_months: int = 0
var union_left_turn: int = -1
var hostile_log: Array = []
var seeded: bool = false


static func default_isf() -> Dictionary:
	return {"reviews_held": 0, "passed": 0, "failed": 0, "renegotiations": 0,
		"suspended": false, "disbursed": 0.0, "last_review_turn": -1, "last_result": ""}


func to_dict() -> Dictionary:
	return {
		"powers": powers.duplicate(true),
		"gas_share": gas_share.duplicate(),
		"reached": reached.duplicate(),
		"members": members.duplicate(true),
		"isf": isf.duplicate(),
		"western_qualifying_months": western_qualifying_months,
		"union_left_turn": union_left_turn,
		"hostile_log": hostile_log.duplicate(true),
		"seeded": seeded,
	}


static func from_dict(data: Variant) -> ForeignState:
	var out := ForeignState.new()
	if data == null:
		return out
	if not (data is Dictionary):
		push_error("ForeignState.from_dict: expected a Dictionary")
		return null
	var d: Dictionary = data
	for field in ["powers", "gas_share", "reached", "members", "isf"]:
		if not (d.get(field, {}) is Dictionary):
			push_error("ForeignState.from_dict: malformed %s" % field)
			return null
	var power_rows: Dictionary = d.get("powers", {})
	for id in power_rows:
		var row: Variant = power_rows[id]
		if not (row is Dictionary):
			push_error("ForeignState.from_dict: malformed power '%s'" % id)
			return null
		out.powers[String(id)] = {"dependence": float(row.get("dependence", 0.0)),
			"commitment": float(row.get("commitment", 0.0)), "leverage": float(row.get("leverage", 0.0))}
	var shares: Dictionary = d.get("gas_share", {})
	for id in shares:
		out.gas_share[String(id)] = float(shares[id])
	var milestones: Dictionary = d.get("reached", {})
	for id in milestones:
		out.reached[String(id)] = int(milestones[id])
	var blocs: Dictionary = d.get("members", {})
	for id in blocs:
		if not (blocs[id] is Array):
			push_error("ForeignState.from_dict: malformed members of '%s'" % id)
			return null
		var ids: Array = []
		for country_id in blocs[id]:
			ids.append(String(country_id))
		out.members[String(id)] = ids
	var isf_data: Dictionary = d.get("isf", {})
	for key in out.isf.keys():
		if not isf_data.has(key):
			continue
		match typeof(out.isf[key]):
			TYPE_INT:
				out.isf[key] = int(isf_data[key])
			TYPE_FLOAT:
				out.isf[key] = float(isf_data[key])
			TYPE_BOOL:
				out.isf[key] = bool(isf_data[key])
			_:
				out.isf[key] = String(isf_data[key])
	out.western_qualifying_months = int(d.get("western_qualifying_months", 0))
	out.union_left_turn = int(d.get("union_left_turn", -1))
	var entries: Variant = d.get("hostile_log", [])
	if not (entries is Array):
		push_error("ForeignState.from_dict: malformed hostile_log")
		return null
	for entry in entries:
		if not (entry is Dictionary):
			push_error("ForeignState.from_dict: malformed hostile_log entry")
			return null
		out.hostile_log.append({"turn": int(entry.get("turn", 0)), "actor": String(entry.get("actor", "")),
			"relation": float(entry.get("relation", 0.0)), "economy": float(entry.get("economy", 0.0)),
			"stability": float(entry.get("stability", 0.0))})
	out.seeded = bool(d.get("seeded", false))
	return out
