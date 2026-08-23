"""
Left panel, in three tiers of decreasing importance.

The old column rendered nine indicators at identical visual weight, which
meant nothing signalled what mattered — and it drew progress bars for growth,
inflation and debt/GDP, none of which is a bounded 0..1 value where higher is
better, so the bar was actively misleading.

Now:
  1. YOUR GOVERNMENT — approval, stability, political capital as large
     headline vitals, one thin track each.
  2. ECONOMY — a compact label/value table, no bars, each value coloured by
     its own health and followed by a trend glyph for the direction of travel
     since last month.
  3. More indicators — the raw figures, behind a disclosure, for when someone
     actually wants them.
"""

from PySide6.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QLabel,
                               QFrame, QToolButton)
from PySide6.QtCore import Qt, Signal, QUrl
from PySide6.QtQuickWidgets import QQuickWidget

import app_paths
from ui import theme, explain, modifier_glyph
from ui.qml_bridge import VitalStatModel

# Trend glyphs. A change smaller than the metric's own threshold reads as
# "flat" rather than being dramatised into a direction.
TREND_UP, TREND_DOWN, TREND_FLAT = "▲", "▼", "–"

# Measured, not guessed (see the 2026-08-23 QML vitals fix-wave report):
# ui/qml/VitalsPanel.qml's root implicitHeight, read offscreen via a
# QQuickWidget with the same four VitalStatModel context properties this
# panel wires up. 128px with no active force glyphs, 137px with Approval's
# ForceGlyph showing a tick (the tallest valid state, since ForceGlyph is the
# only row whose height varies and only Approval ever gets forces=). Fixed
# per CLAUDE.md's "nothing on the dashboard may change size" rule -- this is
# the correct constant for that rule, not a placeholder guess.
VITALS_PANEL_HEIGHT = 137


def _section_title(text: str) -> QLabel:
    lbl = QLabel(text)
    lbl.setStyleSheet(
        f"color: {theme.INK_FAINT}; font-size: {theme.FONT_SIZE_SM}pt; "
        f"letter-spacing: 1.6px; font-weight: 600; padding-top: 2px;")
    return lbl


def _divider() -> QFrame:
    line = QFrame()
    line.setFrameShape(QFrame.HLine)
    line.setStyleSheet(f"color: {theme.PANEL_EDGE}; background: {theme.PANEL_EDGE};")
    line.setFixedHeight(1)
    return line


class _EconRow(QWidget):
    """One label/value line in the economy table: no bar, a coloured figure,
    and a small glyph for which way it moved."""

    clicked = Signal(str)

    def __init__(self, label: str, metric_name: str = None, parent=None):
        super().__init__(parent)
        self._metric_name = metric_name
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 1, 0, 1)
        layout.setSpacing(6)

        self._key = QLabel(label)
        self._key.setStyleSheet(
            f"color: {theme.INK_DIM}; font-size: {theme.FONT_SIZE_PT}pt;")
        self._value = QLabel("—")
        self._value.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self._trend = QLabel("")
        self._trend.setFixedWidth(14)
        self._trend.setAlignment(Qt.AlignCenter)

        layout.addWidget(self._key)
        layout.addStretch(1)
        layout.addWidget(self._value)
        layout.addWidget(self._trend)

        if metric_name is not None:
            self.setCursor(Qt.PointingHandCursor)
            self.setToolTip(f"Click for why {metric_name} is what it is")

    def mousePressEvent(self, event):
        if self._metric_name is not None:
            self.clicked.emit(self._metric_name)

    def set_value(self, text: str, color: str, trend: str = TREND_FLAT,
                  trend_good: bool = None):
        self._value.setText(text)
        self._value.setStyleSheet(
            f"color: {color}; font-size: {theme.FONT_SIZE_PT}pt; font-weight: 600;")
        if trend == TREND_FLAT:
            trend_color = theme.INK_FAINT
        elif trend_good is None:
            trend_color = theme.INK_DIM
        else:
            trend_color = theme.GOOD if trend_good else theme.BAD
        self._trend.setText(trend)
        self._trend.setStyleSheet(
            f"color: {trend_color}; font-size: {theme.FONT_SIZE_SM}pt;")


