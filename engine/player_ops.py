"""
Player operations — the input-free core of every player action:
op_x(state, ...chosen args...) -> ActionResult, no input()/print(). The CLI
(engine/actions.py) and the GUI both gather choices their own way and call
these same ops, so action logic lives in exactly one place. Cost formulas are
exposed separately so the GUI can show prices up front. ActionResult is
defined here (actions.py imports this module, so the reverse would be circular).
"""

import functools
from dataclasses import dataclass

from models.cabinet import CORE_PORTFOLIOS
from models.modifiers import Modifier
from content.bills import bill_catalog
from content.campaign_content import get_background
from content.regions import ARDENIA_REGION_PROFILES, REGIONAL_PROGRAMS
from engine import (legislative, cabinet_ops, diplomacy, stability, events,
                    flavor, domestic_ai, opposition, regions, budget, reforms)
from engine import opening_programme


@dataclass
class ActionResult:
    success: bool
    message: str


# ── Political capital ────────────────────────────────────────────────────

def can_afford(state, amount: float) -> bool:
    return state.player.political_capital >= amount


def spend(state, amount: float) -> bool:
    if state.player.political_capital < amount:
        return False
    state.player.political_capital -= amount
    return True


def faction_by_id(state, fid):
    return next((f for f in state.country.factions if f.id == fid), None)


# ── Government attention ─────────────────────────────────────────────────
#
# The second constraint, alongside political capital, and a different
# question: capital asks "can you afford this in the chamber", attention asks
# "is this what your government spent the month on". Capital accrues over
# time and can be banked; attention does not — it is reset to
# MONTHLY_ATTENTION's worth of headroom by every monthly pulse
# (engine/turn.py) and unspent attention is simply lost.
#
# The point is triage. With forty operations all priced in one regenerating
# currency, nothing ever forced a choice between problems; three major
# initiatives a month does.

MONTHLY_ATTENTION = 3

ATTENTION_EXHAUSTED_REASON = (
    "Your government has already committed this month. "
    "Attention resets when the month turns.")

# Major initiatives — the things a government can be said to have DONE this
# month. Keys are the op_* function name minus the "op_" prefix, so a caller
# can ask costs_attention("propose_bill") without importing the function.
ATTENTION_OPS = frozenset({
    "propose_bill", "propose_budget", "supplementary_appropriation",
    "adopt_reform_objective", "start_regional_program", "campaign_region",
    "reshuffle", "appoint_minister", "dismiss", "address_nation", "repeal_law",
    # Foreign initiatives: opening a front abroad is a month's work too.
    "trade_agreement", "foreign_loan", "defense_pact", "impose_sanctions",
    "lift_sanctions", "hold_summit", "break_treaty", "condemn",
})

# Everything else is free, and three groups of it are free ON PURPOSE:
#
#   resolve_event      — situations are forced on the player, never chosen.
#                        Gating them would deadlock a game whose only pending
#                        decision it could not afford to take.
#   follow-through     — call_vote, call_budget_vote, lobby_faction,
#                        lobby_budget, withdraw_bill, withdraw_budget. One
#                        policy must not cost attention twice; the initiative
#                        was already paid for when it was introduced.
#   opposition + talk  — every opposition operation, plus courting, grievance
#                        work, improving relations, background moves,
#                        confidence votes and ministry reports. A player out
#                        of office is not running a government, and talking is
#                        not the same as governing.


def attention_remaining(state) -> int:
    return max(0, MONTHLY_ATTENTION - int(getattr(state, "attention_spent", 0)))


def costs_attention(op_key: str) -> bool:
    """Whether an operation consumes one of the month's major initiatives.
    `op_key` is the op_* function name without its prefix."""
    return op_key in ATTENTION_OPS


def has_attention(state, op_key: str) -> bool:
    """True if this operation may proceed on attention grounds — always true
    for free operations, so callers can ask unconditionally."""
    return not costs_attention(op_key) or attention_remaining(state) > 0


def spend_attention(state, op_key: str):
    """Consume one initiative if this op is a major one. Called only AFTER an
    operation has committed, so a failed or refused action never burns the
    month."""
    if costs_attention(op_key):
        state.attention_spent = int(getattr(state, "attention_spent", 0)) + 1


def _attention_blocked(state, op_key: str):
    """ActionResult to return when attention is exhausted, or None to
    proceed. Every gated op goes through this so the refusal is visible and
    identical everywhere, rather than each op inventing its own wording."""
    if has_attention(state, op_key):
        return None
    return ActionResult(False, ATTENTION_EXHAUSTED_REASON)


def needs_attention(op_key: str):
    """Mark an op as a major initiative.

    Applied as a decorator rather than open-coded into each op for two
    reasons. First, the rule then exists once: eighteen hand-written guards
    would drift, and a missed `spend_attention` on one of several success
    paths is exactly the kind of silent hole this mechanic cannot afford.
    Second, it enforces the ordering that matters — attention is checked
    BEFORE the op runs (so nothing is half-done or paid for), and consumed
    only AFTER it reports success (so a refused or failed action never burns
    the month).
    """
    def decorate(fn):
        @functools.wraps(fn)
        def wrapper(state, *args, **kwargs):
            blocked = _attention_blocked(state, op_key)
            if blocked is not None:
                return blocked
            result = fn(state, *args, **kwargs)
            if getattr(result, "success", False):
                spend_attention(state, op_key)
            return result
        wrapper.attention_key = op_key
        return wrapper
    return decorate


# ── Cooldowns ─────────────────────────────────────────────────────────────

def on_cooldown(state, key: str, period: int) -> bool:
    last = state.cooldowns.get(key)
    return last is not None and (state.turn - last) < period


def cooldown_remaining(state, key: str, period: int) -> int:
    last = state.cooldowns.get(key)
    if last is None:
        return 0
    return max(0, period - (state.turn - last))


def start_cooldown(state, key: str):
    state.cooldowns[key] = state.turn


