# Ardenia Godot — the living world (Phase 4)

**Status:** situations engine, the schemer arc, the party leadership
challenge, the Vasca question, Vetrenka, the civil-war gauge and
diplomacy are playable — all 46 events (2026-10-28) — the eight AI
countries deliberate and act, opposition is a full career, and the month
ends with a front page. Phase 4 is complete. Same native-design rules as
`SIM_REDESIGN.md`: Python is a reference for what Ardenia contains, never a
formula to match.

## Phase 4 slices, in order

1. **Situations engine** — done. Arrival, pacing, decisions, default lapse,
   follow-up chains, the shared effect pipeline, role resolution, persistence,
   the "needs you" queue and the situation panel.
2. **The arcs** — done: the schemer, the leadership challenge, Vasca and
   Vetrenka (`sim/arcs.gd`, `sim/cabinet_sim.gd`), and since slice 6 the two
   opposition events, whose handlers live in `OppositionSim` and are listed in
   `Arcs.HANDLERS`. An event whose handler is missing still cannot fire;
   `EventsSim.unplayable_events()` is now empty.
3. **Civil-war gauge** — done (`sim/crisis_sim.gd`).
4. **Diplomacy verbs** — done (`actions/diplomacy_actions.gd`,
   `sim/diplomacy_sim.gd`, the Diplomacy desk).
5. **The world acts** — done (`sim/world_sim.gd`).
6. **Opposition play** — done (`sim/opposition_sim.gd`,
   `actions/opposition_actions.gd`, `state/opposition_state.gd`).
7. **The press** — done (`presentation/voice.gd`, `presentation/press.gd`).

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

## Diplomacy

