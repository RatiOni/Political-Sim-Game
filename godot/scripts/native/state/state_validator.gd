class_name StateValidator
extends RefCounted


const _DAYS_IN_MONTH := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")

static func validate(state: GameState) -> PackedStringArray:
	var errors: Array[String] = []

	if state == null:
		errors.append("state is null")
		return PackedStringArray(errors)

	if state.player == null:
		errors.append("player is missing")
	if state.country == null:
		errors.append("country is missing")
		return PackedStringArray(errors)

	_validate_country(state.country, errors, "country(%s)" % state.country.id)

	if state.world.is_empty():
		errors.append("world has no countries")
	var seen_world_ids := {}
	for c in state.world:
		if c == null:
			errors.append("world contains a null country")
			continue
		if seen_world_ids.has(c.id):
			errors.append("duplicate world country id '%s'" % c.id)
		seen_world_ids[c.id] = true
		_validate_country(c, errors, "world country(%s)" % c.id)

	_validate_relation_symmetry(state, errors)
	_validate_relation_ranges(state, errors)
	_validate_date(state, errors)
	_validate_ministers(state, errors)
	_validate_cabinet_shortlists(state, errors)
	_validate_situations(state, errors)
	if not is_finite(state.insurgency_pressure) or state.insurgency_pressure < 0.0 or state.insurgency_pressure > 1.0:
		errors.append("insurgency_pressure out of range")
	_validate_households(state, errors)
	_validate_region_growth(state, errors)
	_validate_budgets(state, errors)
	_validate_laws(state, errors)
	_validate_world_plans(state, errors)
	_validate_world_arcs(state, errors)
	_validate_opposition(state, errors)
	_validate_press(state, errors)

	if state.player != null:
		_validate_player(state, errors)

	if state.stability_value < 0.0 or state.stability_value > 1.0:
		errors.append("stability_value out of range: %s" % state.stability_value)

	if state.civil_war_risk < 0.0 or state.civil_war_risk > 1.0:
		errors.append("civil_war_risk out of range: %s" % state.civil_war_risk)

	if state.ruling_faction_id == "":
		errors.append("ruling_faction_id is empty")
	elif state.country != null:
		var ruling_exists := false
		for f in state.country.factions:
			if f == null:
				continue
			if f.id == state.ruling_faction_id:
				ruling_exists = true
				break
		if not ruling_exists:
			errors.append("ruling_faction_id '%s' does not match any player-country faction" %
				state.ruling_faction_id)

	return PackedStringArray(errors)


static func _validate_player(state: GameState, errors: Array[String]) -> void:
	var player := state.player
	if player.faction_id == "":
		errors.append("player.faction_id is empty")
	if player.approval < 0.0 or player.approval > 1.0:
		errors.append("player.approval out of range: %s" % player.approval)
	if player.political_capital < 0.0:
		errors.append("player.political_capital is negative")
	if player.ideology_economic < -1.0 or player.ideology_economic > 1.0 \
			or player.ideology_social < -1.0 or player.ideology_social > 1.0:
		errors.append("player ideology out of range")

	if state.country != null:
		var found := false
		for f in state.country.factions:
			if f == null:
				continue
			if f.id == player.faction_id:
				found = true
				break
		if not found:
			errors.append("player.faction_id '%s' does not match any faction" % player.faction_id)


static func _validate_relation_symmetry(state: GameState, errors: Array[String]) -> void:
	var all_countries: Array[Country] = [state.country]
	for c in state.world:
		if c != null:
			all_countries.append(c)

	for i in range(all_countries.size()):
		for j in range(i + 1, all_countries.size()):
			var a := all_countries[i]
			var b := all_countries[j]
			var rel_ab: Country.BilateralRelation = a.relations.get(b.id)
			var rel_ba: Country.BilateralRelation = b.relations.get(a.id)
			if rel_ab == null or rel_ba == null:
				errors.append("missing bilateral relation between '%s' and '%s'" % [a.id, b.id])
				continue
			if not is_equal_approx(rel_ab.score, rel_ba.score):
				errors.append("relation score asymmetry between '%s' and '%s'" % [a.id, b.id])
			if not is_equal_approx(rel_ab.trade_volume, rel_ba.trade_volume):
				errors.append("relation trade_volume asymmetry between '%s' and '%s'" % [a.id, b.id])


