class_name BudgetSim
extends RefCounted

## The fiscal year: seeding a campaign's first settlement, putting a voted
## plan into force on 1 January, and what happens when there is no plan.
##
## Design intent (docs/godot/SIM_REDESIGN.md; review S2): failing to govern
## must never be the clever move. A government that reaches January without
## a budget runs on an emergency continuing resolution — spending continues
## at last year's levels so the state does not stop, but no new programme can
## start, every ministry carries the extra work of operating under emergency
## rules, and the political cost mounts each month it lasts. It is survivable
## and always worse than a settlement. The player ends it by passing a budget
## for the current year, which takes effect at once.
##
## Player-authored preview/proposal/lobby/vote/withdraw lives in
## actions/budget_actions.gd; the parliamentary projection lives in
## sim/parliamentary_vote.gd.

## Total appropriations may move at most this far from the current year.
const MIN_TOTAL_FACTOR := 0.70
const MAX_TOTAL_FACTOR := 1.30

## The day the resolution starts: a visible failure, not a catastrophe.
const EMERGENCY_START_APPROVAL_COST := 0.02
const EMERGENCY_START_STABILITY_COST := 0.02
## Every month it lasts, it costs this much, growing as it drags on
## (doubling after EMERGENCY_ESCALATION_MONTHS).
const EMERGENCY_MONTHLY_APPROVAL_COST := 0.003
const EMERGENCY_MONTHLY_STABILITY_COST := 0.004
const EMERGENCY_ESCALATION_MONTHS := 6.0
## Extra workload every ministry carries while running on emergency rules,
## and the most it can grow to.
const EMERGENCY_BASE_WORKLOAD := 0.06
const EMERGENCY_WORKLOAD_PER_MONTH := 0.01
const EMERGENCY_MAX_WORKLOAD := 0.18

const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")


## Splits `expenditure` across the authored envelope shares, giving the last
## envelope the exact remainder so the total is exact despite rounding.
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


static func _envelopes() -> Array:
	var content: Dictionary = ContentRepositoryScript.load_all()
	var catalogs: Dictionary = content.get("catalogs", {})
	var budget_catalog: Dictionary = catalogs.get("budget", {})
	var envelopes: Variant = budget_catalog.get("envelopes", [])
	return envelopes if envelopes is Array else []


## Seeds the campaign's first settlement from primary spending, then returns
## the active budget.
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


## True while the state runs on an emergency continuing resolution.
static func is_emergency(state: GameState) -> bool:
	return state != null and state.active_budget != null \
		and state.active_budget.source == "continuing"


## Extra work each ministry carries under emergency rules right now.
static func emergency_workload(state: GameState) -> float:
	if not is_emergency(state):
		return 0.0
	return minf(EMERGENCY_MAX_WORKLOAD,
		EMERGENCY_BASE_WORKLOAD + EMERGENCY_WORKLOAD_PER_MONTH * state.active_budget.emergency_months)


## Puts `plan` into force. The history records exactly what was voted; the
## active budget carries the same shares, grown by the economy since the plan
## was tabled, and primary spending moves to match it.
static func activate(state: GameState, plan: AnnualBudget) -> AnnualBudget:
	var activated := AnnualBudget.from_dict(plan.to_dict())
	activated.status = "active"
	activated.emergency_months = 0
	var record := AnnualBudget.from_dict(activated.to_dict())
	var basis := plan.economy_basis
	var now := state.country.economy.structural_revenue
	if basis > 0.0 and now > 0.0:
		var growth := now / basis
		for key in activated.allocations.keys():
			activated.allocations[key] = float(activated.allocations[key]) * growth
	activated.economy_basis = now
	state.active_budget = activated
	state.country.economy.structural_expenditure = activated.expenditure()
	state.budget_history.append(record)
	return activated


## Last year's appropriations carried forward unchanged, under emergency rules.
static func _emergency_resolution(state: GameState) -> AnnualBudget:
	var active := ensure_budget_state(state)
	var b := AnnualBudget.new()
	b.year = state.year
	b.allocations = active.allocations.duplicate()
	b.status = "active"
	b.source = "continuing"
	b.proposed_by = state.ruling_faction_id
	b.forecast_revenue = state.country.economy.budget.revenue
	return b


## A restrained plan written from the ruling party's own ideology. An
## opposition player is never punished for a budget they do not control.
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


## Monthly fiscal close. On 1 January a voted plan takes effect, an
## opposition player's government enacts its own, or an emergency
## resolution begins. Every month an emergency resolution lasts, its
## political cost is paid.
static func process_fiscal_year(state: GameState) -> void:
	var active := ensure_budget_state(state)
	if state.month == 1 and active.year < state.year:
		_open_fiscal_year(state)
	elif is_emergency(state):
		_emergency_month(state)


static func _open_fiscal_year(state: GameState) -> void:
	var queued := state.pending_budget
	if queued != null and queued.year == state.year and queued.status == "approved":
		state.pending_budget = null
		activate(state, queued)
		return

	if not state.player.in_government:
		activate(state, _government_ai_budget(state))
		state.pending_budget = null
		return

	activate(state, _emergency_resolution(state))
	state.pending_budget = null
	state.player.approval = maxf(0.0, state.player.approval - EMERGENCY_START_APPROVAL_COST)
	state.stability_value = maxf(0.0, state.stability_value - EMERGENCY_START_STABILITY_COST)


static func _emergency_month(state: GameState) -> void:
	var active := state.active_budget
	active.emergency_months += 1
	var escalation := 1.0 + float(active.emergency_months) / EMERGENCY_ESCALATION_MONTHS
	# Only a government is blamed for having no budget.
	if state.player.in_government:
		state.player.approval = maxf(0.0, state.player.approval - EMERGENCY_MONTHLY_APPROVAL_COST * escalation)
	state.stability_value = maxf(0.0, state.stability_value - EMERGENCY_MONTHLY_STABILITY_COST * escalation)


static func _round1(value: float) -> float:
	return roundf(value * 10.0) / 10.0
