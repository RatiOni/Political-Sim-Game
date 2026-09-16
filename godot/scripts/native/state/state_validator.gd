class_name StateValidator
extends RefCounted

## Structural sanity checks on a GameState built by GameFactory. An empty
## PackedStringArray means valid; each entry is one human-readable problem.
## This checks the shape of Task 2's own typed state (required fields,
## faction seat sums, relation symmetry, numeric ranges) — it is not a
## parity/oracle comparison against the Python reference.

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

	if state.player != null:
		_validate_player(state, errors)

	if state.stability_value < 0.0 or state.stability_value > 1.0:
		errors.append("stability_value out of range: %s" % state.stability_value)

	if state.ruling_faction_id == "":
		errors.append("ruling_faction_id is empty")
	elif state.country != null:
		var ruling_exists := false
		for f in state.country.factions:
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
			if f.id == player.faction_id:
				found = true
				break
		if not found:
			errors.append("player.faction_id '%s' does not match any faction" % player.faction_id)


static func _validate_relation_symmetry(state: GameState, errors: Array[String]) -> void:
	var all_countries: Array[Country] = [state.country]
	all_countries.append_array(state.world)

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


static func _validate_country(country: Country, errors: Array[String], label: String) -> void:
	if country.id == "":
		errors.append("%s: missing id" % label)
	if country.factions.is_empty():
		errors.append("%s: has no factions" % label)

	var seat_total := 0
	var seen_faction_ids := {}
	for f in country.factions:
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
		if f.ideology.economic < -1.0 or f.ideology.economic > 1.0 \
				or f.ideology.social < -1.0 or f.ideology.social > 1.0:
			errors.append("%s: faction '%s' ideology out of range" % [label, f.id])

		for w in f.wings:
			if w.ideology.economic < -1.0 or w.ideology.economic > 1.0 \
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
