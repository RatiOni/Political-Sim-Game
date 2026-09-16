# Native Godot Phase 4 — Opposition, Events, and World Implementation Plan

> **SUPERSEDED 2026-09-16 - read `PLAN.md` at the repository root.**
> The parity-contract programme (`N0`-`N6`, `1e-9` oracle comparison,
> `PARITY_MATRIX.md` as a gate) was cancelled by the project owner. Ardenia is
> being remade in Godot as a game, using the Python source as a design reference
> to read rather than an oracle to match. This document is retained as the
> record of a direction not taken. Do not execute it.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the native political world: opposition play, domestic government, events, crises, diplomacy, other countries, personalities, press, and flavour.

**Architecture:** Port condition/effect callbacks through explicit rule registries, use injected random tapes for branch parity, and keep all authoritative changes inside native simulation/operation modules. Structured news remains the source for press and presentation text.

**Tech Stack:** Godot 4.7.2 GDScript, N3 politics, JSON event/catalog data.

**Spec:** `docs/superpowers/specs/2026-09-16-native-godot-rewrite-design.md`

## Global Constraints

- N3 must be PASS.
- Event defaults are never gated; scheduled follow-ups bypass ordinary trigger gating exactly as Python does.
- World plans and arcs are persisted.
- Opposition choices cannot directly exercise government authority or national effects reserved to office.

---

### Task 1: Opposition and domestic government

**Files:**
- Create: `godot/scripts/native/sim/opposition.gd`
- Create: `godot/scripts/native/sim/domestic_ai.gd`
- Create: `godot/scripts/native/ops/opposition_ops.gd`
- Create: `godot/tests/native/test_opposition.gd`

**Interfaces:**
- Produces daily domestic-government phase and operations for bill response, pledges, campaign, shadow cabinet, confidence vote, and regional campaign.

- [ ] Export fixtures for introduction/response/vote deadlines, support/oppose/amend, pledge add/drop/campaign, shadow appointment, regional campaign, confidence vote, and election victory transition.
- [ ] Write failing state and authority comparisons, including proof that opposition choices affect party/electoral state rather than country policy directly.
- [ ] Port domestic AI timing, opposition operations, and government-transition continuity.
- [ ] Insert the daily domestic-government phase after calendar advancement.
- [ ] Run parity and save/reload tests; commit `feat(godot): port opposition career`.

### Task 2: Dynamic events and authored chains

**Files:**
- Create: `godot/scripts/native/content/event_repository.gd`
- Create: `godot/scripts/native/sim/event_rules.gd`
- Create: `godot/scripts/native/sim/events.gd`
- Create: `godot/scripts/native/ops/event_ops.gd`
- Create: `godot/tests/native/test_events.gd`

**Interfaces:**
- Produces rule registries `CONDITIONS`, `REQUIREMENTS`, and `APPLIERS` keyed by stable ids.
- Produces `Events.check`, `schedule`, `available_options`, `resolve`, and pending-event aging.

- [ ] Export all event metadata with symbolic rule ids and assert every id resolves in the native registries.
- [ ] Write forced-tape fixtures for once/cooldown, follow-ups, default lapse, identity gating, Vasca, Vetrenka, schemer, leadership challenge, and generic events.
- [ ] Port rule callbacks and shared effect bundles; keep event prose in data and behaviour in registries.
- [ ] Port `resolve_event` through OperationRegistry and prove invalid/gated options do not mutate state.
- [ ] Run all event-chain fixtures and commit `feat(godot): port dynamic event system`.

### Task 3: Diplomacy, world simulation, and crisis

**Files:**
- Create: `godot/scripts/native/sim/diplomacy.gd`
- Create: `godot/scripts/native/sim/world_sim.gd`
- Create: `godot/scripts/native/sim/crisis.gd`
- Create: `godot/scripts/native/ops/diplomacy_ops.gd`
- Create: `godot/tests/native/test_world.gd`

**Interfaces:**
- Produces diplomacy operations for relations, trade, loans, condemn, defence pact, sanctions/lift, summit, and treaty exit.
- Produces world `evaluate_interest`, `make_plan`, `execute_plan`, `update_arcs`, and crisis gauges.

- [ ] Export direct fixtures for each diplomatic verb and forced-tape fixtures for each world agenda, pact shelving, plan maturation, sanctions, trade, world arcs, and civil-war latch.
- [ ] Write failing relation symmetry, treaty mirroring, modifier, cost, cooldown, plan persistence, and risk comparisons.
- [ ] Port operations, national-interest scoring, plans, world action effects, crisis bounds, and recurring civil-war effects.
- [ ] Insert world and crisis phases in authoritative monthly positions.
- [ ] Run focused and 120-month boundedness tests; commit `feat(godot): port diplomacy and living world`.

### Task 4: Roleplay, flavour, press, and complete simulation gate

**Files:**
- Create: `godot/scripts/native/sim/roleplay.gd`
- Create: `godot/scripts/native/presentation/flavour.gd`
- Create: `godot/scripts/native/presentation/press.gd`
- Create: `godot/tests/native/test_complete_simulation.gd`
- Modify: `godot/scripts/native/sim/monthly_pulse.gd`

**Interfaces:**
- Produces deterministic local flavour selection independent of simulation RNG.
- Produces structured news and `Press.front_page(before, after) -> Dictionary`.

- [ ] Export fixtures for background ability, address tones, rival tiers, dispatch markers, news ranking, masthead fallback, cabinet restless warning, and schemer escalation.
- [ ] Write failing comparisons proving flavour selection does not consume SimRng and marker keys remain stable.
- [ ] Port roleplay actions, local seeded flavour RNG, structured capture, and press ranking.
- [ ] Complete monthly pulse phases in exact documented order and add a re-entrancy test.
- [ ] Run government and opposition multi-year forced-tape journeys, all N0–N4 native tests, Python smoke, persistence, comparator, and `git diff --check`.
- [ ] Mark N4 PASS after independent review; commit `feat(godot): complete native simulation world`.
