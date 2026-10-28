class_name Arcs
extends RefCounted

## Bespoke consequences for authored story arcs: the effects an ordinary
## effect bundle cannot express (a minister forced out, a party wing purged).
## Each handler re-resolves its subject from live state and quietly does
## nothing if that subject has gone — a schemer who resigned in month 3 is
## not dismissed again in month 6.
##
## EventsSim asks `has_handler` before letting an event fire, so an arc whose
## handlers are not all written here simply cannot start.

const HANDLERS := [
	# The schemer arc.
	"schemer_noted", "schemer_buy_off", "schemer_resign", "schemer_crush",
	"schemer_expose", "schemer_ascend",
	# The party leadership challenge it hands off to.
	"challenge_face_down", "challenge_accommodate", "challenge_purge",
	# The Vasca question.
	"vasca_crackdown", "vasca_lead_personally", "vasca_amnesty", "vasca_downplay",
	"vasca_taken", "vasca_backlash", "vasca_pull_back", "vasca_amnesty_worked",
	"vasca_grows", "vasca_storm", "vasca_exile", "vasca_unresolved",
]

const CONDITIONS := ["schemer_plotting", "vasca_stirring"]

## Vasca never tests a government in its first months.
const VASCA_MIN_TURN := 8
## A crackdown's odds of success never quite reach certainty.
const VASCA_MAX_ODDS := 0.92
## A former general who goes west himself adds this to the odds.
const VASCA_GENERAL_BONUS := 0.20

## How dangerous a schemer must be before they act.
const SCHEMER_THRESHOLD := 0.5


static func has_handler(handler_id: String) -> bool:
	return handler_id in HANDLERS


## Runs one handler; returns a line for the record, or "".
static func run(state: GameState, handler_id: String) -> String:
	match handler_id:
		"schemer_noted":
			var m := arc_schemer(state)
			return "" if m == null else "%s's allies are counting votes in the parliamentary party." % m.name
		"schemer_buy_off":
			var m := arc_schemer(state)
			if m == null:
				return ""
			# Bought loyalty; the ambition that made them dangerous is intact.
			m.loyalty = minf(0.95, m.loyalty + 0.35)
			return "%s takes the offer and falls into line — for now." % m.name
		"schemer_resign", "schemer_expose":
			return _dismiss_schemer(state, 0.0)
		"schemer_crush":
			return _dismiss_schemer(state, 0.04)
		"schemer_ascend":
			var m := arc_schemer(state)
			if m == null:
				return ""
			var wing := _own_dominant_wing(state)
			if wing != null:
				wing.loyalty = maxf(-1.0, wing.loyalty - 0.15)
			return "%s's people now openly talk about the leadership." % m.name
		"challenge_face_down":
			var wing := _own_dominant_wing(state)
			if wing != null:
				wing.loyalty = maxf(-1.0, wing.loyalty - 0.08)
			return "The challenge is faced down. The wing is cowed, and resents it."
		"challenge_accommodate":
			var wing := _own_dominant_wing(state)
			if wing == null:
				return ""
			state.player.ideology_economic += (wing.ideology.economic - state.player.ideology_economic) * 0.15
			state.player.ideology_social += (wing.ideology.social - state.player.ideology_social) * 0.15
			wing.loyalty = minf(1.0, wing.loyalty + 0.25)
			return "The leader moves toward the wing, and the wing comes back."
		"challenge_purge":
			var party := _own_party(state)
			var wing := _own_dominant_wing(state)
			if party == null or wing == null:
				return ""
			wing.strength = maxf(0.0, wing.strength - 0.15)
			party.normalize_wings()
			for w in party.wings:
				w.loyalty = maxf(-1.0, w.loyalty - 0.10)
			state.stability_value = maxf(0.05, state.stability_value - 0.05)
			return "The rebels are purged. The party is smaller, quieter and afraid."
		"vasca_crackdown":
			return _vasca_operation(state, 0.0)
		"vasca_lead_personally":
			return _vasca_operation(state, VASCA_GENERAL_BONUS)
		"vasca_amnesty":
			# Terms for the rank and file, nothing for Vasca. It holds when there
			# is enough goodwill to make surrender look like sense.
			if state.rng.next_float() < 0.35 + state.player.approval * 0.5:
				_insurgency(state, -0.15)
				_schedule(state, "vasca_amnesty_holds", 3)
				return "Fighters begin coming down from the hills under the amnesty."
			_schedule(state, "vasca_regroups", 4)
			return "The amnesty is met with silence from the west."
		"vasca_downplay":
			_insurgency(state, 0.15)
			_schedule(state, "vasca_emboldened", 4)
			return "The government says the west is quiet. The west hears it."
		"vasca_taken":
			return _vasca_end(state, "captured", -0.45, "Vasca is in custody.")
		"vasca_storm":
			return _vasca_end(state, "dead", -0.40, "Vasca is found dead after the assault. Nobody agrees how.")
		"vasca_exile":
			return _vasca_end(state, "exiled", -0.35, "Vasca crosses the border into exile.")
		"vasca_amnesty_worked":
			return _vasca_end(state, "isolated", -0.25, "Vasca is left with a handful of loyalists and no movement.")
		"vasca_unresolved":
			return _vasca_end(state, "unresolved", 0.10, "No ending. The west stays the west.")
		"vasca_backlash":
			_insurgency(state, 0.20)
			state.stability_value = maxf(0.05, state.stability_value - 0.04)
			return "Escalation in the west draws in villages that had stayed out."
		"vasca_pull_back":
			_insurgency(state, 0.05)
			return "The operation is wound down. The remnant survives, and so does the question."
		"vasca_grows":
			_insurgency(state, 0.20)
			return "Vasca's following grows."
	return ""


