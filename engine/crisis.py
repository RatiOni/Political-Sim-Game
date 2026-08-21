"""
Civil war: a deterministic 0..1 risk gauge (stability, hostile factions,
unrest, missing majority, grievances) that latches an ongoing catastrophe —
heavy recurring penalties, not a game over — once it boils over, and clears
if the numbers recover. Player country and world countries alike.
"""

from engine import stability, flavor

# Sustained risk at or above this boils over into civil war.
CIVIL_WAR_RISK_THRESHOLD = 0.75
# Risk falling back below this ends an ongoing civil war (a hard climb, since
# the war itself depresses the very stats that drive the risk).
CIVIL_WAR_END_THRESHOLD = 0.40
# How fast the gauge chases its target — quicker than stability's 0.06: a
# crisis escalates faster than normal politics move.
RISK_LERP = 0.12
# Weight of an active insurgency in the civil-war gauge, and how fast that
# pressure bleeds off if nothing feeds it. Small on purpose: men in the hills
# raise the temperature, they do not by themselves start a civil war.
INSURGENCY_WEIGHT = 0.12
INSURGENCY_DECAY = 0.03      # per turn, toward zero


def _hostile_faction_pressure(factions) -> float:
    """0..1 from the combined strength of factions actively turned against
    the government (Faction.opposition_strength = |loyalty|·power when hostile)."""
    return min(1.0, sum(f.opposition_strength() for f in factions) / 1.0)


def _worst_grievance(factions) -> float:
    """The single most severe grievance anywhere (0..1). Raw severity, not the
    dampened grievance_pressure — a crisis is defined by its sharpest wound."""
    return max((g.severity for f in factions for g in f.grievances), default=0.0)


# ── Player country ──────────────────────────────────────────────────────────

def compute_civil_war_risk(state):
    """Returns (target_risk: float, breakdown: dict) for the player's country."""
    country = state.country
    factions = country.factions

    stability_pressure = max(0.0, (0.45 - state.stability.value) / 0.45)
    unrest = stability.compute_unrest(state)
    hostile = _hostile_faction_pressure(factions)

    coalition_ids = state.coalition_faction_ids()
    if not coalition_ids:
        majority_gap = 1.0
    else:
        coalition_seats = state.legislature.coalition_seats(coalition_ids)
        majority = state.legislature.majority_threshold()
        majority_gap = max(0.0, (majority - coalition_seats) / max(1, majority))

    grievance = _worst_grievance(factions)

    breakdown = {
        "State breakdown (stability)": stability_pressure * 0.35,
        "Armed / hostile factions": hostile * 0.30,
        "Civil unrest": unrest * 0.15,
        "No governing majority": majority_gap * 0.10,
        "Unresolved grievances": grievance * 0.10,
        # Men under arms who never accepted the outcome. Deliberately a
        # smaller weight than the structural drivers: an insurgency raises
        # the temperature, it does not by itself start a civil war. Zero
        # unless narrative content has set it, so the original balance is
        # untouched in a campaign where nothing has flared up.
        "Active insurgency": state.insurgency_pressure * INSURGENCY_WEIGHT,
    }
    target = min(1.0, sum(breakdown.values()))
    return target, breakdown


def maybe_trigger_civil_war(state):
    """One turn of civil-war dynamics for the player's country: age the risk
    gauge toward its target, latch/clear the flag, and — while it's latched —
    apply the ongoing penalties."""
    target, breakdown = compute_civil_war_risk(state)
    state.civil_war_risk += (target - state.civil_war_risk) * RISK_LERP
    state.civil_war_risk = max(0.0, min(1.0, state.civil_war_risk))

    # An insurgency fades if it isn't fed — narrative content pushes this up,
    # time brings it back down, so no branch can leave a permanent flat drag.
    if state.insurgency_pressure > 0.0:
        state.insurgency_pressure = max(0.0, state.insurgency_pressure - INSURGENCY_DECAY)
    state.civil_war_breakdown = breakdown

    if not state.civil_war:
        if state.civil_war_risk >= CIVIL_WAR_RISK_THRESHOLD:
            state.civil_war = True
            state.country.in_civil_war = True
            flavor.say(state, "civil_war_out")
    else:
        if state.civil_war_risk < CIVIL_WAR_END_THRESHOLD:
            state.civil_war = False
            state.country.in_civil_war = False
            flavor.say(state, "civil_war_end")
        else:
            _apply_ongoing_penalties(state)


def _apply_ongoing_penalties(state):
    """The recurring cost of an active civil war on the player's government."""
    state.stability.value = max(0.03, state.stability.value - 0.03)
    state.player.approval = max(0.0, state.player.approval - 0.02)
    state.player.political_capital = max(0.0, state.player.political_capital - 5.0)
    econ = state.country.economy
    econ.gdp *= 0.99  # ~1%/month wartime contraction
    flavor.say(state, "civil_war_ongoing")


# ── World countries ─────────────────────────────────────────────────────────

def compute_country_civil_war_risk(country) -> float:
    """A coarser risk read for a world country, from its own-state signals
    (world countries don't have the full GovernmentStability system)."""
    factions = country.factions
    stability_pressure = max(0.0, (0.45 - country.stability) / 0.45)
    hostile = _hostile_faction_pressure(factions)
    grievance = _worst_grievance(factions)
    econ = country.economy
    econ_pressure = min(1.0, max(0.0, (econ.unemployment - 0.10)) * 2.0)
    risk = (stability_pressure * 0.40 + hostile * 0.35
            + grievance * 0.15 + econ_pressure * 0.10)
    return min(1.0, risk)


def maybe_trigger_country_civil_war(state, country):
    """One turn of civil-war dynamics for a world country, surfaced to the
    player as a world dispatch when it flips."""
    target = compute_country_civil_war_risk(country)
    country.civil_war_risk += (target - country.civil_war_risk) * RISK_LERP
    country.civil_war_risk = max(0.0, min(1.0, country.civil_war_risk))

    if not country.in_civil_war:
        if country.civil_war_risk >= CIVIL_WAR_RISK_THRESHOLD:
            country.in_civil_war = True
            flavor.say(state, "world_civil_war_out", country=country.name,
                       leader=country.leader_name or "the government")
    else:
        if country.civil_war_risk < CIVIL_WAR_END_THRESHOLD:
            country.in_civil_war = False
            flavor.say(state, "world_civil_war_end", country=country.name,
                       leader=country.leader_name or "the government")
        else:
            country.stability = max(0.03, country.stability - 0.03)
            country.economy.gdp *= 0.99
