# International Gameplay 2: Energy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put the Zovar gas contract into the simulation: a persisted `GasContract`, a seasonal monthly flow whose shortfalls hurt households, Zavost/Darev industry, state reach and stability, a supplier that coerces through the world AI by leverage, the Union's real gas benefits, seven player operations, the map hand-off, the Diplomacy desk energy section, and a full re-run of every calibration band.

**Architecture:** `GasContract` hangs off `ForeignState.gas`, so it persists and validates with the foreign ledger. `GasSim` owns the contract mechanics: seeding from a new native catalog `catalogs/energy.json`, the monthly flow inside `ForeignSim.monthly`, renewal, the supplier's coercion ladder (called from `WorldSim._execute` when the supplier's undermine plan matures) and the read-only effect terms that `EconomySim`, `RegionsSim`, `HouseholdsSim` and `StabilitySim` add to their existing targets. `EnergyActions.act(state, verb)` holds the seven input-free player operations; the GUI reaches it through `NativeGame.energy_act`.

**Tech Stack:** Godot 4.7.2, statically typed GDScript, headless `SceneTree` test scripts using `TestSupport`.

**Spec:** `docs/superpowers/specs/2026-10-29-international-gameplay-design.md` (this plan is delivery item 2, section 3 "Energy", plus the Union gas benefit plan 1 deferred). Plan 1 as built: `docs/superpowers/plans/2026-10-29-intl-1-orientation.md`; its ledger `.superpowers/sdd/2026-10-29-intl-1-orientation/progress.md` and `final-fix-report.md`.

## Global Constraints

- `G="/d/AI Stuff/Godot/Godot_v4.7.2-stable_win64_console.exe"`. Run everything from `/d/Political Sim Game/.worktrees/godot-native-sim`.
- Every test command is `timeout 180 "$G" --headless --path godot --script res://...` and must print `NATIVE TESTS: N passed, 0 failed` with no `SCRIPT ERROR`. A script that fails to compile never quits headless, so a timeout (exit 124) with `SCRIPT ERROR` is the expected "red" for a test that references code that does not exist yet.
- Run `timeout 180 "$G" --headless --path godot --import` after adding any file, then `git add` the generated `.uid` files with it.
- The full battery runs after every task, and every line must report 0 failed with no `SCRIPT ERROR`, `EXIT` or `FAIL` line (the vertical slice prints `PASS:` lines and must exit 0). `PENDING` lines are allowed only for the two bands already pending at plan start:

```bash
G="/d/AI Stuff/Godot/Godot_v4.7.2-stable_win64_console.exe"
for f in godot/tests/native/test_*.gd godot/tests/native/run_contract_tests.gd godot/tests/ui/test_*.gd godot/tests/map/test_*.gd godot/scripts/tests/vertical_slice_test.gd; do
  out=$(timeout 180 "$G" --headless --path godot --script "res://${f#godot/}" 2>&1); code=$?
  echo "$f: $(echo "$out" | grep -E 'NATIVE TESTS|SCRIPT ERROR|FAIL|PENDING' | tr '\n' ' ')"
  [ $code -eq 0 ] || echo "EXIT $code: $f"
done
```

