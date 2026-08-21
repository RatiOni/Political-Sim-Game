"""
The terminal action menu: each ActionDef pairs a menu descriptor with a
run_* function that gathers targets via choose()/input() and delegates to
engine/player_ops.py. To add an action: write run_*, append an ActionDef to
ACTIONS — the menu picks it up automatically.
"""

from dataclasses import dataclass
from typing import Callable, Optional

from game_state import GameState
from models.cabinet import CORE_PORTFOLIOS
from content.bills import bill_catalog
from content.regions import ARDENIA_REGION_PROFILES, REGIONAL_PROGRAMS
from content.budget import BUDGET_ENVELOPES, BUDGET_ADJUSTMENTS
from engine import (legislative, cabinet_ops, diplomacy, stability, player_ops,
                    events, opposition, regions, budget, ministries, reforms,
                    opening_programme)
from engine.player_ops import ActionResult  # single definition lives in player_ops


@dataclass
class ActionDef:
    id: str
    name: str
    category: str
    cost_hint: str
    description: str
    available: Callable
    run: Callable


# Which menu entries consume one of the month's major initiatives
# (engine/player_ops.py: ATTENTION_OPS). Kept as an explicit map rather than
# derived from ActionDef.id because several menu ids deliberately differ from
# the op they run: "reshuffle" calls op_appoint_minister, "sanctions" covers
# both impose and lift, "summit" runs op_hold_summit, and the two regional
# entries call op_start_regional_program / op_campaign_region.
ACTION_ATTENTION_KEYS = {
    "propose_bill": "propose_bill",
    "repeal_law": "repeal_law",
    "propose_budget": "propose_budget",
    "supplementary_appropriation": "supplementary_appropriation",
    "adopt_reform_objective": "adopt_reform_objective",
    "regional_program": "start_regional_program",
    "regional_campaign": "campaign_region",
    "reshuffle": "appoint_minister",
    "dismiss": "dismiss",
    "address_nation": "address_nation",
    "trade_agreement": "trade_agreement",
    "foreign_loan": "foreign_loan",
    "condemn": "condemn",
    "defense_pact": "defense_pact",
    "sanctions": "impose_sanctions",
    "summit": "hold_summit",
    "break_treaty": "break_treaty",
}


def attention_block_reason(state, action_id: str):
    """Reason string if this menu entry is out of attention, else None.
    The menu shows it as an unavailability reason so a costed action reads as
    DISABLED with a cause, rather than failing silently when chosen."""
    key = ACTION_ATTENTION_KEYS.get(action_id)
    if key is None or player_ops.has_attention(state, key):
        return None
    return "your government has already committed this month"


# ── Shared UI helpers ────────────────────────────────────────────────────

def choose(prompt: str, items: list) -> Optional[str]:
    """
    items: list of (id, label) tuples. Prints a numbered menu and
    returns the chosen id, or None if the player cancels or the list
    is empty.
    """
    if not items:
        print("  (nothing available)")
        return None
    print(f"\n  {prompt}")
    for i, (_id, label) in enumerate(items, 1):
        print(f"  [{i}] {label}")
    print("  [0] Cancel")
    raw = input("  > ").strip()
    if raw in ("", "0"):
        return None
    try:
        idx = int(raw) - 1
        if 0 <= idx < len(items):
            return items[idx][0]
    except ValueError:
        pass
    print("  Invalid selection.")
    return None


def spend(state: GameState, amount: float) -> bool:
    return player_ops.spend(state, amount)


def faction_by_id(state, fid):
    return player_ops.faction_by_id(state, fid)


def _world_targets(state) -> list:
    items = []
    for c in state.world:
        rel = state.country.relations.get(c.id)
        status = rel.status_label() if rel else "unknown"
        items.append((c.id, f"{c.name}  ({c.regime_type}, {status})"))
    return items


# ── Legislative actions ──────────────────────────────────────────────────

PROPOSAL_COST = player_ops.PROPOSAL_COST


def _live_bill_ids(state) -> set:
    return ({b.id for b in state.legislature.pending_bills} |
            {l.id for l in state.legislature.active_laws})


def run_propose_bill(state: GameState) -> ActionResult:
    candidates = player_ops.proposable_bills(state)
    if not candidates:
        return ActionResult(False, "No new bills are ready to propose right now.")

    items = [(b.id, f"[{b.tier[:4].upper()}] {b.name} — {b.description}") for b in candidates]
    chosen_id = choose("Propose which bill?", items)
    if chosen_id is None:
        return ActionResult(False, "Cancelled.")

    bill = next(b for b in candidates if b.id == chosen_id)
    return player_ops.op_propose_bill(state, bill)


def run_adopt_reform_objective(state: GameState) -> ActionResult:
    objectives = player_ops.reform_objectives(state)
    active_id = (state.reform_project.objective_id
                 if state.reform_project is not None else None)
    items = []
    for objective in objectives:
        active = " [ACTIVE]" if objective["id"] == active_id else ""
        items.append((
            objective["id"],
            f"{objective['name']} — {reforms.urgency_label(objective['score'])} "
            f"{objective['score']*100:.0f}%{active}\n"
            f"      {objective['body']}"))
    objective_id = choose("Adopt which reform objective?", items)
    if objective_id is None:
        return ActionResult(False, "Cancelled.")
    return player_ops.op_adopt_reform_objective(state, objective_id)


