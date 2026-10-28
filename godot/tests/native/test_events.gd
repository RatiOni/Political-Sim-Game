extends SceneTree

## Standalone headless test for situations: EventsSim, EventActions and the
## shared EffectBundle.
## Run via:
##   Godot --headless --path godot --script res://tests/native/test_events.gd
##
## Checks intended behaviour: content integrity (every event has an ungated
## default; arcs without handlers never fire); pacing (quiet opening, one
## unprompted arrival a month, a capped queue); determinism and reload
## continuation; choices apply once with atomic refusals; looking away
## decides by default; follow-ups arrive on schedule even into a full queue;
## roles resolve to the plainest voice; diplomatic events stay about the
## country they named; persistence and validation.

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")


static func _config(seed: int = 424242, role: String = "contextual") -> Dictionary:
	return {"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": seed}


static func _state(seed: int = 424242, role: String = "contextual") -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), _config(seed, role))
	state.rng = SimRng.from_seed(seed)
	return state


## Advances only the situation clock: one monthly close of EventsSim.
static func _month(state: GameState) -> Array[String]:
	state.turn += 1
	return EventsSim.monthly(state)


static func _arrivals(notes: Array[String]) -> int:
	var n := 0
	for line in notes:
		if line.begins_with("A new situation"):
			n += 1
	return n


static func _force(state: GameState, event_id: String, target := "") -> Situation:
	var s := Situation.new()
	s.event_id = event_id
	s.arrived_turn = state.turn
	s.deadline_turn = state.turn + EventsSim.DECISION_WINDOW_MONTHS
	s.target_country_id = target
	state.pending_situations.append(s)
	return s


static func _faction(state: GameState, id: String) -> Faction:
	for f in state.country.factions:
		if f.id == id:
			return f
	return null


# ── Content ──────────────────────────────────────────────────────────────

func _test_catalog_integrity(t) -> void:
	var events := EventsSim.catalog()
	t.equal(events.size(), 46, "all 46 authored events load")
	var defaults_ok := true
	var gated_default := ""
	for e in events:
		var default := EventsSim.option_by_id(e, String(e.get("default_option_id", "")))
		if default.is_empty():
			defaults_ok = false
		elif default.get("requires", null) != null:
			gated_default = String(e["id"])
	t.truth(defaults_ok, "every event has a default option to fall back on")
	t.equal(gated_default, "", "no default option is gated (a lapse must always be possible)")
	var playable := events.size() - EventsSim.unplayable_events().size()
	t.truth(playable >= 20, "at least 20 events are fully playable now (%d)" % playable)
	t.truth("vasca_stirs" in EventsSim.unplayable_events(), "arcs without consequence handlers are held back")
	t.truth(not ("labour_unrest_spreads" in EventsSim.unplayable_events()), "ordinary situations are playable")


func _test_no_unnamed_rules_remain(t) -> void:
	var bad := []
	for e in EventsSim.catalog():
		if String(e.get("condition", "")) == "<lambda>":
			bad.append(e["id"])
		for o in e.get("options", []):
			if o.get("requires", null) is String:
				bad.append("%s/%s" % [e["id"], o["id"]])
	t.equal(bad, [], "no condition or gate is an unnamed placeholder")


# ── Pacing ───────────────────────────────────────────────────────────────

func _test_quiet_opening(t) -> void:
	var state := _state()
	var arrivals := 0
	for _i in range(EventsSim.QUIET_OPENING_MONTHS):
		arrivals += _arrivals(_month(state))
	t.equal(arrivals, 0, "a new government gets its first months without a crisis")