- Mutation-check every new test: break the guarded line named in the task, rerun that test file, see the named assertion fail, restore the line, rerun green. Each task lists its mutations, and they always include the boundary (`>=` vs `>`, the first and last heating month) and the real-calendar timing (a calendar-true `NativeGame.next_month` test must fail when the phase runs a month early or late). A mutation that survives is a missing test: add it before moving on.
- No explanatory comments in new code (the owner's hard rule). No `#` comment lines, no doc comments.
- Determinism: never roll an outcome. Energy draws no RNG at all; every gas outcome is a function of tracked state. Any RNG comes only from `state.rng` (the saved campaign stream).
- Persistence: every new field round-trips through `SaveStore` (binary `store_var` of `to_dict`), and saves without the new data load with defaults (`ForeignSim.ensure` seeds the contract). `StateValidator` rejects non-finite or negative quantities, shares outside 0..1, turns in the future, an unknown supplier, storage above capacity, an impossible threat, an oversized payment history, unknown concessions and a Union member's price above the cap.
- Tests never use save slot `godot_slice`. Each test file that saves uses its own slot named after the file and wipes `.json`, `.json.tmp` and `.json.bak` afterwards.
- UI follows the existing desk conventions (`app.gd` refresh pattern, `REFUSED / reason` status, disabled buttons carry their reason as tooltip and a `Muted` label) and the pixel UI system: no new colours outside `UiPalette`, bars only for bounded 0..1 higher-is-better values, nothing on the desk changes size when the state changes (buttons `clip_text`, labels wrap inside the fixed desk width).
- Other chats commit to this branch. Stage only the files your task names (`git add <paths>`), never `git add -A` or `git add .`.
- Calibration bands are never widened. Task 8 is the only task that re-measures them, by the procedure it states.
- Commit messages are conventional (`feat:`, `test:`, `docs:`) and end with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Rulings on spec gaps (binding for this plan)

1. **Units.** Volume is in bcm a year, price in million kron per bcm, money in the budget's million-kron units. Ardenia's seed: demand 6.0, contracted 6.0, price 50.0, arrears 40.0 (canon: hard currency the country does not have), take-or-pay 0.8, first renewal at turn 22 (January 1995). The bill is about 300 a year, 0.6% of GDP.
2. **Who pays.** The budget carries the contract, and the treasury settles only `PAYMENT_SHARE` (0.85) of each bill in hard currency. The rest accrues as arrears. The budget line is the rolling twelve-month total of what was actually paid, so the winter peak does not spike the deficit that the January and October ISF reviews read. Arrears payments and spot cargoes are one-time debt (`one_time_debt_pct_delta`). Storage and the second line are timed `budget_expenditure` modifiers.
3. **Season.** The monthly weight is 1.5 from October to March and 0.5 from April to September, and the twelve weights sum to 12. The flow uses `state.month` at `close_month`, the month just begun. The supply ratio is the share of demand met. The effects read **severity** = shortfall × weight / 1.5, so the same cut hurts three times more in January than in July. Storage injects in summer and draws in any month with a gap.
4. **Effects are read terms, not modifiers.** Like `trade_revenue_contribution`, the gas terms are added inside the existing targets: `EconomySim` growth (`GasSim.growth_effect`) and expenditure (`GasSim.budget_cost`); `RegionsSim` reach and unemployment targets; `HouseholdsSim` hardship target; `StabilitySim` gets a new "Energy supply" component. This creates no modifier churn, stays bounded, and keeps the convergence each system already has. Regional exposure comes from the catalog (Zavost 1.5, Darev 1.3, the default 1.0). Only Zavost and Darev lose jobs. Separatist territory reads zero exposure, because Krasova supplies it directly.
5. **Supplier ladder.** It runs inside the supplier's world-AI plan: when Krasova's `undermine` plan against the player matures, `GasSim.coerce` takes the move, and otherwise the generic hostile action runs. The rungs are a **demand** for the arrears (arrears ≥ 60; at most every 6 months); then a **threat** (two or more months after a demand, arrears still ≥ 60, leverage ≥ 0.5, no cut in the last 24 months). The threat names next month, and its share is 0.4 × leverage. At maturity the threat becomes a two-month **cut**, unless the arrears have been paid below 30 or a cut is blocked. Leverage ≥ 0.5 in practice means the heating season ("it has mentioned the valve"). Defence pacts and the Meridian guarantee do not shelve gas moves.
6. **Renewal.** When `turn ≥ term_end`, the new price is `reference × (1 + 0.4 × leverage)`, the term runs 36 months, and the contracted volume falls by the second line's volume.
7. **Union gas benefit.** On joining, the price is capped at 0.7 × the reference and half the arrears are rescheduled away. The cap also holds at every renewal. A member cannot be cut, and any running cut ends, unless there is a crisis. Until plan 4 adds tension, a crisis means Krasova warmth < −0.5. On leaving, the price is at least 1.2 × the reference and the term restarts. Cheaper gas also lifts growth (`PRICE_GROWTH_WEIGHT` 0.01 × the price advantage), which gives the Union the real upside plan 1 lacked.
8. **Renegotiation** costs 10 PC, needs Krasova warmth ≥ −0.7, and has a 12-month cooldown. It trades price for one concession:
   - transit fees: ×0.9, and a permanent −20 a year of `budget_revenue`; once only
   - a Union step: ×0.85, and Ardenia takes observer status through `OrientationActions`, paying that step's own 10 PC as well
   - a policy: shelve the second line while it is under construction, ×0.9, and +0.1 Krasova warmth

   The price never falls below 0.5 × the reference. A renegotiated price lasts until the next renewal.
9. **Other operations.**
   - Pay arrears: a tranche of up to 50, no PC, +0.02 warmth.
   - Spot purchase: 0.5 bcm at 1.8 × the price, 5 PC; it arrives in the next month's flow.
   - Storage: 15 PC, 24 months at 40 a year; capacity is built linearly to 1.0 bcm.
   - Second line: 25 PC, 48 months at 60 a year, then 2.0 bcm a year at 1.2 × the reference. Krasova reacts with −0.15 at launch and −0.1 at opening. Take-or-pay keeps billing 80% of Krasovan gas offered until the next renewal shrinks the contract.

   All operations are government-only.
10. **Dependence reads the real contract.** `GasSim.write_share` sets `gas_share[supplier] = contracted / (contracted + second_line)` every month before `update_spine`. The catalog's 1.0 is only the pre-contract seed.
11. **Hooks for later plans.**
    - `GasContract.sabotage` (0..1): multiplies delivered Krasovan supply. It stays 0 in this plan; plan 4 writes it.
    - `GasSim.valve_threat(state)`: returns `{turn, due, share}` or `{}`, the trigger data for plan 3's valve-threat situation.
    - `GasSim.crisis(state)`: plan 4 replaces its warmth test with tension.
12. **Calibration helpers are not changed to dodge the new cost.** The steady helpers never pay arrears, so an ordinary government lives with the valve. Task 8 re-measures and never widens.

## Interfaces for later plans

- Plan 3 reads `GasSim.valve_threat(state)` (a non-empty dictionary means a threat is pending, due at `due`) and calls `EnergyActions.act(state, verb)` / `EnergyActions.reason_for(state, verb)` from `Arcs` handlers (for example `gas_pay_arrears` as the "pay" option).
- Plan 4 writes `state.foreign.gas.sabotage` (validated 0..1, persisted) and overrides `GasSim.crisis`. It reads `GasSim.region_shortfall(state, region_id)` and the snapshot's `foreign.map.gas_supply`.
- The map reads snapshot `foreign.map.gas_supply` (`{region_id: ratio 0..1}`, 1.0 = fully supplied).

## File structure

| File | Responsibility |
|---|---|
| `godot/data/native/catalogs/energy.json` (new) | Contract seed, season weights, regional exposure, second line, dispatch lines |
| `godot/data/native/catalog_manifest.json` | Register the catalog |
| `godot/scripts/native/state/gas_contract.gd` (new) | The persisted contract and its `to_dict`/`from_dict` |
| `godot/scripts/native/state/foreign_state.gd` | `gas` field and its round trip |
| `godot/scripts/native/state/state_validator.gd` | `_validate_gas` |
| `godot/scripts/native/sim/gas_sim.gd` (new) | Seeding, flow, effect terms, renewal, supplier ladder, Union hooks, projects |
| `godot/scripts/native/sim/foreign_sim.gd` | Seed the contract, run the flow inside the month |
| `godot/scripts/native/sim/economy_sim.gd`, `regions_sim.gd`, `households_sim.gd`, `stability_sim.gd` | Read the gas terms |
| `godot/scripts/native/sim/world_sim.gd` | The supplier's undermine plan takes a gas move first |
| `godot/scripts/native/actions/orientation_actions.gd` | Union join/leave gas hooks, snapshot energy and map fields |
| `godot/scripts/native/actions/energy_actions.gd` (new) | Seven player operations, refusals, read model |
| `godot/scripts/native/native_game.gd` | `energy_act` |
| `godot/scenes/panels/diplomacy_panel.tscn`, `godot/scripts/app.gd` | Energy section of the Diplomacy desk |
| `godot/tests/native/energy_probe.gd`, `trajectory_probe.gd` (new, not in battery) | Calibration measurement tools |
| `docs/godot/LIVING_WORLD.md` | Energy section and calibration record |

---

### Task 1: The gas contract, its catalog, persistence and validation

**Files:**
- Create: `godot/data/native/catalogs/energy.json`
- Modify: `godot/data/native/catalog_manifest.json` (files list)
- Create: `godot/scripts/native/state/gas_contract.gd`
- Modify: `godot/scripts/native/state/foreign_state.gd` (field, `to_dict`, `from_dict`)
- Create: `godot/scripts/native/sim/gas_sim.gd`
- Modify: `godot/scripts/native/sim/foreign_sim.gd` (`ensure`)
- Modify: `godot/scripts/native/state/state_validator.gd` (`_validate_foreign`, new `_validate_gas`)
- Test: `godot/tests/native/test_gas_contract.gd`

**Interfaces:**
- Consumes: `ForeignState`, `ForeignSim.power_ids()`, `ForeignSim.ensure(state)`, `StateValidator._foreign_unit(v)`, `SaveStore.save_slot/load_slot`.
- Produces:
  - `GasContract` (fields as in Step 3, `is_active() -> bool`, `to_dict() -> Dictionary`, `static from_dict(Variant) -> GasContract`, consts `PAID_MONTHS`, `FLOAT_FIELDS`, `INT_FIELDS`, `FLOW_FIELDS`)
  - `ForeignState.gas: GasContract`
  - `GasSim.catalog() -> Dictionary`, `GasSim.season_weight(month: int) -> float`, `GasSim.line(key: String, fields := {}) -> String`, `GasSim.gas(state) -> GasContract`, `GasSim.is_active(state) -> bool`, `GasSim.ensure(state) -> bool`, `GasSim.write_share(state) -> void`, `GasSim.union_member(state) -> bool`, `GasSim.union_cap(g: GasContract) -> float`, consts `PAYMENT_SHARE`, `UNION_PRICE_SHARE`, `WINTER_WEIGHT`.

- [ ] **Step 1: Write the failing test**

Create `godot/tests/native/test_gas_contract.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const SLOT := "test_gas_contract"


static func _state(role: String = "government") -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	return state


static func _wipe() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := "user://saves/%s.json%s" % [SLOT, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


static func _rejects(t, state: GameState, fragment: String, label: String) -> void:
	var errors := StateValidator.validate(state)
	t.truth(Array(errors).any(func(e) -> bool: return String(e).contains(fragment)), label)


func _test_the_catalog_is_coherent(t) -> void:
	var weights: Array = GasSim.catalog().get("season", [])
	t.equal(weights.size(), 12, "the season has twelve monthly weights")
	var total := 0.0
	for w in weights:
		total += float(w)
	t.near(total, 12.0, 0.000001, "and they sum to a year of demand")
	t.equal(GasSim.season_weight(3), GasSim.WINTER_WEIGHT, "March is still the heating season")
	t.truth(GasSim.season_weight(4) < 1.0, "April is not")
	t.truth(GasSim.season_weight(9) < 1.0, "September is not")
	t.equal(GasSim.season_weight(10), GasSim.WINTER_WEIGHT, "October is")
	t.truth((GasSim.catalog().get("contracts", {}) as Dictionary).has("ardenia"), "Ardenia's contract is authored")


func _test_a_new_campaign_opens_with_the_zovar_contract(t) -> void:
	var g := _state().foreign.gas
	t.truth(g.is_active(), "the campaign opens with an active gas contract")
	t.equal(g.supplier_id, "krasova", "supplied by Krasova")
	t.equal(g.price, 50.0, "at the authored price")
	t.equal(g.reference_price, 50.0, "which is also the market reference")
	t.equal(g.arrears, 40.0, "already in arrears")
	t.equal(g.term_end, 22, "renewing in January 1995")
	t.equal(g.paid.size(), GasContract.PAID_MONTHS, "with a year of payment history")
	var paid := 0.0
	for p in g.paid:
		paid += p
	t.near(paid, 50.0 * 6.0 * GasSim.PAYMENT_SHARE, 0.000001, "that settles the steady share of a year's bill")


func _test_dependence_share_reads_the_contract(t) -> void:
	var state := _state()
	t.equal(float(state.foreign.gas_share["krasova"]), 1.0, "all gas comes from Krasova at the start")
	state.foreign.gas.second_line_volume = 2.0
	GasSim.write_share(state)
	t.near(float(state.foreign.gas_share["krasova"]), 0.75, 0.000001, "a second line cuts Krasova's share to what it still contracts")


func _test_seeding_twice_never_resets_the_contract(t) -> void:
	var state := _state()
	state.foreign.gas.arrears = 99.0
	t.truth(not GasSim.ensure(state), "an active contract is not seeded again")
	ForeignSim.ensure(state)
	t.equal(state.foreign.gas.arrears, 99.0, "and keeps its arrears")


func _test_the_contract_round_trips_through_a_binary_save(t) -> void:
	_wipe()
	var state := _state()
	var g := state.foreign.gas
	g.cut = 0.25
	g.cut_until = 3
	g.threat = {"turn": 0, "due": 1, "share": 0.2}
	g.concessions.append("transit")
	g.last_flow = {"demand": 0.75, "delivered": 0.5, "drawn": 0.1, "injected": 0.0, "bill": 30.0, "shortfall": 0.2, "severity": 0.2}
	g.storage_target = 1.0
	g.storage_capacity = 0.5
	g.storage = 0.25
	g.cuts = 2
	t.truth(SaveStore.save_slot(SLOT, state).get("ok", false), "the contract saves")
	var loaded: Dictionary = SaveStore.load_slot(SLOT)
	t.truth(loaded.get("ok", false), "and loads")
	t.equal((loaded["state"] as GameState).foreign.gas.to_dict(), g.to_dict(), "every contract field survives the round trip")
	_wipe()


func _test_an_old_save_gains_the_contract_on_load(t) -> void:
	_wipe()
	var state := _state()
	state.foreign.gas = GasContract.new()
	SaveStore.save_slot(SLOT, state)
	var game: Node = NativeGameScript.new()
	t.truth(game.load(SLOT).get("ok", false), "a plan-1 save without a contract loads")
	t.truth(game._state.foreign.gas.is_active(), "and gains the Zovar contract")
	game.free()
	_wipe()


func _test_malformed_contracts_are_refused(t) -> void:
	t.truth(GasContract.from_dict("x") == null, "a contract that is not a dictionary is refused")
	t.truth(GasContract.from_dict({"paid": 3}) == null, "a payment history that is not a list is refused")
	t.truth(GasContract.from_dict({"threat": []}) == null, "a threat that is not a dictionary is refused")
	t.truth(ForeignState.from_dict({"gas": 5}) == null, "and so is a ledger that carries one")
	t.truth(not GasContract.from_dict(null).is_active(), "a missing contract loads inactive")


func _test_the_validator_rejects_impossible_contracts(t) -> void:
	var s := _state()
	s.foreign.gas.arrears = -1.0
	_rejects(t, s, "gas arrears is impossible", "negative arrears are rejected")
	s = _state()
	s.foreign.gas.take_or_pay = NAN
	_rejects(t, s, "gas take_or_pay is impossible", "a non-finite take-or-pay is rejected")
	s = _state()
	s.foreign.gas.cut = 1.5
	_rejects(t, s, "gas cut is above one", "a cut above one is rejected")
	s = _state()
	s.foreign.gas.sabotage = -0.1
	_rejects(t, s, "gas sabotage is impossible", "negative sabotage is rejected")
	s = _state()
	s.foreign.gas.price = 0.0
	_rejects(t, s, "gas price must be positive", "a free contract is rejected")
	s = _state()
	s.foreign.gas.supplier_id = "atlantis"
	_rejects(t, s, "gas supplier 'atlantis' is unknown", "an unknown supplier is rejected")
	s = _state()
	s.foreign.gas.storage = 0.5
	_rejects(t, s, "gas storage exceeds its capacity", "gas above the storage capacity is rejected")
	s = _state()
	s.foreign.gas.storage_capacity = 0.5
	_rejects(t, s, "gas storage exceeds its capacity", "capacity above the programme target is rejected")
	s = _state()
	s.foreign.gas.storage_started = s.turn + 1
	_rejects(t, s, "gas storage_started is out of time", "a programme started in the future is rejected")
	s = _state()
	s.foreign.gas.last_renegotiated = -2
	_rejects(t, s, "gas last_renegotiated is out of time", "a turn before the campaign is rejected")
	s = _state()
	s.foreign.gas.cuts = -1
	_rejects(t, s, "gas cuts is negative", "a negative cut count is rejected")
	s = _state()
	s.foreign.gas.threat = {"turn": 0, "due": 0, "share": 0.2}
	_rejects(t, s, "gas threat is impossible", "a threat due before it is made is rejected")
	s = _state()
	s.foreign.gas.threat = {"turn": 0, "due": 1, "share": 1.2}
	_rejects(t, s, "gas threat is impossible", "a threat beyond the whole supply is rejected")
	s = _state()
	s.foreign.gas.paid.append(1.0)
	_rejects(t, s, "gas payment history is impossible", "more than a year of history is rejected")
	s = _state()
	s.foreign.gas.paid[0] = -1.0
	_rejects(t, s, "gas payment history is impossible", "a negative payment is rejected")
	s = _state()
	s.foreign.gas.concessions.append("souls")
	_rejects(t, s, "unknown gas concession 'souls'", "an unknown concession is rejected")
	s = _state()
	s.foreign.reached["union_observer"] = 0
	s.foreign.reached["union_member"] = 0
	_rejects(t, s, "gas price breaks the Union cap", "a member paying above the Union cap is rejected")
	s.foreign.gas.price = GasSim.union_cap(s.foreign.gas)
	t.truth(StateValidator.validate(s).is_empty(), "a member paying exactly the cap is valid")
	t.truth(StateValidator.validate(_state()).is_empty(), "the opening contract is valid")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_the_catalog_is_coherent(t)
	_test_a_new_campaign_opens_with_the_zovar_contract(t)
	_test_dependence_share_reads_the_contract(t)
	_test_seeding_twice_never_resets_the_contract(t)
	_test_the_contract_round_trips_through_a_binary_save(t)
	_test_an_old_save_gains_the_contract_on_load(t)
	_test_malformed_contracts_are_refused(t)
	_test_the_validator_rejects_impossible_contracts(t)
	quit(t.finish())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_gas_contract.gd`
Expected: exit 124 with `SCRIPT ERROR` (`GasSim` / `GasContract` not declared).

- [ ] **Step 3: Write the catalog, the contract and the seeding**

Create `godot/data/native/catalogs/energy.json`:

```json
{
  "contracts": {
    "ardenia": {"supplier_id": "krasova", "price": 50.0, "annual_demand": 6.0, "contracted_volume": 6.0,
      "arrears": 40.0, "term_end": 22, "take_or_pay": 0.8}
  },
  "season": [1.5, 1.5, 1.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 1.5, 1.5, 1.5],
  "exposure": {"zavost": 1.5, "darev": 1.3, "sela": 0.8, "anera": 0.8, "karsen": 0.8, "orvena": 0.8},
  "industrial": ["zavost", "darev"],
  "second_line": {"name": "the southern interconnector", "volume": 2.0, "price_share": 1.2},
  "lines": {
    "gas_demand": "{supplier}'s gas company presents the Zovar arrears, {arrears} million kron in hard currency, and asks when Ardenia means to pay.",
    "gas_threat": "{supplier} mentions the valve again, and this time names a date: unless the arrears come down, deliveries fall next month.",
    "gas_threat_lapsed": "The date named for the valve passes, and the gas keeps flowing.",
    "gas_cut": "The valve is turned. Deliveries through the Zovar line fall by {share}%.",
    "gas_restored": "Full deliveries resume on the Zovar line.",
    "gas_renewal": "The Zovar contract is renewed at {price} a unit for three more years.",
    "gas_shortfall": "Ardenia is short {share}% of the gas it needs this month.",
    "storage_ready": "The gas storage programme is complete.",
    "second_line_open": "The second supply line opens. For the first time Ardenia can heat itself without Krasova's leave."
  }
}
```

In `godot/data/native/catalog_manifest.json`, add `"catalogs/energy.json",` immediately before `"catalogs/events.json",`.

Create `godot/scripts/native/state/gas_contract.gd`:

```gdscript
class_name GasContract
extends RefCounted


const PAID_MONTHS := 12
const FLOAT_FIELDS := ["price", "reference_price", "contracted_volume", "annual_demand", "arrears",
	"take_or_pay", "cut", "sabotage", "storage", "storage_capacity", "storage_target",
	"second_line_volume", "spot_pending"]
const INT_FIELDS := ["term_end", "cut_until", "last_cut_turn", "last_demand_turn", "storage_started",
	"second_line_started", "last_renegotiated", "demands", "threats", "cuts"]
const FLOW_FIELDS := ["demand", "delivered", "drawn", "injected", "bill", "shortfall", "severity"]

var supplier_id: String = ""
var price: float = 0.0
var reference_price: float = 0.0
var contracted_volume: float = 0.0
var annual_demand: float = 0.0
var arrears: float = 0.0
var term_end: int = 0
var take_or_pay: float = 0.0
var cut: float = 0.0
var cut_until: int = -1
var last_cut_turn: int = -1
var sabotage: float = 0.0
var threat: Dictionary = {}
var last_demand_turn: int = -1
var storage: float = 0.0
var storage_capacity: float = 0.0
var storage_target: float = 0.0
var storage_started: int = -1
var second_line_volume: float = 0.0
var second_line_started: int = -1
var spot_pending: float = 0.0
var last_renegotiated: int = -1
var demands: int = 0
var threats: int = 0
var cuts: int = 0
var concessions: Array[String] = []
var paid: Array[float] = []
var last_flow: Dictionary = {}


func is_active() -> bool:
	return supplier_id != "" and annual_demand > 0.0


func to_dict() -> Dictionary:
	var out := {"supplier_id": supplier_id, "threat": threat.duplicate(),
		"concessions": Array(concessions), "paid": Array(paid), "last_flow": last_flow.duplicate()}
	for field in FLOAT_FIELDS + INT_FIELDS:
		out[field] = get(field)
	return out


static func from_dict(data: Variant) -> GasContract:
	var out := GasContract.new()
	if data == null:
		return out
	if not (data is Dictionary):
		push_error("GasContract.from_dict: expected a Dictionary")
		return null
	var d: Dictionary = data
	for field in ["threat", "last_flow"]:
		if not (d.get(field, {}) is Dictionary):
			push_error("GasContract.from_dict: malformed %s" % field)
			return null
	for field in ["concessions", "paid"]:
		if not (d.get(field, []) is Array):
			push_error("GasContract.from_dict: malformed %s" % field)
			return null
	out.supplier_id = String(d.get("supplier_id", ""))
	for field in FLOAT_FIELDS:
		out.set(field, float(d.get(field, out.get(field))))
	for field in INT_FIELDS:
		out.set(field, int(d.get(field, out.get(field))))
	var raw_threat: Dictionary = d.get("threat", {})
	if not raw_threat.is_empty():
		out.threat = {"turn": int(raw_threat.get("turn", 0)), "due": int(raw_threat.get("due", 0)),
			"share": float(raw_threat.get("share", 0.0))}
	for c in d.get("concessions", []):
		out.concessions.append(String(c))
	for p in d.get("paid", []):
		out.paid.append(float(p))
	var flow: Dictionary = d.get("last_flow", {})
	for key in FLOW_FIELDS:
		if flow.has(key):
			out.last_flow[key] = float(flow[key])
	return out
```

In `godot/scripts/native/state/foreign_state.gd`:
- After `var seeded: bool = false` add `var gas: GasContract = GasContract.new()`.
- In `to_dict()` add the entry `"gas": gas.to_dict(),` after `"seeded": seeded,`.
- In `from_dict`, replace the final `out.seeded = bool(d.get("seeded", false))` / `return out` with:

```gdscript
	out.seeded = bool(d.get("seeded", false))
	out.gas = GasContract.from_dict(d.get("gas", null))
	if out.gas == null:
		push_error("ForeignState.from_dict: malformed gas contract")
		return null
	return out
```

Create `godot/scripts/native/sim/gas_sim.gd`:

```gdscript
class_name GasSim
extends RefCounted


const PAYMENT_SHARE := 0.85
const WINTER_WEIGHT := 1.5
const UNION_PRICE_SHARE := 0.7


static func catalog() -> Dictionary:
	var data: Variant = ContentRepository.load_all().get("catalogs", {}).get("energy", {})
	return data if data is Dictionary else {}


static func season_weight(month: int) -> float:
	var weights: Array = catalog().get("season", [])
	return float(weights[month - 1]) if weights.size() == 12 else 1.0


static func line(key: String, fields: Dictionary = {}) -> String:
	return String(catalog().get("lines", {}).get(key, key)).format(fields)


static func gas(state: GameState) -> GasContract:
	return null if state.foreign == null else state.foreign.gas


static func is_active(state: GameState) -> bool:
	var g := gas(state)
	return g != null and g.is_active()


static func union_member(state: GameState) -> bool:
	return state.foreign != null and state.foreign.reached.has("union_member")


static func union_cap(g: GasContract) -> float:
	return g.reference_price * UNION_PRICE_SHARE


static func ensure(state: GameState) -> bool:
	var g := state.foreign.gas
	if g.is_active():
		return false
	var raw: Variant = catalog().get("contracts", {}).get(state.country.id, null)
	if not (raw is Dictionary):
		return false
	var row: Dictionary = raw
	if state.world_country(String(row.get("supplier_id", ""))) == null:
		return false
	g.supplier_id = String(row["supplier_id"])
	g.price = float(row["price"])
	g.reference_price = g.price
	g.annual_demand = float(row["annual_demand"])
	g.contracted_volume = float(row["contracted_volume"])
	g.arrears = float(row["arrears"])
	g.term_end = int(row["term_end"])
	g.take_or_pay = float(row["take_or_pay"])
	g.paid.clear()
	for _i in range(GasContract.PAID_MONTHS):
		g.paid.append(g.price * g.contracted_volume * PAYMENT_SHARE / float(GasContract.PAID_MONTHS))
	write_share(state)
	return true


static func write_share(state: GameState) -> void:
	var g := state.foreign.gas
	if not g.is_active() or not (g.supplier_id in ForeignSim.power_ids()):
		return
	var total := g.contracted_volume + g.second_line_volume
	state.foreign.gas_share[g.supplier_id] = 0.0 if total <= 0.0 else clampf(g.contracted_volume / total, 0.0, 1.0)
```

In `godot/scripts/native/sim/foreign_sim.gd`, replace `ensure` with:

```gdscript
static func ensure(state: GameState) -> void:
	var f := state.foreign
	if f.seeded:
		if GasSim.ensure(state):
			update_spine(state)
		return
	for p in catalog().get("powers", []):
		f.gas_share[String(p["id"])] = float(p.get("gas_share", 0.0))
	for m in catalog().get("milestones", []):
		if bool(m.get("starts_reached", false)):
			f.reached[String(m["id"])] = state.turn
	for b in catalog().get("blocs", []):
		var ids: Array = []
		for country_id in b.get("seed_members", []):
			if state.world_country(String(country_id)) != null:
				ids.append(String(country_id))
		f.members[String(b["id"])] = ids
	f.isf = ForeignState.default_isf()
	f.seeded = true
	GasSim.ensure(state)
	update_spine(state)
```

In `godot/scripts/native/state/state_validator.gd`, in `_validate_foreign` add `_validate_gas(state, errors)` after `_validate_hostile_log(state, errors)`, and add:

```gdscript
static func _validate_gas(state: GameState, errors: Array[String]) -> void:
	var g := state.foreign.gas
	if g == null:
		errors.append("gas contract is missing")
		return
	for field in GasContract.FLOAT_FIELDS:
		var x := float(g.get(field))
		if not is_finite(x) or x < 0.0:
			errors.append("gas %s is impossible" % field)
	for field in ["take_or_pay", "cut", "sabotage"]:
		if float(g.get(field)) > 1.0:
			errors.append("gas %s is above one" % field)
	if not g.is_active():
		return
	if state.world_country(g.supplier_id) == null:
		errors.append("gas supplier '%s' is unknown" % g.supplier_id)
	if g.price <= 0.0:
		errors.append("gas price must be positive")
	if g.storage > g.storage_capacity + 0.000001 or g.storage_capacity > g.storage_target + 0.000001:
		errors.append("gas storage exceeds its capacity")
	for field in ["cut_until", "last_cut_turn", "last_demand_turn", "storage_started", "second_line_started", "last_renegotiated"]:
		var at := int(g.get(field))
		if at < -1 or (field != "cut_until" and at > state.turn):
			errors.append("gas %s is out of time" % field)
	for field in ["demands", "threats", "cuts"]:
		if int(g.get(field)) < 0:
			errors.append("gas %s is negative" % field)
	if not g.threat.is_empty():
		var made := int(g.threat.get("turn", -1))
		if made < 0 or made > state.turn or int(g.threat.get("due", -1)) <= made \
				or not _foreign_unit(g.threat.get("share", -1.0)):
			errors.append("gas threat is impossible")
	if g.paid.size() > GasContract.PAID_MONTHS or g.paid.any(func(p: float) -> bool: return not is_finite(p) or p < 0.0):
		errors.append("gas payment history is impossible")
	for c in g.concessions:
		if not (c in ["transit"]):
			errors.append("unknown gas concession '%s'" % c)
	if state.foreign.reached.has("union_member") and g.price > GasSim.union_cap(g) + 0.000001:
		errors.append("gas price breaks the Union cap")
```

- [ ] **Step 4: Import, run the test, run the battery**

Run: `timeout 180 "$G" --headless --path godot --import`, then `timeout 180 "$G" --headless --path godot --script res://tests/native/test_gas_contract.gd`
Expected: `NATIVE TESTS: 40 passed, 0 failed` (count may differ by the exact assertions; 0 failed is the gate). Then the full battery: all green. `test_foreign_state.gd`'s round-trip test compares `to_dict()` and must still pass.

- [ ] **Step 5: Mutation-check**

Each mutation must fail the named assertion; restore and rerun green after each:
- Drop `"gas": gas.to_dict(),` from `ForeignState.to_dict` → "every contract field survives the round trip".
- In `write_share`, use `1.0` instead of `g.contracted_volume / total` → "a second line cuts Krasova's share".
- In `ForeignSim.ensure`'s seeded branch, remove the `GasSim.ensure` call → "and gains the Zovar contract".
- Change `weights[month - 1]` to `weights[month % 12]` → the March/April or September/October boundary assertions.
- Change `> GasSim.union_cap(g) + 0.000001` to `>= GasSim.union_cap(g)` → "a member paying exactly the cap is valid".
- Delete each validator branch in turn → its `_rejects` assertion.

- [ ] **Step 6: Commit**

```bash
git add godot/data/native/catalogs/energy.json godot/data/native/catalog_manifest.json \
  godot/scripts/native/state/gas_contract.gd godot/scripts/native/state/gas_contract.gd.uid \
  godot/scripts/native/state/foreign_state.gd godot/scripts/native/sim/gas_sim.gd godot/scripts/native/sim/gas_sim.gd.uid \
  godot/scripts/native/sim/foreign_sim.gd godot/scripts/native/state/state_validator.gd \
  godot/tests/native/test_gas_contract.gd godot/tests/native/test_gas_contract.gd.uid
git commit -m "feat(godot): the Zovar gas contract, persisted and validated

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The monthly seasonal flow, the budget line and real dependence

**Files:**
- Modify: `godot/scripts/native/sim/gas_sim.gd` (flow, readers, `monthly`)
- Modify: `godot/scripts/native/sim/foreign_sim.gd` (`monthly`)
- Modify: `godot/scripts/native/sim/economy_sim.gd` (`_update_budget_lines`)
- Test: `godot/tests/native/test_gas_flow.gd`

**Interfaces:**
- Consumes: Task 1's `GasSim`, `GasContract`.
- Produces: `GasSim.flow(state) -> void`, `GasSim.monthly(state) -> Array[String]`, `GasSim.budget_cost(state) -> float`, `GasSim.national_shortfall(state) -> float`, `GasSim.national_severity(state) -> float`, `GasSim.second_line_price_share() -> float`, consts `INJECTION_SHARE`, `SHORTFALL_NOTE`. `last_flow` keys are `GasContract.FLOW_FIELDS`.

- [ ] **Step 1: Write the failing test**

Create `godot/tests/native/test_gas_flow.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")


static func _state() -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	return state


static func _flow(state: GameState, month: int) -> Dictionary:
	state.month = month
	GasSim.flow(state)
	return state.foreign.gas.last_flow


func _test_a_full_contract_meets_winter_demand(t) -> void:
	var state := _state()
	var arrears := state.foreign.gas.arrears
	var f := _flow(state, 1)
	t.near(float(f["demand"]), 0.75, 0.000001, "January demand is a winter month's share of the year")
	t.near(float(f["shortfall"]), 0.0, 0.000001, "a full contract leaves no shortfall")
	t.near(float(f["bill"]), 37.5, 0.000001, "the bill is the price of what was taken")
	t.near(state.foreign.gas.arrears - arrears, 37.5 * (1.0 - GasSim.PAYMENT_SHARE), 0.000001, "the unpaid share becomes arrears")
	t.equal(state.foreign.gas.paid.size(), GasContract.PAID_MONTHS, "the payment history keeps one year")


func _test_season_boundaries(t) -> void:
	var state := _state()
	t.near(float(_flow(state, 3)["demand"]), 0.75, 0.000001, "March is heated")
	t.near(float(_flow(state, 4)["demand"]), 0.25, 0.000001, "April is not")
	t.near(float(_flow(state, 9)["demand"]), 0.25, 0.000001, "September is not")
	t.near(float(_flow(state, 10)["demand"]), 0.75, 0.000001, "October is")


func _test_a_cut_is_buffered_by_storage(t) -> void:
	var state := _state()
	state.foreign.gas.cut = 0.4
	state.foreign.gas.cut_until = state.turn + 12
	t.near(float(_flow(state, 1)["shortfall"]), 0.4, 0.000001, "a 40% cut in January leaves 40% short")
	t.near(float(state.foreign.gas.last_flow["severity"]), 0.4, 0.000001, "at full winter severity")
	t.near(float(_flow(state, 7)["severity"]), 0.4 / 3.0, 0.000001, "the same cut in July is a third as severe")
	state.foreign.gas.storage_target = 1.0
	state.foreign.gas.storage_capacity = 1.0
	state.foreign.gas.storage = 0.2
	var f := _flow(state, 1)
	t.near(float(f["drawn"]), 0.2, 0.000001, "storage is drawn to cover the gap")
	t.near(float(f["shortfall"]), 0.1 / 0.75, 0.000001, "and only the rest is short")


func _test_sabotage_cuts_delivered_supply(t) -> void:
	var state := _state()
	state.foreign.gas.sabotage = 0.5
	t.near(float(_flow(state, 1)["shortfall"]), 0.5, 0.000001, "sabotage on the line takes its share of supply")


func _test_summer_fills_storage(t) -> void:
	var state := _state()
	state.foreign.gas.storage_target = 1.0
	state.foreign.gas.storage_capacity = 1.0
	var f := _flow(state, 6)
	t.near(float(f["injected"]), GasSim.INJECTION_SHARE, 0.000001, "a summer month injects a quarter of capacity")
	t.near(state.foreign.gas.storage, GasSim.INJECTION_SHARE, 0.000001, "into storage")
	t.near(float(_flow(state, 1)["injected"]), 0.0, 0.000001, "a winter month injects nothing")


func _test_take_or_pay_bills_gas_not_taken(t) -> void:
	var state := _state()
	state.foreign.gas.second_line_volume = 6.0
	var f := _flow(state, 6)
	t.near(float(f["shortfall"]), 0.0, 0.000001, "the second line covers summer demand")
	t.near(float(f["bill"]), 50.0 * 0.8 * 0.25, 0.000001, "but Krasova still bills 80% of what it offered")


func _test_the_gas_bill_is_a_real_budget_line(t) -> void:
	var state := _state()
	var econ := state.country.economy
	EconomySim._update_budget_lines(state)
	var with_gas := econ.budget.expenditure
	state.foreign.gas.paid.clear()
	EconomySim._update_budget_lines(state)
	t.near(with_gas - econ.budget.expenditure, 50.0 * 6.0 * GasSim.PAYMENT_SHARE, 0.001, "a year of paid gas sits in expenditure")


func _test_a_shortfall_is_reported(t) -> void:
	var state := _state()
	state.month = 1
	state.foreign.gas.cut = 0.5
	state.foreign.gas.cut_until = state.turn + 12
	var notes := GasSim.monthly(state)
	t.truth(notes.any(func(n: String) -> bool: return n.contains("short")), "a real shortfall reaches the monthly report")
	state.foreign.gas.cut = GasSim.SHORTFALL_NOTE * 0.5
	notes = GasSim.monthly(state)
	t.truth(not notes.any(func(n: String) -> bool: return n.contains("short")), "a trace shortfall does not")


func _test_the_calendar_drives_the_season(t) -> void:
	var state := _state()
	NativeGameScript.next_month(state)
	t.equal(state.month, 4, "the first month closed is April")
	t.near(float(state.foreign.gas.last_flow["demand"]), 0.25, 0.000001, "and burns summer gas")
	while state.month != 10:
		NativeGameScript.next_month(state)
	t.near(float(state.foreign.gas.last_flow["demand"]), 0.75, 0.000001, "October's close burns winter gas")


func _test_dependence_reads_the_contract_in_the_month(t) -> void:
	var state := _state()
	var before := ForeignSim.dependence(state, "krasova")
	state.foreign.gas.second_line_volume = 6.0
	NativeGameScript.next_month(state)
	t.near(float(state.foreign.gas_share["krasova"]), 0.5, 0.000001, "the month writes Krasova's real share")
	t.near(float(state.foreign.powers["krasova"]["dependence"]), ForeignSim.dependence(state, "krasova"), 0.000001, "before the spine is read")
	t.truth(before - float(state.foreign.powers["krasova"]["dependence"]) > 0.2, "so dependence on Krasova falls")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_a_full_contract_meets_winter_demand(t)
	_test_season_boundaries(t)
	_test_a_cut_is_buffered_by_storage(t)
	_test_sabotage_cuts_delivered_supply(t)
	_test_summer_fills_storage(t)
	_test_take_or_pay_bills_gas_not_taken(t)
	_test_the_gas_bill_is_a_real_budget_line(t)
	_test_a_shortfall_is_reported(t)
	_test_the_calendar_drives_the_season(t)
	_test_dependence_reads_the_contract_in_the_month(t)
	quit(t.finish())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_gas_flow.gd`
Expected: exit 124 with `SCRIPT ERROR` (`GasSim.flow` not found).

- [ ] **Step 3: Implement the flow**

Add to `godot/scripts/native/sim/gas_sim.gd` (constants under the existing ones, functions at the end):

```gdscript
const INJECTION_SHARE := 0.25
const SHORTFALL_NOTE := 0.05
```

```gdscript
static func second_line_price_share() -> float:
	return float(catalog().get("second_line", {}).get("price_share", 1.0))


static func monthly(state: GameState) -> Array[String]:
	var notes: Array[String] = []
	if not is_active(state):
		return notes
	flow(state)
	write_share(state)
	if national_shortfall(state) >= SHORTFALL_NOTE:
		notes.append(line("gas_shortfall", {"share": roundi(national_shortfall(state) * 100.0)}))
	return notes


static func flow(state: GameState) -> void:
	var g := state.foreign.gas
	var season := season_weight(state.month)
	var supply := (1.0 - g.cut) * (1.0 - g.sabotage)
	var demand := g.annual_demand / 12.0 * season
	var offered := g.contracted_volume / 12.0 * season * supply
	var alternative := minf(demand, g.second_line_volume / 12.0 * season + g.spot_pending)
	g.spot_pending = 0.0
	var taken := minf(offered, demand - alternative)
	var gap := demand - alternative - taken
	var drawn := minf(g.storage, gap)
	g.storage -= drawn
	gap -= drawn
	var injected := 0.0
	if season < 1.0 and g.storage < g.storage_capacity:
		injected = minf(g.storage_capacity - g.storage, g.storage_capacity * INJECTION_SHARE) * supply
		g.storage += injected
	var bill := g.price * (maxf(taken, g.take_or_pay * offered) + injected)
	var alternative_bill := g.second_line_volume / 12.0 * season * g.reference_price * second_line_price_share()
	g.arrears += bill * (1.0 - PAYMENT_SHARE)
	g.paid.append(bill * PAYMENT_SHARE + alternative_bill)
	while g.paid.size() > GasContract.PAID_MONTHS:
		g.paid.pop_front()
	var shortfall := 0.0 if demand <= 0.0 else clampf(gap / demand, 0.0, 1.0)
	g.last_flow = {"demand": demand, "delivered": demand - gap, "drawn": drawn, "injected": injected,
		"bill": bill, "shortfall": shortfall, "severity": shortfall * season / WINTER_WEIGHT}


static func budget_cost(state: GameState) -> float:
	if not is_active(state):
		return 0.0
	var total := 0.0
	for p in gas(state).paid:
		total += p
	return total


static func national_shortfall(state: GameState) -> float:
	return 0.0 if not is_active(state) else float(gas(state).last_flow.get("shortfall", 0.0))


static func national_severity(state: GameState) -> float:
	return 0.0 if not is_active(state) else float(gas(state).last_flow.get("severity", 0.0))
```

In `godot/scripts/native/sim/foreign_sim.gd`, replace `monthly` with:

```gdscript
static func monthly(state: GameState) -> Array[String]:
	ensure(state)
	var notes := OrientationSim.monthly(state)
	notes.append_array(GasSim.monthly(state))
	update_spine(state)
	return notes
```

In `godot/scripts/native/sim/economy_sim.gd` `_update_budget_lines`, change the expenditure line to:

```gdscript
	econ.budget.expenditure = (econ.structural_expenditure
		+ _modifiers_sum(state, "budget_expenditure") + econ.debt_service + GasSim.budget_cost(state))
```

- [ ] **Step 4: Import, run the test, run the battery**

Run: `--import`, then the test. Expected: 0 failed. Full battery: calibration-sensitive files (`test_polls.gd`, `test_election_calibration.gd`, `test_orientation_journeys.gd`, `test_fiscal_journeys.gd`) may now miss a band, because gas is a new real cost. **Do not touch any band.** If a calibration assertion fails here, record its number in the task report and carry it to Task 8. Every non-calibration test must be green.

- [ ] **Step 5: Mutation-check**
- `season < 1.0` → `season <= 1.0`: no observable change, which is acceptable because no weight equals 1.0. Instead mutate `season_weight` to return `weights[month]` → "April is not" / "October is".
- Remove `g.storage -= drawn` / the draw → "storage is drawn to cover the gap".
- Replace `maxf(taken, g.take_or_pay * offered)` with `taken` → "Krasova still bills 80%".
- Drop `* (1.0 - g.sabotage)` → "sabotage on the line takes its share".
- Drop `+ GasSim.budget_cost(state)` → "a year of paid gas sits in expenditure".
- `>= SHORTFALL_NOTE` → `> 0.0` → "a trace shortfall does not".
- Move `notes.append_array(GasSim.monthly(state))` after `update_spine(state)` → "before the spine is read".
- Remove the `GasSim.monthly` call from `ForeignSim.monthly` → "October's close burns winter gas".

- [ ] **Step 6: Commit**

```bash
git add godot/scripts/native/sim/gas_sim.gd godot/scripts/native/sim/foreign_sim.gd godot/scripts/native/sim/economy_sim.gd \
  godot/tests/native/test_gas_flow.gd godot/tests/native/test_gas_flow.gd.uid
git commit -m "feat(godot): seasonal gas flow, arrears and the gas budget line

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Shortfall effects on households, Zavost and Darev, state reach and stability

**Files:**
- Modify: `godot/scripts/native/sim/gas_sim.gd` (effect terms)
- Modify: `godot/scripts/native/sim/households_sim.gd` (`simulate`, hardship line)
- Modify: `godot/scripts/native/sim/regions_sim.gd` (`_tick_region`)
- Modify: `godot/scripts/native/sim/economy_sim.gd` (`_apply_headline_stats`)
- Modify: `godot/scripts/native/sim/stability_sim.gd` (`stability_breakdown`)
- Test: `godot/tests/native/test_gas_shortfall.gd`

**Interfaces:**
- Consumes: Task 2's `last_flow`, `national_shortfall`, `national_severity`.
- Produces:
  - `GasSim.exposure(region_id: String) -> float`
  - `GasSim.region_shortfall(state, region_id: String) -> float` (for the map, 0..1)
  - `GasSim.region_severity(state, region_id: String) -> float`
  - `GasSim.supply_by_region(state) -> Dictionary`
  - `GasSim.heating_hardship(state, region_id) -> float`
  - `GasSim.reach_loss(state, region_id) -> float`
  - `GasSim.industry_jobs_loss(state, region_id) -> float`
  - `GasSim.growth_effect(state) -> float`
  - `GasSim.stability_drag(state) -> float`
  - the breakdown key `"Energy supply"`

- [ ] **Step 1: Write the failing test**

Create `godot/tests/native/test_gas_shortfall.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")


static func _state() -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	return state


static func _short(state: GameState, shortfall: float, severity: float) -> void:
	state.foreign.gas.last_flow = {"shortfall": shortfall, "severity": severity}


func _test_exposure_shapes_the_regional_shortfall(t) -> void:
	var state := _state()
	_short(state, 0.2, 0.2)
	t.near(GasSim.region_shortfall(state, "zavost"), 0.3, 0.000001, "industrial Zavost feels half again the national shortfall")
	t.near(GasSim.region_shortfall(state, "vashtera"), 0.2, 0.000001, "an unlisted region feels the national figure")
	t.near(GasSim.region_shortfall(state, "vetrenka"), 0.0, 0.000001, "territory outside state control is not on Ardenia's network")
	_short(state, 0.9, 0.9)
	t.near(GasSim.region_shortfall(state, "zavost"), 1.0, 0.000001, "and no region is more than wholly short")
	var supply := GasSim.supply_by_region(state)
	t.equal(supply.size(), state.regions.size(), "the map gets a supply ratio for every region")
	t.truth(supply.values().all(func(v) -> bool: return float(v) >= 0.0 and float(v) <= 1.0), "each within 0..1")


func _test_a_shortfall_raises_heating_hardship(t) -> void:
	var calm := _state()
	var cold := _state()
	_short(cold, 0.4, 0.4)
	for _i in range(6):
		HouseholdsSim.simulate(calm)
		HouseholdsSim.simulate(cold)
	t.truth(HouseholdsSim.regional_hardship(cold, "zavost") > HouseholdsSim.regional_hardship(calm, "zavost") + 0.05,
		"six cold months raise hardship in Zavost")
	t.truth(HouseholdsSim.regional_confidence(cold, "zavost") < HouseholdsSim.regional_confidence(calm, "zavost"),
		"and cost household confidence")


func _test_a_shortfall_idles_zavost_and_darev(t) -> void:
	var calm := _state()
	var cold := _state()
	_short(cold, 0.4, 0.4)
	for _i in range(6):
		RegionsSim.simulate(calm)
		RegionsSim.simulate(cold)
	for id in ["zavost", "darev"]:
		t.truth((cold.regions[id] as RegionState).unemployment > (calm.regions[id] as RegionState).unemployment,
			"%s's plants lay workers off without gas" % id)
	t.near((cold.regions["vashtera"] as RegionState).unemployment, (calm.regions["vashtera"] as RegionState).unemployment, 0.000001,
		"the capital loses no industrial jobs")
	t.truth((cold.regions["vashtera"] as RegionState).state_reach < (calm.regions["vashtera"] as RegionState).state_reach,
		"but the state reaches less of it")


func _test_growth_reads_shortfall_and_price(t) -> void:
	var state := _state()
	_short(state, 0.5, 0.5)
	t.near(GasSim.growth_effect(state), -0.03, 0.000001, "a severe shortfall costs three points of annualised growth")
	_short(state, 0.0, 0.0)
	state.foreign.gas.price = GasSim.union_cap(state.foreign.gas)
	t.near(GasSim.growth_effect(state), 0.003, 0.000001, "gas 30% under the reference lifts growth")
	state.foreign.gas.price = 60.0
	t.near(GasSim.growth_effect(state), -0.002, 0.000001, "and dear gas drags it")
	state.foreign.gas.price = 50.0
	EconomySim._apply_headline_stats(state)
	var normal := state.country.economy.growth_rate
	_short(state, 0.5, 0.5)
	EconomySim._apply_headline_stats(state)
	t.near(normal - state.country.economy.growth_rate, 0.03, 0.000001, "the economy books it")


func _test_stability_counts_the_cold(t) -> void:
	var state := _state()
	_short(state, 0.5, 0.25)
	t.near(float(StabilitySim.stability_breakdown(state)["Energy supply"]), -0.025, 0.000001, "a shortfall is a named stability drag weighted by severity")
	_short(state, 0.0, 0.0)
	t.near(float(StabilitySim.stability_breakdown(state)["Energy supply"]), 0.0, 0.000001, "full supply costs nothing")


func _test_storage_buffers_a_real_winter(t) -> void:
	var bare := _state()
	var stored := _state()
	for s in [bare, stored]:
		while s.month != 12:
			NativeGameScript.next_month(s)
	stored.foreign.gas.storage_target = 1.0
	stored.foreign.gas.storage_capacity = 1.0
	stored.foreign.gas.storage = 1.0
	var hardship := HouseholdsSim.regional_hardship(bare, "zavost")
	for s in [bare, stored]:
		s.foreign.gas.cut = 0.4
		s.foreign.gas.cut_until = s.turn + 12
		NativeGameScript.next_month(s)
	t.equal(bare.month, 1, "the cut lands in January")
	t.truth(GasSim.national_severity(stored) < GasSim.national_severity(bare), "storage softens the winter cut")
	t.truth(HouseholdsSim.regional_hardship(bare, "zavost") > hardship, "and the unbuffered winter hurts Zavost's households at once")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_exposure_shapes_the_regional_shortfall(t)
	_test_a_shortfall_raises_heating_hardship(t)
	_test_a_shortfall_idles_zavost_and_darev(t)
	_test_growth_reads_shortfall_and_price(t)
	_test_stability_counts_the_cold(t)
	_test_storage_buffers_a_real_winter(t)
	quit(t.finish())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_gas_shortfall.gd`
Expected: exit 124 with `SCRIPT ERROR` (`GasSim.region_shortfall` not found).

- [ ] **Step 3: Implement the effect terms**

Add to `godot/scripts/native/sim/gas_sim.gd`:

```gdscript
const SEPARATIST := "separatist"
const HARDSHIP_PER_SEVERITY := 0.25
const REACH_PER_SEVERITY := 0.15
const JOBS_PER_SEVERITY := 0.06
const GROWTH_PER_SEVERITY := 0.06
const PRICE_GROWTH_WEIGHT := 0.01
const STABILITY_PER_SEVERITY := 0.10
```

```gdscript
static func exposure(region_id: String) -> float:
	return float(catalog().get("exposure", {}).get(region_id, 1.0))


static func _on_network(state: GameState, region_id: String) -> bool:
	var region: RegionState = state.regions.get(region_id) as RegionState
	return region != null and region.control != SEPARATIST


static func region_shortfall(state: GameState, region_id: String) -> float:
	if not _on_network(state, region_id):
		return 0.0
	return clampf(national_shortfall(state) * exposure(region_id), 0.0, 1.0)


static func region_severity(state: GameState, region_id: String) -> float:
	if not _on_network(state, region_id):
		return 0.0
	return clampf(national_severity(state) * exposure(region_id), 0.0, 1.0)


static func supply_by_region(state: GameState) -> Dictionary:
	var out := {}
	for key in state.regions:
		out[String(key)] = 1.0 - region_shortfall(state, String(key))
	return out


static func heating_hardship(state: GameState, region_id: String) -> float:
	return region_severity(state, region_id) * HARDSHIP_PER_SEVERITY


static func reach_loss(state: GameState, region_id: String) -> float:
	return region_severity(state, region_id) * REACH_PER_SEVERITY


static func industry_jobs_loss(state: GameState, region_id: String) -> float:
	if not (region_id in catalog().get("industrial", [])):
		return 0.0
	return region_severity(state, region_id) * JOBS_PER_SEVERITY


static func growth_effect(state: GameState) -> float:
	if not is_active(state) or gas(state).reference_price <= 0.0:
		return 0.0
	var g := gas(state)
	var advantage := clampf((g.reference_price - g.price) / g.reference_price, -1.0, 1.0)
	return advantage * PRICE_GROWTH_WEIGHT - national_severity(state) * GROWTH_PER_SEVERITY


static func stability_drag(state: GameState) -> float:
	return national_severity(state) * STABILITY_PER_SEVERITY
```

In `godot/scripts/native/sim/households_sim.gd` `simulate`, replace the hardship line with:

```gdscript
		var hardship_target := minf(1.0, _hardship_target(region, h, definition) + GasSim.heating_hardship(state, h.region_id))
		h.hardship = clampf(h.hardship + (hardship_target - h.hardship) * 0.15, 0.0, 1.0)
```

In `godot/scripts/native/sim/regions_sim.gd` `_tick_region`, change the unemployment target to:

```gdscript
	var unemployment_target: float = clampf(
		national_unemployment + float(profile.get("unemployment_gap", 0.0))
		+ GasSim.industry_jobs_loss(state, region_id), 0.025, 0.45)
```

and change the line that starts `var reach_target: float = capacity + ...` by appending ` - GasSim.reach_loss(state, region_id)` to the end of its expression, before the control caps.

In `godot/scripts/native/sim/economy_sim.gd` `_apply_headline_stats`, change the growth line to:

```gdscript
	econ.growth_rate = clampf(
		econ.structural_growth_rate + econ.fiscal_impulse + _modifiers_sum(state, "gdp_growth")
		+ GasSim.growth_effect(state), -0.15, 0.20)
```

In `godot/scripts/native/sim/stability_sim.gd` `stability_breakdown`, add the entry `"Energy supply": -GasSim.stability_drag(state),` after `"State presence"`.

- [ ] **Step 4: Import, run the test, run the battery**

Expected: 0 failed for this file. Every non-calibration test in the battery must be green. Calibration misses go in the report for Task 8, and no band is touched.

- [ ] **Step 5: Mutation-check**
- `exposure` default `1.0` → `0.0` → "an unlisted region feels the national figure".
- Remove the `SEPARATIST` check → "territory outside state control is not on Ardenia's network".
- Remove the `clampf` in `region_shortfall` → "no region is more than wholly short".
- Drop `+ GasSim.heating_hardship(...)` → "six cold months raise hardship in Zavost".
- Make `industry_jobs_loss` ignore the industrial list → "the capital loses no industrial jobs".
- Drop `- GasSim.reach_loss(...)` → "the state reaches less of it".
- Use `national_shortfall` instead of `national_severity` in `stability_drag` → "weighted by severity" (0.25 vs 0.5).
- Drop the price advantage term → "gas 30% under the reference lifts growth".
- Remove `stored.foreign.gas.storage = 1.0`'s effect by deleting the draw in `flow` → "storage softens the winter cut" (calendar-true).

- [ ] **Step 6: Commit**

```bash
git add godot/scripts/native/sim/gas_sim.gd godot/scripts/native/sim/households_sim.gd godot/scripts/native/sim/regions_sim.gd \
  godot/scripts/native/sim/economy_sim.gd godot/scripts/native/sim/stability_sim.gd \
  godot/tests/native/test_gas_shortfall.gd godot/tests/native/test_gas_shortfall.gd.uid
git commit -m "feat(godot): gas shortfalls reach households, industry, state reach and stability

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The supplier: renewal, the coercion ladder, and the Union's gas

**Files:**
- Modify: `godot/scripts/native/sim/gas_sim.gd` (renewal, ladder, Union hooks, `monthly`)
- Modify: `godot/scripts/native/sim/world_sim.gd` (`_execute`)
- Modify: `godot/scripts/native/actions/orientation_actions.gd` (`_reach`, `_leave_union`)
- Test: `godot/tests/native/test_gas_supplier.gd`

**Interfaces:**
- Consumes: `ForeignSim.leverage_of(state, id)`, `DiplomacySim.pair/shift`, `WorldSim._execute`, `OrientationActions._reach/_leave_union`.
- Produces:
  - `GasSim.supplier_warmth(state) -> float`
  - `GasSim.crisis(state) -> bool`
  - `GasSim.cuts_blocked(state) -> bool`
  - `GasSim.coerce(state, actor: Country, notes: Array[String]) -> String` (returns `"gas_demand"`, `"gas_threat"` or `""`)
  - `GasSim.valve_threat(state) -> Dictionary`
  - `GasSim.on_union_join(state) -> void`, `GasSim.on_union_leave(state) -> void`
  - consts `ARREARS_DEMAND`, `DEMAND_INTERVAL`, `THREAT_AFTER_DEMAND`, `THREAT_LEVERAGE`, `CUT_COOLDOWN`, `CUT_SHARE_PER_LEVERAGE`, `CUT_MONTHS`, `DEFUSED_SHARE`, `TERM_MONTHS`, `RENEWAL_RISE`, `UNION_RESCHEDULED`, `UNION_CRISIS_WARMTH`, `EXIT_PRICE_RISE`

- [ ] **Step 1: Write the failing test**

Create `godot/tests/native/test_gas_supplier.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")


static func _state() -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	return state


static func _leverage(state: GameState, value: float) -> void:
	state.foreign.powers["krasova"]["leverage"] = value


static func _warmth(state: GameState, value: float) -> void:
	for r in DiplomacySim.pair(state, "krasova"):
		(r as Country.BilateralRelation).score = value


static func _member(state: GameState) -> void:
	state.foreign.reached["union_observer"] = state.turn
	OrientationActions._reach(state, "union_member")


static func _krasova(state: GameState) -> Country:
	return state.world_country("krasova")


func _test_renewal_prices_by_leverage(t) -> void:
	var state := _state()
	var notes: Array[String] = []
	_leverage(state, 0.5)
	state.turn = state.foreign.gas.term_end - 1
	GasSim._renew(state, notes)
	t.equal(state.foreign.gas.price, 50.0, "no renewal a month before the term ends")
	state.turn += 1
	GasSim._renew(state, notes)
	t.near(state.foreign.gas.price, 60.0, 0.000001, "at the term's end the price rises with leverage")
	t.equal(state.foreign.gas.term_end, state.turn + GasSim.TERM_MONTHS, "for a new three-year term")
	t.truth(notes.size() == 1, "and the renewal is reported")


func _test_renewal_respects_the_union_cap_and_the_second_line(t) -> void:
	var state := _state()
	_member(state)
	_leverage(state, 0.9)
	state.foreign.gas.second_line_volume = 2.0
	state.turn = state.foreign.gas.term_end
	GasSim._renew(state, [] as Array[String])
	t.near(state.foreign.gas.price, GasSim.union_cap(state.foreign.gas), 0.000001, "a member renews at the Union cap")
	t.near(state.foreign.gas.contracted_volume, 4.0, 0.000001, "and contracts only what the second line does not carry")


func _test_the_ladder_starts_with_a_demand(t) -> void:
	var state := _state()
	var notes: Array[String] = []
	_leverage(state, 0.6)
	state.foreign.gas.arrears = GasSim.ARREARS_DEMAND - 0.01
	t.equal(GasSim.coerce(state, _krasova(state), notes), "", "arrears just under the line draw no demand")
	state.foreign.gas.arrears = GasSim.ARREARS_DEMAND
	var warmth := GasSim.supplier_warmth(state)
	t.equal(GasSim.coerce(state, _krasova(state), notes), "gas_demand", "arrears at the line draw a demand")
	t.truth(GasSim.supplier_warmth(state) < warmth, "which cools relations")
	t.equal(state.foreign.gas.demands, 1, "and is counted")
	t.equal(GasSim.coerce(state, _krasova(state), notes), "", "nothing more is pressed the same month")
	t.equal(GasSim.coerce(state, state.world_country("solheim"), notes), "", "only the supplier can press for gas")


func _test_a_threat_follows_an_unheeded_demand(t) -> void:
	var state := _state()
	var notes: Array[String] = []
	_leverage(state, 0.6)
	state.foreign.gas.arrears = 80.0
	GasSim.coerce(state, _krasova(state), notes)
	state.turn += GasSim.THREAT_AFTER_DEMAND - 1
	t.equal(GasSim.coerce(state, _krasova(state), notes), "", "a threat waits two months after the demand")
	state.turn += 1
	_leverage(state, GasSim.THREAT_LEVERAGE - 0.01)
	t.equal(GasSim.coerce(state, _krasova(state), notes), "", "a supplier without leverage cannot threaten")
	_leverage(state, 0.6)
	t.equal(GasSim.coerce(state, _krasova(state), notes), "gas_threat", "with leverage it names a date")
	var threat := GasSim.valve_threat(state)
	t.equal(int(threat["due"]), state.turn + 1, "the cut is foreshadowed a month ahead")
	t.near(float(threat["share"]), 0.24, 0.000001, "and scales with leverage")
	t.equal(GasSim.coerce(state, _krasova(state), notes), "", "a pending threat is not repeated")


func _test_a_threat_becomes_a_cut_unless_defused(t) -> void:
	var state := _state()
	var notes: Array[String] = []
	state.foreign.gas.arrears = 80.0
	state.foreign.gas.threat = {"turn": state.turn, "due": state.turn + 1, "share": 0.3}
	GasSim._mature_threat(state, notes)
	t.equal(state.foreign.gas.cut, 0.0, "nothing is cut before the named date")
	state.turn += 1
	GasSim._mature_threat(state, notes)
	t.near(state.foreign.gas.cut, 0.3, 0.000001, "on the date the valve turns")
	t.equal(state.foreign.gas.cut_until, state.turn + GasSim.CUT_MONTHS, "for two months")
	t.equal(state.foreign.gas.cuts, 1, "and the cut is counted")
	state.turn = state.foreign.gas.cut_until - 1
	GasSim._restore(state, notes)
	t.near(state.foreign.gas.cut, 0.3, 0.000001, "the cut holds through its second month")
	state.turn += 1
	GasSim._restore(state, notes)
	t.equal(state.foreign.gas.cut, 0.0, "and then the gas returns")
	var paid := _state()
	paid.foreign.gas.arrears = GasSim.ARREARS_DEMAND * GasSim.DEFUSED_SHARE - 0.01
	paid.foreign.gas.threat = {"turn": paid.turn, "due": paid.turn, "share": 0.3}
	GasSim._mature_threat(paid, notes)
	t.equal(paid.foreign.gas.cut, 0.0, "paying the arrears down defuses the threat")
	t.truth(paid.foreign.gas.threat.is_empty(), "and the threat lapses")


func _test_a_cut_is_not_repeated_within_two_years(t) -> void:
	var state := _state()
	var notes: Array[String] = []
	_leverage(state, 0.6)
	state.foreign.gas.arrears = 80.0
	state.foreign.gas.last_demand_turn = state.turn - GasSim.THREAT_AFTER_DEMAND
	state.foreign.gas.last_cut_turn = state.turn - GasSim.CUT_COOLDOWN + 1
	t.equal(GasSim.coerce(state, _krasova(state), notes), "", "no new threat within two years of a cut")
	state.foreign.gas.last_cut_turn = state.turn - GasSim.CUT_COOLDOWN
	t.equal(GasSim.coerce(state, _krasova(state), notes), "gas_threat", "after two years the valve is mentioned again")


func _test_the_union_shields_its_members_short_of_a_crisis(t) -> void:
	var state := _state()
	var notes: Array[String] = []
	state.foreign.gas.arrears = 100.0
	state.foreign.gas.cut = 0.3
	state.foreign.gas.cut_until = state.turn + 2
	_member(state)
	t.near(state.foreign.gas.price, 35.0, 0.000001, "membership caps the gas price")
	t.near(state.foreign.gas.arrears, 50.0, 0.000001, "and reschedules half the arrears")
	t.equal(state.foreign.gas.cut, 0.0, "and ends a running cut")
	_leverage(state, 0.9)
	_warmth(state, GasSim.UNION_CRISIS_WARMTH)
	state.foreign.gas.arrears = 100.0
	state.foreign.gas.last_demand_turn = state.turn - GasSim.THREAT_AFTER_DEMAND
	t.equal(GasSim.coerce(state, _krasova(state), notes), "", "a member at the crisis line is not threatened")
	_warmth(state, GasSim.UNION_CRISIS_WARMTH - 0.01)
	t.equal(GasSim.coerce(state, _krasova(state), notes), "gas_threat", "but in a crisis even a member hears of the valve")


func _test_leaving_the_union_costs_its_gas(t) -> void:
	var state := _state()
	_member(state)
	OrientationActions._leave_union(state)
	t.near(state.foreign.gas.price, 50.0 * (1.0 + GasSim.EXIT_PRICE_RISE), 0.000001, "walking out loses the Union price and then some")
	t.equal(state.foreign.gas.term_end, state.turn + GasSim.TERM_MONTHS, "on a fresh term")
	t.truth(StateValidator.validate(state).is_empty(), "and the ledger stays valid")


func _test_the_world_ai_presses_with_gas(t) -> void:
	var state := _state()
	var notes: Array[String] = []
	var krasova := _krasova(state)
	state.foreign.gas.arrears = 80.0
	krasova.plan = {"objective": "undermine", "target": state.country.id, "matures_turn": state.turn}
	t.equal(WorldSim._execute(state, krasova, notes), "gas_demand", "Krasova's matured plan against Ardenia takes a gas move first")
	state.foreign.gas.arrears = 0.0
	state.foreign.gas.last_demand_turn = -1
	t.truth(WorldSim._execute(state, krasova, notes) in ["condemned", "undermined", "shelved"], "and without arrears falls back to ordinary pressure")


func _test_the_cut_lands_on_the_named_month(t) -> void:
	var state := _state()
	var notes: Array[String] = []
	state.foreign.gas.arrears = 80.0
	state.foreign.gas.threat = {"turn": state.turn, "due": state.turn + 1, "share": 0.3}
	NativeGameScript.next_month(state)
	t.near(state.foreign.gas.cut, 0.3, 0.000001, "the next calendar month closes with the valve turned")
	t.near(GasSim.national_shortfall(state), 0.3, 0.000001, "and that month's gas is short")
	NativeGameScript.next_month(state)
	t.near(state.foreign.gas.cut, 0.3, 0.000001, "the second month is short too")
	NativeGameScript.next_month(state)
	t.equal(state.foreign.gas.cut, 0.0, "the third is not")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_renewal_prices_by_leverage(t)
	_test_renewal_respects_the_union_cap_and_the_second_line(t)
	_test_the_ladder_starts_with_a_demand(t)
	_test_a_threat_follows_an_unheeded_demand(t)
	_test_a_threat_becomes_a_cut_unless_defused(t)
	_test_a_cut_is_not_repeated_within_two_years(t)
	_test_the_union_shields_its_members_short_of_a_crisis(t)
	_test_leaving_the_union_costs_its_gas(t)
	_test_the_world_ai_presses_with_gas(t)
	_test_the_cut_lands_on_the_named_month(t)
	quit(t.finish())
```

- [ ] **Step 2: Run test to verify it fails**

Expected: exit 124 with `SCRIPT ERROR` (`GasSim._renew` not found).

- [ ] **Step 3: Implement the supplier**

Add to `godot/scripts/native/sim/gas_sim.gd`:

```gdscript
const ARREARS_DEMAND := 60.0
const DEMAND_INTERVAL := 6
const THREAT_AFTER_DEMAND := 2
const THREAT_LEVERAGE := 0.5
const CUT_COOLDOWN := 24
const CUT_SHARE_PER_LEVERAGE := 0.4
const CUT_MONTHS := 2
const DEFUSED_SHARE := 0.5
const DEMAND_RELATIONS := -0.03
const TERM_MONTHS := 36
const RENEWAL_RISE := 0.4
const UNION_RESCHEDULED := 0.5
const UNION_CRISIS_WARMTH := -0.5
const EXIT_PRICE_RISE := 0.2
```

Replace `monthly` with:

```gdscript
static func monthly(state: GameState) -> Array[String]:
	var notes: Array[String] = []
	if not is_active(state):
		return notes
	_renew(state, notes)
	_restore(state, notes)
	_mature_threat(state, notes)
	flow(state)
	write_share(state)
	if national_shortfall(state) >= SHORTFALL_NOTE:
		notes.append(line("gas_shortfall", {"share": roundi(national_shortfall(state) * 100.0)}))
	return notes
```

Add:

```gdscript
static func supplier_warmth(state: GameState) -> float:
	var p := DiplomacySim.pair(state, gas(state).supplier_id)
	return 0.0 if p.is_empty() else (p[0] as Country.BilateralRelation).score


static func crisis(state: GameState) -> bool:
	return supplier_warmth(state) < UNION_CRISIS_WARMTH


static func cuts_blocked(state: GameState) -> bool:
	return union_member(state) and not crisis(state)


static func valve_threat(state: GameState) -> Dictionary:
	return {} if not is_active(state) else gas(state).threat.duplicate()


static func coerce(state: GameState, actor: Country, notes: Array[String]) -> String:
	if actor == null or not is_active(state) or actor.id != gas(state).supplier_id:
		return ""
	var g := gas(state)
	if not g.threat.is_empty() or g.cut > 0.0 or g.arrears < ARREARS_DEMAND:
		return ""
	if g.last_demand_turn < 0 or state.turn - g.last_demand_turn >= DEMAND_INTERVAL:
		g.last_demand_turn = state.turn
		g.demands += 1
		DiplomacySim.shift(state, actor.id, DEMAND_RELATIONS, "Pressed for the gas arrears.")
		notes.append(line("gas_demand", {"supplier": actor.name, "arrears": roundi(g.arrears)}))
		return "gas_demand"
	var leverage := ForeignSim.leverage_of(state, actor.id)
	var cooling := g.last_cut_turn >= 0 and state.turn - g.last_cut_turn < CUT_COOLDOWN
	if state.turn - g.last_demand_turn < THREAT_AFTER_DEMAND or leverage < THREAT_LEVERAGE \
			or cooling or cuts_blocked(state):
		return ""
	g.threat = {"turn": state.turn, "due": state.turn + 1,
		"share": clampf(CUT_SHARE_PER_LEVERAGE * leverage, 0.0, 1.0)}
	g.threats += 1
	notes.append(line("gas_threat", {"supplier": actor.name}))
	return "gas_threat"


static func _renew(state: GameState, notes: Array[String]) -> void:
	var g := gas(state)
	if state.turn < g.term_end:
		return
	var price := g.reference_price * (1.0 + RENEWAL_RISE * ForeignSim.leverage_of(state, g.supplier_id))
	if union_member(state):
		price = minf(price, union_cap(g))
	g.price = price
	g.contracted_volume = maxf(0.0, g.annual_demand - g.second_line_volume)
	g.term_end = state.turn + TERM_MONTHS
	notes.append(line("gas_renewal", {"price": snappedf(price, 0.1)}))


static func _restore(state: GameState, notes: Array[String]) -> void:
	var g := gas(state)
	if g.cut > 0.0 and (state.turn >= g.cut_until or cuts_blocked(state)):
		g.cut = 0.0
		g.cut_until = -1
		notes.append(line("gas_restored"))


static func _mature_threat(state: GameState, notes: Array[String]) -> void:
	var g := gas(state)
	if g.threat.is_empty() or state.turn < int(g.threat["due"]):
		return
	var share := float(g.threat["share"])
	g.threat = {}
	if cuts_blocked(state) or g.arrears < ARREARS_DEMAND * DEFUSED_SHARE:
		notes.append(line("gas_threat_lapsed"))
		return
	g.cut = share
	g.cut_until = state.turn + CUT_MONTHS
	g.last_cut_turn = state.turn
	g.cuts += 1
	notes.append(line("gas_cut", {"share": roundi(share * 100.0)}))


static func on_union_join(state: GameState) -> void:
	if not is_active(state):
		return
	var g := gas(state)
	g.price = minf(g.price, union_cap(g))
	g.arrears *= 1.0 - UNION_RESCHEDULED
	g.threat = {}
	g.cut = 0.0
	g.cut_until = -1


static func on_union_leave(state: GameState) -> void:
	if not is_active(state):
		return
	var g := gas(state)
	g.price = maxf(g.price, g.reference_price * (1.0 + EXIT_PRICE_RISE))
	g.term_end = state.turn + TERM_MONTHS
```

In `godot/scripts/native/sim/world_sim.gd` `_execute`, replace the `"undermine":` arm with:

```gdscript
		"undermine":
			if target == state.country:
				var gas_move := GasSim.coerce(state, actor, notes)
				if gas_move != "":
					return gas_move
			return hostile_action(state, actor, target, notes)
```

In `godot/scripts/native/actions/orientation_actions.gd`:
- In `_reach`'s `"union_member":` arm, add `GasSim.on_union_join(state)` as the arm's last line.
- In `_leave_union`, after `state.modifiers = state.modifiers.filter(...)` (the member path), add `GasSim.on_union_leave(state)`.

- [ ] **Step 4: Import, run the test, run the battery**

Expected: 0 failed for this file. The world AI now spends some undermine turns on gas moves that draw no RNG, so seeded journeys shift. Record any calibration misses for Task 8 and leave all bands alone. Every non-calibration test must be green.

- [ ] **Step 5: Mutation-check**
- `state.turn < g.term_end` → `<=` → "at the term's end the price rises"; `- 1`-turn check → "no renewal a month before".
- Remove the Union `minf` in `_renew` → "a member renews at the Union cap".
- `g.arrears < ARREARS_DEMAND` → `<=` → "arrears at the line draw a demand".
- `< THREAT_AFTER_DEMAND` → `< THREAT_AFTER_DEMAND - 1` → "a threat waits two months".
- `leverage < THREAT_LEVERAGE` → `leverage < 0.0` → "a supplier without leverage cannot threaten".
- `< CUT_COOLDOWN` → `<= CUT_COOLDOWN` → "after two years the valve is mentioned again".
- `"due": state.turn + 1` → `+ 2` → "foreshadowed a month ahead" and the calendar-true "next calendar month closes with the valve turned".
- `crisis` `<` → `<=` → "a member at the crisis line is not threatened".
- Remove `or cuts_blocked(state)` from `_restore` → "and ends a running cut".
- Remove the `DEFUSED_SHARE` check → "paying the arrears down defuses the threat".
- Call `_mature_threat` after `flow` in `monthly` → "and that month's gas is short" (real calendar).
- Remove the `GasSim.coerce` branch in `_execute` → "takes a gas move first".

- [ ] **Step 6: Commit**

```bash
git add godot/scripts/native/sim/gas_sim.gd godot/scripts/native/sim/world_sim.gd godot/scripts/native/actions/orientation_actions.gd \
  godot/tests/native/test_gas_supplier.gd godot/tests/native/test_gas_supplier.gd.uid
git commit -m "feat(godot): Krasova prices, presses and cuts by leverage; the Union caps gas

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The player's energy operations

**Files:**
- Create: `godot/scripts/native/actions/energy_actions.gd`
- Modify: `godot/scripts/native/sim/gas_sim.gd` (projects, `monthly`)
- Modify: `godot/scripts/native/native_game.gd` (`energy_act`)
- Test: `godot/tests/native/test_energy_actions.gd`

**Interfaces:**
- Consumes: Tasks 1–4; `OrientationActions.reason_for/act/COSTS`, `OrientationSim.timed_modifier(id, source, target, magnitude, hold, institutional)`, `EffectBundle.apply`, `DiplomacySim.shift`.
- Produces:
  - `EnergyActions.VERBS`
  - `EnergyActions.act(state, verb: String) -> Dictionary` (`{ok, message}` or `{ok: false, error}`)
  - `EnergyActions.reason_for(state, verb) -> String`
  - `EnergyActions.label_for(verb) -> String`
  - `EnergyActions.read_model(state) -> Dictionary`
  - `GasSim.STORAGE_MONTHS`, `GasSim.SECOND_LINE_MONTHS`, `GasSim.SECOND_LINE_OPENING`, `GasSim._advance_projects`
  - `NativeGame.energy_act(verb: String) -> Dictionary`

- [ ] **Step 1: Write the failing test**

Create `godot/tests/native/test_energy_actions.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")


static func _state(role: String = "government") -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": role, "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	state.player.political_capital = 500.0
	return state


static func _warmth(state: GameState) -> float:
	return GasSim.supplier_warmth(state)


func _test_energy_belongs_to_the_government(t) -> void:
	var state := _state("opposition")
	for verb in EnergyActions.VERBS:
		t.truth(EnergyActions.reason_for(state, verb).contains("belongs to the government"), "%s is refused in opposition" % verb)


func _test_paying_the_arrears(t) -> void:
	var state := _state()
	var debt := state.country.economy.public_debt_pct
	var warmth := _warmth(state)
	t.truth(EnergyActions.act(state, "gas_pay_arrears").get("ok", false), "the arrears can be paid")
	t.equal(state.foreign.gas.arrears, 0.0, "all forty are cleared")
	t.near(state.country.economy.public_debt_pct - debt, 40.0 / state.country.economy.gdp, 0.0000001, "with borrowed hard currency")
	t.truth(_warmth(state) >= warmth, "Krasova does not mind being paid")
	t.truth(EnergyActions.reason_for(state, "gas_pay_arrears").contains("no gas arrears"), "nothing left to pay is refused")
	state.foreign.gas.arrears = 120.0
	EnergyActions.act(state, "gas_pay_arrears")
	t.near(state.foreign.gas.arrears, 70.0, 0.000001, "a large debt is paid one tranche at a time")


func _test_a_spot_cargo_covers_a_cut(t) -> void:
	var state := _state()
	var debt := state.country.economy.public_debt_pct
	t.truth(EnergyActions.act(state, "gas_spot_purchase").get("ok", false), "a spot cargo can be bought")
	t.near(state.country.economy.public_debt_pct - debt, 0.5 * 50.0 * EnergyActions.SPOT_PREMIUM / state.country.economy.gdp, 0.0000001, "at a premium")
	t.truth(EnergyActions.reason_for(state, "gas_spot_purchase") != "", "and only one can be on its way")
	state.month = 1
	state.foreign.gas.cut = 0.5
	state.foreign.gas.cut_until = state.turn + 12
	GasSim.flow(state)
	t.near(GasSim.national_shortfall(state), 0.0, 0.000001, "the cargo fills a January cut")
	t.equal(state.foreign.gas.spot_pending, 0.0, "and is used up")


func _test_storage_is_built_over_two_years(t) -> void:
	var state := _state()
	t.truth(EnergyActions.act(state, "gas_storage").get("ok", false), "storage can be commissioned")
	t.truth(state.modifiers.any(func(m: Modifier) -> bool: return m.source_id == "gas_storage" and m.target == "budget_expenditure"), "and is paid for from the budget")
	t.truth(EnergyActions.reason_for(state, "gas_storage") != "", "once")
	for _i in range(GasSim.STORAGE_MONTHS / 2):
		NativeGameScript.next_month(state)
	t.near(state.foreign.gas.storage_capacity, 0.5, 0.000001, "half is built after a year")
	for _i in range(GasSim.STORAGE_MONTHS / 2 - 1):
		NativeGameScript.next_month(state)
	t.truth(state.foreign.gas.storage_capacity < 1.0, "not all of it a month early")
	NativeGameScript.next_month(state)
	t.near(state.foreign.gas.storage_capacity, 1.0, 0.000001, "all of it after two years")


func _test_the_second_line_takes_four_years_and_angers_krasova(t) -> void:
	var state := _state()
	var warmth := _warmth(state)
	t.truth(EnergyActions.act(state, "gas_second_line").get("ok", false), "the second line can be started")
	t.near(warmth - _warmth(state), -EnergyActions.SECOND_LINE_HOSTILITY, 0.000001, "Krasova takes it as hostile")
	for _i in range(GasSim.SECOND_LINE_MONTHS - 1):
		NativeGameScript.next_month(state)
	t.equal(state.foreign.gas.second_line_volume, 0.0, "nothing flows a month early")
	NativeGameScript.next_month(state)
	t.near(state.foreign.gas.second_line_volume, 2.0, 0.000001, "after four years the line opens")
	t.truth(float(state.foreign.gas_share["krasova"]) < 1.0, "and Krasova's share of Ardenia's gas falls")


func _test_renegotiation_trades_price_for_concessions(t) -> void:
	var state := _state()
	var revenue_before := state.modifiers.size()
	t.truth(EnergyActions.act(state, "gas_renegotiate_transit").get("ok", false), "transit fees can be conceded")
	t.near(state.foreign.gas.price, 45.0, 0.000001, "for a lower price")
	t.truth(state.modifiers.size() == revenue_before + 1 and state.modifiers.any(func(m: Modifier) -> bool: return m.source_id == "gas_transit_concession" and m.target == "budget_revenue" and m.magnitude < 0.0), "at the cost of the transit revenue")
	state.turn += EnergyActions.RENEGOTIATE_COOLDOWN - 1
	t.truth(EnergyActions.reason_for(state, "gas_renegotiate_union").contains("will not reopen"), "the contract cannot be reopened within the year")
	state.turn += 1
	t.truth(EnergyActions.reason_for(state, "gas_renegotiate_transit").contains("already been conceded"), "and transit fees can be conceded once")
	var capital := state.player.political_capital
	t.truth(EnergyActions.act(state, "gas_renegotiate_union").get("ok", false), "after a year a Union step can be traded")
	t.truth(state.foreign.reached.has("union_observer"), "Ardenia takes observer status")
	t.near(state.foreign.gas.price, 45.0 * 0.85, 0.000001, "for a further discount")
	t.near(capital - state.player.political_capital, 20.0, 0.000001, "paying for the step and the talks")


func _test_shelving_the_second_line(t) -> void:
	var state := _state()
	t.truth(EnergyActions.reason_for(state, "gas_renegotiate_policy").contains("no second line"), "there is nothing to shelve yet")
	EnergyActions.act(state, "gas_second_line")
	var warmth := _warmth(state)
	t.truth(EnergyActions.act(state, "gas_renegotiate_policy").get("ok", false), "a line under construction can be shelved")
	t.equal(state.foreign.gas.second_line_started, -1, "the project stops")
	t.truth(not state.modifiers.any(func(m: Modifier) -> bool: return m.source_id == "gas_second_line"), "and so do its costs")
	t.truth(_warmth(state) > warmth, "Krasova is pleased")
	t.near(state.foreign.gas.price, 45.0, 0.000001, "and cuts the price")


func _test_renegotiation_needs_tolerable_relations_and_a_floor(t) -> void:
	var state := _state()
	for r in DiplomacySim.pair(state, "krasova"):
		(r as Country.BilateralRelation).score = EnergyActions.RENEGOTIATE_WARMTH - 0.01
	t.truth(EnergyActions.reason_for(state, "gas_renegotiate_transit").contains("too cold"), "a hostile supplier will not talk")
	for r in DiplomacySim.pair(state, "krasova"):
		(r as Country.BilateralRelation).score = EnergyActions.RENEGOTIATE_WARMTH
	t.equal(EnergyActions.reason_for(state, "gas_renegotiate_transit"), "", "at the line it will")
	state.foreign.gas.price = 26.0
	EnergyActions.act(state, "gas_renegotiate_transit")
	t.near(state.foreign.gas.price, 25.0, 0.000001, "and never sells below half the reference")


func _test_a_refused_operation_changes_nothing(t) -> void:
	var state := _state()
	state.player.political_capital = 4.0
	var before := state.foreign.gas.to_dict()
	var result := EnergyActions.act(state, "gas_spot_purchase")
	t.truth(not result.get("ok", true) and String(result["error"]).contains("political capital"), "too little capital is refused")
	t.equal(state.foreign.gas.to_dict(), before, "and changes nothing")
	t.equal(state.player.political_capital, 4.0, "and costs nothing")


func _test_the_game_runs_energy_operations(t) -> void:
	var game: Node = NativeGameScript.new()
	game._state = _state()
	var result: Dictionary = game.energy_act("gas_pay_arrears")
	t.truth(result.get("ok", false) and result.has("snapshot"), "an operation runs through the game and returns a snapshot")
	t.truth(not game.energy_act("gas_pay_arrears").get("ok", true), "and refusals come back")
	game.free()


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_energy_belongs_to_the_government(t)
	_test_paying_the_arrears(t)
	_test_a_spot_cargo_covers_a_cut(t)
	_test_storage_is_built_over_two_years(t)
	_test_the_second_line_takes_four_years_and_angers_krasova(t)
	_test_renegotiation_trades_price_for_concessions(t)
	_test_shelving_the_second_line(t)
	_test_renegotiation_needs_tolerable_relations_and_a_floor(t)
	_test_a_refused_operation_changes_nothing(t)
	_test_the_game_runs_energy_operations(t)
	quit(t.finish())
```

- [ ] **Step 2: Run test to verify it fails**

Expected: exit 124 with `SCRIPT ERROR` (`EnergyActions` not declared).

- [ ] **Step 3: Implement the operations and the projects**

Add to `godot/scripts/native/sim/gas_sim.gd`:

```gdscript
const STORAGE_MONTHS := 24
const SECOND_LINE_MONTHS := 48
const SECOND_LINE_OPENING := -0.1
```

In `monthly`, insert `_advance_projects(state, notes)` between `_mature_threat(state, notes)` and `flow(state)`, and add:

```gdscript
static func _advance_projects(state: GameState, notes: Array[String]) -> void:
	var g := gas(state)
	if g.storage_started >= 0 and g.storage_capacity < g.storage_target:
		var built := clampf(float(state.turn - g.storage_started) / float(STORAGE_MONTHS), 0.0, 1.0)
		g.storage_capacity = g.storage_target * built
		if built >= 1.0:
			notes.append(line("storage_ready"))
	if g.second_line_started >= 0 and g.second_line_volume <= 0.0 \
			and state.turn - g.second_line_started >= SECOND_LINE_MONTHS:
		g.second_line_volume = float(catalog().get("second_line", {}).get("volume", 0.0))
		DiplomacySim.shift(state, g.supplier_id, SECOND_LINE_OPENING, "Ardenia opened a gas line around Krasova.")
		notes.append(line("second_line_open"))
```

Create `godot/scripts/native/actions/energy_actions.gd`:

```gdscript
class_name EnergyActions
extends RefCounted


const VERBS := ["gas_pay_arrears", "gas_renegotiate_transit", "gas_renegotiate_union", "gas_renegotiate_policy",
	"gas_spot_purchase", "gas_storage", "gas_second_line"]
const COSTS := {"gas_pay_arrears": 0.0, "gas_renegotiate_transit": 10.0, "gas_renegotiate_union": 10.0,
	"gas_renegotiate_policy": 10.0, "gas_spot_purchase": 5.0, "gas_storage": 15.0, "gas_second_line": 25.0}
const LABELS := {
	"gas_pay_arrears": "Pay down the gas arrears",
	"gas_renegotiate_transit": "Renegotiate: concede transit fees",
	"gas_renegotiate_union": "Renegotiate: take Union observer status",
	"gas_renegotiate_policy": "Renegotiate: shelve the second line",
	"gas_spot_purchase": "Emergency spot purchase",
	"gas_storage": "Build gas storage",
	"gas_second_line": "Build a second supply line",
}
const ARREARS_TRANCHE := 50.0
const PAYMENT_GOODWILL := 0.02
const RENEGOTIATE_COOLDOWN := 12
const RENEGOTIATE_WARMTH := -0.7
const PRICE_CUTS := {"gas_renegotiate_transit": 0.9, "gas_renegotiate_union": 0.85, "gas_renegotiate_policy": 0.9}
const PRICE_FLOOR_SHARE := 0.5
const TRANSIT_FEES := 20.0
const SHELVE_GOODWILL := 0.1
const SPOT_VOLUME := 0.5
const SPOT_PREMIUM := 1.8
const STORAGE_TARGET := 1.0
const STORAGE_COST := 40.0
const SECOND_LINE_COST := 60.0
const SECOND_LINE_HOSTILITY := -0.15


static func act(state: GameState, verb: String) -> Dictionary:
	var reason := reason_for(state, verb)
	if reason != "":
		return {"ok": false, "error": reason}
	state.player.political_capital -= float(COSTS[verb])
	var message := ""
	match verb:
		"gas_pay_arrears":
			message = _pay(state)
		"gas_spot_purchase":
			message = _spot(state)
		"gas_storage":
			message = _storage(state)
		"gas_second_line":
			message = _second_line(state)
		_:
			message = _renegotiate(state, verb)
	ForeignSim.update_spine(state)
	return {"ok": true, "message": message}


static func label_for(verb: String) -> String:
	return String(LABELS.get(verb, verb))


static func reason_for(state: GameState, verb: String) -> String:
	if state == null or state.player == null:
		return "No campaign is active."
	if not COSTS.has(verb):
		return "Unknown energy step."
	if not state.player.in_government:
		return "Energy policy belongs to the government."
	if not GasSim.is_active(state):
		return "Ardenia has no gas contract to manage."
	var condition := _condition_reason(state, verb)
	if condition != "":
		return condition
	if state.player.political_capital < _capital_needed(verb):
		return "Requires %.0f political capital." % _capital_needed(verb)
	return ""


static func _capital_needed(verb: String) -> float:
	var extra := float(OrientationActions.COSTS["union_observer"]) if verb == "gas_renegotiate_union" else 0.0
	return float(COSTS[verb]) + extra


static func _condition_reason(state: GameState, verb: String) -> String:
	var g := state.foreign.gas
	match verb:
		"gas_pay_arrears":
			if g.arrears <= 0.0:
				return "There are no gas arrears to pay."
		"gas_spot_purchase":
			if g.spot_pending > 0.0:
				return "A spot cargo is already on its way."
		"gas_storage":
			if g.storage_started >= 0:
				return "The storage programme is already under way."
		"gas_second_line":
			if g.second_line_started >= 0:
				return "The second line is already under way."
		_:
			return _renegotiation_reason(state, verb)
	return ""


static func _renegotiation_reason(state: GameState, verb: String) -> String:
	var g := state.foreign.gas
	if g.last_renegotiated >= 0 and state.turn - g.last_renegotiated < RENEGOTIATE_COOLDOWN:
		return "The supplier will not reopen the contract for %d more months." % [
			RENEGOTIATE_COOLDOWN - (state.turn - g.last_renegotiated)]
	if GasSim.supplier_warmth(state) < RENEGOTIATE_WARMTH:
		return "Relations with the supplier are too cold to reopen the contract (needs %.2f)." % RENEGOTIATE_WARMTH
	match verb:
		"gas_renegotiate_transit":
			if "transit" in g.concessions:
				return "The transit fees have already been conceded."
		"gas_renegotiate_union":
			return OrientationActions.reason_for(state, "union_observer")
		"gas_renegotiate_policy":
			if g.second_line_started < 0 or g.second_line_volume > 0.0:
				return "There is no second line under construction to shelve."
	return ""


static func _pay(state: GameState) -> String:
	var g := state.foreign.gas
	var amount := minf(g.arrears, ARREARS_TRANCHE)
	g.arrears -= amount
	EffectBundle.apply(state, {"one_time_debt_pct_delta": amount / state.country.economy.gdp}, "energy", "gas_pay_arrears")
	DiplomacySim.shift(state, g.supplier_id, PAYMENT_GOODWILL, "Ardenia paid down its gas arrears.")
	return "The treasury pays %.0f million kron of the Zovar arrears in hard currency; %.0f remains." % [amount, g.arrears]


static func _spot(state: GameState) -> String:
	var g := state.foreign.gas
	var cost := SPOT_VOLUME * g.price * SPOT_PREMIUM
	g.spot_pending = SPOT_VOLUME
	EffectBundle.apply(state, {"one_time_debt_pct_delta": cost / state.country.economy.gdp}, "energy", "gas_spot_purchase")
	return "A spot cargo of %.1f units is bought for %.0f million kron. It arrives with next month's deliveries." % [SPOT_VOLUME, cost]


static func _storage(state: GameState) -> String:
	var g := state.foreign.gas
	g.storage_started = state.turn
	g.storage_target = STORAGE_TARGET
	state.modifiers.append(OrientationSim.timed_modifier("gas_storage", "Gas storage programme",
		"budget_expenditure", STORAGE_COST, GasSim.STORAGE_MONTHS - 1, false))
	return "Work begins on gas storage. In %d months Ardenia can carry summer gas into the winter." % GasSim.STORAGE_MONTHS


static func _second_line(state: GameState) -> String:
	var g := state.foreign.gas
	g.second_line_started = state.turn
	state.modifiers.append(OrientationSim.timed_modifier("gas_second_line", "Second supply line",
		"budget_expenditure", SECOND_LINE_COST, GasSim.SECOND_LINE_MONTHS - 1, false))
	DiplomacySim.shift(state, g.supplier_id, SECOND_LINE_HOSTILITY, "Ardenia is building a gas line around Krasova.")
	return "Ardenia begins a second supply line. It will take %d months, and Krasova has noticed." % GasSim.SECOND_LINE_MONTHS


static func _renegotiate(state: GameState, verb: String) -> String:
	var g := state.foreign.gas
	match verb:
		"gas_renegotiate_transit":
			g.concessions.append("transit")
			state.modifiers.append(OrientationSim.timed_modifier("gas_transit_concession", "Zovar transit fees conceded",
				"budget_revenue", -TRANSIT_FEES, Modifier.HOLDS_FOREVER, false))
		"gas_renegotiate_union":
			OrientationActions.act(state, "union_observer")
		"gas_renegotiate_policy":
			g.second_line_started = -1
			state.modifiers = state.modifiers.filter(func(m: Modifier) -> bool: return m.source_id != "gas_second_line")
			DiplomacySim.shift(state, g.supplier_id, SHELVE_GOODWILL, "Ardenia shelved its second gas line.")
	g.price = maxf(g.reference_price * PRICE_FLOOR_SHARE, g.price * float(PRICE_CUTS[verb]))
	g.last_renegotiated = state.turn
	return "The supplier agrees a price of %.1f a unit until the contract is renewed." % g.price


static func _second_line_status(state: GameState) -> String:
	var g := state.foreign.gas
	if g.second_line_volume > 0.0:
		return "open"
	if g.second_line_started < 0:
		return "none"
	return "building, %d months left" % maxi(0, GasSim.SECOND_LINE_MONTHS - (state.turn - g.second_line_started))


static func read_model(state: GameState) -> Dictionary:
	if state == null or state.foreign == null or not GasSim.is_active(state):
		return {"active": false, "steps": []}
	var g := state.foreign.gas
	var steps: Array = []
	for verb in VERBS:
		var reason := reason_for(state, verb)
		steps.append({"verb": verb, "label": label_for(verb), "cost": _capital_needed(verb),
			"eligible": reason == "", "disabled_reason": reason})
	var supplier := state.world_country(g.supplier_id)
	return {"active": true, "supplier": supplier.name if supplier != null else g.supplier_id,
		"price": g.price, "reference_price": g.reference_price, "arrears": g.arrears,
		"months_to_renewal": maxi(0, g.term_end - state.turn), "contracted_volume": g.contracted_volume,
		"storage": g.storage, "storage_capacity": g.storage_capacity, "second_line": _second_line_status(state),
		"cut": g.cut, "threat": not g.threat.is_empty(), "shortfall": GasSim.national_shortfall(state),
		"union_capped": GasSim.union_member(state), "cuts": g.cuts, "steps": steps}
```

In `godot/scripts/native/native_game.gd`, after `orientation_act`, add:

```gdscript
func energy_act(verb: String) -> Dictionary:
	return _guarded(func() -> Dictionary: return EnergyActions.act(_state, verb))
```

- [ ] **Step 4: Import, run the test, run the battery**

Expected: 0 failed for this file. All non-calibration tests green.

- [ ] **Step 5: Mutation-check**
- `ARREARS_TRANCHE` in `minf` → `g.arrears` → "a large debt is paid one tranche at a time".
- Remove the `spot_pending` read in `flow` (alternative without `+ g.spot_pending`) → "the cargo fills a January cut".
- `float(state.turn - g.storage_started)` → `+ 1` → "half is built after a year" (calendar-true) and "not all of it a month early".
- `>= SECOND_LINE_MONTHS` → `>= SECOND_LINE_MONTHS - 1` → "nothing flows a month early" (calendar-true).
- `< RENEGOTIATE_COOLDOWN` → `< RENEGOTIATE_COOLDOWN - 1` → "cannot be reopened within the year".
- `< RENEGOTIATE_WARMTH` → `<=` → "at the line it will".
- Remove the `PRICE_FLOOR_SHARE` `maxf` → "never sells below half the reference".
- Drop the extra observer cost in `_capital_needed` → "paying for the step and the talks".
- Move the PC deduction before `reason_for` → "and costs nothing".

- [ ] **Step 6: Commit**

```bash
git add godot/scripts/native/actions/energy_actions.gd godot/scripts/native/actions/energy_actions.gd.uid \
  godot/scripts/native/sim/gas_sim.gd godot/scripts/native/native_game.gd \
  godot/tests/native/test_energy_actions.gd godot/tests/native/test_energy_actions.gd.uid
git commit -m "feat(godot): pay, renegotiate, buy spot gas, store it and build a second line

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The snapshot, the map hand-off and the Diplomacy desk energy section

**Files:**
- Modify: `godot/scripts/native/actions/orientation_actions.gd` (`read_model`)
- Modify: `godot/scenes/panels/diplomacy_panel.tscn` (four nodes after `OrientationRule`)
- Modify: `godot/scripts/app.gd` (`_refresh_diplomacy`, `_refresh_orientation`, new `_add_step_button`, `_refresh_energy`, `_energy_line`, `_take_energy_step`)
- Test: `godot/tests/native/test_energy_snapshot.gd`, `godot/tests/ui/test_energy_desk.gd`

**Interfaces:**
- Consumes: `EnergyActions.read_model`, `GasSim.supply_by_region`, `NativeGame.energy_act`.
- Produces: snapshot `foreign.energy` (the `EnergyActions.read_model` dictionary) and `foreign.map.gas_supply` (`{region_id: float}`); desk nodes `EnergyHeading`, `EnergyContract`, `EnergySteps`, `EnergyRule`.

- [ ] **Step 1: Write the failing tests**

Create `godot/tests/native/test_energy_snapshot.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")


static func _state() -> GameState:
	var state: GameState = GameFactory.new_campaign(ContentRepository.load_all(), {
		"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal",
		"opening_role": "government", "seed": 424242})
	state.rng = SimRng.from_seed(424242)
	BudgetSim.ensure_budget_state(state)
	ForeignSim.ensure(state)
	return state


func _test_the_snapshot_carries_the_contract(t) -> void:
	var energy: Dictionary = NativeGameScript._build_snapshot(_state())["foreign"]["energy"]
	t.truth(energy.get("active", false), "the desk sees an active contract")
	t.equal(String(energy["supplier"]), "Krasova", "named by its supplier")
	t.equal((energy["steps"] as Array).size(), EnergyActions.VERBS.size(), "with every energy operation")
	t.equal(int(energy["months_to_renewal"]), 22, "and the months until renewal")


func _test_the_map_gets_the_gas_supply(t) -> void:
	var state := _state()
	state.foreign.gas.last_flow = {"shortfall": 0.4, "severity": 0.4}
	var supply: Dictionary = NativeGameScript._build_snapshot(state)["foreign"]["map"]["gas_supply"]
	t.equal(supply.size(), state.regions.size(), "every region has a supply ratio")
	t.near(float(supply["zavost"]), 0.4, 0.000001, "Zavost shows its deeper shortfall")
	t.near(float(supply["vashtera"]), 0.6, 0.000001, "the capital the national one")


func _initialize() -> void:
	var t = TestSupportScript.new()
	_test_the_snapshot_carries_the_contract(t)
	_test_the_map_gets_the_gas_supply(t)
	quit(t.finish())
```

Create `godot/tests/ui/test_energy_desk.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const TEST_SLOT := "test_energy_desk"

var t = TestSupportScript.new()
var app: Node = null
var game: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int = 2) -> void:
	for _i in range(count):
		await process_frame


