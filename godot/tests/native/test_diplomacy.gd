extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const KRASOVA := "krasova"


static func _state(role: String = "contextual") -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	state.player.political_capital = 500.0
	state.turn = 10
	return state


static func _friend(state: GameState) -> String:
	var best := ""
	var best_score := -INF
	for key in state.country.relations:
		var rel: Country.BilateralRelation = state.country.relations[key]
		if rel.score > best_score:
			best = key
			best_score = rel.score
	return best


static func _rel(state: GameState, id: String) -> Country.BilateralRelation:
	return state.country.relations[id]


static func _mirror(state: GameState, id: String) -> Country.BilateralRelation:
	for c in state.world:
		if c.id == id:
			return c.relations[state.country.id]
	return null


static func _do(state: GameState, verb: String, id: String, extra := "") -> Dictionary:
	return DiplomacyActions.act(state, verb, id, extra)


func _test_both_sides_of_a_relationship_always_agree(t) -> void:
	var state := _state()
	var id := _friend(state)
	for verb in ["improve_relations", "trade_agreement", "hold_summit", "condemn"]:
		_do(state, verb, id)
	t.near(_rel(state, id).score, _mirror(state, id).score, 1e-9, "the score is the same seen from either capital")
	t.equal(_rel(state, id).treaties.size(), _mirror(state, id).treaties.size(), "and so is the list of treaties")
	t.near(_rel(state, id).trade_volume, _mirror(state, id).trade_volume, 1e-9, "and the trade between them")


func _test_outreach_warms_relations_and_a_good_minister_helps(t) -> void:
	var a := _state()
	var b := _state()
	var id := _friend(a)
	for m in b.ministers:
		if m.portfolio == "Foreign Affairs":
			m.competence = 1.0
			m.loyalty = 1.0
			m.trait_id = ""
	var a0 := _rel(a, id).score
	_do(a, "improve_relations", id)
	_do(b, "improve_relations", id)
	t.truth(_rel(a, id).score > a0, "diplomatic outreach warms relations")
	t.truth(_rel(b, id).score > _rel(a, id).score, "and an able foreign minister warms them further")
	t.near(a.player.political_capital, 490.0, 1e-9, "outreach costs 10 political capital")


func _test_a_trade_pact_is_signed_once_and_pays_over_time(t) -> void:
	var state := _state()
	var id := _friend(state)
	t.truth(_do(state, "trade_agreement", id).get("ok", false), "a trade pact can be signed")
	t.truth(_rel(state, id).treaties.any(func(tr): return tr["type"] == "trade"), "it is on the record")
	t.truth(state.modifiers.any(func(m): return m.target == "gdp_growth"), "its growth benefit phases in")
	var again := _do(state, "trade_agreement", id)
	t.truth(not again.get("ok", true) and String(again["error"]).contains("already"), "but only once per partner")


func _test_a_defense_pact_needs_trust(t) -> void:
	var state := _state()
	_rel(state, KRASOVA).score = 0.10
	_mirror(state, KRASOVA).score = 0.10
	var refused := _do(state, "defense_pact", KRASOVA)
	t.truth(not refused.get("ok", true) and String(refused["error"]).contains("trust"), "a distrusted state will not commit to mutual defence")
	var id := _friend(state)
	_rel(state, id).score = 0.60
	_mirror(state, id).score = 0.60
	var stab0 := state.stability_value
	t.truth(_do(state, "defense_pact", id).get("ok", false), "a trusted partner will")
	t.truth(state.stability_value > stab0, "and an alliance steadies the government")


func _test_sanctions_cut_trade_and_cannot_hit_a_friend(t) -> void:
	var state := _state()
	var friend := _friend(state)
	_rel(state, friend).score = 0.50
	_mirror(state, friend).score = 0.50
	t.truth(not _do(state, "impose_sanctions", friend).get("ok", true), "sanctioning a friend is refused as self-harm")
	_rel(state, KRASOVA).score = -0.40
	_mirror(state, KRASOVA).score = -0.40
	_rel(state, KRASOVA).trade_volume = 600.0
	_mirror(state, KRASOVA).trade_volume = 600.0
	t.truth(_do(state, "impose_sanctions", KRASOVA).get("ok", false), "a hostile power can be sanctioned")
	t.truth(_rel(state, KRASOVA).sanctioned and _mirror(state, KRASOVA).sanctioned, "the regime is in force on both sides")
	t.near(_rel(state, KRASOVA).trade_volume, 0.0, 1e-9, "trade halts")
	t.truth(state.modifiers.any(func(m): return m.target == "gdp_growth" and m.magnitude < 0.0),
		"and losing a big market costs the sanctioning economy too")
	t.truth(not _do(state, "impose_sanctions", KRASOVA).get("ok", true), "a regime cannot be imposed twice")
	t.truth(_do(state, "lift_sanctions", KRASOVA).get("ok", false), "but it can be lifted")
	t.truth(not _rel(state, KRASOVA).sanctioned, "and trade may rebuild")


