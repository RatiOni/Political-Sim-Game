from dataclasses import dataclass, field
from typing import Optional

# The portfolios that exist in this government. Used to detect vacancies —
# a portfolio with no minister still appears here, just unfilled.
CORE_PORTFOLIOS = ["Finance", "Interior", "Foreign Affairs", "Defense", "Economy", "Justice"]

# Personality traits and their mechanical teeth. (Mechanics live here in
# models — content/ may not be imported upward; flavor copy lives in
# content/dispatches.py.)
#   competence_delta — applied in effective_competence()
#   threat_mult      — scales threat_level()
#   appoint_faction_bonus — extra loyalty for their party on appointment
#   loyalty_floor    — drift-proof minimum loyalty (engine/turn.py enforces)
#   stability_bonus  — added to the cabinet stability component per holder
#   grows            — schemer drift per turn: (competence, ambition)
TRAIT_EFFECTS = {
    "technocrat": {"label": "Technocrat", "competence_delta": 0.10, "threat_mult": 0.9,
                   "blurb": "Runs the department like a machine."},
    "firebrand":  {"label": "Firebrand", "appoint_faction_bonus": 0.04, "threat_mult": 1.25,
                   "blurb": "The base loves them; the tabloids love them more."},
    "loyalist":   {"label": "Loyalist", "competence_delta": -0.05, "threat_mult": 0.5,
                   "loyalty_floor": 0.55,
                   "blurb": "Picked for faith, not brilliance. Never wavers."},
    "grandee":    {"label": "Grandee", "threat_mult": 0.8, "stability_bonus": 0.05,
                   "blurb": "An elder statesman whose presence steadies the room."},
    # A schemer's loyalty erodes as their ambition grows — without that,
    # threat_level() is capped at ambition * (1 - loyalty), so a minister
    # appointed at loyalty 0.5 could never reach the 0.5 threat threshold
    # no matter how ambitious they became, and neither the restless warning
    # nor the schemer arc would ever fire.
    "schemer":    {"label": "Schemer", "threat_mult": 1.0, "grows": (0.004, 0.008),
                   "loyalty_drift": -0.005,
                   "blurb": "Brilliant, improving, and always watching your chair."},
}


def trait_effect(trait: str, key: str, default=0.0):
    return TRAIT_EFFECTS.get(trait, {}).get(key, default)


@dataclass
class Minister:
    """
    A cabinet member. Not just an administrator — a political actor
    with their own ambitions, faction ties, and personal agenda.

    competence: how well their department actually functions
    loyalty:    whether they faithfully implement your policies
    ambition:   how much they want power for themselves
    """
    id: str
    name: str
    portfolio: str      # e.g. "Finance", "Interior", "Foreign Affairs"
    faction_id: str     # which faction they represent in cabinet
    competence: float   # 0.0–1.0
    loyalty: float      # 0.0–1.0
    ambition: float     # 0.0–1.0
    trait: str = ""     # key into TRAIT_EFFECTS; "" = no notable personality

    def trait_label(self) -> str:
        return trait_effect(self.trait, "label", "")

    def effective_competence(self) -> float:
        """How well they actually do the job — the raw stat plus what their
        personality brings to (or drains from) the office."""
        return max(0.0, min(1.0, self.competence
                            + trait_effect(self.trait, "competence_delta", 0.0)))

    def is_reliable(self) -> bool:
        """Loyal enough and capable enough to be trusted."""
        return self.loyalty > 0.6 and self.effective_competence() > 0.5

    def threat_level(self) -> float:
        """
        How dangerous this minister is to the player's position.
        High ambition + low loyalty = internal threat; personality scales it.
        """
        return (self.ambition * (1.0 - self.loyalty)
                * trait_effect(self.trait, "threat_mult", 1.0))

    def implementation_quality(self) -> float:
        """
        How faithfully this minister carries out policy.
        A disloyal minister subtly distorts what you want.
        """
        return self.effective_competence() * (0.5 + 0.5 * self.loyalty)


@dataclass
class Cabinet:
    ministers: list = field(default_factory=list)  # list[Minister]

    def get(self, portfolio: str) -> Optional[Minister]:
        return next((m for m in self.ministers if m.portfolio == portfolio), None)

    def average_loyalty(self) -> float:
        if not self.ministers:
            return 0.0
        return sum(m.loyalty for m in self.ministers) / len(self.ministers)

    def average_competence(self) -> float:
        if not self.ministers:
            return 0.0
        return sum(m.effective_competence() for m in self.ministers) / len(self.ministers)

    def stability_trait_bonus(self) -> float:
        """Grandees steady the government — capped so a cabinet of elders
        doesn't trivialise stability."""
        bonus = sum(trait_effect(m.trait, "stability_bonus", 0.0) for m in self.ministers)
        return min(0.10, bonus)

    def internal_threats(self) -> list:
        """Ministers who are a potential threat to the player."""
        return [m for m in self.ministers if m.threat_level() > 0.5]