def run_select_opening_programme(state: GameState) -> ActionResult:
    programmes = opening_programme.candidates(state)
    items = []
    for programme in programmes:
        tasks = "; ".join(task["name"] for task in programme["tasks"])
        items.append((programme["id"],
                      f"{programme['name']} — {programme['body']}\n"
                      f"      Programme: {tasks}"))
    programme_id = choose("Choose the first ninety-day programme:", items)
    if programme_id is None:
        return ActionResult(False, "Cancelled.")
    return player_ops.op_select_opening_programme(state, programme_id)


def run_lobby_faction(state: GameState) -> ActionResult:
    bills = state.legislature.pending_bills
    if not bills:
        return ActionResult(False, "No pending bills to lobby for.")

    bill_id = choose("Lobby support for which bill?", [(b.id, b.name) for b in bills])
    if bill_id is None:
        return ActionResult(False, "Cancelled.")
    bill = next(b for b in bills if b.id == bill_id)

    seated = [f for f in state.country.factions if f.seats > 0]
    faction_id = choose("Lobby which faction?",
                         [(f.id, f"{f.name}  ({f.seats} seats, loyalty {f.loyalty:+.2f})") for f in seated])
    if faction_id is None:
        return ActionResult(False, "Cancelled.")
    faction = faction_by_id(state, faction_id)

    return player_ops.op_lobby_faction(state, bill, faction)


def run_call_vote(state: GameState) -> ActionResult:
    bills = state.legislature.pending_bills
    if not bills:
        return ActionResult(False, "No pending bills to vote on.")

    bill_id = choose("Call a vote on which bill?", [(b.id, b.name) for b in bills])
    if bill_id is None:
        return ActionResult(False, "Cancelled.")
    bill = next(b for b in bills if b.id == bill_id)

    votes_for, votes_against, breakdown = legislative.projected_votes(state, bill)
    threshold = legislative.threshold_for(state, bill)
    print(f"\n  Projected count for \"{bill.name}\"  (need {threshold}):  {votes_for} for / {votes_against} against")
    for name, seats, lean in breakdown:
        stance = "FOR" if lean >= 0 else "against"
        print(f"    {name:<22} {seats:>3} seats   {stance}")
    for faction, wing, seats, direction in legislative.vote_rebellions(state, bill):
        print(f"      ↳ {seats} {faction.name} rebels ({wing.name}) would vote {direction}")

    confirm = input("\n  Proceed with the vote? [y/N] > ").strip().lower()
    if confirm != "y":
        return ActionResult(False, "Vote postponed.")

    return player_ops.op_call_vote(state, bill)


def run_withdraw_bill(state: GameState) -> ActionResult:
    bills = state.legislature.pending_bills
    if not bills:
        return ActionResult(False, "No pending bills to withdraw.")

    bill_id = choose("Withdraw which bill?", [(b.id, b.name) for b in bills])
    if bill_id is None:
        return ActionResult(False, "Cancelled.")

    bill = next(b for b in bills if b.id == bill_id)
    return player_ops.op_withdraw_bill(state, bill)


def _government_bill(state):
    return player_ops.government_bill(state)


def run_support_government_bill(state: GameState) -> ActionResult:
    bill = _government_bill(state)
    if bill is None:
        return ActionResult(False, "No government bill awaits a response.")
    return player_ops.op_support_government_bill(state, bill.id)


def run_oppose_government_bill(state: GameState) -> ActionResult:
    bill = _government_bill(state)
    if bill is None:
        return ActionResult(False, "No government bill awaits a response.")
    return player_ops.op_oppose_government_bill(state, bill.id)


def run_amend_government_bill(state: GameState) -> ActionResult:
    bill = _government_bill(state)
    if bill is None:
        return ActionResult(False, "No government bill awaits a response.")
    return player_ops.op_amend_government_bill(state, bill.id)


def run_add_agenda_pledge(state: GameState) -> ActionResult:
    candidates = opposition.pledge_candidates(state)
    bill_id = choose("Add which promise to your election platform?", [
        (b.id, f"{b.name} — {b.description}") for b in candidates])
    if bill_id is None:
        return ActionResult(False, "Cancelled.")
    return player_ops.op_add_agenda_pledge(state, bill_id)


def run_campaign_pledge(state: GameState) -> ActionResult:
    items = []
    for pledge in opposition.pledges(state):
        bill = opposition.bill_for_pledge(pledge)
        if bill:
            left = opposition.campaign_cooldown_remaining(state, bill.id)
            items.append((bill.id, f"{bill.name}" + (f" [again in {left} mo]" if left else "")))
    bill_id = choose("Campaign on which promise?", items)
    if bill_id is None:
        return ActionResult(False, "Cancelled.")
    return player_ops.op_campaign_on_pledge(state, bill_id)


def run_drop_agenda_pledge(state: GameState) -> ActionResult:
    items = []
    for pledge in opposition.pledges(state):
        bill = opposition.bill_for_pledge(pledge)
        if bill:
            items.append((bill.id, bill.name))
    bill_id = choose("Withdraw which published promise?", items)
    if bill_id is None:
        return ActionResult(False, "Cancelled.")
    return player_ops.op_drop_agenda_pledge(state, bill_id)


def run_appoint_shadow(state: GameState) -> ActionResult:
    portfolio = choose("Fill which shadow portfolio?", [(p, p) for p in CORE_PORTFOLIOS])
    if portfolio is None:
        return ActionResult(False, "Cancelled.")
    candidates = cabinet_ops.shadow_shortlist(state, portfolio)
    minister_id = choose("Appoint whom?", [
        (m.id, f"{m.name} — {m.trait_label() or 'steady'} · "
               f"effectiveness {m.implementation_quality():.2f}")
        for m in candidates])
    if minister_id is None:
        return ActionResult(False, "Cancelled.")
    minister = next(m for m in candidates if m.id == minister_id)
    return player_ops.op_appoint_shadow_minister(state, portfolio, minister)


