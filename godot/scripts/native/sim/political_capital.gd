class_name PoliticalCapital
extends RefCounted

const BASE_REGEN := 5.0
const MIN_REGEN := 1.0
const SOFT_LIMIT := 80.0
const ABSOLUTE_LIMIT := 140.0
const ABOVE_SOFT_REGEN_FACTOR := 0.25
const PC_UPKEEP_LAW := 0.9
const PC_UPKEEP_TREATY := 0.7
const PC_UPKEEP_SANCTIONS := 1.2

static func upkeep(state: GameState) -> Dictionary:
	var laws := state.enacted_laws.size()
	var treaties := 0
	var sanctions := 0
	for rel in state.country.relations.values():
		var relation: Country.BilateralRelation = rel
		treaties += relation.treaties.size()
		if relation.sanctioned:
			sanctions += 1
	return {"laws": laws * PC_UPKEEP_LAW, "treaties": treaties * PC_UPKEEP_TREATY,
		"sanctions": sanctions * PC_UPKEEP_SANCTIONS}

static func _total_upkeep(state: GameState) -> float:
	var total := 0.0
	for value in upkeep(state).values():
		total += float(value)
	return total

static func regeneration_preview(state: GameState) -> Dictionary:
	var coalition_loyalty := 0.0
	var members := 0
	for faction in state.country.factions:
		if faction.in_coalition:
			coalition_loyalty += faction.loyalty
			members += 1
	if members > 0:
		coalition_loyalty /= float(members)
	var mandate := (state.player.approval - 0.5) * 6.0
	var coalition := coalition_loyalty * 3.0
	var stability := (state.stability_value - 0.5) * 4.0
	var commitments := _total_upkeep(state)
	var raw := BASE_REGEN + mandate + coalition + stability - commitments
	var normal_regen := maxf(MIN_REGEN, raw)
	var factor := ABOVE_SOFT_REGEN_FACTOR if state.player.political_capital >= SOFT_LIMIT else 1.0
	return {"base": BASE_REGEN, "mandate": mandate, "coalition": coalition,
		"stability": stability, "commitments": commitments, "raw": raw,
		"soft_limit_factor": factor, "regen": normal_regen * factor,
		"soft_limited": factor < 1.0}

static func regenerate(state: GameState) -> void:
	var preview := regeneration_preview(state)
	state.player.political_capital = minf(ABSOLUTE_LIMIT,
		state.player.political_capital + float(preview["regen"]))