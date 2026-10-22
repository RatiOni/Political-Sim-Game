extends SceneTree

## Standalone headless test for Phase 2 Task 5: BudgetSim (annual budget
## rollover) and PoliticalCapital (governing overhead + regen).
## Run via:
##   Godot --headless --path godot --script res://tests/native/test_budget_and_pc.gd
##
## These check the ported logic on its own terms (a fresh campaign gets a
## seeded budget, an approved plan activates at January rollover, a
## no-plan government eats the continuing-budget cut, PC upkeep sums the
## commitments that genuinely exist natively today, PC regen respects its
## floor) — no comparison against Python is made or needed (task-5-brief.md:
## no oracle/parity requirement).

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")
const GameFactoryScript = preload("res://scripts/native/state/game_factory.gd")
const BudgetSimScript = preload("res://scripts/native/sim/budget_sim.gd")
const PoliticalCapitalScript = preload("res://scripts/native/sim/political_capital.gd")

const FIXED_SEED := 424242


static func _base_config() -> Dictionary:
	return {
		"country_id": "ardenia",
		"background_id": "none",
		"difficulty_id": "normal",
		"opening_role": "contextual",
		"seed": FIXED_SEED,
	}


static func _sum(allocations: Dictionary) -> float:
	var total := 0.0
	for v in allocations.values():
		total += float(v)
	return total


# ── BudgetSim: seeding ──────────────────────────────────────────────────

