class_name RegionsSim
extends RefCounted


const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")

const PRESSURE_JOBS_WEIGHT := 0.40
const PRESSURE_CAPACITY_WEIGHT := 0.30
const PRESSURE_NATIONAL_WEIGHT := 0.16

const UNEMPLOYMENT_CONVERGENCE := 0.14
const REACH_CONVERGENCE := 0.05
const PRESSURE_CONVERGENCE := 0.12

const CONTROL_LIMITED_MAX := 0.48
const CONTROL_AUTONOMOUS_MIN := 0.24
const CONTROL_AUTONOMOUS_CAPACITY_BONUS := 0.12
const CONTROL_AUTONOMOUS_MAX := 0.42
const CONTROL_VETRENKA_STATE_MIN := 0.22
const CONTROL_VETRENKA_STATE_CAPACITY_BONUS := 0.32
const CONTROL_VETRENKA_STATE_MAX := 0.58
const CONTROL_SEPARATIST_MAX := 0.08

const DELIVERY_BASE := 0.45
const DELIVERY_INSTITUTIONAL_WEIGHT := 0.55
const DELIVERY_MIN := 0.30
const DELIVERY_MAX := 1.0
const MISSING_MINISTER_DELIVERY := 0.35
const DELIVERY_MINISTER_SHARE := 0.65
const DELIVERY_STATE_CAPACITY_SHARE := 0.35
const DEPARTMENT_BASE := 0.55
const DEPARTMENT_DELIVERY_SHARE := 0.45

const VETRENKA_PRESSURE_BIAS := {
	"settled": 0.07,
	"retaken": 0.17,
	"routed": 0.25,
	"partitioned": 0.11,
	"partitioned_contested": 0.20,
	"talks_failed": 0.23,
}


const NATURAL_GROWTH_PER_YEAR := 0.004
const MIGRATION_SHARE_PER_MONTH := 0.002
const DEVELOPMENT_CONVERGENCE := 0.015
const DEVELOPMENT_REACH_BONUS := 0.10
const SEPARATIST_DEVELOPMENT_CEILING := 0.25


static func population_weight(state: GameState, region_id: String) -> float:
	var total := 0.0
	for r in state.regions.values():
		total += (r as RegionState).population
	var region: RegionState = state.regions.get(region_id)
	if total <= 0.0 or region == null or region.population <= 0.0:
		return float(_region_profiles().get(region_id, {}).get("population_weight", 0.0))
	return region.population / total


static func _seed_growth_state(state: GameState, region: RegionState, profile: Dictionary) -> void:
	if region.population <= 0.0:
		region.population = float(profile.get("population_weight", 0.0)) * float(state.country.population) / 1000.0
	if region.development <= 0.0:
		region.development = clampf(0.15 + region.state_reach * 0.55 - region.unemployment * 0.8, 0.05, 0.9)


static func _attractiveness(region: RegionState) -> float:
	return (1.0 - region.unemployment * 3.0) + region.state_reach * 0.5 - region.pressure * 0.6


static func _update_population(state: GameState) -> void:
	var monthly_natural := pow(1.0 + NATURAL_GROWTH_PER_YEAR, 1.0 / 12.0) - 1.0
	var open: Array[RegionState] = []
	var mean := 0.0
	for r in state.regions.values():
		var region := r as RegionState
		region.population *= 1.0 + monthly_natural
		if region.control != "separatist":
			open.append(region)
			mean += _attractiveness(region)
	if open.size() < 2:
		return
	mean /= open.size()
	var flows := {}
	var net := 0.0
	for region in open:
		var flow := region.population * MIGRATION_SHARE_PER_MONTH * (_attractiveness(region) - mean)
		flows[region] = flow
		net += flow
	for region in open:
		region.population = maxf(1.0, region.population + float(flows[region]) - net / open.size())


