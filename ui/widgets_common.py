"""
Shared Qt building blocks for pages and dialogs. Nothing here knows about
game logic — these take already-formatted strings and values.
"""

from PySide6.QtWidgets import (QDialog, QWidget, QVBoxLayout, QHBoxLayout,
                               QLabel, QFrame, QScrollArea, QSizePolicy,
                               QPushButton)
from PySide6.QtCore import Qt, QTimer, Signal

from ui import theme


def section_title(text: str) -> QLabel:
    lbl = QLabel(text)
    lbl.setStyleSheet(
        f"color: {theme.ACCENT}; font-size: {theme.FONT_SIZE_SM}pt; "
        f"letter-spacing: 1px; padding-top: 4px;")
    return lbl


def divider() -> QFrame:
    line = QFrame()
    line.setFrameShape(QFrame.HLine)
    line.setStyleSheet(f"color: {theme.PANEL_EDGE}; background: {theme.PANEL_EDGE};")
    line.setFixedHeight(1)
    return line


def body_label(text: str, dim: bool = False, small: bool = False) -> QLabel:
    lbl = QLabel(text)
    lbl.setWordWrap(True)
    lbl.setTextFormat(Qt.PlainText)
    color = theme.INK_DIM if dim else theme.INK
    size = theme.FONT_SIZE_SM if small else theme.FONT_SIZE_PT
    lbl.setStyleSheet(f"color: {color}; font-size: {size}pt;")
    return lbl


class ElidedLabel(QLabel):
    """A single-line label that shrinks by eliding its text with "…".

    A plain QLabel reports its full text width as a size hint, and that
    propagates all the way up into the window's minimum size — long strings
    end up forcing the whole window wider (and, on a small screen, off it).
    This one keeps its own minimum tiny and trims what it draws instead.
    """

    def __init__(self, text: str = "", parent=None):
        super().__init__(parent)
        self._full_text = text
        self.setTextFormat(Qt.PlainText)
        self.setMinimumWidth(40)
        self.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Preferred)
        self._apply_elision()

    def setText(self, text: str):
        self._full_text = text
        self._apply_elision()

    def fullText(self) -> str:
        return self._full_text

    def _apply_elision(self):
        metrics = self.fontMetrics()
        available = max(20, self.width() - 2)
        super().setText(metrics.elidedText(self._full_text, Qt.ElideRight, available))
        self.setToolTip(self._full_text)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self._apply_elision()


def banded(value: float, bands, reverse: bool = False) -> tuple[str, str]:
    """A raw value -> (label, colour), for the "named band, not decimal"
    treatment MinistryState.status_label() and HouseholdGroupState.
    status_label() already use. Word and number are shown together — the
    word is for scanning, the number is for comparing — so this returns
    both pieces rather than replacing one with the other.

    `bands`: ascending-by-VALUE (ceiling, label) pairs covering the metric's
    practical range; the last entry's label applies to anything at or above
    its ceiling. `reverse=True` when a HIGHER value is WORSE (load_ratio,
    where >1.0 means over capacity) — otherwise higher is treated as better.

    Colour always comes from theme.lerp_status_color at the band's rank in
    the table (0=worst band, 1=best), never a colour invented for this
    helper — so a new named-band field can never introduce a third colour
    system alongside the status ramp and the map's pressure ramp.
    """
    n = len(bands)
    idx = n - 1
    for i, (ceiling, _label) in enumerate(bands):
        if value < ceiling:
            idx = i
            break
    frac = idx / max(1, n - 1)
    if reverse:
        frac = 1.0 - frac
    label = bands[idx][1]
    color = theme.lerp_status_color(frac, higher_is_better=True)
    return label, color


# Shared band tables for banded(). Region pressure deliberately has NO table
# here — it reuses theme.PRESSURE_STEPS directly (theme.pressure_word /
# theme.pressure_color) via ui/panel_right.py: _pressure_label, which is the
# one thing item 3 says must not be reinvented. Budget balance likewise has
# no table here: it reuses engine.digest.BUDGET_BALANCE_BANDS, so the digest
# and the Policies page can never name a deficit two different things.
STATE_REACH_BANDS = ((0.25, "Absent"), (0.50, "Partial"), (0.75, "Present"), (1.01, "Full"))
LOAD_RATIO_BANDS = ((0.70, "Light"), (0.90, "Manageable"), (1.00, "Full"),
                    (1.25, "Over capacity"), (999.0, "Severely over capacity"))
CONFIDENCE_BANDS = ((0.30, "Disaffected"), (0.45, "Wary"), (0.60, "Content"), (1.01, "Confident"))


