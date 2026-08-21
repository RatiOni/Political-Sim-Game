"""
The menu-bar pages (Policies, Cabinet, Diplomacy, Briefing): read live state,
trigger ops via self.run_action, contain no simulation logic. Targets are
picked with dropdowns; costs are shown up front via the ops layer's cost_*
helpers.
"""

from PySide6.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QLabel,
                               QPushButton, QComboBox, QMessageBox)
from PySide6.QtCore import Qt

from ui import theme
from ui import explain
from ui.widgets_common import (PageDialog, section_title, divider, body_label,
                               KeyValueRow, MiniBar, banded, LOAD_RATIO_BANDS,
                               CONFIDENCE_BANDS)

from engine import player_ops as ops
from engine import (legislative, stability, domestic_ai, opposition,
                    budget as budget_engine, ministries as ministry_engine,
                    reforms as reform_engine, decision_queue, political_calendar,
                    opening_programme)
from models.cabinet import CORE_PORTFOLIOS
from content.regions import (ARDENIA_REGION_PROFILES, REGIONAL_ISSUES,
                             REGIONAL_PROGRAMS)
from content.budget import BUDGET_ENVELOPES, BUDGET_ADJUSTMENTS
from content.households import GROUP_BY_ID as HOUSEHOLD_GROUP_BY_ID


def _fmt_pc(cost: float) -> str:
    return "free" if cost <= 0 else f"{cost:.0f} PC"


def _action_row(label: str, cost_text: str, enabled: bool, on_click,
                state=None, attention_key: str = None) -> QWidget:
    """A button + cost label row used by the action sections.

    Pass `state` and `attention_key` for a major initiative
    (engine/player_ops.py: ATTENTION_OPS) and the row disables itself with a
    tooltip once the month's attention is spent — the requirement is that
    these read as DISABLED with a reason, never that they fail silently when
    pressed. The op itself still refuses independently; this is the visible
    half of the same rule, not a substitute for it.
    """
    row = QWidget()
    lay = QHBoxLayout(row)
    lay.setContentsMargins(0, 2, 0, 2)
    lay.setSpacing(8)
    btn = QPushButton(label)

    out_of_attention = (state is not None and attention_key is not None
                        and not ops.has_attention(state, attention_key))
    btn.setEnabled(enabled and not out_of_attention)
    if out_of_attention:
        btn.setToolTip(ops.ATTENTION_EXHAUSTED_REASON)
    btn.clicked.connect(on_click)

    shown_cost = "committed" if out_of_attention else cost_text
    cost = QLabel(shown_cost)
    cost.setStyleSheet(
        f"color: {theme.CRITICAL if out_of_attention else theme.INK_DIM}; "
        f"font-size: {theme.FONT_SIZE_SM}pt;")
    lay.addWidget(btn, stretch=1)
    lay.addWidget(cost)
    return row


# ═══════════════════════════════════════════════════════════════════════════
# POLICIES
# ═══════════════════════════════════════════════════════════════════════════

