extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")


static func _state(role: String = "government", seed: int = 919191) -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": seed})
	state.rng = SimRng.from_seed(seed)
	BudgetSim.ensure_budget_state(state)
	HouseholdsSim.ensure_households(state)
	return state


static func _ruling(state: GameState) -> Faction:
	for f in state.country.factions:
		if f.id == state.ruling_faction_id:
			return f
	return null


static func _set_record(state: GameState, approval: float, confidence: float, misery: float) -> void:
	state.player.approval = approval
	for g in state.households.values():
		(g as HouseholdGroupState).confidence = confidence
	var econ := state.country.economy
	econ.inflation = econ.structural_inflation + misery * 0.5
	econ.unemployment = econ.natural_unemployment + misery * 0.5


static func _support_sum(state: GameState) -> float:
	var total := 0.0
	for f in state.country.factions:
		total += f.support
	return total


func _test_a_record_moves_the_polls(t) -> void:
	var poor := _state()
	var good := _state()
	var start := _ruling(poor).support
	for _m in range(24):
		_set_record(poor, 0.30, 0.30, 0.08)
		_set_record(good, 0.68, 0.68, -0.03)
		PollsSim.monthly(poor)
		PollsSim.monthly(good)
	t.truth(start - _ruling(poor).support >= 0.03, "a failing government loses at least three points in two years (%.1f)" % [(start - _ruling(poor).support) * 100.0])
	t.truth(_ruling(good).support > start, "a successful one gains (%+.1f)" % [(_ruling(good).support - start) * 100.0])


func _test_the_opposition_closest_to_the_public_gains_most(t) -> void:
	var state := _state()
	var before := {}
	for f in state.country.factions:
		before[f.id] = f.support
	for _m in range(12):
		_set_record(state, 0.30, 0.30, 0.08)
		PollsSim.monthly(state)
	var mood := PollsSim.public_mood(state)
	var gains := []
	for f in state.country.factions:
		if f.id != state.ruling_faction_id and not f.in_coalition:
			gains.append([f.effective_ideology().distance_to(mood), f.support - float(before[f.id]), f.id])
	gains.sort_custom(func(a, b): return a[0] < b[0])
	t.truth(gains.size() >= 2 and gains[0][1] > gains[-1][1], "the opposition nearest the public mood gains most (%s over %s)" % [gains[0][2], gains[-1][2]])


func _test_moves_are_bounded_normalised_and_revert(t) -> void:
	var state := _state()
	var total := _support_sum(state)
	var capped := true
	var floor_ok := true
	for _m in range(120):
		var before := {}
		for f in state.country.factions:
			before[f.id] = f.support
		_set_record(state, 0.05, 0.05, 0.30)
		PollsSim.monthly(state)
		for f in state.country.factions:
			if absf(f.support - float(before[f.id])) > PollsSim.MONTHLY_CAP + 1e-9:
				capped = false
			if f.support < PollsSim.SUPPORT_FLOOR - 1e-9:
				floor_ok = false
	t.truth(capped, "no party moves more than a point in a month")
	t.truth(floor_ok, "and none falls through the floor")
	t.near(_support_sum(state), total, 1e-6, "shares stay normalised")
	var displaced := _ruling(state).support
	for _m in range(120):
		_set_record(state, 0.5, 0.5, 0.0)
		PollsSim.monthly(state)
	t.truth(_ruling(state).support > displaced, "a neutral record lets support drift back toward its base")


func _test_the_polls_are_deterministic_and_reported(t) -> void:
	var a := _state()
	var b := GameState.from_dict(a.to_dict())
	var rng := a.rng.to_dict()
	for _m in range(12):
		PollsSim.monthly(a)
		PollsSim.monthly(b)
	t.truth(a.to_dict() == b.to_dict(), "the same record gives the same polls")
	t.equal(a.rng.to_dict(), rng, "and the polls draw nothing from the campaign stream")
	NativeGameScript.close_month(a)
	t.truth(a.monthly_digest.any(func(l: String) -> bool: return l.begins_with("Polls:") and l.contains("Liberal Democrats")),
		"the monthly report carries a poll line")
	var old := _state().to_dict()
	old.erase("support_base")
	t.truth(GameState.from_dict(old) != null, "an older save loads")


