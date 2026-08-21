"""
Dialogs: TurnSummaryDialog (monthly before/after report), DispatchDetailDialog
(why a dispatch happened), MetricBreakdownDialog (approval/stability inputs),
ElectionResultsDialog (turnout, votes → seats, government formed), and
EventDialog — the only mutating one: option choices route through the owning
window's _run_op, the same path as every other player action.
"""

from PySide6.QtWidgets import QDialog, QVBoxLayout, QHBoxLayout, QLabel, QPushButton
from PySide6.QtCore import Qt

from content.dispatches import MARKERS
from ui import theme
from ui import explain
from ui.widgets_common import (section_title, divider, body_label, KeyValueRow,
                               MiniBar, ScrollColumn)
from ui.widgets_assembly import SeatArcWidget


def snapshot_metrics(state) -> dict:
    """Capture the headline numbers for a before/after comparison. Called by
    the window immediately before advancing a turn."""
    econ = state.country.economy
    return {
        "GDP": econ.gdp,
        "Growth": econ.growth_rate,
        "Inflation": econ.inflation,
        "Unemployment": econ.unemployment,
        "Approval": state.player.approval,
        "Stability": state.stability.value,
        "Political Capital": state.player.political_capital,
        "Debt/GDP": econ.public_debt_pct,
    }


def _delta_arrow(delta: float, higher_is_better: bool = True) -> tuple:
    """Returns (arrow, color) for a delta."""
    if abs(delta) < 1e-9:
        return "—", theme.INK_DIM
    up = delta > 0
    good = up if higher_is_better else not up
    arrow = "▲" if up else "▼"
    return arrow, (theme.GOOD if good else theme.BAD)


class TurnSummaryDialog(QDialog):
    # Which metrics read as "higher is better" for colouring deltas.
    _HIGHER_BETTER = {
        "GDP": True, "Growth": True, "Inflation": False, "Unemployment": False,
        "Approval": True, "Stability": True, "Political Capital": True, "Debt/GDP": False,
    }
    _FORMAT = {
        "GDP": lambda v: f"{v:,.0f} M",
        "Growth": lambda v: f"{v*100:+.2f}%",
        "Inflation": lambda v: f"{v*100:.2f}%",
        "Unemployment": lambda v: f"{v*100:.2f}%",
        "Approval": lambda v: f"{v*100:.1f}%",
        "Stability": lambda v: f"{v:.3f}",
        "Political Capital": lambda v: f"{v:.0f}",
        "Debt/GDP": lambda v: f"{v*100:.1f}%",
    }
    _DELTA_FORMAT = {
        "GDP": lambda d: f"{d:+,.0f} M",
        "Growth": lambda d: f"{d*100:+.2f} pp",
        "Inflation": lambda d: f"{d*100:+.2f} pp",
        "Unemployment": lambda d: f"{d*100:+.2f} pp",
        "Approval": lambda d: f"{d*100:+.1f} pp",
        "Stability": lambda d: f"{d:+.3f}",
        "Political Capital": lambda d: f"{d:+.0f}",
        "Debt/GDP": lambda d: f"{d*100:+.1f} pp",
    }

    def __init__(self, state, before, after, parent=None):
        super().__init__(parent)
        from engine import press
        page = press.front_page(state, before, after)

        self.setWindowTitle(f"{page['masthead']} — {page['dateline']}")
        self.setMinimumSize(520, 580)
        self.setStyleSheet(theme.stylesheet())

        root = QVBoxLayout(self)
        root.setContentsMargins(14, 12, 14, 12)
        root.setSpacing(8)

        masthead = QLabel(page["masthead"].upper())
        masthead.setAlignment(Qt.AlignHCenter)
        masthead.setStyleSheet(
            f"color: {theme.ACCENT}; font-size: {theme.FONT_SIZE_LG + 3}pt; "
            f"letter-spacing: 3px; font-weight: bold;")
        root.addWidget(masthead)
        dateline = QLabel(f"—  {page['dateline']}  ·  price 2 crowns  —")
        dateline.setAlignment(Qt.AlignHCenter)
        dateline.setStyleSheet(f"color: {theme.INK_DIM}; font-size: {theme.FONT_SIZE_SM}pt;")
        root.addWidget(dateline)
        root.addWidget(divider())

        col = ScrollColumn()
        root.addWidget(col, stretch=1)
        body = col.body

        lead_head = QLabel(page["lead"]["headline"])
        lead_head.setWordWrap(True)
        lead_head.setStyleSheet(
            f"color: {theme.INK}; font-size: {theme.FONT_SIZE_LG + 1}pt; font-weight: bold;")
        body.addWidget(lead_head)
        if page["lead"]["body"]:
            body.addWidget(body_label(page["lead"]["body"]))

        if page["headlines"]:
            body.addWidget(divider())
            for h in page["headlines"]:
                hl = QLabel(f"▪ {h}")
                hl.setWordWrap(True)
                hl.setStyleSheet(f"color: {theme.INK}; font-size: {theme.FONT_SIZE_PT}pt; "
                                 f"font-weight: bold;")
                body.addWidget(hl)

        if page["briefs"]:
            body.addWidget(divider())
            body.addWidget(section_title("IN BRIEF"))
            for d in page["briefs"]:
                body.addWidget(body_label(f"• {d}", dim=True, small=True))

        if page["numbers"]:
            nb_before, nb_after = page["numbers"]
            body.addWidget(divider())
            body.addWidget(section_title("THE NUMBERS"))
            for key in nb_before:
                old, new = nb_before[key], nb_after[key]
                delta = new - old
                hb = self._HIGHER_BETTER.get(key, True)
                arrow, color = _delta_arrow(delta, hb)
                val_str = self._FORMAT[key](new)
                delta_str = self._DELTA_FORMAT[key](delta) if abs(delta) > 1e-9 else "no change"
                body.addWidget(KeyValueRow(f"{key}", f"{val_str}   {arrow} {delta_str}", color))

        body.addStretch(1)