# ── Cost formulas (exposed so the GUI can show a price up front) ──────────

PROPOSAL_COST = {"executive_order": 20.0, "statutory": 5.0, "constitutional": 10.0}
COST_CALL_VOTE = 0.0
COST_WITHDRAW = 0.0
COST_CONFIDENCE_VOTE = 15.0
COST_RESHUFFLE = 15.0
COST_DISMISS = 6.0
COST_IMPROVE_RELATIONS = 10.0
COST_TRADE_AGREEMENT = 15.0
COST_FOREIGN_LOAN = 8.0
COST_CONDEMN = 5.0
COST_CAMPAIGN = 10.0
COST_BUDGET_LOBBY_BASE = 6.0
COST_SUPPORT_GOVERNMENT_BILL = 4.0
COST_OPPOSE_GOVERNMENT_BILL = 6.0
COST_AMEND_GOVERNMENT_BILL = 8.0
COST_ADD_PLEDGE = opposition.PLEDGE_COST
COST_DROP_PLEDGE = opposition.DROP_PLEDGE_COST
COST_CAMPAIGN_PLEDGE = opposition.CAMPAIGN_COST
COST_APPOINT_SHADOW = opposition.SHADOW_APPOINT_COST
REGIONAL_CAMPAIGN_COST = 7.0
REGIONAL_CAMPAIGN_COOLDOWN = 3
COST_ADOPT_REFORM_OBJECTIVE = 4.0
COST_REPLACE_REFORM_OBJECTIVE = 2.0


def cost_propose(bill) -> float:
    return PROPOSAL_COST.get(bill.tier, 8.0)


def cost_repeal(law) -> float:
    """Unpicking a law costs the same political effort its tier demanded to
    pass — constitutional entrenchment cuts both ways."""
    return PROPOSAL_COST.get(law.tier, 8.0)


def cost_lobby(faction) -> float:
    return 6.0 + max(0.0, -faction.loyalty) * 8.0


def cost_court(faction) -> float:
    return 6.0 + max(0.0, -faction.loyalty) * 10.0


def cost_address_grievance(grievance) -> float:
    return 5.0 + grievance.severity * 15.0


def cost_event_option(option) -> float:
    return option.pc_cost


def cost_regional_program(program_id: str) -> float:
    definition = REGIONAL_PROGRAMS.get(program_id)
    return definition["pc_cost"] if definition else 0.0


# ── Candidate listings (shared by both front-ends for their menus) ────────

def proposable_bills(state) -> list:
    live = ({b.id for b in state.legislature.pending_bills} |
            {l.id for l in state.legislature.active_laws})
    return [b for b in bill_catalog() if b.id not in live]


def trade_eligible_countries(state) -> list:
    return [c for c in state.world
            if (state.country.relations.get(c.id) is None or
                state.country.relations.get(c.id).score > -0.2)]


def loan_eligible_countries(state) -> list:
    return [c for c in state.world
            if (state.country.relations.get(c.id) is None or
                state.country.relations.get(c.id).score > -0.5)]


def portfolios(state) -> list:
    return list(CORE_PORTFOLIOS)


def current_pending_event(state):
    """The one situation currently awaiting a player choice, if any."""
    events.prune_ineligible_pending(state)
    return state.pending_events[0] if state.pending_events else None


def regional_programs_for(state, region_id: str) -> list:
    return regions.available_programs(state, region_id)


def reform_objectives(state) -> list:
    return reforms.ranked_objectives(state)


def cost_reform_objective(state) -> float:
    return (COST_REPLACE_REFORM_OBJECTIVE if state.reform_project is not None
            else COST_ADOPT_REFORM_OBJECTIVE)


def op_select_opening_programme(state, programme_id: str) -> ActionResult:
    ok, message = opening_programme.select(state, programme_id)
    if not ok:
        return ActionResult(False, message)
    programme = opening_programme.selected(state)
    state.log(f"FIRST NINETY DAYS — {programme['name']} becomes the "
              f"{'government' if state.player.in_government else 'opposition'} programme.")
    return ActionResult(True, message)


@needs_attention("adopt_reform_objective")
def op_adopt_reform_objective(state, objective_id: str) -> ActionResult:
    definition = reforms.OBJECTIVE_BY_ID.get(objective_id)
    if definition is None:
        return ActionResult(False, "That reform objective does not exist.")
    current = state.reform_project
    if current is not None and current.objective_id == objective_id:
        return ActionResult(False, "That is already your active reform objective.")
    cost = cost_reform_objective(state)
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")
    replaced = current is not None
    project = reforms.adopt_objective(state, objective_id)
    if project is None:
        state.player.political_capital += cost
        return ActionResult(False, "The reform objective could not be diagnosed.")
    role = "government programme" if state.player.in_government else "opposition programme"
    verb = "replaces its previous objective with" if replaced else "adopts"
    state.log(
        f"REFORM OBJECTIVE — The {role} {verb} {definition['name'].lower()}; "
        f"the diagnosis is {reforms.urgency_label(project.diagnosis_score).lower()} "
        f"({project.diagnosis_score*100:.0f}%).")
    opening_programme.note_action(state, "adopt_reform_objective")
    opening_programme.note_action(state, f"reform_objective:{objective_id}")
    return ActionResult(
        True,
        f"{definition['name']} adopted as the active {role} objective — "
        f"{reforms.urgency_label(project.diagnosis_score).lower()} urgency.")


# ── Regional government ─────────────────────────────────────────────────

