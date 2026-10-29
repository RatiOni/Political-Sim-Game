# International Gameplay 3: Foreign Situations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put Ardenia's foreign affairs on the player's desk as decisions: fifteen new situations (twelve standalone, three chain steps in two chains) plus a re-targeted refugee crisis in `catalogs/events.json`, each aimed at a concrete country through the relation-target mechanism, a Western energy relief path (the Concert fast-tracks the second line), a journey that builds the line and measures the payoff, and a full re-run of every calibration band.

**Architecture:** Foreign situations are ordinary catalogue events. A new `ForeignArcs` class (`sim/foreign_arcs.gd`) owns everything foreign about them: the new target sentinels and their resolution, the new trigger conditions, the consequence handlers, and three data gates that defer to the existing action layers (`EnergyActions`, `OrientationActions`, `DiplomacyActions`). `Arcs` and `EventsSim` delegate to it exactly as `Arcs` already delegates to `OppositionSim`. Two situations are not rolled: the gas supplier's threat and a failed ISF review schedule their situation as a same-month follow-up, so the decision always reaches the player while it still matters. The West relief is one persisted contract field, `GasContract.second_line_months_saved`.

**Tech Stack:** Godot 4.7.2, statically typed GDScript, headless `SceneTree` test scripts using `TestSupport`.

**Spec:** `docs/superpowers/specs/2026-10-29-international-gameplay-design.md` (this plan is delivery item 3, section 4 "Foreign situations"). Plans 1–2 as built: `docs/superpowers/plans/2026-10-29-intl-1-orientation.md`, `docs/superpowers/plans/2026-10-29-intl-2-energy.md`; their ledgers `.superpowers/sdd/2026-10-29-intl-1-orientation/progress.md` and `.superpowers/sdd/2026-10-29-intl-2-energy/progress.md` (the energy final review asked for a West-side energy relief path in this plan). The election calibration that has just landed is in `docs/godot/LIVING_WORLD.md`, section "Elections", and `.superpowers/sdd/election-recalibration-report.md`.

## Global Constraints

- `G="/d/AI Stuff/Godot/Godot_v4.7.2-stable_win64_console.exe"`. Run everything from `/d/Political Sim Game/.worktrees/godot-native-sim`.
- Every test command is `timeout 180 "$G" --headless --path godot --script res://...` and must print `NATIVE TESTS: N passed, 0 failed` with no `SCRIPT ERROR`. A script that fails to compile never quits headless, so a timeout (exit 124) with `SCRIPT ERROR` is the expected "red" for a test that references code that does not exist yet.
- Run `timeout 180 "$G" --headless --path godot --import` after adding any file, then `git add` the generated `.uid` files with it.
- The full battery runs after every task, and every line must report 0 failed with no `SCRIPT ERROR`, `EXIT` or `FAIL` line (the vertical slice prints `PASS:` lines and must exit 0). No band is pending at plan start, so no `PENDING` line is allowed:

```bash
G="/d/AI Stuff/Godot/Godot_v4.7.2-stable_win64_console.exe"
for f in godot/tests/native/test_*.gd godot/tests/native/run_contract_tests.gd godot/tests/ui/test_*.gd godot/tests/map/test_*.gd godot/scripts/tests/vertical_slice_test.gd; do
  out=$(timeout 180 "$G" --headless --path godot --script "res://${f#godot/}" 2>&1); code=$?
  echo "$f: $(echo "$out" | grep -E 'NATIVE TESTS|SCRIPT ERROR|FAIL|PENDING' | tr '\n' ' ')"
  [ $code -eq 0 ] || echo "EXIT $code: $f"
done
```

