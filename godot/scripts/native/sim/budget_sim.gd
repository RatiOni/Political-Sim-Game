class_name BudgetSim
extends RefCounted


const MIN_TOTAL_FACTOR := 0.70
const MAX_TOTAL_FACTOR := 1.30

const EMERGENCY_START_APPROVAL_COST := 0.02
const EMERGENCY_START_STABILITY_COST := 0.02
const EMERGENCY_MONTHLY_APPROVAL_COST := 0.003
const EMERGENCY_MONTHLY_STABILITY_COST := 0.004
const EMERGENCY_ESCALATION_MONTHS := 6.0
const EMERGENCY_MAX_ESCALATION := 3.0
const EMERGENCY_BASE_WORKLOAD := 0.06
const EMERGENCY_WORKLOAD_PER_MONTH := 0.01
const EMERGENCY_MAX_WORKLOAD := 0.18

const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")


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


const AI_TILT_LIMIT := 0.05


static func is_emergency(state: GameState) -> bool:
	return state != null and state.active_budget != null \
		and state.active_budget.source == "continuing"


static func emergency_workload(state: GameState) -> float:
	if not is_emergency(state):
		return 0.0
	return minf(EMERGENCY_MAX_WORKLOAD,
		EMERGENCY_BASE_WORKLOAD + EMERGENCY_WORKLOAD_PER_MONTH * state.active_budget.emergency_months)


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


static func government_ai_budget(state: GameState) -> AnnualBudget:
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

	var reference := _reference_allocations(state)
	var current_total := 0.0
	var tilted_total := 0.0
	var tilted := {}
	for key in active.allocations.keys():
		current_total += float(active.allocations[key])
		tilted[key] = float(reference.get(key, active.allocations[key])) * (1.0 + float(changes.get(key, 0.0)))
		tilted_total += float(tilted[key])
	var allocations := {}
	for key in tilted:
		allocations[key] = _round1(float(tilted[key]) / tilted_total * current_total) if tilted_total > 0.0 else float(active.allocations[key])

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
	b.economy_basis = active.economy_basis if active.economy_basis > 0.0 else active.forecast_revenue
	b.forecast_revenue = state.country.economy.budget.revenue
	b.votes_for = votes_for
	b.votes_against = votes_against
	return b


const AI_COALITION_WHIP := 0.16
const AI_RULING_WHIP := 0.28


static func enact_ai_budget(state: GameState) -> bool:
	var plan := government_ai_budget(state)
	plan.status = "proposed"
	for f in state.country.factions:
		if f.in_coalition:
			plan.lobbying_bonus[f.id] = AI_COALITION_WHIP
	plan.lobbying_bonus[state.ruling_faction_id] = AI_RULING_WHIP
	var division := BudgetActions.projection(state, plan)
	plan.votes_for = int(division["votes_for"])
	plan.votes_against = int(division["votes_against"])
	if bool(division["passed"]):
		activate(state, plan)
		return true
	if not state.budget_history.any(func(b: AnnualBudget) -> bool: return b.source == "government_ai" and b.status == "rejected" and b.year == plan.year):
		plan.status = "rejected"
		state.budget_history.append(plan)
	if not is_emergency(state):
		state.active_budget = activate(state, _emergency_resolution(state))
	return false


static func _reference_allocations(state: GameState) -> Dictionary:
	var reference: Variant = state.campaign_meta.get("ai_budget_reference", {})
	if not (reference is Dictionary) or String(reference.get("party", "")) != state.ruling_faction_id:
		var total := 0.0
		for v in state.active_budget.allocations.values():
			total += float(v)
		var shares := {}
		for key in state.active_budget.allocations:
			shares[key] = float(state.active_budget.allocations[key]) / maxf(total, 1.0)
		reference = {"party": state.ruling_faction_id, "shares": shares}
		state.campaign_meta["ai_budget_reference"] = reference
	return reference["shares"]


static func process_fiscal_year(state: GameState) -> void:
	var active := ensure_budget_state(state)
	if state.month == 1 and active.year < state.year:
		_open_fiscal_year(state)
	elif is_emergency(state) and not state.player.in_government:
		enact_ai_budget(state)
	elif is_emergency(state):
		_emergency_month(state)


static func _open_fiscal_year(state: GameState) -> void:
	var queued := state.pending_budget
	if queued != null and queued.year == state.year and queued.status == "approved":
		state.pending_budget = null
		activate(state, queued)
		return

	if not state.player.in_government:
		state.pending_budget = null
		enact_ai_budget(state)
		return

	state.pending_budget = null
	if is_emergency(state):
		state.active_budget.year = state.year
		_emergency_month(state)
		return
	activate(state, _emergency_resolution(state))
	state.pending_budget = null
	state.player.approval = maxf(0.0, state.player.approval - EMERGENCY_START_APPROVAL_COST)
	state.stability_value = maxf(0.0, state.stability_value - EMERGENCY_START_STABILITY_COST)


static func _emergency_month(state: GameState) -> void:
	var active := state.active_budget
	active.emergency_months += 1
	var escalation := minf(EMERGENCY_MAX_ESCALATION, 1.0 + float(active.emergency_months) / EMERGENCY_ESCALATION_MONTHS)
	if state.player.in_government:
		state.player.approval = maxf(0.0, state.player.approval - EMERGENCY_MONTHLY_APPROVAL_COST * escalation)
	state.stability_value = maxf(0.0, state.stability_value - EMERGENCY_MONTHLY_STABILITY_COST * escalation)


static func _round1(value: float) -> float:
	return roundf(value * 10.0) / 10.0
