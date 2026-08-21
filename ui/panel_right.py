"""
Right panel: election countdown, world-relations list (swatches match the
map), and the selected-country detail box the map fills in on click.
"""

from PySide6.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QLabel, QFrame,
                               QPushButton, QComboBox, QScrollArea)
from PySide6.QtCore import Qt

from ui import theme
from ui.widgets_common import banded, STATE_REACH_BANDS
from ui.ardenia_map_geometry import REGION_MAP_META
from engine import elections, worldsim, regions as region_engine
from engine import player_ops as ops
from content import lore
from content.regions import (ARDENIA_REGION_PROFILES, CONTROL_LABELS,
                             REGIONAL_ISSUES, REGIONAL_PROGRAMS)


def _pressure_label(value: float) -> str:
    """Delegates to the theme ramp so this panel, the map legend and the map
    fill can never disagree about what a given pressure is called."""
    return theme.pressure_word(value)


def _civil_war_line(risk: float, in_civil_war: bool) -> str:
    if in_civil_war:
        return "⚠ IN CIVIL WAR"
    if risk > 0.6:
        return f"Civil-war risk: CRITICAL ({risk*100:.0f}%)"
    if risk > 0.4:
        return f"Civil-war risk: high ({risk*100:.0f}%)"
    if risk > 0.25:
        return f"Civil-war risk: elevated ({risk*100:.0f}%)"
    return None


def _section_title(text: str) -> QLabel:
    lbl = QLabel(text)
    lbl.setStyleSheet(
        f"color: {theme.ACCENT}; font-size: {theme.FONT_SIZE_SM}pt; "
        f"letter-spacing: 1px; padding-top: 6px;")
    return lbl


def _divider() -> QFrame:
    line = QFrame()
    line.setFrameShape(QFrame.HLine)
    line.setStyleSheet(f"color: {theme.PANEL_EDGE}; background: {theme.PANEL_EDGE};")
    line.setFixedHeight(1)
    return line


class _RelationRow(QWidget):
    """A country name with a colour swatch and status word."""
    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 1, 0, 1)
        layout.setSpacing(6)
        self._swatch = QLabel()
        self._swatch.setFixedSize(12, 12)
        self._name = QLabel()
        self._name.setStyleSheet(f"color: {theme.INK};")
        self._status = QLabel()
        self._status.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self._status.setStyleSheet(f"color: {theme.INK_DIM};")
        layout.addWidget(self._swatch)
        layout.addWidget(self._name, stretch=1)
        layout.addWidget(self._status)

    def set_data(self, name, color, status):
        self._swatch.setStyleSheet(f"background: {color}; border: 1px solid {theme.BG};")
        self._name.setText(name)
        self._status.setText(status)


