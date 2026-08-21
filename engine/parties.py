"""Intra-party dynamics: shift the balance of wings and named blocs.

The current model is shared by generic ideological wings and Ardenia's
authored social blocs. Its changing seat shares and leadership loyalty feed
the legislative vote resolver and coalition cohesion.
"""

from models.faction import Ideology
from models.wing import Wing
from engine import stability, flavor

STRENGTH_DRIFT = 0.05        # per-turn pull of wing strengths toward the climate target
LOYALTY_DRIFT = 0.05         # per-turn pull of wing loyalty toward its baseline
_MAX_DISTANCE = 2.83         # far corner to far corner of the compass


def _clamp(v, lo, hi):
    return max(lo, min(hi, v))


def _extremity(ideology) -> float:
    """0..1 — how far this position sits from the political centre."""
    return min(1.0, ideology.distance_to(Ideology(0.0, 0.0)) / _MAX_DISTANCE)


# ── Default spectrum ────────────────────────────────────────────────────────

def generate_default_wings(faction) -> list:
    """A moderate wing pulled toward the centre, a mainstream wing at the party
    line, and a hardline wing pushed further out along the party's own axis."""
    econ, soc = faction.ideology.economic, faction.ideology.social
    mag = (econ ** 2 + soc ** 2) ** 0.5
    if mag < 1e-6:
        # Centrist party: spread along the social axis so the wings still differ.
        dx, dy = 0.0, 1.0
    else:
        dx, dy = econ / mag, soc / mag
    off = 0.22

    def _wing(suffix, name, k, strength, loyalty):
        ideo = Ideology(economic=_clamp(econ + dx * off * k, -1.0, 1.0),
                        social=_clamp(soc + dy * off * k, -1.0, 1.0))
        return Wing(id=f"{faction.id}_{suffix}", name=name, ideology=ideo,
                    strength=strength, loyalty=loyalty)

    return [
        _wing("moderate",   "Moderates",   -1.0, 0.35, 0.65),
        _wing("mainstream", "Mainstream",   0.0, 0.40, 0.70),
        _wing("hardline",   "Hardliners",  +1.0, 0.25, 0.55),
    ]


# ── Per-turn drift ──────────────────────────────────────────────────────────

def _radical_pressure(state) -> float:
    """0..1 — how much the current climate favours the extreme wings. Bad times
    (instability, unrest, weak economy) radicalise; good times reward moderates."""
    econ_signal = stability.compute_economic_signal(state.country.economy)
    unrest = stability.compute_unrest(state)
    pressure = (0.5
                + (0.5 - state.stability.value)
                + unrest * 0.4
                - econ_signal * 0.2)
    return _clamp(pressure, 0.0, 1.0)


def update_party_wings(state):
    """One monthly current-balance update for the player's country.

    Strengths chase the climate-favoured tendencies, loyalty drifts on
    distance from the leading current, and a leadership-changing takeover is
    announced.
    """
    radical = _radical_pressure(state)

    for party in state.country.factions:
        if len(party.wings) < 2:
            continue

        old_dominant = party.dominant_wing()

        # Strengths drift toward a target set by how well each wing's extremity
        # matches the climate.
        desirability = []
        for w in party.wings:
            ext = _extremity(w.ideology)
            desirability.append(radical * ext + (1.0 - radical) * (1.0 - ext))
        total_des = sum(desirability) or 1.0
        for w, des in zip(party.wings, desirability):
            target = des / total_des
            w.strength += (target - w.strength) * STRENGTH_DRIFT
        party.normalize_wings()

        # Loyalty to leadership drifts on distance from the (new) dominant wing.
        dominant = party.dominant_wing()
        for w in party.wings:
            dist = w.ideology.distance_to(dominant.ideology)
            baseline = _clamp(1.0 - (dist / _MAX_DISTANCE) * 2.0, -1.0, 1.0)
            w.loyalty = _clamp(w.loyalty + (baseline - w.loyalty) * LOYALTY_DRIFT, -1.0, 1.0)

        if old_dominant is not None and dominant.id != old_dominant.id:
            flavor.say(state, "wing_takeover",
                       party=party.name, new_wing=dominant.name,
                       old_wing=old_dominant.name,
                       leader=party.leader or "the leadership")
            # A takeover by a restless wing claims the leader's head too —
            # except in the player's own party, where the challenge comes to
            # YOU as a situation (content/events.py: party_leadership_challenge).
            if (dominant.loyalty < 0.5 and party.leader
                    and party.id != state.player.faction_id):
                from engine import cabinet_ops
                old_leader = party.leader
                party.leader = cabinet_ops.generate_name(state)
                flavor.say(state, "leader_ousted",
                           party=party.name, old=old_leader,
                           new=party.leader, wing=dominant.name)
