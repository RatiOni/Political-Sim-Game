"""
Central visual theme: a warm burgundy strategy-dashboard palette. Surfaces
carry the hierarchy; colour is reserved for state, selection, and action.

The base was a very dark navy. This is a deliberately warmer and lighter
range — a wine-red neutral rather than a blue-black one — so the dashboard
reads as a room rather than a void. Every surface here is a step lighter than
its navy equivalent was; if you darken these again, darken them together, or
the hierarchy (BG < PANEL_BG < PANEL_RAISED) stops being legible.
"""

# ── Base palette ──────────────────────────────────────────────────────────
BG           = "#301d26"   # window background — burgundy, not black
PANEL_BG     = "#3e2732"   # main card surface
PANEL_RAISED = "#4f333f"   # controls and nested cards
PANEL_EDGE   = "#70455a"   # restrained borders / gridlines
INK          = "#fdf4f7"   # primary text
INK_DIM      = "#dcbcc7"   # secondary / label text
INK_FAINT    = "#ac8794"   # tertiary / disabled

# Warm gold reads as "act here" against burgundy where the old cool blue
# would have fought it.
ACCENT       = "#f0b365"   # navigation and selection
ACCENT_SOFT  = "#5c3a44"   # selected/hover surface
HIGHLIGHT    = "#f7d99b"   # scarce attention colour
MAP_SEA      = "#2a1922"

# Sunken track behind a bar fill — one step darker than the window.
TRACK_BG    = "#211219"
# Hairline between rows inside a panel (softer than PANEL_EDGE).
ROW_LINE    = "#4a2f3b"

# ── Semantic status colours ───────────────────────────────────────────────
# CRITICAL is deliberately hotter and lighter than it was: the old #e36b76 is
# very nearly the burgundy of the chrome, so "this is on fire" would have read
# as "this is a background".
GOOD        = "#5fd3a4"   # green
OKAY        = "#98d98a"   # soft green
WARN        = "#f0c66e"   # amber
BAD         = "#f0916b"   # orange
CRITICAL    = "#ef5d6b"   # red
NEUTRAL     = "#9a8792"   # grey

# ── Regional pressure ramp (map fills, and nothing else) ──────────────────
# One colour system per job: this four-step sequential ramp is the ONLY thing
# that fills a map region, and it never colours a party. PARTY_PALETTE is the
# reverse — parties only. Keeping them disjoint is what lets a glance at the
# map read as "how much trouble", not "who won here".
# Retuned for the burgundy base. The old ramp topped out at #ab4a52, which is
# essentially the chrome's own colour — "critical" has to be the one thing on
# the map that cannot be mistaken for background, so it is now a hot red, and
# the calm end is cool so the ramp runs across the wheel rather than along it.
PRESSURE_CALM     = "#2f5d6b"
PRESSURE_UNEASY   = "#6d6058"
PRESSURE_STRAINED = "#b4762f"
PRESSURE_CRITICAL = "#e0473f"

# Territory the state does not administer is drawn hatched over this neutral
# grey instead of being given a pressure colour — control status and pressure
# have to stay distinguishable at a glance.
OUTSIDE_ADMIN      = "#453a40"
OUTSIDE_ADMIN_LINE = "#8a7580"

# ── Map ink ───────────────────────────────────────────────────────────────
MAP_REGION_LABEL = "#fbf3f6"   # region names, over their own halo
MAP_CITY_LABEL   = "#e0c9d1"   # city names
MAP_CITY_DOT     = "#b596a2"   # ordinary city markers
MAP_FOREIGN      = "#7a5c68"   # neighbour countries, outside the border
MAP_SEA_LABEL    = "#4a333d"   # the sea, quietest thing on the map

PRESSURE_STEPS = (
    (0.30, PRESSURE_CALM,     "Calm"),
    (0.50, PRESSURE_UNEASY,   "Uneasy"),
    (0.70, PRESSURE_STRAINED, "Strained"),
    (1.01, PRESSURE_CRITICAL, "Critical"),
)


def pressure_color(value: float) -> str:
    """Map 0..1 regional pressure onto the four-step ramp."""
    v = max(0.0, min(1.0, value))
    for ceiling, color, _name in PRESSURE_STEPS:
        if v < ceiling:
            return color
    return PRESSURE_CRITICAL


def pressure_word(value: float) -> str:
    """The ramp step's name, so the legend and the readouts always agree."""
    v = max(0.0, min(1.0, value))
    for ceiling, _color, name in PRESSURE_STEPS:
        if v < ceiling:
            return name
    return "Critical"


# ── Relation / bloc colours (the map legend) ──────────────────────────────
REL_ALLIED   = "#4f86d9"
REL_FRIENDLY = "#75a8dc"
REL_NEUTRAL  = "#65788e"
REL_TENSE    = "#d28b62"
REL_HOSTILE  = "#c95d68"
REL_PLAYER   = "#d9b867"
REL_UNKNOWN  = "#3b4a5e"

FONT_FAMILY   = "'Public Sans', 'Segoe UI', Inter, Arial, sans-serif"
FONT_SIZE_PT  = 10
FONT_SIZE_SM  = 9
FONT_SIZE_LG  = 14


