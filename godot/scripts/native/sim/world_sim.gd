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
const SETTLED_RIVALRY := -0.3
const CAUSE_NEVER_SPENT := ["retaken"]
const CAUSE_SETTLED := ["settled"]

const OPENING_DELAY_MONTHS := 3
const OPENING_STAGGER := 4
const PLAN_MIN_MONTHS := 3
const PLAN_SPREAD_MONTHS := 3
const FORESHADOW_LEAD_MONTHS := 1

const PACT_SHELVE_CHANCE := 0.5
const PATIENCE_FLOOR_MONTHS := 6
const PATIENCE_CEILING_MONTHS := 18
const PATIENCE_COLDEST := -0.8
const PATIENCE_PER_WARMTH := 12.0
const FORESHADOW_MERGE_MONTHS := 3
const CARRIED_PLAN_KEYS := ["last_pressed_turn", "last_warned_target", "last_warned_turn"]
const RIVAL_RECOVERY_RATE := 0.003
const RIVAL_RECOVERY_TARGET := -0.6
const CONDEMN_CHANCE := 0.35
const CONDEMN_COST := -0.12
const PRESSURE_COST := -0.06
const LEVERAGE_PRESSURE_WEIGHT := 0.5
const WARMTH_DAMPING := 0.5
const WARMTH_FACTOR_FLOOR := 0.5
const HOSTILE_LOG_LIMIT := 24
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
	_rivalries_cool(state)
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
			var score := _rel(actor, rival).score
			var resting := kind == "hegemon" and score < spent_rivalry(state, actor, rival)
			var waiting := rival == state.country \
				and state.turn - int(actor.plan.get("last_pressed_turn", -999)) < press_interval(score)
			if resting or waiting:
				var client := _partner(state, actor, "ally", true, rival)
				if client != null:
					return _interest("court", client)
			return _interest("undermine", rival)
	var ally := _partner(state, actor, "ally", true)
	return _interest("court", ally) if ally != null else _interest("consolidate", null)


static func press_interval(score: float) -> int:
	return clampi(PATIENCE_FLOOR_MONTHS + roundi((score - PATIENCE_COLDEST) * PATIENCE_PER_WARMTH),
		PATIENCE_FLOOR_MONTHS, PATIENCE_CEILING_MONTHS)


static func spent_rivalry(state: GameState, actor: Country, rival: Country) -> float:
	var cause := String(actor.agenda.get("backs", ""))
	if cause == "" or rival != state.country or not state.regions.has(cause):
		return SPENT_RIVALRY
	var status := String(state.campaign_meta.get("%s_status" % cause, ""))
	if status in CAUSE_NEVER_SPENT:
		return -INF
	return SETTLED_RIVALRY if status in CAUSE_SETTLED else SPENT_RIVALRY


static func hostile_action(state: GameState, actor: Country, target: Country, notes: Array[String]) -> String:
	if target == null:
		return "none"
	var against_player := target == state.country
	if against_player and _shielded_from(state, actor) and state.rng.next_float() < PACT_SHELVE_CHANCE:
		return "shelved"
	var condemn := state.rng.next_float() < CONDEMN_CHANCE
	if against_player:
		_press_player(state, actor, CONDEMN_COST if condemn else PRESSURE_COST)
		_say(state, notes, "world_condemn_player" if condemn else "world_pressure_player", actor, null)
	else:
		DiplomacySim.shift_between(actor, target, CONDEMN_COST if condemn else PRESSURE_COST)
		_say(state, notes, "world_condemn" if condemn else "world_undermine", actor, target)
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
		_say(state, notes, "world_trade_pact", actor, target)
		return "trade_pact"
	if with_player:
		DiplomacySim.shift(state, actor.id, COURT_PLAYER_GAIN)
	else:
		DiplomacySim.shift_between(actor, target, COURT_GAIN)
	if with_player:
		_say(state, notes, "world_court_player", actor, null)
	else:
		var press_only: Array[String] = []
		_say(state, press_only, "world_deepen", actor, target)
	return "courted"


static func update_arcs(state: GameState, notes: Array[String]) -> void:
	var arced := {}
	for key in state.world_arcs:
		var ids := String(key).split("|")
		if ids.size() == 2:
			arced[ids[0]] = arced.get(ids[0], {})
			arced[ids[0]][ids[1]] = true
			arced[ids[1]] = arced.get(ids[1], {})
			arced[ids[1]][ids[0]] = true
	for p in state.country_pairs():
		var a: Country = p[0]
		var b: Country = p[1]
		var score: float = (p[2] as Country.BilateralRelation).score
		if score >= FEUD_FORMS and score <= AXIS_FORMS and not (arced.has(a.id) and arced[a.id].has(b.id)):
			continue
		_update_arc(state, a, b, notes)


static func arc_key(a_id: String, b_id: String) -> String:
	return a_id + "|" + b_id if a_id < b_id else b_id + "|" + a_id


static func _update_arc(state: GameState, a: Country, b: Country, notes: Array[String]) -> void:
	var rel: Country.BilateralRelation = a.relations.get(b.id)
	if rel == null:
		return
	var key := arc_key(a.id, b.id)
	var arc := String(state.world_arcs.get(key, ""))
	if arc == "":
		if rel.score > AXIS_FORMS and _has_treaty(a, b, "trade"):
			state.world_arcs[key] = "axis"
			notes.append(Voice.say(state, "world_axis", {"a": a.name, "b": b.name}))
		elif rel.score < FEUD_FORMS:
			state.world_arcs[key] = "feud"
			notes.append(Voice.say(state, "world_feud", {"a": a.name, "b": b.name}))
	elif (arc == "axis" and rel.score < AXIS_BREAKS) or (arc == "feud" and rel.score > FEUD_BREAKS):
		state.world_arcs.erase(key)
		notes.append(Voice.say(state, "world_arc_ends", {"a": a.name, "b": b.name, "kind": arc}))


