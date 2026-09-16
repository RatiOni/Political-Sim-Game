# Native rewrite agent guide

This file is the common working contract for Claude, OpenCode, Codex, and human contributors.

## Required reading order

1. `AGENTS.md`
2. `docs/EARLY_ACCESS_MISSION.md`
3. `docs/superpowers/specs/2026-09-16-native-godot-rewrite-design.md`
4. `docs/superpowers/plans/2026-09-16-native-godot-rewrite-master.md`
5. the active phase plan
6. `docs/godot/native_port/STATUS.md` and `PARITY_MATRIX.md`

## Canonical starting point

Start from branch `codex/godot-foundation` at or after `e4cffca`. Before changing code, record `git rev-parse HEAD`, `git status --short`, Godot version, and the active phase in `STATUS.md`. Use a linked worktree and a `godot-native/nN-description` branch. Never work in the user’s dirty root checkout.

## Coordination

- Only one phase is active at a time.
- Within a phase, parallel work is allowed only when file ownership does not overlap and the phase plan marks the tasks independent.
- `native_game.gd`, `monthly_pulse.gd`, `state_codec.gd`, `content_repository.gd`, and `PARITY_MATRIX.md` each have one owner at a time.
- Each task ends with a focused test, the phase suite, `git diff --check`, a commit, and a separate review.
- Critical and Important review findings are fixed before the next task. Minor findings are recorded in `STATUS.md` with an explicit disposition.
- Generated JSON and fixtures are changed only through their exporter command.
- Do not delete or rewrite unrelated user changes. Do not merge, push, tag, or publish without explicit authorization.

## Handoff entry

Append this exact structure to `STATUS.md` after each accepted task:

```markdown
## YYYY-MM-DD — N2 Task 3 — households
- Base: `<commit>`
- Result: accepted / revise
- Files: `<paths>`
- Tests: `<commands and pass counts>`
- Parity rows: `<ids moved to PASS>`
- Review: `<reviewer and disposition>`
- Remaining risk: `<specific evidence gap or none>`
- Next owner: `<task name>`
```

## Definition of done

“Implemented” means the native code exists. “Accepted” means its parity rows pass, state round-trips, the full active-phase suite passes, and an independent review has no open Critical or Important finding. Only accepted work may be consumed by the next phase.

## Runtime prohibition

The final game must run with no Python installation and no external worker. Development scripts may use Python only to extract oracle fixtures, compare states, and import legacy saves. No development-only path may be reachable from a Godot export.
