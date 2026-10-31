# Plan: Ardenia, a native Godot game

_Direction set 2026-09-16; rewritten 2026-10-30 to describe the project as it
now stands._

> **Ardenia is a Godot game.** It is written in GDScript, it runs on Godot
> 4.7.2, and nothing Python executes at runtime, at build time, or in a test
> run. If you are a fresh session picking this repository up, everything you
> build goes under `godot/`. The Python tree at the repository root is a frozen
> historical reference — see *The Python tree* below — and is not the game.

---

## What this is

A single-player political simulation: a career in Ardenian government and
opposition, from the 1993 Reckoning onward. The player leads a party, wins or
loses elections, passes or fails budgets and legislation, appoints ministers who
can or cannot deliver, manages regions and energy dependence, and lives with
what households and neighbouring states make of it.

The whole thing is native Godot:

- **Simulation** — `godot/scripts/native/sim/` (the monthly pulse: economy and
  debt, budget, ministries, political capital, regions, households, polls,
  stability, elections, events and arcs, crisis, diplomacy, the foreign world,
  gas and orientation).
- **State** — typed GDScript classes under `godot/scripts/native/state/`, owned
  by the `NativeGame` autoload, saved through `save_store.gd` to `user://saves/`
  with a serializable RNG so a reload continues deterministically.
- **Player actions** — `godot/scripts/native/actions/`, one input-free module
  per surface (budget, cabinet, legislation, diplomacy, energy, opposition,
  orientation, regional programmes). The UI formats engine read models and
  never derives eligibility or effects itself.
- **Content** — committed JSON under `godot/data/native/`: 31 countries, the
  Ardenian lore package, and thirteen catalogues (bills, budget envelopes,
  reform objectives, traits, events, dispatch pools, press templates, household
  groups, regions and programmes, backgrounds, difficulties, energy, foreign
  orientation).
- **Presentation** — `godot/scenes/` and `godot/scripts/`: the menu, the
  dashboard, the pixel Ardenia map, the desk panels, the city scenes, the
  monthly report, the generated audio bed.
- **Tests** — `godot/tests/{native,map,ui}/`, run headless through
  `godot/tests/native/run_contract_tests.gd`.

A playable Windows build lives at `Play/Ardenia.exe`.

## The Python tree

`engine/`, `content/`, `models/`, `game_state.py`, `gui.py`, `main.py`,
`smoke_test.py` and their helpers are the original PySide6 implementation. They
are kept for one reason: they are a readable record of what Ardenia contains and
how its institutions relate. Treat them as documentation.

- **Do not modify any `.py` file.** Not to fix a bug, not to keep a test green,
  not to re-export content.
- **Do not run Python as part of any task** — no test step, no build step, no
  content export. `scripts/run_godot_slice.ps1` and `scripts/native_port/*` are
  bridge-era and parity-era leftovers; they are dead.
- **The content export is over.** `godot/data/native/` was seeded from
  `content/` once and has since diverged well past it — 31 countries against
  Python's 9, plus energy and foreign-orientation catalogues with no Python
  source at all. That JSON is now authored directly in the Godot tree. Nothing
  regenerates it.
- **Numbers do not have to match.** There is no parity contract, no comparator,
  no tolerance. Godot owns every equation, constant, threshold and update order.
  Where the Python prose explains a causal relationship, read it; where it
  states a formula, you are free to ignore it, and usually should.
- The root `CLAUDE.md` still describes the Python architecture in detail. That
  section is history, useful as a design reference and nothing more.

## Where development actually happens

`PLAN.md` sets direction. Task-level work runs through the
subagent-driven-development process:

- Plan documents in `docs/superpowers/plans/`.
- One ledger per plan at `.superpowers/sdd/<plan-name>/progress.md`. A task
  marked `complete` is done — do not re-dispatch it. Trust the ledger and
  `git log` over your own recollection; sessions get compacted mid-task.
