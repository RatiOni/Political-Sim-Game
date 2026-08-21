"""An organised current inside a political party.

Most countries use broad ideological wings. Ardenia uses named blocs rooted
in the country's history and social groups. They share one lightweight model:
each owns a share of party seats, a political position, and a relationship
with the party leadership.
"""

from dataclasses import dataclass, field

from models.faction import Ideology


@dataclass
class Wing:
    id: str
    name: str
    ideology: Ideology      # the wing's own compass position
    strength: float         # 0..1 share of the party (wings ~sum to 1)
    loyalty: float          # -1..1 loyalty to the party leadership (cohesion)
    # ``bloc`` marks authored social currents; generic country data uses
    # ``wing``. It is useful for presentation but does not create a second
    # mechanics system.
    kind: str = "wing"
    # Empty for generic wings. Ardenian blocs keep their canon prose here so
    # the active simulation and the Codex describe the same actor.
    description: str = ""
    # law_id -> -1..1. Concrete interests can pull a bloc toward or away from
    # a bill beyond its broad ideological position.
    policy_biases: dict = field(default_factory=dict)
