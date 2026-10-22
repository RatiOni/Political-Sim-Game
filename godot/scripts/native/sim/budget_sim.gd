class_name BudgetSim
extends RefCounted

## Typed port of engine/budget.py's fiscal-year lifecycle, scoped to what
## Phase 2 Task 5 needs: seeding a fresh campaign's `AnnualBudget` (native
## `GameFactory` deliberately leaves `active_budget` unset — see
## game_factory.gd's header note) and the January-rollover decision tree
## (`process_fiscal_year`).
##
## Player-authored preview/proposal/lobby/vote/withdraw behavior lives in
## actions/budget_actions.gd; its pure parliamentary projection lives in
## sim/parliamentary_vote.gd. This file remains the fiscal-year lifecycle owner.
##
## NOT ported (out of this task's scope, matching the brief):
##   - `_normalise_plan_envelopes` (legacy 7-envelope save migration) — no
##     native save has ever used the old shape, so there is nothing to
##     migrate from.
##   - Supplementary appropriations (`apply_supplementary` and friends) — a
##     distinct mid-year mechanic the brief doesn't ask for.

## Governing an in-year settlement's rules, mirroring engine/budget.py.
const CONTINUING_CUT := 0.03
const MIN_TOTAL_FACTOR := 0.70
const MAX_TOTAL_FACTOR := 1.30

const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")


## Splits `expenditure` across the exported envelope catalog's authored
## shares (content/budget.py: BUDGET_ENVELOPES, exported to
## godot/data/native/catalogs/budget.json), giving the LAST envelope the
## exact remainder so the total matches `expenditure` to the cent despite
## per-envelope rounding — mirrors engine/budget.py: default_allocations.
## `envelopes` is the raw catalog list of {id, share, ...} dicts.
static func default_allocations(envelopes: Array, expenditure: float) -> Dictionary:
	var total := maxf(0.0, expenditure)
	var out := {}
	var used := 0.0
	for i in range(envelopes.size() - 1):
		var item: Dictionary = envelopes[i]
		var amount := _round1(total * float(item.get("share", 0.0)))
		out[String(item["id"])] = amount
		used += amount
	if not envelopes.is_empty():
		var last: Dictionary = envelopes[envelopes.size() - 1]
		out[String(last["id"])] = _round1(total - used)
	return out


## The budget envelope catalog, loaded fresh via ContentRepository (mirrors
## the rest of this codebase's pattern — see native_game.gd:_do_new_campaign
## — of re-reading exported content rather than caching it; this is static
## build data, and process_fiscal_year runs at most once a month).
static func _envelopes() -> Array:
	var content: Dictionary = ContentRepositoryScript.load_all()
	var catalogs: Dictionary = content.get("catalogs", {})
	var budget_catalog: Dictionary = catalogs.get("budget", {})
	var envelopes: Variant = budget_catalog.get("envelopes", [])
	return envelopes if envelopes is Array else []


## Seeds `state.active_budget` from the country's structural fiscal baseline
## if it is not already set, then returns it — mirrors
## engine/budget.py: ensure_budget_state (minus the legacy-envelope
## migration; see header note).
static func ensure_budget_state(state: GameState) -> AnnualBudget:
	if state.active_budget == null:
		var budget := AnnualBudget.new()
		budget.year = state.year
		budget.allocations = default_allocations(_envelopes(), state.country.economy.structural_expenditure)
		budget.status = "active"
		budget.source = "inherited"
		budget.forecast_revenue = state.country.economy.structural_revenue
		state.active_budget = budget
	return state.active_budget


## Activates `plan` as the new `active_budget`: a detached copy (via
## to_dict/from_dict, so later mutation of `plan` or `state.active_budget`
## can never alias the other — mirrors Python's `copy.deepcopy`) becomes
## `state.active_budget`, the country's structural expenditure baseline
## moves to match it, and another detached copy is appended to
## `budget_history` — mirrors engine/budget.py: activate.
static func _activate(state: GameState, plan: AnnualBudget) -> AnnualBudget:
	var activated := AnnualBudget.from_dict(plan.to_dict())
	activated.status = "active"
	state.active_budget = activated
	state.country.economy.structural_expenditure = activated.expenditure()
	state.budget_history.append(AnnualBudget.from_dict(activated.to_dict()))
	return activated


## A reduced (CONTINUING_CUT) rollover of the current active budget for when
## no plan was passed in time — mirrors engine/budget.py: continuing_budget.
static func _continuing_budget(state: GameState) -> AnnualBudget:
	var active := ensure_budget_state(state)
	var allocations := {}
	for key in active.allocations.keys():
		allocations[key] = _round1(float(active.allocations[key]) * (1.0 - CONTINUING_CUT))
	var b := AnnualBudget.new()
	b.year = state.year
	b.allocations = allocations
	b.status = "continuing"
	b.source = "continuing"
	b.proposed_by = state.ruling_faction_id
	b.forecast_revenue = state.country.economy.budget.revenue
	return b


## A restrained annual plan authored from the actual ruling party's
## ideology, enacted without punishing an opposition player for a budget
## they don't control — mirrors engine/budget.py: government_ai_budget.
static func _government_ai_budget(state: GameState) -> AnnualBudget:
	var active := ensure_budget_state(state)
	var ruling: Faction = null
	for f in state.country.factions:
		if f.id == state.ruling_faction_id:
			ruling = f
			break
	var economic := 0.0
	var social := 0.0
	if ruling != null:
		economic = ruling.ideology.economic
		social = ruling.ideology.social

	var changes := {}
	for key in active.allocations.keys():
		changes[key] = 0.0
	if economic >= 0.2:
		changes["state_administration"] = -0.02
		changes["industry_and_jobs"] = -0.04
		changes["health_and_welfare"] = -0.03
		changes["national_defense"] = 0.03 if social < 0.0 else 0.0
	elif economic <= -0.2:
		changes["education"] = 0.03
		changes["health_and_welfare"] = 0.04
		changes["industry_and_jobs"] = 0.03
		changes["national_defense"] = -0.03 if social > -0.4 else 0.0

	var allocations := {}
	for key in active.allocations.keys():
		var change: float = changes.get(key, 0.0)
		allocations[key] = _round1(float(active.allocations[key]) * (1.0 + change))

	var votes_for := 0
	var votes_against := 0
	for f in state.country.factions:
		if f.in_coalition:
			votes_for += f.seats
		else:
			votes_against += f.seats

	var b := AnnualBudget.new()
	b.year = state.year
	b.allocations = allocations
	b.status = "active"
	b.source = "government_ai"
	b.proposed_by = state.ruling_faction_id
	b.forecast_revenue = state.country.economy.budget.revenue
	b.votes_for = votes_for
	b.votes_against = votes_against
	return b


## Activates a voted plan, or an in-lieu one, at 1 January. Player-authored
## approved plans are created by BudgetActions and remain pending until here.
static func process_fiscal_year(state: GameState) -> void:
	var active := ensure_budget_state(state)
	if state.month != 1 or active.year >= state.year:
		return

	var queued := state.pending_budget
	if queued != null and queued.year == state.year and queued.status == "approved":
		state.pending_budget = null
		_activate(state, queued)
		return

	if not state.player.in_government:
		var enacted := _government_ai_budget(state)
		_activate(state, enacted)
		state.pending_budget = null
		return

	var fallback := _continuing_budget(state)
	_activate(state, fallback)
	state.pending_budget = null
	state.player.approval = maxf(0.0, state.player.approval - 0.015)
	state.stability_value = maxf(0.0, state.stability_value - 0.02)


static func _round1(value: float) -> float:
	return roundf(value * 10.0) / 10.0
