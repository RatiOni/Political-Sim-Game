# The guided first year — design

_Brainstormed with the owner, 2026-10-31. Evidence: `docs/playtests/2026-10-31-ux-review.md`._

## Why

The first screen of a new campaign tells the player nothing: three empty
panels, no statement of office or party, no goal, no first move. A year can
then pass before the game admits anything has gone wrong. The owner's
direction: **the game should guide the player through the first year until they
understand it.**

## Where this sits

The owner raised five items. They split into four sub-projects, each with its
own spec → plan → build cycle. **This spec designs C.** The other three are
recorded here so nothing is lost, and are designed separately.

| | Sub-project | Status | Build order |
|---|---|---|---|
| A | **Clock state** — paused vs running and at what speed must be unmistakable; speed hotkeys; the date visibly ticking. Today the button is labelled `PAUSED` (its state, not its action) and the speed-1 pip stays lit while paused (`app.gd` `_refresh_controls`: `button_pressed = index + 1 == _speed` ignores `_paused`). The input map has no speed keys. | to design | 1st |
| B | **Pause menu and options** — an Escape/pause menu with a route back to the main menu (none exists: nothing in `app.gd` returns to `menu.tscn`); settings (window mode, text size / UI scale, music and effects volume, autosave, guide default); confirmations before Load and Save-over (the project has zero confirmation dialogs); save slots with names and timestamps. Owns the user-settings store this spec depends on. | to design | 2nd |
| D | **Fundamentals pass** — see *D's scope* below. Its compact-vitals item must land before C. | to design | alongside, compact vitals before C |
| C | **The guided first year** | **this spec** | 3rd |

### D's scope (from the analysis of what is missing and what hurts)

- **Compact mode keeps the vitals.** `app.gd:142` hides the national panel at
  1280×720, removing approval, stability, political capital, the economy and
  the assembly with no alternative route. Replace with a compact strip.
  **Blocks C** — the opening's second step points at the vitals.
- **Success feedback is visible.** `_set_status` keeps only the last word in the
  header, so `SAVED / READY` shows `READY`.
- **Desks stop locking the dashboard.** Opening any desk disables every header
  destination and hides the vitals at the moment they are most needed.
- **Data before decoration on data screens.** The budget's largest envelope is
  below the fold at 1920×1080.
- **Player language, not system language.** Remove "the simulation", "once
  connected", "authorised steps" and the engine status footer from the player's
  view; fix the June/March 1993 mismatch and the region name printed twice.
- **Sentence case for anything longer than a label.**
- **Changes reported with cause and who felt them**, not as bare points.
- **The title animation settles.**

## Decisions taken in brainstorming

| Question | Decision |
|---|---|
| How does the year teach? | **Hybrid** — a short scripted opening that holds the clock and points at controls, then an advisor-led agenda while the game runs normally. |
| Which starts are covered? | **Government first.** The opposition start gets an agenda-only brief now; its full guided year follows after the government one has been playtested. |
| Do agenda items carry rewards or penalties? | **Guidance only.** The guide adds no mechanics. It makes the consequences the simulation already has visible in time. A guided campaign plays by exactly the rules of an unguided one. |
| Whose voice? | **Cyrus Baran**, the canonical architect of the handover, *"no formal power and more credibility than anyone who does."* **Text only.** Drawn as a small pixel figure in a suit, in the same style as the people in the desk scenes. |
| Architecture | **Data-driven guide with its own UI layer.** |

## The player's year

### 0. The offer

Immediately after New Campaign, before the clock runs, Baran asks: *"Shall I
walk you through the first year?"* — **Guide me** / **I know the job**.
**Guide me** is preselected unless the player has completed a guided year
before or has set the guide off in Options. Declining once does **not** change
the next campaign's default — a player who declines and then gets lost should
still be offered help. Both preferences (`completed_guided_year`,
`guide_default`) live in sub-project B's settings store, not in the save.

### 1. The scripted opening — March 1993, clock held

Each step waits for the player. Numbers in Baran's text are **live values**
filled from the snapshot, never written into the content.

