# Native port status

> **DIRECTION CHANGED 2026-09-16 — read `PLAN.md` at the repository root.**
> The `N0`–`N6` parity programme is cancelled. N0's test harness survives and is
> still the native test runner; its oracle fixtures, comparator, and parity
> matrix are retired. Entries below remain as the historical record. See the
> final entry for what this means for the next owner.

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

*(Superseded by the entry below — the N0 gate no longer needs to close, because the programme it gated is cancelled.)*

## 2026-09-16 — programme direction changed — parity contract cancelled

- Base: `63eebea` (Codex's in-flight N0 final-review work, committed verbatim and unreviewed so it would not be lost when its credits ran out).
- Result: the `N0`–`N6` native-rewrite parity programme is **cancelled** by the project owner. Ardenia is being remade in Godot as a game — assets, mechanics, UI — with the Python implementation as a *design reference to read*, not an oracle whose arithmetic must be reproduced.
- Rationale: proving `1e-9` cross-language numerical equivalence across ~16,000 lines is a substantially larger project than building the game, and it bought nothing — there are no existing players whose saves need migrating. Godot's own documentation also states float math is not guaranteed deterministic across CPUs, operating systems, or versions, so the tolerance target may not have been reachable.
- Files: `PLAN.md` (new, repository root — current authority), `docs/godot/NATIVE_REWRITE_AGENT_GUIDE.md` and this file (superseded banners), master plan and design spec (superseded banners).
- Survives the change: `godot/scripts/native/testing/test_support.gd` and `godot/tests/native/run_contract_tests.gd` remain the native test harness — useful regardless of the parity question.
- Retired, retained as audit trail, **not deleted**: `PARITY_MATRIX.md`, `godot/data/native/fixtures/`, `scripts/native_port/compare_native_snapshot.py`, `scripts/native_port/export_oracle_fixtures.py`, and the six `2026-09-16-native-godot-phase-*.md` plans.
- Tests: none run for this entry; it is a documentation and direction change only.
- Parity rows: none. The matrix is no longer a gate.
- Review: pending — cross-model plan review by Codex is deferred until its credits reset, at which point it will be pointed at `PLAN.md` to course-correct.
- Remaining risk: an agent resuming from the old phase plans without reading `PLAN.md` would continue building retired infrastructure. Banners were added to every document in the old required-reading order to prevent that.
- Next owner: Phase 1 of `PLAN.md` — native content export, typed GDScript state, campaign creation, calendar, RNG, persistence, and cutting the bridge out of the running app.
