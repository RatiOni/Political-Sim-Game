class_name RegionState
extends RefCounted

## Typed mirror of models/region.py: RegionState + RegionalProgram. GameFactory
## does not populate these yet (see game_factory.gd header note) — the
## authored profiles and seeding logic live in content/regions.py and
## engine/regions.py, which are out of Task 2's scope (Ardenia is the only
## country with an authored regional layer; countries without one keep an
## empty dict in the Python reference too).

class RegionalProgram extends RefCounted:
	## A funded, time-limited government intervention in one region.
	var id: String
	var program_id: String
	var region_id: String
	var started_turn: int
	var duration: int
	var monthly_cost: float
	var months_active: int = 0


	func to_dict() -> Dictionary:
		return {
			"id": id,
			"program_id": program_id,
			"region_id": region_id,
			"started_turn": started_turn,
			"duration": duration,
			"monthly_cost": monthly_cost,
			"months_active": months_active,
		}


	static func from_dict(data: Dictionary) -> RegionalProgram:
		if not (data is Dictionary):
			push_error("RegionalProgram.from_dict: expected a Dictionary, got %s" % [data])
			return null
		var p := RegionalProgram.new()
		p.id = String(data.get("id", ""))
		p.program_id = String(data.get("program_id", ""))
		p.region_id = String(data.get("region_id", ""))
		p.started_turn = RegionState._int_field(data, "started_turn", 0)
		p.duration = RegionState._int_field(data, "duration", 0)
		p.monthly_cost = float(data.get("monthly_cost", 0.0))
		p.months_active = RegionState._int_field(data, "months_active", 0)
		return p


var id: String
var unemployment: float
var state_reach: float
var pressure: float
var control: String = "state"
var issue_id: String = ""
## Absolute local shares plus the national polling shares they were last
## reconciled against (see models/region.py's docstring).
var party_support: Dictionary = {}     # String faction_id -> float
var support_anchor: Dictionary = {}    # String faction_id -> float


func to_dict() -> Dictionary:
	return {
		"id": id,
		"unemployment": unemployment,
		"state_reach": state_reach,
		"pressure": pressure,
		"control": control,
		"issue_id": issue_id,
		"party_support": party_support.duplicate(true),
		"support_anchor": support_anchor.duplicate(true),
	}


static func from_dict(data: Dictionary) -> RegionState:
	if not (data is Dictionary):
		push_error("RegionState.from_dict: expected a Dictionary, got %s" % [data])
		return null
	var r := RegionState.new()
	r.id = String(data.get("id", ""))
	r.unemployment = float(data.get("unemployment", 0.0))
	r.state_reach = float(data.get("state_reach", 0.0))
	r.pressure = float(data.get("pressure", 0.0))
	r.control = String(data.get("control", "state"))
	r.issue_id = String(data.get("issue_id", ""))
	var party_support_data: Variant = data.get("party_support", {})
	r.party_support = party_support_data.duplicate(true) if party_support_data is Dictionary else {}
	var anchor_data: Variant = data.get("support_anchor", {})
	r.support_anchor = anchor_data.duplicate(true) if anchor_data is Dictionary else {}
	return r


## JSON boundary: Godot parses every JSON number as float, so a whole-number
## float must read back as an int wherever an int field is expected.
static func _int_field(data: Dictionary, key: String, fallback: int) -> int:
	var v: Variant = data.get(key, fallback)
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT and v == floorf(v) and absf(v) <= 9007199254740992.0:
		return int(v)
	return fallback
