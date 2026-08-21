"""Focused checks for the shared read-only political calendar."""

import contextlib
import copy
import io
from datetime import date

from content.loader import build_state_for
from engine import budget, political_calendar
from engine.campaign import CampaignConfig, generate_campaign
from engine.turn import TurnEngine
from display.terminal import print_briefing
from models.economy import Loan
from models.events import PendingEvent
from models.region import RegionalProgram


def check(name, fn):
    fn()
    print(f"PASS  {name}")


def baseline_is_pure_sorted_and_public():
    state = build_state_for("ardenia")
    state.scheduled_events.append({"event_id": "secret_follow_up", "due_turn": 2,
                                   "chance": 1.0})
    before = copy.deepcopy(state)
    items = political_calendar.build_calendar(state)
    assert state == before
    assert items == sorted(items, key=lambda item: (item.date, item.kind, item.id))
    assert any(item.id.startswith("monthly_report:") for item in items)
    assert any(item.id == "fiscal_rollover:1994" for item in items)
    assert not any("secret_follow_up" in item.id for item in items)


def opposition_window_becomes_a_dated_vote():
    state = generate_campaign(CampaignConfig(
        country_id="ardenia", party_id="national_conservatives",
        opening_role="opposition", background_id="none", seed=773))
    initial = political_calendar.build_calendar(state)
    window = next(item for item in initial
                  if item.id == "government_legislative_window")
    assert window.date == state.calendar_date()

    TurnEngine().advance(state)
    items = political_calendar.build_calendar(state)
    vote = next(item for item in items
                if item.id.startswith("decision:government_bill_response:"))
    assert vote.date == date(1993, 4, 22)
    assert not any(item.id == "government_legislative_window" for item in items)


def situation_default_uses_real_month_boundaries():
    state = build_state_for("ardenia")
    state.day = 15
    state.pending_events = [PendingEvent("labour_unrest_spreads", turns_pending=2)]
    item = next(item for item in political_calendar.build_calendar(state)
                if item.id == "decision:situation:labour_unrest_spreads")
    # From 15 March, two remaining monthly pulses means the 1 May pulse.
    assert item.date == date(1993, 5, 1)
    assert item.kind == political_calendar.KIND_DEADLINE


def budget_has_one_honest_calendar_entry():
    state = build_state_for("ardenia")
    state.month = 12
    state.day = 15
    plan = budget.build_proposal(state, {})
    plan.status = "proposed"
    state.pending_budget = plan
    proposed = political_calendar.build_calendar(state)
    assert sum(item.date == date(1994, 1, 1) for item in proposed) == 2, (
        "January should contain the monthly report plus one budget deadline")
    assert any(item.id == "decision:budget_vote:1994" for item in proposed)
    assert not any(item.id == "fiscal_rollover:1994" for item in proposed)

    plan.status = "approved"
    approved = political_calendar.build_calendar(state)
    assert any(item.id == "fiscal_rollover:1994" for item in approved)
    assert not any(item.id == "decision:budget_vote:1994" for item in approved)


def commitments_receive_completion_dates():
    state = build_state_for("ardenia")
    state.regional_programs.append(RegionalProgram(
        id="calendar_program", program_id="industrial_recovery",
        region_id="zavost", started_turn=0, duration=3,
        monthly_cost=100.0, months_active=1))
    state.country.economy.loans.append(Loan(
        id="calendar_loan", lender_id="veldoria", principal=500.0,
        annual_interest_rate=0.05, term_months=6, months_elapsed=4))
    items = political_calendar.build_calendar(state)
    programme = next(item for item in items
                     if item.id == "regional_programme:calendar_program")
    loan = next(item for item in items if item.id == "loan_maturity:calendar_loan")
    assert programme.date == date(1993, 5, 1)
    assert loan.date == date(1993, 5, 1)
    assert programme.page == "Briefing" and loan.page == "Diplomacy"


def imminent_election_uses_the_engine_countdown():
    state = build_state_for("ardenia")
    state.last_election_turn = state.turn - 47
    item = next(item for item in political_calendar.build_calendar(state)
                if item.id == "decision:election_preparation")
    assert item.date == date(1993, 4, 1)
    assert item.page == "Parties"


def terminal_consumes_the_shared_views():
    state = build_state_for("ardenia")
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        print_briefing(state)
    text = output.getvalue()
    assert "DECISIONS AND DEADLINES" in text
    assert "POLITICAL CALENDAR" in text
    assert "Monthly national report" in text
    assert "Choose a governing reform objective" in text


if __name__ == "__main__":
    checks = [
        ("baseline calendar is pure, sorted, and hides future story triggers",
         baseline_is_pure_sorted_and_public),
        ("the opposition's opening window becomes a dated government vote",
         opposition_window_becomes_a_dated_vote),
        ("situation defaults use actual month boundaries",
         situation_default_uses_real_month_boundaries),
        ("a proposed or approved budget has one honest fiscal entry",
         budget_has_one_honest_calendar_entry),
        ("regional programmes and loans receive completion dates",
         commitments_receive_completion_dates),
        ("imminent elections use the engine's countdown",
         imminent_election_uses_the_engine_countdown),
        ("the terminal consumes the shared queue and calendar",
         terminal_consumes_the_shared_views),
    ]
    for label, test in checks:
        check(label, test)
    print(f"ALL {len(checks)} POLITICAL CALENDAR CHECKS PASSED")
