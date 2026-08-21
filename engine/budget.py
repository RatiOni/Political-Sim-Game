"""Annual appropriations, parliamentary support and fiscal-year rollover."""

import copy

from content.budget import BUDGET_ENVELOPES, ENVELOPE_BY_ID
from models.budget import AnnualBudget
from models.modifiers import Modifier
from models.faction import Ideology
from models.legislature import Law, LawEffect
from engine import legislative


MIN_TOTAL_FACTOR = 0.70
MAX_TOTAL_FACTOR = 1.30
CONTINUING_CUT = 0.03


def default_allocations(expenditure: float) -> dict[str, float]:
    """Split an existing structural total across the stable envelope shares."""
    total = max(0.0, float(expenditure))
    out = {}
    used = 0.0
    for item in BUDGET_ENVELOPES[:-1]:
        amount = round(total * item["share"], 1)
        out[item["id"]] = amount
        used += amount
    out[BUDGET_ENVELOPES[-1]["id"]] = round(total - used, 1)
    return out


def _normalise_plan_envelopes(plan: AnnualBudget | None):
    """Migrate the original seven-envelope ledger without changing its total."""
    if plan is None:
        return
    expected = set(ENVELOPE_BY_ID)
    current = set(plan.allocations)
    if current == expected:
        return
    if current | {"foreign_affairs"} == expected and "state_administration" in current:
        total = plan.expenditure
        foreign = round(total * ENVELOPE_BY_ID["foreign_affairs"]["share"], 1)
        plan.allocations["foreign_affairs"] = foreign
        plan.allocations["state_administration"] = round(
            max(0.0, plan.allocations["state_administration"] - foreign), 1)
        return
    plan.allocations = default_allocations(plan.expenditure)


def ensure_budget_state(state):
    """Seed campaigns and old saves from their authoritative fiscal baseline."""
    if state.active_budget is None:
        state.active_budget = AnnualBudget(
            year=state.year,
            allocations=default_allocations(state.country.economy.structural_expenditure),
            status="active",
            source="inherited",
            forecast_revenue=state.country.economy.structural_revenue,
        )
    _normalise_plan_envelopes(state.active_budget)
    _normalise_plan_envelopes(state.pending_budget)
    return state.active_budget


def sync_active_total(state, expenditure: float):
    """Keep the displayed envelope ledger aligned with ordinary baseline drift."""
    active = ensure_budget_state(state)
    old_total = active.expenditure
    if old_total <= 0:
        active.allocations = default_allocations(expenditure)
        return
    ratio = max(0.0, expenditure) / old_total
    keys = list(active.allocations)
    used = 0.0
    for key in keys[:-1]:
        active.allocations[key] = round(active.allocations[key] * ratio, 1)
        used += active.allocations[key]
    active.allocations[keys[-1]] = round(max(0.0, expenditure - used), 1)


def on_government_change(state):
    """An unvoted outgoing proposal lapses; an approved settlement survives."""
    plan = state.pending_budget
    if plan is None or plan.status != "proposed":
        return
    plan.status = "rejected"
    state.budget_history.append(plan)
    state.pending_budget = None
    state.log(f"BUDGET LAPSED — the outgoing government's {plan.year} proposal "
              "falls with the change of administration.")


def proposal_year(state) -> int:
    ensure_budget_state(state)
    return max(state.year + 1, state.active_budget.year + 1)


def build_proposal(state, adjustments: dict[str, float]) -> AnnualBudget:
    """Create a detached proposal using percentage changes from the live budget."""
    active = ensure_budget_state(state)
    unknown = set(adjustments) - set(ENVELOPE_BY_ID)
    if unknown:
        raise ValueError(f"unknown budget envelope: {sorted(unknown)[0]}")
    allocations = {}
    for item in BUDGET_ENVELOPES:
        envelope_id = item["id"]
        change = float(adjustments.get(envelope_id, 0.0))
        if change < -0.15 or change > 0.15:
            raise ValueError("each appropriation may change by at most 15%")
        allocations[envelope_id] = round(active.allocations[envelope_id] * (1.0 + change), 1)
    plan = AnnualBudget(
        year=proposal_year(state),
        allocations=allocations,
        status="draft",
        source="player",
        proposed_by=state.player.faction_id,
        forecast_revenue=state.country.economy.budget.revenue,
    )
    validate_proposal(state, plan)
    return plan


