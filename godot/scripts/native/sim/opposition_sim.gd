class_name OppositionSim
extends RefCounted


const RESPONSE_MONTHS := 1
const OPPOSITION_TITLE := "Opposition Leader"
const FINISHED_PLEDGES := ["adopted", "undercut", "delivered"]
const BILL_CADENCE_MONTHS := 4
const RETRY_MONTHS := 24
const RULING_WHIP := 0.28
const COALITION_WHIP := 0.16

const IDEOLOGY_WEIGHT := 3.0
const LOYALTY_WEIGHT := 5.0
const RELIEF_WEIGHT := 2.0
const INFLATION_ALARM := 0.05
const UNEMPLOYMENT_ALARM := 0.10
const SECURITY_ALARM := 0.45

const SHADOW_EXPERIENCE := 0.001
const SHADOW_CEILING := 0.90
const SUPPORT_FLOOR := 0.01
const SUPPORT_CEILING := 0.85

const DELIVERED_CREDIT := 0.09
const ATTEMPTED_CREDIT := 0.015
const ADOPTION_CREDIT := {"support": 0.035, "amend": 0.035, "oppose": -0.06, "": 0.0}
const BROKEN_COST := -0.10
const BROKEN_SUPPORT_COST := 0.008
const CONSISTENT_SUPPORT := 0.04
const CONSISTENT_AMEND := 0.055
const INCONSISTENT_OPPOSE := -0.07
const RELATED_PLEDGE_DISTANCE := 0.9
const RELATED_PLEDGE_WEIGHT := 0.65

const EDGE_FLOOR := -0.06
const EDGE_CEILING := 0.08
const EMPTY_PLATFORM_EDGE := -0.03

const RETREAT_WINDOW_MONTHS := 3
const BY_ELECTION_EARLIEST_TURN := 6
const NATIONAL_BAR := 0.0
const LOCAL_BAR := -0.08

const EVENT_HANDLERS := ["opposition_claims_retreat", "opposition_offers_alternative",
	"opposition_misses_retreat", "by_election_national_push", "by_election_local_push",
	"by_election_stand_down"]
const EVENT_CONDITIONS := ["government_in_retreat", "by_election_opening"]


static func monthly(state: GameState) -> Array[String]:
	var notes: Array[String] = []
	if state.player.in_government:
		return notes
	var opp := state.opposition
	for m in opp.shadow_cabinet:
		m.competence = minf(SHADOW_CEILING, m.competence + SHADOW_EXPERIENCE)
	if opp.government_bill != null:
		if state.turn - opp.bill_introduced_turn >= RESPONSE_MONTHS:
			_bring_to_division(state, notes)
		return notes
	if state.turn < opp.next_bill_turn:
		return notes
	var bill := choose_bill(state)
	if bill != null:
		_introduce(state, bill, notes)
	return notes


static func ruling_party(state: GameState) -> Faction:
	return _faction(state, state.ruling_faction_id)


static func own_party(state: GameState) -> Faction:
	return _faction(state, state.player.faction_id)


static func choose_bill(state: GameState) -> Law:
	var best: Law = null
	var best_score := -INF
	for law in LawActions.catalog_laws():
		if not _government_may_bring(state, law):
			continue
		var score := pressure_score(state, law)
		if best == null or score > best_score or (is_equal_approx(score, best_score) and law.id < best.id):
			best = law
			best_score = score
	return best


static func pressure_score(state: GameState, law: Law) -> float:
	var ruling := ruling_party(state)
	if ruling == null:
		return -INF
	var bill_ideology := Faction.Ideology.new()
	bill_ideology.economic = law.ideology_economic
	bill_ideology.social = law.ideology_social
	var affinity := 1.0 - ruling.effective_ideology().distance_to(bill_ideology) / ParliamentaryVote.MAX_DISTANCE
	var loyalty := float(law.effects.get("faction_loyalty_deltas", {}).get(ruling.id, 0.0))
	return affinity * IDEOLOGY_WEIGHT + loyalty * LOYALTY_WEIGHT + material_relief(state, law) * RELIEF_WEIGHT


