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


	func to_dict() -> Dictionary:
		return {
			"name": name,
			"title": title,
			"faction_id": faction_id,
			"ideology_economic": ideology_economic,
			"ideology_social": ideology_social,
			"approval": approval,
			"political_capital": political_capital,
			"pc_regen_base": pc_regen_base,
			"in_government": in_government,
			"elections_won": elections_won,
		}


	static func from_dict(data: Dictionary) -> Player:
		if not (data is Dictionary):
			push_error("Player.from_dict: expected a Dictionary, got %s" % [data])
			return null
		var p := Player.new()
		p.name = String(data.get("name", ""))
		p.title = String(data.get("title", ""))
		p.faction_id = String(data.get("faction_id", ""))
		p.ideology_economic = float(data.get("ideology_economic", 0.0))
		p.ideology_social = float(data.get("ideology_social", 0.0))
		p.approval = float(data.get("approval", 0.5))
		p.political_capital = float(data.get("political_capital", 50.0))
		p.pc_regen_base = float(data.get("pc_regen_base", 10.0))
		p.in_government = GameState._bool_field(data, "in_government", true)
		p.elections_won = GameState._int_field(data, "elections_won", 0)
		return p


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

## Native parliamentary legislation: one tabled bill, enacted laws, and the
## complete outcome ledger (enacted, defeated, or withdrawn).
var pending_law: Law = null
var enacted_laws: Array[Law] = []
var law_history: Array[Law] = []

## The government's ministers — Python's `Cabinet` is just `list[Minister]`
## plus aggregate helpers, so no wrapper type is ported (see header note).
var ministers: Array[Minister] = []
## Outstanding appointment choices, keyed by core portfolio. Candidates are typed Ministers.
var cabinet_shortlists: Dictionary = {}

## Every active time-shaped policy effect currently in flight (see
## modifier.gd). Task 3 ages these each simulated day/month.
var modifiers: Array[Modifier] = []

var ruling_faction_id: String = ""

## 0..1 pressure gauge + latch for the player's country (engine/crisis.py,
## a later phase). An ongoing pressure, not a game-over.
var civil_war_risk: float = 0.0
var civil_war: bool = false

## Plain scalar stand-in for Python's GovernmentStability aggregate — see
## header note. Default matches models/stability.py: GovernmentStability.value
## (0.55), since Ardenia's own content/countries/ardenia.json has no
## meta.stability_value key and so hits this exact fallback in a real
## campaign — must match the Python reference, not drift from it.
var stability_value: float = 0.55

## Completed native monthly report. Older saves intentionally receive an empty report.
var monthly_digest: Array[String] = []

## Generation metadata (difficulty, seed, background, opening role, national
## traits) as a plain Dictionary, matching Python's campaign_meta.
var campaign_meta: Dictionary = {}

## Situations: those waiting on the government, follow-ups already set in
## motion ({event_id, due_turn, target_country_id}), the turn each event last
## arrived, and every decision taken ({event_id, option_id, turn, lapsed}).
var pending_situations: Array[Situation] = []
var scheduled_events: Array[Dictionary] = []
var event_fire_history: Dictionary = {}   # String event_id -> int turn
var event_history: Array[Dictionary] = []

## The campaign RNG. Never null: a fresh state opens on seed 0 and NativeGame
## reseeds it from the campaign config in unit B.
var rng: SimRng = SimRng.from_seed(0)


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


