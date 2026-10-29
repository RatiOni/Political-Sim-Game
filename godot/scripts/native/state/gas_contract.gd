class_name GasContract
extends RefCounted


const PAID_MONTHS := 12
const FLOAT_FIELDS := ["price", "reference_price", "contracted_volume", "annual_demand", "arrears",
	"take_or_pay", "cut", "sabotage", "storage", "storage_capacity", "storage_target",
	"second_line_volume", "spot_pending"]
const INT_FIELDS := ["term_end", "cut_until", "last_cut_turn", "last_demand_turn", "storage_started",
	"second_line_started", "last_renegotiated", "demands", "threats", "cuts"]
const FLOW_FIELDS := ["demand", "delivered", "drawn", "injected", "bill", "shortfall", "severity"]

var supplier_id: String = ""
var price: float = 0.0
var reference_price: float = 0.0
var contracted_volume: float = 0.0
var annual_demand: float = 0.0
var arrears: float = 0.0
var term_end: int = 0
var take_or_pay: float = 0.0
var cut: float = 0.0
var cut_until: int = -1
var last_cut_turn: int = -1
var sabotage: float = 0.0
var threat: Dictionary = {}
var last_demand_turn: int = -1
var storage: float = 0.0
var storage_capacity: float = 0.0
var storage_target: float = 0.0
var storage_started: int = -1
var second_line_volume: float = 0.0
var second_line_started: int = -1
var spot_pending: float = 0.0
var last_renegotiated: int = -1
var demands: int = 0
var threats: int = 0
var cuts: int = 0
var concessions: Array[String] = []
var paid: Array[float] = []
var last_flow: Dictionary = {}


func is_active() -> bool:
	return supplier_id != "" and annual_demand > 0.0


func to_dict() -> Dictionary:
	var out := {"supplier_id": supplier_id, "threat": threat.duplicate(),
		"concessions": Array(concessions), "paid": Array(paid), "last_flow": last_flow.duplicate()}
	for field in FLOAT_FIELDS + INT_FIELDS:
		out[field] = get(field)
	return out


static func from_dict(data: Variant) -> GasContract:
	var out := GasContract.new()
	if data == null:
		return out
	if not (data is Dictionary):
		push_error("GasContract.from_dict: expected a Dictionary")
		return null
	var d: Dictionary = data
	for field in ["threat", "last_flow"]:
		if not (d.get(field, {}) is Dictionary):
			push_error("GasContract.from_dict: malformed %s" % field)
			return null
	for field in ["concessions", "paid"]:
		if not (d.get(field, []) is Array):
			push_error("GasContract.from_dict: malformed %s" % field)
			return null
	out.supplier_id = String(d.get("supplier_id", ""))
	for field in FLOAT_FIELDS:
		out.set(field, float(d.get(field, out.get(field))))
	for field in INT_FIELDS:
		out.set(field, int(d.get(field, out.get(field))))
	var raw_threat: Dictionary = d.get("threat", {})
	if not raw_threat.is_empty():
		out.threat = {"turn": int(raw_threat.get("turn", 0)), "due": int(raw_threat.get("due", 0)),
			"share": float(raw_threat.get("share", 0.0))}
	for c in d.get("concessions", []):
		out.concessions.append(String(c))
	for p in d.get("paid", []):
		out.paid.append(float(p))
	var flow: Dictionary = d.get("last_flow", {})
	for key in FLOW_FIELDS:
		if flow.has(key):
			out.last_flow[key] = float(flow[key])
	return out
