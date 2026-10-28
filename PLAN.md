# Plan: Rebuild Ardenia as a native Godot game

_Locked via claudex-loop — by Claude + user, 2026-09-16._

> **This file supersedes the `N0`–`N6` native-rewrite parity programme.** It is
> the current authority for the Godot rebuild and is written to be read cold by a
> fresh agent session. If you are resuming work on this repository, start here —
> see *For the incoming agent* below before touching anything under
> `docs/godot/native_port/` or `scripts/native_port/`.

---

## Context — why this plan exists, and what it replaces

Ardenia is a political simulation currently written in Python: a PySide6 desktop
app (`gui.py`), a terminal front-end (`main.py`), and ~9,700 lines of simulation
in `engine/` over ~6,300 lines of content and lore. It works, and it ships — a
built executable exists at `dist\Ardenia\Ardenia.exe` (v0.1.0-playtest.1).

Earlier work migrated presentation to Godot via a **bridge**: Godot rendered a
dashboard while Python remained authoritative, connected by a JSON-lines
subprocess. That reached gate G1 and produced real, reusable Godot work — a map,
a themed dashboard, a menu, save/load, crash recovery.

On 2026-09-16 a second programme was written on top of that: a **native rewrite
governed by a parity contract** (`N0`–`N6`), requiring every mechanic to be
proven numerically equal to the Python implementation within `1e-9`, tracked in
`docs/godot/native_port/PARITY_MATRIX.md`, with both implementations
bug-fixed in lockstep until cutover. Phase N0 (fixtures, comparator, test
harness) was built and largely completed.

**That parity contract is now cancelled.** It was never what the user asked for.
The ask is to *remake the game in Godot* — "a legitimate game with assets,
mechanics, ui, and whatever else the video game consists of" — using the Python
implementation as the **design reference for what Ardenia contains**, not as an
oracle whose arithmetic must be reproduced. Proving equivalence is a far harder
and larger project than building the game, and it bought nothing: there are no
existing players whose saves need to migrate.

Two research findings reinforce the cancellation. Godot's own documentation
states float math "is not guaranteed to be exact or deterministic" and varies
across CPUs, operating systems and versions — so the `1e-9` cross-language
target may not have been physically reachable. And the spec's mandated
nested-untyped-`Dictionary` state, chosen purely so a comparator could diff it
against Python, sits on GDScript's slowest execution path.

### For the incoming agent (Codex, on credit reset)

If you previously worked on the `N0`–`N6` native-rewrite programme, read this
section before anything else:

- **Do not continue the parity programme.** `PARITY_MATRIX.md`, the oracle
  fixtures under `godot/data/native/fixtures/`, `scripts/native_port/compare_native_snapshot.py`
  and `export_oracle_fixtures.py`, and the six phase plans `2026-09-16-native-godot-phase-*.md`
  are **superseded**. They remain in the tree as audit trail, marked as such.
  Do not delete them; do not build on them.
- **One piece of your N0 work survives and is valued:** the dependency-free test
  harness — `godot/scripts/native/testing/test_support.gd` and
  `godot/tests/native/run_contract_tests.gd`. It is useful regardless of the
  parity question and remains the native test runner for this plan.
- **What changed:** Python is now a *reference to read*, not a *target to match*.
  Write idiomatic Godot. Use typed GDScript classes and `Resource`s, not untyped
  dictionaries. Balance by feel and playtest, not by comparator.
- The authority documents are this file and the rewritten master plan/spec; the
  older `docs/superpowers/specs/2026-09-16-native-godot-rewrite-design.md`
  parity sections no longer bind.

---

## Goal

Ship Ardenia as a native Godot 4.7.2 Windows game — no Python at runtime, no
bridge, no worker process — that a player downloads, launches, and plays: a
political career through government and opposition in Ardenia, with the
mechanical depth the Python build already proves out, and with the production
values of a real game (art direction, typography, UI feel, audio, feedback).
The Python source is frozen as a design reference and remains the playable build
until the Godot one surpasses it.

## Approach

Six phases, each ending in something you can launch and play. UI is built as
each phase lands — minimally but functionally — so the game is continuously
playable; Phase 5 is where it becomes a *product*, not where the interface first
appears.

### Phase 1 — Native core (campaign exists without Python)

1. Export content to committed JSON under `godot/data/native/`: the nine
   countries, factions and blocs, regions, household groups, bill catalogue,
   budget envelopes, reform objectives, traits, events, dispatch pools, press
   templates, and the Ardenian lore package. Mechanical translation from
   `content/`. Python callables become stable symbolic rule ids resolved by a
   native registry.
