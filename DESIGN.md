# Design System — Ardenia

## Product Context
- **What this is:** A single-player political/state-management simulation. The
  player runs Ardenia's government month-by-month — cabinet, parliament,
  budget, regions, diplomacy, an unresolved internal conflict — on a dense
  desktop dashboard.
- **Who it's for:** Players who read spreadsheets for fun. Genre peers:
  Democracy 4, Victoria 3, Suzerain, Old World.
- **The memorable thing** (drives every decision below): players should feel
  that *every decision matters*, and should come to understand statecraft as
  an **interwoven system they have to reason about**, not a menu of choices
  with instant effects. The UI's job is to prove that posture, not state it.

## Platform Decision
- **Current:** PySide6 (Qt6) Widgets, a plain Python source tree, PySide6 the
  only third-party dependency.
- **Target:** PySide6 stays — Qt Quick / QML replaces Widgets as the
  presentation layer, hosted via `QQuickWidget` embedded incrementally into
  the existing `QMainWindow`. `models/` → `content/` → `engine/` (the
  simulation itself) is untouched; only `ui/*.py` and the widgets it builds
  are affected.
- **Why QML over the alternatives considered:**
  - *Stay on Widgets* — real ceiling on gradients/blur/rich animation;
    everything is hand-rolled `QPainter` work. Rejected: too limited for the
    motion-as-truth requirement below.
  - *Embedded Chromium (`QWebEngineView`)* — maximum flexibility, but bundles
    a full browser runtime and breaks "PySide6 is the only third-party
    dependency." Rejected: dependency footprint too large for the gain.
  - *Full separate web app* — breaks the plain-Python-source-tree project
    identity, turns in-process `GameState` access into an API boundary.
    Rejected: multi-month scope, not a design-system follow-on.
  - **QML** — same dependency (PySide6 ships `QtQuick`/`QtQml`), GPU-composited
    scene graph gives real gradients/blur/shader-level animation, and
    `GameState` is still read directly from Python with no serialization
    layer. Cost is real (QML is a new language for this codebase, and every
    file in `ui/` is a rewrite, not a reskin) but it's the smallest
    architectural departure that removes the Widgets ceiling.
- **Migration is incremental**, panel by panel, via `QQuickWidget` hosts
  inside the still-Widgets `MainWindow` — not a big-bang rewrite. See the
  implementation plan for the first slice.

## Aesthetic Direction
- **Direction:** Industrial/Institutional — a working ministry, not a game
  HUD. No glow, no bevel, no sci-fi chrome.
- **Decoration level:** Intentional — subtle texture on document-register
  surfaces (dispatches, the newspaper front page), otherwise restrained.
- **Mood:** Weighty, consequential, systemic. The interface should always be
  answering "why is this number what it is," not just reporting the number.
- **Reference points (genre research):** Democracy 4's policy-web diagram
  (nodes/lines showing how policies pull on each other) is the closest any
  competitor gets to visualizing an interwoven system, but it's a diagram you
  open, not something baked into the whole interface — Ardenia's
  modifier-visibility system (below) is the deliberate improvement on that:
  always-on, not opt-in.