class PoliciesPage(PageDialog):
    def __init__(self, state, on_action=None, parent=None):
        super().__init__("Policies", state, on_action, parent)
        self.refresh()

    def refresh(self):
        self._budget_combos = {}
        self._budget_lobby_combo = None
        self._budget_forecast_label = None
        self._supp_combo = None
        self._supp_share_combo = None
        self.clear_content()
        b = self.content.body
        s = self.state

        in_gov = s.player.in_government
        if not in_gov:
            b.addWidget(body_label(
                "You are in opposition. The government controls the legislative calendar, "
                "but your party can support, oppose, or amend its proposals.", dim=True))
            b.addWidget(divider())

            # ── Government-in-waiting platform ──
            b.addWidget(section_title("YOUR ELECTION PLATFORM"))
            b.addWidget(KeyValueRow(
                "Platform credibility", f"{opposition.credibility(s)*100:.0f}%",
                theme.lerp_status_color(opposition.credibility(s))))
            agenda = opposition.pledges(s)
            if agenda:
                for pledge in agenda:
                    bill = opposition.bill_for_pledge(pledge)
                    if bill is None:
                        continue
                    speaker = opposition.spokesperson(s, bill)
                    voice = (f"{speaker.name} · effectiveness {speaker.implementation_quality():.2f}"
                             if speaker else f"no Shadow {opposition.agenda_portfolio(bill)} Minister")
                    b.addWidget(KeyValueRow(
                        bill.name,
                        f"{pledge.get('status', 'pledged')} · {pledge.get('campaigns', 0)} campaign(s)"))
                    b.addWidget(body_label(f"    spokesperson: {voice}", dim=True, small=True))
            else:
                b.addWidget(body_label(
                    "No signature promises yet. An opposition without a platform suffers a "
                    "small election-day turnout penalty.", dim=True, small=True))

            candidates = opposition.pledge_candidates(s)
            if candidates and len(agenda) < opposition.MAX_PLEDGES:
                self._pledge_candidate_combo = QComboBox()
                for bill in candidates:
                    self._pledge_candidate_combo.addItem(
                        f"{bill.name} · {bill.ideology.label() if bill.ideology else 'Pragmatic'}",
                        bill.id)
                add_row = QWidget(); ar = QHBoxLayout(add_row)
                ar.setContentsMargins(0, 0, 0, 0); ar.setSpacing(8)
                ar.addWidget(self._pledge_candidate_combo, stretch=1)
                add_btn = QPushButton("Add Pledge")
                add_btn.clicked.connect(self._do_add_pledge)
                ar.addWidget(add_btn)
                b.addWidget(add_row)

            if agenda:
                self._agenda_combo = QComboBox()
                for pledge in agenda:
                    bill = opposition.bill_for_pledge(pledge)
                    if bill:
                        left = opposition.campaign_cooldown_remaining(s, bill.id)
                        tag = f" · available in {left} mo" if left else ""
                        self._agenda_combo.addItem(f"{bill.name}{tag}", bill.id)
                b.addWidget(self._agenda_combo)
                pledge_actions = QWidget(); pal = QHBoxLayout(pledge_actions)
                pal.setContentsMargins(0, 0, 0, 0); pal.setSpacing(8)
                campaign_btn = QPushButton("Campaign on Pledge")
                campaign_btn.clicked.connect(self._do_campaign_pledge)
                drop_btn = QPushButton("Drop Pledge")
                drop_btn.clicked.connect(self._do_drop_pledge)
                pal.addWidget(campaign_btn, stretch=1)
                pal.addWidget(drop_btn)
                b.addWidget(pledge_actions)
                b.addWidget(body_label(
                    f"New pledge {_fmt_pc(ops.COST_ADD_PLEDGE)} · campaign "
                    f"{_fmt_pc(ops.COST_CAMPAIGN_PLEDGE)} · drop {_fmt_pc(ops.COST_DROP_PLEDGE)}",
                    dim=True, small=True))
            b.addWidget(divider())
        elif opposition.pledges(s):
            b.addWidget(section_title("GOVERNING MANDATE"))
            b.addWidget(KeyValueRow(
                "Manifesto credibility", f"{opposition.credibility(s)*100:.0f}%",
                theme.lerp_status_color(opposition.credibility(s))))
            for pledge in opposition.pledges(s):
                bill = opposition.bill_for_pledge(pledge)
                if bill:
                    b.addWidget(KeyValueRow(
                        bill.name, pledge.get("status", "pledged").upper()))
            b.addWidget(body_label(
                "These promises followed you into office. Introduce and pass them before "
                "the next election or face a manifesto penalty.", dim=True, small=True))
            b.addWidget(divider())

        # ── Reform design: objective stage ──
        b.addWidget(section_title("REFORM PROGRAMME"))
        project = s.reform_project
        if project is not None:
            objective = reform_engine.OBJECTIVE_BY_ID.get(project.objective_id, {})
            live_diagnosis = reform_engine.diagnose_objective(s, project.objective_id)
            b.addWidget(KeyValueRow(
                "Active objective", objective.get("name", project.objective_id),
                theme.ACCENT))
            b.addWidget(KeyValueRow(
                "Diagnosis at adoption",
                f"{reform_engine.urgency_label(project.diagnosis_score)} · "
                f"{project.diagnosis_score*100:.0f}%"))
            b.addWidget(KeyValueRow(
                "Current diagnosis",
                f"{reform_engine.urgency_label(live_diagnosis.get('score', 0.0))} · "
                f"{live_diagnosis.get('score', 0.0)*100:.0f}%"))
            pressures = reform_engine.leading_pressures(live_diagnosis)
            if pressures:
                b.addWidget(body_label(
                    "Main pressures: " + ", ".join(
                        f"{label} {value*100:.0f}%" for label, value in pressures),
                    dim=True, small=True))
            b.addWidget(body_label(
                "Objective selected. The next design stage will choose the instrument, "
                "scope and concessions before a bill is written.", dim=True, small=True))
        else:
            b.addWidget(body_label(
                "Choose the problem the programme exists to solve. Urgency is calculated "
                "from current economic, household, regional and administrative conditions.",
                dim=True, small=True))

        objectives = ops.reform_objectives(s)
        self._reform_combo = QComboBox()
        for objective in objectives:
            active = project is not None and project.objective_id == objective["id"]
            marker = "[ACTIVE] " if active else ""
            self._reform_combo.addItem(
                f"{marker}{objective['name']} · "
                f"{reform_engine.urgency_label(objective['score'])} "
                f"{objective['score']*100:.0f}%",
                objective["id"])
            if active:
                self._reform_combo.setCurrentIndex(self._reform_combo.count() - 1)
        if objectives:
            objective_row = QWidget(); ol = QHBoxLayout(objective_row)
            ol.setContentsMargins(0, 0, 0, 0); ol.setSpacing(8)
            ol.addWidget(self._reform_combo, stretch=1)
            objective_btn = QPushButton(
                "Change Objective" if project is not None else "Adopt Objective")
            objective_btn.clicked.connect(self._do_adopt_reform_objective)
            objective_btn.setEnabled(
                not (project is not None
                     and self._reform_combo.currentData() == project.objective_id))
            self._reform_combo.currentIndexChanged.connect(
                lambda _index, button=objective_btn, current=project:
                button.setEnabled(current is None
                                  or self._reform_combo.currentData() != current.objective_id))
            ol.addWidget(objective_btn)
            b.addWidget(objective_row)
            b.addWidget(body_label(
                f"Adopt {_fmt_pc(ops.COST_ADOPT_REFORM_OBJECTIVE)} · change direction "
                f"{_fmt_pc(ops.COST_REPLACE_REFORM_OBJECTIVE)}",
                dim=True, small=True))

        b.addWidget(divider())

        # ── Annual appropriations ──
        budget_engine.ensure_budget_state(s)
        active_budget = s.active_budget
        b.addWidget(section_title("ANNUAL BUDGET"))
        b.addWidget(KeyValueRow(
            f"{active_budget.year} appropriations",
            f"{active_budget.expenditure:,.0f} M · {active_budget.source.replace('_', ' ')}"))
        # Shares engine.digest.BUDGET_BALANCE_BANDS with the monthly digest,
        # so the two can never call the same balance two different things.
        from engine.digest import BUDGET_BALANCE_BANDS
        econ_budget = s.country.economy.budget
        balance_share = econ_budget.balance / max(1.0, econ_budget.revenue)
        balance_word, balance_color = banded(balance_share, BUDGET_BALANCE_BANDS)
        b.addWidget(KeyValueRow(
            "Current structural balance",
            f"{econ_budget.balance:+,.0f} M {balance_word}",
            balance_color))
        for item in BUDGET_ENVELOPES:
            b.addWidget(KeyValueRow(
                item["name"], f"{active_budget.allocations[item['id']]:,.0f} M"))

        plan = s.pending_budget
        if plan is not None and plan.status in ("proposed", "approved"):
            b.addWidget(body_label(
                f"{plan.year} proposal · {plan.status.upper()} · spending "
                f"{plan.expenditure:,.0f} M · forecast balance "
                f"{plan.forecast_balance:+,.0f} M", small=True))
            if plan.status == "proposed":
                vf, va, _ = budget_engine.projected_votes(s, plan)
                threshold = s.legislature.majority_threshold()
                b.addWidget(KeyValueRow(
                    "Projected vote", f"{vf}-{va} · need {threshold}",
                    theme.GOOD if vf >= threshold else theme.CRITICAL))
                for faction, wing, seats, direction in budget_engine.vote_rebellions(s, plan):
                    b.addWidget(body_label(
                        f"    ↳ {seats} {faction.name} rebels ({wing.name}) vote {direction}",
                        dim=True, small=True))
            else:
                b.addWidget(body_label(
                    "Parliament has approved this plan. It becomes the structural spending "
                    "baseline on 1 January.", dim=True, small=True))

        if in_gov and (plan is None or plan.status not in ("proposed", "approved")):
            b.addWidget(body_label(
                f"Draft {budget_engine.proposal_year(s)}. Changes are measured against the "
                "current envelope; laws and emergency costs remain separate.", dim=True, small=True))
            for item in BUDGET_ENVELOPES:
                row = QWidget(); rl = QHBoxLayout(row)
                rl.setContentsMargins(0, 1, 0, 1); rl.setSpacing(8)
                label = QLabel(item["name"])
                combo = QComboBox()
                for change in BUDGET_ADJUSTMENTS:
                    combo.addItem("No change" if change == 0 else f"{change:+.0%}", change)
                combo.setCurrentIndex(BUDGET_ADJUSTMENTS.index(0.0))
                self._budget_combos[item["id"]] = combo
                combo.currentIndexChanged.connect(self._refresh_budget_forecast)
                rl.addWidget(label, stretch=1); rl.addWidget(combo)
                b.addWidget(row)

            # A projection of the draft above, before it is ever tabled —
            # engine.budget.forecast() run against the live combo selections,
            # never the actual budget vote/commit path. Updated in place on
            # every combo change rather than through self.refresh(), which
            # would reset every combo back to "No change" mid-edit.
            self._budget_forecast_label = body_label("", dim=True, small=True)
            b.addWidget(self._budget_forecast_label)

            propose_budget = QPushButton("Table Annual Budget")
            propose_budget.clicked.connect(self._do_propose_budget)
            b.addWidget(propose_budget)
            self._refresh_budget_forecast()
        elif in_gov and plan is not None and plan.status == "proposed":
            self._budget_lobby_combo = QComboBox()
            for faction in [f for f in s.country.factions if f.seats > 0]:
                cost = ops.COST_BUDGET_LOBBY_BASE + faction.power * 6.0
                self._budget_lobby_combo.addItem(
                    f"Lobby {faction.name} ({_fmt_pc(cost)})", faction.id)
            lobby_row = QWidget(); ll = QHBoxLayout(lobby_row)
            ll.setContentsMargins(0, 0, 0, 0); ll.setSpacing(8)
            ll.addWidget(self._budget_lobby_combo, stretch=1)
            lobby_btn = QPushButton("Lobby")
            lobby_btn.clicked.connect(self._do_lobby_budget)
            ll.addWidget(lobby_btn); b.addWidget(lobby_row)
            vote_row = QWidget(); vl = QHBoxLayout(vote_row)
            vl.setContentsMargins(0, 0, 0, 0); vl.setSpacing(8)
            vote_btn = QPushButton("Call Budget Vote")
            vote_btn.clicked.connect(self._do_call_budget_vote)
            withdraw_btn = QPushButton("Withdraw for Revision")
            withdraw_btn.clicked.connect(self._do_withdraw_budget)
            vl.addWidget(vote_btn, stretch=1); vl.addWidget(withdraw_btn, stretch=1)
            b.addWidget(vote_row)
        elif not in_gov:
            b.addWidget(body_label(
                "The sitting government controls appropriations. Its enacted plan still changes "
                "the state's fiscal baseline while you organise in opposition.", dim=True, small=True))

        # ── Supplementary appropriation: mid-year fiscal room ──
        # The annual settlement is January-gated, so this is the only route to
        # money for a department that is visibly failing in April.
        supp_ok, supp_reason = ops.can_supplementary(s)
        if in_gov:
            b.addWidget(divider())
            b.addWidget(section_title("SUPPLEMENTARY APPROPRIATION"))
            if not supp_ok:
                b.addWidget(body_label(supp_reason, dim=True, small=True))
            else:
                already = budget_engine.supplementaries_this_year(s)
                cost = ops.cost_supplementary(s)
                b.addWidget(body_label(
                    f"In-year money for one department, capped at "
                    f"{budget_engine.SUPPLEMENTARY_CAP_FRACTION*100:.0f}% of its annual "
                    f"appropriation and put to a real chamber vote. Raises spending for the "
                    f"rest of {s.year} only — next year's baseline is untouched."
                    + (f" This would be number {already + 1} this fiscal year, at "
                       f"{cost:.0f} PC." if already else ""),
                    dim=True, small=True))
                self._supp_combo = QComboBox()
                for portfolio in CORE_PORTFOLIOS:
                    cap = budget_engine.supplementary_cap(s, portfolio)
                    ministry = s.ministries.get(portfolio)
                    condition = ministry.status_label().lower() if ministry else "unknown"
                    self._supp_combo.addItem(
                        f"{portfolio} — {condition}, up to {cap:,.0f} M", portfolio)
                b.addWidget(self._supp_combo)
                self._supp_share_combo = QComboBox()
                for label, fraction in (("A quarter of the cap", 0.25),
                                        ("Half the cap", 0.5),
                                        ("The full cap", 1.0)):
                    self._supp_share_combo.addItem(label, fraction)
                self._supp_share_combo.setCurrentIndex(2)
                b.addWidget(self._supp_share_combo)
                b.addWidget(_action_row(
                    "Move a Supplementary", _fmt_pc(cost), True,
                    self._do_supplementary, s, "supplementary_appropriation"))

        b.addWidget(divider())

        # ── Active laws ──
        b.addWidget(section_title("ACTIVE LEGISLATION"))
        if s.legislature.active_laws:
            for law in s.legislature.active_laws:
                b.addWidget(KeyValueRow(law.name, f"{law.tier} · month {law.turns_active}"))
        else:
            b.addWidget(body_label("No active laws.", dim=True, small=True))

        # ── Pending bills, with live vote projection ──
        b.addWidget(divider())
        b.addWidget(section_title("PENDING LEGISLATION"))
        if s.legislature.pending_bills:
            for bill in s.legislature.pending_bills:
                vf, va, _ = legislative.projected_votes(s, bill)
                thr = legislative.threshold_for(s, bill)
                verdict = "would PASS" if vf >= thr else "would FAIL"
                vcolor = theme.GOOD if vf >= thr else theme.CRITICAL
                row = KeyValueRow(bill.name, f"{vf}-{va} (need {thr}) · {verdict}", vcolor)
                b.addWidget(row)
                if bill.proposed_by and bill.proposed_by != "player":
                    sponsor = ops.faction_by_id(s, bill.proposed_by)
                    response = domestic_ai.response_for(s, bill.id)
                    detail = f"government sponsor: {sponsor.name if sponsor else bill.proposed_by}"
                    if response:
                        detail += f" · your position: {response.upper()}"
                    b.addWidget(body_label(f"    {detail}", dim=True, small=True))
                for fac, wing, seats, direction in legislative.vote_rebellions(s, bill):
                    b.addWidget(body_label(
                        f"    ↳ {seats} {fac.name} rebels ({wing.name}) vote {direction}",
                        dim=True, small=True))
                lobbied = ", ".join(sorted(bill.lobbying_bonus.keys()))
                if lobbied:
                    b.addWidget(body_label(f"    lobbied: {lobbied}", dim=True, small=True))
        else:
            b.addWidget(body_label("No bills awaiting a vote.", dim=True, small=True))

        # ── Long-term effects in motion ──
        b.addWidget(divider())
        b.addWidget(section_title("LONG-TERM EFFECTS IN MOTION"))
        if s.modifiers:
            for m in sorted(s.modifiers, key=lambda x: (x.source, x.target)):
                val = m.current_value()
                disp = (f"{val*100:+.2f}%" if m.target in
                        ("gdp_growth", "unemployment", "inflation", "approval_bias",
                         "workforce_quality", "bureaucratic_capacity")
                        else f"{val:+.0f}M")
                b.addWidget(KeyValueRow(f"{m.source} → {m.target}",
                                        f"{disp} · {m.phase_label()}"))
        else:
            b.addWidget(body_label("No long-term effects active.", dim=True, small=True))

        # ── Actions ──
        if in_gov:
            b.addWidget(divider())
            b.addWidget(section_title("ACTIONS"))

            # Propose bill: dropdown of proposable bills + propose button.
            proposable = ops.proposable_bills(s)
            self._bill_combo = QComboBox()
            pledged_ids = {p["bill_id"] for p in opposition.pledges(s)}
            for bill in proposable:
                mandate_tag = "[PLEDGED] " if bill.id in pledged_ids else ""
                self._bill_combo.addItem(
                    f"{mandate_tag}[{bill.tier[:4].upper()}] {bill.name} "
                    f"({_fmt_pc(ops.cost_propose(bill))})", bill.id)
            if proposable:
                combo_row = QWidget(); cl = QHBoxLayout(combo_row)
                cl.setContentsMargins(0, 0, 0, 0); cl.setSpacing(8)
                cl.addWidget(self._bill_combo, stretch=1)
                propose_btn = QPushButton("Propose")
                propose_btn.clicked.connect(self._do_propose)
                cl.addWidget(propose_btn)
                b.addWidget(combo_row)
                b.addWidget(body_label(
                    "Executive-order bills enact immediately; others go to a vote.",
                    dim=True, small=True))
            else:
                b.addWidget(body_label("No new bills available to propose.", dim=True, small=True))

            # Repeal: unwind a law you no longer want to pay for.
            self._repeal_combo = QComboBox()
            for law in s.legislature.active_laws:
                self._repeal_combo.addItem(
                    f"{law.name} ({_fmt_pc(ops.cost_repeal(law))})", law.id)
            if s.legislature.active_laws:
                repeal_row = QWidget(); rl = QHBoxLayout(repeal_row)
                rl.setContentsMargins(0, 0, 0, 0); rl.setSpacing(8)
                rl.addWidget(self._repeal_combo, stretch=1)
                repeal_btn = QPushButton("Repeal")
                repeal_btn.clicked.connect(self._do_repeal)
                rl.addWidget(repeal_btn)
                b.addWidget(repeal_row)

            # Pending-bill actions: lobby / call vote / withdraw.
            if s.legislature.pending_bills:
                self._pending_combo = QComboBox()
                for bill in s.legislature.pending_bills:
                    self._pending_combo.addItem(bill.name, bill.id)
                b.addWidget(self._pending_combo)

                self._lobby_combo = QComboBox()
                for f in [f for f in s.country.factions if f.seats > 0]:
                    self._lobby_combo.addItem(
                        f"Lobby {f.name} ({_fmt_pc(ops.cost_lobby(f))})", f.id)
                lobby_row = QWidget(); ll = QHBoxLayout(lobby_row)
                ll.setContentsMargins(0, 0, 0, 0); ll.setSpacing(8)
                ll.addWidget(self._lobby_combo, stretch=1)
                lobby_btn = QPushButton("Lobby")
                lobby_btn.clicked.connect(self._do_lobby)
                ll.addWidget(lobby_btn)
                b.addWidget(lobby_row)

                vote_row = QWidget(); vl = QHBoxLayout(vote_row)
                vl.setContentsMargins(0, 0, 0, 0); vl.setSpacing(8)
                call_btn = QPushButton("Call Vote")
                call_btn.clicked.connect(self._do_call_vote)
                withdraw_btn = QPushButton("Withdraw")
                withdraw_btn.clicked.connect(self._do_withdraw)
                vl.addWidget(call_btn, stretch=1)
                vl.addWidget(withdraw_btn, stretch=1)
                b.addWidget(vote_row)

        else:
            government_bill = ops.government_bill(s)
            if government_bill is not None:
                b.addWidget(divider())
                b.addWidget(section_title("OPPOSITION RESPONSE"))
                response = domestic_ai.response_for(s, government_bill.id)
                if response:
                    b.addWidget(body_label(
                        f"Your party has declared it will {response} {government_bill.name}. "
                        "The division will be held at the next sitting.", small=True))
                else:
                    b.addWidget(body_label(
                        f"The government has introduced {government_bill.name}. Choose one "
                        "position before the next sitting; your decision changes the vote and "
                        "your party's electoral posture.", small=True))
                    b.addWidget(_action_row(
                        "Support the Bill", _fmt_pc(ops.COST_SUPPORT_GOVERNMENT_BILL), True,
                        self._do_support_government_bill))
                    b.addWidget(_action_row(
                        "Oppose the Bill", _fmt_pc(ops.COST_OPPOSE_GOVERNMENT_BILL), True,
                        self._do_oppose_government_bill))
                    b.addWidget(_action_row(
                        "Negotiate an Amendment", _fmt_pc(ops.COST_AMEND_GOVERNMENT_BILL), True,
                        self._do_amend_government_bill))
            else:
                b.addWidget(divider())
                b.addWidget(section_title("OPPOSITION RESPONSE"))
                b.addWidget(body_label(
                    "No government bill is before the chamber. Use the intervening months to "
                    "campaign, court allies, and prepare for a confidence challenge.",
                    dim=True, small=True))

        b.addStretch(1)

    # ── Action handlers ──
    def _selected_pending(self):
        bid = self._pending_combo.currentData()
        return next((x for x in self.state.legislature.pending_bills if x.id == bid), None)

    def _do_propose(self):
        bid = self._bill_combo.currentData()
        bill = next((x for x in ops.proposable_bills(self.state) if x.id == bid), None)
        if bill:
            self.run_action(lambda st: ops.op_propose_bill(st, bill))

    def _do_adopt_reform_objective(self):
        objective_id = self._reform_combo.currentData()
        if objective_id:
            self.run_action(
                lambda st: ops.op_adopt_reform_objective(st, objective_id))

    def _do_repeal(self):
        law_id = self._repeal_combo.currentData()
        if law_id:
            self.run_action(lambda st: ops.op_repeal_law(st, law_id))

    def _do_lobby(self):
        bill = self._selected_pending()
        fid = self._lobby_combo.currentData()
        faction = ops.faction_by_id(self.state, fid)
        if bill and faction:
            self.run_action(lambda st: ops.op_lobby_faction(st, bill, faction))

    def _do_call_vote(self):
        bill = self._selected_pending()
        if bill:
            vf, va, _ = legislative.projected_votes(self.state, bill)
            thr = legislative.threshold_for(self.state, bill)
            confirm = QMessageBox.question(
                self, "Call Vote",
                f"Projected: {vf} for / {va} against (need {thr}).\n\nProceed with the vote?",
                QMessageBox.Yes | QMessageBox.No)
            if confirm == QMessageBox.Yes:
                self.run_action(lambda st: ops.op_call_vote(st, bill))

    def _do_withdraw(self):
        bill = self._selected_pending()
        if bill:
            self.run_action(lambda st: ops.op_withdraw_bill(st, bill))

    def _do_support_government_bill(self):
        bill = ops.government_bill(self.state)
        if bill:
            self.run_action(lambda st: ops.op_support_government_bill(st, bill.id))

    def _do_oppose_government_bill(self):
        bill = ops.government_bill(self.state)
        if bill:
            self.run_action(lambda st: ops.op_oppose_government_bill(st, bill.id))

    def _do_amend_government_bill(self):
        bill = ops.government_bill(self.state)
        if bill:
            self.run_action(lambda st: ops.op_amend_government_bill(st, bill.id))

    def _do_add_pledge(self):
        bill_id = self._pledge_candidate_combo.currentData()
        if bill_id:
            self.run_action(lambda st: ops.op_add_agenda_pledge(st, bill_id))

    def _do_campaign_pledge(self):
        bill_id = self._agenda_combo.currentData()
        if bill_id:
            self.run_action(lambda st: ops.op_campaign_on_pledge(st, bill_id))

    def _do_drop_pledge(self):
        bill_id = self._agenda_combo.currentData()
        if bill_id:
            self.run_action(lambda st: ops.op_drop_agenda_pledge(st, bill_id))

    def _refresh_budget_forecast(self):
        """Live preview beside the draft, before it is ever tabled —
        engine.budget.forecast() run read-only against the current combo
        selections. Never mutates state; if the combination is invalid
        (moves the total more than the ±30% band), says so instead of
        guessing at a plan that couldn't actually be proposed."""
        label = getattr(self, "_budget_forecast_label", None)
        if label is None:
            return
        adjustments = {envelope_id: combo.currentData()
                       for envelope_id, combo in self._budget_combos.items()}
        try:
            plan = budget_engine.build_proposal(self.state, adjustments)
        except ValueError as exc:
            label.setText(f"Forecast: {exc}")
            return
        fc = budget_engine.forecast(self.state, plan)
        lines = [f"Forecast: {fc['expenditure']:,.0f} M spending, "
                f"balance {fc['projected_balance']:+,.0f} M"]
        for portfolio, direction, status in fc["moves"]:
            lines.append(f"  {portfolio} would move {direction} {status.upper()}")
        label.setText("\n".join(lines))

    def _do_supplementary(self):
        """Read the two combos and call the shared op. All the gating —
        government, cooldown, cap, cost, the vote itself — lives in
        engine/player_ops.py; this only gathers the choice."""
        portfolio = self._supp_combo.currentData()
        fraction = self._supp_share_combo.currentData()
        cap = budget_engine.supplementary_cap(self.state, portfolio)
        amount = cap * float(fraction)
        self.run_action(
            lambda st: ops.op_supplementary_appropriation(st, portfolio, amount))

    def _do_propose_budget(self):
        adjustments = {envelope_id: combo.currentData()
                       for envelope_id, combo in self._budget_combos.items()}
        try:
            plan = budget_engine.build_proposal(self.state, adjustments)
        except ValueError as exc:
            QMessageBox.warning(self, "Annual Budget", str(exc))
            return
        cost = ops.cost_budget_proposal(self.state, plan)
        confirm = QMessageBox.question(
            self, "Table Annual Budget",
            f"{plan.year} spending: {plan.expenditure:,.0f} M\n"
            f"Forecast revenue: {plan.forecast_revenue:,.0f} M\n"
            f"Forecast balance: {plan.forecast_balance:+,.0f} M\n"
            f"Political cost: {cost:.0f} PC\n\nTable this plan in parliament?",
            QMessageBox.Yes | QMessageBox.No)
        if confirm == QMessageBox.Yes:
            self.run_action(lambda st: ops.op_propose_budget(st, plan))

    def _do_lobby_budget(self):
        if self._budget_lobby_combo is not None:
            faction_id = self._budget_lobby_combo.currentData()
            self.run_action(lambda st: ops.op_lobby_budget(st, faction_id))

    def _do_call_budget_vote(self):
        plan = self.state.pending_budget
        if plan is None:
            return
        vf, va, _ = budget_engine.projected_votes(self.state, plan)
        threshold = self.state.legislature.majority_threshold()
        confirm = QMessageBox.question(
            self, "Call Budget Vote",
            f"Projected: {vf} for / {va} against (need {threshold}).\n\nProceed?",
            QMessageBox.Yes | QMessageBox.No)
        if confirm == QMessageBox.Yes:
            self.run_action(lambda st: ops.op_call_budget_vote(st))

    def _do_withdraw_budget(self):
        self.run_action(lambda st: ops.op_withdraw_budget(st))


