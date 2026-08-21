"""Diagnosis and state transitions for the reform-design process."""

from content.reforms import REFORM_OBJECTIVES, OBJECTIVE_BY_ID, SIGNAL_LABELS
from engine import households, ministries, regions
from models.reform import ReformProject


def _clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def _weighted_household(state, attr: str, group_id: str | None = None) -> float:
    households.ensure_households(state)
    total = 0.0
    weights = 0.0
    from content.regions import ARDENIA_REGION_PROFILES
    for household in state.households.values():
        if group_id is not None and household.group_id != group_id:
            continue
        region_weight = ARDENIA_REGION_PROFILES.get(
            household.region_id, {}).get("population_weight", 0.0)
        weight = region_weight * household.population_share
        total += getattr(household, attr) * weight
        weights += weight
    return total / weights if weights else 0.0


def _ministry_average(state, attr: str, fallback=0.0) -> float:
    ministries.ensure_ministries(state)
    if not state.ministries:
        return fallback
    return sum(getattr(item, attr) for item in state.ministries.values()) / len(state.ministries)


def _regional_values(state, attr: str) -> list[float]:
    return [getattr(region, attr) for region in state.regions.values()]


def diagnostic_signals(state) -> dict[str, float]:
    """Return normalized 0..1 problem pressures from the current simulation."""
    econ = state.country.economy
    region_unemployment = _regional_values(state, "unemployment")
    region_reach = _regional_values(state, "state_reach")
    regional_services = [households.regional_service_access(state, region_id)
                         for region_id in state.regions]
    avg_delivery = _ministry_average(state, "delivery", 0.75)
    avg_backlog = _ministry_average(state, "backlog", 0.0)

    revenue = max(1.0, econ.budget.revenue)
    deficit_ratio = max(0.0, -econ.budget.balance) / revenue
    if state.households:
        real_income = households.national_real_income(state)
        employment_security = _weighted_household(state, "employment_security")
        household_hardship = households.national_hardship(state)
        service_access = households.national_service_access(state)
        rural_hardship = _weighted_household(state, "hardship", "rural_households")
    else:
        # Countries without an authored social distribution use restrained
        # national proxies. Zero would mean "total social collapse", not
        # "data unavailable", and would distort the country-neutral engine.
        real_income = 1.0
        employment_security = _clamp(1.0 - econ.unemployment * 1.8)
        household_hardship = _clamp(
            0.16 + max(0.0, econ.unemployment - 0.06) * 1.8
            + max(0.0, econ.inflation - 0.03) * 0.8)
        service_access = _clamp(0.35 + state.country.bureaucratic_capacity * 0.50)
        rural_hardship = household_hardship

    active_laws = len(state.legislature.active_laws)
    treaties = sum(len(relation.treaties)
                   for relation in state.country.relations.values())
    sanctions = sum(1 for relation in state.country.relations.values()
                    if relation.sanctioned)
    overhead = active_laws * 0.8 + treaties * 0.6 + sanctions

    return {
        "inflation_pressure": _clamp((econ.inflation - 0.02) / 0.16),
        "real_income_loss": _clamp((1.0 - real_income) / 0.20),
        "household_hardship": _clamp((household_hardship - 0.18) / 0.52),
        "unemployment_pressure": _clamp((econ.unemployment - 0.05) / 0.20),
        "employment_insecurity": _clamp((0.82 - employment_security) / 0.52),
        "regional_jobs_gap": _clamp(
            ((max(region_unemployment) - min(region_unemployment)) / 0.18)
            if region_unemployment else 0.0),
        "service_access_gap": _clamp((0.85 - service_access) / 0.65),
        "public_delivery_gap": _clamp((0.90 - min(
            households.welfare_delivery(state), households.education_delivery(state))) / 0.65),
        "regional_reach_gap": _clamp(
            ((0.80 - (sum(region_reach) / len(region_reach))) / 0.65)
            if region_reach else 0.0),
        "growth_gap": _clamp((0.04 - econ.growth_rate) / 0.12),
        "workforce_gap": _clamp((0.80 - econ.workforce_quality) / 0.65),
        "ministry_delivery_gap": _clamp((0.90 - avg_delivery) / 0.65),
        "deficit_pressure": _clamp(deficit_ratio / 0.40),
        "debt_pressure": _clamp((econ.public_debt_pct - 0.35) / 0.85),
        "governing_overhead": _clamp(overhead / 24.0),
        "bureaucratic_gap": _clamp((0.90 - state.country.bureaucratic_capacity) / 0.70),
        "ministry_backlog": _clamp(avg_backlog / 5.0),
        "regional_service_gap": _clamp(
            ((max(regional_services) - min(regional_services)) / 0.40)
            if regional_services else 0.0),
        "rural_hardship": _clamp((rural_hardship - 0.18) / 0.55),
        "regional_pressure": _clamp((regions.national_pressure(state) - 0.25) / 0.65),
    }


def diagnose_objective(state, objective_id: str) -> dict:
    definition = OBJECTIVE_BY_ID.get(objective_id)
    if definition is None:
        return {}
    signals = diagnostic_signals(state)
    components = {
        signal_id: signals.get(signal_id, 0.0)
        for signal_id, _weight in definition["signals"]
    }
    contributions = {
        signal_id: components[signal_id] * weight
        for signal_id, weight in definition["signals"]
    }
    return {
        "score": _clamp(sum(contributions.values())),
        "components": components,
        "contributions": contributions,
    }


def ranked_objectives(state) -> list[dict]:
    ranked = []
    for definition in REFORM_OBJECTIVES:
        diagnosis = diagnose_objective(state, definition["id"])
        ranked.append({**definition, **diagnosis})
    return sorted(ranked, key=lambda item: (-item["score"], item["id"]))


def urgency_label(score: float) -> str:
    if score >= 0.70:
        return "Critical"
    if score >= 0.50:
        return "Pressing"
    if score >= 0.30:
        return "Material"
    return "Long-term"


def leading_pressures(diagnosis: dict, limit=3) -> list[tuple[str, float]]:
    components = diagnosis.get("components", {})
    contributions = diagnosis.get("contributions", components)
    ordered_ids = sorted(
        components, key=lambda signal_id: (-contributions.get(signal_id, 0.0), signal_id))
    return [
        (SIGNAL_LABELS.get(signal_id, signal_id.replace("_", " ")),
         components[signal_id])
        for signal_id in ordered_ids[:limit]
    ]


def adopt_objective(state, objective_id: str) -> ReformProject | None:
    diagnosis = diagnose_objective(state, objective_id)
    if not diagnosis:
        return None
    project = ReformProject(
        id=f"reform:{objective_id}:{state.turn}",
        objective_id=objective_id,
        adopted_turn=state.turn,
        adopted_year=state.year,
        adopted_month=state.month,
        diagnosis_score=diagnosis["score"],
        diagnosis_snapshot=dict(diagnosis["components"]),
    )
    state.reform_project = project
    return project
