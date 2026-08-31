"""
Legislative mechanics: vote projection/resolution and the shared
effect-application pipeline (apply_effect_bundle) that laws and events use.
"""

import copy
from typing import Optional

from game_state import GameState
from models.legislature import Law, LawEffect
from models.modifiers import Modifier
from models import roles
from engine import flavor

# How heavily a bill's direct stake in a faction's interests outweighs
# their general loyalty to the government when they decide how to vote.
SALIENCE = 4.0
# How strongly a wing's own ideological read of a bill pulls it away from the
# party line (see wing_votes). Only bills with an authored ideology split.
WING_SALIENCE = 2.0
# A bloc's concrete constituency: a narrow, authored interest can matter as
# much as the party's general position. Generic wings carry no such bias.
BLOC_POLICY_SALIENCE = 1.0
_MAX_DIST = 2.83


def predicted_support(faction, law: Law, state: Optional[GameState] = None) -> float:
    """-1..1 lean on a bill: government trust blended with the bill's stake
    for this faction, plus any lobbying banked for this vote."""
    stake = law.effects.faction_loyalty_deltas.get(faction.id, 0.0)
    policy_lean = max(-1.0, min(1.0, stake * SALIENCE))
    lobbying = law.lobbying_bonus.get(faction.id, 0.0)
    trust = _government_trust(state, faction, law)
    lean = trust * 0.5 + policy_lean * 0.5 + lobbying
    return max(-1.0, min(1.0, lean))


def _government_trust(state: Optional[GameState], faction, law: Law) -> float:
    """-1..1: how much this faction trusts the bill's sponsor to govern.

    ``Faction.loyalty`` is disposition toward the *player*, not toward
    whoever actually proposed this bill — a correct stand-in for "trusts
    the sponsor" only when the player themselves sponsored it (or ``state``
    is unavailable, preserving old callers). For an AI-government bill the
    player did not sponsor (``law.proposed_by`` is a faction id, not
    ``"player"``), trust is read off the faction's actual relationship to
    that sponsor instead: full trust for the sponsor itself, strong trust
    for the ruling coalition it leads, and ideological affinity to the
    sponsor for everyone else — never the faction's unrelated loyalty to
    the player.
    """
    if state is None or not law.proposed_by or law.proposed_by == "player":
        return faction.loyalty
    if faction.id == law.proposed_by:
        return 1.0
    if faction.in_coalition:
        return 0.6
    sponsor = next((f for f in state.country.factions if f.id == law.proposed_by), None)
    if sponsor is None:
        return faction.loyalty
    return 2.0 * _affinity(faction.effective_ideology(), sponsor.effective_ideology()) - 1.0


def _affinity(ideology, law_ideology) -> float:
    return 1.0 - ideology.distance_to(law_ideology) / _MAX_DIST


def _split_seats_by_strength(wings, total_seats: int) -> dict:
    """Largest-remainder split of a party's seats across its wings.

    Seat-conserving only when `strength` values already sum to ~1.0
    (guaranteed by `Faction.normalize_wings()`); normalizes defensively here
    too so a caller that skips that step still can't desync the seat total.
    """
    total_strength = sum(max(0.0, w.strength) for w in wings)
    if total_strength <= 0:
        total_strength = 1.0
    exact = [(w, max(0.0, w.strength) / total_strength * total_seats) for w in wings]
    seats = {w.id: int(v) for w, v in exact}
    remainder = total_seats - sum(seats.values())
    order = sorted(exact, key=lambda t: -(t[1] - int(t[1])))
    for i in range(remainder):
        seats[order[i % len(order)][0].id] += 1
    return seats


