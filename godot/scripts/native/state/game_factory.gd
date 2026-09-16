class_name GameFactory
extends RefCounted

## Builds a fresh campaign GameState from ContentRepository content, mirroring
## content/loader.py: build_state_for plus the opening-role slice of
## engine/campaign.py: generate_campaign (Priority 4/5 nudges from
## traits/difficulty/background numeric deltas are NOT applied — see the
## "Deviations" note below; opening-role government assembly IS ported,
## because the brief's test explicitly checks it for all three roles).
##
## Wing generation (carried-forward finding from Task 1's review): Task 1's
## exported country JSON only carries authored `wings` for Ardenia's twelve
## canonical blocs, because `content/loader.py` only ever writes those wings
## for Ardenia — every other country's factions get GENERIC wings from
## `engine/parties.py: generate_default_wings`, which is simulation logic,
## not static content, and so was correctly left out of the export. This
## factory ports that function (see faction.gd) and calls it for every
## faction of every non-Ardenia country. This deviates from
## `loader.build_state_for`, which only ever generates default wings for the
## PLAYER country's own factions (never the world countries') — but Ardenia
## is this build's only playable country, so "every non-Ardenia faction" and
## "every world-country faction" are the same set here, and the brief asks
## for the former explicitly.
##
## Deviations from the Python reference (documented, not oversights):
##   - No difficulty/background/national-trait numeric nudges
##     (engine/campaign.py: _apply_traits/_apply_difficulty/_apply_character).
##     Those are one-time cosmetic adjustments to the opening position, not
##     needed for the brief's checklist (player/party/government per opening
##     role, world countries + relations, StateValidator). config's
##     background_id/difficulty_id are still recorded in campaign_meta so a
##     later task can add the nudges without an interface change.
##   - Opening-role government assembly (_configure_government /
##     _build_coalition_around, ported from engine/elections.py) does NOT
##     rebuild the cabinet the way `elections.configure_government` does —
##     that requires `cabinet_ops.generate_candidate` (name generation etc.),
##     which is out of scope. The authored cabinet from content stays as-is.
##   - regions/households/ministries/active_budget are left at their empty
##     defaults — see game_state.gd's header note.

const PLAYABLE_COUNTRY_IDS: Array[String] = ["ardenia"]

const DEFAULT_YEAR := 1993
const DEFAULT_MONTH := 3


## `content` is a ContentRepository.load_all() result. `config` carries:
##   country_id (String, must be in PLAYABLE_COUNTRY_IDS)
##   background_id (String, default "none")
##   difficulty_id (String, default "normal")
##   opening_role (String: "contextual" | "government" | "opposition")
##   seed (int, explicit — required by the brief, no hash-derived fallback)
## Returns null (and push_error()s) on any rejection.
static func new_campaign(content: Dictionary, config: Dictionary) -> GameState:
	var country_id: String = String(config.get("country_id", ""))
	if not PLAYABLE_COUNTRY_IDS.has(country_id):
		push_error("GameFactory: country '%s' is not playable (Ardenia-only build)" % country_id)
		return null

	var countries_data: Dictionary = content.get("countries", {})
	if not countries_data.has(country_id):
		push_error("GameFactory: no content data for country '%s'" % country_id)
		return null

	var player_data: Dictionary = countries_data[country_id]
	var player_country := Country.from_json(player_data, true)
	# Ardenia's factions keep the bloc wings that already arrived from
	# content (kind == "bloc") — never regenerate those.

	var other_ids: Array[String] = []
	for cid in countries_data.keys():
		if cid != country_id:
			other_ids.append(String(cid))
	other_ids.sort()

	# Neighbours listed in the player's file come first (matching
	# content/loader.py's ordering), any other defined country follows.
	var neighbour_ids: Array = player_data.get("neighbours", [])
	var ordered: Array[String] = []
	for nid in neighbour_ids:
		if other_ids.has(nid):
			ordered.append(String(nid))
	for oid in other_ids:
		if not ordered.has(oid):
			ordered.append(oid)

	var world: Array[Country] = []
	var data_by_id: Dictionary = {country_id: player_data}
	for cid in ordered:
		var data: Dictionary = countries_data[cid]
		data_by_id[cid] = data
		var c := Country.from_json(data, false)
		for f in c.factions:
			if f.wings.is_empty():
				f.wings = Faction.generate_default_wings(f)
		world.append(c)

	var countries_by_id: Dictionary = {country_id: player_country}
	for c in world:
		countries_by_id[c.id] = c
	_wire_all_relations(countries_by_id, data_by_id)

	var state := GameState.new()
	state.year = DEFAULT_YEAR
	state.month = DEFAULT_MONTH
	state.country = player_country
	state.world = world
	state.player = _build_player(player_data)
	state.ministers = _build_cabinet(player_data)
	state.ruling_faction_id = state.player.faction_id

	var meta_stability = player_data.get("meta", {}).get("stability_value")
	if meta_stability != null:
		state.stability_value = float(meta_stability)

	var opening_role_cfg: String = String(config.get("opening_role", "contextual"))
	_apply_opening_position(state, opening_role_cfg)

	state.campaign_meta = {
		"country_id": country_id,
		"difficulty": String(config.get("difficulty_id", "normal")),
		"background": String(config.get("background_id", "none")),
		"opening_role": ("government" if state.player.in_government else "opposition"),
		"seed": int(config.get("seed", 0)),
		"national_traits": player_country.national_traits.duplicate(),
	}

	return state


