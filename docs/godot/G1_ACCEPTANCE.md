# Godot migration gate G1

**Decision:** `REVISE`

**Evidence date:** 16 September 2026

**Evaluated revision:** `fd245e33b8772cab6bc3651b86e683bb8264864d`

The vertical-slice architecture remains viable and the rendered Godot client is a clearer national dashboard than the reference client. G1 cannot proceed yet because a genuinely matched seeded journey is not reproducible across fresh client processes, unexpected command arguments can mutate state, an unexpected worker failure has no recovery path, and the required headed Windows scaling and live game-feel checks are incomplete.

## Matched journey

The acceptance probe used Vashtera, adopted `reduce_regional_inequality`, advanced from 1 March to 1 April 1993, inspected the three-line monthly digest, saved to an isolated temporary user-data directory, shut down the worker, started a fresh worker, and loaded the save.

With the random stream fixed inside one process, the direct Python route and the worker route produced byte-for-byte equal canonical serialized state. Both reported:

- date: `1 Apr 1993`;
- objective: `reduce_regional_inequality`;
- growth: `0.02581404202597694`;
- unemployment: `0.11025578739220691`;
- inflation: `0.048216`;
- debt/GDP: `0.64`;
- revenue: `12274.241594804611`;
- expenditure: `13059.418441126416`; and
- monthly explanation: three digest lines.

The fresh worker loaded the same date, objective, economy headline, and full Vashtera snapshot object (`id`, `pressure`, `unemployment`, and `state_reach`), then shut down with exit code `0` and no traceback.

This controlled comparison is not enough to pass the simulation condition. `new_campaign` accepts no campaign configuration or seed, and `CampaignConfig.resolved_seed()` uses Python's process-randomised `hash()`. Three fresh interpreters returned three different “default” seeds (`1672854011`, `1713842757`, and `1023534015`). The two clients therefore cannot currently be given the same explicit seed through the G1 command contract.

Region selection is presentation state, not authoritative campaign state. The Godot scene keeps its selected region while loading a save in the same client, but an arbitrary selection is not restored after client exit; a fresh client starts on its hard-coded Vashtera default. The probe proves that Vashtera's complete authoritative region snapshot survives save, worker exit, and fresh-worker load. It does not prove that the client's selected-region id survives application exit.

## Acceptance table

| Area | Result | Evidence |
| --- | --- | --- |
| Simulation | **REVISE** | Controlled direct-Python/worker routing produced identical serialized state after objective adoption and a monthly advance. A normal cross-process matched-seed run is not reproducible because the worker cannot receive a seed and the default seed changes between processes. |
| Safety | **REVISE** | Unknown commands raise `ValueError` without mutation. Invalid arguments do not: `advance_day` accepted `{"unexpected": true}` and advanced `day_index` from `0` to `1`. Per-command argument shapes are not enforced. |
| Reliability | **REVISE** | Invalid request-shape handling, clean worker/client shutdown, isolated save/load, and fresh-worker reload passed. An unexpected worker exit or malformed bridge response safely blocks mutation behind an error overlay, but `app.gd` sets the bridge dead and provides no retry or worker restart. Restarting the application is the only recovery path, so the gate's bridge-failure recovery condition is not met. |
| Readability | **REVISE** | Rendered captures and geometry checks passed at true 1920×1080 and 1280×720 with no overlap, viewport escape, or sub-44-pixel button. At 1280×720 Godot retained the map, region brief, objective, time controls, decision rail, and report; the Qt reference grew to 1280×780 and clipped the lower dispatch area. Actual Windows 125% and 150% display-scaling sessions were not run, so that part of the condition remains open. |
| Game feel | **REVISE** | Render inspection shows clearer selection, stronger map hierarchy, visible speed controls, an adjacent objective action, and a dedicated month-end report. The automated scene journey proves input and acknowledgement, but uses a deterministic fake bridge. A headed normal-user journey did not prove live decision arrival and month-end explanation against the reference client. |
| Performance | **PASS** | In the isolated worker run, startup was `148.755 ms`; 100 normal snapshot round trips had `10.088 ms` median and `11.644 ms` maximum latency. Automated interaction and rendered capture showed no visible stall. This is local development evidence, not packaged-build profiling. |
| Scope | **PASS** | The G1 branch changes only Godot presentation, bridge, test, launcher, generated map, ignore, and documentation paths. No file under `engine/`, `content/`, `models/`, `game_state.py`, or persistence/save schema changed. |
| Cost | **PASS (qualified)** | The map, panels, fake bridge, live bridge, and worker all reuse one protocol envelope, bounded snapshot composer, shared theme, and request path. More surfaces will require new allow-listed actions and snapshot fields, but no evidence yet requires a per-screen transport or formula duplication. |