func _test_summits_are_rationed(t) -> void:
	var state := _state()
	var id := _friend(state)
	t.truth(_do(state, "hold_summit", id).get("ok", false), "a summit can be held")
	var refused := _do(state, "hold_summit", id)
	t.truth(not refused.get("ok", true) and String(refused["error"]).contains("month"), "but the calendar allows one every few months, and says when")
	state.turn += DiplomacyActions.SUMMIT_COOLDOWN
	t.truth(_do(state, "hold_summit", id).get("ok", false), "after which another can be held")


func _test_breaking_a_treaty_has_a_price(t) -> void:
	var state := _state()
	var id := _friend(state)
	_do(state, "trade_agreement", id)
	var treaty_id := String(_rel(state, id).treaties[0]["id"])
	var score0 := _rel(state, id).score
	t.truth(_do(state, "break_treaty", id, treaty_id).get("ok", false), "a treaty can be torn up")
	t.truth(_rel(state, id).treaties.is_empty() and _mirror(state, id).treaties.is_empty(), "it is gone from both sides")
	t.truth(_rel(state, id).score < score0 - 0.15, "and the partner will not forget it")
	t.truth(not state.modifiers.any(func(m): return m.source_id == treaty_id), "the pact's growth benefit dies with it")


func _test_condemnation_pleases_nationalists(t) -> void:
	var state := _state()
	var nat: Faction = null
	for f in state.country.factions:
		if f.id == "national_conservatives":
			nat = f
	var l0 := nat.loyalty
	_do(state, "condemn", KRASOVA)
	t.truth(nat.loyalty > l0, "publicly condemning a rival pleases the nationalist right")


func _test_a_patron_loan_pays_when_markets_charge_a_premium(t) -> void:
	var calm := _state()
	var heavy := _state()
	heavy.country.economy.public_debt_pct = 1.40
	heavy.country.economy.effective_interest_rate = heavy.country.economy.market_interest_rate()
	var id := _friend(calm)
	_do(calm, "foreign_loan", id)
	_do(heavy, "foreign_loan", id)
	var saving_calm := -EconomySim._modifiers_sum(calm, "budget_expenditure")
	var saving_heavy := -EconomySim._modifiers_sum(heavy, "budget_expenditure")
	t.truth(saving_heavy > saving_calm, "refinancing through a patron saves more when markets charge a debt premium (%.0f vs %.0f a year)" % [saving_heavy, saving_calm])
	t.truth(saving_heavy > 0.0, "and saves real money for an indebted state")


func _test_a_loan_has_political_strings(t) -> void:
	var state := _state()
	var nat: Faction = null
	for f in state.country.factions:
		if f.id == "national_conservatives":
			nat = f
	var l0 := nat.loyalty
	_do(state, "foreign_loan", _friend(state))
	t.truth(nat.loyalty < l0, "nationalists resent a foreign patron's money")
	t.equal(state.country.economy.loans.size(), 1, "the loan is on the books")


func _test_loans_run_their_term_and_end(t) -> void:
	var state := _state()
	_do(state, "foreign_loan", _friend(state))
	for _i in range(DiplomacyActions.LOAN_TERM_MONTHS + 1):
		DiplomacySim.monthly(state)
	t.equal(state.country.economy.loans.size(), 0, "a loan is retired at the end of its term")


func _test_refusals_change_nothing(t) -> void:
	var state := _state()
	state.player.political_capital = 2.0
	var before := state.to_dict()
	for verb in ["improve_relations", "trade_agreement", "foreign_loan", "condemn", "defense_pact", "hold_summit"]:
		var r := _do(state, verb, _friend(state))
		t.truth(not r.get("ok", true), "%s is refused without the capital" % verb)
	t.truth(not _do(state, "nonsense", KRASOVA).get("ok", true), "an unknown verb is refused")
	t.truth(not _do(state, "condemn", "atlantis").get("ok", true), "an unknown country is refused")
	t.equal(state.to_dict(), before, "and no refusal changed anything")


