"""
Campaign content: character backgrounds and difficulty presets. Pure data,
applied once at generation to nudge the starting position — difficulties
reshape the hole (or cushion) you start in, never the per-turn rules.
"""

from dataclasses import dataclass, field


# ── Character backgrounds ───────────────────────────────────────────────────

@dataclass
class Background:
    id: str
    name: str
    description: str
    # Small starting nudges. All optional.
    approval_delta: float = 0.0
    political_capital_delta: float = 0.0
    growth_delta: float = 0.0
    inflation_delta: float = 0.0
    bureaucratic_capacity_delta: float = 0.0
    stability_delta: float = 0.0
    # Loyalty nudges toward specific faction *archetypes*, matched by tag.
    # Applied to any faction whose economic/social lean fits (see campaign.py).
    labour_loyalty_delta: float = 0.0    # left-economic factions
    business_loyalty_delta: float = 0.0  # right-economic factions

    # The background's ONGOING ability (engine/player_ops.py:
    # op_background_action): a repeatable in-game action unique to who you
    # were before politics. Empty label = no ability.
    action_label: str = ""
    action_blurb: str = ""
    action_deed: str = ""        # the flavour line, filled into dispatches
    action_cost: float = 8.0
    action_cooldown: int = 10    # turns between uses


_BACKGROUNDS = {
    "none": Background(
        "none", "No Background",
        "No pre-political career nudge at all — the country exactly as authored, "
        "plus only its own inherent national traits.",
    ),
    "economist": Background(
        "economist", "Economist",
        "Years steering monetary policy give you a surer hand on the economy — "
        "and a little more credibility on growth.",
        growth_delta=0.004, inflation_delta=-0.004,
        action_label="Steady the Markets",
        action_blurb="Use your monetary credibility to talk inflation expectations down.",
        action_deed="walks the assembled financiers through the numbers until the panic loses its nerve",
        action_cost=8.0, action_cooldown=10,
    ),
    "lawyer": Background(
        "lawyer", "Lawyer",
        "A career in the courts sharpened your feel for institutions and process. "
        "The civil service runs a touch smoother under you.",
        bureaucratic_capacity_delta=0.05,
        action_label="Constitutional Craftsmanship",
        action_blurb="Redraft your pending bills so tightly that objections lose their footing.",
        action_deed="redrafts every pending bill into language even its enemies struggle to fault",
        action_cost=8.0, action_cooldown=10,
    ),
    "former_general": Background(
        "former_general", "Former General",
        "Command experience lends your government an air of order and resolve — "
        "institutions hold a little firmer.",
        stability_delta=0.05, business_loyalty_delta=0.05,
        action_label="Invoke Military Prestige",
        action_blurb="Remind the country who held the line — order firms up, liberals shift uneasily.",
        action_deed="appears in uniform among the honour guard, and the country stands a little straighter",
        action_cost=10.0, action_cooldown=12,
    ),
    "business_executive": Background(
        "business_executive", "Business Executive",
        "The boardroom taught you to read a balance sheet and win over capital. "
        "Business-aligned factions trust you more.",
        business_loyalty_delta=0.10, political_capital_delta=5.0,
        action_label="Convene the Roundtable",
        action_blurb="Call in the industrialists and squeeze out commitments to invest.",
        action_deed="locks the industrialists in a room until they sign investment commitments",
        action_cost=8.0, action_cooldown=10,
    ),
    "union_leader": Background(
        "union_leader", "Trade Union Leader",
        "You rose through the labour movement. Workers and the left start firmly "
        "in your corner, though capital eyes you warily.",
        labour_loyalty_delta=0.12, business_loyalty_delta=-0.05, approval_delta=0.02,
        action_label="Rally the Rank and File",
        action_blurb="Go back to the halls that made you and settle labour's grievances in person.",
        action_deed="returns to the union halls and speaks as one of their own",
        action_cost=8.0, action_cooldown=10,
    ),
    "academic": Background(
        "academic", "Academic",
        "A scholar-turned-politician: respected, thoughtful, and a bit more "
        "persuasive in the arena of ideas.",
        political_capital_delta=8.0,
        action_label="Publish the Argument",
        action_blurb="Lay out the government's case in a long essay everyone pretends to have read.",
        action_deed="publishes a closely argued essay that sets the terms of the debate for months",
        action_cost=6.0, action_cooldown=10,
    ),
    "career_politician": Background(
        "career_politician", "Career Politician",
        "You've done nothing but this your whole life. No special expertise — "
        "but a broad, dependable competence and a full war chest of favours.",
        political_capital_delta=6.0, approval_delta=0.01,
        action_label="Call in Favours",
        action_blurb="Every deal you ever made left a marker. Collect a few.",
        action_deed="makes a dozen quiet phone calls, and old debts come due",
        action_cost=0.0, action_cooldown=12,
    ),
}


def get_background(bg_id: str):
    return _BACKGROUNDS.get(bg_id)


def all_backgrounds() -> list:
    return list(_BACKGROUNDS.values())


# ── Difficulty presets ──────────────────────────────────────────────────────

@dataclass
class Difficulty:
    id: str
    name: str
    description: str
    # Multiplicative / additive nudges to the starting position.
    approval_delta: float = 0.0
    political_capital_delta: float = 0.0
    growth_delta: float = 0.0
    inflation_delta: float = 0.0
    debt_delta: float = 0.0
    unemployment_delta: float = 0.0
    stability_delta: float = 0.0
    # Coalition loyalty shift (applied to in-coalition factions) and
    # opposition strength shift (applied to hostile factions' power).
    coalition_loyalty_delta: float = 0.0
    opposition_power_delta: float = 0.0


_DIFFICULTIES = {
    "easy": Difficulty(
        "easy", "Easy",
        "A stronger economy, a contented public, and a loyal coalition. Room to learn.",
        approval_delta=0.08, political_capital_delta=15.0,
        growth_delta=0.010, inflation_delta=-0.008, debt_delta=-0.10,
        unemployment_delta=-0.02, stability_delta=0.10,
        coalition_loyalty_delta=0.15, opposition_power_delta=-0.10,
    ),
    "normal": Difficulty(
        "normal", "Normal",
        "The starting position as written — balanced, and unforgiving of nothing in particular.",
    ),
    "hard": Difficulty(
        "hard", "Hard",
        "A weak coalition, high debt and inflation, a strong opposition, and little "
        "political capital to spare. Every month is a negotiation with disaster.",
        approval_delta=-0.06, political_capital_delta=-12.0,
        growth_delta=-0.010, inflation_delta=0.015, debt_delta=0.20,
        unemployment_delta=0.03, stability_delta=-0.12,
        coalition_loyalty_delta=-0.15, opposition_power_delta=0.12,
    ),
}


def get_difficulty(diff_id: str):
    return _DIFFICULTIES.get(diff_id)


def all_difficulties() -> list:
    # Ordered easy → normal → hard for menus.
    return [_DIFFICULTIES["easy"], _DIFFICULTIES["normal"], _DIFFICULTIES["hard"]]
