extends SceneTree

## Standalone headless test for Vetrenka, the frozen conflict.
## Run via:
##   Godot --headless --path godot --script res://tests/native/test_vetrenka_arc.gd
##
## Intended behaviour: the line of contact produces recurring friction that
## resolves nothing but is counted; only after enough incidents does the
## once-only crossroads open, with three roads — peace talks, an offensive,
## or letting the line harden. Talks succeed for a government with standing,
## an offensive for one with a real army; the hardened line is worn quietly
## only by a secure government. Six endings, each recorded and each changing
## the region itself; and once ended, nothing reopens.

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")

const ARC := ["vetrenka_friction", "vetrenka_crossroads", "vetrenka_settled", "vetrenka_talks_fail",
	"vetrenka_retaken", "vetrenka_rout", "vetrenka_partition", "vetrenka_normalised", "vetrenka_backlash"]


static func _state(seed: int = 424242, role: String = "contextual") -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": seed})
	state.rng = SimRng.from_seed(seed)
	state.player.political_capital = 500.0
	state.turn = 12
	return state


static func _decide(state: GameState, event_id: String, option_id: String) -> Dictionary:
	var s := Situation.new()
	s.event_id = event_id
	s.arrived_turn = state.turn
	s.deadline_turn = state.turn + EventsSim.DECISION_WINDOW_MONTHS
	state.pending_situations.append(s)
	return EventActions.resolve(state, event_id, option_id)


static func _scheduled(state: GameState, event_id: String) -> Dictionary:
	for row in state.scheduled_events:
		if row["event_id"] == event_id:
			return row
	return {}


## Share of 60 seeded campaigns, each first adjusted by `configure`, in which
## choosing `option_id` sets `success_id` in motion.
static func _rate(configure: Callable, event_id: String, option_id: String, success_id: String) -> float:
	var wins := 0
	for seed in range(60):
		var state := _state(5000 + seed)
		configure.call(state)
		_decide(state, event_id, option_id)
		if not _scheduled(state, success_id).is_empty():
			wins += 1
	return wins / 60.0


static func _set_security(state: GameState, quality: float, stability: float) -> void:
	for m in state.ministers:
		if m.portfolio in ["Interior", "Defense"]:
			m.competence = quality
			m.loyalty = quality
			m.trait_id = ""
	state.stability_value = stability


# ── Friction ─────────────────────────────────────────────────────────────

func _test_the_whole_arc_is_playable(t) -> void:
	var held := EventsSim.unplayable_events()
	var missing: Array = []
	for id in ARC:
		if id in held:
			missing.append(id)
	t.equal(missing, [], "every step of the Vetrenka arc can now fire")


func _test_friction_is_counted_whatever_the_answer(t) -> void:
	var state := _state()
	for option in ["absorb", "protest", "respond"]:
		_decide(state, "vetrenka_friction", option)
	t.equal(int(state.campaign_meta.get("vetrenka_incidents", 0)), 3, "every incident on the line is counted, however it is answered")
	t.truth(not state.campaign_meta.has("vetrenka_status"), "and none of them changes the status of the conflict")


func _test_responding_in_kind_raises_pressure(t) -> void:
	var state := _state()
	_decide(state, "vetrenka_friction", "respond")
	t.near(state.insurgency_pressure, 0.06, 1e-9, "answering fire with fire adds insurgency pressure")


func _test_the_crossroads_waits_for_enough_incidents(t) -> void:
	var state := _state()
	t.truth(EventsSim.condition_met(state, "vetrenka_friction_due"), "friction can occur while the conflict is frozen")
	state.campaign_meta["vetrenka_incidents"] = Arcs.FRICTION_BEFORE_CROSSROADS - 1
	t.truth(not EventsSim.condition_met(state, "vetrenka_crossroads_ready"), "the crossroads stays shut before enough incidents")
	state.campaign_meta["vetrenka_incidents"] = Arcs.FRICTION_BEFORE_CROSSROADS
	t.truth(EventsSim.condition_met(state, "vetrenka_crossroads_ready"), "and opens once the line has cost enough")
	var opp := _state(424242, "opposition")
	opp.campaign_meta["vetrenka_incidents"] = 9
	t.truth(not EventsSim.condition_met(opp, "vetrenka_friction_due"), "an opposition leader holds no line")


# ── The three roads ──────────────────────────────────────────────────────

static func _standing_high(s: GameState) -> void:
	s.player.approval = 0.70
	s.stability_value = 0.70


static func _standing_low(s: GameState) -> void:
	s.player.approval = 0.35
	s.stability_value = 0.35


static func _standing_typical(s: GameState) -> void:
	s.player.approval = 0.49
	s.stability_value = 0.48


static func _army_strong(s: GameState) -> void:
	_set_security(s, 0.95, 0.85)


static func _army_weak(s: GameState) -> void:
	_set_security(s, 0.25, 0.30)


func _test_talks_favour_a_government_with_standing(t) -> void:
	var strong := _rate(_standing_high, "vetrenka_crossroads", "settlement", "vetrenka_settled")
	var weak := _rate(_standing_low, "vetrenka_crossroads", "settlement", "vetrenka_settled")
	t.truth(strong > weak + 0.3, "a government with standing can sell a compromise (%.2f vs %.2f)" % [strong, weak])


