"""
The political desk: the six government-systems pages (Policies, Cabinet,
Parties, Diplomacy, Briefing, History) in a single-page overlay panel.

Two earlier shapes are worth remembering, because this one is a reaction to
both. They began as modal dialogs, which hid the map and froze the dashboard.
They then became a tabbed QDockWidget, which fixed the freezing but introduced
two problems of its own: a *second* navigation system competing with the menu
bar (whose tab labels elided to "Polic… Cabi… Part…"), and — because a dock is
part of the layout — opening one COMPRESSED the dashboard, crushing the right
column and starving the map.

So: one navigation system (the window's nav bar picks the page), and the desk
sits *above* the dashboard as a fixed-width overlay with a scrim, so opening
and closing it never reflows a single column behind it.

The pages themselves are unchanged (ui/pages.py) — this is the container. It
still owns pushing the live GameState into them and refreshing only the
visible one; a hidden page is marked stale and caught up when it is shown.
"""

from PySide6.QtWidgets import (QWidget, QStackedWidget, QVBoxLayout,
                               QHBoxLayout, QLabel, QPushButton,
                               QGraphicsDropShadowEffect)
from PySide6.QtCore import Qt, Signal, QPropertyAnimation, QEasingCurve, QPoint
from PySide6.QtGui import QColor

from ui import theme
from ui.pages import (PoliciesPage, CabinetPage, PartiesPage,
                      DiplomacyPage, BriefingPage, HistoryPage)

DEFAULT_WIDTH = 428
MIN_WIDTH = 380      # below this the pages start clipping their content
SLIDE_MS = 190


class _Scrim(QWidget):
    """The dim over the dashboard behind the desk. Clicking it closes."""

    clicked = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAttribute(Qt.WA_StyledBackground, True)
        self.setStyleSheet("background: rgba(4, 8, 14, 158);")
        self.hide()

    def mousePressEvent(self, event):
        self.clicked.emit()


