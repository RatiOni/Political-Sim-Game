"""The player's government-in-waiting: pledges, credibility, and shadow team.

Everything durable is stored on GameState.  The agenda itself lives inside
``domestic_politics`` as JSON-friendly data; named shadow ministers use the
existing Cabinet/Minister models so they retain the same competence and
personality mechanics when promoted after an election.
"""

from content.bills import bill_catalog
from models.cabinet import CORE_PORTFOLIOS


MAX_PLEDGES = 3
PLEDGE_COST = 5.0
DROP_PLEDGE_COST = 3.0
CAMPAIGN_COST = 8.0
CAMPAIGN_COOLDOWN = 6
SHADOW_APPOINT_COST = 6.0
_MAX_IDEOLOGY_DISTANCE = 2.83


def _agenda(state) -> dict:
    politics = state.domestic_politics
    agenda = politics.setdefault("opposition_agenda", {})
    agenda.setdefault("pledges", [])
    agenda.setdefault("credibility", 0.50)
    agenda.setdefault("campaign_turns", {})
    agenda.setdefault("mandate_start_turn", None)
    return agenda


def credibility(state) -> float:
    return float(_agenda(state)["credibility"])


def adjust_credibility(state, amount: float):
    """Public hook for opposition-facing situations and campaign content."""
    _shift_credibility(state, amount)


def _shift_credibility(state, amount: float):
    agenda = _agenda(state)
    agenda["credibility"] = max(0.0, min(1.0, agenda["credibility"] + amount))


def pledges(state) -> list[dict]:
    return _agenda(state)["pledges"]


def pledge_for(state, bill_id: str):
    return next((p for p in pledges(state) if p["bill_id"] == bill_id), None)


def bill_for_pledge(pledge):
    return next((b for b in bill_catalog() if b.id == pledge["bill_id"]), None)


def pledge_candidates(state) -> list:
    claimed = {p["bill_id"] for p in pledges(state)}
    live = ({b.id for b in state.legislature.pending_bills} |
            {b.id for b in state.legislature.active_laws})
    return [b for b in bill_catalog()
            if b.tier != "executive_order" and b.id not in claimed and b.id not in live]


def agenda_portfolio(bill) -> str:
    """Every pledge gets a spokesperson, including cross-government bills."""
    return bill.portfolio if bill and bill.portfolio in CORE_PORTFOLIOS else "Economy"


def spokesperson(state, bill):
    return state.shadow_cabinet.get(agenda_portfolio(bill))


def campaign_cooldown_remaining(state, bill_id: str) -> int:
    last = _agenda(state)["campaign_turns"].get(bill_id)
    if last is None:
        return 0
    return max(0, CAMPAIGN_COOLDOWN - (state.turn - last))


def add_pledge(state, bill_id: str) -> tuple[bool, str]:
    if state.player.in_government:
        return False, "Only an opposition party can publish an election pledge."
    if len(pledges(state)) >= MAX_PLEDGES:
        return False, f"Your platform already has its maximum of {MAX_PLEDGES} pledges."
    bill = next((b for b in pledge_candidates(state) if b.id == bill_id), None)
    if bill is None:
        return False, "That policy is not available as a new pledge."
    pledges(state).append({"bill_id": bill.id, "status": "pledged", "campaigns": 0})
    _shift_credibility(state, 0.01)
    return True, f'Published a pledge to enact "{bill.name}" if elected.'


def drop_pledge(state, bill_id: str) -> tuple[bool, str]:
    if state.player.in_government:
        return False, "A governing mandate cannot be quietly rewritten."
    pledge = pledge_for(state, bill_id)
    if pledge is None:
        return False, "That policy is not in your platform."
    bill = bill_for_pledge(pledge)
    pledges(state).remove(pledge)
    _agenda(state)["campaign_turns"].pop(bill_id, None)
    # Abandoning a heavily advertised promise is noticed more than editing a
    # line nobody has heard yet.
    _shift_credibility(state, -0.03 - min(0.06, pledge.get("campaigns", 0) * 0.02))
    return True, f'Dropped the pledge on "{bill.name if bill else bill_id}"; credibility falls.'


def campaign_on_pledge(state, bill_id: str) -> tuple[bool, str, float]:
    if state.player.in_government:
        return False, "Campaign pledges belong to opposition mode.", 0.0
    pledge = pledge_for(state, bill_id)
    if pledge is None:
        return False, "That policy is not in your platform.", 0.0
    left = campaign_cooldown_remaining(state, bill_id)
    if left:
        return False, f"That pledge was just promoted; campaign on it again in {left} months.", 0.0

    bill = bill_for_pledge(pledge)
    speaker = spokesperson(state, bill)
    quality = speaker.implementation_quality() if speaker else 0.35
    vulnerability = max(0.0, 0.55 - state.stability.value)
    gain = min(0.016, 0.004 + quality * 0.007 + vulnerability * 0.008)

    own = next((f for f in state.country.factions if f.id == state.player.faction_id), None)
    ruling = next((f for f in state.country.factions if f.id == state.ruling_faction_id), None)
    if own is not None:
        own.support = min(0.85, own.support + gain)
    if ruling is not None and ruling is not own:
        ruling.support = max(0.01, ruling.support - gain * 0.65)

    pledge["campaigns"] = pledge.get("campaigns", 0) + 1
    _agenda(state)["campaign_turns"][bill_id] = state.turn
    _shift_credibility(state, 0.018 + quality * 0.022)
    who = speaker.name if speaker else "an untested party spokesperson"
    return (True,
            f'{who} campaigns on "{bill.name}"; party support rises by {gain*100:.1f} points.',
            gain)


