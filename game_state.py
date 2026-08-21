import calendar
from dataclasses import dataclass, field
from datetime import date
from typing import Optional

from models.country import Country
from models.cabinet import Cabinet
from models.legislature import Legislature
from models.stability import GovernmentStability
from models.legacy import GovernmentLegacy
from models.modifiers import Modifier
from models.events import PendingEvent
from models.election import ElectionResult
from models.region import RegionState, RegionalProgram
from models.budget import AnnualBudget
from models.ministry import MinistryState
from models.household import HouseholdGroupState
from models.reform import ReformProject


@dataclass
class Player:
    """
    The player character: the head of government.
    This is where the player's personal political identity lives.
    """
    name: str
    title: str          # "President", "Prime Minister", "Chancellor", etc.
    faction_id: str     # the faction that brought them to power

    # Player's own political position (used for faction loyalty drift)
    ideology_economic: float = 0.0
    ideology_social: float = 0.0

    approval: float = 0.5           # public approval (0.0–1.0)
    political_capital: float = 50.0  # the player's action budget
    pc_regen_base: float = 10.0      # PC gained per turn before modifiers

    # False = in opposition (gates government actions; the campaign metadata
    # preserves the office title so winning power restores it).
    in_government: bool = True
    elections_won: int = 0


@dataclass
class GameState:
    """
    The complete, authoritative state of the game at any moment.
    The turn engine reads from this, modifies it, and returns it.
    Nothing lives outside this object.
    """
    # ── Time ──────────────────────────────────────────────────
    year: int
    month: int   # 1–12

    # ── Core actors ───────────────────────────────────────────
    player: Player
    country: Country            # the player's country, full detail
    world: list = field(default_factory=list)  # list[Country]: other nations
    # Live subnational conditions for the playable country, keyed by the same
    # stable ids as content/lore/geography.py. Countries without an authored
    # regional layer simply leave this empty.
    regions: dict[str, RegionState] = field(default_factory=dict)
    # Time-limited interventions launched from the regional map. They keep
    # running as state programmes even if the player later leaves office.
    regional_programs: list[RegionalProgram] = field(default_factory=list)

    # ── Political structures ───────────────────────────────────
    legislature: Legislature = field(default_factory=lambda: Legislature(total_seats=100))
    cabinet: Cabinet = field(default_factory=Cabinet)
    # The player's alternative government while outside office. Nominees
    # campaign on policy pledges and become the real cabinet if the player
    # wins power, preserving personnel continuity across the election.
    shadow_cabinet: Cabinet = field(default_factory=Cabinet)
    # Domestic government planning when the player is in opposition. Kept as
    # plain data so the controller can grow without coupling models to engine.
    domestic_politics: dict = field(default_factory=dict)

    # Annual structural appropriations. The active plan controls the economy's
    # expenditure baseline; a passed future plan waits here until 1 January.
    active_budget: Optional[AnnualBudget] = None
    pending_budget: Optional[AnnualBudget] = None
    budget_history: list[AnnualBudget] = field(default_factory=list)
    # Departmental operating condition, keyed by cabinet portfolio. Money,
    # leadership and state capacity meet the live policy workload here.
    ministries: dict[str, MinistryState] = field(default_factory=dict)
    # Regional social groups carrying the lived economy. Keys are
    # ``region_id:group_id``; non-authored countries leave this empty.
    households: dict[str, HouseholdGroupState] = field(default_factory=dict)
    # The policy problem currently being turned into a designed reform. Only
    # the objective stage exists yet; later stages add instrument and scope.
    reform_project: Optional[ReformProject] = None
    # Government attention: the second, non-monetary constraint on action.
    # Political capital asks "can you afford this in the chamber"; attention
    # asks "is this what your government spent the month on". Spent within a
    # month, reset to zero by the monthly pulse (engine/turn.py) — it does NOT
    # regenerate mid-month the way political capital accrues. See
    # engine/player_ops.py: MONTHLY_ATTENTION / costs_attention.
    attention_spent: int = 0
    # Headline values captured at the START of the current month's pulse
    # (engine/digest.py: snapshot). Lets a monthly digest describe what
    # changed this month without a new history mechanic — it is a lens on
    # the state that already exists, refreshed and overwritten every pulse,
    # never accumulated. Old saves load this as {}, which the digest reads
    # as "nothing to compare against yet" rather than an error.
    last_snapshot: dict = field(default_factory=dict)

    # ── Long-term consequences ──────────────────────────────────
    # Every active time-shaped policy effect currently in flight — from
    # laws, loans, and treaties alike. See models/modifiers.py.
    modifiers: list[Modifier] = field(default_factory=list)

    # ── Dynamic events ───────────────────────────────────────────
    # Situations that have fired but await a player choice. See
    # models/events.py and engine/events.py.
    pending_events: list[PendingEvent] = field(default_factory=list)
    # event_id -> turn it last fired (drives once/cooldown gating).
    event_fire_history: dict = field(default_factory=dict)
    # Follow-up consequences scheduled by past choices:
    # {"event_id", "due_turn", "chance"} each.
    scheduled_events: list = field(default_factory=list)

    # Action cooldowns: action key -> turn it was last used (see
    # engine/player_ops.py: on_cooldown / start_cooldown).
    cooldowns: dict = field(default_factory=dict)

    # 0..1 — how active an armed insurgency is against the state. Driven by
    # narrative content (content/events.py: the Vasca arc), fed into the
    # civil-war gauge (engine/crisis.py) and decayed there each turn, so a
    # flare-up is a lasting pressure rather than a one-off stat hit.
    insurgency_pressure: float = 0.0

    # ── Government stability ────────────────────────────────────
    # The core aggregate simulation variable — see models/stability.py
    # and engine/stability.py.
    stability: GovernmentStability = field(default_factory=GovernmentStability)

    # ── Civil war ────────────────────────────────────────────────
    # 0..1 pressure gauge + latch for the player's country (engine/crisis.py);
    # an ongoing catastrophe, not a game-over.
    civil_war_risk: float = 0.0
    civil_war: bool = False
    civil_war_breakdown: dict = field(default_factory=dict)

    # ── Elections ────────────────────────────────────────────────
    # See models/election.py and engine/elections.py.
    ruling_faction_id: Optional[str] = None   # defaults to player.faction_id — see __post_init__
    last_election_turn: int = 0
    election_history: list[ElectionResult] = field(default_factory=list)

    # ── Logging ───────────────────────────────────────────────
    turn_log: list = field(default_factory=list)      # cleared each turn
    event_history: list = field(default_factory=list) # full game log
    # Structured news for the press (engine/press.py): (key, fields, text)
    # per dispatch this turn. Ephemeral like turn_log; not persisted.
    turn_news: list = field(default_factory=list)

    # ── World developments ─────────────────────────────────────
    # Named multi-month arcs between countries ("a|b" pair key -> "axis" or
    # "feud"), recorded once when they form. Persisted.
    world_arcs: dict = field(default_factory=dict)

    # ── Campaign ──────────────────────────────────────────────
    legacy: Optional[GovernmentLegacy] = None   # administration history record
    # Generation metadata (difficulty, seed, background, traits) as a plain
    # dict so new campaign options don't touch this dataclass.
    campaign_meta: dict = field(default_factory=dict)

    # ── Meta ──────────────────────────────────────────────────
    # Exact calendar position for the real-time-with-pause clock. ``turn``
    # remains the number of completed monthly simulation pulses so the
    # established month-scale mechanics retain their balance.
    day: int = 1
    day_index: int = 0
    turn: int = 0

    def __post_init__(self):
        if self.ruling_faction_id is None:
            self.ruling_faction_id = self.player.faction_id
        if self.legacy is None:
            self.legacy = GovernmentLegacy(
                country_id=self.country.id,
                leader_name=self.player.name,
                party_id=self.player.faction_id,
                start_date=self.date_string(),
            )

    # ── Convenience ───────────────────────────────────────────

    def date_string(self) -> str:
        months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return f"{self.day} {months[self.month - 1]} {self.year}"

    def calendar_date(self) -> date:
        """The exact in-game date as a standard-library date value."""
        return date(self.year, self.month, self.day)

    def days_in_current_month(self) -> int:
        return calendar.monthrange(self.year, self.month)[1]

    def coalition_faction_ids(self) -> list:
        return [f.id for f in self.country.factions if f.in_coalition]

    def log(self, message: str):
        """Append a message to this turn's log and the full history."""
        self.turn_log.append(message)
        self.event_history.append(f"[{self.date_string()}] {message}")

    def world_country(self, country_id: str):
        return next((c for c in self.world if c.id == country_id), None)