def run_call_confidence_vote(state: GameState) -> ActionResult:
    cost = player_ops.COST_CONFIDENCE_VOTE
    if state.player.political_capital < cost:
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")

    in_gov = state.player.in_government
    votes_for, votes_against, threshold = stability._confidence_vote_tally(state)
    print(f"\n  Projected confidence vote count (need {threshold}):  "
          f"{votes_for} for / {votes_against} against")
    print(f"  Current government stability: {state.stability.value:.2f} ({state.stability.label()})")
    if in_gov:
        prompt = ("\n  This is a real gamble — a loss costs you a coalition partner, "
                   "stability, and political capital. Proceed? [y/N] > ")
    else:
        prompt = ("\n  As opposition leader, you're forcing THIS vote against the sitting government — "
                   "if it fails to survive, their coalition takes the hit, not yours. Proceed? [y/N] > ")
    confirm = input(prompt).strip().lower()
    if confirm != "y":
        return ActionResult(False, "Decided against it.")

    return player_ops.op_confidence_vote(state)


# ── Annual budget actions ────────────────────────────────────────────────

def run_propose_budget(state: GameState) -> ActionResult:
    budget.ensure_budget_state(state)
    print(f"\n  Draft {budget.proposal_year(state)} appropriations. Each choice changes "
          "that envelope from the current annual baseline.")
    adjustments = {}
    choices = [(str(i), f"{change:+.0%}")
               for i, change in enumerate(BUDGET_ADJUSTMENTS)]
    for item in BUDGET_ENVELOPES:
        current = state.active_budget.allocations[item["id"]]
        picked = choose(f"{item['name']} — currently {current:,.0f} M", choices)
        if picked is None:
            return ActionResult(False, "Budget drafting cancelled.")
        adjustments[item["id"]] = BUDGET_ADJUSTMENTS[int(picked)]
    try:
        plan = budget.build_proposal(state, adjustments)
    except ValueError as exc:
        return ActionResult(False, str(exc))
    print(f"\n  Proposed expenditure: {plan.expenditure:,.0f} M")
    print(f"  Forecast revenue:     {plan.forecast_revenue:,.0f} M")
    print(f"  Forecast balance:     {plan.forecast_balance:+,.0f} M")

    forecast = budget.forecast(state, plan)
    print("\n  Departmental effect of this plan:")
    for portfolio, m in forecast["ministries"].items():
        print(f"    {portfolio:<16} funding {m['funding_ratio']*100:>5.0f}%  "
              f"delivery {m['delivery']*100:>5.0f}%  {m['status']}")
    for portfolio, direction, status in forecast["moves"]:
        print(f"  ⚠ {portfolio} would move {direction} {status.upper()} under this plan.")

    confirm = input(f"  Table this budget for {player_ops.cost_budget_proposal(state, plan):.0f} PC? [y/N] > ").strip().lower()
    if confirm != "y":
        return ActionResult(False, "Budget drafting cancelled.")
    return player_ops.op_propose_budget(state, plan)


def run_lobby_budget(state: GameState) -> ActionResult:
    seated = [f for f in state.country.factions if f.seats > 0]
    faction_id = choose("Lobby which faction on the budget?", [
        (f.id, f"{f.name} — {f.seats} seats") for f in seated])
    if faction_id is None:
        return ActionResult(False, "Cancelled.")
    return player_ops.op_lobby_budget(state, faction_id)


def run_call_budget_vote(state: GameState) -> ActionResult:
    plan = state.pending_budget
    if plan is None:
        return ActionResult(False, "No budget awaits a vote.")
    votes_for, votes_against, breakdown = budget.projected_votes(state, plan)
    threshold = state.legislature.majority_threshold()
    print(f"\n  Projected {plan.year} budget vote (need {threshold}): "
          f"{votes_for} for / {votes_against} against")
    for name, seats, lean in breakdown:
        print(f"    {name:<22} {seats:>3} seats   {'FOR' if lean >= 0 else 'against'}")
    if input("\n  Proceed with the vote? [y/N] > ").strip().lower() != "y":
        return ActionResult(False, "Vote postponed.")
    return player_ops.op_call_budget_vote(state)


def run_withdraw_budget(state: GameState) -> ActionResult:
    return player_ops.op_withdraw_budget(state)


def run_supplementary_appropriation(state: GameState) -> ActionResult:
    """Mid-year money for one ministry, put to a real chamber vote."""
    ok, reason = player_ops.can_supplementary(state)
    if not ok:
        return ActionResult(False, reason)

    ministry_engine = ministries.ensure_ministries(state)
    choices = []
    for portfolio in CORE_PORTFOLIOS:
        cap = budget.supplementary_cap(state, portfolio)
        ministry = ministry_engine.get(portfolio)
        condition = ministry.status_label().lower() if ministry else "unknown"
        choices.append((portfolio,
                        f"{portfolio} — {condition}, up to {cap:,.0f} M"))
    picked = choose("Supplement which department?", choices)
    if picked is None:
        return ActionResult(False, "Supplementary abandoned.")

    cap = budget.supplementary_cap(state, picked)
    cost = player_ops.cost_supplementary(state)
    already = budget.supplementaries_this_year(state)
    print(f"\n{picked} may be voted up to {cap:,.0f} M for the rest of {state.year}.")
    if already:
        print(f"  This is supplementary #{already + 1} this fiscal year — the "
              f"political price has risen to {cost:.0f} PC.")
    fractions = [("0.25", "a quarter of the cap"), ("0.5", "half the cap"),
                 ("1.0", "the full cap")]
    share = choose(f"How much? (costs {cost:.0f} PC, and a vote)", fractions)
    if share is None:
        return ActionResult(False, "Supplementary abandoned.")
    amount = cap * float(share)

    vote_bill = budget.as_supplementary_vote_bill(state, picked, amount)
    votes_for, votes_against, _ = legislative.projected_votes(state, vote_bill)
    print(f"\nProjected division: {votes_for} for, {votes_against} against "
          f"(need {state.legislature.majority_threshold()}).")
    confirm = input(f"  Move {amount:,.0f} M for {picked}? [y/N] > ").strip().lower()
    if confirm != "y":
        return ActionResult(False, "Supplementary abandoned.")
    return player_ops.op_supplementary_appropriation(state, picked, amount)


