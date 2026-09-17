class_name EconomySim
extends RefCounted

## Typed port of engine/turn.py's `_update_economy` chain — Phase 2 Task 7,
## the largest single formula surface in this phase. Six sub-phases, run in
## the exact Python order: workforce quality -> bureaucratic capacity ->
## sectors -> structural fiscal baseline -> organic inflation -> modifiers
## onto headline stats -> compound GDP.
##
## NOT wired into `NativeGame`'s monthly-rollover path yet — that is Task
## 10's integration job, same as `BudgetSim`/`MinistriesSim` (Tasks 5-6):
## invokable-but-not-yet-invoked by design.
##
## `_modifiers_sum`/`_implementation_quality_for` are ported here (not
## reused from elsewhere — no native file owns them yet) because all three
## headline-stat sub-phases call them. One honest gap versus
## `engine/turn.py: _implementation_quality_for`: Python's
## `ministries.policy_delivery_factor` -> `current_delivery` calls
## `ensure_ministries(state)`, which SIDE-EFFECTS by seeding every
## CORE_PORTFOLIO into `state.ministries` if it's empty. Seeding all six
## ministries as an incidental side effect of summing an economy modifier
## would be a surprising cross-subsystem coupling this task doesn't own, so
## `_policy_delivery_factor` here reads `state.ministries.get(portfolio)`
## directly without seeding: a portfolio genuinely not yet in the dict reads
## as `delivery == 1.0` (MinistryState's own default — see ministry_state.gd)
## instead of running MinistriesSim's seeding first. This is observably
## identical to Python for the fresh-ministry case (a just-seeded
## MinistryState also starts at delivery 1.0) and diverges only if some
## OTHER portfolio has already been simulated to a non-default delivery
## while THIS portfolio has not — a state MinistriesSim itself always
## avoids by seeding every portfolio together, never one at a time.
##
## `_compound_gdp`'s `flavor.say(state, "economy_move", ...)` dispatch call
## is intentionally not ported — no native dispatch/flavor system exists yet
## (same precedent as modifiers.gd's header note on `_age_modifiers`'
## dropped logging call).

const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")

## "normal" annual growth, used by the Okun's-law unemployment link.
const TREND_GROWTH := 0.02
## workforce_quality baseline before any long-term modifiers.
const BASE_WORKFORCE_QUALITY := 0.5
## bureaucratic_capacity baseline before any long-term modifiers.
const BASE_BUREAUCRATIC_CAPACITY := 0.75
## max structural growth bonus/penalty from workforce quality at the extremes.
const WORKFORCE_GROWTH_FACTOR := 0.03
## annual revenue contribution per unit of active trade volume.
const TRADE_CUSTOMS_RATE := 0.05
## TRADE_VOLUME_CEILING/TRADE_VOLUME_APPROACH (engine/turn.py) feed
## `_update_relations`'s trade-volume growth, which is a different phase's
## turn-loop step, not one of this task's six `_update_*` methods — not
## ported here.

# Organic inflation (monthly drift on the structural rate):
## long-run credibility anchor the rate reverts toward.
const INFLATION_ANCHOR := 0.02
## monthly pull toward the anchor.
const INFLATION_REVERSION := 0.008
## monthly push per unit of deficit-to-revenue ratio.
const DEFICIT_INFLATION_FACTOR := 0.003
## monthly push per unit of growth above trend.
const OVERHEAT_INFLATION_FACTOR := 0.010
## hyperinflation ceiling for the structural rate.
const STRUCTURAL_INFLATION_MAX := 0.60


## The brief's required entry point: the full `_update_economy` chain.
static func update(state: GameState) -> void:
	_update_workforce_quality(state)
	_update_bureaucratic_capacity(state)
	_update_sectors(state)
	_update_structural_fiscal_baseline(state)
	_update_structural_inflation(state)
	_apply_modifiers_to_headline_stats(state)
	_compound_gdp(state)


## Slow-moving stat driven only by long-term modifiers (e.g. education reform).
static func _update_workforce_quality(state: GameState) -> void:
	var econ := state.country.economy
	econ.workforce_quality = clampf(
		BASE_WORKFORCE_QUALITY + _modifiers_sum(state, "workforce_quality"), 0.0, 1.0)


