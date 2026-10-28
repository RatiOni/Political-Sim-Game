class_name CabinetActions
extends RefCounted

## Task 14's native cabinet decision boundary. Candidate lists are persisted on
## GameState so no UI refresh or save/load can quietly redraw the choice.

const CORE_PORTFOLIOS: Array[String] = ["Finance", "Interior", "Foreign Affairs", "Defense", "Economy", "Justice"]
const FIRST_NAMES: Array[String] = ["Elena", "Viktor", "Dmitri", "Ana", "Leon", "Sonja", "Mira", "Tomas", "Ingrid", "Pavel", "Katarina", "Stefan"]
const LAST_NAMES: Array[String] = ["Voss", "Haan", "Koval", "Petrov", "Marsh", "Bauer", "Dragu", "Kessler", "Orlov", "Renz", "Sava", "Lindqvist"]

static func issue_shortlist(state: GameState, portfolio: String) -> Dictionary:
	var reason := _action_reason(state, portfolio)
	if reason != "":
		return _error(reason)
	if state.cabinet_shortlists.has(portfolio):
		return {"ok": true, "message": "The existing shortlist remains open."}
	var factions := _candidate_factions(state)
	if factions.size() < 1:
		return _error("No eligible political factions can supply a minister.")
	var picks: Array[Faction] = []
	picks.append(_own_faction(state))
	picks.append(_partner_or_outreach_faction(state, picks[0]))
	picks.append(_wildcard_faction(state, picks))
	var candidates: Array[Minister] = []
	for index in range(3):
		var faction: Faction = picks[index] if index < picks.size() and picks[index] != null else factions[index % factions.size()]
		candidates.append(_generate_candidate(state, portfolio, faction, index == 2))
	state.cabinet_shortlists[portfolio] = candidates
	return {"ok": true, "message": "Three candidates are ready for %s." % portfolio}

static func appoint(state: GameState, portfolio: String, candidate_id: String) -> Dictionary:
	var reason := _action_reason(state, portfolio)
	if reason != "":
		return _error(reason)
	if candidate_id == "":
		return _error("Choose a named candidate before appointing.")
	var shortlist: Variant = state.cabinet_shortlists.get(portfolio, null)
	if not (shortlist is Array):
		return _error("Issue a shortlist before making this appointment.")
	var selected: Minister = null
	for row in shortlist:
		if row is Minister and (row as Minister).id == candidate_id:
			selected = row as Minister
			break
	if selected == null:
		return _error("That candidate is not on the current shortlist.")
	var old := _minister_for(state, portfolio)
	state.ministers = state.ministers.filter(func(row: Minister) -> bool: return row.portfolio != portfolio)
	selected.portfolio = portfolio
	state.ministers.append(selected)
	state.cabinet_shortlists.erase(portfolio)
	if old != null and old.faction_id != selected.faction_id:
		_adjust_loyalty(state, old.faction_id, -0.05)
	var incoming := _faction(state, selected.faction_id)
	if incoming != null:
		var reward := 0.0
		if incoming.id != state.player.faction_id:
			reward = 0.04 if incoming.in_coalition else 0.06
		reward += Minister.trait_effect(selected.trait_id, "appoint_faction_bonus", 0.0)
		_adjust_loyalty(state, incoming.id, reward)
	return {"ok": true, "message": "%s appointed as %s." % [selected.name, portfolio],
		"appointed_id": selected.id}

static func read_model(state: GameState) -> Dictionary:
	if state == null or state.player == null or state.country == null:
		return _error("No campaign is active.")
	var rows: Array = []
	for portfolio in CORE_PORTFOLIOS:
		var incumbent := _minister_for(state, portfolio)
		var candidates: Array = []
		var pending: Variant = state.cabinet_shortlists.get(portfolio, [])
		if pending is Array:
			for candidate in pending:
				if candidate is Minister:
					candidates.append(_minister_row(state, candidate as Minister))
		var reason := _action_reason(state, portfolio)
		rows.append({"portfolio": portfolio, "incumbent": null if incumbent == null else _minister_row(state, incumbent),
			"candidates": candidates, "issue_eligible": reason == "" and candidates.is_empty(),
			"issue_reason": reason if reason != "" else ("A shortlist is already open." if not candidates.is_empty() else ""),
			"appoint_eligible": reason == "" and not candidates.is_empty(),
			"appoint_reason": reason if reason != "" else ("Issue a shortlist first." if candidates.is_empty() else "")})
	return {"ok": true, "portfolios": rows}

