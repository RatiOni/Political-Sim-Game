"""Domestic government simulation while the player is in opposition.

The ruling coalition uses the same bill catalogue, vote resolver, modifiers,
and election state as the player.  This is deliberately a small deterministic
controller: diagnose, introduce, leave a response window, then vote.
"""

from content.bills import bill_catalog
from engine import legislative


BILL_CADENCE = 5                 # legacy month-scale compatibility
VOTE_DELAY = 1
BILL_CADENCE_DAYS = 120
VOTE_DELAY_DAYS = 21


def _politics(state):
    data = state.domestic_politics
    data.setdefault("next_bill_turn", state.turn)
    data.setdefault("introduced_turns", {})
    # Daily scheduling is authoritative. The month keys remain populated so
    # old saves and third-party integrations continue to load intelligibly.
    if "next_bill_day" not in data:
        turns_left = max(0, data["next_bill_turn"] - state.turn)
        data["next_bill_day"] = state.day_index + turns_left * 30
    if "introduced_days" not in data:
        data["introduced_days"] = {
            bill_id: state.day_index - max(0, state.turn - turn) * 30
            for bill_id, turn in data["introduced_turns"].items()
        }
    data.setdefault("responses", {})
    data.setdefault("bills_introduced", 0)
    return data


def current_government_bill(state):
    return next((b for b in state.legislature.pending_bills
                 if b.proposed_by and b.proposed_by != "player"), None)


def response_for(state, bill_id):
    return _politics(state)["responses"].get(bill_id)


def record_response(state, bill_id, response):
    _politics(state)["responses"][bill_id] = response


def _ruling_party(state):
    return next((f for f in state.country.factions
                 if f.id == state.ruling_faction_id), None)


def _pressure_score(state, bill):
    """Rank a bill by ruling-party affinity and current material pressures."""
    ruling = _ruling_party(state)
    if ruling is None:
        return -999.0
    score = 0.0
    if bill.ideology is not None:
        score += 3.0 * (1.0 - ruling.ideology.distance_to(bill.ideology) / 2.83)
    score += bill.effects.faction_loyalty_deltas.get(ruling.id, 0.0) * 5.0

    econ = state.country.economy
    deficit = econ.budget.expenditure - econ.budget.revenue
    if econ.inflation >= 0.05:
        if bill.id in {"central_bank_independence_act", "emergency_price_controls"}:
            score += 2.0
    if econ.unemployment >= 0.10:
        if bill.id in {"infrastructure_investment_act", "education_modernisation_act",
                       "minimum_wage_act"}:
            score += 1.5
    if deficit > 0:
        if bill.id in {"progressive_tax_reform_act", "telecom_privatization_act"}:
            score += 1.5
    if state.civil_war_risk >= 0.45 and bill.id == "defense_spending_act":
        score += 2.0
    return score


def _choose_bill(state):
    live = ({b.id for b in state.legislature.pending_bills} |
            {l.id for l in state.legislature.active_laws})
    candidates = [b for b in bill_catalog()
                  if b.id not in live and b.tier != "executive_order"]
    if not candidates:
        return None
    return max(candidates, key=lambda b: (_pressure_score(state, b), b.id))


def _introduce_bill(state, bill):
    ruling = _ruling_party(state)
    if ruling is None:
        return
    bill.status = "proposed"
    bill.proposed_by = ruling.id
    # Coalition discipline supplies a modest whip operation. Player responses
    # can still move their own party, and fragile coalitions can still lose.
    for faction in state.country.factions:
        if faction.in_coalition:
            bill.lobbying_bonus[faction.id] = 0.16
    bill.lobbying_bonus[ruling.id] = 0.28
    state.legislature.pending_bills.append(bill)

    politics = _politics(state)
    politics["introduced_turns"][bill.id] = state.turn
    politics["introduced_days"][bill.id] = state.day_index
    politics["bills_introduced"] += 1
    state.log(f"GOVERNMENT BILL — {ruling.name} introduces \"{bill.name}\". "
              "The opposition has until the next sitting to declare its position.")


def _resolve_bill(state, bill):
    ruling = _ruling_party(state)
    response = response_for(state, bill.id)
    legislative.resolve_vote(state, bill)
    stance = f" after the opposition chose to {response}" if response else \
             " with the opposition uncommitted"
    state.log(f"The government brings \"{bill.name}\" to a division{stance}.")
    politics = _politics(state)
    politics["introduced_turns"].pop(bill.id, None)
    politics["introduced_days"].pop(bill.id, None)
    politics["responses"].pop(bill.id, None)
    politics["next_bill_turn"] = state.turn + BILL_CADENCE
    politics["next_bill_day"] = state.day_index + BILL_CADENCE_DAYS
    if ruling is not None:
        state.log(f"{ruling.name} returns to its programme after the vote.")


def lapse_pending_government_bills(state):
    """Bills belonging to an outgoing administration fall at an election."""
    kept = []
    for bill in state.legislature.pending_bills:
        if bill.proposed_by and bill.proposed_by != "player":
            bill.status = "lapsed"
            state.legislature.law_history.append(bill)
            state.log(f"\"{bill.name}\" lapses with the outgoing government.")
        else:
            kept.append(bill)
    state.legislature.pending_bills = kept
    politics = _politics(state)
    politics["introduced_turns"] = {}
    politics["introduced_days"] = {}
    politics["responses"] = {}
    politics["next_bill_turn"] = state.turn + 2
    politics["next_bill_day"] = state.day_index + 60


def simulate_domestic_government(state):
    """Advance the non-player government's agenda on the exact day clock."""
    if state.player.in_government:
        return
    politics = _politics(state)
    pending = current_government_bill(state)
    if pending is not None:
        introduced = politics["introduced_days"].get(pending.id, state.day_index)
        if state.day_index - introduced >= VOTE_DELAY_DAYS:
            _resolve_bill(state, pending)
        return

    if state.day_index < politics["next_bill_day"]:
        return
    bill = _choose_bill(state)
    if bill is not None:
        _introduce_bill(state, bill)
