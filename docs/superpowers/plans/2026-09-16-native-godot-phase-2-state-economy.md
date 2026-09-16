# Native Godot Phase 2 — State and Economy Simulation Implementation Plan

> **SUPERSEDED 2026-09-16 - read `PLAN.md` at the repository root.**
> The parity-contract programme (`N0`-`N6`, `1e-9` oracle comparison,
> `PARITY_MATRIX.md` as a gate) was cancelled by the project owner. Ardenia is
> being remade in Godot as a game, using the Python source as a design reference
> to read rather than an oracle to match. This document is retained as the
> record of a direction not taken. Do not execute it.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the complete monthly state-economy core from budgets through household outcomes, stability, and explanations.

**Architecture:** Keep the state-economy segment of the monthly phase order explicit in `monthly_pulse.gd`; each subsystem is a focused stateless script with a single public phase function. N3 and N4 insert the political/event phases around these fixed anchors. Native presenter output is compared to Python oracle fixtures after one and twelve months.

**Tech Stack:** Godot 4.7.2 GDScript, N1 state services, JSON parity fixtures.

**Spec:** `docs/superpowers/specs/2026-09-16-native-godot-rewrite-design.md`

## Global Constraints

- N1 must be PASS.
- Preserve the relative order and exact positions of every N2 phase; N3/N4 fill the remaining documented slots without moving these anchors.
- Economic and household values remain monthly; advancing ordinary days does not invent daily drift.
- Numerical parity tolerance is `1e-9`.

---

### Task 1: Budgets, ministries, and implementation quality

**Files:**
- Create: `godot/scripts/native/sim/budget.gd`
- Create: `godot/scripts/native/sim/ministries.gd`
- Create: `godot/tests/native/test_budget_ministries.gd`

**Interfaces:**
- Produces: `Budget.ensure_state(state)`, `apply_january_rollover(state)`, `fiscal_totals(state) -> Dictionary`.
- Produces: `Ministries.ensure_state(state)`, `update(state)`, `implementation_quality(state, portfolio, institutional) -> float`.

- [ ] Export named oracle fixtures for baseline, January rollover, failed-budget continuation, underfunded ministry, overloaded ministry, and non-institutional modifier.
- [ ] Write native failing comparisons for appropriations, workload, capacity, delivery, backlog, revenue, expenditure, and implementation quality.
- [ ] Port the formulas and caps without UI formatting or duplicated constants.
- [ ] Run focused test plus comparator against every fixture; expect all PASS.
- [ ] Commit `feat(godot): port budgets and ministries`.

### Task 2: Economy, relations, trade, loans, and inflation

**Files:**
- Create: `godot/scripts/native/sim/economy.gd`
- Create: `godot/scripts/native/sim/relations.gd`
- Create: `godot/tests/native/test_economy.gd`

**Interfaces:**
- Produces: `Economy.update(state)`, `apply_modifiers(state)`, `process_loans(state)`.
- Produces: `Relations.update_player_world(state)` and `cap_trade_volume(value) -> float`.

- [ ] Export oracle cases for surplus/deficit inflation, overheating, recession, trade growth, sanctions, loan interest, workforce quality, sector contribution, and GDP compounding.
- [ ] Write failing native comparisons for every affected headline and structural field.
- [ ] Port constants from `engine/turn.py` and relation caps from `models/relations.py` into one constants dictionary loaded by the subsystem; do not scatter copies across scripts.
- [ ] Run cases for 1, 12, and 120 months and assert documented bounds as well as parity.
- [ ] Commit `feat(godot): port economy and bilateral flows`.

### Task 3: Regions and households

**Files:**
- Create: `godot/scripts/native/sim/regions.gd`
- Create: `godot/scripts/native/sim/households.gd`
- Create: `godot/tests/native/test_regions_households.gd`

**Interfaces:**
- Produces: `Regions.update(state)`, `start_program(state, region_id, program_id) -> Dictionary`.
- Produces: `Households.ensure_state(state)`, `update(state)`.

- [ ] Export baseline plus targeted regional-program, high-unemployment, weak-state-reach, high-inflation, service-cut, and opposition-incumbency fixtures.
- [ ] Write failing tests for every region/group id and for nominal income, real income, costs, job security, services, hardship, confidence, pressure, state reach, unemployment, and incumbent support.
- [ ] Port formulas and validate player/government attribution so opposition actions cannot alter national authority incorrectly.
- [ ] Run focused test and compare all named fixtures.
- [ ] Commit `feat(godot): port regional household economy`.

### Task 4: Approval, stability, digest, and monthly orchestrator

**Files:**
- Create: `godot/scripts/native/sim/stability.gd`
- Create: `godot/scripts/native/presentation/digest.gd`
- Create: `godot/scripts/native/sim/monthly_pulse.gd`
- Modify: `godot/scripts/native/native_game.gd`
- Create: `godot/tests/native/test_monthly_core.gd`

**Interfaces:**
- Produces: `Stability.recalculate(state) -> Dictionary`.
- Produces: `Digest.capture_before(state)`, `build(state) -> Array[Dictionary]`.
- Produces: `MonthlyPulse.run_state_core(state) -> void` with named ordered N2 phases; N3/N4 modify this file when their concrete modules exist.

- [ ] Write a failing order test with recording fakes that asserts budget, PC, ministries, economy, relations, loans, regions, households, approval, stability, and modifier aging retain their authoritative relative sequence and documented phase numbers.
- [ ] Write one-month and twelve-month full-state comparisons using deterministic fixtures and exact digest ids/messages.
- [ ] Implement only the re-entrancy guard, before snapshot, concrete N2 subsystem calls, and end-of-pulse aging. Do not add empty phase hooks or placeholder modules.
- [ ] Connect NativeGame month rollover to MonthlyPulse; ordinary day advance remains calendar-only for these systems.
- [ ] Run all N0–N2 tests, Python smoke suite, state comparison, and `git diff --check`.
- [ ] Mark N2 matrix rows PASS, obtain independent review, and commit `feat(godot): complete native monthly state core`.