| Step | Baran, in short | Points at | Waits for |
|---|---|---|---|
| `welcome` | Who you are — office, party, coalition partner, majority against the number needed. What is wrong — the deficit, unemployment, how many regions are in unrest, and that Vetrenka lies outside state control. | — | Continue |
| `republic` | Approval and stability keep you in office. Political capital is what you spend to act. | the national vitals | Continue |
| `map` | "Click a region marked UNREST." Explains pressure, jobs and state reach once one is selected. | the map | any region selected |
| `budget_open` | "Open the Budget." | the Budget button | budget desk opened |
| `budget_tour` | Inside the desk: the envelopes, the vote forecast, tabling — and "you have until December; nothing has to be decided today. Close the desk when you are ready." | the envelope list | budget desk closed |
| `clock` | "Start the clock." The speeds, and that a waiting decision will need your answer. | the clock control | clock started |

### 2. The first-year agenda — from the clock starting until January 1994

Five items, held in the decision rail with due dates. Each is a route: clicking
it opens the relevant desk. Each ticks itself off when its condition is met.

| Item | Done when | Due | What the item says about consequence |
|---|---|---|---|
| Pass the FY1994 budget | a budget for FY1994 has passed | before 1 Jan 1994 | Without one the state runs on an emergency budget: approval and stability fall each month, worse after six, and ministries carry extra load. |
| Answer a situation before it lapses | the player resolves a situation themselves | — | A situation left alone takes its default outcome. |
| Put a bill to the Chamber | a vote is held on a player bill, pass or fail | — | — |
| Launch a regional programme | a programme starts | — | Programmes cannot start while the state runs on an emergency budget. |
| Take one diplomatic step | any successful diplomatic action | — | — |

The consequence text states rules the simulation already enforces. If a rule
changes, its text must change with it; the lint test (below) cannot check
prose, so each consequence line names the constant it describes in a content
comment field.

### 3. Briefings — once each, the first time it happens

The first situation · the first monthly report · the first vote result · a
reminder on 1 November if the budget has not passed ("five weeks") · a
year-end review on 1 January 1994 that opens the Record and closes the guide.

### The opposition start (agenda only, this spec)

No scripted opening. The offer, then an agenda: name a shadow cabinet, make
three pledges, oppose or amend one government bill. Same rail, same card, same
rules engine. Its scripted opening is out of scope.

## On screen

### Baran's card

Bottom-right of the window; moves to bottom-left when its target lies beneath
it. Contains:

- **Baran**, about 48 px tall, drawn by `DeskView.figure()` — charcoal suit,
  white shirt front, dark tie, grey hair. **Point** pose, mirrored when the
  target is to his left; **stand** when there is no target.
- **`CYRUS BARAN · <in-game date>`**, then a body of at most ~60 words in
  **sentence case**.
- **Continue** (also Enter) and a smaller **Skip the guide**, which confirms and
  says the guide can be turned back on in Options. **Escape never skips** — it
  remains bound to closing desks.

A soft `UiSfx` cue plays when a card appears.

### The highlight

A slowly pulsing amber (`UiPalette.GOLD`) frame around the target's global
rect, on a top `CanvasLayer` so desks and panels cannot clip it. No scrim, no
input lock. The only thing a scripted step holds is the clock.

### Briefings hold the clock

A briefing pauses the clock until Continue, so nothing scrolls past unseen at
speed 5. Agenda changes never pause it.

### The agenda in the decision rail

A second block in the rail, `FIRST YEAR · n OF 5`, beside the decision queue.
The three soonest-due open items in fixed-height rows plus a `+n more` line —
the rail keeps its fixed height, per the dashboard rule that nothing changes
size with state. Completed items show struck and dimmed for one month, then
leave.

### 1280×720

The card shrinks (smaller figure, narrower body). Depends on D's compact-vitals
strip existing, because the `republic` step points at it.

## Architecture

```
data/native/catalogs/guide.json        the year as content
scripts/ui/guide/guide_rules.gd         rule id → predicate; nothing else
scripts/ui/guide/guide.gd               the director: step, listening, routing
scripts/ui/guide/guide_card.gd          Baran's card and the highlight layer
scripts/ui/guide/baran.gd               the figure (wraps DeskView.figure)
scripts/native/state/guide_state.gd     the saved record
```

### Content — `guide.json`

```json
{
  "government": {
    "opening": [
      {"id": "map",
       "text": "Click a region marked UNREST. {unrest_count} of them are, today.",
       "point_at": "ArdeniaMap",
       "until": "region_selected"}
    ],
    "agenda": [
      {"id": "budget",
       "text": "Pass the FY{next_fy} budget",
       "consequence": "Without one the state runs on an emergency budget...",
       "describes": "budget_sim.EMERGENCY_*",
       "done_when": "budget_passed",
       "due": "1994-01-01",
       "opens": "BudgetButton"}
    ],
    "briefings": [
      {"id": "budget_reminder", "when": "date>=1993-11-01 & !budget_passed", "text": "..."}
    ]
  },
  "opposition": { "agenda": [ ] }
}
```