def appoint_shadow(state, portfolio: str, minister) -> tuple[bool, str]:
    if state.player.in_government:
        return False, "You already have a governing cabinet."
    if portfolio not in CORE_PORTFOLIOS:
        return False, "That is not a recognised shadow portfolio."
    minister.portfolio = portfolio
    state.shadow_cabinet.ministers = [m for m in state.shadow_cabinet.ministers
                                      if m.portfolio != portfolio]
    state.shadow_cabinet.ministers.append(minister)
    _shift_credibility(state, 0.01 * minister.effective_competence())
    return True, (f"{minister.name} becomes Shadow {portfolio} Minister. Their competence "
                  f"will shape campaigns in this brief.")


def note_response(state, government_bill, response: str):
    """Reward consistency between published promises and parliamentary acts."""
    closest = None
    strength = 0.0
    for pledge in pledges(state):
        promised = bill_for_pledge(pledge)
        if promised is None:
            continue
        if promised.id == government_bill.id:
            closest, strength = pledge, 1.0
            break
        if (agenda_portfolio(promised) == agenda_portfolio(government_bill)
                and promised.ideology is not None and government_bill.ideology is not None):
            distance = promised.ideology.distance_to(government_bill.ideology)
            candidate_strength = max(0.0, 1.0 - distance / 0.9) * 0.65
            if candidate_strength > strength:
                closest, strength = pledge, candidate_strength
    if closest is None or strength <= 0:
        return

    if response in ("support", "amend"):
        _shift_credibility(state, (0.04 if response == "support" else 0.055) * strength)
    else:
        _shift_credibility(state, -0.07 * strength)


def note_player_proposal(state, bill_id: str):
    pledge = pledge_for(state, bill_id)
    if pledge is not None and state.player.in_government:
        pledge["status"] = "introduced"
        _shift_credibility(state, 0.025)


def note_bill_result(state, bill, passed: bool):
    pledge = pledge_for(state, bill.id)
    if pledge is None:
        return
    if bill.proposed_by == "player":
        pledge["status"] = "delivered" if passed else "attempted"
        _shift_credibility(state, 0.09 if passed else 0.015)
    elif passed:
        response = state.domestic_politics.get("responses", {}).get(bill.id)
        pledge["status"] = "adopted" if response in ("support", "amend") else "undercut"
        _shift_credibility(state, 0.035 if response in ("support", "amend") else -0.06)


def election_turnout_bonus(state, faction) -> float:
    """Deterministic turnout edge created by a credible, advertised platform."""
    if state.player.in_government or faction.id != state.player.faction_id:
        return 0.0
    items = pledges(state)
    if not items:
        return -0.015  # an opposition without an offer struggles to mobilise
    coverage = sum(min(3, p.get("campaigns", 0)) for p in items) / (len(items) * 3)
    staffed = sum(1 for p in items if spokesperson(state, bill_for_pledge(p))) / len(items)
    raw = (credibility(state) - 0.5) * 0.09 + coverage * 0.035 + staffed * 0.015
    return max(-0.06, min(0.08, raw))


def prepare_election(state):
    """A government faces the voters on promises it carried into office."""
    agenda = _agenda(state)
    if not state.player.in_government or agenda.get("mandate_start_turn") is None:
        return
    own = next((f for f in state.country.factions if f.id == state.player.faction_id), None)
    broken = 0
    for pledge in pledges(state):
        if pledge.get("status") not in ("delivered", "adopted"):
            pledge["status"] = "broken"
            broken += 1
    if broken:
        _shift_credibility(state, -0.10 * broken)
        if own is not None:
            own.support = max(0.01, own.support - 0.008 * broken)
        state.log(f"MANIFESTO VERDICT — {broken} election pledge(s) went undelivered.")


def after_election(state, was_in_government: bool):
    agenda = _agenda(state)
    if state.player.in_government:
        if not was_in_government:
            agenda["mandate_start_turn"] = state.turn
        # Completed promises need not remain on the next working programme.
        agenda["pledges"] = [p for p in pledges(state)
                             if p.get("status") not in ("delivered", "adopted")]
    else:
        agenda["mandate_start_turn"] = None
        agenda["pledges"] = [p for p in pledges(state)
                             if p.get("status") not in ("delivered", "adopted", "undercut")]
        for pledge in agenda["pledges"]:
            pledge["status"] = "pledged"


def monthly_update(state):
    """Shadow ministers acquire a little real campaign experience each month."""
    if state.player.in_government:
        return
    for minister in state.shadow_cabinet.ministers:
        minister.competence = min(0.90, minister.competence + 0.001)
