from dataclasses import dataclass, field


@dataclass
class GovernmentStability:
    """
    The player government's durability (engine/stability.py) — distinct
    from Country.stability, the coarse world-country signal.
    value: 0..1; trend: change since last turn (for the UI arrow);
    breakdown: last-computed input contributions, display-only.
    """
    value: float = 0.55
    trend: float = 0.0
    breakdown: dict = field(default_factory=dict)

    def label(self) -> str:
        if self.value >= 0.75: return "Solid"
        if self.value >= 0.55: return "Stable"
        if self.value >= 0.35: return "Fragile"
        if self.value >= 0.20: return "Crisis"
        return "Collapsing"