- Mutation-check every new test: break the guarded line named in the task, rerun that test file, see the named assertion fail, restore the line, rerun green. Each task lists its mutations, and they always include the boundary (`<` vs `<=` at the threshold named in the task) and the real-calendar timing (a calendar-true `NativeGame.next_month` test must fail when the situation is scheduled a month late or delivered a month early). A mutation that survives is a missing test: add it before moving on.
- No explanatory comments in new code (the owner's hard rule). No `#` comment lines, no doc comments.
- Determinism: never roll an outcome. RNG comes only from `state.rng` (the saved campaign stream). New events add candidates to the monthly arrival roll and so shift the stream for everything after them; canon tests must already be robust to stream shifts (feud on 6 seeds within 15 years, mean year-10 warmth ≤ −0.6), and no test written in this plan may assert a specific seeded trajectory that a new draw elsewhere would break. Handlers in this plan draw no RNG.
- Persistence: every new field round-trips through `SaveStore` (binary `store_var` of `to_dict`), and saves without the new data load with defaults. `StateValidator` rejects impossible values. `state_validator.gd` is at 788 lines and must stay under 800: new validation goes into its own file (`foreign_situation_validator.gd`) or into the existing `gas_validator.gd`, with at most one call line added to `state_validator.gd`.
- Tests never use save slot `godot_slice`. Each test file that saves uses its own slot named after the file and wipes `.json`, `.json.tmp` and `.json.bak` afterwards.
- UI: situations already reach the desk through `EventActions.read_model` (title, target country, options with disabled reasons). This plan adds no new widget. Nothing on the desk changes size when the state changes; the pixel UI system's colours and bar rules are untouched.
- No literal country ids anywhere in the new events or their handlers. Countries are reached only through target sentinels resolved from live state and the foreign catalog. The `ardenia_only_events` list does not change.
- Other chats commit to this branch. Stage only the files your task names (`git add <paths>`), never `git add -A` or `git add .`. After each commit, verify with `git show HEAD --stat` and `git show HEAD:<path>` that the commit holds exactly your files and your content.
- Calibration bands are never widened. Task 7 is the only task that re-measures them, by the procedure it states.
- Commit messages are conventional (`feat:`, `test:`, `docs:`) and end with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Rulings on spec gaps (binding for this plan)

1. **Targets.** The existing mechanism resolves `__coolest__` and `__most_hostile__` (both to the coldest relation) when a situation arrives, and stores it on `Situation.target_country_id`. This plan keeps that and adds eight sentinels resolved the same way and at the same moment: `__supplier__` (the gas supplier), `__rival__` (the coldest world country whose authored rival is the player), `__western__` (the Concert's anchor from `foreign_orientation.json`), `__union_anchor__` (the Union's anchor), `__in_civil_war__` (the first world country by id at war with itself), `__fragile__` (the first world country by id ripe for a coup), `__concert_foe__` (the world country coldest toward the Concert's anchor below −0.6 and not already under the player's sanctions) and `__warmest__` (the warmest relation). An event may declare `"target": "<sentinel>"`; without it the old inference from `relation_deltas` keys still applies. A follow-up keeps its parent's target.
2. **Handlers know the target.** `Arcs.run(state, handler, target := "")`; `EventsSim.apply_option` passes `situation.target_country_id`. Existing handlers ignore the argument.
3. **Gates that defer to the action layer.** `EventOption.requires` gains three keys: `{"energy_verb": v}`, `{"orientation_verb": v}`, `{"diplomacy_verb": v}`. The gate's reason is that action's own `reason_for` (including its political-capital need), so the desk shows "Requires 15 political capital." or "Relations with the supplier are too cold..." in the action's words. An option so gated carries `pc_cost` 0 because the action charges itself. `EventsSim.gate_reason` and `EventActions.option_reason` gain a `target := ""` argument. Defaults are never gated (the catalog test already enforces it).
4. **Two situations are triggered, not rolled.** When `GasSim.coerce` issues a threat and the player governs, it schedules `valve_threat` at the current turn with the supplier as target; when an ISF review fails and the player governs, `OrientationSim._isf_review` schedules `isf_review_crisis`. Follow-ups arrive the same month (`EventsSim` runs after `ForeignSim` in `close_month`), even into a full queue, and draw no RNG. Both events carry `"stale_after": 1`: a scheduled row more than one month past due is dropped instead of being delivered (a government that lost office at that month's election never inherits a stale valve).
5. **Count.** Fifteen new events: twelve standalone (valve threat, ISF review crisis, transit dispute, transit-fee windfall, Concert delegation, Union invitation, Union pressure on a member, Western aid with strings, a neighbour's coup, a sanctions coalition, an arms offer, the rival's "interests") and three chain steps in two chains (Western aid → its conditions; the Concert energy offer → its conditions, which is the West relief). The refugee flow from a neighbour's civil war already exists as `refugee_crisis`; it is re-targeted at the warring neighbour rather than duplicated. The catalog grows from 46 to 61.
6. **Effects.** New options write only their non-zero `effects` keys (`EffectBundle.apply` reads every key with a default). They never use `budget_revenue_delta` or `budget_expenditure_delta`, which `EffectBundle` makes structural; money is `one_time_debt_pct_delta` or a timed modifier. Faction effects use roles (`@labour`, `@nationalist`, `@reform`, `@business`), never faction ids.
7. **Defaults are mild.** Every calibration journey lets situations lapse, so the default of each new event is the cheap, passive answer, with no follow-up (no RNG draw on lapse) and no handler that changes more than one relation.
8. **A coup happens whichever answer the player gives.** Every option of `neighbour_coup` runs the coup first (regime to `authoritarian`, stability lifted to 0.35); the options are Ardenia's response. A country is ripe when it is not at war with itself, its stability is below 0.30, its civil-war risk is below 0.50 (so Valmora's authored civil-war start plays out first) and it is not already an autocracy.
9. **West relief.** The Concert fast-tracks the second line: accepting the offer sets `GasContract.second_line_months_saved` to 18, so the line opens 30 months after work began instead of 48. The bill does not change (the Concert brings the opening forward, not the cost down). Krasova reacts with −0.08. Six months later the Concert's conditions come due: meeting them costs 8 PC and labour goodwill; the default, stalling, halves the saving to 9 months, or, if the line is already open, costs 0.08 of the Concert anchor's warmth. Shelving the line in a gas renegotiation resets the saving to 0. The offer requires a government, a live contract, the Concert application, no Union step, and a line under construction with more than 18 months still to build.
10. **Payoff is measured A/B.** The relief journey plays the same seed twice, accepting or declining the offer. Before the decision the two runs are identical; after it the streams diverge, so per-seed outcome comparisons are made only on quantities the relief determines (opening month, Krasova gas share while one arm has the line and the other does not). Shortfall, cuts, approval and GDP are measured and recorded in `LIVING_WORLD.md`, and asserted only summed over seeds.

## Interfaces for later plans

- Plan 4 adds incident situations through the same catalogue, sentinels and gates; it can schedule a triggered situation with `ForeignArcs.schedule(state, event_id, target)`.
- Plan 4's tension can read `state.event_history` rows for the foreign events (ids in `ForeignArcs.EVENT_IDS`).

## File structure

| File | Responsibility |
|---|---|
| `godot/scripts/native/sim/foreign_arcs.gd` (new) | Target sentinels, conditions, gates, handlers and scheduling for foreign situations |
| `godot/scripts/native/sim/arcs.gd` | Delegate handlers and conditions to `ForeignArcs`; `run` takes the target |
| `godot/scripts/native/sim/events_sim.gd` | New target keys, declared targets, gate delegation, `stale_after`, pass the target to handlers |
| `godot/scripts/native/actions/event_actions.gd` | Pass the situation's target to the gate |
| `godot/scripts/native/state/foreign_situation_validator.gd` (new) | Situation and follow-up targets name real countries |
| `godot/scripts/native/state/state_validator.gd` | One call line to the new validator |
| `godot/scripts/native/sim/gas_sim.gd` | Schedule `valve_threat`; the second line's build time reads the saving |
| `godot/scripts/native/sim/orientation_sim.gd` | Schedule `isf_review_crisis` on a failed review |
| `godot/scripts/native/state/gas_contract.gd` | `second_line_months_saved` |
| `godot/scripts/native/state/gas_validator.gd` | Bounds on the saving |
| `godot/scripts/native/actions/energy_actions.gd` | Shelving resets the saving; status reads the real build time |
| `godot/data/native/catalogs/events.json` | Fifteen new events, the re-targeted refugee crisis |
| `godot/tests/native/test_foreign_situations.gd` (new) | Targets, gates, conditions, handlers, triggers, persistence, validation |
| `godot/tests/native/test_west_relief.gd` (new) | The fast-track field, the chain, and the A/B relief journey |
| `godot/tests/native/test_foreign_situation_journeys.gd` (new) | Twenty-year coverage, pacing and boundedness of foreign situations |
| `godot/tests/native/test_events.gd` | Catalog count; target and gate plumbing regressions |
| `godot/tests/native/test_gas_contract.gd` | Pinned int field list gains the new field |
| `docs/godot/LIVING_WORLD.md` | "Foreign situations" section; known gap line updated; calibration record |

---

### Task 1: Target sentinels, data gates, triggered scheduling and target validation

**Files:**
- Create: `godot/scripts/native/sim/foreign_arcs.gd`
- Create: `godot/scripts/native/state/foreign_situation_validator.gd`
- Modify: `godot/scripts/native/sim/arcs.gd` (`has_handler`, `run`, `condition_met`)
- Modify: `godot/scripts/native/sim/events_sim.gd` (`TARGET_KEYS`, `is_playable`, `gate_reason`, `_deliver_follow_ups`, `_diplomatic_target`, `apply_option`)
- Modify: `godot/scripts/native/actions/event_actions.gd` (`resolve`, `option_reason`, `read_model`)
- Modify: `godot/scripts/native/state/state_validator.gd:753` (one call line after `GasValidator.validate`)
- Test: `godot/tests/native/test_foreign_situations.gd`

**Interfaces:**
- Consumes: `EventsSim._worst_relation`, `ForeignSim.power(id)`, `GasSim.is_active/gas`, `DiplomacySim.is_rival_of_player`, `EnergyActions.reason_for(state, verb)`, `OrientationActions.reason_for(state, verb)`, `DiplomacyActions.reason_for(state, verb, country_id)`.
- Produces:
  - `ForeignArcs.TARGETS: Array` (the eight sentinels), `ForeignArcs.HANDLERS`, `ForeignArcs.CONDITIONS`, `ForeignArcs.EVENT_IDS` (grown by Tasks 2–5).
  - `ForeignArcs.resolve_target(state: GameState, key: String) -> String` (a world country id or "").
  - `ForeignArcs.gate_reason(state: GameState, gate: Dictionary, target: String) -> String`.
  - `ForeignArcs.schedule(state: GameState, event_id: String, target: String) -> void`.
  - `ForeignArcs.run(state: GameState, handler_id: String, target: String) -> String`, `ForeignArcs.condition_met(state: GameState, rule_id: String) -> bool`.
  - `ForeignArcs.shift(state: GameState, sentinel: String, delta: float) -> void` (shift the relation with whatever the sentinel resolves to; no-op on "").
  - `Arcs.run(state, handler_id, target := "")`, `EventsSim.gate_reason(state, option, target := "")`, `EventActions.option_reason(state, option, target := "")`.
  - `ForeignSituationValidator.validate(state: GameState, errors: Array[String]) -> void`.

- [ ] **Step 1: Write the failing test**

Create `godot/tests/native/test_foreign_situations.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const SLOT := "test_foreign_situations"


static func _state(role: String = "government", seed: int = 424242) -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": seed})
	state.rng = SimRng.from_seed(seed)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	return state


static func _wipe() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := "user://saves/%s.json%s" % [SLOT, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


static func _score(state: GameState, id: String) -> float:
	return (state.country.relations[id] as Country.BilateralRelation).score


static func _set_score(state: GameState, id: String, value: float) -> void:
	DiplomacySim.shift(state, id, value - _score(state, id))


static func _force(state: GameState, event_id: String, target := "") -> Situation:
	var s := Situation.new()
	s.event_id = event_id
	s.arrived_turn = state.turn
	s.deadline_turn = state.turn + EventsSim.DECISION_WINDOW_MONTHS
	s.target_country_id = target
	state.pending_situations.append(s)
	state.event_fire_history[event_id] = state.turn
	return s


static func _rejects(t, state: GameState, fragment: String, label: String) -> void:
	var errors := StateValidator.validate(state)
	t.truth(Array(errors).any(func(e) -> bool: return String(e).contains(fragment)), label)


func _test_every_sentinel_names_a_live_country(t) -> void:
	var state := _state()
	t.equal(ForeignArcs.resolve_target(state, "__supplier__"), state.foreign.gas.supplier_id, "the supplier is the gas contract's supplier")
	t.equal(ForeignArcs.resolve_target(state, "__western__"), String(ForeignSim.power("concert")["anchor"]), "the West is the Concert's anchor")
	t.equal(ForeignArcs.resolve_target(state, "__union_anchor__"), String(ForeignSim.power("union")["anchor"]), "the Union is its anchor")
	var rival := ForeignArcs.resolve_target(state, "__rival__")
	t.truth(rival != "" and DiplomacySim.is_rival_of_player(state, state.world_country(rival)), "the rival is a country whose rival is the player")
	var warmest := ForeignArcs.resolve_target(state, "__warmest__")
	for key in state.country.relations:
		t.truth(_score(state, warmest) >= _score(state, String(key)), "nobody is warmer than the warmest (%s)" % key)
	t.equal(ForeignArcs.resolve_target(state, "__nobody__"), "", "an unknown sentinel names nobody")


func _test_the_war_and_the_coup_sentinels_read_the_world(t) -> void:
	var state := _state()
	for c in state.world:
		c.in_civil_war = false
		c.stability = 0.8
		c.civil_war_risk = 0.0
	t.equal(ForeignArcs.resolve_target(state, "__in_civil_war__"), "", "no war, no warring neighbour")
	t.equal(ForeignArcs.resolve_target(state, "__fragile__"), "", "no fragile state, no coup")
	var a := state.world_country(ForeignArcs.resolve_target(state, "__western__"))
	a.in_civil_war = true
	t.equal(ForeignArcs.resolve_target(state, "__in_civil_war__"), a.id, "a country at war with itself is found")
	a.in_civil_war = false
	a.regime_type = "parliamentary_democracy"
	a.stability = ForeignArcs.COUP_STABILITY
	t.equal(ForeignArcs.resolve_target(state, "__fragile__"), "", "at exactly the coup line a state holds")
	a.stability = ForeignArcs.COUP_STABILITY - 0.01
	t.equal(ForeignArcs.resolve_target(state, "__fragile__"), a.id, "just below it a state is ripe for a coup")
	a.civil_war_risk = ForeignArcs.COUP_MAX_WAR_RISK
	t.equal(ForeignArcs.resolve_target(state, "__fragile__"), "", "a state sliding into civil war is left to its war")
	a.civil_war_risk = 0.0
	a.regime_type = "authoritarian"
	t.equal(ForeignArcs.resolve_target(state, "__fragile__"), "", "an autocracy does not have a coup")


func _test_the_concert_foe_is_cold_to_the_west_and_unsanctioned(t) -> void:
	var state := _state()
	var west := state.world_country(ForeignArcs.resolve_target(state, "__western__"))
	for c in state.world:
		if c != west:
			DiplomacySim.shift_between(c, west, 0.5 - c.get_relation(west.id).score)
	t.equal(ForeignArcs.resolve_target(state, "__concert_foe__"), "", "no one cold to the Concert, no coalition")
	var foe: Country = null
	for c in state.world:
		if c != west and c.id != ForeignArcs.resolve_target(state, "__union_anchor__"):
			foe = c
			break
	DiplomacySim.shift_between(foe, west, ForeignArcs.CONCERT_FOE_LINE - foe.get_relation(west.id).score)
	t.equal(ForeignArcs.resolve_target(state, "__concert_foe__"), "", "at exactly the line it is not yet a foe")
	DiplomacySim.shift_between(foe, west, -0.01)
	t.equal(ForeignArcs.resolve_target(state, "__concert_foe__"), foe.id, "just below it the Concert wants it sanctioned")
	(state.country.relations[foe.id] as Country.BilateralRelation).sanctioned = true
	t.equal(ForeignArcs.resolve_target(state, "__concert_foe__"), "", "and not once Ardenia already sanctions it")


func _test_a_declared_target_is_fixed_on_arrival_and_follows_on(t) -> void:
	var state := _state()
	var event := {"id": "probe", "target": "__supplier__", "options": [{"id": "a", "relation_deltas": {"__supplier__": -0.1}}]}
	t.equal(EventsSim._diplomatic_target(state, event), state.foreign.gas.supplier_id, "a declared target resolves on arrival")
	var legacy := {"id": "probe", "options": [{"id": "a", "relation_deltas": {"__coolest__": -0.1}}]}
	t.equal(EventsSim._diplomatic_target(state, legacy), EventsSim._worst_relation(state, INF), "an undeclared target keeps the old inference")
	var s := Situation.new()
	s.target_country_id = state.foreign.gas.supplier_id
	var before := _score(state, s.target_country_id)
	EventsSim.apply_option(state, event, event["options"][0], s, false)
	t.near(_score(state, s.target_country_id), before - 0.1, 1e-9, "a sentinel delta lands on the situation's own target")
	t.truth("__supplier__" in EventsSim.TARGET_KEYS, "the new sentinels are target keys")
	for key in ForeignArcs.TARGETS:
		t.truth(key in EventsSim.TARGET_KEYS, "%s is a target key" % key)


func _test_data_gates_speak_with_the_action_layers_voice(t) -> void:
	var state := _state()
	state.player.political_capital = 0.0
	var energy := {"requires": {"energy_verb": "gas_spot_purchase"}}
	t.equal(EventsSim.gate_reason(state, energy), EnergyActions.reason_for(state, "gas_spot_purchase"), "an energy gate gives the energy desk's reason")
	t.truth(EventsSim.gate_reason(state, energy) != "", "and it refuses a government with no capital")
	state.player.political_capital = 200.0
	t.equal(EventsSim.gate_reason(state, energy), "", "and opens once the action is possible")
	var orientation := {"requires": {"orientation_verb": "isf_renegotiate"}}
	t.equal(EventsSim.gate_reason(state, orientation), OrientationActions.reason_for(state, "isf_renegotiate"), "an orientation gate gives the orientation desk's reason")
	var target := ForeignArcs.resolve_target(state, "__western__")
	var diplomacy := {"requires": {"diplomacy_verb": "impose_sanctions"}}
	t.equal(EventsSim.gate_reason(state, diplomacy, target), DiplomacyActions.reason_for(state, "impose_sanctions", target), "a diplomacy gate judges the situation's own target")
	t.truth(EventActions.option_reason(state, diplomacy, target) != "", "and refuses to sanction a friend, through the event desk too")
	t.equal(EventsSim.gate_reason(state, {"requires": {"background": "economist"}}), "Only open to a leader with the economist background.", "old gates are unchanged")


func _test_a_triggered_situation_arrives_this_month_and_never_goes_stale(t) -> void:
	var state := _state()
	state.turn = 10
	var event := EventsSim.event_by_id("bank_run").duplicate(true)
	ForeignArcs.schedule(state, "bank_run", "krasova")
	t.equal(state.scheduled_events[-1], {"event_id": "bank_run", "due_turn": 10, "target_country_id": "krasova"}, "a trigger is due this very month")
	var notes: Array[String] = []
	EventsSim._deliver_follow_ups(state, notes)
	t.equal(state.pending_situations.size(), 1, "and is delivered at once")
	t.equal(state.pending_situations[0].target_country_id, "krasova", "about the country that triggered it")
	state.pending_situations.clear()
	EventsSim._by_id["stale_probe"] = event.merged({"id": "stale_probe", "stale_after": 1}, true)
	state.scheduled_events.append({"event_id": "stale_probe", "due_turn": 9, "target_country_id": ""})
	EventsSim._deliver_follow_ups(state, notes)
	t.equal(state.pending_situations.size(), 1, "one month late is still on time")
	state.pending_situations.clear()
	state.scheduled_events.append({"event_id": "stale_probe", "due_turn": 8, "target_country_id": ""})
	EventsSim._deliver_follow_ups(state, notes)
	t.equal(state.pending_situations.size(), 0, "two months late it is dropped")
	t.equal(state.scheduled_events.size(), 0, "and leaves no row behind")
	EventsSim._by_id.erase("stale_probe")


func _test_targets_must_name_real_countries(t) -> void:
	var state := _state()
	t.equal(StateValidator.validate(state).size(), 0, "sanity: a fresh campaign is valid")
	_force(state, "bank_run", "atlantis")
	_rejects(t, state, "targets unknown country", "a situation aimed at no real country is rejected")
	state.pending_situations.clear()
	state.scheduled_events.append({"event_id": "bank_run", "due_turn": 3, "target_country_id": "atlantis"})
	_rejects(t, state, "targets unknown country", "so is a follow-up aimed at no real country")
	state.scheduled_events.clear()
	_force(state, "bank_run", "")
	t.equal(StateValidator.validate(state).size(), 0, "an untargeted situation is fine")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_every_sentinel_names_a_live_country(t)
	_test_the_war_and_the_coup_sentinels_read_the_world(t)
	_test_the_concert_foe_is_cold_to_the_west_and_unsanctioned(t)
	_test_a_declared_target_is_fixed_on_arrival_and_follows_on(t)
	_test_data_gates_speak_with_the_action_layers_voice(t)
	_test_a_triggered_situation_arrives_this_month_and_never_goes_stale(t)
	_test_targets_must_name_real_countries(t)
	quit(t.finish())
```

The test references the literal ids `krasova` and `atlantis` only as test fixtures; the "no literal ids" rule binds content and handlers, not tests.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_foreign_situations.gd`
Expected: timeout with `SCRIPT ERROR` (`ForeignArcs` not declared).

- [ ] **Step 3: Write `foreign_arcs.gd`**

Create `godot/scripts/native/sim/foreign_arcs.gd`:

```gdscript
class_name ForeignArcs
extends RefCounted


const TARGETS := ["__supplier__", "__rival__", "__western__", "__union_anchor__",
	"__in_civil_war__", "__fragile__", "__concert_foe__", "__warmest__"]
const HANDLERS: Array[String] = []
const CONDITIONS: Array[String] = []
const EVENT_IDS: Array[String] = []
const GATES := ["energy_verb", "orientation_verb", "diplomacy_verb"]
const COUP_STABILITY := 0.3
const COUP_MAX_WAR_RISK := 0.5
const CONCERT_FOE_LINE := -0.6


static func resolve_target(state: GameState, key: String) -> String:
	match key:
		"__supplier__":
			return GasSim.gas(state).supplier_id if GasSim.is_active(state) else ""
		"__rival__":
			return _coldest(state, func(c: Country) -> bool: return DiplomacySim.is_rival_of_player(state, c))
		"__western__":
			return _anchor(state, "concert")
		"__union_anchor__":
			return _anchor(state, "union")
		"__in_civil_war__":
			return _first(state, func(c: Country) -> bool: return c.in_civil_war)
		"__fragile__":
			return _first(state, func(c: Country) -> bool: return _fragile(c))
		"__concert_foe__":
			return _concert_foe(state)
		"__warmest__":
			return _warmest(state)
	return ""


static func _world(state: GameState) -> Array[Country]:
	var out: Array[Country] = []
	for c in state.world:
		if c.id != state.country.id:
			out.append(c)
	out.sort_custom(func(a: Country, b: Country) -> bool: return a.id < b.id)
	return out


static func _first(state: GameState, test: Callable) -> String:
	for c in _world(state):
		if test.call(c):
			return c.id
	return ""


static func _score(state: GameState, id: String) -> float:
	var rel: Country.BilateralRelation = state.country.relations.get(id)
	return 0.0 if rel == null else rel.score


static func _coldest(state: GameState, test: Callable) -> String:
	var best := ""
	for c in _world(state):
		if test.call(c) and (best == "" or _score(state, c.id) < _score(state, best)):
			best = c.id
	return best


static func _warmest(state: GameState) -> String:
	var best := ""
	for c in _world(state):
		if state.country.relations.has(c.id) and (best == "" or _score(state, c.id) > _score(state, best)):
			best = c.id
	return best


static func _anchor(state: GameState, power_id: String) -> String:
	var id := String(ForeignSim.power(power_id).get("anchor", ""))
	return id if state.world_country(id) != null else ""


static func _fragile(c: Country) -> bool:
	return not c.in_civil_war and c.stability < COUP_STABILITY and c.civil_war_risk < COUP_MAX_WAR_RISK \
		and String(Country.REGIME_FAMILIES.get(c.regime_type, "")) != "autocracy"


static func _concert_foe(state: GameState) -> String:
	var west := state.world_country(_anchor(state, "concert"))
	if west == null:
		return ""
	var best := ""
	var best_score := CONCERT_FOE_LINE
	for c in _world(state):
		var rel: Country.BilateralRelation = c.get_relation(west.id)
		var own: Country.BilateralRelation = state.country.relations.get(c.id)
		if c == west or rel == null or own == null or own.sanctioned:
			continue
		if rel.score < best_score:
			best = c.id
			best_score = rel.score
	return best


static func gate_reason(state: GameState, gate: Dictionary, target: String) -> String:
	if gate.has("energy_verb"):
		return EnergyActions.reason_for(state, String(gate["energy_verb"]))
	if gate.has("orientation_verb"):
		return OrientationActions.reason_for(state, String(gate["orientation_verb"]))
	if gate.has("diplomacy_verb"):
		return DiplomacyActions.reason_for(state, String(gate["diplomacy_verb"]), target)
	return ""


static func schedule(state: GameState, event_id: String, target: String) -> void:
	state.scheduled_events.append({"event_id": event_id, "due_turn": state.turn, "target_country_id": target})


static func shift(state: GameState, sentinel: String, delta: float) -> void:
	var id := resolve_target(state, sentinel)
	if id != "":
		DiplomacySim.shift(state, id, delta)


static func condition_met(_state: GameState, _rule_id: String) -> bool:
	return false


static func run(_state: GameState, _handler_id: String, _target: String) -> String:
	return ""
```

`HANDLERS`, `CONDITIONS` and `EVENT_IDS` start empty and are filled by Tasks 2–5; `condition_met` and `run` become `match` statements there. If `DiplomacyActions.reason_for` already refuses sanctions on a friend, the test's last diplomacy assertion holds; confirm by reading `godot/scripts/native/actions/diplomacy_actions.gd:48` before Step 4.

- [ ] **Step 4: Wire `Arcs`, `EventsSim`, `EventActions`**

In `godot/scripts/native/sim/arcs.gd`:

```gdscript
static func has_handler(handler_id: String) -> bool:
	return handler_id in HANDLERS or handler_id in ForeignArcs.HANDLERS


static func run(state: GameState, handler_id: String, target := "") -> String:
	if handler_id in ForeignArcs.HANDLERS:
		return ForeignArcs.run(state, handler_id, target)
	if handler_id in OppositionSim.EVENT_HANDLERS:
		return OppositionSim.run_event(state, handler_id)
```

(the rest of `run` unchanged) and at the top of `condition_met`:

```gdscript
	if rule_id in ForeignArcs.CONDITIONS:
		return ForeignArcs.condition_met(state, rule_id)
```

In `godot/scripts/native/sim/events_sim.gd`:

```gdscript
const TARGET_KEYS := ["__coolest__", "__most_hostile__", "__supplier__", "__rival__", "__western__",
	"__union_anchor__", "__in_civil_war__", "__fragile__", "__concert_foe__", "__warmest__"]
```

In `is_playable`, the condition test becomes `condition in KNOWN_CONDITIONS or condition in Arcs.CONDITIONS or condition in ForeignArcs.CONDITIONS`.

`gate_reason` gains the target and falls through to the foreign gates:

```gdscript
static func gate_reason(state: GameState, option: Dictionary, target := "") -> String:
	var gate: Variant = option.get("requires", null)
	if not (gate is Dictionary):
		return ""
	if gate.has("background") and String(state.campaign_meta.get("background", "")) != String(gate["background"]):
		return "Only open to a leader with the %s background." % String(gate["background"]).replace("_", " ")
	if gate.has("player_social_at_most") and state.player.ideology_social > float(gate["player_social_at_most"]):
		return "Only a markedly authoritarian leader would order this."
	return ForeignArcs.gate_reason(state, gate, target)
```

In `_deliver_follow_ups`, after the `is_playable` check and before the audience check:

```gdscript
		if event.has("stale_after") and state.turn > int(row.get("due_turn", 0)) + int(event["stale_after"]):
			state.scheduled_events.erase(row)
			continue
```

`_diplomatic_target`:

```gdscript
static func _diplomatic_target(state: GameState, event: Dictionary) -> String:
	if event.has("target"):
		return ForeignArcs.resolve_target(state, String(event["target"]))
	for o in event.get("options", []):
		for key in o.get("relation_deltas", {}):
			if String(key) in ["__coolest__", "__most_hostile__"]:
				return _worst_relation(state, INF)
	return ""
```

In `apply_option`, the handler call becomes `note = Arcs.run(state, String(handler), situation.target_country_id)`.

In `godot/scripts/native/actions/event_actions.gd`: `option_reason(state, option, target := "")` calls `EventsSim.gate_reason(state, option, target)`; `resolve` calls `option_reason(state, option, situation.target_country_id)`; `read_model` calls `option_reason(state, option, situation.target_country_id)`.

- [ ] **Step 5: Write the validator**

Create `godot/scripts/native/state/foreign_situation_validator.gd`:

```gdscript
class_name ForeignSituationValidator
extends RefCounted


static func validate(state: GameState, errors: Array[String]) -> void:
	for situation in state.pending_situations:
		if situation != null:
			_check(state, situation.event_id, situation.target_country_id, errors)
	for row in state.scheduled_events:
		_check(state, String(row.get("event_id", "")), String(row.get("target_country_id", "")), errors)


static func _check(state: GameState, event_id: String, target: String, errors: Array[String]) -> void:
	if target != "" and state.world_country(target) == null:
		errors.append("situation '%s' targets unknown country '%s'" % [event_id, target])
```

In `godot/scripts/native/state/state_validator.gd`, directly after `GasValidator.validate(state, errors)` (line 753), add `ForeignSituationValidator.validate(state, errors)`. If that call sits inside the foreign branch, which runs only when `state.foreign` exists, move it instead to the end of `_validate_situations` (line ~538). Either way, add only one line, and check with `wc -l` that the file stays under 800.

- [ ] **Step 6: Import, run, pass**

Run: `timeout 180 "$G" --headless --path godot --import`, then the Step 2 command, then `test_events.gd`.
Expected: both `0 failed`. `test_events.gd` still passes: old targets, gates and follow-ups are unchanged.

- [ ] **Step 7: Mutation-check**

Each mutation must fail the named assertion:
1. `c.stability < COUP_STABILITY` → `<=`: "at exactly the coup line a state holds".
2. `rel.score < best_score` → `<=` in `_concert_foe`: "at exactly the line it is not yet a foe".
3. Drop `or own.sanctioned`: "and not once Ardenia already sanctions it".
4. In `schedule`, `state.turn` → `state.turn + 1`: "a trigger is due this very month".
5. `int(event["stale_after"])` → `int(event["stale_after"]) + 1`: "two months late it is dropped".
6. Drop `return ForeignArcs.gate_reason(...)` in `EventsSim.gate_reason` (return ""): "and it refuses a government with no capital".
7. In `EventActions.option_reason` pass `""` instead of `target`: "and refuses to sanction a friend, through the event desk too".
8. In `apply_option` drop `situation.target_country_id` from `Arcs.run`. No test kills this yet; Task 2's handler test does (`valve_appeal_west`). Note it and recheck in Task 2.
9. `target != ""` → `true` in the validator: "an untargeted situation is fine".

- [ ] **Step 8: Full battery, then commit**

```bash
git add godot/scripts/native/sim/foreign_arcs.gd godot/scripts/native/sim/foreign_arcs.gd.uid \
  godot/scripts/native/state/foreign_situation_validator.gd godot/scripts/native/state/foreign_situation_validator.gd.uid \
  godot/scripts/native/sim/arcs.gd godot/scripts/native/sim/events_sim.gd godot/scripts/native/actions/event_actions.gd \
  godot/scripts/native/state/state_validator.gd godot/tests/native/test_foreign_situations.gd godot/tests/native/test_foreign_situations.gd.uid
git commit -m "feat(godot): foreign situation targets, action-layer gates and triggered follow-ups

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show HEAD --stat
```

---

### Task 2: Gas situations: the valve threat, the transit dispute, the transit-fee windfall

**Files:**
- Modify: `godot/scripts/native/sim/foreign_arcs.gd` (constants, `HANDLERS`, `CONDITIONS`, `EVENT_IDS`, `condition_met`, `run`)
- Modify: `godot/scripts/native/sim/gas_sim.gd:242-267` (`coerce` schedules the situation)
- Modify: `godot/data/native/catalogs/events.json` (append three events)
- Modify: `godot/tests/native/test_events.gd:50` (count 46 → 49)
- Test: `godot/tests/native/test_foreign_situations.gd`

**Interfaces:**
- Consumes: `ForeignArcs.schedule/shift/resolve_target`, `EnergyActions.act(state, verb) -> Dictionary`, `GasSim.ARREARS_DEMAND`, `GasSim.DEFUSED_SHARE`, `GasSim.supplier_warmth`, `GasContract.concessions`.
- Produces: events `valve_threat`, `transit_dispute`, `transit_windfall`; conditions `transit_dispute_ripe`, `transit_windfall_due`; handlers `valve_pay`, `valve_cargo`, `valve_appeal_west`, `transit_concede`, `transit_arbitrate`, `windfall_storage`; constants `ForeignArcs.VALVE_TRANCHES` (3), `ForeignArcs.TRANSIT_WARMTH` (−0.3), `ForeignArcs.GAS_SITUATION_TURN` (12), `ForeignArcs.WEST_APPEAL` (0.03), `ForeignArcs.ARBITRATION_GOODWILL` (0.03).

- [ ] **Step 1: Write the failing tests**

Append to `godot/tests/native/test_foreign_situations.gd` (and call each from `_initialize`):

```gdscript
func _test_a_valve_threat_reaches_the_government_the_month_it_is_made(t) -> void:
	var state := _state()
	var g := state.foreign.gas
	var supplier := state.world_country(g.supplier_id)
	while state.month != 11:
		NativeGameScript.next_month(state)
	state.pending_situations.clear()
	state.scheduled_events.clear()
	g.arrears = 120.0
	g.last_demand_turn = state.turn - GasSim.THREAT_AFTER_DEMAND
	g.last_cut_turn = -1
	g.threat = {}
	state.foreign.powers[g.supplier_id] = {"dependence": 1.0, "commitment": 0.0, "leverage": 0.9}
	var notes: Array[String] = []
	GasSim.coerce(state, supplier, notes)
	t.truth(not g.threat.is_empty(), "sanity: the supplier names a date")
	EventsSim._deliver_follow_ups(state, notes)
	var arrived: Array = state.pending_situations.filter(func(s: Situation) -> bool: return s.event_id == "valve_threat")
	t.equal(arrived.size(), 1, "the threat is on the desk the same month")
	t.equal((arrived[0] as Situation).target_country_id, g.supplier_id, "and it is about the supplier")


func _test_a_threat_against_the_opposition_is_not_its_desk(t) -> void:
	var state := _state("opposition")
	var g := state.foreign.gas
	state.turn = 20
	g.arrears = 120.0
	g.last_demand_turn = state.turn - GasSim.THREAT_AFTER_DEMAND
	state.month = 11
	state.foreign.powers[g.supplier_id] = {"dependence": 1.0, "commitment": 0.0, "leverage": 0.9}
	var notes: Array[String] = []
	GasSim.coerce(state, state.world_country(g.supplier_id), notes)
	t.truth(not g.threat.is_empty(), "sanity: the supplier threatens the AI government too")
	t.equal(state.scheduled_events.filter(func(r: Dictionary) -> bool: return r["event_id"] == "valve_threat").size(), 0, "but the opposition is not handed the decision")


func _test_paying_before_the_date_defuses_the_valve(t) -> void:
	var state := _state()
	var g := state.foreign.gas
	g.arrears = 120.0
	g.threat = {"turn": state.turn, "due": state.turn + 1, "share": 0.3}
	_force(state, "valve_threat", g.supplier_id)
	var result := EventActions.resolve(state, "valve_threat", "pay_down")
	t.truth(result.get("ok", false), "the government can pay (%s)" % result.get("error", ""))
	t.truth(g.arrears < GasSim.ARREARS_DEMAND * GasSim.DEFUSED_SHARE, "the arrears fall below the line that defuses the threat (%.1f)" % g.arrears)
	t.near(g.arrears, 120.0 - 2.0 * EnergyActions.ARREARS_TRANCHE, 1e-6, "in whole tranches, and no more than needed")
	state.turn += 1
	var notes: Array[String] = []
	GasSim._mature_threat(state, notes)
	t.equal(g.cut, 0.0, "and the named date passes with the gas flowing")


func _test_paying_never_exceeds_three_tranches(t) -> void:
	var state := _state()
	var g := state.foreign.gas
	g.arrears = 400.0
	_force(state, "valve_threat", g.supplier_id)
	EventActions.resolve(state, "valve_threat", "pay_down")
	t.near(g.arrears, 400.0 - float(ForeignArcs.VALVE_TRANCHES) * EnergyActions.ARREARS_TRANCHE, 1e-6, "a crisis payment is capped at three tranches")


func _test_the_cargo_option_is_the_energy_desks_cargo(t) -> void:
	var state := _state()
	var g := state.foreign.gas
	_force(state, "valve_threat", g.supplier_id)
	state.player.political_capital = 0.0
	var refused := EventActions.resolve(state, "valve_threat", "buy_cargo")
	t.truth(not refused.get("ok", true), "with no capital the cargo is refused before anything happens")
	t.equal(refused.get("error", ""), EnergyActions.reason_for(state, "gas_spot_purchase"), "in the energy desk's own words")
	t.equal(g.spot_pending, 0.0, "and nothing is bought")
	state.player.political_capital = 50.0
	t.truth(EventActions.resolve(state, "valve_threat", "buy_cargo").get("ok", false), "with capital it goes through")
	t.near(g.spot_pending, EnergyActions.SPOT_VOLUME, 1e-9, "and a cargo is on its way")
	t.near(state.player.political_capital, 50.0 - float(EnergyActions.COSTS["gas_spot_purchase"]), 1e-9, "charged once, by the energy desk")


func _test_appealing_to_the_west_moves_both_capitals(t) -> void:
	var state := _state()
	var g := state.foreign.gas
	var west := ForeignArcs.resolve_target(state, "__western__")
	_force(state, "valve_threat", g.supplier_id)
	var s0 := _score(state, g.supplier_id)
	var w0 := _score(state, west)
	EventActions.resolve(state, "valve_threat", "appeal_west")
	t.near(_score(state, west), w0 + ForeignArcs.WEST_APPEAL, 1e-9, "the West hears the appeal")
	t.near(_score(state, g.supplier_id), s0 - 0.05, 1e-9, "and the supplier hears it too")


func _test_calling_the_bluff_is_the_default_and_costs_nothing(t) -> void:
	var state := _state()
	var event := EventsSim.event_by_id("valve_threat")
	t.equal(String(event["default_option_id"]), "call_bluff", "doing nothing is the default")
	var option := EventsSim.option_by_id(event, "call_bluff")
	t.equal(option.get("requires", null), null, "and it is never gated")
	t.equal(option.get("follow_up", null), null, "and starts nothing that would draw on the stream")
	t.equal(int(event.get("stale_after", -1)), 1, "a threat a month stale is never delivered")


func _test_the_transit_dispute_needs_a_cold_supplier_and_uncoded_fees(t) -> void:
	var state := _state()
	state.turn = ForeignArcs.GAS_SITUATION_TURN
	var supplier := state.foreign.gas.supplier_id
	_set_score(state, supplier, ForeignArcs.TRANSIT_WARMTH)
	t.truth(not EventsSim.condition_met(state, "transit_dispute_ripe"), "at exactly the line there is no dispute")
	t.truth(EventsSim.condition_met(state, "transit_windfall_due"), "the fees flow instead")
	_set_score(state, supplier, ForeignArcs.TRANSIT_WARMTH - 0.01)
	t.truth(EventsSim.condition_met(state, "transit_dispute_ripe"), "just colder and the fees are disputed")
	t.truth(not EventsSim.condition_met(state, "transit_windfall_due"), "and no windfall arrives")
	state.turn = ForeignArcs.GAS_SITUATION_TURN - 1
	t.truth(not EventsSim.condition_met(state, "transit_dispute_ripe"), "not in the first year")
	state.turn = ForeignArcs.GAS_SITUATION_TURN
	state.foreign.gas.concessions.append("transit")
	t.truth(not EventsSim.condition_met(state, "transit_dispute_ripe"), "and not once the fees are conceded")
	t.truth(not EventsSim.condition_met(state, "transit_windfall_due"), "when there are no fees to collect either")
	state.foreign.gas.concessions.clear()
	state.player.in_government = false
	t.truth(not EventsSim.condition_met(state, "transit_dispute_ripe"), "and never for the opposition")


func _test_conceding_the_fees_is_the_renegotiation(t) -> void:
	var state := _state()
	var g := state.foreign.gas
	state.player.political_capital = 100.0
	_force(state, "transit_dispute", g.supplier_id)
	var price := g.price
	t.truth(EventActions.resolve(state, "transit_dispute", "concede_fees").get("ok", false), "the fees can be conceded")
	t.truth("transit" in g.concessions, "the contract records the concession")
	t.near(g.price, maxf(g.reference_price * EnergyActions.PRICE_FLOOR_SHARE, price * float(EnergyActions.PRICE_CUTS["gas_renegotiate_transit"])), 1e-9, "at the renegotiation's own price")


func _test_the_windfall_can_fund_storage(t) -> void:
	var state := _state()
	state.player.political_capital = 100.0
	_force(state, "transit_windfall", "")
	t.truth(EventActions.resolve(state, "transit_windfall", "fund_storage").get("ok", false), "the windfall can start storage")
	t.equal(state.foreign.gas.storage_started, state.turn, "and the storage programme begins")
	var again := _state()
	_force(again, "transit_windfall", "")
	var debt := again.country.economy.public_debt_pct
	EventActions.resolve(again, "transit_windfall", "bank_it")
	t.near(again.country.economy.public_debt_pct, debt - 0.001, 1e-9, "banking it pays down a little debt")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_foreign_situations.gd`
Expected: FAIL (`valve_threat` unknown, `ForeignArcs.VALVE_TRANCHES` undeclared → timeout with `SCRIPT ERROR`).

- [ ] **Step 3: Add the events to `events.json`**

Append to the `events` array:

```json
{
  "id": "valve_threat", "title": "The Valve, With a Date",
  "description": "The supplier's gas company has put it in writing: unless the arrears come down, deliveries through the Zovar line fall next month. The Finance Ministry can find some hard currency. Not much, and not twice.",
  "category": "Diplomatic", "condition": "never", "chance": 0.0, "target": "__supplier__", "stale_after": 1,
  "options": [
    {"id": "pay_down", "label": "Pay enough to take the date off the table", "description": "Hard currency the treasury does not have, paid in tranches until the arrears are below the line their lawyers named.", "effects": {}, "relation_deltas": {}, "pc_cost": 0, "follow_up": null, "on_apply": "valve_pay", "requires": null},
    {"id": "buy_cargo", "label": "Buy a spot cargo and let them cut", "description": "A tanker at a premium, so the cut lands on an empty pipe instead of cold flats.", "effects": {}, "relation_deltas": {}, "pc_cost": 0, "follow_up": null, "on_apply": "valve_cargo", "requires": {"energy_verb": "gas_spot_purchase"}},
    {"id": "appeal_west", "label": "Take the letter to the Western embassies", "description": "Make the threat a story about them, not us. The supplier will not enjoy reading it.", "effects": {}, "relation_deltas": {"__supplier__": -0.05}, "pc_cost": 6, "follow_up": null, "on_apply": "valve_appeal_west", "requires": null},
    {"id": "call_bluff", "label": "Call the bluff", "description": "They have mentioned the valve before. Say nothing, and see whether they mean it this time.", "effects": {"faction_loyalty_deltas": {"@nationalist": 0.03}}, "relation_deltas": {}, "pc_cost": 0, "follow_up": null, "on_apply": null, "requires": null}
  ],
  "default_option_id": "call_bluff", "once": false, "cooldown": 0, "audience": "government", "portfolio": "Foreign Affairs"
},
{
  "id": "transit_dispute", "title": "Whose Pipe Is It?",
  "description": "The supplier says the Zovar transit fees were set for a friendlier decade and wants them gone. Its gas company has started paying late, and the Foreign Ministry hears the word 'review' a great deal.",
  "category": "Diplomatic", "condition": "transit_dispute_ripe", "chance": 0.05, "target": "__supplier__",
  "options": [
    {"id": "concede_fees", "label": "Concede the fees for a better price", "description": "Give up the transit revenue for good, and take a cheaper contract until the next renewal.", "effects": {}, "relation_deltas": {}, "pc_cost": 0, "follow_up": null, "on_apply": "transit_concede", "requires": {"energy_verb": "gas_renegotiate_transit"}},
    {"id": "seek_arbitration", "label": "Ask the Western institutions to arbitrate", "description": "A neutral panel in a Western capital. The supplier will call it a provocation and attend anyway.", "effects": {}, "relation_deltas": {"__supplier__": -0.02}, "pc_cost": 8, "follow_up": null, "on_apply": "transit_arbitrate", "requires": null},
    {"id": "hold_fees", "label": "Hold the fees where they are", "description": "The treaty says what it says. Read it to them slowly.", "effects": {"faction_loyalty_deltas": {"@nationalist": 0.02}}, "relation_deltas": {"__supplier__": -0.04}, "pc_cost": 0, "follow_up": null, "on_apply": null, "requires": null}
  ],
  "default_option_id": "hold_fees", "once": false, "cooldown": 24, "audience": "government", "portfolio": "Foreign Affairs"
},
{
  "id": "transit_windfall", "title": "A Cold Winter in Someone Else's Country",
  "description": "Gas through the Zovar line is running above contract on its way west, and the transit fees with it. The Finance Ministry has a sum it did not budget for and three ministers who know what to do with it.",
  "category": "Economic", "condition": "transit_windfall_due", "chance": 0.04,
  "options": [
    {"id": "bank_it", "label": "Pay down the debt", "description": "Nobody thanks a government for a debt figure, but the next ISF review will.", "effects": {"one_time_debt_pct_delta": -0.001}, "relation_deltas": {}, "pc_cost": 0, "follow_up": null, "on_apply": null, "requires": null},
    {"id": "winter_rebate", "label": "A heating rebate for the coldest regions", "description": "Money back on the winter bill, delivered before anyone has to ask.", "effects": {"one_time_debt_pct_delta": 0.0005, "faction_loyalty_deltas": {"@labour": 0.04, "@business": -0.02}}, "relation_deltas": {}, "pc_cost": 4, "follow_up": null, "on_apply": null, "requires": null},
    {"id": "fund_storage", "label": "Put it toward gas storage", "description": "Start the storage programme with someone else's money. The next valve threat will be quieter.", "effects": {}, "relation_deltas": {}, "pc_cost": 0, "follow_up": null, "on_apply": "windfall_storage", "requires": {"energy_verb": "gas_storage"}}
  ],
  "default_option_id": "bank_it", "once": false, "cooldown": 24, "audience": "government", "portfolio": "Finance"
}
```

- [ ] **Step 4: Conditions and handlers**

In `godot/scripts/native/sim/foreign_arcs.gd` replace the empty lists and stubs:

```gdscript
const HANDLERS: Array[String] = ["valve_pay", "valve_cargo", "valve_appeal_west", "transit_concede",
	"transit_arbitrate", "windfall_storage"]
const CONDITIONS: Array[String] = ["transit_dispute_ripe", "transit_windfall_due"]
const EVENT_IDS: Array[String] = ["valve_threat", "transit_dispute", "transit_windfall"]
const VALVE_TRANCHES := 3
const TRANSIT_WARMTH := -0.3
const GAS_SITUATION_TURN := 12
const WEST_APPEAL := 0.03
const ARBITRATION_GOODWILL := 0.03


static func condition_met(state: GameState, rule_id: String) -> bool:
	match rule_id:
		"transit_dispute_ripe":
			return _transit_open(state) and GasSim.supplier_warmth(state) < TRANSIT_WARMTH
		"transit_windfall_due":
			return _transit_open(state) and GasSim.supplier_warmth(state) >= TRANSIT_WARMTH
	return false


static func _transit_open(state: GameState) -> bool:
	return state.player.in_government and GasSim.is_active(state) and state.turn >= GAS_SITUATION_TURN \
		and not ("transit" in GasSim.gas(state).concessions)


static func run(state: GameState, handler_id: String, _target: String) -> String:
	match handler_id:
		"valve_pay":
			return _pay_to_defuse(state)
		"valve_cargo":
			return _through(EnergyActions.act(state, "gas_spot_purchase"))
		"valve_appeal_west":
			shift(state, "__western__", WEST_APPEAL)
			return "The Western embassies take the letter seriously, and say so in public."
		"transit_concede":
			return _through(EnergyActions.act(state, "gas_renegotiate_transit"))
		"transit_arbitrate":
			shift(state, "__western__", ARBITRATION_GOODWILL)
			return "The dispute goes to a panel in a Western capital."
		"windfall_storage":
			return _through(EnergyActions.act(state, "gas_storage"))
	return ""


static func _through(result: Dictionary) -> String:
	return String(result.get("message", result.get("error", "")))


static func _pay_to_defuse(state: GameState) -> String:
	var g := GasSim.gas(state)
	var line := g.arrears < GasSim.ARREARS_DEMAND * GasSim.DEFUSED_SHARE
	var tranches := 0
	while tranches < VALVE_TRANCHES and g.arrears >= GasSim.ARREARS_DEMAND * GasSim.DEFUSED_SHARE:
		if not EnergyActions.act(state, "gas_pay_arrears").get("ok", false):
			break
		tranches += 1
	if line or tranches == 0:
		return ""
	return "The treasury pays %d tranches of the Zovar arrears; %.0f remains." % [tranches, g.arrears]
```

Remove the earlier one-line `condition_met` and `run` stubs.

- [ ] **Step 5: `GasSim.coerce` schedules the decision**

In `godot/scripts/native/sim/gas_sim.gd`, in `coerce`, directly after `g.threats += 1`:

```gdscript
	if state.player.in_government:
		ForeignArcs.schedule(state, "valve_threat", actor.id)
```

In `godot/tests/native/test_events.gd:50` change `46` to `49` in both the number and the label.

- [ ] **Step 6: Run and pass**

Run: `--import`, then `test_foreign_situations.gd`, `test_events.gd`, `test_gas_supplier.gd`.
Expected: all `0 failed`. `test_events._test_catalog_integrity` confirms that every new event is playable and that no default is gated.

- [ ] **Step 7: Mutation-check**

1. `< TRANSIT_WARMTH` → `<=`: "at exactly the line there is no dispute".
2. `>= TRANSIT_WARMTH` → `>`: "the fees flow instead".
3. `state.turn >= GAS_SITUATION_TURN` → `>`: "the fees flow instead" (the test sets turn to exactly 12).
4. Drop the `in_government` guard in `coerce`: "but the opposition is not handed the decision".
5. Remove the `ForeignArcs.schedule` line: "the threat is on the desk the same month" (calendar-true: the test reaches November with `next_month`).
6. `tranches < VALVE_TRANCHES` → `<=`: "a crisis payment is capped at three tranches".
7. `>= ARREARS_DEMAND * DEFUSED_SHARE` → `> ...` in the loop: "in whole tranches, and no more than needed" fails, because an arrears figure of exactly 30 is still at the line. Add an assertion with `g.arrears = 80.0` (one tranche leaves 30, which is still at the line, so a second is paid) if the existing one survives.
8. Task 1 mutation 8 (target dropped from `Arcs.run`): the run should still pass, because no handler here reads the target. Record that it survives by design, as the target is read only through sentinels. Task 4's `sanctions_join` kills it.

- [ ] **Step 8: Full battery, then commit**

```bash
git add godot/scripts/native/sim/foreign_arcs.gd godot/scripts/native/sim/gas_sim.gd godot/data/native/catalogs/events.json \
  godot/tests/native/test_foreign_situations.gd godot/tests/native/test_events.gd
git commit -m "feat(godot): the valve threat, transit dispute and transit windfall as decisions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show HEAD --stat
```

---

### Task 3: Orientation situations: the ISF review crisis, the Concert delegation, the Union's invitation and pressure, Western aid with strings

**Files:**
- Modify: `godot/scripts/native/sim/foreign_arcs.gd`
- Modify: `godot/scripts/native/sim/orientation_sim.gd:105-112` (the failed-review branch schedules the crisis)
- Modify: `godot/data/native/catalogs/events.json` (append six events)
- Modify: `godot/tests/native/test_events.gd:50` (49 → 55)
- Test: `godot/tests/native/test_foreign_situations.gd`

**Interfaces:**
- Consumes: `OrientationActions.act/reason_for`, `OrientationActions.OBSERVER_WARMTH` (−0.35), `OrientationActions.UNION_REJOIN_MONTHS` (60), `OrientationActions.QUALIFYING_MONTHS_FOR_AGREEMENT` (36), `OrientationSim.isf_targets(state)["deficit"]`, `ForeignState.reached/isf/western_qualifying_months/union_left_turn`.
- Produces: events `isf_review_crisis`, `concert_delegation`, `union_invitation`, `union_pressure`, `western_aid_strings`, `aid_conditions_due` (chain-only); conditions `concert_delegation_due`, `union_invites`, `union_member_pressed`, `western_aid_offered`; handlers `isf_crisis_renegotiate`, `concert_embrace`, `union_accept`, `union_play_west`, `union_comply`; constants `ForeignArcs.DELEGATION_MONTHS` (3), `ForeignArcs.PLAY_WEST` (0.03), `ForeignArcs.COMPLY_WEST` (−0.03).

- [ ] **Step 1: Write the failing tests**

Append to `test_foreign_situations.gd` and register in `_initialize`:

```gdscript
func _test_a_failed_review_puts_the_fund_on_the_desk_in_the_review_month(t) -> void:
	var state := _state()
	while state.month != 12:
		NativeGameScript.next_month(state)
	state.pending_situations.clear()
	state.scheduled_events.clear()
	state.country.economy.inflation = 0.5
	NativeGameScript.next_month(state)
	t.equal(state.month, 1, "sanity: January, a review month")
	t.equal(String(state.foreign.isf["last_result"]), "failed", "sanity: the review fails")
	t.truth(state.pending_situations.any(func(s: Situation) -> bool: return s.event_id == "isf_review_crisis"), "the crisis is on the desk in the review month")
	var passed := _state()
	while passed.month != 12:
		NativeGameScript.next_month(passed)
	passed.pending_situations.clear()
	passed.scheduled_events.clear()
	passed.country.economy.inflation = 0.0
	passed.country.economy.budget.expenditure = passed.country.economy.budget.revenue
	NativeGameScript.next_month(passed)
	t.equal(String(passed.foreign.isf["last_result"]), "passed", "sanity: a disciplined government passes")
	t.truth(not passed.pending_situations.any(func(s: Situation) -> bool: return s.event_id == "isf_review_crisis"), "and no crisis follows a pass")


func _test_renegotiating_from_the_crisis_is_the_orientation_desks_renegotiation(t) -> void:
	var state := _state()
	state.foreign.isf["suspended"] = true
	state.player.political_capital = 100.0
	_force(state, "isf_review_crisis", "")
	var held := int(state.foreign.isf["renegotiations"])
	t.truth(EventActions.resolve(state, "isf_review_crisis", "renegotiate").get("ok", false), "the fund can be renegotiated from the crisis")
	t.equal(int(state.foreign.isf["renegotiations"]), held + 1, "the ledger records it")
	t.equal(String(EventsSim.event_by_id("isf_review_crisis")["default_option_id"]), "blame_the_fund", "blaming the fund is the default")


func _test_the_delegation_needs_an_application_and_no_union_step(t) -> void:
	var state := _state()
	t.truth(state.foreign.reached.has("concert_application"), "sanity: Ardenia has applied")
	t.truth(EventsSim.condition_met(state, "concert_delegation_due"), "the Concert sends a delegation to an applicant")
	state.foreign.reached["union_observer"] = state.turn
	t.truth(not EventsSim.condition_met(state, "concert_delegation_due"), "but not to a Union observer")
	state.foreign.reached.erase("union_observer")
	state.foreign.reached["concert_agreement"] = state.turn
	t.truth(not EventsSim.condition_met(state, "concert_delegation_due"), "nor once the agreement is signed")


func _test_embracing_the_conditions_counts_toward_the_agreement_and_caps(t) -> void:
	var state := _state()
	state.player.political_capital = 100.0
	state.foreign.western_qualifying_months = 10
	_force(state, "concert_delegation", ForeignArcs.resolve_target(state, "__western__"))
	EventActions.resolve(state, "concert_delegation", "embrace")
	t.equal(state.foreign.western_qualifying_months, 10 + ForeignArcs.DELEGATION_MONTHS, "the conditions count as months of discipline")
	state.foreign.western_qualifying_months = OrientationActions.QUALIFYING_MONTHS_FOR_AGREEMENT - 1
	_force(state, "concert_delegation", ForeignArcs.resolve_target(state, "__western__"))
	EventActions.resolve(state, "concert_delegation", "embrace")
	t.equal(state.foreign.western_qualifying_months, OrientationActions.QUALIFYING_MONTHS_FOR_AGREEMENT, "but never past what the agreement needs")


func _test_the_union_invites_only_a_tolerable_neighbour(t) -> void:
	var state := _state()
	var anchor := ForeignArcs.resolve_target(state, "__union_anchor__")
	_set_score(state, anchor, OrientationActions.OBSERVER_WARMTH)
	t.truth(EventsSim.condition_met(state, "union_invites"), "at exactly the observer line the Union invites")
	_set_score(state, anchor, OrientationActions.OBSERVER_WARMTH - 0.01)
	t.truth(not EventsSim.condition_met(state, "union_invites"), "just colder and it does not")
	_set_score(state, anchor, 0.0)
	state.foreign.union_left_turn = state.turn
	state.turn += OrientationActions.UNION_REJOIN_MONTHS - 1
	t.truth(not EventsSim.condition_met(state, "union_invites"), "a country that walked out waits out the bar")
	state.turn += 1
	t.truth(EventsSim.condition_met(state, "union_invites"), "and is invited again the month it ends")
	state.foreign.reached["union_observer"] = state.turn
	t.truth(not EventsSim.condition_met(state, "union_invites"), "an observer is not invited twice")


func _test_accepting_the_invitation_takes_observer_status(t) -> void:
	var state := _state()
	state.player.political_capital = 100.0
	_force(state, "union_invitation", ForeignArcs.resolve_target(state, "__union_anchor__"))
	t.truth(EventActions.resolve(state, "union_invitation", "accept_observer").get("ok", false), "the invitation can be accepted")
	t.truth(state.foreign.reached.has("union_observer"), "and Ardenia is an observer")


func _test_union_pressure_lands_on_members_and_compliance_cools_the_west(t) -> void:
	var state := _state()
	t.truth(not EventsSim.condition_met(state, "union_member_pressed"), "a non-member is not pressed")
	state.foreign.reached["union_member"] = state.turn
	t.truth(EventsSim.condition_met(state, "union_member_pressed"), "a member is")
	var west := ForeignArcs.resolve_target(state, "__western__")
	var anchor := ForeignArcs.resolve_target(state, "__union_anchor__")
	_force(state, "union_pressure", anchor)
	var w0 := _score(state, west)
	var a0 := _score(state, anchor)
	EventActions.resolve(state, "union_pressure", "comply")
	t.near(_score(state, west), w0 + ForeignArcs.COMPLY_WEST, 1e-9, "complying costs the West")
	t.near(_score(state, anchor), a0 + 0.03, 1e-9, "and pleases the Union")
	t.equal(String(EventsSim.event_by_id("union_pressure")["default_option_id"]), "comply", "a member that looks away complies")


func _test_western_aid_needs_a_strained_treasury_and_comes_with_conditions(t) -> void:
	var state := _state()
	var limit := float(OrientationSim.isf_targets(state)["deficit"])
	state.foreign.isf["suspended"] = false
	var budget := state.country.economy.budget
	budget.expenditure = budget.revenue
	t.truth(not EventsSim.condition_met(state, "western_aid_offered"), "a balanced, compliant treasury gets no aid offer")
	state.foreign.isf["suspended"] = true
	t.truth(EventsSim.condition_met(state, "western_aid_offered"), "a suspended programme does")
	state.foreign.reached["union_member"] = state.turn
	t.truth(not EventsSim.condition_met(state, "western_aid_offered"), "a Union member does not")
	state.foreign.reached.erase("union_member")
	state.foreign.isf["suspended"] = false
	budget.expenditure = budget.revenue + limit * state.country.economy.gdp + 1.0
	t.truth(EventsSim.condition_met(state, "western_aid_offered"), "nor does a deficit above the fund's target go unnoticed")
	_force(state, "western_aid_strings", ForeignArcs.resolve_target(state, "__western__"))
	var debt := state.country.economy.public_debt_pct
	EventActions.resolve(state, "western_aid_strings", "accept_aid")
	t.near(state.country.economy.public_debt_pct, debt - 0.004, 1e-9, "the aid relieves debt")
	var row: Array = state.scheduled_events.filter(func(r: Dictionary) -> bool: return r["event_id"] == "aid_conditions_due")
	t.equal(row.size(), 1, "and its conditions are set in motion")
	t.equal(int(row[0]["due_turn"]), state.turn + 6, "six months out")
	t.equal(String(row[0]["target_country_id"]), ForeignArcs.resolve_target(state, "__western__"), "owed to the same capital")
```

If `deficit_share_of_gdp()` is computed differently from `(expenditure − revenue) / gdp`, read `godot/scripts/native/state/economy.gd` and set the budget so the deficit share sits just above `limit`; the assertion's meaning is unchanged.

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL / `SCRIPT ERROR` (`isf_review_crisis` unknown, `DELEGATION_MONTHS` undeclared).

- [ ] **Step 3: Add the six events**

```json
{
  "id": "isf_review_crisis", "title": "The Fund Says No",
  "description": "The ISF mission has failed the quarterly review. The disbursement is suspended, the Bank's governor is not taking calls, and the markets have done the arithmetic. The mission chief is still in the capital.",
  "category": "Economic", "condition": "never", "chance": 0.0, "stale_after": 1,
  "options": [
    {"id": "renegotiate", "label": "Renegotiate the programme", "description": "The tranche comes back, the targets tighten, and the bank condition moves later. Everyone will know who asked.", "effects": {}, "relation_deltas": {}, "pc_cost": 0, "follow_up": null, "on_apply": "isf_crisis_renegotiate", "requires": {"orientation_verb": "isf_renegotiate"}},
    {"id": "spending_freeze", "label": "Announce a spending freeze", "description": "A year of frozen budgets, to show the mission before it leaves.", "effects": {"faction_loyalty_deltas": {"@labour": -0.05, "@business": 0.03}, "modifiers": [{"id": "isf_spending_freeze", "target": "budget_expenditure", "magnitude": -40.0, "ramp_duration": 1, "hold_duration": 12, "decay_duration": 0, "institutional": true}]}, "relation_deltas": {}, "pc_cost": 6, "follow_up": null, "on_apply": null, "requires": null},
    {"id": "blame_the_fund", "label": "Blame the Fund", "description": "Foreign accountants who have never wintered here. It plays well at home.", "effects": {"faction_loyalty_deltas": {"@nationalist": 0.04, "@reform": -0.03}}, "relation_deltas": {}, "pc_cost": 0, "follow_up": null, "on_apply": null, "requires": null}
  ],
  "default_option_id": "blame_the_fund", "once": false, "cooldown": 0, "audience": "government", "portfolio": "Finance"
},
{
  "id": "concert_delegation", "title": "The Concert Sends a Delegation",
  "description": "Six officials, two interpreters and a list. The Concert wants procurement law, a court that answers to nobody, and a budget that adds up. In return it will say, in a communique, that Ardenia is on the right road.",
  "category": "Diplomatic", "condition": "concert_delegation_due", "chance": 0.05, "target": "__western__",
  "options": [
    {"id": "embrace", "label": "Embrace the list", "description": "Promise all of it, on camera, and start on the easy half.", "effects": {"faction_loyalty_deltas": {"@labour": -0.03, "@reform": 0.04}}, "relation_deltas": {"__western__": 0.04}, "pc_cost": 6, "follow_up": null, "on_apply": "concert_embrace", "requires": null},
    {"id": "push_back", "label": "Push back on sovereignty", "description": "Ardenia did not leave one union to take dictation from another.", "effects": {"faction_loyalty_deltas": {"@nationalist": 0.04}}, "relation_deltas": {"__western__": -0.05}, "pc_cost": 0, "follow_up": null, "on_apply": null, "requires": null},
    {"id": "note_politely", "label": "Thank them and file it", "description": "A good lunch, a firm handshake, no dates.", "effects": {}, "relation_deltas": {}, "pc_cost": 0, "follow_up": null, "on_apply": null, "requires": null}
  ],
  "default_option_id": "note_politely", "once": false, "cooldown": 24, "audience": "government", "portfolio": "Foreign Affairs"
},
{
  "id": "union_invitation", "title": "An Invitation From the East",
  "description": "The Union's secretariat has sent a letter, in two languages, inviting Ardenia to sit in as an observer. Cheaper gas is mentioned in the second paragraph. The word 'sovereignty' is not mentioned at all.",
  "category": "Diplomatic", "condition": "union_invites", "chance": 0.05, "target": "__union_anchor__",
  "options": [
    {"id": "accept_observer", "label": "Take the observer's seat", "description": "A chair at the table, a flag in the corridor, and a Western ambassador who stops returning calls.", "effects": {}, "relation_deltas": {}, "pc_cost": 0, "follow_up": null, "on_apply": "union_accept", "requires": {"orientation_verb": "union_observer"}},
    {"id": "play_both_sides", "label": "Show the letter to the West", "description": "Let the Concert read it first. Nothing makes a suitor attentive like a rival.", "effects": {"faction_loyalty_deltas": {"@reform": 0.02}}, "relation_deltas": {"__union_anchor__": -0.05}, "pc_cost": 5, "follow_up": null, "on_apply": "union_play_west", "requires": null},
    {"id": "decline", "label": "Decline with thanks", "description": "A polite reply that says not now and means not ever.", "effects": {}, "relation_deltas": {"__union_anchor__": -0.03}, "pc_cost": 0, "follow_up": null, "on_apply": null, "requires": null}
  ],
  "default_option_id": "decline", "once": false, "cooldown": 36, "audience": "government", "portfolio": "Foreign Affairs"
},
{
  "id": "union_pressure", "title": "The Union Expects",
  "description": "The Union's council has a vote coming and a view on how Ardenia will cast it. The message arrived through the energy ministry, which is how everyone knows it is serious.",
  "category": "Diplomatic", "condition": "union_member_pressed", "chance": 0.08, "target": "__union_anchor__",
  "options": [
    {"id": "resist", "label": "Vote with conscience", "description": "Cast the vote Ardenia would cast anyway, and wait for the bill.", "effects": {"faction_loyalty_deltas": {"@nationalist": 0.04}}, "relation_deltas": {"__union_anchor__": -0.08}, "pc_cost": 6, "follow_up": null, "on_apply": null, "requires": null},
    {"id": "threaten_exit", "label": "Mention the door", "description": "Remind them that members can leave, and that leaving would be expensive for everyone.", "effects": {"faction_loyalty_deltas": {"@reform": 0.03}}, "relation_deltas": {"__union_anchor__": -0.12}, "pc_cost": 10, "follow_up": null, "on_apply": null, "requires": null},
    {"id": "comply", "label": "Vote as expected", "description": "It is one vote. It will not be the last one.", "effects": {"faction_loyalty_deltas": {"@nationalist": -0.04}}, "relation_deltas": {"__union_anchor__": 0.03}, "pc_cost": 0, "follow_up": null, "on_apply": "union_comply", "requires": null}
  ],
  "default_option_id": "comply", "once": false, "cooldown": 18, "audience": "government", "portfolio": "Foreign Affairs"
},
{
  "id": "western_aid_strings", "title": "Aid, Conditions Attached",
  "description": "A Western finance minister arrives with a cheque and a binder. The cheque relieves the debt. The binder is the price, and it is due in six months.",
  "category": "Economic", "condition": "western_aid_offered", "chance": 0.05, "target": "__western__",
  "options": [
    {"id": "accept_aid", "label": "Take the money", "description": "Relief now, conditions later. Later always arrives.", "effects": {"one_time_debt_pct_delta": -0.004}, "relation_deltas": {"__western__": 0.03}, "pc_cost": 0, "follow_up": {"event_id": "aid_conditions_due", "delay": 6, "chance": 1.0}, "on_apply": null, "requires": null},
    {"id": "decline", "label": "Decline the binder", "description": "Ardenia will balance its own books, thank you.", "effects": {}, "relation_deltas": {}, "pc_cost": 0, "follow_up": null, "on_apply": null, "requires": null}
  ],
  "default_option_id": "decline", "once": false, "cooldown": 36, "audience": "government", "portfolio": "Finance"
},
{
  "id": "aid_conditions_due", "title": "The Binder Comes Due",
  "description": "Six months on, the donors want to see the conditions met: pension indexation suspended, the state holding company audited, the customs service purged. Their ambassador has a calendar.",
  "category": "Economic", "condition": "never", "chance": 0.0,
  "options": [
    {"id": "deliver", "label": "Deliver the conditions", "description": "Do what was promised, and own every word of it in the regions.", "effects": {"faction_loyalty_deltas": {"@labour": -0.05, "@business": 0.03}}, "relation_deltas": {"__western__": 0.04}, "pc_cost": 8, "follow_up": null, "on_apply": null, "requires": null},
    {"id": "stall", "label": "Stall", "description": "Commissions, consultations, a working group. The donors have seen it before and claw back half.", "effects": {"one_time_debt_pct_delta": 0.002}, "relation_deltas": {"__western__": -0.06}, "pc_cost": 0, "follow_up": null, "on_apply": null, "requires": null}
  ],
  "default_option_id": "stall", "once": false, "cooldown": 0, "audience": "government", "portfolio": "Finance"
}
```

- [ ] **Step 4: Conditions and handlers**

In `foreign_arcs.gd`: extend the three lists and add constants:

```gdscript
const HANDLERS: Array[String] = ["valve_pay", "valve_cargo", "valve_appeal_west", "transit_concede",
	"transit_arbitrate", "windfall_storage", "isf_crisis_renegotiate", "concert_embrace", "union_accept",
	"union_play_west", "union_comply"]
const CONDITIONS: Array[String] = ["transit_dispute_ripe", "transit_windfall_due", "concert_delegation_due",
	"union_invites", "union_member_pressed", "western_aid_offered"]
const EVENT_IDS: Array[String] = ["valve_threat", "transit_dispute", "transit_windfall", "isf_review_crisis",
	"concert_delegation", "union_invitation", "union_pressure", "western_aid_strings", "aid_conditions_due"]
const DELEGATION_MONTHS := 3
const PLAY_WEST := 0.03
const COMPLY_WEST := -0.03
```

Add to the `condition_met` match:

```gdscript
		"concert_delegation_due":
			var r := state.foreign.reached
			return state.player.in_government and r.has("concert_application") and not r.has("concert_agreement") \
				and not r.has("union_observer") and not r.has("union_member")
		"union_invites":
			var r := state.foreign.reached
			var left := state.foreign.union_left_turn
			return state.player.in_government and not r.has("union_observer") and not r.has("union_member") \
				and _score(state, resolve_target(state, "__union_anchor__")) >= OrientationActions.OBSERVER_WARMTH \
				and (left < 0 or state.turn - left >= OrientationActions.UNION_REJOIN_MONTHS)
		"union_member_pressed":
			return state.player.in_government and state.foreign.reached.has("union_member")
		"western_aid_offered":
			var strained := bool(state.foreign.isf.get("suspended", false)) \
				or state.country.economy.deficit_share_of_gdp() > float(OrientationSim.isf_targets(state)["deficit"])
			return state.player.in_government and not state.foreign.reached.has("union_member") and strained
```

Add to the `run` match:

```gdscript
		"isf_crisis_renegotiate":
			return _through(OrientationActions.act(state, "isf_renegotiate"))
		"concert_embrace":
			state.foreign.western_qualifying_months = mini(OrientationActions.QUALIFYING_MONTHS_FOR_AGREEMENT,
				state.foreign.western_qualifying_months + DELEGATION_MONTHS)
			return "The Concert's list becomes the government's programme."
		"union_accept":
			return _through(OrientationActions.act(state, "union_observer"))
		"union_play_west":
			shift(state, "__western__", PLAY_WEST)
			return "The Western embassies read the Union's letter with interest."
		"union_comply":
			shift(state, "__western__", COMPLY_WEST)
			return "Ardenia votes as the Union expects."
```

- [ ] **Step 5: The failed review schedules the crisis**

In `godot/scripts/native/sim/orientation_sim.gd`, in `_isf_review`'s failure branch, after `notes.append(line("isf_fail"))`:

```gdscript
		if state.player.in_government:
			ForeignArcs.schedule(state, "isf_review_crisis", "")
```

Set `test_events.gd:50` to `55`.

- [ ] **Step 6: Run and pass**

Run: `--import`, `test_foreign_situations.gd`, `test_events.gd`, `test_isf_track.gd`, `test_orientation_tracks.gd`.
Expected: all `0 failed`.

- [ ] **Step 7: Mutation-check**

1. Remove the schedule line in `_isf_review`: "the crisis is on the desk in the review month" (calendar-true December → January).
2. Move the schedule line into the pass branch: "and no crisis follows a pass".
3. `>= OrientationActions.OBSERVER_WARMTH` → `>`: "at exactly the observer line the Union invites".
4. `>= UNION_REJOIN_MONTHS` → `>`: "and is invited again the month it ends".
5. Drop `mini(...)`: "but never past what the agreement needs".
6. Drop `not r.has("union_observer")` in `concert_delegation_due`: "but not to a Union observer".
7. Drop the deficit branch of `strained`: "nor does a deficit above the fund's target go unnoticed".
8. `"delay": 6` → `5` in the JSON: "six months out".

- [ ] **Step 8: Full battery, then commit**

```bash
git add godot/scripts/native/sim/foreign_arcs.gd godot/scripts/native/sim/orientation_sim.gd godot/data/native/catalogs/events.json \
  godot/tests/native/test_foreign_situations.gd godot/tests/native/test_events.gd
git commit -m "feat(godot): ISF crisis, Concert delegation, Union invitation and pressure, Western aid with strings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show HEAD --stat
```

---

### Task 4: World situations: a neighbour's coup, a sanctions coalition, an arms offer, the rival's "interests", the refugee flow

**Files:**
- Modify: `godot/scripts/native/sim/foreign_arcs.gd`
- Modify: `godot/data/native/catalogs/events.json` (append four events; edit `refugee_crisis`)
- Modify: `godot/tests/native/test_events.gd:50` (55 → 59)
- Test: `godot/tests/native/test_foreign_situations.gd`

**Interfaces:**
- Consumes: `DiplomacyActions.act(state, verb, country_id)`, `state.foreign.hostile_log` rows `{turn, actor, ...}`, `state.insurgency_pressure`, `Country.stability/regime_type/civil_war_risk`.
- Produces: events `neighbour_coup`, `sanctions_coalition`, `arms_offer`, `rival_interests`; conditions `neighbour_coup_ripe`, `sanctions_coalition_forming`, `arms_offer_open`, `rival_presses_interests`; handlers `coup_recognise`, `coup_condemn`, `coup_wait`, `sanctions_join`, `sanctions_abstain`, `sanctions_oppose`, `arms_buy`, `interests_acknowledge`, `interests_internationalise`; constants `COUP_REGIME` ("authoritarian"), `COUP_ORDER` (0.35), `COUP_CONDEMN_WEST` (0.02), `SANCTIONS_WEST` (0.05), `ABSTAIN_WEST` (−0.03), `OPPOSE_WEST` (−0.06), `ARMS_INSURGENCY` (0.2), `ARMS_RIVAL_LINE` (−0.5), `ARMS_CALM` (0.05), `ARMS_RIVAL` (−0.04), `INTERESTS_LINE` (−0.4), `INTERESTS_MEMORY` (12), `INTERESTS_WEST` (0.04).

- [ ] **Step 1: Write the failing tests**

```gdscript
func _ripe_neighbour(state: GameState) -> Country:
	for c in state.world:
		c.in_civil_war = false
		c.stability = 0.8
		c.civil_war_risk = 0.0
	var c := state.world_country(ForeignArcs.resolve_target(state, "__warmest__"))
	c.regime_type = "hybrid_regime"
	c.stability = 0.2
	return c


func _test_a_coup_happens_whatever_ardenia_says(t) -> void:
	for option in ["recognise", "condemn", "wait_and_see"]:
		var state := _state()
		var c := _ripe_neighbour(state)
		t.truth(EventsSim.condition_met(state, "neighbour_coup_ripe"), "sanity: a fragile neighbour")
		_force(state, "neighbour_coup", c.id)
		state.player.political_capital = 100.0
		EventActions.resolve(state, "neighbour_coup", option)
		t.equal(c.regime_type, ForeignArcs.COUP_REGIME, "%s: the generals hold the capital" % option)
		t.near(c.stability, ForeignArcs.COUP_ORDER, 1e-9, "%s: and impose their order" % option)
		t.truth(not EventsSim.condition_met(state, "neighbour_coup_ripe"), "%s: and the same country has no second coup" % option)


func _test_condemning_a_coup_pleases_the_west(t) -> void:
	var state := _state()
	var c := _ripe_neighbour(state)
	var west := ForeignArcs.resolve_target(state, "__western__")
	_force(state, "neighbour_coup", c.id)
	var w0 := _score(state, west)
	var c0 := _score(state, c.id)
	EventActions.resolve(state, "neighbour_coup", "condemn")
	t.near(_score(state, c.id), c0 - 0.08, 1e-9, "the junta hears the condemnation")
	t.near(_score(state, west), w0 + ForeignArcs.COUP_CONDEMN_WEST + (0.0 if c.id != west else -0.08), 1e-9, "and the West approves")


func _test_joining_a_coalition_is_a_real_sanction_on_the_target(t) -> void:
	var state := _state()
	var west := ForeignArcs.resolve_target(state, "__western__")
	var foe := ForeignArcs.resolve_target(state, "__rival__")
	var foe_c := state.world_country(foe)
	DiplomacySim.shift_between(foe_c, state.world_country(west), -1.0)
	t.equal(ForeignArcs.resolve_target(state, "__concert_foe__"), foe, "sanity: the rival is the Concert's foe")
	state.player.political_capital = 100.0
	_force(state, "sanctions_coalition", foe)
	var w0 := _score(state, west)
	t.truth(EventActions.resolve(state, "sanctions_coalition", "join").get("ok", false), "Ardenia can join (%s)" % EventActions.option_reason(state, EventsSim.option_by_id(EventsSim.event_by_id("sanctions_coalition"), "join"), foe))
	t.truth((state.country.relations[foe] as Country.BilateralRelation).sanctioned, "the target is sanctioned, by the diplomacy desk")
	t.near(state.player.political_capital, 100.0 - float(DiplomacyActions.COSTS["impose_sanctions"]), 1e-9, "charged once")
	t.near(_score(state, west), w0 + ForeignArcs.SANCTIONS_WEST, 1e-9, "and the Concert is grateful")
	t.equal(String(EventsSim.event_by_id("sanctions_coalition")["default_option_id"]), "abstain", "abstaining is the default")


func _test_an_arms_offer_needs_a_threat(t) -> void:
	var state := _state()
	var rival := ForeignArcs.resolve_target(state, "__rival__")
	state.insurgency_pressure = 0.0
	_set_score(state, rival, ForeignArcs.ARMS_RIVAL_LINE + 0.01)
	t.truth(not EventsSim.condition_met(state, "arms_offer_open"), "no insurgency and a tolerable rival, no arms offer")
	_set_score(state, rival, ForeignArcs.ARMS_RIVAL_LINE)
	t.truth(EventsSim.condition_met(state, "arms_offer_open"), "a rival at the line brings one")
	_set_score(state, rival, 0.0)
	state.insurgency_pressure = ForeignArcs.ARMS_INSURGENCY
	t.truth(EventsSim.condition_met(state, "arms_offer_open"), "so does an insurgency at its line")
	_force(state, "arms_offer", ForeignArcs.resolve_target(state, "__warmest__"))
	state.player.political_capital = 100.0
	EventActions.resolve(state, "arms_offer", "buy")
	t.near(state.insurgency_pressure, ForeignArcs.ARMS_INSURGENCY - ForeignArcs.ARMS_CALM, 1e-9, "the arms quieten the insurgency")


func _test_the_rival_presses_its_interests_after_pressing_ardenia(t) -> void:
	var state := _state()
	state.turn = 30
	var rival := ForeignArcs.resolve_target(state, "__rival__")
	_set_score(state, rival, ForeignArcs.INTERESTS_LINE)
	state.foreign.hostile_log.clear()
	t.truth(not EventsSim.condition_met(state, "rival_presses_interests"), "no recent move, no demand")
	state.foreign.hostile_log.append({"turn": state.turn - ForeignArcs.INTERESTS_MEMORY, "actor": rival, "relation": -0.05, "economy": 0.0, "stability": 0.0})
	t.truth(EventsSim.condition_met(state, "rival_presses_interests"), "a move a year ago still counts")
	state.foreign.hostile_log[0]["turn"] = state.turn - ForeignArcs.INTERESTS_MEMORY - 1
	t.truth(not EventsSim.condition_met(state, "rival_presses_interests"), "a move older than that does not")
	state.foreign.hostile_log[0]["turn"] = state.turn
	_set_score(state, rival, ForeignArcs.INTERESTS_LINE + 0.01)
	t.truth(not EventsSim.condition_met(state, "rival_presses_interests"), "a rival warmer than the line makes no demand")


func _test_the_refugee_flow_is_about_the_warring_neighbour(t) -> void:
	var state := _state()
	for c in state.world:
		c.in_civil_war = false
	var war := state.world_country(ForeignArcs.resolve_target(state, "__western__"))
	war.in_civil_war = true
	var notes: Array[String] = []
	EventsSim._arrive(state, EventsSim.event_by_id("refugee_crisis"), "", notes)
	var s: Situation = state.pending_situations[-1]
	t.equal(s.target_country_id, war.id, "the refugees come from the country at war")
	var before := _score(state, war.id)
	state.player.political_capital = 100.0
	EventActions.resolve(state, "refugee_crisis", "open_borders")
	t.near(_score(state, war.id), before + 0.05, 1e-9, "and opening the border is felt there")


func _test_no_foreign_event_names_a_country(t) -> void:
	var ids := {}
	for c in ContentRepository.load_all().get("countries", {}):
		ids[String(c)] = true
	for id in ForeignArcs.EVENT_IDS + ["refugee_crisis"]:
		var e := EventsSim.event_by_id(id)
		t.truth(not e.is_empty(), "%s exists" % id)
		t.truth(not ids.has(String(e.get("target", ""))), "%s declares no literal target" % id)
		for o in e.get("options", []):
			for key in o.get("relation_deltas", {}):
				t.truth(String(key) in EventsSim.TARGET_KEYS, "%s/%s moves only a sentinel (%s)" % [id, o["id"], key])
		t.truth(not (id in ContentRepository.load_all()["catalogs"]["events"]["ardenia_only_events"]), "%s is not bespoke content" % id)
```

If `ContentRepository.load_all()["countries"]` is not keyed by id, read `content_repository.gd` and collect the ids from the same data `GameFactory` uses; the assertion's intent is "no country id from the content".

- [ ] **Step 2: Run to verify it fails**

Expected: `SCRIPT ERROR` (`COUP_REGIME` undeclared).

- [ ] **Step 3: Events**

Append:

```json
{
  "id": "neighbour_coup", "title": "Tanks at a Neighbour's Parliament",
  "description": "Overnight, soldiers took the radio station and the parliament of a fragile neighbour. A general read a statement about order. Every embassy in the capital wants to know what Ardenia will say.",
  "category": "Diplomatic", "condition": "neighbour_coup_ripe", "chance": 0.06, "target": "__fragile__",
  "options": [
    {"id": "recognise", "label": "Recognise the new authorities", "description": "Order on the border is worth more than a constitution that did not hold.", "effects": {"faction_loyalty_deltas": {"@nationalist": 0.02, "@reform": -0.04}}, "relation_deltas": {"__fragile__": 0.05}, "pc_cost": 0, "follow_up": null, "on_apply": "coup_recognise", "requires": null},
    {"id": "condemn", "label": "Condemn the coup", "description": "Ardenia knows what it costs when soldiers decide. Say so.", "effects": {"faction_loyalty_deltas": {"@reform": 0.04}}, "relation_deltas": {"__fragile__": -0.08}, "pc_cost": 4, "follow_up": null, "on_apply": "coup_condemn", "requires": null},
    {"id": "wait_and_see", "label": "Wait and see", "description": "Coups have a way of ending in a second coup. Say nothing until it is clear who is answering the phone.", "effects": {}, "relation_deltas": {}, "pc_cost": 0, "follow_up": null, "on_apply": "coup_wait", "requires": null}
  ],
  "default_option_id": "wait_and_see", "once": false, "cooldown": 24, "audience": "government", "portfolio": "Foreign Affairs"
},
{
  "id": "sanctions_coalition", "title": "The Concert Is Counting Votes",
  "description": "The Concert is assembling a sanctions coalition against a state it has run out of patience with, and has asked Ardenia, politely and in writing, which side of the table it sits on.",
  "category": "Diplomatic", "condition": "sanctions_coalition_forming", "chance": 0.05, "target": "__concert_foe__",
  "options": [
    {"id": "join", "label": "Join the coalition", "description": "Stand with the Concert and pay for it in trade.", "effects": {}, "relation_deltas": {}, "pc_cost": 0, "follow_up": null, "on_apply": "sanctions_join", "requires": {"diplomacy_verb": "impose_sanctions"}},
    {"id": "speak_against", "label": "Speak against sanctions", "description": "Ardenia has lived under other people's embargoes. It will not join one.", "effects": {"faction_loyalty_deltas": {"@nationalist": 0.02}}, "relation_deltas": {"__concert_foe__": 0.05}, "pc_cost": 0, "follow_up": null, "on_apply": "sanctions_oppose", "requires": null},
    {"id": "abstain", "label": "Abstain", "description": "A small country's privilege: to be absent from the room.", "effects": {}, "relation_deltas": {}, "pc_cost": 0, "follow_up": null, "on_apply": "sanctions_abstain", "requires": null}
  ],
  "default_option_id": "abstain", "once": false, "cooldown": 24, "audience": "government", "portfolio": "Foreign Affairs"
},
{
  "id": "arms_offer", "title": "An Offer of Arms",
  "description": "A friendly government has offered rifles, radios and armoured cars on easy terms. The Defense Ministry has already drafted the thank-you letter. The Finance Ministry has not.",
  "category": "Security", "condition": "arms_offer_open", "chance": 0.05, "target": "__warmest__",
  "options": [
    {"id": "buy", "label": "Accept the arms", "description": "The army gets what it has asked for since 1992, and somebody across the line notices.", "effects": {"one_time_debt_pct_delta": 0.003, "faction_loyalty_deltas": {"@nationalist": 0.05}}, "relation_deltas": {"__warmest__": 0.05}, "pc_cost": 5, "follow_up": null, "on_apply": "arms_buy", "requires": null},
    {"id": "decline", "label": "Decline politely", "description": "The army will make do. It always has.", "effects": {}, "relation_deltas": {}, "pc_cost": 0, "follow_up": null, "on_apply": null, "requires": null}
  ],
  "default_option_id": "decline", "once": false, "cooldown": 30, "audience": "government", "portfolio": "Defense"
},
{
  "id": "rival_interests", "title": "Our Neighbour's \"Legitimate Interests\"",
  "description": "After its latest move against Ardenia, the old imperial neighbour has sent a note listing its 'legitimate interests': the language of the border districts, the pipeline's ownership, and who Ardenia may sign treaties with. It asks for a reply that recognises them.",
  "category": "Diplomatic", "condition": "rival_presses_interests", "chance": 0.06, "target": "__rival__",
  "options": [
    {"id": "acknowledge", "label": "Acknowledge their interests", "description": "Words cost little, and these words buy quiet. They also tell the West something.", "effects": {"faction_loyalty_deltas": {"@nationalist": -0.06}}, "relation_deltas": {"__rival__": 0.08}, "pc_cost": 0, "follow_up": null, "on_apply": "interests_acknowledge", "requires": null},
    {"id": "take_it_to_the_concert", "label": "Publish the note in the West", "description": "Let the Concert read what is being demanded of an applicant.", "effects": {"faction_loyalty_deltas": {"@reform": 0.03}}, "relation_deltas": {"__rival__": -0.06}, "pc_cost": 8, "follow_up": null, "on_apply": "interests_internationalise", "requires": null},
    {"id": "reject", "label": "Reject the note", "description": "Ardenia's interests are Ardenia's. Send it back unanswered.", "effects": {"faction_loyalty_deltas": {"@nationalist": 0.03}}, "relation_deltas": {"__rival__": -0.03}, "pc_cost": 0, "follow_up": null, "on_apply": null, "requires": null}
  ],
  "default_option_id": "reject", "once": false, "cooldown": 30, "audience": "government", "portfolio": "Foreign Affairs"
}
```

Edit `refugee_crisis`: add `"target": "__in_civil_war__"`; set `open_borders`'s `relation_deltas` to `{"__in_civil_war__": 0.05}` and `close_border`'s to `{"__in_civil_war__": -0.04}`. Leave every other field unchanged.

- [ ] **Step 4: Conditions and handlers**

Extend the lists:

```gdscript
const HANDLERS: Array[String] = ["valve_pay", "valve_cargo", "valve_appeal_west", "transit_concede",
	"transit_arbitrate", "windfall_storage", "isf_crisis_renegotiate", "concert_embrace", "union_accept",
	"union_play_west", "union_comply", "coup_recognise", "coup_condemn", "coup_wait", "sanctions_join",
	"sanctions_abstain", "sanctions_oppose", "arms_buy", "interests_acknowledge", "interests_internationalise"]
const CONDITIONS: Array[String] = ["transit_dispute_ripe", "transit_windfall_due", "concert_delegation_due",
	"union_invites", "union_member_pressed", "western_aid_offered", "neighbour_coup_ripe",
	"sanctions_coalition_forming", "arms_offer_open", "rival_presses_interests"]
const EVENT_IDS: Array[String] = ["valve_threat", "transit_dispute", "transit_windfall", "isf_review_crisis",
	"concert_delegation", "union_invitation", "union_pressure", "western_aid_strings", "aid_conditions_due",
	"neighbour_coup", "sanctions_coalition", "arms_offer", "rival_interests"]
const COUP_REGIME := "authoritarian"
const COUP_ORDER := 0.35
const COUP_CONDEMN_WEST := 0.02
const SANCTIONS_WEST := 0.05
const ABSTAIN_WEST := -0.03
const OPPOSE_WEST := -0.06
const ARMS_INSURGENCY := 0.2
const ARMS_RIVAL_LINE := -0.5
const ARMS_CALM := 0.05
const ARMS_RIVAL := -0.04
const INTERESTS_LINE := -0.4
const INTERESTS_MEMORY := 12
const INTERESTS_WEST := 0.04
```

Conditions:

```gdscript
		"neighbour_coup_ripe":
			return state.player.in_government and resolve_target(state, "__fragile__") != ""
		"sanctions_coalition_forming":
			return state.player.in_government and resolve_target(state, "__concert_foe__") != ""
		"arms_offer_open":
			var rival := resolve_target(state, "__rival__")
			var threatened := state.insurgency_pressure >= ARMS_INSURGENCY \
				or (rival != "" and _score(state, rival) <= ARMS_RIVAL_LINE)
			return state.player.in_government and threatened and resolve_target(state, "__warmest__") != ""
		"rival_presses_interests":
			var rival := resolve_target(state, "__rival__")
			if not state.player.in_government or rival == "" or _score(state, rival) > INTERESTS_LINE:
				return false
			return state.foreign.hostile_log.any(func(r: Dictionary) -> bool:
				return String(r.get("actor", "")) == rival and state.turn - int(r.get("turn", -999)) <= INTERESTS_MEMORY)
```

Handlers (note `run`'s third parameter is now used, so rename `_target` to `target`):

```gdscript
		"coup_recognise", "coup_wait":
			return _coup(state, target)
		"coup_condemn":
			var line := _coup(state, target)
			shift(state, "__western__", COUP_CONDEMN_WEST)
			return line
		"sanctions_join":
			var line := _through(DiplomacyActions.act(state, "impose_sanctions", target))
			shift(state, "__western__", SANCTIONS_WEST)
			return line
		"sanctions_abstain":
			shift(state, "__western__", ABSTAIN_WEST)
			return "Ardenia abstains, and the Concert notes who did."
		"sanctions_oppose":
			shift(state, "__western__", OPPOSE_WEST)
			return "Ardenia speaks against the coalition."
		"arms_buy":
			state.insurgency_pressure = clampf(state.insurgency_pressure - ARMS_CALM, 0.0, 1.0)
			shift(state, "__rival__", ARMS_RIVAL)
			return "The arms arrive by rail, and the border hears about it."
		"interests_acknowledge":
			shift(state, "__western__", -INTERESTS_WEST)
			return "Ardenia's reply recognises its neighbour's interests. The West reads it twice."
		"interests_internationalise":
			shift(state, "__western__", INTERESTS_WEST)
			return "The note is published in the Western press."
```

and

```gdscript
static func _coup(state: GameState, target: String) -> String:
	var c := state.world_country(target)
	if c == null or not _fragile(c):
		return ""
	c.regime_type = COUP_REGIME
	c.stability = maxf(c.stability, COUP_ORDER)
	return "The generals hold %s's capital." % c.name
```

- [ ] **Step 5: Set the count and run**

Set `test_events.gd:50` to `59`. Run: `--import`, `test_foreign_situations.gd`, `test_events.gd`, `test_world.gd`, `test_diplomacy.gd`.
Expected: all `0 failed`. If `test_events._test_diplomatic_event_stays_about_its_country` or a world test reads `refugee_crisis`'s old empty deltas, it still holds: only the refugee event's own deltas changed.

- [ ] **Step 6: Mutation-check**

1. Drop `_coup` from `coup_wait`: "wait_and_see: the generals hold the capital".
2. `maxf` → plain assignment of `COUP_ORDER`: survives by design when the stability is below; add one case with a neighbour at 0.29 and confirm the result is 0.35, which kills a mutation to `minf`.
3. Pass `""` instead of `target` into `Arcs.run` in `EventsSim.apply_option` (Task 1 mutation 8): "the target is sanctioned, by the diplomacy desk".
4. `<= ARMS_RIVAL_LINE` → `<`: "a rival at the line brings one".
5. `>= ARMS_INSURGENCY` → `>`: "so does an insurgency at its line".
6. `<= INTERESTS_MEMORY` → `<`: "a move a year ago still counts".
7. `> INTERESTS_LINE` → `>=`: "a move a year ago still counts" (the rival sits at the line).
8. Remove `"target": "__in_civil_war__"` from `refugee_crisis`: "the refugees come from the country at war".
9. Put a literal `"krasova"` key in one `relation_deltas`: "moves only a sentinel".

- [ ] **Step 7: Full battery, then commit**

```bash
git add godot/scripts/native/sim/foreign_arcs.gd godot/data/native/catalogs/events.json \
  godot/tests/native/test_foreign_situations.gd godot/tests/native/test_events.gd
git commit -m "feat(godot): coups, sanctions coalitions, arms offers, the rival's interests and a targeted refugee flow

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show HEAD --stat
```

---

### Task 5: The West relief: the Concert fast-tracks the second line

**Files:**
- Modify: `godot/scripts/native/state/gas_contract.gd` (`INT_FIELDS`, new var)
- Modify: `godot/scripts/native/state/gas_validator.gd`
- Modify: `godot/scripts/native/sim/gas_sim.gd` (`FAST_TRACK_MONTHS`, `second_line_months`, `_advance_projects`)
- Modify: `godot/scripts/native/actions/energy_actions.gd` (`_renegotiate` policy branch, `_second_line_status`)
- Modify: `godot/scripts/native/sim/foreign_arcs.gd`
- Modify: `godot/data/native/catalogs/events.json` (append two events)
- Modify: `godot/tests/native/test_events.gd:50` (59 → 61)
- Modify: `godot/tests/native/test_gas_contract.gd:88` (pinned int list)
- Test: `godot/tests/native/test_west_relief.gd` (new)

**Interfaces:**
- Consumes: `GasContract.second_line_started/second_line_volume`, `EnergyActions.act(state, "gas_second_line")`, `ForeignArcs.shift/resolve_target`.
- Produces:
  - `GasContract.second_line_months_saved: int` (0..18, persisted).
  - `GasSim.FAST_TRACK_MONTHS := 18`, `GasSim.second_line_months(g: GasContract) -> int`.
  - Events `concert_energy_offer` and `concert_energy_conditions` (chain-only); condition `west_relief_open`; handlers `west_fast_track`, `west_conditions_stalled`; constants `ForeignArcs.WEST_RELIEF_HOSTILITY` (−0.08), `ForeignArcs.STALLED_SHARE` (0.5), `ForeignArcs.STALLED_OPEN_WEST` (−0.08).

- [ ] **Step 1: Write the failing test**

Create `godot/tests/native/test_west_relief.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const SLOT := "test_west_relief"


static func _state(seed: int = 424242) -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": seed})
	state.rng = SimRng.from_seed(seed)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	return state


static func _wipe() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := "user://saves/%s.json%s" % [SLOT, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


static func _score(state: GameState, id: String) -> float:
	return (state.country.relations[id] as Country.BilateralRelation).score


static func _building(state: GameState) -> GasContract:
	state.player.political_capital = 200.0
	EnergyActions.act(state, "gas_second_line")
	return state.foreign.gas


static func _force(state: GameState, event_id: String, target := "") -> void:
	var s := Situation.new()
	s.event_id = event_id
	s.arrived_turn = state.turn
	s.deadline_turn = state.turn + EventsSim.DECISION_WINDOW_MONTHS
	s.target_country_id = target
	state.pending_situations.append(s)


func _test_the_offer_needs_a_line_with_time_left_to_save(t) -> void:
	var state := _state()
	t.truth(not EventsSim.condition_met(state, "west_relief_open"), "no line, no offer")
	var g := _building(state)
	t.truth(EventsSim.condition_met(state, "west_relief_open"), "a line under construction draws the Concert's offer")
	state.turn = g.second_line_started + GasSim.SECOND_LINE_MONTHS - GasSim.FAST_TRACK_MONTHS - 1
	t.truth(EventsSim.condition_met(state, "west_relief_open"), "with more than eighteen months left it still pays to accelerate")
	state.turn += 1
	t.truth(not EventsSim.condition_met(state, "west_relief_open"), "with exactly eighteen left there is nothing to save")
	state.turn = g.second_line_started
	state.foreign.reached["union_observer"] = state.turn
	t.truth(not EventsSim.condition_met(state, "west_relief_open"), "and never for a Union observer")
	state.foreign.reached.erase("union_observer")
	state.foreign.reached.erase("concert_application")
	t.truth(not EventsSim.condition_met(state, "west_relief_open"), "nor for a state that has not applied")


func _test_accepting_opens_the_line_eighteen_months_early(t) -> void:
	var state := _state()
	var g := _building(state)
	var started := g.second_line_started
	var west := ForeignArcs.resolve_target(state, "__western__")
	_force(state, "concert_energy_offer", west)
	var k0 := _score(state, g.supplier_id)
	t.truth(EventActions.resolve(state, "concert_energy_offer", "accept").get("ok", false), "the offer can be accepted")
	t.equal(g.second_line_months_saved, GasSim.FAST_TRACK_MONTHS, "the build is shortened")
	t.equal(GasSim.second_line_months(g), GasSim.SECOND_LINE_MONTHS - GasSim.FAST_TRACK_MONTHS, "to thirty months")
	t.near(_score(state, g.supplier_id), k0 + ForeignArcs.WEST_RELIEF_HOSTILITY, 1e-9, "and the supplier takes it as hostile")
	var due: Array = state.scheduled_events.filter(func(r: Dictionary) -> bool: return r["event_id"] == "concert_energy_conditions")
	t.equal(due.size(), 1, "the Concert's conditions are set in motion")
	t.equal(int(due[0]["due_turn"]), state.turn + 6, "six months out")
	state.scheduled_events.clear()
	var notes: Array[String] = []
	state.turn = started + GasSim.second_line_months(g) - 1
	GasSim._advance_projects(state, notes)
	t.equal(g.second_line_volume, 0.0, "a month before the shortened date the line is still shut")
	state.turn += 1
	GasSim._advance_projects(state, notes)
	t.truth(g.second_line_volume > 0.0, "on the shortened date it opens")


func _test_the_line_opens_on_the_real_calendar(t) -> void:
	var state := _state()
	var g := _building(state)
	g.second_line_months_saved = GasSim.FAST_TRACK_MONTHS
	var opened := -1
	for _m in range(GasSim.SECOND_LINE_MONTHS):
		NativeGameScript.next_month(state)
		if opened < 0 and g.second_line_volume > 0.0:
			opened = state.turn
	t.equal(opened - g.second_line_started, GasSim.SECOND_LINE_MONTHS - GasSim.FAST_TRACK_MONTHS, "calendar-true, the fast-tracked line opens after thirty months")


func _test_stalling_halves_the_saving_or_costs_the_west(t) -> void:
	var state := _state()
	var g := _building(state)
	g.second_line_months_saved = GasSim.FAST_TRACK_MONTHS
	_force(state, "concert_energy_conditions", ForeignArcs.resolve_target(state, "__western__"))
	t.equal(String(EventsSim.event_by_id("concert_energy_conditions")["default_option_id"]), "stall", "stalling is the default")
	EventActions.resolve(state, "concert_energy_conditions", "stall")
	t.equal(g.second_line_months_saved, int(GasSim.FAST_TRACK_MONTHS * ForeignArcs.STALLED_SHARE), "a stalled state keeps half the saving")
	var open := _state()
	var h := _building(open)
	h.second_line_months_saved = GasSim.FAST_TRACK_MONTHS
	h.second_line_volume = 2.0
	var west := ForeignArcs.resolve_target(open, "__western__")
	_force(open, "concert_energy_conditions", west)
	var w0 := _score(open, west)
	EventActions.resolve(open, "concert_energy_conditions", "stall")
	t.equal(h.second_line_months_saved, GasSim.FAST_TRACK_MONTHS, "an open line cannot be un-built")
	t.near(_score(open, west), w0 + ForeignArcs.STALLED_OPEN_WEST - 0.04, 1e-9, "so the West takes it out in goodwill")


func _test_shelving_the_line_forgets_the_saving(t) -> void:
	var state := _state()
	var g := _building(state)
	g.second_line_months_saved = GasSim.FAST_TRACK_MONTHS
	g.last_renegotiated = -1
	state.player.political_capital = 200.0
	var r := EnergyActions.act(state, "gas_renegotiate_policy")
	t.truth(r.get("ok", false), "the line can be shelved (%s)" % r.get("error", ""))
	t.equal(g.second_line_months_saved, 0, "and the Concert's saving goes with it")
	t.equal(StateValidator.validate(state).size(), 0, "leaving a valid contract")


func _test_the_saving_round_trips_and_validates(t) -> void:
	_wipe()
	var state := _state()
	var g := _building(state)
	g.second_line_months_saved = 9
	t.truth(SaveStore.save_slot(SLOT, state).get("ok", false), "the contract saves")
	var loaded: Dictionary = SaveStore.load_slot(SLOT)
	t.equal((loaded["state"] as GameState).foreign.gas.second_line_months_saved, 9, "the saving survives a binary save")
	_wipe()
	var old := g.to_dict()
	old.erase("second_line_months_saved")
	t.equal(GasContract.from_dict(old).second_line_months_saved, 0, "an old save loads with no saving")
	g.second_line_months_saved = GasSim.FAST_TRACK_MONTHS + 1
	t.truth(Array(StateValidator.validate(state)).any(func(e) -> bool: return String(e).contains("second line saving")), "a saving beyond the Concert's offer is rejected")
	g.second_line_months_saved = -1
	t.truth(Array(StateValidator.validate(state)).any(func(e) -> bool: return String(e).contains("second line saving")), "so is a negative one")
	g.second_line_months_saved = 9
	g.second_line_started = -1
	t.truth(Array(StateValidator.validate(state)).any(func(e) -> bool: return String(e).contains("second line saving")), "and a saving on a line nobody is building")
	g.second_line_months_saved = 0
	t.equal(StateValidator.validate(state).size(), 0, "no saving, no line, no error")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_the_offer_needs_a_line_with_time_left_to_save(t)
	_test_accepting_opens_the_line_eighteen_months_early(t)
	_test_the_line_opens_on_the_real_calendar(t)
	_test_stalling_halves_the_saving_or_costs_the_west(t)
	_test_shelving_the_line_forgets_the_saving(t)
	_test_the_saving_round_trips_and_validates(t)
	quit(t.finish())
```

Task 6 appends the A/B journey to this file.

- [ ] **Step 2: Run to verify it fails**

Expected: `SCRIPT ERROR` (`GasSim.FAST_TRACK_MONTHS` undeclared).

- [ ] **Step 3: The field, its bounds, the build time**

`gas_contract.gd`: append `"second_line_months_saved"` to `INT_FIELDS` and add `var second_line_months_saved: int = 0`. `from_dict` already reads `INT_FIELDS` with defaults. Confirm by reading `gas_contract.gd:55-88`; if it does not default missing keys, make it do so for this field.

`gas_validator.gd`, at the end of `validate` (before the `is_active` return is fine, since the bounds hold for any contract):

```gdscript
	var saved := g.second_line_months_saved
	if saved < 0 or saved > GasSim.FAST_TRACK_MONTHS \
			or (saved > 0 and g.second_line_started < 0 and g.second_line_volume <= 0.0):
		errors.append("gas second line saving is impossible")
```

`gas_sim.gd`: add `const FAST_TRACK_MONTHS := 18` and

```gdscript
static func second_line_months(g: GasContract) -> int:
	return SECOND_LINE_MONTHS - g.second_line_months_saved
```

In `_advance_projects`, replace `state.turn - g.second_line_started >= SECOND_LINE_MONTHS` with `state.turn - g.second_line_started >= second_line_months(g)`.

`energy_actions.gd`: in `_renegotiate`'s `"gas_renegotiate_policy"` branch, after `g.second_line_started = -1`, add `g.second_line_months_saved = 0`. In `_second_line_status`, replace `GasSim.SECOND_LINE_MONTHS` with `GasSim.second_line_months(g)`.

`test_gas_contract.gd:88`: append `"second_line_months_saved"` to the pinned `ints` list.

- [ ] **Step 4: The chain**

Append to `events.json`:

```json
{
  "id": "concert_energy_offer", "title": "The Concert Offers to Build Faster",
  "description": "The Concert's energy commissioner has seen the second line's timetable and offers to put Western contractors and guarantees behind it. It would open a year and a half sooner. The commissioner mentions, in passing, that there will be conditions on the gas market.",
  "category": "Diplomatic", "condition": "west_relief_open", "chance": 0.35, "once": true, "target": "__western__",
  "options": [
    {"id": "accept", "label": "Accept the Concert's help", "description": "Heat without the supplier's leave, eighteen months early. The supplier will read it as what it is.", "effects": {"faction_loyalty_deltas": {"@reform": 0.03}}, "relation_deltas": {"__western__": 0.05}, "pc_cost": 10, "follow_up": {"event_id": "concert_energy_conditions", "delay": 6, "chance": 1.0}, "on_apply": "west_fast_track", "requires": null},
    {"id": "decline", "label": "Build it ourselves", "description": "Slower, and nobody else's line.", "effects": {}, "relation_deltas": {}, "pc_cost": 0, "follow_up": null, "on_apply": null, "requires": null}
  ],
  "default_option_id": "decline", "cooldown": 0, "audience": "government", "portfolio": "Foreign Affairs"
},
{
  "id": "concert_energy_conditions", "title": "The Concert's Gas Conditions",
  "description": "The Concert's help with the second line came with a page about the gas market: unbundle the state gas company, publish the Zovar contract, and let Western suppliers bid. The commissioner would like to see progress.",
  "category": "Diplomatic", "condition": "never", "chance": 0.0,
  "options": [
    {"id": "meet", "label": "Meet the conditions", "description": "Break up the gas company and publish the contract. The supplier's friends in the ministry will not forgive it.", "effects": {"faction_loyalty_deltas": {"@labour": -0.04, "@business": 0.03}}, "relation_deltas": {"__western__": 0.04}, "pc_cost": 8, "follow_up": null, "on_apply": null, "requires": null},
    {"id": "stall", "label": "Stall", "description": "A review of the review. The Concert slows its money to match.", "effects": {}, "relation_deltas": {"__western__": -0.04}, "pc_cost": 0, "follow_up": null, "on_apply": "west_conditions_stalled", "requires": null}
  ],
  "default_option_id": "stall", "once": false, "cooldown": 0, "audience": "government", "portfolio": "Foreign Affairs"
}
```

In `foreign_arcs.gd`: append `"west_fast_track", "west_conditions_stalled"` to `HANDLERS`, `"west_relief_open"` to `CONDITIONS`, and `"concert_energy_offer", "concert_energy_conditions"` to `EVENT_IDS`; add

```gdscript
const WEST_RELIEF_HOSTILITY := -0.08
const STALLED_SHARE := 0.5
const STALLED_OPEN_WEST := -0.08
```

the condition

```gdscript
		"west_relief_open":
			var r := state.foreign.reached
			if not state.player.in_government or not GasSim.is_active(state) or not r.has("concert_application") \
					or r.has("union_observer") or r.has("union_member"):
				return false
			var g := GasSim.gas(state)
			return g.second_line_started >= 0 and g.second_line_volume <= 0.0 and g.second_line_months_saved == 0 \
				and GasSim.second_line_months(g) - (state.turn - g.second_line_started) > GasSim.FAST_TRACK_MONTHS
```

and the handlers

```gdscript
		"west_fast_track":
			var g := GasSim.gas(state)
			if g.second_line_started < 0 or g.second_line_volume > 0.0:
				return ""
			g.second_line_months_saved = GasSim.FAST_TRACK_MONTHS
			shift(state, "__supplier__", WEST_RELIEF_HOSTILITY)
			return "Western contractors arrive on the second line. It will open in %d months." % maxi(0,
				GasSim.second_line_months(g) - (state.turn - g.second_line_started))
		"west_conditions_stalled":
			var g := GasSim.gas(state)
			if g.second_line_volume > 0.0 or g.second_line_started < 0:
				shift(state, "__western__", STALLED_OPEN_WEST)
				return "The Concert notes that its help was banked and its conditions were not."
			g.second_line_months_saved = int(GasSim.FAST_TRACK_MONTHS * STALLED_SHARE)
			return "The Concert slows its money, and the second line slips."
```

Set `test_events.gd:50` to `61`.

- [ ] **Step 5: Run and pass**

Run: `--import`, `test_west_relief.gd`, `test_gas_contract.gd`, `test_energy_actions.gd`, `test_gas_flow.gd`, `test_events.gd`.
Expected: all `0 failed`.

- [ ] **Step 6: Mutation-check**

1. `> GasSim.FAST_TRACK_MONTHS` → `>=` in `west_relief_open`: "with exactly eighteen left there is nothing to save".
2. `_advance_projects` back to `SECOND_LINE_MONTHS`: "on the shortened date it opens", and the calendar test.
3. `>= second_line_months(g)` → `>`: "on the shortened date it opens".
4. Drop `g.second_line_months_saved = 0` in shelving: "and the Concert's saving goes with it".
5. `saved > GasSim.FAST_TRACK_MONTHS` → `>=`: "no saving, no line, no error" survives, so check that the test's 9-month save validates as well; add `t.equal(StateValidator.validate(state).size(), 0, ...)` with the saving at exactly 18 on a building line if this mutation survives.
6. Drop the `second_line_started < 0 and ...` clause: "and a saving on a line nobody is building".
7. Drop the `second_line_volume > 0.0` branch in `west_conditions_stalled`: "an open line cannot be un-built".
8. Remove `"second_line_months_saved"` from `INT_FIELDS`: "the saving survives a binary save".

- [ ] **Step 7: Full battery, then commit**

```bash
git add godot/scripts/native/state/gas_contract.gd godot/scripts/native/state/gas_validator.gd godot/scripts/native/sim/gas_sim.gd \
  godot/scripts/native/actions/energy_actions.gd godot/scripts/native/sim/foreign_arcs.gd godot/data/native/catalogs/events.json \
  godot/tests/native/test_west_relief.gd godot/tests/native/test_west_relief.gd.uid godot/tests/native/test_events.gd \
  godot/tests/native/test_gas_contract.gd
git commit -m "feat(godot): Western energy relief, the Concert fast-tracks the second line

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show HEAD --stat
```

---

### Task 6: Twenty-year journeys: the West relief payoff, foreign-situation coverage, and the record

**Files:**
- Modify: `godot/tests/native/test_west_relief.gd` (the A/B journey)
- Create: `godot/tests/native/test_foreign_situation_journeys.gd`
- Modify: `docs/godot/LIVING_WORLD.md` (new "Foreign situations" section after "Energy"; update the "Known gaps" gas line)

**Interfaces:**
- Consumes: `test_fiscal_journeys.gd: steady_budget(state)`, `test_orientation_journeys.gd: _play(state, strategy)` (strategies `neutral`, `western`, `union`), `ForeignArcs.EVENT_IDS`, `EventActions.resolve`.
- Produces: nothing for later tasks. Task 7 reads the numbers recorded here.

- [ ] **Step 1: Write the A/B relief journey**

Append to `test_west_relief.gd` (and call `_test_the_west_relief_pays(t)` from `_initialize`):

```gdscript
const Journeys = preload("res://tests/native/test_orientation_journeys.gd")
const SEEDS := [919191, 31, 424242, 7]
const MONTHS := 240
const DEPENDENCE_GAIN := 0.2


static func _relief_journey(seed: int, accept: bool) -> Dictionary:
	var state := _state(seed)
	var g := state.foreign.gas
	var offered := -1
	var severity := 0.0
	var share := []
	var lowest_stability := 1.0
	var approval := 0.0
	var invalid := 0
	for m in range(MONTHS):
		Journeys._play(state, "western")
		if g.second_line_started < 0 and g.second_line_volume <= 0.0:
			EnergyActions.act(state, "gas_second_line")
		if state.pending_situations.any(func(s: Situation) -> bool: return s.event_id == "concert_energy_offer"):
			offered = state.turn
			EventActions.resolve(state, "concert_energy_offer", "accept" if accept else "decline")
		if state.pending_situations.any(func(s: Situation) -> bool: return s.event_id == "concert_energy_conditions"):
			EventActions.resolve(state, "concert_energy_conditions", "meet")
		NativeGameScript.next_month(state)
		severity += GasSim.national_severity(state)
		share.append(float(state.foreign.gas_share.get(g.supplier_id, 1.0)))
		lowest_stability = minf(lowest_stability, state.stability_value)
		approval += state.player.approval / float(MONTHS)
		if m % 12 == 11 and not StateValidator.validate(state).is_empty():
			invalid += 1
	return {"offered": offered, "started": g.second_line_started, "saved": g.second_line_months_saved,
		"open": g.second_line_volume > 0.0, "severity": severity, "share": share, "cuts": g.cuts,
		"approval": approval, "lowest_stability": lowest_stability, "invalid": invalid,
		"gdp": state.country.economy.gdp, "krasova": _score(state, g.supplier_id)}


func _test_the_west_relief_pays(t) -> void:
	var accepted := 0
	var relief_severity := 0.0
	var control_severity := 0.0
	for seed in SEEDS:
		var relief := _relief_journey(seed, true)
		var control := _relief_journey(seed, false)
		t.equal(int(relief["invalid"]) + int(control["invalid"]), 0, "seed %d: both journeys stay valid" % seed)
		t.truth(bool(relief["open"]) and bool(control["open"]), "seed %d: both journeys actually build the second line" % seed)
		t.truth(float(relief["approval"]) >= 0.25 and float(relief["lowest_stability"]) >= 0.15, "seed %d: the relief journey is viable" % seed)
		print("relief seed %d: offered %d started %d saved %d severity %.3f/%.3f cuts %d/%d gdp %.0f/%.0f krasova %.3f/%.3f approval %.3f/%.3f" % [
			seed, relief["offered"], relief["started"], relief["saved"], relief["severity"], control["severity"],
			relief["cuts"], control["cuts"], relief["gdp"], control["gdp"], relief["krasova"], control["krasova"],
			relief["approval"], control["approval"]])
		if int(relief["offered"]) < 0:
			continue
		accepted += 1
		var start := int(relief["started"])
		var fast := start + GasSim.SECOND_LINE_MONTHS - int(relief["saved"])
		var slow := start + GasSim.SECOND_LINE_MONTHS
		var gain := 0.0
		for turn in range(fast, slow):
			gain += (float(control["share"][turn - 1]) - float(relief["share"][turn - 1])) / float(slow - fast)
		t.truth(gain >= DEPENDENCE_GAIN, "seed %d: while only the relief has its line, Krasova's gas share is lower by %.2f" % [seed, gain])
		relief_severity += float(relief["severity"])
		control_severity += float(control["severity"])
	t.truth(accepted * 4 >= SEEDS.size() * 3, "the Concert makes its offer on most seeds (%d of %d)" % [accepted, SEEDS.size()])
	t.truth(relief_severity <= control_severity, "summed over seeds, the relief means fewer cold months (%.3f vs %.3f)" % [relief_severity, control_severity])
```

`share[turn - 1]` is the share recorded after the month that closed on `turn` (turn `m + 1` is closed in iteration `m`). If `Journeys._play` is not reachable as a static call through `preload` (the file `extends SceneTree`), copy `_play` and its constants verbatim into this file instead; the same pattern is already used for `FiscalJourneys`.

- [ ] **Step 2: Run it, and record the numbers**

Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_west_relief.gd`
Expected: `0 failed`, and eight `relief seed` lines. If the file exceeds 180 s, move the journey to `godot/tests/native/test_west_relief_journey.gd` (same preload and helpers) and add it to the commit. If the offer arrives on fewer than 3 of 4 seeds, the cause is the content: raise `concert_energy_offer`'s `chance` in 0.05 steps up to 0.6 and rerun. If the summed severity is higher with relief, report the per-seed lines as BLOCKED with the numbers; do not loosen the assertion.

Mutation-check: set `FAST_TRACK_MONTHS` to 0, which must fail the dependence assertion (the gain is 0) or the offer assertion. Set the offer's accept handler to `""` (drop `"on_apply"`), which must fail "Krasova's gas share is lower".

- [ ] **Step 3: Write the coverage journeys**

Create `godot/tests/native/test_foreign_situation_journeys.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const Journeys = preload("res://tests/native/test_orientation_journeys.gd")
const SEEDS := [919191, 31, 424242, 7]
const STRATEGIES := ["neutral", "western", "union"]
const MONTHS := 240
const FOREIGN_SHARE_CEILING := 0.5
const ARRIVALS_PER_FIVE_YEARS := [10, 35]
const NEVER_ROLLED := ["isf_review_crisis", "valve_threat", "aid_conditions_due", "concert_energy_conditions"]


static func _journey(seed: int, strategy: String) -> Dictionary:
	var state := Journeys._state(seed)
	var invalid := 0
	for m in range(MONTHS):
		Journeys._play(state, strategy)
		if strategy == "western" and state.foreign.gas.second_line_started < 0:
			EnergyActions.act(state, "gas_second_line")
		NativeGameScript.next_month(state)
		if m % 12 == 11 and not StateValidator.validate(state).is_empty():
			invalid += 1
	var arrivals := {}
	var governed := 0
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
		var per_five := float(total) * 60.0 / float(MONTHS)
		t.truth(per_five >= ARRIVALS_PER_FIVE_YEARS[0] and per_five <= ARRIVALS_PER_FIVE_YEARS[1], "%s: about twenty decisions in five years (%.1f)" % [key, per_five])
		t.equal(int(runs[key]["invalid"]), 0, "%s: every default leaves a valid state" % key)


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
	_test_seeds_write_different_foreign_desks(t, runs)
	quit(t.finish())
```

`event_history` records only decided or lapsed situations; a situation still pending at month 240 is not counted, which is acceptable. If twelve 240-month runs exceed 180 s, split the strategies across two files (`..._journeys.gd` for neutral and western, `..._union_journeys.gd` for union) with the same helpers, and require coverage over their union by asserting per file only the ids that strategy can reach (Union ids only in the Union file; `concert_energy_offer` only in the western file).

- [ ] **Step 4: Run, measure, fix content only**

Run it. Expected: `0 failed`. On a coverage miss for event `X`, the fix is content: raise `X`'s `chance` (in 0.02 steps, at most 0.15) or relax its own condition only where this plan's rulings allow, and rerun this file plus `test_foreign_situations.gd`. On a pacing miss (`per_five` outside 10–35 or foreign share above half), lower the new events' chances. The constants in this file, including the 10–35 band, are fixed here and are not moved afterwards.

Mutation-check: set every new event's `chance` to 0 locally, which must fail the coverage test for the rolled ids; restore. Change `FOREIGN_SHARE_CEILING` to 0.01, which must fail; restore.

- [ ] **Step 5: Document**

In `docs/godot/LIVING_WORLD.md`, replace the "Known gaps" line "Gas situations (the valve threat as a decision) and Zovar sabotage arrive with plans 3 and 4; ..." with "Zovar sabotage and the escalation ladder arrive with plan 4; the hook is `GasContract.sabotage`." Insert after the "Energy" section:

```markdown
## Foreign situations

**Player-facing job:** foreign affairs arrive as decisions about a named
country, not as weather. Every one can be ignored; ignoring one is a choice
with a price, and the price is small.

- **Fifteen situations, two chains.** The supplier's valve threat, an ISF
  review crisis, a transit dispute and a transit-fee windfall, a Concert
  delegation, the Union's invitation and its pressure on a member, Western
  aid with strings (and its conditions six months on), a neighbour's coup, a
  Concert sanctions coalition, an arms offer, the rival's "legitimate
  interests", and the Concert's offer to fast-track the second line (and
  its gas-market conditions). The refugee crisis is now about the
  neighbour at war.
- **About whom.** Each situation names its country when it arrives:
  the gas supplier, the rival, the Concert's or the Union's anchor, a
  neighbour at war, a neighbour ripe for a coup, the Concert's chosen
  target, or the warmest friend. The names come from live state and the
  foreign catalog; the events name no country.
- **Some cannot be missed.** A valve threat and a failed ISF review put
  their decision on the desk the month they happen, as a follow-up; a
  month later a stale one is dropped instead of delivered.
- **The desks speak for themselves.** An option that pays arrears, buys a
  cargo, renegotiates, joins the Union or sanctions a country is the
  energy, orientation or diplomacy action itself, refused in that desk's
  own words and charged once.
- **A coup happens whatever Ardenia says.** The options are the response.
- **The West's energy relief.** With the Concert application lodged and a
  second line under construction, the Concert offers to fast-track it: the
  line opens after 30 months instead of 48, the bill is unchanged, and
  Krasova takes it as hostile (−0.08). Six months later the Concert's
  gas-market conditions come due; stalling halves the saving.
```

Then add one paragraph with the measured numbers from Step 2 (per seed: offer month, opening month, Krasova gas share while only the relief has its line, summed severity, cuts, GDP, Krasova warmth, approval) and from Step 4 (foreign situations per five years, share of the desk, least-frequent foreign event). Write the numbers as measured, not rounded toward the band.

- [ ] **Step 6: Full battery, then commit**

```bash
git add godot/tests/native/test_west_relief.gd godot/tests/native/test_foreign_situation_journeys.gd \
  godot/tests/native/test_foreign_situation_journeys.gd.uid docs/godot/LIVING_WORLD.md
git commit -m "test(godot): twenty-year foreign situation journeys and the West relief payoff

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show HEAD --stat
```

Add any content-tuning edits to `events.json` from Steps 2 and 4 to this commit, and name them in the message body.

---

### Task 7: Re-run every calibration band

**Files:**
- Modify (only if a band misses because of this plan's content): `godot/data/native/catalogs/events.json`
- Modify: `docs/godot/LIVING_WORLD.md` (calibration record under "Foreign situations")

**Interfaces:**
- Consumes: everything above. Produces: the record.

- [ ] **Step 1: Run every band and invariant**

Run each file below with `timeout 180 "$G" --headless --path godot --script res://tests/native/<file>` and keep the full output:

| Band / invariant | File |
|---|---|
| Elections: steady player 0.40–0.72 (owner's ruling), AI that won power, 1997 steady and schemer-removing governments, opposition start's opening government, player who won from opposition | `test_polls.gd`, `test_election_calibration.gd`, `test_elections.gd` |
| ISF demanding but passable; orientation journeys (viable, goals, price, gas shapes, seeds diverge, determinism) | `test_isf_track.gd`, `test_orientation_journeys.gd` |
| Fiscal regression | `test_fiscal_journeys.gd` |
| Energy journeys and supplier ladder | `test_gas_flow.gd`, `test_gas_shortfall.gd`, `test_gas_supplier.gd`, `test_energy_actions.gd`, `test_energy_snapshot.gd` |
| Canon: feud on 6 seeds within 15 years (mean year-10 ≤ −0.6), courted harm ≤ neglected, Krasova presses across a decade, every threat foreshadowed, a warmer rival waits longer | `test_world.gd`, `test_foreign_spine.gd`, `test_world_blocs.gd` |
| Energy probe (cuts ≤ 5 per 20 years on 919191/31/424242/7) | `energy_probe.gd` (prints; compare with the "Energy calibration" paragraph in `LIVING_WORLD.md`) |
| This plan | `test_foreign_situations.gd`, `test_west_relief.gd`, `test_foreign_situation_journeys.gd` |

Then run the full battery.

- [ ] **Step 2: On a miss, attribute it**

For each failing band, check whether this plan's content causes it. Locally (never committed), set `"chance": 0.0` on the twelve rolled new events and remove the two `ForeignArcs.schedule` calls, then rerun that band's file.
- Green without the content: the cause is this plan's content. Fix the content, not the band. In this order: lower the offending events' chances; make a default milder (smaller relation delta, no faction effect); narrow a condition (for example, require `turn >= GAS_SITUATION_TURN` on another event). Rerun the band and every file of this plan after each change, and stop at the first change that turns the band green.
- Still red without the content: the cause is not this plan. Restore the content and stop. Report **BLOCKED**, naming the band, the measured value, and the run with the content zeroed.

Bands are never widened, and no constant outside `events.json` and `foreign_arcs.gd` is changed to make one pass.

- [ ] **Step 3: Record**

Add a paragraph "**Foreign situations calibration (plan 3 Task 7).**" under "Foreign situations" in `LIVING_WORLD.md`. For every band, give its measured value (for example "steady player 41/78 (0.53) pass; AI that won power 14/30 pass; ..."), the energy probe's cuts per seed, and the feud month per seed. Name every content change made in Step 2, with its before and after values.

- [ ] **Step 4: Full battery, then commit**

```bash
git add docs/godot/LIVING_WORLD.md godot/data/native/catalogs/events.json
git commit -m "test(godot): re-measure every calibration band under foreign situations

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git show HEAD --stat
```

Stage `events.json` only if Step 2 changed it.

---

## Self-review

- **Spec coverage (section 4):**

  | Requirement | Task |
  |---|---|
  | Valve threat | 2 |
  | ISF review crisis | 3 |
  | Transit dispute | 2 |
  | Refugee flow (re-targeted) | 4 |
  | A neighbour's coup | 4 |
  | Sanctions coalition | 4 |
  | Arms offer | 4 |
  | The rival's "interests" | 4 |
  | Concert delegation | 3 |
  | Union invitation | 3 |
  | Union pressure | 3 |
  | Western aid with strings, plus its chain | 3 |
  | Transit-fee windfall | 2 |
  | Concrete targets through relation-target resolution | 1 |
  | Once/cooldown, follow-ups, two-month lapse, ungated defaults, identity and action gating | 1–5, with the catalog integrity test |
  | No literal ids | 4's lint |
  | West relief path through a chain and the existing EnergyActions | 5 |
  | A journey that builds the line and measures the payoff | 6 |
  | Every band re-run | 7 |
  | Persistence and validation | 1 (targets), 5 (saving) |
  | Spec testing: seeds diverge, determinism, bounded | 6 (signatures, validity); the existing orientation determinism test runs with the new content in Task 7 |

- **Types:** `ForeignArcs.run(state, handler_id, target)` everywhere; `Arcs.run(state, handler_id, target := "")`; `EventsSim.gate_reason(state, option, target := "")`; `EventActions.option_reason(state, option, target := "")`; `GasSim.second_line_months(g)`; `GasContract.second_line_months_saved: int`.