# ── Cabinet actions ───────────────────────────────────────────────────────

def run_repeal_law(state: GameState) -> ActionResult:
    active = state.legislature.active_laws
    if not active:
        return ActionResult(False, "There are no active laws to repeal.")
    law_id = choose("Repeal which law?", [
        (l.id, f"{l.name}  ({l.tier}, {l.turns_active} mo on the books) — "
               f"{player_ops.cost_repeal(l):.0f} PC")
        for l in active])
    if law_id is None:
        return ActionResult(False, "Cancelled.")
    return player_ops.op_repeal_law(state, law_id)


def _faction_name(state, faction_id: str) -> str:
    f = next((f for f in state.country.factions if f.id == faction_id), None)
    return f.name if f else "independent"


def run_reshuffle(state: GameState) -> ActionResult:
    cost = player_ops.COST_RESHUFFLE
    if state.player.political_capital < cost:
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")

    portfolio = choose("Reshuffle (or fill) which portfolio?",
                        [(p, f"{p}{'  [VACANT]' if state.cabinet.get(p) is None else ''}") for p in CORE_PORTFOLIOS])
    if portfolio is None:
        return ActionResult(False, "Cancelled.")

    candidates = cabinet_ops.shortlist(state, portfolio)
    picked = choose("The shortlist — who gets the brief?", [
        (str(i), f"{c.name}  ({_faction_name(state, c.faction_id)}; "
                 f"{c.trait_label() or 'no notable traits'})  "
                 f"competence {c.effective_competence():.2f}, loyalty {c.loyalty:.2f}")
        for i, c in enumerate(candidates)])
    if picked is None:
        return ActionResult(False, "Cancelled.")
    return player_ops.op_appoint_minister(state, portfolio, candidates[int(picked)])


def run_dismiss(state: GameState) -> ActionResult:
    cost = player_ops.COST_DISMISS
    if state.player.political_capital < cost:
        return ActionResult(False, f"Not enough political capital (need {cost:.0f}).")

    filled = [m.portfolio for m in state.cabinet.ministers]
    if not filled:
        return ActionResult(False, "No ministers to dismiss.")

    portfolio = choose("Dismiss which minister?", [(p, p) for p in sorted(filled)])
    if portfolio is None:
        return ActionResult(False, "Cancelled.")

    return player_ops.op_dismiss(state, portfolio)


def run_ministry_report(state: GameState) -> ActionResult:
    ministries.ensure_ministries(state)
    print("\n  ── MINISTRY DELIVERY ──")
    for portfolio in CORE_PORTFOLIOS:
        snapshot = ministries.preview(state, portfolio)
        ministry = state.ministries[portfolio]
        print(f"  {portfolio:<18} {ministry.status_label():<10}  delivery "
              f"{snapshot['delivery']*100:>3.0f}%  load "
              f"{snapshot['workload']:.2f}/{snapshot['capacity']:.2f}  "
              f"backlog {ministry.backlog:.2f}  funding {snapshot['funding_ratio']*100:.0f}%")
        detail = ", ".join(f"{name} {amount:.2f}"
                           for name, amount in snapshot["breakdown"].items())
        print(f"    {detail}")
    return ActionResult(True, "Ministry delivery report reviewed.")


# ── Diplomatic actions ───────────────────────────────────────────────────

def run_improve_relations(state: GameState) -> ActionResult:
    country_id = choose("Improve relations with which country?", _world_targets(state))
    if country_id is None:
        return ActionResult(False, "Cancelled.")
    return player_ops.op_improve_relations(state, country_id)


def run_trade_agreement(state: GameState) -> ActionResult:
    eligible = player_ops.trade_eligible_countries(state)
    if not eligible:
        return ActionResult(False, "No country is currently willing to discuss trade.")

    country_id = choose("Propose a trade agreement with which country?",
                         [(c.id, f"{c.name}  ({c.regime_type})") for c in eligible])
    if country_id is None:
        return ActionResult(False, "Cancelled.")
    return player_ops.op_trade_agreement(state, country_id)


def run_foreign_loan(state: GameState) -> ActionResult:
    eligible = player_ops.loan_eligible_countries(state)
    if not eligible:
        return ActionResult(False, "No country trusts you enough to lend right now.")

    country_id = choose("Request a loan from which country?",
                         [(c.id, f"{c.name}  ({c.regime_type})") for c in eligible])
    if country_id is None:
        return ActionResult(False, "Cancelled.")
    return player_ops.op_foreign_loan(state, country_id)


