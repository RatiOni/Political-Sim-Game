class_name EnergyActions
extends RefCounted


const VERBS := ["gas_pay_arrears", "gas_renegotiate_transit", "gas_renegotiate_union", "gas_renegotiate_policy",
	"gas_spot_purchase", "gas_storage", "gas_second_line"]
const COSTS := {"gas_pay_arrears": 0.0, "gas_renegotiate_transit": 10.0, "gas_renegotiate_union": 10.0,
	"gas_renegotiate_policy": 10.0, "gas_spot_purchase": 5.0, "gas_storage": 15.0, "gas_second_line": 25.0}
const LABELS := {
	"gas_pay_arrears": "Pay down the gas arrears",
	"gas_renegotiate_transit": "Renegotiate: concede transit fees",
	"gas_renegotiate_union": "Renegotiate: take Union observer status",
	"gas_renegotiate_policy": "Renegotiate: shelve the second line",
	"gas_spot_purchase": "Emergency spot purchase",
	"gas_storage": "Build gas storage",
	"gas_second_line": "Build a second supply line",
}
const ARREARS_TRANCHE := 50.0
const PAYMENT_GOODWILL := 0.02
const RENEGOTIATE_COOLDOWN := 12
const RENEGOTIATE_WARMTH := -0.7
const PRICE_CUTS := {"gas_renegotiate_transit": 0.9, "gas_renegotiate_union": 0.85, "gas_renegotiate_policy": 0.9}
const PRICE_FLOOR_SHARE := 0.5
const TRANSIT_FEES := 20.0
const SHELVE_GOODWILL := 0.1
const SPOT_VOLUME := 0.5
const SPOT_PREMIUM := 1.8
const STORAGE_TARGET := 1.0
const STORAGE_COST := 40.0
const SECOND_LINE_COST := 60.0
const SECOND_LINE_HOSTILITY := -0.15
const AI_MONTHLY_BUDGET := 60.0


static func act(state: GameState, verb: String) -> Dictionary:
	var reason := reason_for(state, verb)
	if reason != "":
		return {"ok": false, "error": reason}
	state.player.political_capital -= float(COSTS[verb])
	return {"ok": true, "message": _perform(state, verb)}


static func _perform(state: GameState, verb: String) -> String:
	var message := ""
	match verb:
		"gas_pay_arrears":
			message = _pay(state)
		"gas_spot_purchase":
			message = _spot(state)
		"gas_storage":
			message = _storage(state)
		"gas_second_line":
			message = _second_line(state)
		_:
			message = _renegotiate(state, verb)
	ForeignSim.update_spine(state)
	return message


static func label_for(verb: String) -> String:
	return String(LABELS.get(verb, verb))


static func reason_for(state: GameState, verb: String) -> String:
	if state == null or state.player == null:
		return "No campaign is active."
	if not COSTS.has(verb):
		return "Unknown energy step."
	if not state.player.in_government:
		return "Energy policy belongs to the government."
	if not GasSim.is_active(state):
		return "Ardenia has no gas contract to manage."
	var condition := _condition_reason(state, verb)
	if condition != "":
		return condition
	if state.player.political_capital < _capital_needed(verb):
		return "Requires %.0f political capital." % _capital_needed(verb)
	return ""


static func _capital_needed(verb: String) -> float:
	var extra := float(OrientationActions.COSTS["union_observer"]) if verb == "gas_renegotiate_union" else 0.0
	return float(COSTS[verb]) + extra


static func _condition_reason(state: GameState, verb: String) -> String:
	var g := state.foreign.gas
	match verb:
		"gas_pay_arrears":
			if g.arrears <= 0.0:
				return "There are no gas arrears to pay."
		"gas_spot_purchase":
			if g.spot_pending > 0.0:
				return "A spot cargo is already on its way."
		"gas_storage":
			if g.storage_started >= 0:
				return "The storage programme is already under way."
		"gas_second_line":
			if g.second_line_started >= 0:
				return "The second line is already under way."
		_:
			return _renegotiation_reason(state, verb)
	return ""


static func _renegotiation_reason(state: GameState, verb: String) -> String:
	var g := state.foreign.gas
	if g.last_renegotiated >= 0 and state.turn - g.last_renegotiated < RENEGOTIATE_COOLDOWN:
		return "The supplier will not reopen the contract for %d more months." % [
			RENEGOTIATE_COOLDOWN - (state.turn - g.last_renegotiated)]
	if GasSim.supplier_warmth(state) < RENEGOTIATE_WARMTH:
		return "Relations with the supplier are too cold to reopen the contract (needs %.2f)." % RENEGOTIATE_WARMTH
	match verb:
		"gas_renegotiate_transit":
			if "transit" in g.concessions:
				return "The transit fees have already been conceded."
		"gas_renegotiate_union":
			return OrientationActions.reason_for(state, "union_observer")
		"gas_renegotiate_policy":
			if g.second_line_started < 0 or g.second_line_volume > 0.0:
				return "There is no second line under construction to shelve."
	return ""


static func _pay(state: GameState) -> String:
	var g := state.foreign.gas
	var amount := minf(g.arrears, ARREARS_TRANCHE)
	g.arrears -= amount
	EffectBundle.apply(state, {"one_time_debt_pct_delta": amount / state.country.economy.gdp}, "energy", "gas_pay_arrears")
	DiplomacySim.shift(state, g.supplier_id, PAYMENT_GOODWILL, "Ardenia paid down its gas arrears.")
	return "The treasury pays %.0f million kron of the Zovar arrears in hard currency; %.0f remains." % [amount, g.arrears]


