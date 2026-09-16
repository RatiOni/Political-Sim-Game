extends SceneTree

## Standalone headless test for Task 2: typed campaign state + GameFactory.
## Run via:
##   Godot --headless --path godot --script res://tests/native/test_game_factory.gd

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")
const GameFactoryScript = preload("res://scripts/native/state/game_factory.gd")
const StateValidatorScript = preload("res://scripts/native/state/state_validator.gd")

const EXPECTED_WORLD_IDS := [
	"krasova", "merova", "nueva_costa", "qadir",
	"solheim", "terand", "valmora", "veldoria",
]

const FIXED_SEED := 424242


static func _base_config() -> Dictionary:
	return {
		"country_id": "ardenia",
		"background_id": "none",
		"difficulty_id": "normal",
		"opening_role": "contextual",
		"seed": FIXED_SEED,
	}


func _test_rejects_non_ardenia(t, content: Dictionary) -> void:
	var config := _base_config()
	config["country_id"] = "krasova"
	var state = GameFactoryScript.new_campaign(content, config)
	t.equal(state, null, "a non-Ardenia country_id is rejected (Ardenia-only build)")


func _test_world_and_relations(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	t.truth(state != null, "new_campaign succeeds for ardenia")
	if state == null:
		return

	var world_ids: Array = []
	for c in state.world:
		world_ids.append(c.id)
	world_ids.sort()
	t.equal(world_ids, EXPECTED_WORLD_IDS, "all eight other countries exist as world actors")

	for c in state.world:
		t.truth(not c.factions.is_empty(), "world country %s has factions" % c.id)
		t.truth(not c.is_player, "world country %s is not flagged as player" % c.id)

	# Every country pair (player + world) has a wired, symmetric relation —
	# C(9,2) = 36 pairs.
	var all_ids: Array = [state.country.id]
	all_ids.append_array(world_ids)
	var pair_count := 0
	for i in range(all_ids.size()):
		for j in range(i + 1, all_ids.size()):
			var a_id: String = all_ids[i]
			var b_id: String = all_ids[j]
			var a := state.country if a_id == state.country.id else state.world_country(a_id)
			var b := state.country if b_id == state.country.id else state.world_country(b_id)
			var rel_ab = a.relations.get(b_id)
			var rel_ba = b.relations.get(a_id)
			t.truth(rel_ab != null and rel_ba != null,
				"relation wired both ways for %s/%s" % [a_id, b_id])
			if rel_ab != null and rel_ba != null:
				t.equal(rel_ab.score, rel_ba.score, "relation score symmetric for %s/%s" % [a_id, b_id])
				t.equal(rel_ab.trade_volume, rel_ba.trade_volume,
					"relation trade_volume symmetric for %s/%s" % [a_id, b_id])
			pair_count += 1
	t.equal(pair_count, 36, "36 unique country pairs among nine countries")

	# Spot-check one authored relation survives (Ardenia/Veldoria from the
	# JSON's default_relations).
	var ardenia_veldoria = state.country.relations.get("veldoria")
	t.truth(ardenia_veldoria != null, "ardenia/veldoria relation exists")
	if ardenia_veldoria != null:
		t.near(ardenia_veldoria.score, 0.6, 0.001, "ardenia/veldoria score matches authored content")
		t.near(ardenia_veldoria.trade_volume, 2400.0, 0.001,
			"ardenia/veldoria trade_volume matches authored content")


func _test_non_ardenia_wings_generated(t, content: Dictionary) -> void:
	var state: GameState = GameFactoryScript.new_campaign(content, _base_config())
	if state == null:
		return
	for c in state.world:
		for f in c.factions:
			t.truth(not f.wings.is_empty(), "%s/%s has generated wings" % [c.id, f.id])
			for w in f.wings:
				t.equal(w.kind, "wing", "%s/%s wing %s is generic (kind == wing)" % [c.id, f.id, w.id])

	# Ardenia keeps its authored bloc wings untouched.
	for f in state.country.factions:
		for w in f.wings:
			t.equal(w.kind, "bloc", "ardenia/%s wing %s stays a bloc" % [f.id, w.id])


func _test_opening_role(t, content: Dictionary, opening_role: String,
		expected_in_government: bool, expected_ruling_id: String,
		expected_own_in_coalition: bool) -> void:
	var config := _base_config()
	config["opening_role"] = opening_role
	var state: GameState = GameFactoryScript.new_campaign(content, config)
	t.truth(state != null, "new_campaign succeeds for opening_role=%s" % opening_role)
	if state == null:
		return

	t.equal(state.player.in_government, expected_in_government,
		"opening_role=%s: player.in_government" % opening_role)
	t.equal(state.ruling_faction_id, expected_ruling_id,
		"opening_role=%s: ruling_faction_id" % opening_role)
	t.equal(state.player.faction_id, "liberal_democrats",
		"opening_role=%s: player keeps the authored default party" % opening_role)

	var own: Faction = null
	for f in state.country.factions:
		if f.id == state.player.faction_id:
			own = f
	t.truth(own != null, "opening_role=%s: player's own faction is found" % opening_role)
	if own != null:
		t.equal(own.in_coalition, expected_own_in_coalition,
			"opening_role=%s: own faction in_coalition" % opening_role)

	var expected_meta_role := "government" if expected_in_government else "opposition"
	t.equal(state.campaign_meta.get("opening_role"), expected_meta_role,
		"opening_role=%s: campaign_meta records resolved role" % opening_role)
	t.equal(state.campaign_meta.get("seed"), FIXED_SEED,
		"opening_role=%s: campaign_meta preserves the explicit seed" % opening_role)

	var errors := StateValidatorScript.validate(state)
	t.equal(errors.size(), 0, "opening_role=%s: StateValidator reports no errors (%s)" %
		[opening_role, errors])


func _initialize() -> void:
	var t = TestSupportScript.new()

	var content: Dictionary = ContentRepositoryScript.load_all()
	t.truth(not content.has("error"), "content loads for the factory tests")

	if not content.has("error"):
		_test_rejects_non_ardenia(t, content)
		_test_world_and_relations(t, content)
		_test_non_ardenia_wings_generated(t, content)

		# Ardenia's default player sits in an authored coalition (Liberal
		# Democrats + Social Democrats), so "contextual" resolves to
		# "government" and the ruling party stays the player's own.
		_test_opening_role(t, content, "contextual", true, "liberal_democrats", true)
		_test_opening_role(t, content, "government", true, "liberal_democrats", true)

		# Forced opposition: the player's own party (38 seats) steps down and
		# a government forms around the strongest rival, National
		# Conservatives (32 seats), plus its ideologically nearest partners
		# among the remaining factions (Agrarian Union then Social Democrats)
		# until it reaches the 51-seat majority of the 100-seat chamber.
		_test_opening_role(t, content, "opposition", false, "national_conservatives", false)

	quit(t.finish())