func _test_a_typical_government_is_not_hopeless_at_talks(t) -> void:
	var typical := _rate(_standing_typical, "vetrenka_crossroads", "settlement", "vetrenka_settled")
	t.truth(typical > 0.40 and typical < 0.70, "an ordinary government gets a shade better than a coin flip (%.2f)" % typical)


func _test_an_offensive_needs_a_real_army(t) -> void:
	var strong := _rate(_army_strong, "vetrenka_crossroads", "reassert", "vetrenka_retaken")
	var weak := _rate(_army_weak, "vetrenka_crossroads", "reassert", "vetrenka_retaken")
	t.truth(strong > weak + 0.25, "a well-run Interior and Defense is felt on the battlefield (%.2f vs %.2f)" % [strong, weak])
	t.truth(strong <= 0.75, "but this is a war already lost once: never better than about seven in ten")


func _test_formalising_hardens_the_line(t) -> void:
	var state := _state()
	_decide(state, "vetrenka_crossroads", "formalise")
	t.equal(int(_scheduled(state, "vetrenka_partition").get("due_turn", -1)), state.turn + 2, "the line hardens in two months")


func _test_only_a_secure_government_wears_partition_quietly(t) -> void:
	var secure := _state()
	secure.player.approval = 0.80
	secure.stability_value = 0.80
	_decide(secure, "vetrenka_partition", "let_it_stand")
	t.truth(not _scheduled(secure, "vetrenka_normalised").is_empty(), "a secure government makes an unpopular thing boring")
	var shaky := _state()
	shaky.player.approval = 0.40
	shaky.stability_value = 0.40
	_decide(shaky, "vetrenka_partition", "let_it_stand")
	t.truth(not _scheduled(shaky, "vetrenka_backlash").is_empty(), "a shaky one faces a backlash")


# ── Endings ──────────────────────────────────────────────────────────────

func _test_each_ending_is_recorded_and_redraws_the_region(t) -> void:
	var cases := [
		["vetrenka_settled", "sign_it", "settled", "autonomous"],
		["vetrenka_talks_fail", "walk_away", "talks_failed", "separatist"],
		["vetrenka_retaken", "garrison", "retaken", "state"],
		["vetrenka_rout", "accept_ceasefire", "routed", "separatist"],
		["vetrenka_normalised", "say_nothing", "partitioned", "separatist"],
		["vetrenka_backlash", "ride_it_out", "partitioned_contested", "separatist"],
	]
	for c in cases:
		var state := _state()
		_decide(state, c[0], c[1])
		t.equal(state.campaign_meta.get("vetrenka_status", ""), c[2], "%s ends the conflict as '%s'" % [c[0], c[2]])
		var region: RegionState = state.regions.get("vetrenka")
		t.equal(region.control if region != null else "", c[3], "and Vetrenka is now %s" % c[3])


func _test_a_retaken_region_is_its_own_problem(t) -> void:
	var state := _state()
	_decide(state, "vetrenka_retaken", "garrison")
	t.near(state.insurgency_pressure, 0.25, 1e-9, "holding retaken ground breeds its own insurgency")


func _test_a_rout_is_a_national_shock(t) -> void:
	var state := _state()
	var stab0 := state.stability_value
	_decide(state, "vetrenka_rout", "accept_ceasefire")
	t.near(state.insurgency_pressure, 0.35, 1e-9, "a rout emboldens the separatists")
	t.near(state.stability_value, maxf(0.05, stab0 - 0.08), 1e-9, "and shakes the government")


func _test_an_ended_conflict_never_reopens(t) -> void:
	var state := _state()
	state.campaign_meta["vetrenka_incidents"] = 9
	_decide(state, "vetrenka_settled", "sign_it")
	t.truth(not EventsSim.condition_met(state, "vetrenka_friction_due"), "no more friction once the conflict has an ending")
	t.truth(not EventsSim.condition_met(state, "vetrenka_crossroads_ready"), "and no second crossroads")


func _test_the_line_hardens_by_inattention(t) -> void:
	var state := _state()
	state.player.political_capital = 0.0
	state.player.approval = 0.40
	var s := Situation.new()
	s.event_id = "vetrenka_crossroads"
	s.arrived_turn = state.turn
	s.deadline_turn = state.turn + EventsSim.DECISION_WINDOW_MONTHS
	state.pending_situations.append(s)
	# Three decision windows lapse in turn (crossroads, partition, the
	# verdict), with the 2- and 4-or-5-month delays between: about 15 months.
	for _i in range(20):
		state.turn += 1
		EventsSim.monthly(state)
	t.truth(String(state.campaign_meta.get("vetrenka_status", "")).begins_with("partitioned"),
		"a government that never engages lets the line harden (%s)" % state.campaign_meta.get("vetrenka_status", "none"))


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_the_whole_arc_is_playable(t)
	_test_friction_is_counted_whatever_the_answer(t)
	_test_responding_in_kind_raises_pressure(t)
	_test_the_crossroads_waits_for_enough_incidents(t)
	_test_talks_favour_a_government_with_standing(t)
	_test_a_typical_government_is_not_hopeless_at_talks(t)
	_test_an_offensive_needs_a_real_army(t)
	_test_formalising_hardens_the_line(t)
	_test_only_a_secure_government_wears_partition_quietly(t)
	_test_each_ending_is_recorded_and_redraws_the_region(t)
	_test_a_retaken_region_is_its_own_problem(t)
	_test_a_rout_is_a_national_shock(t)
	_test_an_ended_conflict_never_reopens(t)
	_test_the_line_hardens_by_inattention(t)
	quit(t.finish())
