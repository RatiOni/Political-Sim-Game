class_name EventsSim
extends RefCounted


const QUIET_OPENING_MONTHS := 2
const MAX_PENDING := 3
const DECISION_WINDOW_MONTHS := 2


const TARGET_KEYS := ["__coolest__", "__most_hostile__"]

const KNOWN_CONDITIONS := ["always", "never", "has_serious_grievance", "any_cool_relation",
	"any_bad_relation", "any_disloyal_minister", "has_opposition", "has_active_trade",
	"fiscal_strain", "price_or_debt_alarm", "labour_pressure", "high_unemployment",
	"budget_surplus", "weak_state", "has_active_law", "neighbour_in_civil_war",
	"shaky_government", "out_of_office", "own_party_seated_in_opposition", "restless_own_party"]


static func catalog() -> Array:
	var content: Dictionary = ContentRepository.load_all()
	var events: Variant = content.get("catalogs", {}).get("events", {}).get("events", [])
	return events if events is Array else []


static var _by_id: Dictionary = {}


static func event_by_id(event_id: String) -> Dictionary:
	if _by_id.is_empty():
		for e in catalog():
			_by_id[String(e.get("id", ""))] = e
	return _by_id.get(event_id, {})


static func option_by_id(event: Dictionary, option_id: String) -> Dictionary:
	for o in event.get("options", []):
		if String(o.get("id", "")) == option_id:
			return o
	return {}


static func is_playable(event: Dictionary) -> bool:
	var condition := String(event.get("condition", ""))
	if event.is_empty() or not (condition in KNOWN_CONDITIONS or condition in Arcs.CONDITIONS):
		return false
	for o in event.get("options", []):
		var handler: Variant = o.get("on_apply", null)
		if handler != null and not Arcs.has_handler(String(handler)):
			return false
	return option_by_id(event, String(event.get("default_option_id", ""))).size() > 0


static func unplayable_events() -> Array[String]:
	var out: Array[String] = []
	for e in catalog():
		if not is_playable(e):
			out.append(String(e["id"]))
	return out


static func condition_met(state: GameState, rule_id: String) -> bool:
	var econ := state.country.economy
	match rule_id:
		"always":
			return true
		"never":
			return false
		"has_serious_grievance":
			for f in state.country.factions:
				for g in f.grievances:
					if g.severity >= 0.45:
						return true
			return false
		"any_cool_relation":
			return _worst_relation(state, 0.3) != ""
		"any_bad_relation":
			return _worst_relation(state, -0.3) != ""
		"any_disloyal_minister":
			for m in state.ministers:
				if m.loyalty < 0.5:
					return true
			return false
		"has_opposition":
			for f in state.country.factions:
				if not f.in_coalition:
					return true
			return false
		"has_active_trade":
			for rel in state.country.relations.values():
				if (rel as Country.BilateralRelation).trade_volume > 500.0:
					return true
			return false
		"fiscal_strain":
			return econ.public_debt_pct > 0.70 or econ.inflation > 0.08
		"price_or_debt_alarm":
			return econ.inflation > 0.05 or econ.public_debt_pct > 0.60
		"labour_pressure":
			return econ.unemployment > 0.13 or econ.inflation > 0.09
		"high_unemployment":
			return econ.unemployment > 0.09
		"budget_surplus":
			return econ.budget.balance() > 300.0
		"weak_state":
			return state.country.bureaucratic_capacity < 0.6
		"has_active_law":
			return not state.enacted_laws.is_empty()
		"neighbour_in_civil_war":
			for c in state.world:
				if c.in_civil_war:
					return true
			return false
		"shaky_government":
			return state.stability_value < 0.5
		"out_of_office":
			return not state.player.in_government
		"own_party_seated_in_opposition":
			var party := _own_party(state)
			return not state.player.in_government and party != null and party.seats > 0
		"restless_own_party":
			var party := _own_party(state)
			if party == null:
				return false
			var dom := party.dominant_wing()
			return dom != null and dom.loyalty < 0.35
	return Arcs.condition_met(state, rule_id)


static func _own_party(state: GameState) -> Faction:
	for f in state.country.factions:
		if f.id == state.player.faction_id:
			return f
	return null


static func _worst_relation(state: GameState, below: float) -> String:
	var worst := ""
	var worst_score := below
	var keys := state.country.relations.keys()
	keys.sort()
	for key in keys:
		var rel: Country.BilateralRelation = state.country.relations[key]
		if rel.score < worst_score:
			worst = String(key)
			worst_score = rel.score
	return worst


static func audience_ok(state: GameState, event: Dictionary) -> bool:
	match String(event.get("audience", "government")):
		"government":
			return state.player.in_government
		"opposition":
			return not state.player.in_government
	return true


static func gate_reason(state: GameState, option: Dictionary) -> String:
	var gate: Variant = option.get("requires", null)
	if not (gate is Dictionary):
		return ""
	if gate.has("background") and String(state.campaign_meta.get("background", "")) != String(gate["background"]):
		return "Only open to a leader with the %s background." % String(gate["background"]).replace("_", " ")
	if gate.has("player_social_at_most") and state.player.ideology_social > float(gate["player_social_at_most"]):
		return "Only a markedly authoritarian leader would order this."
	return ""


static func monthly(state: GameState) -> Array[String]:
	var notes: Array[String] = []
	_lapse_overdue(state, notes)
	_deliver_follow_ups(state, notes)
	_maybe_arrive(state, notes)
	return notes