## Typography
- **Family (single):** [Public Sans](https://github.com/uswds/public-sans)
  (OFL-1.1, USWDS's own typeface — built specifically for citizens reading
  dense official government data at small sizes; distinct from the
  Inter/Roboto/system-ui default every AI-assisted UI converges on).
- **Display/Hero:** Public Sans SemiBold — country name header, dialog
  titles, the newspaper front page's masthead.
- **Body / UI / Labels:** Public Sans Regular.
- **Data / Tables:** Public Sans Regular using its tabular (lining) figures —
  no separate mono family. (A dedicated document/narrative serif and a
  separate ledger monospace were both proposed and explicitly declined —
  one disciplined family keeps the font-bundling and QML `FontLoader`
  footprint small, which the user chose over the extra visual register.)
- **Weights bundled:** Regular (400), Medium (500), SemiBold (600), Bold
  (700) — `fonts/ttf/PublicSans-{Regular,Medium,SemiBold,Bold}.ttf` from
  release `v2.001`.
- **Loading:** `QFontDatabase.addApplicationFont` for any remaining Widgets
  surfaces; QML `FontLoader` for QML surfaces. Both point at the same bundled
  `.ttf` files under `ui/assets/fonts/`.

## Color
- **Approach:** Restrained — one warm neutral ramp, one accent, semantic
  state colors, nothing else.
- **Base (kept from `ui/theme.py`, not reinvented):** warm burgundy, not the
  genre's default navy/steel-grey. This was proposed as a deliberate
  departure from genre convention (HOI4/EU4/Victoria/Ardenia's own earlier
  mockup all default to cold blue-grey, which reads as "great power" — not
  Ardenia's story as a post-collapse transitional state) and validated
  against research; the user chose not to spend effort re-litigating or
  reverting it, so it carries forward unchanged as the accepted baseline,
  not as a claimed "risk."
  - `BG #301d26` · `PANEL_BG #3e2732` · `PANEL_RAISED #4f333f` ·
    `PANEL_EDGE #70455a`
  - `INK #fdf4f7` · `INK_DIM #dcbcc7` · `INK_FAINT #ac8794`
  - `ACCENT #f0b365` · `ACCENT_SOFT #5c3a44` · `HIGHLIGHT #f7d99b`
  - `TRACK_BG #211219` · `ROW_LINE #4a2f3b`
- **Semantic:** `GOOD #5fd3a4` · `OKAY #98d98a` · `WARN #f0c66e` ·
  `BAD #f0916b` · `CRITICAL #ef5d6b` · `NEUTRAL #9a8792`
- **Regional pressure ramp (map only, never a party color):**
  `PRESSURE_CALM #2f5d6b` → `PRESSURE_UNEASY #6d6058` →
  `PRESSURE_STRAINED #b4762f` → `PRESSURE_CRITICAL #e0473f`
- **Party palette / relation colors:** unchanged from `theme.py`
  (`PARTY_PALETTE`, `REL_*`) — party identity and map pressure stay disjoint
  color systems, as already established.
- **New tokens for the modifier-visibility system** (needed because this is
  new surface area, not a port):
  - Force-glyph phase tints: *onset* → `INK_FAINT` (barely visible, not yet
    biting) · *ramp* → `ACCENT` moving toward the effect's sign color as it
    builds · *hold* → full sign color (`GOOD`-family if the modifier's
    current value is positive for the stat, `BAD`-family if negative) ·
    *decay* → sign color fading toward `INK_FAINT`.
- **Dark mode:** not applicable — this is a single fixed dark palette by
  design (no light-mode toggle exists or is planned).

## Spacing
- **Base unit:** 4px.
- **Density:** comfortable-to-compact — this genre's players tolerate density
  in exchange for information, but numbers still need room to stay scannable.
- **Scale:** 4 · 8 · 12 · 16 · 20 · 24 · 32 · 48 · 64 (matches the rhythm
  already visible in `docs/ardenia_ui_mockup.html`'s 14/22px paddings,
  rounded onto a clean 4px grid going forward).

## Layout
- **Approach:** Grid-disciplined — non-negotiable. Carried forward exactly as
  documented in `CLAUDE.md`: fixed-size dashboard cards, no reflow when state
  changes, map as literal center of gravity, vitals always visible.
- **Structure:** header (country · who · date · play/speed controls) → nav →
  alert strip (fixed-height band, empty or full) → 3-column dashboard (left
  stats / center map+assembly / right panel) → dispatch feed → the desk
  overlay (slide-in system pages).
- **Border radius:** sm 4px, md 7px, lg 8px (matches current card/track
  radii) — no full-round (`9999px`) anywhere; this is a ministry, not an app.

## Motion
- **Approach:** Minimal-functional, but literal — "motion-as-truth."
  Animation exists only to tell the truth about the simulation, never for
  delight. A stat whose value changed because of an active modifier animates
  over a duration derived from that modifier's real remaining ramp/decay
  window (converted from game-months to a perceptible ms range, capped so a
  long ramp doesn't take forever to watch); a stat with no active modifier
  animates over a flat default "value tick" duration.
- **Easing:** build/enter → `Easing.OutCubic` · fade/decay/exit →
  `Easing.InCubic` · repositioning → `Easing.InOutCubic`.
- **Duration:** micro (hover/press) 80ms · short (flat value tick) 200ms ·
  medium (modifier-driven bar fill) 350–900ms depending on the modifier's
  remaining ramp/decay length · long (desk slide-in, unchanged) ~240ms.

## The Modifier-Visibility System (the headline differentiator)
This is the one deliberate risk kept from the original proposal (the
burgundy-vs-navy and serif/sans-split risks were explicitly declined). It
turns the engine's real `onset → ramp → hold → decay` modifier lifecycle
(`models/modifiers.py: Modifier`) into a first-class, always-visible glyph
next to any stat it actually affects — not something the player has to open
a dialog to discover.

- **Where the data already exists:** `ui/explain.py: economic_effects(state)`
  already itemizes active modifiers per economic target
  (`gdp_growth`, `unemployment`, `inflation`, `budget_revenue`,
  `budget_expenditure`) as `(source, current_value)` pairs; `Modifier.
  phase_label()` and `Modifier.current_value()` give the lifecycle phase and
  signed strength for any individual modifier.
- **Where it's honest to show a glyph vs. not:** Approval has real itemized
  modifier data (`state.modifiers` filtered to `target == "approval_bias"`).
  Stability's breakdown (`stability_breakdown`) is computed *signal
  components* (coalition cohesion, economic conditions, ...), not discrete
  `Modifier` objects, and Political Capital has no `Modifier`-driven
  components at all in this engine — both get the QML visual upgrade
  (styling, motion) but **not** a fabricated force-glyph. The five economic
  rows (Growth/Unemployment/Inflation/Budget Revenue/Budget Expenditure) all
  have genuine itemized data and are the richest, most reliably-populated
  home for this system — the implementation plan's Phase 1 pilots the
  pattern on Approval (the single most-watched number) and establishes the
  reusable component the economy table adopts next.
- **Visual language:** a compact row of small ticks beside the stat, one per
  currently-active modifier touching it, each tinted by its lifecycle phase
  (see Color § new tokens above) and length-coded loosely to its relative
  strength. Hovering/clicking still opens the existing breakdown dialog — the
  glyph makes the *existence* of active forces visible at a glance; the
  dialog remains where the detail lives.

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-08-23 | UI presentation layer migrates from Qt Widgets to Qt Quick/QML, PySide6 retained | User wants more visual flexibility than Widgets/QPainter allows (gradients, blur, real animation) without adding a new runtime dependency or breaking the "PySide6 is the only third-party dependency" project identity. Alternatives considered: stay on Widgets (too limited), embed Chromium (dependency footprint too large), full web rewrite (breaks project identity, multi-month scope). |
| 2026-08-23 | Burgundy palette (`ui/theme.py`) retained unchanged as the color baseline | Originally proposed as a genre-departure "risk" (validated by research: warm burgundy fits Ardenia's post-collapse setting better than the genre's default navy/steel-grey). User declined to treat it as a risk worth re-litigating — it carries forward as the accepted baseline since it already exists and costs nothing to keep. |
| 2026-08-23 | Typography simplifies to one family (Public Sans) instead of a proposed serif/sans two-register split | User explicitly declined the two-register-typography risk in favor of a simpler, single-family system. Public Sans still replaces the prior `Segoe UI/Inter/Arial` system-font fallback, since leaving that in place would keep the generic "gave up on typography" look the design proposal was meant to fix. |
| 2026-08-23 | Modifier-visibility + motion-as-truth kept as the one differentiator | Directly serves the user's stated posture ("statecraft as an interwoven system, not click-and-effect") — the only proposed risk the user explicitly asked to keep. Scoped honestly to where the engine actually has itemized per-modifier data (Approval, and the five economic rows), not applied to stats (Stability, Political Capital) that lack it. |