class LeftPanel(QWidget):
    metric_clicked = Signal(str)   # emits a metric name that has a breakdown

    def __init__(self, state, parent=None):
        super().__init__(parent)
        self.setObjectName("LeftPanel")
        self.setFixedWidth(268)
        self.setStyleSheet(
            f"QWidget#LeftPanel {{ background: {theme.PANEL_BG}; "
            f"border: 1px solid {theme.PANEL_EDGE}; border-radius: 8px; }}")

        # Trend needs a "last month" to compare against, and refresh() runs on
        # every action rather than only at month end — so the comparison point
        # is snapshotted per turn, not per repaint. Purely presentational: the
        # engine is not asked to remember anything.
        self._prev = {}
        self._pending = {}
        self._prev_turn = None

        layout = QVBoxLayout(self)
        layout.setContentsMargins(15, 10, 15, 10)
        layout.setSpacing(2)

        # ── Tier 1: the three that decide whether you survive ─────────────
        # QML-hosted (see DESIGN.md) — the only place the modifier-visibility
        # force-glyph currently applies is Approval, which is why only its
        # model is built with a metric_name that has no corresponding
        # ui/explain.py breakdown. Stability and Pol. Capital DO have real
        # breakdowns (ui/explain.py: BREAKDOWNS) and must keep their
        # metric_name to keep the ⓘ / click-to-explain affordance the old
        # Widgets VitalStat gave them — explainable (click/ⓘ) and forces (the
        # glyph) are independent; only Approval ever passes forces=.
        self._approval_model = VitalStatModel("Approval", metric_name="Approval")
        self._stability_model = VitalStatModel("Stability", metric_name="Stability")
        self._pc_model = VitalStatModel("Political capital", metric_name="Pol. Capital")
        self._attention_model = VitalStatModel("Attention")
        for model in (self._approval_model, self._stability_model,
                      self._pc_model, self._attention_model):
            model.clicked.connect(self.metric_clicked)

        self._role_title = _section_title("YOUR GOVERNMENT")
        layout.addWidget(self._role_title)
        layout.addSpacing(4)

        self._vitals_quick = QQuickWidget()
        self._vitals_quick.setResizeMode(QQuickWidget.ResizeMode.SizeRootObjectToView)
        # Measured, not guessed: VITALS_PANEL_HEIGHT below is the QML root's
        # own implicitHeight once loaded (see the constant's comment). Set
        # immediately after setSource so there's no visible 0-height flash,
        # then reconciled against the real root object below in case a
        # future content change shifts it — "nothing on the dashboard may
        # change size" (CLAUDE.md) means the WIDGET's height still has to be
        # a fixed number, it just has to be the right one.
        self._vitals_quick.setFixedHeight(VITALS_PANEL_HEIGHT)
        ctx = self._vitals_quick.rootContext()
        ctx.setContextProperty("approvalModel", self._approval_model)
        ctx.setContextProperty("stabilityModel", self._stability_model)
        ctx.setContextProperty("pcModel", self._pc_model)
        ctx.setContextProperty("attentionModel", self._attention_model)
        qml_path = str(app_paths.resource_path("ui/qml/VitalsPanel.qml"))
        self._vitals_quick.setSource(QUrl.fromLocalFile(qml_path))
        root_obj = self._vitals_quick.rootObject()
        if root_obj is not None:
            measured = int(root_obj.property("implicitHeight"))
            if measured > 0:
                self._vitals_quick.setFixedHeight(measured)
        layout.addWidget(self._vitals_quick)

        # ── Tier 2: the economy, as figures ───────────────────────────────
        layout.addSpacing(2)
        layout.addWidget(_divider())
        layout.addSpacing(4)
        layout.addWidget(_section_title("ECONOMY"))
        layout.addSpacing(2)

        def _row(label: str, metric_name: str) -> _EconRow:
            row = _EconRow(label, metric_name if explain.has_breakdown(metric_name) else None)
            if explain.has_breakdown(metric_name):
                row.clicked.connect(self.metric_clicked)
            return row

        self._r_growth = _row("Growth", "Growth")
        self._r_unemp  = _row("Unemployment", "Unemployment")
        self._r_infl   = _row("Inflation", "Inflation")
        self._r_debt   = _row("Debt / GDP", "Debt / GDP")
        self._r_budget = _row("Budget", "Budget")
        for row in (self._r_growth, self._r_unemp, self._r_infl,
                    self._r_debt, self._r_budget):
            layout.addWidget(row)

        # ── Tier 3: everything else, folded away ──────────────────────────
        layout.addSpacing(4)
        self._more_btn = QToolButton()
        self._more_btn.setText("More indicators")
        self._more_btn.setCheckable(True)
        self._more_btn.setChecked(False)
        self._more_btn.setArrowType(Qt.RightArrow)
        self._more_btn.setToolButtonStyle(Qt.ToolButtonTextBesideIcon)
        self._more_btn.setStyleSheet(
            f"QToolButton {{ background: transparent; border: none; "
            f"color: {theme.INK_FAINT}; font-size: {theme.FONT_SIZE_SM}pt; "
            f"padding: 4px 0; }}"
            f"QToolButton:hover {{ color: {theme.INK_DIM}; }}")
        self._more_btn.toggled.connect(self._toggle_more)
        layout.addWidget(self._more_btn)

        self._more = QWidget()
        more_layout = QVBoxLayout(self._more)
        more_layout.setContentsMargins(0, 2, 0, 0)
        more_layout.setSpacing(0)
        self._r_gdp     = _EconRow("GDP")
        self._r_revenue = _EconRow("Revenue")
        self._r_spend   = _EconRow("Spending")
        self._r_wforce  = _row("Workforce quality", "Workforce Q.")
        self._r_bureau  = _row("Bureaucracy", "Bureaucracy")
        self._r_debtsvc = _EconRow("Debt service")
        for row in (self._r_gdp, self._r_revenue, self._r_spend,
                    self._r_wforce, self._r_bureau, self._r_debtsvc):
            more_layout.addWidget(row)
        self._more.hide()
        layout.addWidget(self._more)

        layout.addStretch(1)
        self.refresh(state)

    def _toggle_more(self, shown: bool):
        self._more.setVisible(shown)
        self._more_btn.setArrowType(Qt.DownArrow if shown else Qt.RightArrow)

    # ── Trend bookkeeping ────────────────────────────────────────────────

    def _trend(self, key: str, value: float, epsilon: float,
               higher_is_better: bool):
        """Direction of travel since the previous month, plus whether that
        direction is good news for this particular metric."""
        previous = self._prev.get(key)
        if previous is None or abs(value - previous) < epsilon:
            return TREND_FLAT, None
        rising = value > previous
        return (TREND_UP if rising else TREND_DOWN), (rising == higher_is_better)

    def _roll_snapshot(self, state, values: dict):
        """Advance the comparison point once per turn, not once per repaint."""
        if self._prev_turn != state.turn:
            if self._prev_turn is not None:
                self._prev = dict(self._pending)
            self._prev_turn = state.turn
        self._pending = values
        if not self._prev:
            self._prev = dict(values)

    # ── Refresh ──────────────────────────────────────────────────────────

    def refresh(self, state):
        p = state.player
        econ = state.country.economy

        values = {
            "growth": econ.growth_rate,
            "unemployment": econ.unemployment,
            "inflation": econ.inflation,
            "debt": econ.public_debt_pct,
            "budget": econ.budget.balance,
        }
        self._roll_snapshot(state, values)

        self._role_title.setText(
            "YOUR GOVERNMENT" if p.in_government else "YOUR OPPOSITION")
        # Reactive relabel (Stability -> "Gov. stability" while in
        # opposition) via VitalStatModel.set_label, so the opposition cue
        # the old VitalStat.set_label gave isn't silently lost.
        self._stability_model.set_label(
            "Stability" if p.in_government else "Gov. stability")

        self._approval_model.refresh_from(
            p.approval, f"{p.approval*100:.0f}%",
            theme.lerp_status_color(p.approval),
            forces=modifier_glyph.approval_forces(state))
        self._stability_model.refresh_from(
            state.stability.value, f"{state.stability.value*100:.0f}%",
            theme.lerp_status_color(state.stability.value),
            qualifier=state.stability.label())
        self._pc_model.refresh_from(
            p.political_capital / 100.0, f"{p.political_capital:.0f}",
            theme.lerp_status_color(p.political_capital / 100.0))

        from engine import player_ops as ops
        left = ops.attention_remaining(state)
        total = ops.MONTHLY_ATTENTION
        self._attention_model.refresh_from(
            left / max(1, total), f"{left} / {total}",
            theme.lerp_status_color(left / max(1, total)),
            qualifier=("committed" if left == 0 else "this month"),
            qualifier_color=theme.CRITICAL if left == 0 else None)

        growth_frac = max(0.0, min(1.0, (econ.growth_rate + 0.05) / 0.13))
        trend, good = self._trend("growth", econ.growth_rate, 0.0005, True)
        self._r_growth.set_value(f"{econ.growth_rate*100:+.1f}%",
                                 theme.lerp_status_color(growth_frac), trend, good)

        unemp_frac = max(0.0, min(1.0, econ.unemployment / 0.30))
        trend, good = self._trend("unemployment", econ.unemployment, 0.0005, False)
        self._r_unemp.set_value(
            f"{econ.unemployment*100:.1f}%",
            theme.lerp_status_color(unemp_frac, higher_is_better=False), trend, good)

        infl_frac = max(0.0, min(1.0, econ.inflation / 0.15))
        trend, good = self._trend("inflation", econ.inflation, 0.0005, False)
        self._r_infl.set_value(
            f"{econ.inflation*100:.1f}%",
            theme.lerp_status_color(infl_frac, higher_is_better=False), trend, good)

        debt_frac = max(0.0, min(1.0, econ.public_debt_pct / 1.5))
        trend, good = self._trend("debt", econ.public_debt_pct, 0.002, False)
        self._r_debt.set_value(
            f"{econ.public_debt_pct*100:.0f}%",
            theme.lerp_status_color(debt_frac, higher_is_better=False), trend, good)

        bal = econ.budget.balance
        trend, good = self._trend("budget", bal, 1.0, True)
        self._r_budget.set_value(
            f"{bal:+,.0f} M", theme.GOOD if bal >= 0 else theme.CRITICAL, trend, good)

        self._r_gdp.set_value(f"{econ.gdp:,.0f} M", theme.INK)
        self._r_revenue.set_value(f"{econ.budget.revenue:,.0f} M", theme.INK)
        self._r_spend.set_value(f"{econ.budget.expenditure:,.0f} M", theme.INK)
        self._r_wforce.set_value(
            f"{econ.workforce_quality:.2f}",
            theme.lerp_status_color(econ.workforce_quality))
        self._r_bureau.set_value(
            f"{state.country.bureaucratic_capacity:.2f}",
            theme.lerp_status_color(state.country.bureaucratic_capacity))
        if econ.loans:
            self._r_debtsvc.set_value(
                f"{econ.total_debt_service():+,.0f} M/yr", theme.BAD)
            self._r_debtsvc.show()
        else:
            self._r_debtsvc.hide()
