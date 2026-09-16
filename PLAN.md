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

### Phase 2 — The monthly simulation

Port the monthly pulse as game systems, in the phase order `engine/turn.py`
documents (order is load-bearing — later phases read earlier same-turn results):
economy (growth, inflation, unemployment, debt, revenue/expenditure), annual
appropriations, ministry capacity/workload/delivery/backlog, regional
conditions, the 36 household groups, then approval and stability. Plus the
political-capital economy and governing overhead, and the monthly digest.

*Playable result:* time means something. The map's pressure colours move for real
reasons; the monthly report explains why.

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
- **Branch `godot-native/rebuild`** off current `codex/godot-foundation` HEAD.

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
`& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path godot --script <test>`.

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
- **GDScript throughput on the monthly pulse** — 36 household groups × regions,
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
2. **The game launches and plays** — `& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --path godot`,
   then actually exercise the phase's new surface by hand.
3. **A campaign survives a round trip** — start, advance, save, quit, relaunch,
   load, and confirm the restored campaign continues coherently.
4. **No Python is reachable** — production scenes load no bridge script and spawn
   no child process. From Phase 1 onward this is a standing check.
5. **Independent review** of the phase diff, with Critical and Important findings
   fixed before the next phase starts.
6. **`STATUS.md` handoff entry appended** in the existing format, so any agent —
   Claude, Codex, OpenCode, or you — can resume cold.

Final acceptance: `Ardenia.exe` runs from an extracted archive on a machine with
neither Python nor Godot installed; new campaign, continue, save, load,
government and opposition play, the monthly pulse, events, a parliamentary vote,
a budget, diplomacy, and an election transition all work; and the process tree
contains no Python.
