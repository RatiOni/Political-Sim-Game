class_name BudgetActions
extends RefCounted

const BudgetSimScript = preload("res://scripts/native/sim/budget_sim.gd")
const ParliamentaryVoteScript = preload("res://scripts/native/sim/parliamentary_vote.gd")
const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")

const PROPOSAL_BASE_COST := 8.0
const PROPOSAL_MOVEMENT_COST := 20.0
const PROPOSAL_COST_CAP := 18.0
const LOBBY_BASE_COST := 6.0
const LOBBY_POWER_COST := 6.0
const LOBBY_INCREMENT := 0.22
const LOBBY_CAP := 0.50
const DEFEAT_APPROVAL_PENALTY := 0.015

static var _catalog_cache: Dictionary = {}


static func preview(state: GameState, adjustments: Dictionary) -> Dictionary:
	if state == null:
		return _error("No campaign is active.")
	if state.pending_budget != null and state.pending_budget.status in ["proposed", "approved"]:
		return _error("The tabled budget is locked until parliament votes or it is withdrawn.")
	var built := _build_plan(state, adjustments)
	if not built.get("ok", false):
		return built
	return {"ok": true, "preview": _preview_plan(state, built["plan"])}


static func preview_pending(state: GameState) -> Dictionary:
	if state == null or state.pending_budget == null or state.pending_budget.status != "proposed":
		return _error("No government budget is awaiting a vote.")
	return {"ok": true, "preview": _preview_plan(state, state.pending_budget)}


static func propose(state: GameState, adjustments: Dictionary) -> Dictionary:
	if state == null or state.player == null or not state.player.in_government:
		return _error("Only the sitting government can introduce appropriations.")
	if state.pending_budget != null and state.pending_budget.status in ["proposed", "approved"]:
		return _error("A budget for the next fiscal year is already before parliament.")
	var built := _build_plan(state, adjustments)
	if not built.get("ok", false):
		return built
	var plan: AnnualBudget = built["plan"]
	var cost := proposal_cost(state, plan)
	if not is_finite(state.player.political_capital) or state.player.political_capital < cost:
		return _error("Not enough political capital (need %.0f)." % cost)
	# All checks have passed: this is the mutation boundary.
	BudgetSimScript.ensure_budget_state(state)
	state.player.political_capital -= cost
	plan.status = "proposed"
	plan.source = "player"
	plan.proposed_by = state.player.faction_id
	plan.proposed_turn = state.turn
	state.pending_budget = plan
	return {"ok": true, "message": "The %s budget is before parliament." % plan.year,
		"political_capital_cost": cost}


static func lobby(state: GameState, faction_id: String) -> Dictionary:
	var plan := _proposed_plan(state)
	if plan == null:
		return _error("No government budget is awaiting a vote.")
	var faction: Faction = null
	for candidate in state.country.factions:
		if candidate.id == faction_id:
			faction = candidate
			break
	if faction == null or faction.seats <= 0:
		return _error("That faction has no parliamentary delegation to lobby.")
	var current_bonus := float(plan.lobbying_bonus.get(faction.id, 0.0))
	if current_bonus >= LOBBY_CAP:
		return _error("That faction's lobbying bonus is already at the cap.")
	var cost := LOBBY_BASE_COST + faction.power * LOBBY_POWER_COST
	if not is_finite(state.player.political_capital) or state.player.political_capital < cost:
		return _error("Not enough political capital (need %.0f)." % cost)
	state.player.political_capital -= cost
	plan.lobbying_bonus[faction.id] = minf(LOBBY_CAP,
		float(plan.lobbying_bonus.get(faction.id, 0.0)) + LOBBY_INCREMENT)
	return {"ok": true, "message": "Lobbied %s on the %s budget." % [faction.name, plan.year],
		"political_capital_cost": cost}


static func vote(state: GameState) -> Dictionary:
	var plan := _proposed_plan(state)
	if plan == null:
		return _error("No government budget is awaiting a vote.")
	var projection := _projection(state, plan)
	plan.votes_for = int(projection["votes_for"])
	plan.votes_against = int(projection["votes_against"])
	var passed := bool(projection["passed"])
	if passed:
		plan.status = "approved"
		if plan.year == state.year:
			# An in-year settlement ends the emergency resolution at once.
			state.pending_budget = null
			BudgetSimScript.activate(state, plan)
	else:
		plan.status = "rejected"
		state.budget_history.append(plan)
		state.pending_budget = null
		state.player.approval = maxf(0.0, state.player.approval - DEFEAT_APPROVAL_PENALTY)
	_apply_rebellion_penalties(state, projection["rebellions"])
	return {"ok": true, "passed": passed, "votes_for": plan.votes_for,
		"votes_against": plan.votes_against, "threshold": projection["threshold"],
		"rebellions": projection["rebellions"].duplicate(true)}


