class_name Arcs
extends RefCounted


const HANDLERS := [
	"schemer_noted", "schemer_buy_off", "schemer_resign", "schemer_crush",
	"schemer_expose", "schemer_ascend",
	"challenge_face_down", "challenge_accommodate", "challenge_purge",
	"vasca_crackdown", "vasca_lead_personally", "vasca_amnesty", "vasca_downplay",
	"vasca_taken", "vasca_backlash", "vasca_pull_back", "vasca_amnesty_worked",
	"vasca_grows", "vasca_storm", "vasca_exile", "vasca_unresolved",
	"vetrenka_absorb", "vetrenka_protest", "vetrenka_respond", "vetrenka_open_talks",
	"vetrenka_launch_offensive", "vetrenka_formalise", "vetrenka_settle",
	"vetrenka_talks_failed", "vetrenka_won", "vetrenka_lost", "vetrenka_partitioned",
	"vetrenka_normal", "vetrenka_backlash_lands",
	"opposition_claims_retreat", "opposition_offers_alternative", "opposition_misses_retreat",
	"by_election_national_push", "by_election_local_push", "by_election_stand_down",
]

const CONDITIONS := ["schemer_plotting", "vasca_stirring", "vetrenka_friction_due",
	"vetrenka_crossroads_ready", "government_in_retreat", "by_election_opening"]

const FRICTION_BEFORE_CROSSROADS := 3
const OCCUPATION_INSURGENCY := 0.25
const VETRENKA_REGION_OUTCOMES := {
	"settled": ["autonomous", "postwar_framework", 0.28, 0.48],
	"talks_failed": ["separatist", "unsettled_ceasefire", 0.03, 0.94],
	"retaken": ["state", "occupation_and_return", 0.32, 0.76],
	"routed": ["separatist", "worsened_ceasefire", 0.02, 0.98],
	"partitioned": ["separatist", "hardened_partition", 0.03, 0.58],
	"partitioned_contested": ["separatist", "contested_partition", 0.03, 0.82],
}

const VASCA_MIN_TURN := 8
const VASCA_MAX_ODDS := 0.92
const VASCA_GENERAL_BONUS := 0.20

const SCHEMER_THRESHOLD := 0.5


static func has_handler(handler_id: String) -> bool:
	return handler_id in HANDLERS


static func run(state: GameState, handler_id: String) -> String:
	if handler_id in OppositionSim.EVENT_HANDLERS:
		return OppositionSim.run_event(state, handler_id)
	match handler_id:
		"schemer_noted":
			var m := arc_schemer(state)
			return "" if m == null else "%s's allies are counting votes in the parliamentary party." % m.name
		"schemer_buy_off":
			var m := arc_schemer(state)
			if m == null:
				return ""
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
		"vetrenka_absorb", "vetrenka_protest":
			return _vetrenka_incident(state)
		"vetrenka_respond":
			_insurgency(state, 0.06)
			return _vetrenka_incident(state)
		"vetrenka_open_talks":
			var odds := clampf(0.55 + (state.player.approval - 0.49) * 1.4
				+ (state.stability_value - 0.48) * 0.7, 0.12, 0.90)
			if state.rng.next_float() < odds:
				_schedule(state, "vetrenka_settled", 4)
			else:
				_schedule(state, "vetrenka_talks_fail", 3)
			return "Talks over Vetrenka open under international mediation."
		"vetrenka_launch_offensive":
			var odds := clampf(0.25 + (security_effectiveness(state) - 0.25) * 1.8, 0.08, 0.70)
			if state.rng.next_float() < odds:
				_schedule(state, "vetrenka_retaken", 3)
			else:
				_schedule(state, "vetrenka_rout", 2)
			return "The army crosses the ceasefire line."
		"vetrenka_formalise":
			_schedule(state, "vetrenka_partition", 2)
			return "The government stops pretending the line is temporary."
		"vetrenka_partitioned":
			_insurgency(state, -0.10)
			var total := 0
			var nationalist_seats := 0
			for f in state.country.factions:
				total += f.seats
				if f.id == "national_conservatives":
					nationalist_seats = f.seats
			var standing := state.player.approval + state.stability_value * 0.5 \
				- float(nationalist_seats) / float(maxi(1, total))
			if standing > 0.70:
				_schedule(state, "vetrenka_normalised", 5)
			else:
				_schedule(state, "vetrenka_backlash", 4)
			return "The line of contact hardens into something like a border."
		"vetrenka_settle":
			_insurgency(state, -0.20)
			return _vetrenka_end(state, "settled", "Vetrenka returns as an autonomous region under a postwar framework.")
		"vetrenka_talks_failed":
			_insurgency(state, 0.10)
			state.stability_value = maxf(0.05, state.stability_value - 0.03)
			return _vetrenka_end(state, "talks_failed", "The talks collapse. The ceasefire holds, barely.")
		"vetrenka_won":
			_insurgency(state, OCCUPATION_INSURGENCY)
			return _vetrenka_end(state, "retaken", "Vetrenka is back under the state's control — and under occupation.")
		"vetrenka_lost":
			_insurgency(state, 0.35)
			state.stability_value = maxf(0.05, state.stability_value - 0.08)
			return _vetrenka_end(state, "routed", "The offensive is routed. The line moves the wrong way.")
		"vetrenka_normal":
			return _vetrenka_end(state, "partitioned", "Partition becomes the ordinary state of things.")
		"vetrenka_backlash_lands":
			state.stability_value = maxf(0.05, state.stability_value - 0.05)
			return _vetrenka_end(state, "partitioned_contested", "Partition stands, and nobody accepts it.")
	return ""


static func vetrenka_open(state: GameState) -> bool:
	return state.country.id == "ardenia" and state.player.in_government \
		and not state.campaign_meta.has("vetrenka_status")


static func _vetrenka_incident(state: GameState) -> String:
	state.campaign_meta["vetrenka_incidents"] = int(state.campaign_meta.get("vetrenka_incidents", 0)) + 1
	return "Another incident on the Vetrenka line."


static func _vetrenka_end(state: GameState, status: String, line: String) -> String:
	state.campaign_meta["vetrenka_status"] = status
	var region: RegionState = state.regions.get("vetrenka")
	var outcome: Array = VETRENKA_REGION_OUTCOMES.get(status, [])
	if region != null and outcome.size() == 4:
		region.control = String(outcome[0])
		region.issue_id = String(outcome[1])
		region.state_reach = float(outcome[2])
		region.pressure = float(outcome[3])
	return line


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
	if rule_id in OppositionSim.EVENT_CONDITIONS:
		return OppositionSim.condition_met(state, rule_id)
	match rule_id:
		"vetrenka_friction_due":
			return vetrenka_open(state)
		"vetrenka_crossroads_ready":
			return vetrenka_open(state) \
				and int(state.campaign_meta.get("vetrenka_incidents", 0)) >= FRICTION_BEFORE_CROSSROADS
		"vasca_stirring":
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
