# International Gameplay 1: Orientation and the Shared Spine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Ardenia a foreign orientation it chooses and lives with: per-power dependence, commitment and leverage, plus the ISF, Western and Krasovan Economic Union tracks, the hard locks, AI bloc memberships, persistence, validation, a Diplomacy desk section and calendar-true journeys.

**Architecture:** One persisted ledger, `ForeignState`, hangs off `GameState.foreign`. `ForeignSim` owns the spine (catalog lookups, seeding, dependence/commitment/leverage, the monthly update) and `OrientationSim` owns the track mechanics that run inside the month (ISF reviews, Western discipline, AI bloc drift). Every player step is one input-free call, `OrientationActions.act(state, verb)`, reached from the GUI through `NativeGame.orientation_act`. Names and prose live in a new native catalog, `catalogs/foreign_orientation.json`; tuning numbers are `const`s beside the code that uses them, as in `DiplomacyActions`.

**Tech Stack:** Godot 4.7.2, statically typed GDScript, headless `SceneTree` test scripts using `TestSupport`.

**Spec:** `docs/superpowers/specs/2026-10-29-international-gameplay-design.md` (this plan is delivery item 1 only).

## Global Constraints

- `G="/d/AI Stuff/Godot/Godot_v4.7.2-stable_win64_console.exe"`. Run everything from `/d/Political Sim Game/.worktrees/godot-native-sim`.
- Every test command is `timeout 180 "$G" --headless --path godot --script res://...` and must print `NATIVE TESTS: N passed, 0 failed` with no `SCRIPT ERROR`. A script that fails to compile never quits headless, so a timeout (exit 124) with `SCRIPT ERROR` is the expected "red" for a test that references code that does not exist yet.
- Run `timeout 180 "$G" --headless --path godot --import` after adding any file, then `git add` the generated `.uid` files with it.
- The full battery runs after every task, and every line must report 0 failed with no `SCRIPT ERROR`, `EXIT` or `FAIL` line (the vertical slice prints `PASS:` lines and must exit 0):

```bash
G="/d/AI Stuff/Godot/Godot_v4.7.2-stable_win64_console.exe"
for f in godot/tests/native/test_*.gd godot/tests/native/run_contract_tests.gd godot/tests/ui/test_*.gd godot/tests/map/test_*.gd godot/scripts/tests/vertical_slice_test.gd; do
  out=$(timeout 180 "$G" --headless --path godot --script "res://${f#godot/}" 2>&1); code=$?
  echo "$f: $(echo "$out" | grep -E 'NATIVE TESTS|SCRIPT ERROR|FAIL' | tr '\n' ' ')"
  [ $code -eq 0 ] || echo "EXIT $code: $f"
done
```

