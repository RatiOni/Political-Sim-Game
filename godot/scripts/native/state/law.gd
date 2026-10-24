class_name Law
extends RefCounted

## Native parliamentary proposal and enacted statute. Authored bill content is
## copied into this typed campaign-owned record when it is tabled.

var id: String = ""
var name: String = ""
var description: String = ""
var tier: String = "statutory"
var status: String = "draft"
var portfolio: String = ""
var ideology_economic: float = 0.0
var ideology_social: float = 0.0
var effects: Dictionary = {}
var lobbying_bonus: Dictionary = {}
var votes_for: int = 0
var votes_against: int = 0
var proposed_by: String = ""
var proposed_turn: int = 0
var enacted_turn: int = -1

static func from_catalog(data: Dictionary) -> Law:
	var law := Law.new()
	law.id = String(data.get("id", ""))
	law.name = String(data.get("name", law.id.capitalize()))
	law.description = String(data.get("description", ""))
	law.tier = String(data.get("tier", "statutory"))
	law.status = "draft"
	law.portfolio = "" if data.get("portfolio", null) == null else String(data.get("portfolio", ""))
	var ideology: Variant = data.get("ideology", {})
	if ideology is Dictionary:
		law.ideology_economic = float(ideology.get("economic", 0.0))
		law.ideology_social = float(ideology.get("social", 0.0))
	var effect_data: Variant = data.get("effects", {})
	law.effects = effect_data.duplicate(true) if effect_data is Dictionary else {}
	return law

func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "description": description, "tier": tier,
		"status": status, "portfolio": portfolio,
		"ideology_economic": ideology_economic, "ideology_social": ideology_social,
		"effects": effects.duplicate(true), "lobbying_bonus": lobbying_bonus.duplicate(true),
		"votes_for": votes_for, "votes_against": votes_against,
		"proposed_by": proposed_by, "proposed_turn": proposed_turn,
		"enacted_turn": enacted_turn,
	}

static func from_dict(data: Dictionary) -> Law:
	var law := Law.new()
	law.id = String(data.get("id", ""))
	law.name = String(data.get("name", ""))
	law.description = String(data.get("description", ""))
	law.tier = String(data.get("tier", "statutory"))
	law.status = String(data.get("status", "draft"))
	law.portfolio = "" if data.get("portfolio", null) == null else String(data.get("portfolio", ""))
	law.ideology_economic = float(data.get("ideology_economic", 0.0))
	law.ideology_social = float(data.get("ideology_social", 0.0))
	var effect_data: Variant = data.get("effects", {})
	if not (effect_data is Dictionary):
		return null
	law.effects = effect_data.duplicate(true)
	var lobbying: Variant = data.get("lobbying_bonus", {})
	if not (lobbying is Dictionary):
		return null
	law.lobbying_bonus = lobbying.duplicate(true)
	law.votes_for = _int_field(data, "votes_for", 0)
	law.votes_against = _int_field(data, "votes_against", 0)
	law.proposed_by = String(data.get("proposed_by", ""))
	law.proposed_turn = _int_field(data, "proposed_turn", 0)
	law.enacted_turn = _int_field(data, "enacted_turn", -1)
	return law

static func _int_field(data: Dictionary, key: String, fallback: int) -> int:
	var value: Variant = data.get(key, fallback)
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and value == floorf(value):
		return int(value)
	return fallback