# ═══════════════════════════════════════════════════════════════════════════
# CABINET
# ═══════════════════════════════════════════════════════════════════════════

class CabinetPage(PageDialog):
    def __init__(self, state, on_action=None, parent=None):
        # A drawn shortlist is uncommitted input held between "Draw Up a
        # Shortlist" and "Appoint". It is discarded whenever the page
        # rebuilds, so an appointment can never be made against candidates
        # from a stale cabinet.
        self._shortlist = []
        self._shortlist_portfolio = None
        self._candidate_combo = None
        self._portfolio_combo = None
        self._selected_portfolio = None
        super().__init__("Cabinet", state, on_action, parent)
        self.refresh()

    def refresh(self):
        if getattr(self, "_portfolio_combo", None) is not None:
            try:
                self._selected_portfolio = self._portfolio_combo.currentData()
            except RuntimeError:
                pass
        self._shortlist = []
        self._shortlist_portfolio = None
        self._candidate_combo = None
        self._portfolio_combo = None
        self.clear_content()
        b = self.content.body
        s = self.state

        b.addWidget(section_title(
            "CABINET STABILITY" if s.player.in_government else "GOVERNMENT CABINET"))
        avg_loy = s.cabinet.average_loyalty()
        avg_comp = s.cabinet.average_competence()
        threats = s.cabinet.internal_threats()
        b.addWidget(KeyValueRow("Average loyalty", f"{avg_loy:.2f}",
                                theme.lerp_status_color(avg_loy)))
        b.addWidget(KeyValueRow("Average competence", f"{avg_comp:.2f}",
                                theme.lerp_status_color(avg_comp)))
        b.addWidget(KeyValueRow("Ministers at risk", str(len(threats)),
                                theme.CRITICAL if threats else theme.GOOD))

        ministry_engine.ensure_ministries(s)
        overloaded = sum(1 for ministry in s.ministries.values()
                         if ministry.status_label() in ("Overloaded", "Failing"))
        b.addWidget(KeyValueRow(
            "Departments overloaded", str(overloaded),
            theme.CRITICAL if overloaded else theme.GOOD))

        b.addWidget(divider())
        b.addWidget(section_title("MINISTERS"))
        for portfolio in CORE_PORTFOLIOS:
            m = s.cabinet.get(portfolio)
            block = QWidget()
            bl = QVBoxLayout(block)
            bl.setContentsMargins(0, 3, 0, 3); bl.setSpacing(1)
            if m is None:
                header = QLabel(f"{portfolio}  —  VACANT")
                header.setStyleSheet(f"color: {theme.CRITICAL};")
                bl.addWidget(header)
                bl.addWidget(body_label(explain.implementation_note(s, portfolio),
                                        dim=True, small=True))
            else:
                faction = ops.faction_by_id(s, m.faction_id)
                fname = faction.name if faction else m.faction_id
                threat = m.threat_level()
                trait_tag = f"  · {m.trait_label()}" if m.trait_label() else ""
                header = QLabel(f"{portfolio}  —  {m.name}  ({fname}){trait_tag}"
                                + ("  ⚠" if threat > 0.5 else ""))
                header.setStyleSheet(
                    f"color: {theme.CRITICAL if threat > 0.5 else theme.INK};")
                bl.addWidget(header)
                bl.addWidget(body_label(
                    f"competence {m.effective_competence():.2f} · loyalty {m.loyalty:.2f} · "
                    f"ambition {m.ambition:.2f} · effectiveness {m.implementation_quality():.2f}",
                    dim=True, small=True))
                bl.addWidget(body_label(f"    {explain.implementation_note(s, portfolio)}"
                                        + ("  ⚠ threat to government" if threat > 0.5 else ""),
                                        dim=True, small=True))
            ministry = s.ministries[portfolio]
            snapshot = ministry_engine.preview(s, portfolio)
            status_color = (theme.GOOD if ministry.status_label() == "Effective"
                            else theme.WARN if ministry.status_label() == "Stretched"
                            else theme.CRITICAL)
            load_ratio = snapshot["workload"] / max(0.01, snapshot["capacity"])
            load_word, _load_color = banded(load_ratio, LOAD_RATIO_BANDS, reverse=True)
            bl.addWidget(body_label(
                f"    DEPARTMENT: {ministry.status_label()} · delivery "
                f"{snapshot['delivery']*100:.0f}% · workload {snapshot['workload']:.2f} / "
                f"capacity {snapshot['capacity']:.2f} ({load_word}) · backlog "
                f"{ministry.backlog:.2f} · funding {snapshot['funding_ratio']*100:.0f}%",
                small=True))
            causes = ", ".join(
                f"{name} {amount:.2f}" for name, amount in snapshot["breakdown"].items())
            detail = body_label(f"    load: {causes}", dim=True, small=True)
            detail.setStyleSheet(detail.styleSheet() + f" color: {status_color};")
            bl.addWidget(detail)
            b.addWidget(block)

        if not s.player.in_government:
            b.addWidget(divider())
            b.addWidget(section_title("SHADOW CABINET — YOUR GOVERNMENT-IN-WAITING"))
            for portfolio in CORE_PORTFOLIOS:
                m = s.shadow_cabinet.get(portfolio)
                if m is None:
                    b.addWidget(KeyValueRow(portfolio, "unassigned", theme.INK_DIM))
                else:
                    b.addWidget(KeyValueRow(
                        portfolio, f"{m.name} · {m.trait_label() or 'steady'} · "
                        f"effectiveness {m.implementation_quality():.2f}"))
            b.addWidget(body_label(
                "Shadow ministers improve campaigns in their briefs and take office with you "
                "if your party wins the election.", dim=True, small=True))

        # ── Actions ──
        if s.player.in_government:
            b.addWidget(divider())
            b.addWidget(section_title(f"ACTIONS  (reshuffle {_fmt_pc(ops.COST_RESHUFFLE)}, "
                                       f"dismiss {_fmt_pc(ops.COST_DISMISS)})"))

            self._portfolio_combo = QComboBox()
            for p in CORE_PORTFOLIOS:
                tag = " [VACANT]" if s.cabinet.get(p) is None else ""
                self._portfolio_combo.addItem(f"{p}{tag}", p)
            if self._selected_portfolio is not None:
                idx = self._portfolio_combo.findData(self._selected_portfolio)
                if idx >= 0:
                    self._portfolio_combo.setCurrentIndex(idx)
            b.addWidget(self._portfolio_combo)

            shortlist_row = QWidget(); sl = QHBoxLayout(shortlist_row)
            sl.setContentsMargins(0, 0, 0, 0); sl.setSpacing(8)
            shortlist_btn = QPushButton("Draw Up a Shortlist")
            shortlist_btn.clicked.connect(self._do_shortlist)
            sl.addWidget(shortlist_btn)
            dismiss_btn = QPushButton("Dismiss Minister")
            dismiss_btn.clicked.connect(self._do_dismiss)
            sl.addWidget(dismiss_btn)
            b.addWidget(shortlist_row)

            self._candidate_combo = QComboBox()
            self._candidate_combo.addItem("— draw up a shortlist first —", None)
            appoint_row = QWidget(); al = QHBoxLayout(appoint_row)
            al.setContentsMargins(0, 0, 0, 0); al.setSpacing(8)
            al.addWidget(self._candidate_combo, stretch=1)
            appoint_btn = QPushButton("Appoint")
            appoint_btn.clicked.connect(self._do_appoint)
            al.addWidget(appoint_btn)
            b.addWidget(appoint_row)

        else:
            b.addWidget(divider())
            b.addWidget(section_title(
                f"BUILD THE SHADOW TEAM  ({_fmt_pc(ops.COST_APPOINT_SHADOW)} per appointment)"))
            self._portfolio_combo = QComboBox()
            for p in CORE_PORTFOLIOS:
                tag = " [VACANT]" if s.shadow_cabinet.get(p) is None else ""
                self._portfolio_combo.addItem(f"{p}{tag}", p)
            b.addWidget(self._portfolio_combo)

            shortlist_btn = QPushButton("Draw Up Party Shortlist")
            shortlist_btn.clicked.connect(self._do_shortlist)
            b.addWidget(shortlist_btn)
            self._candidate_combo = QComboBox()
            self._candidate_combo.addItem("— draw up a shortlist first —", None)
            b.addWidget(self._candidate_combo)
            appoint_btn = QPushButton("Appoint to Shadow Cabinet")
            appoint_btn.clicked.connect(self._do_appoint)
            b.addWidget(appoint_btn)

        b.addStretch(1)

    def has_uncommitted_input(self) -> bool:
        """A drawn shortlist is a decision in progress — the one piece of
        partial input any page holds between method calls."""
        return bool(self._shortlist) and self._shortlist_portfolio is not None

    def _do_shortlist(self):
        from engine import cabinet_ops
        portfolio = self._portfolio_combo.currentData()
        self._shortlist_portfolio = portfolio
        self._shortlist = (cabinet_ops.shortlist(self.state, portfolio)
                           if self.state.player.in_government
                           else cabinet_ops.shadow_shortlist(self.state, portfolio))
        self.uncommitted_changed.emit()
        self._candidate_combo.clear()
        for c in self._shortlist:
            fac = ops.faction_by_id(self.state, c.faction_id)
            fname = fac.name if fac else "independent"
            self._candidate_combo.addItem(
                f"{c.name} — {fname} — {c.trait_label() or 'steady'} "
                f"(comp {c.effective_competence():.2f}, loy {c.loyalty:.2f})", c)

    def _do_appoint(self):
        candidate = (self._candidate_combo.currentData()
                     if self._candidate_combo is not None else None)
        if candidate is None or self._shortlist_portfolio is None:
            QMessageBox.information(self, "Appoint", "Draw up a shortlist first.")
            return
        portfolio = self._shortlist_portfolio
        if self.state.player.in_government:
            self.run_action(lambda st: ops.op_appoint_minister(st, portfolio, candidate))
        else:
            self.run_action(lambda st: ops.op_appoint_shadow_minister(st, portfolio, candidate))

    def _do_dismiss(self):
        portfolio = self._portfolio_combo.currentData()
        if self.state.cabinet.get(portfolio) is None:
            QMessageBox.information(self, "Dismiss", f"{portfolio} is already vacant.")
            return
        self.run_action(lambda st: ops.op_dismiss(st, portfolio))