@needs_attention("start_regional_program")
def op_start_regional_program(state, region_id: str, program_id: str) -> ActionResult:
    ok, reason = regions.can_start_program(state, region_id, program_id)
    if not ok:
        return ActionResult(False, reason)
    definition = REGIONAL_PROGRAMS[program_id]
    cost = definition["pc_cost"]
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")

    regions.start_program(state, region_id, program_id)
    for faction_id, delta in definition.get("faction_loyalty_deltas", {}).items():
        faction = faction_by_id(state, faction_id)
        if faction is not None:
            faction.loyalty = max(-1.0, min(1.0, faction.loyalty + delta))
    region_name = ARDENIA_REGION_PROFILES[region_id]["name"]
    state.log(f"REGIONAL PROGRAMME — {definition['name']} begins in {region_name}; "
              f"the treasury commits {definition['monthly_cost']:.0f} M per month for "
              f"{definition['duration']} months.")
    opening_programme.note_action(state, "regional_programme")
    opening_programme.note_action(state, f"regional_programme:{program_id}")
    return ActionResult(
        True,
        f"{definition['name']} launched in {region_name} — {definition['duration']} months, "
        f"{definition['monthly_cost']:.0f} M/month.")


def can_campaign_region(state, region_id: str):
    region = state.regions.get(region_id)
    if region is None:
        return False, "No regional electorate exists there."
    if regions.electoral_access(state, region_id) <= 0.15:
        return False, "The control line leaves no electorate your party can presently reach."
    own = faction_by_id(state, state.player.faction_id)
    if own is None or own.seats <= 0:
        return False, "Your party has no parliamentary organisation to campaign with."
    key = f"regional_campaign:{region_id}"
    if on_cooldown(state, key, REGIONAL_CAMPAIGN_COOLDOWN):
        left = cooldown_remaining(state, key, REGIONAL_CAMPAIGN_COOLDOWN)
        return False, f"Your organisers need {left} more month(s) before returning."
    return True, ""


@needs_attention("campaign_region")
def op_campaign_region(state, region_id: str) -> ActionResult:
    ok, reason = can_campaign_region(state, region_id)
    if not ok:
        return ActionResult(False, reason)
    if not spend(state, REGIONAL_CAMPAIGN_COST):
        return ActionResult(
            False, f"Not enough political capital (need {REGIONAL_CAMPAIGN_COST:.0f}).")
    own = faction_by_id(state, state.player.faction_id)
    access = regions.electoral_access(state, region_id)
    gain = 0.025 * (0.80 + access * 0.20)
    rival = regions.campaign_in_region(state, region_id, own.id, gain)
    start_cooldown(state, f"regional_campaign:{region_id}")
    region_name = ARDENIA_REGION_PROFILES[region_id]["name"]
    rival_name = rival.name if rival is not None else "the local opposition"
    state.log(f"REGIONAL CAMPAIGN — {own.name} tours {region_name}, taking ground from "
              f"{rival_name} and building a local organisation.")
    opening_programme.note_action(state, "regional_campaign")
    return ActionResult(
        True, f"Campaign completed in {region_name}; {own.name} gain local ground "
        f"from {rival_name}.")


# ── Legislative operations ────────────────────────────────────────────────

@needs_attention("propose_bill")
def op_propose_bill(state, bill) -> ActionResult:
    cost = cost_propose(bill)
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")

    if bill.tier == "executive_order":
        legislative.enact_executive_order(state, bill)
        opening_programme.note_action(state, "propose_bill")
        opening_programme.note_action(state, f"propose_bill:{bill.id}")
        return ActionResult(True, f"\"{bill.name}\" enacted by executive order — no vote required.")

    bill.status = "proposed"
    bill.proposed_by = "player"
    state.legislature.pending_bills.append(bill)
    opposition.note_player_proposal(state, bill.id)
    opening_programme.note_action(state, "propose_bill")
    opening_programme.note_action(state, f"propose_bill:{bill.id}")
    return ActionResult(True, f"\"{bill.name}\" proposed. Call a vote when ready, "
                               f"or lobby factions to build support first.")


def op_lobby_faction(state, bill, faction) -> ActionResult:
    cost = cost_lobby(faction)
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")

    current = bill.lobbying_bonus.get(faction.id, 0.0)
    bill.lobbying_bonus[faction.id] = min(0.5, current + 0.22)
    return ActionResult(True, f"Lobbied {faction.name} on \"{bill.name}\". "
                               f"Their support shifts favourably for this vote.")


def op_call_vote(state, bill) -> ActionResult:
    passed = legislative.resolve_vote(state, bill)
    verdict = "PASSED" if passed else "FAILED"
    return ActionResult(True, f"\"{bill.name}\" {verdict} — {bill.votes_for}-{bill.votes_against}.")


def op_withdraw_bill(state, bill) -> ActionResult:
    state.legislature.pending_bills = [b for b in state.legislature.pending_bills if b.id != bill.id]
    return ActionResult(True, f"Withdrew \"{bill.name}\" before it could come to a vote.")


# ── Annual appropriations ────────────────────────────────────────────────

def cost_budget_proposal(state, plan) -> float:
    return budget.proposal_cost(state, plan)


@needs_attention("propose_budget")
def op_propose_budget(state, plan) -> ActionResult:
    if not state.player.in_government:
        return ActionResult(False, "Only the sitting government can introduce appropriations.")
    if state.pending_budget is not None and state.pending_budget.status in ("proposed", "approved"):
        return ActionResult(False, "A budget for the next fiscal year is already before parliament.")
    try:
        budget.validate_proposal(state, plan)
    except ValueError as exc:
        return ActionResult(False, str(exc))
    cost = cost_budget_proposal(state, plan)
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")
    plan.status = "proposed"
    plan.source = "player"
    plan.proposed_by = state.player.faction_id
    plan.proposed_turn = state.turn
    state.pending_budget = plan
    state.log(f"APPROPRIATIONS — the government tables a {plan.year} budget of "
              f"{plan.expenditure:,.0f} M.")
    return ActionResult(True, f"The {plan.year} budget is before parliament. Lobby or call the vote.")


