extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")
const GameFactoryScript = preload("res://scripts/native/state/game_factory.gd")
const BudgetActionsScript = preload("res://scripts/native/actions/budget_actions.gd")
const ParliamentaryVoteScript = preload("res://scripts/native/sim/parliamentary_vote.gd")

const FIXED_SEED := 424242


static func _config(role: String = "contextual") -> Dictionary:
	return {
		"country_id": "ardenia",
		"background_id": "none",
		"difficulty_id": "normal",
		"opening_role": role,
		"seed": FIXED_SEED,
	}


static func _state(content: Dictionary, role: String = "contextual") -> GameState:
	return GameFactoryScript.new_campaign(content, _config(role))


static func _zero_adjustments(content: Dictionary) -> Dictionary:
	var out := {}
	for item in content["catalogs"]["budget"]["envelopes"]:
		out[String(item["id"])] = 0.0
	return out


static func _motion(ideology: Faction.Ideology, stakes: Dictionary = {}, lobbying: Dictionary = {}) -> Dictionary:
	return {
		"id": "test_motion",
		"ideology": ideology,
		"stakes": stakes,
		"lobbying_bonus": lobbying,
		"sponsor_id": "player_party",
		"player_faction_id": "player_party",
	}


static func _faction(id: String, seats: int, loyalty: float, wing_strengths: Array[float]) -> Faction:
	var faction := Faction.new()
	faction.id = id
	faction.name = id
	faction.seats = seats
	faction.loyalty = loyalty
	faction.power = 0.5
	faction.ideology = Faction.Ideology.new()
	for i in range(wing_strengths.size()):
		var wing := Faction.Wing.new()
		wing.id = "%s_w%s" % [id, i]
		wing.name = wing.id
		wing.ideology = Faction.Ideology.new()
		wing.strength = wing_strengths[i]
		wing.loyalty = 1.0
		faction.wings.append(wing)
	return faction


func _test_vote_kernel_boundaries_and_conservation(t) -> void:
	var ideology := Faction.Ideology.new()
	var a := _faction("player_party", 4, 1.0, [0.34, 0.33, 0.33])
	var b := _faction("opposition", 3, -1.0, [])
	var result: Dictionary = ParliamentaryVoteScript.project([a, b], _motion(ideology))
	t.equal(result["threshold"], 4, "seven seats require exactly four votes")
	t.equal(result["votes_for"], 4, "exact-majority support is counted")
	t.truth(result["passed"], "exact-majority passage is accepted")
	t.equal(int(result["votes_for"]) + int(result["votes_against"]), 7,
		"projection conserves every parliamentary seat")
	var a_breakdown: Dictionary = result["breakdown"][0]
	var split_total := 0
	for wing_row in a_breakdown["wings"]:
		split_total += int(wing_row["seats"])
	t.equal(split_total, a.seats, "largest-remainder wing split conserves faction seats")
	# Stable largest-remainder ties follow authored wing order: 1.36, 1.32, 1.32 -> 2,1,1.
	t.equal(a_breakdown["wings"][0]["seats"], 2, "largest remainder awards the tied extra seat deterministically")


func _test_preview_is_pure_and_deterministic(t, content: Dictionary) -> void:
	var state := _state(content)
	var before: Dictionary = state.to_dict()
	var adjustments := _zero_adjustments(content)
	var first: Dictionary = BudgetActionsScript.preview(state, adjustments)
	var second: Dictionary = BudgetActionsScript.preview(state, adjustments)
	t.truth(first.get("ok", false), "valid preview succeeds")
	t.equal(first, second, "identical preview requests are deterministic")
	t.equal(state.to_dict(), before, "preview leaves the complete campaign state unchanged")
	if first.get("ok", false):
		var view: Dictionary = first["preview"]
		t.near(float(view["political_capital_cost"]), 8.0, 0.000001,
			"unchanged proposal has the exact base political-capital cost")
		t.equal(int(view["votes_for"]) + int(view["votes_against"]),
			state.country.factions.reduce(func(total, f): return total + f.seats, 0),
			"budget projection conserves all assembly seats")


