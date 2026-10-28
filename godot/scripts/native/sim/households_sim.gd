class_name HouseholdsSim
extends RefCounted

## How national conditions land on people: six social groups in each region,
## each exposed differently to jobs, prices, public services and welfare.
## Runs after regions and before approval/stability. Seeding is additive and
## requires existing Ardenian regions. Readers are deliberately pure: they
## never seed; the caller seeds explicitly or calls simulate.

const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")


static func _catalogs() -> Dictionary:
	var content: Dictionary = ContentRepositoryScript.load_all()
	return content.get("catalogs", {})


static func _definitions(catalogs: Dictionary) -> Dictionary:
	var out := {}
	for definition in catalogs.get("household_groups", {}).get("groups", []):
		out[String(definition["id"])] = definition
	return out


static func _seed_missing(state: GameState, catalogs: Dictionary, definitions: Dictionary) -> void:
	if state.country == null or state.country.id != "ardenia" or state.regions.is_empty():
		return
	var shares: Dictionary = catalogs.get("household_groups", {}).get("regional_shares", {})
	for rid in shares:
		var region: RegionState = state.regions.get(rid) as RegionState
		if region == null:
			continue
		for gid in shares[rid]:
			var key: String = "%s:%s" % [rid, gid]
			if state.households.has(key):
				continue
			var definition: Dictionary = definitions[gid]
			var h := HouseholdGroupState.new()
			h.id = key
			h.region_id = String(rid)
			h.group_id = String(gid)
			h.population_share = float(shares[rid][gid])
			h.employment_security = 0.55 if gid == "pensioners" else clampf(
				1.0 - region.unemployment * float(definition["job_sensitivity"]) * 2.0, 0.0, 1.0)
			h.service_access = _initial_service_access(region, h.group_id)
			h.hardship = _hardship_target(region, h, definition)
			h.confidence = clampf(0.66 - h.hardship * 0.55, 0.0, 1.0)
			state.households[key] = h


## Adds missing canonical records only; retained objects keep all history.
static func ensure_households(state: GameState) -> Dictionary:
	if state.country == null or state.country.id != "ardenia" or state.regions.is_empty():
		return state.households
	var catalogs := _catalogs()
	_seed_missing(state, catalogs, _definitions(catalogs))
	return state.households


static func _initial_service_access(region: RegionState, group_id: String) -> float:
	var access := region.state_reach * 0.65 + 0.25
	if group_id == "rural_households":
		access -= 0.10
	if group_id in ["pensioners", "insecure_households"]:
		access -= 0.04
	if region.control == "separatist":
		access = minf(access, 0.15)
	return clampf(access, 0.05, 0.95)


static func _hardship_target(region: RegionState, h: HouseholdGroupState, definition: Dictionary) -> float:
	var income_stress := clampf((1.0 - h.real_income_index) / 0.35, 0.0, 1.0)
	return clampf(income_stress * 0.35
		+ (1.0 - h.employment_security) * (0.22 + float(definition["job_sensitivity"]) * 0.025)
		+ (1.0 - h.service_access) * (0.18 + float(definition["service_dependence"]) * 0.08)
		+ region.pressure * 0.15, 0.0, 1.0)


## How well funded one service is, against what a normal state of this
## economy's size spends on it (not against today's total, which would make
## an across-the-board cut invisible). A deeply starved service reads as
## deeply starved rather than flooring at half.
const ENVELOPE_RATIO_MIN := 0.10
const ENVELOPE_RATIO_MAX := 1.50

static func _envelope_ratio(state: GameState, envelope_id: String, catalogs: Dictionary) -> float:
	if state.active_budget == null:
		return 1.0
	var norm_total := state.country.economy.expected_primary_spending()
	if norm_total <= 0.0:
		norm_total = state.active_budget.expenditure()
	for envelope in catalogs.get("budget", {}).get("envelopes", []):
		if String(envelope["id"]) == envelope_id:
			var expected := norm_total * float(envelope["share"])
			var actual := float(state.active_budget.allocations.get(envelope_id, expected))
			return clampf(actual / maxf(1.0, expected), ENVELOPE_RATIO_MIN, ENVELOPE_RATIO_MAX)
	return 1.0


static func _public_administration_delivery(state: GameState) -> float:
	var finance: MinistryState = state.ministries.get("Finance") as MinistryState
	var interior: MinistryState = state.ministries.get("Interior") as MinistryState
	var finance_delivery := 0.75 if finance == null else finance.delivery
	var interior_delivery := 0.75 if interior == null else interior.delivery
	return finance_delivery * 0.40 + interior_delivery * 0.60


static func _delivery(state: GameState, envelope_id: String, catalogs: Dictionary) -> float:
	return clampf(_envelope_ratio(state, envelope_id, catalogs)
		* _public_administration_delivery(state), 0.10, 1.25)


static func welfare_delivery(state: GameState) -> float:
	return _delivery(state, "health_and_welfare", _catalogs())


static func education_delivery(state: GameState) -> float:
	return _delivery(state, "education", _catalogs())


