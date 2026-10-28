class_name DiplomacyActions
extends RefCounted


const COSTS := {
	"improve_relations": 10.0, "trade_agreement": 15.0, "foreign_loan": 8.0,
	"condemn": 5.0, "defense_pact": 15.0, "impose_sanctions": 8.0,
	"lift_sanctions": 4.0, "hold_summit": 10.0, "break_treaty": 0.0,
}
const LABELS := {
	"improve_relations": "Diplomatic outreach", "trade_agreement": "Sign a trade pact",
	"foreign_loan": "Refinance through a loan", "condemn": "Condemn publicly",
	"defense_pact": "Sign a defence pact", "impose_sanctions": "Impose sanctions",
	"lift_sanctions": "Lift sanctions", "hold_summit": "Hold a summit",
	"break_treaty": "Tear up a treaty",
}

const PACT_TRUST := 0.45
const SANCTION_FRIEND_LIMIT := 0.20
const SUMMIT_COOLDOWN := 8
const LOAN_SHARE_OF_GDP := 0.05
const LOAN_TERM_MONTHS := 48


static func act(state: GameState, verb: String, country_id: String, treaty_id := "") -> Dictionary:
	if not COSTS.has(verb):
		return _error("Unknown diplomatic action.")
	var reason := reason_for(state, verb, country_id, treaty_id)
	if reason != "":
		return _error(reason)
	state.player.political_capital -= float(COSTS[verb])
	var other := DiplomacySim.world_country(state, country_id)
	var message := ""
	match verb:
		"improve_relations": message = improve_relations(state, other, treaty_id)
		"trade_agreement": message = trade_agreement(state, other, treaty_id)
		"foreign_loan": message = foreign_loan(state, other, treaty_id)
		"condemn": message = condemn(state, other, treaty_id)
		"defense_pact": message = defense_pact(state, other, treaty_id)
		"impose_sanctions": message = impose_sanctions(state, other, treaty_id)
		"lift_sanctions": message = lift_sanctions(state, other, treaty_id)
		"hold_summit": message = hold_summit(state, other, treaty_id)
		"break_treaty": message = break_treaty(state, other, treaty_id)
	return {"ok": true, "message": message}


static func reason_for(state: GameState, verb: String, country_id: String, treaty_id := "") -> String:
	if state == null or state.player == null:
		return "No campaign is active."
	if not state.player.in_government:
		return "Foreign policy belongs to the government."
	var other := DiplomacySim.world_country(state, country_id)
	var p := DiplomacySim.pair(state, country_id)
	if other == null or p.is_empty():
		return "No such country."
	var rel: Country.BilateralRelation = p[0]
	match verb:
		"trade_agreement":
			if DiplomacySim.has_treaty(state, country_id, "trade"):
				return "A trade agreement with %s already stands." % other.name
			if rel.sanctioned:
				return "Trade cannot be agreed under a sanctions regime."
		"defense_pact":
			if DiplomacySim.has_treaty(state, country_id, "defense"):
				return "A defence pact with %s already stands." % other.name
			if rel.score < PACT_TRUST:
				return "%s will not commit to mutual defence at this level of trust (needs %.2f)." % [other.name, PACT_TRUST]
		"impose_sanctions":
			if rel.sanctioned:
				return "%s is already under your sanctions." % other.name
			if rel.score >= SANCTION_FRIEND_LIMIT:
				return "Sanctioning a friendly power would be diplomatic self-harm."
		"lift_sanctions":
			if not rel.sanctioned:
				return "There is no sanctions regime to lift."
		"hold_summit":
			var last := int(state.campaign_meta.get("last_summit_turn", -999))
			var left := last + SUMMIT_COOLDOWN - state.turn
			if left > 0:
				return "The diplomatic calendar is full — next summit in %d month%s." % [left, "" if left == 1 else "s"]
		"break_treaty":
			if not rel.treaties.any(func(tr): return String(tr.get("id", "")) == treaty_id):
				return "There is no such treaty with %s." % other.name
	var cost := float(COSTS[verb])
	if state.player.political_capital < cost:
		return "Requires %.0f political capital." % cost
	return ""


static func improve_relations(state: GameState, other: Country, _t: String) -> String:
	var minister: Minister = null
	for m in state.ministers:
		if m.portfolio == "Foreign Affairs":
			minister = m
	var quality := 0.4 if minister == null else minister.implementation_quality()
	var boost := 0.05 + 0.05 * quality
	DiplomacySim.shift(state, other.id, boost, "Diplomatic outreach.")
	return "Outreach to %s warms relations (+%.2f)." % [other.name, boost]


