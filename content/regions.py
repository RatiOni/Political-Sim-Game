"""Authored starting conditions for Ardenia's regional simulation.

The figures here are simulation parameters, not claims about the real world
and not a second copy of the lore.  Names and long-form geography remain in
content/lore/geography.py; these profiles connect those stable ids to the
campaign values that change over time.
"""


CONTROL_LABELS = {
    "state": "Direct state administration",
    "limited": "State authority is uneven",
    "autonomous": "Shared authority under the peace framework",
    "separatist": "Outside Vashtera's administration",
}


ARDENIA_NATIONAL_SUPPORT_BASELINE = {
    "liberal_democrats": 0.38,
    "national_conservatives": 0.32,
    "social_democrats": 0.18,
    "agrarian_union": 0.08,
    "workers_front": 0.04,
}


ARDENIA_REGION_PROFILES = {
    "vashtera": {
        "name": "Vashtera",
        "population_weight": 0.28,
        "unemployment_gap": -0.035,
        "initial_unemployment": 0.075,
        "reach_offset": 0.17,
        "initial_state_reach": 0.92,
        "initial_pressure": 0.24,
        "pressure_bias": 0.00,
        "control": "state",
        "party_support": {
            "liberal_democrats": 0.50, "national_conservatives": 0.25,
            "social_democrats": 0.18, "agrarian_union": 0.03,
            "workers_front": 0.04,
        },
        "issue_id": "administrative_overload",
        "issue_name": "Administrative overload",
        "issue_body": (
            "The capital has the republic's strongest institutions and its least "
            "forgiving public. Ministries can act here, but every failure is visible."
        ),
    },
    "zavost": {
        "name": "Zavost",
        "population_weight": 0.18,
        "unemployment_gap": 0.090,
        "initial_unemployment": 0.205,
        "reach_offset": -0.13,
        "initial_state_reach": 0.61,
        "initial_pressure": 0.68,
        "pressure_bias": 0.14,
        "control": "state",
        "party_support": {
            "liberal_democrats": 0.30, "national_conservatives": 0.33,
            "social_democrats": 0.25, "agrarian_union": 0.03,
            "workers_front": 0.09,
        },
        "issue_id": "industrial_reckoning",
        "issue_name": "Industrial reckoning",
        "issue_body": (
            "Idle plants, wage arrears and exhausted company towns have made employment "
            "the test by which Zavost judges the new order."
        ),
    },
    "sela": {
        "name": "Sela",
        "population_weight": 0.20,
        "unemployment_gap": 0.025,
        "initial_unemployment": 0.135,
        "reach_offset": -0.20,
        "initial_state_reach": 0.54,
        "initial_pressure": 0.51,
        "pressure_bias": 0.09,
        "control": "state",
        "party_support": {
            "liberal_democrats": 0.34, "national_conservatives": 0.32,
            "social_democrats": 0.15, "agrarian_union": 0.16,
            "workers_front": 0.03,
        },
        "issue_id": "land_settlement",
        "issue_name": "The land settlement",
        "issue_body": (
            "Farm titles, old collective holdings and access to the Kesla corridor are "
            "being argued together. A technical settlement will still choose winners."
        ),
    },
    "anera": {
        "name": "Anera",
        "population_weight": 0.12,
        "unemployment_gap": 0.055,
        "initial_unemployment": 0.165,
        "reach_offset": -0.47,
        "initial_state_reach": 0.28,
        "initial_pressure": 0.70,
        "pressure_bias": 0.13,
        "control": "limited",
        "party_support": {
            "liberal_democrats": 0.20, "national_conservatives": 0.55,
            "social_democrats": 0.08, "agrarian_union": 0.15,
            "workers_front": 0.02,
        },
        "issue_id": "absent_state",
        "issue_name": "The absent state",
        "issue_body": (
            "In the uplands the republic is often a distant tax notice, a thin police "
            "post and a road that has not been repaired. Local loyalties fill the gap."
        ),
    },
    "kelvet": {
        "name": "Kelvet",
        "population_weight": 0.14,
        "unemployment_gap": -0.010,
        "initial_unemployment": 0.100,
        "reach_offset": -0.23,
        "initial_state_reach": 0.51,
        "initial_pressure": 0.48,
        "pressure_bias": 0.07,
        "control": "state",
        "party_support": {
            "liberal_democrats": 0.47, "national_conservatives": 0.34,
            "social_democrats": 0.14, "agrarian_union": 0.02,
            "workers_front": 0.03,
        },
        "issue_id": "customs_capture",
        "issue_name": "Customs capture",
        "issue_body": (
            "Trade keeps the coast moving, but the line between a licensed cargo and a "
            "protected one is narrow. Customs reform threatens several quiet fortunes."
        ),
    },
    "vetrenka": {
        "name": "Vetrenka",
        "population_weight": 0.08,
        "unemployment_gap": 0.120,
        "initial_unemployment": 0.235,
        "reach_offset": -0.71,
        "initial_state_reach": 0.04,
        "initial_pressure": 0.90,
        "pressure_bias": 0.22,
        "control": "separatist",
        "party_support": {
            "liberal_democrats": 0.18, "national_conservatives": 0.55,
            "social_democrats": 0.08, "agrarian_union": 0.15,
            "workers_front": 0.04,
        },
        "issue_id": "unsettled_ceasefire",
        "issue_name": "The unsettled ceasefire",
        "issue_body": (
            "The line has stopped moving, not become a border or a peace. Families, "
            "freight and armed men still live by rules Vashtera does not set."
        ),
    },
}


