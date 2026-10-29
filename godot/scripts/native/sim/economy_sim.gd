class_name EconomySim
extends RefCounted


const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")

const BASE_WORKFORCE_QUALITY := 0.5
const BASE_BUREAUCRATIC_CAPACITY := 0.75
const WORKFORCE_GROWTH_FACTOR := 0.03
const TRADE_CUSTOMS_RATE := 0.05

const FISCAL_MULTIPLIER := 0.8
const MAX_FISCAL_IMPULSE := 0.04
const SPENDING_TREND_ADAPTATION := 1.0 / 24.0

const NATURAL_UNEMPLOYMENT_BASE := 0.10
const WORKFORCE_NATURAL_RATE_EFFECT := 0.12
const CAPACITY_NATURAL_RATE_EFFECT := 0.04
const NATURAL_UNEMPLOYMENT_MIN := 0.03
const NATURAL_UNEMPLOYMENT_MAX := 0.20
const UNEMPLOYMENT_REVERSION := 0.02
const OKUN_COEFFICIENT := 0.5

const INFLATION_ANCHOR := 0.02
const INFLATION_REVERSION := 0.008
const ANCHOR_SLIPS_ABOVE := 0.08
const ANCHOR_SLIP_RANGE := 0.25
const ANCHOR_MIN_CREDIBILITY := 0.25
const DEFICIT_INFLATION_FACTOR := 0.006
const DEMAND_INFLATION_FACTOR := 0.04
const MONETISATION_THRESHOLD := 1.0
const MONETISATION_INFLATION_FACTOR := 0.002
const STRUCTURAL_INFLATION_MAX := 0.60

const INTEREST_REPRICING := 1.0 / 36.0
const MAX_DEBT_PCT := 4.0


static func update(state: GameState) -> void:
	_update_workforce_quality(state)
	_update_bureaucratic_capacity(state)
	_update_sectors(state)
	_update_fiscal_baseline(state)
	_update_fiscal_stance(state)
	_update_labour_market(state)
	_update_budget_lines(state)
	_update_prices(state)
	_apply_headline_stats(state)
	_compound_gdp(state)
	_update_balance_sheet(state)


static func _update_workforce_quality(state: GameState) -> void:
	var econ := state.country.economy
	econ.workforce_quality = clampf(
		BASE_WORKFORCE_QUALITY + _modifiers_sum(state, "workforce_quality"), 0.0, 1.0)


static func _update_bureaucratic_capacity(state: GameState) -> void:
	state.country.bureaucratic_capacity = clampf(
		BASE_BUREAUCRATIC_CAPACITY + _modifiers_sum(state, "bureaucratic_capacity"), 0.0, 1.0)


static func _update_sectors(state: GameState) -> void:
	var econ := state.country.economy
	if econ.sectors.is_empty():
		return

	var weighted_growth := 0.0
	for s in econ.sectors:
		weighted_growth += s.gdp_share * s.growth_rate
	var workforce_bonus := (econ.workforce_quality - 0.5) * WORKFORCE_GROWTH_FACTOR
	var target_growth := weighted_growth + workforce_bonus + econ.structural_growth_offset
	econ.structural_growth_rate += (target_growth - econ.structural_growth_rate) * 0.25

	for sector in econ.sectors:
		var relative: float = sector.growth_rate - weighted_growth
		sector.gdp_share = maxf(0.01, sector.gdp_share + relative * 0.01)
		sector.employment_share = maxf(0.01, sector.employment_share +
			(sector.gdp_share - sector.employment_share) * 0.04)

	var total_gdp_share := 0.0
	var total_emp_share := 0.0
	for s in econ.sectors:
		total_gdp_share += s.gdp_share
		total_emp_share += s.employment_share
	if total_gdp_share > 0.0:
		for s in econ.sectors:
			s.gdp_share /= total_gdp_share
	if total_emp_share > 0.0:
		for s in econ.sectors:
			s.employment_share /= total_emp_share

	for sector in econ.sectors:
		for fid in sector.aligned_faction_ids:
			var faction := _faction_by_id(state, fid)
			if faction != null:
				faction.power = clampf(faction.power + sector.growth_rate * 0.015, 0.0, 1.0)


static func _faction_by_id(state: GameState, faction_id: String) -> Faction:
	for f in state.country.factions:
		if f.id == faction_id:
			return f
	return null


