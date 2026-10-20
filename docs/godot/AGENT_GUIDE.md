# Ardenia Godot rebuild — agent guide

This is the common working contract for Claude, Codex, OpenCode, and human
contributors on the Godot rebuild. It replaces
`docs/godot/NATIVE_REWRITE_AGENT_GUIDE.md`, which governed the now-cancelled
parity-contract programme.

## Required reading order

1. `PLAN.md` (repository root) — the plan and its rationale. Read the
   **Context** section first if you touched anything under
   `docs/superpowers/plans/2026-09-16-native-godot-*` or
   `docs/godot/native_port/` before now — it explains what changed and why.
2. `AGENTS.md`
3. `docs/EARLY_ACCESS_MISSION.md` — product authority: what Ardenia is, who
   plays it, what "done" looks like as a game.
4. `.superpowers/sdd/PLAN/progress.md` — the ledger. Task lines marked
   `complete` are done; do not re-dispatch or redo them. A line ending in a
   fix round is mid-loop; resume at the next round. Trust this file and
   `git log` over any memory of your own — sessions get compacted or run out
   of budget mid-task.

## What this project is, in one paragraph

Ardenia is a political simulation currently in Python (`engine/`, `content/`,
`models/`) with a PySide6 desktop front-end. It is being rebuilt as a native
Godot 4.7.2 game — real assets, mechanics, UI, no Python at runtime. **The
Python source is a design reference to read, not an oracle to match
numerically.** There is no parity contract, no fixture comparison, no `1e-9`
tolerance. Write idiomatic GDScript that does the same job the Python code
does; don't transcribe it, and don't chase bit-for-bit equivalence.

## Canonical starting point

Work happens on branch `codex/godot-foundation`. If you're picking this up
fresh: `git status --short` and `git log --oneline -5` first, so you know
whether you're resuming mid-task or starting clean. This repository's shared
worktree for this branch is `D:\Political Sim Game\.worktrees\godot-foundation`
— use it directly; do not create a separate isolated worktree for a task that
the ledger expects to land on this branch. Never work in the user's root
checkout (`D:\Political Sim Game`) — it is a separate, dirty, protected
checkout.

## Coordination

- Only one phase of `PLAN.md` is active at a time (currently: **Phase 3**).
  Tasks 5-10 are complete; **Task 11 (the regional-programme player-action
  slice) is next**. Read `.superpowers/sdd/PLAN/progress.md`
  and `git log` before acting; the ledger and committed work always override
  this guide when they disagree.
- Within a phase, parallel work is fine only when file ownership doesn't
  overlap and the task breakdown marks the tasks independent. Phase 2's tasks
  are ordered by the monthly pulse and consume the earlier systems — preserve
  that sequence unless the ledger records an explicit, non-overlapping split.
- `native_game.gd`, `content_repository.gd`, and any file two tasks would
  both need to edit have one owner at a time. Check the ledger before
  touching a file another task's entry claims.
- Each task ends with its own focused test, a commit, and an independent
  review (spec compliance + code quality) before the next task starts.
- Critical and Important review findings are fixed (or explicitly ruled on
  and parked, per the SDD fix-loop process) before the next task begins.
  Minor findings are recorded in the ledger with a disposition, not silently
  dropped.
- Generated JSON under `godot/data/native/` is written only by its exporter
  script (`scripts/native_port/export_native_content.py` from Phase 1 Task 1
  onward) — never hand-edited.
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

## Runtime prohibition

The final game ships with no Python installation, no PySide, no worker
process, and no repository path baked into it. Development scripts (content
exporters, the retained N0 test harness) may use Python or reference the
repository during development only. No development-only path may be
reachable from a Godot export build.

## For OpenCode specifically

You are the third reserve in this project's workflow — used when both Claude
and Codex hourly limits are exhausted. When you pick up a task:

- Read the ledger (`progress.md`) fully before starting; don't assume the
  task list in `PLAN.md` alone tells you what's already done.
- Follow the same task-brief/report/review discipline the ledger already
  shows, even without the Claude tooling that generates brief files
  automatically — read the task's full text directly from `PLAN.md`, and
  write your own brief-equivalent notes into the ledger before starting if
  none exists yet for the task you're taking.
- Commit with the exact message format the task specifies in `PLAN.md`
  (`type(scope): description`), and append your own ledger entry when done —
  don't leave your work undocumented for the next agent to rediscover cold.