Nine verbs through one guarded entry point (`DiplomacyActions.act`), each
refusing with a stated reason and no side effect: outreach (+0.05 to
+0.10, scaled by the Foreign Affairs minister), a trade pact (once per
partner, growth benefit phasing in over two years), a defence pact (needs
trust ≥ 0.45; steadies the government; alarms the partner's rival),
sanctions (refused against a friend; halt trade; cost your own exporters
if the market was big), lifting them, summits (one every 8 months),
condemnation (pleases the nationalist right), tearing up a treaty (−0.20,
or −0.30 for a defence pact; a trade pact's growth benefit dies with it),
and the foreign loan. Foreign policy belongs to the government.

**The loan is a native design.** With real debt and market interest, a
loan that merely added cash and debt would be meaningless. A patron
refinances 5% of GDP of the public debt for 48 months at a concessional
rate (2%, +1% for an authoritarian lender, less for a warm relationship).
The saving against what the state actually pays is a contractual,
non-institutional budget line: about 98 M a year for a heavily indebted
Ardenia, 12 M for a lightly indebted one — and it always costs
nationalist goodwill.

Every month (`DiplomacySim`, run before the economy so customs read this
month's trade): like drifts toward like (democracies warm to democracies,
cool to autocracies); trade under a pact approaches a ceiling of
4000 × warmth at 4% of the gap a month and decays the same way when
relations cool; sanctions cost their target stability and output;
treaties count their months; loans run their term and retire. Both sides
of every relationship change together through `DiplomacySim.shift`, which
situations now use too.

The compact (1280×720) header now gives the date 120 px instead of 192 so
the Diplomacy button fits.

## The world acts

**Player-facing job:** the neighbours have their own interests, and the
player can read them coming. A foreign move should feel like policy, not
weather.

- **Interest, not dice.** Each country reads its national interest from its
  agenda (hegemon, revanchist, trader, reformer, survivor, ideologue, plus an
  authored rival or ally; an undeclared agenda follows the regime). A country
  at war with itself or below 0.35 stability turns inward; a survivor does so
  below 0.60. Whoever sanctions a country becomes its target, ahead of every
  other interest. A hegemon whose rivalry has bottomed out (below −0.8)
  spends the cycle courting a client instead.
- **Plans, then action.** The choice is a persisted `Country.plan` with a
  maturity month. Openings are staggered (first moves in months 3–6), then
  each country acts every 3–5 months — the one random draw in the
  scheduler, from the saved campaign stream, so a reload replays exactly.
- **Threats leak.** A hostile or trade plan is reported a month before it
  matures ("X is weighing its options toward Y"); courtesies are not.
- **Deterrence works.** Half of hostile moves against a defence-pact holder
  are quietly shelved. A condemnation costs 0.12 of relations, pressure 0.06.
- **No treaty without consent.** Foreign powers court the player (+0.06) but
  never sign a pact on the player's behalf; world-to-world trade pacts form
  between friends (relations above 0.1) and trade then grows like the
  player's. A country never courts the power sanctioning it.
- **Camps drift.** World-to-world relations warm within a regime camp and
  cool across camps at the same rates as the player's own.
- **Named arcs.** A pair above 0.7 with a trade pact becomes an *axis*; a
  pair below −0.7 a *feud*. Each is announced once, persisted in
  `GameState.world_arcs`, and dissolves (axis below 0.3, feud above −0.3)
  with a report of its end.

Over ten years in office or opposition the world takes about 240 actions and
every figure stays bounded.

A binary save whose length happened to begin with a space byte was misread
as JSON and refused; the loader now tries JSON and falls back to binary.

## Opposition play

**Player-facing job:** opposition is a career, not a waiting room. The
player cannot govern, but can shape what the government passes, build a
platform, staff a team, and arrive in office with a mandate to keep.

- **The government legislates.** A month after the campaign opens, and four
  months after each division, the ruling party brings a bill from the shared
  catalogue: the one closest to its ideology and its own interests, raised
  by the country's live problems — inflation lifts bills that cut prices,
  unemployment bills that add jobs or growth, a deficit bills that raise
  revenue or cut spending, war risk defence. A bill it lost is not retried
  for two years. The division comes the month after introduction, through
  the same vote and effect pipeline as the player's own laws
  (`LawActions.resolve`), with the ruling party and coalition whipped.
- **One declared position per bill.** Support (4 PC) whips the player's
  party for it, oppose (4 PC) against; amend (8 PC) offers the party's votes
  for a text pulled 30% toward the player's ideology with its material
  effects softened by a fifth. The division is held on the amended text.
- **A platform of three.** Pledges (5 PC) name catalogue bills; decrees and
  laws already in force cannot be pledged. Campaigning (8 PC, each pledge
  rests six months) moves support from the ruling party to the player's,
  more against a shaky government, and builds credibility — more with an
  able shadow minister for the brief. Dropping a pledge costs credibility,
  more for one that was campaigned on. Backing a bill you promised is
  consistent; opposing it is not. A pledge the government passes is
  *adopted* if you backed it, *undercut* if you fought it.
- **A shadow cabinet** (6 PC a post) is named from the player's party and
  gains a little experience each month. `OppositionSim.take_office` — the
  hook an election will call — restores the government title, builds the
  coalition around the player's party, promotes every shadow into the real
  post, lapses the outgoing government's bill and turns the platform into a
  mandate.
- **Promises are judged.** `electoral_edge` reads credibility, campaign
  coverage and staffing in opposition, and delivered against undelivered
  pledges in government; `judge_mandate` marks undelivered pledges broken
  at the vote, costing credibility and support.
- **The two opposition situations play.** *The Government Retreats* now
  arrives only within three months of a government defeat on the floor
  (`government_in_retreat`): claim it (the quicker support gain) or publish
  the alternative (credibility). *A By-Election Opening* (from month 6)
  is decided, never rolled, by standing — support against the ruling party,
  credibility, and the government's weakness: a national push wins only
  from ahead and is costly to lose; a local campaign wins from slightly
  behind for a smaller prize; a won seat comes from the government.

Not yet native: the general election itself. `take_office`,
`electoral_edge` and `judge_mandate` are its inputs and are tested
directly. The catalogue holds nine parliamentary bills, so a long
opposition term exhausts the government's programme after about five
years.

## The press

**Player-facing job:** a month should read like news. The paper tells the
player what mattered most, in a voice that changes from month to month
without ever changing what happened.

- **One voice.** `Voice.say(state, key, fields)` renders a variant from the
  authored dispatch pools and records `{key, fields, text}` in
  `GameState.monthly_news`. The variant is chosen by a local generator
  seeded from (month, key, position in the month's news) — never the
  campaign stream — so a reload reads the same and the simulation is
  untouched. Every variant of every dispatch carries its stable marker
  keyword (case-insensitive), so tests and players can rely on a word.
- **Who speaks.** Foreign plans, moves and arcs; civil wars at home and
  abroad; every parliamentary division, the government's and the player's.
  Situations, lapses, government bills and the bespoke arc outcomes (Vasca,
  Vetrenka, the schemer) keep their own sentences but are filed under their
  press key, so the paper can rank and headline them.
- **The front page.** `Press.front_page(state, before, after)` ranks the
  month's news by drama (Vetrenka retaken or Vasca dead above a neighbour's
  civil war, above a failed vote, above foreign courtesies, with a leak
  last), leads with the top story's headline and copy, runs up to four more
  headlines, and keeps everything else as briefs, with the month's opening
  and closing numbers. The masthead is the country's own paper, or "The
  <Country> Herald". A month with nothing to report says so.
- **Where it shows.** The month closes by printing the page into
  `GameState.front_page` (saved) and clearing the news; news from the
  player's own actions between closes runs in the next edition. The monthly
  report's dispatch column shows the masthead, the lead and the headlines.
