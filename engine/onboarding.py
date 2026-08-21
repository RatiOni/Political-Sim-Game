"""Which piece of guidance, if any, the player should be offered right now.

Pure and read-only: next_guidance() inspects state and returns an authored
entry from content/onboarding.py or None. It never mutates, never blocks an
action, and never enforces an order — the player can ignore every entry and
play the game exactly as they would have without it.

Nothing new is persisted. Both the dismissed set and the enabled flag live in
campaign_meta, which already round-trips through engine/persistence.py.
"""

from content.onboarding import GUIDANCE, GUIDANCE_BY_ID

ENABLED_KEY = "guidance_enabled"
DISMISSED_KEY = "guidance_dismissed"


def is_enabled(state) -> bool:
    """On unless a campaign explicitly turned it off. Defaulting to True means
    a save written before this feature existed behaves like a new campaign
    that left the option alone, which is the honest default for guidance that
    cannot block anything."""
    return bool(state.campaign_meta.get(ENABLED_KEY, True))


def set_enabled(state, enabled: bool):
    state.campaign_meta[ENABLED_KEY] = bool(enabled)


def dismissed_ids(state) -> set:
    stored = state.campaign_meta.get(DISMISSED_KEY)
    return set(stored) if isinstance(stored, (list, set, tuple)) else set()


def dismiss(state, guidance_id: str) -> bool:
    """Retire one entry permanently. Returns False for an unknown id rather
    than storing junk that would silently suppress a future entry."""
    if guidance_id not in GUIDANCE_BY_ID:
        return False
    current = dismissed_ids(state)
    current.add(guidance_id)
    # Stored as a sorted list: campaign_meta is serialised as JSON, which has
    # no set type, and a stable order keeps saves diffable.
    state.campaign_meta[DISMISSED_KEY] = sorted(current)
    return True


def pending(state) -> list:
    """Every entry whose moment has come and which has not been dismissed, in
    authored order. The order is the teaching order — one system at a time —
    so it is never re-sorted by urgency."""
    if not is_enabled(state):
        return []
    seen = dismissed_ids(state)
    out = []
    for entry in GUIDANCE:
        if entry["id"] in seen:
            continue
        try:
            if entry["trigger"](state):
                out.append(entry)
        except Exception:
            # A trigger is authored content reaching into live state; a
            # malformed one must never take the turn down with it. Skipping
            # is the safe failure for advisory text.
            continue
    return out


def next_guidance(state):
    """The single entry to show now, or None. One at a time, always the
    earliest still-relevant one, so the opening introduces systems in the
    order they were authored rather than all at once."""
    entries = pending(state)
    return entries[0] if entries else None
