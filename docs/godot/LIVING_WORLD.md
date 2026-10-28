# Ardenia Godot — the living world (Phase 4)

**Status:** situations engine, the schemer arc, the party leadership
challenge, the Vasca question, Vetrenka and the civil-war gauge are
playable — 44 of 46 events (2026-10-28). Arcs, the civil-war gauge, diplomacy verbs, the AI countries,
opposition play and the press remain. Same native-design rules as
`SIM_REDESIGN.md`: Python is a reference for what Ardenia contains, never a
formula to match.

## Phase 4 slices, in order

1. **Situations engine** — done. Arrival, pacing, decisions, default lapse,
   follow-up chains, the shared effect pipeline, role resolution, persistence,
   the "needs you" queue and the situation panel.
2. **The arcs** — done: the schemer, the leadership challenge, Vasca and
   Vetrenka (`sim/arcs.gd`, `sim/cabinet_sim.gd`). The two opposition events
   (`government_policy_retreat`, `opposition_by_election`) wait for slice 6,
   because their consequences act on the opposition layer. Each needs its bespoke
   consequence handlers (`on_apply` ids) written into
   `Arcs.HANDLERS`; until a handler exists, its events cannot
   fire (`EventsSim.unplayable_events()` lists them). Their trigger
   conditions (`schemer_plotting`, `vasca_stirring`, `vetrenka_friction_due`,
   `vetrenka_crossroads_ready`) join `Arcs.CONDITIONS` with them.
3. **Civil-war gauge** — done (`sim/crisis_sim.gd`).
4. **Diplomacy verbs** — pacts, sanctions, summits, treaty exit, loans.
5. **The world acts** — the eight AI countries deliberate and act, including
   on the player.
6. **Opposition play** — the domestic-AI government, pledges, shadow cabinet.
7. **The press** — dispatch voice and the monthly front page.

## How situations work (and why)

**Player-facing job:** a government is defined by what arrives on its desk
that it did not choose. Situations must feel like news, carry real
consequences, and never punish the player for missing a pop-up.

- **Pacing over volume.** A new government's first two months are quiet.
  After that at most one unprompted situation arrives a month, and none
  while three are already waiting. Five years produce about twenty.
- **Consequences arrive on schedule.** A follow-up set in motion by an earlier
  choice always arrives when due, even into a full queue.
- **Looking away is a decision.** A situation not decided within two months
  takes its default option, and the record and the monthly report say so.
  A default option can never be gated, so this is always possible.
- **The clock stops for news.** A situation the player has not seen pauses the
  game and plays the alert cue, so it cannot slip past at speed ×5.
- **One saved random stream.** Arrival and follow-up rolls come from the
  campaign RNG, so a reloaded game unfolds exactly as it would have.
- **Honest content.** An event with an unknown trigger condition or a missing
  consequence handler never fires, rather than doing half of what it says.
- **Laws and events share one effect pipeline** (`sim/effect_bundle.gd`):
  economic deltas, faction loyalty/power, modifiers, one-off debt.
- **Roles, not party names.** `@labour`, `@nationalist`, ... resolve to the
  faction furthest out on the role's axis — Ardenia's labour anger lands on
  the Workers' Front, not the Social Democrats. A role nobody holds and with
  no axis (`@establishment` in Ardenia) resolves to nobody rather than to a
  wrong party.
- **Diplomatic situations stay about their country.** "The coolest
  neighbour" is fixed when the situation arrives, so the briefing and the
  consequence name the same state.

## Content fixes made to `catalogs/events.json`

The exporter could not name eight Python lambda conditions or six option
gates. They are now explicit: conditions `always`, `price_or_debt_alarm`,
`out_of_office`, `own_party_seated_in_opposition`, `high_unemployment`; gates
are data — `{"background": "economist"}` or `{"player_social_at_most": -0.2}`.
Re-running the retired exporter would undo this; edit the JSON directly.

## Known gaps

- At 1280x720 the situation panel shows one option above the fold; the rest
  scroll. Phase 5 layout work should give the panel more of the body.
- No dispatch/press voice yet: arrivals and lapses are reported as plain
  monthly-report lines.