static func _validate_relation_ranges(state: GameState, errors: Array[String]) -> void:
	var all_countries: Array[Country] = [state.country]
	all_countries.append_array(state.world)
	for c in all_countries:
		if c == null:
			continue
		for key in c.relations:
			var rel: Variant = c.relations[key]
			if not (rel is Country.BilateralRelation):
				errors.append("country '%s' has a null or malformed relation for '%s'" % [c.id, key])
				continue
			if rel.score < -1.0 or rel.score > 1.0:
				errors.append("relation '%s'->'%s' score out of range: %s" % [c.id, key, rel.score])
			if rel.trade_volume < 0.0:
				errors.append("relation '%s'->'%s' trade_volume is negative: %s" % [c.id, key, rel.trade_volume])


static func _is_leap_year(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)


static func _days_in_month(year: int, month: int) -> int:
	if month == 2 and _is_leap_year(year):
		return 29
	return _DAYS_IN_MONTH[month - 1]


static func _validate_date(state: GameState, errors: Array[String]) -> void:
	if state.month < 1 or state.month > 12:
		errors.append("month out of range: %s" % state.month)
		if state.day < 1:
			errors.append("day out of range: %s" % state.day)
	elif state.day < 1 or state.day > _days_in_month(state.year, state.month):
		errors.append("day %s out of range for month %s year %s" % [state.day, state.month, state.year])
	if state.day_index < 0:
		errors.append("day_index is negative: %s" % state.day_index)
	if state.turn < 0:
		errors.append("turn is negative: %s" % state.turn)


static func _validate_ministers(state: GameState, errors: Array[String]) -> void:
	var factions := _faction_ids(state)
	for m in state.ministers:
		_minister_errors(m, factions, "minister", errors)


static func _faction_ids(state: GameState) -> Dictionary:
	var ids := {}
	if state.country != null:
		for f in state.country.factions:
			if f != null:
				ids[f.id] = true
	return ids


static func _minister_errors(m: Minister, factions: Dictionary, label: String, errors: Array[String]) -> void:
	if m == null:
		errors.append("%s is null" % label)
		return
	if m.id == "":
		errors.append("%s has an empty id" % label)
	if not factions.has(m.faction_id):
		errors.append("%s '%s' belongs to unknown faction '%s'" % [label, m.id, m.faction_id])
	for field in ["loyalty", "competence", "ambition"]:
		var value: float = m.get(field)
		if not is_finite(value) or value < 0.0 or value > 1.0:
			errors.append("%s '%s' %s out of range: %s" % [label, m.id, field, value])
	if m.trait_id != "" and not Minister.TRAIT_EFFECTS.has(m.trait_id):
		errors.append("%s '%s' has an unknown trait '%s'" % [label, m.id, m.trait_id])


static func _validate_cabinet_shortlists(state: GameState, errors: Array[String]) -> void:
	var factions := _faction_ids(state)
	var taken := {}
	for m in state.ministers:
		if m != null:
			taken[m.id] = true
	for portfolio in state.cabinet_shortlists:
		if not portfolio in CabinetActions.CORE_PORTFOLIOS:
			errors.append("cabinet shortlist has unknown portfolio '%s'" % portfolio)
			continue
		var rows: Variant = state.cabinet_shortlists[portfolio]
		if not (rows is Array) or rows.size() != 3:
			errors.append("cabinet shortlist '%s' must contain exactly three candidates" % portfolio)
			continue
		for candidate in rows:
			if not (candidate is Minister):
				errors.append("cabinet shortlist '%s' contains a malformed candidate" % portfolio)
				continue
			var m: Minister = candidate
			_minister_errors(m, factions, "%s candidate" % portfolio, errors)
			if m.portfolio != portfolio:
				errors.append("%s candidate '%s' is for another portfolio" % [portfolio, m.id])
			if taken.has(m.id):
				errors.append("%s candidate '%s' reuses an id already in use" % [portfolio, m.id])
			taken[m.id] = true


