from dataclasses import dataclass, field


@dataclass
class ElectionResult:
    """
    A structured record of one election — the seed of the country's
    political timeline. Kept structured (not just a log string) so
    future mechanics can reference it: "how many terms has the player
    served," "who governed before the current lot," and so on.
    """
    turn: int
    date: str
    was_snap_election: bool
    seat_changes: dict          # faction_id -> seat delta from before this election
    final_seats: dict           # faction_id -> seats after this election
    support_snapshot: dict      # faction_id -> support share at the moment of the election
    ruling_faction_id: str
    coalition_faction_ids: list
    player_in_government: bool
    player_lost_office: bool
    player_gained_office: bool

    # ── Turnout & the popular vote ───────────────────────────────────────
    # Populated by engine/elections.py: hold_election. All default so older
    # saves (which predate turnout) still load, and so a hand-built
    # ElectionResult in a test doesn't have to supply them.
    eligible_voters: int = 0             # voting-age population
    total_votes_cast: int = 0            # sum of every party's votes
    turnout_pct: float = 0.0             # total_votes_cast / eligible_voters (emergent)
    votes_by_faction: dict = field(default_factory=dict)        # faction_id -> vote count
    vote_share_by_faction: dict = field(default_factory=dict)   # faction_id -> share of votes cast (0..1)
    seat_pct_by_faction: dict = field(default_factory=dict)     # faction_id -> seats / total_seats (0..1)
    # Subnational election record. Empty for countries without authored
    # regions and older saves.
    regional_vote_share: dict = field(default_factory=dict)     # region_id -> {faction_id: vote share}
    regional_turnout: dict = field(default_factory=dict)        # region_id -> cast / potential electorate
    regional_access: dict = field(default_factory=dict)         # region_id -> share able to vote