func _test_foreign_policy_belongs_to_the_government(t) -> void:
	var state := _state("opposition")
	var r := _do(state, "improve_relations", _friend(state))
	t.truth(not r.get("ok", true) and String(r["error"]).contains("government"), "an opposition leader cannot conduct foreign policy")


func _test_trade_grows_toward_a_ceiling_set_by_warmth(t) -> void:
	var state := _state()
	var id := _friend(state)
	_rel(state, id).score = 0.60
	_mirror(state, id).score = 0.60
	_do(state, "trade_agreement", id)
	var v0 := _rel(state, id).trade_volume
	for _i in range(24):
		DiplomacySim.monthly(state)
	var v24 := _rel(state, id).trade_volume
	t.truth(v24 > v0, "trade under a pact grows")
	for _i in range(240):
		DiplomacySim.monthly(state)
	t.truth(_rel(state, id).trade_volume <= DiplomacySim.TRADE_CEILING * maxf(0.0, _rel(state, id).score) + 1.0,
		"but saturates at a ceiling set by how warm the relationship is")
	_rel(state, id).score = 0.05
	_mirror(state, id).score = 0.05
	var high := _rel(state, id).trade_volume
	for _i in range(24):
		DiplomacySim.monthly(state)
	t.truth(_rel(state, id).trade_volume < high, "and decays when relations cool")


func _test_sanctions_bleed_their_target(t) -> void:
	var state := _state()
	_rel(state, KRASOVA).score = -0.50
	_mirror(state, KRASOVA).score = -0.50
	_do(state, "impose_sanctions", KRASOVA)
	var target: Country = null
	for c in state.world:
		if c.id == KRASOVA:
			target = c
	var stab0 := target.stability
	var gdp0 := target.economy.gdp
	for _i in range(6):
		DiplomacySim.monthly(state)
	t.truth(target.stability < stab0 and target.economy.gdp < gdp0, "a sanctioned state's economy and stability bleed")


func _test_treaties_age(t) -> void:
	var state := _state()
	var id := _friend(state)
	_do(state, "trade_agreement", id)
	for _i in range(3):
		DiplomacySim.monthly(state)
	t.equal(int(_rel(state, id).treaties[0].get("turns_active", 0)), 3, "a treaty counts the months it has stood")


func _test_relations_survive_save_and_reload(t) -> void:
	var state := _state()
	var id := _friend(state)
	_do(state, "trade_agreement", id)
	_do(state, "foreign_loan", id)
	_rel(state, KRASOVA).score = -0.5
	_mirror(state, KRASOVA).score = -0.5
	_do(state, "impose_sanctions", KRASOVA)
	_do(state, "hold_summit", id)
	var copy := GameState.from_dict(state.to_dict())
	t.equal(copy.country.relations[id].to_dict(), _rel(state, id).to_dict(), "a relationship and its treaties round-trip")
	t.truth(copy.country.relations[KRASOVA].sanctioned, "so does a sanctions regime")
	t.equal(copy.country.economy.loans, state.country.economy.loans, "and the loan book")
	t.truth(not DiplomacyActions.act(copy, "hold_summit", id, "").get("ok", true), "and the summit calendar")


func _test_the_desk_lists_every_country_with_reasons(t) -> void:
	var state := _state()
	var rows := DiplomacyActions.read_model(state)
	t.equal(rows.size(), state.world.size(), "every foreign country has a row")
	var refused_with_reason := true
	for row in rows:
		for action in row["actions"]:
			if not action["eligible"] and String(action["disabled_reason"]) == "":
				refused_with_reason = false
	t.truth(refused_with_reason, "every unavailable action says why")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_both_sides_of_a_relationship_always_agree(t)
	_test_outreach_warms_relations_and_a_good_minister_helps(t)
	_test_a_trade_pact_is_signed_once_and_pays_over_time(t)
	_test_a_defense_pact_needs_trust(t)
	_test_sanctions_cut_trade_and_cannot_hit_a_friend(t)
	_test_summits_are_rationed(t)
	_test_breaking_a_treaty_has_a_price(t)
	_test_condemnation_pleases_nationalists(t)
	_test_a_patron_loan_pays_when_markets_charge_a_premium(t)
	_test_a_loan_has_political_strings(t)
	_test_loans_run_their_term_and_end(t)
	_test_refusals_change_nothing(t)
	_test_foreign_policy_belongs_to_the_government(t)
	_test_trade_grows_toward_a_ceiling_set_by_warmth(t)
	_test_sanctions_bleed_their_target(t)
	_test_treaties_age(t)
	_test_relations_survive_save_and_reload(t)
	_test_the_desk_lists_every_country_with_reasons(t)
	quit(t.finish())