class KeyValueRow(QWidget):
    """LABEL ................ value  — a dotted-feel two-column row.

    The key elides. Two plain QLabels each reported their full text width as a
    minimum, and the sum of those minimums is what pushed the desk's pages
    wider than the desk — the Policies budget list ran off the right edge and
    grew a horizontal scrollbar. The value keeps its full width (a clipped
    figure is worse than a clipped label); the key gives way.
    """
    def __init__(self, key: str, value: str = "", value_color: str = None, parent=None):
        super().__init__(parent)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 1, 0, 1)
        layout.setSpacing(8)
        self._key = ElidedLabel(key)
        self._key.setStyleSheet(f"color: {theme.INK_DIM};")
        self._value = QLabel(value)
        self._value.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self._value.setStyleSheet(f"color: {value_color or theme.INK};")
        self._value.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Preferred)
        layout.addWidget(self._key, stretch=1)
        layout.addWidget(self._value)

    def set_value(self, value: str, color: str = None):
        self._value.setText(value)
        if color:
            self._value.setStyleSheet(f"color: {color};")


class MiniBar(QWidget):
    """A compact fixed-width labelled bar for breakdown rows: label + bar +
    signed value. Fill can be centre-anchored to show + / - contributions."""
    def __init__(self, label: str, parent=None):
        super().__init__(parent)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 1, 0, 1)
        layout.setSpacing(8)
        self._label = QLabel(label)
        self._label.setFixedWidth(150)
        self._label.setStyleSheet(f"color: {theme.INK_DIM}; font-size: {theme.FONT_SIZE_SM}pt;")
        self._bar = QLabel()
        self._bar.setFixedHeight(10)
        self._bar.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
        self._value = QLabel()
        self._value.setFixedWidth(60)
        self._value.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self._value.setStyleSheet(f"color: {theme.INK}; font-size: {theme.FONT_SIZE_SM}pt;")
        layout.addWidget(self._label)
        layout.addWidget(self._bar, stretch=1)
        layout.addWidget(self._value)

    def set_contribution(self, value: float, display: str, scale: float = 0.3):
        """value: signed contribution. scale: value that maps to a full half-bar."""
        frac = max(-1.0, min(1.0, value / scale)) if scale else 0.0
        color = theme.GOOD if value >= 0 else theme.CRITICAL
        # Represent magnitude via a coloured strip; sign via colour.
        pct = int(abs(frac) * 100)
        self._bar.setStyleSheet(
            f"background: qlineargradient(x1:0, y1:0, x2:1, y2:0, "
            f"stop:0 {color}, stop:{max(0.01, pct/100):.2f} {color}, "
            f"stop:{min(0.99, pct/100+0.001):.2f} {theme.BG}, stop:1 {theme.BG});"
            f"border: 1px solid {theme.PANEL_EDGE};")
        self._value.setText(display)


