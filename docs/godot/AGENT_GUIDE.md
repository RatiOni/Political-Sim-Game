# Ardenia Godot rebuild — agent guide

This is the common working contract for Claude, Codex, OpenCode, and human
contributors on the Godot rebuild. It replaces
`docs/godot/NATIVE_REWRITE_AGENT_GUIDE.md`, which governed the now-cancelled
parity-contract programme.

## Required reading order

1. `PLAN.md` (repository root) — what the game is, what has landed, and the
   standing design rules. Its appendix explains the superseded parity
   programme, if you touched anything under
   `docs/superpowers/plans/2026-09-16-native-godot-*` or
   `docs/godot/native_port/` before now.
2. `AGENTS.md`
3. `docs/EARLY_ACCESS_MISSION.md` — product authority: what Ardenia is, who
   plays it, what "done" looks like as a game.
4. The ledger for the plan you are working on, at
   `.superpowers/sdd/<plan-name>/progress.md`. Task lines marked `complete`
   are done; do not re-dispatch or redo them. A line ending in a fix round is
   mid-loop; resume at the next round. Trust this file and `git log` over any
   memory of your own — sessions get compacted or run out of budget mid-task.

## What this project is, in one paragraph

Ardenia is a native Godot 4.7.2 political simulation — GDScript simulation,
typed state, committed JSON content, Godot scenes, and no Python at runtime, at
build time, or in a test run. The Python tree at the repository root
(`engine/`, `content/`, `models/`, the PySide6 front-end) is a **frozen
historical reference**: read it to understand what Ardenia contains, never
modify it, never run it as part of a task. There is no parity contract, no
fixture comparison, no `1e-9` tolerance — Godot owns every equation and
constant. Write idiomatic GDScript that does the same job; don't transcribe,
and don't chase equivalence.

## Canonical starting point

Work happens on branch `claude/godot-native-sim`, in the shared worktree
`D:\Political Sim Game\.worktrees\godot-native-sim`. If you're picking this up
fresh: `git status --short` and `git log --oneline -5` first, so you know
whether you're resuming mid-task or starting clean. Use the worktree directly;
do not create a separate isolated one for a task the ledger expects to land on
this branch. Never work in the user's root checkout
(`D:\Political Sim Game`) — it is a separate, dirty, protected checkout.

The worktree is shared with other agent sessions. Commit with explicit paths
(`git commit -m "..." -- <paths>`) so you never carry someone else's
uncommitted work, and never use bare `git stash` / `git stash pop` — the stash
stack is shared.

## Coordination

- Work is organised per plan: a document in `docs/superpowers/plans/` and its
  own ledger in `.superpowers/sdd/<plan-name>/progress.md`. The native core,
  the monthly political economy, government play and the living world have all
  landed; what remains in `PLAN.md` is **Phase 5 (the game as a game)** and
  **Phase 6 (ship)**, plus whatever deepening slice the current plan names.
  Read that plan's ledger and `git log` before acting; the ledger and
  committed work always override this guide when they disagree.
- Parallel work is fine only when file ownership doesn't overlap and the task
  breakdown marks the tasks independent. Tasks ordered by the monthly pulse
  consume the earlier systems — preserve that sequence unless the ledger
  records an explicit, non-overlapping split.
- `native_game.gd`, `content_repository.gd`, and any file two tasks would
  both need to edit have one owner at a time. Check the ledger before
  touching a file another task's entry claims.
- Each task ends with its own focused test, a commit, and an independent
  review (spec compliance + code quality) before the next task starts.
- Critical and Important review findings are fixed (or explicitly ruled on
  and parked, per the SDD fix-loop process) before the next task begins.
  Minor findings are recorded in the ledger with a disposition, not silently
  dropped.
- JSON under `godot/data/native/` is authored directly in the Godot tree and
  committed. Nothing regenerates it: the old Python exporter
  (`scripts/native_port/export_native_content.py`) is dead, and the content has
  diverged far past `content/` — 31 countries against Python's 9, plus energy
  and foreign-orientation catalogues with no Python source. Edit the JSON, and
  keep `catalog_manifest.json` in step.
- Do not delete or rewrite another contributor's unrelated changes. Do not
  merge, push, tag, or publish without explicit authorization.

## Handoff entry

Progress lives in `.superpowers/sdd/PLAN/progress.md`, in the format the
subagent-driven-development process already uses there — one line per task
status, ruling, or fix round, e.g.:

```
Task 2: complete (commits a1b2c3d..e4f5a6b, review clean)
Task 3: fix round 1/5 (1 addressed, 0 open -- RNG seed validation; commits e4f5a6b..f7a8b9c)
```

If you complete work outside a Claude subagent dispatch (e.g. OpenCode working
directly), append the same shape of entry yourself so the ledger stays the
single source of truth regardless of which tool did the work.