def op_lobby_budget(state, faction_id: str) -> ActionResult:
    plan = state.pending_budget
    if not state.player.in_government or plan is None or plan.status != "proposed":
        return ActionResult(False, "No government budget is awaiting a vote.")
    faction = faction_by_id(state, faction_id)
    if faction is None or faction.seats <= 0:
        return ActionResult(False, "That faction has no parliamentary delegation to lobby.")
    cost = COST_BUDGET_LOBBY_BASE + faction.power * 6.0
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")
    plan.lobbying_bonus[faction.id] = min(
        0.50, plan.lobbying_bonus.get(faction.id, 0.0) + 0.22)
    return ActionResult(True, f"Lobbied {faction.name} on the {plan.year} budget.")


def op_call_budget_vote(state) -> ActionResult:
    plan = state.pending_budget
    if not state.player.in_government or plan is None or plan.status != "proposed":
        return ActionResult(False, "No government budget is awaiting a vote.")
    vote_bill = budget.as_vote_bill(state, plan)
    votes_for, votes_against, _ = legislative.projected_votes(state, vote_bill)
    threshold = state.legislature.majority_threshold()
    plan.votes_for = votes_for
    plan.votes_against = votes_against
    passed = votes_for >= threshold
    if passed:
        plan.status = "approved"
        state.log(f"BUDGET PASSED — the {plan.year} appropriations carry "
                  f"{votes_for}-{votes_against}; they take effect on 1 January.")
        verdict = "PASSED"
    else:
        plan.status = "rejected"
        state.budget_history.append(plan)
        state.pending_budget = None
        state.player.approval = max(0.0, state.player.approval - 0.015)
        state.log(f"BUDGET DEFEATED — the {plan.year} appropriations fail "
                  f"{votes_for}-{votes_against}. The government must return with a revision.")
        verdict = "FAILED"
    for faction, wing, seats, direction in legislative.vote_rebellions(state, vote_bill):
        wing.loyalty = max(-1.0, wing.loyalty - 0.025)
        state.log(f"BUDGET REBELLION — {seats} {faction.name} deputies from "
                  f"{wing.name} vote {direction} their party line.")
    return ActionResult(True, f"{plan.year} budget {verdict} — {votes_for}-{votes_against}.")


def op_withdraw_budget(state) -> ActionResult:
    plan = state.pending_budget
    if not state.player.in_government or plan is None or plan.status != "proposed":
        return ActionResult(False, "No government budget can be withdrawn.")
    plan.status = "rejected"
    state.budget_history.append(plan)
    state.pending_budget = None
    return ActionResult(True, f"Withdrew the {plan.year} budget for revision.")



# ── Supplementary appropriation (mid-year fiscal room) ───────────────────

COST_SUPPLEMENTARY_BASE = 14.0      # a premium over an ordinary statutory bill (5 PC)
COST_SUPPLEMENTARY_ESCALATION = 8.0  # added per supplementary already won this year


def cost_supplementary(state) -> float:
    """Priced above an ordinary bill, and rising with each one already taken
    this fiscal year: the first is an emergency, the third is a habit."""
    already = budget.supplementaries_this_year(state)
    return COST_SUPPLEMENTARY_BASE + COST_SUPPLEMENTARY_ESCALATION * already


def can_supplementary(state, portfolio: str = None):
    """(ok, reason) — everything that gates a supplementary except the money
    and the vote itself. Shared by both front-ends so a disabled button and a
    refused op always give the same account of why."""
    if not state.player.in_government:
        return False, "Only the sitting government can move an appropriation."
    if state.active_budget is None:
        return False, "No budget is in effect to supplement."
    if on_cooldown(state, "supplementary", budget.SUPPLEMENTARY_COOLDOWN):
        left = cooldown_remaining(state, "supplementary", budget.SUPPLEMENTARY_COOLDOWN)
        return False, (f"The chamber will not hear another supplementary for "
                       f"{left} more month(s).")
    if portfolio is not None:
        if portfolio not in CORE_PORTFOLIOS:
            return False, "That is not a cabinet portfolio."
        if budget.supplementary_cap(state, portfolio) <= 0:
            return False, f"{portfolio} has no annual appropriation to supplement."
    return True, ""


@needs_attention("supplementary_appropriation")
def op_supplementary_appropriation(state, portfolio: str, amount: float) -> ActionResult:
    """Move an in-year appropriation for one ministry, and put it to the chamber.

    The annual budget is January-gated; this is the only way to answer a
    fiscal problem the player can see in April. It is deliberately expensive
    on every axis the game has — attention, political capital at a premium,
    an escalating price within the year, and a four-month cooldown — because
    the point is to make the January settlement matter, not to route around
    it.

    The vote is the real one: budget.as_supplementary_vote_bill builds the
    equivalent appropriation and runs it through the same
    legislative.projected_votes / majority-threshold / vote_rebellions path
    the annual budget uses. A defeat costs the capital and the attention and
    returns nothing, exactly as a lost budget does.
    """
    ok, reason = can_supplementary(state, portfolio)
    if not ok:
        return ActionResult(False, reason)

    cap = budget.supplementary_cap(state, portfolio)
    amount = float(amount)
    if amount <= 0:
        return ActionResult(False, "A supplementary must ask for a positive sum.")
    if amount > cap + 1e-6:
        return ActionResult(
            False,
            f"A supplementary may not exceed {budget.SUPPLEMENTARY_CAP_FRACTION*100:.0f}% "
            f"of {portfolio}'s annual appropriation ({cap:,.0f} M).")

    cost = cost_supplementary(state)
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")

    vote_bill = budget.as_supplementary_vote_bill(state, portfolio, amount)
    votes_for, votes_against, _ = legislative.projected_votes(state, vote_bill)
    threshold = state.legislature.majority_threshold()
    passed = votes_for >= threshold

    # The cooldown starts whether or not it carried: the chamber's patience is
    # spent by being asked, not by agreeing.
    start_cooldown(state, "supplementary")

    for faction, wing, seats, direction in legislative.vote_rebellions(state, vote_bill):
        wing.loyalty = max(-1.0, wing.loyalty - 0.025)
        state.log(f"SUPPLEMENTARY REBELLION — {seats} {faction.name} deputies from "
                  f"{wing.name} vote {direction} their party line.")

    if not passed:
        state.player.approval = max(0.0, state.player.approval - 0.01)
        state.log(f"SUPPLEMENTARY DEFEATED — the chamber refuses {amount:,.0f} M for "
                  f"{portfolio} by {votes_against}-{votes_for}.")
        return ActionResult(
            False,
            f"The {portfolio} supplementary fails {votes_for}-{votes_against}. "
            f"The money is refused and the government looks weaker for asking.")

    budget.apply_supplementary(state, portfolio, amount)
    state.log(f"SUPPLEMENTARY PASSED — the chamber votes {amount:,.0f} M in extra "
              f"{portfolio} funding for the rest of {state.year}, {votes_for}-{votes_against}.")
    return ActionResult(
        True,
        f"{portfolio} supplementary of {amount:,.0f} M carries {votes_for}-{votes_against}. "
        f"The department is funded for the remainder of {state.year}; next year's "
        f"baseline is unchanged.")