def validate_proposal(state, plan: AnnualBudget):
    active = ensure_budget_state(state)
    ids = set(ENVELOPE_BY_ID)
    if set(plan.allocations) != ids:
        raise ValueError("the budget must fund every spending envelope")
    if any(not isinstance(v, (int, float)) or v < 0 for v in plan.allocations.values()):
        raise ValueError("appropriations must be non-negative numbers")
    if plan.year != proposal_year(state):
        raise ValueError(f"the next budget must be for {proposal_year(state)}")
    low = active.expenditure * MIN_TOTAL_FACTOR
    high = active.expenditure * MAX_TOTAL_FACTOR
    if plan.expenditure < low or plan.expenditure > high:
        raise ValueError("total appropriations must remain within 30% of the current budget")
    return True


def proposal_cost(state, plan: AnnualBudget) -> float:
    active = ensure_budget_state(state)
    moved = sum(abs(plan.allocations[k] - active.allocations[k]) for k in active.allocations)
    return min(18.0, 8.0 + 20.0 * moved / max(1.0, active.expenditure))


def _budget_ideology(state, plan: AnnualBudget) -> Ideology:
    """Translate composition and total size into the legislature's shared compass."""
    active = ensure_budget_state(state)
    total_change = (plan.expenditure - active.expenditure) / max(1.0, active.expenditure)
    economic = -min(1.0, max(-1.0, total_change / 0.20))
    social_signal = 0.0
    weight = 0.0
    for item in BUDGET_ENVELOPES:
        base = max(1.0, active.allocations[item["id"]])
        relative = (plan.allocations[item["id"]] - base) / base
        social_signal += relative * item["social_weight"]
        weight += abs(item["social_weight"])
        economic += relative * item["economic_weight"] / 4.0
    social = social_signal / max(0.01, weight / len(BUDGET_ENVELOPES))
    return Ideology(
        economic=max(-1.0, min(1.0, economic)),
        social=max(-1.0, min(1.0, social)),
    )


def as_vote_bill(state, plan: AnnualBudget) -> Law:
    """A non-enactable legislative view used only by the established vote logic."""
    active = ensure_budget_state(state)
    faction_stakes = {}
    for faction in state.country.factions:
        affinity = 1.0 - faction.effective_ideology().distance_to(_budget_ideology(state, plan)) / 2.83
        coalition = 0.06 if faction.in_coalition else -0.02
        fiscal_drag = max(0.0, (plan.expenditure - plan.forecast_revenue) /
                          max(1.0, plan.forecast_revenue))
        austerity_drag = max(0.0, (active.expenditure - plan.expenditure) /
                            max(1.0, active.expenditure))
        stake = (affinity - 0.50) * 0.24 + coalition - fiscal_drag * 0.10
        if faction.ideology.economic < 0:
            stake -= austerity_drag * 0.18
        faction_stakes[faction.id] = max(-0.22, min(0.22, stake))
    law = Law(
        id=f"annual_budget_{plan.year}",
        name=f"{plan.year} Appropriations Bill",
        description="The government's annual authorisation of structural public expenditure.",
        status="proposed",
        tier="statutory",
        ideology=_budget_ideology(state, plan),
        effects=LawEffect(faction_loyalty_deltas=faction_stakes),
        proposed_by=plan.proposed_by or "player",
    )
    law.lobbying_bonus = dict(plan.lobbying_bonus)
    return law


def projected_votes(state, plan: AnnualBudget):
    return legislative.projected_votes(state, as_vote_bill(state, plan))


def vote_rebellions(state, plan: AnnualBudget):
    return legislative.vote_rebellions(state, as_vote_bill(state, plan))


def activate(state, plan: AnnualBudget):
    activated = copy.deepcopy(plan)
    activated.status = "active"
    state.active_budget = activated
    state.country.economy.structural_expenditure = activated.expenditure
    state.budget_history.append(copy.deepcopy(activated))
    return activated


def continuing_budget(state) -> AnnualBudget:
    active = ensure_budget_state(state)
    allocations = {k: round(v * (1.0 - CONTINUING_CUT), 1)
                   for k, v in active.allocations.items()}
    return AnnualBudget(
        year=state.year,
        allocations=allocations,
        status="continuing",
        source="continuing",
        proposed_by=state.ruling_faction_id or "",
        forecast_revenue=state.country.economy.budget.revenue,
    )


def government_ai_budget(state) -> AnnualBudget:
    """A restrained annual plan for the sitting government in opposition games."""
    active = ensure_budget_state(state)
    ruling = next((f for f in state.country.factions
                   if f.id == state.ruling_faction_id), None)
    economic = ruling.ideology.economic if ruling is not None else 0.0
    social = ruling.ideology.social if ruling is not None else 0.0
    changes = {item["id"]: 0.0 for item in BUDGET_ENVELOPES}
    if economic >= 0.2:
        changes.update({
            "state_administration": -0.02,
            "industry_and_jobs": -0.04,
            "health_and_welfare": -0.03,
            "national_defense": 0.03 if social < 0 else 0.0,
        })
    elif economic <= -0.2:
        changes.update({
            "education": 0.03,
            "health_and_welfare": 0.04,
            "industry_and_jobs": 0.03,
            "national_defense": -0.03 if social > -0.4 else 0.0,
        })
    allocations = {k: round(v * (1.0 + changes[k]), 1)
                   for k, v in active.allocations.items()}
    return AnnualBudget(
        year=state.year,
        allocations=allocations,
        status="active",
        source="government_ai",
        proposed_by=state.ruling_faction_id or "",
        forecast_revenue=state.country.economy.budget.revenue,
        votes_for=sum(f.seats for f in state.country.factions if f.in_coalition),
        votes_against=sum(f.seats for f in state.country.factions if not f.in_coalition),
    )