def wing_votes(faction, law: Law, state: Optional[GameState] = None):
    """
    Per-wing (wing, seats, lean) when split voting is active — the party has
    ≥2 wings AND the bill carries an ideology — else None (the party votes as
    one bloc, exactly as before). A wing's lean is the party lean with its
    discipline scaling the government-trust component, plus how much closer
    (or further) the wing itself sits to the bill than the party centre does.
    """
    if len(faction.wings) < 2 or law.ideology is None or faction.seats <= 0:
        return None
    stake = law.effects.faction_loyalty_deltas.get(faction.id, 0.0)
    policy_lean = max(-1.0, min(1.0, stake * SALIENCE))
    lobbying = law.lobbying_bonus.get(faction.id, 0.0)
    trust = _government_trust(state, faction, law)
    party_affinity = _affinity(faction.effective_ideology(), law.ideology)
    seat_split = _split_seats_by_strength(faction.wings, faction.seats)

    out = []
    for w in faction.wings:
        discipline = 0.5 + 0.5 * w.loyalty
        bloc_interest = max(-1.0, min(1.0, w.policy_biases.get(law.id, 0.0)))
        lean = (trust * 0.5 * discipline
                + policy_lean * 0.5
                + lobbying
                + (_affinity(w.ideology, law.ideology) - party_affinity) * WING_SALIENCE
                + bloc_interest * BLOC_POLICY_SALIENCE)
        out.append((w, seat_split[w.id], max(-1.0, min(1.0, lean))))
    return out


def projected_votes(state: GameState, law: Law):
    """Returns (votes_for, votes_against, breakdown) without resolving
    anything. Divided parties split their seats across wings on positioned
    bills; breakdown entries stay (name, seats, net-lean) either way."""
    votes_for = 0
    votes_against = 0
    breakdown = []
    for faction in state.country.factions:
        if faction.seats <= 0:
            continue
        wv = wing_votes(faction, law, state)
        if wv is None:
            lean = predicted_support(faction, law, state)
            if lean >= 0:
                votes_for += faction.seats
            else:
                votes_against += faction.seats
            breakdown.append((faction.name, faction.seats, lean))
        else:
            f_for = sum(s for _, s, lean in wv if lean >= 0)
            f_against = faction.seats - f_for
            votes_for += f_for
            votes_against += f_against
            net = sum(lean * s for _, s, lean in wv) / max(1, faction.seats)
            breakdown.append((faction.name, faction.seats, net))
    return votes_for, votes_against, breakdown


def vote_rebellions(state: GameState, law: Law):
    """[(faction, wing, seats, 'for'|'against')] — wings voting against their
    own party's majority side, for display and dispatch."""
    out = []
    for faction in state.country.factions:
        wv = wing_votes(faction, law, state)
        if wv is None or faction.seats <= 0:
            continue
        f_for = sum(s for _, s, lean in wv if lean >= 0)
        party_for = f_for >= (faction.seats - f_for)
        for w, s, lean in wv:
            if s <= 0:
                continue
            wing_for = lean >= 0
            if wing_for != party_for:
                out.append((faction, w, s, "for" if wing_for else "against"))
    return out


def threshold_for(state: GameState, law: Law) -> int:
    if law.tier == "constitutional":
        return state.legislature.supermajority_threshold()
    return state.legislature.majority_threshold()


def resolve_vote(state: GameState, law: Law) -> bool:
    """Tally, check threshold, apply passage effects, move the law to its
    resting list. Returns True if it passed."""
    votes_for, votes_against, _ = projected_votes(state, law)
    rebellions = vote_rebellions(state, law)
    law.votes_for = votes_for
    law.votes_against = votes_against
    threshold = threshold_for(state, law)
    passed = votes_for >= threshold

    state.legislature.pending_bills = [
        b for b in state.legislature.pending_bills if b.id != law.id
    ]

    if passed:
        law.status = "active"
        state.legislature.active_laws.append(law)
        _apply_passage_effects(state, law)
        flavor.say(state, "vote_passed", bill=law.name,
                   vfor=votes_for, vagainst=votes_against, threshold=threshold)
    else:
        law.status = "failed"
        state.legislature.law_history.append(law)
        state.player.approval = max(0.0, state.player.approval - 0.015)
        flavor.say(state, "vote_failed", bill=law.name,
                   vfor=votes_for, vagainst=votes_against, threshold=threshold)

    for faction, wing, seats, direction in rebellions:
        # A division over a concrete interest leaves the bloc less willing to
        # follow its leadership next time. A named rebellion therefore has a
        # small persistent consequence instead of being only a dispatch.
        interest = abs(wing.policy_biases.get(law.id, 0.0))
        wing.loyalty = max(-1.0, wing.loyalty - (0.025 + interest * 0.075))
        flavor.say(state, "vote_rebellion",
                   count=seats, party=faction.name, wing=wing.name,
                   bill=law.name, direction=direction)
    from engine import opposition
    opposition.note_bill_result(state, law, passed)
    _press_reaction(state, law, passed)
    return passed