## Live modifier target, same pattern as workforce quality.
static func _update_bureaucratic_capacity(state: GameState) -> void:
	state.country.bureaucratic_capacity = clampf(
		BASE_BUREAUCRATIC_CAPACITY + _modifiers_sum(state, "bureaucratic_capacity"), 0.0, 1.0)


## Sectors + workforce quality set the STRUCTURAL growth rate; sector
## fortunes shift GDP/employment shares and aligned factions' power.
static func _update_sectors(state: GameState) -> void:
	var econ := state.country.economy
	if econ.sectors.is_empty():
		return

	var weighted_growth := 0.0
	for s in econ.sectors:
		weighted_growth += s.gdp_share * s.growth_rate
	var workforce_bonus := (econ.workforce_quality - 0.5) * WORKFORCE_GROWTH_FACTOR
	var target_growth := weighted_growth + workforce_bonus
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


## Tax/cost base drift with GDP; customs revenue recomputed fresh from
## current trade volume so it tracks relationships instead of ratcheting.
static func _update_structural_fiscal_baseline(state: GameState) -> void:
	var econ := state.country.economy
	var monthly_structural_growth := econ.structural_growth_rate / 12.0
	econ.structural_revenue *= (1.0 + monthly_structural_growth)
	econ.structural_expenditure *= (1.0 + monthly_structural_growth)
	_sync_active_total(state, econ.structural_expenditure)

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


## Keeps the displayed envelope ledger aligned with ordinary baseline drift —
## mirrors engine/budget.py: sync_active_total, not ported by Task 5 (that
## task's own scope was seeding + January rollover; this call site is
## turn.py's, not budget.py's own lifecycle). Reuses BudgetSim's public
## `ensure_budget_state`/`default_allocations` rather than duplicating the
## seeding logic.
static func _sync_active_total(state: GameState, expenditure: float) -> void:
	var active := BudgetSim.ensure_budget_state(state)
	var old_total := active.expenditure()
	if old_total <= 0.0:
		active.allocations = BudgetSim.default_allocations(_envelopes(), expenditure)
		return
	var ratio := maxf(0.0, expenditure) / old_total
	var keys := active.allocations.keys()
	var used := 0.0
	for i in range(keys.size() - 1):
		var key = keys[i]
		var value := _round1(float(active.allocations[key]) * ratio)
		active.allocations[key] = value
		used += value
	if not keys.is_empty():
		var last_key = keys[keys.size() - 1]
		active.allocations[last_key] = _round1(maxf(0.0, expenditure - used))


## The budget envelope catalog, loaded fresh via ContentRepository — mirrors
## budget_sim.gd's own `_envelopes()` (kept as a local copy rather than
## reaching into BudgetSim's underscore-prefixed helper from another file).
static func _envelopes() -> Array:
	var content: Dictionary = ContentRepositoryScript.load_all()
	var catalogs: Dictionary = content.get("catalogs", {})
	var budget_catalog: Dictionary = catalogs.get("budget", {})
	var envelopes: Variant = budget_catalog.get("envelopes", [])
	return envelopes if envelopes is Array else []


static func _round1(value: float) -> float:
	return roundf(value * 10.0) / 10.0


## Organic inflation: deficits push it up, overheating growth pushes it up,
## an anchor pulls it toward ~2%. Reads start-of-turn budget figures.
static func _update_structural_inflation(state: GameState) -> void:
	var econ := state.country.economy
	var revenue := maxf(1.0, econ.budget.revenue)
	var deficit_ratio := (econ.budget.expenditure - econ.budget.revenue) / revenue
	deficit_ratio = clampf(deficit_ratio, -0.5, 1.5)
	var overheat := econ.growth_rate - TREND_GROWTH

	var drift := (deficit_ratio * DEFICIT_INFLATION_FACTOR
		+ overheat * OVERHEAT_INFLATION_FACTOR
		+ (INFLATION_ANCHOR - econ.structural_inflation) * INFLATION_REVERSION)
	econ.structural_inflation = clampf(econ.structural_inflation + drift, 0.0, STRUCTURAL_INFLATION_MAX)


