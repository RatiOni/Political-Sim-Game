extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")


static func _state(role: String = "government") -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	state.player.political_capital = 500.0
	state.turn = 10
	return state


static func _score(state: GameState, id: String) -> float:
	return (state.country.relations[id] as Country.BilateralRelation).score


static func _trade(state: GameState, id: String) -> float:
	return (state.country.relations[id] as Country.BilateralRelation).trade_volume


static func _set_warmth(state: GameState, id: String, score: float) -> void:
	(state.country.relations[id] as Country.BilateralRelation).score = score
	(DiplomacySim.world_country(state, id).relations[state.country.id] as Country.BilateralRelation).score = score


static func _enact_bank_act(state: GameState) -> void:
	var law := Law.new()
	law.id = OrientationSim.BANK_ACT
	state.enacted_laws.append(law)


static func _economy(state: GameState, deficit: float, inflation: float) -> void:
	var econ := state.country.economy
	econ.budget.expenditure = econ.budget.revenue + econ.gdp * deficit
	econ.inflation = inflation


static func _error(result: Dictionary) -> String:
	return String(result.get("error", ""))


static func _member_state() -> GameState:
	var state := _state()
	state.foreign.reached["union_observer"] = 0
	state.turn = OrientationActions.OBSERVER_MONTHS_FOR_MEMBERSHIP + 1
	_set_warmth(state, "krasova", -0.1)
	OrientationActions.act(state, "union_member")
	return state


func _test_the_association_agreement_takes_years_of_discipline(t) -> void:
	var state := _state()
	t.truth(_error(OrientationActions.act(state, "concert_agreement")).contains("months of budget discipline"), "the Concert wants years of discipline first")
	state.foreign.western_qualifying_months = OrientationActions.QUALIFYING_MONTHS_FOR_AGREEMENT
	t.truth(_error(OrientationActions.act(state, "concert_agreement")).contains("independent central bank"), "and an independent central bank")
	_enact_bank_act(state)
	var k0 := _score(state, "krasova")
	var debt0 := state.country.economy.public_debt_pct
	var pc0 := state.player.political_capital
	t.truth(OrientationActions.act(state, "concert_agreement").get("ok", false), "then the agreement is signed")
	t.truth(state.foreign.reached.has("concert_agreement"), "and recorded")
	t.near(state.player.political_capital, pc0 - float(OrientationActions.COSTS["concert_agreement"]), 1e-9, "at its political price")
	t.truth(state.country.economy.public_debt_pct > debt0, "and its treasury price")
	t.truth(state.modifiers.any(func(m: Modifier) -> bool: return m.source_id == "concert_agreement" and m.target == "gdp_growth" and m.magnitude > 0.0), "its market access phases in")
	t.truth(_score(state, "krasova") < k0, "and Krasova takes it as a step away")


func _test_discipline_accrues_and_slips(t) -> void:
	var state := _state()
	state.month = 5
	_economy(state, 0.01, 0.03)
	for _i in range(3):
		OrientationSim.monthly(state)
	t.equal(state.foreign.western_qualifying_months, 3, "three disciplined months count")
	_economy(state, 0.10, 0.03)
	OrientationSim.monthly(state)
	t.equal(state.foreign.western_qualifying_months, 1, "a loose month costs two")
	for _i in range(5):
		OrientationSim.monthly(state)
	t.equal(state.foreign.western_qualifying_months, 0, "and the count never goes below zero")


func _test_a_guarantee_waits_for_vetrenka(t) -> void:
	var state := _state()
	t.truth(OrientationActions.act(state, "meridian_partnership").get("ok", false), "the partnership is open to Ardenia")
	t.truth(_error(OrientationActions.act(state, "meridian_guarantee")).contains("must run"), "a guarantee waits for a mature partnership")
	state.turn += OrientationActions.PARTNERSHIP_MONTHS_FOR_GUARANTEE
	t.truth(_error(OrientationActions.act(state, "meridian_guarantee")).contains("territorial dispute"), "and is barred while Vetrenka is unresolved")
	state.campaign_meta["vetrenka_status"] = "partitioned_contested"
	t.truth(not OrientationActions.act(state, "meridian_guarantee").get("ok", false), "a contested partition is still a dispute")
	state.campaign_meta["vetrenka_status"] = "settled"
	var stability0 := state.stability_value
	t.truth(OrientationActions.act(state, "meridian_guarantee").get("ok", false), "a settled Vetrenka opens the guarantee")
	t.truth(state.stability_value > stability0, "and the guarantee steadies the state")