# ── Party identity colours ────────────────────────────────────────────────
# A stable palette for parties that don't declare their own colour. Assigned
# by a faction's id (see assign_party_colors) so a party keeps the same colour
# turn to turn — the seat arc and election results depend on that stability to
# stay legible as seats shift around.
PARTY_PALETTE = [
    "#c0392b",  # red
    "#3b7dd8",  # blue
    "#4caf7d",  # green
    "#e0b04a",  # gold
    "#8e6fc0",  # purple
    "#d9694a",  # orange
    "#5aa0a0",  # teal
    "#b0708e",  # mauve
]


def assign_party_colors(factions) -> dict:
    """
    Returns {faction_id: hex colour}. A faction with an explicit `color`
    keeps it; the rest are handed palette colours in a stable order (sorted
    by id) so the mapping never shuffles between refreshes as seats change.
    """
    out = {}
    idx = 0
    for f in sorted(factions, key=lambda x: x.id):
        explicit = getattr(f, "color", None)
        if explicit:
            out[f.id] = explicit
        else:
            out[f.id] = PARTY_PALETTE[idx % len(PARTY_PALETTE)]
            idx += 1
    return out


def lerp_status_color(value: float, higher_is_better: bool = True) -> str:
    """
    Map a 0..1 value onto the good→critical status ramp. Used by every
    stat bar so "how healthy is this number" reads the same everywhere.
    higher_is_better=False flips it (for unemployment, inflation, debt).
    """
    v = max(0.0, min(1.0, value))
    if not higher_is_better:
        v = 1.0 - v
    if v >= 0.75: return GOOD
    if v >= 0.55: return OKAY
    if v >= 0.35: return WARN
    if v >= 0.20: return BAD
    return CRITICAL


def relation_color(score) -> str:
    """Colour for a bilateral relation score (-1..1), matching status_label()
    thresholds in models/relations.py so the map and the text agree."""
    if score is None:
        return REL_UNKNOWN
    if score >  0.7:  return REL_ALLIED
    if score >  0.3:  return REL_FRIENDLY
    if score > -0.3:  return REL_NEUTRAL
    if score > -0.7:  return REL_TENSE
    return REL_HOSTILE


def stylesheet() -> str:
    """The global application stylesheet. Applied once at startup."""
    return f"""
        QMainWindow, QWidget {{
            background: {BG};
            color: {INK};
            font-family: {FONT_FAMILY};
            font-size: {FONT_SIZE_PT}pt;
        }}
        QMenuBar {{
            background: {BG};
            color: {INK};
            border-bottom: 1px solid {PANEL_EDGE};
            padding: 3px 8px;
        }}
        QMenuBar::item {{ padding: 6px 11px; border-radius: 4px; }}
        QMenuBar::item:selected {{ background: {ACCENT_SOFT}; color: {INK}; }}
        QMenu {{
            background: {PANEL_BG};
            color: {INK};
            border: 1px solid {PANEL_EDGE};
        }}
        QMenu::item {{ padding: 6px 24px 6px 10px; }}
        QMenu::item:selected {{ background: {ACCENT_SOFT}; color: {INK}; }}
        QMenu::item:disabled {{ color: {INK_FAINT}; }}
        QLabel {{ color: {INK}; }}
        QPushButton {{
            background: {PANEL_RAISED};
            color: {INK};
            border: 1px solid {PANEL_EDGE};
            border-radius: 5px;
            padding: 7px 14px;
            min-height: 20px;
        }}
        QPushButton:hover {{ background: {ACCENT_SOFT}; color: {INK}; border-color: {ACCENT}; }}
        QPushButton:pressed {{ background: {ACCENT}; color: {BG}; }}
        QPushButton:disabled {{ color: {INK_FAINT}; border-color: {PANEL_EDGE}; background: {PANEL_BG}; }}
        QComboBox, QLineEdit, QListWidget {{
            background: {PANEL_RAISED}; color: {INK};
            border: 1px solid {PANEL_EDGE}; border-radius: 4px;
            padding: 5px 7px;
        }}
        QComboBox:hover, QLineEdit:focus {{ border-color: {ACCENT}; }}
        QComboBox::drop-down {{ border: none; width: 22px; }}
        QListWidget::item {{ padding: 5px 7px; border-radius: 3px; }}
        QListWidget::item:selected {{ background: {ACCENT_SOFT}; color: {INK}; }}
        QTabWidget::pane {{ border: 1px solid {PANEL_EDGE}; background: {PANEL_BG}; }}
        QTabBar::tab {{
            background: {BG}; color: {INK_DIM}; border: none;
            border-bottom: 2px solid transparent; padding: 8px 12px;
        }}
        QTabBar::tab:selected {{ color: {INK}; border-bottom-color: {ACCENT}; }}
        QTabBar::tab:hover {{ color: {INK}; background: {PANEL_RAISED}; }}
        QToolTip {{ background: {PANEL_RAISED}; color: {INK}; border: 1px solid {PANEL_EDGE}; padding: 5px; }}
        QScrollBar:vertical {{ background: transparent; width: 9px; margin: 1px; }}
        QScrollBar::handle:vertical {{ background: {PANEL_EDGE}; border-radius: 4px; min-height: 28px; }}
        QScrollBar::add-line, QScrollBar::sub-line {{ height: 0; }}
    """