func to_dict() -> Dictionary:
	var world_dicts: Array = []
	for c in world:
		world_dicts.append(c.to_dict())
	var region_dicts := {}
	for key in regions:
		region_dicts[key] = regions[key].to_dict()
	var program_dicts: Array = []
	for p in regional_programs:
		program_dicts.append(p.to_dict())
	var ministry_dicts := {}
	for key in ministries:
		ministry_dicts[key] = ministries[key].to_dict()
	var household_dicts := {}
	for key in households:
		household_dicts[key] = households[key].to_dict()
	var history_dicts: Array = []
	for b in budget_history:
		history_dicts.append(b.to_dict())
	var enacted_law_dicts: Array = []
	for law in enacted_laws:
		enacted_law_dicts.append(law.to_dict())
	var law_history_dicts: Array = []
	for law in law_history:
		law_history_dicts.append(law.to_dict())
	var minister_dicts: Array = []
	for m in ministers:
		minister_dicts.append(m.to_dict())
	var modifier_dicts: Array = []
	for m in modifiers:
		modifier_dicts.append(m.to_dict())
	# The RNG travels through SimRng's own to_dict, except its two int64s are
	# stored as decimal strings: Godot parses every JSON number as float64,
	# which cannot hold 64-bit PCG state exactly past 2^53 — plain ints would
	# silently fork the stream on load (verified empirically).
	var rng_snapshot := {"state": "0", "inc": "1"}
	if rng != null:
		var raw_rng := rng.to_dict()
		rng_snapshot = {"state": str(raw_rng["state"]), "inc": str(raw_rng["inc"])}
	return {
		"year": year,
		"month": month,
		"day": day,
		"day_index": day_index,
		"turn": turn,
		"player": null if player == null else player.to_dict(),
		"country": null if country == null else country.to_dict(),
		"world": world_dicts,
		"regions": region_dicts,
		"regional_programs": program_dicts,
		"ministries": ministry_dicts,
		"households": household_dicts,
		"active_budget": null if active_budget == null else active_budget.to_dict(),
		"pending_budget": null if pending_budget == null else pending_budget.to_dict(),
		"budget_history": history_dicts,
		"pending_law": null if pending_law == null else pending_law.to_dict(),
		"enacted_laws": enacted_law_dicts,
		"law_history": law_history_dicts,
		"ministers": minister_dicts,
		"cabinet_shortlists": _cabinet_shortlists_to_dict(),
		"modifiers": modifier_dicts,
		"ruling_faction_id": ruling_faction_id,
		"civil_war_risk": civil_war_risk,
		"civil_war": civil_war,
		"stability_value": stability_value,
		"monthly_digest": monthly_digest.duplicate(),
		"campaign_meta": campaign_meta.duplicate(true),
		"pending_situations": _situations_to_array(),
		"scheduled_events": scheduled_events.duplicate(true),
		"event_fire_history": event_fire_history.duplicate(true),
		"event_history": event_history.duplicate(true),
		"rng": rng_snapshot,
	}