def run_condemn(state: GameState) -> ActionResult:
    country_id = choose("Publicly condemn which country?", _world_targets(state))
    if country_id is None:
        return ActionResult(False, "Cancelled.")
    return player_ops.op_condemn(state, country_id)


# ── Faction outreach actions ─────────────────────────────────────────────

def run_address_grievance(state: GameState) -> ActionResult:
    with_grievances = [f for f in state.country.factions if f.grievances]
    if not with_grievances:
        return ActionResult(False, "No faction currently has an active grievance.")

    faction_id = choose("Address a grievance from which faction?",
                         [(f.id, f"{f.name}  ({len(f.grievances)} grievance(s))") for f in with_grievances])
    if faction_id is None:
        return ActionResult(False, "Cancelled.")
    faction = faction_by_id(state, faction_id)

    grievance_items = [(str(i), f"{g.source}  (severity {g.severity:.2f}, {g.turns_active} months old)")
                        for i, g in enumerate(faction.grievances)]
    idx_str = choose("Address which grievance?", grievance_items)
    if idx_str is None:
        return ActionResult(False, "Cancelled.")
    return player_ops.op_address_grievance(state, faction, int(idx_str))


def run_court_faction(state: GameState) -> ActionResult:
    factions = state.country.factions
    if not factions:
        return ActionResult(False, "No factions to court.")

    faction_id = choose("Court which faction?",
                         [(f.id, f"{f.name}  (loyalty {f.loyalty:+.2f})") for f in factions])
    if faction_id is None:
        return ActionResult(False, "Cancelled.")
    faction = faction_by_id(state, faction_id)

    return player_ops.op_court_faction(state, faction)


def run_campaign(state: GameState) -> ActionResult:
    """Direct push on the player's own electoral support, pulled from the
    single strongest rival. Available in or out of government."""
    return player_ops.op_campaign(state)


# ── Regional government ─────────────────────────────────────────────────

def run_regional_program(state: GameState) -> ActionResult:
    region_id = choose("Direct a programme to which region?", [
        (region.id,
         f"{ARDENIA_REGION_PROFILES[region.id]['name']} — "
         f"pressure {region.pressure*100:.0f}%, unemployment "
         f"{region.unemployment*100:.1f}%, state reach {region.state_reach*100:.0f}%, "
         f"leading {regions.leading_party(state, region.id)[0].name if regions.leading_party(state, region.id)[0] else 'none'}")
        for region in state.regions.values()
    ])
    if region_id is None:
        return ActionResult(False, "Cancelled.")

    active = regions.active_program_for(state, region_id)
    if active is not None:
        definition = REGIONAL_PROGRAMS[active.program_id]
        return ActionResult(False, f"{definition['name']} is already active there "
                            f"({active.months_active}/{active.duration} months).")

    programmes = player_ops.regional_programs_for(state, region_id)
    program_id = choose("Launch which programme?", [
        (pid, f"{definition['name']} — {definition['pc_cost']:.0f} PC, "
              f"{definition['monthly_cost']:.0f} M/month for "
              f"{definition['duration']} months — {definition['body']}")
        for pid, definition in programmes
    ])
    if program_id is None:
        return ActionResult(False, "Cancelled.")
    return player_ops.op_start_regional_program(state, region_id, program_id)


def run_campaign_region(state: GameState) -> ActionResult:
    candidates = []
    for region in state.regions.values():
        ok, reason = player_ops.can_campaign_region(state, region.id)
        if ok:
            leader, share = regions.leading_party(state, region.id)
            candidates.append((
                region.id,
                f"{ARDENIA_REGION_PROFILES[region.id]['name']} — leading "
                f"{leader.name if leader else 'none'} {share*100:.0f}%, access "
                f"{regions.electoral_access(state, region.id)*100:.0f}%"))
    region_id = choose("Campaign in which region?", candidates)
    if region_id is None:
        return ActionResult(False, "Cancelled.")
    return player_ops.op_campaign_region(state, region_id)


# ── Event actions ─────────────────────────────────────────────────────────

def run_respond_to_event(state: GameState) -> ActionResult:
    pending = player_ops.current_pending_event(state)
    if pending is None:
        return ActionResult(False, "No situation is currently pending.")

    event = events.event_by_id(pending.event_id)
    print(f"\n  ── {event.title} ──")
    print(f"  {event.description}")

    open_options = events.available_options(state, event)
    items = [(o.id, f"{o.label}  ({o.pc_cost:.0f} PC) — {o.description}") for o in open_options]
    option_id = choose("How do you respond?", items)
    if option_id is None:
        return ActionResult(False, "Deferred — the situation remains pending.")

    return player_ops.op_resolve_event(state, event.id, option_id)


# ── Diplomacy verbs (depth) ───────────────────────────────────────────────

def run_defense_pact(state: GameState) -> ActionResult:
    country_id = choose("A mutual-defense pact with which country?", _world_targets(state))
    if country_id is None:
        return ActionResult(False, "Cancelled.")
    return player_ops.op_defense_pact(state, country_id)


def run_sanctions(state: GameState) -> ActionResult:
    country_id = choose("Sanctions — choose a country (imposes, or lifts an existing regime):",
                        _world_targets(state))
    if country_id is None:
        return ActionResult(False, "Cancelled.")
    rel = state.country.relations.get(country_id)
    if rel is not None and rel.sanctioned:
        return player_ops.op_lift_sanctions(state, country_id)
    return player_ops.op_impose_sanctions(state, country_id)


def run_summit(state: GameState) -> ActionResult:
    country_id = choose("Host a summit with which country?", _world_targets(state))
    if country_id is None:
        return ActionResult(False, "Cancelled.")
    return player_ops.op_hold_summit(state, country_id)