func _test_the_union_admits_observers_then_members(t) -> void:
	var state := _state()
	_set_warmth(state, "krasova", -0.6)
	t.truth(_error(OrientationActions.act(state, "union_observer")).contains("hostility"), "Krasova will not seat a hostile observer")
	_set_warmth(state, "krasova", -0.2)
	t.truth(OrientationActions.act(state, "union_observer").get("ok", false), "but seats a merely cool one")
	t.truth(_error(OrientationActions.act(state, "union_member")).contains("months before membership"), "membership needs time as an observer")
	state.turn += OrientationActions.OBSERVER_MONTHS_FOR_MEMBERSHIP
	_set_warmth(state, "krasova", -0.3)
	t.truth(_error(OrientationActions.act(state, "union_member")).contains("hostility"), "and a warm enough Krasova")
	_set_warmth(state, "krasova", -0.1)
	t.truth(OrientationActions.act(state, "union_member").get("ok", false), "then Ardenia joins the Union")
	t.truth(state.modifiers.any(func(m: Modifier) -> bool: return m.source_id == "union_member" and m.target == "gdp_growth" and m.magnitude > 0.0), "its open markets phase in")
	t.truth(state.modifiers.any(func(m: Modifier) -> bool: return m.source_id == "union_member" and m.target == "budget_expenditure" and m.magnitude < 0.0 and not m.institutional), "and its debt is rescheduled")


func _test_the_hard_locks_hold(t) -> void:
	var member := _member_state()
	t.truth(member.foreign.reached.has("union_member"), "the fixture is a Union member")
	member.foreign.western_qualifying_months = 99
	_enact_bank_act(member)
	t.truth(_error(OrientationActions.act(member, "concert_agreement")).contains("beyond partnership"), "a Union member cannot sign the association agreement")
	t.truth(OrientationActions.act(member, "meridian_partnership").get("ok", false), "but may still hold a Meridian partnership")
	member.turn += OrientationActions.PARTNERSHIP_MONTHS_FOR_GUARANTEE
	member.campaign_meta["vetrenka_status"] = "settled"
	t.truth(_error(OrientationActions.act(member, "meridian_guarantee")).contains("beyond partnership"), "and cannot take a Meridian guarantee")
	var west := _state()
	west.foreign.reached["union_observer"] = 0
	west.foreign.reached["concert_agreement"] = 0
	west.turn += OrientationActions.OBSERVER_MONTHS_FOR_MEMBERSHIP
	_set_warmth(west, "krasova", -0.1)
	t.truth(_error(OrientationActions.act(west, "union_member")).contains("incompatible"), "an associated country cannot join the Union")
	t.equal(Array(StateValidator.validate(member)).filter(func(e) -> bool: return String(e).contains("locked")).size(), 0, "no lock is ever broken by a permitted step")


func _test_union_tariffs_shrink_western_trade(t) -> void:
	var outside := _state()
	var inside := _member_state()
	for s in [outside, inside]:
		_set_warmth(s, "solheim", 0.8)
		DiplomacySim.set_trade(s, "solheim", 0.0)
		DiplomacySim.monthly(s)
	t.near(ForeignSim.trade_ceiling_share(inside, "solheim"), ForeignSim.UNION_TARIFF_SHARE, 1e-9, "Concert trade is capped by the common tariff")
	t.near(ForeignSim.trade_ceiling_share(inside, "krasova"), 1.0, 1e-9, "Union trade is not")
	t.near(ForeignSim.trade_ceiling_share(outside, "solheim"), 1.0, 1e-9, "and outside the Union nothing is capped")
	t.truth(_trade(inside, "solheim") < _trade(outside, "solheim"), "so a member's Concert trade grows more slowly")


