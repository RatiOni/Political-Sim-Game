# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## What this is

A single-player political/state-management simulation game in pure Python. Two front-ends share one simulation engine:

> **Current scope: Ardenia-only, by design.** A new campaign always plays **Ardenia**. The wizard presents one selected "Begin the Ardenia campaign" choice and explains that neighbouring states remain active world actors. The other eight countries are fully implemented as *data and as world actors* — AI governments with agendas and plans, diplomacy targets, map neighbours, civil-war candidates — and everything in `engine/` is country-agnostic (see "Country-neutral content"), but they are **not player-selectable yet**. The gate is one constant — `ui/menu.py: PLAYABLE_COUNTRY_IDS` — plus a guard in `CountrySelectStep.collect`; widening scope later means adding ids to that set, not unpicking anything. Do **not** remove the other eight from content, worldsim, or the map; `build_state_for(<any id>)` must keep working, and tests still exercise it.

- **`gui.py`** — the real game: a PySide6 (Qt6) desktop app with a main menu, New Campaign wizard (country → character → difficulty → seed), world map, and save/load.
- **`main.py`** — a terminal front-end that always starts the fixed Ardenia scenario. Fast iteration target; it's what `smoke_test.py` drives.

No build system, linter, or dependency manifest — a plain source tree run against the interpreter in `.venv` (PySide6 is the only third-party dependency).

## Commands

- **Run the GUI:** `.venv\Scripts\python.exe gui.py`
- **Run the CLI:** `.venv\Scripts\python.exe main.py`
- **Run the engine/CLI test suite:** `.venv\Scripts\python.exe smoke_test.py`
  Not pytest — one hand-rolled script, `assert`-based, `PASS`/`FAIL` per check, exit 1 on failure. Sections run top-to-bottom in one process: **A** direct mechanics, **B** action-menu integration (scripted numeric input), **C** turn-loop invariants, **D** modifier lifecycle, **E** stability, **F** elections + turnout, **G** campaign framework/persistence, **H** dynamic events, **I** living world + civil war, **J** organic inflation, **K** intraparty wings, **L** flavor layer + event chains, **M** roleplay (identity gating, leadership moves, the rival), **N** immersion (press, structured news, world arcs), **O** consequential wings (rebellions, leadership, cohesion), **P** diplomacy verbs (pacts, sanctions, summits, treaty exit), **Q** pacing (world deliberation + PC upkeep), **R** cabinet personalities (traits, shortlists, representation), **S** regression guards (bugs found in review), **T** country-neutral content (roles resolve in all nine countries), **U** dramatization (schemer arc branching, rival escalation, dispatch variety). No way to run one section in isolation — comment others out or write a throwaway script.
  **Seeded-stream fragility:** tests that `random.seed(...)` then assert a specific trajectory WILL break when new content adds RNG draws (each event/name-gen consumes stream). Write such tests against direct mechanics (no turn loop), or patch `engine.events.event_catalog` — see I5/H/L for the idiom.
