class_name MinistriesSim
extends RefCounted

const CORE_PORTFOLIOS: Array[String] = ["Finance", "Interior", "Foreign Affairs", "Defense", "Economy", "Justice"]

const BASE_WORKLOAD := 0.65
const OPERATING_MINIMUM := 0.60
const CAPACITY_AT_MINIMUM := 0.55
const MAX_FUNDING_BONUS := 0.25
const FUNDING_BONUS_SCALE := 0.40
const MAX_BACKLOG := 6.0
const BACKLOG_RECOVERY_SHARE := 0.22

const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")

const CIVIL_WAR_CRISIS_LOAD := {
	"Defense": 1.00, "Interior": 0.85, "Justice": 0.45,
	"Economy": 0.35, "Finance": 0.30, "Foreign Affairs": 0.20,
}


static func _envelopes() -> Array:
	var content: Dictionary = ContentRepositoryScript.load_all()
	var catalogs: Dictionary = content.get("catalogs", {})
	var budget_catalog: Dictionary = catalogs.get("budget", {})
	var envelopes: Variant = budget_catalog.get("envelopes", [])
	return envelopes if envelopes is Array else []


static func envelope_ids(portfolio: String) -> Array[String]:
	var out: Array[String] = []
	for item in _envelopes():
		if String((item as Dictionary).get("portfolio", "")) == portfolio:
			out.append(String((item as Dictionary)["id"]))
	return out


static func portfolio_funding(state: GameState, portfolio: String) -> float:
	if state.active_budget == null:
		return 0.0
	var voted := 0.0
	for envelope_id in envelope_ids(portfolio):
		voted += float(state.active_budget.allocations.get(envelope_id, 0.0))
	return voted + state.active_budget.portfolio_supplement(portfolio)


static func _new_ministry(state: GameState, portfolio: String) -> MinistryState:
	var funding := portfolio_funding(state, portfolio)
	var m := MinistryState.new()
	m.portfolio = portfolio
	m.baseline_funding = funding
	m.funding = funding
	m.delivery = 1.0
	return m


static func initial_ministry_states(state: GameState) -> Dictionary:
	var out := {}
	for portfolio in CORE_PORTFOLIOS:
		out[portfolio] = _new_ministry(state, portfolio)
	return out


static func ensure_ministries(state: GameState) -> Dictionary:
	if state.ministries.is_empty():
		state.ministries = initial_ministry_states(state)
	for portfolio in CORE_PORTFOLIOS:
		if not state.ministries.has(portfolio):
			state.ministries[portfolio] = _new_ministry(state, portfolio)
	return state.ministries


static func _national_pressure(state: GameState) -> float:
	if state.regions.is_empty():
		return 0.0
	var content: Dictionary = ContentRepositoryScript.load_all()
	var catalogs: Dictionary = content.get("catalogs", {})
	var regional_catalog: Dictionary = catalogs.get("regions_and_programs", {})
	var profiles: Dictionary = regional_catalog.get("region_profiles", {})
	var weighted := 0.0
	var total := 0.0
	for key in state.regions:
		var region: RegionState = state.regions[key] as RegionState
		if region == null:
			continue
		var profile: Variant = profiles.get(String(key), {})
		var weight := 1.0
		if profile is Dictionary:
			if (profile as Dictionary).has("population_weight"):
				weight = RegionsSim.population_weight(state, String(key))
		weighted += region.pressure * weight
		total += weight
	return weighted / total if total > 0.0 else 0.0


static func _programme_workload(state: GameState, portfolio: String) -> float:
	var content: Dictionary = ContentRepositoryScript.load_all()
	var catalogs: Dictionary = content.get("catalogs", {})
	var regional_catalog: Dictionary = catalogs.get("regions_and_programs", {})
	var definitions: Dictionary = regional_catalog.get("regional_programs", {})
	var matching := 0
	for program in state.regional_programs:
		var item: RegionState.RegionalProgram = program as RegionState.RegionalProgram
		if item == null:
			continue
		var definition: Variant = definitions.get(item.program_id, {})
		if definition is Dictionary and String((definition as Dictionary).get("portfolio", "")) == portfolio:
			matching += 1
	return float(matching) * 0.48

