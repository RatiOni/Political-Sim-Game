# Task 9 plan-corrections report

This report records the source facts checked before making the documentation-only
corrections in `PLAN.md` and `docs/godot/AGENT_GUIDE.md`.

| Source fact | Correction made |
| --- | --- |
| `content/households.py` defines six household groups and nine authored Ardenian regional distribution entries; the exported `godot/data/native/catalogs/household_groups.json` carries the same nine regional entries. | Replaced Phase 2's incorrect 36-household wording with 54 records, explicitly six groups across nine authored Ardenian regions. Corrected Task 9's read-first prose and failing-test wording, and the Phase 2 performance risk wording. |
| `godot/scripts/app.gd` reads `snapshot["digest"]` as an array and formats its rows in `_lines`; `godot/scripts/native/native_game.gd` currently exposes the bridge-era `digest: []` snapshot stub. | Changed `MonthlyDigest.build` to return `Array[String]` and stated that it supplies the snapshot digest array for UI formatting only. |
| `godot/scripts/native/state/game_state.gd` already holds factions, ministers, economy, regions, households, ministries, and annual-budget state, while its header explicitly defers `Legislature` and the Cabinet wrapper to later work. | Made Task 10 require stability/approval to use the existing native state directly, prohibit inventing `Legislature` or `Cabinet` before Phase 3, and preserve deterministic bounded outputs. Added the read-only budget, ministry, and national household-summary snapshot boundary; UI formats only. |
| `.superpowers/sdd/PLAN/progress.md` records Task 8 complete and carries the separatist programme freeze's modifier hold-window issue into Task 10, preferring a modifier-window extension or an explicit accepted slip. | Added the Task 8 carry-forward and Task 10 resolution/test requirements, with modifier-delivery-window extension during frozen months as the preferred action. |
| `.superpowers/sdd/PLAN/progress.md` is the ledger and records Tasks 5-8 complete, Task 9 next/unclaimed, and Task 10 after it; `AGENT_GUIDE.md` still said Phase 1 Tasks 1-4 were active. | Updated the guide to the actual Phase 2 state without claiming Task 9 complete, while retaining ledger and `git log` as authority. |
| `PLAN.md` still contained obsolete operational instructions for `godot-native/rebuild` and `STATUS.md`; the active branch and ledger are `codex/godot-foundation` and `.superpowers/sdd/PLAN/progress.md`. | Replaced only those obsolete operational references with the active branch and ledger. |
## Fix round 1

- Made Task 10 explicitly own and require the additive persisted `monthly_digest: Array[String]` field in `game_state.gd`, its serialisation/deserialisation, and native persistence coverage. Completed report lines must survive save/load; older saves default to an empty array.
- Reconciled the integration report with the already-corrected `MonthlyDigest.build(...) -> Array[String]` contract and Tasks 5-10 span, distinguishing resolved plan defects from outstanding production work.
- Corrected Task 8's remaining test wording to nine authored regions and aligned the integration report with 54 household records.
- Replaced brittle source and plan line references with file, section, and function references, and prepended the required audit-start snapshot note.
- Validation: `git diff --check` passed after the correction.