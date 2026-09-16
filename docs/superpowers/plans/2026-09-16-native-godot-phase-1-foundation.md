# Native Godot Phase 1 — Campaign Foundation Implementation Plan

> **SUPERSEDED 2026-09-16 - read `PLAN.md` at the repository root.**
> The parity-contract programme (`N0`-`N6`, `1e-9` oracle comparison,
> `PARITY_MATRIX.md` as a gate) was cancelled by the project owner. Ardenia is
> being remade in Godot as a game, using the Python source as a design reference
> to read rather than an oracle to match. This document is retained as the
> record of a direction not taken. Do not execute it.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create, advance, save, and reload a native Ardenia campaign foundation without starting Python.

**Architecture:** Load committed content through one repository, construct canonical dictionary state through one factory, validate at trust boundaries, and let the `NativeGame` autoload own state. Calendar, modifiers, serializable RNG, and atomic saves form the base consumed by all simulation phases.

**Tech Stack:** Godot 4.7.2, typed GDScript, JSON, `FileAccess`, `DirAccess`.

**Spec:** `docs/superpowers/specs/2026-09-16-native-godot-rewrite-design.md`

## Global Constraints

- N0 must be PASS.
- Production native scripts may not import or launch `SimulationBridge`.
- State dictionaries include `format_version`, `rng`, and every persisted oracle key.
- Save writes are atomic and remain under `user://saves/`.

---

### Task 1: Content repository and initial campaign factory

**Files:**
- Create: `scripts/native_port/export_native_content.py`
- Create: `godot/scripts/native/content/content_repository.gd`
- Create: `godot/scripts/native/state/game_factory.gd`
- Create: `godot/scripts/native/state/state_validator.gd`
- Create: `godot/data/native/catalog_manifest.json`
- Create: `godot/data/native/countries/*.json`
- Create: `godot/data/native/catalogs/*.json`
- Create: `godot/tests/native/test_initial_state.gd`

**Interfaces:**
- Produces: `ContentRepository.load_all() -> Dictionary`.
- Produces: `GameFactory.new_campaign(config: Dictionary, content: Dictionary) -> Dictionary`.
- Produces: `StateValidator.validate(state: Dictionary) -> PackedStringArray`.
- Produces: development command `export_native_content.py --write` which is the only writer of runtime catalog JSON.

- [ ] Write exporter self-tests requiring every country, bill, budget option, background, difficulty, opening programme, reform objective/instrument/scope, region/programme, household group, trait, event, dispatch, press template, and lore id to appear exactly once. Require an explicit `RULE_ID_MAP` entry for every Python callable; unknown callables fail export instead of becoming anonymous strings.
- [ ] Run `export_native_content.py --self-test`; expect failure before export functions exist.
- [ ] Implement deterministic export to `countries/*.json` and focused `catalogs/*.json`. Serialize behaviour only as stable condition/requirement/applier ids; do not emit Python source or callable representations. Write `catalog_manifest.json` with schema version, source commit, file hashes, id counts, and relative paths.
- [ ] Run `export_native_content.py --write` twice and require no diff after the second run.
- [ ] Write a failing Godot test loading government/opposition seed `424242` and requiring the same top-level keys, ids, dates, faction seats, cabinet ids, region ids, household ids, relations, budgets, ministries, laws, and campaign metadata as the oracle fixtures.
- [ ] Run the Godot test; expect missing-script failure.
- [ ] Implement `ContentRepository` to load only committed runtime JSON from `catalog_manifest.json`, verify hashes/id counts, reject duplicate ids, and return errors rather than partial catalogs.
- [ ] Implement `GameFactory` for Ardenia-only player construction, all eight world actors, bilateral relation wiring, opening role, background, difficulty, ideology, and explicit seed.
- [ ] Implement validation for required keys, id uniqueness, faction-seat total, relation symmetry, ranges, and state version.
- [ ] Run test and the Python comparator against a native emitted initial state; expect exact structural parity and numeric parity.
- [ ] Commit `feat(godot): build native campaign state`.

