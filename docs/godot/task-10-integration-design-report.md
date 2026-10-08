Source and numbered PLAN references describe the audit-start snapshot at HEAD 3fc8f10. Concurrent plan corrections observed before handoff now fix digest return type to Array[String], household count to 54 and integration task span to Tasks 5-10; those observations below are resolved plan defects, not outstanding production implementation.

# Task 10 integration design brief

## Scope

This is a read-only source audit and implementation contract. Task 9 remains a prerequisite. The Python engine is a design reference; Task 10 ports only Phase 2's monthly economic and social pulse, not the later political/world loop.

## Monthly transaction boundary

Keep one synchronous monthly operation behind `NativeGame.advance_day()`. Its existing busy guard must cover calendar mutation, the complete pulse, snapshot generation and signal emission. A non-rollover day must not mutate monthly ledgers, age modifiers, increment the turn or replace the completed report.

At a monthly rollover:

1. Advance the calendar once.
2. Capture detached numerical before-values through `MonthlyDigest.capture(state)` after rollover and before monthly mutations.
3. Increment `state.turn` exactly once. `Calendar.advance_day()` does not do this itself.
4. Run, once and in order: `BudgetSim.process_fiscal_year` -> `PoliticalCapital.regenerate` -> `MinistriesSim.simulate` -> `EconomySim.update` -> `RegionsSim.simulate` -> `HouseholdsSim.simulate` -> `StabilitySim.update_approval` -> `StabilitySim.update_stability` -> `Modifiers.age_all`.
5. Build the completed report from the captured before-values and committed after-state, store it in `state.monthly_digest`, then publish the ordinary UI snapshot.

Effects must be consumed before ageing; the last active month remains payable. UI reads, save/load and signal subscribers must not trigger simulation.

## Approval and stability contract

Use existing native fields directly: economy values, player approval and role, factions' power/loyalty/seats/cohesion/grievances, ministers' loyalty/traits/threat levels, regional pressure, household confidence/hardship, modifiers and coalition membership. Do not add a dummy Legislature or Cabinet class before Phase 3.

Approval follows the current design-reference weights: economic signal, power-weighted faction loyalty, household mood and approval-bias modifiers, bounded to 0.05..0.95 before the 5% monthly movement. Household mood reverses only for an opposition player's approval; do not reverse economic conditions.

For stability, compute only from live native data: coalition loyalty, minister loyalty plus capped grandee effect, allocated faction-seat margin, approval, economic conditions, minister threat, deterministic unrest and coalition cohesion. Use the existing design-reference weights, target range 0.05..0.95, and 6% movement toward target. Clamp final approval/stability values to 0..1 and reject non-finite state at the validation boundary.

Opposition policy must be explicit. Player approval and faction loyalty describe the player, not the incumbent; the factory can also retain a stale authored cabinet. Until Phase 3 creates a real incumbent-government model, use neutral contributions for player-relative coalition/cabinet/approval terms, disable stale-cabinet dysfunction, and retain real seat margin, cohesion, economy and unrest. Diagnostics must name these as unavailable neutral terms, never as observed incumbent support.

## Digest, persistence and snapshot data

`godot/scripts/app.gd` consumes `snapshot.digest` as an array of lines. Retain the corrected plan contract: `MonthlyDigest.build(state, before) -> Array[String]`, with a pure `capture(state) -> Dictionary` helper. The digest is pure: no simulation mutation, logging or RNG use; a quiet month returns an empty array.

Add `GameState.monthly_digest: Array[String] = []`, serialise/deserialise it, default older saves missing it to an empty report, and reject malformed present data. Persist completed lines, not an opaque cache or large before/after snapshots. This additive save-schema change is now explicitly owned by Task 10 and covered in `test_native_persistence.gd`.

`NativeGame._build_snapshot` should return detached read models only: active budget, committed ministry capacity/workload/delivery/backlog, national household summaries, and numeric stability alongside its label. Snapshot generation must not call preview/simulate/ensure methods or derive gameplay in UI code.

## Frozen regional programmes

When a separatist region freezes a programme, do not advance delivery or programme progress. Preserve committed treasury cost by extending only the matching finite `budget_expenditure` modifier for that programme by one hold month before normal ageing. Unrelated or infinite modifiers must remain untouched. The test matrix must cover prolonged freeze, recovery, completion, unrelated expiry and save/load while frozen.

## Integration proof

Use real `GameFactory`, `NativeGame.advance_day`, save/load and snapshot paths. Tests must prove actual movement, not merely a changed date:

- ordinary day versus month rollover;
- March rollover plus December-to-January fiscal activation;
- budget, political capital, ministries, economy, regions, 54 households, approval and stability each run exactly once;
- economy-to-region-to-household and household-to-approval-to-stability ordering;
- modifier end-points and frozen-programme funding;
- deterministic same-seed replay with no RNG use by reporting/read models;
- save immediately before and immediately after a pulse without double application;
- save/load preservation of the completed report;
- safe empty ledgers, zero seats/power, extreme finite values and reentrant signal callbacks.

## Carry-forwards

Before claiming Phase 2 integration complete, decide whether to correct Task 6's now-stale unweighted regional-pressure helper and omitted regional-programme workload. If not corrected in Task 10, record them as explicit temporary deviations rather than describing the result as full reference behaviour. EconomySim currently does not change public debt monthly; tests should assert its current preservation rather than inventing debt dynamics.