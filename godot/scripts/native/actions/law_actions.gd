class_name LawActions
extends RefCounted

const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")
const ParliamentaryVoteScript = preload("res://scripts/native/sim/parliamentary_vote.gd")

const STATUTORY_PROPOSAL_COST := 10.0
const CONSTITUTIONAL_PROPOSAL_COST := 14.0
const LOBBY_BASE_COST := 6.0
const LOBBY_POWER_COST := 6.0
const LOBBY_INCREMENT := 0.22
const LOBBY_CAP := 0.50
const DEFEAT_APPROVAL_PENALTY := 0.015

static var _catalog_cache: Array = []
static var _catalog_error: String = ""

static func preview_bill(state: GameState, bill_id: String) -> Dictionary:
	var check := _candidate(state, bill_id)
	if not check.get("ok", false):
		return check
	var law: Law = check["law"]
	return {"ok": true, "preview": _preview(state, law)}

static func propose(state: GameState, bill_id: String) -> Dictionary:
	if state == null or state.player == null or not state.player.in_government:
		return _error("Only the sitting government can introduce legislation.")
	if state.pending_law != null:
		return _error("Another bill is already before parliament.")
	var check := _candidate(state, bill_id)
	if not check.get("ok", false):
		return check
	var law: Law = check["law"]
	var cost := proposal_cost(law)
	if not is_finite(state.player.political_capital) or state.player.political_capital < cost:
		return _error("Not enough political capital (need %.0f)." % cost)
	state.player.political_capital -= cost
	law.status = "proposed"
	law.proposed_by = state.player.faction_id
	law.proposed_turn = state.turn
	state.pending_law = law
	return {"ok": true, "message": "%s is before parliament." % law.name,
		"political_capital_cost": cost}

static func lobby(state: GameState, faction_id: String) -> Dictionary:
	var law := _pending(state)
	if law == null:
		return _error("No government bill is awaiting a vote.")
	var faction: Faction = null
	for candidate in state.country.factions:
		if candidate.id == faction_id:
			faction = candidate
			break
	if faction == null or faction.seats <= 0:
		return _error("That faction has no parliamentary delegation to lobby.")
	if float(law.lobbying_bonus.get(faction.id, 0.0)) >= LOBBY_CAP:
		return _error("That faction's lobbying bonus is already at the cap.")
	var cost := LOBBY_BASE_COST + faction.power * LOBBY_POWER_COST
	if not is_finite(state.player.political_capital) or state.player.political_capital < cost:
		return _error("Not enough political capital (need %.0f)." % cost)
	state.player.political_capital -= cost
	law.lobbying_bonus[faction.id] = minf(LOBBY_CAP,
		float(law.lobbying_bonus.get(faction.id, 0.0)) + LOBBY_INCREMENT)
	return {"ok": true, "message": "Lobbied %s on %s." % [faction.name, law.name],
		"political_capital_cost": cost}

static func vote(state: GameState) -> Dictionary:
	var law := _pending(state)
	if law == null:
		return _error("No government bill is awaiting a vote.")
	# Never execute mutable save-file payload as policy. Preserve only campaign
	# process fields; authored identity and effects are rehydrated by stable id.
	law = _canonicalized_record(law)
	if law == null:
		return _error("The authored bill definition is unavailable.")
	state.pending_law = law
	var projection := _projection(state, law)
	law.votes_for = int(projection["votes_for"])
	law.votes_against = int(projection["votes_against"])
	var passed := bool(projection["passed"])
	if passed:
		law.status = "enacted"
		law.enacted_turn = state.turn
		_apply_effects_once(state, law)
		state.enacted_laws.append(law)
	else:
		law.status = "rejected"
		state.player.approval = maxf(0.0, state.player.approval - DEFEAT_APPROVAL_PENALTY)
	state.law_history.append(Law.from_dict(law.to_dict()))
	state.pending_law = null
	_apply_rebellion_penalties(state, projection["rebellions"])
	return {"ok": true, "passed": passed, "votes_for": law.votes_for,
		"votes_against": law.votes_against, "threshold": projection["threshold"],
		"rebellions": projection["rebellions"].duplicate(true),
		"message": "%s %s." % [law.name, "passed" if passed else "was defeated"]}