# ── Opposition responses to the domestic government ─────────────────────

def government_bill(state):
    return domestic_ai.current_government_bill(state)


def _can_respond_to_government_bill(state, bill_id):
    if state.player.in_government:
        return None, "You are the government, not the opposition."
    bill = government_bill(state)
    if bill is None or bill.id != bill_id:
        return None, "There is no government bill awaiting your response."
    if domestic_ai.response_for(state, bill.id):
        return None, "Your party has already declared its position on this bill."
    return bill, ""


def op_support_government_bill(state, bill_id: str) -> ActionResult:
    bill, error = _can_respond_to_government_bill(state, bill_id)
    if error:
        return ActionResult(False, error)
    if not spend(state, COST_SUPPORT_GOVERNMENT_BILL):
        return ActionResult(False, f"Not enough political capital (need {COST_SUPPORT_GOVERNMENT_BILL:.0f}).")
    own = faction_by_id(state, state.player.faction_id)
    current = bill.lobbying_bonus.get(own.id, 0.0)
    bill.lobbying_bonus[own.id] = min(0.65, current + 0.45)
    # Cooperation is rewarded when it is ideologically credible and costs a
    # little distinctiveness when it is not.
    if bill.ideology and own.ideology.distance_to(bill.ideology) <= 0.75:
        own.support = min(0.85, own.support + 0.004)
    else:
        own.support = max(0.01, own.support - 0.004)
    domestic_ai.record_response(state, bill.id, "support")
    opposition.note_response(state, bill, "support")
    opening_programme.note_action(state, "respond_government_bill")
    state.log(f"OPPOSITION RESPONSE — {own.name} will support \"{bill.name}\".")
    return ActionResult(True, f"Your party declares support for \"{bill.name}\".")


def op_oppose_government_bill(state, bill_id: str) -> ActionResult:
    bill, error = _can_respond_to_government_bill(state, bill_id)
    if error:
        return ActionResult(False, error)
    if not spend(state, COST_OPPOSE_GOVERNMENT_BILL):
        return ActionResult(False, f"Not enough political capital (need {COST_OPPOSE_GOVERNMENT_BILL:.0f}).")
    own = faction_by_id(state, state.player.faction_id)
    current = bill.lobbying_bonus.get(own.id, 0.0)
    bill.lobbying_bonus[own.id] = max(-0.65, current - 0.65)
    own.support = min(0.85, own.support + 0.008)
    ruling = faction_by_id(state, state.ruling_faction_id)
    if ruling is not None:
        ruling.support = max(0.01, ruling.support - 0.004)
    domestic_ai.record_response(state, bill.id, "oppose")
    opposition.note_response(state, bill, "oppose")
    opening_programme.note_action(state, "respond_government_bill")
    state.log(f"OPPOSITION RESPONSE — {own.name} orders its deputies to oppose \"{bill.name}\".")
    return ActionResult(True, f"Your party launches formal opposition to \"{bill.name}\".")


def op_amend_government_bill(state, bill_id: str) -> ActionResult:
    bill, error = _can_respond_to_government_bill(state, bill_id)
    if error:
        return ActionResult(False, error)
    if not spend(state, COST_AMEND_GOVERNMENT_BILL):
        return ActionResult(False, f"Not enough political capital (need {COST_AMEND_GOVERNMENT_BILL:.0f}).")
    own = faction_by_id(state, state.player.faction_id)
    if bill.ideology is not None:
        # Pull the proposal one quarter of the way toward the player's stated
        # position. This changes wing affinity as well as the headline label.
        bill.ideology.economic += (state.player.ideology_economic - bill.ideology.economic) * 0.25
        bill.ideology.social += (state.player.ideology_social - bill.ideology.social) * 0.25
    bill.effects.faction_loyalty_deltas[own.id] = \
        bill.effects.faction_loyalty_deltas.get(own.id, 0.0) + 0.10
    bill.lobbying_bonus[own.id] = min(
        0.65, bill.lobbying_bonus.get(own.id, 0.0) + 0.30)
    bill.description += f" Amended in committee after negotiations with {own.name}."
    domestic_ai.record_response(state, bill.id, "amend")
    opposition.note_response(state, bill, "amend")
    opening_programme.note_action(state, "respond_government_bill")
    state.log(f"OPPOSITION AMENDMENT — the government accepts {own.name}'s changes to \"{bill.name}\".")
    return ActionResult(True, f"The government accepts your amendment to \"{bill.name}\".")


def op_add_agenda_pledge(state, bill_id: str) -> ActionResult:
    if not can_afford(state, COST_ADD_PLEDGE):
        return ActionResult(False, f"Not enough political capital (need {COST_ADD_PLEDGE:.0f}).")
    ok, message = opposition.add_pledge(state, bill_id)
    if not ok:
        return ActionResult(False, message)
    spend(state, COST_ADD_PLEDGE)
    opening_programme.note_action(state, "publish_pledge")
    return ActionResult(True, message)


