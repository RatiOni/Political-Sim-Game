class_name Minister
extends RefCounted

## Typed mirror of models/cabinet.py: Minister + TRAIT_EFFECTS. The Cabinet
## wrapper dataclass isn't ported as its own file — it's a thin `list[Minister]`
## with a couple of aggregate helpers, so GameState just holds
## `Array[Minister]` directly (see game_state.gd).
##
## Python's field is named `trait`; it's `trait_id` here because `trait` is a
## reserved word in Godot 4.7's GDScript (the trait/composition feature).

const TRAIT_EFFECTS := {
	"technocrat": {"label": "Technocrat", "competence_delta": 0.10, "threat_mult": 0.9},
	"firebrand": {"label": "Firebrand", "appoint_faction_bonus": 0.04, "threat_mult": 1.25},
	"loyalist": {"label": "Loyalist", "competence_delta": -0.05, "threat_mult": 0.5,
		"loyalty_floor": 0.55},
	"grandee": {"label": "Grandee", "threat_mult": 0.8, "stability_bonus": 0.05},
	# "grows" is per-turn schemer drift (competence, ambition) — inert until a
	# future task wires up the turn loop, but CLAUDE.md (Section U0) documents
	# that omitting it here was a real, previously-fixed bug in the Python
	# reference: without it (or loyalty_drift), threat_level() = ambition *
	# (1 - loyalty) caps a minister appointed at loyalty 0.5 at 0.475 threat,
	# so the schemer arc and the minister_restless warning could never fire.
	"schemer": {"label": "Schemer", "threat_mult": 1.0, "loyalty_drift": -0.005,
		"grows": [0.004, 0.008]},
}

## Deterministic round-robin fallback for authored cabinets whose JSON
## predates traits — no RNG draw, so seeded trajectories stay untouched.
const FALLBACK_TRAITS: Array[String] = ["technocrat", "loyalist", "schemer", "grandee", "firebrand"]

var id: String
var name: String
var portfolio: String
var faction_id: String
var competence: float
var loyalty: float
var ambition: float
var trait_id: String = ""   # key into TRAIT_EFFECTS; "" == no notable personality


static func trait_effect(trait_key: String, key: String, default_value: float = 0.0) -> float:
	var effects: Dictionary = TRAIT_EFFECTS.get(trait_key, {})
	return effects.get(key, default_value)


func trait_label() -> String:
	var effects: Dictionary = TRAIT_EFFECTS.get(trait_id, {})
	return String(effects.get("label", ""))


func effective_competence() -> float:
	return clampf(competence + trait_effect(trait_id, "competence_delta", 0.0), 0.0, 1.0)


func is_reliable() -> bool:
	return loyalty > 0.6 and effective_competence() > 0.5


func threat_level() -> float:
	return ambition * (1.0 - loyalty) * trait_effect(trait_id, "threat_mult", 1.0)


func implementation_quality() -> float:
	return effective_competence() * (0.5 + 0.5 * loyalty)