## Tolerant reader (mirroring engine/persistence.py): an ABSENT key falls back
## to its field's declared default and unknown keys are ignored, so older
## saves load under a newer schema. Strict where tolerance would corrupt:
## the player/country/rng subtrees are REQUIRED (absent, null, or
## unparseable rejects the save), and a PRESENT-but-wrongly-typed container
## (e.g. "world" holding a Dictionary) rejects it too instead of silently
## loading empty. Scalar coercion and the schemaless campaign_meta stay
## lenient, as before. Returns null + push_error on any rejection.
static func from_dict(data: Dictionary) -> GameState:
	if not (data is Dictionary):
		push_error("GameState.from_dict: expected a Dictionary, got %s" % [data])
		return null
	var state := GameState.new()
	state.year = _int_field(data, "year", 0)
	state.month = _int_field(data, "month", 0)
	state.day = _int_field(data, "day", 1)
	state.day_index = _int_field(data, "day_index", 0)
	state.turn = _int_field(data, "turn", 0)
	var player_data: Variant = data.get("player", null)
	if not (player_data is Dictionary):
		push_error("GameState.from_dict: missing or malformed required 'player', got %s" % [player_data])
		return null
	state.player = Player.from_dict(player_data)
	if state.player == null:
		return null
	var country_data: Variant = data.get("country", null)
	if not (country_data is Dictionary):
		push_error("GameState.from_dict: missing or malformed required 'country', got %s" % [country_data])
		return null
	state.country = Country.from_dict(country_data)
	if state.country == null:
		return null
	var world_data: Variant = data.get("world", [])
	if data.has("world") and not (world_data is Array):
		push_error("GameState.from_dict: malformed 'world', expected an Array, got %s" % [world_data])
		return null
	if world_data is Array:
		for c_data in world_data:
			if c_data is Dictionary:
				var c := Country.from_dict(c_data)
				if c != null:
					state.world.append(c)
	var regions_data: Variant = data.get("regions", {})
	if data.has("regions") and not (regions_data is Dictionary):
		push_error("GameState.from_dict: malformed 'regions', expected a Dictionary, got %s" % [regions_data])
		return null
	if regions_data is Dictionary:
		for key in regions_data:
			if regions_data[key] is Dictionary:
				var region := RegionState.from_dict(regions_data[key])
				if region != null:
					state.regions[key] = region
	var programs_data: Variant = data.get("regional_programs", [])
	if data.has("regional_programs") and not (programs_data is Array):
		push_error("GameState.from_dict: malformed 'regional_programs', expected an Array, got %s" % [programs_data])
		return null
	if programs_data is Array:
		for p_data in programs_data:
			if p_data is Dictionary:
				var program := RegionState.RegionalProgram.from_dict(p_data)
				if program != null:
					state.regional_programs.append(program)
	var ministries_data: Variant = data.get("ministries", {})
	if data.has("ministries") and not (ministries_data is Dictionary):
		push_error("GameState.from_dict: malformed 'ministries', expected a Dictionary, got %s" % [ministries_data])
		return null
	if ministries_data is Dictionary:
		for key in ministries_data:
			if ministries_data[key] is Dictionary:
				var ministry := MinistryState.from_dict(ministries_data[key])
				if ministry != null:
					state.ministries[key] = ministry
	var households_data: Variant = data.get("households", {})
	if data.has("households") and not (households_data is Dictionary):
		push_error("GameState.from_dict: malformed 'households', expected a Dictionary, got %s" % [households_data])
		return null
	if households_data is Dictionary:
		for key in households_data:
			var household_data: Variant = households_data[key]
			if not (key is String) or not (household_data is Dictionary):
				push_error("GameState.from_dict: malformed household entry '%s'" % [key])
				return null
			var household := HouseholdGroupState.from_dict(household_data)
			if household == null or not _valid_household(household):
				push_error("GameState.from_dict: malformed household record '%s'" % [key])
				return null
			state.households[key] = household
	var active_data: Variant = data.get("active_budget", null)
	if active_data != null and not (active_data is Dictionary):
		push_error("GameState.from_dict: malformed 'active_budget', expected a Dictionary or null, got %s" % [active_data])
		return null
	if active_data is Dictionary:
		state.active_budget = AnnualBudget.from_dict(active_data)
		if state.active_budget == null:
			return null
	var pending_data: Variant = data.get("pending_budget", null)
	if pending_data != null and not (pending_data is Dictionary):
		push_error("GameState.from_dict: malformed 'pending_budget', expected a Dictionary or null, got %s" % [pending_data])
		return null
	if pending_data is Dictionary:
		state.pending_budget = AnnualBudget.from_dict(pending_data)
		if state.pending_budget == null:
			return null
	var history_data: Variant = data.get("budget_history", [])
	if data.has("budget_history") and not (history_data is Array):
		push_error("GameState.from_dict: malformed 'budget_history', expected an Array, got %s" % [history_data])
		return null
	if history_data is Array:
		for b_data in history_data:
			if not (b_data is Dictionary):
				push_error("GameState.from_dict: malformed 'budget_history' entry, expected Dictionary, got %s" % [b_data])
				return null
			var budget := AnnualBudget.from_dict(b_data)
			if budget == null:
				return null
			state.budget_history.append(budget)
	var pending_law_data: Variant = data.get("pending_law", null)
	if pending_law_data != null and not (pending_law_data is Dictionary):
		push_error("GameState.from_dict: malformed 'pending_law'")
		return null
	if pending_law_data is Dictionary:
		state.pending_law = Law.from_dict(pending_law_data)
		if state.pending_law == null:
			return null
	for field in ["enacted_laws", "law_history"]:
		var rows: Variant = data.get(field, [])
		if data.has(field) and not (rows is Array):
			push_error("GameState.from_dict: malformed '%s'" % field)
			return null
		for row in rows:
			if not (row is Dictionary):
				push_error("GameState.from_dict: malformed '%s' entry" % field)
				return null
			var law := Law.from_dict(row)
			if law == null:
				return null
			if field == "enacted_laws":
				state.enacted_laws.append(law)
			else:
				state.law_history.append(law)
	var ministers_data: Variant = data.get("ministers", [])
	if data.has("ministers") and not (ministers_data is Array):
		push_error("GameState.from_dict: malformed 'ministers', expected an Array, got %s" % [ministers_data])
		return null
	if ministers_data is Array:
		for m_data in ministers_data:
			if m_data is Dictionary:
				var minister := Minister.from_dict(m_data)
				if minister != null:
					state.ministers.append(minister)
	var shortlists_data: Variant = data.get("cabinet_shortlists", {})
	if data.has("cabinet_shortlists") and not (shortlists_data is Dictionary):
		push_error("GameState.from_dict: malformed cabinet_shortlists")
		return null
	if shortlists_data is Dictionary:
		for portfolio in shortlists_data:
			var list_data: Variant = shortlists_data[portfolio]
			if not (portfolio is String) or not (list_data is Array):
				push_error("GameState.from_dict: malformed cabinet shortlist")
				return null
			var shortlist: Array[Minister] = []
			for candidate_data in list_data:
				if not (candidate_data is Dictionary):
					push_error("GameState.from_dict: malformed cabinet candidate")
					return null
				var candidate := Minister.from_dict(candidate_data)
				if candidate == null:
					return null
				shortlist.append(candidate)
			state.cabinet_shortlists[portfolio] = shortlist
	var modifiers_data: Variant = data.get("modifiers", [])
	if data.has("modifiers") and not (modifiers_data is Array):
		push_error("GameState.from_dict: malformed 'modifiers', expected an Array, got %s" % [modifiers_data])
		return null
	if modifiers_data is Array:
		for m_data in modifiers_data:
			if m_data is Dictionary:
				var modifier := Modifier.from_dict(m_data)
				if modifier != null:
					state.modifiers.append(modifier)
	state.ruling_faction_id = String(data.get("ruling_faction_id", ""))
	state.civil_war_risk = float(data.get("civil_war_risk", 0.0))
	state.civil_war = _bool_field(data, "civil_war", false)
	state.stability_value = float(data.get("stability_value", 0.55))
	var digest_data: Variant = data.get("monthly_digest", [])
	if data.has("monthly_digest") and not (digest_data is Array):
		push_error("GameState.from_dict: malformed 'monthly_digest', expected an Array, got %s" % [digest_data])
		return null
	if digest_data is Array:
		for line in digest_data:
			if not (line is String):
				push_error("GameState.from_dict: malformed 'monthly_digest' entry, expected String, got %s" % [line])
				return null
			state.monthly_digest.append(line)
	var meta_data: Variant = data.get("campaign_meta", {})
	state.campaign_meta = meta_data.duplicate(true) if meta_data is Dictionary else {}
	var situations_data: Variant = data.get("pending_situations", [])
	if not (situations_data is Array):
		push_error("GameState.from_dict: malformed pending_situations")
		return null
	for row in situations_data:
		var situation := Situation.from_dict(row)
		if situation == null:
			return null
		state.pending_situations.append(situation)
	for key in ["scheduled_events", "event_history"]:
		var rows: Variant = data.get(key, [])
		if not (rows is Array):
			push_error("GameState.from_dict: malformed %s" % key)
			return null
		for row in rows:
			if not (row is Dictionary):
				push_error("GameState.from_dict: malformed %s entry" % key)
				return null
			var target: Array[Dictionary] = state.scheduled_events if key == "scheduled_events" else state.event_history
			target.append((row as Dictionary).duplicate(true))
	var fired: Variant = data.get("event_fire_history", {})
	if not (fired is Dictionary):
		push_error("GameState.from_dict: malformed event_fire_history")
		return null
	for key in fired:
		state.event_fire_history[String(key)] = int(fired[key])
	if not data.has("rng"):
		push_error("GameState.from_dict: missing required 'rng' (every writer since format v1 includes it)")
		return null
	var restored := _rng_from_dict(data.get("rng"))
	if restored == null:
		return null
	state.rng = restored
	return state


