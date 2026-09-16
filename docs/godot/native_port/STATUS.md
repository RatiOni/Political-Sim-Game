# Native port status

- Planning baseline: `6c794f6e56810c757de0644e856280ed59c78814`
- Active branch: `codex/godot-foundation` in an isolated linked worktree. The user's root checkout is dirty and remains protected.
- Toolchain: Godot `4.7.2.stable.official.ed1daf0bf`; Python `3.14` is development-only.
- Active phase: N0 — contract and oracle.
- Current disposition: final-review fixes are being integrated. N0 is not complete until the repaired phase suite and focused independent re-review both pass.

## 2026-09-16 — N0 Task 1 — native test harness and ledgers

- Base: `6c794f6`; accepted in `13da70c`.
- Result: the dependency-free Godot contract runner and the initial native-port ledgers exist.
- Files: `godot/scripts/native/testing/test_support.gd`, `godot/tests/native/run_contract_tests.gd`, `docs/godot/native_port/PARITY_MATRIX.md`, and this status file.
- Verification: the deliberate failing assertion exited non-zero; the final runner passed `3` checks; the existing Godot vertical-slice suite passed.
- Review: accepted after independent review; no open Critical or Important finding.
- Next owner: N0 Task 2 fixture exporter, then any native phase owner using the runner.

## 2026-09-16 — N0 Task 2 — canonical oracle fixtures

- Base: `13da70c`; accepted through `fd3c77d` after one review-fix round.
- Result: deterministic government and opposition opening-state fixtures, plus a manifest, are generated from the Python oracle.
- Files: `scripts/native_port/export_oracle_fixtures.py`, `godot/data/native/fixtures/`, and `godot/tests/native/run_contract_tests.gd`.
- Verification: exporter self-test and repeated generated-fixture diff check passed; contract runner passed `95` checks; Python smoke and Godot vertical-slice suites passed.
- Review: accepted after the determinism and opening-role assertions were strengthened; no open Critical or Important finding.
- Next owner: N0 Task 3 comparator and N1 owners consuming the frozen fixtures. Change fixtures only through the exporter.

## 2026-09-16 — N0 Task 3 — cross-runtime parity probe

- Base: `fd3c77d`; accepted in `cfef6cd`.
- Result: Godot can emit a fixture snapshot and the development-only comparator checks it recursively against the oracle, including the documented numeric tolerance.
- Files: `scripts/native_port/compare_native_snapshot.py`, `godot/tests/native/emit_fixture_snapshot.gd`, and `docs/godot/native_port/PARITY_MATRIX.md`.
- Verification: comparator self-test passed; an emitted government snapshot matched; a deliberate GDP change failed at `$.country.economy.gdp`; contract runner, bridge, Python smoke, and Godot vertical-slice suites passed.
- Review: accepted after independent review; no open Critical or Important finding at task scope.
- Next owner: N0 final-fix owner, then N1 native state foundation. Treat the three `n0.*` parity rows as infrastructure proof only, not native simulation parity.

## Remaining N0 gate

The N0 final review identified fixes now being integrated. Re-run the active N0 verification suite and obtain focused independent re-review of those fixes before marking this phase complete. The next phase must start only from that accepted result.