func _test_at_most_one_unprompted_arrival_a_month_and_a_capped_queue(t) -> void:
	var state := _state(7)
	var most := 0
	var longest := 0
	var total := 0
	for _i in range(60):
		var n := _arrivals(_month(state))
		most = maxi(most, n)
		total += n
		longest = maxi(longest, state.pending_situations.size())
	t.truth(most <= 1, "never more than one unprompted situation in a month")
	t.truth(longest <= EventsSim.MAX_PENDING, "the queue never exceeds %d" % EventsSim.MAX_PENDING)
	t.truth(total >= 5, "but five years is not uneventful (%d situations)" % total)


func _test_opposition_never_receives_government_business(t) -> void:
	var state := _state(11, "opposition")
	t.truth(not state.player.in_government, "sanity: opposition campaign")
	var wrong := ""
	for _i in range(60):
		_month(state)
		for s in state.pending_situations:
			if String(EventsSim.event_by_id(s.event_id).get("audience", "")) == "government":
				wrong = s.event_id
		state.pending_situations.clear()
	t.equal(wrong, "", "an opposition leader is never handed a government decision")


# ── Determinism ──────────────────────────────────────────────────────────

func _test_same_seed_same_story_and_reload_continues_it(t) -> void:
	var a := _state(99)
	var b := _state(99)
	var log_a: Array = []
	var log_b: Array = []
	for _i in range(12):
		log_a.append(_month(a))
		log_b.append(_month(b))
	t.equal(log_a, log_b, "the same seed tells the same story")
	var reloaded := GameState.from_dict(a.to_dict())
	var cont_a: Array = []
	var cont_r: Array = []
	for _i in range(24):
		cont_a.append(_month(a))
		cont_r.append(_month(reloaded))
	t.equal(cont_r, cont_a, "a reloaded campaign continues exactly as it would have")


# ── Choosing ─────────────────────────────────────────────────────────────

func _test_choice_applies_once_and_is_paid_for(t) -> void:
	var state := _state()
	state.player.political_capital = 50.0
	_force(state, "labour_unrest_spreads")
	var labour := EffectBundle.resolve_faction(state, "@labour")
	var loyalty0 := labour.loyalty
	var mods0 := state.modifiers.size()
	var r := EventActions.resolve(state, "labour_unrest_spreads", "crackdown")
	t.truth(r.get("ok", false), "the crackdown can be ordered")
	t.near(state.player.political_capital, 42.0, 1e-9, "and costs its 8 political capital")
	t.near(labour.loyalty, loyalty0 - 0.15, 1e-9, "labour's voice turns against the government")
	t.equal(state.modifiers.size(), mods0 + 1, "the lingering public reaction is attached")
	t.equal(state.pending_situations.size(), 0, "the situation leaves the queue")
	t.equal(state.event_history[-1], {"event_id": "labour_unrest_spreads", "option_id": "crackdown",
		"turn": state.turn, "lapsed": false}, "and the decision is on the record")
	var again := EventActions.resolve(state, "labour_unrest_spreads", "crackdown")
	t.truth(not again.get("ok", true), "a decided situation cannot be decided twice")


func _test_refusals_change_nothing(t) -> void:
	var state := _state()
	state.player.political_capital = 3.0
	_force(state, "labour_unrest_spreads")
	var before := state.to_dict()
	var poor := EventActions.resolve(state, "labour_unrest_spreads", "negotiate")
	t.truth(not poor.get("ok", true) and String(poor["error"]).contains("political capital"),
		"an unaffordable choice is refused with the reason")
	var bogus := EventActions.resolve(state, "labour_unrest_spreads", "nonsense")
	t.truth(not bogus.get("ok", true), "an unknown option is refused")
	var absent := EventActions.resolve(state, "bank_run", "x")
	t.truth(not absent.get("ok", true), "a situation that is not waiting is refused")
	t.equal(state.to_dict(), before, "and none of those refusals changed anything")


func _test_background_gates_name_the_requirement(t) -> void:
	var state := _state()
	state.player.political_capital = 100.0
	_force(state, "bank_run")
	var option := EventsSim.option_by_id(EventsSim.event_by_id("bank_run"), "stake_reputation")
	t.truth(EventActions.option_reason(state, option).contains("economist"),
		"a background-only choice says which background it needs")
	state.campaign_meta["background"] = "economist"
	t.equal(EventActions.option_reason(state, option), "", "and opens for that leader")