static func material_relief(state: GameState, law: Law) -> float:
	var econ := state.country.economy
	var relief := 0.0
	if econ.inflation >= INFLATION_ALARM and _effect(law, "inflation_delta", "inflation") < 0.0:
		relief += 1.0
	if econ.unemployment >= UNEMPLOYMENT_ALARM \
			and (_effect(law, "unemployment_delta", "unemployment") < 0.0 or _effect(law, "gdp_growth_delta", "gdp_growth") > 0.0):
		relief += 0.75
	if econ.budget.is_deficit() \
			and (_effect(law, "budget_revenue_delta", "budget_revenue") > 0.0 or _effect(law, "budget_expenditure_delta", "budget_expenditure") < 0.0):
		relief += 0.75
	if state.civil_war_risk >= SECURITY_ALARM and law.portfolio == "Defense":
		relief += 1.0
	return relief


static func take_office(state: GameState) -> Array[String]:
	var notes := _lapse_government_bill(state)
	var opp := state.opposition
	GameFactory.configure_government(state, state.player.faction_id, [])
	state.player.in_government = true
	state.ruling_faction_id = state.player.faction_id
	state.player.title = _government_title(state)
	notes.append_array(Elections.staff_cabinet(state, opp.shadow_cabinet))
	opp.shadow_cabinet.clear()
	_carry_unfinished_pledges(state)
	opp.mandate_start_turn = state.turn
	return notes


static func leave_office(state: GameState) -> void:
	var opp := state.opposition
	if state.pending_law != null:
		state.pending_law.status = "lapsed"
		state.law_history.append(Law.from_dict(state.pending_law.to_dict()))
		state.pending_law = null
	if state.pending_budget != null and state.pending_budget.status != "approved":
		state.pending_budget = null
	state.player.in_government = false
	state.player.title = OPPOSITION_TITLE
	if BudgetSim.is_emergency(state):
		BudgetSim.activate(state, BudgetSim.government_ai_budget(state))
	Elections.staff_cabinet(state, [] as Array[Minister])
	_carry_unfinished_pledges(state)
	opp.mandate_start_turn = -1
	opp.government_bill = null
	opp.response = ""
	opp.next_bill_turn = state.turn + OppositionState.FIRST_GOVERNMENT_BILL_TURN


static func renew_mandate(state: GameState) -> void:
	_carry_unfinished_pledges(state)
	state.opposition.mandate_start_turn = state.turn


static func hand_over(state: GameState) -> void:
	_lapse_government_bill(state)
	Elections.staff_cabinet(state, [] as Array[Minister])
	state.opposition.next_bill_turn = state.turn + OppositionState.FIRST_GOVERNMENT_BILL_TURN


static func _lapse_government_bill(state: GameState) -> Array[String]:
	var notes: Array[String] = []
	var opp := state.opposition
	if opp.government_bill != null:
		opp.government_bill.status = "lapsed"
		state.law_history.append(Law.from_dict(opp.government_bill.to_dict()))
		notes.append("\"%s\" lapses with the outgoing government." % opp.government_bill.name)
	opp.government_bill = null
	opp.response = ""
	return notes


static func _carry_unfinished_pledges(state: GameState) -> void:
	var opp := state.opposition
	opp.pledges = opp.pledges.filter(func(p: Dictionary) -> bool: return not (String(p["status"]) in FINISHED_PLEDGES))
	for p in opp.pledges:
		p["status"] = "pledged"


static func judge_mandate(state: GameState) -> Dictionary:
	var opp := state.opposition
	var verdict := {"delivered": 0, "broken": 0}
	if not state.player.in_government or opp.mandate_start_turn < 0:
		return verdict
	for p in opp.pledges:
		if String(p["status"]) in ["delivered", "adopted"]:
			verdict["delivered"] += 1
		else:
			p["status"] = "broken"
			verdict["broken"] += 1
	shift_credibility(state, BROKEN_COST * verdict["broken"])
	var own := own_party(state)
	if own != null:
		own.support = clampf(own.support - BROKEN_SUPPORT_COST * verdict["broken"], SUPPORT_FLOOR, SUPPORT_CEILING)
	return verdict