static func _development_target(state: GameState, region: RegionState, region_id: String, profile: Dictionary) -> float:
	var portfolio := String(profile.get("development_portfolio", "Economy"))
	var ministry: MinistryState = state.ministries.get(portfolio)
	var delivery := 1.0 if ministry == null else ministry.delivery
	var programme := 0.15 if state.regional_programs.any(func(p): return p.region_id == region_id) else 0.0
	var growth := clampf(state.country.economy.growth_rate * 4.0, -0.2, 0.2)
	var crisis := (0.35 if state.civil_war else 0.0) + state.insurgency_pressure * 0.25 + region.pressure * 0.2
	var target := 0.2 + delivery * 0.35 + region.state_reach * 0.25 + programme + growth - crisis
	if region.control == "separatist":
		target = minf(target, SEPARATIST_DEVELOPMENT_CEILING)
	return clampf(target, 0.02, 0.98)


static func _advance_development(state: GameState, profiles: Dictionary) -> void:
	MinistriesSim.ensure_ministries(state)
	for region_id in state.regions.keys():
		var region: RegionState = state.regions[region_id] as RegionState
		var profile: Variant = profiles.get(String(region_id))
		if region == null or not (profile is Dictionary):
			continue
		var target := _development_target(state, region, String(region_id), profile)
		region.development = clampf(region.development + (target - region.development) * DEVELOPMENT_CONVERGENCE, 0.0, 1.0)


static func _region_profiles() -> Dictionary:
	var content: Dictionary = ContentRepositoryScript.load_all()
	var catalogs_raw: Variant = content.get("catalogs", {})
	if not (catalogs_raw is Dictionary):
		return {}
	var regions_raw: Variant = (catalogs_raw as Dictionary).get("regions_and_programs", {})
	if not (regions_raw is Dictionary):
		return {}
	var profiles_raw: Variant = (regions_raw as Dictionary).get("region_profiles", {})
	if not (profiles_raw is Dictionary):
		return {}
	return profiles_raw as Dictionary


static func _program_definitions() -> Dictionary:
	var content: Dictionary = ContentRepositoryScript.load_all()
	var catalogs_raw: Variant = content.get("catalogs", {})
	if not (catalogs_raw is Dictionary):
		return {}
	var regions_raw: Variant = (catalogs_raw as Dictionary).get("regions_and_programs", {})
	if not (regions_raw is Dictionary):
		return {}
	var programs_raw: Variant = (regions_raw as Dictionary).get("regional_programs", {})
	if not (programs_raw is Dictionary):
		return {}
	return programs_raw as Dictionary


static func ensure_region_states(state: GameState) -> void:
	if state.country == null:
		return
	if state.country.id != "ardenia":
		return
	var profiles: Dictionary = _region_profiles()
	if profiles.is_empty():
		return
	var national_support: Dictionary = {}
	for f in state.country.factions:
		national_support[f.id] = f.support
	for region_id in profiles.keys():
		var rid: String = String(region_id)
		if state.regions.has(rid):
			continue
		var profile_raw: Variant = profiles[rid]
		if not (profile_raw is Dictionary):
			continue
		var profile: Dictionary = profile_raw
		var region: RegionState = RegionState.new()
		region.id = rid
		region.unemployment = float(profile.get("initial_unemployment", 0.0))
		region.state_reach = float(profile.get("initial_state_reach", 0.0))
		region.pressure = float(profile.get("initial_pressure", 0.0))
		region.control = String(profile.get("control", "state"))
		region.issue_id = String(profile.get("issue_id", ""))
		var support_raw: Variant = profile.get("party_support", {})
		if support_raw is Dictionary:
			region.party_support = (support_raw as Dictionary).duplicate(true)
		else:
			region.party_support = {}
		region.support_anchor = national_support.duplicate(true)
		_seed_growth_state(state, region, profile)
		state.regions[rid] = region


static func simulate(state: GameState) -> void:
	ensure_region_states(state)
	if state.regions.is_empty():
		return
	var profiles: Dictionary = _region_profiles()
	var definitions: Dictionary = _program_definitions()
	for region_id in state.regions.keys():
		var rid: String = String(region_id)
		var region: RegionState = state.regions.get(rid) as RegionState
		if region == null:
			continue
		var profile_raw: Variant = profiles.get(rid)
		if not (profile_raw is Dictionary):
			continue
		var profile: Dictionary = profile_raw
		_seed_growth_state(state, region, profile)
		_tick_region(state, region, rid, profile)
	_advance_programs(state, profiles, definitions)
	_update_population(state)
	_advance_development(state, profiles)


