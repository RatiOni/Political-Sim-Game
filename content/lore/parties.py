"""The five Ardenian parties and their canonical internal currents."""

# Existing faction origins are intentionally unchanged: campaign briefings and
# the original Codex presentation depend on their exact values and order.
PARTY_ORIGINS = {
    "liberal_democrats":
        "Cyrus Baran's project, and the closest thing the transition has to "
        "an establishment: reform-minded Union-era technocrats, diaspora "
        "returnees and Awakening moderates who never trusted Vasca. Market "
        "reform, integration westward, and a civic rather than ethnic idea "
        "of who counts as Ardenian.",
    "national_conservatives":
        "The Awakening's respectable afterlife. Founded by nationalists who "
        "broke with Vasca before the shooting started, they inherited his "
        "voters without his baggage. Hawkish on the old Union, and defined "
        "above all by Vetrenka: for this party, non-recognition "
        "is not a policy position but an article of faith.",
    "social_democrats":
        "The reform wing of the old Ardenian Dravist Party, rebranded and "
        "re-legitimised. Not nostalgic for the Union, but unwilling to "
        "pretend those decades were only darkness — a great many of their "
        "voters remember full employment more vividly than they remember "
        "the purges. Mixed economy, welfare state, and a deep distrust of "
        "anything described as shock therapy.",
    "workers_front":
        "The people the last three years left behind twice: too late for the "
        "Union's privileges, too poor for the new economy's opportunities. "
        "Industrial workers from the sectors that died with Union demand. "
        "Not organised nostalgia for Dravism exactly — mostly, simply, "
        "aggrieved, and unrepresented by anyone else in the chamber.",
    "agrarian_union":
        "Decollectivisation's constituency. When the collective farms were "
        "broken up, the question of who actually got the land turned into a "
        "politics of its own: local, transactional, allergic to ideology, "
        "and far more interested in credit terms and road budgets than in "
        "whatever the larger parties are shouting about this week.",
}


# The canonical names and social bases of Ardenia's internal currents. Their
# live simulation profiles sit below the prose: the current is the same actor
# in both places, not a parallel generic-wing layer.
BLOCS = [
    {
        "id": "ld_circle",
        "parent_id": "liberal_democrats",
        "name": "The Circle",
        "body": (
            "The technocrats around Baran himself are credible abroad and "
            "disliked at home. They want the stabilisation programme and believe "
            "competence will eventually become a constituency."
        ),
    },
    {
        "id": "ld_return",
        "parent_id": "liberal_democrats",
        "name": "The Return",
        "body": (
            "Diaspora money and diaspora certainty: hardest on the Union, "
            "softest on the market, and impatient for the country they remember "
            "to be restored in stone as well as policy."
        ),
    },
    {
        "id": "ld_bar",
        "parent_id": "liberal_democrats",
        "name": "The Capital Bar",
        "body": (
            "Vashtera lawyers, importers and the new banks, interested in "
            "government chiefly as a source of licences."
        ),
    },
    {
        "id": "nc_square",
        "parent_id": "national_conservatives",
        "name": "The Square",
        "body": (
            "Kestrel Square veterans who are genuinely democratic and genuinely "
            "nationalist. They regard the republic as the achievement for which "
            "their dead friends paid."
        ),
    },
    {
        "id": "nc_line",
        "parent_id": "national_conservatives",
        "name": "The Line",
        "body": (
            "Irredentists with army connections, for whom Vetrenka is the only "
            "issue and Doncic's silence is a standing invitation."
        ),
    },
    {
        "id": "nc_parish",
        "parent_id": "national_conservatives",
        "name": "The Parish",
        "body": (
            "Anera and the Church: the current that would have to decide what "
            "to do if Dorin Vasca ever walked back into public life."
        ),
    },
    {
        "id": "sd_works",
        "parent_id": "social_democrats",
        "name": "The Works",
        "body": (
            "The Zavost union machine delivers the party's votes and expects "
            "the party to protect the plants in return."
        ),
    },
    {
        "id": "sd_reform",
        "parent_id": "social_democrats",
        "name": "The Reform Wing",
        "body": (
            "Former ministry cadres who know how the state functions and are "
            "among the few people in the Chamber capable of administering it. "
            "A breach with the Works would cost the government its majority."
        ),
    },
    {
        "id": "ag_grange",
        "parent_id": "agrarian_union",
        "name": "The Grange",
        "body": (
            "Those who received land when the collectives dissolved. They will "
            "trade on questions outside land, credit and diesel, and do not "
            "pretend otherwise."
        ),
    },
    {
        "id": "ag_leftout",
        "parent_id": "agrarian_union",
        "name": "The Left-Out",
        "body": (
            "Those who did not receive land in the dissolution, angrier than the "
            "Grange and available to whoever promises a second settlement."
        ),
    },
    {
        "id": "wf_shopfloor",
        "parent_id": "workers_front",
        "name": "The Shop Floor",
        "body": (
            "Genuine industrial militancy with the organisational reach to call "
            "a general strike in Zavost."
        ),
    },
    {
        "id": "wf_nostalgics",
        "parent_id": "workers_front",
        "name": "The Nostalgics",
        "body": (
            "The residue of the Dravist old guard: four seats shared with the "
            "Shop Floor, and a memory of a state that paid wages."
        ),
    },
]