class DispatchDetailDialog(QDialog):
    def __init__(self, dispatch_text, state, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Dispatch")
        self.setMinimumSize(440, 320)
        self.setStyleSheet(theme.stylesheet())

        root = QVBoxLayout(self)
        root.setContentsMargins(14, 12, 14, 12)
        root.setSpacing(8)

        header = QLabel("DISPATCH")
        header.setStyleSheet(
            f"color: {theme.ACCENT}; font-size: {theme.FONT_SIZE_LG}pt; letter-spacing: 1px;")
        root.addWidget(header)
        root.addWidget(divider())

        root.addWidget(body_label(dispatch_text))

        # Explain WHY, keyed off the dispatch's structured type.
        why = self._explain(dispatch_text, state)
        if why:
            root.addWidget(divider())
            root.addWidget(section_title("WHY THIS HAPPENED"))
            for line in why:
                root.addWidget(body_label(f"• {line}", small=True))

        root.addStretch(1)

    # Why each KIND of dispatch happens. Keyed by dispatch key (the type
    # recorded in GameState.turn_news), never by loose English words in the
    # rendered text — "loan" or "election" can appear in unrelated prose.
    _EXPLANATIONS = {
        "scandal": ["An ambitious minister with low loyalty broke with the government.",
                    "Cabinet dysfunction and low stability raise this risk each month."],
        "minister_restless": ["A minister's ambition has outgrown their loyalty.",
                              "Left in post, they may resign in scandal — replace or placate them."],
        "protest": ["Civil unrest crossed the threshold that triggers protests.",
                    "Unrest is driven by faction grievances and high unemployment."],
        "confidence_vote": ["Government stability fell low enough for the opposition to strike,",
                            "or the vote was called deliberately."],
        "election": ["Either the parliamentary term elapsed, or the coalition collapsed,",
                     "forcing the country to the polls."],
        "election_winner_quote": ["The new governing party is claiming its mandate."],
        "vote_passed": ["The chamber's factions voted according to their stake in the bill",
                        "and their loyalty — see the Policies page for projections."],
        "vote_failed": ["The chamber's factions voted according to their stake in the bill",
                        "and their loyalty — see the Policies page for projections."],
        "vote_rebellion": ["A party wing broke with its own leadership over this bill.",
                           "Wings vote their own ideology when a bill sits far from them."],
        "vote_reaction_pleased": ["A party with a direct stake in the bill got what it wanted."],
        "vote_reaction_angry": ["A party with a direct stake in the bill lost the vote."],
        "exec_order": ["Enacted by decree, bypassing the chamber — at a cost in trust",
                       "with every faction outside the coalition."],
        "law_repealed": ["A standing law was struck down; its ongoing effects lapse and the",
                         "governing overhead it consumed is freed."],
        "wing_takeover": ["A party's internal balance shifted; a different wing now leads it.",
                          "Wings drift with the political climate — hard times favour extremes."],
        "leader_ousted": ["A restless wing took the party and removed its leader."],
        "world_trade_pact": ["A trade treaty was signed; volume and growth build over time,",
                             "up to a ceiling set by how warm the relationship is."],
        "defense_pact": ["A mutual-defense pact deters hostile moves against its members."],
        "sanctions_imposed": ["Sanctions cut trade dead and bleed the target's economy monthly."],
        "sanctions_lifted": ["The sanctions regime ended; trade must rebuild from nothing."],
        "summit": ["A bilateral summit — a deliberate investment in one relationship."],
        "treaty_broken": ["A standing treaty was torn up; the counterparty will remember it."],
        "world_deliberates": ["A foreign government is weighing a move. Plans mature over a",
                              "few months before they are acted on."],
        "world_axis": ["Two powers grew close enough, with trade behind it, to move as one."],
        "world_feud": ["Two powers fell far enough apart for the quarrel to harden."],
        "civil_war_out": ["Grievances, instability, and hostile factions pushed the civil-war",
                          "gauge past its threshold."],
        "civil_war_ongoing": ["An active civil war bleeds the economy and stability monthly",
                              "until the underlying conditions improve."],
        "civil_war_end": ["Conditions recovered enough for the fighting to subside."],
        "situation": ["A situation fired from the event pool — its conditions were met.",
                      "Unaddressed situations auto-resolve to their default option."],
        "situation_lapsed": ["The situation went unaddressed, so its default option happened."],
        "background_move": ["Your character's own background gave you this lever."],
        "rival_jibe": ["The strongest hostile party's leader is capitalising on a stumble."],
        "modifier_expired": ["A long-term effect finished its lifecycle and stopped applying."],
    }

    def _dispatch_key(self, text, state):
        """The structured type of this dispatch: an exact match in this turn's
        news if it's still there, else the MARKERS table (stable per-type
        keywords, matched longest-first so the most specific type wins)."""
        for key, _fields, txt in reversed(state.turn_news):
            if txt == text:
                return key
        lowered = text.lower()
        for key, marker in sorted(MARKERS.items(), key=lambda kv: -len(kv[1])):
            if "{" in marker:            # placeholder-marker: never in rendered text
                continue
            if marker.lower() in lowered:
                return key
        for key, prefix in (("situation_lapsed", "SITUATION LAPSED"),
                            ("situation_resolved", "SITUATION RESOLVED"),
                            ("situation", "SITUATION"),
                            ("confidence_vote", "CONFIDENCE VOTE"),
                            ("election", "ELECTION")):
            if prefix.lower() in lowered:
                return key
        return None

    def _explain(self, text, state):
        key = self._dispatch_key(text, state)
        out = list(self._EXPLANATIONS.get(key, []))
        # A couple of types earn live numbers on top of the static reason.
        if key == "protest":
            out.append(f"Current unemployment: {state.country.economy.unemployment*100:.1f}%.")
        elif key == "economy_move":
            effects = explain.economic_effects(state).get("inflation", [])
            out.append("The economy moved with growth, its structural baseline, and any")
            out.append("long-term effects currently in motion.")
            for src, val in effects:
                out.append(f"{src}: {val*100:+.2f}% inflation contribution.")
        return out


class MetricBreakdownDialog(QDialog):
    def __init__(self, metric_name, state, parent=None):
        super().__init__(parent)
        self.setWindowTitle(f"{metric_name} — Breakdown")
        self.setMinimumSize(440, 400)
        self.setStyleSheet(theme.stylesheet())

        root = QVBoxLayout(self)
        root.setContentsMargins(14, 12, 14, 12)
        root.setSpacing(8)

        header = QLabel(f"{metric_name.upper()} — WHY")
        header.setStyleSheet(
            f"color: {theme.ACCENT}; font-size: {theme.FONT_SIZE_LG}pt; letter-spacing: 1px;")
        root.addWidget(header)
        root.addWidget(divider())

        col = ScrollColumn()
        root.addWidget(col, stretch=1)
        body = col.body

        # ui/explain.py owns which metrics can explain themselves; the left
        # panel reads the same registry to decide where to show the affordance.
        data = explain.breakdown_for(metric_name, state)

        if data is None:
            body.addWidget(body_label("No breakdown available for this metric.", dim=True))
        else:
            # Each breakdown supplies its own formatters (percent, PC, M) so
            # figures read in their natural units instead of raw fractions.
            default_pct = metric_name in ("Approval", "Stability")
            value_fmt = data.get(
                "value_fmt",
                (lambda v: f"{v*100:.1f}%") if default_pct else (lambda v: f"{v:.3f}"))
            row_fmt = data.get("row_fmt", lambda v: f"{v:+.3f}")

            body.addWidget(KeyValueRow("Current", value_fmt(data["current"])))
            if data.get("target") is not None:
                body.addWidget(KeyValueRow("Trending toward", value_fmt(data["target"])))
            body.addWidget(divider())
            body.addWidget(section_title("CONTRIBUTIONS"))
            for label, contribution in data["rows"]:
                bar = MiniBar(label)
                bar.set_contribution(contribution, row_fmt(contribution))
                body.addWidget(bar)
            if data.get("sub_economic"):
                body.addWidget(divider())
                body.addWidget(section_title("ECONOMIC SIGNAL DETAIL"))
                for label, contribution in data["sub_economic"]:
                    bar = MiniBar(label)
                    bar.set_contribution(contribution, row_fmt(contribution))
                    body.addWidget(bar)
            if data.get("footer"):
                body.addWidget(divider())
                body.addWidget(body_label(data["footer"], dim=True, small=True))

        body.addStretch(1)


class EventDialog(QDialog):
    """
    A pending situation (engine/events.py) awaiting a player choice. Each
    option shows its political-capital cost up front, mirroring the cost
    transparency the menu pages already give the GUI over the terminal.

    `on_action` is the owning window's _run_op — same path every other
    action takes, so choosing here produces a dispatch and a refresh
    exactly like anything from the Policies/Cabinet/Diplomacy pages.
    """
    def __init__(self, event, on_action, state=None, parent=None):
        super().__init__(parent)
        # NOT self.event — QDialog already has a Qt-internal event() method;
        # shadowing it with an EventDef breaks Qt's own event dispatch.
        self._event = event
        self.on_action = on_action
        # Options gated by identity (background/ideology) are hidden when the
        # player doesn't qualify.
        if state is not None:
            from engine import events as _events
            self._options = _events.available_options(state, event)
        else:
            self._options = list(event.options)
        self.setWindowTitle(event.title)
        self.setMinimumSize(560, 440)
        self.setStyleSheet(theme.stylesheet())

        root = QVBoxLayout(self)
        root.setContentsMargins(14, 12, 14, 12)
        root.setSpacing(10)

        context = "GOVERNMENT DECISION" if (state is None or state.player.in_government) \
            else "OPPOSITION DECISION"
        eyebrow = QLabel(f"{context}  ·  {event.category.upper()}")
        eyebrow.setStyleSheet(
            f"color: {theme.ACCENT}; font-size: {theme.FONT_SIZE_SM}pt; "
            f"font-weight: 600; letter-spacing: 1px;")
        root.addWidget(eyebrow)

        header = QLabel(event.title)
        header.setStyleSheet(
            f"color: {theme.INK}; font-size: {theme.FONT_SIZE_LG}pt; font-weight: 600;")
        root.addWidget(header)
        root.addWidget(divider())
        root.addWidget(body_label(event.description))
        root.addWidget(divider())
        root.addWidget(section_title("HOW DO YOU RESPOND?"))

        col = ScrollColumn()
        root.addWidget(col, stretch=1)
        for option in self._options:
            cost_str = f"{option.pc_cost:.0f} PC" if option.pc_cost else "free"
            btn = QPushButton(f"{option.label}    ·    {cost_str}")
            btn.setStyleSheet(
                f"QPushButton {{ text-align: left; background: {theme.PANEL_RAISED}; "
                f"border: 1px solid {theme.PANEL_EDGE}; border-radius: 5px; "
                f"padding: 9px 12px; font-weight: 600; }} "
                f"QPushButton:hover {{ background: {theme.ACCENT_SOFT}; "
                f"border-color: {theme.ACCENT}; }}")
            btn.clicked.connect(lambda checked=False, oid=option.id: self._choose(oid))
            col.body.addWidget(btn)
            col.body.addWidget(body_label(option.description, dim=True, small=True))
        col.body.addStretch(1)

        defer_btn = QPushButton("Decide later")
        defer_btn.clicked.connect(self.reject)
        root.addWidget(defer_btn)

    def _choose(self, option_id: str):
        from engine import player_ops
        self.on_action(lambda st: player_ops.op_resolve_event(st, self._event.id, option_id))
        self.accept()


class _ResultRow(QLabel):
    """One party's line in the election results: colour swatch + name on the
    left, votes/share → seats/share on the right."""
    def __init__(self, color, name, stats, stats_color, parent=None):
        super().__init__(parent)
        self.setTextFormat(Qt.RichText)
        swatch = (f"<span style='color:{color};'>&#9632;</span>")  # ■
        self.setText(
            f"{swatch} {name}"
            f"<span style='color:{theme.INK_DIM};'> &nbsp;—&nbsp; </span>"
            f"<span style='color:{stats_color};'>{stats}</span>")
        self.setStyleSheet(f"color: {theme.INK}; font-size: {theme.FONT_SIZE_SM}pt;")


class ElectionResultsDialog(QDialog):
    """
    Read-only breakdown of an election that just resolved: national turnout,
    the new seat composition (same hemicycle as the bottom strip), and a
    party-by-party line of votes → seats, then the government that formed.
    Reads a stored ElectionResult so it can also be reopened later from the
    Game menu; the live `state` supplies party names, colours, and the arc.
    """
    def __init__(self, result, state, parent=None):
        super().__init__(parent)
        tag = "SNAP ELECTION" if result.was_snap_election else "GENERAL ELECTION"
        self.setWindowTitle(f"{tag} — {result.date}")
        self.setMinimumSize(620, 560)
        self.setStyleSheet(theme.stylesheet())

        colors = theme.assign_party_colors(state.country.factions)
        names = {f.id: f.name for f in state.country.factions}

        root = QVBoxLayout(self)
        root.setContentsMargins(14, 12, 14, 12)
        root.setSpacing(8)

        header = QLabel(f"{tag} — {result.date}")
        header.setStyleSheet(
            f"color: {theme.ACCENT}; font-size: {theme.FONT_SIZE_LG}pt; letter-spacing: 1px;")
        root.addWidget(header)

        # Turnout headline.
        turnout_lbl = QLabel(
            f"Turnout: {result.turnout_pct*100:.1f}%   "
            f"({result.total_votes_cast:,} of {result.eligible_voters:,} eligible voters)")
        turnout_lbl.setStyleSheet(f"color: {theme.INK}; font-size: {theme.FONT_SIZE_PT}pt;")
        root.addWidget(turnout_lbl)
        root.addWidget(divider())

        # New composition, drawn as the same hemicycle as the bottom strip.
        arc = SeatArcWidget()
        arc.setMinimumHeight(150)
        arc.set_data(state.country.factions, state.legislature.total_seats,
                     state.legislature.majority_threshold(), colors)
        root.addWidget(arc)

        col = ScrollColumn()
        root.addWidget(col, stretch=1)
        body = col.body

        body.addWidget(section_title("THE RESULT — VOTES → SEATS"))
        # Order parties by seats won, descending.
        ordered = sorted(result.final_seats.items(), key=lambda kv: -kv[1])
        for fid, seats in ordered:
            votes = result.votes_by_faction.get(fid, 0)
            vote_pct = result.vote_share_by_faction.get(fid, 0.0) * 100
            seat_pct = result.seat_pct_by_faction.get(fid, 0.0) * 100
            change = result.seat_changes.get(fid, 0)
            arrow = f"▲{change}" if change > 0 else (f"▼{abs(change)}" if change < 0 else "—")
            change_color = theme.GOOD if change > 0 else (theme.BAD if change < 0 else theme.INK_DIM)
            stats = (f"{votes:,} votes ({vote_pct:.1f}%)  →  "
                     f"{seats} seats ({seat_pct:.0f}%)  {arrow}")
            body.addWidget(_ResultRow(colors.get(fid, theme.NEUTRAL),
                                      names.get(fid, fid), stats, change_color))

        # Government formed.
        body.addWidget(divider())
        body.addWidget(section_title("GOVERNMENT FORMED"))
        ruling_name = names.get(result.ruling_faction_id, result.ruling_faction_id)
        partners = [names.get(fid, fid) for fid in result.coalition_faction_ids
                    if fid != result.ruling_faction_id]
        gov_line = f"{ruling_name} leads the government"
        if partners:
            gov_line += " with " + ", ".join(partners)
        body.addWidget(body_label(gov_line + "."))

        coalition_seats = sum(result.final_seats.get(fid, 0) for fid in result.coalition_faction_ids)
        majority = state.legislature.majority_threshold()
        ok = coalition_seats >= majority
        maj_lbl = KeyValueRow("Coalition seats", f"{coalition_seats} / {majority} needed",
                              theme.GOOD if ok else theme.CRITICAL)
        body.addWidget(maj_lbl)
        if not ok:
            body.addWidget(body_label("A minority government — it governs without a secured majority.",
                                      dim=True, small=True))

        # What it means for the player.
        if result.player_lost_office:
            verdict, vcolor = "You have LOST office. A new government forms without you.", theme.CRITICAL
        elif result.player_gained_office:
            verdict, vcolor = "You have RETURNED to office, forming a new government.", theme.GOOD
        elif result.player_in_government:
            verdict, vcolor = "Your government has been returned to power.", theme.GOOD
        else:
            verdict, vcolor = "You remain in opposition.", theme.INK_DIM
        body.addWidget(divider())
        verdict_lbl = QLabel(verdict)
        verdict_lbl.setWordWrap(True)
        verdict_lbl.setStyleSheet(f"color: {vcolor}; font-size: {theme.FONT_SIZE_PT}pt;")
        body.addWidget(verdict_lbl)

        body.addStretch(1)

        close_btn = QPushButton("Close")
        close_btn.clicked.connect(self.accept)
        root.addWidget(close_btn)
