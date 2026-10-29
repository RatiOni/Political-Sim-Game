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
	PollsSim.inheritance(state)
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
const CALIBRATION_SEEDS := [11, 22, 33, 44, 55, 66, 77, 88, 99, 110, 121, 132]
const SEQUENCE_SEEDS := [11, 22, 33, 44, 55, 66]


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


static func ordinary_programme(state: GameState) -> void:
	if not state.player.in_government or state.pending_law != null:
		return
	for law in state.law_history:
		if law.proposed_by == state.player.faction_id and state.turn - law.proposed_turn < OppositionSim.BILL_CADENCE_MONTHS:
			return
	var bill := OppositionSim.choose_bill(state)
	if bill != null and LawActions.propose(state, bill.id).get("ok", false):
		LawActions.vote(state)


const SCHEMER_ANSWERS := {"a_schemer_stirs": "confront", "a_schemer_confronted": "demand_resignation", "a_schemer_moves": "expose"}


static func handle_schemer(state: GameState) -> void:
	for situation in state.pending_situations.duplicate():
		if SCHEMER_ANSWERS.has(situation.event_id):
			EventActions.resolve(state, situation.event_id, SCHEMER_ANSWERS[situation.event_id])
	var schemer := Arcs.arc_schemer(state)
	if schemer == null or schemer.threat_level() <= Arcs.SCHEMER_THRESHOLD or not state.player.in_government:
		return
	if CabinetActions.issue_shortlist(state, schemer.portfolio).get("ok", false):
		var best: Minister = null
		for candidate in state.cabinet_shortlists.get(schemer.portfolio, []):
			if best == null or (candidate as Minister).effective_competence() > best.effective_competence():
				best = candidate
		if best != null:
			CabinetActions.appoint(state, schemer.portfolio, best.id)


static func first_election(role: String, step: float, answers_schemer: bool) -> Dictionary:
	var out := {"held": 0, "kept": 0}
	for seed in CALIBRATION_SEEDS:
		var state := _state(role, seed)
		var ruling := state.ruling_faction_id
		for _m in range(Elections.TERM_MONTHS):
			budget_policy(state, step)
			ordinary_programme(state)
			if answers_schemer:
				handle_schemer(state)
			NativeGameScript.next_month(state)
		out["held"] += 1
		out["kept"] += 1 if state.ruling_faction_id == ruling else 0
	return out


static func journeys(roles: Array, step: float, passes_budgets: bool, able_cabinet := false, legislates := true) -> Dictionary:
	var out := {"player_held": 0, "player_kept": 0, "ai_won_held": 0, "ai_won_kept": 0, "opening_held": 0,
		"opening_kept": 0, "first_held": 0, "first_kept": 0, "lost": [], "kept": [], "sequences": {}, "valid": true}
	for role in roles:
		for seed in CALIBRATION_SEEDS:
			var state := _state(role, seed)
			if able_cabinet:
				for m in state.ministers:
					m.competence = 0.95
					m.loyalty = 0.95
					m.trait_id = "technocrat"
			var sequence := ""
			var elected_ai := false
			for _m in range(240):
				var governing := state.player.in_government
				var ruling := state.ruling_faction_id
				if passes_budgets:
					budget_policy(state, step)
				if legislates:
					ordinary_programme(state)
				NativeGameScript.next_month(state)
				if state.election_history.is_empty() or state.election_history[-1].turn != state.turn:
					continue
				var r: ElectionResult = state.election_history[-1]
				sequence += r.ruling_faction_id + ";"
				var returned := r.ruling_faction_id == ruling
				(out["kept"] if returned else out["lost"]).append(r.incumbent_approval)
				var side := "player" if governing else ("ai_won" if elected_ai else "opening")
				out[side + "_held"] += 1
				out[side + "_kept"] += 1 if returned else 0
				if state.election_history.size() == 1:
					out["first_held"] += 1
					out["first_kept"] += 1 if returned else 0
				if not returned:
					elected_ai = not state.player.in_government
			out["valid"] = out["valid"] and StateValidator.validate(state).is_empty()
			if seed in SEQUENCE_SEEDS:
				out["sequences"]["%s:%s" % [role, sequence]] = true
	return out


