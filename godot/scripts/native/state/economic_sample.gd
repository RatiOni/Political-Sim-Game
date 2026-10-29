extends RefCounted
## One monthly reading of the economy, for history charts.

var turn: int = 0
var year: int = 0
var month: int = 1
var growth: float = 0.0
var inflation: float = 0.0
var unemployment: float = 0.0
var debt: float = 0.0
var gdp: float = 0.0
var revenue: float = 0.0
var expenditure: float = 0.0
var approval: float = 0.0
var stability: float = 0.0


func to_dict() -> Dictionary:
	return {"turn": turn, "year": year, "month": month, "growth": growth, "inflation": inflation,
		"unemployment": unemployment, "debt": debt, "gdp": gdp, "revenue": revenue,
		"expenditure": expenditure, "approval": approval, "stability": stability}


static func from_dict(data: Variant) -> RefCounted:
	if not (data is Dictionary):
		return null
	var s: RefCounted = (load("res://scripts/native/state/economic_sample.gd") as GDScript).new()
	s.turn = int(data.get("turn", 0))
	s.year = int(data.get("year", 0))
	s.month = int(data.get("month", 1))
	for key in ["growth", "inflation", "unemployment", "debt", "gdp", "revenue", "expenditure", "approval", "stability"]:
		s.set(key, float(data.get(key, 0.0)))
	return s