static func _build_player(player_data: Dictionary) -> GameState.Player:
	var dp: Dictionary = player_data.get("default_player", {})
	var p := GameState.Player.new()
	p.name = String(dp.get("name", ""))
	p.title = String(dp.get("title", ""))
	p.faction_id = String(dp.get("faction_id", ""))
	p.ideology_economic = float(dp.get("ideology_economic", 0.0))
	p.ideology_social = float(dp.get("ideology_social", 0.0))
	p.approval = float(dp.get("approval", 0.5))
	p.political_capital = float(dp.get("political_capital", 45.0))
	p.pc_regen_base = float(dp.get("pc_regen_base", 10.0))
	return p


## Fallback personalities for authored cabinets whose JSON predates traits —
## ported from content/loader.py: _build_cabinet / _FALLBACK_TRAITS.
static func _build_cabinet(player_data: Dictionary) -> Array[Minister]:
	var out: Array[Minister] = []
	var cabinet_data: Array = player_data.get("cabinet", [])
	for i in range(cabinet_data.size()):
		var m: Dictionary = cabinet_data[i]
		var minister := Minister.new()
		minister.id = String(m.get("id", ""))
		minister.name = String(m.get("name", ""))
		minister.portfolio = String(m.get("portfolio", ""))
		minister.faction_id = String(m.get("faction_id", ""))
		minister.competence = float(m.get("competence", 0.0))
		minister.loyalty = float(m.get("loyalty", 0.0))
		minister.ambition = float(m.get("ambition", 0.0))
		var fallback: String = Minister.FALLBACK_TRAITS[i % Minister.FALLBACK_TRAITS.size()]
		minister.trait_id = String(m.get("trait", fallback))
		out.append(minister)
	return out


## The (score, trade_volume) for a country pair — ported from
## content/loader.py: _pair_relation.
static func _pair_relation(data_by_id: Dictionary, a_id: String, b_id: String) -> Array:
	var a_data: Dictionary = data_by_id.get(a_id, {})
	var a_rel = a_data.get("default_relations", {}).get(b_id)
	var b_data: Dictionary = data_by_id.get(b_id, {})
	var b_rel = b_data.get("default_relations", {}).get(a_id)
	var src: Dictionary = {}
	if a_rel is Dictionary:
		src = a_rel
	elif b_rel is Dictionary:
		src = b_rel
	return [float(src.get("score", 0.0)), float(src.get("trade_volume", 0.0))]