func _fresh() -> void:
	if app != null:
		app.queue_free()
		await _frames()
	root.get_node("GameFlow").start_mode = "new"
	root.get_node("GameFlow").pending_seed = 424242
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	app.save_slot = TEST_SLOT
	root.add_child(app)
	game = root.get_node("NativeGame")
	await _frames(3)


func _wipe_slot() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := "user://saves/%s.json%s" % [TEST_SLOT, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _energy_button(prefix: String) -> Button:
	var steps: VBoxContainer = app.find_child("EnergySteps", true, false)
	for child in steps.get_children():
		if child is Button and (child as Button).text.begins_with(prefix):
			return child
	return null


func _run() -> void:
	_wipe_slot()
	await _test_the_desk_shows_the_contract(t)
	await _test_arrears_can_be_paid_from_the_desk(t)
	await _test_a_threat_and_a_cut_keep_the_desk_width(t)
	_wipe_slot()
	if app != null:
		app.queue_free()
	quit(t.finish())


func _test_the_desk_shows_the_contract(t) -> void:
	await _fresh()
	app._open_diplomacy()
	await _frames()
	var contract: Label = app.find_child("EnergyContract", true, false)
	t.truth(contract != null and contract.text.contains("KRASOVA") and contract.text.contains("Arrears"), "the desk shows the gas contract and its arrears")
	var spot := _energy_button("Emergency spot purchase")
	t.truth(spot != null, "and offers the energy operations")


func _test_arrears_can_be_paid_from_the_desk(t) -> void:
	await _fresh()
	app._open_diplomacy()
	await _frames()
	var button := _energy_button("Pay down the gas arrears")
	t.truth(button != null and not button.disabled, "the arrears can be paid from the desk")
	button.pressed.emit()
	await _frames(3)
	t.equal(game._state.foreign.gas.arrears, 0.0, "pressing it pays them")
	var status: Label = app.find_child("DiplomacyStatus", true, false)
	t.truth(status.text.contains("arrears"), "the desk reports it")
	var again := _energy_button("Pay down the gas arrears")
	t.truth(again != null and again.disabled and again.tooltip_text.contains("no gas arrears"), "and then says why it cannot be pressed again")


func _test_a_threat_and_a_cut_keep_the_desk_width(t) -> void:
	await _fresh()
	app._open_diplomacy()
	await _frames(3)
	var panel: Control = app.find_child("DiplomacyPanel", true, false)
	var width := panel.size.x
	var window_width := root.size.x
	var energy: Dictionary = app.snapshot["foreign"]["energy"]
	energy["threat"] = true
	energy["cut"] = 0.4
	energy["supplier"] = "Krasova " .repeat(60)
	for step in energy["steps"]:
		step["label"] = "Ardenia " .repeat(80)
		step["disabled_reason"] = "Because " .repeat(80)
	app._refresh_energy()
	await _frames(3)
	t.equal(panel.size.x, width, "a threatened, cut, wordy contract leaves the desk width unchanged")
	t.equal(root.size.x, window_width, "and the window width")
	var contract: Label = app.find_child("EnergyContract", true, false)
	t.truth(contract.text.contains("VALVE") and contract.text.contains("CUT"), "and still names the threat and the cut")
```

- [ ] **Step 2: Run tests to verify they fail**

Run both files. Expected: the snapshot test fails (`energy` missing → `SCRIPT ERROR` on the indexing), and the desk test fails on "the desk shows the gas contract" (node missing → `SCRIPT ERROR`).

- [ ] **Step 3: Implement**

In `godot/scripts/native/actions/orientation_actions.gd` `read_model`:
- In the early-return dictionary, change `"map": {"memberships": {}}` to `"map": {"memberships": {}, "gas_supply": {}}, "energy": {"active": false, "steps": []}`.
- In the final returned dictionary, change `"map": {"memberships": memberships(state)},` to:

```gdscript
		"map": {"memberships": memberships(state), "gas_supply": GasSim.supply_by_region(state)},
		"energy": EnergyActions.read_model(state),
```

In `godot/scenes/panels/diplomacy_panel.tscn`, insert after the `OrientationRule` node block (before `CountryStanding`):

```
[node name="EnergyHeading" type="Label" parent="Content/DiplomacyScroll/DiplomacyBody"]
layout_mode = 2
size_flags_horizontal = 3
theme_type_variation = &"Section"
text = "ENERGY"

[node name="EnergyContract" type="Label" parent="Content/DiplomacyScroll/DiplomacyBody"]
layout_mode = 2
size_flags_horizontal = 3
text = ""
autowrap_mode = 3

[node name="EnergySteps" type="VBoxContainer" parent="Content/DiplomacyScroll/DiplomacyBody"]
layout_mode = 2
size_flags_horizontal = 3
theme_override_constants/separation = 6

[node name="EnergyRule" type="HSeparator" parent="Content/DiplomacyScroll/DiplomacyBody"]
layout_mode = 2
```

In `godot/scripts/app.gd`:
- In `_refresh_diplomacy`, after `_refresh_orientation()`, add `_refresh_energy()`.
- In `_refresh_orientation`, replace the block from `var button := Button.new()` through `box.add_child(why)` (the non-held branch of the loop) with `_add_step_button(box, step, _take_orientation_step)`.
- Add:

```gdscript
func _add_step_button(box: VBoxContainer, step: Dictionary, on_press: Callable) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cost := float(step.get("cost", 0.0))
	button.text = str(step.get("label", "")) + ("   · %.0f PC" % cost if cost > 0.0 else "")
	button.clip_text = true
	button.disabled = not step.get("eligible", false)
	button.tooltip_text = str(step.get("disabled_reason", ""))
	button.pressed.connect(on_press.bind(str(step.get("verb", ""))))
	box.add_child(button)
	var reason := str(step.get("disabled_reason", ""))
	if reason != "":
		var why := Label.new()
		why.theme_type_variation = &"Muted"
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		why.text = reason
		box.add_child(why)


func _refresh_energy() -> void:
	var energy: Dictionary = snapshot.get("foreign", {}).get("energy", {})
	var panel = %DiplomacyPanel
	panel.find_child("EnergyContract").text = _energy_line(energy)
	var box: VBoxContainer = panel.find_child("EnergySteps")
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for step in energy.get("steps", []):
		_add_step_button(box, step, _take_energy_step)


static func _energy_line(energy: Dictionary) -> String:
	if not energy.get("active", false):
		return "Ardenia has no gas contract to manage."
	var lines: Array[String] = [
		"%s / price %.1f (reference %.1f)%s / renewal in %d months" % [
			str(energy.get("supplier", "")).to_upper(), float(energy.get("price", 0.0)),
			float(energy.get("reference_price", 0.0)), " / Union cap" if energy.get("union_capped", false) else "",
			int(energy.get("months_to_renewal", 0))],
		"Arrears %.0f / storage %.2f of %.2f / second line: %s" % [
			float(energy.get("arrears", 0.0)), float(energy.get("storage", 0.0)),
			float(energy.get("storage_capacity", 0.0)), str(energy.get("second_line", "none"))],
	]
	if energy.get("threat", false):
		lines.append("VALVE THREATENED / deliveries fall next month unless the arrears come down")
	if float(energy.get("cut", 0.0)) > 0.0:
		lines.append("CUT / deliveries down %d%%" % roundi(float(energy["cut"]) * 100.0))
	lines.append("Supply this month %d%% of demand" % roundi((1.0 - float(energy.get("shortfall", 0.0))) * 100.0))
	return "\n".join(lines)


func _take_energy_step(verb: String) -> void:
	if _game == null:
		return
	var result: Dictionary = _game.energy_act(verb)
	_flush_snapshot()
	_sfx_result(result)
	if not result.get("ok", false):
		_set_diplomacy_status("REFUSED / %s" % result.get("error", "Unknown error"))
		return
	_set_diplomacy_status(str(result.get("message", "")))
```

- [ ] **Step 4: Import, run the tests, run the battery**

Run `--import`, both new tests, then `godot/tests/ui/test_orientation_desk.gd` (the refactored orientation buttons must still pass), then the full battery.
Expected: all green. Open the desk once in the real GUI (`.venv`-free: `"$G" --path godot`) and check that the energy section sits under the orientation section in the pixel style, wraps inside the desk, and does not widen it.

- [ ] **Step 5: Mutation-check**
- Drop `"gas_supply"` from the map → "every region has a supply ratio".
- Use `region_severity` in `supply_by_region` with a severity of 0.2 set in the test → "Zavost shows its deeper shortfall" (change the test's severity to 0.2 temporarily to see it, then restore both).
- Remove `button.clip_text = true` from `_add_step_button` → "leaves the desk width unchanged".
- Remove the `VALVE` line → "and still names the threat and the cut".
- Remove `_refresh_energy()` from `_refresh_diplomacy` → "and then says why it cannot be pressed again".

- [ ] **Step 6: Commit**

```bash
git add godot/scripts/native/actions/orientation_actions.gd godot/scenes/panels/diplomacy_panel.tscn godot/scripts/app.gd \
  godot/tests/native/test_energy_snapshot.gd godot/tests/native/test_energy_snapshot.gd.uid \
  godot/tests/ui/test_energy_desk.gd godot/tests/ui/test_energy_desk.gd.uid
git commit -m "feat(godot): the energy desk and the map's gas supply hand-off

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Calendar-true energy journeys, determinism and the living-world record

**Files:**
- Modify: `godot/tests/native/test_orientation_journeys.gd`
- Modify: `docs/godot/LIVING_WORLD.md` (new `## Energy` section after `## Orientation`; Known gaps line)

**Interfaces:**
- Consumes: everything above.
- Produces: journey records `gas_cuts`, `gas_threats`, `gas_price`, `blocked_cuts`, `peak_arrears`; an extended `_signature`.

- [ ] **Step 1: Extend the journey test (failing first)**

In `godot/tests/native/test_orientation_journeys.gd`:
- Add the constant `const UNION_GAS_EDGE := 1.02`.
- In `_signature`, append `state.foreign.gas.cuts, state.foreign.gas.threats, snappedf(state.foreign.gas.arrears, 1.0)` to the array.
- In `_journey`, declare `var gas_price := 0.0`, `var blocked_cuts := 0` and `var peak_arrears := 0.0` with the other accumulators. Inside the loop, after `NativeGameScript.next_month(state)`, add:

```gdscript
		gas_price += state.foreign.gas.price / float(months)
		peak_arrears = maxf(peak_arrears, state.foreign.gas.arrears)
		if GasSim.cuts_blocked(state) and state.foreign.gas.cut > 0.0:
			blocked_cuts += 1
```

  and add `"gas_cuts": state.foreign.gas.cuts, "gas_threats": state.foreign.gas.threats, "gas_price": gas_price, "blocked_cuts": blocked_cuts, "peak_arrears": peak_arrears,` to the returned dictionary.
- Add:

```gdscript
func _test_gas_shapes_each_orientation(t, runs: Dictionary) -> void:
	var neutral_gdp := 0.0
	var union_gdp := 0.0
	var neutral_cuts := 0
	var union_cuts := 0
	for seed in SEEDS:
		var neutral: Dictionary = runs["neutral/%d" % seed]
		var union: Dictionary = runs["union/%d" % seed]
		t.equal(int(union["blocked_cuts"]), 0, "seed %d: the Union never leaves a member cut short of a crisis" % seed)
		if "union_member" in union["reached"]:
			t.truth(float(union["gas_price"]) < float(neutral["gas_price"]), "seed %d: Union membership buys cheaper gas (%.1f < %.1f)" % [seed, union["gas_price"], neutral["gas_price"]])
		neutral_gdp += float(neutral["gdp"])
		union_gdp += float(union["gdp"])
		neutral_cuts += int(neutral["gas_cuts"])
		union_cuts += int(union["gas_cuts"])
	t.truth(union_gdp >= neutral_gdp * UNION_GAS_EDGE, "the Union's cheap gas is a real growth edge (%.0f >= %.0f x 1.02)" % [union_gdp, neutral_gdp])
	t.truth(union_cuts < neutral_cuts, "the Union is cut less often than neutrality (%d < %d)" % [union_cuts, neutral_cuts])
	var threatened := 0
	for key in runs:
		if int(runs[key]["gas_threats"]) > 0:
			threatened += 1
		t.truth(float(runs[key]["peak_arrears"]) < 10000.0 and is_finite(float(runs[key]["peak_arrears"])), "%s: arrears stay finite and bounded" % key)
	t.truth(threatened >= 1, "Krasova mentions the valve in at least one of the twelve histories (%d)" % threatened)
	for seed in SEEDS:
		t.truth(float(runs["western/%d" % seed]["gas_price"]) >= float(runs["union/%d" % seed]["gas_price"]), "seed %d: leaning west pays more for gas than the Union does" % seed)
```

  Call `_test_gas_shapes_each_orientation(t, runs)` in `_initialize` after `_test_each_orientation_has_a_price(t, runs)`.

- [ ] **Step 2: Run the journeys**

Run: `timeout 180 "$G" --headless --path godot --script res://tests/native/test_orientation_journeys.gd`
If the 12 twenty-year runs exceed 180 s, measure the time without the new code. If it was already near the limit, report it rather than raising the timeout (the timeout is a global constraint). Expected: the new assertions pass. Pre-existing calibration assertions in this file belong to Task 8. If one of them fails, record its numbers and leave it untouched.

- [ ] **Step 3: Mutation-check**
- Set `UNION_PRICE_SHARE` to 1.0 → "Union membership buys cheaper gas" and "a real growth edge".
- Remove `or cuts_blocked(state)` in `_restore` and comment out the cut reset in `on_union_join` → "never leaves a member cut".
- Make `coerce` always return `""` → "mentions the valve in at least one".
- Determinism: `_test_the_same_seed_and_choices_repeat_exactly` must still pass with the extended signature. Mutate `coerce` to read `Time.get_ticks_msec() % 2` as a deciding term → it must fail; restore.

- [ ] **Step 4: Write the living-world record**

In `docs/godot/LIVING_WORLD.md`, add after the `## Orientation` section:

```markdown
## Energy

Ardenia's gas is one contract, `ForeignState.gas` (`GasContract`): Krasova
supplies 6 bcm a year through the Zovar line at 50 million kron a unit,
take-or-pay 80%, renewing every three years from January 1995. The treasury
settles 85% of each bill in hard currency; the rest is arrears (40 at the
start). The budget carries the rolling twelve months actually paid, so the
winter peak does not jolt the deficit the ISF reviews.

Demand weighs 1.5 from October to March and 0.5 otherwise. Delivered supply
is the contract less any cut and any sabotage, plus a second line and spot
cargoes; storage injects in summer and draws whenever there is a gap. The
share of demand met is the map's `foreign.map.gas_supply`; effects read
severity (shortfall scaled by the season), so a January cut costs three times
a July one. Severity raises household hardship by region exposure (Zavost
1.5, Darev 1.3), lays off workers in Zavost and Darev, shortens state reach,
drags growth and appears as the "Energy supply" stability component.
Separatist territory is off the network. Dear gas drags growth and cheap gas
lifts it.

Krasova uses its world-AI undermine plan for gas first: a demand for the
arrears (at 60 or more), two months later a threat naming next month (leverage
0.5 or more, in practice the heating season), and at the named month a two-month
cut unless the arrears were paid below 30. After a cut it waits two years
before threatening again. Renewal reprices by leverage. Union membership caps
the price at 70% of the reference, reschedules half the arrears and blocks
cuts unless relations fall below -0.5; leaving costs 20% over the reference.
The player can pay arrears, renegotiate (transit fees, a Union step, or
shelving the second line), buy a spot cargo, build storage over two years and
build a second line over four, which Krasova treats as hostile. Energy draws
no RNG.
```

Replace the Known gaps line about the Union's growth edge with:

```markdown
- Gas situations (the valve threat as a decision) and Zovar sabotage arrive with plans 3 and 4; the hooks are `GasSim.valve_threat` and `GasContract.sabotage`.
```

- [ ] **Step 5: Run the battery and commit**

Run the full battery. All non-calibration lines must be green, and calibration misses go to Task 8.

```bash
git add godot/tests/native/test_orientation_journeys.gd docs/godot/LIVING_WORLD.md
git commit -m "test(godot): twenty-year gas histories for every orientation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Re-run every calibration band under the new cost

**Files:**
- Create: `godot/tests/native/energy_probe.gd` (measurement tool; not in the battery because it is not `test_*`)
- Create: `godot/tests/native/trajectory_probe.gd` (measurement tool)
- Modify (only if the procedure below calls for it): `godot/scripts/native/sim/gas_sim.gd` constants, `godot/scripts/native/sim/polls_sim.gd` (`ORDINARY_TRAJECTORY`), `godot/tests/native/test_polls.gd` (pending reason strings only)
- Modify: `docs/godot/LIVING_WORLD.md` (calibration record), `.superpowers/sdd/2026-10-29-intl-2-energy/progress.md` (create if absent)

**Interfaces:**
- Consumes: `test_fiscal_journeys.gd`'s `steady_budget` and `_state`, `test_polls.gd`'s `CALIBRATION_SEEDS`, `_state`, `budget_policy`, `ordinary_programme`.
- Produces: a measured table, and either a green battery or a BLOCKED report.

**The bands (never widened):**

| Band | Where | Required |
|---|---|---|
| Steady player government returned | `test_polls.gd` `_test_steady_governments_are_judged_like_ordinary_ones` | 0.40–0.65 |
| Player from opposition returned | same | ≥ 0.25 |
| AI party that won power returned | same | 0.30–0.70 (**pending** at start: 1/27) |
| 1997 steady government | `_test_the_first_term_is_hard_but_winnable` | 0.35–0.50 (**pending** at start: 4/12) |
| Schemer-answered gain over steady | same | ≥ 0.15 |
| Opposition start's opening government | same | 0.30–0.70 |
| Election calibration | `test_election_calibration.gd` | all its assertions |
| ISF pass share | `test_orientation_journeys.gd` `_test_the_isf_is_demanding_but_passable` | 0.2–0.9 |
| Orientation journeys | `test_orientation_journeys.gd`, every assertion | as written |
| Fiscal regression | `test_fiscal_journeys.gd` `_test_steady_government_stays_fiscally_bounded` | deficit ≤ 0.08, inflation ≤ 0.12, 4 seeds × 240 months |

- [ ] **Step 1: Write the probes**

Create `godot/tests/native/energy_probe.gd`:

```gdscript
extends SceneTree

const FiscalJourneys = preload("res://tests/native/test_fiscal_journeys.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")


func _initialize() -> void:
	for seed in [919191, 31, 424242, 7]:
		var state := FiscalJourneys._state("government", seed)
		ForeignSim.ensure(state)
		var winter := 0.0
		var winters := 0
		var bill := 0.0
		for _m in range(240):
			FiscalJourneys.steady_budget(state)
			NativeGameScript.next_month(state)
			if GasSim.season_weight(state.month) > 1.0:
				winter += GasSim.national_shortfall(state)
				winters += 1
			bill += GasSim.budget_cost(state) / state.country.economy.gdp / 240.0
		var g := state.foreign.gas
		print("E seed=%d demands=%d threats=%d cuts=%d winter_short=%.4f bill_gdp=%.4f arrears=%.0f price=%.1f" % [
			seed, g.demands, g.threats, g.cuts, winter / maxf(1.0, winters), bill, g.arrears, g.price])
	quit()
```

Create `godot/tests/native/trajectory_probe.gd`. It is the recorded `ORDINARY_TRAJECTORY` procedure: 12 calibration seeds × 240 calendar-true months, the ordinary legislative programme, `budget_policy(-0.05)`, two-year periods, and both starts blended 0.9 government : 0.1 opposition:

```gdscript
extends SceneTree

const Polls = preload("res://tests/native/test_polls.gd")
const NativeGameScript = preload("res://scripts/native/native_game.gd")
const GOVERNMENT_WEIGHT := 0.9


static func _periods(role: String) -> Dictionary:
	var periods := {}
	for seed in Polls.CALIBRATION_SEEDS:
		var state := Polls._state(role, seed)
		for _m in range(240):
			Polls.budget_policy(state, -0.05)
			Polls.ordinary_programme(state)
			NativeGameScript.next_month(state)
			var k := state.turn / 24
			if not periods.has(k):
				periods[k] = [0.0, 0.0, 0.0, 0.0, 0]
			periods[k][0] += PollsSim.government_approval(state)
			periods[k][1] += HouseholdsSim.national_confidence(state)
			periods[k][2] += PollsSim.misery_gap(state)
			periods[k][3] += state.stability_value
			periods[k][4] += 1
	return periods


func _initialize() -> void:
	var government := _periods("government")
	var opposition := _periods("opposition")
	var keys: Array = government.keys()
	keys.sort()
	for k in keys:
		var g: Array = government[k]
		var o: Array = opposition.get(k, g)
		var row: Array[float] = []
		for i in range(4):
			row.append(GOVERNMENT_WEIGHT * g[i] / g[4] + (1.0 - GOVERNMENT_WEIGHT) * o[i] / o[4])
		print('\t{"approval": %.3f, "confidence": %.3f, "misery": %.4f, "stability": %.3f},' % row)
	quit()
```

Run `--import` and `git add` both files and their `.uid`s.

- [ ] **Step 2: Measure everything**

Run, each with `timeout 180` except the trajectory probe. The trajectory probe runs 24 twenty-year campaigns; run it with `timeout 600` and in the background if needed. It is a measurement tool, not a test:
- `res://tests/native/energy_probe.gd`
- `res://tests/native/test_polls.gd`, `res://tests/native/test_election_calibration.gd`, `res://tests/native/test_orientation_journeys.gd`, `res://tests/native/test_fiscal_journeys.gd`

Fill this table in the task report: band, value at plan start (from the ledger: steady 39/73, opposition 23/34, AI-won 1/27, 1997 4/12, opening AI 8/12, ISF 0.83, fiscal worst deficits 0.037/0.038/0.035/0.036 and inflation 0.086/0.077/0.087/0.082), value now, and pass/miss.

- [ ] **Step 3: The principled re-measure procedure (apply in order, stop at the first that makes everything pass)**

1. **Energy in its design range?** The probe's ordinary steady government must sit inside the design range this plan was written to:
   - gas bill 0.4–0.8% of GDP
   - mean heating-season shortfall under 0.05
   - at most 5 cuts in 20 years
   - arrears finite
   - the price within 0.7–1.4 × the reference

   If a probe figure is outside its range, the energy mechanics are wrong, not the band. Find which constant puts the figure out of range (for example, cuts too frequent: `CUT_COOLDOWN`, `THREAT_LEVERAGE`). Change only that constant, add a direct-mechanics test pinning the corrected behaviour, mutation-check it, and re-measure from Step 2.
2. **Re-measure the ordinary reference.** Gas is a real cost on every government, so the ordinary case has moved. Run `trajectory_probe.gd`, replace the rows of `ORDINARY_TRAJECTORY` in `polls_sim.gd` with its output (same count of rows, same keys), and re-measure from Step 2. This is the only change to the polling reference allowed here; `TRAJECTORY_PERIOD_MONTHS`, weights, fades and fatigue are not touched.
3. **Pending bands.** The two pending checks in `test_polls.gd` already pass themselves when back in range (their `if` branch). If they are in range now, nothing is edited. If they still miss, they stay pending. Update only their reason strings to the current counts, for example `"1997 steady: N/12 after energy; recalibrate with election follow-up"`. Their bands are not changed.
4. **Anything else still missing → BLOCKED.** Never widen a band, never weaken an assertion, and never change a test strategy or helper so that it dodges gas. Commit only the probes, and report BLOCKED with the table, the probe output and which band misses. A separate election recalibration follows this plan, and the controller rules on the rest.

- [ ] **Step 4: Record and commit**

Add a short "Energy calibration" paragraph to the `## Energy` section of `docs/godot/LIVING_WORLD.md`. It gives the probe figures per seed, any constant changed in step 1 with its reason, whether `ORDINARY_TRAJECTORY` was re-measured, and the final band table, including the state of the two pending bands. Write the same table to `.superpowers/sdd/2026-10-29-intl-2-energy/progress.md`.

Run the full battery: all lines must report 0 failed, and only the allowed `PENDING` lines may remain.

```bash
git add godot/tests/native/energy_probe.gd godot/tests/native/energy_probe.gd.uid \
  godot/tests/native/trajectory_probe.gd godot/tests/native/trajectory_probe.gd.uid docs/godot/LIVING_WORLD.md
git add godot/scripts/native/sim/polls_sim.gd godot/scripts/native/sim/gas_sim.gd godot/tests/native/test_polls.gd
git commit -m "test(godot): re-measure every calibration band under the gas bill

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(The second `git add` stages only files that this task actually changed; `git add` of an unchanged file stages nothing.)

---

## Self-review

**Spec coverage (section 3 and the deferred items):**
- `GasContract` with `supplier_id`, `price`, `contracted_volume`, `arrears`, `term_end`, `take_or_pay`: Task 1.
- Monthly flow, the October–March peak, cost into the budget, unpaid → arrears, delivered = contracted − cut − sabotage: Task 2.
- Shortfall effects on households, Zavost/Darev industry, state reach and stability, deterministic, season-weighted, buffered by storage: Task 3.
- Supplier behaviour through the world AI, gated by leverage: the renewal price rise, the arrears demand, the threat foreshadowed a month ahead, the real cut, Union price cap and cut block short of a crisis: Task 4.
- Player operations (pay arrears, renegotiate for three concessions, spot purchase, storage, second line as hostile): Task 5.
- Map hand-off (`foreign.map.gas_supply`): Task 6. Persistence and validation: Task 1. The Diplomacy desk energy section: Task 6.
- Union gas benefit deferred by plan 1: Task 4 (cap, rescheduling, no cuts) and Task 3 (price-driven growth), measured in Task 7.
- Dependence reading the real contract: Tasks 1 and 2.
- Hooks for plans 3 and 4 (`valve_threat`, `sabotage`, `crisis`): Tasks 2 and 4, and "Interfaces for later plans".
- Journeys, determinism and the LIVING_WORLD update: Task 7. Calibration re-run with the procedure and the never-widen rule: Task 8.

**Placeholder scan:** every code step carries complete code; no TBD/TODO; the Task 8 edits are conditional by stated rule, with the exact content source (probe output) given.

**Type consistency:**
- `GasSim.ensure` returns `bool`, and `ForeignSim.ensure` uses it.
- `last_flow` keys match `GasContract.FLOW_FIELDS`, including `severity`.
- `last_cut_turn` is in `INT_FIELDS`, the validator and `coerce`.
- `EnergyActions.VERBS`, `COSTS` and `LABELS` share one key set.
- `OrientationActions.read_model`'s `energy` and `map.gas_supply` match Task 6's tests.
- `GasSim.STORAGE_MONTHS` and `SECOND_LINE_MONTHS` are defined in Task 5 before `EnergyActions` uses them.
- `union_cap` takes a `GasContract` everywhere.
