extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const ContentRepositoryScript = preload("res://scripts/native/content/content_repository.gd")
const GameFactoryScript = preload("res://scripts/native/state/game_factory.gd")
const LawActionsScript = preload("res://scripts/native/actions/law_actions.gd")
const StateValidatorScript = preload("res://scripts/native/state/state_validator.gd")

static func _config(role: String = "contextual") -> Dictionary:
	return {"country_id": "ardenia", "background_id": "none",
		"difficulty_id": "normal", "opening_role": role, "seed": 424242}

static func _state(content: Dictionary, role: String = "contextual") -> GameState:
	return GameFactoryScript.new_campaign(content, _config(role))

func _test_catalog_and_thresholds(t, content: Dictionary) -> void:
	var state := _state(content)
	var model := LawActionsScript.read_model(state)
	t.truth(model.get("ok", false), "legislation read model builds")
	t.equal(model["bills"].size(), content["catalogs"]["bills"].size(),
		"every authored bill appears")
	var executive: Dictionary = {}
	for row in model["bills"]:
		if String(row["id"]) == "emergency_price_controls":
			executive = row
			break
	t.truth(not executive["eligible"], "executive orders are visibly unavailable")
	t.truth(not LawActionsScript.preview_bill(state, "emergency_price_controls").get("ok", true),
		"unimplemented executive order cannot be previewed as parliamentary legislation")
	var statutory := LawActionsScript.preview_bill(state, "minimum_wage_act")
	var constitutional := LawActionsScript.preview_bill(state, "press_freedom_act")
	t.truth(statutory.get("ok", false) and constitutional.get("ok", false),
		"statutory and constitutional bills both preview")
	t.equal(statutory["preview"]["threshold"], 51, "statutory bill needs a strict majority")
	t.equal(constitutional["preview"]["threshold"], 67, "constitutional bill needs two thirds")

func _test_guards_lobby_and_withdraw(t, content: Dictionary) -> void:
	var opposition := _state(content, "opposition")
	var before := opposition.to_dict()
	t.truth(not LawActionsScript.propose(opposition, "minimum_wage_act").get("ok", true),
		"opposition cannot introduce government legislation")
	t.equal(opposition.to_dict(), before, "refused opposition proposal is atomic")
	var state := _state(content)
	var pc := state.player.political_capital
	t.truth(LawActionsScript.propose(state, "minimum_wage_act").get("ok", false),
		"government can table an authored statute")
	t.near(state.player.political_capital, pc - LawActionsScript.STATUTORY_PROPOSAL_COST,
		0.0001, "proposal spends political capital once")
	t.truth(not LawActionsScript.propose(state, "defense_spending_act").get("ok", true),
		"only one bill may be tabled")
	var target: Faction = state.country.factions[0]
	t.truth(LawActionsScript.lobby(state, target.id).get("ok", false),
		"tabled bill can be lobbied")
	t.near(float(state.pending_law.lobbying_bonus[target.id]), LawActionsScript.LOBBY_INCREMENT,
		0.0001, "lobbying changes the pending bill")
	t.truth(LawActionsScript.withdraw(state).get("ok", false), "bill can be withdrawn")
	t.equal(state.pending_law, null, "withdraw clears the table")
	t.equal(state.law_history[-1].status, "withdrawn", "withdrawal is recorded")

func _test_passage_effects_exactly_once_and_round_trip(t, content: Dictionary) -> void:
	var state := _state(content)
	for faction in state.country.factions:
		faction.loyalty = 1.0
		faction.ideology.economic = 0.0
		faction.ideology.social = -0.1
		for wing in faction.wings:
			wing.loyalty = 1.0
			wing.ideology.economic = 0.0
			wing.ideology.social = -0.1
			wing.policy_biases["infrastructure_investment_act"] = 0.0
	var debt_before := state.country.economy.public_debt_pct
	var modifier_count := state.modifiers.size()
	t.truth(LawActionsScript.propose(state, "infrastructure_investment_act").get("ok", false),
		"infrastructure bill is tabled")
	var result := LawActionsScript.vote(state)
	t.truth(result.get("ok", false) and result.get("passed", false), "unanimous bill passes")
	t.equal(state.pending_law, null, "vote clears pending law")
	t.equal(state.enacted_laws.size(), 1, "passage enacts exactly one law")
	t.equal(state.law_history.size(), 1, "passage records exactly one outcome")
	t.near(state.country.economy.public_debt_pct, debt_before + 0.025, 0.000001,
		"one-time debt effect applies once")
	t.equal(state.modifiers.size(), modifier_count + 2, "authored modifiers attach once")
	t.truth(not LawActionsScript.vote(state).get("ok", true), "resolved bill cannot be voted twice")
	t.near(state.country.economy.public_debt_pct, debt_before + 0.025, 0.000001,
		"refused second vote cannot reapply effects")
	t.truth(not LawActionsScript.propose(state, "infrastructure_investment_act").get("ok", true),
		"enacted law cannot be proposed again")
	var restored := GameState.from_dict(state.to_dict())
	t.truth(restored != null, "law-bearing state deserializes")
	if restored != null:
		t.equal(restored.enacted_laws[0].id, "infrastructure_investment_act",
			"enacted law survives round trip")
		t.equal(restored.law_history[0].status, "enacted", "law history survives round trip")
		var errors := StateValidatorScript.validate(restored)
		t.equal(errors.size(), 0, "restored law state validates (%s)" % [errors])

