class_name RegionsSim
extends RefCounted

## Typed port of engine/regions.py: simulate_regions, _advance_programs and
## program_delivery_quality — Ardenia's monthly regional conditions (local
## unemployment, state reach, political pressure) plus single-month delivery
## of any active RegionalProgram.
##
## Only Ardenia has an authored regional layer; every other country keeps an
## empty `state.regions` (same as the Python reference). Regions live on
## `GameState.regions` only — never `Country.regions`, no per-tick
## reallocation. Call convention is static, matching `ministries_sim.gd`
## (`RegionsSim.ensure_region_states` / `RegionsSim.simulate`).
##
## NOT wired into any turn loop here — Task 10 owns the monthly pulse wiring
## (same standing note as Task 6's ministries work). Electoral *dynamics*
## (`update_party_support` / projection / judgment, `campaign_in_region`) are
## OUT of scope: they need Task 9 households. Only seed values are carried.
## Programme start verbs (`start_program` / `can_start` / `available`) are OUT
## too (later phase); tests construct `RegionalProgram` objects directly.
##
## Documented deviations from the Python reference (deliberate, not drift):
##   - Separatist delivery freeze: Python gates only programme *start* on
##     control, but a state that cannot reach a territory cannot progress work
##     there either — so a separatist-control region gets no delivered effects
##     AND no `months_active` increment that month. The programme stays
##     active, frozen; its booked treasury Modifier is untouched (parliament
##     committed the money). Known interaction (review finding, Task 8):
##     frozen months extend wall-clock duration past the Modifier's booked
##     hold window, so late delivery months run unfunded — accepted for now;
##     Task 10 (pulse wiring) should extend the hold by frozen months or
##     explicitly accept the slip. See the ledger's Task 10 carry-forward.
##   - Completion notice goes through `print()`, not `state.log()`: no native
##     `turn_log` / `event_history` store exists yet, and adding one would be
##     a save-schema change (an explicit non-goal). The wording matches
##     Python's log line.
##   - The departmental delivery multiplier reads `state.ministries` directly
##     without seeding (default `delivery == 1.0` for a missing portfolio, the
##     same value a freshly-seeded MinistryState carries) instead of calling
##     into `MinistriesSim`'s seeding path — the same no-surprising-coupling
##     precedent `economy_sim.gd` documents for its own delivery factor.
##     `MinistriesSim` exposes no public `policy_delivery_factor` (only the
##     minister-side `Minister.implementation_quality()` is real and public),
##     so this file duplicates that two-line multiplier locally rather than
##     reaching into another sim's privates.
##   - Control NEVER flips in the passive tick — carried over exactly as the
##     Python design holdover documents it.

const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")

## Pressure-target weights (engine/regions.py module constants).
const PRESSURE_JOBS_WEIGHT := 0.40
const PRESSURE_CAPACITY_WEIGHT := 0.30
const PRESSURE_NATIONAL_WEIGHT := 0.16

## Monthly convergence rates toward each target.
const UNEMPLOYMENT_CONVERGENCE := 0.14
const REACH_CONVERGENCE := 0.05
const PRESSURE_CONVERGENCE := 0.12

## State-reach target caps by control (engine/regions.py: simulate_regions).
const CONTROL_LIMITED_MAX := 0.48
const CONTROL_AUTONOMOUS_MIN := 0.24
const CONTROL_AUTONOMOUS_CAPACITY_BONUS := 0.12
const CONTROL_AUTONOMOUS_MAX := 0.42
const CONTROL_VETRENKA_STATE_MIN := 0.22
const CONTROL_VETRENKA_STATE_CAPACITY_BONUS := 0.32
const CONTROL_VETRENKA_STATE_MAX := 0.58
const CONTROL_SEPARATIST_MAX := 0.08