static func workload_breakdown(state: GameState, portfolio: String) -> Dictionary:
	var breakdown := {"ordinary administration": BASE_WORKLOAD}


	if BudgetSim.is_emergency(state):
		breakdown["emergency budget rules"] = BudgetSim.emergency_workload(state)

	var programme_load := _programme_workload(state, portfolio)
	if programme_load > 0.0:
		breakdown["regional programmes"] = programme_load

	if portfolio == "Foreign Affairs":
		var treaties := 0
		var sanctions := 0
		for rel in state.country.relations.values():
			var relation: Country.BilateralRelation = rel
			treaties += relation.treaties.size()
			if relation.sanctioned:
				sanctions += 1
		if treaties > 0:
			breakdown["treaties"] = treaties * 0.10
		if sanctions > 0:
			breakdown["sanctions"] = sanctions * 0.22
	elif portfolio == "Finance" and not state.country.economy.loans.is_empty():
		breakdown["debt administration"] = state.country.economy.loans.size() * 0.12

	if state.civil_war:
		var crisis_load: float = CIVIL_WAR_CRISIS_LOAD.get(portfolio, 0.0)
		if crisis_load > 0.0:
			breakdown["civil war"] = crisis_load

	if portfolio == "Interior" and not state.regions.is_empty():
		var pressure := _national_pressure(state)
		if pressure > 0.45:
			breakdown["regional pressure"] = (pressure - 0.45) * 0.90

	return breakdown


static func _minister_for_portfolio(state: GameState, portfolio: String) -> Minister:
	for m in state.ministers:
		if (m as Minister).portfolio == portfolio:
			return m
	return null


static func _minister_quality(state: GameState, portfolio: String) -> float:
	var minister := _minister_for_portfolio(state, portfolio)
	return 0.35 if minister == null else minister.implementation_quality()


static func funding_factor(funding_ratio: float) -> float:
	var ratio := maxf(0.0, funding_ratio)
	if ratio < OPERATING_MINIMUM:
		return CAPACITY_AT_MINIMUM * ratio / OPERATING_MINIMUM
	if ratio <= 1.0:
		return lerpf(CAPACITY_AT_MINIMUM, 1.0, (ratio - OPERATING_MINIMUM) / (1.0 - OPERATING_MINIMUM))
	return 1.0 + MAX_FUNDING_BONUS * (1.0 - exp(-(ratio - 1.0) / FUNDING_BONUS_SCALE))


static func operating_capacity(state: GameState, ministry: MinistryState) -> Array:
	var funding := portfolio_funding(state, ministry.portfolio)
	var baseline := maxf(1.0, ministry.baseline_funding)
	var funding_ratio := funding / baseline
	var money_factor := funding_factor(funding_ratio)
	var state_factor := 0.65 + 0.35 * state.country.bureaucratic_capacity
	var leadership_factor := 0.60 + 0.40 * _minister_quality(state, ministry.portfolio)
	var stability_factor := 0.80 + 0.20 * state.stability_value
	var capacity := 1.45 * money_factor * state_factor * leadership_factor * stability_factor
	return [capacity, funding, funding_ratio]


static func preview(state: GameState, portfolio: String) -> Dictionary:
	var ministry: MinistryState = ensure_ministries(state)[portfolio]
	var breakdown := workload_breakdown(state, portfolio)
	var workload := 0.0
	for v in breakdown.values():
		workload += float(v)
	var capacity_result := operating_capacity(state, ministry)
	var capacity: float = capacity_result[0]
	var funding: float = capacity_result[1]
	var funding_ratio: float = capacity_result[2]
	var demand := workload + minf(ministry.backlog, workload * BACKLOG_RECOVERY_SHARE)
	var served := minf(demand, capacity)
	var delivery := clampf(served / maxf(0.01, demand), 0.0, 1.0)
	return {
		"breakdown": breakdown,
		"workload": workload,
		"capacity": capacity,
		"funding": funding,
		"funding_ratio": funding_ratio,
		"delivery": delivery,
	}


static func simulate(state: GameState) -> void:
	var ministries := ensure_ministries(state)
	var monthly_growth := state.country.economy.structural_growth_rate / 12.0
	for portfolio in ministries.keys():
		var ministry: MinistryState = ministries[portfolio]
		if ministry.baseline_funding <= 0.0:
			ministry.baseline_funding = portfolio_funding(state, portfolio)
		ministry.baseline_funding *= (1.0 + monthly_growth)
		var snapshot := preview(state, portfolio)
		var workload: float = snapshot["workload"]
		var capacity: float = snapshot["capacity"]
		var old_backlog := ministry.backlog
		var backlog: float
		if capacity >= workload:
			var recovered := minf(old_backlog, (capacity - workload) * BACKLOG_RECOVERY_SHARE)
			backlog = old_backlog - recovered
		else:
			backlog = old_backlog + workload - capacity
		ministry.funding = snapshot["funding"]
		ministry.funding_ratio = snapshot["funding_ratio"]
		ministry.workload = workload
		ministry.capacity = capacity
		ministry.delivery = snapshot["delivery"]
		ministry.backlog = clampf(backlog, 0.0, MAX_BACKLOG)
		ministry.workload_breakdown = (snapshot["breakdown"] as Dictionary).duplicate(true)
		if capacity < workload:
			ministry.months_overloaded += 1
		else:
			ministry.months_overloaded = maxi(0, ministry.months_overloaded - 1)