def process_fiscal_year(state):
    """Activate the voted plan on 1 January, or impose a reduced continuation."""
    ensure_budget_state(state)
    if state.month != 1 or state.active_budget.year >= state.year:
        return None
    queued = state.pending_budget
    if queued is not None and queued.year == state.year and queued.status == "approved":
        state.pending_budget = None
        activated = activate(state, queued)
        state.log(f"BUDGET — the {state.year} appropriations take effect at "
                  f"{activated.expenditure:,.0f} M.")
        return activated
    if not state.player.in_government:
        enacted = activate(state, government_ai_budget(state))
        state.pending_budget = None
        ruler = next((f.name for f in state.country.factions
                      if f.id == state.ruling_faction_id), "The government")
        state.log(f"GOVERNMENT BUDGET — {ruler} enacts {state.year} appropriations "
                  f"of {enacted.expenditure:,.0f} M.")
        return enacted
    fallback = continuing_budget(state)
    activate(state, fallback)
    state.pending_budget = None
    state.player.approval = max(0.0, state.player.approval - 0.015)
    state.stability.value = max(0.0, state.stability.value - 0.02)
    state.log(f"BUDGET IMPASSE — no {state.year} appropriations passed. A reduced "
              f"continuing budget of {fallback.expenditure:,.0f} M takes effect.")
    return fallback


def forecast(state, plan: AnnualBudget) -> dict:
    """Read-only projection of what a draft plan would do to ministry
    delivery, before the player commits to it.

    engine/ministries.py: operating_capacity reads funding from
    state.active_budget, so there is no way to ask "what would this draft
    produce" without state.active_budget pointing at it. This function does
    exactly that: swaps it in, calls the SAME ministries.preview() the
    monthly pulse itself calls for every portfolio, then restores the real
    active budget in a finally block. Nothing on state is different before
    and after a call to this function — see smoke_test.py: AG1's purity
    check, which this function is covered by.

    Workload composition (active laws, situations, regional programmes) is
    NOT projected forward — a budget vote does not change what a ministry
    has to do, only what it is funded to do it with — so the projected
    delivery band uses the ministry's CURRENT backlog. That makes this a
    same-month "if this funding applied today" read, not a multi-month
    trajectory; backlog still accumulates or clears at its own pace after
    the plan actually takes effect.
    """
    from engine import ministries as ministry_engine
    from models.ministry import MinistryState
    from models.cabinet import CORE_PORTFOLIOS

    real_active = state.active_budget
    try:
        state.active_budget = plan
        previews = {portfolio: ministry_engine.preview(state, portfolio)
                   for portfolio in CORE_PORTFOLIOS}
    finally:
        state.active_budget = real_active

    ministries_out = {}
    moves = []
    for portfolio in CORE_PORTFOLIOS:
        current = state.ministries.get(portfolio)
        snap = previews[portfolio]
        current_backlog = current.backlog if current is not None else 0.0
        projected = MinistryState(
            portfolio=portfolio, delivery=snap["delivery"], backlog=current_backlog)
        projected_status = projected.status_label()
        current_status = current.status_label() if current is not None else None

        ministries_out[portfolio] = {
            "funding_ratio": snap["funding_ratio"],
            "delivery": snap["delivery"],
            "status": projected_status,
            "current_status": current_status,
        }

        crisis = {"Overloaded", "Failing"}
        was_crisis = current_status in crisis
        will_be_crisis = projected_status in crisis
        if will_be_crisis and not was_crisis:
            moves.append((portfolio, "into", projected_status))
        elif was_crisis and not will_be_crisis:
            moves.append((portfolio, "out of", current_status))

    projected_balance = plan.forecast_revenue - plan.expenditure

    return {
        "year": plan.year,
        "expenditure": plan.expenditure,
        "forecast_revenue": plan.forecast_revenue,
        "projected_balance": projected_balance,
        "ministries": ministries_out,
        "moves": moves,
    }
    return fallback