static func trade_agreement(state: GameState, other: Country, _t: String) -> String:
	var treaty := _treaty(state, other, "trade", "Trade Agreement with %s" % other.name)
	var p := DiplomacySim.pair(state, other.id)
	DiplomacySim.set_trade(state, other.id, (p[0] as Country.BilateralRelation).trade_volume + 250.0)
	DiplomacySim.shift(state, other.id, 0.05, "Trade agreement signed.")
	var growth := Modifier.new()
	growth.id = "%s_growth" % treaty["id"]
	growth.source = treaty["name"]
	growth.target = "gdp_growth"
	growth.magnitude = 0.0015
	growth.onset_delay = 3
	growth.ramp_duration = 24
	growth.hold_duration = Modifier.HOLDS_FOREVER
	growth.source_id = treaty["id"]
	growth.portfolio = "Foreign Affairs"
	state.modifiers.append(growth)
	return "Trade agreement signed with %s. Trade will build as relations hold; the growth benefit phases in over two years." % other.name


static func foreign_loan(state: GameState, other: Country, _t: String) -> String:
	var econ := state.country.economy
	var p := DiplomacySim.pair(state, other.id)
	var warmth := (p[0] as Country.BilateralRelation).score
	var rate := clampf(0.02 + (0.01 if other.regime_type == "authoritarian" else 0.0) - warmth * 0.02, 0.01, 0.08)
	var amount := minf(econ.gdp * LOAN_SHARE_OF_GDP, econ.public_debt_pct * econ.gdp)
	var saving := (econ.effective_interest_rate - rate) * amount
	var loan_id := "loan_%s_%d" % [other.id, state.turn]
	econ.loans.append({"id": loan_id, "lender_id": other.id, "principal": amount,
		"rate": rate, "months_left": LOAN_TERM_MONTHS})
	var interest := Modifier.new()
	interest.id = loan_id
	interest.source = "Loan from %s" % other.name
	interest.target = "budget_expenditure"
	interest.magnitude = -saving
	interest.onset_delay = 0
	interest.ramp_duration = 1
	interest.hold_duration = LOAN_TERM_MONTHS - 1
	interest.decay_duration = 0
	interest.source_id = loan_id
	interest.institutional = false
	state.modifiers.append(interest)
	DiplomacySim.shift(state, other.id, 0.04, "Loan accepted.")
	for f in state.country.factions:
		if f.ideology != null and f.ideology.social < -0.3:
			f.loyalty = maxf(-1.0, f.loyalty - 0.05)
	return "%s refinances %.0f M of the debt at %.1f%% for %d months — %s %.0f M a year. Nationalists call it dependence." % [
		other.name, amount, rate * 100.0, LOAN_TERM_MONTHS, "saving" if saving >= 0.0 else "costing", absf(saving)]


static func condemn(state: GameState, other: Country, _t: String) -> String:
	DiplomacySim.shift(state, other.id, -0.15, "Publicly condemned.")
	state.player.approval = minf(1.0, state.player.approval + 0.01)
	for f in state.country.factions:
		if f.ideology != null and f.ideology.social < -0.3:
			f.loyalty = minf(1.0, f.loyalty + 0.04)
	return "You condemn %s. Relations sour; the nationalist right approves." % other.name


static func defense_pact(state: GameState, other: Country, _t: String) -> String:
	_treaty(state, other, "defense", "Defence Pact with %s" % other.name)
	DiplomacySim.shift(state, other.id, 0.10, "Defence pact signed.")
	state.stability_value = minf(0.95, state.stability_value + 0.02)
	var rival := String(other.agenda.get("rival", ""))
	if rival != "" and rival != state.country.id and DiplomacySim.world_country(state, rival) != null:
		DiplomacySim.shift(state, rival, -0.10, "Alarmed by your pact with %s." % other.name)
	return "A defence pact binds you to %s. Its rivals now watch you too." % other.name


