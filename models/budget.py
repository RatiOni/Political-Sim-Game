from dataclasses import dataclass, field


@dataclass
class AnnualBudget:
    """One fiscal year's voted structural appropriations.

    Temporary costs and revenues from laws, treaties and crises remain in the
    modifier system; this object records only the expenditure baseline that
    parliament authorises.
    """

    year: int
    allocations: dict[str, float] = field(default_factory=dict)
    status: str = "draft"  # draft | proposed | approved | active | rejected | continuing
    source: str = "inherited"  # inherited | player | government_ai | continuing
    proposed_by: str = ""
    proposed_turn: int = -1
    forecast_revenue: float = 0.0
    votes_for: int = 0
    votes_against: int = 0
    lobbying_bonus: dict[str, float] = field(default_factory=dict)
    # Mid-year supplementary appropriations won since this budget took effect,
    # keyed by portfolio (engine/player_ops.py: op_supplementary_appropriation).
    # Held SEPARATELY from `allocations` on purpose: a supplementary raises a
    # ministry's spending power for the remainder of the year only, and next
    # year's proposal is built from `allocations`, so keeping it out of that
    # dict is what stops an emergency becoming a permanent baseline. It dies
    # with the year, because January installs a different AnnualBudget.
    supplements: dict[str, float] = field(default_factory=dict)

    @property
    def expenditure(self) -> float:
        """The VOTED structural total — supplements deliberately excluded.

        This figure is the appropriation baseline: it is what next year is
        measured against, what the ±30% validation band applies to, and what
        `activate` writes to Economy.structural_expenditure. A supplementary
        is an in-year addition on top of it, carried as a budget_expenditure
        modifier, not a rewrite of the settlement parliament voted.
        """
        return sum(self.allocations.values())

    def portfolio_supplement(self, portfolio: str) -> float:
        return float(self.supplements.get(portfolio, 0.0))

    @property
    def forecast_balance(self) -> float:
        return self.forecast_revenue - self.expenditure