func _test_the_union_must_consent(t) -> void:
	var state := _member_state()
	t.truth(_error(DiplomacyActions.act(state, "impose_sanctions", "krasova")).contains("Union"), "a member cannot sanction a fellow member")
	t.truth(_error(DiplomacyActions.act(state, "condemn", "krasova")).contains("Union"), "or condemn one")
	_set_warmth(state, "veldoria", 0.9)
	t.truth(_error(DiplomacyActions.act(state, "defense_pact", "veldoria")).contains("Union"), "or sign a defence pact outside the bloc")
	var free := _state()
	_set_warmth(free, "veldoria", 0.9)
	t.truth(DiplomacyActions.act(free, "defense_pact", "veldoria").get("ok", false), "outside the Union the same pact is free")


func _test_leaving_the_union_is_a_crisis(t) -> void:
	var state := _member_state()
	var stability0 := state.stability_value
	var k0 := _score(state, "krasova")
	t.truth(OrientationActions.act(state, "union_leave").get("ok", false), "Ardenia can walk out")
	t.truth(not state.foreign.reached.has("union_member") and not state.foreign.reached.has("union_observer"), "and holds no Union standing after")
	t.truth(not state.modifiers.any(func(m: Modifier) -> bool: return m.source_id == "union_member"), "the Union's benefits end at once")
	t.truth(state.stability_value < stability0, "the exit shakes the government")
	t.near(_score(state, "krasova"), maxf(-1.0, k0 + OrientationActions.EXIT_RELATIONS_COST), 1e-9, "and Krasova calls it betrayal")
	t.truth(state.modifiers.any(func(m: Modifier) -> bool: return m.target == "gdp_growth" and m.magnitude < 0.0 and m.source_id.begins_with("union_exit")), "tariffs return overnight")
	_set_warmth(state, "krasova", -0.1)
	t.truth(_error(OrientationActions.act(state, "union_observer")).contains("readmit"), "and Krasova will not readmit Ardenia soon")
	t.truth(_error(OrientationActions.act(_state(), "union_leave")).contains("not part of the Union"), "there is nothing to leave outside the Union")


func _test_refusals_change_nothing(t) -> void:
	var state := _state()
	var before := state.foreign.to_dict()
	var pc := state.player.political_capital
	for verb in OrientationActions.VERBS:
		if OrientationActions.reason_for(state, verb) != "":
			OrientationActions.act(state, verb)
	t.equal(state.foreign.to_dict(), before, "a refused step leaves the ledger untouched")
	t.near(state.player.political_capital, pc, 1e-9, "and costs nothing")
	var opposition := _state("opposition")
	for verb in OrientationActions.VERBS:
		t.equal(OrientationActions.reason_for(opposition, verb), "Foreign policy belongs to the government.", "%s belongs to the government" % verb)