## Observable client differences

- At 1920×1080, Godot makes the selected region, pressure layer, objective, date, speed, and monthly report readable in one view. The reference client devotes more space to the map and national statistics but requires separate navigation to reach the reform objective.
- At 1280×720, Godot deliberately removes the secondary national column and dispatch column while keeping the primary loop. The reference window reports an actual minimum height of 780 pixels when asked for 720, and the lower dispatch content is clipped in the captured frame.
- Godot's selected region is outlined and paired with a persistent regional brief. The reference client has denser map overlays and more national context, but its opening right panel still asks the player to select a region.
- The captured Godot frames use the scene test's clearly labelled synthetic fixture. They demonstrate layout and hierarchy only. Campaign correctness comes from the separate Python/worker parity and fresh-worker reload probes.

## Required revision before rerunning G1

1. Make the G1 campaign configuration and seed explicit at the `new_campaign` boundary, and add a fresh-process parity check that does not depend on resetting global RNG inside one interpreter.
2. Define allowed argument keys for every bridge command and reject extra or missing arguments before any mutation. Add a regression check proving the serialized state is unchanged.
3. Add a bounded retry/restart path for an unexpected worker or protocol failure, then prove the client can resume from a known authoritative state without silently continuing from stale presentation data.
4. Decide whether selected region must survive client restart. If yes, persist it as client settings/presentation state without changing the campaign save schema; if no, amend the G1 journey wording to require region-data read-back rather than selection persistence.
5. Run the real Godot and reference clients through the complete journey at 1920×1080, 1280×720, and actual Windows 125% and 150% scaling. Record a human check of decision arrival, action acknowledgement, and the live month-end explanation.

These are bounded G1 corrections. The evidence does not justify abandoning the Godot presentation path, changing the Python-authoritative architecture, or beginning complete presentation migration in parallel.

## Reproduction

Run the gate probe from the repository root. Exit `1` is expected at this revision because it reports the two automated gate failures rather than masking them:

```powershell
& "D:\Political Sim Game\.venv\Scripts\python.exe" scripts\g1_acceptance_probe.py `
  --capture-dir ".superpowers\sdd\2026-09-16-godot-foundation-and-vertical-slice\g1-captures"
```

Run the rendered Godot scene journey and capture both target sizes:

```powershell
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" `
  --path godot `
  --script res://scripts/tests/vertical_slice_test.gd `
  -- --capture-dir="D:\Political Sim Game\.worktrees\godot-foundation\.superpowers\sdd\2026-09-16-godot-foundation-and-vertical-slice\g1-captures"
