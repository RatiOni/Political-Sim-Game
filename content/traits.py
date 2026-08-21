"""
National traits: stable country descriptors that nudge starting conditions
once at campaign generation (never per-turn hooks) and provide flavour text
for selection/briefing screens. Adding one = a dict entry here + the trait id
in a country JSON's "national_traits".
"""

from dataclasses import dataclass, field


@dataclass
class Trait:
    id: str
    name: str
    description: str
    # Starting-condition deltas, all optional and small. Applied once, at
    # campaign generation, to the already-built player country/economy.
    bureaucratic_capacity_delta: float = 0.0
    stability_delta: float = 0.0
    growth_delta: float = 0.0
    inflation_delta: float = 0.0
    debt_delta: float = 0.0
    approval_delta: float = 0.0
    # Free-form tags other systems (or future procedural generation) can read.
    tags: list = field(default_factory=list)


_TRAITS = {
    "post_communist_legacy": Trait(
        "post_communist_legacy", "Post-Communist Legacy",
        "Decades of central planning left weak markets but a broad welfare habit. "
        "Institutions are still maturing.",
        bureaucratic_capacity_delta=-0.05, growth_delta=0.004, inflation_delta=0.010,
        tags=["transitional", "welfare_habit"],
    ),
    "strong_institutions": Trait(
        "strong_institutions", "Strong Institutions",
        "Courts, civil service, and central bank command real independence and public trust.",
        bureaucratic_capacity_delta=0.10, stability_delta=0.05,
        tags=["rule_of_law"],
    ),
    "weak_institutions": Trait(
        "weak_institutions", "Weak Institutions",
        "Rules bend to whoever holds power this month; the state struggles to deliver.",
        bureaucratic_capacity_delta=-0.10, stability_delta=-0.05,
        tags=["fragile"],
    ),
    "trade_oriented": Trait(
        "trade_oriented", "Trade-Oriented Economy",
        "An open, export-driven economy — prosperous when the world buys, exposed when it doesn't.",
        growth_delta=0.006, tags=["open_economy"],
    ),
    "agricultural": Trait(
        "agricultural", "Agricultural Economy",
        "A large rural sector: stable and self-reliant, but slower to grow and modernise.",
        growth_delta=-0.004, stability_delta=0.03, tags=["rural"],
    ),
    "high_corruption": Trait(
        "high_corruption", "High Corruption",
        "Patronage and graft siphon off public capacity and quietly erode trust.",
        bureaucratic_capacity_delta=-0.10, approval_delta=-0.03, tags=["corruption"],
    ),
    "low_corruption": Trait(
        "low_corruption", "Low Corruption",
        "Clean government: public money mostly reaches its purpose.",
        bureaucratic_capacity_delta=0.06, approval_delta=0.02, tags=["clean"],
    ),
    "federal": Trait(
        "federal", "Federal State",
        "Power is shared with strong regions — resilient, but harder to steer from the centre.",
        stability_delta=0.03, bureaucratic_capacity_delta=-0.03, tags=["decentralized"],
    ),
    "centralized": Trait(
        "centralized", "Centralized Government",
        "Authority concentrates in the capital — decisive, but brittle if the centre falters.",
        bureaucratic_capacity_delta=0.04, stability_delta=-0.02, tags=["centralized"],
    ),
    "resource_rich": Trait(
        "resource_rich", "Resource Wealth",
        "Oil, gas, or minerals fill the treasury — a cushion of easy money that also "
        "warps the economy around whoever controls the spigot.",
        growth_delta=0.006, debt_delta=-0.05, tags=["rentier", "resource"],
    ),
    "militarist": Trait(
        "militarist", "Militarist State",
        "The armed forces are a pillar of the regime — disciplined and assertive abroad, "
        "expensive and coup-prone at home.",
        stability_delta=0.03, debt_delta=0.05, tags=["militarist"],
    ),
    "ethnically_divided": Trait(
        "ethnically_divided", "Ethnic Fault Lines",
        "Deep communal divisions run under every institution; grievances travel fast and "
        "the centre is never fully trusted by the periphery.",
        stability_delta=-0.10, bureaucratic_capacity_delta=-0.04, tags=["fractured", "volatile"],
    ),
    "theocratic": Trait(
        "theocratic", "Theocratic Authority",
        "Political legitimacy flows from religious authority — a unifying source of order "
        "for believers, an exclusionary one for everyone else.",
        stability_delta=0.04, approval_delta=-0.02, tags=["theocratic"],
    ),
    "young_democracy": Trait(
        "young_democracy", "Young Democracy",
        "Democratic institutions are real but recent — enthusiastic, untested, and easily "
        "strained by their first serious crisis.",
        stability_delta=-0.05, bureaucratic_capacity_delta=-0.05, approval_delta=0.03,
        tags=["transitional", "hopeful"],
    ),
}


def get_trait(trait_id: str):
    return _TRAITS.get(trait_id)


def all_traits() -> list:
    return list(_TRAITS.values())


def describe_traits(trait_ids) -> list:
    """(name, description) pairs for the given trait ids, for display."""
    out = []
    for tid in trait_ids:
        t = _TRAITS.get(tid)
        if t:
            out.append((t.name, t.description))
    return out