static func withdraw(state: GameState) -> Dictionary:
	var law := _pending(state)
	if law == null:
		return _error("No government bill can be withdrawn.")
	law.status = "withdrawn"
	state.law_history.append(Law.from_dict(law.to_dict()))
	state.pending_law = null
	return {"ok": true, "message": "Withdrew %s." % law.name}

static func read_model(state: GameState) -> Dictionary:
	if state == null or state.player == null or state.country == null:
		return _error("No campaign is active.")
	var catalog := _catalog()
	if catalog.is_empty():
		return _error(_catalog_error if _catalog_error != "" else "Bill catalogue is unavailable.")
	var bills: Array = []
	for raw in catalog:
		var law := Law.from_catalog(raw)
		var content_reason := _content_reason(state, law)
		if content_reason != "":
			return _error("Bill catalogue is invalid: %s" % content_reason)
		var reason := _availability_reason(state, law)
		bills.append({"id": law.id, "name": law.name, "description": law.description,
			"tier": law.tier, "portfolio": law.portfolio,
			"eligible": reason == "", "disabled_reason": reason})
	var pending_preview: Variant = null
	var pending_record: Variant = null
	if state.pending_law != null:
		var canonical_pending := _canonicalized_record(state.pending_law)
		if canonical_pending == null:
			return _error("The pending bill no longer exists in authored content.")
		pending_preview = _preview(state, canonical_pending)
		pending_record = canonical_pending.to_dict()
	var enacted: Array = []
	for law in state.enacted_laws:
		var canonical_enacted := _canonicalized_record(law)
		if canonical_enacted != null:
			enacted.append(canonical_enacted.to_dict())
	var history: Array = []
	for law in state.law_history:
		var canonical_history := _canonicalized_record(law)
		if canonical_history != null:
			history.append(canonical_history.to_dict())
	var pending_reason := "" if _pending(state) != null else "No government bill is awaiting a vote."
	var lobby_rows: Array = []
	for faction in state.country.factions:
		var cost := LOBBY_BASE_COST + faction.power * LOBBY_POWER_COST
		var reason := pending_reason
		if reason == "" and faction.seats <= 0:
			reason = "That faction has no parliamentary delegation to lobby."
		elif reason == "" and float(state.pending_law.lobbying_bonus.get(faction.id, 0.0)) >= LOBBY_CAP:
			reason = "That faction's lobbying bonus is already at the cap."
		elif reason == "" and state.player.political_capital < cost:
			reason = "Not enough political capital (need %.0f)." % cost
		lobby_rows.append({"id": faction.id, "name": faction.name, "seats": faction.seats,
			"cost": cost, "current_bonus": 0.0 if state.pending_law == null else
				float(state.pending_law.lobbying_bonus.get(faction.id, 0.0)),
			"eligible": reason == "", "disabled_reason": reason})
	return {"ok": true, "bills": bills,
		"pending": pending_record,
		"pending_preview": pending_preview, "enacted": enacted, "history": history,
		"political_capital": state.player.political_capital,
		"actions": {
			"propose": {"eligible": state.player.in_government and state.pending_law == null,
				"disabled_reason": "" if state.player.in_government and state.pending_law == null else
					("Only the sitting government can introduce legislation." if not state.player.in_government else "Another bill is already before parliament.")},
			"lobby": {"eligible": pending_reason == "", "disabled_reason": pending_reason},
			"vote": {"eligible": pending_reason == "", "disabled_reason": pending_reason},
			"withdraw": {"eligible": pending_reason == "", "disabled_reason": pending_reason},
		},
		"lobby_factions": lobby_rows}

static func proposal_cost(law: Law) -> float:
	return CONSTITUTIONAL_PROPOSAL_COST if law != null and law.tier == "constitutional" else STATUTORY_PROPOSAL_COST