class _DiplomacyActions(QWidget):
    """The diplomacy verbs for whichever country is selected on the map —
    the same player_ops.op_* functions the Diplomacy page calls, one click
    from the map instead of behind a modal with its own dropdown."""

    def __init__(self, on_action, parent=None):
        super().__init__(parent)
        self._on_action = on_action
        self._layout = QVBoxLayout(self)
        self._layout.setContentsMargins(0, 2, 0, 0)
        self._layout.setSpacing(3)
        self._treaty_combo = None
        self.hide()

    def _clear(self):
        # setParent(None) detaches immediately; deleteLater alone would leave
        # the old buttons in the widget tree until the event loop caught up.
        while self._layout.count():
            item = self._layout.takeAt(0)
            w = item.widget()
            if w is not None:
                w.setParent(None)
                w.deleteLater()

    def _button(self, label, enabled, why, handler):
        btn = QPushButton(label)
        btn.setEnabled(enabled)
        btn.setStyleSheet(f"font-size: {theme.FONT_SIZE_SM}pt; padding: 3px 4px;")
        if why:
            btn.setToolTip(why)
        if enabled:
            btn.clicked.connect(handler)
        return btn

    def rebuild(self, state, country_id):
        self._clear()
        self._treaty_combo = None
        if (self._on_action is None or country_id is None
                or country_id == state.country.id
                or not state.player.in_government):
            self.hide()
            return
        country = state.world_country(country_id)
        if country is None:
            self.hide()
            return

        rel = state.country.get_relation(country_id)
        score = rel.score if rel else 0.0
        sanctioned = bool(rel and rel.sanctioned)
        has_pact = any(t.type == "defense" for t in rel.treaties) if rel else False
        trade_ok = country_id in {c.id for c in ops.trade_eligible_countries(state)}
        summit_cd = ops.on_cooldown(state, "summit", ops.SUMMIT_COOLDOWN)

        self._layout.addWidget(_section_title(f"ACTIONS — {country.name.upper()}"))

        rows = [
            [("Improve", True, f"{ops.COST_IMPROVE_RELATIONS:.0f} PC",
              lambda: self._run(lambda st: ops.op_improve_relations(st, country_id))),
             ("Trade Deal", trade_ok,
              f"{ops.COST_TRADE_AGREEMENT:.0f} PC" if trade_ok
              else "They won't discuss trade at this level of trust",
              lambda: self._run(lambda st: ops.op_trade_agreement(st, country_id)))],
            [("Loan", True, f"{ops.COST_FOREIGN_LOAN:.0f} PC — cash now, interest later",
              lambda: self._run(lambda st: ops.op_foreign_loan(st, country_id))),
             ("Condemn", True, f"{ops.COST_CONDEMN:.0f} PC",
              lambda: self._run(lambda st: ops.op_condemn(st, country_id)))],
            [("Defense Pact", (score >= ops.PACT_RELATION_FLOOR and not has_pact),
              f"{ops.PACT_COST:.0f} PC — needs relations ≥ {ops.PACT_RELATION_FLOOR:.2f}"
              + (" (already allied)" if has_pact else ""),
              lambda: self._run(lambda st: ops.op_defense_pact(st, country_id))),
             ("Summit", not summit_cd,
              f"{ops.SUMMIT_COST:.0f} PC" if not summit_cd
              else f"Again in {ops.cooldown_remaining(state, 'summit', ops.SUMMIT_COOLDOWN)} mo",
              lambda: self._run(lambda st: ops.op_hold_summit(st, country_id)))],
        ]
        if sanctioned:
            rows.append([("Lift Sanctions", True, f"{ops.LIFT_SANCTIONS_COST:.0f} PC",
                          lambda: self._run(lambda st: ops.op_lift_sanctions(st, country_id))),
                         None])
        else:
            rows.append([("Sanction", score < 0.2,
                          f"{ops.SANCTIONS_COST:.0f} PC" if score < 0.2
                          else "Relations are too good to sanction",
                          lambda: self._run(lambda st: ops.op_impose_sanctions(st, country_id))),
                         None])

        for pair in rows:
            row = QWidget(); rl = QHBoxLayout(row)
            rl.setContentsMargins(0, 0, 0, 0); rl.setSpacing(4)
            for spec in pair:
                if spec is None:
                    rl.addStretch(1)
                    continue
                label, enabled, why, handler = spec
                rl.addWidget(self._button(label, enabled, why, handler), stretch=1)
            self._layout.addWidget(row)

        treaties = list(rel.treaties) if rel else []
        if treaties:
            self._treaty_combo = QComboBox()
            self._treaty_combo.setStyleSheet(f"font-size: {theme.FONT_SIZE_SM}pt;")
            for t in treaties:
                self._treaty_combo.addItem(f"{t.type.title()} treaty", t.id)
            trow = QWidget(); tl = QHBoxLayout(trow)
            tl.setContentsMargins(0, 0, 0, 0); tl.setSpacing(4)
            tl.addWidget(self._treaty_combo, stretch=1)
            tear = self._button("Tear Up", True, "Walk away — they will remember it",
                                lambda: self._tear_up(country_id))
            tl.addWidget(tear)
            self._layout.addWidget(trow)

        self.show()

    def _run(self, op):
        self._on_action(op)

    def _tear_up(self, country_id):
        if self._treaty_combo is None:
            return
        tid = self._treaty_combo.currentData()
        self._on_action(lambda st: ops.op_break_treaty(st, country_id, tid))