### Task 2: Serializable RNG, calendar, and modifier lifecycle

**Files:**
- Create: `godot/scripts/native/state/sim_rng.gd`
- Create: `godot/scripts/native/sim/calendar.gd`
- Create: `godot/scripts/native/sim/modifiers.gd`
- Create: `godot/tests/native/test_foundation_mechanics.gd`

**Interfaces:**
- Produces: `SimRng.from_seed(seed: int)`, `next_u32() -> int`, `next_float() -> float`, `choose_index(size: int) -> int`, `to_dict() -> Dictionary`, `from_dict(data: Dictionary)`.
- Produces: `Calendar.advance_day(state) -> bool` where return means month rollover.
- Produces: `Modifiers.current_value(modifier) -> float`, `is_expired(modifier) -> bool`, `age_all(state) -> void`.

- [ ] Write failing tests for leap years, month/year rollover, `day_index`, modifier onset/ramp/hold/decay/expiry, RNG replay after serialization, bounds, and invalid seed/state rejection.
- [ ] Run test; expect missing-script failure.
- [ ] Implement one small integer RNG algorithm using only 64-bit integer state and document its constants in the file; mask after each transition so Windows and Linux produce identical sequences.
- [ ] Port the calendar and modifier formulas exactly, including indefinite hold and phase labels.
- [ ] Run the native tests twice; require byte-identical RNG sequence and all calendar/modifier assertions passing.
- [ ] Commit `feat(godot): add native time modifiers and rng`.

### Task 3: State codec and atomic persistence

**Files:**
- Create: `godot/scripts/native/state/state_codec.gd`
- Create: `godot/scripts/native/state/save_store.gd`
- Create: `godot/tests/native/test_native_persistence.gd`

**Interfaces:**
- Produces: `StateCodec.encode(state) -> String`, `decode(text) -> Dictionary`.
- Produces: `SaveStore.save_slot(slot: String, state: Dictionary) -> Dictionary` and `load_slot(slot: String) -> Dictionary`, each returning `{ok, state|error}`.

- [ ] Write failing tests for exact round-trip, corrupt JSON, unsupported version, traversal slots, interrupted-write preservation, RNG state continuity, and a save that includes every oracle top-level key.
- [ ] Run test; expect missing-script failure.
- [ ] Implement canonical serialization, validator call on decode, safe slot regex `^[a-z0-9_-]{1,48}$`, `.tmp` write, flush, and atomic replace with `.bak` recovery.
- [ ] Run tests under an isolated `--user-data-dir`; require no writes to repository `saves/`.
- [ ] Commit `feat(godot): add native campaign persistence`.

### Task 4: NativeGame state owner

**Files:**
- Create: `godot/scripts/native/native_game.gd`
- Modify: `godot/project.godot`
- Create: `godot/tests/native/test_native_game.gd`

**Interfaces:**
- Produces signals `state_changed(snapshot: Dictionary)`, `operation_completed(result: Dictionary)`, `fatal_error(message: String)`.
- Produces methods `new_campaign(config)`, `execute(operation_id, args)`, `advance_day()`, `save(slot)`, `load(slot)`, `snapshot()`.

- [ ] Write a test that injects fixture content, starts seed `424242`, advances one day, saves, replaces memory with a second campaign, loads, and asserts full restoration.
- [ ] Run test; expect NativeGame autoload missing.
- [ ] Implement NativeGame with one private `_state`, one in-flight operation guard, validator after state replacement, and read-only deep-duplicated snapshots.
- [ ] Register `NativeGame` as a development autoload alongside the existing bridge; do not route production scenes to it in Phase 1.
- [ ] Run all N0/N1 tests and prove no test starts a Python child process.
- [ ] Mark N1 parity rows PASS, obtain independent review, and commit `feat(godot): own native campaign lifecycle`.
