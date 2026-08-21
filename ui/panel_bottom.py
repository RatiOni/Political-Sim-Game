"""
Bottom region: the assembly strip (one line — seat count, a stacked party bar
with a majority marker, and a route to the detail) and the dispatch feed.

The permanent seat-arc hemicycle used to live here, taking a large block of
the dashboard to answer a question — "do I still have a majority?" — that is
one number. The arc itself is not gone: it moved to the Parties desk page,
where someone asking for seat detail can actually read it.
"""

from PySide6.QtWidgets import QWidget, QHBoxLayout, QVBoxLayout, QLabel
from PySide6.QtCore import Qt, Signal

from ui import theme


class _SeatBar(QWidget):
    """A thin stacked bar of party seat shares with a majority marker."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFixedHeight(15)
        self._segments = []       # (fraction, colour)
        self._majority_frac = 0.0
        self.setMinimumWidth(120)

    def set_data(self, segments, majority_frac):
        self._segments = list(segments)
        self._majority_frac = max(0.0, min(1.0, majority_frac))
        self.update()

    def paintEvent(self, event):
        from PySide6.QtGui import QPainter, QColor, QPen
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        w, h = self.width(), self.height()
        painter.setPen(Qt.NoPen)
        painter.setBrush(QColor(theme.BG))
        painter.drawRoundedRect(0, 0, w, h, 3, 3)

        x = 0.0
        for fraction, color in self._segments:
            seg_w = fraction * w
            painter.setBrush(QColor(color))
            painter.drawRect(int(round(x)), 0, int(round(seg_w)) + 1, h)
            x += seg_w

        # The majority line, drawn last so it is never buried under a segment.
        mx = int(round(self._majority_frac * w))
        painter.setPen(QPen(QColor(theme.INK), 2))
        painter.drawLine(mx, -2, mx, h + 2)
        painter.end()


class FactionStrip(QWidget):
    """The assembly, in one line: seats against the threshold, the chamber as
    a stacked bar, and a link into the Parties desk page for the full arc."""

    seat_detail_requested = Signal()

    def __init__(self, state, parent=None):
        super().__init__(parent)
        self.setObjectName("FactionStrip")
        self.setStyleSheet(
            f"QWidget#FactionStrip {{ background: {theme.PANEL_BG}; "
            f"border: 1px solid {theme.PANEL_EDGE}; border-radius: 8px; }}")
        self.setFixedHeight(48)
        self.setMinimumWidth(320)

        row = QHBoxLayout(self)
        row.setContentsMargins(15, 0, 15, 0)
        row.setSpacing(14)

        self._summary = QLabel()
        self._summary.setStyleSheet(f"color: {theme.INK_DIM};")
        self._bar = _SeatBar()

        self._link = QLabel("Seat detail  →")
        self._link.setCursor(Qt.PointingHandCursor)
        self._link.setStyleSheet(
            f"color: {theme.ACCENT}; font-size: {theme.FONT_SIZE_SM}pt;")
        self._link.mousePressEvent = lambda _e: self.seat_detail_requested.emit()

        row.addWidget(self._summary)
        row.addWidget(self._bar, stretch=1)
        row.addWidget(self._link)

        self.refresh(state)

    def refresh(self, state):
        leg = state.legislature
        colors = theme.assign_party_colors(state.country.factions)
        majority = leg.majority_threshold()
        total = leg.total_seats or 1

        coalition_seats = leg.coalition_seats(state.coalition_faction_ids())
        ok = coalition_seats >= majority
        self._summary.setText(
            f"{coalition_seats} / {majority} needed  ·  "
            f"{'majority' if ok else 'MINORITY'}")
        self._summary.setStyleSheet(
            f"color: {theme.GOOD if ok else theme.CRITICAL};")

        # Coalition first, then the rest by size — the bar reads left-to-right
        # as "the government, then everyone else", which is what the majority
        # marker is measuring against.
        coalition = sorted([f for f in state.country.factions if f.in_coalition],
                           key=lambda f: -f.seats)
        others = sorted([f for f in state.country.factions if not f.in_coalition],
                        key=lambda f: -f.seats)
        segments = [(f.seats / total, colors.get(f.id, theme.NEUTRAL))
                    for f in coalition + others if f.seats > 0]
        self._bar.set_data(segments, majority / total)
        self._bar.setToolTip("\n".join(
            [f"{leg.total_seats} seats · majority {majority}",
             f"Government: {coalition_seats} "
             f"({'majority' if ok else 'MINORITY'})"]
            + [f"  {f.name}: {f.seats}" for f in coalition + others]))


class _DispatchLine(QLabel):
    """One dispatch, wrapped, in a row of fixed height.

    Fixed height matters: a wrapping label is as tall as its text needs, so a
    feed of them changed height every turn as the dispatches changed length,
    and everything above it moved. Two text rows is plenty at full dashboard
    width; anything longer clips and the tooltip carries the rest.
    """

    clicked = Signal(str)
    def __init__(self, rows=2, parent=None):
        super().__init__(parent)
        self._rows = max(1, int(rows))
        self.setWordWrap(True)
        self.setTextFormat(Qt.PlainText)
        self.setCursor(Qt.PointingHandCursor)
        self.setAlignment(Qt.AlignLeft | Qt.AlignTop)
        # Word wrap alone would let a long dispatch report a wide size hint;
        # an explicit small minimum keeps the feed from widening the window.
        self.setMinimumWidth(160)
        self.setFixedHeight(self.fontMetrics().lineSpacing() * self._rows + 10)
        self._text = ""
        self._apply(hover=False)

    def set_text(self, text: str, dim: bool = False):
        self._text = text
        self._dim = dim
        self.setText(text)
        self.setToolTip(text)
        self._apply(hover=False)

    def _apply(self, hover: bool):
        color = theme.INK if hover else (
            theme.INK_FAINT if getattr(self, "_dim", False) else theme.INK_DIM)
        self.setStyleSheet(
            f"color: {color}; font-size: {theme.FONT_SIZE_SM}pt; "
            f"padding: 5px 0; border-bottom: 1px solid {theme.ROW_LINE};")

    def enterEvent(self, event):
        self._apply(hover=True)
        super().enterEvent(event)

    def leaveEvent(self, event):
        self._apply(hover=False)
        super().leaveEvent(event)

    def mousePressEvent(self, event):
        if self._text:
            self.clicked.emit(self._text)


class EventLog(QWidget):
    """
    The dispatch feed, full width along the bottom of the dashboard.

    It was a fixed-height QListWidget, which clipped every dispatch
    mid-sentence — the prose is most of the game's voice, so a feed that cuts
    it off at the column edge throws away the thing it exists to show. Now
    each entry is a wrapped label and the newest four are shown complete.
    Clicking one still emits dispatch_clicked, which the window turns into a
    detail dialog explaining WHY it happened.
    """
    dispatch_clicked = Signal(str)

    MAX_LINES = 4

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setObjectName("EventLog")
        self.setStyleSheet(
            f"QWidget#EventLog {{ background: {theme.PANEL_BG}; "
            f"border: 1px solid {theme.PANEL_EDGE}; border-radius: 8px; }}")
        layout = QVBoxLayout(self)
        layout.setContentsMargins(15, 10, 15, 11)
        layout.setSpacing(0)

        title = QLabel("DISPATCHES")
        title.setStyleSheet(
            f"color: {theme.INK_FAINT}; font-size: {theme.FONT_SIZE_SM}pt; "
            f"letter-spacing: 1.6px; font-weight: 600;")
        layout.addWidget(title)
        layout.addSpacing(4)

        self._lines = []
        for _ in range(self.MAX_LINES):
            line = _DispatchLine()
            line.clicked.connect(self.dispatch_clicked)
            self._lines.append(line)
            layout.addWidget(line)

        self._title_height = title.sizeHint().height()
        self._layout_margins_height = (
            layout.contentsMargins().top() + layout.contentsMargins().bottom())

    def _fit_to_rows(self, count: int):
        """Reserve only rows that can actually be read.

        The previous maximum-height reservation consumed 189 px even when
        three of four rows were blank. At 1080p that blank space competed
        directly with the map and headline statistics.
        """
        count = max(1, min(self.MAX_LINES, count))
        for index, line in enumerate(self._lines):
            line.setVisible(index < count)
        self.setFixedHeight(
            self._title_height + 4
            + count * self._lines[0].height()
            + self._layout_margins_height)

    def set_dispatches(self, dispatches, state=None):
        """Populate the feed from a list of dispatch strings, newest last."""
        entries = list(dispatches)[-self.MAX_LINES:]
        if not entries:
            entries = ["A quiet month so far. Nothing of note."]
            self._lines[0].set_text(entries[0], dim=True)
        else:
            for line, entry in zip(self._lines, entries):
                line.set_text(entry)
        for line in self._lines[len(entries):]:
            line.set_text("")
        self._fit_to_rows(len(entries))

    # Backwards-compatible helpers (used by any older call sites / tests).
    def show_turn(self, state):
        self.set_dispatches(list(state.turn_log), state)

    def show_message(self, text):
        self.set_dispatches([text])


class DigestPanel(QWidget):
    """
    "This month": the government's own account of what moved and why
    (engine/digest.py), sitting above the dispatch feed.

    Deliberately a separate card, not a section inside EventLog — one is the
    world talking about itself (the press), the other is the state
    explaining its own numbers, and they should never be visually confused.
    The accent-coloured left edge is the one thing marking that difference.

    A month with no digest does not render an empty five-row card. Digest
    entries are compact one-line explanations: at dashboard width the full
    sentence normally fits, and the tooltip preserves any text elided by a
    narrower window.
    """

    MAX_LINES = 5

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setObjectName("DigestPanel")
        self.setStyleSheet(
            f"QWidget#DigestPanel {{ background: {theme.PANEL_BG}; "
            f"border: 1px solid {theme.PANEL_EDGE}; "
            f"border-left: 3px solid {theme.ACCENT}; border-radius: 8px; }}")
        layout = QVBoxLayout(self)
        layout.setContentsMargins(15, 10, 15, 11)
        layout.setSpacing(0)

        title = QLabel("THIS MONTH")
        title.setStyleSheet(
            f"color: {theme.ACCENT}; font-size: {theme.FONT_SIZE_SM}pt; "
            f"letter-spacing: 1.6px; font-weight: 600;")
        layout.addWidget(title)
        layout.addSpacing(4)

        self._lines = []
        for _ in range(self.MAX_LINES):
            line = _DispatchLine(rows=1)
            line.setCursor(Qt.ArrowCursor)  # not clickable, unlike dispatches
            self._lines.append(line)
            layout.addWidget(line)

        self._title_height = title.sizeHint().height()
        self._layout_margins_height = (
            layout.contentsMargins().top() + layout.contentsMargins().bottom())
        self.set_digest([])

    def _fit_to_rows(self, count: int):
        count = max(0, min(self.MAX_LINES, count))
        for index, line in enumerate(self._lines):
            line.setVisible(index < count)
        if count == 0:
            self.hide()
            return
        self.setFixedHeight(
            self._title_height + 4
            + count * self._lines[0].height()
            + self._layout_margins_height)
        self.show()

    def set_digest(self, lines):
        """`lines`: the strings monthly_digest() returned (already capped at
        five). A quiet month has no empty card competing with the map."""
        entries = list(lines)[:self.MAX_LINES]
        for line, entry in zip(self._lines, entries):
            line.set_text(entry)
        for line in self._lines[len(entries):]:
            line.set_text("")
        self._fit_to_rows(len(entries))
