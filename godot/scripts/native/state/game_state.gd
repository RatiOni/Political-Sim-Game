class_name GameState
extends RefCounted

## Typed mirror of game_state.py: GameState + Player, scoped to what Phase 1
## Task 2 (campaign construction) actually needs. game_state.py's full field
## set also covers systems this rebuild's later phases own — the legislative
## engine (Legislature/Law/Cabinet-as-a-wrapper), elections, shadow cabinet,
## opposition/domestic-AI politics, the annual budget vote cycle, reform
## design, the household/ministry turn-by-turn recalculation, events, and the
## GovernmentStability aggregate. None of those are read by
## `content/loader.py: build_state_for` at construction time in a way Task 2
## needs to reproduce (per the brief's own "Read first" list), so they are
## deliberately not modelled yet:
##   - `legislature` / `cabinet` (as wrapper types) — cabinet ministers are
##     just `ministers: Array[Minister]` here (Cabinet is a thin list wrapper
##     in Python with no fields of its own).
##   - `stability` (GovernmentStability) — represented as a plain scalar
##     `stability_value` for now, matching what `loader.build_state_for` seeds
##     it from (`meta.stability_value`).
##   - `regions` / `households` / `ministries` / `active_budget` — the typed
##     container classes exist (region.gd, household_group.gd,
##     ministry_state.gd, annual_budget.gd) so GameState can hold them, but
##     GameFactory does not populate them: the seeding logic lives in
##     engine/regions.py, engine/households.py, engine/ministries.py and
##     engine/budget.py, none of which are in this task's scope.
## A future task that ports one of those systems extends this class rather
## than replacing it.

class Player extends RefCounted:
	## The head of government — the player's own political identity.
	var name: String
	var title: String            # "Prime Minister", "President", etc.
	var faction_id: String       # the faction that brought them to power
	var ideology_economic: float = 0.0
	var ideology_social: float = 0.0
	var approval: float = 0.5
	var political_capital: float = 50.0
	var pc_regen_base: float = 10.0
	## False = in opposition (gates government-only actions).
	var in_government: bool = true
	var elections_won: int = 0


var year: int
var month: int   # 1-12
var day: int = 1
var day_index: int = 0
var turn: int = 0

var player: Player
var country: Country                  # the player's country, full detail
var world: Array[Country] = []        # other nations

## Live subnational conditions, keyed by content/lore/geography.py's stable
## region ids. Not yet populated by GameFactory — see header note.
var regions: Dictionary = {}                 # String region_id -> RegionState
var regional_programs: Array = []            # RegionState.RegionalProgram

## Departmental operating condition, keyed by cabinet portfolio. Not yet
## populated by GameFactory — see header note.
var ministries: Dictionary = {}              # String portfolio -> MinistryState
## Keys are "region_id:group_id". Not yet populated by GameFactory.
var households: Dictionary = {}              # String -> HouseholdGroupState

## Annual structural appropriations. Not yet populated by GameFactory.
var active_budget: AnnualBudget = null
var pending_budget: AnnualBudget = null
var budget_history: Array[AnnualBudget] = []

## The government's ministers — Python's `Cabinet` is just `list[Minister]`
## plus aggregate helpers, so no wrapper type is ported (see header note).
var ministers: Array[Minister] = []

## Every active time-shaped policy effect currently in flight (see
## modifier.gd). Task 3 ages these each simulated day/month.
var modifiers: Array[Modifier] = []

var ruling_faction_id: String = ""

## 0..1 pressure gauge + latch for the player's country (engine/crisis.py,
## a later phase). An ongoing pressure, not a game-over.
var civil_war_risk: float = 0.0
var civil_war: bool = false

## Plain scalar stand-in for Python's GovernmentStability aggregate — see
## header note.
var stability_value: float = 0.7

## Generation metadata (difficulty, seed, background, opening role, national
## traits) as a plain Dictionary, matching Python's campaign_meta.
var campaign_meta: Dictionary = {}


func coalition_faction_ids() -> Array[String]:
	var out: Array[String] = []
	for f in country.factions:
		if f.in_coalition:
			out.append(f.id)
	return out


func world_country(country_id: String) -> Country:
	for c in world:
		if c.id == country_id:
			return c
	return null