static func _lapse_overdue(state: GameState, notes: Array[String]) -> void:
	for situation in state.pending_situations.duplicate():
		if state.turn <= situation.deadline_turn:
			continue
		var event := event_by_id(situation.event_id)
		if not audience_ok(state, event):
			continue
		var option := option_by_id(event, String(event.get("default_option_id", "")))
		state.pending_situations.erase(situation)
		if option.is_empty():
			continue
		state.player.political_capital = maxf(0.0,
			state.player.political_capital - float(option.get("pc_cost", 0.0)))
		var line := apply_option(state, event, option, situation, true)
		var lapse_line := "Left undecided, %s was settled by default: %s." % [
			String(event.get("title", situation.event_id)), String(option.get("label", ""))]
		Voice.record(state, "situation_lapsed", {"title": String(event.get("title", situation.event_id)),
			"option": String(option.get("label", ""))}, lapse_line)
		notes.append(lapse_line)
		if line != "":
			notes.append(line)


static func _deliver_follow_ups(state: GameState, notes: Array[String]) -> void:
	for row in state.scheduled_events.duplicate():
		if int(row.get("due_turn", 0)) > state.turn:
			continue
		var event := event_by_id(String(row.get("event_id", "")))
		if not is_playable(event):
			state.scheduled_events.erase(row)
			continue
		if not audience_ok(state, event) or _is_pending(state, event["id"]):
			continue
		state.scheduled_events.erase(row)
		_arrive(state, event, String(row.get("target_country_id", "")), notes, true)


static func _maybe_arrive(state: GameState, notes: Array[String]) -> void:
	if state.turn <= QUIET_OPENING_MONTHS or state.pending_situations.size() >= MAX_PENDING:
		return
	var candidates: Array = []
	var none_chance := 1.0
	for event in catalog():
		if not _eligible(state, event):
			continue
		var chance := clampf(float(event.get("chance", 0.0)), 0.0, 1.0)
		candidates.append([event, chance])
		none_chance *= (1.0 - chance)
	if candidates.is_empty():
		return
	if state.rng.next_float() >= 1.0 - none_chance:
		return
	var total := 0.0
	for c in candidates:
		total += float(c[1])
	var pick := state.rng.next_float() * total
	for c in candidates:
		pick -= float(c[1])
		if pick <= 0.0:
			_arrive(state, c[0], "", notes)
			return
	_arrive(state, candidates[-1][0], "", notes)


static func _eligible(state: GameState, event: Dictionary) -> bool:
	var id := String(event.get("id", ""))
	if float(event.get("chance", 0.0)) <= 0.0 or not is_playable(event) or not audience_ok(state, event):
		return false
	if _is_pending(state, id):
		return false
	if state.event_fire_history.has(id):
		if bool(event.get("once", false)):
			return false
		var cooldown := int(event.get("cooldown", 0))
		if state.turn - int(state.event_fire_history[id]) < cooldown:
			return false
	if state.campaign_meta.get("country_id", "ardenia") != "ardenia" \
			and id in ContentRepository.load_all().get("catalogs", {}).get("events", {}).get("ardenia_only_events", []):
		return false
	return condition_met(state, String(event.get("condition", "never")))


static func _is_pending(state: GameState, event_id: String) -> bool:
	for s in state.pending_situations:
		if s.event_id == event_id:
			return true
	return false


static func _arrive(state: GameState, event: Dictionary, target: String, notes: Array[String],
		follows_on := false) -> void:
	var situation := Situation.new()
	situation.event_id = String(event["id"])
	situation.arrived_turn = state.turn
	situation.deadline_turn = state.turn + DECISION_WINDOW_MONTHS
	situation.target_country_id = target if target != "" else _diplomatic_target(state, event)
	state.pending_situations.append(situation)
	state.event_fire_history[situation.event_id] = state.turn
	var title := String(event.get("title", situation.event_id))
	var line := ("Following on from an earlier decision: %s needs a decision." if follows_on
		else "A new situation needs a decision: %s.") % title
	Voice.record(state, "situation", {"title": title, "category": String(event.get("category", ""))}, line)
	notes.append(line)


static func _diplomatic_target(state: GameState, event: Dictionary) -> String:
	for o in event.get("options", []):
		for key in o.get("relation_deltas", {}):
			if String(key) in TARGET_KEYS:
				return _worst_relation(state, INF)
	return ""


static func apply_option(state: GameState, event: Dictionary, option: Dictionary,
		situation: Situation, lapsed: bool) -> String:
	var event_id := String(event.get("id", ""))
	EffectBundle.apply(state, option.get("effects", {}), String(event.get("title", event_id)), "event:" + event_id, false)
	var deltas: Dictionary = option.get("relation_deltas", {})
	for key in deltas:
		var country_id := situation.target_country_id if String(key) in TARGET_KEYS else String(key)
		_shift_relation(state, country_id, float(deltas[key]))
	var follow: Variant = option.get("follow_up", null)
	if follow is Dictionary and state.rng.next_float() < float(follow.get("chance", 1.0)):
		state.scheduled_events.append({
			"event_id": String(follow.get("event_id", "")),
			"due_turn": state.turn + int(follow.get("delay", 1)),
			"target_country_id": situation.target_country_id,
		})
	var note := ""
	var handler: Variant = option.get("on_apply", null)
	if handler != null:
		var fields := Arcs.press_fields(state, String(handler))
		note = Arcs.run(state, String(handler))
		if note != "" and Arcs.PRESS_KEYS.has(String(handler)):
			Voice.record(state, String(Arcs.PRESS_KEYS[handler]), fields, note)
	state.event_history.append({"event_id": event_id, "option_id": String(option.get("id", "")),
		"turn": state.turn, "lapsed": lapsed})
	return note


static func _shift_relation(state: GameState, country_id: String, delta: float) -> void:
	DiplomacySim.shift(state, country_id, delta)
