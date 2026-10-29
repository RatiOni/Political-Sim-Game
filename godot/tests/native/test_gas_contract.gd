extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const SLOT := "test_gas_contract"


static func _state(role: String = "government") -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	return state


static func _wipe() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := "user://saves/%s.json%s" % [SLOT, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


static func _rejects(t, state: GameState, fragment: String, label: String) -> void:
	var errors := StateValidator.validate(state)
	t.truth(Array(errors).any(func(e) -> bool: return String(e).contains(fragment)), label)


func _test_the_catalog_is_coherent(t) -> void:
	var weights: Array = GasSim.catalog().get("season", [])
	t.equal(weights.size(), 12, "the season has twelve monthly weights")
	var total := 0.0
	for w in weights:
		total += float(w)
	t.near(total, 12.0, 0.000001, "and they sum to a year of demand")
	t.equal(GasSim.season_weight(3), GasSim.WINTER_WEIGHT, "March is still the heating season")
	t.truth(GasSim.season_weight(4) < 1.0, "April is not")
	t.truth(GasSim.season_weight(9) < 1.0, "September is not")
	t.equal(GasSim.season_weight(10), GasSim.WINTER_WEIGHT, "October is")
	t.truth((GasSim.catalog().get("contracts", {}) as Dictionary).has("ardenia"), "Ardenia's contract is authored")


func _test_a_new_campaign_opens_with_the_zovar_contract(t) -> void:
	var g := _state().foreign.gas
	t.truth(g.is_active(), "the campaign opens with an active gas contract")
	t.equal(g.supplier_id, "krasova", "supplied by Krasova")
	t.equal(g.price, 50.0, "at the authored price")
	t.equal(g.reference_price, 50.0, "which is also the market reference")
	t.equal(g.arrears, 40.0, "already in arrears")
	t.equal(g.term_end, 22, "renewing in January 1995")
	t.equal(g.paid.size(), GasContract.PAID_MONTHS, "with a year of payment history")
	var paid := 0.0
	for p in g.paid:
		paid += p
	t.near(paid, 50.0 * 6.0 * GasSim.PAYMENT_SHARE, 0.000001, "that settles the steady share of a year's bill")


func _test_dependence_share_reads_the_contract(t) -> void:
	var state := _state()
	t.equal(float(state.foreign.gas_share["krasova"]), 1.0, "all gas comes from Krasova at the start")
	state.foreign.gas.second_line_volume = 2.0
	GasSim.write_share(state)
	t.near(float(state.foreign.gas_share["krasova"]), 0.75, 0.000001, "a second line cuts Krasova's share to what it still contracts")


func _test_joining_the_union_caps_the_price(t) -> void:
	var state := _state()
	GasSim.on_union_join(state)
	t.near(state.foreign.gas.price, 35.0, 0.000001, "joining the Union caps the price at seventy percent of the reference")
	state.foreign.gas.price = 20.0
	GasSim.on_union_join(state)
	t.equal(state.foreign.gas.price, 20.0, "and never raises a cheaper one")


func _test_seeding_twice_never_resets_the_contract(t) -> void:
	var state := _state()
	state.foreign.gas.arrears = 99.0
	t.truth(not GasSim.ensure(state), "an active contract is not seeded again")
	ForeignSim.ensure(state)
	t.equal(state.foreign.gas.arrears, 99.0, "and keeps its arrears")


func _test_the_contract_round_trips_through_a_binary_save(t) -> void:
	_wipe()
	var state := _state()
	var g := state.foreign.gas
	var floats := ["price", "reference_price", "contracted_volume", "annual_demand", "arrears", "take_or_pay", "cut", "sabotage", "storage", "storage_capacity", "storage_target", "second_line_volume", "spot_pending"]
	var ints := ["term_end", "cut_until", "last_cut_turn", "last_demand_turn", "storage_started", "second_line_started", "last_renegotiated", "demands", "threats", "cuts", "second_line_months_saved"]
	t.equal(floats, GasContract.FLOAT_FIELDS, "the float field list is the one pinned here")
	t.equal(ints, GasContract.INT_FIELDS, "the int field list is the one pinned here")
	var n := 1
	for field in floats:
		g.set(field, 0.1 * float(n))
		n += 1
	for field in ints:
		g.set(field, n)
		n += 1
	g.cut = 0.25
	g.cut_until = 3
	g.threat = {"turn": 0, "due": 1, "share": 0.2}
	g.concessions.append("transit")
	g.last_flow = {"demand": 0.75, "delivered": 0.5, "drawn": 0.1, "injected": 0.0, "bill": 30.0, "shortfall": 0.2, "severity": 0.2}
	g.storage_target = 1.0
	g.storage_capacity = 0.5
	g.storage = 0.25
	g.cuts = 2
	t.truth(SaveStore.save_slot(SLOT, state).get("ok", false), "the contract saves")
	var loaded: Dictionary = SaveStore.load_slot(SLOT)
	t.truth(loaded.get("ok", false), "and loads")
	var back := (loaded["state"] as GameState).foreign.gas
	t.equal(back.to_dict(), g.to_dict(), "every contract field survives the round trip")
	for field in floats + ints:
		t.equal(back.get(field), g.get(field), "%s survives the round trip" % field)
		t.truth(g.get(field) != GasContract.new().get(field), "%s is set to a non-default value" % field)
	t.equal(back.supplier_id, g.supplier_id, "the supplier survives")
	t.equal(back.threat, g.threat, "the threat survives")
	t.equal(back.concessions, g.concessions, "the concessions survive")
	t.equal(back.paid, g.paid, "the payment history survives")
	t.equal(back.last_flow, g.last_flow, "the last flow survives")
	_wipe()


func _test_an_old_save_gains_the_contract_on_load(t) -> void:
	_wipe()
	var state := _state()
	state.foreign.gas = GasContract.new()
	SaveStore.save_slot(SLOT, state)
	var game: Node = NativeGameScript.new()
	t.truth(game.load(SLOT).get("ok", false), "a plan-1 save without a contract loads")
	t.truth(game._state.foreign.gas.is_active(), "and gains the Zovar contract")
	game.free()
	_wipe()


func _test_malformed_contracts_are_refused(t) -> void:
	t.truth(GasContract.from_dict("x") == null, "a contract that is not a dictionary is refused")
	t.truth(GasContract.from_dict({"paid": 3}) == null, "a payment history that is not a list is refused")
	t.truth(GasContract.from_dict({"concessions": 3}) == null, "a concession list that is not a list is refused")
	t.truth(GasContract.from_dict({"threat": []}) == null, "a threat that is not a dictionary is refused")
	t.truth(GasContract.from_dict({"last_flow": 3}) == null, "a flow record that is not a dictionary is refused")
	t.truth(ForeignState.from_dict({"gas": 5}) == null, "and so is a ledger that carries one")
	t.truth(not GasContract.from_dict(null).is_active(), "a missing contract loads inactive")


func _test_the_validator_rejects_impossible_contracts(t) -> void:
	var s := _state()
	s.foreign.gas.arrears = -1.0
	_rejects(t, s, "gas arrears is impossible", "negative arrears are rejected")
	s = _state()
	s.foreign.gas.take_or_pay = NAN
	_rejects(t, s, "gas take_or_pay is impossible", "a non-finite take-or-pay is rejected")
	s = _state()
	s.foreign.gas.cut = 1.5
	_rejects(t, s, "gas cut is above one", "a cut above one is rejected")
	s = _state()
	s.foreign.gas.sabotage = -0.1
	_rejects(t, s, "gas sabotage is impossible", "negative sabotage is rejected")
	s = _state()
	s.foreign.gas.price = 0.0
	_rejects(t, s, "gas price must be positive", "a free contract is rejected")
	s = _state()
	s.foreign.gas.supplier_id = "atlantis"
	_rejects(t, s, "gas supplier 'atlantis' is unknown", "an unknown supplier is rejected")
	s = _state()
	s.foreign.gas.storage = 0.5
	_rejects(t, s, "gas storage exceeds its capacity", "gas above the storage capacity is rejected")
	s = _state()
	s.foreign.gas.storage_capacity = 0.5
	_rejects(t, s, "gas storage exceeds its capacity", "capacity above the programme target is rejected")
	s = _state()
	s.foreign.gas.storage_started = s.turn + 1
	_rejects(t, s, "gas storage_started is out of time", "a programme started in the future is rejected")
	s = _state()
	s.foreign.gas.last_renegotiated = -2
	_rejects(t, s, "gas last_renegotiated is out of time", "a turn before the campaign is rejected")
	s = _state()
	s.foreign.gas.cuts = -1
	_rejects(t, s, "gas cuts is negative", "a negative cut count is rejected")
	s = _state()
	s.foreign.gas.threat = {"turn": 0, "due": 0, "share": 0.2}
	_rejects(t, s, "gas threat is impossible", "a threat due before it is made is rejected")
	s = _state()
	s.foreign.gas.threat = {"turn": 0, "due": 1, "share": 1.2}
	_rejects(t, s, "gas threat is impossible", "a threat beyond the whole supply is rejected")
	s = _state()
	s.foreign.gas.threat = {"turn": s.turn + 1, "due": s.turn + 2, "share": 0.2}
	_rejects(t, s, "gas threat is impossible", "a threat made in the future is rejected")
	s = _state()
	s.foreign.gas.threat = {"turn": -1, "due": 1, "share": 0.2}
	_rejects(t, s, "gas threat is impossible", "a threat made before the campaign is rejected")
	s = _state()
	s.foreign.gas.paid.append(1.0)
	_rejects(t, s, "gas payment history is impossible", "more than a year of history is rejected")
	s = _state()
	s.foreign.gas.paid[0] = -1.0
	_rejects(t, s, "gas payment history is impossible", "a negative payment is rejected")
	s = _state()
	s.foreign.gas.concessions.append("transit")
	t.truth(StateValidator.validate(s).is_empty(), "a catalogued concession is accepted")
	s = _state()
	s.foreign.gas.concessions.append("souls")
	_rejects(t, s, "unknown gas concession 'souls'", "an unknown concession is rejected")
	s = _state()
	s.foreign.reached["union_observer"] = 0
	s.foreign.reached["union_member"] = 0
	_rejects(t, s, "gas price breaks the Union cap", "a member paying above the Union cap is rejected")
	s.foreign.gas.price = GasSim.union_cap(s.foreign.gas)
	t.truth(StateValidator.validate(s).is_empty(), "a member paying exactly the cap is valid")
	t.truth(StateValidator.validate(_state()).is_empty(), "the opening contract is valid")
	s = _state()
	s.foreign.gas = GasContract.new()
	t.truth(StateValidator.validate(s).is_empty(), "a country with no contract is valid")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_the_catalog_is_coherent(t)
	_test_a_new_campaign_opens_with_the_zovar_contract(t)
	_test_dependence_share_reads_the_contract(t)
	_test_joining_the_union_caps_the_price(t)
	_test_seeding_twice_never_resets_the_contract(t)
	_test_the_contract_round_trips_through_a_binary_save(t)
	_test_an_old_save_gains_the_contract_on_load(t)
	_test_malformed_contracts_are_refused(t)
	_test_the_validator_rejects_impossible_contracts(t)
	quit(t.finish())
