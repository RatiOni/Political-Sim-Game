# Ardenia Native Godot Rewrite Implementation Plan

> **SUPERSEDED 2026-09-16 - read `PLAN.md` at the repository root.**
> The parity-contract programme (`N0`-`N6`, `1e-9` oracle comparison,
> `PARITY_MATRIX.md` as a gate) was cancelled by the project owner. Ardenia is
> being remade in Godot as a game, using the Python source as a design reference
> to read rather than an oracle to match. This document is retained as the
> record of a direction not taken. Do not execute it.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the complete Ardenia political simulation as a native Godot 4.7.2 Windows game with no Python runtime and a downloadable executable.

**Architecture:** Preserve the Python implementation as a development oracle while rebuilding the authoritative state, simulation phases, player operations, presentation, persistence, and content runtime in GDScript. Progress through seven dependent parity gates; replace the bridge only after the complete native campaign passes, then export and verify the standalone executable.

**Tech Stack:** Godot 4.7.2, typed GDScript, JSON content, PowerShell packaging, GitHub Actions, existing Python 3.14 oracle scripts during development only.

**Spec:** `docs/superpowers/specs/2026-09-16-native-godot-rewrite-design.md`

## Global Constraints

- Baseline is `codex/godot-foundation` at or after `e4cffca`.
- `docs/EARLY_ACCESS_MISSION.md` remains the product authority.
- Ardenia is the only playable country; all other countries remain active world actors.
- No new mechanics, content expansion, balance changes, or save-schema changes are mixed into parity work.
- Native campaign state has one owner: `NativeGame`; UI code never applies simulation effects.
- Final exported runtime contains no Python, PySide, virtual environment, worker, shell, or repository path.
- Deterministic numeric parity tolerance is `1e-9` unless a parity row records another rule.
- Every phase requires its focused native tests, the Python oracle suite, persistence proof, `git diff --check`, and independent review.
- Do not start a dependent phase while its predecessor gate is `REVISE`.

---

## File structure locked by this programme

```text
godot/scripts/native/native_game.gd                 campaign owner and operation router
godot/scripts/native/content/content_repository.gd  runtime catalog loader
godot/scripts/native/state/                         factory, validation, codec, RNG, saves
godot/scripts/native/sim/                           simulation phase modules
godot/scripts/native/ops/                           player operations and availability
godot/scripts/native/presentation/                  read models, explanations, press
godot/scripts/native/testing/                       dependency-free test support
godot/tests/native/                                 headless native tests
godot/data/native/                                  committed runtime JSON and fixtures
godot/scenes/                                       menus, dashboard, system pages, dialogs
scripts/native_port/                                development exporters and parity probes
docs/godot/native_port/STATUS.md                    append-only agent handoffs
docs/godot/native_port/PARITY_MATRIX.md             mechanic-level acceptance ledger
```

## Programme sequence

| Phase | Plan | Gate |
| --- | --- | --- |
| 0 | `2026-09-16-native-godot-phase-0-contract.md` | N0 |
| 1 | `2026-09-16-native-godot-phase-1-foundation.md` | N1 |
| 2 | `2026-09-16-native-godot-phase-2-state-economy.md` | N2 |
| 3 | `2026-09-16-native-godot-phase-3-government.md` | N3 |
| 4 | `2026-09-16-native-godot-phase-4-world-opposition.md` | N4 |
| 5 | `2026-09-16-native-godot-phase-5-complete-ui.md` | N5 |
| 6 | `2026-09-16-native-godot-phase-6-export-cutover.md` | N6 |

### Task 1: Establish N0

**Files:** Execute the Phase 0 plan.

**Interfaces:** Produces the test harness, frozen oracle fixtures, content manifest, state schema, parity matrix, and status ledger consumed by every later phase.

- [ ] Execute every Phase 0 task in order and obtain an independent gate review.
- [ ] Record `N0: PASS` in `STATUS.md` only when all Phase 0 acceptance commands exit `0`.
- [ ] Commit with `test(godot): establish native rewrite parity contract`.

### Task 2: Establish N1

**Files:** Execute the Phase 1 plan.