static func _spot(state: GameState) -> String:
	var g := state.foreign.gas
	var cost := SPOT_VOLUME * g.price * SPOT_PREMIUM
	g.spot_pending = SPOT_VOLUME
	EffectBundle.apply(state, {"one_time_debt_pct_delta": cost / state.country.economy.gdp}, "energy", "gas_spot_purchase")
	return "A spot cargo of %.1f units is bought for %.0f million kron. It arrives with next month's deliveries." % [SPOT_VOLUME, cost]


static func _storage(state: GameState) -> String:
	var g := state.foreign.gas
	g.storage_started = state.turn
	g.storage_target = STORAGE_TARGET
	state.modifiers.append(OrientationSim.timed_modifier("gas_storage", "Gas storage programme",
		"budget_expenditure", STORAGE_COST, GasSim.STORAGE_MONTHS - 1, false))
	return "Work begins on gas storage. In %d months Ardenia can carry summer gas into the winter." % GasSim.STORAGE_MONTHS


static func _second_line(state: GameState) -> String:
	var g := state.foreign.gas
	g.second_line_started = state.turn
	state.modifiers.append(OrientationSim.timed_modifier("gas_second_line", "Second supply line",
		"budget_expenditure", SECOND_LINE_COST, GasSim.SECOND_LINE_MONTHS - 1, false))
	DiplomacySim.shift(state, g.supplier_id, SECOND_LINE_HOSTILITY, "Ardenia is building a gas line around Krasova.")
	return "Ardenia begins a second supply line. It will take %d months, and Krasova has noticed." % GasSim.SECOND_LINE_MONTHS


static func _renegotiate(state: GameState, verb: String) -> String:
	var g := state.foreign.gas
	match verb:
		"gas_renegotiate_transit":
			g.concessions.append("transit")
			state.modifiers.append(OrientationSim.timed_modifier("gas_transit_concession", "Zovar transit fees conceded",
				"budget_revenue", -TRANSIT_FEES, Modifier.HOLDS_FOREVER, false))
		"gas_renegotiate_union":
			OrientationActions.act(state, "union_observer")
		"gas_renegotiate_policy":
			g.second_line_started = -1
			state.modifiers = state.modifiers.filter(func(m: Modifier) -> bool: return m.source_id != "gas_second_line")
			DiplomacySim.shift(state, g.supplier_id, SHELVE_GOODWILL, "Ardenia shelved its second gas line.")
	g.price = maxf(g.reference_price * PRICE_FLOOR_SHARE, g.price * float(PRICE_CUTS[verb]))
	g.last_renegotiated = state.turn
	return "The supplier agrees a price of %.1f a unit until the contract is renewed." % g.price


static func _second_line_status(state: GameState) -> String:
	var g := state.foreign.gas
	if g.second_line_volume > 0.0:
		return "open"
	if g.second_line_started < 0:
		return "none"
	return "building, %d months left" % maxi(0, GasSim.SECOND_LINE_MONTHS - (state.turn - g.second_line_started))


static func read_model(state: GameState) -> Dictionary:
	if state == null or state.foreign == null or not GasSim.is_active(state):
		return {"active": false, "steps": []}
	var g := state.foreign.gas
	var steps: Array = []
	for verb in VERBS:
		var reason := reason_for(state, verb)
		steps.append({"verb": verb, "label": label_for(verb), "cost": _capital_needed(verb),
			"eligible": reason == "", "disabled_reason": reason})
	var supplier := state.world_country(g.supplier_id)
	return {"active": true, "supplier": supplier.name if supplier != null else g.supplier_id,
		"price": g.price, "reference_price": g.reference_price, "arrears": g.arrears,
		"months_to_renewal": maxi(0, g.term_end - state.turn), "contracted_volume": g.contracted_volume,
		"storage": g.storage, "storage_capacity": g.storage_capacity, "second_line": _second_line_status(state),
		"cut": g.cut, "threat": not g.threat.is_empty(), "shortfall": GasSim.national_shortfall(state),
		"union_capped": GasSim.union_member(state), "cuts": g.cuts, "steps": steps}


static func ai_policy(state: GameState) -> Array[String]:
	var taken: Array[String] = []
	if state == null or state.player == null or state.player.in_government or not GasSim.is_active(state):
		return taken
	var g := state.foreign.gas
	var room := AI_MONTHLY_BUDGET
	var pressed := not g.threat.is_empty() or (g.last_demand_turn >= 0 and state.turn - g.last_demand_turn < GasSim.DEMAND_INTERVAL)
	var arrears_cost := _cash_cost(state, "gas_pay_arrears")
	if pressed and _ai_try(state, "gas_pay_arrears", room):
		room -= arrears_cost
		taken.append("gas_pay_arrears")
	var next_month := state.month % 12 + 1
	if g.cut > 0.0 and GasSim.season_weight(next_month) >= GasSim.WINTER_WEIGHT and _ai_try(state, "gas_spot_purchase", room):
		taken.append("gas_spot_purchase")
	return taken


static func _ai_try(state: GameState, verb: String, room: float) -> bool:
	if _condition_reason(state, verb) != "" or _cash_cost(state, verb) > room:
		return false
	_perform(state, verb)
	return true


static func _cash_cost(state: GameState, verb: String) -> float:
	var g := state.foreign.gas
	match verb:
		"gas_pay_arrears":
			return minf(g.arrears, ARREARS_TRANCHE)
		"gas_spot_purchase":
			return SPOT_VOLUME * g.price * SPOT_PREMIUM
	return 0.0
