from dataclasses import dataclass, field
from typing import Optional

from models.economy import Economy
from models.relations import BilateralRelation

# Regime types — determines what political mechanics are available
REGIME_TYPES = [
    "parliamentary_democracy",
    "presidential_democracy",
    "hybrid_regime",
    "authoritarian",
    "totalitarian",
]

# Coarse regime "camps", used for relation drift: two countries in the same
# camp drift slightly together over time, different camps slightly apart.
# Shared by the player↔world drift (engine/turn.py) and the world↔world drift
# and agenda AI (engine/worldsim.py) so both read one taxonomy.
REGIME_FAMILIES = {
    "parliamentary_democracy": "democracy",
    "presidential_democracy": "democracy",
    "hybrid_regime": "hybrid",
    "authoritarian": "autocracy",
    "totalitarian": "autocracy",
}


@dataclass
class Country:
    """
    Represents a country.

    For the player's country: full detail (factions, economy, legislature).
    For world countries: simplified — you see signals, not full internals.
    This mirrors real intelligence limitations.
    """
    id: str
    name: str
    regime_type: str
    population: int
    economy: Economy

    # Domestic politics (full for player country, simplified for others)
    factions: list = field(default_factory=list)  # list[Faction]

    # Bilateral relations: other_country_id -> BilateralRelation
    relations: dict = field(default_factory=dict)

    # Regime-stability signal for world countries (the player's own country
    # uses the full GameState.stability system instead).
    stability: float = 0.7  # 0.0 (collapsing) to 1.0 (stable)

    # How competently the state apparatus executes policy in general.
    bureaucratic_capacity: float = 0.75  # 0.0–1.0

    # Trait ids (content/traits.py) — stable descriptors applied once at
    # campaign generation.
    national_traits: list = field(default_factory=list)

    # Foreign-policy posture for the AI world-sim, e.g. {"type": "revanchist",
    # "rival": "veldoria", "ally": "krasova"}. Empty → default by regime type.
    agenda: dict = field(default_factory=dict)

    # Head of state/government's name (from the country's default_player),
    # quoted in world dispatches.
    leader_name: str = ""

    # The national newspaper's masthead (meta.paper in the JSON); empty →
    # "The {name} Herald". See engine/press.py.
    paper: str = ""

    # Capital city (meta.capital in the JSON), for dispatch and lore text.
    # Empty is fine — flavour falls back to "the capital".
    capital: str = ""

    # The country's current deliberated plan (engine/worldsim.py):
    # {"objective", "target", "matures_turn"}. Empty = needs deliberation.
    plan: dict = field(default_factory=dict)

    # Civil-war gauge + latch (engine/crisis.py); applies to world countries
    # and the player's country alike (the latter mirrored on GameState).
    civil_war_risk: float = 0.0
    in_civil_war: bool = False

    is_player: bool = False

    def get_relation(self, other_country_id: str) -> Optional[BilateralRelation]:
        return self.relations.get(other_country_id)

    def has_trait(self, trait_id: str) -> bool:
        return trait_id in self.national_traits