static func _validate_households(state: GameState, errors: Array[String]) -> void:
	for key in state.households:
		var household: Variant = state.households[key]
		if not (key is String) or not (household is HouseholdGroupState):
			errors.append("households contains a malformed entry '%s'" % [key])
			continue
		var h: HouseholdGroupState = household
		if h.id != key or h.id == "" or h.region_id == "" or h.group_id == "":
			errors.append("household '%s' has inconsistent identity" % [key])
		for value in [h.population_share, h.nominal_income_index, h.living_cost_index, h.real_income_index,
			h.employment_security, h.service_access, h.hardship, h.confidence, h.last_real_income_index]:
			if not is_finite(float(value)):
				errors.append("household '%s' has a non-finite value" % [key])
				break
		if h.population_share < 0.0 or h.employment_security < 0.0 or h.employment_security > 1.0 \
				or h.service_access < 0.0 or h.service_access > 1.0 or h.hardship < 0.0 or h.hardship > 1.0 \
				or h.confidence < 0.0 or h.confidence > 1.0:
			errors.append("household '%s' has an out-of-range value" % [key])

static func _validate_laws(state: GameState, errors: Array[String]) -> void:
	var content: Dictionary = ContentRepositoryScript.load_all()
	var catalog: Variant = content.get("catalogs", {}).get("bills", [])
	var known := {}
	if catalog is Array:
		for row in catalog:
			if row is Dictionary:
				known[String(row.get("id", ""))] = row
	var faction_ids := {}
	var total_seats := 0
	for faction in state.country.factions:
		faction_ids[faction.id] = true
		total_seats += faction.seats
	if state.pending_law != null:
		_validate_law(state.pending_law, "pending_law", ["proposed"],
			known, faction_ids, errors)
		if not state.player.in_government:
			errors.append("pending_law exists for an opposition player")
		if state.pending_law.proposed_by != state.player.faction_id:
			errors.append("pending_law sponsor is not the governing player faction")
		_validate_law_lifecycle(state.pending_law, "pending_law", state.turn,
			total_seats, errors)
	var enacted_ids := {}
	for i in range(state.enacted_laws.size()):
		var law: Law = state.enacted_laws[i]
		_validate_law(law, "enacted_laws[%s]" % i, ["enacted"],
			known, faction_ids, errors)
		_validate_law_lifecycle(law, "enacted_laws[%s]" % i, state.turn,
			total_seats, errors)
		if law != null:
			if enacted_ids.has(law.id):
				errors.append("duplicate enacted law id '%s'" % law.id)
			enacted_ids[law.id] = true
	if state.pending_law != null and enacted_ids.has(state.pending_law.id):
		errors.append("pending_law duplicates an enacted law '%s'" % state.pending_law.id)

	var historical_enacted := {}
	for i in range(state.law_history.size()):
		var historical: Law = state.law_history[i]
		_validate_law(historical, "law_history[%s]" % i,
			["enacted", "rejected", "withdrawn", "lapsed"], known, faction_ids, errors)
		_validate_law_lifecycle(historical, "law_history[%s]" % i, state.turn,
			total_seats, errors)
		if historical != null and historical.status == "enacted":
			historical_enacted[historical.id] = true
			if not enacted_ids.has(historical.id):
				errors.append("enacted history has no matching active law '%s'" % historical.id)
	for law_id in enacted_ids:
		if not historical_enacted.has(law_id):
			errors.append("enacted law has no matching history '%s'" % law_id)