static func rate(out: Dictionary, side: String) -> float:
	return float(out[side + "_kept"]) / maxf(1.0, float(out[side + "_held"]))


static func mean(xs: Array) -> float:
	var s := 0.0
	for x in xs:
		s += float(x)
	return s / maxf(1.0, xs.size())


func _test_ruling_costs_about_two_points_a_term(t) -> void:
	var state := _state()
	var term_cost := PollsSim.ruling_cost(state) * Elections.TERM_MONTHS
	t.near(term_cost, PollsSim.RULING_COST_PER_TERM, 1e-9, "an untroubled government pays about %.1f points a term for ruling" % (PollsSim.RULING_COST_PER_TERM * 100.0))
	var neutral := _state()
	var start := _ruling(neutral).support
	_set_record(neutral, float(PollsSim.ordinary_at(neutral.turn)["approval"]), float(PollsSim.ordinary_at(neutral.turn)["confidence"]),
		float(PollsSim.ordinary_at(neutral.turn)["misery"]))
	neutral.stability_value = float(PollsSim.ordinary_at(neutral.turn)["stability"])
	neutral.campaign_meta.erase(PollsSim.INHERITANCE_KEY)
	PollsSim.inheritance(neutral)
	for _m in range(Elections.TERM_MONTHS):
		_set_record(neutral, float(PollsSim.ordinary_at(neutral.turn)["approval"]), float(PollsSim.ordinary_at(neutral.turn)["confidence"]),
			float(PollsSim.ordinary_at(neutral.turn)["misery"]))
		neutral.stability_value = float(PollsSim.ordinary_at(neutral.turn)["stability"])
		PollsSim.monthly(neutral)
	var lost := start - _ruling(neutral).support
	t.truth(lost > 0.005 and lost < 0.03, "an ordinary government ends its term a little down (%.1f points)" % (lost * 100.0))
	var troubled := _state()
	troubled.active_budget = BudgetSim.activate(troubled, BudgetSim._emergency_resolution(troubled))
	troubled.event_history.append({"event_id": "corruption_trial", "option_id": "x", "turn": troubled.turn, "lapsed": false})
	troubled.opposition.mandate_start_turn = 0
	troubled.opposition.pledges.append({"bill_id": "minimum_wage_act", "status": "broken", "campaigns": 0})
	var defeated := Law.new()
	defeated.id = "minimum_wage_act"
	defeated.status = "rejected"
	defeated.proposed_by = troubled.ruling_faction_id
	defeated.proposed_turn = troubled.turn
	troubled.law_history.append(defeated)
	t.truth(PollsSim.ruling_cost(troubled) > PollsSim.ruling_cost(_state()) * 3.0,
		"scandal, a broken pledge, a lost bill and an unfunded year make ruling dearer")
	var opposition := _state("opposition")
	var player_party: Faction = null
	for f in opposition.country.factions:
		if f.id == opposition.player.faction_id:
			player_party = f
	t.truth(PollsSim.ruling_cost(opposition) > 0.0 and opposition.ruling_faction_id != player_party.id, "an AI government pays the same price")


func _test_the_base_realigns_after_each_election(t) -> void:
	var state := _state()
	PollsSim.monthly(state)
	var before := state.support_base.duplicate()
	var result := Elections.hold(state, false)
	var moved := true
	var total := 0.0
	for id in before:
		var expected := float(before[id]) + (float(result.vote_share.get(id, 0.0)) - float(before[id])) * Elections.BASE_REALIGNMENT
		moved = moved and absf(float(state.support_base[id]) - expected) < 1e-6
		total += float(state.support_base[id])
	t.truth(moved, "every party's base moves a quarter of the way toward its result")
	t.near(total, 1.0, 1e-6, "and the bases stay normalised")