static func _update_fiscal_baseline(state: GameState) -> void:
	var econ := state.country.economy
	var monthly_structural_growth := econ.structural_growth_rate / 12.0
	econ.structural_revenue *= (1.0 + monthly_structural_growth)
	econ.structural_expenditure *= (1.0 + monthly_structural_growth)
	econ.spending_trend *= (1.0 + monthly_structural_growth)
	_sync_active_total(state, econ.structural_expenditure)
	state.active_budget.economy_basis *= (1.0 + monthly_structural_growth)

	var total_trade_revenue := 0.0
	for rel in state.country.relations.values():
		var relation: Country.BilateralRelation = rel
		var has_trade := false
		for tr in relation.treaties:
			if tr is Dictionary and String(tr.get("type", "")) == "trade":
				has_trade = true
				break
		if has_trade:
			total_trade_revenue += relation.trade_volume * TRADE_CUSTOMS_RATE
	econ.trade_revenue_contribution = total_trade_revenue


static func _sync_active_total(state: GameState, expenditure: float) -> void:
	var active := BudgetSim.ensure_budget_state(state)
	var keys: Array = []
	for envelope in _envelopes():
		keys.append(String(envelope.get("id", "")))
	for key in active.allocations.keys():
		if not key in keys:
			active.allocations.erase(key)
	var old_total := active.expenditure()
	if old_total <= 0.0:
		active.allocations = BudgetSim.default_allocations(_envelopes(), expenditure)
		return
	var ratio := maxf(0.0, expenditure) / old_total
	var present: Array = keys.filter(func(k): return active.allocations.has(k))
	var used := 0.0
	for i in range(present.size() - 1):
		var value := _round1(float(active.allocations[present[i]]) * ratio)
		active.allocations[present[i]] = value
		used += value
	if not present.is_empty():
		active.allocations[present[-1]] = _round1(maxf(0.0, expenditure - used))


static func _envelopes() -> Array:
	var content: Dictionary = ContentRepositoryScript.load_all()
	var catalogs: Dictionary = content.get("catalogs", {})
	var budget_catalog: Dictionary = catalogs.get("budget", {})
	var envelopes: Variant = budget_catalog.get("envelopes", [])
	return envelopes if envelopes is Array else []


static func _round1(value: float) -> float:
	return roundf(value * 10.0) / 10.0


static func _update_fiscal_stance(state: GameState) -> void:
	var econ := state.country.economy
	var primary := econ.structural_expenditure + _modifiers_sum(state, "budget_expenditure")
	if econ.spending_trend <= 0.0:
		econ.spending_trend = primary
	var gap_share := 0.0 if econ.gdp <= 0.0 else (primary - econ.spending_trend) / econ.gdp
	econ.fiscal_impulse = clampf(gap_share * FISCAL_MULTIPLIER, -MAX_FISCAL_IMPULSE, MAX_FISCAL_IMPULSE)
	econ.spending_trend += (primary - econ.spending_trend) * SPENDING_TREND_ADAPTATION


static func demand_gap(state: GameState) -> float:
	var econ := state.country.economy
	return econ.fiscal_impulse + _modifiers_sum(state, "gdp_growth")


static func natural_unemployment_for(state: GameState) -> float:
	var econ := state.country.economy
	return clampf(NATURAL_UNEMPLOYMENT_BASE
		- (econ.workforce_quality - 0.5) * WORKFORCE_NATURAL_RATE_EFFECT
		- (state.country.bureaucratic_capacity - BASE_BUREAUCRATIC_CAPACITY) * CAPACITY_NATURAL_RATE_EFFECT,
		NATURAL_UNEMPLOYMENT_MIN, NATURAL_UNEMPLOYMENT_MAX)


static func _update_labour_market(state: GameState) -> void:
	var econ := state.country.economy
	econ.natural_unemployment = natural_unemployment_for(state)
	var reversion := (econ.natural_unemployment - econ.structural_unemployment) * UNEMPLOYMENT_REVERSION
	var demand_effect := demand_gap(state) * OKUN_COEFFICIENT / 12.0
	econ.structural_unemployment = clampf(
		econ.structural_unemployment + reversion - demand_effect, 0.01, 0.50)