def run_break_treaty(state: GameState) -> ActionResult:
    options = []
    for c in state.world:
        rel = state.country.relations.get(c.id)
        if rel is None:
            continue
        for t in rel.treaties:
            options.append((f"{c.id}|{t.id}",
                            f"{t.name}  ({t.type}, {t.turns_active} mo old)"))
    if not options:
        return ActionResult(False, "You hold no treaties to break.")
    pick = choose("Tear up which treaty?", options)
    if pick is None:
        return ActionResult(False, "Cancelled.")
    cid, tid = pick.split("|", 1)
    return player_ops.op_break_treaty(state, cid, tid)


# ── Leadership actions (roleplay) ─────────────────────────────────────────

def run_background_action(state: GameState) -> ActionResult:
    return player_ops.op_background_action(state)


def run_address_nation(state: GameState) -> ActionResult:
    tone = choose("Strike what tone?", [
        ("reassuring", "Reassuring — steady the country's nerves (best when stability is low)"),
        ("defiant", "Defiant — rally your base, name your enemies"),
        ("visionary", "Visionary — sell the future (slow-building approval)"),
        ("contrite", "Contrite — own the failures (recovers cratered approval)"),
    ])
    if tone is None:
        return ActionResult(False, "You decide against speaking today.")
    return player_ops.op_address_nation(state, tone)


# ── Availability checks ──────────────────────────────────────────────────

def _avail_always(state):
    return True, ""


def _avail_pending_bills(state):
    if state.legislature.pending_bills:
        return True, ""
    return False, "no pending bills"


def _avail_new_bills(state):
    if any(b.id not in _live_bill_ids(state) for b in bill_catalog()):
        return True, ""
    return False, "no new bills available"


def _avail_reform_objective(state):
    objectives = player_ops.reform_objectives(state)
    current_id = (state.reform_project.objective_id
                  if state.reform_project is not None else None)
    if any(objective["id"] != current_id for objective in objectives):
        return True, ""
    return False, "no alternative objective"


def _avail_opening_programme(state):
    if opening_programme.candidates(state):
        return True, ""
    if opening_programme.selected(state) is not None:
        return False, "programme already chosen"
    return False, "opening window has passed"


def _avail_grievances(state):
    if any(f.grievances for f in state.country.factions):
        return True, ""
    return False, "no active grievances"


def _avail_active_laws(state):
    if state.legislature.active_laws:
        return True, ""
    return False, "no active laws"


def _avail_new_budget(state):
    if not state.player.in_government:
        return False, "not in government"
    plan = state.pending_budget
    if plan is not None and plan.status in ("proposed", "approved"):
        return False, ("budget already awaiting a vote" if plan.status == "proposed"
                       else "next budget already approved")
    return True, ""


def _avail_pending_budget(state):
    plan = state.pending_budget
    if not state.player.in_government:
        return False, "not in government"
    if plan is None or plan.status != "proposed":
        return False, "no budget awaiting a vote"
    return True, ""


def _avail_supplementary(state):
    ok, reason = player_ops.can_supplementary(state)
    return (True, "") if ok else (False, reason.rstrip("."))


def _avail_pending_event(state):
    if state.pending_events:
        return True, ""
    return False, "no pending situation"


def _avail_background_action(state):
    bg = player_ops.background_ability(state)
    if bg is None:
        return False, "no background ability"
    if player_ops.on_cooldown(state, "background_action", bg.action_cooldown):
        left = player_ops.cooldown_remaining(state, "background_action", bg.action_cooldown)
        return False, f"again in {left} mo"
    return True, ""


def _avail_address(state):
    if player_ops.on_cooldown(state, "address_nation", player_ops.ADDRESS_COOLDOWN):
        left = player_ops.cooldown_remaining(state, "address_nation", player_ops.ADDRESS_COOLDOWN)
        return False, f"again in {left} mo"
    return True, ""


def _avail_government_bill(state):
    if state.player.in_government:
        return False, "not in opposition"
    bill = player_ops.government_bill(state)
    if bill is None:
        return False, "no government bill awaiting response"
    from engine import domestic_ai
    if domestic_ai.response_for(state, bill.id):
        return False, "position already declared"
    return True, ""


def _avail_add_pledge(state):
    if state.player.in_government:
        return False, "not in opposition"
    if len(opposition.pledges(state)) >= opposition.MAX_PLEDGES:
        return False, "platform is full"
    if not opposition.pledge_candidates(state):
        return False, "no policies available"
    return True, ""


def _avail_agenda(state):
    if state.player.in_government:
        return False, "not in opposition"
    if not opposition.pledges(state):
        return False, "no published pledges"
    return True, ""


def _avail_shadow(state):
    return (True, "") if not state.player.in_government else (False, "already in government")


def _avail_regional_program(state):
    if not state.player.in_government:
        return False, "not in government"
    if not state.regions:
        return False, "no authored regional administration"
    for region_id in state.regions:
        if (regions.active_program_for(state, region_id) is None
                and player_ops.regional_programs_for(state, region_id)):
            return True, ""
    return False, "every reachable region already has a programme"


def _avail_regional_campaign(state):
    if not state.regions:
        return False, "no authored regional electorates"
    for region_id in state.regions:
        ok, _reason = player_ops.can_campaign_region(state, region_id)
        if ok:
            return True, ""
    return False, "no reachable region is ready for another campaign"


def _requires_government(check):
    """Gate an availability check on actually holding power — applied at
    catalog definition so the government/opposition boundary lives here."""
    def wrapped(state):
        if not state.player.in_government:
            return False, "not in government"
        return check(state)
    return wrapped


