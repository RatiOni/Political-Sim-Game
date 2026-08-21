"""Deterministic monthly regional simulation for the playable country."""

from content.regions import (ARDENIA_NATIONAL_SUPPORT_BASELINE,
                             ARDENIA_REGION_PROFILES, REGIONAL_PROGRAMS)
from models.region import RegionState, RegionalProgram


def _clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


# simulate_regions' pressure-target weights, named so a read-only explainer
# (ui/explain.py, engine/digest.py) can cite the real formula instead of
# mirroring these numbers a second time.
PRESSURE_JOBS_WEIGHT = 0.40
PRESSURE_CAPACITY_WEIGHT = 0.30
PRESSURE_NATIONAL_WEIGHT = 0.16


def initial_region_states(country_id: str, national_support=None) -> dict:
    """Return fresh live region state for a country that has authored data."""
    if country_id != "ardenia":
        return {}
    anchor = dict(national_support or ARDENIA_NATIONAL_SUPPORT_BASELINE)
    return {
        region_id: RegionState(
            id=region_id,
            unemployment=profile["initial_unemployment"],
            state_reach=profile["initial_state_reach"],
            pressure=profile["initial_pressure"],
            control=profile["control"],
            issue_id=profile["issue_id"],
            party_support=dict(profile["party_support"]),
            support_anchor=dict(anchor),
        )
        for region_id, profile in ARDENIA_REGION_PROFILES.items()
    }


def _normalise_support(support: dict, faction_ids=None) -> dict:
    ids = list(faction_ids or support.keys())
    clean = {faction_id: max(0.0, support.get(faction_id, 0.0))
             for faction_id in ids}
    total = sum(clean.values())
    if total <= 0.0 and ids:
        return {faction_id: 1.0 / len(ids) for faction_id in ids}
    return {faction_id: value / total for faction_id, value in clean.items()}


def ensure_electoral_support(state) -> None:
    """Fill regional voting data added after older campaigns were saved."""
    if not state.regions:
        return
    faction_ids = [faction.id for faction in state.country.factions]
    national = _normalise_support(
        {faction.id: faction.support for faction in state.country.factions}, faction_ids)
    for region_id, region in state.regions.items():
        profile = ARDENIA_REGION_PROFILES.get(region_id)
        if profile is None:
            continue
        if not region.party_support:
            region.party_support = dict(profile["party_support"])
        region.party_support = _normalise_support(region.party_support, faction_ids)
        if not region.support_anchor:
            region.support_anchor = dict(national)
        else:
            region.support_anchor = _normalise_support(region.support_anchor, faction_ids)


def projected_party_support(state, region_id: str) -> dict:
    """Local shares after unsynchronised national polling changes are applied."""
    ensure_electoral_support(state)
    region = state.regions.get(region_id)
    if region is None:
        return {}
    faction_ids = [faction.id for faction in state.country.factions]
    national = _normalise_support(
        {faction.id: faction.support for faction in state.country.factions}, faction_ids)
    adjusted = {}
    for faction_id in faction_ids:
        anchor = max(0.001, region.support_anchor.get(faction_id, national[faction_id]))
        ratio = _clamp(national[faction_id] / anchor, 0.10, 10.0)
        adjusted[faction_id] = region.party_support.get(faction_id, 0.0) * ratio
    return _normalise_support(adjusted, faction_ids)


def _shift_party_support(region, deltas: dict, scale=1.0) -> None:
    shifted = dict(region.party_support)
    for faction_id, delta in deltas.items():
        if faction_id in shifted:
            shifted[faction_id] = max(0.001, shifted[faction_id] + delta * scale)
    region.party_support = _normalise_support(shifted)


def update_party_support(state) -> None:
    """Reconcile national polling, then apply persistent local judgement."""
    if not state.regions:
        return
    ensure_electoral_support(state)
    national = _normalise_support(
        {faction.id: faction.support for faction in state.country.factions})
    ruling_id = state.ruling_faction_id
    national_unemployment = state.country.economy.unemployment
    from engine import households
    for region_id, region in state.regions.items():
        region.party_support = projected_party_support(state, region_id)
        region.support_anchor = dict(national)
        if ruling_id not in region.party_support:
            continue
        # Regions judge the sitting government by the local experience, not
        # merely the national headline. The small monthly shift accumulates
        # into genuine electoral geography across a term.
        local_delta = (
            (0.50 - region.pressure) * 0.012
            + (national_unemployment - region.unemployment) * 0.030
            + (region.state_reach - 0.50) * 0.003
            + (households.regional_confidence(state, region_id) - 0.5) * 0.008
        )
        local_delta = _clamp(local_delta, -0.008, 0.008)
        _shift_party_support(region, {ruling_id: local_delta})


def electoral_access(state, region_id: str) -> float:
    """Share of the potential regional electorate able to cast a ballot."""
    region = state.regions.get(region_id)
    if region is None:
        return 0.0
    if region.control == "separatist":
        return 0.0
    control_base = {"state": 1.0, "limited": 0.72, "autonomous": 0.62}.get(
        region.control, 0.75)
    if region_id == "vetrenka" and state.campaign_meta.get("vetrenka_status") == "retaken":
        control_base = min(control_base, 0.55)
    administrative_access = 0.72 + region.state_reach * 0.28
    return _clamp(control_base * administrative_access)


