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
- Kept the compact 1280x720 layout usable by collapsing secondary regional
  diagnostics while retaining programme choice and launch.
- Added focused service, NativeGame, monthly, save/load, re-entry, and real-app
  journey coverage.

No balance values, authored content, persistence schema, Python mechanics, or
other Phase 3 systems changed.

## Verification

All commands ran from `D:\Political Sim Game\.worktrees\godot-foundation`.

- `Godot --headless --path godot --script tests/native/test_regional_program_actions.gd`
  — exit 0; 34 passed, 0 failed.
- Every `godot/tests/native/test_*.gd` suite — exit 0; 4,085 passed, 0 failed.
- `Godot --headless --path godot --script tests/native/run_contract_tests.gd`
  — exit 0; 96 passed, 0 failed.
- `Godot --headless --path godot --script scripts/tests/vertical_slice_test.gd`
  — exit 0; 1920x1080 and 1280x720 journeys passed, including real UI launch.
- `D:\Political Sim Game\.venv\Scripts\python.exe smoke_test.py`
  — exit 0; full Python smoke suite passed.
- `git diff --check` — exit 0; only line-ending notices, no whitespace errors.

The first test run failed because the action service did not yet exist, which
records the required red phase. Later focused failures caught a typed-GDScript
inference warning and the new controls exceeding the 720p height; both were
fixed before the full gate.
