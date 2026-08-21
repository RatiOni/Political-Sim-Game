from dataclasses import dataclass, field
from typing import Callable, Optional

from models.legislature import LawEffect


# relation_deltas keys that resolve at apply time to whichever country
# actually triggered the situation, so an event stays true wherever it fires
# instead of naming one. Resolved in engine/events.py.
#
#   TARGET_MOST_HOSTILE — the worst relation, and only if it is genuinely
#                         hostile (< -0.3); None otherwise.
#   TARGET_COOLEST      — simply the worst relation the player has, however
#                         mild. For events whose trigger is coolness rather
#                         than open hostility.
TARGET_MOST_HOSTILE = "__most_hostile__"
TARGET_COOLEST = "__coolest__"


@dataclass
class EventOption:
    """One choice on a fired situation; `effects` is a LawEffect, applied
    through the same pipeline as bill passage (apply_effect_bundle)."""
    id: str
    label: str
    description: str
    effects: LawEffect = field(default_factory=LawEffect)
    # country_id -> bilateral relation score delta. LawEffect has no notion
    # of foreign relations (bills never touch them), but diplomatic-flavored
    # events need to — applied via engine/diplomacy.py: adjust_relation,
    # the same helper the Diplomatic action-menu entries already use.
    relation_deltas: dict = field(default_factory=dict)
    pc_cost: float = 0.0
    # Optional delayed consequence: {"event_id", "delay" (turns), "chance"}.
    # Choosing this option schedules that event — choices come back around.
    follow_up: Optional[dict] = None
    # Optional custom consequence beyond what a LawEffect can express
    # (ideology shifts, wing surgery, ...): called as on_apply(state) by
    # engine/events.py when the option is applied. Content-defined, like
    # `requires` and `condition` — never serialized.
    on_apply: Optional[Callable] = None
    # Optional extra gate beyond affordability, e.g. "only if still in
    # government". Political capital is checked generically by the
    # resolver, so this is for narrative/structural conditions only.
    requires: Optional[Callable[[object], bool]] = None


@dataclass
class EventDef:
    """A situation that can fire during a turn: `condition` gates
    eligibility, `chance` is rolled fresh each eligible turn."""
    id: str
    title: str
    description: str
    category: str
    condition: Callable[[object], bool]
    chance: float
    options: list = field(default_factory=list)      # list[EventOption]
    default_option_id: str = ""                        # auto-resolved if left pending too long
    once: bool = False        # fires at most once per campaign
    cooldown: int = 12        # min turns between repeat fires
    # Who is institutionally allowed to make this decision. Existing content
    # defaults to government because almost every original situation grants
    # executive authority (treasury spending, police orders, diplomacy).
    # Values: "government" | "opposition" | "any".
    audience: str = "government"
    # Chain-only events set chance=0.0 (and/or condition False): they never
    # fire from the random pool, only via an option's follow_up.
    # If set, this event's effects are scaled by how well that cabinet
    # portfolio is being run (see engine/turn.py: _implementation_quality_for),
    # same convention as Law.portfolio / Modifier.portfolio.
    portfolio: Optional[str] = None


@dataclass
class PendingEvent:
    """A fired-but-unresolved EventDef awaiting a player choice."""
    event_id: str
    turns_pending: int = 0
