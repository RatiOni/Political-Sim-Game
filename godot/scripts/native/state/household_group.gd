class_name HouseholdGroupState
extends RefCounted

## Typed mirror of models/household.py: one social group's lived economic
## condition inside one region. GameFactory does not populate these yet
## (see game_factory.gd header note) — the seeding logic lives in
## engine/households.py, which is out of Task 2's scope.

var id: String
var group_id: String
var region_id: String
var population_share: float
var nominal_income_index: float = 1.0
var living_cost_index: float = 1.0
var real_income_index: float = 1.0
var employment_security: float = 0.7
var service_access: float = 0.6
var hardship: float = 0.3
var confidence: float = 0.5
var last_real_income_index: float = 1.0


func status_label() -> String:
	if hardship >= 0.68:
		return "Severe hardship"
	if hardship >= 0.48:
		return "Under strain"
	if hardship >= 0.30:
		return "Insecure"
	return "Secure"


func to_dict() -> Dictionary:
	return {
		"id": id,
		"group_id": group_id,
		"region_id": region_id,
		"population_share": population_share,
		"nominal_income_index": nominal_income_index,
		"living_cost_index": living_cost_index,
		"real_income_index": real_income_index,
		"employment_security": employment_security,
		"service_access": service_access,
		"hardship": hardship,
		"confidence": confidence,
		"last_real_income_index": last_real_income_index,
	}


static func from_dict(data: Dictionary) -> HouseholdGroupState:
	if not (data is Dictionary):
		push_error("HouseholdGroupState.from_dict: expected a Dictionary, got %s" % [data])
		return null
	for key in ["population_share", "nominal_income_index", "living_cost_index",
			"real_income_index", "employment_security", "service_access", "hardship",
			"confidence", "last_real_income_index"]:
		if data.has(key):
			var value: Variant = data[key]
			if not (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) or not is_finite(float(value)):
				push_error("HouseholdGroupState.from_dict: malformed numeric field '%s'" % [key])
				return null
	var h := HouseholdGroupState.new()
	h.id = String(data.get("id", ""))
	h.group_id = String(data.get("group_id", ""))
	h.region_id = String(data.get("region_id", ""))
	h.population_share = float(data.get("population_share", 0.0))
	h.nominal_income_index = float(data.get("nominal_income_index", 1.0))
	h.living_cost_index = float(data.get("living_cost_index", 1.0))
	h.real_income_index = float(data.get("real_income_index", 1.0))
	h.employment_security = float(data.get("employment_security", 0.7))
	h.service_access = float(data.get("service_access", 0.6))
	h.hardship = float(data.get("hardship", 0.3))
	h.confidence = float(data.get("confidence", 0.5))
	h.last_real_income_index = float(data.get("last_real_income_index", 1.0))
	return h