- Mutation-check every new test: break the guarded line named in the task, rerun that test file, see the named assertion fail, restore the line, rerun green. Each task lists its mutations.
- No explanatory comments in new code (the owner's hard rule). No `#` comment lines, no doc comments.
- Determinism: never roll an outcome. Everything in this plan is a function of tracked state; it draws no RNG at all. Any future RNG comes only from `state.rng` (the saved campaign stream).
- Persistence: every new field round-trips through `SaveStore` (binary `store_var` of `to_dict`), and saves without the new data load with defaults (`ForeignSim.ensure`). `StateValidator` rejects gauges outside 0..1, negative counters, invalid lock combinations and unknown power, milestone, bloc and country ids.
- Tests never use save slot `godot_slice`. Each test file that saves uses its own slot named after the file and wipes `.json`, `.json.tmp` and `.json.bak` afterwards.
- UI follows the existing desk conventions (`app.gd` refresh pattern, `REFUSED / reason` status, disabled buttons carry their reason as tooltip and a `Muted` label) and the pixel UI system: no new colours outside `UiPalette`, bars only for bounded 0..1 higher-is-better values. Dependence, commitment and leverage are not higher-is-better, so they are figures, never bars.
- Commit messages are conventional (`feat:`, `test:`, `docs:`) and end with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Rulings on spec gaps (binding for this plan)

1. **Powers.** Five: `krasova` (state), `isf` (institution), `concert`, `meridian`, `union` (blocs). A bloc's relations are read through its anchor country (`solheim` for the Concert and Meridian, `krasova` for the Union); the ISF has no anchor and reads as neutral.
2. **Dependence** = `0.5 * gas_share + 0.25 * debt_share + 0.25 * export_share`, clamped. `gas_share` is a stored per-power number seeded from the catalog (Krasova 1.0); plan 2 (energy) owns updating it. **Commitment** = the highest milestone weight reached on that power's track; a state power adds its treaty weights plus half the commitment of any bloc it anchors. **Leverage** = `dependence * (0.75 - 0.25 * warmth) * (1 + 0.25 * gas_share in October–March)`, clamped.
3. **ISF "renegotiation situation".** Situations belong to plan 3. Here a failed review suspends the programme and makes the input-free step `isf_renegotiate` available; plan 3 wraps it in a situation whose option calls `OrientationActions.act(state, "isf_renegotiate")` through an `Arcs` handler. Investor confidence is a `gdp_growth` modifier; a disbursement is a three-month `budget_revenue` inflow whose total is recorded as debt the ISF holds.
4. **Union benefits that need gas** (discount, arrears) are deferred to plan 2. Membership now gives open markets (a phased growth modifier) and debt rescheduling (a contractual `budget_expenditure` saving); tariff alignment caps trade with Concert members at 60% of its ceiling.
5. **"Vetrenka resolved"** means `campaign_meta.vetrenka_status` is `settled`, `retaken` or `partitioned`. Unset, `talks_failed`, `routed` and `partitioned_contested` are active disputes.
6. **Hard locks** bind membership only: `union_member` excludes `concert_agreement` and `meridian_guarantee`. Observers are unrestricted, and a member may hold the application and the partnership.
7. **Union consent** is a refusal: a member cannot sanction or condemn a fellow member, nor sign a defence pact outside the bloc.
8. **Leverage in the world AI.** A hostile move against the player hits harder by `1 + 0.5 * leverage`; a Meridian guarantee shields like a defence pact. Coercive gas moves are plan 2.
9. **Journeys.** "At least 12 seeds, one each for three strategies" is 4 seeds × 3 strategies = 12 twenty-year runs.
10. **Content source.** `foreign_orientation.json` is a native-only catalog; the retired Python exporter does not produce it.

## Interfaces for later plans

- Plan 2 (energy) writes `state.foreign.gas_share[power_id]` (0..1) and adds snapshot `foreign.map.gas_supply` (`{region_id: ratio}`); it reads `ForeignSim.leverage(state, "krasova")` and `state.foreign.reached.has("union_member")`.
- Plan 3 (situations) calls `OrientationActions.act(state, verb)` and `OrientationActions.reason_for(state, verb)` from `Arcs` handlers; it reads `state.foreign.isf["suspended"]`.
- Plan 4 (pressure) adds `ForeignState.tension` (`{power_id: float}`, persisted and validated the same way as `powers`), snapshot `foreign.map.tension` and `foreign.map.incidents` (`{region_id: [incident ids]}`), and reads `ForeignSim.leverage_of(state, actor_id)` inside `WorldSim`.

## File structure

| File | Responsibility |
|---|---|
| `godot/data/native/catalogs/foreign_orientation.json` (new) | Powers, blocs, milestones, dispatch lines |
| `godot/data/native/catalog_manifest.json` | Register the catalog |
| `godot/scripts/native/state/foreign_state.gd` (new) | The persisted ledger and its `to_dict`/`from_dict` |
| `godot/scripts/native/state/game_state.gd` | `foreign` field and its round trip |
| `godot/scripts/native/state/state_validator.gd` | `_validate_foreign` |
| `godot/scripts/native/sim/foreign_sim.gd` (new) | Catalog lookups, seeding, the spine, monthly entry point, tariff share, locks |
| `godot/scripts/native/sim/orientation_sim.gd` (new) | ISF reviews, Western discipline, AI bloc drift |
| `godot/scripts/native/actions/orientation_actions.gd` (new) | Player steps, refusals, consent, read model |
| `godot/scripts/native/sim/diplomacy_sim.gd` | Tariff alignment |
| `godot/scripts/native/actions/diplomacy_actions.gd` | Union consent |
| `godot/scripts/native/sim/world_sim.gd` | Leverage-scaled pressure, guarantee shield |
| `godot/scripts/native/native_game.gd` | Month order, `orientation_act`, seeding on new/load, snapshot |
| `godot/scenes/panels/diplomacy_panel.tscn`, `godot/scripts/app.gd` | Orientation section of the Diplomacy desk |
| `docs/godot/LIVING_WORLD.md` | Orientation section |

---

### Task 1: The foreign ledger, its catalog, persistence and validation

**Files:**
- Create: `godot/data/native/catalogs/foreign_orientation.json`
- Modify: `godot/data/native/catalog_manifest.json`
- Create: `godot/scripts/native/state/foreign_state.gd`
- Create: `godot/scripts/native/sim/foreign_sim.gd`
- Modify: `godot/scripts/native/state/game_state.gd` (field near `var opposition`, `to_dict`, `from_dict` after the opposition block)
- Modify: `godot/scripts/native/state/state_validator.gd` (`validate` and two new helpers)
- Test: `godot/tests/native/test_foreign_state.gd`

**Interfaces:**
- Consumes: `ContentRepository.load_all()`, `GameState.world_country(id)`, `SaveStore.save_slot/load_slot`.
- Produces:
  - `class_name ForeignState` with `powers: Dictionary` (`{power_id: {"dependence": float, "commitment": float, "leverage": float}}`), `gas_share: Dictionary` (`{power_id: float}`), `reached: Dictionary` (`{milestone_id: int turn}`), `members: Dictionary` (`{bloc_id: Array of country id String}`), `isf: Dictionary` (keys of `default_isf()`), `western_qualifying_months: int`, `union_left_turn: int`, `seeded: bool`; `static func default_isf() -> Dictionary`; `func to_dict() -> Dictionary`; `static func from_dict(data: Variant) -> ForeignState` (null data gives a fresh, unseeded ledger; malformed data gives null).
  - `GameState.foreign: ForeignState`.
  - `class_name ForeignSim`: `UNION_LOCKS: Array`, `UNION_LOCKED_BLOCS: Array`, `catalog() -> Dictionary`, `power_ids() / milestone_ids() / bloc_ids() -> Array[String]`, `power(id) / milestone(id) / bloc(id) -> Dictionary`, `milestone_name(id) -> String`, `ensure(state: GameState) -> void`.

- [ ] **Step 1: Write the failing test**

Create `godot/tests/native/test_foreign_state.gd`:

```gdscript
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


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_the_catalog_is_coherent(t)
	_test_a_new_campaign_opens_with_the_canon_obligations(t)
	_test_seeding_twice_never_resets_progress(t)
	_test_the_ledger_round_trips_through_a_binary_save(t)
	_test_an_old_save_gains_the_ledger_on_load(t)
	_test_the_validator_rejects_impossible_ledgers(t)
	quit(t.finish())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_foreign_state.gd`
Expected: `SCRIPT ERROR` naming `ForeignSim` as undeclared, then exit 124 (compile failure never quits).

- [ ] **Step 3: Write the catalog**

Create `godot/data/native/catalogs/foreign_orientation.json`:

```json
{
  "powers": [
    {"id": "krasova", "name": "Krasova", "kind": "state", "anchor": "krasova", "gas_share": 1.0},
    {"id": "isf", "name": "International Stabilisation Fund", "kind": "institution", "anchor": "", "gas_share": 0.0},
    {"id": "concert", "name": "The Concert", "kind": "bloc", "anchor": "solheim", "gas_share": 0.0},
    {"id": "meridian", "name": "The Meridian Treaty Organisation", "kind": "bloc", "anchor": "solheim", "gas_share": 0.0},
    {"id": "union", "name": "The Krasovan Economic Union", "kind": "bloc", "anchor": "krasova", "gas_share": 0.0}
  ],
  "blocs": [
    {"id": "concert", "seed_members": ["solheim", "nueva_costa"], "agendas": ["trader", "reformer"], "families": ["democratic"], "requires": "", "excludes": ["union"], "min_stability": 0.45, "min_warmth": 0.2, "leave_stability": 0.3, "leave_warmth": -0.2},
    {"id": "meridian", "seed_members": ["solheim", "nueva_costa"], "agendas": ["trader", "reformer"], "families": ["democratic"], "requires": "concert", "excludes": ["union"], "min_stability": 0.5, "min_warmth": 0.3, "leave_stability": 0.3, "leave_warmth": -0.1},
    {"id": "union", "seed_members": ["krasova"], "agendas": ["revanchist", "hegemon"], "families": ["autocratic", "hybrid"], "requires": "", "excludes": ["concert", "meridian"], "min_stability": 0.3, "min_warmth": 0.1, "leave_stability": 0.2, "leave_warmth": -0.3}
  ],
  "milestones": [
    {"id": "isf_programme", "track": "isf", "power": "isf", "name": "ISF stabilisation programme", "commitment": 0.4, "starts_reached": true, "body": "The agreement the Baran Council signed in December 1992. Quarterly reviews judge the deficit, inflation and, in time, the Bank's independence."},
    {"id": "concert_application", "track": "western", "power": "concert", "name": "Concert association application", "commitment": 0.15, "starts_reached": true, "body": "Ardenia's application to the Concert's association process is lodged. Admission is a decade away."},
    {"id": "concert_agreement", "track": "western", "power": "concert", "name": "Concert association agreement", "commitment": 0.5, "starts_reached": false, "body": "The agreement binds Ardenia to Concert rules on budgets and markets, and opens those markets in return."},
    {"id": "meridian_partnership", "track": "western", "power": "meridian", "name": "Meridian partnership", "commitment": 0.3, "starts_reached": false, "body": "Officers trained, exercises observed, no promises made."},
    {"id": "meridian_guarantee", "track": "western", "power": "meridian", "name": "Meridian security guarantee", "commitment": 0.7, "starts_reached": false, "body": "An attack on Ardenia is now an attack on the alliance."},
    {"id": "union_observer", "track": "union", "power": "union", "name": "Krasovan Economic Union observer status", "commitment": 0.3, "starts_reached": false, "body": "Ardenia hears the Union's plans and is asked for nothing yet."},
    {"id": "union_member", "track": "union", "power": "union", "name": "Krasovan Economic Union membership", "commitment": 0.8, "starts_reached": false, "body": "Open markets to the east, rescheduled debts, and a common tariff set in Krasova."}
  ],
  "lines": {
    "isf_pass": "The ISF mission signs off the quarterly review, and the next tranche is released.",
    "isf_fail": "The ISF mission refuses to sign off the quarterly review. The tranche is suspended until terms are agreed.",
    "bloc_join": "{country} joins {bloc}.",
    "bloc_leave": "{country} leaves {bloc}."
  }
}
```

In `godot/data/native/catalog_manifest.json`, add `"catalogs/foreign_orientation.json",` to `files` directly after `"catalogs/events.json",`, and add `"catalogs/foreign_orientation.json": 15,` to `id_counts` directly after the `events.json` entry.

- [ ] **Step 4: Write `ForeignState`**

Create `godot/scripts/native/state/foreign_state.gd`:

```gdscript
class_name ForeignState
extends RefCounted


var powers: Dictionary = {}
var gas_share: Dictionary = {}
var reached: Dictionary = {}
var members: Dictionary = {}
var isf: Dictionary = default_isf()
var western_qualifying_months: int = 0
var union_left_turn: int = -1
var seeded: bool = false


static func default_isf() -> Dictionary:
	return {"reviews_held": 0, "passed": 0, "failed": 0, "renegotiations": 0,
		"suspended": false, "disbursed": 0.0, "last_review_turn": -1, "last_result": ""}


func to_dict() -> Dictionary:
	return {
		"powers": powers.duplicate(true),
		"gas_share": gas_share.duplicate(),
		"reached": reached.duplicate(),
		"members": members.duplicate(true),
		"isf": isf.duplicate(),
		"western_qualifying_months": western_qualifying_months,
		"union_left_turn": union_left_turn,
		"seeded": seeded,
	}


static func from_dict(data: Variant) -> ForeignState:
	var out := ForeignState.new()
	if data == null:
		return out
	if not (data is Dictionary):
		push_error("ForeignState.from_dict: expected a Dictionary")
		return null
	var d: Dictionary = data
	for field in ["powers", "gas_share", "reached", "members", "isf"]:
		if not (d.get(field, {}) is Dictionary):
			push_error("ForeignState.from_dict: malformed %s" % field)
			return null
	var power_rows: Dictionary = d.get("powers", {})
	for id in power_rows:
		var row: Variant = power_rows[id]
		if not (row is Dictionary):
			push_error("ForeignState.from_dict: malformed power '%s'" % id)
			return null
		out.powers[String(id)] = {"dependence": float(row.get("dependence", 0.0)),
			"commitment": float(row.get("commitment", 0.0)), "leverage": float(row.get("leverage", 0.0))}
	var shares: Dictionary = d.get("gas_share", {})
	for id in shares:
		out.gas_share[String(id)] = float(shares[id])
	var milestones: Dictionary = d.get("reached", {})
	for id in milestones:
		out.reached[String(id)] = int(milestones[id])
	var blocs: Dictionary = d.get("members", {})
	for id in blocs:
		if not (blocs[id] is Array):
			push_error("ForeignState.from_dict: malformed members of '%s'" % id)
			return null
		var ids: Array = []
		for country_id in blocs[id]:
			ids.append(String(country_id))
		out.members[String(id)] = ids
	var isf_data: Dictionary = d.get("isf", {})
	for key in out.isf.keys():
		if not isf_data.has(key):
			continue
		match typeof(out.isf[key]):
			TYPE_INT:
				out.isf[key] = int(isf_data[key])
			TYPE_FLOAT:
				out.isf[key] = float(isf_data[key])
			TYPE_BOOL:
				out.isf[key] = bool(isf_data[key])
			_:
				out.isf[key] = String(isf_data[key])
	out.western_qualifying_months = int(d.get("western_qualifying_months", 0))
	out.union_left_turn = int(d.get("union_left_turn", -1))
	out.seeded = bool(d.get("seeded", false))
	return out
```

- [ ] **Step 5: Write `ForeignSim` (catalog and seeding)**

Create `godot/scripts/native/sim/foreign_sim.gd`:

```gdscript
class_name ForeignSim
extends RefCounted


const UNION_LOCKS := ["concert_agreement", "meridian_guarantee"]
const UNION_LOCKED_BLOCS := ["concert", "meridian"]


static func catalog() -> Dictionary:
	var data: Variant = ContentRepository.load_all().get("catalogs", {}).get("foreign_orientation", {})
	return data if data is Dictionary else {}


static func _ids(section: String) -> Array[String]:
	var out: Array[String] = []
	for row in catalog().get(section, []):
		out.append(String(row.get("id", "")))
	return out


static func _row(section: String, id: String) -> Dictionary:
	for row in catalog().get(section, []):
		if String(row.get("id", "")) == id:
			return row
	return {}


static func power_ids() -> Array[String]:
	return _ids("powers")


static func milestone_ids() -> Array[String]:
	return _ids("milestones")


static func bloc_ids() -> Array[String]:
	return _ids("blocs")


static func power(id: String) -> Dictionary:
	return _row("powers", id)


static func milestone(id: String) -> Dictionary:
	return _row("milestones", id)


static func bloc(id: String) -> Dictionary:
	return _row("blocs", id)


static func milestone_name(id: String) -> String:
	return String(milestone(id).get("name", id))


static func ensure(state: GameState) -> void:
	var f := state.foreign
	if f.seeded:
		return
	for p in catalog().get("powers", []):
		f.gas_share[String(p["id"])] = float(p.get("gas_share", 0.0))
	for m in catalog().get("milestones", []):
		if bool(m.get("starts_reached", false)):
			f.reached[String(m["id"])] = state.turn
	for b in catalog().get("blocs", []):
		var ids: Array = []
		for country_id in b.get("seed_members", []):
			if state.world_country(String(country_id)) != null:
				ids.append(String(country_id))
		f.members[String(b["id"])] = ids
	f.isf = ForeignState.default_isf()
	f.seeded = true
```

- [ ] **Step 6: Wire `GameState`**

In `godot/scripts/native/state/game_state.gd`, add after `var opposition: OppositionState = OppositionState.new()`:

```gdscript
var foreign: ForeignState = ForeignState.new()
```

In `to_dict()`, add after `"opposition": opposition.to_dict(),`:

```gdscript
		"foreign": null if foreign == null else foreign.to_dict(),
```

In `from_dict()`, add directly after the block ending `push_error("GameState.from_dict: malformed opposition")` / `return null`:

```gdscript
	state.foreign = ForeignState.from_dict(data.get("foreign", null))
	if state.foreign == null:
		push_error("GameState.from_dict: malformed foreign ledger")
		return null
```

- [ ] **Step 7: Wire the validator**

In `godot/scripts/native/state/state_validator.gd`, in `validate`, add after `_validate_opposition_out_of_government(state, errors)`:

```gdscript
	_validate_foreign(state, errors)
```

Append to the file:

```gdscript
static func _foreign_unit(v: Variant) -> bool:
	var x := float(v)
	return is_finite(x) and x >= 0.0 and x <= 1.0


static func _validate_foreign(state: GameState, errors: Array[String]) -> void:
	var f := state.foreign
	if f == null:
		errors.append("foreign ledger is missing")
		return
	if not f.seeded:
		return
	var powers := ForeignSim.power_ids()
	for id in f.powers:
		if not (String(id) in powers):
			errors.append("unknown foreign power '%s'" % id)
			continue
		var row: Variant = f.powers[id]
		if not (row is Dictionary):
			errors.append("foreign power '%s' is malformed" % id)
			continue
		for field in ["dependence", "commitment", "leverage"]:
			if not _foreign_unit(row.get(field, 0.0)):
				errors.append("foreign power '%s' %s out of range" % [id, field])
	for id in f.gas_share:
		if not (String(id) in powers):
			errors.append("unknown foreign power '%s'" % id)
		elif not _foreign_unit(f.gas_share[id]):
			errors.append("foreign gas_share out of range for '%s'" % id)
	var milestones := ForeignSim.milestone_ids()
	for id in f.reached:
		if not (String(id) in milestones):
			errors.append("unknown milestone '%s'" % id)
		elif int(f.reached[id]) > state.turn:
			errors.append("milestone '%s' reached in the future" % id)
	if f.reached.has("union_member"):
		if not f.reached.has("union_observer"):
			errors.append("union_member without observer status")
		for locked in ForeignSim.UNION_LOCKS:
			if f.reached.has(locked):
				errors.append("union membership is locked out by '%s'" % locked)
	_validate_foreign_blocs(state, errors)
	var isf := f.isf
	var held := int(isf.get("reviews_held", 0))
	var passed := int(isf.get("passed", 0))
	var failed := int(isf.get("failed", 0))
	var disbursed := float(isf.get("disbursed", 0.0))
	if held < 0 or passed < 0 or failed < 0 or passed + failed != held \
			or int(isf.get("renegotiations", 0)) < 0 or not is_finite(disbursed) or disbursed < 0.0 \
			or not (String(isf.get("last_result", "")) in ["", "passed", "failed"]):
		errors.append("isf ledger is impossible")
	if f.western_qualifying_months < 0 or f.union_left_turn < -1 or f.union_left_turn > state.turn:
		errors.append("foreign counters are impossible")


static func _validate_foreign_blocs(state: GameState, errors: Array[String]) -> void:
	var blocs := ForeignSim.bloc_ids()
	for bloc_id in state.foreign.members:
		if not (String(bloc_id) in blocs):
			errors.append("unknown bloc '%s'" % bloc_id)
			continue
		for country_id in state.foreign.members[bloc_id]:
			var id := String(country_id)
			if id == state.country.id:
				errors.append("bloc '%s' lists the player country" % bloc_id)
			elif state.world_country(id) == null:
				errors.append("bloc '%s' has unknown member '%s'" % [bloc_id, id])
	for country_id in state.foreign.members.get("union", []):
		for other in ForeignSim.UNION_LOCKED_BLOCS:
			if country_id in state.foreign.members.get(other, []):
				errors.append("bloc membership is exclusive for '%s'" % country_id)
```

- [ ] **Step 8: Import and run the test to verify it passes**

Run: `timeout 180 "$G" --headless --path godot --import`
Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_foreign_state.gd`
Expected: `NATIVE TESTS: N passed, 0 failed`, no `SCRIPT ERROR`.

- [ ] **Step 9: Mutation-check**

One at a time, rerun the test after each and restore:
- In `ensure`, delete `if f.seeded:` / `return` → "a second ensure keeps the ISF record" fails.
- In `to_dict`, drop the `"members"` entry → "the foreign ledger comes back unchanged" fails.
- In `_validate_foreign`, delete the `for locked in ForeignSim.UNION_LOCKS` loop → both lock assertions fail.
- In `_validate_foreign_blocs`, delete the exclusivity loop → "a country cannot sit in the Union and the Concert" fails.
- In `from_dict`, replace `return null` after `malformed %s` with `return out` → "a malformed ledger refuses to load" fails.

- [ ] **Step 10: Run the full battery** (Global Constraints). Expected: every file 0 failed.

- [ ] **Step 11: Commit**

```bash
git add godot/data/native/catalogs/foreign_orientation.json godot/data/native/catalog_manifest.json godot/scripts/native/state/foreign_state.gd godot/scripts/native/state/foreign_state.gd.uid godot/scripts/native/sim/foreign_sim.gd godot/scripts/native/sim/foreign_sim.gd.uid godot/scripts/native/state/game_state.gd godot/scripts/native/state/state_validator.gd godot/tests/native/test_foreign_state.gd godot/tests/native/test_foreign_state.gd.uid
git commit -m "$(cat <<'EOF'
feat(godot): a persisted foreign ledger for Ardenia's orientation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: The shared spine (dependence, commitment, leverage) in the month and the world AI

**Files:**
- Modify: `godot/scripts/native/sim/foreign_sim.gd` (append spine; one line in `ensure`)
- Create: `godot/scripts/native/sim/orientation_sim.gd` (empty month entry point, filled in Task 3)
- Modify: `godot/scripts/native/native_game.gd` (`close_month`)
- Modify: `godot/scripts/native/sim/world_sim.gd` (`hostile_action`, `_shielded_from`)
- Test: `godot/tests/native/test_foreign_spine.gd`

**Interfaces:**
- Consumes: Task 1's `ForeignSim` lookups and `ForeignState`; `DiplomacySim.pair`, `DiplomacySim.world_country`.
- Produces on `ForeignSim`: `GAS_WEIGHT := 0.5`, `DEBT_WEIGHT := 0.25`, `EXPORT_WEIGHT := 0.25`, `HEATING_MONTHS`, `WINTER_GAS_BONUS := 0.25`, `TREATY_COMMITMENT`, `BLOC_COMMITMENT_TO_ANCHOR := 0.5`; `countries_of(state, power_id) -> Array[String]`, `debt_share(state, power_id) -> float`, `export_share(state, power_id) -> float`, `dependence(state, power_id) -> float`, `commitment(state, power_id) -> float`, `is_heating_season(state) -> bool`, `leverage(state, power_id) -> float`, `leverage_of(state, power_id) -> float` (the stored monthly value), `update_spine(state) -> void`, `monthly(state) -> Array[String]`.
- Produces `class_name OrientationSim` with `static func monthly(state: GameState) -> Array[String]`.
- Produces on `WorldSim`: `LEVERAGE_PRESSURE_WEIGHT := 0.5`.

- [ ] **Step 1: Write the failing test**

Create `godot/tests/native/test_foreign_spine.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")


static func _state() -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	return state


static func _trade(state: GameState, id: String) -> float:
	return (state.country.relations[id] as Country.BilateralRelation).trade_volume


static func _score(state: GameState, id: String) -> float:
	return (state.country.relations[id] as Country.BilateralRelation).score


func _test_gas_is_the_heaviest_dependence(t) -> void:
	var state := _state()
	state.foreign.gas_share["krasova"] = 1.0
	var with_gas := ForeignSim.dependence(state, "krasova")
	state.foreign.gas_share["krasova"] = 0.0
	t.near(with_gas - ForeignSim.dependence(state, "krasova"), ForeignSim.GAS_WEIGHT, 1e-9, "the gas contract alone is half of Krasova's hold")


func _test_debt_held_abroad_is_dependence(t) -> void:
	var state := _state()
	var econ := state.country.economy
	econ.loans.clear()
	t.near(ForeignSim.debt_share(state, "krasova"), 0.0, 1e-9, "no Krasovan loans, no debt hold")
	var debt := econ.public_debt_pct * econ.gdp
	econ.loans.append({"id": "l1", "lender_id": "krasova", "principal": debt * 0.2, "rate": 0.03, "months_left": 12})
	t.near(ForeignSim.debt_share(state, "krasova"), 0.2, 1e-6, "a loan for a fifth of the debt is a fifth of the hold")
	state.foreign.isf["disbursed"] = debt * 0.1
	t.near(ForeignSim.debt_share(state, "isf"), 0.1, 1e-6, "ISF disbursements are debt the Fund holds")


func _test_trade_share_is_dependence(t) -> void:
	var state := _state()
	var total := 0.0
	for key in state.country.relations:
		total += _trade(state, String(key))
	t.near(ForeignSim.export_share(state, "krasova"), _trade(state, "krasova") / total, 1e-9, "Krasova's hold includes its share of trade")
	var concert := 0.0
	for id in state.foreign.members["concert"]:
		concert += _trade(state, String(id))
	t.near(ForeignSim.export_share(state, "concert"), concert / total, 1e-9, "a bloc's share is the trade with all its members")


func _test_commitment_is_what_has_been_signed(t) -> void:
	var state := _state()
	t.near(ForeignSim.commitment(state, "isf"), 0.4, 1e-9, "the standing ISF programme is a real commitment")
	t.near(ForeignSim.commitment(state, "union"), 0.0, 1e-9, "no Union step, no Union commitment")
	t.near(ForeignSim.commitment(state, "krasova"), 0.0, 1e-9, "and nothing signed with Krasova")
	DiplomacyActions.trade_agreement(state, DiplomacySim.world_country(state, "krasova"), "")
	t.near(ForeignSim.commitment(state, "krasova"), 0.15, 1e-9, "a trade pact commits a little")
	state.foreign.reached["union_observer"] = 0
	t.near(ForeignSim.commitment(state, "union"), 0.3, 1e-9, "observer status commits more")
	state.foreign.reached["union_member"] = 0
	t.near(ForeignSim.commitment(state, "union"), 0.8, 1e-9, "membership commits a great deal")
	t.near(ForeignSim.commitment(state, "krasova"), 0.55, 1e-9, "and binds Ardenia to the Union's anchor")


func _test_winter_sharpens_the_gas_lever(t) -> void:
	var state := _state()
	state.month = 7
	var summer := ForeignSim.leverage(state, "krasova")
	state.month = 1
	var winter := ForeignSim.leverage(state, "krasova")
	t.truth(winter > summer, "Krasova's leverage is greater in the heating season (%.3f > %.3f)" % [winter, summer])
	state.foreign.gas_share["krasova"] = 0.0
	var no_gas_winter := ForeignSim.leverage(state, "krasova")
	state.month = 7
	t.near(no_gas_winter, ForeignSim.leverage(state, "krasova"), 1e-9, "without gas the season does not matter")


func _test_warmth_blunts_leverage(t) -> void:
	var state := _state()
	var krasova := DiplomacySim.world_country(state, "krasova")
	DiplomacySim.shift_between(state.country, krasova, -0.5)
	var cold := ForeignSim.leverage(state, "krasova")
	DiplomacySim.shift_between(state.country, krasova, 0.8)
	t.truth(ForeignSim.leverage(state, "krasova") < cold, "a warmer relationship makes the same dependence less coercive")


func _test_leverage_is_bounded_at_the_extremes(t) -> void:
	var state := _state()
	state.month = 1
	var econ := state.country.economy
	econ.loans.append({"id": "all", "lender_id": "krasova", "principal": econ.public_debt_pct * econ.gdp * 5.0, "rate": 0.03, "months_left": 12})
	for key in state.country.relations:
		DiplomacySim.set_trade(state, String(key), 0.0)
	DiplomacySim.set_trade(state, "krasova", DiplomacySim.TRADE_CEILING)
	DiplomacySim.shift_between(state.country, DiplomacySim.world_country(state, "krasova"), -2.0)
	for id in ForeignSim.power_ids():
		var lev := ForeignSim.leverage(state, id)
		t.truth(is_finite(lev) and lev >= 0.0 and lev <= 1.0, "%s leverage stays within 0..1 at the extremes (%.3f)" % [id, lev])
	t.near(ForeignSim.leverage(state, "krasova"), 1.0, 1e-9, "total dependence on a hostile supplier in winter is total leverage")


func _test_the_month_records_every_power(t) -> void:
	var state := _state()
	state.foreign.powers.clear()
	NativeGameScript.next_month(state)
	for id in ForeignSim.power_ids():
		t.truth(state.foreign.powers.has(id), "%s is on the monthly ledger" % id)
	t.equal(StateValidator.validate(state).size(), 0, "and the month leaves a valid state")
	var unseeded := _state()
	unseeded.foreign = ForeignState.new()
	NativeGameScript.next_month(unseeded)
	t.truth(unseeded.foreign.seeded, "a campaign without a ledger is seeded by its first month")


func _test_leverage_sharpens_krasovan_pressure(t) -> void:
	var deltas: Array[float] = []
	for lev in [0.0, 1.0]:
		var state := _state()
		for key in state.country.relations:
			(state.country.relations[key] as Country.BilateralRelation).treaties.clear()
		var krasova := DiplomacySim.world_country(state, "krasova")
		state.foreign.powers["krasova"] = {"dependence": 1.0, "commitment": 0.0, "leverage": lev}
		var before := _score(state, "krasova")
		var notes: Array[String] = []
		WorldSim.hostile_action(state, krasova, state.country, notes)
		deltas.append(_score(state, "krasova") - before)
	t.truth(deltas[1] < deltas[0], "a supplier with leverage presses harder (%.3f vs %.3f)" % [deltas[1], deltas[0]])


func _test_a_meridian_guarantee_shields_like_a_pact(t) -> void:
	var state := _state()
	for key in state.country.relations:
		(state.country.relations[key] as Country.BilateralRelation).treaties.clear()
	var krasova := DiplomacySim.world_country(state, "krasova")
	t.truth(not WorldSim._shielded_from(state, krasova), "without pacts or a guarantee Ardenia stands alone")
	state.foreign.reached["meridian_guarantee"] = 0
	t.truth(WorldSim._shielded_from(state, krasova), "a Meridian guarantee deters like a defence pact")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_gas_is_the_heaviest_dependence(t)
	_test_debt_held_abroad_is_dependence(t)
	_test_trade_share_is_dependence(t)
	_test_commitment_is_what_has_been_signed(t)
	_test_winter_sharpens_the_gas_lever(t)
	_test_warmth_blunts_leverage(t)
	_test_leverage_is_bounded_at_the_extremes(t)
	_test_the_month_records_every_power(t)
	_test_leverage_sharpens_krasovan_pressure(t)
	_test_a_meridian_guarantee_shields_like_a_pact(t)
	quit(t.finish())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_foreign_spine.gd`
Expected: `SCRIPT ERROR` (`ForeignSim.dependence` not found), exit 124.

- [ ] **Step 3: Append the spine to `ForeignSim`**

Add these constants under `UNION_LOCKED_BLOCS` in `godot/scripts/native/sim/foreign_sim.gd`:

```gdscript
const GAS_WEIGHT := 0.5
const DEBT_WEIGHT := 0.25
const EXPORT_WEIGHT := 0.25
const HEATING_MONTHS := [10, 11, 12, 1, 2, 3]
const WINTER_GAS_BONUS := 0.25
const TREATY_COMMITMENT := {"trade": 0.15, "defense": 0.3}
const BLOC_COMMITMENT_TO_ANCHOR := 0.5
```

At the end of `ensure`, after `f.seeded = true`, add:

```gdscript
	update_spine(state)
```

Append to the file:

```gdscript
static func countries_of(state: GameState, power_id: String) -> Array[String]:
	var out: Array[String] = []
	match String(power(power_id).get("kind", "")):
		"state":
			out.append(power_id)
		"bloc":
			for id in state.foreign.members.get(power_id, []):
				out.append(String(id))
	return out


static func debt_share(state: GameState, power_id: String) -> float:
	var econ := state.country.economy
	var debt := econ.public_debt_pct * econ.gdp
	if debt <= 0.0:
		return 0.0
	var held := float(state.foreign.isf.get("disbursed", 0.0)) if power_id == "isf" else 0.0
	var lenders := countries_of(state, power_id)
	for loan in econ.loans:
		if String(loan.get("lender_id", "")) in lenders:
			held += float(loan.get("principal", 0.0))
	return clampf(held / debt, 0.0, 1.0)


static func export_share(state: GameState, power_id: String) -> float:
	var partners := countries_of(state, power_id)
	var total := 0.0
	var held := 0.0
	for key in state.country.relations:
		var volume := (state.country.relations[key] as Country.BilateralRelation).trade_volume
		total += volume
		if String(key) in partners:
			held += volume
	return 0.0 if total <= 0.0 else clampf(held / total, 0.0, 1.0)


static func dependence(state: GameState, power_id: String) -> float:
	var gas := float(state.foreign.gas_share.get(power_id, 0.0))
	return clampf(GAS_WEIGHT * gas + DEBT_WEIGHT * debt_share(state, power_id)
		+ EXPORT_WEIGHT * export_share(state, power_id), 0.0, 1.0)


static func commitment(state: GameState, power_id: String) -> float:
	var total := 0.0
	for id in state.foreign.reached:
		var m := milestone(String(id))
		if String(m.get("power", "")) == power_id:
			total = maxf(total, float(m.get("commitment", 0.0)))
	if String(power(power_id).get("kind", "")) == "state":
		var p := DiplomacySim.pair(state, power_id)
		if not p.is_empty():
			for tr in (p[0] as Country.BilateralRelation).treaties:
				if tr is Dictionary:
					total += float(TREATY_COMMITMENT.get(String(tr.get("type", "")), 0.0))
		for other in power_ids():
			if other != power_id and String(power(other).get("anchor", "")) == power_id:
				total += BLOC_COMMITMENT_TO_ANCHOR * commitment(state, other)
	return clampf(total, 0.0, 1.0)


static func is_heating_season(state: GameState) -> bool:
	return state.month in HEATING_MONTHS


static func leverage(state: GameState, power_id: String) -> float:
	var anchor := String(power(power_id).get("anchor", ""))
	var warmth := 0.0
	if anchor != "" and state.country.relations.has(anchor):
		warmth = (state.country.relations[anchor] as Country.BilateralRelation).score
	var gas := float(state.foreign.gas_share.get(power_id, 0.0))
	var season := 1.0 + (WINTER_GAS_BONUS * gas if is_heating_season(state) else 0.0)
	return clampf(dependence(state, power_id) * (0.75 - 0.25 * warmth) * season, 0.0, 1.0)


static func leverage_of(state: GameState, power_id: String) -> float:
	if state.foreign == null:
		return 0.0
	var row: Variant = state.foreign.powers.get(power_id, {})
	return float((row as Dictionary).get("leverage", 0.0)) if row is Dictionary else 0.0


static func update_spine(state: GameState) -> void:
	for id in power_ids():
		state.foreign.powers[id] = {"dependence": dependence(state, id),
			"commitment": commitment(state, id), "leverage": leverage(state, id)}


static func monthly(state: GameState) -> Array[String]:
	ensure(state)
	var notes := OrientationSim.monthly(state)
	update_spine(state)
	return notes
```

- [ ] **Step 4: Create the month entry point for the tracks**

Create `godot/scripts/native/sim/orientation_sim.gd`:

```gdscript
class_name OrientationSim
extends RefCounted


static func monthly(_state: GameState) -> Array[String]:
	var notes: Array[String] = []
	return notes
```

- [ ] **Step 5: Put the spine in the month**

In `godot/scripts/native/native_game.gd`, `close_month`, replace:

```gdscript
	DiplomacySim.monthly(state)
	var world_notes := WorldSim.monthly(state)
```

with:

```gdscript
	DiplomacySim.monthly(state)
	var foreign_notes := ForeignSim.monthly(state)
	var world_notes := WorldSim.monthly(state)
	world_notes.append_array(foreign_notes)
```

- [ ] **Step 6: Let the world AI read leverage**

In `godot/scripts/native/sim/world_sim.gd`, add under `const PRESSURE_COST := -0.06`:

```gdscript
const LEVERAGE_PRESSURE_WEIGHT := 0.5
```

In `hostile_action`, replace:

```gdscript
	var condemn := state.rng.next_float() < CONDEMN_CHANCE
	DiplomacySim.shift_between(actor, target, CONDEMN_COST if condemn else PRESSURE_COST)
```

with:

```gdscript
	var condemn := state.rng.next_float() < CONDEMN_CHANCE
	var strength := (1.0 + LEVERAGE_PRESSURE_WEIGHT * ForeignSim.leverage_of(state, actor.id)) if against_player else 1.0
	DiplomacySim.shift_between(actor, target, (CONDEMN_COST if condemn else PRESSURE_COST) * strength)
```

In `_shielded_from`, insert as the first lines of the body:

```gdscript
	if state.foreign != null and state.foreign.reached.has("meridian_guarantee"):
		return true
```

- [ ] **Step 7: Import and run the test to verify it passes**

Run: `timeout 180 "$G" --headless --path godot --import`
Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_foreign_spine.gd`
Expected: `NATIVE TESTS: N passed, 0 failed`.

- [ ] **Step 8: Mutation-check**

- `GAS_WEIGHT := 0.4` → "half of Krasova's hold" fails.
- In `leverage`, replace `season` with `1.0` in the return → "greater in the heating season" fails.
- Drop the `clampf` in `leverage` (`return dependence(...) * (...) * season`) → "stays within 0..1" and "total leverage" fail.
- Delete the anchored-bloc loop in `commitment` → "binds Ardenia to the Union's anchor" fails.
- Remove `var foreign_notes := ForeignSim.monthly(state)` and its `append_array` from `close_month` → "is on the monthly ledger" fails.
- Set `strength := 1.0` unconditionally → "presses harder" fails.
- Delete the guarantee lines in `_shielded_from` → "deters like a defence pact" fails.

- [ ] **Step 9: Run the full battery.** If a `test_world.gd` assertion fails, read it: if it pins the exact pre-plan pressure magnitude of a Krasovan move against the player in a `next_month` journey, the change is intended (leverage now sharpens it) and the expected value is recomputed as `PRESSURE_COST * (1.0 + LEVERAGE_PRESSURE_WEIGHT * ForeignSim.leverage_of(state, "krasova"))`. Any other failure is a bug in this task.

- [ ] **Step 10: Commit**

```bash
git add godot/scripts/native/sim/foreign_sim.gd godot/scripts/native/sim/orientation_sim.gd godot/scripts/native/sim/orientation_sim.gd.uid godot/scripts/native/native_game.gd godot/scripts/native/sim/world_sim.gd godot/tests/native/test_foreign_spine.gd godot/tests/native/test_foreign_spine.gd.uid
git commit -m "$(cat <<'EOF'
feat(godot): dependence, commitment and leverage, read by the world AI

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: The ISF stabilisation track

**Files:**
- Modify (replace contents): `godot/scripts/native/sim/orientation_sim.gd`
- Create: `godot/scripts/native/actions/orientation_actions.gd`
- Test: `godot/tests/native/test_isf_track.gd`

**Interfaces:**
- Consumes: `ForeignSim.catalog()`, `ForeignSim.update_spine`, `GameState.enacted_laws`, `Economy.deficit_share_of_gdp()`.
- Produces on `OrientationSim`: constants `REVIEW_MONTHS`, `ISF_REVIEWS := 12`, `ISF_DEFICIT_TARGET := 0.05`, `ISF_INFLATION_TARGET := 0.08`, `ISF_TIGHTENING := 0.85`, `ISF_BANK_DUE_REVIEW := 4`, `ISF_BANK_DELAY := 4`, `BANK_ACT := "central_bank_independence_act"`, `ISF_TRANCHE_SHARE := 0.004`, `ISF_TRANCHE_MONTHS := 3`; functions `isf_targets(state) -> Dictionary` (`deficit`, `inflation`, `bank_due_review`), `bank_independent(state) -> bool`, `isf_review_due(state) -> bool`, `isf_passes(state) -> bool`, `release_tranche(state, label: String) -> float`, `timed_modifier(id, source, target, magnitude: float, hold: int, institutional: bool) -> Modifier`, `line(key: String, fields: Dictionary = {}) -> String`.
- Produces `class_name OrientationActions`: `VERBS`, `COSTS`, `act(state, verb: String) -> Dictionary` (`{"ok": true, "message"}` or `{"ok": false, "error"}`), `reason_for(state, verb: String) -> String` (empty when allowed).

- [ ] **Step 1: Write the failing test**

Create `godot/tests/native/test_isf_track.gd`:

```gdscript
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


static func _economy(state: GameState, deficit: float, inflation: float) -> void:
	var econ := state.country.economy
	econ.budget.expenditure = econ.budget.revenue + econ.gdp * deficit
	econ.inflation = inflation


static func _enact_bank_act(state: GameState) -> void:
	var law := Law.new()
	law.id = OrientationSim.BANK_ACT
	state.enacted_laws.append(law)


func _test_reviews_fall_due_each_quarter(t) -> void:
	var state := _state()
	state.month = 5
	t.truth(not OrientationSim.isf_review_due(state), "there is no review in May")
	state.month = 4
	t.truth(OrientationSim.isf_review_due(state), "the quarter's review falls due in April")
	state.foreign.isf["reviews_held"] = OrientationSim.ISF_REVIEWS
	t.truth(not OrientationSim.isf_review_due(state), "the programme ends after its last review")


func _test_a_pass_releases_the_tranche(t) -> void:
	var state := _state()
	state.month = 4
	_economy(state, 0.01, 0.03)
	var notes := OrientationSim.monthly(state)
	t.equal(int(state.foreign.isf["passed"]), 1, "a disciplined quarter passes")
	t.truth(float(state.foreign.isf["disbursed"]) > 0.0, "the tranche is released and held as ISF debt")
	t.truth(state.modifiers.any(func(m: Modifier) -> bool: return m.target == "budget_revenue" and m.magnitude > 0.0 and m.id.begins_with("isf_tranche")), "the money arrives in the budget")
	t.truth(state.modifiers.any(func(m: Modifier) -> bool: return m.target == "gdp_growth" and m.magnitude > 0.0 and m.id.begins_with("isf_confidence")), "and investors take heart")
	t.truth(notes.any(func(n: String) -> bool: return n.contains("signs off")), "the month reports the sign-off")


func _test_a_fail_suspends_the_programme(t) -> void:
	var state := _state()
	state.month = 7
	_economy(state, 0.10, 0.03)
	OrientationSim.monthly(state)
	t.equal(int(state.foreign.isf["failed"]), 1, "a loose quarter fails")
	t.truth(bool(state.foreign.isf["suspended"]), "and the programme is suspended")
	t.near(float(state.foreign.isf["disbursed"]), 0.0, 1e-9, "no tranche is released")
	t.truth(state.modifiers.any(func(m: Modifier) -> bool: return m.target == "gdp_growth" and m.magnitude < 0.0 and m.id.begins_with("isf_confidence")), "and confidence takes a knock")


func _test_one_review_per_month(t) -> void:
	var state := _state()
	state.month = 10
	_economy(state, 0.01, 0.03)
	OrientationSim.monthly(state)
	OrientationSim.monthly(state)
	t.equal(int(state.foreign.isf["reviews_held"]), 1, "a month never holds two reviews")


func _test_the_bank_becomes_a_condition(t) -> void:
	var state := _state()
	state.month = 1
	_economy(state, 0.01, 0.03)
	state.foreign.isf["reviews_held"] = OrientationSim.ISF_BANK_DUE_REVIEW
	state.foreign.isf["passed"] = OrientationSim.ISF_BANK_DUE_REVIEW
	t.truth(not OrientationSim.isf_passes(state), "from the fifth review, good numbers are not enough without an independent bank")
	_enact_bank_act(state)
	t.truth(OrientationSim.isf_passes(state), "an independent bank satisfies the Fund")


func _test_renegotiation_trades_capital_for_tighter_terms(t) -> void:
	var state := _state()
	var refused := OrientationActions.act(state, "isf_renegotiate")
	t.truth(not refused.get("ok", true) and String(refused["error"]).contains("not suspended"), "there is nothing to renegotiate while the programme runs")
	t.near(state.player.political_capital, 500.0, 1e-9, "and a refusal costs nothing")
	state.month = 7
	_economy(state, 0.10, 0.03)
	OrientationSim.monthly(state)
	var before := OrientationSim.isf_targets(state)
	var done := OrientationActions.act(state, "isf_renegotiate")
	t.truth(done.get("ok", false), "a suspended programme can be renegotiated")
	t.near(state.player.political_capital, 500.0 - float(OrientationActions.COSTS["isf_renegotiate"]), 1e-9, "for political capital")
	t.truth(not bool(state.foreign.isf["suspended"]), "the suspension lifts")
	t.truth(float(state.foreign.isf["disbursed"]) > 0.0, "the held tranche is released")
	var after := OrientationSim.isf_targets(state)
	t.truth(float(after["deficit"]) < float(before["deficit"]) and float(after["inflation"]) < float(before["inflation"]), "and the next targets are tighter")
	t.equal(int(after["bank_due_review"]), int(before["bank_due_review"]) + OrientationSim.ISF_BANK_DELAY, "while the bank condition is pushed back")


func _test_the_review_is_national_but_the_reply_is_the_governments(t) -> void:
	var state := _state("opposition")
	state.month = 7
	_economy(state, 0.10, 0.03)
	OrientationSim.monthly(state)
	t.equal(int(state.foreign.isf["failed"]), 1, "the Fund reviews the country whoever governs")
	t.equal(OrientationActions.reason_for(state, "isf_renegotiate"), "Foreign policy belongs to the government.", "but only the government may renegotiate")
	t.truth(not OrientationActions.act(state, "annex_the_moon").get("ok", true), "an unknown step is refused")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_reviews_fall_due_each_quarter(t)
	_test_a_pass_releases_the_tranche(t)
	_test_a_fail_suspends_the_programme(t)
	_test_one_review_per_month(t)
	_test_the_bank_becomes_a_condition(t)
	_test_renegotiation_trades_capital_for_tighter_terms(t)
	_test_the_review_is_national_but_the_reply_is_the_governments(t)
	quit(t.finish())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_isf_track.gd`
Expected: `SCRIPT ERROR` (`OrientationActions` / `OrientationSim.BANK_ACT` not found), exit 124.

- [ ] **Step 3: Write the ISF mechanics**

Replace the contents of `godot/scripts/native/sim/orientation_sim.gd` with:

```gdscript
class_name OrientationSim
extends RefCounted


const REVIEW_MONTHS := [1, 4, 7, 10]
const ISF_REVIEWS := 12
const ISF_DEFICIT_TARGET := 0.05
const ISF_INFLATION_TARGET := 0.08
const ISF_TIGHTENING := 0.85
const ISF_BANK_DUE_REVIEW := 4
const ISF_BANK_DELAY := 4
const BANK_ACT := "central_bank_independence_act"
const ISF_TRANCHE_SHARE := 0.004
const ISF_TRANCHE_MONTHS := 3
const ISF_CONFIDENCE_GAIN := 0.001
const ISF_CONFIDENCE_LOSS := -0.002
const ISF_CONFIDENCE_GAIN_MONTHS := 3
const ISF_CONFIDENCE_LOSS_MONTHS := 6


static func monthly(state: GameState) -> Array[String]:
	var notes: Array[String] = []
	_isf_review(state, notes)
	return notes


static func isf_targets(state: GameState) -> Dictionary:
	var renegotiations := int(state.foreign.isf.get("renegotiations", 0))
	var tight := pow(ISF_TIGHTENING, float(renegotiations))
	return {"deficit": ISF_DEFICIT_TARGET * tight, "inflation": ISF_INFLATION_TARGET * tight,
		"bank_due_review": ISF_BANK_DUE_REVIEW + ISF_BANK_DELAY * renegotiations}


static func bank_independent(state: GameState) -> bool:
	return state.enacted_laws.any(func(l: Law) -> bool: return l.id == BANK_ACT)


static func isf_review_due(state: GameState) -> bool:
	var isf := state.foreign.isf
	return state.foreign.reached.has("isf_programme") and state.month in REVIEW_MONTHS \
		and int(isf.get("reviews_held", 0)) < ISF_REVIEWS \
		and int(isf.get("last_review_turn", -1)) != state.turn


static func isf_passes(state: GameState) -> bool:
	var econ := state.country.economy
	var targets := isf_targets(state)
	var bank_ok := int(state.foreign.isf.get("reviews_held", 0)) < int(targets["bank_due_review"]) \
		or bank_independent(state)
	return econ.deficit_share_of_gdp() <= float(targets["deficit"]) \
		and econ.inflation <= float(targets["inflation"]) and bank_ok


static func release_tranche(state: GameState, label: String) -> float:
	var tranche := state.country.economy.gdp * ISF_TRANCHE_SHARE
	state.foreign.isf["disbursed"] = float(state.foreign.isf.get("disbursed", 0.0)) + tranche
	state.modifiers.append(timed_modifier("isf_tranche_%d" % state.turn, label, "budget_revenue",
		tranche / float(ISF_TRANCHE_MONTHS), ISF_TRANCHE_MONTHS - 1, false))
	return tranche


static func timed_modifier(id: String, source: String, target: String, magnitude: float,
		hold: int, institutional: bool) -> Modifier:
	var m := Modifier.new()
	m.id = id
	m.source = source
	m.target = target
	m.magnitude = magnitude
	m.onset_delay = 0
	m.ramp_duration = 1
	m.hold_duration = hold
	m.decay_duration = 0
	m.source_id = id
	m.portfolio = "Foreign Affairs"
	m.institutional = institutional
	return m


static func line(key: String, fields: Dictionary = {}) -> String:
	return String(ForeignSim.catalog().get("lines", {}).get(key, key)).format(fields)


static func _isf_review(state: GameState, notes: Array[String]) -> void:
	if not isf_review_due(state):
		return
	var isf := state.foreign.isf
	var passed := isf_passes(state)
	isf["reviews_held"] = int(isf.get("reviews_held", 0)) + 1
	isf["last_review_turn"] = state.turn
	if passed:
		isf["passed"] = int(isf.get("passed", 0)) + 1
		isf["suspended"] = false
		isf["last_result"] = "passed"
		release_tranche(state, "ISF disbursement")
		state.modifiers.append(timed_modifier("isf_confidence_%d" % state.turn, "ISF review passed",
			"gdp_growth", ISF_CONFIDENCE_GAIN, ISF_CONFIDENCE_GAIN_MONTHS, true))
		notes.append(line("isf_pass"))
	else:
		isf["failed"] = int(isf.get("failed", 0)) + 1
		isf["suspended"] = true
		isf["last_result"] = "failed"
		state.modifiers.append(timed_modifier("isf_confidence_%d" % state.turn, "ISF review failed",
			"gdp_growth", ISF_CONFIDENCE_LOSS, ISF_CONFIDENCE_LOSS_MONTHS, true))
		notes.append(line("isf_fail"))
```

- [ ] **Step 4: Write the action layer (ISF verb only; Task 4 replaces this file with the full set)**

Create `godot/scripts/native/actions/orientation_actions.gd`:

```gdscript
class_name OrientationActions
extends RefCounted


const VERBS := ["isf_renegotiate"]
const COSTS := {"isf_renegotiate": 15.0}


static func act(state: GameState, verb: String) -> Dictionary:
	var reason := reason_for(state, verb)
	if reason != "":
		return {"ok": false, "error": reason}
	state.player.political_capital -= float(COSTS[verb])
	var message := _renegotiate(state)
	ForeignSim.update_spine(state)
	return {"ok": true, "message": message}


static func reason_for(state: GameState, verb: String) -> String:
	if state == null or state.player == null:
		return "No campaign is active."
	if not COSTS.has(verb):
		return "Unknown orientation step."
	if not state.player.in_government:
		return "Foreign policy belongs to the government."
	if state.foreign == null or not state.foreign.seeded:
		return "The foreign ledger is not ready."
	if not bool(state.foreign.isf.get("suspended", false)):
		return "The ISF programme is not suspended; there is nothing to renegotiate."
	if state.player.political_capital < float(COSTS[verb]):
		return "Requires %.0f political capital." % float(COSTS[verb])
	return ""


static func _renegotiate(state: GameState) -> String:
	var isf := state.foreign.isf
	isf["renegotiations"] = int(isf.get("renegotiations", 0)) + 1
	isf["suspended"] = false
	OrientationSim.release_tranche(state, "ISF disbursement after renegotiation")
	var targets := OrientationSim.isf_targets(state)
	return "The ISF agrees new terms and releases the held tranche. From the next review it wants a deficit under %.1f%% and inflation under %.1f%%." % [
		float(targets["deficit"]) * 100.0, float(targets["inflation"]) * 100.0]
```

- [ ] **Step 5: Import and run the test to verify it passes**

Run: `timeout 180 "$G" --headless --path godot --import`
Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_isf_track.gd`
Expected: `NATIVE TESTS: N passed, 0 failed`.

- [ ] **Step 6: Mutation-check**

- `REVIEW_MONTHS := [1, 4, 5, 7, 10]` → "there is no review in May" fails.
- Delete `and int(isf.get("last_review_turn", -1)) != state.turn` → "a month never holds two reviews" fails.
- In `isf_passes`, replace `bank_ok` with `true` → "without an independent bank" fails.
- In `isf_targets`, set `tight := 1.0` → "the next targets are tighter" fails.
- In `_isf_review`, delete `isf["suspended"] = true` → "the programme is suspended" fails.
- In `reason_for`, delete the `in_government` check → "only the government may renegotiate" fails.

- [ ] **Step 7: Run the full battery.** Expected: all green.

- [ ] **Step 8: Commit**

```bash
git add godot/scripts/native/sim/orientation_sim.gd godot/scripts/native/actions/orientation_actions.gd godot/scripts/native/actions/orientation_actions.gd.uid godot/tests/native/test_isf_track.gd godot/tests/native/test_isf_track.gd.uid
git commit -m "$(cat <<'EOF'
feat(godot): quarterly ISF reviews, tranches, suspension and renegotiation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: The Western and Union tracks, hard locks, consent and tariffs

**Files:**
- Modify (replace contents): `godot/scripts/native/actions/orientation_actions.gd`
- Modify: `godot/scripts/native/sim/orientation_sim.gd` (`monthly`, new constants, `_western_discipline`)
- Modify: `godot/scripts/native/sim/foreign_sim.gd` (append tariff share and Vetrenka check)
- Modify: `godot/scripts/native/sim/diplomacy_sim.gd` (`monthly`, one line)
- Modify: `godot/scripts/native/actions/diplomacy_actions.gd` (`reason_for`, three lines)
- Test: `godot/tests/native/test_orientation_tracks.gd`

**Interfaces:**
- Consumes: Tasks 1–3 (`ForeignSim.UNION_LOCKS`, `ForeignSim.milestone`, `ForeignSim.update_spine`, `OrientationSim.timed_modifier`, `OrientationSim.release_tranche`, `OrientationSim.isf_targets`, `OrientationSim.bank_independent`), `DiplomacySim.shift`, `DiplomacySim.pair`, `EffectBundle.apply`.
- Produces on `OrientationActions`: `VERBS` (8 verbs, in desk order), `COSTS`, `LABELS`, `PLAYER_BLOCS`, `QUALIFYING_MONTHS_FOR_AGREEMENT := 36`, `PARTNERSHIP_MONTHS_FOR_GUARANTEE := 24`, `OBSERVER_MONTHS_FOR_MEMBERSHIP := 12`, `EXIT_RELATIONS_COST := -0.35`; `act`, `reason_for`, `lock_reason(state, verb) -> String`, `label_for(verb) -> String`, `consent_reason(state, verb, country_id) -> String`.
- Produces on `OrientationSim`: `CONCERT_DEFICIT_LIMIT := 0.04`, `CONCERT_INFLATION_LIMIT := 0.08`, `QUALIFYING_SETBACK := 2`.
- Produces on `ForeignSim`: `UNION_TARIFF_SHARE := 0.6`, `RESOLVED_VETRENKA`, `trade_ceiling_share(state, country_id) -> float`, `vetrenka_resolved(state) -> bool`.

- [ ] **Step 1: Write the failing test**

Create `godot/tests/native/test_orientation_tracks.gd`:

```gdscript
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
	t.equal(StateValidator.validate(member).filter(func(e) -> bool: return String(e).contains("locked")).size(), 0, "no lock is ever broken by a permitted step")


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
	quit(t.finish())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_orientation_tracks.gd`
Expected: `SCRIPT ERROR` (`OrientationActions.OBSERVER_MONTHS_FOR_MEMBERSHIP` not found), exit 124.

- [ ] **Step 3: Append tariff share and the Vetrenka check to `ForeignSim`**

Add under `BLOC_COMMITMENT_TO_ANCHOR` in `foreign_sim.gd`:

```gdscript
const UNION_TARIFF_SHARE := 0.6
const RESOLVED_VETRENKA := ["settled", "retaken", "partitioned"]
```

Append:

```gdscript
static func trade_ceiling_share(state: GameState, country_id: String) -> float:
	if state.foreign == null or not state.foreign.reached.has("union_member"):
		return 1.0
	return UNION_TARIFF_SHARE if country_id in state.foreign.members.get("concert", []) else 1.0


static func vetrenka_resolved(state: GameState) -> bool:
	if not state.regions.has("vetrenka"):
		return true
	return String(state.campaign_meta.get("vetrenka_status", "")) in RESOLVED_VETRENKA
```

- [ ] **Step 4: Add Western discipline to the month**

In `orientation_sim.gd`, add under `ISF_CONFIDENCE_LOSS_MONTHS`:

```gdscript
const CONCERT_DEFICIT_LIMIT := 0.04
const CONCERT_INFLATION_LIMIT := 0.08
const QUALIFYING_SETBACK := 2
```

Replace `monthly` with:

```gdscript
static func monthly(state: GameState) -> Array[String]:
	var notes: Array[String] = []
	_isf_review(state, notes)
	_western_discipline(state)
	return notes
```

Append:

```gdscript
static func _western_discipline(state: GameState) -> void:
	var f := state.foreign
	if not f.reached.has("concert_application") or f.reached.has("concert_agreement"):
		return
	var econ := state.country.economy
	if econ.deficit_share_of_gdp() <= CONCERT_DEFICIT_LIMIT and econ.inflation <= CONCERT_INFLATION_LIMIT:
		f.western_qualifying_months += 1
	else:
		f.western_qualifying_months = maxi(0, f.western_qualifying_months - QUALIFYING_SETBACK)
```

- [ ] **Step 5: Replace the action layer with the full set**

Replace the contents of `godot/scripts/native/actions/orientation_actions.gd` with:

```gdscript
class_name OrientationActions
extends RefCounted


const VERBS := ["concert_application", "concert_agreement", "meridian_partnership", "meridian_guarantee",
	"union_observer", "union_member", "union_leave", "isf_renegotiate"]
const COSTS := {
	"concert_application": 5.0, "concert_agreement": 25.0, "meridian_partnership": 15.0,
	"meridian_guarantee": 30.0, "union_observer": 10.0, "union_member": 20.0,
	"union_leave": 0.0, "isf_renegotiate": 15.0,
}
const LABELS := {"union_leave": "Leave the Union", "isf_renegotiate": "Renegotiate the ISF terms"}
const TREASURY_DEBT := {"concert_agreement": 0.003, "meridian_partnership": 0.001, "meridian_guarantee": 0.002}
const REACTIONS := {
	"concert_agreement": {"krasova": -0.08},
	"meridian_partnership": {"krasova": -0.06},
	"meridian_guarantee": {"krasova": -0.15},
	"union_observer": {"krasova": 0.08, "bloc:concert": -0.03},
	"union_member": {"krasova": 0.10, "bloc:concert": -0.06},
}
const PLAYER_BLOCS := {"concert": "concert_agreement", "meridian": "meridian_guarantee", "union": "union_member"}
const QUALIFYING_MONTHS_FOR_AGREEMENT := 36
const PARTNERSHIP_MONTHS_FOR_GUARANTEE := 24
const OBSERVER_MONTHS_FOR_MEMBERSHIP := 12
const OBSERVER_WARMTH := -0.35
const MEMBER_WARMTH := -0.15
const UNION_REJOIN_MONTHS := 60
const CONCERT_GROWTH := 0.002
const CONCERT_GROWTH_RAMP := 24
const UNION_GROWTH := 0.003
const UNION_GROWTH_RAMP := 12
const UNION_RESCHEDULING := 60.0
const UNION_RESCHEDULING_MONTHS := 36
const PARTNERSHIP_STABILITY := 0.01
const GUARANTEE_STABILITY := 0.03
const STABILITY_CEILING := 0.95
const EXIT_RELATIONS_COST := -0.35
const OBSERVER_EXIT_COST := -0.10
const EXIT_STABILITY_COST := 0.04
const EXIT_GROWTH_COST := -0.004
const EXIT_GROWTH_MONTHS := 12
const EXIT_GROWTH_DECAY := 6


static func act(state: GameState, verb: String) -> Dictionary:
	var reason := reason_for(state, verb)
	if reason != "":
		return {"ok": false, "error": reason}
	state.player.political_capital -= float(COSTS[verb])
	var message := ""
	match verb:
		"isf_renegotiate":
			message = _renegotiate(state)
		"union_leave":
			message = _leave_union(state)
		_:
			message = _reach(state, verb)
	_react(state, verb)
	ForeignSim.update_spine(state)
	return {"ok": true, "message": message}


static func label_for(verb: String) -> String:
	return String(LABELS[verb]) if LABELS.has(verb) else ForeignSim.milestone_name(verb)


static func lock_reason(state: GameState, verb: String) -> String:
	var reached := state.foreign.reached
	if verb in ForeignSim.UNION_LOCKS and reached.has("union_member"):
		return "A Union member cannot take Western steps beyond partnership."
	if verb == "union_member":
		for locked in ForeignSim.UNION_LOCKS:
			if reached.has(locked):
				return "Union membership is incompatible with the %s." % ForeignSim.milestone_name(locked)
	return ""


static func reason_for(state: GameState, verb: String) -> String:
	if state == null or state.player == null:
		return "No campaign is active."
	if not COSTS.has(verb):
		return "Unknown orientation step."
	if not state.player.in_government:
		return "Foreign policy belongs to the government."
	if state.foreign == null or not state.foreign.seeded:
		return "The foreign ledger is not ready."
	var lock := lock_reason(state, verb)
	if lock != "":
		return lock
	var standing := _standing_reason(state, verb)
	if standing != "":
		return standing
	var condition := _condition_reason(state, verb)
	if condition != "":
		return condition
	if state.player.political_capital < float(COSTS[verb]):
		return "Requires %.0f political capital." % float(COSTS[verb])
	return ""


static func consent_reason(state: GameState, verb: String, country_id: String) -> String:
	if state.foreign == null or not state.foreign.reached.has("union_member"):
		return ""
	var in_union: bool = country_id in state.foreign.members.get("union", [])
	if verb in ["impose_sanctions", "condemn"] and in_union:
		return "The Union withholds its consent: you cannot turn on a fellow member."
	if verb == "defense_pact" and not in_union:
		return "The Union withholds its consent to a defence pact outside the bloc."
	return ""


static func _standing_reason(state: GameState, verb: String) -> String:
	var f := state.foreign
	match verb:
		"isf_renegotiate":
			if not bool(f.isf.get("suspended", false)):
				return "The ISF programme is not suspended; there is nothing to renegotiate."
		"union_leave":
			if not f.reached.has("union_observer"):
				return "Ardenia is not part of the Union."
		_:
			if f.reached.has(verb):
				return "%s is already in place." % ForeignSim.milestone_name(verb)
	return ""


static func _condition_reason(state: GameState, verb: String) -> String:
	var f := state.foreign
	match verb:
		"concert_agreement":
			if not f.reached.has("concert_application"):
				return "Apply for association first."
			if f.western_qualifying_months < QUALIFYING_MONTHS_FOR_AGREEMENT:
				return "The Concert wants %d months of budget discipline; Ardenia has %d." % [
					QUALIFYING_MONTHS_FOR_AGREEMENT, f.western_qualifying_months]
			if not OrientationSim.bank_independent(state):
				return "The Concert requires an independent central bank."
		"meridian_guarantee":
			if not f.reached.has("meridian_partnership"):
				return "Join the Meridian partnership first."
			var held := _months_held(state, "meridian_partnership")
			if held < PARTNERSHIP_MONTHS_FOR_GUARANTEE:
				return "The partnership must run %d months before a guarantee (%d so far)." % [
					PARTNERSHIP_MONTHS_FOR_GUARANTEE, held]
			if not ForeignSim.vetrenka_resolved(state):
				return "Meridian will not guarantee a country with an active territorial dispute."
		"union_observer":
			if f.union_left_turn >= 0 and state.turn - f.union_left_turn < UNION_REJOIN_MONTHS:
				return "Krasova will not readmit Ardenia for %d more months." % [
					UNION_REJOIN_MONTHS - (state.turn - f.union_left_turn)]
			if _krasova_warmth(state) < OBSERVER_WARMTH:
				return "Krasova will not seat an observer at this level of hostility (needs %.2f)." % OBSERVER_WARMTH
		"union_member":
			if not f.reached.has("union_observer"):
				return "Take observer status first."
			var observed := _months_held(state, "union_observer")
			if observed < OBSERVER_MONTHS_FOR_MEMBERSHIP:
				return "Observer status must run %d months before membership (%d so far)." % [
					OBSERVER_MONTHS_FOR_MEMBERSHIP, observed]
			if _krasova_warmth(state) < MEMBER_WARMTH:
				return "Krasova will not admit a member at this level of hostility (needs %.2f)." % MEMBER_WARMTH
	return ""


static func _months_held(state: GameState, milestone_id: String) -> int:
	return state.turn - int(state.foreign.reached.get(milestone_id, state.turn))


static func _krasova_warmth(state: GameState) -> float:
	var p := DiplomacySim.pair(state, "krasova")
	return -1.0 if p.is_empty() else (p[0] as Country.BilateralRelation).score


static func _reach(state: GameState, verb: String) -> String:
	state.foreign.reached[verb] = state.turn
	var debt := float(TREASURY_DEBT.get(verb, 0.0))
	if debt > 0.0:
		EffectBundle.apply(state, {"one_time_debt_pct_delta": debt}, "orientation", verb)
	match verb:
		"concert_agreement":
			state.modifiers.append(_phased(verb, "Concert association", CONCERT_GROWTH, CONCERT_GROWTH_RAMP))
		"meridian_partnership":
			state.stability_value = minf(STABILITY_CEILING, state.stability_value + PARTNERSHIP_STABILITY)
		"meridian_guarantee":
			state.stability_value = minf(STABILITY_CEILING, state.stability_value + GUARANTEE_STABILITY)
		"union_member":
			state.modifiers.append(_phased(verb, "Krasovan Economic Union", UNION_GROWTH, UNION_GROWTH_RAMP))
			var rescheduling := OrientationSim.timed_modifier("union_rescheduling", "Union debt rescheduling",
				"budget_expenditure", -UNION_RESCHEDULING, UNION_RESCHEDULING_MONTHS - 1, false)
			rescheduling.source_id = verb
			state.modifiers.append(rescheduling)
	return "%s. %s" % [ForeignSim.milestone_name(verb), String(ForeignSim.milestone(verb).get("body", ""))]


static func _phased(source_id: String, source: String, magnitude: float, ramp: int) -> Modifier:
	var m := Modifier.new()
	m.id = "%s_growth" % source_id
	m.source = source
	m.target = "gdp_growth"
	m.magnitude = magnitude
	m.onset_delay = 3
	m.ramp_duration = ramp
	m.hold_duration = Modifier.HOLDS_FOREVER
	m.source_id = source_id
	m.portfolio = "Foreign Affairs"
	return m


static func _react(state: GameState, verb: String) -> void:
	var deltas: Dictionary = REACTIONS.get(verb, {})
	for key in deltas:
		var k := String(key)
		var targets: Array = state.foreign.members.get(k.trim_prefix("bloc:"), []) if k.begins_with("bloc:") else [k]
		for id in targets:
			DiplomacySim.shift(state, String(id), float(deltas[key]), "Reacted to %s." % label_for(verb))


static func _renegotiate(state: GameState) -> String:
	var isf := state.foreign.isf
	isf["renegotiations"] = int(isf.get("renegotiations", 0)) + 1
	isf["suspended"] = false
	OrientationSim.release_tranche(state, "ISF disbursement after renegotiation")
	var targets := OrientationSim.isf_targets(state)
	return "The ISF agrees new terms and releases the held tranche. From the next review it wants a deficit under %.1f%% and inflation under %.1f%%." % [
		float(targets["deficit"]) * 100.0, float(targets["inflation"]) * 100.0]


static func _leave_union(state: GameState) -> String:
	var f := state.foreign
	var was_member := f.reached.has("union_member")
	f.reached.erase("union_member")
	f.reached.erase("union_observer")
	f.union_left_turn = state.turn
	if not was_member:
		DiplomacySim.shift(state, "krasova", OBSERVER_EXIT_COST, "Ardenia gave up its Union seat.")
		return "Ardenia gives up its observer seat in the Krasovan Economic Union. Krasova notes the date."
	state.modifiers = state.modifiers.filter(func(m: Modifier) -> bool: return m.source_id != "union_member")
	state.stability_value = maxf(0.0, state.stability_value - EXIT_STABILITY_COST)
	var shock := OrientationSim.timed_modifier("union_exit_%d" % state.turn, "Union exit", "gdp_growth",
		EXIT_GROWTH_COST, EXIT_GROWTH_MONTHS, true)
	shock.decay_duration = EXIT_GROWTH_DECAY
	state.modifiers.append(shock)
	DiplomacySim.shift(state, "krasova", EXIT_RELATIONS_COST, "Ardenia walked out of the Union.")
	return "Ardenia walks out of the Krasovan Economic Union. Tariffs return overnight, and Krasova calls it betrayal."
```

- [ ] **Step 6: Tariff alignment in the monthly trade**

In `godot/scripts/native/sim/diplomacy_sim.gd`, `monthly`, directly after:

```gdscript
		elif not has_treaty(state, other.id, "trade"):
			ceiling *= NO_PACT_CEILING_SHARE
```

add (same indentation as the `if mine.sanctioned:` line):

```gdscript
		ceiling *= ForeignSim.trade_ceiling_share(state, other.id)
```

- [ ] **Step 7: Union consent in diplomacy**

In `godot/scripts/native/actions/diplomacy_actions.gd`, `reason_for`, directly after `var rel: Country.BilateralRelation = p[0]`, add:

```gdscript
	var consent := OrientationActions.consent_reason(state, verb, country_id)
	if consent != "":
		return consent
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_orientation_tracks.gd`
Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_isf_track.gd`
Expected: both `NATIVE TESTS: N passed, 0 failed`.

- [ ] **Step 9: Mutation-check**

- `QUALIFYING_SETBACK := 0` → "a loose month costs two" fails.
- `RESOLVED_VETRENKA := ["settled", "retaken", "partitioned", "partitioned_contested"]` → "a contested partition is still a dispute" fails.
- In `lock_reason`, delete the first `if` → "cannot sign the association agreement" and "cannot take a Meridian guarantee" fail.
- In `lock_reason`, delete the `union_member` loop → "an associated country cannot join the Union" fails.
- `UNION_TARIFF_SHARE := 1.0` → "capped by the common tariff" and "grows more slowly" fail.
- Delete the consent lines in `DiplomacyActions.reason_for` → the three consent assertions fail.
- In `_leave_union`, delete the `filter` line → "the Union's benefits end at once" fails.
- In `act`, move `state.player.political_capital -= ...` above the `reason != ""` check → "and costs nothing" fails.

- [ ] **Step 10: Run the full battery.** `test_diplomacy.gd` must stay green (consent is inert outside the Union).

- [ ] **Step 11: Commit**

```bash
git add godot/scripts/native/actions/orientation_actions.gd godot/scripts/native/sim/orientation_sim.gd godot/scripts/native/sim/foreign_sim.gd godot/scripts/native/sim/diplomacy_sim.gd godot/scripts/native/actions/diplomacy_actions.gd godot/tests/native/test_orientation_tracks.gd godot/tests/native/test_orientation_tracks.gd.uid
git commit -m "$(cat <<'EOF'
feat(godot): the Western ladder and the Krasovan Economic Union, with hard locks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: AI countries join and leave blocs

**Files:**
- Modify: `godot/scripts/native/sim/orientation_sim.gd` (`monthly`, append bloc drift)
- Test: `godot/tests/native/test_world_blocs.gd`

**Interfaces:**
- Consumes: `ForeignSim.catalog()`, `ForeignSim.power(id)`, `WorldSim.agenda_type(c)`, `DiplomacySim.REGIME_FAMILY`, `OrientationSim.line`.
- Produces on `OrientationSim`: `BLOC_MONTH := 1`, `bloc_fits(state, c: Country, b: Dictionary) -> bool`, `bloc_rejects(state, c: Country, b: Dictionary) -> bool`. Bloc membership changes only in January and is a pure function of agenda, regime family, stability, warmth to the anchor and the other blocs.

- [ ] **Step 1: Write the failing test**

Create `godot/tests/native/test_world_blocs.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")


static func _state() -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	return state


static func _between(a: Country, b: Country, score: float) -> void:
	(a.relations[b.id] as Country.BilateralRelation).score = score
	(b.relations[a.id] as Country.BilateralRelation).score = score


static func _in(state: GameState, bloc_id: String, country_id: String) -> bool:
	return country_id in state.foreign.members.get(bloc_id, [])


func _test_democratic_traders_drift_into_the_concert(t) -> void:
	var state := _state()
	var veldoria := DiplomacySim.world_country(state, "veldoria")
	veldoria.stability = 0.7
	_between(veldoria, DiplomacySim.world_country(state, "solheim"), 0.6)
	state.month = 5
	OrientationSim.monthly(state)
	t.truth(not _in(state, "concert", "veldoria"), "blocs take members only at the turn of the year")
	state.month = 1
	var notes := OrientationSim.monthly(state)
	t.truth(_in(state, "concert", "veldoria"), "a stable democratic trader warm to Solheim joins the Concert")
	t.truth(notes.any(func(n: String) -> bool: return n.contains(veldoria.name) and n.contains("joins")), "and the world hears of it")


func _test_the_meridian_takes_only_steady_concert_members(t) -> void:
	var state := _state()
	var veldoria := DiplomacySim.world_country(state, "veldoria")
	veldoria.stability = 0.47
	_between(veldoria, DiplomacySim.world_country(state, "solheim"), 0.6)
	state.month = 1
	OrientationSim.monthly(state)
	t.truth(_in(state, "concert", "veldoria"), "steady enough for the Concert")
	t.truth(not _in(state, "meridian", "veldoria"), "but not for the alliance")


func _test_krasovan_clients_join_the_union(t) -> void:
	var state := _state()
	var terand := DiplomacySim.world_country(state, "terand")
	terand.stability = 0.6
	_between(terand, DiplomacySim.world_country(state, "krasova"), 0.4)
	state.month = 1
	OrientationSim.monthly(state)
	t.truth(_in(state, "union", "terand"), "a revanchist warm to Krasova joins the Union")
	t.truth(not _in(state, "concert", "terand"), "and sits in no Western bloc")


func _test_members_who_turn_cold_walk_away(t) -> void:
	var state := _state()
	var terand := DiplomacySim.world_country(state, "terand")
	var krasova := DiplomacySim.world_country(state, "krasova")
	terand.stability = 0.6
	_between(terand, krasova, 0.4)
	state.month = 1
	OrientationSim.monthly(state)
	_between(terand, krasova, -0.6)
	var notes := OrientationSim.monthly(state)
	t.truth(not _in(state, "union", "terand"), "a member that turns on the anchor leaves the bloc")
	t.truth(notes.any(func(n: String) -> bool: return n.contains(terand.name) and n.contains("leaves")), "and the world hears of it")


func _test_an_anchor_never_leaves_its_bloc(t) -> void:
	var state := _state()
	DiplomacySim.world_country(state, "solheim").stability = 0.05
	DiplomacySim.world_country(state, "krasova").stability = 0.05
	state.month = 1
	OrientationSim.monthly(state)
	t.truth(_in(state, "concert", "solheim") and _in(state, "meridian", "solheim"), "Solheim anchors the Western blocs through any crisis")
	t.truth(_in(state, "union", "krasova"), "Krasova anchors the Union through any crisis")


func _test_no_country_sits_on_both_sides(t) -> void:
	var state := _state()
	var veldoria := DiplomacySim.world_country(state, "veldoria")
	(state.foreign.members["union"] as Array).append("veldoria")
	veldoria.stability = 0.7
	_between(veldoria, DiplomacySim.world_country(state, "solheim"), 0.6)
	_between(veldoria, DiplomacySim.world_country(state, "krasova"), 0.6)
	state.month = 1
	OrientationSim.monthly(state)
	t.truth(not (_in(state, "concert", "veldoria") and _in(state, "union", "veldoria")), "no country is in the Union and the Concert at once")
	t.equal(StateValidator.validate(state).size(), 0, "and the bloc map stays valid")
	t.truth(not _in(state, "concert", "ardenia") and not _in(state, "union", "ardenia"), "the player is never listed as an AI member")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_democratic_traders_drift_into_the_concert(t)
	_test_the_meridian_takes_only_steady_concert_members(t)
	_test_krasovan_clients_join_the_union(t)
	_test_members_who_turn_cold_walk_away(t)
	_test_an_anchor_never_leaves_its_bloc(t)
	_test_no_country_sits_on_both_sides(t)
	quit(t.finish())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_world_blocs.gd`
Expected: compiles, then `FAIL` lines starting with "a stable democratic trader warm to Solheim joins the Concert"; `NATIVE TESTS: N passed, M failed` with M > 0.

- [ ] **Step 3: Write the bloc drift**

In `orientation_sim.gd`, add under `QUALIFYING_SETBACK`:

```gdscript
const BLOC_MONTH := 1
```

Replace `monthly` with:

```gdscript
static func monthly(state: GameState) -> Array[String]:
	var notes: Array[String] = []
	_isf_review(state, notes)
	_western_discipline(state)
	if state.month == BLOC_MONTH:
		_world_blocs(state, notes)
	return notes
```

Append:

```gdscript
static func _anchor(bloc_id: String) -> String:
	return String(ForeignSim.power(bloc_id).get("anchor", ""))


static func _warmth(c: Country, anchor: String) -> float:
	if c.id == anchor:
		return 1.0
	var rel: Country.BilateralRelation = c.relations.get(anchor)
	return 0.0 if rel == null else rel.score


static func _in_excluded(state: GameState, c: Country, b: Dictionary) -> bool:
	for other in b.get("excludes", []):
		if c.id in state.foreign.members.get(String(other), []):
			return true
	return false


static func bloc_fits(state: GameState, c: Country, b: Dictionary) -> bool:
	var anchor := _anchor(String(b["id"]))
	if c.in_civil_war or c.stability < float(b.get("min_stability", 0.0)) or _in_excluded(state, c, b):
		return false
	var requires := String(b.get("requires", ""))
	if requires != "" and not (c.id in state.foreign.members.get(requires, [])):
		return false
	var family := String(DiplomacySim.REGIME_FAMILY.get(c.regime_type, c.regime_type))
	var client := String(c.agenda.get("ally", "")) == anchor
	var kindred: bool = WorldSim.agenda_type(c) in b.get("agendas", []) and family in b.get("families", [])
	return (client or kindred) and _warmth(c, anchor) >= float(b.get("min_warmth", 0.0))


static func bloc_rejects(state: GameState, c: Country, b: Dictionary) -> bool:
	var anchor := _anchor(String(b["id"]))
	return c.in_civil_war or c.stability < float(b.get("leave_stability", 0.0)) \
		or _warmth(c, anchor) < float(b.get("leave_warmth", 0.0)) or _in_excluded(state, c, b)


static func _world_blocs(state: GameState, notes: Array[String]) -> void:
	for b in ForeignSim.catalog().get("blocs", []):
		var bloc_id := String(b["id"])
		var anchor := _anchor(bloc_id)
		var bloc_name := String(ForeignSim.power(bloc_id).get("name", bloc_id))
		var current: Array = state.foreign.members.get(bloc_id, [])
		var next: Array = []
		for c in state.world:
			var member: bool = c.id in current
			var stays := c.id == anchor or (not bloc_rejects(state, c, b) if member else bloc_fits(state, c, b))
			if stays:
				next.append(c.id)
			if stays != member:
				notes.append(line("bloc_join" if stays else "bloc_leave", {"country": c.name, "bloc": bloc_name}))
		state.foreign.members[bloc_id] = next
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_world_blocs.gd`
Expected: `NATIVE TESTS: N passed, 0 failed`.

- [ ] **Step 5: Mutation-check**

- `if state.month == BLOC_MONTH:` → `if true:` → "only at the turn of the year" fails.
- In `bloc_fits`, delete the `requires` check → "but not for the alliance" fails.
- In `bloc_fits`, delete `or _in_excluded(state, c, b)` → "no country is in the Union and the Concert at once" fails.
- In `_world_blocs`, change `c.id == anchor or` to `false or` → "anchors ... through any crisis" fails.
- In `bloc_rejects`, delete the `leave_warmth` clause → "leaves the bloc" fails.

- [ ] **Step 6: Run the full battery.** Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add godot/scripts/native/sim/orientation_sim.gd godot/tests/native/test_world_blocs.gd godot/tests/native/test_world_blocs.gd.uid
git commit -m "$(cat <<'EOF'
feat(godot): world countries join and leave the Concert, Meridian and Union

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: The game surface, the map hand-off and the Diplomacy desk

**Files:**
- Modify: `godot/scripts/native/actions/orientation_actions.gd` (append `memberships`, `read_model`)
- Modify: `godot/scripts/native/native_game.gd` (`orientation_act`, `load`, `_do_new_campaign`, `_build_snapshot`)
- Modify: `godot/scenes/panels/diplomacy_panel.tscn`
- Modify: `godot/scripts/app.gd` (`_refresh_diplomacy` and three new functions)
- Test: `godot/tests/native/test_orientation_snapshot.gd`, `godot/tests/ui/test_orientation_desk.gd`

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces:
  - `OrientationActions.memberships(state) -> Dictionary` (`{country_id: Array of bloc ids}`, the player included through `PLAYER_BLOCS`).
  - `OrientationActions.read_model(state) -> Dictionary`: `{"powers": [{id, name, kind, dependence, commitment, leverage}], "steps": [{verb, label, cost, held, eligible, disabled_reason}], "isf": {reviews_held, reviews_total, passed, failed, suspended, last_result, deficit_target, inflation_target, bank_required}, "western_qualifying_months": int, "qualifying_months_needed": int, "map": {"memberships": {...}}}`. Later plans add `map.gas_supply`, `map.tension`, `map.incidents`.
  - Snapshot key `"foreign"` = that read model.
  - `NativeGame.orientation_act(verb: String) -> Dictionary` (same contract as `diplomacy_act`).
  - Diplomacy desk nodes: `OrientationPowers` (Label), `OrientationReviews` (Label), `OrientationSteps` (VBoxContainer).

- [ ] **Step 1: Write the failing tests**

Create `godot/tests/native/test_orientation_snapshot.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const SLOT := "test_orientation_snapshot"


static func _state() -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	state.player.political_capital = 500.0
	return state


static func _wipe() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := "user://saves/%s.json%s" % [SLOT, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _test_the_snapshot_carries_the_orientation_desk(t) -> void:
	var foreign: Dictionary = NativeGameScript._build_snapshot(_state()).get("foreign", {})
	t.equal((foreign.get("powers", []) as Array).size(), ForeignSim.power_ids().size(), "every power is on the desk")
	t.equal((foreign.get("steps", []) as Array).size(), OrientationActions.VERBS.size(), "and every orientation step")
	t.truth((foreign.get("isf", {}) as Dictionary).has("deficit_target"), "with the ISF's next targets")
	var held: Array = (foreign["steps"] as Array).filter(func(s: Dictionary) -> bool: return bool(s["held"]))
	t.truth(held.any(func(s: Dictionary) -> bool: return s["verb"] == "concert_application"), "the standing application shows as held")
	t.truth(held.all(func(s: Dictionary) -> bool: return String(s["disabled_reason"]) == ""), "and a held step carries no refusal")


func _test_the_map_learns_who_sits_in_which_bloc(t) -> void:
	var state := _state()
	state.foreign.reached["union_observer"] = 0
	state.foreign.reached["union_member"] = 0
	var memberships: Dictionary = NativeGameScript._build_snapshot(state)["foreign"]["map"]["memberships"]
	t.truth("union" in memberships["ardenia"], "Ardenia's Union membership is published for the map")
	t.truth("concert" in memberships["solheim"], "as is each world country's")
	t.truth(not ("concert" in memberships["ardenia"]), "an application is not membership")


func _test_the_game_takes_orientation_steps(t) -> void:
	var game: Node = NativeGameScript.new()
	game._state = _state()
	var result: Dictionary = game.orientation_act("meridian_partnership")
	t.truth(result.get("ok", false), "a step can be taken through the game")
	var steps: Array = result["snapshot"]["foreign"]["steps"]
	t.truth(steps.any(func(s: Dictionary) -> bool: return s["verb"] == "meridian_partnership" and s["held"]), "and the returned snapshot shows it held")
	t.truth(not game.orientation_act("meridian_partnership").get("ok", true), "a step cannot be taken twice")
	game.free()


func _test_a_save_without_a_ledger_is_seeded_on_load(t) -> void:
	_wipe()
	var state := _state()
	state.foreign = ForeignState.new()
	SaveStore.save_slot(SLOT, state)
	var game: Node = NativeGameScript.new()
	t.truth(game.load(SLOT).get("ok", false), "a save without a foreign ledger loads")
	t.truth(game._state.foreign.seeded and game._state.foreign.reached.has("isf_programme"), "and is seeded with the canon obligations")
	game.free()
	_wipe()


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_the_snapshot_carries_the_orientation_desk(t)
	_test_the_map_learns_who_sits_in_which_bloc(t)
	_test_the_game_takes_orientation_steps(t)
	_test_a_save_without_a_ledger_is_seeded_on_load(t)
	quit(t.finish())
```

Create `godot/tests/ui/test_orientation_desk.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const TEST_SLOT := "test_orientation_desk"

var t = TestSupportScript.new()
var app: Node = null
var game: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int = 2) -> void:
	for _i in range(count):
		await process_frame


func _fresh() -> void:
	if app != null:
		app.queue_free()
		await _frames()
	root.get_node("GameFlow").start_mode = "new"
	root.get_node("GameFlow").pending_seed = 424242
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	app.save_slot = TEST_SLOT
	root.add_child(app)
	game = root.get_node("NativeGame")
	await _frames(3)


func _wipe_slot() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := "user://saves/%s.json%s" % [TEST_SLOT, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _step_button(prefix: String) -> Button:
	var steps: VBoxContainer = app.find_child("OrientationSteps", true, false)
	for child in steps.get_children():
		if child is Button and (child as Button).text.begins_with(prefix):
			return child
	return null


func _run() -> void:
	_wipe_slot()
	await _test_the_desk_shows_where_ardenia_stands(t)
	await _test_a_step_can_be_taken_from_the_desk(t)
	await _test_a_step_out_of_reach_says_why(t)
	_wipe_slot()
	if app != null:
		app.queue_free()
	quit(t.finish())


func _test_the_desk_shows_where_ardenia_stands(t) -> void:
	await _fresh()
	app._open_diplomacy()
	await _frames()
	var powers: Label = app.find_child("OrientationPowers", true, false)
	t.truth(powers != null and powers.text.contains("KRASOVA") and powers.text.contains("leverage"), "the desk lists each power's hold over Ardenia")
	var reviews: Label = app.find_child("OrientationReviews", true, false)
	t.truth(reviews != null and reviews.text.contains("ISF"), "and the state of the ISF programme")
	var steps: VBoxContainer = app.find_child("OrientationSteps", true, false)
	t.truth(steps.get_children().any(func(c: Node) -> bool: return c is Label and (c as Label).text.contains("IN PLACE")), "standing obligations are shown as in place")


func _test_a_step_can_be_taken_from_the_desk(t) -> void:
	await _fresh()
	t.truth(game._state.player.in_government, "the desk test opens in government")
	game._state.player.political_capital = 500.0
	app.apply_snapshot(game.snapshot())
	app._open_diplomacy()
	await _frames()
	var button := _step_button("Meridian partnership")
	t.truth(button != null and not button.disabled, "the Meridian partnership can be joined from the desk")
	button.pressed.emit()
	await _frames(3)
	t.truth(game._state.foreign.reached.has("meridian_partnership"), "pressing it takes the step")
	var status: Label = app.find_child("DiplomacyStatus", true, false)
	t.truth(status.text.contains("Meridian"), "the desk reports it")
	t.truth(_step_button("Meridian partnership") == null, "and no longer offers it")


func _test_a_step_out_of_reach_says_why(t) -> void:
	await _fresh()
	app._open_diplomacy()
	await _frames()
	var button := _step_button("Meridian security guarantee")
	t.truth(button != null and button.disabled and button.tooltip_text != "", "a step out of reach is disabled with its reason")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_orientation_snapshot.gd`
Expected: `SCRIPT ERROR` (`orientation_act` not found on the node, or `foreign` missing), non-zero exit.
Run: `timeout 180 "$G" --headless --path godot --script res://tests/ui/test_orientation_desk.gd`
Expected: `FAIL  the desk lists each power's hold over Ardenia` (node missing), `M failed` with M > 0.

- [ ] **Step 3: The read model**

Append to `godot/scripts/native/actions/orientation_actions.gd`:

```gdscript
static func memberships(state: GameState) -> Dictionary:
	var out := {}
	for bloc_id in state.foreign.members:
		for country_id in state.foreign.members[bloc_id]:
			if not out.has(country_id):
				out[country_id] = []
			(out[country_id] as Array).append(String(bloc_id))
	var own: Array = []
	for bloc_id in PLAYER_BLOCS:
		if state.foreign.reached.has(PLAYER_BLOCS[bloc_id]):
			own.append(bloc_id)
	out[state.country.id] = own
	return out


static func read_model(state: GameState) -> Dictionary:
	if state == null or state.foreign == null or not state.foreign.seeded:
		return {"powers": [], "steps": [], "isf": {}, "western_qualifying_months": 0,
			"qualifying_months_needed": QUALIFYING_MONTHS_FOR_AGREEMENT, "map": {"memberships": {}}}
	var powers: Array = []
	for id in ForeignSim.power_ids():
		var row: Dictionary = state.foreign.powers.get(id, {})
		var p := ForeignSim.power(id)
		powers.append({"id": id, "name": String(p.get("name", id)), "kind": String(p.get("kind", "")),
			"dependence": float(row.get("dependence", 0.0)), "commitment": float(row.get("commitment", 0.0)),
			"leverage": float(row.get("leverage", 0.0))})
	var steps: Array = []
	for verb in VERBS:
		var held := state.foreign.reached.has(verb)
		var reason := reason_for(state, verb)
		steps.append({"verb": verb, "label": label_for(verb), "cost": float(COSTS[verb]), "held": held,
			"eligible": reason == "", "disabled_reason": "" if held else reason})
	var isf := state.foreign.isf
	var targets := OrientationSim.isf_targets(state)
	return {
		"powers": powers,
		"steps": steps,
		"isf": {
			"reviews_held": int(isf.get("reviews_held", 0)),
			"reviews_total": OrientationSim.ISF_REVIEWS,
			"passed": int(isf.get("passed", 0)),
			"failed": int(isf.get("failed", 0)),
			"suspended": bool(isf.get("suspended", false)),
			"last_result": String(isf.get("last_result", "")),
			"deficit_target": float(targets["deficit"]),
			"inflation_target": float(targets["inflation"]),
			"bank_required": int(isf.get("reviews_held", 0)) >= int(targets["bank_due_review"]),
		},
		"western_qualifying_months": state.foreign.western_qualifying_months,
		"qualifying_months_needed": QUALIFYING_MONTHS_FOR_AGREEMENT,
		"map": {"memberships": memberships(state)},
	}
```

- [ ] **Step 4: The game surface**

In `godot/scripts/native/native_game.gd`:

After `func diplomacy_act(...)` (before `func resolve_situation`), add:

```gdscript
func orientation_act(verb: String) -> Dictionary:
	return _guarded(func() -> Dictionary: return OrientationActions.act(_state, verb))
```

In `load`, after `BudgetSimScript.ensure_budget_state(incoming)`, add:

```gdscript
	ForeignSim.ensure(incoming)
```

In `_do_new_campaign`, after `BudgetSimScript.ensure_budget_state(fresh)`, add:

```gdscript
	ForeignSim.ensure(fresh)
```

In `_build_snapshot`, after `"diplomacy": DiplomacyActions.read_model(state).duplicate(true),`, add:

```gdscript
		"foreign": OrientationActions.read_model(state).duplicate(true),
```

- [ ] **Step 5: The desk scene**

In `godot/scenes/panels/diplomacy_panel.tscn`, change the `Intro` text to:

```
text = "Set the country's orientation first, then choose a country to see where you stand with it and spend political capital on the relationship."
```

Insert these node blocks directly before `[node name="CountryStanding" ...]`:

```
[node name="OrientationHeading" type="Label" parent="Content/DiplomacyScroll/DiplomacyBody"]
layout_mode = 2
size_flags_horizontal = 3
theme_type_variation = &"Section"
text = "ORIENTATION"

[node name="OrientationPowers" type="Label" parent="Content/DiplomacyScroll/DiplomacyBody"]
layout_mode = 2
size_flags_horizontal = 3
text = ""
autowrap_mode = 3

[node name="OrientationReviews" type="Label" parent="Content/DiplomacyScroll/DiplomacyBody"]
layout_mode = 2
size_flags_horizontal = 3
theme_type_variation = &"Muted"
text = ""
autowrap_mode = 3

[node name="OrientationSteps" type="VBoxContainer" parent="Content/DiplomacyScroll/DiplomacyBody"]
layout_mode = 2
size_flags_horizontal = 3
theme_override_constants/separation = 6

[node name="OrientationRule" type="HSeparator" parent="Content/DiplomacyScroll/DiplomacyBody"]
layout_mode = 2
```

- [ ] **Step 6: The desk refresh**

In `godot/scripts/app.gd`, `_refresh_diplomacy`, add as the first line of the body:

```gdscript
	_refresh_orientation()
```

After `func _set_diplomacy_status`, add:

```gdscript
func _refresh_orientation() -> void:
	var foreign: Dictionary = snapshot.get("foreign", {})
	var panel = %DiplomacyPanel
	var lines: Array[String] = []
	for p in foreign.get("powers", []):
		lines.append("%s / dependence %.2f / commitment %.2f / leverage %.2f" % [
			str(p.get("name", "")).to_upper(), float(p.get("dependence", 0.0)),
			float(p.get("commitment", 0.0)), float(p.get("leverage", 0.0))])
	panel.find_child("OrientationPowers").text = "\n".join(lines)
	panel.find_child("OrientationReviews").text = _isf_line(foreign.get("isf", {}), foreign)
	var box: VBoxContainer = panel.find_child("OrientationSteps")
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for step in foreign.get("steps", []):
		if step.get("held", false):
			var held := Label.new()
			held.theme_type_variation = &"Muted"
			held.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			held.text = "IN PLACE / %s" % str(step.get("label", ""))
			box.add_child(held)
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cost := float(step.get("cost", 0.0))
		button.text = str(step.get("label", "")) + ("   · %.0f PC" % cost if cost > 0.0 else "")
		button.disabled = not step.get("eligible", false)
		button.tooltip_text = str(step.get("disabled_reason", ""))
		button.pressed.connect(_take_orientation_step.bind(str(step.get("verb", ""))))
		box.add_child(button)
		var reason := str(step.get("disabled_reason", ""))
		if reason != "":
			var why := Label.new()
			why.theme_type_variation = &"Muted"
			why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			why.text = reason
			box.add_child(why)


static func _isf_line(isf: Dictionary, foreign: Dictionary) -> String:
	if isf.is_empty():
		return ""
	return "ISF reviews %d of %d / passed %d / failed %d%s / next targets: deficit %.1f%%, inflation %.1f%%%s\nConcert discipline: %d of %d months" % [
		int(isf.get("reviews_held", 0)), int(isf.get("reviews_total", 0)),
		int(isf.get("passed", 0)), int(isf.get("failed", 0)),
		" / SUSPENDED" if isf.get("suspended", false) else "",
		float(isf.get("deficit_target", 0.0)) * 100.0, float(isf.get("inflation_target", 0.0)) * 100.0,
		", independent bank" if isf.get("bank_required", false) else "",
		int(foreign.get("western_qualifying_months", 0)), int(foreign.get("qualifying_months_needed", 0))]


func _take_orientation_step(verb: String) -> void:
	if _game == null:
		return
	var result: Dictionary = _game.orientation_act(verb)
	_flush_snapshot()
	_sfx_result(result)
	if not result.get("ok", false):
		_set_diplomacy_status("REFUSED / %s" % result.get("error", "Unknown error"))
		return
	_set_diplomacy_status(str(result.get("message", "")))
```

- [ ] **Step 7: Import and run the tests to verify they pass**

Run: `timeout 180 "$G" --headless --path godot --import`
Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_orientation_snapshot.gd`
Run: `timeout 180 "$G" --headless --path godot --script res://tests/ui/test_orientation_desk.gd`
Expected: both `NATIVE TESTS: N passed, 0 failed`.

- [ ] **Step 8: Look at it**

Launch the GUI (`"$G" --path godot`), start a new campaign, open Diplomacy, take a screenshot. Check: the orientation block sits above the country picker, text uses the pixel fonts, nothing scrolls sideways, and the header still fits at 1280 wide. Fix any overflow before continuing.

- [ ] **Step 9: Mutation-check**

- Delete `ForeignSim.ensure(incoming)` from `load` → "is seeded with the canon obligations" fails.
- In `memberships`, delete the `PLAYER_BLOCS` loop → "Ardenia's Union membership is published" fails.
- In `read_model`, set `"disabled_reason": reason` → "a held step carries no refusal" fails.
- In `_refresh_orientation`, delete the `if step.get("held", false):` block → "shown as in place" and "no longer offers it" fail.
- In `_refresh_orientation`, delete `button.disabled = ...` → "disabled with its reason" fails.

- [ ] **Step 10: Run the full battery.** `test_app_behaviour.gd` and the vertical slice must stay green.

- [ ] **Step 11: Commit**

```bash
git add godot/scripts/native/actions/orientation_actions.gd godot/scripts/native/native_game.gd godot/scenes/panels/diplomacy_panel.tscn godot/scripts/app.gd godot/tests/native/test_orientation_snapshot.gd godot/tests/native/test_orientation_snapshot.gd.uid godot/tests/ui/test_orientation_desk.gd godot/tests/ui/test_orientation_desk.gd.uid
git commit -m "$(cat <<'EOF'
feat(godot): orientation on the Diplomacy desk and bloc memberships for the map

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Calendar-true journeys, determinism and the living-world record

**Files:**
- Test: `godot/tests/native/test_orientation_journeys.gd`
- Modify: `docs/godot/LIVING_WORLD.md` (new `## Orientation` section after `## Diplomacy`)
- Possibly modify: `godot/scripts/native/sim/orientation_sim.gd` (`ISF_DEFICIT_TARGET` only, Step 3)

**Interfaces:**
- Consumes: `NativeGame.next_month`, `test_fiscal_journeys.gd`'s `static func steady_budget(state)`, `OrientationActions.act`, `DiplomacyActions.act`, `ForeignSim.dependence/leverage_of/power_ids`, `StateValidator.validate`.
- Produces: nothing for later code; the guardrail later plans extend with gas cuts and incidents.

- [ ] **Step 1: Write the journey test**

Create `godot/tests/native/test_orientation_journeys.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const FiscalJourneys = preload("res://tests/native/test_fiscal_journeys.gd")
const SEEDS := [919191, 31, 424242, 7]
const STRATEGIES := ["neutral", "western", "union"]
const MONTHS := 240
const WESTERN_STEPS := ["meridian_partnership", "concert_agreement", "meridian_guarantee"]
const UNION_STEPS := ["union_observer", "union_member"]
const OUTREACH_RESERVE := 40.0


static func _state(seed: int) -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": seed})
	state.rng = SimRng.from_seed(seed)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	return state


static func _score(state: GameState, id: String) -> float:
	return (state.country.relations[id] as Country.BilateralRelation).score


static func _bloc_trade(state: GameState, bloc_id: String) -> float:
	var total := 0.0
	for id in state.foreign.members.get(bloc_id, []):
		if state.country.relations.has(id):
			total += (state.country.relations[id] as Country.BilateralRelation).trade_volume
	return total


static func _play(state: GameState, strategy: String) -> void:
	FiscalJourneys.steady_budget(state)
	OrientationActions.act(state, "isf_renegotiate")
	match strategy:
		"western":
			for verb in WESTERN_STEPS:
				OrientationActions.act(state, verb)
		"union":
			for verb in UNION_STEPS:
				OrientationActions.act(state, verb)
			if state.player.political_capital > OUTREACH_RESERVE:
				DiplomacyActions.act(state, "improve_relations", "krasova")


static func _unbounded(state: GameState) -> int:
	var count := 0
	for id in ForeignSim.power_ids():
		var row: Dictionary = state.foreign.powers.get(id, {})
		for field in ["dependence", "commitment", "leverage"]:
			var v := float(row.get(field, -1.0))
			if not is_finite(v) or v < 0.0 or v > 1.0:
				count += 1
	return count


static func _signature(state: GameState) -> String:
	var reached: Array = state.foreign.reached.keys()
	reached.sort()
	return str([state.foreign.members, int(state.foreign.isf["passed"]), int(state.foreign.isf["failed"]),
		reached, snappedf(_score(state, "krasova"), 0.001), state.event_history.size()])


static func _journey(seed: int, strategy: String, months: int) -> Dictionary:
	var state := _state(seed)
	var approval := 0.0
	var lowest_stability := 1.0
	var krasova_warmth := 0.0
	var concert_trade := 0.0
	var invalid := 0
	var unbounded := 0
	for m in range(months):
		_play(state, strategy)
		NativeGameScript.next_month(state)
		approval += state.player.approval / float(months)
		lowest_stability = minf(lowest_stability, state.stability_value)
		krasova_warmth += _score(state, "krasova") / float(months)
		concert_trade += _bloc_trade(state, "concert") / float(months)
		unbounded += _unbounded(state)
		if m % 12 == 11 and not StateValidator.validate(state).is_empty():
			invalid += 1
	return {"approval": approval, "lowest_stability": lowest_stability, "krasova_warmth": krasova_warmth,
		"concert_trade": concert_trade, "invalid": invalid, "unbounded": unbounded,
		"gdp": state.country.economy.gdp, "reached": state.foreign.reached.keys(),
		"isf": state.foreign.isf.duplicate(), "signature": _signature(state), "foreign": state.foreign.to_dict()}


func _test_every_orientation_is_viable_and_bounded(t, runs: Dictionary) -> void:
	for key in runs:
		var r: Dictionary = runs[key]
		t.equal(int(r["invalid"]), 0, "%s: the state stays valid every year" % key)
		t.equal(int(r["unbounded"]), 0, "%s: every gauge stays within 0..1" % key)
		t.truth(float(r["approval"]) >= 0.25 and float(r["approval"]) <= 0.75, "%s: approval stays in a sane band (%.3f)" % [key, r["approval"]])
		t.truth(float(r["lowest_stability"]) >= 0.15, "%s: the state never collapses (lowest stability %.3f)" % [key, r["lowest_stability"]])


func _test_each_orientation_reaches_its_goal(t, runs: Dictionary) -> void:
	var members := 0
	for seed in SEEDS:
		t.truth("meridian_partnership" in runs["western/%d" % seed]["reached"], "seed %d: a Western-leaning government joins the Meridian partnership" % seed)
		t.truth(not ("union_observer" in runs["neutral/%d" % seed]["reached"]), "seed %d: a neutral government stays out of the Union" % seed)
		t.truth(not ("union_observer" in runs["western/%d" % seed]["reached"]), "seed %d: a Western-leaning one does too" % seed)
		if "union_member" in runs["union/%d" % seed]["reached"]:
			members += 1
	t.truth(members * 2 >= SEEDS.size(), "a Krasova-leaning government usually reaches membership (%d of %d)" % [members, SEEDS.size()])


func _test_each_orientation_has_a_price(t, runs: Dictionary) -> void:
	for seed in SEEDS:
		var neutral: Dictionary = runs["neutral/%d" % seed]
		var west: Dictionary = runs["western/%d" % seed]
		var union: Dictionary = runs["union/%d" % seed]
		t.truth(float(west["krasova_warmth"]) < float(neutral["krasova_warmth"]), "seed %d: leaning west costs Krasova's goodwill (%.3f < %.3f)" % [seed, west["krasova_warmth"], neutral["krasova_warmth"]])
		if "union_member" in union["reached"]:
			t.truth(float(union["concert_trade"]) < float(neutral["concert_trade"]), "seed %d: Union tariffs cost Western trade (%.0f < %.0f)" % [seed, union["concert_trade"], neutral["concert_trade"]])
			t.truth(float(neutral["gdp"]) < float(union["gdp"]), "seed %d: staying neutral forgoes the Union's markets (%.0f < %.0f)" % [seed, neutral["gdp"], union["gdp"]])


func _test_the_isf_is_demanding_but_passable(t, runs: Dictionary) -> void:
	var passed := 0
	var held := 0
	for seed in SEEDS:
		var isf: Dictionary = runs["neutral/%d" % seed]["isf"]
		passed += int(isf["passed"])
		held += int(isf["reviews_held"])
	var share := float(passed) / float(maxi(1, held))
	t.equal(held, SEEDS.size() * OrientationSim.ISF_REVIEWS, "every programme runs all its reviews")
	t.truth(share >= 0.2 and share <= 0.9, "a steady government passes some reviews and fails others (%.2f)" % share)


func _test_seeds_write_different_foreign_histories(t, runs: Dictionary) -> void:
	var seen := {}
	for seed in SEEDS:
		seen[String(runs["neutral/%d" % seed]["signature"])] = true
	t.truth(seen.size() >= 3, "different seeds give different foreign histories (%d distinct of %d)" % [seen.size(), SEEDS.size()])


func _test_the_same_seed_and_choices_repeat_exactly(t) -> void:
	var a := _journey(424242, "union", 60)
	var b := _journey(424242, "union", 60)
	t.equal(a["foreign"], b["foreign"], "the same seed and the same choices give the same foreign ledger")
	t.equal(a["signature"], b["signature"], "and the same history")


func _initialize() -> void:
	var t = TestSupportScript.new()
	var runs := {}
	for strategy in STRATEGIES:
		for seed in SEEDS:
			runs["%s/%d" % [strategy, seed]] = _journey(seed, strategy, MONTHS)
	_test_every_orientation_is_viable_and_bounded(t, runs)
	_test_each_orientation_reaches_its_goal(t, runs)
	_test_each_orientation_has_a_price(t, runs)
	_test_the_isf_is_demanding_but_passable(t, runs)
	_test_seeds_write_different_foreign_histories(t, runs)
	_test_the_same_seed_and_choices_repeat_exactly(t)
	quit(t.finish())
```

- [ ] **Step 2: Run it**

Run: `time timeout 180 "$G" --headless --path godot --import && time timeout 180 "$G" --headless --path godot --script res://tests/native/test_orientation_journeys.gd`
Expected: `NATIVE TESTS: N passed, 0 failed`. If the run takes over 150 s, split the file by strategy into `test_orientation_journeys_neutral.gd`, `_western.gd`, `_union.gd` (each keeps `_journey`, `_play` and the helpers, runs its own strategy plus `neutral` for the comparisons it needs, and the determinism test lives in the neutral file), so each stays under the timeout.

- [ ] **Step 3: Calibrate the ISF only if the band assertion fails**

If "passes some reviews and fails others" fails, print the deficit share at each review month for the four neutral seeds (add a temporary `print` in `_isf_review`, run, then remove it), and move `OrientationSim.ISF_DEFICIT_TARGET` so a steady government's share lands inside 0.2–0.9. Change no other constant. If any other journey assertion fails, it is a balance finding: report the numbers rather than loosening the threshold.

- [ ] **Step 4: Mutation-check**

- `ForeignSim.UNION_TARIFF_SHARE := 1.0` → "Union tariffs cost Western trade" fails on member seeds.
- Empty `OrientationActions.REACTIONS["meridian_partnership"]` and `["concert_agreement"]` (set both to `{}`) → "leaning west costs Krasova's goodwill" fails.
- `OrientationActions.UNION_GROWTH := 0.0` → "forgoes the Union's markets" fails.
- In `_isf_review`, compute `passed := true` → the ISF band assertion fails.
- In `ForeignSim.leverage`, return `dependence(...) * 2.0` with no clamp → "every gauge stays within 0..1" fails.

- [ ] **Step 5: Record the design in `docs/godot/LIVING_WORLD.md`**

Add after the `## Diplomacy` section:

```markdown
## Orientation

Ardenia's alignment is never a label. Five powers (Krasova, the ISF, the
Concert, the Meridian Treaty Organisation and the Krasovan Economic Union)
each carry three numbers, kept in `GameState.foreign` and recomputed every
month by `ForeignSim` after the diplomacy pass and before the world acts:
**dependence** (half gas share, a quarter of the debt it holds, a quarter
of Ardenia's trade with it), **commitment** (the furthest milestone signed
on its track; Krasova also counts its treaties and half the Union's
commitment) and **leverage** (dependence, blunted by warm relations,
sharpened by a quarter in the October–March heating season for a gas
supplier). A hostile Krasovan move hits harder by up to half its leverage,
and a Meridian guarantee shelves hostile plans like a defence pact.

**The ISF.** Twelve quarterly reviews (January, April, July, October)
judge the deficit (5% of GDP) and inflation (8%), and from the fifth
review the Central Bank Independence Act. A pass releases a tranche of
0.4% of GDP into the budget over three months and lifts growth briefly; a
fail suspends the programme and dents growth for six months. A suspended
programme can be renegotiated for 15 PC: the tranche is released, both
targets tighten by 15% and the bank condition moves four reviews later.

**The Western ladder.** The Concert application is lodged at the start.
The association agreement needs 36 months of discipline (deficit ≤ 4%,
inflation ≤ 8%; a loose month costs two) and an independent bank. The
Meridian partnership is open at once; a guarantee needs 24 months of
partnership and a resolved Vetrenka (settled, retaken or partitioned).

**The Union.** Observer status needs Krasova no colder than −0.35;
membership needs a year as observer and Krasova no colder than −0.15.
Membership brings open markets (growth phasing in over a year) and
rescheduled debt (60 M a year for three years), caps Concert trade at 60%
of its ceiling, and needs Union consent to sanction or condemn a member or
to sign a defence pact outside the bloc. Walking out costs stability,
growth for a year and 0.35 of Krasova's goodwill, and bars re-entry for
five years. The only hard locks: a member cannot hold the association
agreement or a Meridian guarantee.

**Blocs in the world.** Every January each bloc re-reads its world
members: democratic traders and reformers warm to Solheim drift into the
Concert (and, if steadier, the Meridian); revanchists, autocratic hegemons
and Krasova's clients warm to Krasova drift into the Union. Anchors never
leave, and no country sits on both sides. The snapshot publishes
memberships under `foreign.map.memberships` for the map.

Twenty-year journeys on four seeds for each of three strategies (neutral,
Western, Krasovan) check that each is viable, bounded and costly, and that
seeds diverge.
```

- [ ] **Step 6: Run the full battery.** Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add godot/tests/native/test_orientation_journeys*.gd godot/tests/native/test_orientation_journeys*.gd.uid docs/godot/LIVING_WORLD.md godot/scripts/native/sim/orientation_sim.gd
git commit -m "$(cat <<'EOF'
test(godot): twenty-year orientation journeys, and the record in LIVING_WORLD

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Self-review

**Spec coverage (delivery item 1):**
- Spine: dependence, commitment, leverage (§1) → Task 2; world AI reads leverage → Task 2 (ruling 8). Tension is plan 4 (interface listed).
- Map hand-off for what this plan creates → Task 6 (`foreign.map.memberships`, per-power gauges); gas, incidents and tension keys are reserved for plans 2 and 4.
- ISF reviews, pass/fail, renegotiation for PC with tighter later targets (§2) → Task 3 (ruling 3 for the situation).
- Western ladder and the guarantee locked while Vetrenka is unresolved → Task 4 (ruling 5).
- Union steps, benefits, costs, consent, costly exit → Task 4 (ruling 4 for gas benefits).
- Hard locks, few and explicit → Task 4 actions, Task 1 validator.
- AI memberships by agenda → Task 5.
- Milestone PC and treasury costs, effects, reactions of other powers → Task 4 (`COSTS`, `TREASURY_DEBT`, `REACTIONS`).
- Persistence, old saves, validator (gauges, negative counters, lock combinations, unknown ids) → Task 1, with seeding on load in Task 6.
- Diplomacy desk orientation section → Task 6.
- Journeys: viable, costly, bounded, divergent, deterministic → Task 7 (ruling 9).
- `LIVING_WORLD.md` update → Task 7.

**Placeholder scan:** every code step shows its code. The one conditional step (Task 7 Step 3) names the single constant to move and the band it must land in.

**Type consistency:** `ForeignState` fields and `ForeignSim`/`OrientationSim`/`OrientationActions` names match across tasks. `OrientationActions.VERBS`, `COSTS`, `OBSERVER_MONTHS_FOR_MEMBERSHIP`, `PARTNERSHIP_MONTHS_FOR_GUARANTEE`, `QUALIFYING_MONTHS_FOR_AGREEMENT` and `EXIT_RELATIONS_COST` are defined in Task 4 and used in Tasks 4, 6 and 7. `OrientationSim.BANK_ACT`, `ISF_BANK_DELAY`, `ISF_BANK_DUE_REVIEW`, `ISF_REVIEWS`, `isf_targets`, `release_tranche`, `timed_modifier` and `line` come from Task 3. `ForeignSim.trade_ceiling_share`, `UNION_TARIFF_SHARE` and `vetrenka_resolved` come from Task 4, `leverage_of` and `update_spine` from Task 2, `UNION_LOCKS` from Task 1.
