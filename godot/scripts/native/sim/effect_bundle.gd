class_name EffectBundle
extends RefCounted

## The one consequence pipeline shared by laws and situations: direct
## economic deltas, faction loyalty and power, lingering modifiers and
## one-off debt. Anything that "happens" to the country goes through here,
## so a law and an event with the same effect land identically.
##
## Factions may be named directly ("social_democrats") or by role
## ("@labour"). Content written against roles works in any country: a role
## resolves to the faction most plainly on that side of politics — the one
## furthest out on the role's defining axis. Two Ardenian parties are labour
## parties; labour's anger lands on the Workers' Front, not the Social
## Democrats, because the Workers' Front is labour's furthest voice.

## role -> [ideology axis, direction]. Roles without an axis resolve only to
## a faction actually classified into them.
const ROLE_AXIS := {
	"@labour": ["economic", -1.0],
	"@business": ["economic", 1.0],
	"@nationalist": ["social", -1.0],
	"@reform": ["social", 1.0],
	"@agrarian": [],
	"@establishment": [],
}


## The concrete faction a key refers to in this country, or null.
static func resolve_faction(state: GameState, key: String) -> Faction:
	if not key.begins_with("@"):
		for f in state.country.factions:
			if f.id == key:
				return f
		return null
	var axis: Array = ROLE_AXIS.get(key, [])
	var best: Faction = null
	var best_score := -INF
	for f in state.country.factions:
		if f.role != key:
			continue
		var score := _axis_score(f, axis) if not axis.is_empty() else float(f.seats)
		if score > best_score:
			best = f
			best_score = score
	if best != null or axis.is_empty():
		return best
	# Nobody is classified into the role: whoever leans hardest that way
	# speaks for it, provided they lean that way at all.
	for f in state.country.factions:
		var score := _axis_score(f, axis)
		if score > 0.0 and score > best_score:
			best = f
			best_score = score
	return best


static func _axis_score(f: Faction, axis: Array) -> float:
	if axis.is_empty() or f.ideology == null:
		return 0.0
	var value: float = f.ideology.economic if axis[0] == "economic" else f.ideology.social
	return value * float(axis[1])


## Applies `effects` once. `source` names it in modifiers ("Telecom
## Privatization Act", "Labour Unrest Spreads"); `source_id` lets a later
## system find and end those modifiers.
static func apply(state: GameState, effects: Dictionary, source: String, source_id: String) -> void:
	var economy := state.country.economy
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
	for key in loyalty:
		var faction := resolve_faction(state, String(key))
		if faction != null:
			faction.loyalty = clampf(faction.loyalty + float(loyalty[key]), -1.0, 1.0)
	var power: Dictionary = effects.get("faction_power_deltas", {})
	for key in power:
		var faction := resolve_faction(state, String(key))
		if faction != null:
			faction.power = clampf(faction.power + float(power[key]), 0.0, 1.0)

	for raw in effects.get("modifiers", []):
		if raw is Dictionary:
			state.modifiers.append(_modifier_from(raw, source, source_id))


static func _modifier_from(raw: Dictionary, source: String, source_id: String) -> Modifier:
	var modifier := Modifier.new()
	modifier.id = String(raw.get("id", ""))
	modifier.source = String(raw.get("source", source))
	modifier.target = String(raw.get("target", ""))
	modifier.magnitude = float(raw.get("magnitude", 0.0))
	modifier.onset_delay = int(raw.get("onset_delay", 0))
	modifier.ramp_duration = int(raw.get("ramp_duration", 1))
	modifier.hold_duration = -1 if raw.get("hold_duration", null) == null else int(raw["hold_duration"])
	modifier.decay_duration = int(raw.get("decay_duration", 0))
	modifier.age = int(raw.get("age", 0))
	modifier.source_id = source_id
	modifier.portfolio = "" if raw.get("portfolio", null) == null else String(raw["portfolio"])
	modifier.institutional = bool(raw.get("institutional", true))
	return modifier
