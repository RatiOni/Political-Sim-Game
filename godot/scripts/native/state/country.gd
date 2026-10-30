class_name Country
extends RefCounted


const REGIME_TYPES: Array[String] = [
	"parliamentary_democracy", "presidential_democracy", "hybrid_regime",
	"authoritarian", "totalitarian",
]

const REGIME_FAMILIES := {
	"parliamentary_democracy": "democracy",
	"presidential_democracy": "democracy",
	"hybrid_regime": "hybrid",
	"authoritarian": "autocracy",
	"totalitarian": "autocracy",
}


class BilateralRelation extends RefCounted:
	var country_a_id: String
	var country_b_id: String
	var score: float = 0.0
	var trade_volume: float = 0.0
	var treaties: Array = []
	var history: Array[String] = []
	var sanctioned: bool = false

	func is_hostile() -> bool:
		return score < -0.3

	func is_friendly() -> bool:
		return score > 0.3

	func status_label() -> String:
		if score > 0.7:
			return "Allied"
		elif score > 0.3:
			return "Friendly"
		elif score > -0.3:
			return "Neutral"
		elif score > -0.7:
			return "Tense"
		else:
			return "Hostile"


	func to_dict() -> Dictionary:
		return {
			"country_a_id": country_a_id,
			"country_b_id": country_b_id,
			"score": score,
			"trade_volume": trade_volume,
			"treaties": treaties.duplicate(true),
			"history": history.duplicate(),
			"sanctioned": sanctioned,
		}


	static func from_dict(data: Dictionary) -> BilateralRelation:
		if not (data is Dictionary):
			push_error("BilateralRelation.from_dict: expected a Dictionary, got %s" % [data])
			return null
		var rel := BilateralRelation.new()
		rel.country_a_id = String(data.get("country_a_id", ""))
		rel.country_b_id = String(data.get("country_b_id", ""))
		rel.score = float(data.get("score", 0.0))
		rel.trade_volume = float(data.get("trade_volume", 0.0))
		var treaties_data: Variant = data.get("treaties", [])
		rel.treaties = treaties_data.duplicate(true) if treaties_data is Array else []
		var history_data: Variant = data.get("history", [])
		if history_data is Array:
			for h in history_data:
				rel.history.append(String(h))
		rel.sanctioned = Country._bool_field(data, "sanctioned", false)
		return rel


var id: String
var name: String
var regime_type: String
var population: int
var economy: Economy

var factions: Array[Faction] = []

var relations: Dictionary = {}

var stability: float = 0.7

var bureaucratic_capacity: float = 0.75
var national_traits: Array[String] = []

var agenda: Dictionary = {}

var leader_name: String = ""
var paper: String = ""
var capital: String = ""

var plan: Dictionary = {}

var civil_war_risk: float = 0.0
var in_civil_war: bool = false
var is_player: bool = false


func get_relation(other_country_id: String) -> BilateralRelation:
	return relations.get(other_country_id)


func has_trait(trait_id: String) -> bool:
	return national_traits.has(trait_id)


static func from_json(data: Dictionary, p_is_player: bool) -> Country:
	var c := Country.new()
	c.id = String(data.get("id", ""))
	c.name = String(data.get("name", ""))
	c.regime_type = String(data.get("regime_type", ""))
	c.population = int(data.get("population", 0))
	c.economy = Economy.from_json(data.get("economy", {}))

	for f in data.get("factions", []):
		c.factions.append(Faction.from_json(f))

	var meta: Dictionary = data.get("meta", {})
	c.stability = float(meta.get("stability_value", 0.7))
	c.civil_war_risk = float(meta.get("civil_war_risk", 0.0))
	c.bureaucratic_capacity = float(data.get("bureaucratic_capacity", 0.75))

	for t in data.get("national_traits", []):
		c.national_traits.append(String(t))

	c.agenda = data.get("agenda", {}).duplicate(true)
	c.leader_name = String(data.get("default_player", {}).get("name", ""))
	c.paper = String(meta.get("paper", ""))
	c.capital = String(meta.get("capital", ""))
	c.is_player = p_is_player
	return c


func to_dict() -> Dictionary:
	var faction_dicts: Array = []
	for f in factions:
		faction_dicts.append(f.to_dict())
	var relation_dicts := {}
	for key in relations:
		relation_dicts[key] = relations[key].to_dict()
	return {
		"id": id,
		"name": name,
		"regime_type": regime_type,
		"population": population,
		"economy": null if economy == null else economy.to_dict(),
		"factions": faction_dicts,
		"relations": relation_dicts,
		"stability": stability,
		"bureaucratic_capacity": bureaucratic_capacity,
		"national_traits": national_traits.duplicate(),
		"agenda": agenda.duplicate(true),
		"leader_name": leader_name,
		"paper": paper,
		"capital": capital,
		"plan": plan.duplicate(true),
		"civil_war_risk": civil_war_risk,
		"in_civil_war": in_civil_war,
		"is_player": is_player,
	}


static func from_dict(data: Dictionary) -> Country:
	if not (data is Dictionary):
		push_error("Country.from_dict: expected a Dictionary, got %s" % [data])
		return null
	var c := Country.new()
	c.id = String(data.get("id", ""))
	c.name = String(data.get("name", ""))
	c.regime_type = String(data.get("regime_type", ""))
	c.population = _int_field(data, "population", 0)
	var economy_data: Variant = data.get("economy", null)
	if economy_data is Dictionary:
		c.economy = Economy.from_dict(economy_data)
		if c.economy == null:
			return null
	var factions_data: Variant = data.get("factions", [])
	if factions_data is Array:
		for f_data in factions_data:
			if f_data is Dictionary:
				var faction := Faction.from_dict(f_data)
				if faction != null:
					c.factions.append(faction)
	var relations_data: Variant = data.get("relations", {})
	if relations_data is Dictionary:
		for key in relations_data:
			if relations_data[key] is Dictionary:
				var rel := BilateralRelation.from_dict(relations_data[key])
				if rel != null:
					c.relations[key] = rel
	c.stability = float(data.get("stability", 0.7))
	c.bureaucratic_capacity = float(data.get("bureaucratic_capacity", 0.75))
	var traits_data: Variant = data.get("national_traits", [])
	if traits_data is Array:
		for t in traits_data:
			c.national_traits.append(String(t))
	var agenda_data: Variant = data.get("agenda", {})
	c.agenda = agenda_data.duplicate(true) if agenda_data is Dictionary else {}
	c.leader_name = String(data.get("leader_name", ""))
	c.paper = String(data.get("paper", ""))
	c.capital = String(data.get("capital", ""))
	var plan_data: Variant = data.get("plan", {})
	c.plan = plan_data.duplicate(true) if plan_data is Dictionary else {}
	c.civil_war_risk = float(data.get("civil_war_risk", 0.0))
	c.in_civil_war = _bool_field(data, "in_civil_war", false)
	c.is_player = _bool_field(data, "is_player", false)
	return c


static func _int_field(data: Dictionary, key: String, fallback: int) -> int:
	var v: Variant = data.get(key, fallback)
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT and v == floorf(v) and absf(v) <= 9007199254740992.0:
		return int(v)
	return fallback


static func _bool_field(data: Dictionary, key: String, fallback: bool) -> bool:
	var v: Variant = data.get(key, fallback)
	if typeof(v) == TYPE_BOOL:
		return v
	return fallback