static func anchor_credibility(inflation: float) -> float:
	var slip := clampf((inflation - ANCHOR_SLIPS_ABOVE) / ANCHOR_SLIP_RANGE, 0.0, 1.0)
	return lerpf(1.0, ANCHOR_MIN_CREDIBILITY, slip)


static func _update_prices(state: GameState) -> void:
	var econ := state.country.economy
	var deficit := clampf(econ.deficit_share_of_gdp(), -0.10, 0.30)
	var monetisation := maxf(0.0, econ.public_debt_pct - MONETISATION_THRESHOLD)
	var drift := (deficit * DEFICIT_INFLATION_FACTOR
		+ demand_gap(state) * DEMAND_INFLATION_FACTOR
		+ monetisation * MONETISATION_INFLATION_FACTOR
		+ (INFLATION_ANCHOR - econ.structural_inflation) * INFLATION_REVERSION
			* anchor_credibility(econ.structural_inflation))
	econ.structural_inflation = clampf(econ.structural_inflation + drift, 0.0, STRUCTURAL_INFLATION_MAX)


static func _apply_headline_stats(state: GameState) -> void:
	var econ := state.country.economy

	econ.growth_rate = clampf(
		econ.structural_growth_rate + econ.fiscal_impulse + _modifiers_sum(state, "gdp_growth")
		+ GasSim.growth_effect(state), -0.15, 0.20)
	econ.unemployment = clampf(
		econ.structural_unemployment + _modifiers_sum(state, "unemployment"), 0.01, 0.50)
	econ.inflation = clampf(
		econ.structural_inflation + _modifiers_sum(state, "inflation"), 0.0, 1.0)

	_update_budget_lines(state)


static func _update_budget_lines(state: GameState) -> void:
	var econ := state.country.economy
	econ.debt_service = econ.interest_bill()
	econ.budget.revenue = (econ.structural_revenue + econ.trade_revenue_contribution
		+ _modifiers_sum(state, "budget_revenue"))
	econ.budget.expenditure = (econ.structural_expenditure
		+ _modifiers_sum(state, "budget_expenditure") + econ.debt_service + GasSim.budget_cost(state))


static func _compound_gdp(state: GameState) -> void:
	var econ := state.country.economy
	econ.gdp *= (1.0 + econ.growth_rate / 12.0)


static func _update_balance_sheet(state: GameState) -> void:
	var econ := state.country.economy
	if econ.gdp <= 0.0:
		return
	econ.public_debt = clampf(econ.public_debt + (econ.budget.expenditure - econ.budget.revenue) / 12.0,
		0.0, MAX_DEBT_PCT * econ.gdp)
	econ.effective_interest_rate += (econ.market_interest_rate() - econ.effective_interest_rate) * INTEREST_REPRICING


static func _modifiers_sum(state: GameState, target: String) -> float:
	var total := 0.0
	for m in state.modifiers:
		if m.target != target:
			continue
		var value := m.current_value()
		if m.institutional:
			value *= _implementation_quality_for(state, m.portfolio)
		total += value
	return total


static func _implementation_quality_for(state: GameState, portfolio: String) -> float:
	var minister_component := 1.0
	if portfolio != "":
		var minister := _minister_for_portfolio(state, portfolio)
		minister_component = 0.35 if minister == null else minister.implementation_quality()

	var capacity := state.country.bureaucratic_capacity
	var corruption_drag := _cabinet_risk_fraction(state) * 0.3
	var institutional_health := clampf(
		(capacity - corruption_drag) * 0.5 + state.stability_value * 0.5, 0.0, 1.0)
	var dampener := 0.5 + 0.5 * institutional_health

	return minister_component * dampener * _policy_delivery_factor(state, portfolio)


static func _minister_for_portfolio(state: GameState, portfolio: String) -> Minister:
	for m in state.ministers:
		if m.portfolio == portfolio:
			return m
	return null


static func _cabinet_risk_fraction(state: GameState) -> float:
	if state.ministers.is_empty():
		return 0.0
	var threats := 0
	for m in state.ministers:
		if m.threat_level() > 0.5:
			threats += 1
	return float(threats) / float(state.ministers.size())


static func _policy_delivery_factor(state: GameState, portfolio: String) -> float:
	if portfolio == "":
		return 1.0
	var ministry: MinistryState = state.ministries.get(portfolio)
	var delivery := 1.0 if ministry == null else ministry.delivery
	return 0.55 + 0.45 * delivery
