extends SceneTree

## Standalone headless test for the civil-war gauge (CrisisSim).
## Run via:
##   Godot --headless --path godot --script res://tests/native/test_crisis.gd
##
## Intended behaviour: civil-war risk is a deterministic reading of how close
## the state is to breaking — never rolled; the gauge chases that reading
## faster than ordinary politics move; it boils over only past a high bar and
## clears only well below it, so a war is hard to end; a war costs every month
## it lasts but is never a game over; an insurgency raises the temperature but
## cannot start a war by itself, and fades unless something keeps feeding it;
## the eight world countries live under the same dynamics.

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")


static func _state() -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "contextual", "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	return state


static func _break_the_state(state: GameState) -> void:
	state.stability_value = 0.05
	for f in state.country.factions:
		if not f.in_coalition:
			f.loyalty = -1.0
			f.power = 1.0
		else:
			f.in_coalition = false
	state.insurgency_pressure = 1.0


# ── The reading ──────────────────────────────────────────────────────────

func _test_a_calm_country_reads_low(t) -> void:
	var state := _state()
	var reading := CrisisSim.target_risk(state)
	t.truth(reading < CrisisSim.WAR_THRESHOLD * 0.6, "an ordinary Ardenian government is far from civil war (%.2f)" % reading)


func _test_a_broken_state_reads_past_the_threshold(t) -> void:
	var state := _state()
	_break_the_state(state)
	t.truth(CrisisSim.target_risk(state) >= CrisisSim.WAR_THRESHOLD,
		"a state with no authority, no majority and armed enemies reads past the threshold")


func _test_the_breakdown_explains_the_reading(t) -> void:
	var state := _state()
	_break_the_state(state)
	var total := 0.0
	for v in CrisisSim.breakdown(state).values():
		total += float(v)
	t.near(minf(1.0, total), CrisisSim.target_risk(state), 1e-9, "the named components add up to the reading")


func _test_insurgency_alone_cannot_start_a_war(t) -> void:
	var state := _state()
	var calm := CrisisSim.target_risk(state)
	state.insurgency_pressure = 1.0
	var hot := CrisisSim.target_risk(state)
	t.truth(hot > calm, "an insurgency raises the temperature")
	t.truth(hot < CrisisSim.WAR_THRESHOLD, "but men in the hills do not by themselves start a civil war (%.2f)" % hot)


# ── The gauge ────────────────────────────────────────────────────────────

func _test_the_gauge_chases_its_reading(t) -> void:
	var state := _state()
	_break_the_state(state)
	state.civil_war_risk = 0.0
	CrisisSim.monthly(state)
	var one := state.civil_war_risk
	t.truth(one > 0.0 and one < CrisisSim.target_risk(state), "one month moves the gauge part of the way")
	for _i in range(6):
		CrisisSim.monthly(state)
	t.truth(state.civil_war_risk > one, "and it keeps climbing while the causes remain")


func _test_war_breaks_out_past_the_threshold_and_is_hard_to_end(t) -> void:
	var state := _state()
	state.civil_war_risk = CrisisSim.WAR_THRESHOLD + 0.01
	_break_the_state(state)
	CrisisSim.monthly(state)
	t.truth(state.civil_war, "a gauge past the threshold latches civil war")
	t.truth(state.country.in_civil_war, "and the country is marked as at war")
	state.civil_war_risk = (CrisisSim.WAR_THRESHOLD + CrisisSim.PEACE_THRESHOLD) / 2.0
	var calm := _state()
	state.stability_value = calm.stability_value
	state.insurgency_pressure = 0.0
	state.country.factions = calm.country.factions
	CrisisSim.monthly(state)
	t.truth(state.civil_war, "a war does not end just because risk dips below the outbreak line")
	state.civil_war_risk = CrisisSim.PEACE_THRESHOLD - 0.05
	CrisisSim.monthly(state)
	t.truth(not state.civil_war and not state.country.in_civil_war, "it ends only once risk falls well below it")


