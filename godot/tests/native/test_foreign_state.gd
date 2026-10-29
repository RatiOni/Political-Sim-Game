extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const SLOT := "test_foreign_state"


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
	t.equal(ForeignSim.power_ids().size(), 5, "five foreign powers are authored")
	t.equal(ForeignSim.milestone_ids().size(), 7, "seven orientation milestones are authored")
	t.equal(ForeignSim.bloc_ids().size(), 3, "three blocs are authored")
	var state := _state()
	for id in ForeignSim.milestone_ids():
		t.truth(String(ForeignSim.milestone(id).get("power", "")) in ForeignSim.power_ids(), "milestone %s belongs to a known power" % id)
	for id in ForeignSim.bloc_ids():
		var anchor := String(ForeignSim.power(id).get("anchor", ""))
		t.truth(state.world_country(anchor) != null, "bloc %s is anchored on a real country" % id)


func _test_a_new_campaign_opens_with_the_canon_obligations(t) -> void:
	var state := _state()
	t.truth(state.foreign.seeded, "the foreign ledger is seeded")
	t.truth(state.foreign.reached.has("isf_programme"), "the ISF agreement is already signed")
	t.truth(state.foreign.reached.has("concert_application"), "and the Concert application is already lodged")
	t.truth(not state.foreign.reached.has("union_observer"), "but Ardenia has no Union standing")
	t.near(float(state.foreign.gas_share["krasova"]), 1.0, 1e-9, "Krasova supplies all the gas")
	t.truth("solheim" in state.foreign.members["concert"], "Solheim anchors the Concert")
	t.truth("krasova" in state.foreign.members["union"], "Krasova anchors the Union")
	t.equal(StateValidator.validate(state).size(), 0, "a seeded campaign is valid")


func _test_seeding_twice_never_resets_progress(t) -> void:
	var state := _state()
	state.foreign.isf["reviews_held"] = 1
	state.foreign.isf["passed"] = 1
	ForeignSim.ensure(state)
	t.equal(int(state.foreign.isf["passed"]), 1, "a second ensure keeps the ISF record")


func _test_the_ledger_round_trips_through_a_binary_save(t) -> void:
	_wipe()
	var state := _state()
	state.foreign.reached["union_observer"] = 0
	state.foreign.isf["failed"] = 1
	state.foreign.isf["reviews_held"] = 1
	state.foreign.isf["suspended"] = true
	state.foreign.isf["last_result"] = "failed"
	state.foreign.western_qualifying_months = 7
	state.foreign.powers["krasova"] = {"dependence": 0.6, "commitment": 0.15, "leverage": 0.5}
	t.truth(SaveStore.save_slot(SLOT, state).get("ok", false), "the campaign saves")
	var loaded := SaveStore.load_slot(SLOT)
	t.truth(loaded.get("ok", false), "and loads")
	var back: GameState = loaded.get("state")
	t.equal(back.foreign.to_dict(), state.foreign.to_dict(), "the foreign ledger comes back unchanged")
	t.equal(back.foreign.members, state.foreign.members, "the bloc members survive the save")
	_wipe()


func _test_an_old_save_gains_the_ledger_on_load(t) -> void:
	var data := _state().to_dict()
	data.erase("foreign")
	var old := GameState.from_dict(data)
	t.truth(old != null and not old.foreign.seeded, "a save from before orientation loads with an empty ledger")
	t.equal(StateValidator.validate(old).size(), 0, "an unseeded ledger is not an error")
	ForeignSim.ensure(old)
	t.truth(old.foreign.reached.has("isf_programme"), "and is seeded with the canon obligations")
	t.equal(StateValidator.validate(old).size(), 0, "and is then valid")
	var broken := _state().to_dict()
	broken["foreign"] = 5
	t.truth(GameState.from_dict(broken) == null, "a malformed ledger refuses to load")


