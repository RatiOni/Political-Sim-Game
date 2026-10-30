extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const FiscalJourneys = preload("res://tests/native/test_fiscal_journeys.gd")
const SEEDS := [919191, 31, 424242, 7, 1993, 2718]
const MONTHS := 240
const WORLD_SIZE := 30
const DIGEST_CAP := 20
const DIGEST_MEAN_CAP := 8.0
const MAX_ACTIONS_PER_COUNTRY_YEAR := 4
const MIN_HOSTILE_MOVES := 40
const MAX_WORLD_GDP_MULTIPLE := 12.0
const MIN_WORLD_GDP_MULTIPLE := 0.1
const HOSTILE_OUTCOMES := ["undermined", "condemned", "shelved"]


static func _state(seed: int) -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": seed})
	state.rng = SimRng.from_seed(seed)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	return state


static func _bad(v: float, lo: float, hi: float) -> bool:
	return not is_finite(v) or v < lo or v > hi


static func _unbounded(state: GameState, start_gdp: Dictionary) -> Array:
	var out: Array = []
	for c in state.world:
		var e := c.economy
		var multiple := e.gdp / float(start_gdp[c.id])
		if _bad(c.stability, 0.0, 1.0) or _bad(c.civil_war_risk, 0.0, 1.0) \
				or _bad(multiple, MIN_WORLD_GDP_MULTIPLE, MAX_WORLD_GDP_MULTIPLE) \
				or _bad(e.unemployment, 0.0, 1.0) or _bad(e.inflation, -0.5, 1.0) or _bad(e.growth_rate, -0.5, 0.5) \
				or _bad(e.public_debt_pct, 0.0, 5.0):
			out.append(c.id)
		for other in c.relations:
			var rel: Country.BilateralRelation = c.relations[other]
			if _bad(rel.score, -1.0, 1.0) or _bad(rel.trade_volume, 0.0, DiplomacySim.TRADE_CEILING):
				out.append("%s-%s" % [c.id, other])
	return out


static func _journey(seed: int) -> Dictionary:
	var state := _state(seed)
	var start_gdp := {}
	for c in state.world:
		start_gdp[c.id] = c.economy.gdp
	var acted := {}
	var actions := {}
	var hostile := 0
	var on_player := 0
	var peak_digest := 0
	var digest_total := 0
	var unbounded: Array = []
	var invalid := 0
	var busiest_year := 0
	for m in range(MONTHS):
		FiscalJourneys.steady_budget(state)
		NativeGameScript.next_month(state)
		peak_digest = maxi(peak_digest, state.monthly_digest.size())
		digest_total += state.monthly_digest.size()
		for c in state.world:
			var last := int(c.plan.get("last_acted_turn", -1))
			if last >= 0 and last != int(acted.get(c.id, -1)):
				acted[c.id] = last
				var year_key := "%s/%d" % [c.id, m / 12]
				actions[year_key] = int(actions.get(year_key, 0)) + 1
				busiest_year = maxi(busiest_year, int(actions[year_key]))
				if String(c.plan.get("last_outcome", "")) in HOSTILE_OUTCOMES:
					hostile += 1
		for bad in _unbounded(state, start_gdp):
			if not unbounded.has(bad):
				unbounded.append(bad)
		if m % 12 == 11 and not StateValidator.validate(state).is_empty():
			invalid += 1
	var total := 0
	for k in actions:
		total += int(actions[k])
	return {"actions": total, "busiest_year": busiest_year, "hostile": hostile,
		"pressed": state.foreign.hostile_log.size(), "peak_digest": peak_digest,
		"mean_digest": float(digest_total) / float(MONTHS), "unbounded": unbounded, "invalid": invalid,
		"world": state.world.size(), "player_gdp": state.country.economy.gdp, "approval": state.player.approval,
		"outcomes": _outcome_counts(state)}


static func _outcome_counts(state: GameState) -> Dictionary:
	var out := {}
	for c in state.world:
		var o := String(c.plan.get("last_outcome", ""))
		out[o] = int(out.get(o, 0)) + 1
	return out


func _initialize() -> void:
	var t = TestSupportScript.new()
	for seed in SEEDS:
		var r := _journey(seed)
		print("journey %d: %s" % [seed, r])
		t.equal(int(r["world"]), WORLD_SIZE, "seed %d: all thirty foreign states are still in the world" % seed)
		t.equal(r["unbounded"], [], "seed %d: every country and relationship stays finite and bounded" % seed)
		t.equal(int(r["invalid"]), 0, "seed %d: the state validates every year" % seed)
		t.truth(is_finite(float(r["player_gdp"])) and float(r["player_gdp"]) > 0.0, "seed %d: Ardenia's economy stays finite" % seed)
		var expected_floor := WORLD_SIZE * (MONTHS / 12) * 2
		t.truth(int(r["actions"]) >= expected_floor, "seed %d: the world keeps acting (%d plans carried out)" % [seed, r["actions"]])
		t.truth(int(r["busiest_year"]) <= MAX_ACTIONS_PER_COUNTRY_YEAR, "seed %d: no country acts more than %d times a year (%d)" % [seed, MAX_ACTIONS_PER_COUNTRY_YEAR, r["busiest_year"]])
		t.truth(int(r["hostile"]) >= MIN_HOSTILE_MOVES, "seed %d: hostile moves happen (%d)" % [seed, r["hostile"]])
		t.truth(int(r["pressed"]) > 0, "seed %d: someone presses Ardenia" % seed)
		t.truth(int(r["peak_digest"]) <= DIGEST_CAP, "seed %d: no month's report runs past %d lines (%d)" % [seed, DIGEST_CAP, r["peak_digest"]])
		t.truth(float(r["mean_digest"]) <= DIGEST_MEAN_CAP, "seed %d: the average month stays readable (%.1f lines)" % [seed, r["mean_digest"]])
	quit(t.finish())
