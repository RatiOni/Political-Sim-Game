"""Authored spending envelopes for the annual appropriations system.

These are stable policy ids shared by the engine and both front-ends. The
delivery portfolios are hooks for the ministry-capacity layer; appropriations
do not yet manufacture immediate policy outcomes on their own.
"""


BUDGET_ENVELOPES = [
    {
        "id": "state_administration",
        "name": "State Administration",
        "body": "The civil service, revenue offices, records and ordinary machinery of the state.",
        "share": 0.08,
        "portfolio": "Interior",
        "economic_weight": 0.10,
        "social_weight": -0.15,
    },
    {
        "id": "foreign_affairs",
        "name": "Foreign Affairs",
        "body": "The diplomatic service, embassies, treaty administration and foreign intelligence work.",
        "share": 0.04,
        "portfolio": "Foreign Affairs",
        "economic_weight": 0.05,
        "social_weight": 0.10,
    },
    {
        "id": "justice_and_policing",
        "name": "Justice and Policing",
        "body": "The courts, prosecutors, police and the institutions that make state authority lawful.",
        "share": 0.07,
        "portfolio": "Justice",
        "economic_weight": 0.05,
        "social_weight": -0.65,
    },
    {
        "id": "national_defense",
        "name": "National Defense",
        "body": "The armed forces, border defense, readiness and procurement.",
        "share": 0.15,
        "portfolio": "Defense",
        "economic_weight": 0.15,
        "social_weight": -0.85,
    },
    {
        "id": "infrastructure",
        "name": "Infrastructure",
        "body": "Roads, rail, water, power networks and the capital works that bind the country together.",
        "share": 0.12,
        "portfolio": "Economy",
        "economic_weight": -0.35,
        "social_weight": 0.05,
    },
    {
        "id": "industry_and_jobs",
        "name": "Industry and Jobs",
        "body": "Industrial support, employment programmes, rural credit and economic reconstruction.",
        "share": 0.09,
        "portfolio": "Economy",
        "economic_weight": -0.60,
        "social_weight": 0.05,
    },
    {
        "id": "education",
        "name": "Education",
        "body": "Schools, colleges, vocational training and the next generation of the workforce.",
        "share": 0.16,
        "portfolio": "Finance",
        "economic_weight": -0.65,
        "social_weight": 0.55,
    },
    {
        "id": "health_and_welfare",
        "name": "Health and Welfare",
        "body": "Hospitals, clinics, pensions, income support and protection from destitution.",
        "share": 0.29,
        "portfolio": "Finance",
        "economic_weight": -0.90,
        "social_weight": 0.35,
    },
]

ENVELOPE_BY_ID = {item["id"]: item for item in BUDGET_ENVELOPES}
BUDGET_ADJUSTMENTS = (-0.15, -0.10, -0.05, 0.0, 0.05, 0.10, 0.15)