```

The Godot scene test must exit `0`. The four local captures are evidence artefacts and remain outside the commit: `ardenia-1920x1080.png`, `ardenia-1280x720.png`, `qt-reference-1920x1080.png`, and `qt-reference-1280x720.png`.

## Progress since evaluation (revision `fd245e3`)

The table and evidence above are the historical record of what the probe found at `fd245e3`; they are left unedited. This section tracks closure of the "Required revision" list against later commits.

1. **Closed** (commit `528c22d`). `new_campaign` now accepts an optional integer `seed`; two independent worker processes given the same seed produce byte-for-byte identical serialized state (proven by spawning two real OS processes and diffing their snapshots, not by resetting RNG inside one interpreter). Omitting `seed` is unchanged — the CLI/GUI's existing per-launch-random default campaign is untouched.
2. **Closed** (commit `528c22d`). Every bridge command now validates its `args` against an explicit `ALLOWED_ARGS` allow-list before any state-mutating branch runs; `advance_day` no longer accepts `{"unexpected": true}`, proven by a test that snapshots state before and after a rejected call.
3. **Closed** (commits `32b7602`, `3bf912c`, `111f7a8`; independently reviewed, one fix round). `SimulationBridge` gained a bounded `reconnect()` (3 lifetime attempts, refreshed after any genuinely healthy round trip); the app shows a Reconnect control while attempts remain, clears the stale in-memory snapshot on a successful respawn (the old campaign lived only in the dead process), and resumes from a known state — this client's own last save, or a fresh campaign if there is none. Exhausted attempts surface a permanent, non-recoverable failure instead of retrying forever. The first review round (against `32b7602`) returned REQUEST CHANGES: `_attempt_recovery()` cleared the snapshot *data* but not the rendered widgets, leaving the pre-crash dashboard visibly on screen for one IPC round trip — exactly the failure mode this finding names; the recovery-success test could pass vacuously (both sides of its equality check were the same untouched fixture); and the fake bridge's scripted failure emitted a frame late, skipping the reentrancy the real bridge's synchronous failure path has to survive. `111f7a8` fixed all three (plus a log-truncation issue found in the same pass) and added a direct check that the dashboard clears synchronously, before the load response arrives. Proven by four headless scenarios: one failed respawn then a successful one recovering via `load` to a state proven to differ from the pre-crash baseline, exhausted attempts showing no retry control, a `load` against no saved state falling back to `new_campaign` with a genuine fresh snapshot, and the immediate (pre-response) clearing of the rendered dashboard.
4. **Closed by ruling, no code change.** *Ruling:* selected region does **not** need to survive a client restart. It is presentation state, not authoritative campaign state (Global Constraint: "Godot presentation state may cache selection and layout only; authoritative campaign state remains in Python"), and the vertical-slice scope has no other client-settings persistence surface to justify adding one for this alone. The G1 journey's actual requirement is read-back of the underlying region data after reload, which the matched-journey probe already proves ("the probe proves that Vashtera's complete authoritative region snapshot survives save, worker exit, and fresh-worker load" — see "Matched journey" above); it does not, and need not, prove that the UI's selected-region id itself survives an application exit. *Cost if wrong:* if a future review decides selection persistence matters for player experience, it is additive (a small client-settings file) and does not require touching the campaign save schema — nothing here forecloses it.
5. **Open — requires a person at a real Windows display.** Actual Windows 125%/150% display-scaling sessions and a live human game-feel check (decision arrival, action acknowledgment, month-end explanation) against the reference client were not run. This is a genuine limit of what an agent can produce: OS-level display scaling is a system-wide setting change outside this worktree, and "game feel" is a human judgment call by design — the spec deliberately keeps it a human acceptance check separate from the automated gates. Rendered captures and headless geometry checks at true 1920×1080 and 1280×720 remain the automated evidence; they do not substitute for this item.

**Net:** 4 of 5 required revisions are closed. Item 1/2 (Task 8) reviewed clean (APPROVE, only deferred minors). Item 3 (Task 9) went through one fix round after its first review (REQUEST CHANGES); the fixes are committed and re-verified by the automated headless suite, with a scoped re-review of the fix diff pending. Item 4 is closed by ruling, not code. The gate decision remains `REVISE` until item 5 is run — that rerun is a short, bounded activity for a human at the actual machine, not further engineering.

## Distribution risk

G1 remains a developer hybrid. It requires the repository virtual environment and installed Godot editor; no clean-machine executable was produced or claimed. Worker bundling, private runtime paths, console suppression, protocol compatibility, clean-machine launch, and release size remain G4/G5 risks. Nothing from this gate is suitable for public or tester distribution.
