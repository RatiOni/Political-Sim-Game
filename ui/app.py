"""
The main window: owns the single GameState + TurnEngine, advances time,
refreshes every panel, and runs every player action through _run_op (one
place where an op becomes a state change + dispatch + repaint). Panels and
pages never reach into each other — they call back here.
"""

from PySide6.QtWidgets import (QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
                               QLabel, QPushButton)
from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QShortcut, QKeySequence

from ui import theme
from ui.panel_left import LeftPanel
from ui.panel_right import RightPanel
from ui.panel_bottom import FactionStrip, EventLog, DigestPanel
from ui.widgets_ardenia_map import ArdeniaMapWidget
from ui.widgets_common import AlertStrip, Toast, ElidedLabel, GuidancePanel
from ui.dock import SystemDock
from ui.dialogs import (TurnSummaryDialog, DispatchDetailDialog,
                        MetricBreakdownDialog, EventDialog, ElectionResultsDialog,
                        snapshot_metrics)

from main import build_sample_game
from engine.turn import TurnEngine


class MainWindow(QMainWindow):
    def __init__(self, state=None, on_exit_to_menu=None):
        super().__init__()
        # State can be injected (from the campaign wizard or a loaded save);
        # falling back to build_sample_game keeps the old direct-launch path
        # working for anything that still constructs MainWindow() bare.
        self.state = state if state is not None else build_sample_game()
        self.engine = TurnEngine()
        self._on_exit_to_menu = on_exit_to_menu
        self._clock_speed = 0
        self._last_clock_speed = 1
        self._clock_timer = QTimer(self)
        self._clock_timer.setTimerType(Qt.PreciseTimer)
        self._clock_timer.timeout.connect(self._on_clock_tick)

        # Dispatch feed for the current turn (player action results plus
        # this turn's simulation log). Reset at the start of each turn.
        # Seeded from the state's existing log so a brand-new campaign opens
        # on its briefing (engine/campaign.py: _opening_briefing) rather than
        # on an empty panel.
        self._dispatches = list(self.state.turn_log)

        self.setWindowTitle(f"{self.state.country.name} — a political simulation")
        # Designed around a 16:9 desktop while remaining usable when the
        # systems dock opens beside it.
        self.resize(1440, 860)

        self._build_menu()
        self._build_central()
        self._refresh_all()

    # ── Construction ─────────────────────────────────────────────────────────

    def _build_menu(self):
        # The six system pages are reached from the nav bar (_build_nav) — the
        # ONE navigation system. This menu is for app-level commands only; it
        # used to also carry a "Show X" submenu per page, which competed with
        # the dock's own tab bar for the same six destinations.
        bar = self.menuBar()

        game_menu = bar.addMenu("Game")
        act_end = game_menu.addAction("Pause / Resume Time")
        act_end.setShortcut("Space")
        act_end.triggered.connect(self.toggle_clock)
        act_day = game_menu.addAction("Advance One Day")
        act_day.setShortcut(".")
        act_day.triggered.connect(self._advance_one_day)
        game_menu.addSeparator()
        act_save = game_menu.addAction("Save Campaign")
        act_save.setShortcut("Ctrl+S")
        act_save.triggered.connect(self._save_campaign)
        act_load = game_menu.addAction("Load Campaign")
        act_load.triggered.connect(self._load_campaign)
        game_menu.addSeparator()
        act_situation = game_menu.addAction("Respond to Situation…")
        act_situation.triggered.connect(self._open_event_dialog)
        act_election = game_menu.addAction("Last Election Results…")
        act_election.triggered.connect(self._open_election_results)
        game_menu.addSeparator()
        if self._on_exit_to_menu is not None:
            act_menu = game_menu.addAction("Main Menu")
            act_menu.triggered.connect(self._on_exit_to_menu)
        act_quit = game_menu.addAction("Quit")
        act_quit.triggered.connect(self.close)

        self._act_end_turn = act_end

        # Esc closes the desk. Window-scoped, so it doesn't fight the modal
        # dialogs (which consume Esc themselves).
        self._esc = QShortcut(QKeySequence(Qt.Key_Escape), self)
        self._esc.activated.connect(self._close_desk_if_open)

    def _build_header(self):
        """Country · who · date, with the clock at the right end.

        The Play button and the speed pips are the most-used control in a
        real-time-with-pause game; they were bottom-right, below the fold and
        partly occluded. They belong beside the date.
        """
        header = QWidget()
        header.setObjectName("TopBar")
        header.setStyleSheet(
            f"QWidget#TopBar {{ background: {theme.PANEL_BG}; "
            f"border-bottom: 1px solid {theme.PANEL_EDGE}; }}")
        row = QHBoxLayout(header)
        row.setContentsMargins(18, 9, 14, 9)
        row.setSpacing(14)

        # Elided: this line changes every turn (name, title, date), and a
        # plain QLabel would report its full text width as the window's
        # minimum — the window then grows on its own as the text changes.
        self._top_bar = ElidedLabel()
        self._top_bar.setStyleSheet(
            f"color: {theme.INK}; font-size: {theme.FONT_SIZE_LG}pt; "
            f"font-weight: 600;")
        row.addWidget(self._top_bar, stretch=1)

        self._end_turn_btn = QPushButton("▶  Play")
        self._end_turn_btn.setFixedHeight(30)
        self._end_turn_btn.setStyleSheet(
            f"QPushButton {{ background: {theme.ACCENT}; color: {theme.BG}; "
            f"border: 1px solid {theme.ACCENT}; border-radius: 5px; "
            f"font-weight: 600; padding: 5px 16px; }} "
            f"QPushButton:hover {{ background: {theme.INK}; border-color: {theme.INK}; }} "
            f"QPushButton:disabled {{ background: {theme.PANEL_RAISED}; color: {theme.INK_FAINT}; "
            f"border-color: {theme.PANEL_EDGE}; }}")
        self._end_turn_btn.clicked.connect(self.toggle_clock)
        row.addWidget(self._end_turn_btn)

        self._speed_buttons = {}
        for speed in range(1, 6):
            btn = QPushButton(str(speed))
            btn.setFixedSize(27, 30)
            btn.setCheckable(True)
            btn.setStyleSheet(
                f"QPushButton {{ padding: 0; font-size: {theme.FONT_SIZE_SM}pt; }}"
                f"QPushButton:checked {{ background: {theme.ACCENT_SOFT}; "
                f"color: {theme.INK}; border-color: {theme.ACCENT}; }}")
            btn.setToolTip(f"Run at speed {speed}")
            btn.clicked.connect(lambda _checked=False, value=speed:
                                self._set_clock_speed(value))
            self._speed_buttons[speed] = btn
            row.addWidget(btn)
        return header

    def _build_nav(self):
        """The one navigation system: six destinations, one row, real labels.

        Previously the same six pages were reachable from both a per-page menu
        on the menu bar and the dock's own tab bar, whose labels elided to
        "Polic… Cabi… Part…".
        """
        nav = QWidget()
        nav.setObjectName("NavBar")
        nav.setStyleSheet(
            f"QWidget#NavBar {{ background: {theme.BG}; "
            f"border-bottom: 1px solid {theme.PANEL_EDGE}; }}")
        row = QHBoxLayout(nav)
        row.setContentsMargins(16, 0, 16, 0)
        row.setSpacing(2)

        self._nav_buttons = {}
        for name in SystemDock.TABS:
            btn = QPushButton(name)
            btn.setFlat(True)
            btn.setCursor(Qt.PointingHandCursor)
            btn.clicked.connect(lambda _checked=False, n=name: self._toggle_page(n))
            self._nav_buttons[name] = btn
            row.addWidget(btn)
        row.addStretch(1)
        self._style_nav(None)
        return nav

    def _style_nav(self, active_name):
        for name, btn in getattr(self, "_nav_buttons", {}).items():
            on = (name == active_name)
            btn.setStyleSheet(
                f"QPushButton {{ background: transparent; border: none; "
                f"border-bottom: 2px solid "
                f"{theme.ACCENT if on else 'transparent'}; "
                f"color: {theme.INK if on else theme.INK_DIM}; "
                f"padding: 8px 14px; border-radius: 0; }}"
                f"QPushButton:hover {{ color: {theme.INK}; "
                f"background: {theme.PANEL_RAISED}; }}")

    def _build_central(self):
        central = QWidget()
        root = QVBoxLayout(central)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        root.addWidget(self._build_header())
        root.addWidget(self._build_nav())

        # What actually needs a decision, as clickable routes. Collapses to
        # nothing when there is genuinely nothing.
        self._alerts = AlertStrip(self.state,
                                  on_open_page=self._show_page,
                                  on_select_region=self._select_region)
        root.addWidget(self._alerts)

        dashboard = QWidget()
        dashboard.setStyleSheet(f"background: {theme.BG};")
        dash = QVBoxLayout(dashboard)
        dash.setContentsMargins(16, 12, 16, 10)
        dash.setSpacing(12)

        middle = QHBoxLayout()
        middle.setContentsMargins(0, 0, 0, 0)
        middle.setSpacing(12)

        self._left = LeftPanel(self.state)
        self._map = ArdeniaMapWidget(self.state)
        self._right = RightPanel(self.state, on_action=self._run_op,
                                 on_open_page=self._show_page)

        self._map.region_selected.connect(self._on_region_selected)
        if hasattr(self._left, "metric_clicked"):
            self._left.metric_clicked.connect(self._open_metric_breakdown)

        # One line, not a permanent chart: the arc lives on the Parties page.
        self._factions = FactionStrip(self.state)
        self._factions.seat_detail_requested.connect(
            lambda: self._show_page("Parties"))
        centre = QVBoxLayout()
        centre.setContentsMargins(0, 0, 0, 0)
        centre.setSpacing(10)
        centre.addWidget(self._map, stretch=1)
        centre.addWidget(self._factions)

        middle.addWidget(self._left)
        middle.addLayout(centre, stretch=1)
        middle.addWidget(self._right)
        dash.addLayout(middle, stretch=1)

        # The two narrative feeds share one bottom row. Stacking their maximum
        # contents consumed more than 350 logical pixels; on a 1080p Windows
        # display at 125% scaling that left less than the map's minimum height
        # and Qt overlapped the assembly strip across the map. Side by side,
        # they remain distinct without competing vertically with the actual
        # dashboard. When the digest is empty it hides and Dispatches receives
        # the whole width.
        # The guided opening (engine/onboarding.py): advisory, dismissible,
        # and absent entirely once the player is past it. Above the
        # narrative row so a note reads as addressed to the player rather
        # than as another feed.
        self._guidance = GuidancePanel()
        self._guidance.dismissed.connect(self._dismiss_guidance)
        self._guidance.go_to_page.connect(self._show_page)
        self._guidance.go_to_region.connect(self._select_region)
        dash.addWidget(self._guidance)

        self._digest = DigestPanel()
        self._log = EventLog()
        if hasattr(self._log, "dispatch_clicked"):
            self._log.dispatch_clicked.connect(self._open_dispatch_detail)
        self._log.set_dispatches(self._dispatches, self.state)
        narrative = QHBoxLayout()
        narrative.setContentsMargins(0, 0, 0, 0)
        narrative.setSpacing(12)
        narrative.addWidget(self._digest, stretch=2)
        narrative.addWidget(self._log, stretch=3)
        dash.addLayout(narrative)

        root.addWidget(dashboard, stretch=1)
        self.setCentralWidget(central)

        # The system pages: an overlay above the dashboard, NOT part of the
        # layout — opening it must not reflow a single column behind it.
        self._dock = SystemDock(self.state, on_action=self._run_op, parent=central)
        self._dock.visibility_changed.connect(self._on_dock_visibility)
        self._dock.uncommitted_changed.connect(self._update_end_turn_guard)
        self._dock.hide()          # starts closed; the dashboard comes first

        self._toggle_desk_shortcut = QShortcut(QKeySequence("Ctrl+G"), self)
        self._toggle_desk_shortcut.activated.connect(self._toggle_dock)

        # Floats above the layout; repositioned on resize.
        self._toast = Toast(central)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if getattr(self, "_dock", None) is not None:
            self._dock.reposition()
        if getattr(self, "_toast", None) is not None and self._toast.isVisible():
            self._toast.reposition()

    # ── Turn cycle ───────────────────────────────────────────────────────────

    _CLOCK_INTERVALS = {1: 1200, 2: 650, 3: 350, 4: 180, 5: 90}

    def _set_clock_speed(self, speed: int):
        speed = max(0, min(5, int(speed)))
        blocked = (getattr(self, "_dock", None) is not None
                   and self._dock.has_uncommitted_input())
        if speed and blocked:
            return
        self._clock_speed = speed
        if speed == 0:
            self._clock_timer.stop()
            if getattr(self, "_end_turn_btn", None) is not None:
                self._end_turn_btn.setText("▶  Play")
        else:
            self._last_clock_speed = speed
            self._clock_timer.start(self._CLOCK_INTERVALS[speed])
            if getattr(self, "_end_turn_btn", None) is not None:
                self._end_turn_btn.setText("⏸  Pause")
        for value, button in getattr(self, "_speed_buttons", {}).items():
            button.setChecked(value == speed)

    def toggle_clock(self):
        self._set_clock_speed(0 if self._clock_speed else self._last_clock_speed)

    def _on_clock_tick(self):
        self._advance_one_day()

    def _advance_one_day(self):
        """Advance one exact day and redraw heavy panels only at month-end."""
        if getattr(self, "_advancing", False):
            return
        if getattr(self, "_dock", None) is not None and self._dock.has_uncommitted_input():
            self._set_clock_speed(0)
            return
        self._advancing = True
        try:
            previous_government_bill = None
            if not self.state.player.in_government:
                from engine import domestic_ai
                bill = domestic_ai.current_government_bill(self.state)
                previous_government_bill = bill.id if bill is not None else None
            self.state = self.engine.advance_day(self.state)
            daily_activity = bool(self.state.turn_log)
            if not self.engine.last_advance_monthly and not daily_activity:
                self._top_bar.setText(self._top_bar_text())
                self._right.refresh(self.state)
                return

            self._refresh_all()
            self._dispatches = list(self.state.turn_log)
            self._log.set_dispatches(self._dispatches, self.state)
            if self.engine.last_advance_monthly:
                self._refresh_digest()

            from engine import player_ops
            current_bill = player_ops.government_bill(self.state)
            new_government_bill = (current_bill is not None
                                   and current_bill.id != previous_government_bill)
            election_now = (self.engine.last_advance_monthly
                            and bool(self.state.election_history)
                            and self.state.election_history[-1].turn == self.state.turn)
            situation_now = (self.engine.last_advance_monthly
                             and player_ops.current_pending_event(self.state) is not None)
            if election_now or situation_now or new_government_bill:
                self._set_clock_speed(0)
            if election_now:
                self._maybe_show_election_results()
            if situation_now:
                self._maybe_show_event_dialog()
            self._autosave()
        finally:
            self._advancing = False

    def advance_turn(self):
        # Belt-and-braces against a double advance: the End Turn control is
        # disabled while the dock is open, and re-entrancy is blocked here so
        # neither the button, the menu item, nor the Space shortcut can fire
        # a second turn while one is still resolving (the summary dialog
        # spins the event loop mid-advance).
        if getattr(self, "_advancing", False):
            return
        if getattr(self, "_dock", None) is not None and self._dock.has_uncommitted_input():
            return          # authoritative: not only the widgets are guarded
        self._advancing = True
        try:
            self._advance_turn_inner()
        finally:
            self._advancing = False

    def _advance_turn_inner(self):
        before = snapshot_metrics(self.state)

        self.state = self.engine.advance(self.state)

        after = snapshot_metrics(self.state)
        self._refresh_all()

        dlg = TurnSummaryDialog(self.state, before, after, parent=self)
        dlg.exec()

        # A new turn starts with a fresh dispatch feed seeded by the turn log.
        self._dispatches = list(self.state.turn_log)
        self._log.set_dispatches(self._dispatches, self.state)
        # advance() (unlike advance_day()) is always a monthly pulse.
        self._refresh_digest()

        # An election that resolved this turn gets its own results screen,
        # ahead of any situation dialog — it's the bigger moment.
        self._maybe_show_election_results()

        # A newly-fired situation gets the player's attention right away;
        # if they defer it ("Decide later"), Game → Respond to Situation
        # reopens it, and it stays pending until addressed or it lapses.
        self._maybe_show_event_dialog()

        self._autosave()

    def _dismiss_guidance(self, guidance_id: str):
        from engine import onboarding
        onboarding.dismiss(self.state, guidance_id)
        self._refresh_guidance()

    def _refresh_guidance(self):
        """Show the next pending note, or nothing. Read-only apart from
        the explicit dismissal above — guidance never changes the game."""
        from engine import onboarding
        self._guidance.set_entry(onboarding.next_guidance(self.state))

    def _refresh_digest(self):
        """Recompute "This month" after a monthly pulse. state.last_snapshot
        is the "before" the pulse itself captured (engine/turn.py:
        _run_monthly_pulse); an empty dict there — the very first month, or a
        save from before this feature existed — means nothing to compare
        against, so the panel is cleared rather than guessing."""
        from engine import digest as digest_engine
        if not self.state.last_snapshot:
            self._digest.set_digest([])
            return
        after = digest_engine.snapshot(self.state)
        lines = digest_engine.monthly_digest(self.state, self.state.last_snapshot, after)
        self._digest.set_digest(lines)

    def _autosave(self):
        """Best-effort monthly autosave; failures never interrupt play."""
        try:
            from engine import persistence
            persistence.save_campaign(self.state, slot="autosave")
        except Exception as e:
            self._dispatches.append(f"(autosave failed: {e})")
            self._log.set_dispatches(self._dispatches, self.state)

    def _save_campaign(self):
        from PySide6.QtWidgets import QInputDialog, QMessageBox
        from engine import persistence
        name, ok = QInputDialog.getText(self, "Save Campaign", "Save name:",
                                         text=f"{self.state.player.name}")
        if not ok or not name.strip():
            return
        try:
            persistence.save_campaign(self.state, slot=name.strip())
            QMessageBox.information(self, "Save Campaign", f"Saved as \"{name.strip()}\".")
        except Exception as e:
            QMessageBox.warning(self, "Save Failed", str(e))

    def _load_campaign(self):
        from PySide6.QtWidgets import QMessageBox
        from ui.menu import LoadDialog
        dlg = LoadDialog(parent=self)
        if dlg.exec() and dlg.selected_slot:
            from engine import persistence
            try:
                self.state = persistence.load_campaign(dlg.selected_slot)
                self.engine = TurnEngine()
                self._set_clock_speed(0)
                self._dispatches = []
                # A loaded save may be a different country than the one on screen.
                self.setWindowTitle(f"{self.state.country.name} — a political simulation")
                self._refresh_all()
                self._log.set_dispatches([f"Loaded campaign: {self.state.player.name}, "
                                          f"{self.state.date_string()}."], self.state)
                # A freshly loaded campaign should not reprint an old month's
                # digest; the next real pulse will populate it again.
                self._digest.set_digest([])
            except Exception as e:
                QMessageBox.warning(self, "Load Failed", str(e))

    def _run_op(self, op_callable):
        """Single path for a player action: run op, record dispatch, repaint,
        and acknowledge it on screen so an action never lands silently."""
        result = op_callable(self.state)
        if result is not None and result.message:
            self._dispatches.append(result.message)
            self._log.set_dispatches(self._dispatches, self.state)
            self._toast.show_message(result.message, success=bool(result.success))
        self._refresh_all()
        return result

    def _refresh_all(self):
        self._top_bar.setText(self._top_bar_text())
        self._refresh_guidance()
        self._alerts.refresh(self.state)
        self._left.refresh(self.state)
        self._right.refresh(self.state)
        self._factions.refresh(self.state)
        self._map.set_state(self.state)
        # The dock's pages outlive the turn, so they're handed the live state
        # here — this is what keeps an open tab correct while the world moves.
        if getattr(self, "_dock", None) is not None:
            self._dock.refresh(self.state)
            self._update_end_turn_guard()   # a rebuild drops partial input

    def _top_bar_text(self) -> str:
        s = self.state
        if s.player.in_government:
            who = f"{s.player.title} {s.player.name}"
        else:
            who = f"{s.player.name}, Opposition Leader"
        base = (f"{s.country.name.upper()}   ·   {who}   ·   "
                f"{s.date_string()}   ·   Day {s.day_index + 1}")
        if s.civil_war:
            base += "   ·   ⚠ CIVIL WAR"
        return base

    # ── Interaction ──────────────────────────────────────────────────────────

    def _on_region_selected(self, region_id: str):
        self._right.set_selected_region(region_id, self.state)

    def _on_country_selected(self, country_id: str):
        """Compatibility route for callers that focus a diplomatic partner.

        The dashboard map is national now, so normal foreign selection happens
        through the Diplomacy page rather than by clicking a continent map.
        """
        self._right.set_selected(country_id, self.state)
        # Keep the Diplomacy tab pointed at the same country as the map, so
        # the two routes to the same verbs never disagree.
        if getattr(self, "_dock", None) is not None:
            self._dock.set_selected_country(country_id)

    def _open_metric_breakdown(self, metric_name: str):
        MetricBreakdownDialog(metric_name, self.state, parent=self).exec()

    def _open_dispatch_detail(self, dispatch_text: str):
        DispatchDetailDialog(dispatch_text, self.state, parent=self).exec()

    def _maybe_show_event_dialog(self):
        """Auto-called after ending a turn; silently does nothing if no
        situation is pending."""
        from engine import player_ops, events
        pending = player_ops.current_pending_event(self.state)
        if pending is None:
            return
        event = events.event_by_id(pending.event_id)
        EventDialog(event, self._run_op, state=self.state, parent=self).exec()

    def _open_event_dialog(self):
        """Game menu 'Respond to Situation…' — same dialog, but tells the
        player if nothing is actually pending rather than doing nothing."""
        from engine import player_ops
        from PySide6.QtWidgets import QMessageBox
        if player_ops.current_pending_event(self.state) is None:
            QMessageBox.information(self, "No Situation Pending",
                                    "There is no situation awaiting your response right now.")
            return
        self._maybe_show_event_dialog()

    def _maybe_show_election_results(self):
        """Auto-called after ending a turn; shows the results screen only when
        an election actually resolved this turn."""
        history = self.state.election_history
        if history and history[-1].turn == self.state.turn:
            ElectionResultsDialog(history[-1], self.state, parent=self).exec()

    def _open_election_results(self):
        """Game menu 'Last Election Results…' — reopen the most recent one, or
        say so if the country hasn't been to the polls yet."""
        from PySide6.QtWidgets import QMessageBox
        if not self.state.election_history:
            QMessageBox.information(self, "No Elections Yet",
                                    "No election has been held in this campaign yet.")
            return
        ElectionResultsDialog(self.state.election_history[-1], self.state, parent=self).exec()

    # ── Menu pages ────────────────────────────────────────────────────────────

    # ── The system dock ──────────────────────────────────────────────────────

    def _show_page(self, name: str):
        """Open the desk on a page. Called by the nav bar, the needs cards,
        the assembly strip's seat link and the relations 'see all'."""
        self._dock.select_tab(name)
        self._open_dock()
        self._style_nav(name)

    def _toggle_page(self, name: str):
        """Nav-bar click: the same entry twice closes the desk again."""
        if self._dock.isVisible() and self._dock.current_page_name() == name:
            self._dock.close_desk()
            return
        self._show_page(name)

    def _select_region(self, region_id: str):
        """A needs card that points at a region selects it on the map."""
        self._map.set_selected(region_id)
        self._on_region_selected(region_id)

    def _open_dock(self):
        self._dock.open_desk()

    def _close_desk_if_open(self):
        if self._dock.isVisible():
            self._dock.close_desk()

    def _toggle_dock(self):
        if self._dock.isVisible():
            self._dock.close_desk()
        else:
            self._open_dock()

    def _on_dock_visibility(self, visible: bool):
        self._style_nav(self._dock.current_page_name() if visible else None)
        self._update_end_turn_guard()

    def _update_end_turn_guard(self):
        """End Turn is blocked while a page holds an unfinished decision.

        The pages used to be modal, and that modality was doing double duty:
        it blocked input, which also stopped a turn being advanced mid-
        interaction. Non-modal, the guard has to be explicit. It is scoped to
        *uncommitted input* rather than "dock is open" on purpose — being
        able to end a turn and watch the dashboard move with a tab open is
        the whole point of the dock.
        """
        blocked = self._dock is not None and self._dock.has_uncommitted_input()
        self._end_turn_btn.setEnabled(not blocked)
        for button in getattr(self, "_speed_buttons", {}).values():
            button.setEnabled(not blocked)
        self._act_end_turn.setEnabled(not blocked)   # menu item + Space shortcut
        self._end_turn_btn.setToolTip(
            "Finish or cancel the decision in the government panel first"
            if blocked else "")
