"""The dated political future already implied by the live GameState.

This module does not schedule or execute anything.  It gathers known dates
from the decision queue and from existing public commitments: monthly
reports, the opposition government's legislative timetable, fiscal rollover,
elections, regional-programme conclusions, and loan maturities.  Hidden event
follow-ups are intentionally excluded; a calendar should clarify information
the player could know, not reveal future story triggers.
"""

from dataclasses import dataclass
from datetime import date, timedelta
from typing import Optional

from engine import decision_queue


KIND_DEADLINE = "deadline"
KIND_SCHEDULED = "scheduled"
KIND_REPORT = "report"
KIND_COMMITMENT = "commitment"


@dataclass(frozen=True)
class CalendarItem:
    id: str
    date: date
    kind: str
    tag: str
    title: str
    detail: str
    page: str
    authority: str = ""
    decision_id: Optional[str] = None

    def days_from(self, state) -> int:
        return max(0, (self.date - state.calendar_date()).days)


def _month_start_after(state, months: int) -> date:
    index = (state.month - 1) + max(0, months)
    return date(state.year + index // 12, index % 12 + 1, 1)


def _from_decisions(state) -> list[CalendarItem]:
    out = []
    for decision in decision_queue.build_queue(state):
        if decision.due_date is None:
            continue
        out.append(CalendarItem(
            id=f"decision:{decision.id}",
            date=decision.due_date,
            kind=KIND_DEADLINE,
            tag=decision.tag,
            title=decision.title,
            detail=decision.detail,
            page=decision.page,
            authority=decision.authority,
            decision_id=decision.id,
        ))
    return out


def _monthly_report(state) -> CalendarItem:
    return CalendarItem(
        id=f"monthly_report:{state.year}:{state.month}",
        date=_month_start_after(state, 1),
        kind=KIND_REPORT,
        tag="Briefing",
        title="Monthly national report",
        detail="Economic, household, regional, administrative, and political conditions update.",
        page="Briefing",
        authority="state",
    )


def _government_legislative_window(state) -> list[CalendarItem]:
    if state.player.in_government:
        return []

    from engine import domestic_ai

    if domestic_ai.current_government_bill(state) is not None:
        # The known vote date already arrived through the decision queue.
        return []
    if domestic_ai._choose_bill(state) is None:
        # The finite authored catalogue has been exhausted; an old/past
        # next_bill_day no longer promises a sitting the government cannot
        # actually use.
        return []
    next_day = state.domestic_politics.get("next_bill_day")
    # A freshly generated opposition campaign has not asked the domestic-AI
    # controller to initialise its compatibility keys yet. Its real rule is
    # to open the first window immediately, so report today without calling
    # the mutating initialiser merely to populate those keys.
    remaining = 0 if next_day is None else max(0, int(next_day) - state.day_index)
    return [CalendarItem(
        id="government_legislative_window",
        date=state.calendar_date() + timedelta(days=remaining),
        kind=KIND_SCHEDULED,
        tag="Chamber",
        title="Government legislative window",
        detail="The administration is expected to bring the next part of its programme forward.",
        page="Policies",
        authority="government",
    )]


def _fiscal_rollover(state) -> list[CalendarItem]:
    plan = state.pending_budget
    target_year = state.year + 1
    if plan is not None and plan.year >= state.year:
        target_year = plan.year
    target = date(target_year, 1, 1)
    if target < state.calendar_date():
        return []

    if plan is not None and plan.status == "approved":
        title = f"The {plan.year} budget takes effect"
        detail = "Parliament's approved appropriations become the operating baseline."
    elif plan is not None and plan.status == "proposed":
        # The decision queue already contains the passage deadline on this
        # date, so do not add a duplicate fiscal card.
        return []
    elif state.player.in_government:
        title = f"The {target_year} fiscal year begins"
        detail = "A voted settlement must be ready or a reduced continuing budget will take effect."
    else:
        title = f"The {target_year} fiscal year begins"
        detail = "The sitting government will enact the next annual appropriations."

    return [CalendarItem(
        id=f"fiscal_rollover:{target_year}",
        date=target,
        kind=KIND_SCHEDULED,
        tag="Budget",
        title=title,
        detail=detail,
        page="Policies",
        authority="government",
    )]


def _regional_programme_dates(state) -> list[CalendarItem]:
    from content.regions import ARDENIA_REGION_PROFILES, REGIONAL_PROGRAMS

    out = []
    for programme in state.regional_programs:
        definition = REGIONAL_PROGRAMS.get(programme.program_id)
        if definition is None:
            continue
        remaining = max(1, programme.duration - programme.months_active)
        region = ARDENIA_REGION_PROFILES.get(programme.region_id, {})
        region_name = region.get("name", programme.region_id.replace("_", " ").title())
        out.append(CalendarItem(
            id=f"regional_programme:{programme.id}",
            date=_month_start_after(state, remaining),
            kind=KIND_COMMITMENT,
            tag=region_name,
            title=f"{definition['short_name']} concludes",
            detail=f"The programme in {region_name} reaches its scheduled end and leaves ordinary administration to sustain the gains.",
            page="Briefing",
            authority="government",
        ))
    return out


def _loan_dates(state) -> list[CalendarItem]:
    out = []
    for loan in state.country.economy.loans:
        remaining = loan.months_remaining()
        lender = state.world_country(loan.lender_id)
        lender_name = lender.name if lender is not None else loan.lender_id
        out.append(CalendarItem(
            id=f"loan_maturity:{loan.id}",
            date=_month_start_after(state, max(1, remaining)),
            kind=KIND_COMMITMENT,
            tag="Debt",
            title=f"Loan from {lender_name} matures",
            detail=f"The {loan.principal:,.0f} M principal reaches the end of its {loan.term_months}-month term.",
            page="Diplomacy",
            authority="government",
        ))
    return out


def build_calendar(state, horizon_days: int = 365,
                   max_items: Optional[int] = None) -> list[CalendarItem]:
    """Return known public dates from today through the chosen horizon."""

    today = state.calendar_date()
    end = today + timedelta(days=max(0, horizon_days))
    candidates = [_monthly_report(state)]
    candidates.extend(_from_decisions(state))
    candidates.extend(_government_legislative_window(state))
    candidates.extend(_fiscal_rollover(state))
    candidates.extend(_regional_programme_dates(state))
    candidates.extend(_loan_dates(state))

    unique = {}
    for item in candidates:
        if item.date < today or item.date > end:
            continue
        unique.setdefault(item.id, item)
    items = sorted(unique.values(), key=lambda item: (item.date, item.kind, item.id))
    return items if max_items is None else items[:max(0, max_items)]