class _RegionalActions(QWidget):
    """Government programmes for the region selected on the national map."""

    def __init__(self, on_action, parent=None):
        super().__init__(parent)
        self._on_action = on_action
        self._layout = QVBoxLayout(self)
        self._layout.setContentsMargins(0, 4, 0, 0)
        self._layout.setSpacing(4)
        self.hide()

    def _clear(self):
        while self._layout.count():
            item = self._layout.takeAt(0)
            widget = item.widget()
            if widget is not None:
                widget.setParent(None)
                widget.deleteLater()

    def rebuild(self, state, region_id):
        self._clear()
        if self._on_action is None or region_id is None:
            self.hide()
            return

        active = region_engine.active_program_for(state, region_id)
        if active is not None:
            definition = REGIONAL_PROGRAMS[active.program_id]
            remaining = max(0, active.duration - active.months_active)
            quality = region_engine.program_delivery_quality(state, active)
            self._layout.addWidget(_section_title("ACTIVE PROGRAMME"))
            label = QLabel(
                f"{definition['name']}\n"
                f"Delivered {active.months_active} of {active.duration} months · "
                f"{remaining} remaining\n"
                f"{active.monthly_cost:.0f} M/month · delivery {quality*100:.0f}%")
            label.setWordWrap(True)
            label.setStyleSheet(
                f"color: {theme.INK}; font-size: {theme.FONT_SIZE_SM}pt; "
                f"background: {theme.PANEL_RAISED}; padding: 6px; border-radius: 4px;")
            self._layout.addWidget(label)

        if active is None:
            self._layout.addWidget(_section_title("REGIONAL PROGRAMMES"))
            if not state.player.in_government:
                note = QLabel(
                    "Only the sitting government can direct state programmes.")
                note.setWordWrap(True)
                note.setStyleSheet(
                    f"color: {theme.INK_DIM}; font-size: {theme.FONT_SIZE_SM}pt;")
                self._layout.addWidget(note)
            else:
                programmes = ops.regional_programs_for(state, region_id)
                if not programmes:
                    note = QLabel(
                        "The current control line prevents state programme delivery here.")
                    note.setWordWrap(True)
                    note.setStyleSheet(
                        f"color: {theme.WARN}; font-size: {theme.FONT_SIZE_SM}pt;")
                    self._layout.addWidget(note)
                for program_id, definition in programmes:
                    cost = definition["pc_cost"]
                    button = QPushButton(
                        f"{definition['short_name']} — {cost:.0f} PC\n"
                        f"{definition['duration']} mo · {definition['monthly_cost']:.0f} M/mo")
                    button.setEnabled(state.player.political_capital >= cost)
                    button.setStyleSheet(
                        f"font-size: {theme.FONT_SIZE_SM}pt; padding: 5px 4px; text-align: left;")
                    button.setToolTip(definition["body"])
                    button.clicked.connect(
                        lambda _checked=False, pid=program_id:
                        self._on_action(
                            lambda st: ops.op_start_regional_program(st, region_id, pid)))
                    self._layout.addWidget(button)

        self._layout.addWidget(_section_title("PARTY ORGANISATION"))
        campaign_ok, campaign_reason = ops.can_campaign_region(state, region_id)
        campaign = QPushButton(
            f"Campaign in this region — {ops.REGIONAL_CAMPAIGN_COST:.0f} PC")
        campaign.setEnabled(
            campaign_ok and state.player.political_capital >= ops.REGIONAL_CAMPAIGN_COST)
        campaign.setToolTip(campaign_reason or
                            "Build local support at the strongest rival's expense.")
        campaign.setStyleSheet(
            f"font-size: {theme.FONT_SIZE_SM}pt; padding: 5px 4px;")
        campaign.clicked.connect(
            lambda: self._on_action(lambda st: ops.op_campaign_region(st, region_id)))
        self._layout.addWidget(campaign)
        self.show()


