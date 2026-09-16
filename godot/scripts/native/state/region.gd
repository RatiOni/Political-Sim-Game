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
