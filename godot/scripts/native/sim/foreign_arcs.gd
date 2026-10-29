class_name ForeignArcs
extends RefCounted


const TARGETS := ["__supplier__", "__rival__", "__western__", "__union_anchor__",
	"__in_civil_war__", "__fragile__", "__concert_foe__", "__warmest__"]
const HANDLERS: Array[String] = []
const CONDITIONS: Array[String] = []
const EVENT_IDS: Array[String] = []
const GATES := ["energy_verb", "orientation_verb", "diplomacy_verb"]
const COUP_STABILITY := 0.3
const COUP_MAX_WAR_RISK := 0.5
const CONCERT_FOE_LINE := -0.6


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


static func condition_met(_state: GameState, _rule_id: String) -> bool:
	return false


static func run(_state: GameState, _handler_id: String, _target: String) -> String:
	return ""
