"""A read-only, shared account of what currently needs the player.

The simulation stores decisions in the systems that own them: situations in
``pending_events``, bills in the legislature, the annual settlement in
``pending_budget``, appointments in the cabinet, and so on.  Front-ends should
not each rediscover that state or invent their own urgency rules.  This module
turns the existing state into a small ordered list with stable ids, authority,
deadlines, and destinations.

This is a lens, not a mechanic.  Building the queue never mutates GameState,
advances time, spends political capital, or reveals scheduled hidden events.
"""

from dataclasses import dataclass
from datetime import date, timedelta
from typing import Optional


PRIORITY_REQUIRED = "required"
PRIORITY_URGENT = "urgent"
PRIORITY_PLANNED = "planned"
PRIORITY_OPTIONAL = "optional"
PRIORITY_INFORMATION = "information"

PRIORITY_ORDER = {
    PRIORITY_REQUIRED: 0,
    PRIORITY_URGENT: 1,
    PRIORITY_PLANNED: 2,
    PRIORITY_OPTIONAL: 3,
    PRIORITY_INFORMATION: 4,
}


@dataclass(frozen=True)
class DecisionItem:
    """One stable route from a live condition to the place that handles it."""

    id: str
    priority: str
    tag: str
    title: str
    detail: str
    page: str
    authority: str
    days_remaining: Optional[int] = None
    due_text: str = ""
    due_date: Optional[date] = None
    region_id: Optional[str] = None

    def sort_key(self):
        due = self.days_remaining if self.days_remaining is not None else 10**9
        return (PRIORITY_ORDER.get(self.priority, 99), due, self.id)


def _days_to(state, target: date) -> int:
    return max(0, (target - state.calendar_date()).days)