def op_drop_agenda_pledge(state, bill_id: str) -> ActionResult:
    if not can_afford(state, COST_DROP_PLEDGE):
        return ActionResult(False, f"Not enough political capital (need {COST_DROP_PLEDGE:.0f}).")
    ok, message = opposition.drop_pledge(state, bill_id)
    if not ok:
        return ActionResult(False, message)
    spend(state, COST_DROP_PLEDGE)
    return ActionResult(True, message)


def op_campaign_on_pledge(state, bill_id: str) -> ActionResult:
    if not can_afford(state, COST_CAMPAIGN_PLEDGE):
        return ActionResult(False, f"Not enough political capital (need {COST_CAMPAIGN_PLEDGE:.0f}).")
    ok, message, _ = opposition.campaign_on_pledge(state, bill_id)
    if not ok:
        return ActionResult(False, message)
    spend(state, COST_CAMPAIGN_PLEDGE)
    opening_programme.note_action(state, "campaign_pledge")
    state.log(f"OPPOSITION CAMPAIGN — {message}")
    return ActionResult(True, message)


def op_appoint_shadow_minister(state, portfolio: str, minister) -> ActionResult:
    if not can_afford(state, COST_APPOINT_SHADOW):
        return ActionResult(False, f"Not enough political capital (need {COST_APPOINT_SHADOW:.0f}).")
    ok, message = opposition.appoint_shadow(state, portfolio, minister)
    if not ok:
        return ActionResult(False, message)
    spend(state, COST_APPOINT_SHADOW)
    opening_programme.note_action(state, "appoint_shadow")
    state.log(f"SHADOW CABINET — {message}")
    return ActionResult(True, message)


def op_confidence_vote(state) -> ActionResult:
    cost = COST_CONFIDENCE_VOTE
    in_gov = state.player.in_government
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")

    outcome = stability.player_call_confidence_vote(state)
    if outcome == "survived":
        msg = ("The government wins the vote and reasserts its mandate." if in_gov else
               "The government survives your challenge — for now.")
    else:
        msg = ("The government loses the vote — a coalition partner walks." if in_gov else
               "Your gambit pays off — the government loses the vote and a coalition partner walks.")
    return ActionResult(True, msg)


# ── Cabinet operations ────────────────────────────────────────────────────

@needs_attention("reshuffle")
def op_reshuffle(state, portfolio: str, faction_id: str) -> ActionResult:
    cost = COST_RESHUFFLE
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")
    message = cabinet_ops.reshuffle(state, portfolio, faction_id)
    return ActionResult(True, message)


@needs_attention("appoint_minister")
def op_appoint_minister(state, portfolio: str, minister) -> ActionResult:
    """Installs a specific chosen candidate (from cabinet_ops.shortlist) —
    the personality-aware successor to blind reshuffling."""
    cost = COST_RESHUFFLE
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")
    message = cabinet_ops.appoint(state, portfolio, minister)
    faction = faction_by_id(state, minister.faction_id)
    flavor.say(state, "minister_appointed",
               name=minister.name, portfolio=portfolio,
               party=faction.name if faction else "no party",
               trait=(minister.trait_label() or "safe pair of hands").lower())
    return ActionResult(True, message)


@needs_attention("repeal_law")
def op_repeal_law(state, law_id: str) -> ActionResult:
    law = next((l for l in state.legislature.active_laws if l.id == law_id), None)
    if law is None:
        return ActionResult(False, "No such law is on the books.")
    cost = cost_repeal(law)
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")
    message = legislative.repeal_law(state, law)
    return ActionResult(True, message)


@needs_attention("dismiss")
def op_dismiss(state, portfolio: str) -> ActionResult:
    cost = COST_DISMISS
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")
    message = cabinet_ops.dismiss(state, portfolio)
    return ActionResult(True, message)


# ── Diplomatic operations ─────────────────────────────────────────────────

def op_improve_relations(state, country_id: str) -> ActionResult:
    cost = COST_IMPROVE_RELATIONS
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")
    fa_minister = state.cabinet.get("Foreign Affairs")
    competence = fa_minister.implementation_quality() if fa_minister else 0.4
    message = diplomacy.improve_relations(state, country_id, competence)
    return ActionResult(True, message)


@needs_attention("trade_agreement")
def op_trade_agreement(state, country_id: str) -> ActionResult:
    other = state.world_country(country_id)
    if other is None:
        return ActionResult(False, "No such country.")
    if diplomacy.has_treaty(state, country_id, "trade"):
        return ActionResult(False, f"A trade agreement with {other.name} already stands.")
    cost = COST_TRADE_AGREEMENT
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")
    message = diplomacy.propose_trade_agreement(state, country_id)
    return ActionResult(True, message)


@needs_attention("foreign_loan")
def op_foreign_loan(state, country_id: str) -> ActionResult:
    cost = COST_FOREIGN_LOAN
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")
    message = diplomacy.request_foreign_loan(state, country_id)
    return ActionResult(True, message)


@needs_attention("condemn")
def op_condemn(state, country_id: str) -> ActionResult:
    cost = COST_CONDEMN
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")
    message = diplomacy.condemn(state, country_id)
    return ActionResult(True, message)


# ── Faction-outreach operations ───────────────────────────────────────────

def op_address_grievance(state, faction, grievance_index: int) -> ActionResult:
    if grievance_index < 0 or grievance_index >= len(faction.grievances):
        return ActionResult(False, "That grievance no longer exists.")
    grievance = faction.grievances[grievance_index]
    cost = cost_address_grievance(grievance)
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")

    faction.loyalty = min(1.0, faction.loyalty + grievance.severity * 0.3)
    faction.grievances.pop(grievance_index)
    opening_programme.note_action(state, "address_grievance")
    return ActionResult(True, f"Resolved \"{grievance.source}\" for {faction.name}. Loyalty improves.")