## Delivery quality bounds and composition (engine/regions.py:
## program_delivery_quality; missing minister reads as 0.35 there).
const DELIVERY_BASE := 0.45
const DELIVERY_INSTITUTIONAL_WEIGHT := 0.55
const DELIVERY_MIN := 0.30
const DELIVERY_MAX := 1.0
const MISSING_MINISTER_DELIVERY := 0.35
const DELIVERY_MINISTER_SHARE := 0.65
const DELIVERY_STATE_CAPACITY_SHARE := 0.35
const DEPARTMENT_BASE := 0.55
const DEPARTMENT_DELIVERY_SHARE := 0.45

## Vetrenka pressure-bias overrides by campaign outcome
## (engine/regions.py: simulate_regions); any unknown status keeps the
## profile's authored bias.
const VETRENKA_PRESSURE_BIAS := {
	"settled": 0.07,
	"retaken": 0.17,
	"routed": 0.25,
	"partitioned": 0.11,
	"partitioned_contested": 0.20,
	"talks_failed": 0.23,
}


## The authored region profiles from the exported content catalogue — the
## JSON I/O boundary (dictionaries only here, never as state).
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


## The authored programme definitions from the same catalogue.
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


## Seed only missing authored region ids; never clobber live values
## (additive setdefault semantics — engine/regions.py: ensure_region_states).
## Loads profiles itself, same pattern as `BudgetSim.ensure_budget_state`.
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
		state.regions[rid] = region


## Full monthly tick: ensure-seed first (Ardenia seeds, then proceeds;
## non-Ardenia stays empty and returns), then unemployment/reach/pressure per
## region, then exactly one programme-advancement pass.
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
		_tick_region(state, region, rid, profile)
	_advance_programs(state, profiles, definitions)


## One region's unemployment/reach/pressure convergence for the month —
## engine/regions.py: simulate_regions, same order (pressure reads the
## just-updated local unemployment and reach).
static func _tick_region(state: GameState, region: RegionState, region_id: String,
		profile: Dictionary) -> void:
	var national_unemployment: float = state.country.economy.unemployment
	var capacity: float = state.country.bureaucratic_capacity
	var stability: float = state.stability_value

	var unemployment_target: float = clampf(
		national_unemployment + float(profile.get("unemployment_gap", 0.0)), 0.025, 0.45)
	region.unemployment = clampf(
		region.unemployment + (unemployment_target - region.unemployment) * UNEMPLOYMENT_CONVERGENCE,
		0.0, 0.60)

	var reach_target: float = capacity + float(profile.get("reach_offset", 0.0)) + (stability - 0.5) * 0.12
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


## One month of delivery for every active programme — engine/regions.py:
## _advance_programs. Increment-then-test `>= duration`: completion removes
## the programme exactly once with its modifier cleanup. Unknown programme or
## region ids strip their modifiers and drop silently.
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


## A separatist freeze preserves only the programme’s own finite treasury
## window. This runs before Modifiers.age_all in NativeGame, so the final
## booked payable month is retained while delivery is inaccessible.
static func _extend_frozen_programme_funding(state: GameState, program: RegionState.RegionalProgram) -> void:
	for modifier in state.modifiers:
		if modifier.source_id == program.id and modifier.target == "budget_expenditure" and modifier.hold_duration >= 0:
			modifier.hold_duration += 1

## Cabinet and state capacity determine how much of a budget reaches dirt —
## engine/regions.py: program_delivery_quality. Missing minister reads as
## 0.35; the result clamps to 0.30-1.0.
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


## Moderate multiplier: workload compounds existing implementation, not
## replaces it — mirrors engine/ministries.py: policy_delivery_factor, except
## it never seeds a missing portfolio (see this file's header note).
static func _department_factor(state: GameState, portfolio: String) -> float:
	if portfolio == "":
		return 1.0
	var ministry: MinistryState = state.ministries.get(portfolio) as MinistryState
	var delivery: float = 1.0 if ministry == null else ministry.delivery
	return DEPARTMENT_BASE + DEPARTMENT_DELIVERY_SHARE * delivery


## Drop every modifier booked against a finished (or orphaned) programme.
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
