class_name MinistryState
extends RefCounted

## Typed mirror of models/ministry.py: one cabinet department's persistent
## operating condition. GameFactory does not populate these yet (see
## game_factory.gd header note) — the seeding/recalculation logic lives in
## engine/ministries.py, which is out of Task 2's scope.

var portfolio: String
var baseline_funding: float = 0.0
var funding: float = 0.0
var funding_ratio: float = 1.0
var workload: float = 0.0
var capacity: float = 0.0
var delivery: float = 1.0
var backlog: float = 0.0
var months_overloaded: int = 0
var workload_breakdown: Dictionary = {}   # String label -> float


func load_ratio() -> float:
	return workload / maxf(0.01, capacity)


func status_label() -> String:
	if delivery >= 0.90 and backlog < 0.25:
		return "Effective"
	if delivery >= 0.72 and backlog < 1.0:
		return "Stretched"
	if delivery >= 0.50 and backlog < 2.5:
		return "Overloaded"
	return "Failing"


func to_dict() -> Dictionary:
	return {
		"portfolio": portfolio,
		"baseline_funding": baseline_funding,
		"funding": funding,
		"funding_ratio": funding_ratio,
		"workload": workload,
		"capacity": capacity,
		"delivery": delivery,
		"backlog": backlog,
		"months_overloaded": months_overloaded,
		"workload_breakdown": workload_breakdown.duplicate(true),
	}


static func from_dict(data: Dictionary) -> MinistryState:
	if not (data is Dictionary):
		push_error("MinistryState.from_dict: expected a Dictionary, got %s" % [data])
		return null
	var m := MinistryState.new()
	m.portfolio = String(data.get("portfolio", ""))
	m.baseline_funding = float(data.get("baseline_funding", 0.0))
	m.funding = float(data.get("funding", 0.0))
	m.funding_ratio = float(data.get("funding_ratio", 1.0))
	m.workload = float(data.get("workload", 0.0))
	m.capacity = float(data.get("capacity", 0.0))
	m.delivery = float(data.get("delivery", 1.0))
	m.backlog = float(data.get("backlog", 0.0))
	m.months_overloaded = _int_field(data, "months_overloaded", 0)
	var breakdown_data: Variant = data.get("workload_breakdown", {})
	m.workload_breakdown = breakdown_data.duplicate(true) if breakdown_data is Dictionary else {}
	return m


## JSON boundary: Godot parses every JSON number as float, so a whole-number
## float must read back as an int wherever an int field is expected.
static func _int_field(data: Dictionary, key: String, fallback: int) -> int:
	var v: Variant = data.get(key, fallback)
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT and v == floorf(v) and absf(v) <= 9007199254740992.0:
		return int(v)
	return fallback