static func withdraw(state: GameState) -> Dictionary:
	var plan := _proposed_plan(state)
	if plan == null:
		return _error("No government budget can be withdrawn.")
	plan.status = "rejected"
	state.budget_history.append(plan)
	state.pending_budget = null
	return {"ok": true, "message": "Withdrew the %s budget for revision." % plan.year}


static func read_model(state: GameState) -> Dictionary:
	if state == null or state.player == null or state.country == null:
		return _error("No campaign is active.")
	var catalog := _catalog()
	if catalog.has("error"):
		return catalog
	var adjustments: Array = catalog["adjustments"].duplicate(true)
	var zero := {}
	for item in catalog["envelopes"]:
		zero[String(item["id"])] = 0.0
	var built := _build_plan(state, zero)
	if not built.get("ok", false):
		return built
	var default_plan: AnnualBudget = built["plan"]
	var default_preview := _preview_plan(state, default_plan)
	var active := _active_view(state, catalog["envelopes"])
	var envelope_rows: Array = []
	for item in catalog["envelopes"]:
		var id := String(item["id"])
		envelope_rows.append({
			"id": id,
			"name": String(item.get("name", id)),
			"body": String(item.get("body", "")),
			"portfolio": String(item.get("portfolio", "")),
			"current": float(active.allocations[id]),
			"allowed_adjustments": adjustments.duplicate(true),
		})

	var pending_preview: Variant = null
	if state.pending_budget != null:
		pending_preview = _preview_plan(state, state.pending_budget)
	var history: Array = []
	for budget in state.budget_history:
		history.append(budget.to_dict())

	var propose_reason := ""
	if not state.player.in_government:
		propose_reason = "Only the sitting government can introduce appropriations."
	elif state.pending_budget != null and state.pending_budget.status in ["proposed", "approved"]:
		propose_reason = "A budget for the next fiscal year is already before parliament."
	elif not is_finite(state.player.political_capital) \
			or state.player.political_capital < float(default_preview["political_capital_cost"]):
		propose_reason = "Not enough political capital (need %.0f)." % float(default_preview["political_capital_cost"])

	var pending_action_reason := ""
	if not state.player.in_government or state.pending_budget == null \
			or state.pending_budget.status != "proposed":
		pending_action_reason = "No government budget is awaiting a vote."
	var lobby_rows: Array = []
	for faction in state.country.factions:
		var cost := LOBBY_BASE_COST + faction.power * LOBBY_POWER_COST
		var reason := pending_action_reason
		if reason == "" and faction.seats <= 0:
			reason = "That faction has no parliamentary delegation to lobby."
		elif reason == "" and state.pending_budget != null \
				and float(state.pending_budget.lobbying_bonus.get(faction.id, 0.0)) >= LOBBY_CAP:
			reason = "That faction's lobbying bonus is already at the cap."
		elif reason == "" and (not is_finite(state.player.political_capital) \
				or state.player.political_capital < cost):
			reason = "Not enough political capital (need %.0f)." % cost
		lobby_rows.append({
			"id": faction.id,
			"name": faction.name,
			"seats": faction.seats,
			"cost": cost,
			"current_bonus": 0.0 if state.pending_budget == null else \
				float(state.pending_budget.lobbying_bonus.get(faction.id, 0.0)),
			"eligible": reason == "",
			"disabled_reason": reason,
		})

	return {
		"ok": true,
		"active": active.to_dict(),
		"pending": null if state.pending_budget == null else state.pending_budget.to_dict(),
		"history": history,
		"envelopes": envelope_rows,
		"adjustments": adjustments,
		"proposal_year": default_plan.year,
		"political_capital": state.player.political_capital,
		"default_preview": default_preview,
		"pending_preview": pending_preview,
		"actions": {
			"preview": {"eligible": state.pending_budget == null, "disabled_reason": "" if state.pending_budget == null else "The tabled budget is locked until parliament votes or it is withdrawn."},
			"propose": {"eligible": propose_reason == "", "disabled_reason": propose_reason},
			"lobby": {"eligible": pending_action_reason == "", "disabled_reason": pending_action_reason},
			"vote": {"eligible": pending_action_reason == "", "disabled_reason": pending_action_reason},
			"withdraw": {"eligible": pending_action_reason == "", "disabled_reason": pending_action_reason},
		},
		"lobby_factions": lobby_rows,
	}