func _test_fresh_campaign_has_no_active_budget(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	t.equal(state.active_budget, null,
		"GameFactory leaves active_budget unset (Phase 1 Task 2's documented scope)")


func _test_process_fiscal_year_seeds_fresh_budget(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	t.equal(state.active_budget, null, "no active_budget before the first call")

	# Default campaign opens in March (game_factory.gd: DEFAULT_MONTH), not
	# January — seeding must happen regardless of month, mirroring Python's
	# ensure_budget_state() being called unconditionally at the top of
	# process_fiscal_year every turn, not only in January.
	t.equal(state.month, 3, "sanity: campaign opens in March, not January")
	BudgetSimScript.process_fiscal_year(state)

	t.truth(state.active_budget != null, "process_fiscal_year seeds active_budget when absent")
	if state.active_budget == null:
		return
	t.equal(state.active_budget.year, state.year, "seeded budget is for the current year")
	t.equal(state.active_budget.status, "active", "seeded budget is immediately active")
	t.equal(state.active_budget.source, "inherited", "seeded budget is marked inherited")
	t.near(_sum(state.active_budget.allocations), state.country.economy.structural_expenditure,
		0.5, "seeded allocations sum to the structural expenditure baseline")
	t.near(state.active_budget.forecast_revenue, state.country.economy.structural_revenue,
		0.0001, "seeded forecast_revenue matches the structural revenue baseline")

	# Not January and the freshly-seeded budget's year == state.year, so no
	# rollover fires on this same call — pending_budget stays untouched and
	# no history entry is created yet.
	t.equal(state.pending_budget, null, "no pending_budget exists yet")
	t.equal(state.budget_history.size(), 0, "seeding alone does not activate/append history")


func _test_default_allocations_matches_envelope_shares(t, content: Dictionary) -> void:
	var catalogs: Dictionary = content.get("catalogs", {})
	var budget_catalog: Dictionary = catalogs.get("budget", {})
	var envelopes: Array = budget_catalog.get("envelopes", [])
	t.truth(not envelopes.is_empty(), "budget catalog has envelopes")
	if envelopes.is_empty():
		return

	var allocations: Dictionary = BudgetSimScript.default_allocations(envelopes, 1000.0)
	t.equal(allocations.size(), envelopes.size(), "one allocation per envelope")
	t.near(_sum(allocations), 1000.0, 0.15,
		"default_allocations distributes the full expenditure across envelopes")
	for item in envelopes:
		var envelope_id := String(item["id"])
		t.truth(allocations.has(envelope_id), "allocation exists for envelope %s" % envelope_id)
		var expected: float = 1000.0 * float(item["share"])
		t.near(float(allocations.get(envelope_id, -1.0)), expected, 0.15,
			"envelope %s allocation matches its authored share" % envelope_id)


# ── BudgetSim: January rollover ──────────────────────────────────────────

func _test_approved_pending_becomes_active(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return

	BudgetSimScript.process_fiscal_year(state)   # seeds active_budget for state.year (1993)
	t.truth(state.active_budget != null, "active_budget seeded before rollover test")

	state.year += 1
	state.month = 1

	var pending := AnnualBudget.new()
	pending.year = state.year
	pending.status = "approved"
	pending.source = "player"
	pending.allocations = {"state_administration": 50.0, "foreign_affairs": 25.0,
		"justice_and_policing": 40.0, "national_defense": 90.0, "infrastructure": 70.0,
		"industry_and_jobs": 55.0, "education": 95.0, "health_and_welfare": 170.0}
	pending.forecast_revenue = 700.0
	pending.votes_for = 58
	pending.votes_against = 43
	pending.lobbying_bonus = {"national_conservatives": 0.22}
	state.pending_budget = pending

	var history_before := state.budget_history.size()
	BudgetSimScript.process_fiscal_year(state)

	t.truth(state.active_budget != null, "active_budget still set after rollover")
	if state.active_budget != null:
		t.equal(state.active_budget.year, state.year, "activated budget is for the new year")
		t.equal(state.active_budget.status, "active", "approved plan becomes active")
		t.equal(state.active_budget.source, "player", "activated plan keeps its player source")
		t.near(_sum(state.active_budget.allocations), _sum(pending.allocations), 0.001,
			"activated allocations match the approved plan")
		t.near(state.country.economy.structural_expenditure, _sum(pending.allocations), 0.001,
			"structural_expenditure baseline updates to the activated plan's total")
	t.equal(state.pending_budget, null, "pending_budget is cleared after activation")
	t.equal(state.budget_history.size(), history_before + 1,
		"activation appends exactly one history entry")
	if state.active_budget != null:
		t.equal(state.active_budget.votes_for, 58, "activated budget preserves its recorded votes")
		t.near(float(state.active_budget.lobbying_bonus["national_conservatives"]), 0.22, 0.000001,
			"activated budget preserves its lobbying record")
	var history_after := state.budget_history.size()
	BudgetSimScript.process_fiscal_year(state)
	t.equal(state.budget_history.size(), history_after,
		"a second January call does not activate the approved settlement twice")


func _test_no_plan_gets_continuing_budget_cut(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	t.truth(state.player.in_government, "sanity: default Ardenia opening is in government")

	BudgetSimScript.process_fiscal_year(state)   # seeds active_budget for state.year (1993)
	var original_allocations: Dictionary = state.active_budget.allocations.duplicate(true)
	var original_total := _sum(original_allocations)

	state.year += 1
	state.month = 1
	state.pending_budget = null
	var approval_before: float = state.player.approval
	var stability_before: float = state.stability_value

	BudgetSimScript.process_fiscal_year(state)

	t.truth(state.active_budget != null, "active_budget still set")
	if state.active_budget != null:
		# activate() always stamps status="active" on whatever it enacts,
		# even a continuing rollover — mirrors engine/budget.py: activate,
		# which does the same before storing (Python's continuing_budget()
		# builds status="continuing", but activate() overwrites it). `source`
		# is what actually distinguishes a continuing rollover afterward.
		t.equal(state.active_budget.status, "active", "activation always stamps status active, even for a continuing rollover")
		t.equal(state.active_budget.source, "continuing", "continuing budget is marked as such")
		t.near(_sum(state.active_budget.allocations), original_total * (1.0 - BudgetSimScript.CONTINUING_CUT),
			0.5, "continuing budget applies the 3%% reduction to the prior total")
	t.equal(state.pending_budget, null, "pending_budget stays cleared")
	t.near(state.player.approval, maxf(0.0, approval_before - 0.015), 0.0001,
		"budget impasse costs the player approval")
	t.near(state.stability_value, maxf(0.0, stability_before - 0.02), 0.0001,
		"budget impasse costs government stability")


func _test_opposition_player_gets_government_ai_budget(t, content: Dictionary) -> void:
	var config := _base_config()
	config["opening_role"] = "opposition"
	var state: GameState = GameFactoryScript.new_campaign(content, config)
	t.truth(state != null, "opposition campaign builds")
	if state == null:
		return
	t.truth(not state.player.in_government, "sanity: opposition role leaves the player out of government")

	BudgetSimScript.process_fiscal_year(state)
	state.year += 1
	state.month = 1
	state.pending_budget = null

	var approval_before: float = state.player.approval
	BudgetSimScript.process_fiscal_year(state)

	t.truth(state.active_budget != null, "active_budget still set for an opposition player")
	if state.active_budget != null:
		t.equal(state.active_budget.status, "active", "the sitting government's own budget is enacted, not a continuation")
		t.equal(state.active_budget.source, "government_ai", "an opposition player does not author the enacted budget")
	t.near(state.player.approval, approval_before, 0.0001,
		"an opposition player is not punished for a budget they don't control (engine/budget.py process_fiscal_year)")


# ── PoliticalCapital: upkeep ─────────────────────────────────────────────

func _test_upkeep_zero_on_a_fresh_campaign(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	var breakdown: Dictionary = PoliticalCapitalScript.upkeep(state)
	t.equal(float(breakdown.get("laws", -1.0)), 0.0,
		"no Legislature exists natively yet, so law upkeep is always zero (task-5-brief.md)")
	t.equal(float(breakdown.get("treaties", -1.0)), 0.0, "a fresh campaign starts with no treaties")
	t.equal(float(breakdown.get("sanctions", -1.0)), 0.0, "a fresh campaign starts with no sanctions")


func _test_upkeep_counts_sanctions_and_treaties(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return

	var relation_ids: Array = state.country.relations.keys()
	t.truth(relation_ids.size() >= 3, "sanity: the player country has at least 3 relations")
	if relation_ids.size() < 3:
		return
	relation_ids.sort()

	var rel_a: Country.BilateralRelation = state.country.relations[relation_ids[0]]
	var rel_b: Country.BilateralRelation = state.country.relations[relation_ids[1]]
	var rel_c: Country.BilateralRelation = state.country.relations[relation_ids[2]]
	rel_a.sanctioned = true
	rel_b.sanctioned = true
	rel_c.treaties = [{"type": "trade"}, {"type": "defense"}]

	var breakdown: Dictionary = PoliticalCapitalScript.upkeep(state)
	t.equal(float(breakdown.get("laws", -1.0)), 0.0, "law upkeep is still zero")
	t.near(float(breakdown.get("sanctions", -1.0)), 2.0 * 1.0, 0.0001,
		"two sanctioned relations cost PC_UPKEEP_SANCTIONS each")
	t.near(float(breakdown.get("treaties", -1.0)), 2.0 * 0.6, 0.0001,
		"two treaties on one relation cost PC_UPKEEP_TREATY each")


# ── PoliticalCapital: regen ──────────────────────────────────────────────

func _test_regen_formula_above_floor(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return

	# Zero every commitment so upkeep is exactly zero and the formula is
	# exercised in isolation.
	for rel in state.country.relations.values():
		rel.sanctioned = false
		rel.treaties = []

	# Exactly one faction in coalition, with a known loyalty, isolates the
	# coalition_bonus term.
	var chosen: Faction = state.country.factions[0]
	for f in state.country.factions:
		f.in_coalition = (f.id == chosen.id)
	chosen.loyalty = 0.8

	state.player.approval = 0.7
	state.stability_value = 0.6
	state.player.pc_regen_base = 10.0
	state.player.political_capital = 50.0

	# approval_bonus = (0.7-0.5)*10 = 2.0; coalition_bonus = 0.8*5 = 4.0;
	# stability_bonus = (0.6-0.5)*4 = 0.4; upkeep = 0.
	# regen = 10.0 + 2.0 + 4.0 + 0.4 - 0.0 = 16.4
	PoliticalCapitalScript.regenerate(state)
	t.near(state.player.political_capital, 50.0 + 16.4, 0.001,
		"regen formula matches the hand-computed value above the floor")


func _test_regen_respects_floor(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return

	# Pile on enough upkeep and drag every bonus term to its worst case so the
	# raw formula goes deeply negative — regen must still clamp to the floor.
	var relation_ids: Array = state.country.relations.keys()
	for rid in relation_ids:
		var rel: Country.BilateralRelation = state.country.relations[rid]
		rel.sanctioned = true
	for f in state.country.factions:
		f.in_coalition = false

	state.player.approval = 0.0
	state.stability_value = 0.0
	state.player.pc_regen_base = 0.0
	state.player.political_capital = 50.0

	PoliticalCapitalScript.regenerate(state)
	t.near(state.player.political_capital, 50.0 + PoliticalCapitalScript.PC_REGEN_FLOOR, 0.0001,
		"regen never drops below PC_REGEN_FLOOR even under heavy upkeep and low morale")


func _test_regen_caps_at_one_hundred(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "campaign builds")
	if state == null:
		return
	for rel in state.country.relations.values():
		rel.sanctioned = false
		rel.treaties = []
	state.player.approval = 1.0
	state.stability_value = 1.0
	state.player.pc_regen_base = 50.0
	state.player.political_capital = 99.0

	PoliticalCapitalScript.regenerate(state)
	t.equal(state.player.political_capital, 100.0, "political_capital never exceeds the 100 ceiling")


func _initialize() -> void:
	var t = TestSupportScript.new()

	var content: Dictionary = ContentRepositoryScript.load_all()
	t.truth(not content.has("error"), "content loads for the budget/PC tests")

	if not content.has("error"):
		_test_fresh_campaign_has_no_active_budget(t, content)
		_test_process_fiscal_year_seeds_fresh_budget(t, content)
		_test_default_allocations_matches_envelope_shares(t, content)

		_test_approved_pending_becomes_active(t, content)
		_test_no_plan_gets_continuing_budget_cut(t, content)
		_test_opposition_player_gets_government_ai_budget(t, content)

		_test_upkeep_zero_on_a_fresh_campaign(t, content)
		_test_upkeep_counts_sanctions_and_treaties(t, content)

		_test_regen_formula_above_floor(t, content)
		_test_regen_respects_floor(t, content)
		_test_regen_caps_at_one_hundred(t, content)

	quit(t.finish())
