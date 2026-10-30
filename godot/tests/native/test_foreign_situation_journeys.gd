extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const Journeys = preload("res://tests/native/test_orientation_journeys.gd")
const SEEDS := [919191, 31, 424242, 7]
const STRATEGIES := ["neutral", "western", "union"]
const MONTHS := 240
const FOREIGN_SHARE_CEILING := 0.5
const ARRIVALS_PER_FIVE_YEARS := [10, 35]
const WESTERN_ACCEPTS := {"western_aid_strings": "accept_aid", "concert_energy_offer": "accept"}


static func _journey(seed: int, strategy: String) -> Dictionary:
	var state := Journeys._state(seed)
	var invalid := 0
	for m in range(MONTHS):
		Journeys._play(state, strategy)
		if strategy == "western" and state.foreign.gas.second_line_started < 0:
			EnergyActions.act(state, "gas_second_line")
		if strategy == "western":
			for id in WESTERN_ACCEPTS:
				if state.pending_situations.any(func(s: Situation) -> bool: return s.event_id == id):
					EventActions.resolve(state, id, String(WESTERN_ACCEPTS[id]))
		NativeGameScript.next_month(state)
		if m % 12 == 11 and not StateValidator.validate(state).is_empty():
			invalid += 1
	var arrivals := {}
	for row in state.event_history:
		var id := String(row["event_id"])
		arrivals[id] = int(arrivals.get(id, 0)) + 1
	return {"arrivals": arrivals, "total": state.event_history.size(), "invalid": invalid,
		"signature": str(state.event_history.map(func(r: Dictionary) -> String: return "%s@%d" % [r["event_id"], r["turn"]]))}


func _test_every_foreign_situation_happens_somewhere(t, runs: Dictionary) -> void:
	var seen := {}
	for key in runs:
		for id in runs[key]["arrivals"]:
			seen[id] = int(seen.get(id, 0)) + int(runs[key]["arrivals"][id])
	for id in ForeignArcs.EVENT_IDS:
		t.truth(int(seen.get(id, 0)) > 0, "%s reaches some government in twelve twenty-year journeys (%d)" % [id, int(seen.get(id, 0))])


func _test_foreign_affairs_do_not_crowd_the_desk(t, runs: Dictionary) -> void:
	for key in runs:
		var foreign := 0
		for id in runs[key]["arrivals"]:
			if id in ForeignArcs.EVENT_IDS:
				foreign += int(runs[key]["arrivals"][id])
		var total := int(runs[key]["total"])
		t.truth(float(foreign) <= FOREIGN_SHARE_CEILING * float(maxi(1, total)), "%s: foreign situations are at most half the desk (%d of %d)" % [key, foreign, total])
		t.equal(int(runs[key]["invalid"]), 0, "%s: every default leaves a valid state" % key)


func _test_each_strategy_keeps_the_pace(t, runs: Dictionary) -> void:
	for strategy in STRATEGIES:
		var total := 0
		for seed in SEEDS:
			total += int(runs["%s/%d" % [strategy, seed]]["total"])
		var per_five := float(total) * 60.0 / float(MONTHS * SEEDS.size())
		t.truth(per_five >= ARRIVALS_PER_FIVE_YEARS[0] and per_five <= ARRIVALS_PER_FIVE_YEARS[1], "%s: about twenty decisions in five years across the seeds (%.1f)" % [strategy, per_five])


func _test_seeds_write_different_foreign_desks(t, runs: Dictionary) -> void:
	var seen := {}
	for seed in SEEDS:
		seen[String(runs["neutral/%d" % seed]["signature"])] = true
	t.truth(seen.size() == SEEDS.size(), "every seed writes its own record of decisions (%d of %d)" % [seen.size(), SEEDS.size()])


func _initialize() -> void:
	var t = TestSupportScript.new()
	var runs := {}
	for strategy in STRATEGIES:
		for seed in SEEDS:
			runs["%s/%d" % [strategy, seed]] = _journey(seed, strategy)
	_test_every_foreign_situation_happens_somewhere(t, runs)
	_test_foreign_affairs_do_not_crowd_the_desk(t, runs)
	_test_each_strategy_keeps_the_pace(t, runs)
	_test_seeds_write_different_foreign_desks(t, runs)
	quit(t.finish())
