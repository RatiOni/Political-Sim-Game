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
]

const CONDITIONS := ["schemer_plotting"]

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
	return ""


static func condition_met(state: GameState, rule_id: String) -> bool:
	match rule_id:
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
