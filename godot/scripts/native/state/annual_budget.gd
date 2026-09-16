class_name AnnualBudget
extends RefCounted

## Typed mirror of models/budget.py: one fiscal year's voted structural
## appropriations. GameFactory does not populate `active_budget` yet (see
## game_factory.gd header note) — the seeding/voting logic lives in
## engine/budget.py, which is out of Task 2's scope.

var year: int
var allocations: Dictionary = {}   # String portfolio -> float
var status: String = "draft"       # draft | proposed | approved | active | rejected | continuing
var source: String = "inherited"   # inherited | player | government_ai | continuing
var proposed_by: String = ""
var proposed_turn: int = -1
var forecast_revenue: float = 0.0
var votes_for: int = 0
var votes_against: int = 0
var lobbying_bonus: Dictionary = {}   # String faction_id -> float
## Mid-year supplementary appropriations, kept separate from `allocations` on
## purpose — see models/budget.py's docstring for why.
var supplements: Dictionary = {}      # String portfolio -> float


func expenditure() -> float:
	var total := 0.0
	for value in allocations.values():
		total += float(value)
	return total


func portfolio_supplement(portfolio: String) -> float:
	return float(supplements.get(portfolio, 0.0))


func forecast_balance() -> float:
	return forecast_revenue - expenditure()
