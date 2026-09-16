# Native Godot Phase 3 — Government Politics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a native government campaign fully playable through programmes, reform objectives, parliament, budgets, cabinet management, parties, and elections.

**Architecture:** Port `engine/player_ops.py` as the sole native action boundary. Availability, costs, and effects live in operation modules; scenes consume an operation catalog and never mutate state. Legislative, party, cabinet, reform, and election engines join the monthly orchestrator only after direct parity passes.

**Tech Stack:** Godot 4.7.2 GDScript, N2 state core, JSON content registries.

**Spec:** `docs/superpowers/specs/2026-09-16-native-godot-rewrite-design.md`

## Global Constraints

- N2 must be PASS.
- Every public Python `op_*` receives a stable native operation id or an explicit N4 assignment.
- Government authority checks occur in operations, not only in UI visibility.
- Deterministic elections, turnout, stability, and voting remain non-random.

---

### Task 1: Operation registry and reform/programme actions

**Files:**
- Create: `godot/scripts/native/ops/operation_registry.gd`
- Create: `godot/scripts/native/ops/reform_ops.gd`
- Create: `godot/scripts/native/sim/reforms.gd`
- Create: `godot/scripts/native/sim/opening_programme.gd`
- Modify: `godot/scripts/native/native_game.gd`
- Create: `godot/tests/native/test_reform_ops.gd`

**Interfaces:**
- Produces: `OperationRegistry.describe(state) -> Array[Dictionary]` and `execute(state, operation_id, args) -> Dictionary`.
- Operation result shape: `{ok: bool, message: String, code: String, changed: bool, cost: float}`.

- [ ] Export availability/result/state fixtures for opening programme, adopting reform objective, starting regional programme, attention exhaustion, insufficient capital, wrong role, unknown id, and duplicate action.
- [ ] Write failing tests proving invalid calls do not mutate canonical state.
- [ ] Implement exact argument allow-lists, authority gates, PC/attention costs, cooldowns, and result codes.
- [ ] Route NativeGame.execute through the registry and emit a new snapshot only when `changed` is true.
- [ ] Run parity comparisons and commit `feat(godot): port programmes and reform operations`.

### Task 2: Legislature, laws, wings, and party dynamics

**Files:**
- Create: `godot/scripts/native/sim/legislature.gd`
- Create: `godot/scripts/native/sim/parties.gd`
- Create: `godot/scripts/native/ops/legislative_ops.gd`
- Create: `godot/tests/native/test_legislature.gd`

**Interfaces:**
- Produces: `Legislature.vote_projection`, `wing_votes`, `resolve_vote`, `apply_effect_bundle`, `activate_law_modifiers`.
- Produces operations `propose_bill`, `lobby_faction`, `call_vote`, `withdraw_bill`, `repeal_law`.

- [ ] Export every bill catalog entry and direct fixtures for loyal/rebellious wings, coalition/no-majority, passed/failed vote, repeal, modifier activation, and loyalty effects.
- [ ] Write failing exact seat/vote/effect comparisons and assert every content faction/role id resolves.
- [ ] Port role resolution, largest-remainder wing allocation, salience, rebellions, and shared effect pipeline.
- [ ] Port government legislative operations through OperationRegistry.
- [ ] Run focused tests and commit `feat(godot): port parliament and party wings`.

### Task 3: Annual budget operations and cabinet

**Files:**
- Create: `godot/scripts/native/ops/budget_ops.gd`
- Create: `godot/scripts/native/sim/cabinet.gd`
- Create: `godot/scripts/native/ops/cabinet_ops.gd`
- Create: `godot/tests/native/test_budget_cabinet_ops.gd`

**Interfaces:**
- Produces budget operations `propose_budget`, `lobby_budget`, `call_budget_vote`, `withdraw_budget`, `supplementary_appropriation`.
- Produces cabinet operations `appoint_minister`, `reshuffle`, `dismiss`, `ministry_report`.

- [ ] Export proposal, vote, continuing settlement, supplementary, shortlist, appointment, dismissal, trait, representation, loyalty, and threat fixtures.
- [ ] Write failing tests for costs, authority, fiscal balance, portfolio validation, trait effects, cabinet representation, and no-mutation failures.
- [ ] Port operations and cabinet update formulas, keeping shortlist/name generation behind injected RNG.
- [ ] Run direct and persistence comparisons; commit `feat(godot): port budgets and cabinet politics`.

### Task 4: Elections and government journey gate

**Files:**
- Create: `godot/scripts/native/sim/elections.gd`
- Create: `godot/tests/native/test_elections.gd`
- Create: `godot/tests/native/test_government_journey.gd`
- Modify: `godot/scripts/native/sim/monthly_pulse.gd`

**Interfaces:**
- Produces: `Elections.calculate_turnout`, `allocate_seats`, `run_election`, `apply_transition`.
- Consumes: complete N3 operation registry and monthly core.

- [ ] Export turnout/seat fixtures for every difficulty, support boundary, coalition threshold, scheduled election, snap election, government win, and government loss.
- [ ] Write failing deterministic comparisons including seat total and government/opposition transition.
- [ ] Port election formulas and insert party drift/election phases at their authoritative monthly positions.
- [ ] Write a journey that selects programme, objective, proposes/lobbies/passes a law, proposes/passes a budget, appoints a minister, advances to election, and round-trips the result.
- [ ] Run N0–N3 native suites, Python smoke, comparator, and `git diff --check`.
- [ ] Mark N3 PASS after independent review; commit `feat(godot): complete native government campaign`.
