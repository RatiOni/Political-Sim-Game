"""
Government legacy: the administration's running historical record, on
GameState.legacy. Recording is additive and optional — an empty legacy is
valid. (No summary screen consumes it yet.)
"""

from dataclasses import dataclass, field


@dataclass
class GovernmentLegacy:
    """A running historical record of the player's time in power."""
    # Identity of the campaign this legacy belongs to.
    country_id: str = ""
    leader_name: str = ""
    party_id: str = ""
    start_date: str = ""

    # Tallies — bumped by their relevant systems over the campaign.
    elections_won: int = 0
    elections_lost: int = 0
    reforms_passed: int = 0
    bills_failed: int = 0
    scandals: int = 0
    protests: int = 0
    confidence_votes_survived: int = 0
    confidence_votes_lost: int = 0
    treaties_signed: int = 0
    loans_taken: int = 0
    months_in_office: int = 0

    # Time series and event log — appended to for later charting/summary.
    gdp_history: list = field(default_factory=list)         # (date_str, gdp)
    approval_history: list = field(default_factory=list)     # (date_str, approval)
    coalition_history: list = field(default_factory=list)    # (date_str, [faction_ids])
    milestones: list = field(default_factory=list)           # (date_str, text)

    def record_milestone(self, date_str: str, text: str):
        self.milestones.append((date_str, text))
