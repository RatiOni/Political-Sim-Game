class_name DiplomacySim
extends RefCounted


const TRADE_CEILING := 4000.0
const TRADE_APPROACH := 0.04
const NO_PACT_CEILING_SHARE := 0.5
const SAME_CAMP_DRIFT := 0.0015
const OTHER_CAMP_DRIFT := -0.0008
const SANCTION_STABILITY_COST := 0.01
const SANCTION_OUTPUT_LOSS := 0.003

const REGIME_FAMILY := {
	"parliamentary_democracy": "democratic",
	"presidential_democracy": "democratic",
	"authoritarian": "autocratic",
	"hybrid_regime": "hybrid",
}


static func world_country(state: GameState, country_id: String) -> Country:
	for c in state.world:
		if c.id == country_id:
			return c
	return null


static func pair(state: GameState, country_id: String) -> Array:
	var other := world_country(state, country_id)
	if other == null or not state.country.relations.has(country_id) \
			or not other.relations.has(state.country.id):
		return []
	return [state.country.relations[country_id], other.relations[state.country.id]]


static func shift(state: GameState, country_id: String, delta: float, note := "") -> void:
	var p := pair(state, country_id)
	if p.is_empty():
		return
	var mine: Country.BilateralRelation = p[0]
	mine.score = clampf(mine.score + delta, -1.0, 1.0)
	(p[1] as Country.BilateralRelation).score = mine.score
	if note != "":
		mine.history.append(note)
		(p[1] as Country.BilateralRelation).history.append(note)


static func set_trade(state: GameState, country_id: String, volume: float) -> void:
	var p := pair(state, country_id)
	for rel in p:
		(rel as Country.BilateralRelation).trade_volume = clampf(volume, 0.0, TRADE_CEILING)


static func has_treaty(state: GameState, country_id: String, kind: String) -> bool:
	var p := pair(state, country_id)
	return not p.is_empty() and (p[0] as Country.BilateralRelation).treaties.any(
		func(tr): return tr is Dictionary and String(tr.get("type", "")) == kind)


static func monthly(state: GameState) -> void:
	var family: String = REGIME_FAMILY.get(state.country.regime_type, state.country.regime_type)
	for other in state.world:
		var p := pair(state, other.id)
		if p.is_empty():
			continue
		var mine: Country.BilateralRelation = p[0]
		var theirs: Country.BilateralRelation = p[1]
		var same: bool = family == String(REGIME_FAMILY.get(other.regime_type, other.regime_type))
		mine.score = clampf(mine.score + (SAME_CAMP_DRIFT if same else OTHER_CAMP_DRIFT), -1.0, 1.0)
		theirs.score = mine.score
		for rel in [mine, theirs]:
			for tr in rel.treaties:
				if tr is Dictionary:
					tr["turns_active"] = int(tr.get("turns_active", 0)) + 1
		var ceiling := maxf(0.0, mine.score) * TRADE_CEILING
		if mine.sanctioned:
			ceiling = 0.0
			other.stability = maxf(0.03, other.stability - SANCTION_STABILITY_COST)
			if other.economy != null:
				other.economy.gdp *= (1.0 - SANCTION_OUTPUT_LOSS)
		elif not has_treaty(state, other.id, "trade"):
			ceiling *= NO_PACT_CEILING_SHARE
		set_trade(state, other.id, mine.trade_volume + (ceiling - mine.trade_volume) * TRADE_APPROACH)
	var loans := state.country.economy.loans
	for loan in loans.duplicate():
		loan["months_left"] = int(loan.get("months_left", 0)) - 1
		if int(loan["months_left"]) <= 0:
			loans.erase(loan)