static func _preview(state: GameState, law: Law) -> Dictionary:
	var canonical := _canonicalized_record(law)
	if canonical != null:
		law = canonical
	var projection := _projection(state, law)
	var effect_rows: Array = []
	for key in ["gdp_growth_delta", "unemployment_delta", "inflation_delta",
		"budget_revenue_delta", "budget_expenditure_delta", "one_time_debt_pct_delta"]:
		var value := float(law.effects.get(key, 0.0))
		if not is_zero_approx(value):
			effect_rows.append({"key": key, "value": value})
	for pair in [["faction_loyalty_deltas", "loyalty"], ["faction_power_deltas", "power"]]:
		var deltas: Dictionary = law.effects.get(pair[0], {})
		for faction_id in deltas:
			var faction_name := String(faction_id).replace("_", " ").capitalize()
			for faction in state.country.factions:
				if faction.id == faction_id:
					faction_name = faction.name
					break
			effect_rows.append({"key": "faction_%s" % pair[1], "subject": faction_name,
				"value": float(deltas[faction_id])})
	for modifier in law.effects.get("modifiers", []):
		if modifier is Dictionary:
			effect_rows.append({"key": String(modifier.get("target", "modifier")),
				"value": float(modifier.get("magnitude", 0.0)),
				"delay": int(modifier.get("onset_delay", 0))})
	return {"bill": law.to_dict(), "effects": effect_rows,
		"votes_for": projection["votes_for"], "votes_against": projection["votes_against"],
		"threshold": projection["threshold"], "passed": projection["passed"],
		"breakdown": projection["breakdown"].duplicate(true),
		"rebellions": projection["rebellions"].duplicate(true),
		"political_capital_cost": proposal_cost(law)}

static func _candidate(state: GameState, bill_id: String) -> Dictionary:
	if state == null or state.country == null:
		return _error("No campaign is active.")
	var law := _canonical_law(bill_id)
	if law == null:
		return _error("Unknown bill: %s." % bill_id)
	var reason := _availability_reason(state, law)
	return _error(reason) if reason != "" else {"ok": true, "law": law}

static func _canonical_law(bill_id: String) -> Law:
	for raw in _catalog():
		if raw is Dictionary and String(raw.get("id", "")) == bill_id:
			return Law.from_catalog(raw)
	return null

static func _canonicalized_record(source: Law) -> Law:
	if source == null:
		return null
	var law := _canonical_law(source.id)
	if law == null:
		return null
	law.status = source.status
	law.lobbying_bonus = source.lobbying_bonus.duplicate(true)
	law.votes_for = source.votes_for
	law.votes_against = source.votes_against
	law.proposed_by = source.proposed_by
	law.proposed_turn = source.proposed_turn
	law.enacted_turn = source.enacted_turn
	return law

static func _content_reason(state: GameState, law: Law) -> String:
	var faction_ids := {}
	for faction in state.country.factions:
		faction_ids[faction.id] = true
	for key in ["faction_loyalty_deltas", "faction_power_deltas"]:
		for faction_id in law.effects.get(key, {}):
			if not faction_ids.has(faction_id):
				return "%s references unknown faction '%s'." % [law.id, faction_id]
	return ""

static func _availability_reason(state: GameState, law: Law) -> String:
	if law.tier == "executive_order":
		return "Executive orders are not available in this parliamentary slice."
	if not (law.tier in ["statutory", "constitutional"]):
		return "Unsupported legislative tier."
	if state.pending_law != null and state.pending_law.id != law.id:
		return "Another bill is already before parliament."
	for enacted in state.enacted_laws:
		if enacted.id == law.id:
			return "This law is already in force."
	return ""

static func _pending(state: GameState) -> Law:
	if state == null or state.player == null or not state.player.in_government:
		return null
	if state.pending_law == null or state.pending_law.status != "proposed":
		return null
	return state.pending_law

static func _projection(state: GameState, law: Law) -> Dictionary:
	var ideology := Faction.Ideology.new()
	ideology.economic = law.ideology_economic
	ideology.social = law.ideology_social
	var stakes := {}
	var loyalty_deltas: Dictionary = law.effects.get("faction_loyalty_deltas", {})
	for faction in state.country.factions:
		var affinity := 1.0 - faction.effective_ideology().distance_to(ideology) / ParliamentaryVoteScript.MAX_DISTANCE
		var authored := float(loyalty_deltas.get(faction.id, 0.0))
		var coalition := 0.08 if faction.in_coalition else -0.03
		stakes[faction.id] = clampf((affinity - 0.5) * 0.28 + authored + coalition, -0.25, 0.25)
	var motion := {"id": law.id, "ideology": ideology, "stakes": stakes,
		"lobbying_bonus": law.lobbying_bonus.duplicate(true),
		"sponsor_id": state.player.faction_id,
		"player_faction_id": state.player.faction_id,
		"required_fraction": 2.0 / 3.0 if law.tier == "constitutional" else 0.5}
	return ParliamentaryVoteScript.project(state.country.factions, motion)

