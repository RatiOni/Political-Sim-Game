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

### Phase 2 — The monthly simulation

Port the monthly pulse as game systems, in the phase order `engine/turn.py`
documents (order is load-bearing — later phases read earlier same-turn results):
economy (growth, inflation, unemployment, debt, revenue/expenditure), annual
appropriations, ministry capacity/workload/delivery/backlog, regional
conditions, the 54 household records (six groups across nine authored Ardenian
regions), then approval and stability. Plus the
political-capital economy and governing overhead, and the monthly digest.

*Playable result:* time means something. The map's pressure colours move for real
reasons; the monthly report explains why.

#### Phase 2 tasks

Decomposed for subagent dispatch, following `engine/turn.py: TurnEngine._run_monthly_pulse`'s
documented call order (its own docstring numbers all 23 phases — order is
load-bearing because later phases read earlier same-turn results). Phase 2
implements this subset, in this order:

```
budget.process_fiscal_year        (Task 5)
_regenerate_political_capital     (Task 5)
ministries.simulate_ministries    (Task 6)
_update_economy (+6 sub-phases)   (Task 7)
regions.simulate_regions          (Task 8)
households.simulate_households    (Task 9)
_update_approval                  (Task 10)
_update_stability                 (Task 10)
```

Numbered globally, continuing from Phase 1's Tasks 1-4 (the `task-brief`
tooling matches `### Task N` by number across the whole plan file, not
per-phase — task numbers must be unique file-wide).

Everything else in `_run_monthly_pulse` (domestic-government/opposition
simulation, world relations and worldsim, loans, faction loyalty and
grievances, minister/cabinet updates, protests, confidence votes, civil war,
faction support, elections, law tracking, events, rival watch) is later-phase
territory (Phase 3/4) and stays out of scope here — do not implement it early
just because it's in the same Python method.

**Testing pattern, same as Phase 1:** each of Tasks 5-9 builds and unit-tests
one subsystem function against a constructed `GameState`, called directly —
not yet wired into `NativeGame`'s monthly pulse. **Task 10 does the
integration**: it adds approval/stability, then wires all of Tasks 5-9's
functions plus its own into `NativeGame`'s monthly-rollover path in the exact
order above (currently that path only calls `Modifiers.age_all()`, from
Phase 1 Task 4), and proves the whole chain with an end-to-end test that
advances a real campaign through a month boundary and checks fields from
every subsystem moved. This mirrors how Phase 1 Task 4 was the integration
point for Phase 1's Tasks 1-3.

### Task 5: Annual budget and political capital

**Files:**
- Create: `godot/scripts/native/sim/budget_sim.gd`
- Create: `godot/scripts/native/sim/political_capital.gd`
- Create: `godot/tests/native/test_budget_and_pc.gd`

**Interfaces:**
- Produces: `BudgetSim.process_fiscal_year(state: GameState) -> void` — applies
  a pending/continuing budget at January rollover into `state.active_budget`.
