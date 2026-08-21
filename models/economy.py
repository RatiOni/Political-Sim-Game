from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Sector:
    """
    An economic sector. Its fortunes directly affect the power and mood
    of politically aligned factions.
    """
    id: str
    name: str
    gdp_share: float          # fraction of total GDP (all sectors should sum to ~1.0)
    growth_rate: float        # annual growth rate (-0.10 to +0.20 typical)
    employment_share: float   # fraction of total workforce
    aligned_faction_ids: list = field(default_factory=list)


@dataclass
class Budget:
    revenue: float      # annual, in game currency (millions) — the displayed/effective figure
    expenditure: float

    @property
    def balance(self) -> float:
        return self.revenue - self.expenditure

    @property
    def is_deficit(self) -> bool:
        return self.balance < 0


@dataclass
class Loan:
    """A foreign loan being serviced: principal + schedule. The matching
    budget_expenditure Modifier carries the interest cost turn to turn."""
    id: str
    lender_id: str                # country_id of the lender
    principal: float               # original amount borrowed, in millions
    annual_interest_rate: float
    term_months: int
    months_elapsed: int = 0

    def is_due(self) -> bool:
        return self.months_elapsed >= self.term_months

    def annual_interest_cost(self) -> float:
        return self.principal * self.annual_interest_rate

    def months_remaining(self) -> int:
        return max(0, self.term_months - self.months_elapsed)


@dataclass
class Economy:
    gdp: float              # total GDP in millions
    growth_rate: float      # EFFECTIVE annual growth rate: structural + active policy modifiers
    inflation: float        # EFFECTIVE annual inflation: structural + active policy modifiers
    unemployment: float     # EFFECTIVE unemployment: structural + active policy modifiers
    public_debt_pct: float  # debt as fraction of GDP
    budget: Budget
    sectors: list = field(default_factory=list)  # list[Sector]

    # Structural baselines — the fundamentals, moved by sectors and organic
    # dynamics, not directly by policy; modifiers layer on top each turn to
    # produce the effective values above. Seeded from headline values in
    # __post_init__.
    structural_growth_rate: Optional[float] = None
    structural_unemployment: Optional[float] = None
    structural_inflation: Optional[float] = None
    structural_revenue: Optional[float] = None
    structural_expenditure: Optional[float] = None

    workforce_quality: float = 0.5            # 0.0–1.0; moved by long-term modifiers (e.g. education reform)
    trade_revenue_contribution: float = 0.0    # recomputed fresh each turn from active trade treaties

    loans: list = field(default_factory=list)  # list[Loan]

    def __post_init__(self):
        if self.structural_growth_rate is None:
            self.structural_growth_rate = self.growth_rate
        if self.structural_unemployment is None:
            self.structural_unemployment = self.unemployment
        if self.structural_inflation is None:
            self.structural_inflation = self.inflation
        if self.structural_revenue is None:
            self.structural_revenue = self.budget.revenue
        if self.structural_expenditure is None:
            self.structural_expenditure = self.budget.expenditure

    def sector_by_id(self, sector_id: str):
        return next((s for s in self.sectors if s.id == sector_id), None)

    def gdp_per_capita(self, population: int) -> float:
        if population == 0:
            return 0.0
        return (self.gdp * 1_000_000) / population

    def total_debt_service(self) -> float:
        return sum(loan.annual_interest_cost() for loan in self.loans)
