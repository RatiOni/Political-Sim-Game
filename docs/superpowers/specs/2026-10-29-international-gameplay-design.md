# International gameplay — design

**Date:** 2026-10-29 · **Status:** approved by the owner in conversation
(approach A, sections 1–5).

## Goal

Ardenia's foreign affairs become a sandbox in which a weak post-Kolvenian state
chooses and lives with its orientation. The core is gas dependence, foreign
situations that demand decisions, proxy pressure on a bounded escalation
ladder, and real two-sided blocs. No orientation is the "correct" one.

Out of scope: the map, which another workstream owns. This design only
publishes data the map can draw. Also out of scope: full war and occupation.

## Decisions taken with the owner

| Question | Decision |
|---|---|
| Fantasy | Open-ended sandbox: pro-Krasova, pro-West and neutral orientations are all viable and all have costs |
| Energy | A contract with seasonal leverage (not a full energy economy) |
| Conflict | Incidents on an escalation ladder up to a limited armed clash, never full war or occupation |
| Blocs | Two-sided orientation: the Western track (ISF, Concert, Meridian) and a Krasovan Economic Union, with neutrality viable |
| Structure | Approach A: one design, four plans built in order (orientation → energy → situations → pressure) |

## Canon used

These live in `content/lore/economy.py`:

- `ENERGY` — gas comes from Krasova through the Zovar line, paid in hard currency, with an October–March heating season. Krasova "has mentioned the valve".
- `FOREIGN_OBLIGATIONS` — the ISF stabilisation agreement (quarterly reviews on the deficit and Bank independence), Concert association ("not admitted for a decade"), and the Meridian partnership. A Meridian security guarantee is barred while a territorial dispute is active.

Krasova is Vetrenka's backer and Ardenia's canon antagonist; see the world AI in
`docs/godot/LIVING_WORLD.md`. The Krasovan Economic Union is new content,
written in canon voice. Its ids, names and prose live in native content data.

## 1. The shared spine

- **Alignment is not one slider.** Each foreign power or institution carries three tracked numbers:
  - `dependence` (0..1): what it holds over Ardenia (gas share, debt and loans held, export share).
  - `commitment` (0..1): what Ardenia has signed with it (treaties, programmes, union steps).
  - The existing bilateral `relations`.

  Orientation is never a label. It is read off these numbers.
- **Leverage.** `leverage(power) = f(dependence, relations, season)`. It is deterministic and bounded. The world AI's existing plan loop reads leverage to decide which coercive moves are available and how strong they are.
- **Tension.** Each power hostile to Ardenia has a 0..1 gauge. Incidents and the responses to them raise it; quiet decays it. It is never rolled. Thresholds unlock ladder rungs.
- **One pipeline.** Every consequence runs through the existing `EffectBundle`, the modifier system and the situations engine. Every decision arrives as a situation under the existing pacing, follow-up and default-lapse rules, and every default option is ungated.
- **Determinism.** The rules match the rest of the simulation. Outcomes are functions of tracked state. RNG only triggers events and picks world-AI plans, and it always comes from the saved campaign stream.
- **Map hand-off.** The game snapshot gains read-only fields for the map workstream:
  - per-region gas supply ratio
  - active incident locations, by region id
  - per-power tension

  Nothing in this design depends on how they are drawn.

## 2. Orientation tracks

Each track is a persisted state machine of milestones. Each milestone has
conditions, a political-capital and treasury cost, effects, and the reactions
of other powers.

- **ISF stabilisation.**
  - Quarterly reviews check deficit, inflation and Bank-independence targets.
  - A pass releases the next disbursement (a cash inflow) and lifts investor confidence.
  - A fail suspends disbursement, applies a confidence penalty, and opens a renegotiation situation.
  - Conditions can be renegotiated for political capital, at the price of tighter targets later.
- **Western integration.** A ladder: Concert association application → association agreement (reform and budget-discipline conditions over years) → Meridian partnership → Meridian security guarantee. The guarantee is locked while Vetrenka is unresolved.
- **Krasovan Economic Union.**
  - Steps: observer → member.
  - Benefits: discounted gas, rescheduled gas arrears and debt, open markets (growth).
  - Costs: tariff alignment (Western trade drops), no Meridian or Concert steps beyond partnership, and Krasovan influence on Ardenian policy (some player operations need Union consent).
  - Leaving is possible, but it is a costly crisis.
- **Hard locks are few and explicit.** Union membership and a Meridian guarantee are mutually exclusive, as are Union membership and the Concert association agreement. Everything else is a soft trade-off expressed through dependence, commitment and leverage.
- **AI countries hold memberships too.** World countries join tracks by agenda, so the player sees blocs form. Existing agenda logic is extended: traders lean toward the Concert, and revanchists and Krasovan clients lean toward the Union.

