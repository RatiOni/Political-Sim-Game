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


func _test_twenty_years_change_hands_for_a_reason(t) -> void:
	var lost: Array[float] = []
	var kept: Array[float] = []
	for role in ["government", "opposition"]:
		for seed in [919191, 31, 4242]:
			var state := _state(role, seed)
			var incumbent := state.ruling_faction_id
			for _m in range(240):
				NativeGameScript.close_month(state)
				if not state.election_history.is_empty() and state.election_history[-1].turn == state.turn:
					var r: ElectionResult = state.election_history[-1]
					(lost if r.ruling_faction_id != incumbent else kept).append(r.incumbent_approval)
					incumbent = r.ruling_faction_id
			t.truth(StateValidator.validate(state).is_empty(), "twenty years from %s (seed %d) stay valid" % [role, seed])
	var mean := func(xs: Array[float]) -> float:
		var s := 0.0
		for x in xs:
			s += x
		return s / maxf(1.0, xs.size())
	t.truth(not lost.is_empty() and not kept.is_empty(), "governments both fall and survive (%d fell, %d survived)" % [lost.size(), kept.size()])
	t.truth(mean.call(lost) < mean.call(kept), "and those that fell were less approved (%.2f) than those returned (%.2f)" % [mean.call(lost), mean.call(kept)])


const ENVELOPES := ["state_administration", "foreign_affairs", "justice_and_policing", "national_defense",
	"infrastructure", "industry_and_jobs", "education", "health_and_welfare"]


static func _steady_budget(state: GameState) -> void:
	if not state.player.in_government or state.month != 10 or state.pending_budget != null:
		return
	var adjustments := {}
	for e in ENVELOPES:
		adjustments[e] = -0.05 if state.year == 1993 else 0.0
	if BudgetActions.propose(state, adjustments).get("ok", false):
		for f in state.country.factions:
			if not f.in_coalition:
				BudgetActions.lobby(state, f.id)
				break
		BudgetActions.vote(state)


func _test_a_steady_government_is_returned_about_half_the_time(t) -> void:
	var held := 0
	var returned := 0
	for seed in [11, 22, 33, 44, 55, 66]:
		var state := _state("government", seed)
		for _m in range(240):
			var governing := state.player.in_government
			_steady_budget(state)
			NativeGameScript.next_month(state)
			if governing and not state.election_history.is_empty() and state.election_history[-1].turn == state.turn:
				held += 1
				if state.player.in_government:
					returned += 1
	var rate := float(returned) / maxf(1.0, held)
	t.truth(rate >= 0.4 and rate <= 0.65, "a steady government is returned about half the time (%d of %d, %.2f)" % [returned, held, rate])


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_a_record_moves_the_polls(t)
	_test_the_opposition_closest_to_the_public_gains_most(t)
	_test_moves_are_bounded_normalised_and_revert(t)
	_test_the_polls_are_deterministic_and_reported(t)
	_test_regions_follow_national_moves(t)
	_test_twenty_years_change_hands_for_a_reason(t)
	_test_a_steady_government_is_returned_about_half_the_time(t)
	quit(t.finish())