static func validation_error(state: GameState, plan: AnnualBudget) -> String:
	if state == null or plan == null:
		return "The budget proposal is missing."
	var catalog := _catalog()
	if catalog.has("error"):
		return String(catalog["error"])
	var expected := {}
	for item in catalog["envelopes"]:
		expected[String(item["id"])] = true
	if plan.allocations.size() != expected.size():
		return "The budget must fund every spending envelope."
	for key in plan.allocations:
		if not expected.has(key):
			return "The budget must fund every spending envelope."
		var value: Variant = plan.allocations[key]
		if not (typeof(value) in [TYPE_INT, TYPE_FLOAT]) or not is_finite(float(value)) or float(value) < 0.0:
			return "Appropriations must be finite non-negative numbers."
	var active := _active_view(state, catalog["envelopes"])
	var expected_year := target_year(state, active)
	if plan.year != expected_year:
		return "The next budget must be for %s." % expected_year
	var low := active.expenditure() * BudgetSimScript.MIN_TOTAL_FACTOR
	var high := active.expenditure() * BudgetSimScript.MAX_TOTAL_FACTOR
	if plan.expenditure() < low or plan.expenditure() > high:
		return "Total appropriations must remain within 30% of the current budget."
	return ""


## The fiscal year a new plan is for. Normally next year; while the state is
## on an emergency resolution, a plan for THIS year ends the emergency.
static func target_year(state: GameState, active: AnnualBudget) -> int:
	if BudgetSimScript.is_emergency(state) and active.year == state.year:
		return state.year
	return maxi(state.year + 1, active.year + 1)


static func proposal_cost(state: GameState, plan: AnnualBudget) -> float:
	var catalog := _catalog()
	var active := _active_view(state, catalog.get("envelopes", []))
	var moved := 0.0
	for key in active.allocations:
		moved += absf(float(plan.allocations.get(key, active.allocations[key])) - float(active.allocations[key]))
	return minf(PROPOSAL_COST_CAP,
		PROPOSAL_BASE_COST + PROPOSAL_MOVEMENT_COST * moved / maxf(1.0, active.expenditure()))


static func _build_plan(state: GameState, adjustments: Dictionary) -> Dictionary:
	var catalog := _catalog()
	if catalog.has("error"):
		return catalog
	var allowed: Array = catalog["adjustments"]
	var known := {}
	for item in catalog["envelopes"]:
		known[String(item["id"])] = true
	for key in adjustments:
		if not known.has(key):
			return _error("Unknown budget envelope: %s." % key)
		var value: Variant = adjustments[key]
		if not (typeof(value) in [TYPE_INT, TYPE_FLOAT]) or not is_finite(float(value)):
			return _error("Budget adjustments must be finite numbers.")
		var allowed_step := false
		for step in allowed:
			if float(value) == float(step):
				allowed_step = true
				break
		if not allowed_step:
			return _error("Each appropriation must use an allowed adjustment step.")
	var active := _active_view(state, catalog["envelopes"])
	var plan := AnnualBudget.new()
	plan.year = target_year(state, active)
	plan.status = "draft"
	plan.source = "player"
	plan.proposed_by = state.player.faction_id if state.player != null else ""
	plan.forecast_revenue = state.country.economy.budget.revenue
	plan.economy_basis = state.country.economy.structural_revenue
	for item in catalog["envelopes"]:
		var id := String(item["id"])
		var change := float(adjustments.get(id, 0.0))
		plan.allocations[id] = _round1(float(active.allocations[id]) * (1.0 + change))
	var error := validation_error(state, plan)
	return _error(error) if error != "" else {"ok": true, "plan": plan}


static func _preview_plan(state: GameState, plan: AnnualBudget) -> Dictionary:
	var catalog := _catalog()
	var active := _active_view(state, catalog.get("envelopes", []))
	var projection := _projection(state, plan)
	var rows: Array = []
	for item in catalog.get("envelopes", []):
		var id := String(item["id"])
		rows.append({"id": id, "name": String(item.get("name", id)),
			"current": float(active.allocations[id]), "proposed": float(plan.allocations[id])})
	return {
		"plan": plan.to_dict(),
		"rows": rows,
		"active_total": active.expenditure(),
		"total": plan.expenditure(),
		"forecast_revenue": plan.forecast_revenue,
		"forecast_balance": plan.forecast_balance(),
		"political_capital_cost": proposal_cost(state, plan),
		"votes_for": projection["votes_for"],
		"votes_against": projection["votes_against"],
		"threshold": projection["threshold"],
		"passed": projection["passed"],
		"breakdown": projection["breakdown"].duplicate(true),
		"rebellions": projection["rebellions"].duplicate(true),
	}