static func _deliberate(state: GameState, actor: Country, index: int, notes: Array[String]) -> void:
	if actor.plan.is_empty():
		_make_plan(state, actor, state.turn + OPENING_DELAY_MONTHS - 1 + index % OPENING_STAGGER, -1)
		return
	if state.turn >= int(actor.plan.get("matures_turn", 0)):
		var outcome := _execute(state, actor, notes)
		if String(actor.plan.get("objective", "")) == "undermine" and String(actor.plan.get("target", "")) == state.country.id:
			actor.plan["last_pressed_turn"] = state.turn
		_make_plan(state, actor, state.turn + PLAN_MIN_MONTHS + state.rng.choose_index(PLAN_SPREAD_MONTHS), state.turn)
		actor.plan["last_outcome"] = outcome
		return
	_foreshadow(state, actor, notes)


static func _make_plan(state: GameState, actor: Country, matures_turn: int, acted_turn: int) -> void:
	var interest := national_interest(state, actor)
	var plan := {"objective": interest["objective"], "target": interest["target"],
		"matures_turn": matures_turn, "last_acted_turn": acted_turn, "foreshadowed": false}
	for key in CARRIED_PLAN_KEYS:
		if actor.plan.has(key):
			plan[key] = actor.plan[key]
	actor.plan = plan


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
	if String(plan.get("last_warned_target", "")) == target.id \
			and state.turn - int(plan.get("last_warned_turn", -999)) < FORESHADOW_MERGE_MONTHS:
		return
	plan["last_warned_target"] = target.id
	plan["last_warned_turn"] = state.turn
	_say(state, notes, "world_deliberates", actor, target)


static func _execute(state: GameState, actor: Country, notes: Array[String]) -> String:
	var target := country_by_id(state, String(actor.plan.get("target", "")))
	match String(actor.plan.get("objective", "")):
		"undermine":
			return hostile_action(state, actor, target, notes)
		"court", "trade":
			return cooperative_action(state, actor, target, notes)
	actor.stability = minf(CONSOLIDATION_CEILING, actor.stability + CONSOLIDATION_GAIN)
	return "consolidated"


static func _say(state: GameState, notes: Array[String], key: String, actor: Country, target: Country) -> void:
	var fields := {"actor": actor.name, "actor_leader": Voice.leader(actor)}
	if target != null:
		fields["target"] = "your government" if target == state.country else target.name
		fields["target_leader"] = state.player.name if target == state.country else Voice.leader(target)
	notes.append(Voice.say(state, key, fields))


static func _drift_world_relations(state: GameState) -> void:
	var families: Array[String] = [""]
	for c in state.world:
		families.append(String(DiplomacySim.REGIME_FAMILY.get(c.regime_type, c.regime_type)))
	for p in state.country_pairs():
		if p[4]:
			continue
		var a: Country = p[0]
		var b: Country = p[1]
		var ab: Country.BilateralRelation = p[2]
		var ba: Country.BilateralRelation = p[3]
		var same: bool = families[p[5]] == families[p[6]]
		ab.score = clampf(ab.score + (DiplomacySim.SAME_CAMP_DRIFT if same else DiplomacySim.OTHER_CAMP_DRIFT), -1.0, 1.0)
		ba.score = ab.score
		if ab.treaties.is_empty() and ba.treaties.is_empty():
			continue
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
	if rel == null:
		return false
	for tr in rel.treaties:
		if tr is Dictionary and String(tr.get("type", "")) == kind:
			return true
	return false


static func _shielded_from(state: GameState, aggressor: Country) -> bool:
	if state.foreign != null and state.foreign.reached.has("meridian_guarantee"):
		return true
	for other in state.world:
		if other != aggressor and _has_treaty(state.country, other, "defense"):
			return true
	return false


static func _rivalries_cool(state: GameState) -> void:
	for c in state.world:
		if not DiplomacySim.is_rival_of_player(state, c) or not c.relations.has(state.country.id):
			continue
		var feeding := String(c.plan.get("objective", "")) == "undermine" and String(c.plan.get("target", "")) == state.country.id
		var score := _rel(c, state.country).score
		if not feeding and score < RIVAL_RECOVERY_TARGET:
			DiplomacySim.shift(state, c.id, minf(RIVAL_RECOVERY_RATE, RIVAL_RECOVERY_TARGET - score))


static func warmth_factor(score: float) -> float:
	return clampf(1.0 - WARMTH_DAMPING * maxf(0.0, score - FEUD_FORMS), WARMTH_FACTOR_FLOOR, 1.0)


static func coercion_strength(state: GameState, actor: Country) -> float:
	var score := _rel(state.country, actor).score
	return (1.0 + LEVERAGE_PRESSURE_WEIGHT * ForeignSim.leverage_of(state, actor.id)) * warmth_factor(score)


static func _press_player(state: GameState, actor: Country, cost: float) -> void:
	var relation_before := _rel(state.country, actor).score
	var growth_before := state.country.economy.growth_rate
	var stability_before := state.stability_value
	DiplomacySim.shift_between(actor, state.country, cost * coercion_strength(state, actor))
	if state.foreign == null:
		return
	state.foreign.hostile_log.append({"turn": state.turn, "actor": actor.id,
		"relation": _rel(state.country, actor).score - relation_before,
		"economy": state.country.economy.growth_rate - growth_before,
		"stability": state.stability_value - stability_before})
	while state.foreign.hostile_log.size() > HOSTILE_LOG_LIMIT:
		state.foreign.hostile_log.pop_front()
