from dataclasses import dataclass, field

# A trading partner's economy is finite: volume converges on a ceiling set by
# how warm the relationship is (score × MAX_TRADE_VOLUME) instead of
# compounding forever. Calibrated so the authored starting volumes in
# content/countries/*.json ARE the equilibrium for their authored scores
# (e.g. Ardenia↔Veldoria: 0.6 × 4000 = 2400). Enforced at every write site
# (engine/turn.py, worldsim.py, diplomacy.py) so no path can reintroduce the
# snowball.
MAX_TRADE_VOLUME = 4000.0


def cap_trade_volume(value: float) -> float:
    return max(0.0, min(MAX_TRADE_VOLUME, value))


@dataclass
class Treaty:
    id: str
    name: str
    type: str         # 'trade' | 'defense' | 'non_aggression' | 'alliance'
    parties: list     # list of country_ids
    turns_active: int = 0


@dataclass
class BilateralRelation:
    """
    The relationship between two countries.
    score: -1.0 (openly hostile) to +1.0 (close allies)
    """
    country_a_id: str
    country_b_id: str
    score: float = 0.0           # -1.0 to 1.0
    trade_volume: float = 0.0    # annual trade in millions
    treaties: list = field(default_factory=list)   # list[Treaty]
    history:  list = field(default_factory=list)   # list[str]: log of key events
    sanctioned: bool = False     # an active sanctions regime on this pair

    def is_hostile(self) -> bool:
        return self.score < -0.3

    def is_friendly(self) -> bool:
        return self.score > 0.3

    def status_label(self) -> str:
        if   self.score >  0.7: return "Allied"
        elif self.score >  0.3: return "Friendly"
        elif self.score > -0.3: return "Neutral"
        elif self.score > -0.7: return "Tense"
        else:                   return "Hostile"
