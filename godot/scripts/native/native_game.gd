extends Node

## The in-process owner of the live campaign (Phase 1 Task 4 unit B). One
## private GameState, one single-operation in-flight guard, synchronous
## return-dict calls — the UI reads snapshots and acts through these methods
## directly, with no request/response round trip. Snapshots are plain
## Dictionaries, but only as the UI boundary: the campaign itself is always
## the typed GameState, never a Dictionary.
##
## _ready() is deliberately side-effect free: it starts no campaign, so
## headless tests can load the autoload tree without doing any work.
##
## No `class_name` here, deliberately: this script IS the NativeGame
## autoload, and Godot 4.7 rejects a global class that hides an autoload
## singleton (hard parse error, not a warning). Reach the singleton via
## get_node("/root/NativeGame"); preload this script path for isolated
## test instances. (Same shape as game_flow.gd, the other autoload.)

signal state_changed(snapshot: Dictionary)
signal fatal_error(message: String)

const _MONTH_NAMES := ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

# Preloaded (not a bare class_name reference): SaveStore is new enough that
# headless runs may not have it in the editor's global class cache yet —
# the same reason the persistence suite preloads it.
const SaveStoreScript = preload("res://scripts/native/state/save_store.gd")
const BudgetSimScript = preload("res://scripts/native/sim/budget_sim.gd")
const PoliticalCapitalScript = preload("res://scripts/native/sim/political_capital.gd")
const MinistriesSimScript = preload("res://scripts/native/sim/ministries_sim.gd")
const EconomySimScript = preload("res://scripts/native/sim/economy_sim.gd")
const RegionsSimScript = preload("res://scripts/native/sim/regions_sim.gd")
const HouseholdsSimScript = preload("res://scripts/native/sim/households_sim.gd")
const StabilitySimScript = preload("res://scripts/native/sim/stability_sim.gd")
const MonthlyDigestScript = preload("res://scripts/native/presentation/monthly_digest.gd")
const RegionalProgramActionsScript = preload("res://scripts/native/actions/regional_program_actions.gd")

var _state: GameState = null
var _busy := false


func _ready() -> void:
	pass


## Starts a fresh Ardenia campaign from `config` (GameFactory's keys:
## country_id, background_id, difficulty_id, opening_role, plus an explicit
## int seed). The factory-built RNG is reseeded from the config seed, then
## the state is validated; a rejection keeps the OLD state and reports
## {ok:false} through the return dict. fatal_error is emitted ONLY when there
## is no valid live campaign to show (_state == null) — a recoverable failure
## behind a live campaign must never brick the UI behind the blocker.
func new_campaign(config: Dictionary) -> Dictionary:
	if _busy:
		return {"ok": false, "error": "another NativeGame operation is already in flight"}
	_busy = true
	var result := _do_new_campaign(config)
	# Emits happen while _busy is held, deliberately: a subscriber that calls
	# back into NativeGame mid-notification is refused by the guard instead
	# of recursing into a half-observed operation (reentrant emission was
	# observed to recurse ~1000 deep and spew engine stack errors).
	if result.get("ok", false):
		state_changed.emit(result.get("snapshot", {}))
	elif _state == null:
		fatal_error.emit(str(result.get("error", "Unknown error")))
	_busy = false
	return result


## Advances the calendar by exactly one day. On a month boundary it runs the
## complete Phase 2 pulse once, then ages modifiers and stores the completed
## monthly digest. Ordinary days change only the calendar.
func advance_day() -> Dictionary:
	if _busy:
		return {"ok": false, "error": "another NativeGame operation is already in flight"}
	if _state == null:
		return {"ok": false, "error": "no campaign is active"}
	_busy = true
	var month_rolled := Calendar.advance_day(_state)
	if month_rolled:
		var before: Dictionary = MonthlyDigestScript.capture(_state)
		_state.turn += 1
		BudgetSimScript.process_fiscal_year(_state)
		PoliticalCapitalScript.regenerate(_state)
		MinistriesSimScript.simulate(_state)
		EconomySimScript.update(_state)
		RegionsSimScript.simulate(_state)
		HouseholdsSimScript.simulate(_state)
		StabilitySimScript.update_approval(_state)
		StabilitySimScript.update_stability(_state)
		Modifiers.age_all(_state)
		_state.monthly_digest = MonthlyDigestScript.build(_state, before)
	var snap := snapshot()
	state_changed.emit(snap)
	_busy = false
	return {"ok": true, "snapshot": snap, "month_rolled": month_rolled}