# ═══════════════════════════════════════════════════════════════════════════
# DIPLOMACY
# ═══════════════════════════════════════════════════════════════════════════

class DiplomacyPage(PageDialog):
    def __init__(self, state, on_action=None, parent=None):
        super().__init__("Diplomacy", state, on_action, parent)
        # Survives the rebuild that every refresh performs — the page is
        # long-lived now, so losing the user's chosen country on each action
        # would be maddening.
        self._selected_country_id = None
        self._country_combo = None
        self._treaty_combo = None
        self.refresh()

    def refresh(self):
        # Remember the selection across the rebuild below.
        if getattr(self, "_country_combo", None) is not None:
            try:
                self._selected_country_id = self._country_combo.currentData()
            except RuntimeError:
                pass          # combo already destroyed by a prior refresh
        self._country_combo = None
        self._treaty_combo = None
        self.clear_content()
        b = self.content.body
        s = self.state

        b.addWidget(section_title("FOREIGN RELATIONS"))
        for c in s.world:
            rel = s.country.get_relation(c.id)
            block = QWidget()
            bl = QVBoxLayout(block)
            bl.setContentsMargins(0, 3, 0, 3); bl.setSpacing(1)
            status = rel.status_label() if rel else "unknown"
            color = theme.relation_color(rel.score if rel else None)
            header = QLabel(f"{c.name} — {status}")
            header.setStyleSheet(f"color: {color};")
            bl.addWidget(header)
            details = f"{c.regime_type.replace('_',' ')} · stability {c.stability:.2f}"
            if rel:
                details += f" · trade {rel.trade_volume:,.0f}M · score {rel.score:+.2f}"
                if rel.treaties:
                    details += f" · {len(rel.treaties)} treaty(ies)"
                if rel.sanctioned:
                    details += " · SANCTIONED"
            bl.addWidget(body_label(details, dim=True, small=True))
            b.addWidget(block)

        # Active loans (a diplomacy-adjacent obligation)
        if s.country.economy.loans:
            b.addWidget(divider())
            b.addWidget(section_title("ACTIVE LOANS"))
            for loan in s.country.economy.loans:
                lender = s.world_country(loan.lender_id)
                lname = lender.name if lender else loan.lender_id
                b.addWidget(KeyValueRow(
                    f"{lname}",
                    f"{loan.principal:,.0f}M @ {loan.annual_interest_rate*100:.1f}% · "
                    f"{loan.months_remaining()} mo left"))

        # ── Actions ──
        if s.player.in_government:
            b.addWidget(divider())
            b.addWidget(section_title("ACTIONS"))
            self._country_combo = QComboBox()
            for c in s.world:
                self._country_combo.addItem(c.name, c.id)
            if self._selected_country_id is not None:
                idx = self._country_combo.findData(self._selected_country_id)
                if idx >= 0:
                    self._country_combo.setCurrentIndex(idx)
            b.addWidget(self._country_combo)

            grid = QWidget(); gl = QVBoxLayout(grid)
            gl.setContentsMargins(0, 0, 0, 0); gl.setSpacing(4)
            gl.addWidget(_action_row("Improve Relations", _fmt_pc(ops.COST_IMPROVE_RELATIONS),
                                     True, self._do_improve))
            gl.addWidget(_action_row("Propose Trade Agreement", _fmt_pc(ops.COST_TRADE_AGREEMENT),
                                     True, self._do_trade, s, "trade_agreement"))
            gl.addWidget(_action_row("Request Foreign Loan", _fmt_pc(ops.COST_FOREIGN_LOAN),
                                     True, self._do_loan, s, "foreign_loan"))
            gl.addWidget(_action_row("Condemn Government", _fmt_pc(ops.COST_CONDEMN),
                                     True, self._do_condemn, s, "condemn"))
            gl.addWidget(_action_row("Defense Pact", _fmt_pc(ops.PACT_COST),
                                     True, self._do_pact, s, "defense_pact"))
            gl.addWidget(_action_row("Sanctions (impose / lift)", _fmt_pc(ops.SANCTIONS_COST),
                                     True, self._do_sanctions, s, "impose_sanctions"))
            summit_cd = ops.on_cooldown(s, "summit", ops.SUMMIT_COOLDOWN)
            gl.addWidget(_action_row("Host a Summit", _fmt_pc(ops.SUMMIT_COST),
                                     not summit_cd, self._do_summit, s, "hold_summit"))
            b.addWidget(grid)
            self._treaty_combo = None
            treaties = [(c, t) for c in s.world
                        for t in (s.country.relations.get(c.id).treaties
                                  if s.country.relations.get(c.id) else [])]
            if treaties:
                trow = QWidget(); tl = QHBoxLayout(trow)
                tl.setContentsMargins(0, 0, 0, 0); tl.setSpacing(8)
                self._treaty_combo = QComboBox()
                for c, t in treaties:
                    self._treaty_combo.addItem(f"{t.name} ({t.type})", (c.id, t.id))
                tl.addWidget(self._treaty_combo, stretch=1)
                tear = QPushButton("Tear Up")
                tear.clicked.connect(self._do_break_treaty)
                tl.addWidget(tear)
                b.addWidget(trow)

        b.addStretch(1)

    def select_country(self, country_id: str):
        """Point this page at a country — used to keep the tab in step with
        the map's selection so the two routes to the same verbs agree."""
        self._selected_country_id = country_id
        combo = getattr(self, "_country_combo", None)
        if combo is None:
            return
        try:
            idx = combo.findData(country_id)
        except RuntimeError:
            return
        if idx >= 0:
            combo.setCurrentIndex(idx)

    def _sel_country(self):
        return self._country_combo.currentData()

    def _do_pact(self):
        self.run_action(lambda st: ops.op_defense_pact(st, self._sel_country()))

    def _do_sanctions(self):
        cid = self._sel_country()
        rel = self.state.country.relations.get(cid)
        if rel is not None and rel.sanctioned:
            self.run_action(lambda st: ops.op_lift_sanctions(st, cid))
        else:
            self.run_action(lambda st: ops.op_impose_sanctions(st, cid))

    def _do_summit(self):
        self.run_action(lambda st: ops.op_hold_summit(st, self._sel_country()))

    def _do_break_treaty(self):
        if self._treaty_combo is None:
            return
        cid, tid = self._treaty_combo.currentData()
        self.run_action(lambda st: ops.op_break_treaty(st, cid, tid))

    def _do_improve(self):
        self.run_action(lambda st: ops.op_improve_relations(st, self._sel_country()))

    def _do_trade(self):
        cid = self._sel_country()
        eligible = {c.id for c in ops.trade_eligible_countries(self.state)}
        if cid not in eligible:
            QMessageBox.information(self, "Trade",
                                     "That country is not currently willing to discuss trade.")
            return
        self.run_action(lambda st: ops.op_trade_agreement(st, cid))

    def _do_loan(self):
        cid = self._sel_country()
        eligible = {c.id for c in ops.loan_eligible_countries(self.state)}
        if cid not in eligible:
            QMessageBox.information(self, "Loan",
                                     "That country does not trust you enough to lend right now.")
            return
        self.run_action(lambda st: ops.op_foreign_loan(st, cid))

    def _do_condemn(self):
        self.run_action(lambda st: ops.op_condemn(st, self._sel_country()))


