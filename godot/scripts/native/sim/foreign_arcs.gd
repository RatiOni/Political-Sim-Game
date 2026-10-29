class_name ForeignArcs
extends RefCounted


const TARGETS := ["__supplier__", "__rival__", "__western__", "__union_anchor__",
	"__in_civil_war__", "__fragile__", "__concert_foe__", "__warmest__"]
const HANDLERS: Array[String] = ["valve_pay", "valve_cargo", "valve_appeal_west", "transit_concede",
	"transit_arbitrate", "windfall_storage"]
const CONDITIONS: Array[String] = ["transit_dispute_ripe", "transit_windfall_due"]
const EVENT_IDS: Array[String] = ["valve_threat", "transit_dispute", "transit_windfall"]
const GATES := ["energy_verb", "orientation_verb", "diplomacy_verb"]
const COUP_STABILITY := 0.3
const COUP_MAX_WAR_RISK := 0.5
const CONCERT_FOE_LINE := -0.6
const VALVE_TRANCHES := 3
const TRANSIT_WARMTH := -0.3
const GAS_SITUATION_TURN := 12
const WEST_APPEAL := 0.03
const ARBITRATION_GOODWILL := 0.03

static var probes: Dictionary = {}


static func resolve_target(state: GameState, key: String) -> String:
	match key:
		"__supplier__":
			return GasSim.gas(state).supplier_id if GasSim.is_active(state) else ""
		"__rival__":
			return _coldest(state, func(c: Country) -> bool: return DiplomacySim.is_rival_of_player(state, c))
		"__western__":
			return _anchor(state, "concert")
		"__union_anchor__":
			return _anchor(state, "union")
		"__in_civil_war__":
			return _first(state, func(c: Country) -> bool: return c.in_civil_war)
		"__fragile__":
			return _first(state, func(c: Country) -> bool: return _fragile(c))
		"__concert_foe__":
			return _concert_foe(state)
		"__warmest__":
			return _warmest(state)
	return ""


static func _world(state: GameState) -> Array[Country]:
	var out: Array[Country] = []
	for c in state.world:
		if c.id != state.country.id:
			out.append(c)
	out.sort_custom(func(a: Country, b: Country) -> bool: return a.id < b.id)
	return out


static func _first(state: GameState, test: Callable) -> String:
	for c in _world(state):
		if test.call(c):
			return c.id
	return ""


static func _score(state: GameState, id: String) -> float:
	var rel: Country.BilateralRelation = state.country.relations.get(id)
	return 0.0 if rel == null else rel.score


static func _coldest(state: GameState, test: Callable) -> String:
	var best := ""
	for c in _world(state):
		if test.call(c) and (best == "" or _score(state, c.id) < _score(state, best)):
			best = c.id
	return best


static func _warmest(state: GameState) -> String:
	var best := ""
	for c in _world(state):
		if state.country.relations.has(c.id) and (best == "" or _score(state, c.id) > _score(state, best)):
			best = c.id
	return best


static func _anchor(state: GameState, power_id: String) -> String:
	var id := String(ForeignSim.power(power_id).get("anchor", ""))
	return id if state.world_country(id) != null else ""


static func _fragile(c: Country) -> bool:
	return not c.in_civil_war and c.stability < COUP_STABILITY and c.civil_war_risk < COUP_MAX_WAR_RISK \
		and String(Country.REGIME_FAMILIES.get(c.regime_type, "")) != "autocracy"


static func _concert_foe(state: GameState) -> String:
	var west := state.world_country(_anchor(state, "concert"))
	if west == null:
		return ""
	var best := ""
	var best_score := CONCERT_FOE_LINE
	for c in _world(state):
		var rel: Country.BilateralRelation = c.get_relation(west.id)
		var own: Country.BilateralRelation = state.country.relations.get(c.id)
		if c == west or rel == null or own == null or own.sanctioned:
			continue
		if rel.score < best_score:
			best = c.id
			best_score = rel.score
	return best


static func gate_reason(state: GameState, gate: Dictionary, target: String) -> String:
	if gate.has("energy_verb"):
		return EnergyActions.reason_for(state, String(gate["energy_verb"]))
	if gate.has("orientation_verb"):
		return OrientationActions.reason_for(state, String(gate["orientation_verb"]))
	if gate.has("diplomacy_verb"):
		return DiplomacyActions.reason_for(state, String(gate["diplomacy_verb"]), target)
	return ""


static func schedule(state: GameState, event_id: String, target: String) -> void:
	state.scheduled_events.append({"event_id": event_id, "due_turn": state.turn, "target_country_id": target})


static func shift(state: GameState, sentinel: String, delta: float) -> void:
	var id := resolve_target(state, sentinel)
	if id != "":
		DiplomacySim.shift(state, id, delta)


static func condition_met(state: GameState, rule_id: String) -> bool:
	match rule_id:
		"transit_dispute_ripe":
			return _transit_open(state) and GasSim.supplier_warmth(state) < TRANSIT_WARMTH
		"transit_windfall_due":
			return _transit_open(state) and GasSim.supplier_warmth(state) >= TRANSIT_WARMTH
	return false


static func _transit_open(state: GameState) -> bool:
	return state.player.in_government and GasSim.is_active(state) and state.turn >= GAS_SITUATION_TURN 		and not ("transit" in GasSim.gas(state).concessions)


static func handles(handler_id: String) -> bool:
	return handler_id in HANDLERS or probes.has(handler_id)


static func run(state: GameState, handler_id: String, target: String) -> String:
	if probes.has(handler_id):
		return String((probes[handler_id] as Callable).call(state, target))
	match handler_id:
		"valve_pay":
			return _pay_to_defuse(state)
		"valve_cargo":
			return _through(EnergyActions.act(state, "gas_spot_purchase"))
		"valve_appeal_west":
			shift(state, "__western__", WEST_APPEAL)
			return "The Western embassies take the letter seriously, and say so in public."
		"transit_concede":
			return _through(EnergyActions.act(state, "gas_renegotiate_transit"))
		"transit_arbitrate":
			shift(state, "__western__", ARBITRATION_GOODWILL)
			return "The dispute goes to a panel in a Western capital."
		"windfall_storage":
			return _through(EnergyActions.act(state, "gas_storage"))
	return ""


static func _through(result: Dictionary) -> String:
	return String(result.get("message", result.get("error", "")))


static func _pay_to_defuse(state: GameState) -> String:
	var g := GasSim.gas(state)
	var line := g.arrears < GasSim.ARREARS_DEMAND * GasSim.DEFUSED_SHARE
	var tranches := 0
	while tranches < VALVE_TRANCHES and g.arrears >= GasSim.ARREARS_DEMAND * GasSim.DEFUSED_SHARE:
		if not EnergyActions.act(state, "gas_pay_arrears").get("ok", false):
			break
		tranches += 1
	if line or tranches == 0:
		return ""
	return "The treasury pays %d tranches of the Zovar arrears; %.0f remains." % [tranches, g.arrears]
