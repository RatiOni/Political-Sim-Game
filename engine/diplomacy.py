"""
International relations mechanics: adjusting bilateral relations,
trade, and loans. Both sides of a relationship are kept in sync here
so the action layer never has to remember to update both Country
objects independently.
"""

import random

from models.relations import BilateralRelation, Treaty, cap_trade_volume
from models.economy import Loan
from models.modifiers import Modifier

LOAN_AMOUNT = 800.0
LOAN_TERM_MONTHS = 48   # ~4 years — long enough to feel like a real commitment,
                        # short enough that most playthroughs will see it retired


def get_or_create_relation(country, other_id: str) -> BilateralRelation:
    rel = country.relations.get(other_id)
    if rel is None:
        rel = BilateralRelation(country.id, other_id)
        country.relations[other_id] = rel
    return rel


def adjust_relation(state, country_id: str, delta: float, note: str = ""):
    """Symmetrically adjusts the relation score on both sides of the relationship."""
    player = state.country
    other = state.world_country(country_id)
    if other is None:
        return

    rel_a = get_or_create_relation(player, country_id)
    rel_b = get_or_create_relation(other, player.id)

    rel_a.score = max(-1.0, min(1.0, rel_a.score + delta))
    rel_b.score = rel_a.score

    if note:
        rel_a.history.append(note)
        rel_b.history.append(note)


def improve_relations(state, country_id: str, minister_competence: float = 0.4) -> str:
    other = state.world_country(country_id)
    boost = 0.05 + 0.05 * minister_competence
    adjust_relation(state, country_id, boost, note=f"Diplomatic outreach ({state.date_string()}).")
    return f"Diplomatic outreach to {other.name} improves relations (+{boost:.2f})."


def propose_trade_agreement(state, country_id: str) -> str:
    player = state.country
    other = state.world_country(country_id)

    treaty = Treaty(
        id=f"trade_{country_id}_{state.year}_{state.month}",
        name=f"Trade Agreement with {other.name}",
        type="trade",
        parties=[player.id, country_id],
    )

    rel_a = get_or_create_relation(player, country_id)
    rel_b = get_or_create_relation(other, player.id)
    rel_a.treaties.append(treaty)
    rel_b.treaties.append(treaty)
    rel_a.trade_volume = cap_trade_volume(rel_a.trade_volume + 250.0)
    rel_b.trade_volume = rel_a.trade_volume

    adjust_relation(state, country_id, 0.05, note=f"Trade agreement signed ({state.date_string()}).")

    # Volume growth + customs revenue are handled per-turn elsewhere; the
    # GDP-growth payoff phases in over ~2 years via its own modifier.
    state.modifiers.append(Modifier(
        id=f"{treaty.id}_growth", source=f"Trade Agreement with {other.name}",
        target="gdp_growth", magnitude=0.0015,
        onset_delay=3, ramp_duration=24, hold_duration=None,
        source_id=treaty.id, portfolio="Foreign Affairs",
    ))

    return (f"Trade agreement signed with {other.name}. Trade volume will build as relations hold, "
            f"and the growth benefits will phase in gradually over the next couple of years.")


def _loan_interest_rate(state, lender) -> float:
    """Base rate nudged by lender regime type and relationship quality."""
    base = 0.06
    if lender.regime_type in ("authoritarian", "totalitarian"):
        base += 0.02
    rel = state.country.relations.get(lender.id)
    rel_score = rel.score if rel else 0.0
    return max(0.03, min(0.12, base - rel_score * 0.02))


def request_foreign_loan(state, country_id: str) -> str:
    player = state.country
    other = state.world_country(country_id)
    econ = player.economy

    rate = _loan_interest_rate(state, other)
    loan = Loan(
        id=f"loan_{country_id}_{state.year}_{state.month}_{random.randint(1000, 9999)}",
        lender_id=country_id,
        principal=LOAN_AMOUNT,
        annual_interest_rate=rate,
        term_months=LOAN_TERM_MONTHS,
    )
    econ.loans.append(loan)

    # One-off cash injection (not folded into the structural baseline, so it
    # isn't re-added every turn) plus the debt.
    econ.budget.revenue += LOAN_AMOUNT
    econ.public_debt_pct = min(3.0, econ.public_debt_pct + LOAN_AMOUNT / econ.gdp)

    # Interest is contractual — institutional=False so no minister or crisis
    # discounts it. ramp 1 + hold term-1 = exactly term_months of cost.
    state.modifiers.append(Modifier(
        id=f"{loan.id}_interest", source=f"Loan from {other.name}",
        target="budget_expenditure", magnitude=loan.annual_interest_cost(),
        onset_delay=0, ramp_duration=1, hold_duration=max(0, LOAN_TERM_MONTHS - 1), decay_duration=0,
        source_id=loan.id, portfolio=None, institutional=False,
    ))

    adjust_relation(state, country_id, 0.04, note=f"Loan accepted from {other.name} ({state.date_string()}).")

    # Sovereignty backlash among nationalist-leaning factions (by ideology).
    for faction in player.factions:
        if faction.ideology.social < -0.3:
            faction.loyalty = max(-1.0, faction.loyalty - 0.05)

    return (f"Accepted a {LOAN_AMOUNT:.0f}M loan from {other.name} at {rate*100:.1f}% interest "
            f"over {LOAN_TERM_MONTHS} months. Public debt rises now; debt servicing "
            f"({loan.annual_interest_cost():.0f}M/year) will weigh on the budget until it's repaid.")


def has_treaty(state, country_id: str, treaty_type: str) -> bool:
    rel = state.country.relations.get(country_id)
    return rel is not None and any(t.type == treaty_type for t in rel.treaties)