## One monthly pulse. All catalog reads are shared for this call; no global
## RNG, synthetic ministries/budget, or separate national economy is created.
static func simulate(state: GameState) -> void:
	if state.country == null:
		return
	var catalogs := _catalogs()
	var definitions := _definitions(catalogs)
	_seed_missing(state, catalogs, definitions)
	if state.households.is_empty():
		return
	var econ := state.country.economy
	var welfare := _delivery(state, "health_and_welfare", catalogs)
	var education := _delivery(state, "education", catalogs)
	var agriculture := econ.sector_by_id("agriculture")
	var agriculture_growth := econ.growth_rate if agriculture == null else agriculture.growth_rate
	for value in state.households.values():
		var h: HouseholdGroupState = value
		var region: RegionState = state.regions.get(h.region_id) as RegionState
		if region == null or not definitions.has(h.group_id):
			continue
		var definition: Dictionary = definitions[h.group_id]
		h.last_real_income_index = h.real_income_index
		var cost_rate := econ.inflation * float(definition["price_sensitivity"])
		h.living_cost_index *= 1.0 + cost_rate / 12.0
		var growth := agriculture_growth if h.group_id == "rural_households" else econ.growth_rate
		var indexation := float(definition["income_indexation"])
		if h.group_id in ["pensioners", "insecure_households"]:
			indexation += float(definition["welfare_dependence"]) * welfare * 0.38
		var nominal_rate := econ.inflation * indexation + growth * float(definition["growth_exposure"])
		var excess_unemployment := maxf(0.0, region.unemployment - 0.08)
		nominal_rate -= excess_unemployment * float(definition["job_sensitivity"]) * 0.12
		h.nominal_income_index = clampf(h.nominal_income_index * (1.0 + nominal_rate / 12.0), 0.45, 2.50)
		h.living_cost_index = clampf(h.living_cost_index, 0.65, 3.50)
		h.real_income_index = clampf(h.nominal_income_index / h.living_cost_index, 0.35, 2.00)
		var employment_target := 0.42 + welfare * 0.38 if h.group_id == "pensioners" else (
			1.0 - region.unemployment * float(definition["job_sensitivity"]) * 2.0)
		h.employment_security = clampf(h.employment_security
			+ (clampf(employment_target, 0.0, 1.0) - h.employment_security) * 0.18, 0.0, 1.0)
		var welfare_weight := float(definition["service_dependence"])
		var education_weight := 1.0 - welfare_weight * 0.45
		var public_delivery := (welfare * welfare_weight + education * education_weight
			) / maxf(0.01, welfare_weight + education_weight)
		var service_target := region.state_reach * 0.58 + public_delivery * 0.42
		if h.group_id == "rural_households":
			service_target -= 0.10
		if region.control == "separatist":
			service_target = minf(service_target, 0.15)
		h.service_access += (clampf(service_target, 0.03, 0.98) - h.service_access) * 0.12
		h.hardship = clampf(h.hardship + (_hardship_target(region, h, definition) - h.hardship) * 0.15, 0.0, 1.0)
		var real_change := h.real_income_index - h.last_real_income_index
		var confidence_target := clampf(0.62 - h.hardship * 0.62 + econ.growth_rate * 1.2
			+ (state.stability_value - 0.5) * 0.16 + real_change * 3.0, 0.0, 1.0)
		h.confidence = clampf(h.confidence + (confidence_target - h.confidence) * 0.12, 0.0, 1.0)


## National weights = authored regional population x local household share.
## For a regional reader the regional factor cancels in normalization.
static func _weighted(state: GameState, attr: String, region_id: String = "") -> float:
	if state.households.is_empty():
		return 0.0
	var profiles: Dictionary = _catalogs().get("regions_and_programs", {}).get("region_profiles", {})
	var total := 0.0
	var weight_total := 0.0
	for value in state.households.values():
		var h: HouseholdGroupState = value
		if region_id != "" and h.region_id != region_id:
			continue
		var weight := float(profiles.get(h.region_id, {}).get("population_weight", 0.0)) * h.population_share
		total += float(h.get(attr)) * weight
		weight_total += weight
	return total / weight_total if weight_total > 0.0 else 0.0


static func national_hardship(state: GameState) -> float:
	return _weighted(state, "hardship")


static func national_confidence(state: GameState) -> float:
	return 0.5 if state.households.is_empty() else _weighted(state, "confidence")


static func national_real_income(state: GameState) -> float:
	return 1.0 if state.households.is_empty() else _weighted(state, "real_income_index")


static func national_living_cost(state: GameState) -> float:
	return 1.0 if state.households.is_empty() else _weighted(state, "living_cost_index")


static func national_service_access(state: GameState) -> float:
	return _weighted(state, "service_access")


static func regional_hardship(state: GameState, region_id: String) -> float:
	return _weighted(state, "hardship", region_id)


static func regional_confidence(state: GameState, region_id: String) -> float:
	return _weighted(state, "confidence", region_id)


static func regional_service_access(state: GameState, region_id: String) -> float:
	return _weighted(state, "service_access", region_id)


## New array, existing records; sorting never changes ledger insertion order.
static func hardest_hit(state: GameState, limit: int = 5) -> Array:
	var ranked := state.households.values()
	ranked.sort_custom(func(a: HouseholdGroupState, b: HouseholdGroupState) -> bool:
		return a.hardship > b.hardship)
	return ranked.slice(0, maxi(0, limit))