static func _validate_law(law: Law, label: String, statuses: Array,
		known: Dictionary, faction_ids: Dictionary, errors: Array[String]) -> void:
	if law == null:
		errors.append("%s is null" % label)
		return
	if law.id == "" or not known.has(law.id):
		errors.append("%s has unknown bill id '%s'" % [label, law.id])
	elif String(known[law.id].get("tier", "")) != law.tier:
		errors.append("%s tier does not match the authored bill definition" % label)
	if not law.status in statuses:
		errors.append("%s has impossible status '%s'" % [label, law.status])
	if not law.tier in ["statutory", "constitutional"]:
		errors.append("%s has unsupported tier '%s'" % [label, law.tier])
	if law.votes_for < 0 or law.votes_against < 0:
		errors.append("%s has negative vote totals" % label)
	var invalid_ideology := (
		not is_finite(law.ideology_economic)
		or not is_finite(law.ideology_social)
		or absf(law.ideology_economic) > 1.0
		or absf(law.ideology_social) > 1.0
	)
	if invalid_ideology:
		errors.append("%s has invalid ideology" % label)
	for faction_id in law.lobbying_bonus:
		var value: Variant = law.lobbying_bonus[faction_id]
		var malformed := (
			not faction_ids.has(faction_id)
			or not (typeof(value) in [TYPE_INT, TYPE_FLOAT])
			or not is_finite(float(value))
			or float(value) < 0.0
			or float(value) > 0.50
		)
		if malformed:
			errors.append("%s has malformed lobbying for '%s'" % [label, faction_id])


static func _validate_law_lifecycle(law: Law, label: String, current_turn: int,
		total_seats: int, errors: Array[String]) -> void:
	if law == null:
		return
	if law.proposed_by == "" or law.proposed_turn < 0 or law.proposed_turn > current_turn:
		errors.append("%s has an invalid proposal lifecycle" % label)
	var threshold := ceili(float(total_seats) * 2.0 / 3.0) if law.tier == "constitutional" else floori(float(total_seats) / 2.0) + 1
	if law.status == "proposed":
		if law.enacted_turn != -1 or law.votes_for != 0 or law.votes_against != 0:
			errors.append("%s has resolved fields before a vote" % label)
	elif law.status in ["enacted", "rejected"]:
		if law.votes_for + law.votes_against != total_seats:
			errors.append("%s vote totals do not match the chamber" % label)
		if law.status == "enacted":
			if law.enacted_turn < law.proposed_turn or law.enacted_turn > current_turn or law.votes_for < threshold:
				errors.append("%s has an impossible enactment outcome" % label)
		elif law.enacted_turn != -1 or law.votes_for >= threshold:
			errors.append("%s has an impossible rejected outcome" % label)
	elif law.status in ["withdrawn", "lapsed"] and (law.enacted_turn != -1 or law.votes_for != 0 or law.votes_against != 0):
		errors.append("%s has impossible withdrawn fields" % label)