def leading_party(state, region_id: str):
    support = projected_party_support(state, region_id)
    if not support:
        return None, 0.0
    faction_id, share = max(support.items(), key=lambda item: item[1])
    faction = next((item for item in state.country.factions if item.id == faction_id), None)
    return faction, share


def population_weight(region_id: str) -> float:
    profile = ARDENIA_REGION_PROFILES.get(region_id)
    return profile["population_weight"] if profile else 0.0


def region_name(region_id: str) -> str:
    profile = ARDENIA_REGION_PROFILES.get(region_id)
    return profile["name"] if profile else region_id.replace("_", " ").title()


def campaign_in_region(state, region_id: str, faction_id: str, amount: float):
    """Shift one regional electorate and return the rival displaced by it."""
    ensure_electoral_support(state)
    region = state.regions.get(region_id)
    own = next((faction for faction in state.country.factions
                if faction.id == faction_id), None)
    if region is None or own is None:
        return None

    region.party_support = projected_party_support(state, region_id)
    rivals = [(other_id, share) for other_id, share in region.party_support.items()
              if other_id != faction_id]
    rival_id = max(rivals, key=lambda item: item[1])[0] if rivals else None
    deltas = {faction_id: amount}
    if rival_id is not None:
        deltas[rival_id] = -amount
    _shift_party_support(region, deltas)

    # A regional tour has a small national polling echo proportional to the
    # electorate actually reached; the local movement remains much larger.
    national_delta = amount * population_weight(region_id) * electoral_access(state, region_id)
    own.support = max(0.001, own.support + national_delta)
    rival = next((faction for faction in state.country.factions
                  if faction.id == rival_id), None)
    if rival is not None:
        rival.support = max(0.001, rival.support - national_delta)
    national = _normalise_support(
        {faction.id: faction.support for faction in state.country.factions})
    for faction in state.country.factions:
        faction.support = national[faction.id]
    # Do not apply the national echo to the target twice when it is next read.
    region.support_anchor = dict(national)
    return rival


def national_pressure(state) -> float:
    """Population-weighted regional pressure, or zero without regional data."""
    if not state.regions:
        return 0.0
    weighted = 0.0
    total = 0.0
    for region_id, region in state.regions.items():
        profile = ARDENIA_REGION_PROFILES.get(region_id)
        if profile is None:
            continue
        weight = profile["population_weight"]
        weighted += region.pressure * weight
        total += weight
    return weighted / total if total else 0.0


def average_state_reach(state) -> float:
    """Population-weighted reach of the playable state's institutions."""
    if not state.regions:
        return 0.0
    weighted = 0.0
    total = 0.0
    for region_id, region in state.regions.items():
        profile = ARDENIA_REGION_PROFILES.get(region_id)
        if profile is None:
            continue
        weight = profile["population_weight"]
        weighted += region.state_reach * weight
        total += weight
    return weighted / total if total else 0.0


def active_program_for(state, region_id: str):
    return next((program for program in state.regional_programs
                 if program.region_id == region_id), None)


def available_programs(state, region_id: str) -> list:
    """Authored programme definitions the state can physically run here."""
    region = state.regions.get(region_id)
    if region is None:
        return []
    out = []
    for program_id, definition in REGIONAL_PROGRAMS.items():
        allowed = definition.get("allowed_regions")
        if allowed is not None and region_id not in allowed:
            continue
        if region.control in definition.get("blocked_controls", []):
            continue
        out.append((program_id, definition))
    return out


def can_start_program(state, region_id: str, program_id: str):
    if not state.player.in_government:
        return False, "Regional programmes belong to the sitting government."
    region = state.regions.get(region_id)
    if region is None:
        return False, "No regional administration exists for that area."
    definition = REGIONAL_PROGRAMS.get(program_id)
    if definition is None:
        return False, "No such regional programme."
    if active_program_for(state, region_id) is not None:
        return False, "That region already has an active government programme."
    allowed = definition.get("allowed_regions")
    if allowed is not None and region_id not in allowed:
        return False, "That programme is not designed for this region."
    if region.control in definition.get("blocked_controls", []):
        return False, "The state cannot deliver this programme across the current control line."
    return True, ""


def start_program(state, region_id: str, program_id: str) -> RegionalProgram:
    definition = REGIONAL_PROGRAMS[program_id]
    program = RegionalProgram(
        id=f"{program_id}:{region_id}:{state.turn}",
        program_id=program_id,
        region_id=region_id,
        started_turn=state.turn,
        duration=definition["duration"],
        monthly_cost=definition["monthly_cost"],
    )
    state.regional_programs.append(program)
    launch_pressure = definition.get("launch_pressure", 0.0)
    if launch_pressure:
        region = state.regions[region_id]
        region.pressure = _clamp(region.pressure + launch_pressure)
    return program


