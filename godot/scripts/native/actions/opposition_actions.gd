class_name OppositionActions
extends RefCounted


const RESPONSE_COSTS := {"support": 4.0, "oppose": 4.0, "amend": 8.0}
const RESPONSE_WHIP := {"support": 0.35, "oppose": -0.35, "amend": 0.20}
const AMENDMENT_PULL := 0.30
const AMENDMENT_SOFTENING := 0.80
const SOFTENED_EFFECTS := ["gdp_growth_delta", "unemployment_delta", "inflation_delta",
	"budget_revenue_delta", "budget_expenditure_delta", "one_time_debt_pct_delta"]

const MAX_PLEDGES := 3
const PLEDGE_COST := 5.0
const DROP_COST := 3.0
const CAMPAIGN_COST := 8.0
const CAMPAIGN_COOLDOWN := 6
const SHADOW_COST := 6.0
const DEFAULT_PORTFOLIO := "Economy"
const UNSTAFFED_QUALITY := 0.35


static func respond(state: GameState, response: String) -> Dictionary:
	var reason := response_reason(state, response)
	if reason != "":
		return _error(reason)
	var opp := state.opposition
	var law := opp.government_bill
	state.player.political_capital -= float(RESPONSE_COSTS[response])
	opp.response = response
	law.lobbying_bonus[state.player.faction_id] = float(RESPONSE_WHIP[response])
	OppositionSim.note_response(state, law, response)
	var verbs := {"support": "will vote for", "oppose": "will vote against", "amend": "offers its votes for an amended"}
	return {"ok": true, "message": "The opposition %s \"%s\"." % [verbs[response], law.name]}


static func response_reason(state: GameState, response: String) -> String:
	if state.player.in_government:
		return "The government does not respond to its own bills."
	if state.opposition.government_bill == null:
		return "No government bill is before parliament."
	if not RESPONSE_COSTS.has(response):
		return "Unknown response."
	if state.opposition.response != "":
		return "The opposition has already declared its position on this bill."
	if state.player.political_capital < float(RESPONSE_COSTS[response]):
		return "Requires %.0f political capital." % RESPONSE_COSTS[response]
	return ""


static func apply_amendment(state: GameState, law: Law) -> void:
	law.ideology_economic += (state.player.ideology_economic - law.ideology_economic) * AMENDMENT_PULL
	law.ideology_social += (state.player.ideology_social - law.ideology_social) * AMENDMENT_PULL
	for key in SOFTENED_EFFECTS:
		if law.effects.has(key):
			law.effects[key] = float(law.effects[key]) * AMENDMENT_SOFTENING
	for m in law.effects.get("modifiers", []):
		if m is Dictionary:
			m["magnitude"] = float(m.get("magnitude", 0.0)) * AMENDMENT_SOFTENING


static func pledge_reason(state: GameState, bill_id: String) -> String:
	var reason := _opposition_reason(state, PLEDGE_COST)
	if reason == "" and state.opposition.pledges.size() >= MAX_PLEDGES:
		reason = "Your platform already carries %d pledges." % MAX_PLEDGES
	var law := _law(bill_id)
	if reason == "" and (law == null or law.tier == "executive_order"):
		reason = "That policy cannot be pledged."
	if reason == "" and not state.opposition.pledge_for(bill_id).is_empty():
		reason = "That policy is already in your platform."
	if reason == "" and state.enacted_laws.any(func(l: Law) -> bool: return l.id == bill_id):
		reason = "That policy is already law."
	return reason


static func add_pledge(state: GameState, bill_id: String) -> Dictionary:
	var reason := pledge_reason(state, bill_id)
	if reason != "":
		return _error(reason)
	var law := _law(bill_id)
	state.player.political_capital -= PLEDGE_COST
	state.opposition.pledges.append({"bill_id": bill_id, "status": "pledged", "campaigns": 0})
	OppositionSim.shift_credibility(state, 0.01)
	return {"ok": true, "message": "Your party pledges to enact \"%s\" if elected." % law.name}


static func drop_pledge(state: GameState, bill_id: String) -> Dictionary:
	var reason := _opposition_reason(state, DROP_COST)
	var pledge := state.opposition.pledge_for(bill_id)
	if reason == "" and pledge.is_empty():
		reason = "That policy is not in your platform."
	if reason != "":
		return _error(reason)
	state.player.political_capital -= DROP_COST
	state.opposition.pledges.erase(pledge)
	state.opposition.campaign_turns.erase(bill_id)
	OppositionSim.shift_credibility(state, -0.03 - minf(0.06, int(pledge["campaigns"]) * 0.02))
	return {"ok": true, "message": "The pledge is dropped, and people notice."}


