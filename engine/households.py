"""Regional household incomes, costs, security, services and hardship."""

from content.households import GROUP_BY_ID, REGIONAL_HOUSEHOLD_SHARES
from content.budget import ENVELOPE_BY_ID
from content.regions import ARDENIA_REGION_PROFILES
from models.household import HouseholdGroupState


def _clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def _key(region_id: str, group_id: str) -> str:
    return f"{region_id}:{group_id}"


def _envelope_ratio(state, envelope_id: str) -> float:
    if state.active_budget is None:
        return 1.0
    expected = state.active_budget.expenditure * ENVELOPE_BY_ID[envelope_id]["share"]
    actual = state.active_budget.allocations.get(envelope_id, expected)
    return _clamp(actual / max(1.0, expected), 0.50, 1.50)


def _public_administration_delivery(state) -> float:
    """Finance can release and account for funds; Interior supplies the
    territorial machinery that gets ordinary services to people. Ardenia has
    no separate health or education portfolio yet, so both must work for an
    appropriation to become provision."""
    finance = state.ministries.get("Finance")
    interior = state.ministries.get("Interior")
    finance_delivery = finance.delivery if finance is not None else 0.75
    interior_delivery = interior.delivery if interior is not None else 0.75
    return finance_delivery * 0.40 + interior_delivery * 0.60


def welfare_delivery(state) -> float:
    return _clamp(_envelope_ratio(state, "health_and_welfare")
                  * _public_administration_delivery(state),
                  0.25, 1.25)


def education_delivery(state) -> float:
    return _clamp(_envelope_ratio(state, "education")
                  * _public_administration_delivery(state),
                  0.25, 1.25)


def initial_households(state) -> dict[str, HouseholdGroupState]:
    if state.country.id != "ardenia" or not state.regions:
        return {}
    out = {}
    for region_id, shares in REGIONAL_HOUSEHOLD_SHARES.items():
        region = state.regions.get(region_id)
        if region is None:
            continue
        for group_id, share in shares.items():
            definition = GROUP_BY_ID[group_id]
            if group_id == "pensioners":
                security = 0.55
            else:
                security = _clamp(1.0 - region.unemployment
                                  * definition["job_sensitivity"] * 2.0)
            access = _initial_service_access(region, definition)
            hardship = _hardship_target(
                region, 1.0, security, access, definition)
            out[_key(region_id, group_id)] = HouseholdGroupState(
                id=_key(region_id, group_id), group_id=group_id,
                region_id=region_id, population_share=share,
                employment_security=security, service_access=access,
                hardship=hardship, confidence=_clamp(0.66 - hardship * 0.55),
            )
    return out


def ensure_households(state):
    """Add any missing canonical household records without resetting history.

    Older campaigns may contain a complete household layer for the original
    six regions.  A truthiness-only migration would leave the three new
    regions socially empty forever, while rebuilding the whole mapping would
    erase accumulated income and hardship.  Merge only absent records.
    """
    canonical = initial_households(state)
    if not state.households:
        state.households = canonical
    else:
        for household_id, household in canonical.items():
            state.households.setdefault(household_id, household)
    return state.households


def _initial_service_access(region, definition) -> float:
    access = region.state_reach * 0.65 + 0.25
    if definition["id"] == "rural_households":
        access -= 0.10
    if definition["id"] in ("pensioners", "insecure_households"):
        access -= 0.04
    if region.control == "separatist":
        access = min(access, 0.15)
    return _clamp(access, 0.05, 0.95)


def _hardship_target(region, real_income, employment_security, service_access,
                     definition) -> float:
    income_stress = _clamp((1.0 - real_income) / 0.35)
    job_stress = 1.0 - employment_security
    service_stress = 1.0 - service_access
    return _clamp(
        income_stress * 0.35
        + job_stress * (0.22 + definition["job_sensitivity"] * 0.025)
        + service_stress * (0.18 + definition["service_dependence"] * 0.08)
        + region.pressure * 0.15
    )


def _agriculture_growth(state) -> float:
    sector = next((sector for sector in state.country.economy.sectors
                   if sector.id == "agriculture"), None)
    return sector.growth_rate if sector is not None else state.country.economy.growth_rate


