# Ardenia Godot — the living world (Phase 4)

**Status:** situations engine, the schemer arc, the party leadership
challenge and the Vasca question are playable (2026-10-28). Arcs, the civil-war gauge, diplomacy verbs, the AI countries,
opposition play and the press remain. Same native-design rules as
`SIM_REDESIGN.md`: Python is a reference for what Ardenia contains, never a
formula to match.

## Phase 4 slices, in order

1. **Situations engine** — done. Arrival, pacing, decisions, default lapse,
   follow-up chains, the shared effect pipeline, role resolution, persistence,
   the "needs you" queue and the situation panel.
2. **The arcs** — the schemer, the leadership challenge and Vasca are done
   (`sim/arcs.gd`, `sim/cabinet_sim.gd`); Vetrenka and opposition
   by-elections remain. Each needs its bespoke
   consequence handlers (`on_apply` ids) written into
   `Arcs.HANDLERS`; until a handler exists, its events cannot
   fire (`EventsSim.unplayable_events()` lists them). Their trigger
   conditions (`schemer_plotting`, `vasca_stirring`, `vetrenka_friction_due`,
   `vetrenka_crossroads_ready`) join `Arcs.CONDITIONS` with them.
3. **Civil-war gauge** — insurgency pressure and the latched catastrophe,
   fed by the arcs.
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