func _test_thresholds_sit_exactly_on_their_boundaries(t) -> void:
	var state := _state()
	state.foreign.reached["concert_application"] = 0
	_economy(state, OrientationSim.CONCERT_DEFICIT_LIMIT, OrientationSim.CONCERT_INFLATION_LIMIT)
	OrientationSim.monthly(state)
	t.equal(state.foreign.western_qualifying_months, 1, "a month exactly on both limits qualifies")
	_economy(state, OrientationSim.CONCERT_DEFICIT_LIMIT + 0.001, 0.03)
	OrientationSim.monthly(state)
	t.equal(state.foreign.western_qualifying_months, 0, "a deficit just over the limit does not")
	_economy(state, 0.01, OrientationSim.CONCERT_INFLATION_LIMIT + 0.001)
	state.foreign.western_qualifying_months = 5
	OrientationSim.monthly(state)
	t.equal(state.foreign.western_qualifying_months, 3, "nor does inflation just over the limit")
	var unapplied := _state()
	unapplied.foreign.reached.erase("concert_application")
	_economy(unapplied, 0.01, 0.03)
	OrientationSim.monthly(unapplied)
	t.equal(unapplied.foreign.western_qualifying_months, 0, "discipline counts only after applying")
	_enact_bank_act(state)
	state.foreign.western_qualifying_months = OrientationActions.QUALIFYING_MONTHS_FOR_AGREEMENT - 1
	t.truth(_error(OrientationActions.act(state, "concert_agreement")).contains("months of budget discipline"), "one month short of the agreement is refused")
	state.foreign.western_qualifying_months = OrientationActions.QUALIFYING_MONTHS_FOR_AGREEMENT
	t.equal(OrientationActions.reason_for(state, "concert_agreement"), "", "the exact count is enough")
	var m := _state()
	m.foreign.reached["meridian_partnership"] = m.turn
	m.campaign_meta["vetrenka_status"] = "retaken"
	m.turn += OrientationActions.PARTNERSHIP_MONTHS_FOR_GUARANTEE - 1
	t.truth(_error(OrientationActions.act(m, "meridian_guarantee")).contains("must run"), "a partnership one month short cannot carry a guarantee")
	m.turn += 1
	t.equal(OrientationActions.reason_for(m, "meridian_guarantee"), "", "and the exact term can; a retaken Vetrenka counts as resolved")
	var u := _state()
	_set_warmth(u, "krasova", OrientationActions.OBSERVER_WARMTH)
	t.equal(OrientationActions.reason_for(u, "union_observer"), "", "an observer seat opens exactly at the warmth floor")
	_set_warmth(u, "krasova", OrientationActions.OBSERVER_WARMTH - 0.01)
	t.truth(OrientationActions.reason_for(u, "union_observer") != "", "and not below it")
	u.foreign.reached["union_observer"] = u.turn
	_set_warmth(u, "krasova", OrientationActions.MEMBER_WARMTH)
	u.turn += OrientationActions.OBSERVER_MONTHS_FOR_MEMBERSHIP - 1
	t.truth(_error(OrientationActions.act(u, "union_member")).contains("months before membership"), "membership one month early is refused")
	u.turn += 1
	t.equal(OrientationActions.reason_for(u, "union_member"), "", "the exact term at the exact warmth admits")
	_set_warmth(u, "krasova", OrientationActions.MEMBER_WARMTH - 0.01)
	t.truth(OrientationActions.reason_for(u, "union_member") != "", "and just below that warmth does not")
	var r := _member_state()
	OrientationActions.act(r, "union_leave")
	_set_warmth(r, "krasova", 0.5)
	r.turn += OrientationActions.UNION_REJOIN_MONTHS - 1
	t.truth(_error(OrientationActions.act(r, "union_observer")).contains("1 more months"), "readmission stays barred until the last month")
	r.turn += 1
	t.equal(OrientationActions.reason_for(r, "union_observer"), "", "and opens exactly when the bar expires")
	var p := _state()
	p.player.political_capital = float(OrientationActions.COSTS["meridian_partnership"])
	t.equal(OrientationActions.reason_for(p, "meridian_partnership"), "", "exactly enough capital is enough")
	p.player.political_capital -= 0.01
	t.truth(OrientationActions.reason_for(p, "meridian_partnership").contains("political capital"), "a fraction short is not")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_the_association_agreement_takes_years_of_discipline(t)
	_test_discipline_accrues_and_slips(t)
	_test_a_guarantee_waits_for_vetrenka(t)
	_test_the_union_admits_observers_then_members(t)
	_test_the_hard_locks_hold(t)
	_test_union_tariffs_shrink_western_trade(t)
	_test_the_union_must_consent(t)
	_test_leaving_the_union_is_a_crisis(t)
	_test_refusals_change_nothing(t)
	_test_thresholds_sit_exactly_on_their_boundaries(t)
	quit(t.finish())