func _test_preview_rejects_malformed_inputs_atomically(t, content: Dictionary) -> void:
	var state := _state(content)
	var good := _zero_adjustments(content)
	var invalid_cases: Array[Dictionary] = []
	var unknown := good.duplicate(true)
	unknown["unknown_envelope"] = 0.0
	invalid_cases.append(unknown)
	var text := good.duplicate(true)
	text[good.keys()[0]] = "five percent"
	invalid_cases.append(text)
	var nan_value := good.duplicate(true)
	nan_value[good.keys()[0]] = NAN
	invalid_cases.append(nan_value)
	var inf_value := good.duplicate(true)
	inf_value[good.keys()[0]] = INF
	invalid_cases.append(inf_value)
	var wrong_step := good.duplicate(true)
	wrong_step[good.keys()[0]] = 0.01
	invalid_cases.append(wrong_step)
	for malformed in invalid_cases:
		var before := state.to_dict()
		var result: Dictionary = BudgetActionsScript.preview(state, malformed)
		t.truth(not result.get("ok", true), "malformed preview is refused")
		t.equal(state.to_dict(), before, "malformed preview refusal is atomic")


func _test_plan_validation_boundaries(t, content: Dictionary) -> void:
	var state := _state(content)
	var valid_result: Dictionary = BudgetActionsScript.preview(state, _zero_adjustments(content))
	t.truth(valid_result.get("ok", false), "valid plan fixture builds")
	if not valid_result.get("ok", false):
		return
	var plan := AnnualBudget.from_dict(valid_result["preview"]["plan"])
	t.equal(BudgetActionsScript.validation_error(state, plan), "", "valid draft passes validation")
	plan.year += 1
	t.truth(BudgetActionsScript.validation_error(state, plan) != "", "wrong fiscal year is refused")
	plan.year -= 1
	var key: String = plan.allocations.keys()[0]
	plan.allocations[key] = -1.0
	t.truth(BudgetActionsScript.validation_error(state, plan) != "", "negative allocation is refused")
	plan.allocations[key] = INF
	t.truth(BudgetActionsScript.validation_error(state, plan) != "", "non-finite allocation is refused")
	# Direct validation guards the 70/130 percent trust boundary even though the authored
	# adjustment menu cannot normally reach it in one step.
	var active_total := float(valid_result["preview"]["active_total"])
	for envelope_id in plan.allocations:
		plan.allocations[envelope_id] = active_total * 2.0 / plan.allocations.size()
	t.truth(BudgetActionsScript.validation_error(state, plan) != "", "total above 130 percent is refused")
	for envelope_id in plan.allocations:
		plan.allocations[envelope_id] = active_total * 0.5 / plan.allocations.size()
	t.truth(BudgetActionsScript.validation_error(state, plan) != "", "total below 70 percent is refused")


func _test_proposal_guards_and_single_spend(t, content: Dictionary) -> void:
	var adjustments := _zero_adjustments(content)
	var opposition := _state(content, "opposition")
	var opposition_before := opposition.to_dict()
	var opposed: Dictionary = BudgetActionsScript.propose(opposition, adjustments)
	t.truth(not opposed.get("ok", true), "opposition cannot table appropriations")
	t.equal(opposition.to_dict(), opposition_before, "opposition refusal is atomic")

	var poor := _state(content)
	poor.player.political_capital = 7.99
	var poor_before := poor.to_dict()
	var unaffordable: Dictionary = BudgetActionsScript.propose(poor, adjustments)
	t.truth(not unaffordable.get("ok", true), "proposal below the exact 8 PC boundary is refused")
	t.equal(poor.to_dict(), poor_before, "unaffordable proposal refusal is atomic")

	var state := _state(content)
	var pc_before: float = state.player.political_capital
	var result: Dictionary = BudgetActionsScript.propose(state, adjustments)
	t.truth(result.get("ok", false), "government can table a valid budget")
	t.truth(state.pending_budget != null and state.pending_budget.status == "proposed",
		"successful proposal creates one pending proposed budget")
	t.near(state.player.political_capital, pc_before - 8.0, 0.000001,
		"successful proposal spends political capital exactly once")
	var after_success := state.to_dict()
	var duplicate: Dictionary = BudgetActionsScript.propose(state, adjustments)
	t.truth(not duplicate.get("ok", true), "duplicate pending proposal is refused")
	t.equal(state.to_dict(), after_success, "duplicate refusal neither spends nor replaces the plan")


func _test_lobby_cap_and_zero_seat_guard(t, content: Dictionary) -> void:
	var state := _state(content)
	state.player.political_capital = 100.0
	t.truth(BudgetActionsScript.propose(state, _zero_adjustments(content)).get("ok", false),
		"lobby fixture proposal succeeds")
	var target: Faction = state.country.factions[0]
	var old_seats := target.seats
	target.seats = 0
	var before_zero := state.to_dict()
	t.truth(not BudgetActionsScript.lobby(state, target.id).get("ok", true),
		"zero-seat faction cannot be lobbied")
	t.equal(state.to_dict(), before_zero, "zero-seat lobby refusal is atomic")
	target.seats = old_seats
	state.player.political_capital = 100.0
	for i in range(3):
		t.truth(BudgetActionsScript.lobby(state, target.id).get("ok", false),
			"valid lobby attempt %s succeeds" % [i + 1])
	t.near(float(state.pending_budget.lobbying_bonus[target.id]), 0.50, 0.000001,
		"lobbying bonus is capped at the design-reference 0.50")