## Bilateral relation objects for EVERY country pair, both ways — ported from
## content/loader.py: _wire_all_relations.
static func _wire_all_relations(countries_by_id: Dictionary, data_by_id: Dictionary) -> void:
	var ids: Array = countries_by_id.keys()
	ids.sort()
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var a_id: String = ids[i]
			var b_id: String = ids[j]
			var pair := _pair_relation(data_by_id, a_id, b_id)

			var rel_ab := Country.BilateralRelation.new()
			rel_ab.country_a_id = a_id
			rel_ab.country_b_id = b_id
			rel_ab.score = pair[0]
			rel_ab.trade_volume = pair[1]
			countries_by_id[a_id].relations[b_id] = rel_ab

			var rel_ba := Country.BilateralRelation.new()
			rel_ba.country_a_id = b_id
			rel_ba.country_b_id = a_id
			rel_ba.score = pair[0]
			rel_ba.trade_volume = pair[1]
			countries_by_id[b_id].relations[a_id] = rel_ba


## Ported from engine/campaign.py: _apply_opening_position. Turns the party +
## opening-role config into a coherent government (no cabinet rebuild — see
## the file header's "Deviations" note).
static func _apply_opening_position(state: GameState, opening_role_cfg: String) -> void:
	var own: Faction = null
	for f in state.country.factions:
		if f.id == state.player.faction_id:
			own = f
			break
	if own == null:
		return

	var role := opening_role_cfg
	if role != "contextual" and role != "government" and role != "opposition":
		role = "contextual"
	if role == "contextual":
		role = "government" if own.in_coalition else "opposition"

	if role == "government":
		if state.ruling_faction_id != own.id:
			_configure_government(state, own.id, [])
		else:
			state.player.in_government = true
	else:
		# Preserve the authored cabinet when it already excludes this party;
		# otherwise build an alternative around the strongest rival.
		if own.in_coalition:
			var rivals: Array[Faction] = []
			for f in state.country.factions:
				if f.id != own.id and f.seats > 0:
					rivals.append(f)
			if not rivals.is_empty():
				var lead := rivals[0]
				for f in rivals:
					if f.seats > lead.seats:
						lead = f
				_configure_government(state, lead.id, [own.id])
		state.player.in_government = false

	if not state.player.in_government:
		state.player.title = "Opposition Leader"


## Ported from engine/elections.py: configure_government.
static func _configure_government(state: GameState, ruling_faction_id: String,
		excluded_ids: Array) -> Array[Faction]:
	var factions: Array[Faction] = []
	for f in state.country.factions:
		if f.seats > 0 and not excluded_ids.has(f.id):
			factions.append(f)

	var seed_faction: Faction = null
	for f in factions:
		if f.id == ruling_faction_id:
			seed_faction = f
			break
	if seed_faction == null:
		return []

	var total_seats := 0
	for f in state.country.factions:
		total_seats += f.seats
	var threshold := total_seats / 2 + 1

	var coalition := _build_coalition_around(seed_faction, factions, threshold)
	if coalition.is_empty():
		coalition = [seed_faction]

	for f in state.country.factions:
		f.in_coalition = coalition.has(f)
	state.ruling_faction_id = seed_faction.id
	state.player.in_government = (seed_faction.id == state.player.faction_id)
	return coalition


## Ported from engine/elections.py: _build_coalition_around. Greedily adds the
## seed's ideologically nearest partners, in order, until a majority is
## reached. Returns [] if even every willing partner can't get there (Python
## returns None for this; [] is used instead since GDScript typed arrays
## can't be null, and the seed alone always makes a non-empty success).
static func _build_coalition_around(seed_faction: Faction, factions: Array[Faction],
		threshold: int) -> Array[Faction]:
	var coalition: Array[Faction] = [seed_faction]
	var seats := seed_faction.seats
	if seats >= threshold:
		return coalition

	var candidates: Array[Faction] = []
	for f in factions:
		if f.id != seed_faction.id and f.seats > 0:
			candidates.append(f)
	candidates.sort_custom(func(a: Faction, b: Faction) -> bool:
		return seed_faction.ideology.distance_to(a.ideology) < seed_faction.ideology.distance_to(b.ideology))

	for candidate in candidates:
		if seats >= threshold:
			break
		coalition.append(candidate)
		seats += candidate.seats

	if seats >= threshold:
		return coalition
	return []