static func _apply_effects_once(state: GameState, law: Law) -> void:
	var economy := state.country.economy
	var effects := law.effects
	var growth := float(effects.get("gdp_growth_delta", 0.0))
	var unemployment := float(effects.get("unemployment_delta", 0.0))
	var inflation := float(effects.get("inflation_delta", 0.0))
	var revenue := float(effects.get("budget_revenue_delta", 0.0))
	var expenditure := float(effects.get("budget_expenditure_delta", 0.0))
	economy.structural_growth_rate += growth
	economy.growth_rate += growth
	economy.structural_unemployment = clampf(economy.structural_unemployment + unemployment, 0.0, 1.0)
	economy.unemployment = clampf(economy.unemployment + unemployment, 0.0, 1.0)
	economy.structural_inflation += inflation
	economy.inflation += inflation
	economy.structural_revenue += revenue
	economy.structural_expenditure += expenditure
	economy.budget.revenue += revenue
	economy.budget.expenditure += expenditure
	economy.public_debt_pct = maxf(0.0, economy.public_debt_pct +
		float(effects.get("one_time_debt_pct_delta", 0.0)))
	var loyalty: Dictionary = effects.get("faction_loyalty_deltas", {})
	var power: Dictionary = effects.get("faction_power_deltas", {})
	for faction in state.country.factions:
		if loyalty.has(faction.id):
			faction.loyalty = clampf(faction.loyalty + float(loyalty[faction.id]), -1.0, 1.0)
		if power.has(faction.id):
			faction.power = clampf(faction.power + float(power[faction.id]), 0.0, 1.0)
	for raw in effects.get("modifiers", []):
		if not (raw is Dictionary):
			continue
		var modifier := Modifier.new()
		modifier.id = String(raw.get("id", ""))
		modifier.source = String(raw.get("source", law.name))
		modifier.target = String(raw.get("target", ""))
		modifier.magnitude = float(raw.get("magnitude", 0.0))
		modifier.onset_delay = int(raw.get("onset_delay", 0))
		modifier.ramp_duration = int(raw.get("ramp_duration", 1))
		modifier.hold_duration = -1 if raw.get("hold_duration", null) == null else int(raw["hold_duration"])
		modifier.decay_duration = int(raw.get("decay_duration", 0))
		modifier.age = int(raw.get("age", 0))
		modifier.source_id = law.id
		modifier.portfolio = "" if raw.get("portfolio", null) == null else String(raw["portfolio"])
		modifier.institutional = bool(raw.get("institutional", true))
		state.modifiers.append(modifier)

static func _apply_rebellion_penalties(state: GameState, rebellions: Array) -> void:
	var rebel_ids := {}
	for row in rebellions:
		rebel_ids[String(row["wing_id"])] = true
	for faction in state.country.factions:
		for wing in faction.wings:
			if rebel_ids.has(wing.id):
				wing.loyalty = maxf(-1.0, wing.loyalty - 0.025)

static func _catalog() -> Array:
	var raw: Variant = _catalog_cache
	if _catalog_cache.is_empty():
		var content: Dictionary = ContentRepositoryScript.load_all()
		raw = content.get("catalogs", {}).get("bills", [])
	_catalog_error = _validate_catalog(raw)
	if _catalog_error != "":
		return []
	_catalog_cache = (raw as Array).duplicate(true)
	return _catalog_cache.duplicate(true)

