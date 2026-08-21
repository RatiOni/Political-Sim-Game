"""
Roleplay glue: the player's dynamic rival — the leader of the strongest
hostile party — who needles the government when it stumbles. A cheap layer
of personal antagonism; durable grudge-memory arrives with the negotiation
system later.
"""

import random

from engine import flavor

JIBE_CHANCE = 0.5      # per stumble-turn (trigger roll — global RNG, like protests)
JIBE_COOLDOWN = 3      # turns between jibes, so the rival doesn't nag
_STUMBLE_MARKERS = ("VOTE FAILED", "SCANDAL", "PROTESTS", "CIVIL WAR")

# How many times the rival has had a go at you this campaign. Stored in the
# existing GameState.cooldowns dict — already persisted, so escalation
# survives save/load without a new field to serialise.
JIBE_COUNT_KEY = "rival_jibe_count"
SHARP_AFTER = 3        # they stop being polite
BITTER_AFTER = 9       # ...and eventually stop enjoying it


def jibe_count(state) -> int:
    return int(state.cooldowns.get(JIBE_COUNT_KEY, 0))


def jibe_tier(state) -> str:
    """Which rival_jibe pool fits where this feud has got to.

    Early on the rival is dismissive. Once they have landed a few blows —
    or once the government is visibly struggling — they sharpen. Late in a
    long campaign, a rival who has been right for years and lost anyway
    turns bitter instead.
    """
    count = jibe_count(state)
    if count >= BITTER_AFTER:
        # Bitterness is for a rival who keeps losing; if the government is
        # actually failing they stay on the attack instead.
        return "rival_jibe_sharp" if state.player.approval < 0.40 else "rival_jibe_bitter"
    if count >= SHARP_AFTER or state.player.approval < 0.35:
        return "rival_jibe_sharp"
    return "rival_jibe"


def current_rival(state):
    """The strongest hostile party (by opposition_strength), or None."""
    hostile = [f for f in state.country.factions if f.opposition_strength() > 0]
    if not hostile:
        return None
    return max(hostile, key=lambda f: f.opposition_strength())


def rival_watch(state):
    """Late turn phase: after a visible stumble, the rival may pounce."""
    rival = current_rival(state)
    if rival is None or not rival.leader:
        return
    recent = list(state.turn_log) + list(state.event_history[-6:])
    if not any(marker in line for line in recent for marker in _STUMBLE_MARKERS):
        return
    last = state.cooldowns.get("rival_jibe")
    if last is not None and (state.turn - last) < JIBE_COOLDOWN:
        return
    if random.random() < JIBE_CHANCE:
        state.cooldowns["rival_jibe"] = state.turn
        state.cooldowns[JIBE_COUNT_KEY] = jibe_count(state) + 1
        flavor.say(state, jibe_tier(state), rival=rival.leader, party=rival.name)
