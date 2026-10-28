# Ardenia Godot simulation redesign

**Status:** Design authority before any simulation rewrite.

## Non-negotiable native-design rules

Godot is not a numerical replica of another runtime. A simulation file exists
to create a player-facing experience, not to preserve an inherited equation.
No comment, test, task brief, or implementation note may describe a mechanic as
a port, mirror, or numerical equivalent, or cite a source file as justification.
Every formula and constant must have a stated Godot-side reason: player choice,
readability, pacing, bounded behaviour, or a desired long-term trade-off.

Tests protect intended behaviour. If a test asserts an inherited number, replace
it with a stronger test of direction, threshold, boundedness, persistence,
causality, or player-visible consequence. Never delete or weaken a test to
obtain green output. Each redesign task must list every test changed and why.

The prior implementation and its passing tests remain in the repository as an
auditable baseline. They are not a tuning target.

## Redesign sequence

1. Economy and debt: `economy_sim.gd`, then `budget_sim.gd`.
2. Ministry capacity: `ministries_sim.gd`, using the new fiscal signals.
3. Political capital: `political_capital.gd`, using the redesigned commitment
   costs and clear caps.
4. Regional and household feedback: `regions_sim.gd`, then the household layer
   when its specification is written.
5. Calendar orchestration: `calendar.gd` only after the monthly systems have
   a deliberate cadence.

The current review identifiers S7–S10 are referenced by the user but the named
`docs/economy-review.md` is absent from both available checkouts. Their exact
findings must be recovered before their respective implementation begins; this
document does not invent them.

---

## `economy_sim.gd` — economy, prices, jobs, debt service

### Player-facing job

Make the economy a constrained medium-term problem. Growth can help employment
and incomes, but fast demand, imported cost pressure, and deficits can make
life worse before the headline figure improves. A player should be able to see
why a budget, law, or external shock moved prices, jobs, debt, and household
confidence.

### What is wrong with the copied version

- **S1:** A yearly deficit does not accumulate into `public_debt_pct`; debt
  moves only through exceptional direct effects. Spending therefore lacks a
  balance-sheet consequence.
- **S3:** Inflation is too cheap: policies can buy output or relief without a
  sufficiently legible price and household-cost response.
- **S5:** A fixed growth trend makes unemployment drift toward its floor even
  when the player does nothing. That removes the strategic labour-market
  problem.
- The current formula chain makes implementation structure and constants feel
  inherited rather than chosen for Ardenia's pacing.

### New design

- Each monthly fiscal result contributes to a rolling annualised primary
  balance. A deficit increases debt relative to GDP; a surplus stabilises or
  reduces it. This is gradual, visible, and never an instant punishment.
- Debt service is an explicit recurring pressure on the next fiscal plan. High
  debt narrows discretionary spending and raises vulnerability to inflation or
  confidence shocks; it does not simply impose a hidden stat penalty.
- Inflation has separate demand, import-cost, and expectations pressures. It
  is expensive because it raises household living costs, erodes real incomes,
  and makes future fiscal choices harder. Temporary relief may be worth that
  cost, but the forecast must disclose it.
- Unemployment moves toward a dynamic labour-market floor (a NAIRU-like
  baseline) determined by workforce quality, sector health, regional access,
  and sustained demand. Growth below that floor is not a free permanent cure;
  overheating can raise inflation before employment improves further.
- Tune to stories, not fixed legacy outputs: austerity should protect debt at a
  real social and electoral cost; a stimulus should buy near-term activity at
  fiscal and price risk; competent delivery should improve the conversion from
  spending to jobs rather than make jobs automatic.

### Tests to change and why

- Replace exact monthly headline-number assertions with scenario tests:
  sustained deficits raise debt/GDP; sustained primary surpluses lower it;
  higher debt service reduces next-year fiscal room; equal nominal spending has
  worse real household results under higher inflation; unemployment converges
  toward the dynamic floor instead of an arbitrary hard minimum.
- Add a save/reload continuation test for rolling balances, debt, and debt
  service so a reload cannot reset fiscal memory.
- Retain bounds and non-finite-value rejection tests; expand them to long,
  multi-year simulations.

---

## `budget_sim.gd` — annual settlement and failure to govern

### Player-facing job

Turn the annual budget into a visible political settlement: protect priorities,
meet obligations, accept cuts or raise revenue, and show what administration,
households, regions, and parliament will feel next.

### What is wrong with the copied version

- **S2:** The small continuing-budget cut makes non-decision an optimal or
  nearly optimal strategy. A player can avoid political conflict while paying
  too little cost.
- The current settlement does not fully communicate the connection between a
  deficit, debt service, ministry delivery, and the next year's room to act.

### New design

- A passed budget selects priorities and has an explicit fiscal balance.
- A failed budget creates an emergency continuing resolution: protected wages,
  debt service, and legally committed programmes continue; discretionary
  activity is frozen, ministries accumulate backlog, and political credibility
  falls. It is survivable, never optimal.
- Emergency operation is evaluated monthly, so the player sees the costs mount
  and can choose whether to compromise, cut, or seek revenue.
- The pre-vote view forecasts debt direction, interest burden, overload risk,
  affected households/regions, and parliamentary fault lines.

### Tests to change and why

- Replace exact continuing-cut assertions with a comparison scenario proving
  that repeated budget failure creates worse delivery, credibility, and fiscal
  flexibility than a realistic passed settlement.
