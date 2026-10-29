extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")


static func _state(seed: int = 4242) -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": seed})
	state.rng = SimRng.from_seed(seed)
	BudgetSim.ensure_budget_state(state)
	HouseholdsSim.ensure_households(state)
	return state


func _test_one_sample_per_month_not_per_day(t) -> void:
	var state := _state()
	t.equal(state.economic_history.size(), 0, "a fresh campaign has no history")
	var days := 0
	var months := 0
	while months < 3:
		days += 1
		if Calendar.advance_day(state):
			NativeGameScript.close_month(state)
			months += 1
	t.truth(days > 60, "ran well over three months of days (%d)" % days)
	t.equal(state.economic_history.size(), 3, "three rollovers record exactly three samples")
	var last: RefCounted = state.economic_history[2]
	t.equal(last.turn, state.turn, "the sample carries the turn it was taken in")
	t.near(last.growth, state.country.economy.growth_rate, 1e-9, "the sample reads the settled economy")


func _test_round_trip_and_old_saves(t) -> void:
	var state := _state()
	for _i in range(5):
		NativeGameScript.next_month(state)
	var data: Variant = JSON.parse_string(JSON.stringify(state.to_dict()))
	var loaded: GameState = GameState.from_dict(data)
	t.truth(loaded != null, "a state with history loads")
	t.equal(loaded.economic_history.size(), 5, "history length survives a JSON round trip")
	t.near(loaded.economic_history[4].gdp, state.economic_history[4].gdp, 1e-6, "the newest sample survives the round trip")
	t.equal(loaded.economic_history[4].turn, state.economic_history[4].turn, "and keeps its turn")
	t.equal(typeof(loaded.economic_history[0].year), TYPE_INT, "typed ints come back as ints")
	var old: Dictionary = (JSON.parse_string(JSON.stringify(state.to_dict())) as Dictionary)
	old.erase("economic_history")
	var legacy: GameState = GameState.from_dict(old)
	t.truth(legacy != null, "an old save without the field loads")
	t.equal(legacy.economic_history.size(), 0, "and starts with an empty series")


func _test_the_series_is_bounded(t) -> void:
	var state := _state()
	for _i in range(GameState.HISTORY_RECENT_MONTHS + 12 * 25):
		NativeGameScript.next_month(state)
	var total := GameState.HISTORY_RECENT_MONTHS + 12 * 25
	var size := state.economic_history.size()
	var years := 25 + GameState.HISTORY_RECENT_MONTHS / 12 + 1
	t.truth(size <= GameState.HISTORY_RECENT_MONTHS + years, "%d months of play keep %d samples (cap %d)" % [total, size, GameState.HISTORY_RECENT_MONTHS + years])
	var h: Array = state.economic_history
	var tail := h.slice(h.size() - GameState.HISTORY_RECENT_MONTHS)
	var contiguous := true
	for i in range(1, tail.size()):
		if tail[i].turn != tail[i - 1].turn + 1:
			contiguous = false
	t.truth(contiguous, "the recent window stays monthly and contiguous")
	var older := h.slice(0, h.size() - GameState.HISTORY_RECENT_MONTHS)
	var one_per_year := true
	for i in range(1, older.size()):
		if older[i].year == older[i - 1].year:
			one_per_year = false
	t.truth(older.size() > 0 and one_per_year, "older samples are thinned to one per year (%d kept)" % older.size())
	t.equal(h[h.size() - 1].turn, state.turn, "the newest sample is always the current month")


func _test_derived_series_match_history(t) -> void:
	var state := _state()
	for _i in range(30):
		NativeGameScript.next_month(state)
	var snap: Dictionary = NativeGameScript._build_snapshot(state)
	var hist: Dictionary = snap["history"]
	t.equal((hist["economy"] as Array).size(), state.economic_history.size(), "snapshot exposes every economic sample")
	var budgets: Array = hist["budgets"]
	t.equal(budgets.size(), state.budget_history.size(), "one budget row per budget_history entry")
	for i in range(budgets.size()):
		var b: AnnualBudget = state.budget_history[i]
		t.equal(budgets[i]["year"], b.year, "budget row %d year matches" % i)
		t.near(budgets[i]["balance"], b.forecast_revenue - b.expenditure(), 1e-9, "budget row %d balance is revenue minus expenditure" % i)
	t.truth(budgets.size() > 0, "thirty months crossed at least one fiscal year")
	var elections: Array = hist["elections"]
	t.equal(elections.size(), state.election_history.size(), "one election row per election_history entry")
	var synthetic := ElectionResult.new()
	synthetic.turn = 7
	synthetic.year = 1997
	synthetic.turnout = 0.61
	synthetic.vote_share = {"a": 0.6, "b": 0.4}
	state.election_history.append(synthetic)
	var row: Dictionary = (NativeGameScript._build_snapshot(state)["history"]["elections"] as Array).back()
	t.near(row["turnout"], 0.61, 1e-9, "election turnout is exposed")
	t.equal(row["vote_share"], {"a": 0.6, "b": 0.4}, "election vote shares are exposed")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_one_sample_per_month_not_per_day(t)
	_test_round_trip_and_old_saves(t)
	_test_the_series_is_bounded(t)
	_test_derived_series_match_history(t)
	quit(t.finish())
