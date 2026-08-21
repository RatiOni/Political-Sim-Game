"""
The core primitive for long-term consequences: laws, loans, treaties, and
events attach Modifiers to GameState.modifiers instead of mutating stats
directly. The engine reads each modifier's CURRENT value fresh every turn —
never accumulated — so effects stay bounded however long they run.
"""

from dataclasses import dataclass
from typing import Optional


@dataclass
class Modifier:
    """
    A time-shaped effect on one stat. Lifecycle in months:

        onset_delay ▶ ramp (0→magnitude) ▶ hold ▶ decay (magnitude→0) ▶ gone

    hold_duration=None holds at full magnitude forever (never auto-expires).
    `target` is a stat key the turn engine reads ("gdp_growth", "inflation",
    "budget_revenue", ...). `portfolio`, if set, scales strength by how well
    that ministry is currently run.
    """
    id: str
    source: str                        # human-readable origin, for logs/UI
    target: str
    magnitude: float                   # full-strength delta once ramped in
    onset_delay: int = 0
    ramp_duration: int = 1
    hold_duration: Optional[int] = None
    decay_duration: int = 0
    age: int = 0
    source_id: Optional[str] = None    # law/loan/treaty id — lets a future
                                        # repeal action find & remove these
    portfolio: Optional[str] = None

    # Whether this effect's strength depends on the state's general ability
    # to implement things (bureaucratic capacity, government stability,
    # cabinet dysfunction) — see engine/turn.py: _implementation_quality_for.
    # True for basically every policy effect. False is reserved for things
    # that are contractual/external rather than administered by the state
    # apparatus at all — e.g. loan interest, which accrues by contract
    # regardless of how well the government happens to be functioning.
    institutional: bool = True

    def current_value(self) -> float:
        t = self.age
        if t < self.onset_delay:
            return 0.0
        t -= self.onset_delay

        if t < self.ramp_duration:
            frac = (t + 1) / max(1, self.ramp_duration)
            return self.magnitude * min(1.0, frac)
        t -= self.ramp_duration

        if self.hold_duration is None:
            return self.magnitude
        if t < self.hold_duration:
            return self.magnitude
        t -= self.hold_duration

        if self.decay_duration <= 0:
            return 0.0
        if t < self.decay_duration:
            frac = 1.0 - (t + 1) / self.decay_duration
            return self.magnitude * max(0.0, frac)
        return 0.0

    def is_expired(self) -> bool:
        """Indefinite modifiers (hold_duration=None) never auto-expire."""
        if self.hold_duration is None:
            return False
        total_life = self.onset_delay + self.ramp_duration + self.hold_duration + self.decay_duration
        return self.age >= total_life

    def phase_label(self) -> str:
        """Human-readable lifecycle phase, for the dashboard."""
        t = self.age
        if t < self.onset_delay:
            return f"pending (starts in {self.onset_delay - t}mo)"
        t -= self.onset_delay

        if self.ramp_duration > 1:
            if t < self.ramp_duration:
                return f"phasing in ({t + 1}/{self.ramp_duration}mo)"
            t -= self.ramp_duration
        # ramp_duration <= 1 has no visible ramp — treated as immediate

        if self.hold_duration is None:
            return "active"
        if t < self.hold_duration:
            return "active"
        t -= self.hold_duration

        if self.decay_duration > 0 and t < self.decay_duration:
            return f"fading ({t + 1}/{self.decay_duration}mo)"
        return "expired"