def _press_reaction(state, law: Law, passed: bool):
    """One quoted reaction from the faction with the most at stake — never
    the player themselves, who would otherwise be quoted in the third person
    reacting to their own government's vote."""
    deltas = law.effects.faction_loyalty_deltas
    by_id = {f.id: f for f in state.country.factions}
    stakes = [(fid, d) for fid, d in deltas.items()
              if fid in by_id and d != 0.0
              and by_id[fid].leader != state.player.name]
    if not stakes:
        return
    winner_id, wd = max(stakes, key=lambda kv: kv[1])
    loser_id, ld = min(stakes, key=lambda kv: kv[1])
    if passed and ld < 0:
        f = by_id[loser_id]
        flavor.say(state, "vote_reaction_angry",
                   leader=f.leader or "Its leadership", party=f.name, bill=law.name)
    elif passed and wd > 0:
        f = by_id[winner_id]
        flavor.say(state, "vote_reaction_pleased",
                   leader=f.leader or "Its leadership", party=f.name, bill=law.name)
    elif not passed and wd > 0:
        f = by_id[winner_id]
        flavor.say(state, "vote_reaction_angry",
                   leader=f.leader or "Its leadership", party=f.name, bill=law.name)


def _apply_passage_effects(state: GameState, law: Law):
    """One-time faction loyalty/power shifts triggered by a bill passing,
    plus activation of everything that unfolds afterward. Thin wrapper
    around apply_effect_bundle so a law's own identity (name/id/portfolio)
    feeds the general-purpose path."""
    apply_effect_bundle(state, law.effects, law.name, law.id, law.portfolio)


def _pick_for_role(candidates, role: str):
    """Of several factions, the one that most embodies a role: furthest out
    on the role's defining axis, or closest to its centroid for the roles
    that have no single extreme."""
    if roles.ROLE_AXIS.get(role) is not None:
        return max(candidates, key=lambda f: roles.axis_value(f.ideology, role))
    return min(candidates, key=lambda f: roles.role_distance(f.ideology, role))


def role_faction(state: GameState, role: str):
    """The faction that plays a canonical role in THIS country, or None.

    Factions classified into the role come first, and the most extreme of
    them speaks for it. If a country has nobody classified there — Solheim
    has no party that classifies as business — the role falls back to the
    best *eligible* faction instead: one on the correct side of the defining
    axis (Solheim's Liberal Party, its most economically-right party). An
    empty role would mean an authored event silently doing nothing in that
    country, so we only return None when no plausible stand-in exists at all
    (Terand genuinely has no faction left of centre).
    """
    classified = [f for f in state.country.factions if f.role == role]
    if classified:
        return _pick_for_role(classified, role)
    eligible = [f for f in state.country.factions
                if roles.eligible_for(f.ideology, role)]
    if not eligible:
        return None
    return _pick_for_role(eligible, role)


def resolve_faction_key(state: GameState, key: str):
    """Map a faction_loyalty_deltas key — a literal faction id or a '@role'
    key — onto a faction of the country being played, or None.

    This is the single resolution point: authored content names roles, and
    they become concrete factions here, when the effect actually lands, not
    at authoring time (the mapping is per-country).
    """
    if roles.is_role_key(key):
        return role_faction(state, key)
    return next((f for f in state.country.factions if f.id == key), None)


def apply_effect_bundle(state: GameState, effects: LawEffect, source_name: str,
                        source_id: Optional[str] = None, portfolio: Optional[str] = None):
    """Apply a LawEffect-shaped consequence bundle: one-time faction
    loyalty/power/support shifts plus instantiation of its Modifiers.
    Shared by bill passage and dynamic events (engine/events.py)."""
    for fid, delta in effects.faction_loyalty_deltas.items():
        faction = resolve_faction_key(state, fid)
        if faction:
            faction.loyalty = max(-1.0, min(1.0, faction.loyalty + delta))
            # A loyalty shift also nudges electoral support at smaller scale —
            # same signal read a second way, no separate field needed.
            faction.support = max(0.0, min(1.0, faction.support + delta * 0.3))

    for fid, delta in effects.faction_power_deltas.items():
        faction = resolve_faction_key(state, fid)
        if faction:
            faction.power = max(0.0, min(1.0, faction.power + delta))

    _instantiate_effect_modifiers(state, effects, source_name, source_id, portfolio)


