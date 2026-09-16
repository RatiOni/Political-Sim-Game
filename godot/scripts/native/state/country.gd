class_name Country
extends RefCounted

## Typed mirror of models/country.py: Country — plus models/relations.py's
## BilateralRelation (kept here, not a separate file, since it only ever
## exists as one country's view of another). Treaty isn't ported as a typed
## class: no country starts a campaign with one, and the treaty mechanics
## (engine/diplomacy.py) are out of Task 2's scope.

const REGIME_TYPES: Array[String] = [
	"parliamentary_democracy", "presidential_democracy", "hybrid_regime",
	"authoritarian", "totalitarian",
]

## Coarse regime "camps" — shared taxonomy for player↔world and world↔world
## relation drift (a later phase's engine work; kept here as the same design
## reference Python uses).
const REGIME_FAMILIES := {
	"parliamentary_democracy": "democracy",
	"presidential_democracy": "democracy",
	"hybrid_regime": "hybrid",
	"authoritarian": "autocracy",
	"totalitarian": "autocracy",
}


class BilateralRelation extends RefCounted:
	## score: -1.0 (openly hostile) to +1.0 (close allies).
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


var id: String
var name: String
var regime_type: String
var population: int
var economy: Economy

## Full for the player country; simplified (still typed) for world countries.
var factions: Array[Faction] = []

## other_country_id -> BilateralRelation.
var relations: Dictionary = {}

## Regime-stability signal for WORLD countries. The player's own country uses
## the full GameState stability system instead (not yet ported — see
## game_state.gd header note); this field is still seeded from
## meta.stability_value for every country, player included, matching
## content/loader.py: build_country.
var stability: float = 0.7

var bureaucratic_capacity: float = 0.75
var national_traits: Array[String] = []

## e.g. {"type": "revanchist", "rival": "veldoria"}. Empty -> default by regime.
var agenda: Dictionary = {}

var leader_name: String = ""
var paper: String = ""
var capital: String = ""

## The country's current deliberated plan (engine/worldsim.py, a later
## phase). Empty = needs deliberation.
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
	c.bureaucratic_capacity = float(data.get("bureaucratic_capacity", 0.75))

	for t in data.get("national_traits", []):
		c.national_traits.append(String(t))

	c.agenda = data.get("agenda", {}).duplicate(true)
	c.leader_name = String(data.get("default_player", {}).get("name", ""))
	c.paper = String(meta.get("paper", ""))
	c.capital = String(meta.get("capital", ""))
	c.is_player = p_is_player
	return c