func _test_withdraw_and_vote_lifecycle(t, content: Dictionary) -> void:
	var withdrawn_state := _state(content)
	t.truth(BudgetActionsScript.propose(withdrawn_state, _zero_adjustments(content)).get("ok", false),
		"withdraw fixture proposal succeeds")
	var withdrawn: Dictionary = BudgetActionsScript.withdraw(withdrawn_state)
	t.truth(withdrawn.get("ok", false), "proposed budget can be withdrawn")
	t.equal(withdrawn_state.pending_budget, null, "withdrawal clears pending budget")
	t.equal(withdrawn_state.budget_history.size(), 1, "withdrawal moves plan into history")
	t.equal(withdrawn_state.budget_history[0].status, "rejected", "withdrawn plan is rejected")
	var after_withdraw := withdrawn_state.to_dict()
	t.truth(not BudgetActionsScript.withdraw(withdrawn_state).get("ok", true),
		"invalid second withdrawal is refused")
	t.equal(withdrawn_state.to_dict(), after_withdraw, "invalid action order is atomic")

	var passed_state := _state(content)
	for faction in passed_state.country.factions:
		faction.loyalty = 1.0
	t.truth(BudgetActionsScript.propose(passed_state, _zero_adjustments(content)).get("ok", false),
		"pass fixture proposal succeeds")
	var passed: Dictionary = BudgetActionsScript.vote(passed_state)
	t.truth(passed.get("ok", false) and passed.get("passed", false), "supportive assembly approves budget")
	t.equal(passed_state.pending_budget.status, "approved", "passed budget remains pending until January")

	var failed_state := _state(content)
	for faction in failed_state.country.factions:
		faction.loyalty = -1.0
	t.truth(BudgetActionsScript.propose(failed_state, _zero_adjustments(content)).get("ok", false),
		"defeat fixture proposal succeeds")
	var approval_before: float = failed_state.player.approval
	var failed: Dictionary = BudgetActionsScript.vote(failed_state)
	t.truth(failed.get("ok", false) and not failed.get("passed", true), "hostile assembly defeats budget")
	t.equal(failed_state.pending_budget, null, "defeat clears pending budget")
	t.equal(failed_state.budget_history.size(), 1, "defeat archives rejected plan")
	t.near(failed_state.player.approval, maxf(0.0, approval_before - 0.015), 0.000001,
		"defeat applies the existing approval consequence")


func _test_rebellion_penalty_targets_only_reported_wings(t, content: Dictionary) -> void:
	var state := _state(content)
	var adjustments := _zero_adjustments(content)
	adjustments["national_defense"] = 0.15
	adjustments["justice_and_policing"] = 0.15
	adjustments["education"] = -0.15
	adjustments["health_and_welfare"] = -0.15
	var faction: Faction = state.country.factions[0]
	faction.loyalty = 0.0
	faction.ideology.economic = 0.0
	faction.ideology.social = 0.0
	faction.wings = []
	for i in range(2):
		var wing := Faction.Wing.new()
		wing.id = "split_%s" % i
		wing.name = wing.id
		wing.ideology = Faction.Ideology.new()
		wing.ideology.social = -1.0 if i == 0 else 1.0
		wing.strength = 0.5
		wing.loyalty = 0.0
		faction.wings.append(wing)
	t.truth(BudgetActionsScript.propose(state, adjustments).get("ok", false),
		"rebellion fixture proposal succeeds")
	var projection: Dictionary = BudgetActionsScript.preview_pending(state)
	t.truth(projection.get("ok", false), "pending proposal can be previewed")
	if not projection.get("ok", false):
		return
	var rebellions: Array = projection["preview"]["rebellions"]
	t.truth(not rebellions.is_empty(), "polarized authored fixture produces a reported rebellion")
	var before := {}
	for f in state.country.factions:
		for wing in f.wings:
			before[wing.id] = wing.loyalty
	var reported := {}
	for rebellion in rebellions:
		reported[String(rebellion["wing_id"])] = true
	BudgetActionsScript.vote(state)
	for f in state.country.factions:
		for wing in f.wings:
			var expected: float = maxf(-1.0, float(before[wing.id]) - 0.025) if reported.has(wing.id) else float(before[wing.id])
			t.near(wing.loyalty, expected, 0.000001,
				"only reported rebel wing %s receives the loyalty penalty" % wing.id)


