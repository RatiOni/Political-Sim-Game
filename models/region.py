from dataclasses import dataclass, field


@dataclass
class RegionState:
    """The small, persistent state of one playable-country region.

    Geography and prose live in content/regions.py.  This object carries only
    values that can change during a campaign, keyed by the same stable id the
    lore and map use.
    """

    id: str
    unemployment: float
    state_reach: float
    pressure: float
    control: str = "state"
    issue_id: str = ""
    # Absolute local shares plus the national polling shares they were last
    # reconciled against. The anchor lets direct national campaign/law changes
    # flow into every region without erasing persistent geographic variation.
    party_support: dict[str, float] = field(default_factory=dict)
    support_anchor: dict[str, float] = field(default_factory=dict)


@dataclass
class RegionalProgram:
    """A funded, time-limited government intervention in one region."""

    id: str
    program_id: str
    region_id: str
    started_turn: int
    duration: int
    monthly_cost: float
    months_active: int = 0
