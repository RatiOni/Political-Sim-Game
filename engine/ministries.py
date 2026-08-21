"""Ministry resources, administrative demand, delivery and accumulated backlog."""

from content.budget import BUDGET_ENVELOPES
from models.cabinet import CORE_PORTFOLIOS
from models.ministry import MinistryState


BASE_WORKLOAD = 0.65
MAX_BACKLOG = 6.0
BACKLOG_RECOVERY_SHARE = 0.22


def _clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def envelope_ids(portfolio: str) -> list[str]:
    return [item["id"] for item in BUDGET_ENVELOPES
            if item.get("portfolio") == portfolio]


def portfolio_funding(state, portfolio: str) -> float:
    """This portfolio's spending power for the CURRENT year.

    Voted envelopes plus any mid-year supplementary appropriation won for it
    (models/budget.py: AnnualBudget.supplements). The supplement is added
    here rather than folded into `allocations` so that it raises capacity now
    without becoming part of the baseline next year's budget is built from.
    """
    if state.active_budget is None:
        return 0.0
    voted = sum(state.active_budget.allocations.get(envelope_id, 0.0)
                for envelope_id in envelope_ids(portfolio))
    return voted + state.active_budget.portfolio_supplement(portfolio)


def initial_ministry_states(state) -> dict[str, MinistryState]:
    out = {}
    for portfolio in CORE_PORTFOLIOS:
        funding = portfolio_funding(state, portfolio)
        out[portfolio] = MinistryState(
            portfolio=portfolio,
            baseline_funding=funding,
            funding=funding,
            delivery=1.0,
        )
    return out


def ensure_ministries(state):
    if not state.ministries:
        state.ministries = initial_ministry_states(state)
    for portfolio in CORE_PORTFOLIOS:
        if portfolio not in state.ministries:
            funding = portfolio_funding(state, portfolio)
            state.ministries[portfolio] = MinistryState(
                portfolio=portfolio,
                baseline_funding=funding,
                funding=funding,
                delivery=1.0,
            )
    return state.ministries


def workload_breakdown(state, portfolio: str) -> dict[str, float]:
    breakdown = {"ordinary administration": BASE_WORKLOAD}

    laws = 0.0
    for law in state.legislature.active_laws:
        if law.portfolio != portfolio:
            continue
        laws += {"constitutional": 0.55, "statutory": 0.38,
                 "executive_order": 0.28}.get(law.tier, 0.35)
    if laws:
        breakdown["active legislation"] = laws

    programmes = 0.0
    if portfolio:
        from content.regions import REGIONAL_PROGRAMS
        for programme in state.regional_programs:
            definition = REGIONAL_PROGRAMS.get(programme.program_id, {})
            if definition.get("portfolio") == portfolio:
                programmes += 0.48
    if programmes:
        breakdown["regional programmes"] = programmes

    situations = 0.0
    if state.pending_events:
        from content.events import event_catalog
        by_id = {event.id: event for event in event_catalog()}
        situations = sum(0.20 for pending in state.pending_events
                         if by_id.get(pending.event_id) is not None
                         and by_id[pending.event_id].portfolio == portfolio)
    if situations:
        breakdown["unresolved situations"] = situations

    if portfolio == "Foreign Affairs":
        treaties = sum(len(relation.treaties)
                       for relation in state.country.relations.values())
        sanctions = sum(1 for relation in state.country.relations.values()
                        if relation.sanctioned)
        if treaties:
            breakdown["treaties"] = treaties * 0.10
        if sanctions:
            breakdown["sanctions"] = sanctions * 0.22
    elif portfolio == "Finance" and state.country.economy.loans:
        breakdown["debt administration"] = len(state.country.economy.loans) * 0.12

    if state.civil_war:
        crisis_load = {
            "Defense": 1.00, "Interior": 0.85, "Justice": 0.45,
            "Economy": 0.35, "Finance": 0.30, "Foreign Affairs": 0.20,
        }.get(portfolio, 0.0)
        if crisis_load:
            breakdown["civil war"] = crisis_load

    if portfolio == "Interior" and state.regions:
        from engine import regions
        pressure = regions.national_pressure(state)
        if pressure > 0.45:
            breakdown["regional pressure"] = (pressure - 0.45) * 0.90
    return breakdown


def _minister_quality(state, portfolio: str) -> float:
    minister = state.cabinet.get(portfolio)
    return 0.35 if minister is None else minister.implementation_quality()


def operating_capacity(state, ministry: MinistryState) -> tuple[float, float, float]:
    funding = portfolio_funding(state, ministry.portfolio)
    baseline = max(1.0, ministry.baseline_funding)
    funding_ratio = funding / baseline
    funding_factor = 0.65 + 0.35 * _clamp(funding_ratio, 0.50, 1.50)
    state_factor = 0.65 + 0.35 * state.country.bureaucratic_capacity
    leadership_factor = 0.60 + 0.40 * _minister_quality(state, ministry.portfolio)
    stability_factor = 0.80 + 0.20 * state.stability.value
    capacity = 1.45 * funding_factor * state_factor * leadership_factor * stability_factor
    return capacity, funding, funding_ratio


def preview(state, portfolio: str) -> dict:
    ministry = ensure_ministries(state)[portfolio]
    breakdown = workload_breakdown(state, portfolio)
    workload = sum(breakdown.values())
    capacity, funding, funding_ratio = operating_capacity(state, ministry)
    demand = workload + min(ministry.backlog, workload * BACKLOG_RECOVERY_SHARE)
    served = min(demand, capacity)
    delivery = _clamp(served / max(0.01, demand))
    return {
        "breakdown": breakdown,
        "workload": workload,
        "capacity": capacity,
        "funding": funding,
        "funding_ratio": funding_ratio,
        "delivery": delivery,
    }


def simulate_ministries(state):
    """Run once before policy effects so this month's load constrains delivery."""
    for portfolio, ministry in ensure_ministries(state).items():
        snapshot = preview(state, portfolio)
        workload = snapshot["workload"]
        capacity = snapshot["capacity"]
        old_backlog = ministry.backlog
        if capacity >= workload:
            recovered = min(old_backlog, (capacity - workload) * BACKLOG_RECOVERY_SHARE)
            backlog = old_backlog - recovered
        else:
            backlog = old_backlog + workload - capacity
        ministry.funding = snapshot["funding"]
        ministry.funding_ratio = snapshot["funding_ratio"]
        ministry.workload = workload
        ministry.capacity = capacity
        ministry.delivery = snapshot["delivery"]
        ministry.backlog = _clamp(backlog, 0.0, MAX_BACKLOG)
        ministry.workload_breakdown = dict(snapshot["breakdown"])
        if capacity < workload:
            ministry.months_overloaded += 1
        else:
            ministry.months_overloaded = max(0, ministry.months_overloaded - 1)


def current_delivery(state, portfolio: str | None) -> float:
    if portfolio is None:
        return 1.0
    ministry = ensure_ministries(state).get(portfolio)
    return ministry.delivery if ministry is not None else 1.0


def policy_delivery_factor(state, portfolio: str | None) -> float:
    """Moderate multiplier: workload compounds existing implementation, not replaces it."""
    if portfolio is None:
        return 1.0
    return 0.55 + 0.45 * current_delivery(state, portfolio)