# ═══════════════════════════════════════════════════════════════════════════
# BRIEFING
# ═══════════════════════════════════════════════════════════════════════════

class BriefingPage(PageDialog):
    """Daily intelligence plus the campaign's declared opening programme."""

    def __init__(self, state, on_action=None, parent=None):
        super().__init__("Briefing", state, on_action, parent)
        self.refresh()

    def refresh(self):
        self.clear_content()
        b = self.content.body
        s = self.state
        econ = s.country.economy

        # Header line
        who = (f"{s.player.title} {s.player.name}" if s.player.in_government
               else f"{s.player.name} (Opposition)")
        b.addWidget(body_label(f"{who} — {s.date_string()}"))
        b.addWidget(divider())

        # A programme is chosen once, but completed through the ordinary
        # policy, party, and regional controls.  The buttons establish intent;
        # they do not grant effects or create duplicate action routes.
        programme_report = opening_programme.progress(s)
        b.addWidget(section_title("FIRST NINETY DAYS"))
        if programme_report["status"] == "unselected":
            b.addWidget(body_label(
                f"Choose one political programme for the opening months. "
                f"{programme_report['days_remaining']} day(s) remain; the programme "
                "tracks existing actions and grants no hidden bonuses.",
                dim=True, small=True))
            for programme in opening_programme.candidates(s):
                heading = QLabel(programme["name"])
                heading.setWordWrap(True)
                heading.setStyleSheet(
                    f"color: {theme.ACCENT}; font-size: {theme.FONT_SIZE_PT}pt; "
                    "font-weight: 600;")
                b.addWidget(heading)
                b.addWidget(body_label(programme["body"], small=True))
                b.addWidget(body_label(
                    "Programme: " + " · ".join(task["name"]
                                                for task in programme["tasks"]),
                    dim=True, small=True))
                button = QPushButton(f"Adopt {programme['name']}")
                programme_id = programme["id"]
                button.clicked.connect(
                    lambda _checked=False, pid=programme_id:
                    self.run_action(lambda st: ops.op_select_opening_programme(st, pid)))
                b.addWidget(button)
        elif programme_report["status"] == "missed":
            b.addWidget(body_label(
                "The opening programme window passed without a declared programme.",
                dim=True, small=True))
        else:
            programme = programme_report["programme"]
            status = programme_report["status"]
            if status == "active":
                timing = f"{programme_report['days_remaining']} day(s) remain"
                color = theme.ACCENT
            elif status == "complete":
                timing = "programme completed"
                color = theme.GOOD
            elif status == "superseded":
                timing = "concluded by a change of office"
                color = theme.INK_DIM
            else:
                timing = "ninety-day window expired"
                color = theme.WARN
            b.addWidget(KeyValueRow(
                programme["name"],
                f"{programme_report['completed']}/{programme_report['total']} complete · {timing}",
                color))
            b.addWidget(body_label(programme["body"], dim=True, small=True))
            for task, done in programme_report["tasks"]:
                marker = "✓" if done else "○"
                task_color = theme.GOOD if done else theme.INK
                heading = QLabel(f"{marker}  {task['name']}")
                heading.setWordWrap(True)
                heading.setStyleSheet(
                    f"color: {task_color}; font-size: {theme.FONT_SIZE_SM}pt; "
                    "font-weight: 600;")
                b.addWidget(heading)
                b.addWidget(body_label(
                    f"{task['body']}  Open {task['page']}.", dim=True, small=True))
        b.addWidget(divider())

        # One ordered account of what actually needs the player.  The same
        # read-only queue feeds the dashboard's compact alert cards; this is
        # its full briefing form, including planned work that is not yet a
        # crisis.  Destinations name existing dock tabs rather than adding a
        # second set of action controls here.
        decisions = decision_queue.build_queue(s)
        b.addWidget(section_title("DECISIONS AND DEADLINES"))
        if not decisions:
            b.addWidget(body_label(
                "Nothing currently requires a decision. The political calendar is clear.",
                dim=True, small=True))
        else:
            priority_colors = {
                decision_queue.PRIORITY_REQUIRED: theme.CRITICAL,
                decision_queue.PRIORITY_URGENT: theme.WARN,
                decision_queue.PRIORITY_PLANNED: theme.ACCENT,
                decision_queue.PRIORITY_OPTIONAL: theme.INK_DIM,
                decision_queue.PRIORITY_INFORMATION: theme.INK_DIM,
            }
            for item in decisions[:10]:
                heading = QLabel(f"{item.priority.upper()}  ·  {item.title}")
                heading.setWordWrap(True)
                heading.setStyleSheet(
                    f"color: {priority_colors.get(item.priority, theme.INK)}; "
                    f"font-size: {theme.FONT_SIZE_SM}pt; font-weight: 600;")
                b.addWidget(heading)
                route = f"Open {item.page}"
                if item.region_id:
                    route = f"Select {item.tag} on the map"
                suffix = f" · {item.due_text}" if item.due_text else ""
                b.addWidget(body_label(
                    f"{item.detail}  {route} · authority: {item.authority}{suffix}",
                    dim=True, small=True))
            if len(decisions) > 10:
                b.addWidget(body_label(
                    f"+ {len(decisions) - 10} lower-priority item(s)",
                    dim=True, small=True))
        b.addWidget(divider())

        # Dated public commitments only: hidden event follow-ups never appear
        # here. The calendar is calculated from the same deadlines as the
        # decision queue plus the simulation's existing fiscal, legislative,
        # programme, loan, election, and monthly-report dates.
        calendar_items = political_calendar.build_calendar(
            s, horizon_days=365, max_items=8)
        b.addWidget(section_title("POLITICAL CALENDAR · NEXT 12 MONTHS"))
        if not calendar_items:
            b.addWidget(body_label("No public commitments are currently dated.",
                                   dim=True, small=True))
        else:
            kind_colors = {
                political_calendar.KIND_DEADLINE: theme.CRITICAL,
                political_calendar.KIND_SCHEDULED: theme.ACCENT,
                political_calendar.KIND_REPORT: theme.INK_DIM,
                political_calendar.KIND_COMMITMENT: theme.WARN,
            }
            for item in calendar_items:
                when = item.date.strftime("%d %b %Y").lstrip("0")
                b.addWidget(KeyValueRow(
                    when, item.title,
                    kind_colors.get(item.kind, theme.INK)))
                authority = f" · authority: {item.authority}" if item.authority else ""
                b.addWidget(body_label(
                    f"{item.detail}  Open {item.page}{authority}",
                    dim=True, small=True))
        b.addWidget(divider())

        # Economic summary
        b.addWidget(section_title("ECONOMIC SUMMARY"))
        b.addWidget(KeyValueRow("GDP", f"{econ.gdp:,.0f} M"))
        b.addWidget(KeyValueRow("Growth", f"{econ.growth_rate*100:+.1f}%",
                                theme.lerp_status_color(max(0, min(1, (econ.growth_rate+0.05)/0.13)))))
        b.addWidget(KeyValueRow("Unemployment", f"{econ.unemployment*100:.1f}%",
                                theme.lerp_status_color(econ.unemployment/0.30, higher_is_better=False)))
        b.addWidget(KeyValueRow("Inflation", f"{econ.inflation*100:.1f}%",
                                theme.lerp_status_color(econ.inflation/0.15, higher_is_better=False)))
        bal = econ.budget.balance
        b.addWidget(KeyValueRow("Budget balance", f"{bal:+,.0f} M",
                                theme.GOOD if bal >= 0 else theme.BAD))
        b.addWidget(KeyValueRow("Debt / GDP", f"{econ.public_debt_pct*100:.0f}%",
                                theme.lerp_status_color(econ.public_debt_pct/1.5, higher_is_better=False)))

        if s.households:
            from engine import households as household_engine
            b.addWidget(divider())
            b.addWidget(section_title("HOUSEHOLD ECONOMY"))
            real_income = household_engine.national_real_income(s)
            living_cost = household_engine.national_living_cost(s)
            hardship = household_engine.national_hardship(s)
            services = household_engine.national_service_access(s)
            confidence = household_engine.national_confidence(s)
            b.addWidget(KeyValueRow(
                "Real household income", f"{real_income*100:.1f} · start = 100",
                theme.lerp_status_color(max(0.0, min(1.0, real_income - 0.5)))))
            b.addWidget(KeyValueRow(
                "Living costs", f"{living_cost*100:.1f} · start = 100",
                theme.lerp_status_color(max(0.0, min(1.0, 1.5 - living_cost)),
                                        higher_is_better=True)))
            b.addWidget(KeyValueRow(
                "Households in hardship", f"{hardship*100:.0f}% pressure index",
                theme.lerp_status_color(hardship, higher_is_better=False)))
            b.addWidget(KeyValueRow(
                "Public-service access", f"{services*100:.0f}%",
                theme.lerp_status_color(services)))
            confidence_word, confidence_color = banded(confidence, CONFIDENCE_BANDS)
            b.addWidget(KeyValueRow(
                "Household confidence", f"{confidence*100:.0f}% {confidence_word}",
                confidence_color))
            for household in household_engine.hardest_hit(s, 4):
                group = HOUSEHOLD_GROUP_BY_ID[household.group_id]
                region = ARDENIA_REGION_PROFILES[household.region_id]
                b.addWidget(body_label(
                    f"• {group['name']}, {region['name']}: "
                    f"{household.status_label().lower()} · real income "
                    f"{household.real_income_index*100:.0f} · services "
                    f"{household.service_access*100:.0f}%", small=True))

        # Political summary
        b.addWidget(divider())
        b.addWidget(section_title("POLITICAL SUMMARY"))
        b.addWidget(KeyValueRow("Approval", f"{s.player.approval*100:.0f}%",
                                theme.lerp_status_color(s.player.approval)))
        trend = s.stability.trend
        arrow = "▲" if trend > 0.002 else ("▼" if trend < -0.002 else "—")
        b.addWidget(KeyValueRow("Government stability",
                                f"{s.stability.value:.2f} {s.stability.label()} {arrow}",
                                theme.lerp_status_color(s.stability.value)))
        coalition_ids = s.coalition_faction_ids()
        seats = s.legislature.coalition_seats(coalition_ids)
        maj = s.legislature.majority_threshold()
        b.addWidget(KeyValueRow("Coalition seats", f"{seats} / {s.legislature.total_seats} (need {maj})",
                                theme.GOOD if seats >= maj else theme.CRITICAL))
        from engine import roleplay
        rival = roleplay.current_rival(s)
        if rival is not None and rival.leader:
            b.addWidget(KeyValueRow("Chief antagonist", f"{rival.leader} ({rival.name})",
                                    theme.BAD))
        from engine.turn import political_upkeep
        upkeep, detail = political_upkeep(s)
        if upkeep > 0:
            parts = ", ".join(f"{k} -{v:.1f}" for k, v in detail.items() if v > 0)
            b.addWidget(KeyValueRow("Governing overhead", f"-{upkeep:.1f} PC/mo ({parts})",
                                    theme.WARN))

        # Cabinet warnings
        threats = s.cabinet.internal_threats()
        vacancies = [p for p in CORE_PORTFOLIOS if s.cabinet.get(p) is None]
        if threats or vacancies:
            b.addWidget(divider())
            b.addWidget(section_title("CABINET WARNINGS"))
            for m in threats:
                b.addWidget(body_label(f"⚠ {m.name} ({m.portfolio}) — ambitious and disloyal, "
                                       f"a resignation risk.", small=True))
            for p in vacancies:
                b.addWidget(body_label(f"⚠ {p} is vacant — reforms in this area underperform.", small=True))

        # Active crises: unrest / protests risk, deficit, debt
        crises = self._crises(s)
        if crises:
            b.addWidget(divider())
            b.addWidget(section_title("ACTIVE CRISES"))
            for c in crises:
                b.addWidget(body_label(f"• {c}", small=True))

        # Subnational conditions: the dashboard map provides the spatial view;
        # the briefing ranks the places where pressure is most consequential.
        if s.regions:
            from engine import regions as region_engine
            b.addWidget(divider())
            b.addWidget(section_title("REGIONAL PICTURE"))
            b.addWidget(KeyValueRow(
                "State reach",
                f"{region_engine.average_state_reach(s)*100:.0f}% population-weighted",
                theme.lerp_status_color(region_engine.average_state_reach(s))))
            b.addWidget(KeyValueRow(
                "Regional pressure",
                f"{region_engine.national_pressure(s)*100:.0f}% population-weighted",
                theme.lerp_status_color(region_engine.national_pressure(s),
                                        higher_is_better=False)))
            for region in sorted(s.regions.values(), key=lambda item: item.pressure,
                                 reverse=True)[:3]:
                profile = ARDENIA_REGION_PROFILES[region.id]
                issue = REGIONAL_ISSUES.get(region.issue_id, {
                    "name": profile["issue_name"]})
                b.addWidget(body_label(
                    f"• {profile['name']}: {region.pressure*100:.0f}% pressure, "
                    f"{region.unemployment*100:.1f}% unemployed — "
                    f"{issue['name']}", small=True))
            if s.regional_programs:
                b.addWidget(KeyValueRow(
                    "Programme commitments",
                    f"{region_engine.monthly_program_cost(s):,.0f} M/month",
                    theme.WARN))
                for program in s.regional_programs:
                    definition = REGIONAL_PROGRAMS[program.program_id]
                    region_name = ARDENIA_REGION_PROFILES[program.region_id]["name"]
                    b.addWidget(body_label(
                        f"→ {region_name}: {definition['short_name']} — "
                        f"month {program.months_active}/{program.duration}", small=True))

        # Upcoming election
        from engine import elections
        b.addWidget(divider())
        b.addWidget(section_title("UPCOMING ELECTION"))
        days = elections.days_until_election(s)
        txt = f"{days:,} day(s) away"
        if elections.should_trigger_snap_election(s):
            txt += " — ⚠ collapse risk, may come sooner"
        b.addWidget(body_label(txt, small=True))

        # Recommendations
        recs = self._recommendations(s)
        if recs:
            b.addWidget(divider())
            b.addWidget(section_title("RECOMMENDATIONS"))
            for r in recs:
                b.addWidget(body_label(f"→ {r}", small=True))

        # ── Leadership actions (roleplay) ──
        if s.player.in_government:
            b.addWidget(divider())
            b.addWidget(section_title("LEADERSHIP"))

            bg = ops.background_ability(s)
            if bg is not None:
                on_cd = ops.on_cooldown(s, "background_action", bg.action_cooldown)
                cd_note = ""
                if on_cd:
                    cd_note = f" (again in {ops.cooldown_remaining(s, 'background_action', bg.action_cooldown)} mo)"
                b.addWidget(_action_row(
                    f"{bg.action_label}{cd_note}", _fmt_pc(bg.action_cost),
                    not on_cd, self._do_background))
                b.addWidget(body_label(f"    {bg.action_blurb}", dim=True, small=True))

            addr_cd = ops.on_cooldown(s, "address_nation", ops.ADDRESS_COOLDOWN)
            self._tone_combo = QComboBox()
            for tone, label in (("reassuring", "Reassuring — steady the nerves"),
                                ("defiant", "Defiant — rally the base"),
                                ("visionary", "Visionary — sell the future"),
                                ("contrite", "Contrite — own the failures")):
                self._tone_combo.addItem(label, tone)
            addr_row = QWidget(); al = QHBoxLayout(addr_row)
            al.setContentsMargins(0, 0, 0, 0); al.setSpacing(8)
            al.addWidget(self._tone_combo, stretch=1)
            addr_btn = QPushButton("Address the Nation"
                                   + (f" (again in {ops.cooldown_remaining(s, 'address_nation', ops.ADDRESS_COOLDOWN)} mo)"
                                      if addr_cd else ""))
            addr_btn.setEnabled(not addr_cd)
            addr_btn.clicked.connect(self._do_address)
            al.addWidget(addr_btn)
            b.addWidget(addr_row)

        b.addStretch(1)

    def _do_background(self):
        self.run_action(lambda st: ops.op_background_action(st))

    def _do_address(self):
        tone = self._tone_combo.currentData()
        self.run_action(lambda st: ops.op_address_nation(st, tone))

    # Both of these delegate to ui/explain.py, which is the single source of
    # truth shared with the always-visible alert strip in ui/app.py.
    def _crises(self, s):
        return [text for _sev, text in explain.crises(s)]

    def _recommendations(self, s):
        return [text for _sev, text in explain.recommendations(s)]


