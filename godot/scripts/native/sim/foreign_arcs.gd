class_name ForeignArcs
extends RefCounted


const TARGETS := ["__supplier__", "__rival__", "__western__", "__union_anchor__",
	"__in_civil_war__", "__fragile__", "__concert_foe__", "__warmest__"]
const HANDLERS: Array[String] = ["valve_pay", "valve_cargo", "valve_appeal_west", "transit_concede",
	"transit_arbitrate", "windfall_storage", "isf_crisis_renegotiate", "concert_embrace", "union_accept",
	"union_play_west", "union_comply", "coup_recognise", "coup_condemn", "coup_wait", "sanctions_join",
	"sanctions_abstain", "sanctions_oppose", "arms_buy", "interests_acknowledge", "interests_internationalise",
	"west_fast_track", "west_conditions_stalled"]
const CONDITIONS: Array[String] = ["transit_dispute_ripe", "transit_windfall_due", "concert_delegation_due",
	"union_invites", "union_member_pressed", "western_aid_offered", "neighbour_coup_ripe",
	"sanctions_coalition_forming", "arms_offer_open", "rival_presses_interests", "west_relief_open"]
const EVENT_IDS: Array[String] = ["valve_threat", "transit_dispute", "transit_windfall", "isf_review_crisis",
	"concert_delegation", "union_invitation", "union_pressure", "western_aid_strings", "aid_conditions_due",
	"neighbour_coup", "sanctions_coalition", "arms_offer", "rival_interests", "concert_energy_offer", "concert_energy_conditions"]
const GATES := ["energy_verb", "orientation_verb", "diplomacy_verb"]
const COUP_STABILITY := 0.3
const COUP_MAX_WAR_RISK := 0.5
const CONCERT_FOE_LINE := -0.6
const VALVE_TRANCHES := 3
const TRANSIT_WARMTH := -0.3
const GAS_SITUATION_TURN := 12
const WEST_APPEAL := 0.03
const ARBITRATION_GOODWILL := 0.03
const DELEGATION_MONTHS := 3
const PLAY_WEST := 0.03
const COMPLY_WEST := -0.03
const COUP_REGIME := "authoritarian"
const COUP_ORDER := 0.35
const COUP_CONDEMN_WEST := 0.02
const SANCTIONS_WEST := 0.05
const ABSTAIN_WEST := -0.03
const OPPOSE_WEST := -0.06
const ARMS_INSURGENCY := 0.2
const ARMS_RIVAL_LINE := -0.5
const ARMS_CALM := 0.05
const ARMS_RIVAL := -0.04
const INTERESTS_LINE := -0.4
const INTERESTS_MEMORY := 12
const INTERESTS_WEST := 0.04
const WEST_RELIEF_HOSTILITY := -0.08
const STALLED_SHARE := 0.5
const STALLED_OPEN_WEST := -0.08

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
		"concert_delegation_due":
			var r := state.foreign.reached
			return state.player.in_government and r.has("concert_application") and not r.has("concert_agreement") \
				and not r.has("union_observer") and not r.has("union_member")
		"union_invites":
			var r := state.foreign.reached
			var left := state.foreign.union_left_turn
			return state.player.in_government and not r.has("union_observer") and not r.has("union_member") \
				and _score(state, resolve_target(state, "__union_anchor__")) >= OrientationActions.OBSERVER_WARMTH \
				and (left < 0 or state.turn - left >= OrientationActions.UNION_REJOIN_MONTHS)
		"union_member_pressed":
			return state.player.in_government and state.foreign.reached.has("union_member")
		"western_aid_offered":
			var strained := bool(state.foreign.isf.get("suspended", false)) \
				or state.country.economy.deficit_share_of_gdp() > float(OrientationSim.isf_targets(state)["deficit"])
			return state.player.in_government and not state.foreign.reached.has("union_member") and strained
		"neighbour_coup_ripe":
			return state.player.in_government and resolve_target(state, "__fragile__") != ""
		"sanctions_coalition_forming":
			return state.player.in_government and resolve_target(state, "__concert_foe__") != ""
		"arms_offer_open":
			var rival := resolve_target(state, "__rival__")
			var threatened := state.insurgency_pressure >= ARMS_INSURGENCY 				or (rival != "" and _score(state, rival) <= ARMS_RIVAL_LINE)
			return state.player.in_government and threatened and resolve_target(state, "__warmest__") != ""
		"rival_presses_interests":
			var rival := resolve_target(state, "__rival__")
			if not state.player.in_government or rival == "" or _score(state, rival) > INTERESTS_LINE:
				return false
			return state.foreign.hostile_log.any(func(r: Dictionary) -> bool:
				return String(r.get("actor", "")) == rival and state.turn - int(r.get("turn", -999)) <= INTERESTS_MEMORY)
		"west_relief_open":
			var r := state.foreign.reached
			if not state.player.in_government or not GasSim.is_active(state) or not r.has("concert_application") \
					or r.has("union_observer") or r.has("union_member"):
				return false
			var g := GasSim.gas(state)
			return g.second_line_started >= 0 and g.second_line_volume <= 0.0 and g.second_line_months_saved == 0 \
				and GasSim.second_line_months(g) - (state.turn - g.second_line_started) > GasSim.FAST_TRACK_MONTHS
	return false