# Issues are keyed separately from regions because a consequential event can
# close one question and open another without changing the geographic id.
REGIONAL_ISSUES = {
    profile["issue_id"]: {
        "name": profile["issue_name"],
        "body": profile["issue_body"],
    }
    for profile in ARDENIA_REGION_PROFILES.values()
}
REGIONAL_ISSUES.update({
    "postwar_framework": {
        "name": "Making the framework real",
        "body": (
            "The shooting has stopped under an agreed formula. Return, policing and "
            "shared administration now have to work in villages that trusted neither side."
        ),
    },
    "occupation_and_return": {
        "name": "Occupation and return",
        "body": (
            "The flag has returned ahead of ordinary government. Security, displaced "
            "families and reconstruction now compete for an administration built in war."
        ),
    },
    "worsened_ceasefire": {
        "name": "A line moved by defeat",
        "body": (
            "The failed offensive left the line further inland and the separatist position "
            "harder. Border communities are living with the government's miscalculation."
        ),
    },
    "hardened_partition": {
        "name": "The permanent temporary line",
        "body": (
            "Crossings and customs now make the ceasefire durable without making it lawful. "
            "The practical settlement has become the political grievance."
        ),
    },
    "contested_partition": {
        "name": "The partition backlash",
        "body": (
            "The line has hardened, but the country has not accepted the bargain. Veterans, "
            "displaced families and the opposition are organising around reversal."
        ),
    },
})