def op_court_faction(state, faction) -> ActionResult:
    cost = cost_court(faction)
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")
    faction.loyalty = min(1.0, faction.loyalty + 0.06)
    return ActionResult(True, f"You meet privately with {faction.name} leadership. A small step closer.")


def op_campaign(state) -> ActionResult:
    cost = COST_CAMPAIGN
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")

    own_faction = faction_by_id(state, state.player.faction_id)
    if own_faction is None:
        return ActionResult(False, "Your party no longer holds a seat in the legislature.")

    boost = 0.015
    own_faction.support = min(0.85, own_faction.support + boost)
    rivals = [f for f in state.country.factions if f.id != own_faction.id]
    if rivals:
        biggest_rival = max(rivals, key=lambda f: f.support)
        biggest_rival.support = max(0.01, biggest_rival.support - boost * 0.6)

    return ActionResult(True, f"A renewed campaign push lifts {own_faction.name}'s standing with voters "
                               f"(support now {own_faction.support*100:.1f}%).")


# ── Event operations ──────────────────────────────────────────────────────

def op_resolve_event(state, event_id: str, option_id: str) -> ActionResult:
    pending = next((p for p in state.pending_events if p.event_id == event_id), None)
    if pending is None:
        return ActionResult(False, "That situation is no longer pending.")

    event = events.event_by_id(event_id)
    if not events.available_to_player(state, event):
        events.prune_ineligible_pending(state)
        return ActionResult(False, "That decision belongs to the sitting government, not your office.")
    option = events.option_by_id(event, option_id)
    if option is None:
        return ActionResult(False, "That option no longer exists.")
    if option not in events.available_options(state, event):
        return ActionResult(False, "That option isn't open to someone like you.")

    cost = cost_event_option(option)
    if not spend(state, cost):
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")

    message = events.resolve_event(state, pending, option)
    return ActionResult(True, message)


# ── Diplomacy verbs (depth) ───────────────────────────────────────────────

PACT_COST = 15.0
SANCTIONS_COST = 8.0
LIFT_SANCTIONS_COST = 4.0
SUMMIT_COST = 10.0
SUMMIT_COOLDOWN = 8
PACT_RELATION_FLOOR = 0.45


@needs_attention("defense_pact")
def op_defense_pact(state, country_id: str) -> ActionResult:
    other = state.world_country(country_id)
    if other is None:
        return ActionResult(False, "No such country.")
    rel = state.country.relations.get(country_id)
    if rel is None or rel.score < PACT_RELATION_FLOOR:
        return ActionResult(False, f"{other.name} won't commit to mutual defense at this "
                                   f"level of trust (need relations ≥ {PACT_RELATION_FLOOR:.2f}).")
    if diplomacy.has_treaty(state, country_id, "defense"):
        return ActionResult(False, f"A defense pact with {other.name} already stands.")
    if not spend(state, PACT_COST):
        return ActionResult(False, f"Not enough political capital (need {PACT_COST:.0f}).")
    msg = diplomacy.sign_defense_pact(state, country_id)
    flavor.say(state, "defense_pact", country=other.name,
               leader=other.leader_name or f"{other.name}'s leadership")
    return ActionResult(True, msg)


@needs_attention("impose_sanctions")
def op_impose_sanctions(state, country_id: str) -> ActionResult:
    other = state.world_country(country_id)
    if other is None:
        return ActionResult(False, "No such country.")
    rel = state.country.relations.get(country_id)
    if rel is not None and rel.sanctioned:
        return ActionResult(False, f"{other.name} is already under your sanctions.")
    if rel is not None and rel.score >= 0.2:
        return ActionResult(False, f"Sanctioning a friendly power would be diplomatic "
                                   f"self-harm — relations with {other.name} are too good.")
    if not spend(state, SANCTIONS_COST):
        return ActionResult(False, f"Not enough political capital (need {SANCTIONS_COST:.0f}).")
    msg = diplomacy.impose_sanctions(state, country_id)
    flavor.say(state, "sanctions_imposed", country=other.name,
               leader=other.leader_name or f"{other.name}'s leadership")
    return ActionResult(True, msg)


@needs_attention("lift_sanctions")
def op_lift_sanctions(state, country_id: str) -> ActionResult:
    other = state.world_country(country_id)
    rel = state.country.relations.get(country_id)
    if other is None or rel is None or not rel.sanctioned:
        return ActionResult(False, "There is no sanctions regime to lift there.")
    if not spend(state, LIFT_SANCTIONS_COST):
        return ActionResult(False, f"Not enough political capital (need {LIFT_SANCTIONS_COST:.0f}).")
    msg = diplomacy.lift_sanctions(state, country_id)
    flavor.say(state, "sanctions_lifted", country=other.name)
    return ActionResult(True, msg)


@needs_attention("hold_summit")
def op_hold_summit(state, country_id: str) -> ActionResult:
    other = state.world_country(country_id)
    if other is None:
        return ActionResult(False, "No such country.")
    if on_cooldown(state, "summit", SUMMIT_COOLDOWN):
        left = cooldown_remaining(state, "summit", SUMMIT_COOLDOWN)
        return ActionResult(False, f"The diplomatic calendar is full — next summit in {left} month(s).")
    if not spend(state, SUMMIT_COST):
        return ActionResult(False, f"Not enough political capital (need {SUMMIT_COST:.0f}).")
    msg = diplomacy.hold_summit(state, country_id)
    start_cooldown(state, "summit")
    flavor.say(state, "summit", country=other.name,
               leader=other.leader_name or f"{other.name}'s leadership",
               name=state.player.name)
    return ActionResult(True, msg)


