class_name WorldSim
extends RefCounted


const AGGRESSION := {
	"hegemon": 0.55, "revanchist": 0.80, "trader": 0.15,
	"reformer": 0.35, "survivor": 0.20, "ideologue": 0.55,
}
const DEFAULT_AGENDA := {
	"parliamentary_democracy": "trader", "presidential_democracy": "reformer",
	"hybrid_regime": "survivor", "authoritarian": "hegemon", "totalitarian": "hegemon",
}
const OBJECTIVES := ["consolidate", "undermine", "court", "trade"]
const LEAKING_OBJECTIVES := ["undermine", "trade"]
const ARC_KINDS := ["axis", "feud"]

const HOSTILE_AGENDA_LINE := 0.5
const TURN_INWARD_STABILITY := 0.35
const SURVIVOR_SAFE_STABILITY := 0.6
const SPENT_RIVALRY := -0.8

const OPENING_DELAY_MONTHS := 3
const OPENING_STAGGER := 4
const PLAN_MIN_MONTHS := 3
const PLAN_SPREAD_MONTHS := 3
const FORESHADOW_LEAD_MONTHS := 1

const PACT_SHELVE_CHANCE := 0.5
const CONDEMN_CHANCE := 0.35
const CONDEMN_COST := -0.12
const PRESSURE_COST := -0.06
const COURT_GAIN := 0.05
const COURT_PLAYER_GAIN := 0.06
const PACT_GROUND := 0.1
const PACT_CHANCE := 0.5
const PACT_OPENING_TRADE := 200.0
const PACT_GOODWILL := 0.05
const CONSOLIDATION_GAIN := 0.01
const CONSOLIDATION_CEILING := 0.95

const AXIS_FORMS := 0.7
const AXIS_BREAKS := 0.3
const FEUD_FORMS := -0.7
const FEUD_BREAKS := -0.3


static func monthly(state: GameState) -> Array[String]:
	var notes: Array[String] = []
	_drift_world_relations(state)
	for i in range(state.world.size()):
		_deliberate(state, state.world[i], i, notes)
	update_arcs(state, notes)
	return notes


static func agenda_type(c: Country) -> String:
	var declared := String(c.agenda.get("type", ""))
	return declared if AGGRESSION.has(declared) else String(DEFAULT_AGENDA.get(c.regime_type, "survivor"))


static func country_by_id(state: GameState, id: String) -> Country:
	return state.country if id == state.country.id else state.world_country(id)


static func national_interest(state: GameState, actor: Country) -> Dictionary:
	var kind := agenda_type(actor)
	if actor.in_civil_war or actor.stability < TURN_INWARD_STABILITY \
			or (kind == "survivor" and actor.stability <= SURVIVOR_SAFE_STABILITY):
		return _interest("consolidate", null)
	for other in _others(state, actor):
		if _rel(actor, other).sanctioned:
			return _interest("undermine", other)
	if kind == "trader":
		var partner := _partner(state, actor, "ally", true)
		if partner == null:
			return _interest("consolidate", null)
		var pact_possible := partner != state.country and not _has_treaty(actor, partner, "trade")
		return _interest("trade" if pact_possible else "court", partner)
	if float(AGGRESSION[kind]) >= HOSTILE_AGENDA_LINE:
		var rival := _partner(state, actor, "rival", false)
		if rival != null:
			if kind == "hegemon" and _rel(actor, rival).score < SPENT_RIVALRY:
				var client := _partner(state, actor, "ally", true, rival)
				if client != null:
					return _interest("court", client)
			return _interest("undermine", rival)
	var ally := _partner(state, actor, "ally", true)
	return _interest("court", ally) if ally != null else _interest("consolidate", null)


static func hostile_action(state: GameState, actor: Country, target: Country, notes: Array[String]) -> String:
	if target == null:
		return "none"
	var against_player := target == state.country
	if against_player and _player_has_defence_pact(state) and state.rng.next_float() < PACT_SHELVE_CHANCE:
		return "shelved"
	var condemn := state.rng.next_float() < CONDEMN_CHANCE
	DiplomacySim.shift_between(actor, target, CONDEMN_COST if condemn else PRESSURE_COST)
	if against_player:
		notes.append(("%s publicly condemns your government." if condemn
			else "%s leans on your government, and relations cool.") % actor.name)
	else:
		notes.append(("%s publicly condemns %s." if condemn
			else "%s moves quietly to undermine %s.") % [actor.name, target.name])
	return "condemned" if condemn else "undermined"


