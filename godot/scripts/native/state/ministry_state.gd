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
