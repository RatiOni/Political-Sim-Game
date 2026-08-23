# Ardenia — Economy Review

Read-only design review of the economic simulation. All figures below come from
runs of the real engine (`TurnEngine.advance`, seeded, 240–480 months from
`build_state_for("ardenia")`), not from reading source alone. No game code was
changed to produce it.

## Baseline evidence: four 20-year policies (1993 → 2013)

| policy | infl | unemp | debt/GDP | expenditure | approval | stab | hh confidence | PC |
|---|---|---|---|---|---|---|---|---|
| start | .038 | .112 | .64 | 13,400 | .48 | .55 | .52 | 45 |
| do-nothing | **.005** | **.063** | **.57** | 10,959 | .48 | .53 | .45 | **100** |
| max welfare (+15%/yr) | .433 | .190 | **.61** | 181,315 | .38 | .47 | .31 | 100 |
| max austerity (−15%/yr) | .005 | **.058** | .59 | **466** | **.54** | **.56** | .49 | 100 |
| max investment | .393 | .200 | .62 | 125,576 | .37 | .44 | .28 | 100 |

40-year do-nothing: unemployment hits the 1.0% floor by 2023, inflation 0.5%,
debt 0.64 → 0.42, stability .44 → .57, PC 100 every month.

## Findings, severity-ranked

### S1 — Deficits never become debt. The fiscal loop is open.

`models/economy.py:60` / `engine/turn.py:_update_structural_fiscal_baseline`
(l.300–318). `public_debt_pct` is written in exactly four places — campaign
setup, a foreign loan (`engine/diplomacy.py:113`), a law's
`one_time_debt_pct_delta` (`engine/legislative.py:323`), and loan repayment
(`turn.py:409`). **Nothing accumulates the annual balance into it.**

Evidence: the max-spend run reaches expenditure 237,146 M against revenue
18,168 M — a deficit **12× annual revenue, ~5× GDP per year, sustained for 18
years** — and debt/GDP ends at **0.62, below its 0.64 start**. Conversely the
passive run runs surpluses for 20 years and debt still only moves because of
event deltas.

Why it matters: appropriations are the game's biggest lever and they have no
balance-sheet consequence. There is no borrowing constraint, no interest, no
bond-market feedback, and `debt_pressure` in `engine/reforms.py:95` is
diagnosing a number that never moves. Every subsystem that reads debt
(`content/events.py:57`, `:834`, the UI gauges) is reading a decoration.

Fix: at the end of the monthly pulse,
`public_debt_pct += (expenditure − revenue)/12 / gdp`, and attach an interest
cost as a `budget_expenditure` modifier scaled to debt (or fold it into
`structural_expenditure`). A rising debt path is what closes the loop from
spending → inflation → approval. Add a debt-ceiling event chain rather than a
hard fail.

### S2 — Austerity is strictly dominant, and doing nothing is a strategy.

`engine/budget.py:15` `CONTINUING_CUT = 0.03` and `engine/budget.py:283`
(impasse branch).

Cutting every envelope 15%/yr for 20 years takes expenditure from 13,400 M to
**466 M — 3.5% of the original state** — and produces the *best* outcome in the
game: highest approval (.54), highest stability (.56), lowest unemployment
(5.8%), lowest hardship (.27), inflation floored. Ministry delivery at 6% of
baseline funding is still **1.00** for Defense, Economy, Justice and Interior.

Worse, failing to pass any budget applies a compounding 3% cut *every year* for
a one-off −0.015 approval / −0.02 stability. Passive play is therefore a
self-executing consolidation programme: revenue grows 2%/yr with GDP while
expenditure falls ~1%/yr net, inflation collapses to the floor, and the economic
signal improves. **The intended failure state is the optimal strategy.**

Fix: make the state's absence hurt. Ministry capacity must fall meaningfully
below ~0.8× funding (see S4); household `service_access` and `welfare_delivery`
must bite harder (`_envelope_ratio` currently clamps to 0.50, so under-funding
by 94% reads the same as by 50%); and the impasse penalty should scale with how
long it persists, not be a flat annual tap.

### S3 — Inflation is nearly costless; the economic signal is badly weighted.

`engine/stability.py:20-23`:

```
(growth − 0.02)*4.0 − unemployment*0.5 − inflation*0.3
```

Measured: 40% inflation costs −0.114 of signal; 1pp of growth is worth +0.04;
3pp of unemployment −0.015. **43% annual inflation costs the government less
approval than a 3-point growth swing.** In the max-welfare run, hyperinflation
of 43% plus 19% unemployment leaves approval at .38 and stability at .47, with
no civil war (risk peaked at .26) and no game-over path.