func _test_a_malformed_inheritance_is_refused_and_rebuilt(t) -> void:
	var state := _state()
	t.truth(StateValidator.validate(state).is_empty(), "a recorded inheritance validates")
	for bad in [{"party": state.ruling_faction_id, "turn": 0}, "nonsense",
			{"party": state.ruling_faction_id, "turn": 0, "approval": "high", "confidence": 0.4, "misery": 0.0, "stability": 0.5},
			{"party": state.ruling_faction_id, "turn": 9999, "approval": 0.4, "confidence": 0.4, "misery": 0.0, "stability": 0.5}]:
		state.campaign_meta[PollsSim.INHERITANCE_KEY] = bad
		t.truth(not StateValidator.validate(state).is_empty(), "the validator rejects a malformed inheritance %s" % [bad])
		var rebuilt := PollsSim.inheritance(state)
		t.truth(PollsSim.valid_inheritance(rebuilt, state), "and the polls rebuild it rather than read it")
	state.campaign_meta.erase(PollsSim.INHERITANCE_KEY)
	t.truth(StateValidator.validate(state).is_empty(), "an absent inheritance is fine")


func _test_steady_governments_are_judged_like_ordinary_ones(t) -> void:
	var governing := journeys(["government"], 0.0, true)
	var opposing := journeys(["opposition"], 0.0, true)
	t.truth(governing["valid"] and opposing["valid"], "twenty calendar-true years from either side stay valid")
	var player_held: int = governing["player_held"] + opposing["player_held"]
	var player_kept: int = governing["player_kept"] + opposing["player_kept"]
	var player_rate := float(player_kept) / maxf(1.0, player_held)
	t.truth(player_rate >= 0.4 and player_rate <= PollsSim.STEADY_RETURN_CEILING, "a steady player government is usually returned (%d of %d)" % [player_kept, player_held])
	t.truth(rate(opposing, "player") >= 0.25, "a player who wins office from opposition is returned often enough (%d of %d)" % [opposing["player_kept"], opposing["player_held"]])
	var won_held: int = governing["ai_won_held"] + opposing["ai_won_held"]
	var won_kept: int = governing["ai_won_kept"] + opposing["ai_won_kept"]
	var won_rate := float(won_kept) / maxf(1.0, won_held)
	t.truth(won_rate >= 0.3 and won_rate <= 0.7, "an AI party that won power is returned often enough (%d of %d)" % [won_kept, won_held])
	var first_held: int = governing["first_held"] + opposing["first_held"]
	var first_kept: int = governing["first_kept"] + opposing["first_kept"]
	var first_rate := float(first_kept) / maxf(1.0, first_held)
	var lost: Array = governing["lost"] + opposing["lost"]
	var kept: Array = governing["kept"] + opposing["kept"]
	t.truth(mean(lost) < mean(kept), "governments that fell were less approved (%.2f) than those returned (%.2f)" % [mean(lost), mean(kept)])
	t.truth((governing["sequences"] as Dictionary).size() >= 3,
		"six seeds write at least three political histories (%d)" % (governing["sequences"] as Dictionary).size())


func _test_the_first_term_is_hard_but_winnable(t) -> void:
	var steady := first_election("government", 0.0, false)
	var answered := first_election("government", 0.0, true)
	var opening_ai := first_election("opposition", 0.0, false)
	var steady_rate := float(steady["kept"]) / float(steady["held"])
	var answered_rate := float(answered["kept"]) / float(answered["held"])
	var ai_rate := float(opening_ai["kept"]) / float(opening_ai["held"])
	t.truth(steady_rate >= 0.35 and steady_rate <= 0.5, "a steady government wins the 1997 election sometimes (%d of %d)" % [steady["kept"], steady["held"]])
	t.truth(answered_rate - steady_rate >= 0.15, "and clearly more often once it deals with the schemer (%d of %d)" % [answered["kept"], answered["held"]])
	t.truth(ai_rate >= 0.3 and ai_rate <= 0.7, "the opposition start's opening government faces a fair first election (%d of %d)" % [opening_ai["kept"], opening_ai["held"]])


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_a_record_moves_the_polls(t)
	_test_the_opposition_closest_to_the_public_gains_most(t)
	_test_moves_are_bounded_normalised_and_revert(t)
	_test_the_polls_are_deterministic_and_reported(t)
	_test_regions_follow_national_moves(t)
	_test_steady_governments_are_judged_like_ordinary_ones(t)
	_test_the_first_term_is_hard_but_winnable(t)
	_test_ruling_costs_about_two_points_a_term(t)
	_test_the_base_realigns_after_each_election(t)
	_test_a_malformed_inheritance_is_refused_and_rebuilt(t)
	quit(t.finish())