# ── Catalog ───────────────────────────────────────────────────────────────

ACTIONS = [
    ActionDef("respond_to_event", "Respond to Situation", "Situations", "varies",
              "React to a situation that has come up — each option carries its own cost and trade-offs.",
              _avail_pending_event, run_respond_to_event),

    ActionDef("propose_bill", "Propose Bill", "Legislative", "5-20 PC",
              "Bring a new bill before the legislature, or enact one immediately by executive order.",
              _requires_government(_avail_new_bills), run_propose_bill),
    ActionDef("lobby_faction", "Lobby Faction on Pending Bill", "Legislative", "~6-14 PC",
              "Spend political capital to shift a faction's vote on a specific pending bill.",
              _requires_government(_avail_pending_bills), run_lobby_faction),
    ActionDef("call_vote", "Call Vote", "Legislative", "free",
              "Bring a pending bill to a final vote.",
              _requires_government(_avail_pending_bills), run_call_vote),
    ActionDef("withdraw_bill", "Withdraw Bill", "Legislative", "free",
              "Pull a pending bill before it can fail and embarrass you.",
              _requires_government(_avail_pending_bills), run_withdraw_bill),
    ActionDef("repeal_law", "Repeal a Law", "Legislative", "varies",
              "Strike an active law from the books. Its ongoing effects lapse, the factions "
              "it served resent it, and the governing overhead it consumed is freed.",
              _requires_government(_avail_active_laws), run_repeal_law),
    ActionDef("call_confidence_vote", "Call Confidence Vote", "Legislative", "15 PC",
              "As government: gamble your survival on an existential vote. As opposition: force "
              "the sitting government into one instead — a possible shortcut to a snap election.",
              _avail_always, run_call_confidence_vote),

    ActionDef("propose_budget", "Draft Annual Budget", "Budget", "8-18 PC",
              "Set next year's structural appropriations across seven spending envelopes and "
              "table the result in parliament.",
              _avail_new_budget, run_propose_budget),
    ActionDef("lobby_budget", "Lobby on the Budget", "Budget", "~6-12 PC",
              "Build parliamentary support for the pending appropriations bill.",
              _avail_pending_budget, run_lobby_budget),
    ActionDef("vote_budget", "Call Budget Vote", "Budget", "free",
              "Put the pending annual budget to a recorded parliamentary vote.",
              _avail_pending_budget, run_call_budget_vote),
    ActionDef("withdraw_budget", "Withdraw Budget", "Budget", "free",
              "Pull the pending appropriations and return with a revision.",
              _avail_pending_budget, run_withdraw_budget),
    ActionDef("supplementary_appropriation", "Move a Supplementary", "Budget",
              "14+ PC",
              "Mid-year money for one department, capped at 15% of its annual "
              "appropriation and put to a real chamber vote. Raises spending for "
              "the rest of this year only; next year's baseline is untouched.",
              _avail_supplementary, run_supplementary_appropriation),

    ActionDef("support_government_bill", "Support Government Bill", "Opposition", "4 PC",
              "Lend your party's votes to the government's current proposal. Cooperation "
              "can look responsible or erase your distinctiveness.",
              _avail_government_bill, run_support_government_bill),
    ActionDef("oppose_government_bill", "Oppose Government Bill", "Opposition", "6 PC",
              "Whip your party against the current proposal and make the division an "
              "electoral test of the government.",
              _avail_government_bill, run_oppose_government_bill),
    ActionDef("amend_government_bill", "Negotiate an Amendment", "Opposition", "8 PC",
              "Pull the proposal toward your platform and support the amended settlement.",
              _avail_government_bill, run_amend_government_bill),
    ActionDef("add_agenda_pledge", "Publish Election Pledge", "Opposition", "5 PC",
              "Commit to a real bill you will introduce if elected. Up to three promises form "
              "your government-in-waiting programme.",
              _avail_add_pledge, run_add_agenda_pledge),
    ActionDef("campaign_pledge", "Campaign on a Pledge", "Opposition", "8 PC",
              "Build support and platform credibility. The relevant shadow minister's "
              "effectiveness determines how strongly the issue lands.",
              _avail_agenda, run_campaign_pledge),
    ActionDef("drop_agenda_pledge", "Drop a Pledge", "Opposition", "3 PC",
              "Rewrite your platform at a credibility cost, especially after campaigning on it.",
              _avail_agenda, run_drop_agenda_pledge),
    ActionDef("appoint_shadow", "Appoint Shadow Minister", "Opposition", "6 PC",
              "Build the alternative cabinet that campaigns on your programme and takes office "
              "with you after an election victory.",
              _avail_shadow, run_appoint_shadow),

    ActionDef("reshuffle", "Reshuffle Minister", "Cabinet", "15 PC",
              "Replace or fill a portfolio with an appointee from a faction of your choice.",
              _requires_government(_avail_always), run_reshuffle),
    ActionDef("dismiss", "Dismiss Minister", "Cabinet", "6 PC",
              "Remove a minister without naming a replacement. The post sits vacant.",
              _requires_government(_avail_always), run_dismiss),
    ActionDef("ministry_report", "Inspect Ministry Delivery", "Cabinet", "free",
              "Review each department's funding, live workload, capacity, delivery and backlog.",
              _avail_always, run_ministry_report),

    ActionDef("improve_relations", "Improve Relations", "Diplomatic", "10 PC",
              "Diplomatic outreach to warm relations with another country.",
              _requires_government(_avail_always), run_improve_relations),
    ActionDef("trade_agreement", "Propose Trade Agreement", "Diplomatic", "15 PC",
              "Formalise a trade treaty, growing trade volume and customs revenue over time.",
              _requires_government(_avail_always), run_trade_agreement),
    ActionDef("foreign_loan", "Request Foreign Loan", "Diplomatic", "8 PC",
              "Borrow from another country — fast cash, rising debt, and a sovereignty cost at home.",
              _requires_government(_avail_always), run_foreign_loan),
    ActionDef("condemn", "Condemn a Country", "Diplomatic", "5 PC",
              "Publicly denounce another nation. Plays well with nationalists, costs you the relationship.",
              _requires_government(_avail_always), run_condemn),
    ActionDef("defense_pact", "Defense Pact", "Diplomatic", "15 PC",
              "Bind a friendly power (relations ≥ 0.45) to mutual defense. Deters hostile "
              "moves against you; their rivals take notice.",
              _requires_government(_avail_always), run_defense_pact),
    ActionDef("sanctions", "Sanctions", "Diplomatic", "8 PC",
              "Cut a hostile power off from your markets — their economy bleeds monthly, "
              "yours takes a smaller hit. Choose a sanctioned country again to lift.",
              _requires_government(_avail_always), run_sanctions),
    ActionDef("summit", "Host a Summit", "Diplomatic", "10 PC",
              "A bilateral summit: a real thaw with one country, and the cameras love it.",
              _requires_government(_avail_always), run_summit),
    ActionDef("break_treaty", "Tear Up a Treaty", "Diplomatic", "free",
              "Walk away from a standing treaty. The counterparty — and the world — will "
              "remember it.",
              _requires_government(_avail_always), run_break_treaty),

    ActionDef("address_grievance", "Address Grievance", "Faction Outreach", "varies",
              "Directly resolve a specific faction grievance before it festers further.",
              _requires_government(_avail_grievances), run_address_grievance),
    ActionDef("court_faction", "Court Faction", "Faction Outreach", "~6-16 PC",
              "General political courtship to nudge a faction's loyalty upward.",
              _avail_always, run_court_faction),
    ActionDef("campaign", "Campaign", "Faction Outreach", "10 PC",
              "Push your own party's standing with voters, pulling support from your strongest rival. "
              "Available whether in government or opposition.",
              _avail_always, run_campaign),

    ActionDef("regional_program", "Launch Regional Programme", "Regional", "9-14 PC",
              "Commit the cabinet and treasury to a time-limited intervention in one "
              "region. Local delivery continues month by month after launch.",
              _avail_regional_program, run_regional_program),
    ActionDef("regional_campaign", "Campaign in a Region", "Regional", "7 PC",
              "Build the player's party organisation in one reachable electorate, taking "
              "support from its strongest local rival. Available in government or opposition.",
              _avail_regional_campaign, run_campaign_region),

    ActionDef("opening_programme", "Choose 90-Day Programme", "Leadership", "free",
              "Set three role-appropriate priorities for the opening months. This guides "
              "existing actions and carries no hidden bonuses or penalties.",
              _avail_opening_programme, run_select_opening_programme),

    ActionDef("background_action", "Leadership Move", "Leadership", "varies",
              "Play the card only your past can play — each background has its own signature move.",
              _requires_government(_avail_background_action), run_background_action),
    ActionDef("address_nation", "Address the Nation", "Leadership", "8 PC",
              "Speak to the country directly, in a tone of your choosing — reassure, defy, "
              "inspire, or apologise.",
              _requires_government(_avail_address), run_address_nation),

    ActionDef("adopt_reform_objective", "Adopt Reform Objective", "Reform Design", "2-4 PC",
              "Choose the live social or economic problem your next reform exists to solve. "
              "Available in government or opposition.",
              _avail_reform_objective, run_adopt_reform_objective),
]