static func electoral_edge(state: GameState) -> float:
	var opp := state.opposition
	var credibility_edge := (opp.credibility - 0.5) * 0.09
	if state.player.in_government:
		if opp.mandate_start_turn < 0:
			return 0.0
		var kept := 0
		var broken := 0
		for p in opp.pledges:
			if String(p["status"]) in ["delivered", "adopted"]:
				kept += 1
			else:
				broken += 1
		return clampf(credibility_edge + kept * 0.015 - broken * 0.02, EDGE_FLOOR, EDGE_CEILING)
	if opp.pledges.is_empty():
		return EMPTY_PLATFORM_EDGE
	var coverage := 0.0
	var staffed := 0.0
	for p in opp.pledges:
		coverage += minf(3.0, float(p["campaigns"])) / 3.0
		if opp.shadow_for(OppositionActions.pledge_portfolio(String(p["bill_id"]))) != null:
			staffed += 1.0
	var n := float(opp.pledges.size())
	return clampf(credibility_edge + coverage / n * 0.035 + staffed / n * 0.015, EDGE_FLOOR, EDGE_CEILING)


static func shift_credibility(state: GameState, amount: float) -> void:
	state.opposition.credibility = clampf(state.opposition.credibility + amount, 0.0, 1.0)


static func shift_support(state: GameState, own_delta: float, ruling_delta: float) -> void:
	var own := own_party(state)
	var ruling := ruling_party(state)
	if own != null:
		own.support = clampf(own.support + own_delta, SUPPORT_FLOOR, SUPPORT_CEILING)
	if ruling != null and ruling != own:
		ruling.support = clampf(ruling.support + ruling_delta, SUPPORT_FLOOR, SUPPORT_CEILING)


static func note_response(state: GameState, law: Law, response: String) -> void:
	var strength := 0.0
	for p in state.opposition.pledges:
		var promised := _catalog_law(String(p["bill_id"]))
		if promised == null:
			continue
		if promised.id == law.id:
			strength = 1.0
			break
		if OppositionActions.pledge_portfolio(promised.id) == OppositionActions.pledge_portfolio(law.id):
			var distance := Vector2(promised.ideology_economic - law.ideology_economic,
				promised.ideology_social - law.ideology_social).length()
			strength = maxf(strength, maxf(0.0, 1.0 - distance / RELATED_PLEDGE_DISTANCE) * RELATED_PLEDGE_WEIGHT)
	if strength <= 0.0:
		return
	match response:
		"support":
			shift_credibility(state, CONSISTENT_SUPPORT * strength)
		"amend":
			shift_credibility(state, CONSISTENT_AMEND * strength)
		"oppose":
			shift_credibility(state, INCONSISTENT_OPPOSE * strength)


static func note_bill_result(state: GameState, law: Law, passed: bool) -> void:
	var p := state.opposition.pledge_for(law.id)
	if p.is_empty():
		return
	if law.proposed_by == state.player.faction_id:
		p["status"] = "delivered" if passed else "attempted"
		shift_credibility(state, DELIVERED_CREDIT if passed else ATTEMPTED_CREDIT)
	elif passed:
		var response := state.opposition.response
		p["status"] = "undercut" if response == "oppose" else "adopted"
		shift_credibility(state, ADOPTION_CREDIT.get(response, 0.0))


static func condition_met(state: GameState, rule_id: String) -> bool:
	match rule_id:
		"government_in_retreat":
			return not state.player.in_government \
				and state.turn - state.opposition.last_government_defeat_turn <= RETREAT_WINDOW_MONTHS
		"by_election_opening":
			var own := own_party(state)
			return not state.player.in_government and own != null and own.seats > 0 \
				and state.turn >= BY_ELECTION_EARLIEST_TURN
	return false


static func by_election_standing(state: GameState) -> float:
	var own := own_party(state)
	var ruling := ruling_party(state)
	if own == null or ruling == null:
		return -INF
	return own.support - ruling.support + (state.opposition.credibility - 0.5) * 0.3 \
		+ (0.5 - state.stability_value) * 0.3