## The schemer arc

A schemer grows abler and more ambitious each month while their loyalty
wears thin (`CabinetSim`); Ardenia's opening schemer crosses the threat
line in month 22, and the arc opens between months 22 and 28 across seeds.
Confronting early leads to a reckoning (buy them off, or force them out);
waiting lets them move (crush them at a stability cost, expose them, or
let them rise). A schemer who rises emboldens the player's own party and
forces a formal leadership challenge: face it down, accommodate the wing
(the leader's ideology moves toward it), or purge it. Every step finds its
schemer fresh and does nothing if they have already gone.

## The Vasca question

The west stirs (once per campaign, never before month 8) for a government
that looks weak: stability under 0.65, approval under 0.50, or civil-war
risk over 0.25. A crackdown succeeds in proportion to real security
effectiveness — the Interior and Defense ministers' implementation quality
(0.30 for a vacancy) weighted 60/40 with stability, capped at 92% — and a
former general leading in person adds 20 points. An amnesty holds with
odds 0.35 + approval × 0.5. Every road moves `insurgency_pressure`, which
now feeds national unrest (×0.40). Five recorded endings live in
`campaign_meta["vasca_status"]`: captured, dead, exiled, isolated, and
unresolved — "no ending" is recorded too, and any ending closes the arc.
Rolls use the campaign RNG, so reloads replay the same story.

## Vetrenka

A different rhythm from Vasca: recurring friction on the line of contact
(cooldown 6) resolves nothing but is counted in
`campaign_meta["vetrenka_incidents"]`. After `FRICTION_BEFORE_CROSSROADS`
(3) incidents the once-only crossroads opens: peace talks (odds read the
government's deviation from the ordinary approval 0.49 / stability 0.48 —
measured 0.45 for a typical government, 0.87 for a strong one), an
offensive (odds from security effectiveness, 0.08–0.70: 0.12 for a broken
army, 0.63 for a capable one), or formalising the line, the default. A
hardened line is worn quietly only if approval + stability/2 minus the
nationalist seat share exceeds 0.70. Six endings — settled, talks_failed,
retaken, routed, partitioned, partitioned_contested — each recorded in
`campaign_meta["vetrenka_status"]` and each redrawing the region's control,
issue, reach and pressure. A government that never engages lets the line
harden in about 15 months.

Follow-up situations are now reported as "Following on from an earlier
decision", so the monthly report shows cause and effect.

## The civil-war gauge

Risk is never rolled: it is a deterministic reading of six named
components (collapsing stability, hostile factions, unrest, no governing
majority, the worst grievance, insurgency), which the gauge chases at 12%
of the gap a month. War breaks out at 0.75 and ends only below 0.40; each
month of war costs stability, approval, 5 PC and 1% of output, but never
ends the game. Insurgency weighs only 0.12 (it cannot start a war alone)
and decays 0.03 a month unless an arc feeds it. The eight world countries
run the same dynamics from coarser readings, and the monthly report names
any that falls into or out of war. Over 20 years no fiscal policy tips
Ardenia into war; reckless ones run at 0.50–0.52 against 0.37 for steady
government.

## Decisions from the slice-2 code review

- **Government business waits for a government.** A follow-up whose
  audience is not met (government business while the player is out of
  office) stays scheduled and arrives once it can; a pending situation in
  that state is frozen — it does not lapse, cannot be decided, and is not
  shown. Without this, losing office mid-arc would strand Vasca or Vetrenka
  for ever. Only content that can never play is dropped from the schedule.
- **Looking away costs what choosing would.** A lapse charges the default
  option's political-capital cost (as much as the government has), so
  ignoring a situation is never the cheap way to pick its default.
- **The decision window** runs through the end of the deadline month: a
  situation arriving in month T can be decided in T, T+1 and T+2 and
  lapses at the T+3 close. "Decide this month" in the last month is exact.
- **Lag is deliberate.** Situations close the month, after approval and
  stability, so an effect from a lapse or an arc shows in the next month's
  figures — the report announces it first, the numbers follow.
- Ties for "worst relation" break by country id, so a reload cannot change
  which neighbour a diplomatic situation is about.
