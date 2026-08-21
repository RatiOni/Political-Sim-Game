"""
Bill catalog — proposable legislation, calibrated to Ardenia's factions.
faction_loyalty_deltas double as the vote-prediction "stake" signal.
Flat LawEffect deltas cover immediate/indefinite effects; author explicit
Modifiers when the delay/ramp/fade IS the point (see the last three bills).
"""

from models.faction import Ideology
from models.legislature import Law, LawEffect
from models.modifiers import Modifier


def bill_catalog() -> list:
    """
    Returns a fresh set of proposable bills. Called fresh each time a
    bill is needed so that proposing one never mutates a shared object.
    """
    return [
        Law(
            id="minimum_wage_act",
            name="Minimum Wage Increase Act",
            description="Raises the statutory minimum wage by 18%, indexed to inflation thereafter.",
            status="draft",
            tier="statutory",
            portfolio="Economy",
            ideology=Ideology(economic=-0.6, social=0.1),
            effects=LawEffect(
                unemployment_delta=0.006,
                budget_expenditure_delta=120.0,
                faction_loyalty_deltas={
                    "workers_front": 0.20,
                    "social_democrats": 0.12,
                    "national_conservatives": -0.10,
                    "liberal_democrats": -0.03,
                },
            ),
        ),
        Law(
            id="telecom_privatization_act",
            name="Telecom Privatisation Act",
            description="Sells the state telecom monopoly to private investors.",
            status="draft",
            tier="statutory",
            portfolio="Economy",
            ideology=Ideology(economic=0.7, social=0.1),
            effects=LawEffect(
                gdp_growth_delta=0.004,
                budget_revenue_delta=600.0,
                faction_loyalty_deltas={
                    "liberal_democrats": 0.08,
                    "national_conservatives": 0.10,
                    "workers_front": -0.20,
                    "social_democrats": -0.12,
                },
                faction_power_deltas={
                    "national_conservatives": 0.04,
                    "workers_front": -0.03,
                },
            ),
        ),
        Law(
            id="land_reform_act",
            name="Land Reform Act",
            description="Redistributes large agricultural holdings to smallholder farmers.",
            status="draft",
            tier="constitutional",
            portfolio="Interior",
            ideology=Ideology(economic=-0.6, social=-0.1),
            effects=LawEffect(
                gdp_growth_delta=-0.003,
                faction_loyalty_deltas={
                    "agrarian_union": 0.22,
                    "workers_front": 0.10,
                    "national_conservatives": -0.18,
                },
                faction_power_deltas={
                    "agrarian_union": 0.06,
                    "national_conservatives": -0.05,
                },
            ),
        ),
        Law(
            id="defense_spending_act",
            name="Defense Modernisation Act",
            description="Significantly increases the defense budget and procurement spending.",
            status="draft",
            tier="statutory",
            portfolio="Defense",
            ideology=Ideology(economic=0.2, social=-0.6),
            effects=LawEffect(
                budget_expenditure_delta=500.0,
                faction_loyalty_deltas={
                    "national_conservatives": 0.18,
                    "social_democrats": -0.10,
                    "workers_front": -0.08,
                },
            ),
        ),
        Law(
            id="press_freedom_act",
            name="Press Freedom Act",
            description="Enshrines constitutional protections for independent media and whistleblowers.",
            status="draft",
            tier="constitutional",
            portfolio="Justice",
            ideology=Ideology(economic=0.1, social=0.8),
            effects=LawEffect(
                faction_loyalty_deltas={
                    "liberal_democrats": 0.15,
                    "social_democrats": 0.08,
                    "national_conservatives": -0.14,
                },
            ),
        ),
        Law(
            id="central_bank_independence_act",
            name="Central Bank Independence Act",
            description="Removes the central bank from direct executive control to anchor monetary credibility.",
            status="draft",
            tier="statutory",
            portfolio="Finance",
            ideology=Ideology(economic=0.5, social=0.2),
            effects=LawEffect(
                inflation_delta=-0.012,
                faction_loyalty_deltas={
                    "liberal_democrats": 0.10,
                    "national_conservatives": 0.04,
                    "workers_front": -0.06,
                },
            ),
        ),
        Law(
            id="emergency_price_controls",
            name="Emergency Price Controls",
            description="Executive order capping prices on staple goods to blunt inflation immediately.",
            status="draft",
            tier="executive_order",
            portfolio="Economy",
            ideology=Ideology(economic=-0.5, social=-0.2),
            effects=LawEffect(
                inflation_delta=-0.02,
                gdp_growth_delta=-0.006,
                faction_loyalty_deltas={
                    "workers_front": 0.10,
                    "national_conservatives": -0.06,
                },
            ),
        ),

        # ── Long-term consequence showcase ──────────────────────────────
        # These three bills use explicit Modifiers rather than flat deltas,
        # because their defining trait is exactly the thing flat deltas
        # can't express: the payoff or the pain doesn't land all at once.

        Law(
            id="progressive_tax_reform_act",
            name="Progressive Tax Reform Act",
            description="Raises income and corporate tax rates on higher brackets to increase state revenue.",
            status="draft",
            tier="statutory",
            portfolio="Finance",
            ideology=Ideology(economic=-0.6, social=0.1),
            effects=LawEffect(
                # Immediate political reaction to the ANNOUNCEMENT — factions
                # react fast to what a law says the moment it passes.
                faction_loyalty_deltas={
                    "liberal_democrats": -0.03,
                    "social_democrats": 0.10,
                    "national_conservatives": -0.08,
                    "workers_front": 0.05,
                },
                modifiers=[
                    # Revenue collection ramps up fairly quickly once the new
                    # brackets take effect.
                    Modifier(
                        id="tax_reform_revenue", source="Progressive Tax Reform Act",
                        target="budget_revenue", magnitude=500.0,
                        onset_delay=0, ramp_duration=4, hold_duration=None,
                        portfolio="Finance",
                    ),
                    # But the MATERIAL effect on ordinary approval — people
                    # feeling the bite in their paychecks — builds slowly
                    # over about ten months, distinct from the immediate
                    # political reaction above.
                    Modifier(
                        id="tax_reform_approval", source="Progressive Tax Reform Act",
                        target="approval_bias", magnitude=-0.05,
                        onset_delay=2, ramp_duration=10, hold_duration=None,
                        portfolio="Finance",
                    ),
                ],
            ),
        ),

        Law(
            id="infrastructure_investment_act",
            name="Infrastructure Investment Act",
            description="A multi-year programme of road, rail, and grid construction, financed by new bond issuance.",
            status="draft",
            tier="statutory",
            portfolio="Economy",
            ideology=Ideology(economic=0.0, social=-0.1),
            effects=LawEffect(
                one_time_debt_pct_delta=0.025,  # the bond issuance itself — immediate, one-time
                faction_loyalty_deltas={
                    "national_conservatives": 0.06,
                    "agrarian_union": 0.08,
                    "liberal_democrats": 0.02,
                },
                modifiers=[
                    # Construction costs money for the ~2.5 years the
                    # programme runs, then tapers off as projects wrap up.
                    Modifier(
                        id="infra_construction_cost", source="Infrastructure Investment Act",
                        target="budget_expenditure", magnitude=700.0,
                        onset_delay=0, ramp_duration=2, hold_duration=30, decay_duration=6,
                        portfolio="Economy",
                    ),
                    # The payoff: nothing for two years while it's being
                    # built, then a permanent growth boost as it comes online.
                    Modifier(
                        id="infra_growth_payoff", source="Infrastructure Investment Act",
                        target="gdp_growth", magnitude=0.007,
                        onset_delay=24, ramp_duration=24, hold_duration=None,
                        portfolio="Economy",
                    ),
                ],
            ),
        ),

        Law(
            id="education_modernisation_act",
            name="Education Modernisation Act",
            description="Overhauls curricula, teacher training, and school funding to raise long-run workforce quality.",
            status="draft",
            tier="statutory",
            portfolio=None,  # implemented broadly across the school system, not one ministry
            ideology=Ideology(economic=-0.2, social=0.3),
            effects=LawEffect(
                faction_loyalty_deltas={
                    "liberal_democrats": 0.08,
                    "social_democrats": 0.10,
                    "national_conservatives": -0.04,
                },
                modifiers=[
                    # Running better schools costs money right away.
                    Modifier(
                        id="edu_funding_cost", source="Education Modernisation Act",
                        target="budget_expenditure", magnitude=180.0,
                        onset_delay=0, ramp_duration=3, hold_duration=None,
                    ),
                    # The whole point: a reformed cohort doesn't reach the
                    # workforce for years. Nothing happens for three years,
                    # then workforce quality climbs over the following two
                    # as that cohort graduates in — the longest fuse of any
                    # policy in this catalog, by design.
                    Modifier(
                        id="edu_workforce_payoff", source="Education Modernisation Act",
                        target="workforce_quality", magnitude=0.22,
                        onset_delay=36, ramp_duration=24, hold_duration=None,
                    ),
                ],
            ),
        ),
    ]