def monthly_program_cost(state) -> float:
    return sum(program.monthly_cost for program in state.regional_programs)


def program_delivery_quality(state, program) -> float:
    """Cabinet and state capacity determine how much of a budget reaches dirt."""
    from engine import ministries
    definition = REGIONAL_PROGRAMS[program.program_id]
    minister = state.cabinet.get(definition["portfolio"])
    minister_delivery = 0.35 if minister is None else minister.implementation_quality()
    institutional = minister_delivery * 0.65 + state.country.bureaucratic_capacity * 0.35
    departmental = ministries.policy_delivery_factor(state, definition["portfolio"])
    return _clamp((0.45 + institutional * 0.55) * departmental, 0.30, 1.0)


def _advance_programs(state) -> None:
    if not state.regional_programs:
        return
    still_active = []
    for program in state.regional_programs:
        definition = REGIONAL_PROGRAMS.get(program.program_id)
        region = state.regions.get(program.region_id)
        if definition is None or region is None:
            continue

        # The fiscal baseline is reconstructed earlier in the monthly pulse;
        # programme commitments are then layered onto this month's headline
        # expenditure. Organic inflation reads that deficit next month.
        state.country.economy.budget.expenditure += program.monthly_cost

        quality = program_delivery_quality(state, program)
        regional_fit = definition.get("region_multipliers", {}).get(program.region_id, 1.0)
        scale = quality * regional_fit / max(1, program.duration)
        effects = definition["effects"]
        region.unemployment = _clamp(
            region.unemployment + effects.get("unemployment", 0.0) * scale,
            0.0, 0.60)
        region.state_reach = _clamp(
            region.state_reach + effects.get("state_reach", 0.0) * scale)
        region.pressure = _clamp(
            region.pressure + effects.get("pressure", 0.0) * scale)
        _shift_party_support(
            region, definition.get("regional_support_deltas", {}), scale)

        program.months_active += 1
        if program.months_active >= program.duration:
            region_name = ARDENIA_REGION_PROFILES[program.region_id]["name"]
            state.log(f"REGIONAL PROGRAMME — {definition['name']} concludes in "
                      f"{region_name}. Its gains now have to survive ordinary government.")
        else:
            still_active.append(program)
    state.regional_programs = still_active


def simulate_regions(state) -> None:
    """Move local labour, state reach and political pressure one month.

    National performance reaches every area, but authored structural gaps make
    Zavost remain more exposed than Vashtera and Anera harder to administer
    than Sela. Control is deliberately not changed by this passive pulse: a
    ceasefire line or a crisis of sovereignty should move through explicit
    political mechanics, not because a decimal happened to cross a threshold.
    """
    if not state.regions:
        return

    national_unemployment = state.country.economy.unemployment
    national_stress = _clamp((0.58 - state.stability.value) / 0.43)
    capacity = state.country.bureaucratic_capacity

    for region_id, region in state.regions.items():
        profile = ARDENIA_REGION_PROFILES.get(region_id)
        if profile is None:
            continue

        unemployment_target = _clamp(
            national_unemployment + profile["unemployment_gap"], 0.025, 0.45)
        region.unemployment += (unemployment_target - region.unemployment) * 0.14
        region.unemployment = _clamp(region.unemployment, 0.0, 0.60)

        reach_target = capacity + profile["reach_offset"] + (state.stability.value - 0.5) * 0.12
        if region.control == "limited":
            reach_target = min(reach_target, 0.48)
        elif region.control == "autonomous":
            reach_target = max(reach_target, 0.24 + capacity * 0.12)
            reach_target = min(reach_target, 0.42)
        elif region_id == "vetrenka" and region.control == "state":
            # Retaking territory puts the army ahead of civilian capacity.
            # Administration can grow, but does not become Vashtera overnight.
            reach_target = max(reach_target, 0.22 + capacity * 0.32)
            reach_target = min(reach_target, 0.58)
        elif region.control == "separatist":
            reach_target = min(reach_target, 0.08)
        reach_target = _clamp(reach_target, 0.02, 0.97)
        region.state_reach += (reach_target - region.state_reach) * 0.05
        region.state_reach = _clamp(region.state_reach)

        jobs_stress = _clamp((region.unemployment - 0.055) / 0.23)
        capacity_stress = 1.0 - region.state_reach
        pressure_bias = profile["pressure_bias"]
        if region_id == "vetrenka":
            pressure_bias = {
                "settled": 0.07,
                "retaken": 0.17,
                "routed": 0.25,
                "partitioned": 0.11,
                "partitioned_contested": 0.20,
                "talks_failed": 0.23,
            }.get(state.campaign_meta.get("vetrenka_status"), pressure_bias)
        pressure_target = _clamp(
            jobs_stress * PRESSURE_JOBS_WEIGHT
            + capacity_stress * PRESSURE_CAPACITY_WEIGHT
            + national_stress * PRESSURE_NATIONAL_WEIGHT
            + pressure_bias
        )
        region.pressure += (pressure_target - region.pressure) * 0.12
        region.pressure = _clamp(region.pressure)

    _advance_programs(state)