**Interfaces:** Consumes N0 fixtures; produces `NativeGame`, native initial state, content loading, calendar, modifiers, RNG, and atomic persistence.

- [ ] Execute every Phase 1 task after N0 passes.
- [ ] Prove the native foundation starts, saves, exits, and reloads with the same canonical state without starting Python.
- [ ] Record `N1: PASS` and commit `feat(godot): add native campaign foundation`.

### Task 3: Establish N2

**Files:** Execute the Phase 2 plan.

**Interfaces:** Consumes N1 state services; produces the complete economy-through-stability monthly core and digest.

- [ ] Execute every Phase 2 task after N1 passes.
- [ ] Compare named one-month, twelve-month, stressed-budget, and overloaded-ministry fixtures.
- [ ] Record `N2: PASS` and commit `feat(godot): port state economy simulation`.

### Task 4: Establish N3

**Files:** Execute the Phase 3 plan.

**Interfaces:** Consumes N2 monthly core; produces government player operations, legislature, reform, cabinet, parties, and elections.

- [ ] Execute every Phase 3 task after N2 passes.
- [ ] Complete a native government journey from programme selection through a law, budget, reform objective, cabinet action, and election.
- [ ] Record `N3: PASS` and commit `feat(godot): port government politics`.

### Task 5: Establish N4

**Files:** Execute the Phase 4 plan.

**Interfaces:** Consumes N3 politics; produces opposition play, domestic AI, events, crisis, diplomacy, world simulation, roleplay, flavour, and press.

- [ ] Execute every Phase 4 task after N3 passes.
- [ ] Complete native government and opposition journeys across an election with forced stochastic tapes.
- [ ] Record `N4: PASS` and commit `feat(godot): complete native political world`.

### Task 6: Establish N5

**Files:** Execute the Phase 5 plan.

**Interfaces:** Consumes the complete native engine; produces every player-facing Godot flow and removes Python bridge use from the production scene tree.

- [ ] Execute every Phase 5 task after N4 passes.
- [ ] Prove all player operations are reachable, authority-gated, keyboard navigable, and explained in headed and headless journeys.
- [ ] Record `N5: PASS` and commit `feat(godot): complete native Ardenia interface`.

### Task 7: Establish N6

**Files:** Execute the Phase 6 plan.

**Interfaces:** Consumes N5 game; produces native save import, export presets, deterministic Windows build, release archive, checksum, and clean-machine evidence.

- [ ] Execute every Phase 6 task after N5 passes.
- [ ] Search the exported archive and running process tree for Python/bridge dependencies; both checks must find none.
- [ ] Record `N6: PASS` and commit `build(godot): ship native Windows executable`.

### Task 8: Cut over the canonical game

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/EARLY_ACCESS_MISSION.md` only to update verified technical baseline
- Create: `docs/godot/native_port/CUTOVER_REPORT.md`

**Interfaces:** Consumes N6; produces the repository’s canonical launch/build/test instructions.

- [ ] Write a failing documentation assertion in `distribution_test.py` requiring the canonical run command to point to the Godot project/export and forbidding `gui.py` as the advertised game entry point.
- [ ] Run `D:\Political Sim Game\.venv\Scripts\python.exe distribution_test.py`; expect that assertion to fail before docs change.
- [ ] Update README and AGENTS with the verified native commands and preserve Python-oracle instructions under a clearly labelled archival section.
- [ ] Write `CUTOVER_REPORT.md` with N0–N6 commits, pass counts, packaged hash, clean-machine environment, known limitations, and rollback commit.
- [ ] Run `distribution_test.py`, all Godot native tests, the packaged journey, and `git diff --check`; expect all to pass.
- [ ] Commit `docs: make native Godot Ardenia canonical`.

## Final acceptance

The programme is complete only when `Ardenia.exe` launches from an extracted archive on Windows without Python or Godot installed; New Campaign, Continue, Save, Load, government and opposition authority, daily time, monthly simulation, events, a parliamentary vote, budget, diplomacy, an election transition, and restart continuity all work; every parity row is PASS or carries an explicitly approved product change; and the final process has no Python child process.