func _test_preview_and_read_model_detached(t, content: Dictionary) -> void:
	var state := _state(content)
	var before := state.to_dict()
	var preview := LawActionsScript.preview_bill(state, "progressive_tax_reform_act")
	t.truth(preview.get("ok", false), "modifier-bearing law previews")
	t.truth(not preview["preview"]["effects"].is_empty(), "preview exposes structured effects")
	var faction_preview := LawActionsScript.preview_bill(state, "telecom_privatization_act")
	var saw_loyalty := false
	var saw_power := false
	for row in faction_preview["preview"]["effects"]:
		saw_loyalty = saw_loyalty or row.get("key") == "faction_loyalty"
		saw_power = saw_power or row.get("key") == "faction_power"
	t.truth(saw_loyalty and saw_power,
		"preview discloses authored faction loyalty and power consequences")
	preview["preview"]["bill"]["name"] = "poisoned"
	t.equal(state.to_dict(), before, "preview is pure and detached")
	var model := LawActionsScript.read_model(state)
	model["bills"][0]["name"] = "poisoned"
	t.truth(LawActionsScript.read_model(state)["bills"][0]["name"] != "poisoned",
		"read model callers cannot poison the cached catalogue")

func _test_malformed_save_payloads_rejected_and_never_executed(t, content: Dictionary) -> void:
	var state := _state(content)
	t.truth(LawActionsScript.propose(state, "infrastructure_investment_act").get("ok", false),
		"malformed boundary fixture tables a canonical bill")
	var poisoned_dict := state.to_dict()
	poisoned_dict["pending_law"]["effects"]["one_time_debt_pct_delta"] = 999.0
	var poisoned := GameState.from_dict(poisoned_dict)
	t.truth(poisoned != null, "schemaless effect payload reaches validation boundary")
	if poisoned != null:
		poisoned.pending_law.name = "Old release copy"
		t.equal(StateValidatorScript.validate(poisoned).size(), 0,
			"authored copy/effect snapshots remain loadable across content updates")
		var hydrated_model := LawActionsScript.read_model(poisoned)
		t.truth(hydrated_model.get("ok", false)
			and hydrated_model["pending"]["name"] == "Infrastructure Investment Act"
			and float(hydrated_model["pending"]["effects"]["one_time_debt_pct_delta"]) == 0.025,
			"read model rehydrates current canonical authored content by stable id")
		var honest_preview := LawActionsScript.preview_bill(poisoned, "infrastructure_investment_act")
		poisoned.pending_law.proposed_by = "national_conservatives"
		t.truth(not StateValidatorScript.validate(poisoned).is_empty(),
			"validator rejects a tampered pending sponsor")
		var tampered_preview := LawActionsScript.preview_bill(poisoned, "infrastructure_investment_act")
		t.equal(tampered_preview["preview"]["votes_for"], honest_preview["preview"]["votes_for"],
			"vote projection derives sponsor from the trusted live player")
		poisoned.pending_law.proposed_by = poisoned.player.faction_id
		for faction in poisoned.country.factions:
			faction.loyalty = 1.0
			faction.ideology.economic = 0.0
			faction.ideology.social = -0.1
			for wing in faction.wings:
				wing.loyalty = 1.0
				wing.ideology.economic = 0.0
				wing.ideology.social = -0.1
				wing.policy_biases["infrastructure_investment_act"] = 0.0
		var debt_before := poisoned.country.economy.public_debt_pct
		var voted := LawActionsScript.vote(poisoned)
		t.truth(voted.get("ok", false) and voted.get("passed", false),
			"canonicalized poisoned fixture can still resolve")
		t.near(poisoned.country.economy.public_debt_pct, debt_before + 0.025, 0.000001,
			"vote applies canonical debt effect, never poisoned payload")
		poisoned.enacted_laws[0].name = "mutated active label"
		t.truth(poisoned.law_history[0].name != poisoned.enacted_laws[0].name,
			"active enacted state cannot mutate the immutable history record")

	var duplicate := _state(content)
	var enacted := Law.from_catalog(content["catalogs"]["bills"][0])
	enacted.status = "enacted"
	enacted.enacted_turn = duplicate.turn
	duplicate.enacted_laws.append(enacted)
	duplicate.law_history.append(Law.from_dict(enacted.to_dict()))
	var pending := Law.from_catalog(content["catalogs"]["bills"][0])
	pending.status = "proposed"
	duplicate.pending_law = pending
	t.truth(not StateValidatorScript.validate(duplicate).is_empty(),
		"validator rejects the same bill as pending and enacted")

	var orphan := _state(content)
	orphan.enacted_laws.append(enacted)
	t.truth(not StateValidatorScript.validate(orphan).is_empty(),
		"validator rejects enacted law without matching enacted history")

	var false_majority := _state(content)
	var tied := Law.from_catalog(content["catalogs"]["bills"][0])
	tied.status = "enacted"
	tied.proposed_by = false_majority.player.faction_id
	tied.proposed_turn = false_majority.turn
	tied.enacted_turn = false_majority.turn
	tied.votes_for = 50
	tied.votes_against = 50
	false_majority.enacted_laws.append(tied)
	false_majority.law_history.append(Law.from_dict(tied.to_dict()))
	t.truth(not StateValidatorScript.validate(false_majority).is_empty(),
		"validator rejects a statutory tie recorded as enacted")

	var forged_constitutional := _state(content)
	var constitutional: Law = null
	for row in content["catalogs"]["bills"]:
		if row.get("id") == "press_freedom_act":
			constitutional = Law.from_catalog(row)
			break
	constitutional.status = "enacted"
	constitutional.tier = "statutory"
	constitutional.proposed_by = forged_constitutional.player.faction_id
	constitutional.proposed_turn = forged_constitutional.turn
	constitutional.enacted_turn = forged_constitutional.turn
	constitutional.votes_for = 51
	constitutional.votes_against = 49
	forged_constitutional.enacted_laws.append(constitutional)
	forged_constitutional.law_history.append(Law.from_dict(constitutional.to_dict()))
	t.truth(not StateValidatorScript.validate(forged_constitutional).is_empty(),
		"validator rejects a forged statutory tier on a constitutional enactment")