# Regional programmes are authored policy instruments rather than event
# choices. Effects are the intended full-program change before delivery
# quality and the region's structural multiplier are applied. The monthly
# simulation spreads them across the duration.
REGIONAL_PROGRAMS = {
    "industrial_recovery": {
        "name": "Industrial recovery package",
        "short_name": "Industrial recovery",
        "body": (
            "Temporary payroll support, plant rehabilitation and credit guarantees for "
            "employers willing to keep production and apprenticeships in the region."
        ),
        "portfolio": "Economy",
        "pc_cost": 12.0,
        "duration": 12,
        "monthly_cost": 110.0,
        "effects": {"unemployment": -0.035, "state_reach": 0.01, "pressure": -0.10},
        "faction_loyalty_deltas": {
            "workers_front": 0.04, "social_democrats": 0.03,
            "liberal_democrats": -0.02,
        },
        "regional_support_deltas": {
            "workers_front": 0.025, "social_democrats": 0.020,
            "liberal_democrats": -0.010,
        },
        "region_multipliers": {"zavost": 1.25, "vashtera": 0.80, "anera": 0.85},
        "blocked_controls": ["separatist"],
    },
    "administrative_deployment": {
        "name": "Regional administrative mission",
        "short_name": "Administrative mission",
        "body": (
            "Second civil servants, inspectors and mobile public offices into the region, "
            "with money for records, local posts and the roads needed to reach them."
        ),
        "portfolio": "Interior",
        "pc_cost": 10.0,
        "duration": 10,
        "monthly_cost": 70.0,
        "effects": {"unemployment": -0.004, "state_reach": 0.15, "pressure": -0.08},
        "faction_loyalty_deltas": {
            "liberal_democrats": 0.02, "agrarian_union": 0.02,
        },
        "regional_support_deltas": {
            "liberal_democrats": 0.025, "agrarian_union": 0.010,
        },
        "region_multipliers": {"anera": 1.25, "vashtera": 0.70, "vetrenka": 0.80},
        "blocked_controls": ["separatist"],
    },
    "public_works": {
        "name": "Regional public-works programme",
        "short_name": "Public works",
        "body": (
            "Repair transport, power and municipal infrastructure through local contracts. "
            "The employment arrives first; durable state presence takes longer."
        ),
        "portfolio": "Economy",
        "pc_cost": 14.0,
        "duration": 18,
        "monthly_cost": 140.0,
        "effects": {"unemployment": -0.018, "state_reach": 0.08, "pressure": -0.10},
        "faction_loyalty_deltas": {
            "social_democrats": 0.03, "agrarian_union": 0.02,
            "liberal_democrats": -0.02,
        },
        "regional_support_deltas": {
            "social_democrats": 0.025, "agrarian_union": 0.020,
            "liberal_democrats": -0.010,
        },
        "region_multipliers": {"sela": 1.15, "anera": 1.10, "vashtera": 0.80},
        "blocked_controls": ["separatist"],
    },
    "customs_enforcement": {
        "name": "Kelvet customs clean-up",
        "short_name": "Customs clean-up",
        "body": (
            "Rotate officers, audit bonded warehouses and put the port manifests under one "
            "chain of command. The state gains ground; protected traders lose it."
        ),
        "portfolio": "Justice",
        "pc_cost": 9.0,
        "duration": 12,
        "monthly_cost": 55.0,
        "effects": {"unemployment": 0.004, "state_reach": 0.13, "pressure": -0.07},
        "faction_loyalty_deltas": {
            "liberal_democrats": 0.02, "national_conservatives": 0.01,
        },
        "regional_support_deltas": {
            "liberal_democrats": 0.020, "national_conservatives": 0.010,
            "workers_front": -0.010,
        },
        "region_multipliers": {"kelvet": 1.30},
        "allowed_regions": ["kelvet"],
        "blocked_controls": ["separatist"],
        "launch_pressure": 0.035,
    },
    "security_stabilisation": {
        "name": "Security stabilisation operation",
        "short_name": "Security operation",
        "body": (
            "Concentrate police, courts and intelligence against armed networks. It may "
            "restore access, but the opening raids increase tension before they reduce it."
        ),
        "portfolio": "Interior",
        "pc_cost": 11.0,
        "duration": 8,
        "monthly_cost": 90.0,
        "effects": {"unemployment": 0.002, "state_reach": 0.09, "pressure": -0.12},
        "faction_loyalty_deltas": {
            "national_conservatives": 0.05, "social_democrats": -0.03,
            "workers_front": -0.04, "liberal_democrats": -0.01,
        },
        "regional_support_deltas": {
            "national_conservatives": 0.035, "social_democrats": -0.015,
            "workers_front": -0.020,
        },
        "region_multipliers": {"anera": 1.15, "vetrenka": 0.85},
        "blocked_controls": ["separatist"],
        "launch_pressure": 0.06,
    },
}