## How well the state can actually reach into the west: the Interior and
## Defense ministers (a vacancy counts for little), steadied or undermined by
## how much authority the government has left.
static func security_effectiveness(state: GameState) -> float:
	var total := 0.0
	for portfolio in ["Interior", "Defense"]:
		var minister: Minister = null
		for m in state.ministers:
			if m.portfolio == portfolio:
				minister = m
				break
		total += 0.30 if minister == null else minister.implementation_quality()
	return clampf((total / 2.0) * 0.6 + state.stability_value * 0.4, 0.0, 1.0)


static func _vasca_operation(state: GameState, bonus: float) -> String:
	if state.rng.next_float() < minf(VASCA_MAX_ODDS, security_effectiveness(state) + bonus):
		_schedule(state, "vasca_crackdown_works", 2)
		return "Security forces sweep the western districts and close in."
	_insurgency(state, 0.30)
	_schedule(state, "vasca_crackdown_fails", 2)
	return "The sweep finds empty camps and angry villages."


static func _vasca_end(state: GameState, status: String, pressure_delta: float, line: String) -> String:
	_insurgency(state, pressure_delta)
	state.campaign_meta["vasca_status"] = status
	return line


static func _insurgency(state: GameState, delta: float) -> void:
	state.insurgency_pressure = clampf(state.insurgency_pressure + delta, 0.0, 1.0)


static func _schedule(state: GameState, event_id: String, delay: int) -> void:
	state.scheduled_events.append({"event_id": event_id, "due_turn": state.turn + delay, "target_country_id": ""})


static func condition_met(state: GameState, rule_id: String) -> bool:
	match rule_id:
		"vasca_stirring":
			# The west tests a government that looks weak enough to be worth it.
			if state.country.id != "ardenia" or not state.player.in_government:
				return false
			if state.turn < VASCA_MIN_TURN or state.campaign_meta.has("vasca_status"):
				return false
			return state.stability_value < 0.65 or state.player.approval < 0.50 or state.civil_war_risk > 0.25
		"schemer_plotting":
			if not state.player.in_government:
				return false
			var m := arc_schemer(state)
			return m != null and m.threat_level() > SCHEMER_THRESHOLD
	return false


## The most dangerous schemer in cabinet, or null.
static func arc_schemer(state: GameState) -> Minister:
	var best: Minister = null
	for m in state.ministers:
		if m.trait_id == "schemer" and (best == null or m.threat_level() > best.threat_level()):
			best = m
	return best


static func _dismiss_schemer(state: GameState, stability_cost: float) -> String:
	var m := arc_schemer(state)
	if m == null:
		return ""
	state.ministers.erase(m)
	if stability_cost > 0.0:
		state.stability_value = maxf(0.05, state.stability_value - stability_cost)
	return "%s is out of the cabinet; the %s portfolio is vacant." % [m.name, m.portfolio]


static func _own_party(state: GameState) -> Faction:
	for f in state.country.factions:
		if f.id == state.player.faction_id:
			return f
	return null


static func _own_dominant_wing(state: GameState) -> Faction.Wing:
	var party := _own_party(state)
	return null if party == null else party.dominant_wing()