def _month_start_after(state, months: int) -> date:
    index = (state.month - 1) + max(0, months)
    return date(state.year + index // 12, index % 12 + 1, 1)


def _situation_items(state) -> list[DecisionItem]:
    from engine import events

    out = []
    for pending in state.pending_events:
        event = events.event_by_id(pending.event_id)
        if event is None:
            continue
        pulses_left = max(0, events.EVENT_AUTO_RESOLVE_TURNS + 1
                          - pending.turns_pending)
        due = (f"Defaults in {pulses_left} monthly update(s)"
               if pulses_left else "Default response is imminent")
        out.append(DecisionItem(
            id=f"situation:{pending.event_id}",
            priority=PRIORITY_REQUIRED,
            tag="Situation",
            title=event.title,
            detail="Choose a response or the situation will resolve by its default course.",
            page="Briefing",
            authority=event.audience,
            days_remaining=pulses_left * 30,
            due_text=due,
            due_date=_month_start_after(state, pulses_left),
        ))
    return out


def _bill_items(state) -> list[DecisionItem]:
    from engine import domestic_ai

    out = []
    politics = state.domestic_politics
    responses = politics.get("responses", {})
    introduced_days = politics.get("introduced_days", {})

    for bill in state.legislature.pending_bills:
        belongs_to_player = bill.proposed_by == "player"
        belongs_to_government = bool(bill.proposed_by and not belongs_to_player)

        if not state.player.in_government and belongs_to_government:
            if responses.get(bill.id) is not None:
                continue
            introduced = introduced_days.get(bill.id, state.day_index)
            remaining = max(0, domestic_ai.VOTE_DELAY_DAYS
                            - (state.day_index - introduced))
            priority = PRIORITY_REQUIRED if remaining <= 7 else PRIORITY_URGENT
            out.append(DecisionItem(
                id=f"government_bill_response:{bill.id}",
                priority=priority,
                tag="Chamber",
                title=f"Declare a position on {bill.name}",
                detail="Support it, oppose it, or seek an amendment before the division.",
                page="Policies",
                authority="opposition",
                days_remaining=remaining,
                due_text=f"Government vote in {remaining} day(s)",
                due_date=state.calendar_date() + timedelta(days=remaining),
            ))
            continue

        if state.player.in_government and (belongs_to_player or not belongs_to_government):
            out.append(DecisionItem(
                id=f"player_bill:{bill.id}",
                priority=PRIORITY_PLANNED,
                tag="Chamber",
                title=f"Decide the fate of {bill.name}",
                detail="Lobby for support, call the vote, or withdraw the proposal.",
                page="Policies",
                authority="government",
            ))
    return out


def _budget_items(state) -> list[DecisionItem]:
    if not state.player.in_government:
        return []

    plan = state.pending_budget
    if plan is not None and plan.status == "proposed":
        remaining = _days_to(state, date(plan.year, 1, 1))
        priority = (PRIORITY_REQUIRED if remaining <= 31 else
                    PRIORITY_URGENT if remaining <= 90 else PRIORITY_PLANNED)
        return [DecisionItem(
            id=f"budget_vote:{plan.year}",
            priority=priority,
            tag="Budget",
            title=f"Secure passage of the {plan.year} budget",
            detail="Lobby the chamber, call the vote, or withdraw the proposed settlement.",
            page="Policies",
            authority="government",
            days_remaining=remaining,
            due_text=f"Must be ready for 1 Jan {plan.year} · {remaining} day(s)",
            due_date=date(plan.year, 1, 1),
        )]

    if plan is not None and plan.status == "approved":
        return []

    # The inherited/current settlement is enough early in the year.  From
    # July onward, preparing the next fiscal year becomes a real programme
    # commitment; this telegraphs January without nagging from opening day.
    if state.month < 7:
        return []
    target_year = state.year + 1
    remaining = _days_to(state, date(target_year, 1, 1))
    priority = (PRIORITY_REQUIRED if remaining <= 31 else
                PRIORITY_URGENT if remaining <= 75 else PRIORITY_PLANNED)
    return [DecisionItem(
        id=f"budget_prepare:{target_year}",
        priority=priority,
        tag="Budget",
        title=f"Prepare the {target_year} budget",
        detail="Set the next annual appropriations and put them before parliament.",
        page="Policies",
        authority="government",
        days_remaining=remaining,
        due_text=f"Fiscal year begins in {remaining} day(s)",
        due_date=date(target_year, 1, 1),
    )]


def _cabinet_items(state) -> list[DecisionItem]:
    from models.cabinet import CORE_PORTFOLIOS

    cabinet = state.cabinet if state.player.in_government else state.shadow_cabinet
    vacancies = [portfolio for portfolio in CORE_PORTFOLIOS
                 if cabinet.get(portfolio) is None]
    if not vacancies:
        return []

    names = ", ".join(vacancies)
    if state.player.in_government:
        return [DecisionItem(
            id="cabinet_vacancies",
            priority=PRIORITY_URGENT,
            tag="Cabinet",
            title=(f"Fill {len(vacancies)} cabinet vacancy" if len(vacancies) == 1
                   else f"Fill {len(vacancies)} cabinet vacancies"),
            detail=f"Vacant: {names}. Unstaffed ministries underperform.",
            page="Cabinet",
            authority="government",
        )]

    return [DecisionItem(
        id="shadow_cabinet_vacancies",
        priority=PRIORITY_PLANNED,
        tag="Party",
        title="Complete the shadow cabinet",
        detail=f"Unstaffed opposition briefs: {names}.",
        page="Cabinet",
        authority="opposition",
    )]


def _programme_items(state) -> list[DecisionItem]:
    from engine import opening_programme

    next_task = opening_programme.next_incomplete_task(state)
    if next_task is not None and next_task.get("check") == "reform_objective":
        return []
    if state.reform_project is not None:
        return []

    if state.player.in_government:
        return [DecisionItem(
            id="choose_reform_objective",
            priority=PRIORITY_PLANNED,
            tag="Programme",
            title="Choose a governing reform objective",
            detail="Adopt one live national problem as the purpose of the government programme.",
            page="Policies",
            authority="government",
        )]

    return [DecisionItem(
        id="choose_opposition_objective",
        priority=PRIORITY_OPTIONAL,
        tag="Programme",
        title="Develop an opposition reform objective",
        detail="Record the problem your party intends to address if it wins power.",
        page="Policies",
        authority="opposition",
    )]


def _opposition_platform_items(state) -> list[DecisionItem]:
    from engine import opening_programme

    if state.player.in_government:
        return []
    next_task = opening_programme.next_incomplete_task(state)
    if next_task is not None and next_task.get("check") == "pledge":
        return []
    agenda = state.domestic_politics.get("opposition_agenda", {})
    if agenda.get("pledges"):
        return []
    return [DecisionItem(
        id="opposition_platform",
        priority=PRIORITY_PLANNED,
        tag="Party",
        title="Publish an election platform",
        detail="Your party has no policy pledge on which to campaign.",
        page="Policies",
        authority="opposition",
    )]


def _opening_programme_items(state) -> list[DecisionItem]:
    from engine import opening_programme

    report = opening_programme.progress(state)
    role = opening_programme.role_for(state)
    if report["status"] == "unselected":
        selection_remaining = max(
            0, opening_programme.SELECTION_DEADLINE_DAY - state.day_index)
        if state.day_index <= opening_programme.SELECTION_DEADLINE_DAY:
            priority = PRIORITY_REQUIRED
            remaining = selection_remaining
            due = f"Set the programme within {remaining} day(s)"
        else:
            priority = PRIORITY_URGENT
            remaining = report["days_remaining"]
            due = f"Opening window closes in {remaining} day(s)"
        return [DecisionItem(
            id="select_opening_programme",
            priority=priority,
            tag="Programme",
            title="Choose the first ninety-day programme",
            detail=("Set three public priorities appropriate to your authority. "
                    "The programme guides existing actions and applies no hidden bonuses."),
            page="Briefing",
            authority=role,
            days_remaining=remaining,
            due_text=due,
            due_date=state.calendar_date() + timedelta(days=remaining),
        )]

    if report["status"] != "active":
        return []
    task = opening_programme.next_incomplete_task(state)
    if task is None:
        return []
    remaining = report["days_remaining"]
    priority = PRIORITY_URGENT if remaining <= 15 else PRIORITY_PLANNED
    return [DecisionItem(
        id=f"opening_programme:{task['id']}",
        priority=priority,
        tag="Programme",
        title=task["name"],
        detail=task["body"],
        page=task["page"],
        authority=role,
        days_remaining=remaining,
        due_text=f"First ninety days end in {remaining} day(s)",
        due_date=state.calendar_date() + timedelta(days=remaining),
    )]


def _regional_items(state) -> list[DecisionItem]:
    from content.regions import ARDENIA_REGION_PROFILES

    out = []
    pressured = sorted(
        ((region_id, region) for region_id, region in state.regions.items()
         if region.pressure >= 0.62),
        key=lambda pair: (-pair[1].pressure, pair[0]),
    )
    for region_id, region in pressured[:3]:
        profile = ARDENIA_REGION_PROFILES.get(region_id, {})
        name = profile.get("name", region_id.replace("_", " ").title())
        response = ("Review state reach and consider a regional programme."
                    if state.player.in_government else
                    "The government's weakness creates an opening for regional campaigning.")
        out.append(DecisionItem(
            id=f"regional_pressure:{region_id}",
            priority=PRIORITY_URGENT,
            tag=name,
            title=f"Pressure is mounting in {name}",
            detail=f"Political pressure is {region.pressure*100:.0f}%. {response}",
            page="Briefing",
            authority="government" if state.player.in_government else "opposition",
            region_id=region_id,
        ))
    return out


def _election_items(state) -> list[DecisionItem]:
    from engine import elections

    remaining = elections.days_until_election(state)
    snap = elections.should_trigger_snap_election(state)
    if not snap and remaining > 180:
        return []
    priority = PRIORITY_URGENT if snap or remaining <= 30 else PRIORITY_PLANNED
    title = "Prepare for a possible snap election" if snap else "Prepare for the election"
    detail = ("The governing majority or stability may force an early contest."
              if snap else
              "Review the record, programme, personnel, and regional battlegrounds.")
    return [DecisionItem(
        id="election_preparation",
        priority=priority,
        tag="Election",
        title=title,
        detail=detail,
        page="Parties",
        authority="party",
        days_remaining=0 if snap else remaining,
        due_text="Snap-election conditions are present" if snap
                 else f"Election in {remaining} day(s)",
        due_date=state.calendar_date() if snap
                 else state.calendar_date() + timedelta(days=remaining),
    )]


def _internal_crisis_items(state) -> list[DecisionItem]:
    if state.civil_war:
        return [DecisionItem(
            id="civil_war",
            priority=PRIORITY_URGENT,
            tag="Security",
            title="The state is in civil war",
            detail="Stability, faction grievances, insurgency, and regional authority require attention.",
            page="Briefing",
            authority="government" if state.player.in_government else "party",
        )]
    if state.civil_war_risk >= 0.55:
        return [DecisionItem(
            id="civil_war_risk",
            priority=PRIORITY_URGENT,
            tag="Security",
            title="Civil-war pressure is becoming dangerous",
            detail=f"The risk gauge stands at {state.civil_war_risk*100:.0f}%; inspect its causes before it latches.",
            page="Briefing",
            authority="government" if state.player.in_government else "party",
        )]
    return []


def build_queue(state, include_optional: bool = True) -> list[DecisionItem]:
    """Return the ordered, deduplicated queue for the live state."""

    items = []
    items.extend(_situation_items(state))
    items.extend(_bill_items(state))
    items.extend(_budget_items(state))
    items.extend(_cabinet_items(state))
    items.extend(_opening_programme_items(state))
    items.extend(_programme_items(state))
    items.extend(_opposition_platform_items(state))
    items.extend(_regional_items(state))
    items.extend(_election_items(state))
    items.extend(_internal_crisis_items(state))

    unique = {}
    for item in items:
        if not include_optional and item.priority in (PRIORITY_OPTIONAL,
                                                       PRIORITY_INFORMATION):
            continue
        unique.setdefault(item.id, item)
    return sorted(unique.values(), key=lambda item: item.sort_key())


def priority_counts(items: list[DecisionItem]) -> dict[str, int]:
    counts = {priority: 0 for priority in PRIORITY_ORDER}
    for item in items:
        counts[item.priority] = counts.get(item.priority, 0) + 1
    return counts