static func _tick_region(state: GameState, region: RegionState, region_id: String,
		profile: Dictionary) -> void:
	var national_unemployment: float = state.country.economy.unemployment
	var capacity: float = state.country.bureaucratic_capacity
	var stability: float = state.stability_value

	var unemployment_target: float = clampf(
		national_unemployment + float(profile.get("unemployment_gap", 0.0))
		+ GasSim.industry_jobs_loss(state, region_id), 0.025, 0.45)
	region.unemployment = clampf(
		region.unemployment + (unemployment_target - region.unemployment) * UNEMPLOYMENT_CONVERGENCE,
		0.0, 0.60)

	var reach_target: float = capacity + float(profile.get("reach_offset", 0.0)) + (stability - 0.5) * 0.12 + (region.development - 0.5) * DEVELOPMENT_REACH_BONUS - GasSim.reach_loss(state, region_id)
	if region.control == "limited":
		reach_target = minf(reach_target, CONTROL_LIMITED_MAX)
	elif region.control == "autonomous":
		reach_target = maxf(reach_target, CONTROL_AUTONOMOUS_MIN + capacity * CONTROL_AUTONOMOUS_CAPACITY_BONUS)
		reach_target = minf(reach_target, CONTROL_AUTONOMOUS_MAX)
	elif region_id == "vetrenka" and region.control == "state":
		reach_target = maxf(reach_target, CONTROL_VETRENKA_STATE_MIN + capacity * CONTROL_VETRENKA_STATE_CAPACITY_BONUS)
		reach_target = minf(reach_target, CONTROL_VETRENKA_STATE_MAX)
	elif region.control == "separatist":
		reach_target = minf(reach_target, CONTROL_SEPARATIST_MAX)
	reach_target = clampf(reach_target, 0.02, 0.97)
	region.state_reach = clampf(
		region.state_reach + (reach_target - region.state_reach) * REACH_CONVERGENCE, 0.0, 1.0)

	var jobs_stress: float = clampf((region.unemployment - 0.055) / 0.23, 0.0, 1.0)
	var capacity_stress: float = 1.0 - region.state_reach
	var pressure_bias: float = float(profile.get("pressure_bias", 0.0))
	if region_id == "vetrenka":
		var status_raw: Variant = state.campaign_meta.get("vetrenka_status")
		if status_raw is String:
			var status_key: String = status_raw
			if VETRENKA_PRESSURE_BIAS.has(status_key):
				pressure_bias = float(VETRENKA_PRESSURE_BIAS[status_key])
	var national_stress: float = clampf((0.58 - stability) / 0.43, 0.0, 1.0)
	var pressure_target: float = clampf(
		jobs_stress * PRESSURE_JOBS_WEIGHT
		+ capacity_stress * PRESSURE_CAPACITY_WEIGHT
		+ national_stress * PRESSURE_NATIONAL_WEIGHT
		+ pressure_bias, 0.0, 1.0)
	region.pressure = clampf(
		region.pressure + (pressure_target - region.pressure) * PRESSURE_CONVERGENCE, 0.0, 1.0)


