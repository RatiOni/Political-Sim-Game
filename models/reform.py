from dataclasses import dataclass, field


@dataclass
class ReformProject:
    """The player's current reform-design process.

    The first stage records the problem the player has chosen to solve. Later
    stages will add an instrument, scope and negotiated concessions without
    changing the identity or diagnosis that began the project.
    """

    id: str
    objective_id: str
    adopted_turn: int
    adopted_year: int
    adopted_month: int
    status: str = "objective"
    diagnosis_score: float = 0.0
    diagnosis_snapshot: dict = field(default_factory=dict)