class RightPanel(QWidget):
    def __init__(self, state, on_action=None, on_open_page=None, parent=None):
        super().__init__(parent)
        self.setObjectName("RightPanel")
        self._on_open_page = on_open_page
        self.setFixedWidth(288)
        self.setStyleSheet(
            f"QWidget#RightPanel {{ background: {theme.PANEL_BG}; "
            f"border: 1px solid {theme.PANEL_EDGE}; border-radius: 8px; }}")

        # Scrollable: this panel's content varies a lot (the diplomacy action
        # block appears on selection, treaty rows come and go). Without the
        # scroll area its minimum height tracks its contents and shoves the
        # whole window taller when they grow.
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        scroll.setMinimumHeight(120)     # explicit minimum beats the content hint
        inner = QWidget()
        scroll.setWidget(inner)
        outer.addWidget(scroll)

        layout = QVBoxLayout(inner)
        layout.setContentsMargins(12, 10, 12, 10)
        layout.setSpacing(3)

        layout.addWidget(_section_title("NEXT ELECTION"))
        self._election_days = QLabel()
        self._election_days.setStyleSheet(
            f"color: {theme.INK}; font-size: 15pt; font-weight: 600;")
        layout.addWidget(self._election_days)
        self._election = QLabel()
        self._election.setStyleSheet(
            f"color: {theme.INK_FAINT}; font-size: {theme.FONT_SIZE_SM}pt;")
        self._election.setWordWrap(True)
        layout.addWidget(self._election)

        layout.addSpacing(6)
        layout.addWidget(_divider())
        layout.addWidget(_section_title("ABROAD"))
        # Only relations that are actually saying something get a row. Nine
        # rows of which eight read "Neutral" is a list that costs a column of
        # dashboard to convey one fact — that nothing has changed.
        self._relation_rows = []
        self._relations_container = QVBoxLayout()
        self._relations_container.setSpacing(1)
        layout.addLayout(self._relations_container)
        self._relations_note = QLabel()
        self._relations_note.setWordWrap(True)
        self._relations_note.setTextFormat(Qt.RichText)
        self._relations_note.setStyleSheet(
            f"color: {theme.INK_FAINT}; font-size: {theme.FONT_SIZE_SM}pt; padding-top: 4px;")
        self._relations_note.setCursor(Qt.PointingHandCursor)
        self._relations_note.mousePressEvent = self._on_relations_note_clicked
        layout.addWidget(self._relations_note)

        layout.addSpacing(6)
        layout.addWidget(_divider())
        layout.addWidget(_section_title("SELECTED REGION"))
        self._detail = QLabel("Click a region on the map.")
        self._detail.setWordWrap(True)
        self._detail.setStyleSheet(f"color: {theme.INK_DIM}; font-size: {theme.FONT_SIZE_SM}pt;")
        self._detail.setTextFormat(Qt.PlainText)
        layout.addWidget(self._detail)

        # Diplomacy, one click from the map (same ops as the Diplomacy page).
        self._regional_actions = _RegionalActions(on_action)
        layout.addWidget(self._regional_actions)
        self._actions = _DiplomacyActions(on_action)
        layout.addWidget(self._actions)

        layout.addStretch(1)
        self._selected_id = None
        self._selected_region_id = None
        self.refresh(state)

    def _ensure_rows(self, n):
        """Create relation rows lazily to match the number of world countries."""
        while len(self._relation_rows) < n:
            row = _RelationRow()
            self._relation_rows.append(row)
            self._relations_container.addWidget(row)

    def set_selected(self, country_id, state):
        self._selected_id = country_id
        self._selected_region_id = None
        self._refresh_detail(state)

    def set_selected_region(self, region_id, state):
        """Show domestic geography in the dashboard; diplomacy stays in its tab."""
        self._selected_region_id = region_id
        self._selected_id = None
        self._refresh_detail(state)

    def _refresh_detail(self, state):
        region_id = self._selected_region_id
        if region_id is not None:
            self._actions.rebuild(state, None)
            self._regional_actions.rebuild(state, region_id)
            region = next((item for item in lore.REGIONS if item["id"] == region_id), None)
            if region is None:
                self._detail.setText("—")
                return
            lines = [
                region["name"],
                REGION_MAP_META.get(region_id, "Regional briefing pending."),
            ]
            live = getattr(state, "regions", {}).get(region_id)
            profile = ARDENIA_REGION_PROFILES.get(region_id)
            if live is not None and profile is not None:
                issue = REGIONAL_ISSUES.get(live.issue_id, {
                    "name": profile["issue_name"], "body": profile["issue_body"]})
                local_support = region_engine.projected_party_support(state, region_id)
                ranked = sorted(local_support.items(), key=lambda item: item[1], reverse=True)
                faction_names = {faction.id: faction.name
                                 for faction in state.country.factions}
                poll_line = " · ".join(
                    f"{faction_names.get(faction_id, faction_id)} {share*100:.0f}%"
                    for faction_id, share in ranked[:2])
                reach_word, _reach_color = banded(live.state_reach, STATE_REACH_BANDS)
                lines.extend([
                    f"Control: {CONTROL_LABELS.get(live.control, live.control)}",
                    f"State reach: {live.state_reach*100:.0f}% — {reach_word}",
                    f"Unemployment: {live.unemployment*100:.1f}%",
                    f"Political pressure: {live.pressure*100:.0f}% — "
                    f"{_pressure_label(live.pressure)}",
                    f"Electoral access: {region_engine.electoral_access(state, region_id)*100:.0f}%",
                    f"Local polling: {poll_line}",
                    "",
                    f"Defining issue: {issue['name']}",
                    issue["body"],
                ])
            elif region_id == "vetrenka":
                lines.append("Control: Vetrenka Free Front")
                lines.append("Status: ceasefire line; inaccessible to Vashtera")
            elif region_id == "anera":
                lines.append("Control: formal state authority; uneven in the uplands")
            else:
                lines.append("Control: Vashtera")
            self._detail.setText("\n".join(lines))
            return

        cid = self._selected_id
        self._regional_actions.rebuild(state, None)
        self._actions.rebuild(state, cid)
        if cid is None:
            self._detail.setText("Click a region on the map.")
            return
        if cid == state.country.id:
            c = state.country
            lines = [
                f"{c.name} (your country)",
                f"Regime: {c.regime_type.replace('_', ' ')}",
                f"Population: {c.population:,}",
            ]
            cw = _civil_war_line(state.civil_war_risk, state.civil_war)
            if cw:
                lines.append(cw)
            self._detail.setText("\n".join(lines))
            return
        c = state.world_country(cid)
        if c is None:
            self._detail.setText("—")
            return
        rel = state.country.get_relation(cid)
        lines = [
            f"{c.name}",
            f"Regime: {c.regime_type.replace('_', ' ')}",
            f"Population: {c.population:,}",
            f"Stability: {c.stability:.2f}",
            f"Posture: {worldsim.describe_agenda(state, c)}",
        ]
        if rel:
            lines.append(f"Relation: {rel.status_label()} ({rel.score:+.2f})")
            lines.append(f"Trade: {rel.trade_volume:,.0f} M")
        if rel and rel.sanctioned:
            lines.append("⚠ Under your sanctions")
        cw = _civil_war_line(c.civil_war_risk, c.in_civil_war)
        if cw:
            lines.append(cw)
        self._detail.setText("\n".join(lines))

    def _on_relations_note_clicked(self, _event):
        if self._on_open_page is not None:
            self._on_open_page("Diplomacy")

    def refresh(self, state):
        days = elections.days_until_election(state)
        snap = elections.should_trigger_snap_election(state)
        self._election_days.setText(f"{days:,} days")
        notes = []
        if snap:
            notes.append("⚠ collapse risk — may come sooner")
        if not state.player.in_government:
            notes.append("(you are in opposition)")
        self._election.setText("\n".join(notes) if notes else "Full term")

        # A relation earns a row by being something other than neutral; the
        # rest are summarised in one line with a route to the full table.
        notable = []
        neutral = 0
        for c in state.world:
            rel = state.country.get_relation(c.id)
            score = rel.score if rel else None
            sanctioned = bool(rel and rel.sanctioned)
            if score is not None and -0.3 < score <= 0.3 and not sanctioned:
                neutral += 1
                continue
            status = rel.status_label() if rel else "unknown"
            if sanctioned:
                status += " · sanctioned"
            notable.append((c.name, theme.relation_color(score), status,
                            abs(score) if score is not None else 0.0))
        notable.sort(key=lambda item: -item[3])

        self._ensure_rows(len(notable))
        for i, row in enumerate(self._relation_rows):
            if i < len(notable):
                name, color, status, _weight = notable[i]
                row.set_data(name, color, status)
                row.show()
            else:
                row.hide()

        parts = []
        if neutral:
            parts.append(f"{neutral} other{'s' if neutral != 1 else ''} neutral")
        if not notable:
            parts = [f"All {neutral} relations neutral"] if neutral else ["No relations"]
        parts.append(f"<span style='color:{theme.ACCENT};'>see all →</span>")
        self._relations_note.setText(" — ".join(parts))

        self._refresh_detail(state)