func _test_malformed_catalogue_is_refused_atomically(t, content: Dictionary) -> void:
	var state := _state(content)
	var before := state.to_dict()
	var original_cache: Array = LawActionsScript._catalog_cache.duplicate(true)
	LawActionsScript._catalog_cache = [{"id": "broken"}]
	var model := LawActionsScript.read_model(state)
	t.truth(not model.get("ok", true) and "catalogue" in str(model.get("error", "")).to_lower(),
		"malformed authored catalogue is refused as one engine error")
	t.equal(state.to_dict(), before, "malformed catalogue refusal is atomic")
	var malformed_modifier: Array = original_cache.duplicate(true)
	for row in malformed_modifier:
		if not row.get("effects", {}).get("modifiers", []).is_empty():
			row["effects"]["modifiers"][0]["institutional"] = "false"
			break
	LawActionsScript._catalog_cache = malformed_modifier
	LawActionsScript._catalog_error = ""
	var modifier_model := LawActionsScript.read_model(state)
	t.truth(not modifier_model.get("ok", true),
		"string institutional flag is refused instead of truthy-coerced")
	LawActionsScript._catalog_cache = original_cache
	LawActionsScript._catalog_error = ""
	var recovered := LawActionsScript.read_model(state)
	t.truth(recovered.get("ok", false), "valid catalogue remains available after test reset")


func _initialize() -> void:
	var t = TestSupportScript.new()
	var content := ContentRepositoryScript.load_all()
	t.truth(not content.has("error"), "content loads for legislative action tests")
	if not content.has("error"):
		_test_catalog_and_thresholds(t, content)
		_test_guards_lobby_and_withdraw(t, content)
		_test_passage_effects_exactly_once_and_round_trip(t, content)
		_test_preview_and_read_model_detached(t, content)
		_test_malformed_save_payloads_rejected_and_never_executed(t, content)
		_test_malformed_catalogue_is_refused_atomically(t, content)
	quit(t.finish())