- `{field}` placeholders resolve from a **fixed, named set** of read-model
  values exposed by `guide_rules.gd`. The initial set is exactly: `leader`,
  `office`, `party`, `partner`, `seats`, `majority`, `deficit`,
  `unemployment`, `unrest_count`, `next_fy`. Adding one means adding it to
  `guide_rules.gd`; an unknown placeholder fails the lint test.
- `point_at` and `opens` name **unique nodes** in `main.tscn`.
- `until`, `done_when` and `when` are rule ids.

### Rules — `guide_rules.gd`

A table from id to `Callable(snapshot: Dictionary, event: Dictionary) -> bool`.
Initial ids: `continue`, `region_selected`, `desk_opened:<desk>`,
`desk_closed:<desk>`, `clock_started`, `budget_passed`, `situation_answered`,
`bill_voted`, `programme_launched`, `diplomacy_acted`, `date>=<YYYY-MM-DD>`,
`first_situation`, `first_report`, `first_vote`, plus `&` and `!` for the
briefing conditions. Nothing else lives in this file.

### Where the guide hears things

- **UI events.** `app.gd` gains one signal, `ui_event(kind: String, arg: String)`,
  emitted where a desk opens or closes, a region is selected, and the clock
  starts — on the order of five lines. `app.gd` is already 1,975 lines; the
  guide adds wiring there and nothing else.
- **Game actions.** `NativeGame` gains `action_taken(kind: String)`, emitted when
  a player operation succeeds.
- **State.** The guide reads the same snapshots the dashboard does.

### Persistence

- Snapshots are read-only copies, so the guide never writes state directly. It
  calls **`NativeGame.update_guide(record)`**, which validates and stores it —
  `NativeGame` remains the only owner of campaign state.
- **`GameState.guide`** (`GuideState`): `mode` (`off` / `offered` / `opening` /
  `year` / `done`), `step` (opening index), `done` (agenda ids), `seen`
  (briefing ids). Round-trips through `GameState.to_dict` / `from_dict`.
- **A save without the record loads with the guide `off`.** The guide never
  interrupts a campaign that began without it.
- User preferences (`guide_default`, `completed_guided_year`) live in sub-project
  B's settings store, not in the save.

### Guidance only, enforced

The guide's only writes are its own record (through `update_guide`) and the
clock's pause state. It calls no player operation and attaches no modifier.

## Failure

- An unknown rule id, placeholder or target fails the **lint test**; it is not
  discovered in play.
- At runtime, a target that cannot be found shows the card without a highlight.
- **Any guide error turns the guide off for the session and the game carries
  on.** The tutorial must never be the reason the game cannot be played.

## Testing

All in the existing GDScript harness (`tests/native/run_contract_tests.gd`).

1. **Lint** — every rule id, placeholder, `point_at` and `opens` in
   `guide.json` resolves; every agenda item has a `done_when`.
2. **Rules** — each predicate against hand-built snapshots and events,
   including the `&` / `!` combinations.
3. **Journey** — boot `main.tscn` with the guide on; walk the opening through
   real `ui_event`s; assert the clock is held throughout and released at
   `clock`; save mid-opening, load, and resume at the same step; complete each
   agenda item through a real player operation.
4. **Guidance only** — run a seeded year guided and the same year unguided with
   identical player actions; the two final states must be equal apart from
   `GameState.guide`.
5. **Old saves** — a save written without a guide record loads with the guide
   off and never shows the offer.
6. **Render** — Baran's card at 1920×1080 and 1280×720, checked by eye.

## Out of scope

- The opposition start's scripted opening (agenda only here).
- Spoken or voiced dialogue — the owner asked for text only.
- **A government cabinet desk.** `cabinet_actions.gd` exists but no government
  screen reaches it, so "fill the cabinet" cannot be taught yet. Recorded as a
  gap for a later slice, not built here.
- Tutorials for systems the first year does not reach (elections, the energy
  crisis, the Vetrenka crossroads).
- Rewards, achievements or any mechanical effect of following the guide.
