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
