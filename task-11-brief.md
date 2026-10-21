# Task 11 brief — regional programme player action

## Objective

Make one existing government action playable end to end in the native Godot
build: select an Ardenian region, launch one authored regional programme,
observe its existing monthly effects, save, reload, and continue delivery.

## Ownership

- `RegionalProgramActions` owns eligibility, cost, validation, and effects.
- `NativeGame` owns campaign mutation, the in-flight guard, and signaling.
- The app renders detached snapshot data and submits stable region/program ids.

## Required behavior

- Deterministic programme options with backend-owned disabled reasons.
- Atomic rejection for unknown ids, opposition play, incompatible or blocked
  regions, insufficient political capital, and duplicate active programmes.
- Exact-cost launch, immediate authored launch effects, one stable programme
  instance, and one finite non-institutional treasury modifier.
- Exactly one state-change emission on success, none on failure, and guarded
  re-entry.
- A real 44 px UI action that remains usable at 1920x1080 and 1280x720.
- Public-API proof of launch, monthly delivery, save/load restoration, and
  continued delivery through the real app scene.

## Non-goals

No new balance values, authored content, save fields, simulation formulas,
legislation, cabinet actions, events, elections, diplomacy, or world behavior.
Python remains a read-only design reference.

## Verification gate

Run every native `test_*.gd`, the contract runner, the real vertical-slice
journey at both acceptance resolutions, the full Python smoke suite, and an
independent review of the saved implementation diff.
