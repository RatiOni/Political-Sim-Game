# Ardenia Native Godot Rewrite Design

> **SUPERSEDED 2026-09-16 - read `PLAN.md` at the repository root.**
> The parity-contract programme (`N0`-`N6`, `1e-9` oracle comparison,
> `PARITY_MATRIX.md` as a gate) was cancelled by the project owner. Ardenia is
> being remade in Godot as a game, using the Python source as a design reference
> to read rather than an oracle to match. This document is retained as the
> record of a direction not taken. Do not execute it.


**Decision:** Replace the Python/PySide application with a Godot 4.7.2 game whose complete runtime is GDScript and committed game data.

**Baseline:** `codex/godot-foundation` at `e4cffca`. The existing Godot slice, bridge, menu, map, Save/Load controls, seeded-worker checks, and recovery tests are evidence and reusable presentation work. They are not the final runtime architecture.

## Product boundary

The rewrite changes the engine and presentation technology, not the game’s identity. `docs/EARLY_ACCESS_MISSION.md` remains authoritative: Ardenia is the only playable country; the eight neighbouring countries remain simulated actors; the core experience is a political career through government and opposition; policy intent, administrative delivery, households, regions, parties, parliament, elections, and foreign pressure must remain connected.

No new simulation mechanic is added during the rewrite. Content and balance are frozen except for confirmed bug fixes, and every such fix must be applied to both implementations until native cutover. This prevents the reference target from moving while it is being reproduced.

## Runtime architecture

The shipped game contains:

- Godot 4.7.2 scenes, themes, and GDScript;
- JSON content and map data under `godot/data/native/`;
- native campaign saves under `user://saves/`;
- no Python interpreter, Python worker, PySide library, virtual environment, shell launcher, or repository path.

The native engine mirrors the current repository layers:

```text
godot/data/native/        authored and exported content
godot/scripts/native/state/       state creation, validation, persistence
godot/scripts/native/sim/         deterministic simulation phases
godot/scripts/native/ops/         input-free player operations
godot/scripts/native/presentation/ read models and explanations
godot/scenes/              player-facing Godot scenes
```

Canonical native campaign state is a versioned `Dictionary`. Simulation modules are stateless GDScript scripts that receive and mutate that dictionary. This preserves the current explicit persistence model, makes parity comparison straightforward, avoids a parallel forest of one-use model classes, and keeps presentation code from owning authoritative state.

`NativeGame` is the only runtime owner of campaign state. UI scenes submit an operation id and validated argument dictionary to `NativeGame.execute()`. They render read models produced by native presenters. A scene must never calculate simulation effects.

## Determinism and randomness

Deterministic mechanics must match the Python oracle within explicit numeric tolerances. Native stochastic systems use one serializable `SimRng` owned by campaign state. The port does not attempt to reproduce Python’s private `random` byte stream. Stochastic parity is instead proven with injected random tapes that force the same branch in both implementations, plus invariant and distribution checks.

Saving and loading must preserve the native RNG state so a native campaign continues deterministically after restart.

## Content migration

Existing country JSON is reused directly where its schema is sufficient. Python-authored catalogs are exported during development to canonical JSON fixtures. Runtime callbacks are replaced by stable symbolic rule ids resolved by explicit native registries. Generated files are never edited by hand; the exporter and registry-lint tests are the source of truth until cutover.

The final executable does not run the exporter. All required content is committed before export.

## Parity contract

Every mechanic is entered in `docs/godot/native_port/PARITY_MATRIX.md` and receives one of these proofs:

1. **Exact:** ids, strings, integer values, dates, phase order, eligibility, and serialized structures match.
2. **Tolerant numeric:** floating-point results match to `1e-9` absolute tolerance unless the matrix records a stricter domain rule.
3. **Forced stochastic:** an injected tape produces the same branch and effects.
4. **Invariant/statistical:** the native system preserves documented bounds and rates when exact RNG-stream parity is intentionally not required.
5. **Human interaction:** readability, navigation, feedback, and game feel are verified in a headed build.

A subsystem is not ported because its files exist. It is ported when its matrix rows pass, its saves round-trip, its player operations are available in Godot, and a separate reviewer approves the gate.

## Save policy

Native saves use a new explicit format version and atomic write-then-replace. A development importer reads the current Python JSON save schema and produces native state. Imported campaigns preserve authoritative political, economic, regional, household, world, event, and calendar state. Python RNG continuation is not promised; the importer seeds native RNG deterministically from the imported campaign identity and records that conversion in save metadata.

## Cutover and executable

The Python application remains intact as an oracle until all parity gates pass. It is never deleted piecemeal. At cutover:

- `NativeGame` replaces `SimulationBridge` in the production project;
- the Godot project imports no bridge scripts and launches no external process;
- Windows export presets produce `Ardenia.exe` and its `.pck`/data payload;
- a clean-machine verification runs without Python or Godot installed;
- save, restart, government/opposition continuity, a monthly pulse, an election transition, and error logging are verified from the packaged executable;
- the Python source may remain under `legacy_python/` for audit until a separate archival decision, but it is excluded from the shipped archive and from production launch paths.

## Programme gates

| Gate | Required outcome |
| --- | --- |
| N0 | Contract, fixtures, test runner, parity matrix, and agent handoff exist. |
| N1 | Native content, initial campaign state, calendar, modifiers, RNG, and persistence work without Python. |
| N2 | Economy, budgets, ministries, regions, households, stability, digest, and monthly phase order pass parity. |
| N3 | Legislature, reforms, cabinet, parties, player operations, and elections pass government-mode parity. |
| N4 | Opposition, domestic AI, events, crises, diplomacy, world simulation, roleplay, press, and flavour pass parity. |
| N5 | Every playable Python surface has a Godot scene; a complete government/opposition election-cycle journey passes. |
| N6 | The bridge is removed from production, native saves/import work, and a downloadable Windows executable passes clean-machine verification. |

Failure at a gate blocks dependent phases. Work may return to an earlier phase; it may not waive parity to preserve schedule.

## Explicit exclusions

- Playable foreign countries.
- Tactical warfare.
- New reform families, event chains, economic variables, or balance passes.
- Multiplayer, accounts, telemetry, cloud saves, mod workshop integration, or online services.
- Recreating the current UI screen-for-screen when a clearer Godot interaction expresses the same mechanic.