Fix: inflation should enter non-linearly (e.g. `−max(0, infl−0.03)*3.0` or a
squared term above 10%), and its main channel to the player should be household
real income (which does work — real income 1.00 → 0.62 by 2005) with a heavier
weight than the current `household_mood * 0.12` in `turn.py:_update_approval`.

### S4 — Ministry funding is decision-free above and below a narrow band.

`engine/ministries.py:134` `funding_factor = 0.65 + 0.35 * clamp(ratio, 0.50, 1.50)`,
`:138` `capacity = 1.45 * …`.

Measured sensitivity: funding at 0.40× and 0.50× of baseline give **identical**
capacity; 1.50× and 2.00× give identical capacity. Across the entire live range
capacity moves only 0.90 → 1.28 for Finance. Baseline workload is 0.65 for five
of six portfolios, so **only Finance is ever constrained** (workload 1.03,
carrying both Education and Health & Welfare) and it is stuck at delivery
0.87–1.00 regardless of policy. Backlog never accumulates outside Finance.

Compounding this: `baseline_funding` is captured once at campaign start
(`ministries.py:43`) and never re-based. With ~2%/yr nominal expenditure drift,
every ministry drifts past the 1.50 clamp within a decade and gets max capacity
for free, permanently.

Fix: widen the clamp (0.25–1.75), make `funding_factor` roughly linear in ratio,
re-base `baseline_funding` each January to the voted plan (making it a
*year-on-year* comparison, which is what the funding-ratio UI implies), and
raise baseline workload so more than one portfolio sits near its capacity.

### S5 — Unemployment is a one-way ratchet; the country repairs itself.

`engine/turn.py:346`: `structural_unemployment -= growth_gap * 0.3`, monthly,
with no mean-reversion. `TREND_GROWTH = 0.02`, but Ardenia's sector-weighted
structural growth is **0.0209 and rising** (Services at 3.1% growth gains GDP
share every month in `_update_sectors`, taking weighted growth to 0.0227 by
2033). The gap is therefore permanently positive.

Result: with **zero player input**, unemployment falls 11.2% → 6.3% (20 yrs) →
1.0% floor (30 yrs), stability rises .44 → .57, approval drifts to .52. The
single most visible problem in the opening scenario solves itself on a timer.

Fix: give unemployment a NAIRU it reverts toward
(`structural_unemployment += (nairu − u)*k − growth_gap*0.3`), where the NAIRU
itself is what education and workforce reforms move. Also either set
`TREND_GROWTH` from the country's own sector mix at load, or drift it, so "above
trend" is not a permanent state.

### S6 — Political capital is not a currency.

`engine/turn.py:225-245`. Regen at the opening position: 10 base +
(approval−.5)*10 + loyalty*5 + (stab−.5)*4 − 0.8 upkeep ≈ **+12/month**,
hard-capped at 100. PC reads 100.0 in every one of the 240-month runs, from year
2 onward, under every policy. Costs are 7–18 (a regional programme is 12, a bill
~10). Governing overhead maxes at ~0.8/law and never approached the
`PC_REGEN_FLOOR`.

The real constraint is `MONTHLY_ATTENTION = 3` (`player_ops.py:59`), which is
well-designed — but it means PC is a second currency that never says no. Every
"not enough political capital" branch in `player_ops.py` is dead code in
practice.

Fix: either lower the cap to ~40 and the base regen to ~4–5, so three
initiatives a month genuinely draws down a balance, or delete PC as a gate and
let attention be the sole scarcity. Half a currency is worse than either.

### S7 — Regional programmes are effectively free.

`content/regions.py` costs 9–14 PC (regenerates in one month) and 55–140 M/month.
That monthly cost is added to `budget.expenditure` (`regions.py:312`) but never
to `structural_expenditure` and never to debt — its only consequence is the
deficit → inflation channel at `DEFICIT_INFLATION_FACTOR = 0.003`, i.e. a
110 M/month programme moves equilibrium inflation by ~+0.3pp. Six regions × one
programme each is a ~72 PC one-off with no fiscal opportunity cost. Attention is
the only brake.

Fix: once S1 lands, programme cost becomes real automatically. Additionally
consider charging programmes against the sponsoring portfolio's appropriation,
so the map competes with the budget rather than running beside it.

### S8 — The appropriations system has no revenue side.

