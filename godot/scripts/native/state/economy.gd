class_name Economy
extends RefCounted

## Typed mirror of models/economy.py: Sector, Budget, Economy. Loan isn't
## ported as a typed class — no country starts a campaign with one, and the
## loan mechanics (engine/diplomacy.py: op_foreign_loan) are out of Task 2's
## scope — so `loans` stays a plain empty Array reserved for a later task.

class Sector extends RefCounted:
	var id: String
	var name: String
	var gdp_share: float
	var growth_rate: float
	var employment_share: float
	var aligned_faction_ids: Array[String] = []

	static func from_json(data: Dictionary) -> Sector:
		var s := Sector.new()
		s.id = String(data.get("id", ""))
		s.name = String(data.get("name", ""))
		s.gdp_share = float(data.get("gdp_share", 0.0))
		s.growth_rate = float(data.get("growth_rate", 0.0))
		s.employment_share = float(data.get("employment_share", 0.0))
		for fid in data.get("aligned_faction_ids", []):
			s.aligned_faction_ids.append(String(fid))
		return s


	func to_dict() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"gdp_share": gdp_share,
			"growth_rate": growth_rate,
			"employment_share": employment_share,
			"aligned_faction_ids": aligned_faction_ids.duplicate(),
		}


	static func from_dict(data: Dictionary) -> Sector:
		if not (data is Dictionary):
			push_error("Sector.from_dict: expected a Dictionary, got %s" % [data])
			return null
		var s := Sector.new()
		s.id = String(data.get("id", ""))
		s.name = String(data.get("name", ""))
		s.gdp_share = float(data.get("gdp_share", 0.0))
		s.growth_rate = float(data.get("growth_rate", 0.0))
		s.employment_share = float(data.get("employment_share", 0.0))
		var faction_ids: Variant = data.get("aligned_faction_ids", [])
		if faction_ids is Array:
			for fid in faction_ids:
				s.aligned_faction_ids.append(String(fid))
		return s


class Budget extends RefCounted:
	var revenue: float
	var expenditure: float

	func balance() -> float:
		return revenue - expenditure

	func is_deficit() -> bool:
		return balance() < 0.0

	static func from_json(data: Dictionary) -> Budget:
		var b := Budget.new()
		b.revenue = float(data.get("revenue", 0.0))
		b.expenditure = float(data.get("expenditure", 0.0))
		return b


	func to_dict() -> Dictionary:
		return {"revenue": revenue, "expenditure": expenditure}


	static func from_dict(data: Dictionary) -> Budget:
		if not (data is Dictionary):
			push_error("Budget.from_dict: expected a Dictionary, got %s" % [data])
			return null
		var b := Budget.new()
		b.revenue = float(data.get("revenue", 0.0))
		b.expenditure = float(data.get("expenditure", 0.0))
		return b


var gdp: float
var growth_rate: float
var inflation: float
var unemployment: float
var public_debt_pct: float
var budget: Budget
var sectors: Array[Sector] = []

## Structural baselines — seeded from the headline values on construction,
## mirroring Python's Economy.__post_init__.
var structural_growth_rate: float
var structural_unemployment: float
var structural_inflation: float
var structural_revenue: float
var structural_expenditure: float

var workforce_quality: float = 0.5
var trade_revenue_contribution: float = 0.0
var loans: Array = []


func sector_by_id(sector_id: String) -> Sector:
	for s in sectors:
		if s.id == sector_id:
			return s
	return null


func gdp_per_capita(population: int) -> float:
	if population == 0:
		return 0.0
	return (gdp * 1000000.0) / population


func total_debt_service() -> float:
	return 0.0   # no Loan class ported yet — see header note


static func from_json(data: Dictionary) -> Economy:
	var e := Economy.new()
	e.gdp = float(data.get("gdp", 0.0))
	e.growth_rate = float(data.get("growth_rate", 0.0))
	e.inflation = float(data.get("inflation", 0.0))
	e.unemployment = float(data.get("unemployment", 0.0))
	e.public_debt_pct = float(data.get("public_debt_pct", 0.0))
	e.budget = Budget.from_json(data.get("budget", {}))
	for sector_data in data.get("sectors", []):
		e.sectors.append(Sector.from_json(sector_data))

	e.structural_growth_rate = e.growth_rate
	e.structural_unemployment = e.unemployment
	e.structural_inflation = e.inflation
	e.structural_revenue = e.budget.revenue
	e.structural_expenditure = e.budget.expenditure
	return e


func to_dict() -> Dictionary:
	var sector_dicts: Array = []
	for s in sectors:
		sector_dicts.append(s.to_dict())
	return {
		"gdp": gdp,
		"growth_rate": growth_rate,
		"inflation": inflation,
		"unemployment": unemployment,
		"public_debt_pct": public_debt_pct,
		"budget": null if budget == null else budget.to_dict(),
		"sectors": sector_dicts,
		"structural_growth_rate": structural_growth_rate,
		"structural_unemployment": structural_unemployment,
		"structural_inflation": structural_inflation,
		"structural_revenue": structural_revenue,
		"structural_expenditure": structural_expenditure,
		"workforce_quality": workforce_quality,
		"trade_revenue_contribution": trade_revenue_contribution,
		"loans": loans.duplicate(true),
	}


static func from_dict(data: Dictionary) -> Economy:
	if not (data is Dictionary):
		push_error("Economy.from_dict: expected a Dictionary, got %s" % [data])
		return null
	var e := Economy.new()
	e.gdp = float(data.get("gdp", 0.0))
	e.growth_rate = float(data.get("growth_rate", 0.0))
	e.inflation = float(data.get("inflation", 0.0))
	e.unemployment = float(data.get("unemployment", 0.0))
	e.public_debt_pct = float(data.get("public_debt_pct", 0.0))
	var budget_data: Variant = data.get("budget", null)
	if budget_data is Dictionary:
		e.budget = Budget.from_dict(budget_data)
		if e.budget == null:
			return null
	var sectors_data: Variant = data.get("sectors", [])
	if sectors_data is Array:
		for s_data in sectors_data:
			if s_data is Dictionary:
				var sector := Sector.from_dict(s_data)
				if sector != null:
					e.sectors.append(sector)
	e.structural_growth_rate = float(data.get("structural_growth_rate", e.growth_rate))
	e.structural_unemployment = float(data.get("structural_unemployment", e.unemployment))
	e.structural_inflation = float(data.get("structural_inflation", e.inflation))
	var revenue_default := 0.0
	var expenditure_default := 0.0
	if e.budget != null:
		revenue_default = e.budget.revenue
		expenditure_default = e.budget.expenditure
	e.structural_revenue = float(data.get("structural_revenue", revenue_default))
	e.structural_expenditure = float(data.get("structural_expenditure", expenditure_default))
	e.workforce_quality = float(data.get("workforce_quality", 0.5))
	e.trade_revenue_contribution = float(data.get("trade_revenue_contribution", 0.0))
	var loans_data: Variant = data.get("loans", [])
	e.loans = loans_data.duplicate(true) if loans_data is Array else []
	return e