# ── Supplementary appropriations (mid-year fiscal room) ──────────────────
#
# The annual budget is January-gated, which means eleven months a year the
# largest lever in the game is out of reach even when the player can see
# exactly which ministry needs funding. A supplementary is the release valve:
# real mid-year money, priced and gated hard enough that it never replaces
# the discipline of getting the annual settlement right.

SUPPLEMENTARY_CAP_FRACTION = 0.15   # of that portfolio's current annual appropriation
SUPPLEMENTARY_COOLDOWN = 4          # months between supplementaries
SUPPLEMENTARY_YEAR_KEY = "supplementaries"   # campaign_meta: {year: count}


def portfolio_appropriation(state, portfolio: str) -> float:
    """The VOTED annual appropriation for one portfolio — the base the 15%
    cap is measured against. Deliberately excludes supplements already won,
    so three successive supplementaries cannot ratchet the ceiling upward."""
    active = ensure_budget_state(state)
    from engine import ministries
    return sum(active.allocations.get(envelope_id, 0.0)
               for envelope_id in ministries.envelope_ids(portfolio))


def supplementary_cap(state, portfolio: str) -> float:
    return portfolio_appropriation(state, portfolio) * SUPPLEMENTARY_CAP_FRACTION


def supplementaries_this_year(state) -> int:
    record = state.campaign_meta.get(SUPPLEMENTARY_YEAR_KEY, {})
    return int(record.get(str(state.year), 0)) if isinstance(record, dict) else 0


def note_supplementary(state):
    record = state.campaign_meta.get(SUPPLEMENTARY_YEAR_KEY)
    if not isinstance(record, dict):
        record = {}
    key = str(state.year)
    record[key] = int(record.get(key, 0)) + 1
    state.campaign_meta[SUPPLEMENTARY_YEAR_KEY] = record


def months_remaining_in_year(state) -> int:
    """December is 1 (this month only); January is 12. A supplementary funds
    the rest of the year and no further."""
    return max(1, 13 - int(state.month))


def as_supplementary_vote_bill(state, portfolio: str, amount: float) -> Law:
    """The chamber's view of a supplementary, built through the SAME path an
    annual budget takes to a vote.

    A supplementary is an appropriation, so it is put to the chamber as one:
    this constructs the equivalent AnnualBudget — the live allocations with
    `amount` added to this portfolio's envelopes — and hands it to
    as_vote_bill(). Factions therefore weigh it on exactly the ideology,
    coalition and fiscal-drag terms they weigh the annual settlement on, and
    wing rebellions resolve through legislative.vote_rebellions unchanged.
    There is no second vote model here to drift out of step with the first.
    """
    active = ensure_budget_state(state)
    from engine import ministries
    envelopes = ministries.envelope_ids(portfolio)
    allocations = dict(active.allocations)
    if envelopes:
        share = amount / len(envelopes)
        for envelope_id in envelopes:
            allocations[envelope_id] = allocations.get(envelope_id, 0.0) + share

    plan = AnnualBudget(
        year=active.year,
        allocations=allocations,
        status="proposed",
        source="player",
        proposed_by=state.player.faction_id,
        forecast_revenue=active.forecast_revenue,
    )
    law = as_vote_bill(state, plan)
    law.id = f"supplementary_{portfolio.lower().replace(' ', '_')}_{state.year}_{state.month}"
    law.name = f"{portfolio} Supplementary Appropriation"
    law.description = (f"An in-year authorisation of {amount:,.0f} M in additional "
                       f"spending for {portfolio}, outside the {active.year} settlement.")
    return law


def apply_supplementary(state, portfolio: str, amount: float):
    """Book a won supplementary: spending power now, deficit now, and
    nothing at all next year.

    Two separate channels, on purpose. The ministry's operating capacity
    reads AnnualBudget.supplements (engine/ministries.py: portfolio_funding),
    which dies when January installs a new budget. The Treasury cost is a
    budget_expenditure Modifier held for the rest of the calendar year, so
    the deficit widens through the same non-accumulating pipeline every other
    in-year cost uses. `institutional=False` because parliament voted this
    money: it is spent whether or not the department spends it well, which is
    what delivery already models separately.
    """
    active = ensure_budget_state(state)
    active.supplements[portfolio] = active.portfolio_supplement(portfolio) + amount

    months = months_remaining_in_year(state)
    state.modifiers = [m for m in state.modifiers
                       if m.id != f"supplementary_{portfolio}_{state.year}"]
    state.modifiers.append(Modifier(
        id=f"supplementary_{portfolio}_{state.year}",
        source=f"{portfolio} Supplementary Appropriation",
        target="budget_expenditure",
        magnitude=amount,
        onset_delay=0, ramp_duration=1,
        hold_duration=months, decay_duration=0,
        institutional=False,
    ))
    note_supplementary(state)
    return active.supplements[portfolio]