static func _advance_programs(state: GameState, profiles: Dictionary,
		definitions: Dictionary) -> void:
	if state.regional_programs.is_empty():
		return
	var still_active: Array = []
	for item in state.regional_programs:
		var program: RegionState.RegionalProgram = item as RegionState.RegionalProgram
		if program == null:
			continue
		var definition_raw: Variant = definitions.get(program.program_id)
		var region: RegionState = state.regions.get(program.region_id) as RegionState
		if not (definition_raw is Dictionary) or region == null:
			_strip_program_modifiers(state, program.id)
			continue
		var definition: Dictionary = definition_raw
		if region.control == "separatist":
			_extend_frozen_programme_funding(state, program)
			still_active.append(program)
			continue
		var quality: float = _delivery_quality(state, String(definition.get("portfolio", "")))
		var regional_fit: float = 1.0
		var mults_raw: Variant = definition.get("region_multipliers", {})
		if mults_raw is Dictionary and (mults_raw as Dictionary).has(program.region_id):
			regional_fit = float((mults_raw as Dictionary)[program.region_id])
		var scale: float = quality * regional_fit / float(maxi(1, program.duration))
		var effects: Dictionary = {}
		var effects_raw: Variant = definition.get("effects", {})
		if effects_raw is Dictionary:
			effects = effects_raw
		region.unemployment = clampf(
			region.unemployment + float(effects.get("unemployment", 0.0)) * scale, 0.0, 0.60)
		region.state_reach = clampf(
			region.state_reach + float(effects.get("state_reach", 0.0)) * scale, 0.0, 1.0)
		region.pressure = clampf(
			region.pressure + float(effects.get("pressure", 0.0)) * scale, 0.0, 1.0)
		var deltas_raw: Variant = definition.get("regional_support_deltas", {})
		if deltas_raw is Dictionary and not (deltas_raw as Dictionary).is_empty():
			_shift_party_support(region, deltas_raw, scale)
		program.months_active += 1
		if program.months_active >= program.duration:
			var region_name: String = program.region_id
			var profile_raw: Variant = profiles.get(program.region_id)
			if profile_raw is Dictionary:
				region_name = String((profile_raw as Dictionary).get("name", program.region_id))
			print("REGIONAL PROGRAMME — %s concludes in %s. Its gains now have to survive ordinary government." % [
				String(definition.get("name", program.program_id)), region_name])
			_strip_program_modifiers(state, program.id)
		else:
			still_active.append(program)
	state.regional_programs = still_active


static func _extend_frozen_programme_funding(state: GameState, program: RegionState.RegionalProgram) -> void:
	for modifier in state.modifiers:
		if modifier.source_id == program.id and modifier.target == "budget_expenditure" and modifier.hold_duration >= 0:
			modifier.hold_duration += 1

static func _delivery_quality(state: GameState, portfolio: String) -> float:
	var minister_component: float = MISSING_MINISTER_DELIVERY
	for m in state.ministers:
		if m.portfolio == portfolio:
			minister_component = m.implementation_quality()
			break
	var institutional: float = (minister_component * DELIVERY_MINISTER_SHARE
		+ state.country.bureaucratic_capacity * DELIVERY_STATE_CAPACITY_SHARE)
	var departmental: float = _department_factor(state, portfolio)
	return clampf((DELIVERY_BASE + institutional * DELIVERY_INSTITUTIONAL_WEIGHT) * departmental,
		DELIVERY_MIN, DELIVERY_MAX)


static func _department_factor(state: GameState, portfolio: String) -> float:
	if portfolio == "":
		return 1.0
	var ministry: MinistryState = state.ministries.get(portfolio) as MinistryState
	var delivery: float = 1.0 if ministry == null else ministry.delivery
	return DEPARTMENT_BASE + DEPARTMENT_DELIVERY_SHARE * delivery


static func _strip_program_modifiers(state: GameState, source_id: String) -> void:
	var kept: Array[Modifier] = []
	for m in state.modifiers:
		if m.source_id != source_id:
			kept.append(m)
	state.modifiers.assign(kept)


static func _normalise_support(support: Dictionary) -> Dictionary:
	var clean: Dictionary = {}
	for key in support.keys():
		var fid: String = String(key)
		clean[fid] = maxf(0.0, float(support[key]))
	var total: float = 0.0
	for v in clean.values():
		total += float(v)
	var ids: Array = clean.keys()
	if total <= 0.0 and not ids.is_empty():
		for fid_key in ids:
			clean[String(fid_key)] = 1.0 / float(ids.size())
	elif total > 0.0:
		for fid_key in clean.keys():
			clean[fid_key] = float(clean[fid_key]) / total
	return clean


static func _shift_party_support(region: RegionState, deltas: Dictionary, scale: float) -> void:
	var shifted: Dictionary = region.party_support.duplicate(true)
	for key in deltas.keys():
		var fid: String = String(key)
		if shifted.has(fid):
			shifted[fid] = maxf(0.001, float(shifted[fid]) + float(deltas[key]) * scale)
	region.party_support = _normalise_support(shifted)