# ── Looking away ─────────────────────────────────────────────────────────

func _test_an_ignored_situation_decides_itself(t) -> void:
	var state := _state()
	state.turn = 10
	_force(state, "labour_unrest_spreads")
	var notes: Array[String] = []
	for _i in range(EventsSim.DECISION_WINDOW_MONTHS + 1):
		notes.append_array(_month(state))
		state.pending_situations = state.pending_situations.filter(func(s): return s.event_id == "labour_unrest_spreads")
	var lapsed := state.event_history.filter(func(h): return h["event_id"] == "labour_unrest_spreads")
	t.equal(lapsed.size(), 1, "after the decision window the situation is settled")
	if lapsed.size() == 1:
		t.equal(lapsed[0]["option_id"], "ignore", "by its default option")
		t.truth(lapsed[0]["lapsed"], "and the record shows nobody chose it")
	var told := false
	for line in notes:
		if line.contains("settled by default"):
			told = true
	t.truth(told, "the monthly report tells the player it happened")


# ── Follow-ups ───────────────────────────────────────────────────────────

func _test_follow_up_arrives_on_schedule_even_into_a_full_queue(t) -> void:
	var state := _state()
	state.turn = 20
	var event := EventsSim.event_by_id("strike_wave")
	var option := EventsSim.option_by_id(event, "hold_firm").duplicate(true)
	t.truth(option.get("follow_up", null) is Dictionary, "sanity: holding firm against strikes can lead somewhere")
	if not (option.get("follow_up", null) is Dictionary):
		return
	option["follow_up"]["chance"] = 1.0
	var situation := _force(state, "strike_wave")
	state.pending_situations.erase(situation)
	EventsSim.apply_option(state, event, option, situation, false)
	t.equal(state.scheduled_events.size(), 1, "the consequence is set in motion")
	var due := int(state.scheduled_events[0]["due_turn"])
	for id in ["bank_run", "bumper_harvest", "media_empire"]:
		_force(state, id)
	while state.turn < due:
		_month(state)
	var arrived := state.pending_situations.any(func(s): return s.event_id == String(option["follow_up"]["event_id"]))
	t.truth(arrived, "and arrives when due, even though the queue was full")


# ── Roles and targets ────────────────────────────────────────────────────

func _test_roles_resolve_to_the_plainest_voice(t) -> void:
	var state := _state()
	t.equal(EffectBundle.resolve_faction(state, "@labour").id, "workers_front",
		"of two labour parties, labour's furthest voice speaks for it")
	t.equal(EffectBundle.resolve_faction(state, "@nationalist").id, "national_conservatives", "nationalists resolve")
	var business := EffectBundle.resolve_faction(state, "@business")
	t.truth(business != null and business.ideology.economic > 0.0,
		"with no business party, the most pro-market faction speaks for business")
	t.equal(EffectBundle.resolve_faction(state, "@establishment"), null,
		"a role nobody holds and with no axis resolves to nobody, not to a wrong party")
	t.equal(EffectBundle.resolve_faction(state, "liberal_democrats").id, "liberal_democrats", "literal ids still work")


func _test_diplomatic_event_stays_about_its_country(t) -> void:
	var state := _state()
	var worst := ""
	var worst_score := INF
	for key in state.country.relations:
		var rel: Country.BilateralRelation = state.country.relations[key]
		if rel.score < worst_score:
			worst = key
			worst_score = rel.score
	var event := EventsSim.event_by_id("border_incident")
	var notes: Array[String] = []
	EventsSim._arrive(state, event, "", notes)
	var situation: Situation = state.pending_situations[-1]
	t.equal(situation.target_country_id, worst, "a border incident is with the neighbour we get on worst with")
	state.player.political_capital = 100.0
	var rel: Country.BilateralRelation = state.country.relations[worst]
	var before := rel.score
	EventActions.resolve(state, "border_incident", "protest_formally")
	t.near(rel.score, clampf(before - 0.04, -1.0, 1.0), 1e-9, "and the protest lands on that same country")


