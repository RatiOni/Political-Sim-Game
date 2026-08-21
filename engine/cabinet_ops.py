"""
Cabinet operations: minister candidate generation, reshuffles, dismissals.
"""

import random

from models.cabinet import Minister, TRAIT_EFFECTS, trait_effect

FIRST_NAMES = ["Elena", "Viktor", "Dmitri", "Ana", "Leon", "Sonja", "Mira", "Tomas",
               "Ingrid", "Pavel", "Katarina", "Stefan", "Lucia", "Aldo", "Nadia", "Boris"]
LAST_NAMES = ["Voss", "Haan", "Koval", "Petrov", "Marsh", "Bauer", "Dragu", "Kessler",
              "Orlov", "Renz", "Sava", "Lindqvist", "Brandt", "Moreau", "Calin", "Husek"]

def live_names(state) -> set:
    """Every name currently in play, derived from the state itself.

    Deliberately NOT a module-level registry: all game state lives on
    GameState, so a save/load or a second campaign in the same process must
    not inherit a stale set of "used" names.
    """
    if state is None:
        return set()
    names = {m.name for m in state.cabinet.ministers}
    names |= {m.name for m in state.shadow_cabinet.ministers}
    names |= {f.leader for f in state.country.factions if f.leader}
    names |= {c.leader_name for c in state.world if c.leader_name}
    for c in state.world:
        names |= {f.leader for f in c.factions if f.leader}
    if state.player.name:
        names.add(state.player.name)
    return names


def generate_name(state=None, used=None) -> str:
    """A fresh political name — shared by minister generation and party-leader
    generation (content/loader.py). Pass state to avoid colliding with names
    already in play; pass `used` for names claimed during a build that has no
    GameState yet (the loader assembling a fresh campaign)."""
    used = live_names(state) | set(used or ())
    for _ in range(20):
        name = f"{random.choice(FIRST_NAMES)} {random.choice(LAST_NAMES)}"
        if name not in used:
            return name
    return f"{random.choice(FIRST_NAMES)} {random.choice(LAST_NAMES)} II"


def generate_candidate(faction, portfolio: str, state=None) -> Minister:
    """
    Generates a new minister candidate from a given faction.
    Allied factions tend to offer more loyal picks; ideologically
    distant ones offer outsiders you're courting rather than people
    who already owe you anything — you rarely buy both loyalty and
    independence with the same appointment.
    """
    base_loyalty = 0.5 + faction.loyalty * 0.3
    loyalty = max(0.15, min(0.95, base_loyalty + random.uniform(-0.1, 0.1)))
    competence = random.uniform(0.35, 0.85)
    ambition = random.uniform(0.1, 0.7)

    return Minister(
        id=f"min_{random.randint(1000, 9999)}",
        name=generate_name(state),
        portfolio=portfolio,
        faction_id=faction.id,
        competence=round(competence, 2),
        loyalty=round(loyalty, 2),
        ambition=round(ambition, 2),
        trait=random.choice(list(TRAIT_EFFECTS)),
    )


def shortlist(state, portfolio: str) -> list:
    """Three named candidates for a vacancy: one of your own, one owed to a
    coalition partner (or the friendliest other party), and a wildcard rolled
    for raw ability. Both UIs present these; op_appoint_minister installs."""
    own = next((f for f in state.country.factions
                if f.id == state.player.faction_id), None)
    partners = [f for f in state.country.factions
                if f.in_coalition and f.id != state.player.faction_id]
    if partners:
        partner = max(partners, key=lambda f: f.power)
    else:
        others = [f for f in state.country.factions if f.id != state.player.faction_id]
        partner = max(others, key=lambda f: f.loyalty) if others else None
    wild = random.choice(state.country.factions)

    candidates = [generate_candidate(f, portfolio, state)
                  for f in (own, partner, wild) if f is not None]
    if len(candidates) >= 3:
        # The wildcard's pitch is ability, whatever their politics.
        candidates[-1].competence = round(max(candidates[-1].competence,
                                              random.uniform(0.60, 0.90)), 2)
    return candidates


def shadow_shortlist(state, portfolio: str) -> list:
    """Three members of the player's own party competing for a shadow brief.

    Opposition appointments build a recognisable alternative government; a
    cross-party wildcard here would blur responsibility before the player has
    even won a mandate.
    """
    own = next((f for f in state.country.factions
                if f.id == state.player.faction_id), None)
    if own is None:
        return []
    candidates = [generate_candidate(own, portfolio, state) for _ in range(3)]
    # Ensure the choice contains at least one credible policy specialist.
    candidates[-1].competence = round(max(candidates[-1].competence,
                                          random.uniform(0.65, 0.90)), 2)
    return candidates


def appoint(state, portfolio: str, minister: Minister) -> str:
    """Installs a chosen candidate. Faction consequences: the ousted
    minister's party stings, the appointee's party warms (more for coalition
    partners — a seat at the table — and more again for a firebrand)."""
    faction = next((f for f in state.country.factions
                    if f.id == minister.faction_id), None)
    old = state.cabinet.get(portfolio)
    minister.portfolio = portfolio
    state.cabinet.ministers = [m for m in state.cabinet.ministers
                               if m.portfolio != portfolio]
    state.cabinet.ministers.append(minister)

    if old is not None and old.faction_id != minister.faction_id:
        old_faction = next((f for f in state.country.factions
                            if f.id == old.faction_id), None)
        if old_faction is not None:
            old_faction.loyalty = max(-1.0, old_faction.loyalty - 0.05)

    if faction is not None:
        if faction.in_coalition and faction.id != state.player.faction_id:
            faction.loyalty = min(1.0, faction.loyalty + 0.04)   # a seat at the table
        elif not faction.in_coalition:
            faction.loyalty = min(1.0, faction.loyalty + 0.06)
        faction.loyalty = min(1.0, faction.loyalty
                              + trait_effect(minister.trait, "appoint_faction_bonus", 0.0))

    fname = faction.name if faction else "independent"
    label = minister.trait_label() or "safe pair of hands"
    return f"{minister.name} ({fname}; {label}) appointed to {portfolio}."


def reshuffle(state, portfolio: str, faction_id: str) -> str:
    """Fills (or replaces) a portfolio with a new minister from the given faction."""
    faction = next((f for f in state.country.factions if f.id == faction_id), None)
    if faction is None:
        return "Invalid faction."

    old_minister = state.cabinet.get(portfolio)
    new_minister = generate_candidate(faction, portfolio, state)

    state.cabinet.ministers = [m for m in state.cabinet.ministers if m.portfolio != portfolio]
    state.cabinet.ministers.append(new_minister)

    if old_minister and old_minister.faction_id != faction_id:
        old_faction = next((f for f in state.country.factions if f.id == old_minister.faction_id), None)
        if old_faction:
            old_faction.loyalty = max(-1.0, old_faction.loyalty - 0.05)

    if not faction.in_coalition:
        faction.loyalty = min(1.0, faction.loyalty + 0.06)

    verb = "reshuffled into" if old_minister else "appointed to fill"
    return f"{new_minister.name} ({faction.name}) {verb} {portfolio}."


def dismiss(state, portfolio: str) -> str:
    minister = state.cabinet.get(portfolio)
    if minister is None:
        return f"{portfolio} is already vacant."

    state.cabinet.ministers = [m for m in state.cabinet.ministers if m.portfolio != portfolio]

    faction = next((f for f in state.country.factions if f.id == minister.faction_id), None)
    if faction:
        faction.loyalty = max(-1.0, faction.loyalty - 0.09)

    return f"{minister.name} dismissed from {portfolio}. The post is now vacant — laws under it will underperform until refilled."