class SystemDock(QWidget):
    """Single-page overlay home for the six system pages.

    Kept the old class name and public surface (TABS, refresh, select_tab,
    current_page_name, has_uncommitted_input, set_selected_country, the two
    signals) so ui/app.py and the UI smoke test did not have to be rewritten
    around a container change.
    """

    # Emitted whenever the desk opens or closes, so the window can react.
    visibility_changed = Signal(bool)
    # Emitted when some page's uncommitted-input state may have changed —
    # the window uses it to guard the clock.
    uncommitted_changed = Signal()

    # No longer tab labels — just the page order the nav bar walks.
    TABS = ("Policies", "Cabinet", "Parties", "Diplomacy", "Briefing", "History")

    def __init__(self, state, on_action=None, parent=None):
        super().__init__(parent)
        self.setObjectName("SystemDock")
        self.setAutoFillBackground(True)
        self.setAttribute(Qt.WA_StyledBackground, True)
        self.setStyleSheet(
            theme.stylesheet()
            + f"\nQWidget#SystemDock {{ background: {theme.PANEL_BG}; "
              f"border-left: 1px solid {theme.PANEL_EDGE}; }}")
        self.setMinimumWidth(MIN_WIDTH)

        # The scrim is a sibling, not a child: it has to cover the dashboard
        # while the desk sits on top of it.
        self._scrim = _Scrim(parent)
        self._scrim.clicked.connect(self.close_desk)

        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        header = QWidget()
        header.setObjectName("DeskHeader")
        header.setStyleSheet(
            f"QWidget#DeskHeader {{ background: {theme.PANEL_BG}; "
            f"border-bottom: 1px solid {theme.PANEL_EDGE}; }}")
        head = QHBoxLayout(header)
        head.setContentsMargins(14, 12, 14, 12)
        head.setSpacing(10)

        self._back = QPushButton("←")
        self._back.setFixedSize(28, 28)
        self._back.setToolTip("Close the desk (Esc)")
        self._back.setStyleSheet(
            f"QPushButton {{ background: transparent; border: none; "
            f"color: {theme.INK_DIM}; font-size: {theme.FONT_SIZE_LG}pt; }}"
            f"QPushButton:hover {{ color: {theme.INK}; }}")
        self._back.clicked.connect(self.close_desk)

        self._title = QLabel("")
        self._title.setStyleSheet(
            f"background: transparent; color: {theme.ACCENT}; "
            f"font-size: {theme.FONT_SIZE_LG}pt; font-weight: 600; "
            f"letter-spacing: 2px;")

        head.addWidget(self._back)
        head.addWidget(self._title, stretch=1)
        root.addWidget(header)

        self.pages = {
            "Policies": PoliciesPage(state, on_action=on_action),
            "Cabinet": CabinetPage(state, on_action=on_action),
            "Parties": PartiesPage(state, on_action=on_action),
            "Diplomacy": DiplomacyPage(state, on_action=on_action),
            "Briefing": BriefingPage(state, on_action=on_action),
            "History": HistoryPage(state, on_action=on_action),
        }
        self._stack = QStackedWidget()
        self._order = list(self.TABS)
        for name in self._order:
            page = self.pages[name]
            self._stack.addWidget(page)
            page.uncommitted_changed.connect(self.uncommitted_changed)
        # Only the visible page is redrawn on refresh (see refresh()), so a
        # page that was hidden while the world moved gets caught up here.
        self._stack.currentChanged.connect(self._on_page_changed)
        root.addWidget(self._stack, stretch=1)

        shadow = QGraphicsDropShadowEffect(self)
        shadow.setBlurRadius(44)
        shadow.setXOffset(-14)
        shadow.setYOffset(0)
        shadow.setColor(QColor(0, 0, 0, 150))
        self.setGraphicsEffect(shadow)

        self._state = state
        self._stale = set()
        self._anim = QPropertyAnimation(self, b"pos", self)
        self._anim.setDuration(SLIDE_MS)
        self._anim.setEasingCurve(QEasingCurve.OutCubic)
        self._sync_title()
        self.hide()

    # ── State plumbing ───────────────────────────────────────────────────

    def refresh(self, state):
        """Push the live state into every page, redrawing the visible one.

        Hidden pages are marked stale rather than redrawn: rebuilding six
        scrollable pages on every action is wasted work, and a hidden page
        has nothing on screen to be wrong. _on_page_changed catches them up
        the moment they're shown.
        """
        self._state = state
        for page in self.pages.values():
            page.state = state
        self._stale = set(self.pages)
        current = self.current_page_name()
        if current:
            self.pages[current].refresh()
            self._stale.discard(current)

    def _on_page_changed(self, _index):
        name = self.current_page_name()
        if name and name in self._stale:
            self.pages[name].state = self._state
            self.pages[name].refresh()
            self._stale.discard(name)
        self._sync_title()

    def _sync_title(self):
        name = self.current_page_name()
        self._title.setText((name or "").upper())

    def has_uncommitted_input(self) -> bool:
        """True if any page is holding a decision the player started but
        hasn't finished. Only meaningful while the desk is open."""
        if not self.isVisible():
            return False
        return any(p.has_uncommitted_input() for p in self.pages.values())

    def current_page_name(self):
        widget = self._stack.currentWidget()
        for name, page in self.pages.items():
            if page is widget:
                return name
        return None

    def select_tab(self, name: str):
        if name not in self.pages:
            return
        self._stack.setCurrentWidget(self.pages[name])
        self._sync_title()

    # ── Map ↔ Diplomacy page ─────────────────────────────────────────────

    def set_selected_country(self, country_id: str):
        """Keep the Diplomacy page pointed at whatever the map selected, so
        the two routes to the same verbs never disagree."""
        page = self.pages.get("Diplomacy")
        if page is not None and hasattr(page, "select_country"):
            page.select_country(country_id)

    # ── Open/close ───────────────────────────────────────────────────────

    def _target_geometry(self):
        """Fixed comfortable width, pinned to the right of the host widget."""
        host = self.parentWidget()
        if host is None:
            return 0, 0, DEFAULT_WIDTH, self.height()
        width = max(MIN_WIDTH, min(DEFAULT_WIDTH, host.width()))
        return host.width() - width, 0, width, host.height()

    def reposition(self):
        """Re-pin desk and scrim after the host resizes.

        A resize mid-slide would otherwise leave the animation driving toward
        an x computed from the OLD window width, landing the desk off the
        right edge. A resize is a deliberate, infrequent act, so the animation
        is abandoned and the desk snaps to where it was going.
        """
        host = self.parentWidget()
        if host is None:
            return
        self._scrim.setGeometry(0, 0, host.width(), host.height())
        x, y, w, h = self._target_geometry()
        if self.isVisible():
            self._anim.stop()
            self.setGeometry(x, y, w, h)
        else:
            self.resize(w, h)

    def open_desk(self):
        """Slide in over the dashboard. The layout behind does not move."""
        host = self.parentWidget()
        if host is None:
            self.show()
            return
        x, y, w, h = self._target_geometry()
        self._scrim.setGeometry(0, 0, host.width(), host.height())
        self._scrim.show()
        self._scrim.raise_()
        self.setGeometry(x, y, w, h)
        already_open = self.isVisible()
        self.show()
        self.raise_()
        if not already_open:
            self._anim.stop()
            self._anim.setStartValue(QPoint(host.width(), y))
            self._anim.setEndValue(QPoint(x, y))
            self._anim.start()

    def close_desk(self):
        """Close from a UI affordance (back arrow, scrim, Esc, toggle)."""
        self.hide()

    def show(self):
        # Any route that shows the desk must also put the scrim up, or the
        # dashboard behind stays fully lit and clickable.
        host = self.parentWidget()
        if host is not None:
            self._scrim.setGeometry(0, 0, host.width(), host.height())
            self._scrim.show()
            self._scrim.raise_()
        super().show()
        self.raise_()

    def hide(self):
        self._anim.stop()
        self._scrim.hide()
        super().hide()

    def showEvent(self, event):
        super().showEvent(event)
        self.visibility_changed.emit(True)

    def hideEvent(self, event):
        super().hideEvent(event)
        self.visibility_changed.emit(False)