- Add tests that protected obligations survive a continuing resolution while
  discretionary commitments freeze.
- Add debt-service and save/reload continuation tests at a January boundary.

---

## `ministries_sim.gd` — conversion of authority into delivery

### Player-facing job

Make state capacity Ardenia's signature constraint. The player should feel the
difference between approving money, appointing a minister, and a service
actually reaching people.

### What is wrong with the copied version

- **S4:** The present funding response is compressed enough that materially
  different allocations barely change capacity. Funding choices therefore read
  as cosmetic.
- Workload and backlog are technically present but insufficiently connected to
  a forecast the player can act on before committing policy.
- Any remaining S7–S10 finding that concerns capacity must be recovered before
  this system is tuned.

### New design

- Use a visibly responsive, bounded funding curve with three readable zones:
  below operating minimum, credible operation, and diminishing returns.
- Leadership, bureaucratic quality, stability, and workload each matter in a
  distinct way. Good ministers improve conversion; they do not erase a starved
  or overloaded state.
- Backlog is accumulated unfinished work with consequences that become clear in
  the forecast: delayed programmes, weaker reach, higher pressure, or worse
  service access.
- Every action shows the responsible ministry, current load, expected added
  load, and the likely delivery band before commitment.

### Tests to change and why

- Replace exact capacity-factor assertions with comparative tests proving that
  a low-funded ministry delivers materially less than a credibly funded one,
  and that extra funding has diminishing returns.
- Add scenario tests that a capable minister cannot completely offset severe
  underfunding or overload, and that spare capacity reduces backlog over time.
- Keep bounds, missing-minister, persistence, and no-crash coverage.

---

## `political_capital.gd` — political attention and governing bandwidth

### Player-facing job

Represent the limited attention a government can spend on conflict, bargaining,
and implementation without making the campaign stall behind an arbitrary meter.

### What is wrong with the copied version

- **S6:** Political capital becomes pinned at 100, flattening both gains and
  meaningful choices.
- Commitment upkeep risks becoming hidden friction rather than a legible
  decision about governing bandwidth.
- Any S7–S10 finding assigned to political capital must be recovered before
  detailed tuning.

### New design

- Political capital has a soft accumulation limit, not a permanent hard pin.
  Excess political momentum decays or converts into a different benefit rather
  than silently disappearing at a cap.
- Regeneration reflects public mandate, coalition confidence, and uncommitted
  governing capacity. It should keep a recovering government playable while
  preventing unlimited action spam.
- Commitments create visible recurring attention costs. The player can inspect
  what is consuming capacity and can retire, complete, or renegotiate it.

### Tests to change and why

- Replace cap-equality tests with tests for a soft-limit response, readable
  upkeep breakdown, recovery from low capital, and no unbounded accumulation.
- Add comparison tests that an overcommitted government has less room for new
  action but is never soft-locked solely by the meter.

---

## `regions_sim.gd` — geography of state presence

### Player-facing job

Show that the same national government is experienced differently across
Ardenia. Regions translate national conditions and local capacity into pressure,
state reach, employment, and political control.

### What is wrong with the copied version

- Existing response curves inherit their shape rather than expressing a chosen
  political geography.
- Regional programmes risk functioning as fixed effect bundles rather than
  contested delivery commitments.
- S8–S10 may include regional or cross-system defects; their named findings
  must be recovered before this redesign is implemented.

### New design

- Each region has a limited set of structural sensitivities: employment base,
  distance from administrative reach, conflict exposure, and defining issue.
- National policy filters through those sensitivities and ministry delivery;
  regional programmes target one bottleneck but consume real administrative and
  fiscal capacity.
- Pressure rises from observable, accumulated grievance and weak reach rather
  than arbitrary monthly jumps. Recovery takes sustained competent delivery.

### Tests to change and why

- Replace exact regional delta tests with relative scenarios: a low-reach,
  high-unemployment region deteriorates faster under neglect; successful,
  supported delivery improves reach or pressure gradually; frozen territory
  cannot receive fictional delivery.
- Preserve deterministic, bounded, save/reload, and no-cross-region-leak tests.

---

## `calendar.gd` — political pacing and simulation cadence

### Player-facing job

Give the player a living political calendar without forcing them to watch daily
stat churn. Days create room for deadlines and future political events; months
resolve the economic and administrative consequences that need time.

### What is wrong with the copied version

- The calendar itself is sound infrastructure, but its monthly orchestration
  currently serves inherited system order rather than a deliberately explained
  player rhythm.
- Calendar tests risk treating exact update order as sacred even when a
  redesigned causal order would create clearer consequences.

### New design

- Keep deterministic days, pause, speed controls, month and year rollover, and
  save continuity.
- Define the monthly close as a clear sequence for the player: fiscal position
  closes, ministries attempt delivery, economy and prices respond, regions and
  households experience outcomes, then the political report explains them.
- Introduce scheduled decision dates only when a player-facing system needs
  them; do not add daily micro-management for atmosphere alone.

### Tests to change and why

- Retain calendar correctness, leap-year, rollover, and persistence tests.
- Replace inherited subsystem-order assertions with an integration test that
  checks causality: the budget is visible to delivery, delivery is visible to
  regional/household results, and the monthly report explains the resulting
  changes.
- Add long-run cadence tests that quiet time can advance safely and no month
  closes twice after save/load.