func _test_the_validator_rejects_impossible_ledgers(t) -> void:
	var a := _state()
	a.foreign.powers["krasova"] = {"dependence": 1.5, "commitment": 0.0, "leverage": 0.0}
	_rejects(t, a, "dependence out of range", "a gauge above one is rejected")
	var b := _state()
	b.foreign.powers["atlantis"] = {"dependence": 0.1, "commitment": 0.0, "leverage": 0.0}
	_rejects(t, b, "unknown foreign power", "an unknown power is rejected")
	var c := _state()
	c.foreign.reached["union_observer"] = 0
	c.foreign.reached["union_member"] = 0
	c.foreign.reached["concert_agreement"] = 0
	_rejects(t, c, "locked out by 'concert_agreement'", "Union membership with the Concert agreement is rejected")
	var d := _state()
	d.foreign.reached["union_observer"] = 0
	d.foreign.reached["union_member"] = 0
	d.foreign.reached["meridian_guarantee"] = 0
	_rejects(t, d, "locked out by 'meridian_guarantee'", "Union membership with a Meridian guarantee is rejected")
	var e := _state()
	e.foreign.reached["moon_landing"] = 0
	_rejects(t, e, "unknown milestone", "an unknown milestone is rejected")
	var f := _state()
	f.foreign.isf["reviews_held"] = -1
	_rejects(t, f, "isf ledger is impossible", "a negative ISF record is rejected")
	var g := _state()
	(g.foreign.members["concert"] as Array).append("atlantis")
	_rejects(t, g, "unknown member", "an unknown bloc member is rejected")
	var h := _state()
	(h.foreign.members["union"] as Array).append("ardenia")
	_rejects(t, h, "lists the player country", "the player is never an AI bloc member")
	var i := _state()
	i.foreign.reached["union_member"] = 0
	_rejects(t, i, "without observer", "membership without observer status is rejected")
	var j := _state()
	j.foreign.gas_share["krasova"] = -0.1
	_rejects(t, j, "gas_share out of range", "a negative gas share is rejected")
	var k := _state()
	k.foreign.reached["meridian_partnership"] = k.turn + 5
	_rejects(t, k, "reached in the future", "a milestone from the future is rejected")
	var l := _state()
	(l.foreign.members["concert"] as Array).append("krasova")
	_rejects(t, l, "exclusive", "a country cannot sit in the Union and the Concert")
	var m := _state()
	m.foreign.western_qualifying_months = -1
	_rejects(t, m, "foreign counters are impossible", "a negative discipline count is rejected")
	var n := _state()
	n.foreign.members["warsaw"] = []
	_rejects(t, n, "unknown bloc", "an unknown bloc is rejected")


func _test_malformed_fields_are_refused_without_crashing(t) -> void:
	var base := _state().foreign.to_dict()
	t.truth(ForeignState.from_dict(base) != null, "an intact ledger parses")
	for field in ["powers", "gas_share", "reached", "members", "isf"]:
		var data := base.duplicate(true)
		data[field] = "garbage"
		t.truth(ForeignState.from_dict(data) == null, "a non-Dictionary %s is refused" % field)
	var bad_power := base.duplicate(true)
	bad_power["powers"] = {"krasova": 5}
	t.truth(ForeignState.from_dict(bad_power) == null, "a power row that is not a Dictionary is refused")
	var bad_members := base.duplicate(true)
	bad_members["members"] = {"concert": "solheim"}
	t.truth(ForeignState.from_dict(bad_members) == null, "a bloc roster that is not an Array is refused")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_the_catalog_is_coherent(t)
	_test_a_new_campaign_opens_with_the_canon_obligations(t)
	_test_seeding_twice_never_resets_progress(t)
	_test_the_ledger_round_trips_through_a_binary_save(t)
	_test_an_old_save_gains_the_ledger_on_load(t)
	_test_the_validator_rejects_impossible_ledgers(t)
	_test_malformed_fields_are_refused_without_crashing(t)
	quit(t.finish())