static func _action_reason(state: GameState, portfolio: String) -> String:
	if state == null or state.player == null or state.country == null:
		return "No campaign is active."
	if not state.player.in_government:
		return "Only the sitting government can appoint ministers."
	if not CORE_PORTFOLIOS.has(portfolio):
		return "Unknown cabinet portfolio."
	return ""

static func _candidate_factions(state: GameState) -> Array[Faction]:
	var out: Array[Faction] = []
	for faction in state.country.factions:
		if faction != null and faction.seats > 0:
			out.append(faction)
	return out

static func _own_faction(state: GameState) -> Faction:
	return _faction(state, state.player.faction_id)

static func _partner_or_outreach_faction(state: GameState, own: Faction) -> Faction:
	var candidates: Array[Faction] = []
	for faction in _candidate_factions(state):
		if faction != own and faction.in_coalition:
			candidates.append(faction)
	if candidates.is_empty():
		for faction in _candidate_factions(state):
			if faction != own:
				candidates.append(faction)
	if candidates.is_empty(): return own
	candidates.sort_custom(func(a: Faction, b: Faction) -> bool: return a.loyalty > b.loyalty)
	return candidates[0]

static func _wildcard_faction(state: GameState, excluded: Array) -> Faction:
	var options: Array[Faction] = []
	for faction in _candidate_factions(state):
		if not excluded.has(faction): options.append(faction)
	if options.is_empty(): options = _candidate_factions(state)
	return options[state.rng.choose_index(options.size())]

static func _generate_candidate(state: GameState, portfolio: String, faction: Faction, wildcard: bool) -> Minister:
	var minister := Minister.new()
	minister.id = "cab_%s_%d" % [portfolio.to_lower().replace(" ", "_"), state.rng.next_u32()]
	minister.name = "%s %s" % [FIRST_NAMES[state.rng.choose_index(FIRST_NAMES.size())], LAST_NAMES[state.rng.choose_index(LAST_NAMES.size())]]
	minister.portfolio = portfolio
	minister.faction_id = faction.id
	minister.competence = clampf(0.38 + state.rng.next_float() * 0.44 + (0.14 if wildcard else 0.0), 0.0, 0.95)
	minister.loyalty = clampf(0.50 + faction.loyalty * 0.25 + (state.rng.next_float() - 0.5) * 0.18, 0.15, 0.95)
	minister.ambition = clampf(0.12 + state.rng.next_float() * 0.58, 0.0, 0.90)
	var traits: Array = Minister.TRAIT_EFFECTS.keys()
	traits.sort()
	minister.trait_id = String(traits[state.rng.choose_index(traits.size())])
	return minister

static func _minister_row(state: GameState, minister: Minister) -> Dictionary:
	var faction := _faction(state, minister.faction_id)
	return {"id": minister.id, "name": minister.name, "faction_id": minister.faction_id,
		"faction_name": minister.faction_id if faction == null else faction.name, "portfolio": minister.portfolio,
		"competence": minister.competence, "effective_competence": minister.effective_competence(),
		"loyalty": minister.loyalty, "ambition": minister.ambition, "trait": minister.trait_label(),
		"implementation_quality": minister.implementation_quality(), "threat": minister.threat_level()}

static func _minister_for(state: GameState, portfolio: String) -> Minister:
	for candidate in state.ministers:
		if candidate is Minister and (candidate as Minister).portfolio == portfolio: return candidate as Minister
	return null

static func _faction(state: GameState, faction_id: String) -> Faction:
	for faction in state.country.factions:
		if faction.id == faction_id: return faction
	return null

static func _adjust_loyalty(state: GameState, faction_id: String, amount: float) -> void:
	var faction := _faction(state, faction_id)
	if faction != null: faction.loyalty = clampf(faction.loyalty + amount, -1.0, 1.0)

static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}