def has_any_defense_pact(state) -> bool:
    return any(any(t.type == "defense" for t in r.treaties)
               for r in state.country.relations.values())


def sign_defense_pact(state, country_id: str) -> str:
    """Mechanics only — eligibility/cost live in player_ops.op_defense_pact."""
    player = state.country
    other = state.world_country(country_id)

    treaty = Treaty(
        id=f"defense_{country_id}_{state.year}_{state.month}",
        name=f"Defense Pact with {other.name}",
        type="defense",
        parties=[player.id, country_id],
    )
    rel_a = get_or_create_relation(player, country_id)
    rel_b = get_or_create_relation(other, player.id)
    rel_a.treaties.append(treaty)
    rel_b.treaties.append(treaty)

    adjust_relation(state, country_id, 0.10, note=f"Defense pact signed ({state.date_string()}).")
    state.stability.value = min(0.95, state.stability.value + 0.02)

    # The partner's rival reads an alliance as aimed at them.
    rival_id = other.agenda.get("rival")
    if rival_id and rival_id != player.id and state.world_country(rival_id) is not None:
        adjust_relation(state, rival_id, -0.10,
                        note=f"Alarmed by your pact with {other.name} ({state.date_string()}).")
    return (f"A defense pact binds you to {other.name}. Hostile powers will think twice; "
            f"{other.name}'s rivals now watch you too.")


def impose_sanctions(state, country_id: str) -> str:
    player = state.country
    other = state.world_country(country_id)
    rel_a = get_or_create_relation(player, country_id)
    rel_b = get_or_create_relation(other, player.id)

    lost_trade = rel_a.trade_volume
    rel_a.sanctioned = True
    rel_b.sanctioned = True
    rel_a.trade_volume = 0.0
    rel_b.trade_volume = 0.0
    adjust_relation(state, country_id, -0.20,
                    note=f"Sanctions imposed by {player.name} ({state.date_string()}).")

    if lost_trade > 200.0:
        state.modifiers.append(Modifier(
            id=f"sanctions_cost_{country_id}_{state.turn}",
            source=f"Sanctions on {other.name}",
            target="gdp_growth", magnitude=-0.002,
            onset_delay=0, ramp_duration=2, hold_duration=6, decay_duration=2,
            portfolio="Foreign Affairs"))
    return (f"Sanctions slam shut on {other.name}: trade halts, their economy will bleed "
            f"monthly — and your own exporters take the collateral hit.")


def lift_sanctions(state, country_id: str) -> str:
    player = state.country
    other = state.world_country(country_id)
    rel_a = get_or_create_relation(player, country_id)
    rel_b = get_or_create_relation(other, player.id)
    rel_a.sanctioned = False
    rel_b.sanctioned = False
    adjust_relation(state, country_id, 0.05,
                    note=f"Sanctions lifted ({state.date_string()}).")
    return f"Sanctions on {other.name} are lifted. Trade must rebuild from nothing."


def hold_summit(state, country_id: str) -> str:
    other = state.world_country(country_id)
    adjust_relation(state, country_id, 0.12,
                    note=f"Bilateral summit ({state.date_string()}).")
    state.player.approval = min(0.95, state.player.approval + 0.01)
    return (f"A summit with {other.name}: handshakes, communiqués, and a real thaw. "
            f"The cameras loved it.")


def break_treaty(state, country_id: str, treaty_id: str) -> str:
    player = state.country
    other = state.world_country(country_id)
    rel_a = get_or_create_relation(player, country_id)
    rel_b = get_or_create_relation(other, player.id)

    treaty = next((t for t in rel_a.treaties if t.id == treaty_id), None)
    if treaty is None:
        return "No such treaty."
    # Remove exactly the one matched instance, on both sides. A live treaty
    # is the SAME Python object referenced from both relations (see
    # propose_trade_agreement/sign_defense_pact), so identity comparison
    # removes only it — a filter keyed on id alone would delete every
    # treaty sharing that id in one action if ids were ever to collide.
    rel_b_match = next((t for t in rel_b.treaties if t is treaty), None)
    rel_a.treaties = [t for t in rel_a.treaties if t is not treaty]
    if rel_b_match is not None:
        rel_b.treaties = [t for t in rel_b.treaties if t is not rel_b_match]
    else:
        # Defensive fallback (e.g. a state that lost the identity link
        # across save/load): remove the first id match on the other side.
        idx = next((i for i, t in enumerate(rel_b.treaties) if t.id == treaty_id), None)
        if idx is not None:
            del rel_b.treaties[idx]

    penalty = -0.30 if treaty.type == "defense" else -0.20
    adjust_relation(state, country_id, penalty,
                    note=f"{treaty.name} torn up by {player.name} ({state.date_string()}).")
    if treaty.type == "trade":
        rel_a.trade_volume *= 0.5
        rel_b.trade_volume = rel_a.trade_volume
        # The pact's phased-in growth benefit dies with it.
        state.modifiers = [m for m in state.modifiers if m.source_id != treaty.id]
    return f"You tear up the {treaty.name}. {other.name} will not forget it."


def condemn(state, country_id: str) -> str:
    other = state.world_country(country_id)
    adjust_relation(state, country_id, -0.15, note=f"Publicly condemned by {state.country.name} ({state.date_string()}).")
    state.player.approval = min(1.0, state.player.approval + 0.01)

    for faction in state.country.factions:
        if faction.ideology.social < -0.3:
            faction.loyalty = min(1.0, faction.loyalty + 0.04)

    return f"You publicly condemned {other.name}. Relations sour; nationalist-leaning factions approve."