## Launches one authored regional programme. The action service owns every
## rule and effect; this method owns the operation guard and notification.
func start_regional_program(region_id: String, program_id: String) -> Dictionary:
	if _busy:
		return {"ok": false, "error": "another NativeGame operation is already in flight"}
	if _state == null:
		return {"ok": false, "error": "no campaign is active"}
	_busy = true
	var content := ContentRepository.load_all()
	if content.has("error"):
		_busy = false
		return {"ok": false, "error": "Could not load regional programme content: %s" % content["error"]}
	var result: Dictionary = RegionalProgramActionsScript.start(_state, region_id, program_id, content)
	if result.get("ok", false):
		var snap := snapshot()
		result["snapshot"] = snap
		state_changed.emit(snap)
	_busy = false
	return result


## Persists the live campaign under `slot`. SaveStore's {ok} passes
## straight through; saves never mutate or emit.
func save(slot: String) -> Dictionary:
	if _busy:
		return {"ok": false, "error": "another NativeGame operation is already in flight"}
	if _state == null:
		return {"ok": false, "error": "no campaign is active"}
	_busy = true
	var result := SaveStoreScript.save_slot(slot, _state)
	_busy = false
	return result


## Replaces the live campaign with the contents of `slot`, then validates.
## A rejection keeps the OLD state and reports {ok:false} — never through
## fatal_error (the caller shows LOAD FAILED and keeps playing).
func load(slot: String) -> Dictionary:
	if _busy:
		return {"ok": false, "error": "another NativeGame operation is already in flight"}
	_busy = true
	var stored := SaveStoreScript.load_slot(slot)
	if not stored.get("ok", false):
		_busy = false
		return stored
	var incoming: GameState = stored.get("state")
	var errors := StateValidator.validate(incoming)
	if not errors.is_empty():
		_busy = false
		var message := "Loaded campaign failed validation: %s" % [", ".join(errors)]
		return {"ok": false, "error": message}
	_state = incoming
	var snap := snapshot()
	state_changed.emit(snap)
	_busy = false
	return {"ok": true, "snapshot": snap}


## A deep-duplicated, read-only view of the live campaign in exactly the
## shape app.gd's apply_snapshot reads (date.text, player, headline,
## economy, factions, regions, decisions, digest, dispatches, reform).
## Mutating the returned Dictionary never touches live state. Empty when
## no campaign is active.
func snapshot() -> Dictionary:
	if _state == null:
		return {}
	return _build_snapshot(_state).duplicate(true)


func _do_new_campaign(config: Dictionary) -> Dictionary:
	# Never emits: the caller emits state_changed / fatal_error while still
	# holding _busy, so a reentrant subscriber calling back in is refused by
	# the in-flight guard instead of recursing into a half-observed
	# operation. Emitting here would be equivalent, but a single emit site
	# per public method keeps the guard coverage obvious.
	var content := ContentRepository.load_all()
	if content.has("error"):
		var content_message := "Could not load campaign content: %s" % [content["error"]]
		return {"ok": false, "error": content_message}
	var fresh: GameState = GameFactory.new_campaign(content, config)
	if fresh == null:
		var factory_message := "Could not build a campaign from the given config."
		return {"ok": false, "error": factory_message}
	fresh.rng = SimRng.from_seed(int(config.get("seed", 0)))
	var errors := StateValidator.validate(fresh)
	if not errors.is_empty():
		var validation_message := "New campaign failed validation: %s" % [", ".join(errors)]
		return {"ok": false, "error": validation_message}
	_state = fresh
	var snap := snapshot()
	return {"ok": true, "snapshot": snap}


