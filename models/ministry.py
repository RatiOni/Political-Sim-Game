from dataclasses import dataclass, field


@dataclass
class MinistryState:
    """Persistent operating condition of one cabinet department."""

    portfolio: str
    baseline_funding: float = 0.0
    funding: float = 0.0
    funding_ratio: float = 1.0
    workload: float = 0.0
    capacity: float = 0.0
    delivery: float = 1.0
    backlog: float = 0.0
    months_overloaded: int = 0
    workload_breakdown: dict[str, float] = field(default_factory=dict)

    @property
    def load_ratio(self) -> float:
        return self.workload / max(0.01, self.capacity)

    def status_label(self) -> str:
        if self.delivery >= 0.90 and self.backlog < 0.25:
            return "Effective"
        if self.delivery >= 0.72 and self.backlog < 1.0:
            return "Stretched"
        if self.delivery >= 0.50 and self.backlog < 2.5:
            return "Overloaded"
        return "Failing"