static func _projection(state: GameState, plan: AnnualBudget) -> Dictionary:
	var motion := _motion(state, plan)
	return ParliamentaryVoteScript.project(state.country.factions, motion)


static func _motion(state: GameState, plan: AnnualBudget) -> Dictionary:
	var ideology := _budget_ideology(state, plan)
	var active := _active_view(state, _catalog().get("envelopes", []))
	var stakes := {}
	for faction in state.country.factions:
		var affinity := 1.0 - faction.effective_ideology().distance_to(ideology) / ParliamentaryVoteScript.MAX_DISTANCE
		var coalition := 0.06 if faction.in_coalition else -0.02
		var fiscal_drag := maxf(0.0, (plan.expenditure() - plan.forecast_revenue) / maxf(1.0, plan.forecast_revenue))
		var austerity_drag := maxf(0.0, (active.expenditure() - plan.expenditure()) / maxf(1.0, active.expenditure()))
		var stake := (affinity - 0.50) * 0.24 + coalition - fiscal_drag * 0.10
		if faction.ideology.economic < 0.0:
			stake -= austerity_drag * 0.18
		stakes[faction.id] = clampf(stake, -0.22, 0.22)
	return {"id": "annual_budget_%s" % plan.year, "ideology": ideology,
		"stakes": stakes, "lobbying_bonus": plan.lobbying_bonus.duplicate(true),
		"sponsor_id": plan.proposed_by, "player_faction_id": state.player.faction_id}


static func _budget_ideology(state: GameState, plan: AnnualBudget) -> Faction.Ideology:
	var catalog := _catalog()
	var envelopes: Array = catalog.get("envelopes", [])
	var active := _active_view(state, envelopes)
	var total_change := (plan.expenditure() - active.expenditure()) / maxf(1.0, active.expenditure())
	var economic := -clampf(total_change / 0.20, -1.0, 1.0)
	var social_signal := 0.0
	var weight := 0.0
	for item in envelopes:
		var id := String(item["id"])
		var base := maxf(1.0, float(active.allocations[id]))
		var relative := (float(plan.allocations[id]) - base) / base
		social_signal += relative * float(item.get("social_weight", 0.0))
		weight += absf(float(item.get("social_weight", 0.0)))
		economic += relative * float(item.get("economic_weight", 0.0)) / 4.0
	var ideology := Faction.Ideology.new()
	ideology.economic = clampf(economic, -1.0, 1.0)
	ideology.social = clampf(social_signal / maxf(0.01, weight / maxf(1.0, float(envelopes.size()))), -1.0, 1.0)
	return ideology


static func _active_view(state: GameState, envelopes: Array) -> AnnualBudget:
	if state.active_budget != null:
		return state.active_budget
	var budget := AnnualBudget.new()
	budget.year = state.year
	budget.allocations = BudgetSimScript.default_allocations(envelopes,
		state.country.economy.structural_expenditure)
	budget.status = "active"
	budget.source = "inherited"
	budget.forecast_revenue = state.country.economy.structural_revenue
	return budget


static func _proposed_plan(state: GameState) -> AnnualBudget:
	if state == null or state.player == null or not state.player.in_government:
		return null
	if state.pending_budget == null or state.pending_budget.status != "proposed":
		return null
	return state.pending_budget


static func _apply_rebellion_penalties(state: GameState, rebellions: Array) -> void:
	var rebel_ids := {}
	for row in rebellions:
		rebel_ids[String(row["wing_id"])] = true
	for faction in state.country.factions:
		for wing in faction.wings:
			if rebel_ids.has(wing.id):
				wing.loyalty = maxf(-1.0, wing.loyalty - 0.025)


static func _catalog() -> Dictionary:
	if not _catalog_cache.is_empty():
		return _catalog_cache.duplicate(true)
	var content: Dictionary = ContentRepositoryScript.load_all()
	if content.has("error"):
		return _error(String(content["error"]))
	var catalog: Variant = content.get("catalogs", {}).get("budget", null)
	if not (catalog is Dictionary) or not (catalog.get("envelopes", null) is Array) \
			or not (catalog.get("adjustments", null) is Array):
		return _error("Budget catalogue is unavailable.")
	_catalog_cache = catalog.duplicate(true)
	return _catalog_cache.duplicate(true)


static func _round1(value: float) -> float:
	return roundf(value * 10.0) / 10.0


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
