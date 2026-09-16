# Native Godot Phase 0 — Contract and Oracle Implementation Plan

> **SUPERSEDED 2026-09-16 - read `PLAN.md` at the repository root.**
> The parity-contract programme (`N0`-`N6`, `1e-9` oracle comparison,
> `PARITY_MATRIX.md` as a gate) was cancelled by the project owner. Ardenia is
> being remade in Godot as a game, using the Python source as a design reference
> to read rather than an oracle to match. This document is retained as the
> record of a direction not taken. Do not execute it.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a reproducible contract that lets native GDScript mechanics be compared against the complete Python game without shipping Python.

**Architecture:** Export immutable oracle states and content manifests from Python, then consume them through a dependency-free Godot headless test harness. Track each mechanic in a parity matrix and every accepted task in an append-only status ledger.

**Tech Stack:** Python 3.14 development scripts, Godot 4.7.2 headless GDScript, JSON, Markdown.

**Spec:** `docs/superpowers/specs/2026-09-16-native-godot-rewrite-design.md`

## Global Constraints

- Python is an oracle only; no Phase 0 script is reachable from exported Godot scenes.
- Generated fixtures use sorted keys, UTF-8, `\n`, and stable explicit seeds.
- Fixtures contain no absolute paths, machine names, or timestamps.
- Existing Python tests and current Godot vertical-slice tests must keep passing.

---

### Task 1: Create the native test runner and ledgers

**Files:**
- Create: `godot/scripts/native/testing/test_support.gd`
- Create: `godot/tests/native/run_contract_tests.gd`
- Create: `docs/godot/native_port/STATUS.md`
- Create: `docs/godot/native_port/PARITY_MATRIX.md`

**Interfaces:**
- Produces: `TestSupport.equal(actual, expected, label)`, `near(actual, expected, tolerance, label)`, `truth(value, label)`, and `finish() -> int`.
- Produces: executable command `godot --headless --path godot --script res://tests/native/run_contract_tests.gd`.

- [ ] Write `run_contract_tests.gd` so it loads `TestSupport`, deliberately compares `1` to `2`, and exits non-zero through `quit(t.finish())`.
- [ ] Run Godot headless and verify exit code `1` with one labelled failure.
- [ ] Implement `TestSupport` with counters and stable `PASS`/`FAIL` lines:

```gdscript
class_name TestSupport
extends RefCounted

var passed := 0
var failed := 0

func equal(actual: Variant, expected: Variant, label: String) -> void:
    if actual == expected:
        passed += 1
        print("PASS  ", label)
    else:
        failed += 1
        push_error("FAIL  %s\n  expected=%s\n  actual=%s" % [label, expected, actual])

func near(actual: float, expected: float, tolerance: float, label: String) -> void:
    truth(absf(actual - expected) <= tolerance, label)

func truth(value: bool, label: String) -> void:
    equal(value, true, label)

func finish() -> int:
    print("NATIVE TESTS: %d passed, %d failed" % [passed, failed])
    return 0 if failed == 0 else 1
```

- [ ] Replace the deliberate failure with assertions that the support methods pass; run headless and verify exit `0`.
- [ ] Create `PARITY_MATRIX.md` with one row for every `engine/*.py`, `models/*.py`, `content/*.py`, and each public `op_*` function. Columns: id, Python source, native target, proof type, fixture/test, state.
- [ ] Create `STATUS.md` with baseline commit, protected dirty-root note, Godot/Python versions, N0 active, and the handoff template from `NATIVE_REWRITE_AGENT_GUIDE.md`.
- [ ] Commit `test(godot): add native parity test harness`.

### Task 2: Export canonical content and state fixtures

**Files:**
- Create: `scripts/native_port/export_oracle_fixtures.py`
- Create: `godot/data/native/fixtures/manifest.json`
- Create: `godot/data/native/fixtures/campaign_government_seed_424242.json`
- Create: `godot/data/native/fixtures/campaign_opposition_seed_424242.json`
- Modify: `godot/tests/native/run_contract_tests.gd`

**Interfaces:**
- Produces: `export_fixture(path: Path, value: dict) -> None` with sorted canonical JSON.
- Produces: manifest keys `schema_version`, `source_commit`, `catalogs`, `operations`, `monthly_phases`, `fixtures`.

- [ ] Add a Python test function inside the exporter that writes the same dictionary twice and asserts byte equality, no absolute repository path, and trailing newline.
- [ ] Run `D:\Political Sim Game\.venv\Scripts\python.exe scripts\native_port\export_oracle_fixtures.py --self-test`; expect failure because exporter functions do not exist.
- [ ] Implement the exporter using `campaign.generate_campaign`, explicit `CampaignConfig(seed=424242, opening_role=...)`, `persistence.serialize_state`, catalog functions, `inspect` for public operation names, and `TurnEngine` phase names copied from its authoritative docstring.
- [ ] Export both opening roles and a manifest. Store numeric values without string formatting and omit ephemeral `turn_log`/`turn_news` only when the manifest explicitly labels them non-persistent.
- [ ] Run exporter twice and verify `git diff --exit-code -- godot/data/native/fixtures` after the second run.
- [ ] Add GDScript assertions that both fixtures parse, carry distinct `in_government` values, share seed `424242`, and contain every manifest top-level state key.
- [ ] Run contract tests and Python `smoke_test.py`; expect both to pass.
- [ ] Commit `test(godot): freeze native rewrite oracle fixtures`.

### Task 3: Add the cross-runtime comparison probe

**Files:**
- Create: `scripts/native_port/compare_native_snapshot.py`
- Create: `godot/tests/native/emit_fixture_snapshot.gd`
- Modify: `docs/godot/native_port/PARITY_MATRIX.md`

**Interfaces:**
- Consumes: one oracle fixture path and one native output path.
- Produces: exit `0` only when paths, scalar types, strings, ids, arrays, and numeric values satisfy the parity contract.

- [ ] Write self-tests with one exact pass, one missing-key failure, one string mismatch, and numeric values inside/outside `1e-9`.
- [ ] Run `compare_native_snapshot.py --self-test`; expect failure until recursive comparison exists.
- [ ] Implement a recursive comparator that reports JSON paths such as `$.country.economy.gdp`, never stops at the first mismatch, and supports only the documented numeric tolerance.
- [ ] Make `emit_fixture_snapshot.gd` load and re-emit the government fixture with sorted JSON through a path passed after `--`.
- [ ] Run emitter then comparator against the source fixture; expect exit `0`.
- [ ] Change one emitted field in a temporary copy and verify comparator exits `1` with the exact JSON path.
- [ ] Mark the N0 contract rows PASS, run bridge, smoke, vertical-slice, and contract suites, and obtain independent review.
- [ ] Commit `test(godot): add cross-runtime parity probe`.