static func cooperative_action(state: GameState, actor: Country, target: Country, notes: Array[String]) -> String:
	if target == null:
		return "none"
	var with_player := target == state.country
	if with_player and _rel(state.country, actor).sanctioned:
		return "refused"
	if not with_player and _rel(actor, target).score > PACT_GROUND and not _has_treaty(actor, target, "trade") \
			and state.rng.next_float() < PACT_CHANCE:
		_sign_trade_pact(state, actor, target)
		notes.append("%s and %s sign a trade pact." % [actor.name, target.name])
		return "trade_pact"
	DiplomacySim.shift_between(actor, target, COURT_PLAYER_GAIN if with_player else COURT_GAIN)
	if with_player:
		notes.append("%s is courting your government." % actor.name)
	else:
		notes.append("%s and %s deepen their ties." % [actor.name, target.name])
	return "courted"


static func update_arcs(state: GameState, notes: Array[String]) -> void:
	var everyone: Array[Country] = [state.country]
	everyone.append_array(state.world)
	for i in range(everyone.size()):
		for j in range(i + 1, everyone.size()):
			_update_arc(state, everyone[i], everyone[j], notes)


static func arc_key(a_id: String, b_id: String) -> String:
	return "%s|%s" % ([a_id, b_id] if a_id < b_id else [b_id, a_id])


static func _update_arc(state: GameState, a: Country, b: Country, notes: Array[String]) -> void:
	var rel: Country.BilateralRelation = a.relations.get(b.id)
	if rel == null:
		return
	var key := arc_key(a.id, b.id)
	var arc := String(state.world_arcs.get(key, ""))
	if arc == "":
		if rel.score > AXIS_FORMS and _has_treaty(a, b, "trade"):
			state.world_arcs[key] = "axis"
			notes.append("Diplomats begin speaking of a %s–%s axis." % [a.name, b.name])
		elif rel.score < FEUD_FORMS:
			state.world_arcs[key] = "feud"
			notes.append("The quarrel between %s and %s hardens into open feud." % [a.name, b.name])
	elif (arc == "axis" and rel.score < AXIS_BREAKS) or (arc == "feud" and rel.score > FEUD_BREAKS):
		state.world_arcs.erase(key)
		notes.append("The %s–%s %s is no more." % [a.name, b.name, arc])


static func _deliberate(state: GameState, actor: Country, index: int, notes: Array[String]) -> void:
	if actor.plan.is_empty():
		_make_plan(state, actor, state.turn + OPENING_DELAY_MONTHS - 1 + index % OPENING_STAGGER, -1)
		return
	if state.turn >= int(actor.plan.get("matures_turn", 0)):
		_execute(state, actor, notes)
		_make_plan(state, actor, state.turn + PLAN_MIN_MONTHS + state.rng.choose_index(PLAN_SPREAD_MONTHS), state.turn)
		return
	_foreshadow(state, actor, notes)


static func _make_plan(state: GameState, actor: Country, matures_turn: int, acted_turn: int) -> void:
	var interest := national_interest(state, actor)
	actor.plan = {"objective": interest["objective"], "target": interest["target"],
		"matures_turn": matures_turn, "last_acted_turn": acted_turn, "foreshadowed": false}


static func _foreshadow(state: GameState, actor: Country, notes: Array[String]) -> void:
	var plan := actor.plan
	if bool(plan.get("foreshadowed", false)) or not (String(plan.get("objective", "")) in LEAKING_OBJECTIVES):
		return
	if state.turn < int(plan.get("matures_turn", 0)) - FORESHADOW_LEAD_MONTHS:
		return
	var target := country_by_id(state, String(plan.get("target", "")))
	if target == null:
		return
	plan["foreshadowed"] = true
	notes.append("%s is weighing its options toward %s." % [actor.name, target.name])