static func _valid_household(household: HouseholdGroupState) -> bool:
	if household.id == "" or household.group_id == "" or household.region_id == "":
		return false
	for value in [household.population_share, household.nominal_income_index, household.living_cost_index,
		household.real_income_index, household.employment_security, household.service_access,
		household.hardship, household.confidence, household.last_real_income_index]:
		if not is_finite(float(value)):
			return false
	return true

## Accepts the string form to_dict writes, plus raw ints and whole-number
## floats (hand-written or foreign saves) — the int/float tolerance the JSON
## boundary requires. Null + push_error on anything else.
static func _rng_from_dict(v: Variant) -> SimRng:
	if not (v is Dictionary):
		push_error("GameState.from_dict: malformed 'rng', expected a Dictionary, got %s" % [v])
		return null
	var coerced := {}
	for key in ["state", "inc"]:
		var raw: Variant = v.get(key)
		if typeof(raw) == TYPE_INT:
			coerced[key] = raw
		elif typeof(raw) == TYPE_STRING and raw.is_valid_int():
			coerced[key] = int(raw)
		elif typeof(raw) == TYPE_FLOAT and raw == floorf(raw) and absf(raw) <= 9007199254740992.0:
			coerced[key] = int(raw)
		else:
			push_error("GameState.from_dict: malformed rng field '%s' in %s" % [key, v])
			return null
	return SimRng.from_dict(coerced)


## JSON boundary: Godot parses every JSON number as float, so a whole-number
## float must read back as an int wherever an int field is expected.
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

func _cabinet_shortlists_to_dict() -> Dictionary:
	var out := {}
	for portfolio in cabinet_shortlists:
		var rows: Variant = cabinet_shortlists[portfolio]
		var serial: Array = []
		if rows is Array:
			for candidate in rows:
				if candidate is Minister:
					serial.append((candidate as Minister).to_dict())
		out[portfolio] = serial
	return out


func _situations_to_array() -> Array:
	var out: Array = []
	for situation in pending_situations:
		out.append(situation.to_dict())
	return out
