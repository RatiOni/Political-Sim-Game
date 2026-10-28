class_name GameFactory
extends RefCounted


const PLAYABLE_COUNTRY_IDS: Array[String] = ["ardenia"]

const DEFAULT_YEAR := 1993
const DEFAULT_MONTH := 3


static func new_campaign(content: Dictionary, config: Dictionary) -> GameState:
	var country_id: String = String(config.get("country_id", ""))
	if not PLAYABLE_COUNTRY_IDS.has(country_id):
		push_error("GameFactory: country '%s' is not playable (Ardenia-only build)" % country_id)
		return null

	var seed_raw: Variant = config.get("seed", null)
	if typeof(seed_raw) != TYPE_INT:
		push_error("GameFactory: config 'seed' must be an int, got %s" % [seed_raw])
		return null

	var catalogs_raw: Variant = content.get("catalogs", {})
	if catalogs_raw is Dictionary:
		var catalogs: Dictionary = catalogs_raw
		if catalogs.has("backgrounds"):
			var backgrounds_data: Variant = catalogs["backgrounds"]
			if backgrounds_data is Array:
				var background_ids := {}
				for entry in backgrounds_data:
					if entry is Dictionary and (entry as Dictionary).has("id"):
						background_ids[String((entry as Dictionary)["id"])] = true
				var background_id := String(config.get("background_id", "none"))
				if not background_ids.has(background_id):
					push_error("GameFactory: unknown background_id '%s'" % background_id)
					return null
		if catalogs.has("difficulties"):
			var difficulties_data: Variant = catalogs["difficulties"]
			if difficulties_data is Array:
				var difficulty_ids := {}
				for entry in difficulties_data:
					if entry is Dictionary and (entry as Dictionary).has("id"):
						difficulty_ids[String((entry as Dictionary)["id"])] = true
				var difficulty_id := String(config.get("difficulty_id", "normal"))
				if not difficulty_ids.has(difficulty_id):
					push_error("GameFactory: unknown difficulty_id '%s'" % difficulty_id)
					return null

	var countries_raw: Variant = content.get("countries", null)
	if not (countries_raw is Dictionary):
		push_error("GameFactory: content 'countries' is missing or not a Dictionary")
		return null
	var countries_data: Dictionary = countries_raw
	if not countries_data.has(country_id):
		push_error("GameFactory: no content data for country '%s'" % country_id)
		return null

	var player_raw: Variant = countries_data[country_id]
	if not (player_raw is Dictionary):
		push_error("GameFactory: country data for '%s' is not a Dictionary" % country_id)
		return null
	var player_data: Dictionary = player_raw
	var player_country := Country.from_json(player_data, true)
	if player_country == null:
		push_error("GameFactory: could not parse country '%s'" % country_id)
		return null

	var other_ids: Array[String] = []
	for cid in countries_data.keys():
		if cid != country_id:
			other_ids.append(String(cid))
	other_ids.sort()

	var neighbour_raw: Variant = player_data.get("neighbours", [])
	if not (neighbour_raw is Array):
		push_error("GameFactory: country '%s' neighbours is not an Array" % country_id)
		return null
	var neighbour_ids: Array = neighbour_raw
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
		var data_raw: Variant = countries_data[cid]
		if not (data_raw is Dictionary):
			push_error("GameFactory: country data for '%s' is not a Dictionary" % String(cid))
			return null
		var data: Dictionary = data_raw
		data_by_id[cid] = data
		var c := Country.from_json(data, false)
		if c == null:
			push_error("GameFactory: could not parse country '%s'" % String(cid))
			return null
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
	var built_player := _build_player(player_data, player_country)
	if built_player == null:
		return null
	state.player = built_player
	var built_cabinet: Variant = _build_cabinet(player_data)
	if built_cabinet == null:
		return null
	state.ministers = built_cabinet
	state.ruling_faction_id = state.player.faction_id

	var meta_raw: Variant = player_data.get("meta", {})
	var meta_stability = null
	if meta_raw is Dictionary:
		meta_stability = (meta_raw as Dictionary).get("stability_value")
	if meta_stability != null:
		state.stability_value = float(meta_stability)

	var opening_role_cfg: String = String(config.get("opening_role", "contextual"))
	_apply_opening_position(state, opening_role_cfg)

	state.campaign_meta = {
		"country_id": country_id,
		"difficulty": String(config.get("difficulty_id", "normal")),
		"background": String(config.get("background_id", "none")),
		"opening_role": ("government" if state.player.in_government else "opposition"),
		"seed": seed_raw,
		"national_traits": player_country.national_traits.duplicate(),
	}

	RegionsSim.ensure_region_states(state)

	return state


static func _build_player(player_data: Dictionary, player_country: Country) -> GameState.Player:
	var dp_raw: Variant = player_data.get("default_player", null)
	if not (dp_raw is Dictionary):
		push_error("GameFactory: missing or malformed default_player for country '%s'" % player_country.id)
		return null
	var dp: Dictionary = dp_raw
	var faction_id := String(dp.get("faction_id", ""))
	if faction_id == "":
		push_error("GameFactory: default_player.faction_id is missing or empty")
		return null
	var found := false
	for f in player_country.factions:
		if f.id == faction_id:
			found = true
			break
	if not found:
		push_error("GameFactory: default_player.faction_id '%s' matches no faction" % faction_id)
		return null
	var p := GameState.Player.new()
	p.name = String(dp.get("name", ""))
	p.title = String(dp.get("title", ""))
	p.faction_id = faction_id
	p.ideology_economic = float(dp.get("ideology_economic", 0.0))
	p.ideology_social = float(dp.get("ideology_social", 0.0))
	p.approval = float(dp.get("approval", 0.5))
	p.political_capital = float(dp.get("political_capital", 50.0))
	p.pc_regen_base = float(dp.get("pc_regen_base", 10.0))
	return p


static func _build_cabinet(player_data: Dictionary) -> Variant:
	var out: Array[Minister] = []
	var cabinet_raw: Variant = player_data.get("cabinet", [])
	if not (cabinet_raw is Array):
		push_error("GameFactory: cabinet is not an Array")
		return null
	var cabinet_data: Array = cabinet_raw
	for i in range(cabinet_data.size()):
		var m_raw: Variant = cabinet_data[i]
		if not (m_raw is Dictionary):
			push_error("GameFactory: cabinet entry %d is not a Dictionary" % i)
			return null
		var m: Dictionary = m_raw
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


static func _pair_relation(data_by_id: Dictionary, a_id: String, b_id: String) -> Array:
	var a_raw: Variant = data_by_id.get(a_id, {})
	var a_data: Dictionary = a_raw if a_raw is Dictionary else {}
	var a_rels_raw: Variant = a_data.get("default_relations", {})
	var a_rels: Dictionary = a_rels_raw if a_rels_raw is Dictionary else {}
	var a_rel = a_rels.get(b_id)
	var b_raw: Variant = data_by_id.get(b_id, {})
	var b_data: Dictionary = b_raw if b_raw is Dictionary else {}
	var b_rels_raw: Variant = b_data.get("default_relations", {})
	var b_rels: Dictionary = b_rels_raw if b_rels_raw is Dictionary else {}
	var b_rel = b_rels.get(a_id)
	var src: Dictionary = {}
	if a_rel is Dictionary:
		src = a_rel
	elif b_rel is Dictionary:
		src = b_rel
	return [float(src.get("score", 0.0)), float(src.get("trade_volume", 0.0))]


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