static func _transit_open(state: GameState) -> bool:
	return state.player.in_government and GasSim.is_active(state) and state.turn >= GAS_SITUATION_TURN \
			and not ("transit" in GasSim.gas(state).concessions)


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
		"isf_crisis_renegotiate":
			return _through(OrientationActions.act(state, "isf_renegotiate"))
		"concert_embrace":
			state.foreign.western_qualifying_months = mini(OrientationActions.QUALIFYING_MONTHS_FOR_AGREEMENT,
				state.foreign.western_qualifying_months + DELEGATION_MONTHS)
			return "The Concert's list becomes the government's programme."
		"union_accept":
			return _through(OrientationActions.act(state, "union_observer"))
		"union_play_west":
			shift(state, "__western__", PLAY_WEST)
			return "The Western embassies read the Union's letter with interest."
		"union_comply":
			shift(state, "__western__", COMPLY_WEST)
			return "Ardenia votes as the Union expects."
		"coup_recognise", "coup_wait":
			return _coup(state, target)
		"coup_condemn":
			var line := _coup(state, target)
			shift(state, "__western__", COUP_CONDEMN_WEST)
			return line
		"sanctions_join":
			var line := _through(DiplomacyActions.act(state, "impose_sanctions", target))
			shift(state, "__western__", SANCTIONS_WEST)
			return line
		"sanctions_abstain":
			shift(state, "__western__", ABSTAIN_WEST)
			return "Ardenia abstains, and the Concert notes who did."
		"sanctions_oppose":
			shift(state, "__western__", OPPOSE_WEST)
			return "Ardenia speaks against the coalition."
		"arms_buy":
			state.insurgency_pressure = clampf(state.insurgency_pressure - ARMS_CALM, 0.0, 1.0)
			shift(state, "__rival__", ARMS_RIVAL)
			return "The arms arrive by rail, and the border hears about it."
		"interests_acknowledge":
			shift(state, "__western__", -INTERESTS_WEST)
			return "Ardenia's reply recognises its neighbour's interests. The West reads it twice."
		"interests_internationalise":
			shift(state, "__western__", INTERESTS_WEST)
			return "The note is published in the Western press."
		"west_fast_track":
			var g := GasSim.gas(state)
			if g.second_line_started < 0 or g.second_line_volume > 0.0:
				return ""
			g.second_line_months_saved = GasSim.FAST_TRACK_MONTHS
			shift(state, "__supplier__", WEST_RELIEF_HOSTILITY)
			return "Western contractors arrive on the second line. It will open in %d months." % maxi(0, \
				GasSim.second_line_months(g) - (state.turn - g.second_line_started))
		"west_conditions_stalled":
			var g := GasSim.gas(state)
			if g.second_line_volume > 0.0 or g.second_line_started < 0:
				shift(state, "__western__", STALLED_OPEN_WEST)
				return "The Concert notes that its help was banked and its conditions were not."
			if g.second_line_months_saved > 0:
				g.second_line_months_saved = int(GasSim.FAST_TRACK_MONTHS * STALLED_SHARE)
			return "The Concert slows its money, and the second line slips."
	return ""


static func _coup(state: GameState, target: String) -> String:
	var c := state.world_country(target)
	if c == null or not _fragile(c):
		return ""
	c.regime_type = COUP_REGIME
	c.stability = maxf(c.stability, COUP_ORDER)
	return "The generals hold %s's capital." % c.name


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
