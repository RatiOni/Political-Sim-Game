extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")
const RegionalProgramActionsScript = preload("res://scripts/native/actions/regional_program_actions.gd")


static func _state(content: Dictionary) -> GameState:
	return GameFactory.new_campaign(content, {
		"country_id": "ardenia", "background_id": "none",
		"difficulty_id": "normal", "opening_role": "contextual", "seed": 424242,
	})


func _initialize() -> void:
	var t = TestSupportScript.new()
	var content := ContentRepositoryScript.load_all()
	var state := _state(content)
	var options: Array = RegionalProgramActionsScript.options_for(state, "anera", content)
	t.equal(options.size(), 5, "all five programmes are described for a normal state-controlled region")
	t.equal(options.map(func(row): return row["id"]), ["administrative_deployment", "customs_enforcement", "industrial_recovery", "public_works", "security_stabilisation"], "option order is deterministic")
	var before := state.to_dict()
	var refused: Dictionary = RegionalProgramActionsScript.start(state, "anera", "customs_enforcement", content)
	t.truth(not refused.get("ok", true), "region-incompatible programme is refused")
	t.equal(state.to_dict(), before, "a refused action is atomic")
	var invalid_before := state.to_dict()
	t.truth(not RegionalProgramActionsScript.start(state, "missing", "public_works", content).get("ok", true), "unknown region is refused")
	t.truth(not RegionalProgramActionsScript.start(state, "anera", "missing", content).get("ok", true), "unknown programme is refused")
	t.equal(state.to_dict(), invalid_before, "unknown-id refusals are atomic")
	var poor := _state(content)
	poor.player.political_capital = 10.999
	var poor_before := poor.to_dict()
	t.truth(not RegionalProgramActionsScript.start(poor, "anera", "security_stabilisation", content).get("ok", true), "insufficient political capital is refused")
	t.equal(poor.to_dict(), poor_before, "insufficient-capital refusal is atomic")
	var separatist := _state(content)
	var separatist_before := separatist.to_dict()
	t.truth(not RegionalProgramActionsScript.start(separatist, "vetrenka", "security_stabilisation", content).get("ok", true), "separatist control blocks launch")
	t.equal(separatist.to_dict(), separatist_before, "control refusal is atomic")
	var kelvet_options: Array = RegionalProgramActionsScript.options_for(state, "kelvet", content)
	var customs_in_anera := false
	var customs_in_kelvet := false
	for option in options:
		if option["id"] == "customs_enforcement":
			customs_in_anera = option["eligible"]
	for option in kelvet_options:
		if option["id"] == "customs_enforcement":
			customs_in_kelvet = option["eligible"]
	t.truth(not customs_in_anera and customs_in_kelvet, "Kelvet customs clean-up is eligible only in Kelvet")
	var loyalty_before := {}
	for faction in state.country.factions:
		loyalty_before[faction.id] = faction.loyalty
	state.player.political_capital = 11.0
	var pressure_before: float = state.regions["anera"].pressure
	var result: Dictionary = RegionalProgramActionsScript.start(state, "anera", "security_stabilisation", content)
	t.truth(result.get("ok", false), "exact political-capital cost succeeds")
	t.near(state.player.political_capital, 0.0, 0.000001, "political capital is charged once")
	t.near(state.regions["anera"].pressure, pressure_before + 0.06, 0.000001, "launch pressure lands immediately")
	for faction in state.country.factions:
		var delta: float = float({"national_conservatives": 0.05, "social_democrats": -0.03, "workers_front": -0.04, "liberal_democrats": -0.01}.get(faction.id, 0.0))
		t.near(faction.loyalty, float(loyalty_before[faction.id]) + delta, 0.000001, "authored faction loyalty delta applies for " + faction.id)
	t.equal(state.regional_programs.size(), 1, "one active programme is created")
	var programme: RegionState.RegionalProgram = state.regional_programs[0]
	t.equal(programme.id, "security_stabilisation:anera:0", "programme instance id is stable")
	t.equal(programme.duration, 8, "authored duration is preserved")
	t.near(programme.monthly_cost, 90.0, 0.000001, "authored monthly cost is preserved")
	t.equal(state.modifiers.size(), 1, "one treasury modifier is created")
	var modifier: Modifier = state.modifiers[0]
	t.equal(modifier.source_id, programme.id, "treasury modifier is tied to the programme instance")
	t.equal(modifier.target, "budget_expenditure", "treasury modifier uses the shared fiscal pipeline")
	t.near(modifier.magnitude, 1080.0, 0.000001, "monthly cost is annualised once")
	t.equal(modifier.hold_duration, 8, "modifier lasts for the programme duration")
	t.truth(not modifier.institutional, "programme funding is contractual, not institutional")
	var after := state.to_dict()
	var duplicate: Dictionary = RegionalProgramActionsScript.start(state, "anera", "public_works", content)
	t.truth(not duplicate.get("ok", true), "a region with an active programme refuses a second")
	t.equal(state.to_dict(), after, "duplicate refusal leaves state unchanged")
	var opposition := _state(content)
	opposition.player.in_government = false
	var opposition_before := opposition.to_dict()
	t.truth(not RegionalProgramActionsScript.start(opposition, "anera", "security_stabilisation", content).get("ok", true), "opposition cannot launch government programmes")
	t.equal(opposition.to_dict(), opposition_before, "opposition refusal is atomic")
	quit(t.finish())