static func campaign(state: GameState, bill_id: String) -> Dictionary:
	var reason := _opposition_reason(state, CAMPAIGN_COST)
	var pledge := state.opposition.pledge_for(bill_id)
	if reason == "" and pledge.is_empty():
		reason = "That policy is not in your platform."
	var left := cooldown_left(state, bill_id)
	if reason == "" and left > 0:
		reason = "You campaigned on that recently; again in %d month%s." % [left, "" if left == 1 else "s"]
	if reason != "":
		return _error(reason)
	var speaker := state.opposition.shadow_for(pledge_portfolio(bill_id))
	var quality := UNSTAFFED_QUALITY if speaker == null else speaker.implementation_quality()
	var gain := minf(0.016, 0.004 + quality * 0.007 + maxf(0.0, 0.55 - state.stability_value) * 0.008)
	state.player.political_capital -= CAMPAIGN_COST
	OppositionSim.shift_support(state, gain, -gain * 0.65)
	OppositionSim.shift_credibility(state, 0.018 + quality * 0.022)
	pledge["campaigns"] = int(pledge["campaigns"]) + 1
	state.opposition.campaign_turns[bill_id] = state.turn
	var who := "An untested spokesperson" if speaker == null else speaker.name
	return {"ok": true, "message": "%s campaigns on \"%s\"; support rises %.1f points." % [
		who, _law(bill_id).name, gain * 100.0], "gain": gain}


static func appoint_shadow(state: GameState, portfolio: String) -> Dictionary:
	var reason := _opposition_reason(state, SHADOW_COST)
	if reason == "" and not CabinetActions.CORE_PORTFOLIOS.has(portfolio):
		reason = "Unknown portfolio."
	var own := OppositionSim.own_party(state)
	if reason == "" and own == null:
		reason = "Your party is missing."
	if reason != "":
		return _error(reason)
	state.player.political_capital -= SHADOW_COST
	var minister: Minister = CabinetActions.generate_candidate(state, portfolio, own, false)
	minister.id = "shadow_%s" % minister.id
	state.opposition.shadow_cabinet = state.opposition.shadow_cabinet.filter(
		func(m: Minister) -> bool: return m.portfolio != portfolio)
	state.opposition.shadow_cabinet.append(minister)
	OppositionSim.shift_credibility(state, 0.01 * minister.effective_competence())
	return {"ok": true, "message": "%s becomes Shadow %s Minister." % [minister.name, portfolio],
		"appointed_id": minister.id}


static func cooldown_left(state: GameState, bill_id: String) -> int:
	if not state.opposition.campaign_turns.has(bill_id):
		return 0
	return maxi(0, int(state.opposition.campaign_turns[bill_id]) + CAMPAIGN_COOLDOWN - state.turn)


static func pledge_portfolio(bill_id: String) -> String:
	var law := _law(bill_id)
	return law.portfolio if law != null and CabinetActions.CORE_PORTFOLIOS.has(law.portfolio) else DEFAULT_PORTFOLIO


static func read_model(state: GameState) -> Dictionary:
	var opp := state.opposition
	var bill: Variant = null
	if opp.government_bill != null:
		var responses: Array = []
		for r in RESPONSE_COSTS:
			var reason := response_reason(state, r)
			responses.append({"response": r, "cost": RESPONSE_COSTS[r], "eligible": reason == "", "disabled_reason": reason})
		bill = {"id": opp.government_bill.id, "name": opp.government_bill.name,
			"response": opp.response, "responses": responses}
	var pledges: Array = []
	for p in opp.pledges:
		var law := _law(String(p["bill_id"]))
		pledges.append({"bill_id": p["bill_id"], "name": "" if law == null else law.name,
			"status": p["status"], "campaigns": p["campaigns"], "cooldown": cooldown_left(state, String(p["bill_id"]))})
	var shadows: Array = []
	for m in opp.shadow_cabinet:
		shadows.append({"id": m.id, "name": m.name, "portfolio": m.portfolio, "competence": m.competence, "trait": m.trait_label()})
	var options: Array = []
	for law in LawActions.catalog_laws():
		if law.tier == "executive_order":
			continue
		var reason := pledge_reason(state, law.id)
		options.append({"id": law.id, "name": law.name, "cost": PLEDGE_COST, "eligible": reason == "", "disabled_reason": reason})
	var portfolios: Array = []
	var shadow_reason := _opposition_reason(state, SHADOW_COST)
	for portfolio in CabinetActions.CORE_PORTFOLIOS:
		var holder := opp.shadow_for(portfolio)
		portfolios.append({"portfolio": portfolio, "holder": "" if holder == null else holder.name, "cost": SHADOW_COST,
			"eligible": shadow_reason == "", "disabled_reason": shadow_reason})
	return {"active": not state.player.in_government, "credibility": opp.credibility,
		"government_bill": bill, "pledges": pledges, "shadow_cabinet": shadows,
		"electoral_edge": OppositionSim.electoral_edge(state),
		"pledge_options": options, "portfolios": portfolios}


static func _opposition_reason(state: GameState, cost: float) -> String:
	if state.player.in_government:
		return "That belongs to opposition politics."
	if state.player.political_capital < cost:
		return "Requires %.0f political capital." % cost
	return ""


static func _law(bill_id: String) -> Law:
	for law in LawActions.catalog_laws():
		if law.id == bill_id:
			return law
	return null


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