- `docs/godot/AGENT_GUIDE.md` is the working contract: file ownership, review
  requirements, handoff format, and the UI rules that have already bitten
  (notably: no runtime-text `Label` without `text_overrun_behavior = 3`, or it
  sets the window's minimum width).
- Current branch: `claude/godot-native-sim`, in the worktree
  `D:\Political Sim Game\.worktrees\godot-native-sim`. The worktree is shared
  with other agent sessions — commit with explicit paths
  (`git commit -m "..." -- <paths>`) and never use bare `git stash`.

## Where the plan stands

**Landed.** The native core (typed state, campaign factory, calendar and
modifier lifecycle, serializable RNG, save/load, the bridge cut out of
production scenes); the monthly political economy across all six domains; the
government-play action surface; and the living world — events and the schemer,
Vasca and Vetrenka arcs, the civil-war gauge, diplomacy and treaties and
sanctions, opposition play with the domestic-AI government, shadow cabinet and
pledges, the press and dispatch layer, and a 31-country foreign world with
orientation and energy politics.

**Open.** Two things:

### Phase 5 — The game as a game

1. Every screen a real Godot scene, to the same standard: campaign setup,
   dashboard, policies, cabinet, parties, diplomacy, briefing, history/codex,
   settings.
2. **Art direction: the control-room terminal.** Near-black glass chrome, thin
   grey frame lines with titles cut into the top line (`TerminalFrame`), a
   monospace display face in caps, dim keys against cream values, amber for live
   state, red reserved for alarm, `[████····]` bracket gauges. Pictures — map,
   region and city scenes, menu backdrop — sit under `CrtGlass`. Colours live in
   `godot/scripts/ui/ui_palette.gd` and `theme/ardenia_theme.tres`; change one,
   change the other. This replaced the earlier burgundy/gold "Ministry Wire"
   documentary direction, which the project window title
   (`Ardenia — Ministerial Wire`) is still a leftover of.
3. Map polish on the pixel map that exists, not a rebuild.
4. Icons, transitions, input feedback, and the small responses that make an
   action feel acknowledged. The generated audio bed is in; it is unverified by
   ear.
5. Keyboard navigation, readable defaults at 1920×1080 and 1280×720, real
   Windows display-scaling checks.

*Done when:* it looks and feels like a product, not a prototype.

### Phase 6 — Ship

Export presets (`godot/export_presets.cfg`), `Ardenia.exe` plus payload,
clean-machine verification with neither Python nor Godot installed, release
archive and checksum, versioning, release checklist.

## Standing design rules

These bound every new system and every slice, and they are the reason this is a
remake rather than a port.

1. **State the intended player experience before selecting a formula.** A
   decision needs a legible cost, a delayed consequence, and a credible
   trade-off.
2. **Give every constant a reason** stated beside the system or in its design
   record. "It was that in the old build" is not a reason.
3. **Never copy a formula, constant, update order or test assertion** merely
   because it existed elsewhere.
4. **Test intended behaviour** — ranges, monotonic directions, boundedness,
   save continuity — not inherited numbers. Record every altered test in the
   task report.
5. **Never weaken an assertion to make a build pass.**
6. **Tune by play session**, after the behavioural tests are green.

Every player-facing slice must also state: the decision and the uncertainty the
player can understand; the lasting political, administrative and economic
consequence; what is shown before commitment and what is explained after; and
why it is still interesting on a second campaign.

## Key decisions

- **Design-remake, not port.** The Python build describes what Ardenia
  contains; Godot decides how it computes anything. The two have diverged
  numerically by design, and the Python build is not a fallback.
- **Typed GDScript classes, not nested dictionaries.** Raw `Dictionary` and
  `Array` are normal at JSON I/O boundaries — content loading, save files — and
  never the canonical in-memory representation of campaign state.
- **Determinism where it is cheap.** Elections, turnout, stability and the
  civil-war gauge are deterministic functions of tracked state. RNG appears in
  triggers, is owned by campaign state, and round-trips through the save.
- **Modifiers over repeated mutation.** `onset → ramp → hold → decay`,
  recomputed fresh each turn so nothing accumulates and effects stay bounded.
- **One colour system per job.** Party colours never fill a map region; the
  pressure/unrest ramp never colours a party.
- **Nothing finer than a tile** may be authored into a map edge, and count
  *octaves*, not just scale — a three-octave ridged fold creases at roughly
  eight times its scale, and sub-tile detail can only alias into a sawtooth.
- **Ardenia only, by design.** One playable country. The other thirty are world
  actors — AI governments with agendas and plans, diplomacy targets, map
  neighbours. Widening scope later means widening the gate, not unpicking
  anything.
- **Retire rather than delete.** Superseded plans and the parity apparatus stay
  in the tree as the record of how this was decided.

## Toolchain

- **Engine:** `D:\AI Stuff\Godot\Godot_v4.7.2-stable_win64_console.exe` (note
  `D:\AI Stuff\`, not `D:\Godot\`).
- **Run the game:** `& "<godot>" --path godot`
- **Run a test:** `& "<godot>" --headless --path godot --script res://tests/native/<test>.gd`
- **Run the suite:** the same, with `res://tests/native/run_contract_tests.gd`.
- **Re-import after a data bake:** `& "<godot>" --headless --path godot --import`
  — Godot's import cache is a separate staleness source from the baked files,
  and a stale cache makes `test_tile_baker` fail for reasons that have nothing
  to do with your change.
- **Build:** `godot/export_presets.cfg`; the current build sits in `Play/`.

## Out of scope

Playable foreign countries. Tactical warfare. Multiplayer, accounts, telemetry,
cloud saves, mod workshop. Recreating the Qt UI screen-for-screen where a better
Godot interaction expresses the same mechanic. And explicitly: numerical parity
with Python, any oracle comparator, and bug-fixing the two implementations in
lockstep.

## Verification

Before any slice is called done:

1. **Its focused tests pass**, plus `run_contract_tests.gd`, headless, exit 0.
2. **The game launches and the new surface is exercised by hand.**
3. **A campaign survives a round trip** — start, advance, save, quit, relaunch,
   load, continue coherently.
4. **No Python is reachable** — no production scene loads a bridge script, no
   child process spawns, no task step runs an interpreter.
5. **Independent review** of the diff, with Critical and Important findings
   fixed before the next slice starts.
6. **A ledger entry appended** in that plan's
   `.superpowers/sdd/<plan>/progress.md`, so any session can resume cold.

Final acceptance: `Ardenia.exe` runs from an extracted archive on a machine with
neither Python nor Godot installed; new campaign, continue, save, load,
government and opposition play, the monthly pulse, events, a parliamentary vote,
a budget, diplomacy, and an election transition all work.

---

## Appendix — how this direction was reached

Kept short, because it no longer governs anything.

The project began in Python with a PySide6 front-end. Presentation moved to
Godot first via a **bridge** — Godot rendered, Python stayed authoritative over
a JSON-lines subprocess. On top of that a **native rewrite under a parity
contract** (`N0`–`N6`) was written, requiring every mechanic to be provably
equal to Python within `1e-9`, tracked in a parity matrix, with both
implementations fixed in lockstep until cutover.

That contract was cancelled on 2026-09-16. It was never what was asked for; the
ask was to remake the game. Proving equivalence is a larger project than
building the game and bought nothing, since no existing player had saves to
migrate. Two findings sealed it: Godot documents that float math "is not
guaranteed to be exact or deterministic" across CPUs, operating systems and
versions, so the `1e-9` cross-language target may not have been physically
reachable; and the nested untyped `Dictionary` state the parity spec mandated,
chosen purely so a comparator could diff it, sits on GDScript's slowest
execution path.

Superseded and retained as audit trail: `docs/godot/native_port/`,
`docs/godot/NATIVE_REWRITE_AGENT_GUIDE.md`,
`docs/superpowers/plans/2026-09-16-native-godot-*`,
`docs/superpowers/specs/2026-09-16-native-godot-rewrite-design.md`,
`scripts/native_port/`, and `godot/data/native/fixtures/`. Do not build on them.
One piece survives and is still in use: the dependency-free test harness,
`godot/scripts/native/testing/test_support.gd` and
`godot/tests/native/run_contract_tests.gd`.