@needs_attention("break_treaty")
def op_break_treaty(state, country_id: str, treaty_id: str) -> ActionResult:
    other = state.world_country(country_id)
    rel = state.country.relations.get(country_id)
    if other is None or rel is None:
        return ActionResult(False, "No such relationship.")
    treaty = next((t for t in rel.treaties if t.id == treaty_id), None)
    if treaty is None:
        return ActionResult(False, "No such treaty.")
    treaty_name = treaty.name
    msg = diplomacy.break_treaty(state, country_id, treaty_id)
    flavor.say(state, "treaty_broken", country=other.name, treaty=treaty_name,
               leader=other.leader_name or f"{other.name}'s leadership")
    return ActionResult(True, msg)


# ── Leadership operations (roleplay) ──────────────────────────────────────

ADDRESS_COST = 8.0
ADDRESS_COOLDOWN = 6
ADDRESS_TONES = ("reassuring", "defiant", "visionary", "contrite")


def background_ability(state):
    """The player's ongoing background ability, or None."""
    bg = get_background(state.campaign_meta.get("background", "none"))
    return bg if bg is not None and bg.action_label else None


def op_background_action(state) -> ActionResult:
    bg = background_ability(state)
    if bg is None:
        return ActionResult(False, "Your past offers no special lever here.")
    if on_cooldown(state, "background_action", bg.action_cooldown):
        left = cooldown_remaining(state, "background_action", bg.action_cooldown)
        return ActionResult(False, f"Too soon — that card can be played again in {left} month(s).")
    if not spend(state, bg.action_cost):
        return ActionResult(False, f"Not enough political capital (need {bg.action_cost:.0f}).")

    if bg.id == "economist":
        state.modifiers.append(Modifier(
            id=f"bg_economist_{state.turn}", source="Steady the Markets",
            target="inflation", magnitude=-0.008,
            onset_delay=0, ramp_duration=1, hold_duration=5, decay_duration=3))
    elif bg.id == "former_general":
        state.stability.value = min(0.95, state.stability.value + 0.05)
        worst = max(state.country.factions, key=lambda f: f.grievance_pressure())
        if worst.grievances:
            worst.grievances[0].severity = max(0.0, worst.grievances[0].severity - 0.15)
        for f in state.country.factions:
            if f.ideology.social < -0.3:
                f.loyalty = min(1.0, f.loyalty + 0.05)
            elif f.ideology.social > 0.5:
                f.loyalty = max(-1.0, f.loyalty - 0.03)
    elif bg.id == "union_leader":
        for f in state.country.factions:
            if f.ideology.economic < -0.3:
                f.loyalty = min(1.0, f.loyalty + 0.06)
                if f.grievances:
                    f.grievances[0].severity = max(0.0, f.grievances[0].severity - 0.2)
    elif bg.id == "business_executive":
        state.modifiers.append(Modifier(
            id=f"bg_exec_{state.turn}", source="Convene the Roundtable",
            target="gdp_growth", magnitude=0.004,
            onset_delay=0, ramp_duration=2, hold_duration=6, decay_duration=3))
        for f in state.country.factions:
            if f.ideology.economic > 0.3:
                f.loyalty = min(1.0, f.loyalty + 0.05)
    elif bg.id == "lawyer":
        if not state.legislature.pending_bills:
            state.player.political_capital += bg.action_cost  # refund; nothing to redraft
            return ActionResult(False, "No pending bills to redraft.")
        for bill in state.legislature.pending_bills:
            for f in state.country.factions:
                if f.seats > 0:
                    cur = bill.lobbying_bonus.get(f.id, 0.0)
                    bill.lobbying_bonus[f.id] = min(0.5, cur + 0.10)
    elif bg.id == "academic":
        state.modifiers.append(Modifier(
            id=f"bg_academic_{state.turn}", source="Publish the Argument",
            target="approval_bias", magnitude=0.015,
            onset_delay=1, ramp_duration=2, hold_duration=6, decay_duration=3))
    elif bg.id == "career_politician":
        state.player.political_capital = min(100.0, state.player.political_capital + 10.0)

    start_cooldown(state, "background_action")
    flavor.say(state, "background_move", name=state.player.name,
               title=state.player.title, deed=bg.action_deed)
    return ActionResult(True, f"{bg.action_label} — done. ({bg.action_blurb})")


@needs_attention("address_nation")
def op_address_nation(state, tone: str) -> ActionResult:
    if tone not in ADDRESS_TONES:
        return ActionResult(False, "That is not a tone you can strike.")
    if on_cooldown(state, "address_nation", ADDRESS_COOLDOWN):
        left = cooldown_remaining(state, "address_nation", ADDRESS_COOLDOWN)
        return ActionResult(False, f"The country heard from you recently — again in {left} month(s).")
    if not spend(state, ADDRESS_COST):
        return ActionResult(False, f"Not enough political capital (need {ADDRESS_COST:.0f}).")

    if tone == "reassuring":
        # Strongest when things are shaky; a calm country barely notices.
        gap = max(0.0, 0.55 - state.stability.value)
        state.stability.value = min(0.95, state.stability.value + gap * 0.5)
    elif tone == "defiant":
        own = faction_by_id(state, state.player.faction_id)
        if own is not None:
            own.support = min(0.85, own.support + 0.02)
        for f in state.country.factions:
            if f.is_hostile():
                f.loyalty = max(-1.0, f.loyalty - 0.04)
    elif tone == "visionary":
        state.modifiers.append(Modifier(
            id=f"address_vision_{state.turn}", source="Address to the Nation",
            target="approval_bias", magnitude=0.012,
            onset_delay=1, ramp_duration=2, hold_duration=6, decay_duration=3))
    elif tone == "contrite":
        # Recovers most when approval has cratered.
        state.player.approval = min(0.95, state.player.approval
                                    + max(0.0, 0.5 - state.player.approval) * 0.25)

    start_cooldown(state, "address_nation")
    opening_programme.note_action(state, "address_nation")
    flavor.say(state, f"address_{tone}", name=state.player.name, title=state.player.title)
    return ActionResult(True, f"You address the nation — {tone}.")
