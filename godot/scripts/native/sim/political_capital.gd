class_name PoliticalCapital
extends RefCounted

## Native political-capital economy. Standing commitments consume governing
## capacity each month; approval, coalition loyalty and stability replenish it.
## Laws are campaign-owned native Law records, while treaties and sanctions
## remain on bilateral relations.
const PC_UPKEEP_LAW := 0.8
const PC_UPKEEP_TREATY := 0.6
const PC_UPKEEP_SANCTIONS := 1.0
const PC_REGEN_FLOOR := 3.0


## The PC-per-turn cost of everything the government currently maintains,
## broken down by source — mirrors engine/turn.py: political_upkeep, except
## the total is left for the caller to sum (regenerate() does this) since
## "breakdown by source" is exactly what the brief asks this Dictionary to
## be, and GDScript has no tuple return to mirror Python's (total, breakdown).
static func upkeep(state: GameState) -> Dictionary:
	var laws := state.enacted_laws.size()
	var treaties := 0
	var sanctions := 0
	for rel in state.country.relations.values():
		var relation: Country.BilateralRelation = rel
		treaties += relation.treaties.size()
		if relation.sanctioned:
			sanctions += 1
	return {
		"laws": laws * PC_UPKEEP_LAW,
		"treaties": treaties * PC_UPKEEP_TREATY,
		"sanctions": sanctions * PC_UPKEEP_SANCTIONS,
	}


static func _total_upkeep(state: GameState) -> float:
	var breakdown := upkeep(state)
	var total := 0.0
	for v in breakdown.values():
		total += float(v)
	return total


## PC regen from approval, coalition loyalty, and stability, minus governing
## overhead, floored at PC_REGEN_FLOOR and capped at 100 — mirrors
## engine/turn.py: TurnEngine._regenerate_political_capital exactly (reads
## `state.stability_value`, this port's scalar stand-in for Python's
## `state.stability.value` — see game_state.gd's header note).
static func regenerate(state: GameState) -> void:
	var approval_bonus := (state.player.approval - 0.5) * 10.0

	var coalition_ids := state.coalition_faction_ids()
	var coalition_loyalty := 0.0
	if not coalition_ids.is_empty():
		var loyalty_sum := 0.0
		var member_count := 0
		for f in state.country.factions:
			if coalition_ids.has(f.id):
				loyalty_sum += f.loyalty
				member_count += 1
		if member_count > 0:
			coalition_loyalty = loyalty_sum / member_count
	var coalition_bonus := coalition_loyalty * 5.0

	var stability_bonus := (state.stability_value - 0.5) * 4.0

	var regen := (state.player.pc_regen_base + approval_bonus + coalition_bonus
		+ stability_bonus - _total_upkeep(state))
	regen = maxf(PC_REGEN_FLOOR, regen)
	state.player.political_capital = minf(100.0, state.player.political_capital + regen)
