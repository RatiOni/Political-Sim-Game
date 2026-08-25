"""
Headless smoke test for the Qt interface — run this on YOUR machine.

    python ui_smoke_test.py

Tests that the *interface* constructs and runs against REAL PySide6,
using Qt's "offscreen" platform so no window actually opens. It won't
prove the layout looks right — only your eyes on the real window can do
that — but it catches construction errors, bad Qt API calls, broken
signal wiring, and crashes in the turn / action / page / dialog flows,
without you clicking through anything.

If this passes, `python gui.py` should open a working window.
"""

import os
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, os.path.dirname(__file__))

from PySide6.QtWidgets import QApplication, QLabel, QPushButton
from PySide6.QtCore import Qt, QUrl, QPoint, qInstallMessageHandler
from PySide6.QtGui import QFontDatabase
from PySide6.QtQuickWidgets import QQuickWidget
from PySide6.QtTest import QTest

from ui import theme
from ui.app import MainWindow
from engine import player_ops as ops
from version import VERSION


def main():
    app = QApplication(sys.argv)
    app.setStyleSheet(theme.stylesheet())

    checks = []
    def check(name, fn):
        try:
            fn()
            checks.append(("PASS", name))
        except Exception as e:
            import traceback
            traceback.print_exc()
            checks.append(("FAIL", f"{name}: {type(e).__name__}: {e}"))

    window = {}
    def _main_window_constructs():
        window["w"] = MainWindow()
        assert VERSION in window["w"].windowTitle()
    check("MainWindow constructs with all panels", _main_window_constructs)

    if "w" in window:
        w = window["w"]
        w.state.player.political_capital = 100.0

        check("window.show() triggers a real paint pass",
              lambda: (w.show(), app.processEvents()))

        def _daily_clock():
            w._set_clock_speed(0)
            before_day = w.state.day_index
            before_turn = w.state.turn
            w._advance_one_day()
            assert w.state.day_index == before_day + 1
            assert w.state.turn == before_turn, "a quiet day must not run a monthly pulse"
            w._set_clock_speed(3)
            assert w._clock_timer.isActive() and w._clock_speed == 3
            w.toggle_clock()
            assert not w._clock_timer.isActive() and w._clock_speed == 0
        check("daily pause-and-speed clock advances without multiplying monthly systems",
              _daily_clock)

        def _ardenia_map_canon():
            from content import lore
            from ui.ardenia_map_geometry import CITY_MARKERS, REGION_SHAPES

            region_ids = {region["id"] for region in lore.REGIONS}
            assert set(REGION_SHAPES) == region_ids, "every canon region needs one map shape"
            assert set(CITY_MARKERS) == {city["id"] for city in lore.CITIES}, \
                "every named city needs one dashboard marker"
            for city in lore.CITIES:
                marker = CITY_MARKERS[city["id"]]
                assert marker["region_id"] == city["region_id"]
                assert w._map._region_at(w._map._point(marker["point"])) == city["region_id"], \
                    f"{city['name']} marker sits outside {city['region_id']}"
            assert set(w.state.regions) == region_ids
            assert w._map._region_fill("vashtera") != w._map._region_fill("vetrenka"), \
                "live pressure should be legible in the regional map fill"
        check("Ardenia map covers every canonical region and city", _ardenia_map_canon)

        # ── System dock: the five pages live here now (non-modal tabs), so
        # they're exercised through the dock rather than via .exec(). ──
        def _pages_construct():
            for name in w._dock.TABS:
                w._show_page(name)
                app.processEvents()
                page = w._dock.pages[name]
                assert w._dock.current_page_name() == name, f"{name} tab did not focus"
                assert page.content.body.count() > 0, f"{name} rendered no content"
                if name == "Parties":
                    texts = [label.text() for label in page.findChildren(QLabel)]
                    assert any("leading bloc" in text for text in texts), \
                        "Ardenia's party page should name live blocs, not generic wings"
                    assert any("The Capital Bar" in text for text in texts), \
                        "the canonical bloc roster should be visible in the party page"
                    assert any("current pulls:" in text for text in texts), \
                        "the page should explain each bloc's live policy pressures"
            w._dock.hide()
            app.processEvents()
        check("all six system pages open + render as dock tabs", _pages_construct)

        def _dock_behaviour():
            # The dashboard must stay live while a tab is open — the whole
            # point of moving off modal dialogs.
            w._show_page("Briefing")
            app.processEvents()
            top_before = w._top_bar.text()
            turn_before = w.state.turn
            w.advance_turn()
            app.processEvents()
            assert w.state.turn == turn_before + 1, "turn should advance with a tab open"
            assert w._top_bar.text() != top_before, "dashboard must refresh live"
            assert w._dock.isVisible(), "dock should stay open across a turn"
            assert w._dock.pages["Briefing"].state is w.state, "page lost the live state"

            # An unfinished decision blocks End Turn on every route; finishing
            # or rebuilding the page releases it.
            w._show_page("Cabinet")
            app.processEvents()
            cab = w._dock.pages["Cabinet"]
            cab._do_shortlist()
            app.processEvents()
            assert cab.has_uncommitted_input()
            assert not w._end_turn_btn.isEnabled(), "button must block mid-decision"
            assert not w._act_end_turn.isEnabled(), "menu/shortcut must block too"
            guarded_turn = w.state.turn
            w.advance_turn()
            assert w.state.turn == guarded_turn, "direct call must be refused too"
            cab.refresh()
            app.processEvents()
            assert not cab.has_uncommitted_input()
            w._update_end_turn_guard()
            assert w._end_turn_btn.isEnabled(), "guard should release after rebuild"

            # The main map is domestic now: a region selection updates the
            # regional brief, while foreign focus remains in Diplomacy.
            w._on_region_selected("zavost")
            app.processEvents()
            assert w._right._selected_region_id == "zavost"
            assert "Zavost" in w._right._detail.text()
            assert "Political pressure:" in w._right._detail.text()
            assert "Industrial reckoning" in w._right._detail.text()
            programme_buttons = [button.text() for button in
                                 w._right._regional_actions.findChildren(QPushButton)]
            assert any("Industrial recovery" in text for text in programme_buttons)
            assert any("Campaign in this region" in text for text in programme_buttons)

            w._show_page("Diplomacy")
            w._dock.set_selected_country("krasova")
            app.processEvents()
            assert w._dock.pages["Diplomacy"]._country_combo.currentData() == "krasova"

            w._dock.hide()
            app.processEvents()
        check("dock stays live across a turn; End Turn guard + map wiring hold",
              _dock_behaviour)

        # ── Each action op, driven through the window's shared runner. ──
        def _actions():
            # This check exists to prove every op ROUTES through the window,
            # not that one government could do all of this in a single month.
            # Government attention (engine/player_ops.py: MONTHLY_ATTENTION)
            # caps major initiatives at three per month, so attention is
            # cleared between groups below — clearing it here is the honest
            # equivalent of "and the next month, they did this too", and keeps
            # the routing coverage without weakening the cap.
            def _new_month():
                w.state.attention_spent = 0

            # Propose a statutory bill, then lobby, then vote on it.
            _new_month()
            statutory = next((b for b in ops.proposable_bills(w.state) if b.tier == "statutory"), None)
            if statutory:
                w._run_op(lambda st: ops.op_propose_bill(st, statutory))
                pending = w.state.legislature.pending_bills
                if pending:
                    bill = pending[0]
                    fac = w.state.country.factions[1]
                    w._run_op(lambda st: ops.op_lobby_faction(st, bill, fac))
                    w._run_op(lambda st: ops.op_call_vote(st, bill))
            _new_month()
            # Executive order.
            eo = next((b for b in ops.proposable_bills(w.state) if b.tier == "executive_order"), None)
            if eo:
                w._run_op(lambda st: ops.op_propose_bill(st, eo))
            _new_month()
            # Cabinet.
            w._run_op(lambda st: ops.op_reshuffle(st, "Defense", "agrarian_union"))
            w._run_op(lambda st: ops.op_dismiss(st, "Justice"))
            _new_month()
            # Diplomacy.
            w._run_op(lambda st: ops.op_improve_relations(st, "veldoria"))
            w._run_op(lambda st: ops.op_trade_agreement(st, "veldoria"))
            w._run_op(lambda st: ops.op_foreign_loan(st, "veldoria"))
            w._run_op(lambda st: ops.op_condemn(st, "krasova"))
            _new_month()
            # Faction outreach.
            wf = next(f for f in w.state.country.factions if f.id == "workers_front")
            if wf.grievances:
                w._run_op(lambda st: ops.op_address_grievance(st, wf, 0))
            w._run_op(lambda st: ops.op_court_faction(st, w.state.country.factions[0]))
            w._run_op(lambda st: ops.op_campaign(st))
            _new_month()
            w.state.player.political_capital = 100.0
            w._run_op(lambda st: ops.op_start_regional_program(
                st, "zavost", "industrial_recovery"))
            assert w.state.regional_programs
            app.processEvents()
        check("every player action runs through the window", _actions)

        # ── Dialogs. ──
        from ui.dialogs import (TurnSummaryDialog, DispatchDetailDialog,
                                MetricBreakdownDialog, snapshot_metrics)

        def _dialogs():
            before = snapshot_metrics(w.state)
            w.state = w.engine.advance(w.state)
            after = snapshot_metrics(w.state)
            TurnSummaryDialog(w.state, before, after)
            for txt in ["VOTE PASSED — X", "SCANDAL — minister resigns", "PROTESTS begin",
                        "CONFIDENCE VOTE lost", "GENERAL ELECTION held", "Trade agreement signed"]:
                DispatchDetailDialog(txt, w.state)
            MetricBreakdownDialog("Approval", w.state)
            MetricBreakdownDialog("Stability", w.state)
            app.processEvents()
        check("summary + dispatch-detail + metric-breakdown dialogs construct", _dialogs)

        # ── Clickable signals fire without error. ──
        def _signals():
            w._left.metric_clicked.emit("Approval")   # would open a breakdown
            w._map.region_selected.emit("kelvet")
            app.processEvents()
            assert "Kelvet" in w._right._detail.text()
        check("metric + map click signals propagate", _signals)

        # ── A long run, exercising turn summaries through an election. ──
        def _long_run():
            for _ in range(50):
                w.advance_turn()
                app.processEvents()
        check("50 full turn cycles (incl. summary dialog) through an election", _long_run)
    else:
        # MainWindow never constructed, so every check that depends on it
        # never ran. Record that explicitly rather than silently omitting
        # them — a report that just goes quiet about ~6 checks would read
        # as "everything else passed" when really nothing else was tested.
        _skipped_without_window = [
            "window.show() triggers a real paint pass",
            "all four menu pages construct + refresh",
            "every player action runs through the window",
            "summary + dispatch-detail + metric-breakdown dialogs construct",
            "metric + map click signals propagate",
            "50 full turn cycles (incl. summary dialog) through an election",
        ]
        for name in _skipped_without_window:
            checks.append(("SKIP", f"{name} — skipped: MainWindow construction failed"))

    # ── Menu / wizard / campaign framework (this phase) ──────────────────────
    from ui.menu import (RootController, MainMenu, NewCampaignWizard,
                        CountrySelectStep, CharacterStep, DifficultyStep,
                        SummaryStep, LoadDialog, SettingsDialog, CreditsDialog)
    from engine.campaign import CampaignConfig, generate_campaign
    from engine import persistence

    check("MainMenu constructs", lambda: MainMenu())
    def _root_controller_constructs():
        root = RootController()
        assert VERSION in root.windowTitle()
    check("RootController constructs", _root_controller_constructs)
    check("SettingsDialog + CreditsDialog construct",
          lambda: (SettingsDialog(), CreditsDialog()))
    check("LoadDialog constructs", lambda: LoadDialog())

    def _wizard():
        wiz = NewCampaignWizard()
        captured = {}
        wiz.finished_config.connect(lambda cfg: captured.__setitem__("cfg", cfg))
        # Walk every step; each collect() must run cleanly against real Qt.
        wiz._go_next(); wiz._go_next(); wiz._go_next(); wiz._go_next()
        assert "cfg" in captured
        # The game is Ardenia-only for now: the wizard can only ever produce
        # an Ardenian campaign.
        assert captured["cfg"].country_id == "ardenia", captured["cfg"].country_id
        st = generate_campaign(captured["cfg"])
        assert st.player is not None
        assert st.country.id == "ardenia"
    check("wizard walks all steps + generates an Ardenian campaign", _wizard)

    def _character_options():
        step = CharacterStep()
        cfg = CampaignConfig(country_id="ardenia")
        step.on_enter(cfg)
        assert not hasattr(step, "_portrait"), "portrait selector should be completely removed"
        party_ids = [step._party.itemData(i) for i in range(step._party.count())]
        assert "national_conservatives" in party_ids and "workers_front" in party_ids
        roles = [step._opening_role.itemData(i)
                 for i in range(step._opening_role.count())]
        assert roles == ["contextual", "government", "opposition"]
        step._party.setCurrentIndex(party_ids.index("national_conservatives"))
        step._opening_role.setCurrentIndex(2)
        step._use_ideology.setChecked(True)
        step._econ["slider"].setValue(-25)
        step._soc["slider"].setValue(70)
        step.collect(cfg)
        assert cfg.party_id == "national_conservatives"
        assert cfg.opening_role == "opposition"
        assert cfg.ideology_economic == -0.25 and cfg.ideology_social == 0.70
    check("character setup has mechanical party, position, ideology, and no portrait",
          _character_options)

    def _opposition_policy_page():
        from ui.pages import PoliciesPage
        from engine.turn import TurnEngine
        st = generate_campaign(CampaignConfig(
            country_id="ardenia", party_id="national_conservatives",
            opening_role="opposition", background_id="none", seed=611))
        TurnEngine().advance(st)  # government introduces its first bill
        page = PoliciesPage(st)
        labels = {button.text() for button in page.findChildren(QPushButton)}
        assert {"Support the Bill", "Oppose the Bill", "Negotiate an Amendment"} <= labels
        assert "Add Pledge" in labels
        page._do_add_pledge()
        labels = {button.text() for button in page.findChildren(QPushButton)}
        assert "Campaign on Pledge" in labels and st.domestic_politics[
            "opposition_agenda"]["pledges"]
        page._do_oppose_government_bill()
        assert not any(button.text() == "Oppose the Bill"
                       for button in page.findChildren(QPushButton)), \
            "declaring a position should replace the response controls"
    check("opposition policy page responds to AI government legislation",
          _opposition_policy_page)

    def _shadow_cabinet_page():
        from ui.pages import CabinetPage
        st = generate_campaign(CampaignConfig(
            country_id="ardenia", party_id="workers_front",
            opening_role="opposition", background_id="none", seed=612))
        st.player.political_capital = 100.0
        page = CabinetPage(st)
        labels = {button.text() for button in page.findChildren(QPushButton)}
        assert "Draw Up Party Shortlist" in labels
        assert "Appoint to Shadow Cabinet" in labels
        page._do_shortlist()
        assert page.has_uncommitted_input() and page._candidate_combo.count() == 3
        page._candidate_combo.setCurrentIndex(0)
        portfolio = page._shortlist_portfolio
        page._do_appoint()
        assert st.shadow_cabinet.get(portfolio) is not None
        assert not page.has_uncommitted_input()
    check("opposition cabinet page builds a persistent shadow team",
          _shadow_cabinet_page)

    def _country_step_scope():
        from ui.menu import PLAYABLE_COUNTRY_IDS
        from content import loader as country_loader
        step = CountrySelectStep()
        rows = [step._list.item(i) for i in range(step._list.count())]
        assert PLAYABLE_COUNTRY_IDS == {"ardenia"}
        assert len(rows) == 1, f"expected one campaign country, got {len(rows)}"
        assert [item.data(Qt.UserRole) for item in rows] == ["ardenia"]
        assert [item.text() for item in rows] == ["Begin the Ardenia campaign"]
        assert all("Coming Soon" not in item.text() for item in rows)
        visible_copy = [label.text() for label in step.findChildren(QLabel)]
        assert "Neighboring states remain active world actors." in visible_copy
        # Ardenia is selected, so the player can simply press Next.
        assert step._list.currentRow() == 0
        assert step._summaries[0]["id"] == "ardenia"
        cfg = CampaignConfig(country_id="krasova")
        step.collect(cfg)
        assert cfg.country_id == "ardenia"
        # Defensive collection must still reject an injected foreign id even
        # though foreign countries no longer have visible campaign rows.
        foreign = next(summary for summary in country_loader.list_country_summaries()
                       if summary["id"] != "ardenia")
        step._summaries[0] = foreign
        step.collect(cfg)
        assert cfg.country_id == "ardenia", "foreign selection must be rejected"
        # Foreign countries remain fully constructible as world actors.
        foreign_state = country_loader.build_state_for(foreign["id"])
        assert foreign_state.country.id == foreign["id"]
    check("country step: one confident Ardenia campaign with world actors intact",
          _country_step_scope)

    def _save_load_roundtrip():
        st = generate_campaign(CampaignConfig(country_id="veldoria", difficulty_id="easy"))
        persistence.save_campaign(st, slot="_uitest")
        loaded = persistence.load_campaign("_uitest")
        assert loaded.country.name == st.country.name
        persistence.delete_save("_uitest")
    check("campaign save + load round-trip", _save_load_roundtrip)

    def _launch_from_campaign():
        st = generate_campaign(CampaignConfig(country_id="krasova", difficulty_id="hard"))
        gw = MainWindow(state=st, on_exit_to_menu=lambda: None)
        gw.show()
        gw.advance_turn()   # exercises the autosave path with real Qt
        app.processEvents()
        persistence.delete_save("autosave")
    check("game window launches from a generated campaign + autosaves", _launch_from_campaign)

    def _public_sans_fonts_load():
        import glob
        font_files = sorted(glob.glob(
            os.path.join(os.path.dirname(__file__), "ui", "assets", "fonts", "*.ttf")))
        assert len(font_files) == 4, f"expected 4 Public Sans .ttf files, found {len(font_files)}"
        families = set()
        for path in font_files:
            font_id = QFontDatabase.addApplicationFont(path)
            assert font_id != -1, f"Qt rejected font file: {path}"
            families.update(QFontDatabase.applicationFontFamilies(font_id))
        assert "Public Sans" in families, f"no 'Public Sans' family registered, got {families}"
    check("Public Sans font files load into QFontDatabase", _public_sans_fonts_load)

    def _public_sans_registered_by_real_gui_startup():
        # The check above proves the .ttf files are valid and loadable; it
        # does NOT prove gui.py's actual startup registers them — that
        # registration call could be silently deleted from gui.main() and
        # this suite would never notice. So this drives the real
        # gui.main() code path instead of re-implementing registration.
        # gui.main() constructs its own QApplication(argv), which would
        # collide with the QApplication this test harness already owns; the
        # "--verify-build" argv path is used because it returns instead of
        # calling app.exec()'s blocking event loop (it fails fast on missing
        # packaged-only files here, but only *after* the font registration
        # and stylesheet lines run, which is the part under test).
        import gui
        original_qapplication = gui.QApplication
        gui.QApplication = lambda argv: app
        try:
            gui.main(["--verify-build"])
        finally:
            gui.QApplication = original_qapplication
        families = QFontDatabase.families()
        assert "Public Sans" in families, (
            "gui.main()'s real startup sequence did not register Public Sans — "
            "has the register_bundled_fonts() call been removed from gui.py? "
            f"got families containing 'Public': {[f for f in families if 'Public' in f]}")
    check("gui.py's real startup (gui.main) registers Public Sans, not just the raw .ttf files",
          _public_sans_registered_by_real_gui_startup)

    def _vitals_panel_qml_loads():
        from ui.qml_bridge import VitalStatModel
        quick = QQuickWidget()
        quick.setResizeMode(QQuickWidget.ResizeMode.SizeRootObjectToView)
        ctx = quick.rootContext()
        approval = VitalStatModel("Approval", metric_name="Approval")
        stability = VitalStatModel("Stability", metric_name="Stability")
        pc = VitalStatModel("Political capital", metric_name="Pol. Capital")
        attention = VitalStatModel("Attention")
        ctx.setContextProperty("approvalModel", approval)
        ctx.setContextProperty("stabilityModel", stability)
        ctx.setContextProperty("pcModel", pc)
        ctx.setContextProperty("attentionModel", attention)

        # errors()/status() alone let Critical #1 through: an illegal anchor
        # on a Column child doesn't raise a QML *error*, it emits a runtime
        # *warning* and silently disables the positioner. Capture every
        # qDebug/qWarning/qCritical message for the duration of this load and
        # fail on anything QML-sourced, then restore the previous handler so
        # this doesn't leak into the rest of the suite.
        captured = []
        previous_handler = qInstallMessageHandler(
            lambda msg_type, context, message: captured.append(message))
        try:
            qml_path = os.path.join(os.path.dirname(__file__), "ui", "qml", "VitalsPanel.qml")
            quick.setSource(QUrl.fromLocalFile(qml_path))
            app.processEvents()
        finally:
            qInstallMessageHandler(previous_handler)

        assert quick.status() == QQuickWidget.Status.Ready, \
            f"VitalsPanel.qml failed to load, status={quick.status()}, errors={quick.errors()}"
        assert quick.errors() == [], f"QML reported errors: {quick.errors()}"
        qml_warnings = [m for m in captured if "QML " in m]
        assert qml_warnings == [], f"QML reported warnings (not just errors): {qml_warnings}"

        # Geometry: a real assertion on layout, not just "it loaded". This is
        # the check that would have caught Critical #1 (all four vitals
        # collapsing to height 0 at y=0, fully overlapping).
        root = quick.rootObject()
        implicit_height = root.property("implicitHeight")
        assert implicit_height > 0, f"VitalsPanel root implicitHeight is {implicit_height}, expected > 0"
        assert implicit_height < 400, \
            f"VitalsPanel root implicitHeight is {implicit_height}, expected a sane ceiling (< 400)"
        children = root.childItems()
        assert len(children) == 4, f"expected 4 VitalStat children, got {len(children)}"
        ys = [c.property("y") for c in children]
        assert ys == sorted(ys) and len(set(ys)) == len(ys), \
            f"VitalStat children are not laid out in strictly increasing y order (collapsed/overlapping?): {ys}"
    check("VitalsPanel.qml loads with no QML errors or warnings, and lays out with real geometry",
          _vitals_panel_qml_loads)

    def _left_panel_vitals_python_signal_forwarding():
        # Honest name: this only exercises the Python-side signal chain
        # (VitalStatModel.activate() -> .clicked -> LeftPanel.metric_clicked)
        # via a direct method call, never the actual QML MouseArea hit-test —
        # see the check below for that. Built against a fresh sample state
        # rather than reusing the MainWindow fixture, so this check is
        # independent of whichever earlier check ran (or didn't) first.
        from ui.panel_left import LeftPanel
        from main import build_sample_game
        st = build_sample_game()
        panel = LeftPanel(st)
        app.processEvents()
        clicked = []
        panel.metric_clicked.connect(lambda name: clicked.append(name))
        panel.refresh(st)
        assert panel._approval_model.readoutText.endswith("%")
        panel._approval_model.activate()
        assert clicked == ["Approval"], f"expected a click-through from QML to LeftPanel.metric_clicked, got {clicked}"
    check("LeftPanel's QML vitals refresh and forward the Python-side click signal",
          _left_panel_vitals_python_signal_forwarding)

    def _left_panel_vitals_real_mouse_click():
        # Stronger coverage than the Python-signal check above: drives an
        # actual QTest.mouseClick on the QQuickWidget's Approval row, so a
        # mispositioned or non-functional click target (exactly what
        # Critical #1's broken Column/MouseArea anchoring produced) would
        # fail this check even if the Python signal wiring were fine.
        from ui.panel_left import LeftPanel
        from main import build_sample_game
        st = build_sample_game()
        panel = LeftPanel(st)
        panel.refresh(st)
        # QTest.mouseClick needs a real window handle to deliver events
        # through — without .show() the offscreen QQuickWidget never gets
        # one and the click silently goes nowhere.
        panel.show()
        app.processEvents()
        clicked = []
        panel.metric_clicked.connect(lambda name: clicked.append(name))
        # Approval is the first VitalStat, occupying y=0 down to its own
        # height at the top of the QQuickWidget — (10, 8) lands inside its
        # MouseArea (anchors.fill over the whole Column) regardless of the
        # panel's exact measured height.
        QTest.mouseClick(panel._vitals_quick, Qt.LeftButton, pos=QPoint(10, 8))
        app.processEvents()
        assert clicked == ["Approval"], \
            f"a real mouse click on the Approval vital did not reach LeftPanel.metric_clicked, got {clicked}"
    check("LeftPanel's QML vitals forward a real QTest mouse click on the Approval hit target",
          _left_panel_vitals_real_mouse_click)

    def _left_panel_vitals_populated_height_fits():
        # A bare QQuickWidget (as in the earlier check) measures a
        # different, SMALLER implicitHeight than one embedded in
        # LeftPanel's real QVBoxLayout — confirmed empirically (108px bare
        # vs. 149px embedded, same populated content). That gap is exactly
        # what let a real regression through once already: the fixed panel
        # height was measured at construction time, before refresh() had
        # ever populated the models, and undershot the real content,
        # clipping the Attention vital. This check reproduces the actual
        # embedding (a real LeftPanel, shown, refreshed with a genuine
        # Approval force so ForceGlyph renders its tallest state) and
        # confirms the real content still fits inside the fixed height.
        from ui.panel_left import LeftPanel, VITALS_PANEL_HEIGHT
        from main import build_sample_game
        from models.modifiers import Modifier
        st = build_sample_game()
        st.modifiers.append(Modifier(id="qa-probe", source="Probe reform",
                                     target="approval_bias", magnitude=0.05,
                                     onset_delay=0, ramp_duration=3, age=1))
        panel = LeftPanel(st)
        panel.show()
        app.processEvents()
        app.processEvents()
        widget_height = panel._vitals_quick.height()
        assert widget_height == VITALS_PANEL_HEIGHT, \
            f"widget height {widget_height} should equal the fixed VITALS_PANEL_HEIGHT constant {VITALS_PANEL_HEIGHT}"
        root_obj = panel._vitals_quick.rootObject()
        real_height = root_obj.property("implicitHeight")
        assert real_height <= widget_height, (
            f"CLIPPING: real populated implicitHeight is {real_height}, but the "
            f"fixed widget height is only {widget_height} — content is cut off. "
            f"Re-measure (with a real refresh() + show(), not right after "
            f"setSource()) and update ui/panel_left.VITALS_PANEL_HEIGHT.")
        children = root_obj.childItems()
        for child in children:
            y, h = child.property("y"), child.property("height")
            assert y + h <= widget_height, \
                f"a VitalStat (y={y}, h={h}) extends past the widget's {widget_height}px height"
        panel.hide()
        app.processEvents()
    check("LeftPanel's real, populated vitals panel fits inside its fixed height (no clipping)",
          _left_panel_vitals_populated_height_fits)

    print("\n" + "=" * 60)
    for status, name in checks:
        print(f"  {status}  {name}")
    n_pass = sum(1 for s, _ in checks if s == "PASS")
    n_fail = sum(1 for s, _ in checks if s == "FAIL")
    n_skip = sum(1 for s, _ in checks if s == "SKIP")
    print("=" * 60)
    print(f"{n_pass} passed, {n_fail} failed, {n_skip} skipped  (of {len(checks)} checks total)")
    if n_fail:
        print(f"{n_fail} FAILURE(S) — see tracebacks above.")
    elif n_skip:
        print(f"{n_skip} check(s) never ran because an earlier check they depend on failed — "
              f"not a clean pass.")
    else:
        print(f"ALL {len(checks)} UI SMOKE CHECKS PASSED — `python gui.py` should work.")
    sys.exit(1 if (n_fail or n_skip) else 0)


if __name__ == "__main__":
    main()