func _test_a_war_costs_every_month_but_is_no_game_over(t) -> void:
	var state := _state()
	_break_the_state(state)
	state.civil_war = true
	state.country.in_civil_war = true
	state.civil_war_risk = 0.95
	state.player.political_capital = 40.0
	var gdp0 := state.country.economy.gdp
	var approval0 := state.player.approval
	CrisisSim.monthly(state)
	t.truth(state.country.economy.gdp < gdp0, "the war shrinks the economy")
	t.truth(state.player.approval < approval0, "costs the government approval")
	t.truth(state.player.political_capital < 40.0, "and political capital")
	for _i in range(120):
		CrisisSim.monthly(state)
	t.truth(state.stability_value > 0.0 and state.player.political_capital >= 0.0,
		"ten years of war leave a battered state, not a broken game")


# ── Insurgency fades unless fed ──────────────────────────────────────────

func _test_an_unfed_insurgency_fades(t) -> void:
	var state := _state()
	state.insurgency_pressure = 0.30
	for _i in range(6):
		CrisisSim.monthly(state)
	t.truth(state.insurgency_pressure < 0.30, "an insurgency nothing feeds loses men every month")
	for _i in range(24):
		CrisisSim.monthly(state)
	t.near(state.insurgency_pressure, 0.0, 1e-9, "and eventually comes down from the hills")


# ── The world ────────────────────────────────────────────────────────────

func _test_world_countries_live_under_the_same_dynamics(t) -> void:
	var state := _state()
	var c: Country = state.world[0]
	c.stability = 0.02
	for f in c.factions:
		f.loyalty = -1.0
		f.power = 1.0
	c.civil_war_risk = CrisisSim.WAR_THRESHOLD + 0.01
	var gdp0 := c.economy.gdp
	CrisisSim.monthly(state)
	t.truth(c.in_civil_war, "a broken foreign state falls into civil war")
	CrisisSim.monthly(state)
	t.truth(c.economy.gdp < gdp0, "and its war costs it too")


func _test_neighbours_at_war_are_reported(t) -> void:
	var state := _state()
	var c: Country = state.world[0]
	c.stability = 0.02
	for f in c.factions:
		f.loyalty = -1.0
		f.power = 1.0
	c.civil_war_risk = CrisisSim.WAR_THRESHOLD + 0.01
	var notes := CrisisSim.monthly(state)
	var told := false
	for line in notes:
		if line.contains(c.name):
			told = true
	t.truth(told, "the monthly report names a neighbour that has fallen into civil war")


# ── Persistence ──────────────────────────────────────────────────────────

func _test_the_gauge_survives_save_and_reload(t) -> void:
	var state := _state()
	state.civil_war_risk = 0.61
	state.civil_war = true
	state.world[0].civil_war_risk = 0.33
	var copy := GameState.from_dict(state.to_dict())
	t.near(copy.civil_war_risk, 0.61, 1e-9, "the gauge round-trips")
	t.truth(copy.civil_war, "so does an ongoing war")
	t.near(copy.world[0].civil_war_risk, 0.33, 1e-9, "and the world's gauges")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_a_calm_country_reads_low(t)
	_test_a_broken_state_reads_past_the_threshold(t)
	_test_the_breakdown_explains_the_reading(t)
	_test_insurgency_alone_cannot_start_a_war(t)
	_test_the_gauge_chases_its_reading(t)
	_test_war_breaks_out_past_the_threshold_and_is_hard_to_end(t)
	_test_a_war_costs_every_month_but_is_no_game_over(t)
	_test_an_unfed_insurgency_fades(t)
	_test_world_countries_live_under_the_same_dynamics(t)
	_test_neighbours_at_war_are_reported(t)
	_test_the_gauge_survives_save_and_reload(t)
	quit(t.finish())