## 3. Energy

A `GasContract` is persisted. Its fields: `supplier_id`, `price`, `contracted_volume`, `arrears` (hard currency), `term_end`, `take_or_pay`.

- **Monthly flow.**
  - Demand follows the season and peaks October–March.
  - Cost goes into the budget.
  - Whatever is unpaid accrues as arrears.
  - Delivered supply = contracted volume − supplier cut − sabotage.
- **Shortfall effects** are deterministic and weighted by season:
  - household confidence and hardship
  - industrial growth, mainly in Zavost and Darev
  - state reach in the affected regions
  - stability

  Storage buffers the effects.
- **Supplier behaviour** runs through the world AI. The supplier can do any of the following, with the threats and the cut foreshadowed a month ahead:
  - raise the price at renewal
  - demand payment of arrears
  - threaten a cut
  - cut volume

  These moves are gated by leverage. Union membership caps price and blocks cuts short of a crisis.
- **Player actions** are input-free operations in the native action layer:
  - pay down arrears
  - renegotiate (trade price for a concession: transit fees, a Union step, or a policy)
  - emergency spot purchase at a premium
  - gas storage, a multi-year programme that buffers winter shortfall
  - a second supply line, a multi-year project that lowers Krasovan dependence, and which Krasova reacts to as hostile

## 4. Foreign situations

There are 12–15 new situations in the existing events catalogue, plus 2–3 short chains. Each one targets concrete countries through the existing relation-target resolution. The set:

- valve threat
- ISF review crisis
- transit dispute
- refugee flow from a neighbour's civil war
- a neighbour's coup
- a sanctions coalition asks Ardenia to join
- arms offer
- Krasova demands recognition of its "interests"
- Concert delegation and reform conditions
- Union invitation
- Union pressure on a member
- Western aid with strings
- a transit-fee windfall

The existing rules apply: once/cooldown gating, follow-ups, a two-month default lapse, and identity-gated options where they fit. No literal country ids appear except in documented bespoke Ardenian content, which follows the `ARDENIA_ONLY` convention.

## 5. Pressure and the escalation ladder

- **Proxy moves.** These join the world-AI hostile repertoire, each with a foreshadowing dispatch:
  - fund Vetrenka (feeds insurgency pressure)
  - sponsor unrest in a region (feeds regional pressure)
  - sabotage the Zovar line (cuts supply)
  - border incident
  - information campaign (feeds approval and polls)
- **Incidents are situations.**
  - Responses: de-escalate, respond in kind, internationalise (calls on the Western track or the Union), or ignore (the default).
  - Each response moves tension with a named weight.
- **Rungs.**
  - At 0.3: routine incidents.
  - At 0.5: crisis. Mobilisation costs a monthly treasury and stability charge, and the press switches to crisis mode.
  - At 0.75: a limited armed clash. This is a set-piece chain whose costs land on stability, approval, growth and regional reach. It resolves through talks, mediation by a third power or institution, or a ceasefire.
  - The ladder ends there: no occupation, no full war.
- **Deterrence and decay.**
  - Defence pacts and a Meridian guarantee reduce the frequency and strength of hostile plans.
  - Union membership reduces Krasovan pressure but grants it influence.
  - Tension decays when nothing feeds it.

## Persistence and validation

Every new state round-trips through binary saves, and old saves load with defaults. `StateValidator` rejects impossible values: gauges outside 0..1, negative arrears, invalid lock combinations, and unknown power or track ids.

## Testing

- Unit tests for each system, mutation-checked. Each test must fail when the behaviour it guards is broken.
- Persistence and validator coverage for all new state.
- Calendar-true 20-year journeys on at least 12 seeds, one each for the neutral, Western-leaning and Krasova-leaning strategies. They assert:
  - every strategy is viable (approval and stability stay inside sane ranges)
  - every strategy has measurable costs
  - no runaway, no NaN, everything bounded
  - different seeds produce different foreign histories (incidents, gas cuts, memberships)
- Determinism: the same seed and the same choices give the same history.

## Delivery

There are four plans, built in order. Each plan ships a playable, tested slice and
updates `docs/godot/LIVING_WORLD.md`. UI follows the existing desk and dashboard
conventions (the pixel UI system memory); the Diplomacy desk gains
orientation, energy and tension sections.

1. Orientation tracks and the shared spine: dependence, commitment, leverage, plus ISF, Western and Union tracks.
2. Energy.
3. Foreign situations.
4. Pressure and the escalation ladder.