static func _same_variant(left: Variant, right: Variant) -> bool:
	if typeof(left) in [TYPE_INT, TYPE_FLOAT] and typeof(right) in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(left), float(right))
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key in left:
			if not right.has(key) or not _same_variant(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for i in range(left.size()):
			if not _same_variant(left[i], right[i]):
				return false
		return true
	return left == right

static func _validate_budgets(state: GameState, errors: Array[String]) -> void:
	var content: Dictionary = ContentRepositoryScript.load_all()
	if content.has("error"):
		errors.append("budget catalogue could not be loaded")
		return
	var envelopes: Variant = content.get("catalogs", {}).get("budget", {}).get("envelopes", null)
	if not (envelopes is Array):
		errors.append("budget catalogue has no envelopes")
		return
	var expected := {}
	var portfolios := {}
	for item in envelopes:
		expected[String(item.get("id", ""))] = true
		portfolios[String(item.get("portfolio", ""))] = true
	if state.active_budget != null:
		_validate_budget(state.active_budget, "active_budget", "active", state.year, expected, portfolios, errors)
	if state.pending_budget != null:
		var pending_year := state.year if BudgetSim.is_emergency(state) 			and state.pending_budget.year == state.year else state.year + 1
		_validate_budget(state.pending_budget, "pending_budget", "pending", pending_year - 1, expected, portfolios, errors)
	for i in range(state.budget_history.size()):
		_validate_budget(state.budget_history[i], "budget_history[%s]" % i, "history", state.year, expected, portfolios, errors)


static func _validate_budget(budget: AnnualBudget, label: String, container: String,
		current_year: int, expected: Dictionary, portfolios: Dictionary,
		errors: Array[String]) -> void:
	if budget == null:
		errors.append("%s is null" % label)
		return
	if budget.year <= 0:
		errors.append("%s has an invalid fiscal year" % label)
	if container == "active":
		if budget.year != current_year or budget.status != "active" \
				or not budget.source in ["inherited", "player", "government_ai", "continuing"]:
			errors.append("%s has an impossible active-budget lifecycle" % label)
	elif container == "pending":
		if budget.year != current_year + 1 or not budget.status in ["proposed", "approved"] \
				or budget.source != "player":
			errors.append("%s has an impossible pending-budget lifecycle" % label)
	elif container == "history":
		var enacted_ok := budget.status == "active" \
			and budget.source in ["player", "government_ai", "continuing"] \
			and budget.year <= current_year
		var rejected_ok := budget.status == "rejected" and budget.source == "player" \
			and budget.year <= current_year + 1
		if not enacted_ok and not rejected_ok:
			errors.append("%s has an impossible historical lifecycle" % label)
	if budget.allocations.size() != expected.size():
		errors.append("%s does not fund every spending envelope" % label)
		return
	for key in budget.allocations:
		if not expected.has(key):
			errors.append("%s has unknown spending envelope '%s'" % [label, key])
			continue
		var value: Variant = budget.allocations[key]
		if not (typeof(value) in [TYPE_INT, TYPE_FLOAT]) or not is_finite(float(value)) \
				or float(value) < 0.0:
			errors.append("%s envelope '%s' is not a finite non-negative number" % [label, key])
	if not is_finite(budget.forecast_revenue):
		errors.append("%s forecast_revenue is non-finite" % label)
	if budget.votes_for < 0 or budget.votes_against < 0:
		errors.append("%s has negative vote totals" % label)
	for faction_id in budget.lobbying_bonus:
		var bonus: Variant = budget.lobbying_bonus[faction_id]
		if not (typeof(bonus) in [TYPE_INT, TYPE_FLOAT]) or not is_finite(float(bonus)) \
				or float(bonus) < 0.0 or float(bonus) > 0.50:
			errors.append("%s lobbying bonus for '%s' is malformed" % [label, faction_id])
	if container != "active" and not budget.supplements.is_empty():
		errors.append("%s cannot carry mid-year supplements" % label)
	for portfolio in budget.supplements:
		var supplement: Variant = budget.supplements[portfolio]
		if not portfolios.has(portfolio) or not (typeof(supplement) in [TYPE_INT, TYPE_FLOAT]) \
				or not is_finite(float(supplement)) or float(supplement) < 0.0:
			errors.append("%s supplement for '%s' is malformed" % [label, portfolio])

static func _validate_country(country: Country, errors: Array[String], label: String) -> void:
	if country.id == "":
		errors.append("%s: missing id" % label)
	if country.factions.is_empty():
		errors.append("%s: has no factions" % label)

	var seat_total := 0
	var seen_faction_ids := {}
	for f in country.factions:
		if f == null:
			errors.append("%s: has a null faction entry" % label)
			continue
		if seen_faction_ids.has(f.id):
			errors.append("%s: duplicate faction id '%s'" % [label, f.id])
		seen_faction_ids[f.id] = true

		if f.seats < 0:
			errors.append("%s: faction '%s' has negative seats" % [label, f.id])
		seat_total += f.seats

		if f.power < 0.0 or f.power > 1.0:
			errors.append("%s: faction '%s' power out of range" % [label, f.id])
		if f.loyalty < -1.0 or f.loyalty > 1.0:
			errors.append("%s: faction '%s' loyalty out of range" % [label, f.id])
		if f.support < 0.0 or f.support > 1.0:
			errors.append("%s: faction '%s' support out of range" % [label, f.id])
		if f.ideology == null:
			errors.append("%s: faction '%s' is missing ideology" % [label, f.id])
		elif f.ideology.economic < -1.0 or f.ideology.economic > 1.0 \
				or f.ideology.social < -1.0 or f.ideology.social > 1.0:
			errors.append("%s: faction '%s' ideology out of range" % [label, f.id])

		for w in f.wings:
			if w == null:
				errors.append("%s: faction '%s' has a null wing entry" % [label, f.id])
				continue
			if w.ideology == null:
				errors.append("%s: faction '%s' wing '%s' is missing ideology" %
					[label, f.id, w.id])
			elif w.ideology.economic < -1.0 or w.ideology.economic > 1.0 \
					or w.ideology.social < -1.0 or w.ideology.social > 1.0:
				errors.append("%s: faction '%s' wing '%s' ideology out of range" %
					[label, f.id, w.id])
			if w.strength < 0.0 or w.strength > 1.0:
				errors.append("%s: faction '%s' wing '%s' strength out of range" %
					[label, f.id, w.id])

	if seat_total <= 0:
		errors.append("%s: faction seats sum to zero or less" % label)

	if country.economy == null:
		errors.append("%s: missing economy" % label)
	else:
		if country.economy.gdp <= 0.0:
			errors.append("%s: economy.gdp is not positive" % label)
		if country.economy.unemployment < 0.0 or country.economy.unemployment > 1.0:
			errors.append("%s: economy.unemployment out of range" % label)
		if country.economy.public_debt_pct < 0.0:
			errors.append("%s: economy.public_debt_pct is negative" % label)

	if country.stability < 0.0 or country.stability > 1.0:
		errors.append("%s: stability out of range" % label)
	if country.bureaucratic_capacity < 0.0 or country.bureaucratic_capacity > 1.0:
		errors.append("%s: bureaucratic_capacity out of range" % label)
	if country.civil_war_risk < 0.0 or country.civil_war_risk > 1.0:
		errors.append("%s: civil_war_risk out of range" % label)


static func _validate_situations(state: GameState, errors: Array[String]) -> void:
	var seen := {}
	for situation in state.pending_situations:
		if situation == null:
			errors.append("pending_situations contains a null entry")
			continue
		if EventsSim.event_by_id(situation.event_id).is_empty():
			errors.append("pending situation names unknown event '%s'" % situation.event_id)
		if seen.has(situation.event_id):
			errors.append("situation '%s' is pending twice" % situation.event_id)
		seen[situation.event_id] = true
		if situation.deadline_turn < situation.arrived_turn:
			errors.append("situation '%s' has a deadline before it arrived" % situation.event_id)
	for row in state.scheduled_events:
		if EventsSim.event_by_id(String(row.get("event_id", ""))).is_empty():
			errors.append("scheduled follow-up names unknown event '%s'" % String(row.get("event_id", "")))
		if not (row.get("due_turn", null) is int or row.get("due_turn", null) is float):
			errors.append("scheduled follow-up '%s' has no due turn" % String(row.get("event_id", "")))



static func _validate_region_growth(state: GameState, errors: Array[String]) -> void:
	for key in state.regions:
		var region: RegionState = state.regions[key] as RegionState
		if region == null:
			continue
		if not is_finite(region.population) or region.population < 0.0:
			errors.append("region '%s' population out of range" % region.id)
		if not is_finite(region.development) or region.development < 0.0 or region.development > 1.0:
			errors.append("region '%s' development out of range" % region.id)


static func _validate_world_plans(state: GameState, errors: Array[String]) -> void:
	var ids := {state.country.id: true}
	for c in state.world:
		if c != null:
			ids[c.id] = true
	for c in state.world:
		if c == null or c.plan.is_empty():
			continue
		var target := String(c.plan.get("target", ""))
		if not (String(c.plan.get("objective", "")) in WorldSim.OBJECTIVES):
			errors.append("world country(%s) plan has an unknown objective" % c.id)
		if target == c.id or (target != "" and not ids.has(target)):
			errors.append("world country(%s) plan has an impossible target '%s'" % [c.id, target])
		var matures: Variant = c.plan.get("matures_turn", null)
		if not (matures is int or matures is float) or float(matures) < 0.0:
			errors.append("world country(%s) plan has no maturity" % c.id)
		if target == "" and String(c.plan.get("objective", "")) != "consolidate":
			errors.append("world country(%s) plan has no target" % c.id)
		if not (c.plan.get("foreshadowed", false) is bool):
			errors.append("world country(%s) plan has a malformed leak flag" % c.id)
		var acted: Variant = c.plan.get("last_acted_turn", -1)
		if not (acted is int or acted is float) or float(acted) > state.turn:
			errors.append("world country(%s) plan acted at an impossible time" % c.id)


static func _validate_world_arcs(state: GameState, errors: Array[String]) -> void:
	var ids := {state.country.id: true}
	for c in state.world:
		if c != null:
			ids[c.id] = true
	for key in state.world_arcs:
		var parts := String(key).split("|")
		if parts.size() != 2 or parts[0] >= parts[1] or not ids.has(parts[0]) or not ids.has(parts[1]):
			errors.append("world arc '%s' does not name two known countries" % key)
		if not (String(state.world_arcs[key]) in WorldSim.ARC_KINDS):
			errors.append("world arc '%s' has an unknown kind" % key)


static func _validate_opposition(state: GameState, errors: Array[String]) -> void:
	var opp := state.opposition
	if opp == null:
		errors.append("opposition state is missing")
		return
	if not is_finite(opp.credibility) or opp.credibility < 0.0 or opp.credibility > 1.0:
		errors.append("opposition credibility out of range")
	if opp.pledges.size() > OppositionActions.MAX_PLEDGES:
		errors.append("more than %d pledges" % OppositionActions.MAX_PLEDGES)
	var known := {}
	for law in LawActions.catalog_laws():
		known[law.id] = true
	var seen := {}
	for p in opp.pledges:
		var bill_id := String(p.get("bill_id", ""))
		if not known.has(bill_id) or seen.has(bill_id):
			errors.append("pledge '%s' is unknown or repeated" % bill_id)
		seen[bill_id] = true
		if not (String(p.get("status", "")) in OppositionState.PLEDGE_STATUSES) or int(p.get("campaigns", 0)) < 0:
			errors.append("pledge '%s' has an impossible record" % bill_id)
	var portfolios := {}
	for m in opp.shadow_cabinet:
		if not CabinetActions.CORE_PORTFOLIOS.has(m.portfolio) or portfolios.has(m.portfolio) \
				or m.faction_id != state.player.faction_id:
			errors.append("shadow minister '%s' holds an impossible post" % m.id)
		portfolios[m.portfolio] = true
	if not (opp.response in OppositionState.RESPONSES):
		errors.append("opposition response '%s' is unknown" % opp.response)
	if opp.government_bill != null:
		if state.player.in_government:
			errors.append("a domestic government bill exists while the player governs")
		if opp.government_bill.status != "proposed" or not known.has(opp.government_bill.id) \
				or opp.government_bill.proposed_by != state.ruling_faction_id:
			errors.append("the government bill record is impossible")
	elif opp.response != "":
		errors.append("an opposition response exists without a government bill")


static func _validate_press(state: GameState, errors: Array[String]) -> void:
	for item in state.monthly_news:
		if not (item is Dictionary) or String(item.get("key", "")) == "" or not (item.get("fields", null) is Dictionary) \
				or not (item.get("text", null) is String):
			errors.append("a news item is malformed")
	var page := state.front_page
	if page.is_empty():
		return
	var lead: Variant = page.get("lead", null)
	if not (page.get("masthead", null) is String) or not (page.get("dateline", null) is String) \
			or not (lead is Dictionary) or not (lead.get("headline", null) is String) \
			or not (lead.get("body", null) is String) or not (page.get("headlines", null) is Array) \
			or not (page.get("briefs", null) is Array) or not (page.get("numbers", null) is Array):
		errors.append("the front page is malformed")
