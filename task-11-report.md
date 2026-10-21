# Task 11 report — regional programme player action

## Result

Ardenia's native Godot build now supports one complete government action loop:
select a region, choose an authored programme, spend political capital, observe
the active commitment, advance through monthly delivery, save, reload, and
continue delivery. Eligibility and all effects are owned by the native action
service; the UI renders detached snapshot data only.

## Scope

- Added `RegionalProgramActions` as the sole rules/effects owner.
- Added guarded `NativeGame.start_regional_program` signaling.
- Added programme option and active-commitment region read models.
- Replaced the disabled region-action placeholder with a real selector,
  status, and 44 px launch control.
- Kept the compact 1280x720 layout usable by condensing live pressure,
  unemployment, and state-reach metrics beside programme choice and launch.
- Added focused service, NativeGame, monthly, save/load, re-entry, and real-app
  journey coverage.

No balance values, authored content, persistence schema, Python mechanics, or
other Phase 3 systems changed.

## Verification

All commands ran from `D:\Political Sim Game\.worktrees\godot-foundation`.

- `Godot --headless --path godot --script tests/native/test_regional_program_actions.gd`
  — exit 0; 34 passed, 0 failed.
- Every `godot/tests/native/test_*.gd` suite — exit 0; 4,086 passed, 0 failed.
- `Godot --headless --path godot --script tests/native/run_contract_tests.gd`
  — exit 0; 96 passed, 0 failed.
- `Godot --headless --path godot --script scripts/tests/vertical_slice_test.gd`
  — exit 0; 1920x1080 and 1280x720 journeys passed, including a live-metric
  resize check, real UI launch, monthly delivery, save/load, and continued
  delivery.
- `D:\Political Sim Game\.venv\Scripts\python.exe smoke_test.py`
  — exit 0; full Python smoke suite passed.
- `git diff --check` — exit 0; only line-ending notices, no whitespace errors.

The first test run failed because the action service did not yet exist, which
records the required red phase. Later focused failures caught a typed-GDScript
inference warning and the new controls exceeding the 720p height; both were
fixed before the full gate.

## Independent review

Review round one found three Important gaps: inaccessible reasons on disabled
options, private-state proof instead of a complete public real-scene journey,
and hidden compact regional metrics. Commit `fbed69c` made rejected options
inspectable, moved assertions to detached snapshots, and extended the journey
through monthly delivery and save/load continuation.

A fresh re-review then found one resize edge case: switching an already-open
1920x1080 campaign to 1280x720 retained the non-compact status while hiding the
detail controls. Commit `01bba54` refreshes the selected region at the resize
boundary and pins the exact transition in the real-scene test. The same commit
restores `task-11-brief.md`.

Final independent verdict: **APPROVE**, with 0 Critical and 0 Important findings.

## Verification notes

The final post-review gate was rerun after `01bba54`: 4,086 native assertions,
96 contract assertions, the real scene at both target resolutions, and the
Python smoke suite all exited 0. `git diff --check 4cef5dc..01bba54` was clean.

One batched test wrapper returned before its spawned `NativeGame` child. A
second run briefly collided with the first run's test-only save slot and
reported two false failures. The owned child was identified, allowed to finish,
and the suite was rerun alone: 102 passed, 0 failed. No production state or
player save was involved.