func _test_regions_follow_national_moves(t) -> void:
	var state := _state()
	var region: RegionState = state.regions["vashtera"]
	var before := float(Elections.local_support(state, region)[state.ruling_faction_id])
	for _m in range(24):
		_set_record(state, 0.30, 0.30, 0.08)
		PollsSim.monthly(state)
	var after := float(Elections.local_support(state, region)[state.ruling_faction_id])
	t.truth(after < before, "a national slide shows in the regions")
	var anera := float(Elections.local_support(state, state.regions["anera"])[state.ruling_faction_id])
	t.truth(absf(after - anera) > 0.01, "while each keeps its local character")


const ENVELOPES := ["state_administration", "foreign_affairs", "justice_and_policing", "national_defense",
	"infrastructure", "industry_and_jobs", "education", "health_and_welfare"]
const CALIBRATION_SEEDS := [11, 22, 33, 44, 55, 66]


static func budget_policy(state: GameState, step: float) -> void:
	var due := state.month == 10 or BudgetSim.is_emergency(state)
	if not state.player.in_government or not due or state.pending_budget != null:
		return
	var adjustments := {}
	for e in ENVELOPES:
		adjustments[e] = step if (step != -0.05 or state.year == 1993) else 0.0
	if BudgetActions.propose(state, adjustments).get("ok", false):
		for f in state.country.factions:
			if not f.in_coalition:
				BudgetActions.lobby(state, f.id)
				break
		BudgetActions.vote(state)


static func journeys(roles: Array, step: float, passes_budgets: bool, able_cabinet := false) -> Dictionary:
	var out := {"player_held": 0, "player_kept": 0, "ai_held": 0, "ai_kept": 0, "lost": [], "kept": [],
		"sequences": {}, "valid": true}
	for role in roles:
		for seed in CALIBRATION_SEEDS:
			var state := _state(role, seed)
			if able_cabinet:
				for m in state.ministers:
					m.competence = 0.95
					m.loyalty = 0.95
					m.trait_id = "technocrat"
			var sequence := ""
			for _m in range(240):
				var governing := state.player.in_government
				var ruling := state.ruling_faction_id
				if passes_budgets:
					budget_policy(state, step)
				NativeGameScript.next_month(state)
				if state.election_history.is_empty() or state.election_history[-1].turn != state.turn:
					continue
				var r: ElectionResult = state.election_history[-1]
				sequence += r.ruling_faction_id + ";"
				var returned := r.ruling_faction_id == ruling
				(out["kept"] if returned else out["lost"]).append(r.incumbent_approval)
				var side := "player" if governing else "ai"
				out[side + "_held"] += 1
				out[side + "_kept"] += 1 if returned else 0
			out["valid"] = out["valid"] and StateValidator.validate(state).is_empty()
			out["sequences"]["%s:%s" % [role, sequence]] = true
	return out


static func rate(out: Dictionary, side: String) -> float:
	return float(out[side + "_kept"]) / maxf(1.0, float(out[side + "_held"]))


static func mean(xs: Array) -> float:
	var s := 0.0
	for x in xs:
		s += float(x)
	return s / maxf(1.0, xs.size())


func _test_steady_governments_are_judged_like_ordinary_ones(t) -> void:
	var steady := journeys(["government", "opposition"], -0.05, true)
	t.truth(steady["valid"], "twenty calendar-true years from either side stay valid")
	t.truth(rate(steady, "player") >= 0.4 and rate(steady, "player") <= 0.65,
		"a steady player government is returned about half the time (%d of %d)" % [steady["player_kept"], steady["player_held"]])
	t.truth(rate(steady, "ai") >= 0.35 and rate(steady, "ai") <= 0.65,
		"and so is an ordinary AI government (%d of %d)" % [steady["ai_kept"], steady["ai_held"]])
	t.truth(not steady["lost"].is_empty() and not steady["kept"].is_empty(), "governments both fall and survive")
	t.truth(mean(steady["lost"]) < mean(steady["kept"]),
		"and those that fell were less approved (%.2f) than those returned (%.2f)" % [mean(steady["lost"]), mean(steady["kept"])])
	var government_sequences: Array = (steady["sequences"] as Dictionary).keys().filter(func(k: String) -> bool: return k.begins_with("government:"))
	t.truth(government_sequences.size() >= 2, "the seeds do not all write the same political history (%d distinct)" % government_sequences.size())


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_a_record_moves_the_polls(t)
	_test_the_opposition_closest_to_the_public_gains_most(t)
	_test_moves_are_bounded_normalised_and_revert(t)
	_test_the_polls_are_deterministic_and_reported(t)
	_test_regions_follow_national_moves(t)
	_test_steady_governments_are_judged_like_ordinary_ones(t)
	quit(t.finish())
