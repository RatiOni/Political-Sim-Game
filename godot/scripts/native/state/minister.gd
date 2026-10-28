class_name Minister
extends RefCounted


const TRAIT_EFFECTS := {
	"technocrat": {"label": "Technocrat", "competence_delta": 0.10, "threat_mult": 0.9},
	"firebrand": {"label": "Firebrand", "appoint_faction_bonus": 0.04, "threat_mult": 1.25},
	"loyalist": {"label": "Loyalist", "competence_delta": -0.05, "threat_mult": 0.5,
		"loyalty_floor": 0.55},
	"grandee": {"label": "Grandee", "threat_mult": 0.8, "stability_bonus": 0.05},
	"schemer": {"label": "Schemer", "threat_mult": 1.0, "loyalty_drift": -0.005,
		"grows": [0.004, 0.008]},
}

const FALLBACK_TRAITS: Array[String] = ["technocrat", "loyalist", "schemer", "grandee", "firebrand"]

var id: String
var name: String
var portfolio: String
var faction_id: String
var competence: float
var loyalty: float
var ambition: float
var trait_id: String = ""


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


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"portfolio": portfolio,
		"faction_id": faction_id,
		"competence": competence,
		"loyalty": loyalty,
		"ambition": ambition,
		"trait_id": trait_id,
	}


static func from_dict(data: Dictionary) -> Minister:
	if not (data is Dictionary):
		push_error("Minister.from_dict: expected a Dictionary, got %s" % [data])
		return null
	var m := Minister.new()
	m.id = String(data.get("id", ""))
	m.name = String(data.get("name", ""))
	m.portfolio = String(data.get("portfolio", ""))
	m.faction_id = String(data.get("faction_id", ""))
	m.competence = float(data.get("competence", 0.0))
	m.loyalty = float(data.get("loyalty", 0.0))
	m.ambition = float(data.get("ambition", 0.0))
	m.trait_id = String(data.get("trait_id", ""))
	return m
