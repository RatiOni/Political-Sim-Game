class_name AnnualBudget
extends RefCounted


var year: int
var allocations: Dictionary = {}
var status: String = "draft"
var source: String = "inherited"
var proposed_by: String = ""
var proposed_turn: int = -1
var forecast_revenue: float = 0.0
var votes_for: int = 0
var votes_against: int = 0
var lobbying_bonus: Dictionary = {}
var supplements: Dictionary = {}
var emergency_months: int = 0
var economy_basis: float = 0.0


func expenditure() -> float:
	var keys := allocations.keys()
	keys.sort()
	var total := 0.0
	for key in keys:
		total += float(allocations[key])
	return total


func portfolio_supplement(portfolio: String) -> float:
	return float(supplements.get(portfolio, 0.0))


func forecast_balance() -> float:
	return forecast_revenue - expenditure()


func to_dict() -> Dictionary:
	return {
		"year": year,
		"allocations": allocations.duplicate(true),
		"status": status,
		"source": source,
		"emergency_months": emergency_months,
		"economy_basis": economy_basis,
		"proposed_by": proposed_by,
		"proposed_turn": proposed_turn,
		"forecast_revenue": forecast_revenue,
		"votes_for": votes_for,
		"votes_against": votes_against,
		"lobbying_bonus": lobbying_bonus.duplicate(true),
		"supplements": supplements.duplicate(true),
	}


static func from_dict(data: Dictionary) -> AnnualBudget:
	if not (data is Dictionary):
		push_error("AnnualBudget.from_dict: expected a Dictionary, got %s" % [data])
		return null
	var b := AnnualBudget.new()
	b.year = _int_field(data, "year", 0)
	var allocations_data: Variant = data.get("allocations", {})
	b.allocations = allocations_data.duplicate(true) if allocations_data is Dictionary else {}
	b.status = String(data.get("status", "draft"))
	b.source = String(data.get("source", "inherited"))
	b.emergency_months = maxi(0, _int_field(data, "emergency_months", 0))
	b.economy_basis = maxf(0.0, float(data.get("economy_basis", 0.0)))
	b.proposed_by = String(data.get("proposed_by", ""))
	b.proposed_turn = _int_field(data, "proposed_turn", -1)
	b.forecast_revenue = float(data.get("forecast_revenue", 0.0))
	b.votes_for = _int_field(data, "votes_for", 0)
	b.votes_against = _int_field(data, "votes_against", 0)
	var lobbying_data: Variant = data.get("lobbying_bonus", {})
	b.lobbying_bonus = lobbying_data.duplicate(true) if lobbying_data is Dictionary else {}
	var supplements_data: Variant = data.get("supplements", {})
	if data.has("supplements") and not (supplements_data is Dictionary):
		push_error("AnnualBudget.from_dict: malformed 'supplements', expected a Dictionary, got %s" % [supplements_data])
		return null
	b.supplements = supplements_data.duplicate(true)
	return b


static func _int_field(data: Dictionary, key: String, fallback: int) -> int:
	var v: Variant = data.get(key, fallback)
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT and v == floorf(v) and absf(v) <= 9007199254740992.0:
		return int(v)
	return fallback