def _flat_effect_modifiers(effects: LawEffect, source_name: str,
                           source_id: Optional[str], portfolio: Optional[str]) -> list:
    """Wrap flat deltas into indefinite-hold Modifiers so they flow through
    the same non-accumulating pipeline as explicit long-term effects."""
    mods = []
    simple_targets = [
        ("gdp_growth",        effects.gdp_growth_delta),
        ("unemployment",      effects.unemployment_delta),
        ("inflation",         effects.inflation_delta),
        ("budget_revenue",    effects.budget_revenue_delta),
        ("budget_expenditure", effects.budget_expenditure_delta),
    ]
    for target, magnitude in simple_targets:
        if magnitude:
            mods.append(Modifier(
                id=f"{source_id or source_name}_{target}", source=source_name, target=target,
                magnitude=magnitude, onset_delay=0, ramp_duration=1, hold_duration=None,
                source_id=source_id, portfolio=portfolio,
            ))
    return mods


def _upsert_modifier(state: GameState, modifier: Modifier):
    """Install a modifier, replacing any existing one with the same id.

    A modifier id identifies an effect from a specific source, so a repeat
    application (a repeatable event firing again, a law re-enacted) must
    REFRESH that effect rather than stack a second copy — otherwise
    indefinite-hold modifiers accumulate without bound over a long game.
    """
    state.modifiers = [m for m in state.modifiers if m.id != modifier.id]
    state.modifiers.append(modifier)


def _instantiate_effect_modifiers(state: GameState, effects: LawEffect, source_name: str,
                                  source_id: Optional[str], portfolio: Optional[str]):
    for template in effects.modifiers:
        m = copy.deepcopy(template)
        m.age = 0
        m.source_id = m.source_id or source_id
        _upsert_modifier(state, m)

    for m in _flat_effect_modifiers(effects, source_name, source_id, portfolio):
        _upsert_modifier(state, m)

    if effects.one_time_debt_pct_delta:
        econ = state.country.economy
        econ.public_debt_pct = max(0.0, econ.public_debt_pct + effects.one_time_debt_pct_delta)


def repeal_law(state: GameState, law: Law) -> str:
    """Strike an active law from the books: its ongoing effects die with it
    (removed by source_id, the same way a broken treaty's do), the factions
    it served resent the loss while its opponents are pleased, and the
    governing overhead it consumed is freed the moment it leaves
    active_laws (turn.py: political_upkeep)."""
    state.legislature.active_laws = [l for l in state.legislature.active_laws
                                     if l.id != law.id]
    state.modifiers = [m for m in state.modifiers if m.source_id != law.id]

    # Repeal is passage run backwards: whoever gained from the law loses.
    for fid, delta in law.effects.faction_loyalty_deltas.items():
        faction = next((f for f in state.country.factions if f.id == fid), None)
        if faction:
            faction.loyalty = max(-1.0, min(1.0, faction.loyalty - delta))
            faction.support = max(0.0, min(1.0, faction.support - delta * 0.3))

    law.status = "repealed"
    law.turns_active = 0
    state.legislature.law_history.append(law)

    flavor.say(state, "law_repealed", bill=law.name)
    return (f"\"{law.name}\" is struck from the statute book. Its effects lapse, and the "
            f"attention it consumed returns to the government.")


def activate_law_modifiers(state: GameState, law: Law):
    """Instantiate a law's modifiers + one-time debt effect WITHOUT the
    passage loyalty shock. Deliberately narrower than apply_effect_bundle:
    content/loader.py calls this for laws already active at campaign start,
    whose loyalty impact is baked into the authored starting loyalties.
    """
    _instantiate_effect_modifiers(state, law.effects, law.name, law.id, law.portfolio)


def enact_executive_order(state: GameState, law: Law):
    """Skip the vote entirely; every non-coalition faction loses trust."""
    law.status = "active"
    state.legislature.active_laws.append(law)
    _apply_passage_effects(state, law)

    coalition_ids = set(state.coalition_faction_ids())
    for faction in state.country.factions:
        if faction.id not in coalition_ids and faction.seats > 0:
            faction.loyalty = max(-1.0, faction.loyalty - 0.03)

    flavor.say(state, "exec_order", bill=law.name)
