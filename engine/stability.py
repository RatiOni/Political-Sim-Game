"""
Government stability: the shared signal functions (economic health, unrest,
cabinet risk, per-faction electoral momentum — computed once here so every
consumer reads the same numbers), the stability target itself, and the
discrete crises low stability enables (protests, confidence votes).
"""

import random
from typing import Optional

CONFIDENCE_VOTE_STABILITY_THRESHOLD = 0.30
CONFIDENCE_VOTE_BASE_CHANCE = 0.10
PROTEST_UNREST_THRESHOLD = 0.50


# ── Shared signals ───────────────────────────────────────────────────────

def compute_economic_signal(econ) -> float:
    """~-1..1: how good economic conditions feel. Shared by approval,
    stability, and electoral turnout."""
    return ((econ.growth_rate - 0.02) * 4.0
            - econ.unemployment * 0.5
            - econ.inflation * 0.3)


def compute_unrest(state) -> float:
    """0..1 from grievances, unemployment and persistent regional strain.
    Feeds stability's drag, protest triggers, and civil-war risk."""
    econ = state.country.economy
    worst_grievance = max((f.grievance_pressure() for f in state.country.factions), default=0.0)
    unemployment_pressure = max(0.0, econ.unemployment - 0.10) * 3.0
    # Regional strain begins to matter only above an ordinary background
    # pressure of 0.45, and is capped to remain a supporting signal rather
    # than a second copy of national unemployment.
    from engine import regions
    regional_pressure = max(0.0, regions.national_pressure(state) - 0.45) * 0.50
    from engine import households
    household_pressure = max(0.0, households.national_hardship(state) - 0.35) * 0.35
    return max(0.0, min(1.0,
                        worst_grievance * 0.6 + unemployment_pressure
                        + regional_pressure + household_pressure))


def faction_performance_signal(state, faction) -> float:
    """Per-faction electoral momentum: governing parties judged by outcomes,
    opposition benefits inversely (more when hostile), grievances cut opposite
    ways for each. Shared by monthly support drift AND election-day turnout so
    the two can't diverge."""
    econ_signal = compute_economic_signal(state.country.economy)
    if faction.in_coalition:
        perf = (econ_signal * 0.5
                + (state.stability.value - 0.5)
                + (state.player.approval - 0.5)) / 2.5
        perf -= faction.grievance_pressure() * 0.1
    else:
        capture = 0.3 + 0.5 * max(0.0, -faction.loyalty)
        perf = -((econ_signal * 0.5 + (state.stability.value - 0.5)) / 1.5) * capture
        perf += faction.grievance_pressure() * 0.1
    return perf


def compute_cabinet_risk_fraction(state) -> float:
    """0..1: share of the cabinet that's currently a latent threat (see
    Minister.threat_level / Cabinet.internal_threats). Used as a
    continuous scandal-risk drag on stability, and as a mild
    corruption-correlate drag on implementation quality."""
    ministers = state.cabinet.ministers
    if not ministers:
        return 0.0
    return len(state.cabinet.internal_threats()) / len(ministers)


# ── Target stability ─────────────────────────────────────────────────────

def compute_target_stability(state):
    """
    Returns (target: float, breakdown: dict). Mirrors how approval
    already computes a target and lerps toward it — same idiom, applied
    to the higher-order variable that aggregates across coalition,
    cabinet, legislature, approval, and the economy at once.
    """
    econ = state.country.economy
    leg = state.legislature

    coalition_ids = state.coalition_faction_ids()
    coalition_members = [f for f in state.country.factions if f.id in coalition_ids]
    coalition_loyalty = (sum(f.loyalty for f in coalition_members) / len(coalition_members)
                          if coalition_members else 0.0)
    coalition_component = (coalition_loyalty + 1.0) / 2.0  # -1..1 -> 0..1

    # Loyalty plus what grandees bring to the room (capped in the model).
    cabinet_component = min(1.0, state.cabinet.average_loyalty()
                            + state.cabinet.stability_trait_bonus())

    coalition_seats = leg.coalition_seats(coalition_ids)
    margin = (coalition_seats - leg.majority_threshold()) / max(1, leg.total_seats)
    majority_component = max(0.0, min(1.0, 0.5 + margin * 2.0))

    approval_component = state.player.approval  # already 0..1

    econ_signal = compute_economic_signal(econ)
    econ_component = max(0.0, min(1.0, 0.5 + econ_signal * 0.5))

    cabinet_risk = compute_cabinet_risk_fraction(state)
    unrest = compute_unrest(state)

    # A coalition of internally divided parties governs worse than one of
    # united ones — zero drag when every partner is fully cohesive.
    coalition_cohesion = (sum(f.cohesion() for f in coalition_members)
                          / len(coalition_members)) if coalition_members else 1.0

    breakdown = {
        "Coalition loyalty":  coalition_component * 0.25,
        "Cabinet loyalty":    cabinet_component   * 0.20,
        "Parliamentary margin": majority_component * 0.20,
        "Public approval":    approval_component  * 0.15,
        "Economic conditions": econ_component     * 0.10,
        "Cabinet dysfunction": -cabinet_risk * 0.15,
        "Unrest":              -unrest * 0.15,
        "Coalition cohesion": -(1.0 - coalition_cohesion) * 0.08,
    }
    target = max(0.05, min(0.95, sum(breakdown.values())))
    return target, breakdown