## The UI read model: only observational data, with every nested container
## detached by snapshot(). Phase 2 exposes live regions, budget, ministries,
## households and the completed monthly digest; later systems retain their
## explicit empty placeholders.
static func _build_snapshot(state: GameState) -> Dictionary:
	var content := ContentRepository.load_all()
	var regional_catalog: Dictionary = content.get("catalogs", {}).get("regions_and_programs", {}) if not content.has("error") else {}
	var profiles: Dictionary = regional_catalog.get("region_profiles", {})
	var definitions: Dictionary = regional_catalog.get("regional_programs", {})
	var active_by_region := {}
	for active in state.regional_programs:
		if active is RegionState.RegionalProgram:
			active_by_region[active.region_id] = active
	var regions: Array = []
	for key in state.regions.keys():
		var region: RegionState = state.regions[key]
		var profile: Dictionary = profiles.get(region.id, {})
		var active_model: Variant = null
		if active_by_region.has(region.id):
			var active: RegionState.RegionalProgram = active_by_region[region.id]
			var definition: Dictionary = definitions.get(active.program_id, {})
			active_model = {
				"instance_id": active.id,
				"program_id": active.program_id,
				"name": String(definition.get("name", active.program_id.capitalize())),
				"short_name": String(definition.get("short_name", definition.get("name", active.program_id.capitalize()))),
				"months_active": active.months_active,
				"duration": active.duration,
				"monthly_cost": active.monthly_cost,
			}
		regions.append({
			"id": region.id,
			"name": String(profile.get("name", region.id.capitalize())),
			"pressure": region.pressure,
			"unemployment": region.unemployment,
			"state_reach": region.state_reach,
			"control": region.control,
			"issue_id": region.issue_id,
			"active_program": active_model,
			"program_options": RegionalProgramActionsScript.options_for(state, region.id, content),
		})
	regions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	var factions: Array = []
	if state.country != null:
		for faction in state.country.factions:
			factions.append({
				"id": faction.id,
				"name": faction.name,
				"seats": faction.seats,
				"support": faction.support,
				"loyalty": faction.loyalty,
				"in_coalition": faction.in_coalition,
				"color": faction.color,
			})
	var economy := {"growth": 0.0, "unemployment": 0.0, "inflation": 0.0,
		"debt": 0.0, "revenue": 0.0, "expenditure": 0.0}
	if state.country != null and state.country.economy != null:
		var source: Economy = state.country.economy
		economy = {
			"growth": source.growth_rate,
			"unemployment": source.unemployment,
			"inflation": source.inflation,
			"debt": source.public_debt_pct,
			"revenue": source.budget.revenue if source.budget != null else 0.0,
			"expenditure": source.budget.expenditure if source.budget != null else 0.0,
		}
	var player := {"name": "", "title": "", "party_id": "",
		"in_government": true, "approval": 0.5, "political_capital": 0.0}
	if state.player != null:
		player = {
			"name": state.player.name,
			"title": state.player.title,
			"party_id": state.player.faction_id,
			"in_government": state.player.in_government,
			"approval": state.player.approval,
			"political_capital": state.player.political_capital,
		}
	return {
		"date": {
			"text": _date_text(state),
			"year": state.year,
			"month": state.month,
			"day": state.day,
			"day_index": state.day_index,
			"turn": state.turn,
		},
		"player": player,
		"headline": {"stability": _stability_label(state.stability_value), "value": state.stability_value, "attention_spent": 0},
		"economy": economy,
		"regions": regions,
		"factions": factions,
		"decisions": [],
		"budget": _budget_snapshot(state),
		"ministries": _ministries_snapshot(state),
		"households": _household_snapshot(state),
		"digest": state.monthly_digest.duplicate(),
		"reform": {"active": null, "objectives": []},
		"dispatches": [],
	}


static func _budget_snapshot(state: GameState) -> Dictionary:
	if state.active_budget == null:
		return {}
	return {
		"year": state.active_budget.year,
		"status": state.active_budget.status,
		"allocations": state.active_budget.allocations.duplicate(true),
		"expenditure": state.active_budget.expenditure(),
	}


static func _ministries_snapshot(state: GameState) -> Dictionary:
	var out := {}
	for portfolio in state.ministries:
		var ministry: MinistryState = state.ministries[portfolio] as MinistryState
		if ministry == null:
			continue
		out[String(portfolio)] = {
			"capacity": ministry.capacity,
			"workload": ministry.workload,
			"delivery": ministry.delivery,
			"backlog": ministry.backlog,
			"funding": ministry.funding,
			"funding_ratio": ministry.funding_ratio,
			"months_overloaded": ministry.months_overloaded,
			"workload_breakdown": ministry.workload_breakdown.duplicate(true),
		}
	return out


static func _household_snapshot(state: GameState) -> Dictionary:
	return {
		"count": state.households.size(),
		"national_confidence": HouseholdsSimScript.national_confidence(state),
		"national_hardship": HouseholdsSimScript.national_hardship(state),
		"national_real_income": HouseholdsSimScript.national_real_income(state),
		"national_living_cost": HouseholdsSimScript.national_living_cost(state),
		"national_service_access": HouseholdsSimScript.national_service_access(state),
	}

## Same abbreviated form as game_state.py: GameState.date_string
## ("1 Mar 1993") — the UI only displays this string.
static func _date_text(state: GameState) -> String:
	var month_name := str(state.month)
	if state.month >= 1 and state.month <= 12:
		month_name = _MONTH_NAMES[state.month - 1]
	return "%d %s %d" % [state.day, month_name, state.year]


## Same thresholds as models/stability.py: GovernmentStability.label —
## the UI only displays this string.
static func _stability_label(value: float) -> String:
	if value >= 0.75:
		return "Solid"
	if value >= 0.55:
		return "Stable"
	if value >= 0.35:
		return "Fragile"
	if value >= 0.20:
		return "Crisis"
	return "Collapsing"