static func impose_sanctions(state: GameState, other: Country, _t: String) -> String:
	var p := DiplomacySim.pair(state, other.id)
	var lost := (p[0] as Country.BilateralRelation).trade_volume
	for rel in p:
		(rel as Country.BilateralRelation).sanctioned = true
	DiplomacySim.set_trade(state, other.id, 0.0)
	DiplomacySim.shift(state, other.id, -0.20, "Sanctions imposed.")
	if lost > 200.0:
		var cost := Modifier.new()
		cost.id = "sanctions_cost_%s_%d" % [other.id, state.turn]
		cost.source = "Sanctions on %s" % other.name
		cost.target = "gdp_growth"
		cost.magnitude = -0.002
		cost.ramp_duration = 2
		cost.hold_duration = 6
		cost.decay_duration = 2
		cost.portfolio = "Foreign Affairs"
		state.modifiers.append(cost)
	return "Sanctions slam shut on %s. Their economy will bleed — and your exporters take the hit." % other.name


static func lift_sanctions(state: GameState, other: Country, _t: String) -> String:
	for rel in DiplomacySim.pair(state, other.id):
		(rel as Country.BilateralRelation).sanctioned = false
	DiplomacySim.shift(state, other.id, 0.05, "Sanctions lifted.")
	return "Sanctions on %s are lifted. Trade must rebuild from nothing." % other.name


static func hold_summit(state: GameState, other: Country, _t: String) -> String:
	DiplomacySim.shift(state, other.id, 0.12, "Bilateral summit.")
	state.player.approval = minf(0.95, state.player.approval + 0.01)
	state.campaign_meta["last_summit_turn"] = state.turn
	return "A summit with %s: handshakes, a communiqué, and a real thaw." % other.name


static func break_treaty(state: GameState, other: Country, treaty_id: String) -> String:
	var p := DiplomacySim.pair(state, other.id)
	var treaty: Dictionary = {}
	for tr in (p[0] as Country.BilateralRelation).treaties:
		if String(tr.get("id", "")) == treaty_id:
			treaty = tr
	for rel in p:
		var r: Country.BilateralRelation = rel
		r.treaties = r.treaties.filter(func(tr): return String(tr.get("id", "")) != treaty_id)
	var kind := String(treaty.get("type", ""))
	DiplomacySim.shift(state, other.id, -0.30 if kind == "defense" else -0.20, "Treaty torn up.")
	if kind == "trade":
		DiplomacySim.set_trade(state, other.id, (p[0] as Country.BilateralRelation).trade_volume * 0.5)
		state.modifiers = state.modifiers.filter(func(m): return m.source_id != treaty_id)
	return "You tear up the %s. %s will not forget it." % [String(treaty.get("name", "treaty")), other.name]


static func read_model(state: GameState) -> Array:
	var rows: Array = []
	if state == null:
		return rows
	for other in state.world:
		var p := DiplomacySim.pair(state, other.id)
		if p.is_empty():
			continue
		var rel: Country.BilateralRelation = p[0]
		var actions: Array = []
		for verb in COSTS:
			if verb == "break_treaty":
				continue
			var reason := reason_for(state, verb, other.id)
			actions.append({"verb": verb, "label": LABELS[verb], "cost": COSTS[verb],
				"eligible": reason == "", "disabled_reason": reason, "treaty_id": ""})
		var treaties: Array = []
		for tr in rel.treaties:
			treaties.append({"id": String(tr.get("id", "")), "name": String(tr.get("name", "")),
				"type": String(tr.get("type", "")), "months": int(tr.get("turns_active", 0))})
			var reason := reason_for(state, "break_treaty", other.id, String(tr.get("id", "")))
			actions.append({"verb": "break_treaty", "label": "Tear up: %s" % String(tr.get("name", "")),
				"cost": 0.0, "eligible": reason == "", "disabled_reason": reason, "treaty_id": String(tr.get("id", ""))})
		rows.append({"id": other.id, "name": other.name, "regime": other.regime_type,
			"score": rel.score, "status": rel.status_label(), "trade": rel.trade_volume,
			"sanctioned": rel.sanctioned, "in_civil_war": other.in_civil_war,
			"treaties": treaties, "actions": actions})
	return rows


static func _treaty(state: GameState, other: Country, kind: String, name: String) -> Dictionary:
	var treaty := {"id": "%s_%s_%d" % [kind, other.id, state.turn], "name": name, "type": kind,
		"parties": [state.country.id, other.id], "turns_active": 0}
	for rel in DiplomacySim.pair(state, other.id):
		(rel as Country.BilateralRelation).treaties.append(treaty.duplicate(true))
	return treaty


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
