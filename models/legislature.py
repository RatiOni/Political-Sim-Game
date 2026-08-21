from dataclasses import dataclass, field
from typing import Optional

from models.faction import Ideology


@dataclass
class LawEffect:
    """
    A law's (or event option's) mechanical impact. Flat delta fields are
    wrapped into indefinite Modifiers at activation; author explicit
    Modifiers in `modifiers` when the effect should delay/ramp/fade.
    All values are deltas from the country's baseline.
    """
    # Economic effects (annual rates)
    gdp_growth_delta: float = 0.0
    unemployment_delta: float = 0.0
    inflation_delta: float = 0.0
    budget_revenue_delta: float = 0.0      # millions per year
    budget_expenditure_delta: float = 0.0  # millions per year

    # Political effects — applied once when law passes, not each turn
    # faction_id -> loyalty delta
    faction_loyalty_deltas: dict = field(default_factory=dict)

    # Power shifts — who gains or loses structural influence
    # faction_id -> power delta
    faction_power_deltas: dict = field(default_factory=dict)

    # Long-term consequences — effects that phase in/hold/fade over many
    # months rather than landing all at once. See models/modifiers.py.
    # list[Modifier]; instantiated into GameState.modifiers on passage.
    modifiers: list = field(default_factory=list)

    # A one-time (not ongoing) shift to debt-as-%-of-GDP applied once, at
    # the moment the law passes — e.g. bond issuance for a capital project.
    one_time_debt_pct_delta: float = 0.0


@dataclass
class Law:
    """
    A piece of legislation. Can be proposed, active, failed, lapsed, or repealed.
    Laws are the primary mechanism for changing the game state deliberately.
    """
    id: str
    name: str
    description: str
    status: str   # 'proposed' | 'active' | 'failed' | 'repealed'
    tier: str     # 'constitutional' | 'statutory' | 'executive_order'
    effects: LawEffect = field(default_factory=LawEffect)

    # Which cabinet portfolio is responsible for implementing this law.
    # None = not tied to any ministry (effects always apply at full strength).
    portfolio: Optional[str] = None

    # Where the bill sits on the compass. None = ideologically neutral, and
    # parties vote as single blocs on it; a positioned bill lets party WINGS
    # diverge from their leadership (engine/legislative.py: wing_votes).
    ideology: Optional[Ideology] = None

    # faction_id -> extra support secured by player lobbying, for the
    # NEXT vote only. Read by the vote resolver, not persisted afterward.
    lobbying_bonus: dict = field(default_factory=dict)

    # Vote record
    votes_for: int = 0
    votes_against: int = 0

    # Tracking
    turns_active: int = 0
    proposed_by: Optional[str] = None  # 'player' or sponsoring faction id

    def vote_margin(self) -> int:
        return self.votes_for - self.votes_against


@dataclass
class Legislature:
    """
    The legislative body. Tracks seat distribution and manages legislation.
    """
    total_seats: int
    seat_distribution: dict = field(default_factory=dict)  # faction_id -> seats

    pending_bills: list = field(default_factory=list)  # list[Law]: awaiting vote
    active_laws:   list = field(default_factory=list)  # list[Law]: currently in effect
    law_history:   list = field(default_factory=list)  # list[Law]: all resolved laws

    def coalition_seats(self, coalition_faction_ids: list) -> int:
        return sum(self.seat_distribution.get(fid, 0) for fid in coalition_faction_ids)

    def majority_threshold(self) -> int:
        return self.total_seats // 2 + 1

    def supermajority_threshold(self) -> int:
        """Required for constitutional changes."""
        return int(self.total_seats * 2 / 3) + 1

    def has_majority(self, faction_ids: list) -> bool:
        return self.coalition_seats(faction_ids) >= self.majority_threshold()

    def has_supermajority(self, faction_ids: list) -> bool:
        return self.coalition_seats(faction_ids) >= self.supermajority_threshold()