- Produces: `PoliticalCapital.regenerate(state: GameState) -> void` and
  `PoliticalCapital.upkeep(state: GameState) -> Dictionary` (breakdown by
  source, mirroring `political_upkeep()`'s return shape).

**Read first:** `engine/budget.py` (`process_fiscal_year`, and how a fresh
campaign seeds its first `AnnualBudget` from `Economy.structural_expenditure`
— native campaigns have no `active_budget` yet per Phase 1 Task 2's documented
scope, so this task's first job is seeding one, not just processing rollover),
`turn.py: political_upkeep()` and `_regenerate_political_capital`.

**Note:** native `Country`/`GameState` has no `Legislature`/laws/treaties
class yet (Phase 3 territory) — read `country.gd` to see what relation/treaty
data, if any, already exists on the ported `Country`/relation classes, and
adapt `upkeep()`'s law/treaty/sanction counts to whatever is genuinely present
today (likely just sanctions, since `BilateralRelation.sanctioned` is exactly
the kind of per-relation flag Phase 1 would have ported). Do not invent a
Legislature class to make this task's parity look more complete — an upkeep
total that's currently law-free because no laws exist yet is correct, not a
gap.

- [ ] Write failing tests: a fresh campaign gets a seeded budget on its first
      January if none exists; an approved `pending_budget` becomes
      `active_budget` at January rollover; a government with no plan passed by
      January gets the continuing-budget reduction; PC upkeep sums correctly
      from whatever commitment data natively exists; PC regen respects
      `PC_REGEN_FLOOR`.
- [ ] Run test; expect missing-script failure.
- [ ] Implement `BudgetSim` and `PoliticalCapital` as a design-reference port
      of the Python logic above.
- [ ] Run test; all assertions pass.
- [ ] Commit `feat(godot): add native budget rollover and political capital`.

### Task 6: Ministry capacity, workload, delivery, backlog

**Files:**
- Create: `godot/scripts/native/sim/ministries_sim.gd`
- Create: `godot/tests/native/test_ministries_sim.gd`

**Interfaces:**
- Produces: `MinistriesSim.simulate(state: GameState) -> void` — recalculates
  every `MinistryState` in `state.ministries` (populated for the first time by
  this task; Phase 1 left it an empty dict per `game_factory.gd`'s documented
  scope).

**Read first:** `engine/ministries.py` (capacity/workload/delivery/backlog
formulas), `CLAUDE.md`'s "Ministry capacity and delivery" section (workload
sources, the backlog-doesn't-clear-overnight design intent), `models/ministry.py`
(already ported as `ministry_state.gd` in Phase 1 — read it for the exact
field names you're computing into).

- [ ] Write failing tests: a ministry's capacity responds to funding ratio,
      minister competence/loyalty (if a minister is assigned to that
      portfolio — Phase 1's ministers may be stale/unassigned per the parked
      opposition-cabinet finding; handle a missing/mismatched minister
      gracefully, don't crash), bureaucratic capacity, and stability; workload
      accumulates from whatever sources natively exist today (active laws:
      none yet, so 0 — same reasoning as Task 5; regional pressure and civil
      war ARE native today via Phase 1's typed classes); backlog only clears
      with spare capacity, never instantly; `months_overloaded` increments
      correctly.
- [ ] Run test; expect missing-script failure.
- [ ] Seed every `CORE_PORTFOLIO` ministry into `state.ministries` on
      campaign creation if not already done — check whether Phase 1's
      `GameFactory` already creates empty entries; if not, this task owns that
      seeding too (read `game_factory.gd`'s header note to confirm the exact
      boundary).
- [ ] Implement `MinistriesSim.simulate()` as a design-reference port.
- [ ] Run test; all assertions pass.
- [ ] Commit `feat(godot): add native ministry capacity and delivery`.

### Task 7: The monthly economy

**Files:**
- Create: `godot/scripts/native/sim/economy_sim.gd`
- Create: `godot/tests/native/test_economy_sim.gd`

**Interfaces:**
- Produces: `EconomySim.update(state: GameState) -> void` — the full
  `_update_economy` chain: workforce quality, bureaucratic capacity, sectors,
  structural fiscal baseline, organic inflation, applying modifiers to
  headline stats, then compounding GDP.

**Read first:** `engine/turn.py`'s six `_update_*`/`_compound_gdp` private
methods this task ports (`_update_workforce_quality`,
`_update_bureaucratic_capacity`, `_update_sectors`,
`_update_structural_fiscal_baseline`, `_update_structural_inflation`,
`_apply_modifiers_to_headline_stats`, `_compound_gdp`), `CLAUDE.md`'s "Organic
inflation" and "The PC economy" sections, `models/economy.py` (`economy.gd`
from Phase 1 — read for exact field names). This is the largest single
formula surface in Phase 2; read it once, fully, before writing any test.

- [ ] Write failing tests: workforce quality and bureaucratic capacity respond
      to their documented inputs; sector `gdp_share`/`growth_rate` evolve
      plausibly (not fixed); structural fiscal baseline reflects
      `active_budget`'s size and composition once Task 5 exists (if Task 5
      isn't complete when this task starts per the ledger, coordinate — this
      task consumes Task 5's `active_budget`); inflation drifts toward
      `INFLATION_ANCHOR`, pushed by deficit and overheating, bounded by
      `STRUCTURAL_INFLATION_MAX`; active modifiers apply to growth/
      unemployment/inflation/debt exactly once per pulse (no double-application
      across a save/reload); GDP compounds from growth correctly over several
      months.
- [ ] Run test; expect missing-script failure.
- [ ] Implement `EconomySim.update()` as a design-reference port of the six
      sub-phases, in order.
- [ ] Run test; all assertions pass.
- [ ] Commit `feat(godot): add native monthly economy simulation`.

### Task 8: Regional conditions

**Files:**
- Create: `godot/scripts/native/sim/regions_sim.gd`
- Create: `godot/tests/native/test_regions_sim.gd`

**Interfaces:**
- Produces: `RegionsSim.simulate(state: GameState) -> void` — updates every
  `RegionState` in `state.regions` from national economy, bureaucratic
  capacity, and stability; applies one month of delivery to any active
  `RegionalProgram`, removing it on completion.

**Read first:** `engine/regions.py: simulate_regions` and
`program_delivery_quality`, `CLAUDE.md`'s "Regional simulation" section
(control doesn't flip passively; separatist territory inaccessible;
population-weighted pressure feeds unrest modestly), `content/regions.py`
(authored starting profiles — already exported as JSON by Phase 1 Task 1 under
`godot/data/native/catalogs/regions_and_programs.json`; `game_factory.gd`
does not yet seed `state.regions` from it, so this task likely owns that
seeding too — check the factory's header note).

- [ ] Write failing tests: Ardenia's nine authored regions seed correctly (or
      confirm they already do, if Task 2's factory work turned out to cover
      it) with their authored unemployment/state-reach/pressure/control/issue
      values; a country with no authored regional data (all eight others)
      keeps an empty `state.regions` for that country and doesn't crash;
      regional unemployment/pressure respond to national conditions;
      separatist-controlled territory stays inaccessible to programmes; an
      active `RegionalProgram` advances one month and completes/removes
      itself on its authored duration.
- [ ] Carry forward to Task 10: a separatist programme freeze must preserve
      the programme's intended delivery window. Prefer extending the relevant
      modifier delivery window during each frozen month; the only alternative is a
      deliberately accepted, documented delivery slip. Add a focused test for
      the chosen behaviour.
- [ ] Run test; expect missing-script failure.
- [ ] Implement `RegionsSim.simulate()` as a design-reference port.
- [ ] Run test; all assertions pass.
- [ ] Commit `feat(godot): add native regional simulation`.

### Task 9: The household economy

**Files:**
- Create: `godot/scripts/native/sim/households_sim.gd`
- Create: `godot/tests/native/test_households_sim.gd`

**Interfaces:**
- Produces: `HouseholdsSim.simulate(state: GameState) -> void` — updates every
  `HouseholdGroupState` in `state.households` (nominal income, living costs,
  real income, employment security, service access, hardship, confidence),
  run after `RegionsSim` and before approval/stability, per the documented
  monthly order.

**Read first:** `engine/households.py: simulate_households`, `CLAUDE.md`'s
"The household economy" section (54 records = 6 groups × 9 authored Ardenian regions;
national figures are population-weighted aggregates, not a second economy;
countries without authored data keep an empty ledger), `content/households.py`
(already exported by Phase 1 Task 1 under
`godot/data/native/catalogs/household_groups.json`; likely needs seeding into
`state.households` by this task, same pattern as Task 8's regions).

- [ ] Write failing tests: Ardenia's 54 household records (six groups across
      nine authored Ardenian regions) seed correctly;
      inflation/growth/local unemployment/state reach move
      income/security/hardship/confidence in the documented directions; a
      country with no authored household data keeps an empty
      `state.households`; national aggregates are population-weighted, not a
      flat average.
- [ ] Run test; expect missing-script failure.
- [ ] Implement `HouseholdsSim.simulate()` as a design-reference port.
- [ ] Run test; all assertions pass.
- [ ] Commit `feat(godot): add native household economy simulation`.

### Task 10: Approval, stability, the monthly digest, and full pulse integration

**Files:**
- Create: `godot/scripts/native/sim/stability_sim.gd`
- Create: `godot/scripts/native/presentation/monthly_digest.gd`
- Modify: `godot/scripts/native/native_game.gd` (wire the full monthly-pulse
  call order into the rollover path)
- Modify: `godot/scripts/native/sim/regions_sim.gd` (preserve a frozen
  programme's finite treasury-modifier delivery window while normal modifier
  ageing continues)
- Modify: `godot/scripts/native/state/game_state.gd` (persist the completed
  `monthly_digest: Array[String]` with an empty default for older saves)
- Create: `godot/tests/native/test_stability_and_digest.gd`
- Create: `godot/tests/native/test_monthly_pulse_integration.gd`
- Modify: `godot/tests/native/test_native_persistence.gd` (round-trip and
  malformed-input coverage for the persisted monthly digest)

**Interfaces:**
- Produces: `StabilitySim.update_approval(state: GameState) -> void`,
  `StabilitySim.update_stability(state: GameState) -> void`.
- Produces: `MonthlyDigest.build(state: GameState, before: Dictionary) -> Array[String]`
  — the snapshot digest array for the dashboard's monthly report, replacing
  the bridge-era stub (`digest: []` in `native_game.gd`'s snapshot). The UI
  formats these strings only; it does not derive simulation state.
- Persists: the completed `GameState.monthly_digest: Array[String]`, so the
  report survives save/load without replaying simulation or digest formulas.
  Missing data in older saves loads as an empty report; malformed present data
  is rejected by the normal persistence boundary.
- Modifies: `NativeGame`'s monthly-rollover handler to call, in order:
  `BudgetSim.process_fiscal_year` → `PoliticalCapital.regenerate` →
  `MinistriesSim.simulate` → `EconomySim.update` → `RegionsSim.simulate` →
  `HouseholdsSim.simulate` → `StabilitySim.update_approval` →
  `StabilitySim.update_stability` → (existing) `Modifiers.age_all`.
- Modifies: `NativeGame.snapshot()` to expose read-only budget, ministry, and
  national household-summary data for the UI surfaces already backed by this
  phase. The UI formats those snapshot fields only; it must not recompute them.

**Read first:** `engine/turn.py: _update_approval`, `_update_stability`,
`engine/stability.py` (shared signal functions — CLAUDE.md: "Elections,
turnout, stability, civil-war risk are never rolled — they're deterministic
functions of tracked state"), `engine/digest.py` (`snapshot()` — already
called by `_run_monthly_pulse` for the before/after digest), the current
`godot/scripts/native/native_game.gd` monthly-rollover method you're
extending.

- [ ] Write failing tests for `StabilitySim`: approval and government
      stability respond to economy/household/regional signals in the
      documented directions; both stay bounded (never leave their valid
      range regardless of extreme inputs). Implement from existing native
      state directly — faction seats, coalition membership, loyalty and
      cohesion, ministers, economy, regions, and households — without
      inventing a `Legislature` or `Cabinet` class before Phase 3. Keep the
      outputs deterministic and bounded.
- [ ] Write a failing end-to-end test in `test_monthly_pulse_integration.gd`:
      construct a real Ardenia campaign via `GameFactory`, advance it through
      a full month via `NativeGame`, and assert that budget, ministries,
      economy, regions, households, approval, and stability all show
      evidence of having actually run (not just that the date advanced) —
      this is the test that proves Tasks 5-10 are genuinely wired together in
      the right order, not just individually correct in isolation.
- [ ] Run tests; expect missing-script/assertion failures.
- [ ] Implement `StabilitySim` and `MonthlyDigest` as design-reference ports.
- [ ] Wire the full call order into `native_game.gd`'s rollover path, in the
      exact sequence given above.
- [ ] Persist completed digest lines through `GameState.to_dict()` / `from_dict()`
      and prove a saved-and-reloaded campaign retains them without running a
      second monthly pulse.
- [ ] Update the dashboard's `digest` snapshot field to use `MonthlyDigest.build()`
      instead of the empty stub, so the monthly report on screen shows real
      content.
- [ ] Expose the read-only budget, ministry, and national household-summary
      snapshot fields used by Phase 2 UI surfaces, and test that the UI-facing
      snapshot is sufficient for formatting without any UI-side derivation.
- [ ] Resolve the Task 8 separatist-programme-freeze carry-forward: preferably
      extend the relevant modifier delivery window during every frozen month; if
      accepting a delivery slip instead, document that ruling explicitly. Test
      the selected behaviour.
- [ ] Run all Phase 2 tests plus the full Phase 1 regression suite
      (`test_content_repository.gd`, `test_game_factory.gd`,
      `test_foundation_mechanics.gd`, `test_native_persistence.gd`,
      `test_native_game.gd`, `run_contract_tests.gd`,
      `godot/scripts/tests/vertical_slice_test.gd`); all must pass.
- [ ] Manually launch the game and play through several months: confirm the
      map's regional pressure colours change, the monthly report shows real
      content, and nothing crashes across a save/reload mid-campaign.
- [ ] Commit `feat(godot): wire the full native monthly simulation`.

### Phase 3 — Government play

Legislation (bill catalogue, parliamentary arithmetic, bloc/wing votes and
rebellions), reform objectives, cabinet (ministers, traits, shortlists,
appointment), parties and coalition cohesion, elections and deterministic
turnout, regional programmes and regional campaigning.

*Playable result:* you can actually govern — pass a law, appoint a minister,
run a budget, fight an election.

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