## Definition of done

"Implemented" means the code exists and its own task's test passes.
"Complete" means: the focused test passes, a full manual or headless play
verification for that task's `Playable result` (see `PLAN.md`) succeeds, and
an independent review has no open Critical or Important finding. Only
complete work may be consumed by a later task or phase.

## The owner plays a packaged build, not the source

`D:\Political Sim Game\Play\Ardenia.exe` is an exported Windows build with
the scenes and scripts baked in at export time. **Editing the source does not
change what the owner is playing.** A fix is not delivered until the build is
re-exported:

```
"D:\AI Stuff\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path <worktree>/godot --import
"D:\AI Stuff\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path <worktree>/godot --export-release "Windows Desktop" "D:\Political Sim Game\Play\Ardenia.exe"
```

`Play/Update Ardenia.cmd` does exactly this and then launches the game. This
has already cost one round trip: a header-layout fix was committed at 13:12
and reported as "not sure it did anything" because the build in `Play/` was
from 12:48. Check the build's timestamp against the fix before concluding a
fix did not work, and re-export when the owner is going to play. Note the
export packages the worktree as it stands, including any other worker's
uncommitted changes — boot the result once before handing it over.

## UI gotcha: a label must never set the window's minimum size

A Godot `Label` reports its full text width as its minimum size and
propagates that up through every parent to the window. A label that takes
runtime text therefore widens the whole dashboard past the viewport, and the
UI reads as clipped or "zoomed in" at both edges. This has now bitten twice:
once in the Qt build (see the matching gotcha in the root `CLAUDE.md`) and
once here, when resolving a decision wrote a full sentence into the header's
`PreviewStatus` and pushed the scene to 2142 px inside a 1920 px window.

**Any label that receives runtime text needs `text_overrun_behavior = 3`**
(trim to ellipsis), and a header label that should absorb slack rather than
demand it also wants `clip_text = true`, `size_flags_horizontal = 3` and a
modest `custom_minimum_size`. Labels with static text authored in the
`.tscn` do not need this.

Note the trap that let it ship: the journey test asserts the layout at both
1920 and 1280, but compact mode **hides** `PreviewStatus` below 1500, so the
1280 case could never reproduce it. `vertical_slice_test.gd` now sets a wordy
status before the native-size assertion at each width; that guard fails
loudly if the protection is removed.

## Pictures are ASCII conversions of a smooth source

Every picture except the map reaches the screen through
`scripts/ui/ascii/ascii_convert.gd` (`shaders/ascii_convert.gdshader`). The
control underneath draws an ordinary smooth image (sub-pixel motion, soft
light, gradients and translucency are all fine there), and the converter re-picks
every 5x8 screen-pixel cell each frame: tone chooses a glyph on the density
ramp (empty . · : ░ ▒ ▓ █), hue snaps to the scene's restrained palette
(`AsciiConvert.PALETTES`), and only glyph ink is drawn on `#0b0e09`. Rows
below `set_water_from` use dash streaks. `burst()` is the big-moment flash and
shockwave. Consequences:

- Do not pixel-snap or quantise a source; the converter does that, and
  snapping is what makes motion jump cell to cell.
- Do not add glow, scanlines or colour grading on top of a converted picture —
  nothing may reach the screen except glyphs. Scanlines (`CrtGlass`) belong to
  the map only, by the owner's choice.
- The ░ ▒ ▓ shades are screen-space patterns, not bitmaps: a 5-px cell cannot
  tile a checkerboard, and a bitmap one prints vertical stripes.
- Thumbnails mislead: amber ink at 25-50% coverage reads olive when scaled
  down. Measure ink colour before "fixing" a palette.

The map is the exception: `AsciiTerrain` draws glyphs from terrain data
directly, with cell backgrounds, under scanline glass.

## Runtime prohibition

Nothing in this project runs Python any more — not the game, not the build,
not a test step. The final game ships with no Python installation, no PySide,
no worker process, and no repository path baked into it. The test harness is
pure GDScript (`godot/tests/native/run_contract_tests.gd`). No development-only
path may be reachable from a Godot export build.

## For OpenCode specifically

You are the third reserve in this project's workflow — used when both Claude
and Codex hourly limits are exhausted. When you pick up a task:

- Read the current plan's ledger (`.superpowers/sdd/<plan>/progress.md`) fully
  before starting; `PLAN.md` gives direction, not the task list.
- Follow the same task-brief/report/review discipline the ledger already
  shows, even without the Claude tooling that generates brief files
  automatically — read the task's full text from its plan document under
  `docs/superpowers/plans/`, and write your own brief-equivalent notes into
  the ledger before starting if none exists yet for the task you're taking.
- Commit with the message format the task specifies
  (`type(scope): description`), and append your own ledger entry when done —
  don't leave your work undocumented for the next agent to rediscover cold.