# ── Persistence and validation ───────────────────────────────────────────

func _test_situations_survive_save_and_reload(t) -> void:
	var state := _state()
	state.turn = 5
	_force(state, "bank_run", "krasova")
	state.scheduled_events.append({"event_id": "general_strike", "due_turn": 9, "target_country_id": ""})
	state.event_fire_history["bank_run"] = 5
	state.event_history.append({"event_id": "x", "option_id": "y", "turn": 4, "lapsed": true})
	var copy := GameState.from_dict(state.to_dict())
	t.equal(copy.pending_situations.size(), 1, "waiting situations survive a reload")
	t.equal(copy.pending_situations[0].to_dict(), state.pending_situations[0].to_dict(), "with their deadline and target")
	t.equal(copy.scheduled_events, state.scheduled_events, "consequences in motion survive")
	t.equal(copy.event_fire_history, state.event_fire_history, "so do cooldowns")
	t.equal(copy.event_history, state.event_history, "and the record of decisions")


func _test_validator_rejects_impossible_situations(t) -> void:
	var state := _state()
	t.equal(StateValidator.validate(state).size(), 0, "sanity: a fresh campaign is valid")
	_force(state, "no_such_event")
	t.truth(StateValidator.validate(state).size() > 0, "a situation naming no real event is rejected")
	state.pending_situations.clear()
	_force(state, "bank_run")
	_force(state, "bank_run")
	t.truth(StateValidator.validate(state).size() > 0, "so is the same situation waiting twice")


# ── Through the real game ────────────────────────────────────────────────

func _test_situations_reach_the_player_through_the_game(t) -> void:
	var game = NativeGameScript.new()
	root.add_child(game)
	game.new_campaign(_config(31))
	var seen := false
	var reported := false
	for _day in range(400):
		var r: Dictionary = game.advance_day()
		if not r.get("snapshot", {}).get("situations", []).is_empty():
			seen = true
		for line in game._state.monthly_digest:
			if line.begins_with("A new situation"):
				reported = true
		if seen and reported:
			break
	t.truth(seen, "within a year a situation reaches the player's snapshot")
	t.truth(reported, "and the monthly report announces it")
	if seen:
		var row: Dictionary = game.snapshot()["situations"][0]
		var choice := ""
		for o in row["options"]:
			if o["eligible"]:
				choice = o["id"]
				break
		game._state.player.political_capital = 200.0
		var done: Dictionary = game.resolve_situation(row["event_id"], choice)
		t.truth(done.get("ok", false), "and the player can decide it through the game (%s)" % done.get("error", ""))
	game.queue_free()


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_catalog_integrity(t)
	_test_no_unnamed_rules_remain(t)
	_test_quiet_opening(t)
	_test_at_most_one_unprompted_arrival_a_month_and_a_capped_queue(t)
	_test_opposition_never_receives_government_business(t)
	_test_same_seed_same_story_and_reload_continues_it(t)
	_test_choice_applies_once_and_is_paid_for(t)
	_test_refusals_change_nothing(t)
	_test_background_gates_name_the_requirement(t)
	_test_an_ignored_situation_decides_itself(t)
	_test_follow_up_arrives_on_schedule_even_into_a_full_queue(t)
	_test_roles_resolve_to_the_plainest_voice(t)
	_test_diplomatic_event_stays_about_its_country(t)
	_test_situations_survive_save_and_reload(t)
	_test_validator_rejects_impossible_situations(t)
	_test_situations_reach_the_player_through_the_game(t)
	quit(t.finish())