static func _execute(state: GameState, actor: Country, notes: Array[String]) -> void:
	var target := country_by_id(state, String(actor.plan.get("target", "")))
	match String(actor.plan.get("objective", "")):
		"consolidate":
			actor.stability = minf(CONSOLIDATION_CEILING, actor.stability + CONSOLIDATION_GAIN)
		"undermine":
			hostile_action(state, actor, target, notes)
		"court", "trade":
			cooperative_action(state, actor, target, notes)


static func _drift_world_relations(state: GameState) -> void:
	for i in range(state.world.size()):
		for j in range(i + 1, state.world.size()):
			var a := state.world[i]
			var b := state.world[j]
			var ab: Country.BilateralRelation = a.relations.get(b.id)
			var ba: Country.BilateralRelation = b.relations.get(a.id)
			if ab == null or ba == null:
				continue
			var same: bool = DiplomacySim.REGIME_FAMILY.get(a.regime_type, a.regime_type) \
				== DiplomacySim.REGIME_FAMILY.get(b.regime_type, b.regime_type)
			DiplomacySim.shift_between(a, b, DiplomacySim.SAME_CAMP_DRIFT if same else DiplomacySim.OTHER_CAMP_DRIFT)
			for rel in [ab, ba]:
				for tr in rel.treaties:
					if tr is Dictionary:
						tr["turns_active"] = int(tr.get("turns_active", 0)) + 1
			if _has_treaty(a, b, "trade"):
				var ceiling := maxf(0.0, ab.score) * DiplomacySim.TRADE_CEILING
				var volume := clampf(ab.trade_volume + (ceiling - ab.trade_volume) * DiplomacySim.TRADE_APPROACH,
					0.0, DiplomacySim.TRADE_CEILING)
				ab.trade_volume = volume
				ba.trade_volume = volume


static func _sign_trade_pact(state: GameState, actor: Country, target: Country) -> void:
	var treaty := {"id": "trade_%s_%s_%d" % [actor.id, target.id, state.turn],
		"name": "%s–%s Trade Pact" % [actor.name, target.name], "type": "trade",
		"parties": [actor.id, target.id], "turns_active": 0}
	var ab := _rel(actor, target)
	var volume := clampf(ab.trade_volume + PACT_OPENING_TRADE, 0.0, DiplomacySim.TRADE_CEILING)
	for rel in [ab, _rel(target, actor)]:
		rel.treaties.append(treaty.duplicate(true))
		rel.trade_volume = volume
	DiplomacySim.shift_between(actor, target, PACT_GOODWILL)


static func _interest(objective: String, target: Country) -> Dictionary:
	return {"objective": objective, "target": "" if target == null else target.id}


static func _others(state: GameState, actor: Country) -> Array[Country]:
	var out: Array[Country] = []
	for c in state.world:
		if c != actor and actor.relations.has(c.id):
			out.append(c)
	if actor != state.country and actor.relations.has(state.country.id):
		out.append(state.country)
	out.sort_custom(func(x: Country, y: Country) -> bool: return x.id < y.id)
	return out


static func _partner(state: GameState, actor: Country, role: String, warmest: bool, excluded: Country = null) -> Country:
	var authored := country_by_id(state, String(actor.agenda.get(role, "")))
	if authored != null and authored != actor and authored != excluded and actor.relations.has(authored.id):
		return authored
	var best: Country = null
	for other in _others(state, actor):
		if other == excluded:
			continue
		var score := _rel(actor, other).score
		if best == null or (score > _rel(actor, best).score if warmest else score < _rel(actor, best).score):
			best = other
	return best


static func _rel(a: Country, b: Country) -> Country.BilateralRelation:
	return a.relations.get(b.id)


static func _has_treaty(a: Country, b: Country, kind: String) -> bool:
	var rel := _rel(a, b)
	return rel != null and rel.treaties.any(func(tr): return tr is Dictionary and String(tr.get("type", "")) == kind)


static func _player_has_defence_pact(state: GameState) -> bool:
	for other in state.world:
		if _has_treaty(state.country, other, "defense"):
			return true
	return false
