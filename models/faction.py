from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Ideology:
    """
    2D political compass position.
    economic: -1.0 (far left / collectivist) to +1.0 (far right / free market)
    social:   -1.0 (authoritarian)           to +1.0 (libertarian)
    """
    economic: float = 0.0
    social: float = 0.0

    def distance_to(self, other: "Ideology") -> float:
        """Ideological distance. 0.0 = identical, ~2.83 = polar opposites."""
        return ((self.economic - other.economic) ** 2 +
                (self.social - other.social) ** 2) ** 0.5

    def label(self) -> str:
        e, s = self.economic, self.social
        if e < -0.5 and s < -0.5:  return "Authoritarian Left"
        if e < -0.5 and s >  0.5:  return "Libertarian Left"
        if e >  0.5 and s < -0.5:  return "Authoritarian Right"
        if e >  0.5 and s >  0.5:  return "Libertarian Right"
        if e < -0.3:                return "Centre Left"
        if e >  0.3:                return "Centre Right"
        return "Centrist"


@dataclass
class Grievance:
    source: str        # what caused this (e.g. "Austerity measures")
    severity: float    # 0.0–1.0
    turns_active: int = 0


@dataclass
class Demand:
    description: str
    urgency: float              # 0.0–1.0: how soon they need a response
    law_id: Optional[str] = None  # tied to specific legislation, if any


@dataclass
class Faction:
    """
    A political actor — a party, an institutional bloc, an interest group.
    The fundamental unit of domestic politics.
    """
    id: str
    name: str
    ideology: Ideology
    power: float         # 0.0–1.0: real-world leverage (money, org, media, votes)
    loyalty: float       # -1.0–1.0: disposition toward the player government
    seats: int           # seats in the legislature
    in_coalition: bool = False
    grievances: list = field(default_factory=list)  # list[Grievance]
    demands:    list = field(default_factory=list)  # list[Demand]

    # Share of the electorate backing this party (~sums to 1.0 across all).
    # Distinct from loyalty: support is the public's view of the party,
    # loyalty is the party's disposition toward the player's government.
    support: float = 0.2

    # Optional party identity colour (hex, e.g. "#c0392b"), used by the seat
    # arc and election results. None means "assign one from the shared palette"
    # (see ui/theme.py: assign_party_colors) — purely cosmetic, no mechanics.
    color: Optional[str] = None

    # Intra-party currents (models/wing.py): generic ideological wings or
    # authored social blocs. Empty → the party is monolithic.
    wings: list = field(default_factory=list)  # list[Wing]

    # The party leader's name — quoted in dispatches. Authored or generated
    # at load; purely narrative for now.
    leader: str = ""
    # Canonical political role (models/roles.py), assigned from this
    # faction's ideology when the country is built. Lets one authored event
    # address "the labour bloc" in any of the nine countries.
    role: str = ""

    def effective_ideology(self) -> "Ideology":
        """Strength-weighted average of the wings' positions; falls back to the
        party's own ideology when it has no wings."""
        if not self.wings:
            return self.ideology
        total = sum(max(0.0, w.strength) for w in self.wings)
        if total <= 0:
            return self.ideology
        econ = sum(w.ideology.economic * max(0.0, w.strength) for w in self.wings) / total
        soc = sum(w.ideology.social * max(0.0, w.strength) for w in self.wings) / total
        return Ideology(economic=econ, social=soc)

    def dominant_wing(self):
        """The highest-strength wing (the one setting the party line), or None."""
        return max(self.wings, key=lambda w: w.strength) if self.wings else None

    def cohesion(self) -> float:
        """0..1 internal unity: how tightly the wings cluster around the party's
        effective stance, tempered by their loyalty to the leadership."""
        if len(self.wings) < 2:
            return 1.0
        centre = self.effective_ideology()
        total = sum(max(0.0, w.strength) for w in self.wings) or 1.0
        spread = sum(w.ideology.distance_to(centre) * max(0.0, w.strength)
                     for w in self.wings) / total
        spread_unity = max(0.0, 1.0 - spread / 2.83)          # 2.83 = max distance
        loyalty_unity = (sum(w.loyalty for w in self.wings) / len(self.wings) + 1.0) / 2.0
        return max(0.0, min(1.0, 0.5 * spread_unity + 0.5 * loyalty_unity))

    def normalize_wings(self):
        """Clamp strengths ≥0 and renormalise them to sum to 1."""
        if not self.wings:
            return
        for w in self.wings:
            w.strength = max(0.0, w.strength)
        total = sum(w.strength for w in self.wings)
        if total <= 0:
            for w in self.wings:
                w.strength = 1.0 / len(self.wings)
        else:
            for w in self.wings:
                w.strength /= total

    def is_allied(self) -> bool:
        return self.in_coalition or self.loyalty > 0.4

    def is_hostile(self) -> bool:
        return self.loyalty < -0.3

    def opposition_strength(self) -> float:
        """How dangerous this faction is to the government right now."""
        if self.loyalty >= 0:
            return 0.0
        return abs(self.loyalty) * self.power

    def grievance_pressure(self) -> float:
        """How close this faction is to causing active trouble."""
        if not self.grievances:
            return 0.0
        return min(1.0, sum(g.severity for g in self.grievances) / 3)
