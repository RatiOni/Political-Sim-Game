# Ardenia Godot Migration Programme Design

**Status:** Proposed migration programme
**Date:** 16 September 2026
**Target:** A Godot-based Ardenia client backed by the proven Python political simulation, with any native-engine rewrite requiring separate evidence

## 1. Purpose

Ardenia has outgrown the feel of a Python desktop utility, but it has not outgrown its simulation. The repository already contains a country-neutral political engine, deterministic monthly systems, government and opposition careers, households, regions, ministries, budgets, parties, diplomacy, events, persistence, a downloadable Windows build, and a large regression suite. Godot is being adopted to make those systems feel like one coherent game: a readable national map, purposeful time controls, animated state change, stronger navigation, sound, and a presentation hierarchy suited to a political simulation.

This programme does not treat a new engine as permission to discard working rules. Python remains the reference implementation until a Godot-native replacement proves the same campaign outcomes. Visual migration and simulation development are separate reviewable tracks joined by explicit data contracts.

## 2. Product outcome

The migrated game should let a new player:

1. understand their office, immediate national situation, and available authority;
2. choose a political objective and see the people, regions, institutions, and parties involved;
3. negotiate, legislate, fund, and administer a response;
4. advance through meaningful political dates without watching empty days;
5. understand both the intended and observed consequences of their choices;
6. continue through government, defeat, opposition, and a route back to office; and
7. download and run the Windows build without installing Python or Godot.

The Early Access mission remains authoritative. Godot changes how Ardenia is experienced; it does not change the product into a map painter, a daily economic micromanagement game, or a generic multi-country sandbox.

## 3. Architecture decision

The migration uses a strangler approach with three runtime states:

### State A: Python reference plus Godot presentation

Godot owns scenes, input, animation, audio, responsive layout, and presentation state. A narrow local bridge owns a live Python `GameState` and exposes versioned JSON commands. The bridge calls existing `engine/player_ops.py`, `TurnEngine`, and persistence code. Godot never edits a save or mutates simulation fields directly.

This state exists to answer one question cheaply: does Godot materially improve Ardenia as a game?

### State B: Production Godot client plus packaged Python simulation

The Godot client reaches full feature coverage while Python remains authoritative. The bridge is packaged as a private worker beside the Godot executable, started and stopped by the game, with no console window or user setup. This is a legitimate release architecture: Godot supplies game presentation and Python supplies the simulation it already runs correctly.

The verified development editor is Godot 4.7.2 standard at `D:\Godot\Godot_v4.7.2-stable_win64.exe`. GDScript is sufficient for scenes, presentation, and the local process client. No .NET SDK or second gameplay language is required for the migration gates described here.

### State C: Optional native simulation investigation

A Godot-native simulation is considered only if measured startup, distribution size, crash reliability, platform support, profiling, or developer workflow shows that the Python worker is the limiting factor. That decision receives a separate architecture review and plan. Improving simulation depth is not evidence for changing language: the existing Python engine can be extended directly.

## 4. Non-negotiable boundaries

- Ardenia remains the only Early Access player country. The other eight countries remain simulated world actors.
- `engine/player_ops.py` remains the only action authority while Python owns the simulation.
- The Python bridge exposes an allow-listed command registry. It never accepts a Python function name, expression, module, filesystem path, or arbitrary object from Godot.
- Simulation state crosses the bridge as versioned JSON snapshots. No Python object identity leaks into the client.
- Godot presentation nodes do not contain economic, electoral, legislative, diplomatic, or stability formulas.
- Monthly economic and social simulation remains monthly. Daily time is reserved for scheduled political process, deadlines, domestic-government legislation, and presentation.
- Random triggers remain seedable. Core elections, stability, turnout, implementation, and crisis calculations remain deterministic.
- Existing save files remain loadable by the Python reference during the hybrid period.
- Godot and PySide6 clients must load the same save format while both exist.
- No balance changes are bundled into visual migration commits.
- No new mechanic is accepted without one direct mechanics test, one consequence/explainability check, and persistence coverage when state is added.
- The current PySide6 build remains runnable until the Godot build passes the external playtest gate.

## 5. Programme workstreams

### 5.1 Foundation and vertical slice

Create the Godot project, a versioned Python-to-Godot protocol, a playable national dashboard, the Ardenia map, calendar controls, decision queue, monthly digest, one real player action, and save/load. This milestone must be independently playable without changing balance or adding mechanics.

The slice is accepted only if it demonstrates a clearer 1920x1080 experience, no simulation divergence, and a reproducible Windows development launch. If it does not, the programme stops with the Python game intact.

### 5.2 Complete presentation migration

Move the existing player-facing surfaces into Godot in user-journey order:

1. campaign setup and opening briefing;
2. dashboard, national map, decision queue, calendar, and monthly report;
3. policies and reform workspace;
4. cabinet and ministries;
5. parties, blocs, legislature, and elections;
6. regions and households;
7. diplomacy and the living world;
8. history, glossary, save/load, settings, accessibility, and feedback export.

Every surface consumes shared snapshots and submits allow-listed actions. PySide6 remains a reference client until feature coverage is recorded, not guessed.

### 5.3 Mechanic depth: the canonical reform loop

After the repository's human evidence gate is complete, implement one reform family from diagnosis through judgment. The evidence decides which family, political counterparty, and pacing model lead; the migration does not pre-commit to regional inequality merely because it is currently prominent in the code.

The canonical loop contains:

- diagnosis from live household, regional, fiscal, and ministry signals;
- a durable objective;
- instrument, scope, pace, territorial reach, and funding choices;
- consultation with named blocs, coalition partners, ministers, and affected stakeholders;
- amendments, concessions, delay, rejection, or conflict;
- parliamentary and/or executive authority;
- implementation through funding, capacity, state reach, resistance, and time;
- six-, twelve-, and twenty-four-month evaluation; and
- remembered political judgment by households, regions, parties, media, and voters.

This is depth through interaction among existing systems, not a second economy built beside the first one.

### 5.4 Simulation quality work

Simulation expansion follows the causal chain the player can observe:

```text
objective and instrument
        -> law / budget / administrative programme
        -> ministry workload and delivery
        -> regional and household outcomes
        -> public interpretation and party conflict
        -> electoral and coalition consequences
```

Priority improvements are:

1. a promise and concession ledger so political actors remember commitments;
2. reform implementation milestones and failure modes;
3. regional and household histories sufficient to compare before and after;
4. minister and bloc positions tied to concrete reform components;
5. political-calendar items generated by actual processes;
6. forecasts that state direction, cost, workload, likely votes, and uncertainty;
7. causal reports that explain which policy, condition, or institutional bottleneck moved an outcome; and
8. opposition tools that influence public interpretation, amendments, scrutiny, campaigns, and coalition fractures without granting state authority.

New numeric subsystems are added only where these interactions cannot be represented by the existing models, modifiers, memories, and schedules. These changes remain in the Python engine during the planned migration, so both clients receive identical behavior.

### 5.5 Visual and interaction quality

The visual direction uses the established Ministry Wire / Ministerial Broadsheet family rather than generic sci-fi panels. Godot should improve:

- a legible long east-west Ardenia map with selectable regions, settlements, routes, terrain, and political overlays;
- layered map modes for politics, economy, state reach, services, and security;
- motion that communicates causality: dates arriving, pressure accumulating, votes shifting, programmes entering implementation, and modifiers changing phase;
- stable information density at 1920x1080 and Windows scaling settings;
- progressive disclosure: national headline, regional comparison, then underlying components;
- keyboard navigation, focus visibility, scalable text, contrast, and reduced-motion settings;
- brief, intentional sound for dispatches, deadlines, votes, crises, and month-end reports; and
- charts that answer a political question rather than decorate a statistic.

Godot does not create an art direction by itself. UI scenes must follow the repository's design contract and use shared theme resources, spacing, typography, and motion rules.

## 6. Migration sequence and release gates

| Gate | Deliverable | Evidence required to proceed |
| --- | --- | --- |
| G0 | Toolchain and baseline | Godot 4.7.2 installation recorded; absence of a .NET dependency confirmed; Python suites pass; deterministic fixtures captured |
| G1 | Godot vertical slice | One real campaign state, map interaction, time, one action, monthly report, save/load; no state divergence |
| G2 | Presentation-complete hybrid | All player actions reachable; campaign setup through election playable; PySide6 comparison checklist complete |
| G3 | Canonical reform slice | External baseline synthesis exists; diagnosis-to-judgment loop demonstrates stakes, opposition, delivery, and memory |
| G4 | Production bridge and packaging | Worker lifecycle, logs, crash recovery, protocol compatibility, save paths, and clean-machine bundle pass |
| G5 | Godot Windows candidate | Full Godot journey works without Python/Godot installed by the tester; legacy saves load; release checks pass |
| G6 | Early Access candidate | Full election cycle, government/opposition continuity, onboarding, accessibility, performance, and external playtests pass |

Failing a gate means fixing or narrowing that milestone. It does not authorize building the following phase in parallel to hide the failure.

## 7. Test strategy

Four layers protect the migration:

1. **Python regression:** `smoke_test.py`, `distribution_test.py`, and the modal-patched `ui_smoke_test.py` continue to pass during the hybrid period.
2. **Contract tests:** JSON request/response fixtures verify bridge versioning, validation, action allow-listing, error shapes, and snapshot stability.
3. **Client parity tests:** Qt/CLI and Godot submit the same command sequence to the same Python engine and compare canonical serialized state. Presentation snapshots must never alter that state.
4. **Godot journey tests:** headless scene tests cover startup, new campaign, map selection, action submission, time advancement, save/load, and focus/navigation. Visual review at 1920x1080 and 125%/150% scaling remains a human acceptance check.

Tests establish correctness; external playtests establish whether the result is understandable and enjoyable.

## 8. Distribution transition

The hybrid prototype is a developer build. It is not sent to testers until a repeatable launcher starts Godot and the private Python worker, closes the worker when the client exits, writes logs to the Ardenia user-data directory, and verifies the exact bundled protocol version.

The public build pipeline changes only after the Godot candidate reaches G5. The release bundle contains the Godot executable and a private packaged Python worker; the tester installs neither runtime. Existing GitHub releases remain reproducible and downloadable. A Godot release receives a new version and tag; it does not overwrite a PySide6 asset.

## 9. Deliberate exclusions

- No multiplayer, mod SDK, console port, mobile port, or web build.
- No playable foreign-country campaigns for Early Access.
- No 3D world, character walking, tactical combat, or province-level map painting.
- No conversion of every monthly statistic into a daily calculation.
- No simultaneous rewrite of simulation formulas and presentation surfaces.
- No native simulation rewrite without evidence that the packaged Python core is the limiting factor.
- No speculative plugin framework, entity-component rewrite, network service, or database.
- No deletion of the Python reference before G5.

## 10. Immediate execution unit

The first implementation unit is `docs/superpowers/plans/2026-09-16-godot-foundation-and-vertical-slice.md`. It ends at G1. Presentation completion, the canonical reform loop, and production packaging receive separate implementation plans after their preceding gates provide real interfaces and evidence.
