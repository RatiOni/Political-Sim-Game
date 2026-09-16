# Native Godot Phase 5 — Complete Player Interface Implementation Plan

> **SUPERSEDED 2026-09-16 - read `PLAN.md` at the repository root.**
> The parity-contract programme (`N0`-`N6`, `1e-9` oracle comparison,
> `PARITY_MATRIX.md` as a gate) was cancelled by the project owner. Ardenia is
> being remade in Godot as a game, using the Python source as a design reference
> to read rather than an oracle to match. This document is retained as the
> record of a direction not taken. Do not execute it.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every playable PySide surface with a coherent Godot interface driven exclusively by `NativeGame`.

**Architecture:** Keep the current national dashboard as the shell, add a campaign wizard and focused system pages, and use reusable operation-list, detail, explanation, and confirmation components. Pages render presenter read models and submit operation ids; modal interruption is reserved for material decisions.

**Tech Stack:** Godot 4.7.2 Control scenes, typed GDScript, native presenters, existing Ardenia theme and map.

**Spec:** `docs/superpowers/specs/2026-09-16-native-godot-rewrite-design.md`

## Global Constraints

- N4 must be PASS.
- Minimum supported viewport is 1280×720; primary controls are at least 44 px.
- Keyboard navigation, focus visibility, text scaling, and colour-independent status cues are required.
- No scene imports `SimulationBridge` or derives game effects.
- Each Python action/page is mapped in the parity matrix before N5 can pass.

---

### Task 1: Campaign setup and navigation shell

**Files:**
- Create: `godot/scenes/campaign_wizard.tscn`
- Create: `godot/scripts/ui/campaign_wizard.gd`
- Create: `godot/scenes/system_dock.tscn`
- Create: `godot/scripts/ui/system_dock.gd`
- Modify: `godot/scenes/menu.tscn`
- Modify: `godot/scripts/menu.gd`
- Create: `godot/tests/native/test_campaign_ui.gd`

**Interfaces:**
- Produces campaign config `{country_id, name, faction_id, ideology_economic, ideology_social, background_id, difficulty_id, opening_role, seed}`.
- Produces routes `dashboard`, `policies`, `cabinet`, `parties`, `diplomacy`, `briefing`, `history`.

- [ ] Write a failing headless journey for New Campaign wizard validation, both opening roles, Back/Next, seed, and NativeGame creation.
- [ ] Implement Ardenia-only wizard without portrait selector or disabled foreign-country menu.
- [ ] Implement persistent system navigation with focus restoration and Escape/back behaviour.
- [ ] Test 1920×1080, 1280×720, keyboard-only flow, and saved Continue.
- [ ] Commit `feat(godot): add native campaign setup and navigation`.

### Task 2: Shared operation and explanation components

**Files:**
- Create: `godot/scenes/components/operation_list.tscn`
- Create: `godot/scripts/ui/operation_list.gd`
- Create: `godot/scenes/components/explanation_panel.tscn`
- Create: `godot/scripts/ui/explanation_panel.gd`
- Create: `godot/scenes/dialogs/decision_dialog.tscn`
- Create: `godot/scripts/ui/decision_dialog.gd`
- Create: `godot/tests/native/test_shared_ui.gd`

**Interfaces:**
- Consumes OperationRegistry descriptions and presenter explanation rows.
- Emits `operation_requested(operation_id, args)` only after validation/confirmation.

- [ ] Write failing tests for disabled reason, cost, forecast, confirmation, success/failure acknowledgement, stale-snapshot rejection, focus return, and long-text wrapping.
- [ ] Implement shared components using containers and theme constants; no fixed screen coordinates.
- [ ] Connect them to NativeGame signals and prove every request is disabled while another operation is in flight.
- [ ] Run accessibility and resolution checks; commit `feat(godot): add operation and explanation UI`.

### Task 3: Policies, budget, reforms, and cabinet pages

**Files:**
- Create: `godot/scenes/pages/policies.tscn`
- Create: `godot/scripts/ui/pages/policies.gd`
- Create: `godot/scenes/pages/cabinet.tscn`
- Create: `godot/scripts/ui/pages/cabinet.gd`
- Create: `godot/scenes/pages/briefing.tscn`
- Create: `godot/scripts/ui/pages/briefing.gd`
- Create: `godot/tests/native/test_government_pages.gd`

**Interfaces:**
- Consumes native presenters for bills, vote projection, budget baseline/plan, reform objective/project, ministries, cabinet, decision queue, calendar, households, and digest.

- [ ] Map every government operation to a visible control and every unavailable operation to a visible reason.
- [ ] Write failing journeys for law, budget, reform, regional programme, shortlist/appointment, ministry report, and background action.
- [ ] Implement pages and decision dialogs with forecast before commitment and explanation after result.
- [ ] Run headed screenshot review plus headless journeys in both resolutions.
- [ ] Commit `feat(godot): add government system pages`.

### Task 4: Parties, opposition, diplomacy, events, and history pages

**Files:**
- Create: `godot/scenes/pages/parties.tscn`
- Create: `godot/scripts/ui/pages/parties.gd`
- Create: `godot/scenes/pages/diplomacy.tscn`
- Create: `godot/scripts/ui/pages/diplomacy.gd`
- Create: `godot/scenes/pages/history.tscn`
- Create: `godot/scripts/ui/pages/history.gd`
- Create: `godot/tests/native/test_world_pages.gd`

**Interfaces:**
- Consumes presenters for factions/wings/coalitions, opposition programme/pledges/shadow cabinet, relations/treaties/world plans, pending events, press, lore, and legacy.

- [ ] Write failing journeys for opposition bill response, pledge, regional campaign, shadow appointment, each diplomacy verb, event resolution, and scrolling all history sections.
- [ ] Implement pages with government/opposition contextual variants from the same operation registry.
- [ ] Ensure world-map replacement is not reintroduced; diplomacy uses country list/detail while Ardenia remains the central map.
- [ ] Run focus, scroll, long-copy, role-gating, and resolution checks.
- [ ] Commit `feat(godot): add political world pages`.

### Task 5: Production scene cutover and complete journey

**Files:**
- Modify: `godot/project.godot`
- Modify: `godot/scenes/main.tscn`
- Modify: `godot/scripts/app.gd`
- Create: `godot/tests/native/test_complete_player_journey.gd`
- Modify: `docs/godot/native_port/PARITY_MATRIX.md`

**Interfaces:**
- Production scenes consume only `NativeGame`.
- Development bridge remains callable only from explicit legacy test commands until N6 removes it from production assets.

- [ ] Write a failing static test that recursively scans production `.tscn`/`.gd` dependencies and rejects `SimulationBridge`, `godot_bridge`, `python`, or external process calls.
- [ ] Replace bridge startup/request/recovery with NativeGame lifecycle and signals; preserve visible Save/Load and failure UI.
- [ ] Run a complete seeded government-to-opposition-to-government election-cycle journey and a starting-opposition journey with save/restart at each transition.
- [ ] Run every native suite, Python oracle suite, all resolution/accessibility checks, and headed human comparison at 100%, 125%, and 150% Windows scaling.
- [ ] Mark every UI/action parity row PASS, obtain independent review, record N5 PASS, and commit `feat(godot): cut interface over to native game`.