CATEGORIES = ["Legislative", "Cabinet", "Diplomatic", "Faction Outreach", "Situations",
              "Leadership", "Opposition", "Regional", "Budget", "Reform Design"]


def actions_in(category: str) -> list:
    return [a for a in ACTIONS if a.category == category]


# ── Menu loop ─────────────────────────────────────────────────────────────

def run_action_menu(state: GameState):
    """Top-level interactive loop for taking an action. Returns when the player backs all the way out."""
    while True:
        print(f"\n  ── ACTIONS ──  (political capital: "
              f"{state.player.political_capital:.0f}  ·  attention: "
              f"{player_ops.attention_remaining(state)}/"
              f"{player_ops.MONTHLY_ATTENTION})")
        cat = choose("Choose a category:", [(c, c) for c in CATEGORIES])
        if cat is None:
            return

        while True:
            options = []
            for a in actions_in(cat):
                ok, reason = a.available(state)
                if ok:
                    blocked = attention_block_reason(state, a.id)
                    if blocked:
                        ok, reason = False, blocked
                tag = "" if ok else f"  [unavailable: {reason}]"
                options.append((a.id, f"{a.name}  ({a.cost_hint}){tag}"))

            action_id = choose(f"{cat} actions:", options)
            if action_id is None:
                break  # back to category selection

            action = next(a for a in ACTIONS if a.id == action_id)
            ok, reason = action.available(state)
            if ok:
                blocked = attention_block_reason(state, action.id)
                if blocked:
                    ok, reason = False, blocked
            if not ok:
                print(f"  Unavailable: {reason}.")
                continue

            result = action.run(state)
            print(f"\n  {'✓' if result.success else '✗'} {result.message}")