static func _validate_catalog(raw: Variant) -> String:
	if not (raw is Array) or raw.is_empty():
		return "Bill catalogue is unavailable."
	var ids := {}
	for index in range(raw.size()):
		var row: Variant = raw[index]
		if not (row is Dictionary):
			return "Bill catalogue row %d is not an object." % index
		var bill_id := String(row.get("id", ""))
		if bill_id == "" or String(row.get("name", "")) == "" or String(row.get("description", "")) == "":
			return "Bill catalogue row %d has incomplete identity text." % index
		if ids.has(bill_id):
			return "Bill catalogue contains duplicate id '%s'." % bill_id
		ids[bill_id] = true
		if not String(row.get("tier", "")) in ["statutory", "constitutional", "executive_order"]:
			return "Bill '%s' has an unsupported tier." % bill_id
		var ideology: Variant = row.get("ideology")
		if not (ideology is Dictionary):
			return "Bill '%s' has no ideology object." % bill_id
		for axis in ["economic", "social"]:
			var value: Variant = ideology.get(axis)
			if not (typeof(value) in [TYPE_INT, TYPE_FLOAT]) or not is_finite(float(value)) or absf(float(value)) > 1.0:
				return "Bill '%s' has invalid %s ideology." % [bill_id, axis]
		var effects: Variant = row.get("effects")
		if not (effects is Dictionary):
			return "Bill '%s' has no effects object." % bill_id
		for key in ["gdp_growth_delta", "unemployment_delta", "inflation_delta", "budget_revenue_delta", "budget_expenditure_delta", "one_time_debt_pct_delta"]:
			if effects.has(key) and (not (typeof(effects[key]) in [TYPE_INT, TYPE_FLOAT]) or not is_finite(float(effects[key]))):
				return "Bill '%s' has invalid effect '%s'." % [bill_id, key]
		for key in ["faction_loyalty_deltas", "faction_power_deltas"]:
			var deltas: Variant = effects.get(key, {})
			if not (deltas is Dictionary):
				return "Bill '%s' has invalid %s." % [bill_id, key]
			for faction_id in deltas:
				var delta: Variant = deltas[faction_id]
				if String(faction_id) == "" or not (typeof(delta) in [TYPE_INT, TYPE_FLOAT]) or not is_finite(float(delta)):
					return "Bill '%s' has malformed faction delta." % bill_id
		var modifiers: Variant = effects.get("modifiers", [])
		if not (modifiers is Array):
			return "Bill '%s' has invalid modifiers." % bill_id
		for modifier in modifiers:
			if not (modifier is Dictionary) or String(modifier.get("id", "")) == "" or String(modifier.get("target", "")) == "":
				return "Bill '%s' has a malformed modifier." % bill_id
			var magnitude: Variant = modifier.get("magnitude")
			if not (typeof(magnitude) in [TYPE_INT, TYPE_FLOAT]) or not is_finite(float(magnitude)):
				return "Bill '%s' has a non-finite modifier." % bill_id
			if typeof(modifier.get("source", "")) != TYPE_STRING or String(modifier.get("source", "")) == "":
				return "Bill '%s' has an invalid modifier source." % bill_id
			var portfolio: Variant = modifier.get("portfolio", null)
			if portfolio != null and typeof(portfolio) != TYPE_STRING:
				return "Bill '%s' has an invalid modifier portfolio." % bill_id
			if typeof(modifier.get("institutional", true)) != TYPE_BOOL:
				return "Bill '%s' has an invalid institutional flag." % bill_id
			var source_id: Variant = modifier.get("source_id", null)
			if source_id != null and typeof(source_id) != TYPE_STRING:
				return "Bill '%s' has an invalid modifier source id." % bill_id
			for timing in ["onset_delay", "ramp_duration", "decay_duration", "age"]:
				var timing_value: Variant = modifier.get(timing, 0)
				if not (typeof(timing_value) in [TYPE_INT, TYPE_FLOAT]) or float(timing_value) != floorf(float(timing_value)) or int(timing_value) < 0:
					return "Bill '%s' has invalid modifier timing." % bill_id
			var hold: Variant = modifier.get("hold_duration", null)
			if hold != null and (not (typeof(hold) in [TYPE_INT, TYPE_FLOAT]) or float(hold) != floorf(float(hold)) or int(hold) < 0):
				return "Bill '%s' has invalid modifier hold duration." % bill_id
	return ""

static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}