# The numbers here are starting political balance, not demographic inputs.
# ``policy_biases`` are intentionally narrow: they give a bloc a stake in the
# bills already on the chamber's agenda without introducing a second ideology
# system. -1 means strongly opposed; +1 means strongly in favour.
BLOC_PROFILES = {
    "ld_circle": {
        "ideology": {"economic": 0.25, "social": 0.65}, "strength": 0.40, "loyalty": 0.82,
        "policy_biases": {"central_bank_independence_act": 0.30,
                          "emergency_price_controls": -0.25,
                          "fiscal_consolidation_act": 0.20},
    },
    "ld_return": {
        "ideology": {"economic": 0.68, "social": 0.42}, "strength": 0.27, "loyalty": 0.50,
        "policy_biases": {"telecom_privatization_act": 0.30,
                          "central_bank_independence_act": 0.20,
                          "press_freedom_act": 0.15},
    },
    "ld_bar": {
        "ideology": {"economic": 0.55, "social": 0.35}, "strength": 0.33, "loyalty": 0.62,
        "policy_biases": {"telecom_privatization_act": 0.35,
                          "central_bank_independence_act": 0.18,
                          "progressive_tax_reform_act": -0.32,
                          "emergency_price_controls": -0.35,
                          "infrastructure_investment_act": 0.12},
    },
    "nc_square": {
        "ideology": {"economic": 0.25, "social": -0.25}, "strength": 0.35, "loyalty": 0.68,
        "policy_biases": {"defense_spending_act": 0.18, "press_freedom_act": 0.18},
    },
    "nc_line": {
        "ideology": {"economic": 0.48, "social": -0.90}, "strength": 0.35, "loyalty": 0.34,
        "policy_biases": {"defense_spending_act": 0.45, "press_freedom_act": -0.12},
    },
    "nc_parish": {
        "ideology": {"economic": 0.18, "social": -0.70}, "strength": 0.30, "loyalty": 0.54,
        "policy_biases": {"press_freedom_act": -0.28, "education_modernisation_act": -0.10},
    },
    "sd_works": {
        "ideology": {"economic": -0.72, "social": 0.10}, "strength": 0.52, "loyalty": 0.42,
        "policy_biases": {"minimum_wage_act": 0.45, "telecom_privatization_act": -0.40,
                          "central_bank_independence_act": -0.25, "emergency_price_controls": 0.24,
                          "infrastructure_investment_act": 0.28},
    },
    "sd_reform": {
        "ideology": {"economic": -0.18, "social": 0.55}, "strength": 0.48, "loyalty": 0.74,
        "policy_biases": {"central_bank_independence_act": 0.20, "press_freedom_act": 0.28,
                          "infrastructure_investment_act": 0.30, "education_modernisation_act": 0.35},
    },
    "ag_grange": {
        "ideology": {"economic": -0.08, "social": -0.15}, "strength": 0.55, "loyalty": 0.66,
        "policy_biases": {"land_reform_act": 0.34, "infrastructure_investment_act": 0.34,
                          "emergency_price_controls": 0.12},
    },
    "ag_leftout": {
        "ideology": {"economic": -0.52, "social": -0.15}, "strength": 0.45, "loyalty": 0.36,
        "policy_biases": {"land_reform_act": 0.56, "progressive_tax_reform_act": 0.24,
                          "minimum_wage_act": 0.16},
    },
    "wf_shopfloor": {
        "ideology": {"economic": -0.86, "social": 0.24}, "strength": 0.65, "loyalty": 0.30,
        "policy_biases": {"minimum_wage_act": 0.52, "telecom_privatization_act": -0.48,
                          "central_bank_independence_act": -0.28, "emergency_price_controls": 0.36,
                          "infrastructure_investment_act": 0.22},
    },
    "wf_nostalgics": {
        "ideology": {"economic": -0.96, "social": -0.08}, "strength": 0.35, "loyalty": 0.12,
        "policy_biases": {"minimum_wage_act": 0.34, "telecom_privatization_act": -0.56,
                          "central_bank_independence_act": -0.42, "emergency_price_controls": 0.48,
                          "progressive_tax_reform_act": 0.30},
    },
}