class Toast(QLabel):
    """A brief, non-blocking acknowledgement that an action happened.

    Floats over its parent, colour-coded by success/failure, and clears
    itself after a couple of seconds. Deliberately lightweight — the
    newspaper handles the drama; this just says 'that landed'.
    """

    VISIBLE_MS = 2600
    MAX_CHARS = 130

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWordWrap(True)
        self.setMaximumWidth(520)
        self.setTextFormat(Qt.PlainText)
        self.hide()
        self._timer = QTimer(self)
        self._timer.setSingleShot(True)
        self._timer.timeout.connect(self.hide)

    def show_message(self, message: str, success: bool = True):
        text = message.strip()
        if len(text) > self.MAX_CHARS:
            text = text[:self.MAX_CHARS - 1].rstrip() + "…"
        colour = theme.GOOD if success else theme.CRITICAL
        self.setStyleSheet(
            f"background: {theme.PANEL_BG}; color: {colour}; "
            f"border: 1px solid {colour}; border-radius: 3px; "
            f"padding: 7px 12px; font-size: {theme.FONT_SIZE_SM}pt;")
        self.setText(("✓  " if success else "✕  ") + text)
        self.adjustSize()
        self.reposition()
        self.show()
        self.raise_()
        self._timer.start(self.VISIBLE_MS)

    def reposition(self):
        """Bottom-centre of the parent, clear of the end-turn controls."""
        p = self.parentWidget()
        if p is None:
            return
        x = max(0, (p.width() - self.width()) // 2)
        y = max(0, p.height() - self.height() - 110)
        self.move(x, y)


class _NeedCard(QWidget):
    """One clickable thing that wants the player's attention.

    Fixed width and fixed height on purpose. A card that sized itself to its
    text made the strip's height and minimum width depend on which alerts
    happened to be live, so every resolved situation nudged the whole
    dashboard.
    """

    CARD_WIDTH = 300
    CARD_HEIGHT = 34

    def __init__(self, tag: str, text: str, severity: str, on_click, parent=None):
        super().__init__(parent)
        self.setObjectName("NeedCard")
        self._on_click = on_click
        self.setCursor(Qt.PointingHandCursor)
        edge = theme.CRITICAL if severity == "critical" else theme.WARN
        self._normal = (
            f"QWidget#NeedCard {{ background: {theme.PANEL_BG}; "
            f"border: 1px solid {theme.PANEL_EDGE}; "
            f"border-left: 3px solid {edge}; border-radius: 5px; }}")
        self._hover = (
            f"QWidget#NeedCard {{ background: {theme.PANEL_RAISED}; "
            f"border: 1px solid {theme.ACCENT}; "
            f"border-left: 3px solid {edge}; border-radius: 5px; }}")
        self.setStyleSheet(self._normal)
        self.setFixedSize(self.CARD_WIDTH, self.CARD_HEIGHT)
        self.setToolTip(f"{tag} — {text}")

        layout = QHBoxLayout(self)
        layout.setContentsMargins(11, 0, 12, 0)
        layout.setSpacing(8)
        tag_label = QLabel(tag.upper())
        tag_label.setStyleSheet(
            f"color: {theme.INK_FAINT}; font-size: {theme.FONT_SIZE_SM}pt; "
            f"letter-spacing: 1.2px;")
        tag_label.setSizePolicy(QSizePolicy.Fixed, QSizePolicy.Preferred)
        body = ElidedLabel(text)
        body.setStyleSheet(f"color: {theme.INK}; font-size: {theme.FONT_SIZE_SM}pt;")
        layout.addWidget(tag_label)
        layout.addWidget(body, stretch=1)

    def enterEvent(self, event):
        self.setStyleSheet(self._hover)
        super().enterEvent(event)

    def leaveEvent(self, event):
        self.setStyleSheet(self._normal)
        super().leaveEvent(event)

    def mousePressEvent(self, event):
        if self._on_click is not None:
            self._on_click()


class AlertStrip(QWidget):
    """The "needs you" queue: a row of clickable cards for the things that
    actually want a decision — a bill awaiting a vote, a situation waiting on
    an answer, a region past the pressure threshold.

    It used to be a full-width band whose commonest state was the sentence
    "No pressing alerts — your government has room to act", which spent a
    whole row of a dashboard saying nothing actionable. Now a quiet turn
    collapses it to zero height, and everything shown is a route to somewhere.

    Class name kept: ui/app.py and the UI smoke test refer to it.

    The band it occupies is a CONSTANT height whenever it is shown, and the
    strip's own minimum width is small regardless of how many cards are live.
    Both matter: a strip that grew and shrank with the alert list moved the
    entire dashboard down and up every time a situation was resolved, which is
    exactly the "UI keeps resizing itself" symptom.
    """

    MAX_CARDS = 4

    def __init__(self, state, on_open_page=None, on_select_region=None, parent=None):
        super().__init__(parent)
        self.setStyleSheet(f"background: {theme.BG};")
        self._on_open_page = on_open_page
        self._on_select_region = on_select_region
        self._layout = QHBoxLayout(self)
        self._layout.setContentsMargins(16, 8, 16, 4)
        self._layout.setSpacing(9)
        # Cards are fixed-size and simply clip past the right edge on a narrow
        # window; without this the row's minimum is the sum of its cards and
        # would drag the window wider as alerts arrived.
        self.setMinimumWidth(120)
        self._band = (_NeedCard.CARD_HEIGHT
                      + self._layout.contentsMargins().top()
                      + self._layout.contentsMargins().bottom())
        self.setFixedHeight(self._band)
        self.refresh(state)

    def minimumSizeHint(self):
        """Small, regardless of how many cards are in the row.

        A widget with a layout reports the layout's total minimum as its own,
        so a row of fixed-width cards would otherwise make the WINDOW at least
        as wide as every live alert laid end to end — and the window would
        visibly grow the moment a fourth alert arrived. The cards simply clip.
        """
        hint = super().minimumSizeHint()
        hint.setWidth(120)
        return hint

    def _clear(self):
        while self._layout.count():
            item = self._layout.takeAt(0)
            w = item.widget()
            if w is not None:
                w.setParent(None)      # detach now, not when the loop catches up
                w.deleteLater()
            # (spacer items are dropped by takeAt alone)

    def _page(self, name):
        if self._on_open_page is not None:
            return lambda: self._on_open_page(name)
        return None

    def _needs(self, state):
        """(tag, text, severity, handler) for everything currently waiting.

        Read-only: this asks the state what is pending, it never advances or
        mutates anything.
        """
        out = []

        # Decisions and deadlines come from the engine-side lens shared by
        # the full Briefing queue.  The strip deliberately shows only the two
        # actionable priority bands; planned and optional work belongs in the
        # scrollable briefing rather than four tiny dashboard cards.
        from engine import decision_queue
        decisions = decision_queue.build_queue(state, include_optional=False)
        for item in decisions:
            if item.priority not in (decision_queue.PRIORITY_REQUIRED,
                                     decision_queue.PRIORITY_URGENT):
                continue
            if item.region_id is not None and self._on_select_region is not None:
                handler = (lambda rid=item.region_id: self._on_select_region(rid))
            else:
                handler = self._page(item.page)
            text = item.title
            if item.due_text:
                text += f" — {item.due_text}"
            out.append((item.tag, text,
                        "critical" if item.priority == decision_queue.PRIORITY_REQUIRED
                        else "warning",
                        handler))

        # Anything ui/explain.py flags that isn't already represented above.
        from ui import explain
        for severity, text in explain.alerts(state):
            if severity not in ("critical", "warning"):
                continue
            out.append(("Government", text, severity, self._page("Briefing")))

        order = {"critical": 0, "warning": 1}
        out.sort(key=lambda item: order.get(item[2], 2))
        return out

    def refresh(self, state):
        self._clear()
        for tag, text, severity, handler in self._needs(state)[:self.MAX_CARDS]:
            self._layout.addWidget(_NeedCard(tag, text, severity, handler))
        self._layout.addStretch(1)
        # The band is reserved whether or not anything is in it. An empty
        # queue shows nothing at all — no "no pressing alerts" sentence — but
        # it does NOT collapse, because collapsing is what made the dashboard
        # jump every time an alert appeared or cleared.
        self.setFixedHeight(self._band)



class GuidancePanel(QWidget):
    """One note from the guided opening (engine/onboarding.py), with a way to
    dismiss it and, where the note points somewhere, a way to go there.

    Advisory by construction: it renders next to the dashboard rather than
    over it, nothing behind it is disabled while it is up, and it disappears
    for good the moment it is dismissed. When there is no guidance pending it
    hides entirely — this is the one dashboard element allowed to collapse,
    because it belongs to the opening months and should leave no permanent
    furniture behind once the player is past them.
    """

    dismissed = Signal(str)
    go_to_page = Signal(str)
    go_to_region = Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setObjectName("GuidancePanel")
        self.setStyleSheet(
            f"QWidget#GuidancePanel {{ background: {theme.PANEL_BG}; "
            f"border: 1px solid {theme.PANEL_EDGE}; "
            f"border-left: 3px solid {theme.HIGHLIGHT}; border-radius: 8px; }}")
        outer = QVBoxLayout(self)
        outer.setContentsMargins(15, 10, 15, 11)
        outer.setSpacing(4)

        self._title = QLabel()
        self._title.setStyleSheet(
            f"color: {theme.HIGHLIGHT}; font-size: {theme.FONT_SIZE_PT}pt; "
            f"font-weight: 600;")
        self._title.setWordWrap(True)
        outer.addWidget(self._title)

        self._body = QLabel()
        self._body.setWordWrap(True)
        self._body.setTextFormat(Qt.PlainText)
        self._body.setStyleSheet(
            f"color: {theme.INK_DIM}; font-size: {theme.FONT_SIZE_SM}pt;")
        outer.addWidget(self._body)

        row = QHBoxLayout()
        row.setContentsMargins(0, 4, 0, 0)
        row.setSpacing(8)
        self._go = QPushButton("Show me")
        self._go.clicked.connect(self._on_go)
        self._dismiss = QPushButton("Got it")
        self._dismiss.clicked.connect(self._on_dismiss)
        row.addWidget(self._go)
        row.addWidget(self._dismiss)
        row.addStretch(1)
        outer.addLayout(row)

        self._entry = None
        self.hide()

    def set_entry(self, entry):
        """`entry` is an authored dict from content/onboarding.py, or None."""
        self._entry = entry
        if entry is None:
            self.hide()
            return
        self._title.setText(entry["title"])
        self._body.setText(entry["body"])
        self._go.setVisible(bool(entry.get("page") or entry.get("region")))
        self.show()

    def _on_go(self):
        if self._entry is None:
            return
        if self._entry.get("page"):
            self.go_to_page.emit(self._entry["page"])
        elif self._entry.get("region"):
            self.go_to_region.emit(self._entry["region"])

    def _on_dismiss(self):
        if self._entry is not None:
            self.dismissed.emit(self._entry["id"])


class ScrollColumn(QScrollArea):
    """A vertical scroll area with a column layout you add widgets to via
    .body layout. Keeps long pages usable in a fixed dialog."""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWidgetResizable(True)
        self.setFrameShape(QFrame.NoFrame)
        # An explicit minimum overrides minimumSizeHint, which would
        # otherwise inherit the widest child inside and force the window
        # (and everything docked next to it) wider. Content that genuinely
        # doesn't fit scrolls instead.
        self.setMinimumWidth(220)
        # Vertically only. A page is allowed to be long; it is never allowed
        # to be wide — sideways-scrolling a settings panel is not a real
        # affordance, and it is how the Policies page ended up with half its
        # figures past the right edge.
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        inner = QWidget()
        self.body = QVBoxLayout(inner)
        self.body.setContentsMargins(4, 4, 4, 4)
        self.body.setSpacing(4)
        self.setWidget(inner)


class PagePanel(QWidget):
    """
    Base for the system pages (Policies, Cabinet, Parties, Diplomacy,
    Briefing). A titled panel with a scrollable body; subclasses fill
    self.content (a ScrollColumn) and implement refresh().

    A plain QWidget, not a dialog: these live permanently inside the docked
    tab panel (ui/dock.py) alongside the dashboard, so the map and stat
    panels stay visible and keep updating while a page is in use.

    Actions inside a page call back into the owning window to run an op
    and then refresh both the page and the main dashboard — that wiring
    is passed in as on_action so pages don't reach into the window.
    """

    # Emitted when has_uncommitted_input() may have changed, so the window
    # can re-evaluate whether End Turn should be available.
    uncommitted_changed = Signal()

    def __init__(self, title: str, state, on_action=None, parent=None):
        super().__init__(parent)
        self.state = state
        self.on_action = on_action  # callable(op_callable) -> ActionResult
        self.title = title
        self.setWindowTitle(title)
        self.setStyleSheet(theme.stylesheet())

        root = QVBoxLayout(self)
        root.setContentsMargins(12, 10, 12, 10)
        root.setSpacing(8)

        # No title label here: the desk's own header names the current page
        # (ui/dock.py), and when these were modal dialogs it was the window
        # title's job. Rendering it again inside the page just printed the
        # word twice, one line below itself.
        self.content = ScrollColumn()
        root.addWidget(self.content, stretch=1)

    def set_state(self, state):
        """Point the page at the current GameState and redraw.

        Pages outlive a turn now, so they can't assume the state object they
        were constructed with is still the live one — loading a campaign
        replaces it outright.
        """
        self.state = state
        self.refresh()

    def clear_content(self):
        while self.content.body.count():
            item = self.content.body.takeAt(0)
            w = item.widget()
            if w is not None:
                # Detach immediately: these panels are long-lived and refresh
                # on every action, so deferring removal to the event loop
                # would pile up stale widgets in the tree.
                w.setParent(None)
                w.deleteLater()

    def run_action(self, op_callable):
        """Run an op via the owning window (which handles refresh + dispatch),
        then refresh this page so it reflects the new state."""
        if self.on_action is not None:
            result = self.on_action(op_callable)
            self.refresh()
            return result
        # Pages are also useful as standalone widgets in tests and tooling.
        # In that case there is no MainWindow callback to execute the shared
        # operation, so run it against the page's current state directly.
        result = op_callable(self.state)
        self.refresh()
        return result

    def has_uncommitted_input(self) -> bool:
        """True while the page holds partial input the player hasn't
        committed yet (a drawn shortlist, a half-built proposal).

        The pages were modal before they moved into the dock, and that
        modality was quietly preventing a turn from being advanced mid-
        interaction. Non-modal, that guard has to be explicit — a page that
        says True here blocks End Turn until the player finishes or the page
        rebuilds. Most pages hold nothing, so the default is False.
        """
        return False

    def refresh(self):
        raise NotImplementedError


# The pages were modal dialogs before they moved into the dock; the old name
# is kept so nothing outside ui/ has to care.
PageDialog = PagePanel