static func run_event(state: GameState, handler_id: String) -> String:
	match handler_id:
		"opposition_claims_retreat":
			shift_support(state, 0.010, -0.006)
			return "Your front bench claims the retreat; the polls give you a little of the credit."
		"opposition_offers_alternative":
			shift_credibility(state, 0.05)
			shift_support(state, 0.004, -0.002)
			return "Your alternative gets a hearing. You look more like a government."
		"opposition_misses_retreat":
			shift_support(state, 0.0, 0.004)
			return "The government recovers its footing before anyone notices the retreat."
		"by_election_national_push":
			if by_election_standing(state) > NATIONAL_BAR:
				_take_seat(state)
				shift_support(state, 0.015, -0.010)
				shift_credibility(state, 0.04)
				return "The by-election becomes a verdict on the government, and you win it."
			shift_support(state, -0.006, 0.004)
			shift_credibility(state, -0.05)
			return "You made the by-election a referendum and lost it."
		"by_election_local_push":
			if by_election_standing(state) > LOCAL_BAR:
				_take_seat(state)
				shift_support(state, 0.006, -0.004)
				shift_credibility(state, 0.02)
				return "A disciplined local campaign takes the seat."
			shift_credibility(state, -0.01)
			return "The local campaign falls short; the organisation it built remains."
		"by_election_stand_down":
			shift_credibility(state, -0.01)
			return "The government holds the seat unopposed in all but name."
	return ""


static func _take_seat(state: GameState) -> void:
	var own := own_party(state)
	var ruling := ruling_party(state)
	if own != null and ruling != null and ruling.seats > 0:
		ruling.seats -= 1
		own.seats += 1


static func _introduce(state: GameState, law: Law, notes: Array[String]) -> void:
	var ruling := ruling_party(state)
	if ruling == null:
		return
	law.status = "proposed"
	law.proposed_by = ruling.id
	law.proposed_turn = state.turn
	for f in state.country.factions:
		if f.in_coalition:
			law.lobbying_bonus[f.id] = COALITION_WHIP
	law.lobbying_bonus[ruling.id] = RULING_WHIP
	state.opposition.government_bill = law
	state.opposition.bill_introduced_turn = state.turn
	state.opposition.response = ""
	var line := "Government bill: %s introduces \"%s\". The opposition can support, oppose or amend it before the vote next month." % [ruling.name, law.name]
	Voice.record(state, "government_bill", {"bill": law.name, "party": ruling.name}, line)
	notes.append(line)


static func _bring_to_division(state: GameState, notes: Array[String]) -> void:
	var opp := state.opposition
	var law := LawActions.canonical(opp.government_bill)
	if law == null:
		opp.government_bill = null
		return
	if opp.response == "amend":
		OppositionActions.apply_amendment(state, law)
	var result := LawActions.resolve(state, law)
	var passed := bool(result["passed"])
	note_bill_result(state, law, passed)
	if not passed:
		opp.last_government_defeat_turn = state.turn
	notes.append(Voice.say(state, "vote_passed" if passed else "vote_failed", {"bill": law.name,
		"vfor": law.votes_for, "vagainst": law.votes_against, "threshold": result["threshold"]}))
	opp.government_bill = null
	opp.response = ""
	opp.next_bill_turn = state.turn + BILL_CADENCE_MONTHS


static func _government_may_bring(state: GameState, law: Law) -> bool:
	if law.tier == "executive_order":
		return false
	for enacted in state.enacted_laws:
		if enacted.id == law.id:
			return false
	for past in state.law_history:
		if past.id == law.id and past.proposed_by != state.player.faction_id \
				and state.turn - past.proposed_turn < RETRY_MONTHS:
			return false
	return true


static func _effect(law: Law, delta_key: String, modifier_target: String) -> float:
	var total := float(law.effects.get(delta_key, 0.0))
	for m in law.effects.get("modifiers", []):
		if m is Dictionary and String(m.get("target", "")) == modifier_target:
			total += float(m.get("magnitude", 0.0))
	return total


static func _government_title(state: GameState) -> String:
	var data: Variant = ContentRepository.load_all().get("countries", {}).get(state.country.id, {})
	var title := String(data.get("default_player", {}).get("title", "")) if data is Dictionary else ""
	return title if title != "" else "Head of Government"


static func _catalog_law(bill_id: String) -> Law:
	for law in LawActions.catalog_laws():
		if law.id == bill_id:
			return law
	return null


static func _faction(state: GameState, faction_id: String) -> Faction:
	for f in state.country.factions:
		if f.id == faction_id:
			return f
	return null