func _test_read_model_is_pure_detached_and_rule_complete(t, content: Dictionary) -> void:
	var state := _state(content)
	t.truth(BudgetActionsScript.propose(state, _zero_adjustments(content)).get("ok", false),
		"read-model fixture proposal succeeds")
	var before := state.to_dict()
	var model: Dictionary = BudgetActionsScript.read_model(state)
	t.truth(model.get("ok", false), "budget read model builds")
	t.equal(state.to_dict(), before, "budget read model is non-mutating")
	if not model.get("ok", false):
		return
	t.equal(model["envelopes"].size(), 8, "read model exposes all eight authored envelopes")
	t.equal(model["adjustments"].size(), 7, "read model exposes all seven authored adjustment steps")
	t.truth(model["pending"] != null and model["pending_preview"] != null,
		"read model exposes pending budget and its engine preview")
	t.truth(not model["actions"]["propose"]["eligible"],
		"read model disables duplicate proposal with an engine reason")
	t.truth(model["actions"]["vote"]["eligible"], "read model enables a valid pending vote")
	t.equal(model["lobby_factions"].size(), state.country.factions.size(),
		"read model exposes every real faction as a lobby row")
	var active_key: String = model["active"]["allocations"].keys()[0]
	model["active"]["allocations"][active_key] = 999999.0
	model["pending"]["allocations"][active_key] = 999999.0
	model["envelopes"][0]["current"] = 999999.0
	t.equal(state.to_dict(), before, "mutating nested read-model data cannot mutate live state")

	t.truth(BudgetActionsScript.withdraw(state).get("ok", false), "history read-model fixture withdraws")
	var historical: Dictionary = BudgetActionsScript.read_model(state)
	var history_before := state.to_dict()
	historical["history"][0]["allocations"][active_key] = 999999.0
	t.equal(state.to_dict(), history_before, "history read model is deeply detached")

	var opposition := _state(content, "opposition")
	var opposition_model: Dictionary = BudgetActionsScript.read_model(opposition)
	t.truth(opposition_model.get("ok", false), "opposition receives the same budget read model")
	t.truth(not opposition_model["actions"]["propose"]["eligible"] \
		and String(opposition_model["actions"]["propose"]["disabled_reason"]) != "",
		"opposition proposal is disabled with an engine-owned reason")


func _test_exact_movement_cost_and_unaffordable_lobby(t, content: Dictionary) -> void:
	var state := _state(content)
	var adjustments := _zero_adjustments(content)
	adjustments["state_administration"] = 0.15
	var preview_result: Dictionary = BudgetActionsScript.preview(state, adjustments)
	t.truth(preview_result.get("ok", false), "movement-cost preview succeeds")
	if preview_result.get("ok", false):
		var view: Dictionary = preview_result["preview"]
		var moved := 0.0
		for row in view["rows"]:
			moved += absf(float(row["proposed"]) - float(row["current"]))
		var expected := minf(18.0, 8.0 + 20.0 * moved / maxf(1.0, float(view["active_total"])))
		t.near(float(view["political_capital_cost"]), expected, 0.000001,
			"movement proposal uses the exact authored political-capital formula")

	state.player.political_capital = 100.0
	t.truth(BudgetActionsScript.propose(state, _zero_adjustments(content)).get("ok", false),
		"unaffordable-lobby fixture proposal succeeds")
	state.player.political_capital = 0.0
	var before := state.to_dict()
	var target: Faction = state.country.factions[0]
	t.truth(not BudgetActionsScript.lobby(state, target.id).get("ok", true),
		"unaffordable lobby request is refused")
	t.equal(state.to_dict(), before, "unaffordable lobby refusal is atomic")

func _initialize() -> void:
	var t = TestSupportScript.new()
	var content: Dictionary = ContentRepositoryScript.load_all()
	t.truth(not content.has("error"), "content loads for budget action tests")
	_test_vote_kernel_boundaries_and_conservation(t)
	if not content.has("error"):
		_test_preview_is_pure_and_deterministic(t, content)
		_test_preview_rejects_malformed_inputs_atomically(t, content)
		_test_plan_validation_boundaries(t, content)
		_test_proposal_guards_and_single_spend(t, content)
		_test_lobby_cap_and_zero_seat_guard(t, content)
		_test_withdraw_and_vote_lifecycle(t, content)
		_test_rebellion_penalty_targets_only_reported_wings(t, content)
		_test_read_model_is_pure_detached_and_rule_complete(t, content)
		_test_exact_movement_cost_and_unaffordable_lobby(t, content)
	quit(t.finish())