# ── Discrete events ───────────────────────────────────────────────────────

def maybe_trigger_protest(state) -> Optional[str]:
    """Probabilistic once unrest crosses the threshold; hits stability and
    approval and deepens the driving grievance, so neglect compounds."""
    unrest = compute_unrest(state)
    if unrest < PROTEST_UNREST_THRESHOLD:
        return None
    chance = min(0.4, (unrest - PROTEST_UNREST_THRESHOLD) * 0.8)
    if random.random() >= chance:
        return None

    driving_faction = max(state.country.factions, key=lambda f: f.grievance_pressure())
    state.stability.value = max(0.05, state.stability.value - 0.05)
    state.player.approval = max(0.0, state.player.approval - 0.02)
    grievance_src = "long-simmering anger"
    if driving_faction.grievances:
        driving_faction.grievances[0].severity = min(1.0, driving_faction.grievances[0].severity + 0.08)
        grievance_src = driving_faction.grievances[0].source.lower()

    from engine import flavor
    return flavor.say(state, "protest",
                      faction=driving_faction.name,
                      leader=driving_faction.leader or f"a {driving_faction.name} organiser",
                      grievance=grievance_src)


def _confidence_vote_tally(state):
    """
    An existential vote, not a policy vote: coalition members back the
    government almost by default (they lose their own posts too if it
    falls), everyone else votes their general loyalty sign. Returns
    (votes_for, votes_against, threshold).
    """
    coalition_ids = set(state.coalition_faction_ids())
    votes_for, votes_against = 0, 0
    for faction in state.country.factions:
        if faction.seats <= 0:
            continue
        if faction.id in coalition_ids or faction.loyalty >= 0:
            votes_for += faction.seats
        else:
            votes_against += faction.seats
    return votes_for, votes_against, state.legislature.majority_threshold()


def resolve_confidence_vote(state) -> str:
    """Returns "survived" or "lost". A loss costs the coalition its least
    loyal member, stability, and PC — full coalition collapse then feeds the
    snap-election check in engine/elections.py."""
    votes_for, votes_against, threshold = _confidence_vote_tally(state)
    survived = votes_for >= threshold

    if survived:
        state.stability.value = min(0.95, state.stability.value + 0.12)
        msg = (f"CONFIDENCE VOTE — the government survives {votes_for}-{votes_against} "
               f"(needed {threshold}). A costly reprieve.")
        state.log(msg)
        state.turn_news.append(("confidence_vote", {"survived": True,
                                                    "vfor": votes_for,
                                                    "vagainst": votes_against}, msg))
        return "survived"

    coalition_members = [f for f in state.country.factions if f.in_coalition]
    if coalition_members:
        defector = min(coalition_members, key=lambda f: f.loyalty)
        defector.in_coalition = False
        msg = (f"CONFIDENCE VOTE LOST — {votes_for}-{votes_against} (needed {threshold}). "
               f"{defector.name} abandons the coalition.")
    else:
        msg = (f"CONFIDENCE VOTE LOST — {votes_for}-{votes_against} (needed {threshold}). "
               f"The coalition has nothing left to lose.")
    state.log(msg)
    state.turn_news.append(("confidence_vote", {"survived": False,
                                                "vfor": votes_for,
                                                "vagainst": votes_against}, msg))

    state.stability.value = max(0.05, state.stability.value - 0.15)
    state.player.political_capital = max(0.0, state.player.political_capital - 20.0)
    return "lost"


def maybe_trigger_confidence_vote(state) -> Optional[str]:
    """
    Automatic risk check: once stability drops below the threshold,
    there's a rising per-turn chance the opposition forces a vote.
    Called from the turn engine, near the end of the turn, after
    everything else (economy, scandals, protests) has already had its
    say — so a genuinely bad month can compound into an existential one.
    """
    stability = state.stability.value
    if stability >= CONFIDENCE_VOTE_STABILITY_THRESHOLD:
        return None
    deficit = CONFIDENCE_VOTE_STABILITY_THRESHOLD - stability
    chance = min(0.5, CONFIDENCE_VOTE_BASE_CHANCE + deficit * 1.2)
    if random.random() >= chance:
        return None
    state.log("The opposition senses weakness and forces a confidence vote.")
    return resolve_confidence_vote(state)


def player_call_confidence_vote(state) -> str:
    """
    The player-initiated version — a deliberate gamble rather than
    something that happens to you. Useful either to reassert a mandate
    while you're confident, or to deliberately force out a coalition
    partner who's about to defect anyway, on your terms rather than
    theirs.
    """
    state.log("The government calls a confidence vote on its own initiative.")
    return resolve_confidence_vote(state)
