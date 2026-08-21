"""Ardenia's social groups and their starting regional distribution."""


HOUSEHOLD_GROUPS = [
    {
        "id": "urban_workers", "name": "Urban wage earners",
        "body": "Factory, transport and service workers living principally from wages.",
        "growth_exposure": 0.45, "income_indexation": 0.55,
        "job_sensitivity": 1.25, "price_sensitivity": 1.05,
        "service_dependence": 0.70, "welfare_dependence": 0.20,
    },
    {
        "id": "salaried_middle", "name": "Salaried middle class",
        "body": "Civil servants, teachers, professionals and office employees with regular salaries.",
        "growth_exposure": 0.50, "income_indexation": 0.65,
        "job_sensitivity": 0.75, "price_sensitivity": 0.95,
        "service_dependence": 0.65, "welfare_dependence": 0.10,
    },
    {
        "id": "small_business", "name": "Small business and traders",
        "body": "Shopkeepers, carriers, workshops and independent traders exposed to demand and credit.",
        "growth_exposure": 1.10, "income_indexation": 0.45,
        "job_sensitivity": 0.85, "price_sensitivity": 0.90,
        "service_dependence": 0.40, "welfare_dependence": 0.05,
    },
    {
        "id": "rural_households", "name": "Rural households",
        "body": "Farm families and village workers dependent on land, transport and local markets.",
        "growth_exposure": 0.60, "income_indexation": 0.40,
        "job_sensitivity": 0.95, "price_sensitivity": 1.05,
        "service_dependence": 0.80, "welfare_dependence": 0.18,
    },
    {
        "id": "pensioners", "name": "Pensioners",
        "body": "Older households living on public pensions, family support and accessible clinics.",
        "growth_exposure": 0.05, "income_indexation": 0.30,
        "job_sensitivity": 0.0, "price_sensitivity": 1.15,
        "service_dependence": 1.00, "welfare_dependence": 0.90,
    },
    {
        "id": "insecure_households", "name": "Economically insecure households",
        "body": "The unemployed, displaced, informally employed and families without reliable income.",
        "growth_exposure": 0.20, "income_indexation": 0.20,
        "job_sensitivity": 1.45, "price_sensitivity": 1.15,
        "service_dependence": 0.95, "welfare_dependence": 1.00,
    },
]

GROUP_BY_ID = {group["id"]: group for group in HOUSEHOLD_GROUPS}


REGIONAL_HOUSEHOLD_SHARES = {
    "vashtera": {
        "urban_workers": 0.25, "salaried_middle": 0.28, "small_business": 0.16,
        "rural_households": 0.05, "pensioners": 0.14, "insecure_households": 0.12,
    },
    "zavost": {
        "urban_workers": 0.32, "salaried_middle": 0.10, "small_business": 0.08,
        "rural_households": 0.12, "pensioners": 0.16, "insecure_households": 0.22,
    },
    "sela": {
        "urban_workers": 0.10, "salaried_middle": 0.08, "small_business": 0.10,
        "rural_households": 0.42, "pensioners": 0.16, "insecure_households": 0.14,
    },
    "anera": {
        "urban_workers": 0.07, "salaried_middle": 0.06, "small_business": 0.08,
        "rural_households": 0.48, "pensioners": 0.16, "insecure_households": 0.15,
    },
    "kelvet": {
        "urban_workers": 0.18, "salaried_middle": 0.18, "small_business": 0.24,
        "rural_households": 0.08, "pensioners": 0.14, "insecure_households": 0.18,
    },
    "vetrenka": {
        "urban_workers": 0.10, "salaried_middle": 0.05, "small_business": 0.08,
        "rural_households": 0.28, "pensioners": 0.18, "insecure_households": 0.31,
    },
}

