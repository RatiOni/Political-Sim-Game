# Engine pivot analysis — Ardenia

## What was measured (not assumed)

| Thing | Measured |
|---|---|
| `build_state_for('ardenia')` | 2.4 ms |
| 120 monthly turns, full `TurnEngine.advance` | 216 ms total, **1.80 ms/turn** |
| Full `serialize_state` + `json.dumps` | **1.37 ms**, **136 KB** |
| Simulation source (`engine/` + `content/` + `models/`) | 16,757 lines |
| Presentation source (`ui/`) | 7,589 lines |

Two conclusions fall straight out of those numbers.

**1. There is no engine-optimization problem to solve.** A turn costs 1.8 ms in
CPython. A player advances one turn every few seconds. The simulation runs
roughly 1000x faster than anyone can consume it. Nobody pivots engines for a
1.8 ms tick. If the game ever feels slow, it is Qt Widgets repainting
`QPainter` code in `ui/`, not `engine/turn.py`. Any "engine optimization" pitch
aimed at the simulation layer is solving a non-problem.

**2. The stated reason for rejecting a web UI in DESIGN.md does not survive
contact with the numbers.** DESIGN.md rejects the separate web app partly
because it "turns in-process `GameState` access into an API boundary." That
boundary costs 1.37 ms and 136 KB for the *entire* game state, and
`engine/persistence.py` already implements it. Pushing full state across a
local IPC channel every turn is cheaper than one frame of animation. The
serialization objection is dead. The scope objection is not (see below).

## The actual question

"Engine" here does not mean the simulation. `engine/`, `content/` and `models/`
are a clean, dependency-free, deterministic, well-tested 16.7k-line political
simulation with a country-agnostic core. That is the asset. It should survive
any pivot untouched.

The real question is: **what replaces the 7,589 lines in `ui/`?**

That reframing kills most of the candidate list immediately, because a
game-engine pivot means rewriting the simulation too.

## Options, ranked

### Rejected: Godot 4
Godot's Control-node UI is competent and its theming system is real, but the
pivot costs the whole Python simulation. `godot-python` is not a maintained
path a 16.7k-line deterministic sim should depend on, and the alternative is a
GDScript or C# rewrite of `engine/`, `content/` and `models/` plus the entire
`smoke_test.py` suite (sections A through AF). Months spent rebuilding
something that already works, in exchange for a UI toolkit that is *worse*
than QML for dense tabular data. Godot earns its keep for real-time rendering,
physics, and console export. Ardenia has none of those requirements.

### Rejected: Unity
Same rewrite cost as Godot, plus a heavier runtime and licensing exposure. UI
Toolkit (UXML/USS) is genuinely the best data-dense UI system in any game
engine and is the one honest argument for Unity here. Not worth a C# port of
the simulation. If you want HTML/CSS-shaped layout, get actual HTML/CSS
(option B) rather than Unity's imitation of it.

### Rejected: Bevy, MonoGame, LÖVE, Ren'Py
Wrong shape. Frame-loop or visual-novel engines for a turn-based
spreadsheet-with-consequences game. No path keeps the Python sim.

### Option A: PySide6 + Qt Quick/QML (the plan already in DESIGN.md)
- **Keeps:** the simulation, in-process `GameState` access, one third-party
  dependency, the PyInstaller distribution pipeline, all of `smoke_test.py`.
- **Buys:** GPU-composited scene graph, real gradients/blur/shaders,
  declarative layout, property animation, and `QQuickWidget` lets you migrate
  panel by panel instead of big-bang.
- **Costs:** all 7,589 lines of `ui/` get rewritten. QML is a new language for
  this codebase. Tooling is thin: no browser-devtools equivalent, a weak
  designer story, hot reload needs setup, and the community answer to most
  dense-data-UI questions is "write a custom `QQuickPaintedItem`", which is
  where you already are.
- **Ceiling:** high enough for everything in DESIGN.md. Not high enough for the
  layered, document-like presentation the "interwoven system" thesis
  eventually wants.

### Option B: keep the Python engine, put the UI in a web view
Python stays the game. The UI becomes HTML/CSS/TS talking to it over a local
channel. Two shells:
- **pywebview** — thinnest, uses the OS WebView2 on Windows, pip-installable,
  keeps a single-process Python app.
