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

var _state: GameState = null
var _busy := false


func _ready() -> void:
	pass


## Starts a fresh Ardenia campaign from `config` (GameFactory's keys:
## country_id, background_id, difficulty_id, opening_role, plus an explicit
## int seed). The factory-built RNG is reseeded from the config seed, then
## the state is validated; a rejection keeps the OLD state and reports
## {ok:false} through the return dict plus fatal_error (defensive — a
## factory-built state must not fail validation).
func new_campaign(config: Dictionary) -> Dictionary:
	if _busy:
		return {"ok": false, "error": "another NativeGame operation is already in flight"}
	_busy = true
	var result := _do_new_campaign(config)
	_busy = false
	return result


## Advances the calendar by exactly one day. Modifier aging runs here too,
## but only when the day crosses a month boundary (mirroring
## TurnEngine._age_modifiers, which is monthly, not daily). The rest of the
## monthly simulation pulse — economy, approval, stability — is Phase 2
## work, not here.
func advance_day() -> Dictionary:
	if _busy:
		return {"ok": false, "error": "another NativeGame operation is already in flight"}
	if _state == null:
		return {"ok": false, "error": "no campaign is active"}
	_busy = true
	var month_rolled := Calendar.advance_day(_state)
	if month_rolled:
		Modifiers.age_all(_state)
	var snap := snapshot()
	state_changed.emit(snap)
	_busy = false
	return {"ok": true, "snapshot": snap, "month_rolled": month_rolled}


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


## Replaces the live campaign with the contents of `slot`, then validates
## (same defensive posture as new_campaign: a rejection keeps the OLD
## state, reports {ok:false}, and surfaces through fatal_error).
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
		fatal_error.emit(message)
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
	var content := ContentRepository.load_all()
	if content.has("error"):
		var content_message := "Could not load campaign content: %s" % [content["error"]]
		fatal_error.emit(content_message)
		return {"ok": false, "error": content_message}
	var fresh: GameState = GameFactory.new_campaign(content, config)
	if fresh == null:
		var factory_message := "Could not build a campaign from the given config."
		fatal_error.emit(factory_message)
		return {"ok": false, "error": factory_message}
	fresh.rng = SimRng.from_seed(int(config.get("seed", 0)))
	var errors := StateValidator.validate(fresh)
	if not errors.is_empty():
		var validation_message := "New campaign failed validation: %s" % [", ".join(errors)]
		fatal_error.emit(validation_message)
		return {"ok": false, "error": validation_message}
	_state = fresh
	var snap := snapshot()
	state_changed.emit(snap)
	return {"ok": true, "snapshot": snap}


## The UI read model: only what apply_snapshot renders, nothing it could
## use to reach back into live objects. Regions come from live state
## (empty until a later phase seeds the regional layer); decisions, the
## monthly digest, dispatches, and reform objectives are likewise empty
## until their systems land — the UI already renders every one of those
## empty states.
static func _build_snapshot(state: GameState) -> Dictionary:
	var regions: Array = []
	for key in state.regions.keys():
		var region: RegionState = state.regions[key]
		regions.append({
			"id": region.id,
			"pressure": region.pressure,
			"unemployment": region.unemployment,
			"state_reach": region.state_reach,
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
		"headline": {"stability": _stability_label(state.stability_value), "attention_spent": 0},
		"economy": economy,
		"regions": regions,
		"factions": factions,
		"decisions": [],
		"digest": [],
		"reform": {"active": null, "objectives": []},
		"dispatches": [],
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