`structural_revenue` is only ever scaled by GDP growth (`turn.py:302`). The only
revenue levers in the whole game are two bills (`telecom_privatization_act`
+600 M, `progressive_tax_reform_act` +500 M) and customs at
`TRADE_CUSTOMS_RATE = 0.05`. A budget system where the player chooses spending
but never taxation removes the central trade-off of fiscal politics — and it is
why max-spend has no counterweight.

Fix: add a taxation dimension to the annual settlement (a rate multiplier on
`structural_revenue`, with ideology weights like the envelopes have, feeding the
same vote pipeline). It is the missing sink for the spending faucet.

### S9 — Nominal modifiers against a real-growing base.

Every fiscal `LawEffect` is a fixed nominal figure (`budget_revenue_delta=600.0`,
`budget_expenditure_delta=500.0`) with `hold_duration=None`, layered on a base
that compounds with GDP and inflation. The Tax Reform Act is worth 5.0% of
revenue in 1993 and 2.6% by 2013 — and under the max-spend run's 43% inflation,
3% of nothing. Policy silently evaporates.

Fix: express fiscal magnitudes as a fraction of `structural_revenue` /
`structural_expenditure` at application time, or index the modifier value to GDP.

### S10 — Household real income decays even in the good case.

`engine/households.py:139-149`. `nominal_rate = infl*indexation + growth*exposure`
versus `cost_rate = infl*price_sensitivity`. For every group,
`income_indexation` (0.20–0.65) is below `price_sensitivity` (0.90–1.15). At any
positive inflation, real income falls indefinitely until the 0.35 clamp; the only
equilibrium is zero inflation. Do-nothing: 1.00 → 0.89. Max-welfare: → 0.62 and
heading for the floor.

This is defensible as a deliberate model of a 1990s transition economy, but there
is currently **no policy that raises indexation** — the only cure is deflation,
which reinforces S2. Give the player an indexation instrument (wage law, pension
uprating) or the group definitions a slow catch-up term.

## What is well-designed — do not "fix" these

- **The Modifier lifecycle** (`models/modifiers.py`). Recomputed fresh each turn,
  never accumulated, `_upsert_modifier` refreshing by id rather than stacking.
  This is the single reason nothing in the game inflates without bound, and it
  holds under 480-month runs. The three showcase bills' pacing (infrastructure:
  cost immediately, growth at month 24 ramping to 48; education: workforce at
  month 36 ramping to 60) is genuinely good economy pacing — long enough to be a
  legacy decision, short enough to land inside two terms.
- **`MONTHLY_ATTENTION = 3`** and the reasoning in its comment. This is the
  game's real economy and it works. The exemption list (situations,
  follow-through, opposition play) is correctly drawn.
- **Trade volume saturating toward a relationship-set ceiling**
  (`turn.py:_update_relations`) rather than compounding, with the same code path
  handling decay. Textbook closed loop.
- **Determinism of elections / stability / civil-war risk** with RNG confined to
  triggers. It makes the economy legible to the player, which is the
  precondition for any of the above fixes being felt.
- **`ministries.preview` / `budget.forecast` sharing one code path** so the
  projection can't drift from the simulation, and `portfolio_appropriation`
  deliberately excluding won supplements so they can't ratchet the cap. Both are
  the right instincts — the problem is the magnitudes, not the plumbing.
- **`budget.py` supplementary design**: real mid-year money, 15% cap, 4-month
  cooldown, cost booked as a modifier that dies with the year. Correct sink
  discipline.

## Pacing summary

A player's decision lands on this schedule today: flat `LawEffect` deltas — same
month (`ramp_duration=1`); authored modifiers — 2 to 48 months; regional
programme — spread across 8–18 months at ~1/duration per month, then decaying
back toward the national target at 0.14/month once it ends; budget — January
only, then delivery changes the same month (too fast, because backlog barely
exists outside Finance); reform objective — never, it has no mechanical effect
yet.

The long fuses are good. The gap is the **short** end: there is currently no
lever whose effect the player feels within one to three months except an
executive order, which makes month-to-month play feel inert.

## Suggested order of work

1. **S1** (debt accumulation + interest) — closes the biggest open loop and makes
   S2 and S7 self-correcting.
2. **S5** (NAIRU) — removes the auto-win drift.
3. **S2 / S4** (make under-funding hurt; re-base `baseline_funding`) — restores
   budget opportunity cost.
4. **S3** (inflation weight) — gives the deficit path teeth.
5. **S6** (PC cap and regen) and **S8** (revenue side).