2. Typed GDScript state: `GameState`, `Country`, `Faction`, `Region`,
   `HouseholdGroup`, `Minister`, `Economy`, `Modifier`, `AnnualBudget`,
   `MinistryState` as classes under `godot/scripts/native/state/`.
3. Campaign creation — Ardenia only, with background, difficulty, opening role
   (government/opposition), and explicit seed.
4. Calendar: day tick, month rollover, the modifier lifecycle
   (`onset → ramp → hold → decay`).
5. Serializable RNG owned by campaign state, so a reload continues deterministically.
6. Native save/load: versioned format, atomic write-then-replace, under `user://saves/`.
7. **Cut the bridge from the running app.** The existing dashboard reads native
   state. `SimulationBridge` stops being loaded by production scenes.

*Playable result:* the current dashboard runs with zero Python. Date advances,
campaigns start, saves reload.

#### Phase 1 tasks

Decomposed for subagent dispatch. No task here produces or checks oracle
parity — tests are functional (does the mechanic behave correctly), not
comparative (does it match Python's number). State is typed GDScript classes;
raw `Dictionary`/`Array` is normal and expected at JSON I/O boundaries (content
loading, save files) but never the canonical in-memory representation of
campaign state.

### Task 1: Native content export and content repository

**Files:**
- Create: `scripts/native_port/export_native_content.py`
- Create: `godot/data/native/catalog_manifest.json`
- Create: `godot/data/native/countries/*.json` (all nine countries)
- Create: `godot/data/native/catalogs/*.json` (bills, budget envelopes, reform
  objectives/instruments/scopes, traits, events, dispatch pools, press
  templates, household groups, regions and programmes, backgrounds,
  difficulties)
- Create: `godot/data/native/lore/*.json` (the Ardenian lore package —
  timeline, geography, society, institutions, economy, parties, figures)
- Create: `godot/scripts/native/content/content_repository.gd`
- Create: `godot/tests/native/test_content_repository.gd`

**Interfaces:**
- Produces: `ContentRepository.load_all() -> Dictionary` (raw content lookup by
  id, keyed by catalog — this is the JSON I/O boundary, not campaign state)
- Produces: development command `export_native_content.py --write`, the only
  writer of `godot/data/native/**/*.json`

**Read first:** `content/loader.py`, `content/countries/*.json`,
`content/bills.py`, `content/budget.py`, `content/reforms.py`,
`content/traits.py`, `content/events.py`, `content/households.py`,
`content/regions.py`, `content/campaign_content.py`, `content/lore/` — these
are the design reference. Reproduce their *content and structure*, not their
Python code. Python callables (event conditions, requirements, appliers)
become stable symbolic string ids; do not try to serialize Python behavior —
Task 2's game systems will implement the actual logic natively in GDScript
against these ids.

- [ ] Write `export_native_content.py`: reads the Python content modules via
      the existing `.venv` interpreter, emits one JSON file per catalog listed
      above, and writes `catalog_manifest.json` (schema version, file list,
      per-catalog id counts).
- [ ] Run `export_native_content.py --write` twice; require no diff on the
      second run (deterministic export).
- [ ] Implement `ContentRepository.load_all()`: reads `catalog_manifest.json`,
      loads every listed file, rejects duplicate ids within a catalog, and
      returns clear errors (not partial data) on a missing or malformed file.
- [ ] Write `test_content_repository.gd`: loads all content, asserts all nine
      countries are present with their factions/wings, asserts the Ardenian
      bloc set (twelve currents) loads correctly, asserts every catalog listed
      in the manifest is non-empty, asserts duplicate-id rejection actually
      rejects.
- [ ] Run the test via the existing N0 harness:
      `& "D:\AI Stuff\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path godot --script res://tests/native/test_content_repository.gd`
- [ ] Run `D:\Political Sim Game\.venv\Scripts\python.exe smoke_test.py` to
      confirm the Python source is untouched and still passes (it is the
      reference; this task must not edit it).
- [ ] Commit `feat(godot): export native content and add content repository`.

### Task 2: Typed campaign state and the new-campaign factory

**Files:**
- Create: `godot/scripts/native/state/game_state.gd` (typed class, `extends RefCounted`)
- Create: `godot/scripts/native/state/country.gd`, `faction.gd`, `region.gd`,
  `household_group.gd`, `minister.gd`, `economy.gd`, `modifier.gd`,
  `annual_budget.gd`, `ministry_state.gd` (typed classes matching
  `models/*.py` field-for-field, as a design reference)
- Create: `godot/scripts/native/state/game_factory.gd`
- Create: `godot/scripts/native/state/state_validator.gd`
- Create: `godot/tests/native/test_game_factory.gd`

**Interfaces:**
- Consumes: `ContentRepository.load_all()` from Task 1.
- Produces: `GameFactory.new_campaign(config: Dictionary) -> GameState` —
  `config` carries country (Ardenia only — validate and reject others),
  background id, difficulty id, opening role, and an explicit integer seed.
- Produces: `StateValidator.validate(state: GameState) -> PackedStringArray` —
  empty array means valid.

**Read first:** `content/loader.py: build_state_for`, `game_state.py`,
`models/country.py`, `models/faction.py`, `engine/campaign.py`.

- [ ] Write `test_game_factory.gd`: constructs a campaign with a fixed seed,
      asserts Ardenia's player/party/government are set correctly for each of
      the three opening roles (contextual/government/opposition), asserts all
      eight other countries exist as world actors with bilateral relations
      wired for every country pair, asserts `StateValidator.validate()` passes
      on the result.
- [ ] Run the test; expect missing-script failure.
- [ ] Implement the typed state classes and `GameFactory`. Ardenia is the only
      player-selectable country — enforce this the same way
      `ui/menu.py: PLAYABLE_COUNTRY_IDS` does in the Python build, referenced
      as the design pattern, not imported.
- [ ] Implement `StateValidator`: required fields present, faction seats sum
      correctly per country, relation symmetry, numeric ranges sane.
- [ ] Run the test; all assertions pass.
- [ ] Commit `feat(godot): add typed native campaign state and factory`.

### Task 3: Calendar, modifiers, and serializable RNG

**Files:**
- Create: `godot/scripts/native/state/sim_rng.gd`
- Create: `godot/scripts/native/sim/calendar.gd`
- Create: `godot/scripts/native/sim/modifiers.gd`
- Create: `godot/tests/native/test_foundation_mechanics.gd`

**Interfaces:**
- Produces: `SimRng.from_seed(seed: int)`, `next_u32() -> int`,
  `next_float() -> float`, `choose_index(size: int) -> int`,
  `to_dict() -> Dictionary`, `from_dict(data: Dictionary) -> SimRng` (the save
  boundary — RNG state persists as a dict inside the save file, same as any
  other serialized field).
- Produces: `Calendar.advance_day(state: GameState) -> bool` (return value:
  did the month roll over).
- Produces: `Modifiers.current_value(modifier: Modifier) -> float`,
  `is_expired(modifier: Modifier) -> bool`, `age_all(state: GameState) -> void`.

**Read first:** `models/modifiers.py` (the onset/ramp/hold/decay lifecycle —
"the engine recomputes each modifier's current value fresh every turn —
nothing accumulates" is load-bearing, per `CLAUDE.md`), the calendar logic in
`engine/turn.py` and `game_state.py`.

- [ ] Write failing tests: leap years, month/year rollover, `day_index`
      continuity, modifier onset/ramp/hold/decay/expiry (including
      `institutional=False` never being discounted), RNG replay after a
      `to_dict()`/`from_dict()` round trip, RNG rejecting a malformed seed.
- [ ] Run test; expect missing-script failure.
- [ ] Implement one small, well-known PRNG algorithm (e.g. PCG32 or
      xorshift64*) using GDScript's signed 64-bit `int` with explicit masking
      after every transition — GDScript has no unsigned 64-bit type and
      silently wraps on overflow, so mask deliberately rather than relying on
      wraparound. Document the algorithm and constants in the file. This RNG
      only needs to be deterministic *within the Godot build* across
      platforms — it is not required to reproduce Python's `random` stream.
- [ ] Port the calendar and modifier lifecycle logic as a design reference —
      same phases, same formulas — written idiomatically in GDScript.
- [ ] Run the tests twice; require byte-identical RNG sequence across runs
      and all calendar/modifier assertions passing.
- [ ] Commit `feat(godot): add native calendar, modifiers, and rng`.

### Task 4: Native persistence and the NativeGame state owner

**Files:**
- Create: `godot/scripts/native/state/save_store.gd`
- Create: `godot/scripts/native/native_game.gd`
- Modify: `godot/project.godot` (register `NativeGame` autoload; remove
  `SimulationBridge` from production autoloads)
- Modify: `godot/scripts/app.gd`, `godot/scripts/menu.gd`,
  `godot/scripts/game_flow.gd` (read from `NativeGame` instead of submitting
  bridge requests)
- Create: `godot/tests/native/test_native_persistence.gd`
- Create: `godot/tests/native/test_native_game.gd`

**Interfaces:**
- Consumes: `GameFactory`, `SimRng`, `Calendar`, `Modifiers` from Tasks 2-3.
- Produces: `SaveStore.save_slot(slot: String, state: GameState) -> Dictionary`
  and `load_slot(slot: String) -> Dictionary`, each `{ok, state|error}`. Save
  format is native-only — no Python save compatibility required (Global
  Constraint: no existing players).
- Produces `NativeGame` (autoload) signals `state_changed(snapshot)`,
  `fatal_error(message)`; methods `new_campaign(config)`, `advance_day()`,
  `save(slot)`, `load(slot)`, `snapshot()`.

**Read first:** `engine/persistence.py` (the hand-written, versioned,
tolerant-of-missing-fields approach is the pattern worth keeping, even though
the schema itself is new), the current bridge-era `godot/scripts/app.gd` and
`godot/scripts/bridge/simulation_bridge.gd` (being replaced — read for the
UI-facing contract shape, e.g. what `apply_snapshot` expects, so the swap is
close to drop-in).

- [ ] Write failing tests: exact save/load round trip including RNG
      continuity, corrupt-JSON rejection, unsupported version rejection, path
      traversal rejected by a slot regex `^[a-z0-9_-]{1,48}$`, atomic
      write-then-replace survives an interrupted write (verify via a `.tmp`
      file left behind and a `.bak` recovery path).
- [ ] Write a `NativeGame` test: start seed `424242`, advance one day, save,
      replace in-memory state with a second campaign, load, assert full
      restoration including RNG state.
- [ ] Run tests; expect missing-script failures.
- [ ] Implement `SaveStore` under `user://saves/` with atomic
      write-then-replace and `.bak` recovery.
- [ ] Implement `NativeGame`: one private state field, one in-flight-operation
      guard, calls `StateValidator` after any state replacement (new
      campaign or load), returns deep-duplicated read-only snapshots.
- [ ] Register `NativeGame` as the sole production autoload; remove
      `SimulationBridge` from `project.godot`'s production autoload list (it
      may remain in the tree for reference but must not be loaded by
      `scenes/menu.tscn` or `scenes/main.tscn`).
- [ ] Update `app.gd`/`menu.gd`/`game_flow.gd` to call `NativeGame` directly
      (no request/response round trip needed — it's in-process now) instead of
      `_bridge.request(...)`. Keep the existing UI layout, header, map, and
      Save/Load buttons from the bridge era; only the data source changes.
- [ ] Run all native tests and the full N0 harness; grep the Godot process
      tree during a manual launch to confirm no Python child process starts.
- [ ] Manually launch
      `& "D:\AI Stuff\Godot\Godot_v4.7.2-stable_win64_console.exe" --path godot` and
      play through: new campaign, region selection, objective adoption, a few
      days of advance, save, quit, relaunch, continue.
- [ ] Commit `feat(godot): own native campaign lifecycle and cut the bridge`.

### Phase 2 — The monthly political economy

**Native means designed for the player, not transcribed from another runtime.**
Every Phase 2 system starts with the experience it must create: a decision has a
legible cost, delayed consequences, and a credible trade-off. Godot owns the
numbers, equations, thresholds and update order. Reference material may explain
Ardenia's institutions and causal relationships, but it cannot prescribe an
equation, a constant, a class layout, or a test expectation.

The monthly pulse exists to answer one question after each meaningful period:
**what changed, who felt it, and what did the government trade to cause it?**
It is deliberately monthly because fiscal capacity, ministry performance,
household confidence and regional conditions should be read as political trends,
not daily noise.

The six simulation domains are budget and public debt, political capital,
ministries, economy, regions, and households. Their redesign specifications
live in `docs/godot/SIM_REDESIGN.md`. Economy and debt are the dependency-first
work: until deficits accumulate into debt and debt has an interest cost, a
budget cannot be a serious political choice.

**Rules for every rebuild in this phase:**

1. State the intended player experience before selecting a formula.
2. Give every retained or newly chosen constant a Godot-side design reason,
   stated beside the system or in its design record.
3. Never copy a formula, numeric constant, update sequence, or test assertion
   merely because it existed elsewhere.
4. Replace tests that assert inherited numbers with tests of intended player
   behaviour, ranges, monotonic directions, boundedness, and save continuity.
   Record every altered test in the task report.
5. Do not weaken or remove an assertion simply to make a build pass.
6. Use play sessions to tune the numbers after the behavioural tests are green.

The existing typed state, save boundary, content JSON, calendar, map and scenes
remain valuable infrastructure. Existing simulation code and its tests are not
to be deleted. They are quarantined as an auditable baseline while each domain
is redesigned deliberately.

#### Phase 2 redesign order

1. **Economy and debt:** deficits add to public debt; debt interest constrains
   future budgets; inflation has political and household costs; unemployment
   tends toward a labour-market floor rather than falling forever.
2. **Budget:** a passed plan funds commitments; failure to pass one produces a
   politically costly emergency settlement rather than an optimal quiet cut.
3. **Ministries:** funding, leadership and overload produce visibly different
   delivery outcomes; a budget change must be felt in implementation.
4. **Political capital:** attention is scarce but never permanently capped out
   by invisible bookkeeping; commitments make governing harder without making
   play inert.
5. **Regions and households:** national choices reach places and groups through
   administration, prices, jobs and state reach, then return as political
   pressure and confidence.
6. **Approval, stability and the digest:** the player sees a causal account of
   material changes, rather than a pile of unexplained stat movement.

A task is complete only after its focused behaviour tests, a save/reload
continuation check, a play session through the relevant decision, and an
independent review. The ledger retains the historical task records; it does not
authorize their inherited equations.
### Phase 3 — Government play

Government play turns the political economy into authorship. The player should
form a governing project: select priorities, fund them, appoint people who can
or cannot deliver them, negotiate through parliament, and live with the social
and regional effects. Each new action is native game design, not a compatibility
exercise.

Every Phase 3 slice must state:

- the decision the player is making and the uncertainty they can understand;
- the lasting political, administrative and economic consequence;
- the information shown before commitment and the explanation shown after it;
- why the system is fun across more than one campaign.

Legislation, cabinet appointments, reforms, parties, coalition cohesion,
elections, regional programmes and campaigning remain in scope. No slice may
reuse inherited vote arithmetic, fixed costs, or outcome thresholds solely
because they were previously implemented. Existing action code remains
uncommitted and untouched until its underlying economic and political design is
reviewed against this standard.

*Playable result:* a player can pursue a distinct governing project, understand
why it is succeeding or failing, and make a different credible strategy on the
next campaign.
### Task 11: Regional programme player-action slice

This is the first player-directed Phase 3 slice, not Phase 3 completion. Reuse
the regional catalogue, political capital, modifiers, monthly pulse, map,
save/load and the existing RegionAction control; do not port legislation,
cabinet appointments, elections, reforms or regional campaigning here.

**Files:**
- Create: `godot/scripts/native/actions/regional_program_actions.gd`
- Modify: `godot/scripts/native/native_game.gd`
- Modify: `godot/scenes/panels/region_brief.tscn`
- Modify: `godot/scripts/app.gd`
- Create: `godot/tests/native/test_regional_program_actions.gd`
- Modify: `godot/tests/native/test_native_game.gd`
- Modify: `godot/scripts/tests/vertical_slice_test.gd`

**Acceptance:** From the Ardenia map, a government player can choose and launch
an authored regional programme, immediately see its political-capital cost and
active commitment, advance time to observe delivered effects, save, reload and
continue the same programme. Opposition, unaffordable, duplicate, inaccessible
and region-incompatible actions are refused atomically by the native engine.
The UI formats detached engine read models and never derives eligibility or
effects.

- [ ] Write failing service tests for deterministic option read models,
      eligibility, atomic rejection, exact-cost success, launch pressure,
      faction loyalty, stable ids and the finite non-institutional treasury
      modifier.
- [ ] Implement one input-free action service; do not duplicate rules in UI.
- [ ] Add `NativeGame.start_regional_program(...)` under the existing busy
      guard: success emits one snapshot, failure emits none, re-entry is refused.
- [ ] Put detached option and active-program read models on each region
      snapshot; load catalogue data once per snapshot rather than once per
      region.
- [ ] Replace the disabled placeholder with an OptionButton, active status and
      the existing 44px action button. Show backend reasons for disabled states.
- [ ] Prove launch -> monthly delivery -> save/load -> continued delivery
      through the public NativeGame API and the real app scene at 1920x1080 and
      1280x720.
- [ ] Run the full native battery, vertical slice and Python smoke suite.
- [ ] Commit `feat(godot): make regional programmes playable`.

### Task 12: Annual budget player-action slice

Make the already-simulated annual appropriations system playable without
building a disposable budget-only vote engine. Add one pure parliamentary
projection kernel for the faction/wing arithmetic shared by budgets now and
legislation later; do not add persistent Law or Legislature models in this
task.

**Files:**
- Create: `godot/scripts/native/sim/parliamentary_vote.gd`
- Create: `godot/scripts/native/actions/budget_actions.gd`
- Create: `godot/scenes/panels/budget_panel.tscn`
- Create: `godot/tests/native/test_budget_actions.gd`
- Modify: `godot/scripts/native/sim/budget_sim.gd`
- Modify: `godot/scripts/native/state/state_validator.gd`
- Modify: `godot/scripts/native/native_game.gd`
- Modify: `godot/scenes/main.tscn`
- Modify: `godot/scripts/app.gd`
- Modify: `godot/tests/native/test_budget_and_pc.gd`
- Modify: `godot/tests/native/test_native_game.gd`
- Modify: `godot/tests/native/test_native_persistence.gd`
- Modify: `godot/scripts/tests/vertical_slice_test.gd`

**Acceptance:** From a fresh government campaign, the player can open a
readable budget panel, adjust all eight authored envelopes only by the
catalogue's allowed values, inspect a non-mutating engine preview of the exact
allocations, total, forecast balance, political-capital cost and parliamentary
projection, table the plan, lobby a real faction, withdraw it or call the vote,
save and reload an approved settlement, then advance to 1 January and see that
same settlement become the active budget used by the existing monthly
simulation. Opposition and every malformed, unaffordable, duplicate or
out-of-sequence request are refused atomically. The UI renders detached read
models and never computes fiscal or voting outcomes.

- [ ] Write failing tests for proposal validation, exact political-capital
      cost, preview non-mutation, deterministic faction/wing projection,
      largest-remainder seat conservation, exact threshold boundaries,
      lobbying cap, withdrawal, passage, defeat and rebellion consequences.
- [ ] Implement a pure motion-based parliamentary vote kernel. It may know
      faction seats, loyalty, ideology, wings, stakes, lobbying and sponsor,
      but must not import or understand `AnnualBudget` or budget envelopes.
- [ ] Implement one input-free budget action service that owns preview,
      proposal, lobbying, vote and withdrawal rules. Reuse `AnnualBudget`,
      `BudgetSim`, the exported budget catalogue and the existing January
      rollover; add no save field or balance/content value.
- [ ] Validate active, pending and historical budgets at the existing state
      validation/load boundary so malformed or non-finite allocations cannot
      enter a live campaign.
- [ ] Add guarded `NativeGame` preview/mutation APIs. Successful mutations emit
      one snapshot; refusals and previews emit none; re-entry is refused.
- [ ] Extend the detached budget snapshot with active/pending/history and all
      authored UI rows, disabled reasons and projection data needed for
      formatting. Seed the active budget before the first player snapshot.
- [ ] Add the data-driven budget panel without a new widget class. Keep 44px
      actions and readable scrolling at 1920x1080 and 1280x720.
- [ ] Prove preview -> proposal -> lobby/withdraw or vote -> save/load ->
      1 January activation through the public NativeGame API and the real app
      scene at both supported resolutions.
- [ ] Run every native `test_*.gd`, the contract runner, vertical slice and
      Python smoke suite.
- [ ] Commit `feat(godot): make annual budgets playable`.

**Deferred:** persistent laws/legislature, general bill UI, repeal and executive
orders, supplementary appropriations, reforms, cabinet, elections, press copy
and Phase 5 visual polish. Those are separate player-action slices.

### Task 13: Native legislation player-action slice

Turn the authored bill catalogue and shared parliamentary projection into a
complete Godot governing loop. This is a native design: Python is not a runtime,
oracle, or parity target. Reuse the typed campaign state, political capital,
factions and wings, modifiers, save/load, and Task 12 vote kernel.

**Files:**
- Create: `godot/scripts/native/state/law.gd`
- Create: `godot/scripts/native/actions/law_actions.gd`
- Create: `godot/scenes/panels/legislation_panel.tscn`
- Create: `godot/tests/native/test_legislative_actions.gd`
- Modify: `godot/scripts/native/state/game_state.gd`
- Modify: `godot/scripts/native/state/state_validator.gd`
- Modify: `godot/scripts/native/sim/parliamentary_vote.gd`
- Modify: `godot/scripts/native/native_game.gd`
- Modify: `godot/scenes/main.tscn`
- Modify: `godot/scripts/app.gd`
- Modify: native persistence/game/journey tests as required

**Acceptance:** A government player can open Legislation, choose any authored
statutory or constitutional bill, inspect its effects and deterministic vote
projection, table it, lobby a real faction, withdraw it or call a vote, and see
an enacted or defeated terminal record. Statutory bills require a simple
majority; constitutional bills require two thirds. Passage applies the authored
direct effects and modifiers exactly once. The pending motion, enacted laws,
history, votes and lobbying survive save/load. Opposition, executive orders,
duplicates, malformed content and out-of-sequence requests are refused
atomically with engine-provided reasons. The real scene remains usable at
1920x1080 and 1280x720. Repeal, amendments and executive-order gameplay remain
later slices.

- [x] Claim the task and write the failing action, persistence, public API and
      real-scene journey checks.
- [x] Add typed Law state and tolerant-but-validating persistence.
- [x] Implement one input-free law action service; reuse ParliamentaryVote.
- [x] Add guarded NativeGame APIs and a detached legislation read model.
- [x] Add a data-driven legislation panel with 44px actions and backend reasons.
- [x] Prove choose -> preview -> propose -> lobby/withdraw or vote -> save/load
      through NativeGame and the real scene at both supported resolutions.
- [x] Run the full native battery, vertical slice and Python smoke suite.
- [x] Commit `feat(godot): make legislation playable`.
### Phase 4 — The living world

Events and situation chains (including the schemer arc and the bespoke Vasca and
Vetrenka arcs), the civil-war gauge, diplomacy verbs and treaties and sanctions,
the eight AI countries with agendas and deliberation, opposition play with the
domestic-AI government, shadow cabinet and pledges, and the press/dispatch/
flavour layer.

*Playable result:* every system the Python game has, present and interacting.

### Phase 5 — The game as a game

1. Every screen as a real Godot scene: campaign setup, dashboard, policies,
   cabinet, parties, diplomacy, briefing, history/codex, settings.
2. **Ministry Wire art direction applied properly** — the F/H–I–J direction
   already chosen, ported from the HTML mockups into a Godot theme resource:
   typography scale, the burgundy/gold palette, rules and dividers, document
   framing. The project window already carries the name.
3. Map rendering rebuilt for Godot rather than transcribed from `QPainter`.
4. Icons, audio, transitions, input feedback, and the small responses that make
   actions feel acknowledged.
5. Keyboard navigation, readable defaults at 1920×1080 and 1280×720, and real
   Windows display-scaling checks.

*Playable result:* it looks and feels like a product, not a prototype.

### Phase 6 — Ship

Export presets, `Ardenia.exe` plus payload, clean-machine verification with
neither Python nor Godot installed, release archive and checksum, versioning,
and the release checklist. Verify by inspection of the archive and the running
process tree that no Python is present.

## Key decisions & tradeoffs

- **Design-port, not parity-port.** Python specifies *what Ardenia contains*;
  Godot decides *how it computes it*. No comparator, no `1e-9` tolerance, no
  dual maintenance. Cost: the two builds will diverge numerically, so the Python
  build cannot be a fallback mid-campaign. Accepted — there are no players with
  saves.
- **Typed GDScript classes over nested dictionaries.** The dictionary mandate
  existed only to serve the comparator. Typed code is both faster (untyped access
  is GDScript's biggest measured cost) and better to build a game on.
- **Keep the existing Godot presentation work.** Map, theme, dashboard scenes,
  menu, and save/load UI were built during the bridge era and survive the
  architecture change; only their data source is replaced.
- **Retire rather than delete** the parity apparatus and superseded phase plans.
  Deletion is irreversible and they are the record of how this was decided.
- **Preserve Codex's uncommitted work** before branching — five modified N0 files
  are committed as-is first. Retiring a direction is not a licence to discard
  another agent's unfinished work silently.
- **Art direction is settled, not re-explored.** Ministry Wire. It is also cheap
  to execute well: a documentary/typographic aesthetic is achievable with type,
  rule, and layout rather than illustration — which matters, because neither
  agent bench has a Godot or art-production skill installed.
- **Python freezes.** No new features. `dist\Ardenia\Ardenia.exe` remains the
  playable build until Godot surpasses it.
- **Continue on `codex/godot-foundation`.** It is the active shared branch for
  this rebuild; do not create a replacement branch.

## Toolchain

Skill inventory scanned both benches (`~/.claude/skills`, `~/.agents/skills`):
near-identical packs, and **no Godot, GDScript, or game-engine skill exists on
either**. Nothing domain-specific to load. Proposed generic skills:

- `test-driven-development` — for simulation systems, where a failing check first
  is genuinely cheaper than debugging a wrong number later.
- `code-review` / `code-review-and-quality` — per-phase independent review.
- `ponytail` — active session-wide; keeps the port from reintroducing
  abstractions the Python build does not have.

Native tests run through the surviving N0 harness:
`godot/tests/native/run_contract_tests.gd` via
`& "D:\AI Stuff\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path godot --script <test>`.

## Assumptions

Confirmed with the user in the Phase 0 ledger:

1. Task is a full remake in Godot; Python is the design reference. — user, this session
2. ~16,090 lines of Python exist as reference (engine 9,693; content+lore 6,297;
   models and `game_state.py`), across 9 country JSONs. — `wc -l`
3. `smoke_test.py` (5,982 lines, 260+ checks) defines current behaviour but does
   not transfer; native tests are written per system. — `wc -l`, CLAUDE.md
4. Native code today is 8 files, all infrastructure; zero simulation ported. — `find`
5. No live agent competes for the worktree: Codex is out of credits, OpenCode is
   a third reserve only. — user, this session
6. No `CONTEXT.md` or `docs/adr/`; `CLAUDE.md`, `AGENTS.md` and
   `docs/EARLY_ACCESS_MISSION.md` carry the project vocabulary. — `ls`
7. `JSON.stringify()` sorts keys by default in Godot 4, so JSON output is stable. — Godot issue #74941

## Risks / open questions

- **Cross-model plan review is unavailable.** claudex-loop Phase 2 requires an
  adversarial review by a different model; Codex has no credits. Parked: the user
  will point Codex at this plan on reset, which serves the same purpose one beat
  later. A Claude subagent review would be an echo chamber and is not a substitute.
- **GDScript throughput on the monthly pulse** — 54 household records (six
  groups across nine authored Ardenian regions),
  9 countries, ministries, budget, and stability every month. Measure during
  Phase 2 with a real profile; mitigate with typed access and hot-path work.
  Fallback is C# for specific systems. Do not pre-optimise.
- **Scope is a whole game.** Phases are individually playable so progress is
  visible and the plan can be stopped or re-scoped at any boundary.
- **Save format will change between phases.** Acceptable while there are no
  players; freeze the format at Phase 5.
- **Balance drifts from the Python build** by design. Phase 3 onward needs real
  playtesting, not comparison.

## Out of scope

Playable foreign countries. Tactical warfare. New reform families, event chains,
or economic variables beyond what Python already implements. Multiplayer,
accounts, telemetry, cloud saves, mod workshop. Recreating the Qt UI
screen-for-screen where a better Godot interaction expresses the same mechanic.
And explicitly: numerical parity with Python, the oracle comparator, and
lockstep bug-fixing across both implementations.

## Verification

Per phase, before it is called done:

1. **Native tests pass** — `run_contract_tests.gd` plus that phase's focused
   tests, headless, exit 0.
2. **The game launches and plays** — `& "D:\AI Stuff\Godot\Godot_v4.7.2-stable_win64_console.exe" --path godot`,
   then actually exercise the phase's new surface by hand.
3. **A campaign survives a round trip** — start, advance, save, quit, relaunch,
   load, and confirm the restored campaign continues coherently.
4. **No Python is reachable** — production scenes load no bridge script and spawn
   no child process. From Phase 1 onward this is a standing check.
5. **Independent review** of the phase diff, with Critical and Important findings
   fixed before the next phase starts.
6. **`.superpowers/sdd/PLAN/progress.md` handoff entry appended** in the
   existing format, so any agent — Claude, Codex, OpenCode, or you — can resume
   cold.

Final acceptance: `Ardenia.exe` runs from an extracted archive on a machine with
neither Python nor Godot installed; new campaign, continue, save, load,
government and opposition play, the monthly pulse, events, a parliamentary vote,
a budget, diplomacy, and an election transition all work; and the process tree
contains no Python.