# ═══════════════════════════════════════════════════════════════════════════
# PARTIES  (intra-party wings)
# ═══════════════════════════════════════════════════════════════════════════

class HistoryPage(PageDialog):
    """Read-only Codex: how the country got here.

    Renders content/lore/, which is the canon events and dispatches cite —
    one source, so the Codex can never drift from the flavour text. Ardenia
    is the only country with an authored history; anywhere else this says so
    rather than inventing one."""

    def __init__(self, state, on_action=None, parent=None):
        super().__init__("History", state, on_action, parent)
        self.refresh()

    def refresh(self):
        self.clear_content()
        b = self.content.body
        s = self.state

        if s.country.id != "ardenia":
            b.addWidget(body_label(
                f"No history has been written for {s.country.name} yet.", dim=True))
            b.addStretch(1)
            return

        from content import lore

        header = QLabel(s.country.name.upper())
        header.setStyleSheet(f"color: {theme.ACCENT}; font-size: {theme.FONT_SIZE_LG}pt; "
                             f"letter-spacing: 2px;")
        b.addWidget(header)
        if s.country.capital:
            b.addWidget(body_label(f"Capital: {s.country.capital}", dim=True, small=True))
        b.addWidget(body_label(lore.OVERVIEW))

        b.addWidget(divider())
        b.addWidget(section_title("HOW WE GOT HERE"))
        for period, title, body in lore.TIMELINE:
            row = QLabel(f"{title}    <span style='color:{theme.INK_DIM}'>{period}</span>")
            row.setTextFormat(Qt.RichText)
            row.setWordWrap(True)
            row.setStyleSheet(f"color: {theme.INK}; font-size: {theme.FONT_SIZE_PT}pt;")
            b.addWidget(row)
            b.addWidget(body_label(body, dim=True, small=True))

        b.addWidget(divider())
        b.addWidget(section_title("WHERE THE PARTIES CAME FROM"))
        for party in sorted(s.country.factions, key=lambda f: -f.seats):
            origin = lore.PARTY_ORIGINS.get(party.id)
            if not origin:
                continue
            name = QLabel(party.name)
            name.setStyleSheet(f"color: {theme.ACCENT}; font-size: {theme.FONT_SIZE_PT}pt;")
            b.addWidget(name)
            b.addWidget(body_label(origin, dim=True, small=True))

        b.addWidget(divider())
        b.addWidget(section_title("NAMES THAT STILL MATTER"))
        for _key, blurb in lore.FIGURES.items():
            b.addWidget(body_label(f"• {blurb}", dim=True, small=True))

        def add_entry(entry):
            name = QLabel(entry["name"])
            name.setWordWrap(True)
            name.setStyleSheet(
                f"color: {theme.INK}; font-size: {theme.FONT_SIZE_PT}pt;")
            b.addWidget(name)
            b.addWidget(body_label(entry["body"], dim=True, small=True))

        b.addWidget(divider())
        b.addWidget(section_title("THE COUNTRY"))
        add_entry(lore.COUNTRY_PROFILE)
        add_entry(lore.KESLA)
        add_entry(lore.CEASEFIRE_LINE)
        for region in lore.REGIONS:
            add_entry(region)
        for city in lore.CITIES:
            add_entry(city)

        b.addWidget(divider())
        b.addWidget(section_title("THE PEOPLE"))
        add_entry(lore.DEMOGRAPHY)
        for people in lore.PEOPLES:
            add_entry(people)
        for social_group in lore.SOCIAL_ORDER:
            add_entry(social_group)
        add_entry(lore.LANGUAGE_AND_SCRIPT)
        for faith in lore.RELIGION:
            add_entry(faith)

        b.addWidget(divider())
        b.addWidget(section_title("HOW ARDENIA IS GOVERNED"))
        add_entry(lore.CONSTITUTIONAL_ORDER)
        for officeholder in lore.OFFICEHOLDERS:
            add_entry(officeholder)
        for institution in lore.INSTITUTIONS:
            add_entry(institution)
        for item in lore.LAW_AND_POWER:
            add_entry(item)
        for item in lore.MEDIA_AND_CIVIL_SOCIETY:
            add_entry(item)

        b.addWidget(divider())
        b.addWidget(section_title("THE ECONOMY"))
        add_entry(lore.ECONOMIC_PICTURE)
        for sector in lore.SECTORS:
            add_entry(sector)
        add_entry(lore.KRON)
        add_entry(lore.ENERGY)
        for obligation in lore.FOREIGN_OBLIGATIONS:
            add_entry(obligation)
        add_entry(lore.PRESENT_DAY)

        b.addWidget(divider())
        b.addWidget(section_title("INSIDE THE PARTIES"))
        for party in sorted(s.country.factions, key=lambda f: -f.seats):
            blocs = [item for item in lore.BLOCS if item["parent_id"] == party.id]
            if not blocs:
                continue
            party_name = QLabel(party.name)
            party_name.setStyleSheet(
                f"color: {theme.ACCENT}; font-size: {theme.FONT_SIZE_PT}pt;")
            b.addWidget(party_name)
            for bloc in blocs:
                add_entry(bloc)

        b.addStretch(1)