- **Tauri** — Rust shell, Python as a sidecar process, ~10 MB bundle, real
  auto-update and code-signing story.

- **Keeps:** the entire simulation, unchanged. `player_ops.py` is already
  input-free `op_*(state, ...) -> ActionResult` functions, which is exactly a
  command API. `persistence.serialize_state` is already the state wire format.
  The two-front-ends-one-implementation architecture in CLAUDE.md means a
  third front end is a supported shape, not a violation.
- **Buys, and this is the substance of the ask:**
  - *Visual UI creation and readability.* Flexbox and CSS grid solve the
    fixed-size and elision problems that CLAUDE.md's "Gotchas" section
    documents at length. Every one of those Qt sizing workarounds
    (`ElidedLabel`, the fixed band height on `AlertStrip`, `_DispatchLine`
    rows blanked-not-hidden, explicit `setMinimumWidth`) exists because Qt
    propagates content width up the parent chain. In CSS this is
    `min-width: 0` plus `text-overflow: ellipsis`. A whole category of your
    existing bugs stops being possible.
  - *Expansive features.* Charts, timelines, and force-directed policy graphs
    (Democracy 4's policy web, which DESIGN.md names as the reference point)
    are one library away instead of a `QPainter` project. SVG maps with real
    hit-testing replace the hand-rolled polygons in
    `ui/ardenia_map_geometry.py`.
  - *Iteration speed.* Devtools, live CSS editing, hot module reload. Design
    changes take seconds, not a relaunch.
  - `docs/ardenia_ui_mockup.html` is already the visual target. In this option
    the mockup and the product are the same technology.
- **Costs:** the same 7,589-line UI rewrite as option A, plus a second language
  toolchain, plus you lose "PySide6 is the only runtime dependency."
  Distribution gains a Node build step. The IPC boundary is real conceptual
  overhead even though it is performance-free.

## Recommendation

Do not pivot to a game engine. Godot and Unity both require discarding the one
part of this project that is finished and hard to rebuild.

Options A and B cost the same thing: a full rewrite of `ui/`. Since the price
is identical, pick on ceiling and tooling, and **B wins on both**. Web is the
better technology for dense, text-and-number, document-shaped interfaces, and
it is the only option where design iteration is fast enough to pursue taste
rather than budget it.

Choose A only if "one third-party dependency, plain Python source tree" is a
non-negotiable identity constraint rather than a preference. That is a
legitimate call and DESIGN.md already made it. But it is now the *only*
surviving argument for A, since the serialization objection measured out at
1.37 ms.

## "What makes a game a game" — the gap neither option closes for free

Both A and B leave you hand-rolling what a game engine gives away. Worth
planning explicitly:

- **Audio.** No music, no UI feedback sound, no ambience today. Qt gives
  `QtMultimedia`; web gives Web Audio, which is better. Adaptive scoring that
  responds to stability or crisis state is a real design opportunity and cheap
  in either.
- **Feedback and juice.** Numbers change instantly with no animation, so
  causation is invisible. This is the highest-leverage game-feel gap and it is
  exactly what DESIGN.md's "motion as truth" requirement is about. CSS
  transitions make it trivial; QML property animation makes it easy.
- **Onboarding and difficulty legibility.** `content/onboarding.py` exists;
  whether it teaches the interwoven-system thesis is a content question.
- **Localization.** No i18n layer. Qt has `tr()`; web has i18next. Retrofit
  cost grows with every authored string, and `content/lore/` is already large.
  Decide before it doubles again.
- **Modding.** `content/countries/*.json` is already a data format. Exposing it,
  plus events and bills, is a genuine longevity feature in this genre and
  costs little.
- **Accessibility.** Screen readers, UI scaling, colorblind-safe pressure ramp.
  Web is meaningfully ahead of Qt here, and the four-step `PRESSURE_*` ramp
  plus `PARTY_PALETTE` need a colorblind pass either way.
- **Achievements / Steam.** If Steam is ever a target, both options need
  Steamworks bindings; neither is harder than the other.
