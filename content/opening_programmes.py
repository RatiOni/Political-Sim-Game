"""Authored first-ninety-day programmes.

These are navigation and intent, not effect bundles.  The engine reads the
stable ids below to recognise work the player has already done through the
ordinary policy, party, parliamentary, and regional systems.
"""


OPENING_PROGRAMMES = [
    {
        "id": "government_household_settlement",
        "role": "government",
        "name": "A Household Settlement",
        "body": (
            "Put living standards ahead of institutional grandeur. Diagnose the "
            "pressure on wages and prices, bring relief before parliament, and "
            "settle one grievance before it hardens into organised resistance."
        ),
        "tasks": [
            {
                "id": "household_objective",
                "name": "Name the household problem",
                "body": "Adopt a reform objective centred on purchasing power or work and wages.",
                "page": "Policies",
                "check": "reform_objective",
                "objective_ids": ["restore_purchasing_power", "secure_work_and_wages"],
            },
            {
                "id": "household_measure",
                "name": "Put relief before parliament",
                "body": "Propose a wage, price, or tax measure as the programme's first bill.",
                "page": "Policies",
                "check": "propose_bill",
                "bill_ids": [
                    "minimum_wage_act", "emergency_price_controls",
                    "progressive_tax_reform_act",
                ],
            },
            {
                "id": "household_address",
                "name": "Address the country",
                "body": "Use a national address to explain the government's opening direction.",
                "page": "Briefing",
                "check": "action",
                "action_id": "address_nation",
            },
        ],
    },
    {
        "id": "government_jobs_regions",
        "role": "government",
        "name": "Jobs Across Ardenia",
        "body": (
            "Make recovery visible beyond the capital. Choose an employment or "
            "regional diagnosis, commit the state to one local programme, and give "
            "the chamber a measure that can widen productive opportunity."
        ),
        "tasks": [
            {
                "id": "jobs_objective",
                "name": "Choose the recovery diagnosis",
                "body": "Adopt a jobs, productive-economy, or regional-inequality objective.",
                "page": "Policies",
                "check": "reform_objective",
                "objective_ids": [
                    "secure_work_and_wages", "modernise_productive_economy",
                    "reduce_regional_inequality",
                ],
            },
            {
                "id": "jobs_programme",
                "name": "Commit to one region",
                "body": "Launch industrial recovery or public works in a region that needs it.",
                "page": "Game map",
                "check": "regional_programme",
                "programme_ids": ["industrial_recovery", "public_works"],
            },
            {
                "id": "jobs_measure",
                "name": "Legislate for productive recovery",
                "body": "Propose infrastructure, education, or minimum-wage legislation.",
                "page": "Policies",
                "check": "propose_bill",
                "bill_ids": [
                    "infrastructure_investment_act", "education_modernisation_act",
                    "minimum_wage_act",
                ],
            },
        ],
    },
    {
        "id": "government_working_state",
        "role": "government",
        "name": "A State That Works",
        "body": (
            "Treat administrative weakness as the government's first political fact. "
            "Choose a capacity diagnosis, establish a regional arm of the state, and "
            "demonstrate that the ministry can carry a real legislative commitment."
        ),
        "tasks": [
            {
                "id": "state_objective",
                "name": "Diagnose the state's weakness",
                "body": "Adopt a state-capacity or public-services reform objective.",
                "page": "Policies",
                "check": "reform_objective",
                "objective_ids": ["strengthen_state_capacity", "rebuild_public_services"],
            },
            {
                "id": "state_programme",
                "name": "Extend administrative reach",
                "body": "Launch an administrative, customs, or security programme in one region.",
                "page": "Game map",
                "check": "regional_programme",
                "programme_ids": [
                    "administrative_deployment", "customs_enforcement",
                    "security_stabilisation",
                ],
            },
            {
                "id": "state_measure",
                "name": "Test the machinery of government",
                "body": "Put one player-authored measure before parliament.",
                "page": "Policies",
                "check": "action",
                "action_id": "propose_bill",
            },
        ],
    },
    {
        "id": "opposition_government_in_waiting",
        "role": "opposition",
        "name": "A Government in Waiting",
        "body": (
            "Build credibility before chasing the government's every move. Publish one "
            "promise, give it a responsible shadow minister, and take that promise to "
            "the electorate."
        ),
        "tasks": [
            {
                "id": "waiting_pledge",
                "name": "Publish a governing promise",
                "body": "Add one concrete bill to the election platform.",
                "page": "Policies",
                "check": "pledge",
            },
            {
                "id": "waiting_shadow",
                "name": "Name a responsible front bench",
                "body": "Appoint at least one shadow minister.",
                "page": "Cabinet",
                "check": "shadow_minister",
            },
            {
                "id": "waiting_campaign",
                "name": "Campaign on substance",
                "body": "Campaign at least once on a published pledge.",
                "page": "Policies",
                "check": "pledge_campaign",
            },
        ],
    },
    {
        "id": "opposition_parliamentary_test",
        "role": "opposition",
        "name": "Test the Government",
        "body": (
            "Use parliament to define the alternative. Publish your own commitment, "
            "staff the front bench, and make a recorded choice on the government's "
            "legislative programme."
        ),
        "tasks": [
            {
                "id": "test_pledge",
                "name": "State the alternative",
                "body": "Add one concrete bill to the election platform.",
                "page": "Policies",
                "check": "pledge",
            },
            {
                "id": "test_shadow",
                "name": "Staff the challenge",
                "body": "Appoint at least one shadow minister.",
                "page": "Cabinet",
                "check": "shadow_minister",
            },
            {
                "id": "test_response",
                "name": "Take a parliamentary position",
                "body": "Support, oppose, or amend one government bill.",
                "page": "Policies",
                "check": "action",
                "action_id": "respond_government_bill",
            },
        ],
    },
    {
        "id": "opposition_regional_rebuild",
        "role": "opposition",
        "name": "Rebuild from the Regions",
        "body": (
            "Turn national opposition into a local organisation. Publish a promise, "
            "take the party into one reachable region, and return to campaign on the "
            "commitment you made."
        ),
        "tasks": [
            {
                "id": "regions_pledge",
                "name": "Give the campaign a promise",
                "body": "Add one concrete bill to the election platform.",
                "page": "Policies",
                "check": "pledge",
            },
            {
                "id": "regions_campaign",
                "name": "Build a regional organisation",
                "body": "Campaign in at least one reachable region.",
                "page": "Game map",
                "check": "regional_campaign",
            },
            {
                "id": "regions_message",
                "name": "Campaign on the programme",
                "body": "Campaign at least once on a published pledge.",
                "page": "Policies",
                "check": "pledge_campaign",
            },
        ],
    },
]


PROGRAMME_BY_ID = {programme["id"]: programme for programme in OPENING_PROGRAMMES}