class PartiesPage(PageDialog):
    """Read-only view of each party's live internal currents."""

    def __init__(self, state, on_action=None, parent=None):
        super().__init__("Parties", state, on_action, parent)
        self.refresh()

    def refresh(self):
        self.clear_content()
        b = self.content.body
        s = self.state
        colors = theme.assign_party_colors(s.country.factions)

        # The seat arc used to sit permanently on the dashboard, spending a
        # large block of it on a question that is really one number. It lives
        # here now — this is the page someone opens when they actually want
        # seat detail, and the dashboard strip links straight to it.
        from ui.widgets_assembly import SeatArcWidget
        leg = s.legislature
        majority = leg.majority_threshold()
        arc = SeatArcWidget()
        arc.setMinimumHeight(150)
        arc.set_data(s.country.factions, leg.total_seats, majority, colors)
        b.addWidget(arc)
        coalition_seats = leg.coalition_seats(s.coalition_faction_ids())
        holds = coalition_seats >= majority
        summary = QLabel(
            f"Government {coalition_seats} / {majority} needed  ·  "
            f"{'majority' if holds else 'MINORITY'}")
        summary.setStyleSheet(
            f"color: {theme.GOOD if holds else theme.CRITICAL}; "
            f"font-size: {theme.FONT_SIZE_SM}pt;")
        b.addWidget(summary)
        b.addWidget(divider())

        for party in sorted(s.country.factions, key=lambda f: -f.seats):
            color = colors.get(party.id, theme.NEUTRAL)
            eff = party.effective_ideology()
            dom = party.dominant_wing()
            current_label = "bloc" if any(w.kind == "bloc" for w in party.wings) else "wing"

            header = QLabel(f"{party.name}")
            header.setStyleSheet(f"color: {color}; font-size: {theme.FONT_SIZE_PT}pt;")
            b.addWidget(header)
            coh = party.cohesion()
            b.addWidget(body_label(
                f"    stance: {eff.label()}  ·  leading {current_label}: "
                f"{dom.name if dom else '—'}  ·  cohesion {coh*100:.0f}%",
                dim=True, small=True))

            if len(party.wings) < 2:
                b.addWidget(body_label(f"    (a united party — no distinct {current_label}s)",
                                       dim=True, small=True))
            else:
                for w in sorted(party.wings, key=lambda x: -x.strength):
                    lead = "  ★" if dom and w.id == dom.id else ""
                    bar = MiniBar(f"  {w.name}{lead}")
                    bar.set_contribution(w.strength, f"{w.strength*100:.0f}%", scale=1.0)
                    b.addWidget(bar)
                    b.addWidget(body_label(
                        f"      {w.ideology.label()} · loyalty to leadership {w.loyalty:+.2f}",
                        dim=True, small=True))
                    if w.description:
                        b.addWidget(body_label(f"      {w.description}", dim=True, small=True))
                    if w.policy_biases:
                        pulls = ", ".join(
                            f"{'for' if bias > 0 else 'against'} {bill_id.replace('_', ' ')}"
                            for bill_id, bias in sorted(w.policy_biases.items(),
                                                        key=lambda item: -abs(item[1]))[:2]
                        )
                        b.addWidget(body_label(f"      current pulls: {pulls}",
                                               dim=True, small=True))
            b.addWidget(divider())

        b.addStretch(1)