## Effective stats = structural baseline + active modifiers, assigned fresh
## (`=`, never `+=`) so long-lived laws can't compound on themselves.
static func _apply_modifiers_to_headline_stats(state: GameState) -> void:
	var econ := state.country.economy

	econ.growth_rate = econ.structural_growth_rate + _modifiers_sum(state, "gdp_growth")
	econ.growth_rate = clampf(econ.growth_rate, -0.15, 0.20)

	# Unemployment: the structural level is nudged by an Okun's-law-style
	# link to the EFFECTIVE growth rate (so policy-driven growth gains
	# eventually show up here too), then policy modifiers are layered on.
	var growth_gap := econ.growth_rate - TREND_GROWTH
	econ.structural_unemployment -= growth_gap * 0.3
	econ.structural_unemployment = clampf(econ.structural_unemployment, 0.01, 0.50)
	econ.unemployment = econ.structural_unemployment + _modifiers_sum(state, "unemployment")
	econ.unemployment = clampf(econ.unemployment, 0.01, 0.50)

	# structural_inflation moves organically each turn (deficits, overheating,
	# anchor — see _update_structural_inflation); policy modifiers layer on top.
	econ.inflation = econ.structural_inflation + _modifiers_sum(state, "inflation")
	econ.inflation = clampf(econ.inflation, 0.0, 1.0)

	econ.budget.revenue = (econ.structural_revenue + econ.trade_revenue_contribution
		+ _modifiers_sum(state, "budget_revenue"))
	econ.budget.expenditure = econ.structural_expenditure + _modifiers_sum(state, "budget_expenditure")


static func _compound_gdp(state: GameState) -> void:
	var econ := state.country.economy
	var monthly_growth := econ.growth_rate / 12.0
	econ.gdp *= (1.0 + monthly_growth)
	# flavor.say(state, "economy_move", ...) intentionally not ported — see
	# header note.


## Fresh sum of every active modifier's current contribution to a stat —
## recomputed each turn, never accumulated, so effects stay bounded. Exactly
## once per pulse: nothing here reads or writes an accumulator, so calling
## this twice (e.g. across a save/reload) always returns the same value for
## the same state instead of compounding.
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


## Minister competence/loyalty (0.35 floor when vacant, 1.0 when no
## portfolio applies) dampened — not multiplied down — by general government
## capacity (bureaucracy, cabinet risk, stability). "" is Modifier's own
## Python-None sentinel (see modifier.gd).
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


## Matches models/cabinet.py: Cabinet.get exactly (first match by portfolio,
## no faction check) — the same lookup ministries_sim.gd's own
## `_minister_for_portfolio` performs, duplicated here rather than reached
## into across sim files.
static func _minister_for_portfolio(state: GameState, portfolio: String) -> Minister:
	for m in state.ministers:
		if m.portfolio == portfolio:
			return m
	return null


## 0..1: share of the cabinet that's currently a latent threat — mirrors
## engine/stability.py: compute_cabinet_risk_fraction (Minister.threat_level()
## > 0.5, same threshold as models/cabinet.py: Cabinet.internal_threats).
static func _cabinet_risk_fraction(state: GameState) -> float:
	if state.ministers.is_empty():
		return 0.0
	var threats := 0
	for m in state.ministers:
		if m.threat_level() > 0.5:
			threats += 1
	return float(threats) / float(state.ministers.size())


## Moderate multiplier: workload compounds existing implementation, not
## replaces it — mirrors engine/ministries.py: policy_delivery_factor /
## current_delivery, EXCEPT it never calls `ensure_ministries` to seed a
## missing portfolio (see header note): a portfolio not yet in
## `state.ministries` reads as the same `delivery == 1.0` a freshly-seeded
## MinistryState would have anyway.
static func _policy_delivery_factor(state: GameState, portfolio: String) -> float:
	if portfolio == "":
		return 1.0
	var ministry: MinistryState = state.ministries.get(portfolio)
	var delivery := 1.0 if ministry == null else ministry.delivery
	return 0.55 + 0.45 * delivery