def simulate_households(state):
    if not ensure_households(state):
        return
    econ = state.country.economy
    welfare = welfare_delivery(state)
    education = education_delivery(state)
    agriculture_growth = _agriculture_growth(state)

    for household in state.households.values():
        definition = GROUP_BY_ID[household.group_id]
        region = state.regions.get(household.region_id)
        if region is None:
            continue

        household.last_real_income_index = household.real_income_index
        cost_rate = econ.inflation * definition["price_sensitivity"]
        household.living_cost_index *= 1.0 + cost_rate / 12.0

        growth = (agriculture_growth if household.group_id == "rural_households"
                  else econ.growth_rate)
        indexation = definition["income_indexation"]
        if household.group_id in ("pensioners", "insecure_households"):
            indexation += definition["welfare_dependence"] * welfare * 0.38
        nominal_rate = (econ.inflation * indexation
                        + growth * definition["growth_exposure"])
        excess_unemployment = max(0.0, region.unemployment - 0.08)
        nominal_rate -= excess_unemployment * definition["job_sensitivity"] * 0.12
        household.nominal_income_index *= 1.0 + nominal_rate / 12.0
        household.nominal_income_index = _clamp(
            household.nominal_income_index, 0.45, 2.50)
        household.living_cost_index = _clamp(household.living_cost_index, 0.65, 3.50)
        household.real_income_index = _clamp(
            household.nominal_income_index / household.living_cost_index, 0.35, 2.00)

        if household.group_id == "pensioners":
            employment_target = 0.42 + welfare * 0.38
        else:
            employment_target = 1.0 - (region.unemployment
                                       * definition["job_sensitivity"] * 2.0)
        household.employment_security += (
            _clamp(employment_target) - household.employment_security) * 0.18
        household.employment_security = _clamp(household.employment_security)

        # Weighted mean of welfare/education delivery, weights summing to 1
        # so a group facing perfectly-delivered welfare AND education always
        # reads public_delivery == 1.0, whatever its service_dependence.
        # (The old divisor used a different, unrelated normalizer and
        # silently capped the achievable maximum below 1.0 for every group
        # but pensioners.)
        _sd = definition["service_dependence"]
        _welfare_weight = _sd
        _education_weight = 1.0 - _sd * 0.45
        public_delivery = (welfare * _welfare_weight + education * _education_weight)
        public_delivery /= max(0.01, _welfare_weight + _education_weight)
        service_target = region.state_reach * 0.58 + public_delivery * 0.42
        if household.group_id == "rural_households":
            service_target -= 0.10
        if region.control == "separatist":
            service_target = min(service_target, 0.15)
        household.service_access += (
            _clamp(service_target, 0.03, 0.98) - household.service_access) * 0.12

        hardship_target = _hardship_target(
            region, household.real_income_index, household.employment_security,
            household.service_access, definition)
        household.hardship += (hardship_target - household.hardship) * 0.15
        household.hardship = _clamp(household.hardship)

        real_change = household.real_income_index - household.last_real_income_index
        confidence_target = _clamp(
            0.62 - household.hardship * 0.62
            + econ.growth_rate * 1.2
            + (state.stability.value - 0.5) * 0.16
            + real_change * 3.0)
        household.confidence += (confidence_target - household.confidence) * 0.12
        household.confidence = _clamp(household.confidence)


def _weighted(state, attr: str, region_id: str | None = None) -> float:
    households = ensure_households(state)
    total = 0.0
    weight_total = 0.0
    for household in households.values():
        if region_id is not None and household.region_id != region_id:
            continue
        region_weight = ARDENIA_REGION_PROFILES.get(
            household.region_id, {}).get("population_weight", 0.0)
        weight = region_weight * household.population_share
        total += getattr(household, attr) * weight
        weight_total += weight
    return total / weight_total if weight_total else 0.0


def national_hardship(state) -> float:
    return _weighted(state, "hardship")


def national_confidence(state) -> float:
    return _weighted(state, "confidence") if ensure_households(state) else 0.5


def national_real_income(state) -> float:
    return _weighted(state, "real_income_index") if ensure_households(state) else 1.0


def national_living_cost(state) -> float:
    return _weighted(state, "living_cost_index") if ensure_households(state) else 1.0


def national_service_access(state) -> float:
    return _weighted(state, "service_access")


def regional_hardship(state, region_id: str) -> float:
    return _weighted(state, "hardship", region_id)


def regional_confidence(state, region_id: str) -> float:
    return _weighted(state, "confidence", region_id)


def regional_service_access(state, region_id: str) -> float:
    return _weighted(state, "service_access", region_id)


def hardest_hit(state, limit=5):
    return sorted(ensure_households(state).values(),
                  key=lambda household: household.hardship, reverse=True)[:limit]
