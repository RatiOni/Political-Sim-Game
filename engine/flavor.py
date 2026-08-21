"""
Dispatch rendering: say(state, key, **fields) picks a variant from
content/dispatches.py and logs it. Variant choice uses a LOCAL Random seeded
from (turn, key, position-in-log) — varied turn to turn and call to call, yet
fully deterministic and never touching the global RNG stream the seeded
trigger mechanics (and their tests) depend on.
"""

import random

from content.dispatches import TEMPLATES


def render(state, key: str, **fields) -> str:
    pool = TEMPLATES[key]
    rng = random.Random(hash((state.turn, key, len(state.turn_log))) & 0xffffffff)
    return rng.choice(pool).format(**fields)


def say(state, key: str, **fields) -> str:
    """Render a variant, log it as a dispatch, and record the structured
    (key, fields, text) news item for the press. Returns the text."""
    msg = render(state, key, **fields)
    state.log(msg)
    state.turn_news.append((key, dict(fields), msg))
    return msg