- **Headless GUI test:** `.venv\Scripts\python.exe ui_smoke_test.py` — **known pre-existing issue:** any check that calls `.exec()` on a modal dialog hangs forever under `QT_QPA_PLATFORM=offscreen` on this machine (nothing clicks it), and the script only prints its results at the end, so a hang looks like zero output. Don't treat a hang as a regression. The working idiom is to patch the modals out and run the file's `main()`:
  `QDialog.exec = lambda self, *a, **k: 0` (plus `QMessageBox.exec`/`.information`) before `import ui_smoke_test; ui_smoke_test.main()`. The five system pages are no longer modal (they're dock tabs), so they test directly.
- Offscreen rendering has no fonts → text draws as boxes in screenshots. Register a TTF via `QFontDatabase.addApplicationFont(r"C:\Windows\Fonts\arialbd.ttf")` in the harness when a readable render matters.

## Architecture

### Layering: `models/` → `content/` → `engine/` → (`main.py` / `ui/`)

- **`models/*.py`** — plain dataclasses only. Nothing here imports `game_state.py` or `engine/*` (no circular-import risk when adding `GameState` fields that reference model types).
- **`content/*.py`** — data: `countries/*.json` (nine countries; adding one is a JSON file + a map cell), `bills.py`, `events.py`, `traits.py`, `campaign_content.py`, and `loader.py` (`build_state_for(id)` assembles a full `GameState`; it also wires bilateral relations for **every** country pair and seeds authored `meta.stability_value` + civil-war risk).
- **`engine/*.py`** — all simulation logic. `turn.py: TurnEngine.advance()` is the per-month loop; its docstring lists the exact phase order (order matters — later phases read earlier phases' same-turn results). Key modules: `legislative.py` (incl. `apply_effect_bundle`, the shared consequence pipeline), `elections.py` (deterministic turnout → seats), `stability.py` (shared signal functions), `worldsim.py` (AI countries acting on agendas), `crisis.py` (civil-war gauge), `events.py`, `campaign.py`, `persistence.py`, `player_ops.py`, `actions.py`.
- **`game_state.py`** — the one `GameState` dataclass everything reads/mutates. No other module-level mutable game state exists.

### The GUI shell

`ui/app.py: MainWindow` is a dashboard (top bar → `AlertStrip` → left stats / map / right panel → assembly + dispatch feed) plus a **persistent tabbed dock** (`ui/dock.py: SystemDock`, right-hand side) holding the five system pages. Those pages were modal dialogs; they're now plain widgets (`widgets_common.PagePanel`, aliased as `PageDialog`) that live for the whole session, so the map and stats keep updating while you use them. Consequences to respect when touching them: the dock pushes the live `GameState` into every page on each `_refresh_all` (pages can't assume the state object they were built with is current — loading a save replaces it); only the visible tab is redrawn, hidden ones are marked stale and catch up on switch; and because modality no longer blocks input, End Turn is guarded explicitly by `PagePanel.has_uncommitted_input()` (only CabinetPage's drawn-but-unappointed shortlist returns True) plus a re-entrancy flag in `advance_turn`. `EventDialog`, `TurnSummaryDialog`, and the breakdown dialogs remain deliberately modal.

### Two front-ends, one action implementation

Every player action's real logic is one input-free `op_*(state, ...) -> ActionResult` in **`engine/player_ops.py`**. The CLI (`engine/actions.py`) gathers input via `choose()`/`input()`; the GUI (`ui/pages.py`, `ui/dialogs.py`) gathers it via widgets and calls the same op through `MainWindow._run_op`. **New action logic goes in `player_ops.py`** — never duplicated into both front-ends.

### The Modifier system

`models/modifiers.py: Modifier` is the mechanism for *any* delayed/lingering effect (laws, loans, treaties, events): `onset_delay → ramp → hold → decay`. The engine recomputes each modifier's current value fresh every turn — nothing accumulates — so effects stay bounded forever. **Attach a Modifier rather than repeatedly mutating a stat.** `institutional=False` is reserved for contractual effects (loan interest) that no minister or crisis can discount.

### Determinism philosophy

Elections, turnout, stability, civil-war risk are **never rolled** — they're deterministic functions of tracked state. RNG appears only in event/scandal/protest/agenda *triggers* (seedable in tests via `random.seed`).

### The voice layer

Dispatches route through `engine/flavor.py: say(state, key, **fields)`, which picks a wording variant from the template pools in `content/dispatches.py`. Variant choice uses a **local** `Random` seeded from (turn, key, log-position) — never the global RNG stream (that would shift every seeded test). `MARKERS` in dispatches.py guarantees a stable keyword per dispatch type; tests match on markers, not exact wording. Named people feed the templates: `Faction.leader` (authored in ardenia.json, generated elsewhere via `cabinet_ops.generate_name()`) and `Country.leader_name` (from each JSON's `default_player`).

### Consequential wings

A bill with an authored `Law.ideology` splits every multi-wing party's seats across its wings (`legislative.wing_votes`, largest-remainder): each wing votes the party line ± its own read of the bill (`WING_SALIENCE`), so distant restless wings rebel (`vote_rebellions`, dispatched on resolve). A bill with `ideology=None` keeps the exact legacy bloc vote — that's the safety gate. Wing takeovers by a disloyal wing (loyalty < 0.5) oust non-player party leaders (`parties.update_party_wings`); the player's own party instead raises the `party_leadership_challenge` situation (options use `EventOption.on_apply`, the content-callback hook for effects a LawEffect can't express). Average coalition cohesion feeds `compute_target_stability` ("Coalition cohesion" component, zero drag at full cohesion).

### The press layer

`flavor.say` records every dispatch as a structured `(key, fields, text)` item in `GameState.turn_news` (ephemeral, cleared per turn); the few direct `state.log` dramas (situations, elections, confidence votes) append their own captures. `engine/press.py: front_page(state, before, after)` ranks them by drama and builds a newspaper (masthead from `Country.paper`, else "The X Herald") from the headline/lead pools in `content/press.py` — `SAMPLE_FIELDS` there documents each key's fields and is linted by Section N. The GUI's `TurnSummaryDialog` IS the front page; the CLI prints the lead above the turn log. `GameState.world_arcs` (persisted) tracks named one-time world developments (axes/feuds) detected in `worldsim._update_world_arcs`.

### Roleplay layer

The player's identity is mechanical all game: each `Background` in `content/campaign_content.py` carries an ongoing ability (`action_label`/`action_deed`/cost/cooldown) executed by `player_ops.op_background_action`; `op_address_nation(state, tone)` gives four context-dependent tones. Both live in the CLI "Leadership" category and on the GUI Briefing page. Cooldowns are generic: `GameState.cooldowns` + `player_ops.on_cooldown/start_cooldown`. `EventOption.requires` (a callable on state) gates situation options by background/ideology — enforced in `events.available_options`, `op_resolve_event`, the CLI listing, and `EventDialog`; an event's default option must never be gated (auto-lapse takes it; Section M lints this). `engine/roleplay.py` supplies the dynamic rival (strongest hostile party's leader) who jibes after stumbles, escalating across a campaign: `jibe_tier()` picks between the `rival_jibe` / `rival_jibe_sharp` / `rival_jibe_bitter` pools from a counter kept in `GameState.cooldowns` (already persisted, so no new field) plus current approval — dismissive early, sharper once blows land or the government struggles, bitter for a rival who keeps being right and losing anyway.

### Ardenia's history (canon)

`content/lore.py` is the single source of truth for the backstory the data always implied: the Kolvenian Union and its doctrine Dravism, the February Intervention of 1921, Kestrel Square 1989, the Awakening, Dorin Vasca's presidency and the Turn of the Year coup, Cyrus Baran's State Council, the Vetrenka War and its unresolved ceasefire, and the Reckoning election that seats the player's coalition in March 1993. Plain data (`TIMELINE`, `PARTY_ORIGINS`, `FIGURES`, `opening_briefing()`), no imports from engine/models — the Codex (`ui/pages.py: HistoryPage`, the dock's sixth tab) renders it, `engine/campaign.py: _opening_briefing` seeds the first three dispatches from it, and event flavour cites it. **Krasova is the Union's core successor state and Vetrenka's backer** — that's why it's Ardenia's default antagonist. The player's default name deliberately matches the Liberal Democrats' leader: the player *is* the party leader, elected at the Reckoning. That is not a bug; don't "fix" it. Vasca's fate, Vetrenka's future, and what became of Doncic and Yeska are deliberately open for future event chains.

### Country-neutral content (roles)

`content/events.py` names no country's parties or neighbours. Faction effects address canonical **roles** — `models/roles.py`: `@labour`, `@business`, `@nationalist`, `@agrarian`, `@reform`, `@establishment`, whose centroids are the cluster means of the 37 authored factions across all nine countries. `content/loader.py` stamps `Faction.role` (nearest centroid) at build time; `legislative.resolve_faction_key` turns a role into a concrete faction when the effect lands — the single resolution point, because the mapping is per-country. `role_faction` picks whoever is **furthest out on the role's defining axis** (`ROLE_AXIS`), so Ardenia's labour bloc stays the Workers' Front and Terand's nationalists are the Military Bloc; if no faction classifies into a role, it falls back to the best sign-correct candidate (Solheim's Liberal Party covers business). Diplomatic effects use `TARGET_COOLEST` / `TARGET_MOST_HOSTILE`, resolved against the relation that triggered the event (`events.resolve_relation_target`).

Section T is the guardrail: it asserts every role resolves in every country apart from an explicit, re-verified exception list (only Terand/labour — no faction there sits left of centre), that every option's declared roles land sign-correctly in all nine countries, and that no option is a silent no-op anywhere. **A new country JSON or an edited ideology vector will fail Section T if it creates a role gap** — that's the point.

### The schemer arc (a branching chain)

The one multi-step, *branching* story: `a_schemer_stirs` → (`confront` → `a_schemer_confronted` | `wait` → `a_schemer_moves`) → `a_schemer_triumphant` → hands off to `party_leadership_challenge`. Entry is gated on the schemer trait's own threat curve, so it plays in whichever country's cabinet has a schemer — never a hardcoded minister id. Every step re-resolves its subject via `_arc_schemer(state)` and no-ops quietly if that minister has since left. **Note:** `threat_level()` is `ambition × (1 − loyalty)`, so schemers carry `loyalty_drift` in `TRAIT_EFFECTS` — without it a minister appointed at loyalty 0.5 was capped at 0.475 threat and neither this arc nor the older `minister_restless` warning could ever fire. Section U0 pins that.

### Dynamic events (chains)

`content/events.py` holds 20+ situations. `EventDef.once`/`cooldown` gate repeat fires (tracked in `GameState.event_fire_history`); an `EventOption.follow_up` (`{event_id, delay, chance}`) schedules a delayed consequence into `GameState.scheduled_events` — chain-only events use `condition=_never, chance=0.0` and fire exclusively via follow-ups, which bypass condition/cooldown gating.

### Cabinet personalities

`Minister.trait` + `TRAIT_EFFECTS` (in models/cabinet.py — mechanics can't live in content/ because models may not import upward): technocrat/firebrand/loyalist/grandee/schemer, each with real hooks — `effective_competence()` (feeds `implementation_quality`), `threat_level()` multipliers, an appointment loyalty bonus, a drift-proof loyalty floor, a capped cabinet `stability_trait_bonus`, and per-turn schemer growth (`turn.py:_update_ministers`, which also fires the `minister_restless` warning on threat > 0.5 with a per-portfolio cooldown). Appointment = choosing from `cabinet_ops.shortlist` (own party / coalition partner / high-competence wildcard) via `op_appoint_minister`; coalition partners drift +/− loyalty by cabinet representation (`_update_faction_loyalty`). The old `reshuffle(faction_id)` path still exists for compatibility.

### Diplomacy verbs

Beyond improve/trade/loan/condemn, the player holds real statecraft (`engine/diplomacy.py` mechanics + `player_ops.op_defense_pact/op_impose_sanctions/op_lift_sanctions/op_hold_summit/op_break_treaty`): defense pacts (trust-gated ≥0.45, both-sides `Treaty(type="defense")`, and `worldsim._hostile_action` shelves 50% of hostile moves against a pact-holder), sanctions (`BilateralRelation.sanctioned`, mirrored + persisted; the target bleeds growth/stability monthly in `simulate_world`, the player eats a lost-markets modifier if trade was big), summits (cooldown "summit"), and treaty exit (both-sides removal, penalty scaled by treaty type, a trade pact's growth modifier dies by `source_id`). Treaties age via `turns_active`.

### The world is alive

`engine/worldsim.py` runs every non-player country each turn: economy/stability drift, world↔world relation drift, and a **deliberation loop** (`_pursue_agendas` → `_make_plan`/`_execute_plan`): each country evaluates its national interest (`_national_interest`, deterministic — agenda type from `Country.agenda`: hegemon/revanchist/trader/reformer/survivor/ideologue + optional rival/ally; a sanctioning power outranks everything), commits to a `Country.plan` (persisted), foreshadows hostile/trade plans via the `world_deliberates` dispatch, executes when the plan matures (staggered openings — months 1–2 are quiet; then one action per country every ~3–5 turns), and plans again — including acting on the player. `engine/crisis.py` tracks a 0..1 civil-war gauge for player and world countries; past `CIVIL_WAR_RISK_THRESHOLD` it latches an ongoing catastrophe (recurring penalties, not a game over). Valmora is the authored crisis start (~0.72 risk).

### The PC economy

`turn.py: political_upkeep(state)` — every active law (0.8), treaty (0.6), and sanctions regime (1.0) consumes a slice of the monthly PC gain ("governing overhead"), floored at `PC_REGEN_FLOOR` (3.0) so no government is paralysed. Shared by the turn engine, the CLI capital bar, and the Briefing page's "Governing overhead" row. Repealing laws / exiting treaties frees capacity — the brake scales with commitments, not with time.

### Organic inflation

`turn.py: _update_structural_inflation` — deficits push structural inflation up, growth above trend overheats it, an anchor pulls it toward ~2%. Policy modifiers layer on top of the organic base.

### The map

`ui/widgets_map.py` draws a procedurally generated continent from **`ui/map_geometry.py`** — nine countries tiling one landmass with fractal shared borders (deterministic; same continent every launch). Each country is a clickable polygon filled by its live relation to the player, with game-drawn labels. The drawing code assumes nothing about the shapes beyond "a list of (x, y) points in 0..100 space", so a future custom map just replaces `COUNTRY_SHAPES`/`COUNTRY_LABEL_ANCHOR`.

### Persistence

`engine/persistence.py` maps `GameState` ↔ JSON **by hand**, versioned and tolerant (missing fields → model defaults). **Any new field on `GameState` or a nested model must be added to `serialize_state`/`deserialize_state` or it silently won't round-trip.** GUI autosaves each turn to the `autosave` slot in `saves/`.

## Gotchas

- Never name a `QDialog` subclass attribute `self.event` — it shadows Qt's internal `event()` method and breaks event dispatch (use `self._event`).
- **A long non-wrapping `QLabel` sets the window's minimum size.** Qt propagates a label's full text width up through every parent, so a status line or alert whose text changes at runtime makes the *window* grow on its own — it reads as the UI "zooming in", and with a dock open it can exceed the screen. Use `widgets_common.ElidedLabel` for any single-line text that varies, and give panels whose content grows (right panel, scroll columns) an explicit `setMinimumWidth/Height` — an explicit minimum overrides `minimumSizeHint`, so content scrolls instead of resizing the window. Same reason `AlertStrip` reserves a fixed-height band rather than growing with the alert count.
- Some `smoke_test.py` Section B/H tests drive the CLI menu with hardcoded positional input sequences — a menu reorder can silently exercise the wrong action rather than fail loudly. Known debt.
- In `smoke_test.py`, Section G8 reassigns the name `bill` from the helper function to a Law object — sections after G must fetch bills via `next(b for b in bill_catalog() if b.id == ...)`, never `bill(...)`. Has bitten twice (K6, O1).
- `content/countries/*.json` faction ids are still referenced by **bills** (`content/bills.py`) loyalty deltas; unknown ids are skipped safely, so those degrade gracefully rather than crashing. **Events no longer use literal faction ids at all** — they use roles (see "Country-neutral content"). If you add a delta to an event, use a `ROLE_*` key, and remember two ids that map to the same role would silently collide as dict keys.

## Imported Claude Cowork project instructions

help with video game development by coming up with ideas, catching bugs, changing code, and fixing/expanding the game

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
- Author a backlog-ready spec/issue → invoke /spec
