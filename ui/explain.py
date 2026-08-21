"""
Explainability — read-only breakdowns of the headline metrics.

Priority 5 asks that every important number expose *why* it is what it
is. This module produces those breakdowns. It is strictly read-only:
every function takes a GameState and returns plain data (lists of
(label, contribution) pairs, or small dicts) without mutating anything.

Where the engine already stores a breakdown (government stability keeps
one on state.stability.breakdown, recomputed each turn), we surface that
directly. Where it doesn't (approval), we RECONSTRUCT the breakdown using
the exact same shared signal functions the engine's own update uses —
stability.compute_economic_signal, the same faction-sentiment sum, the
same approval_bias modifier total — so the explanation can never drift
from the real formula. The one duplicated thing is the weighting
constants (0.25 / 0.15), which we mirror from engine/turn.py
_update_approval; they're annotated on both sides so a future change
stays in sync.

Nothing here is a new mechanic. It's a lens on the mechanics that exist.
"""

from engine import stability


# Approval weighting — mirrors engine/turn.py _update_approval. If those
# constants change, change them here too (both are annotated).
_APPROVAL_ECON_WEIGHT = 0.25
_APPROVAL_FACTION_WEIGHT = 0.15


def _modifiers_total(state, target: str) -> float:
    """Read-only sum of active modifier contributions to a target — mirrors
    TurnEngine._modifiers_sum but without needing an engine instance. Used
    for the approval_bias term and the economic-effects breakdowns."""
    total = 0.0
    for m in state.modifiers:
        if m.target != target:
            continue
        value = m.current_value()
        if m.institutional:
            # Institutional modifiers are scaled by implementation quality.
            # We approximate that here with the minister/vacancy factor only;
            # the exact engine value also folds in stability, but for an
            # explanatory breakdown the direction and rough size are what
            # matter, and we clearly label these as contributions.
            minister = state.cabinet.get(m.portfolio) if m.portfolio else None
            if m.portfolio and minister is None:
                value *= 0.35
        total += value
    return total


def approval_breakdown(state):
    """
    Returns a list of (label, signed_contribution_to_target) pairs
    explaining the approval TARGET the game is lerping toward. The target,
    not the current value, is what the breakdown explains — that's the
    quantity the formula actually computes.
    """
    econ = state.country.economy
    econ_signal = stability.compute_economic_signal(econ)

    total_power = sum(f.power for f in state.country.factions)
    if total_power > 0:
        faction_signal = sum(f.loyalty * f.power for f in state.country.factions) / total_power
    else:
        faction_signal = 0.0

    approval_bias = _modifiers_total(state, "approval_bias")

    rows = [
        ("Baseline", 0.5),
        ("Economic conditions", econ_signal * _APPROVAL_ECON_WEIGHT),
        ("Faction sentiment", faction_signal * _APPROVAL_FACTION_WEIGHT),
    ]
    # Break the economic signal down further so "economic conditions" isn't
    # a black box — these sub-terms mirror compute_economic_signal.
    sub = [
        ("  · growth", (econ.growth_rate - 0.02) * 4.0 * _APPROVAL_ECON_WEIGHT),
        ("  · unemployment", -econ.unemployment * 0.5 * _APPROVAL_ECON_WEIGHT),
        ("  · inflation", -econ.inflation * 0.3 * _APPROVAL_ECON_WEIGHT),
    ]
    if abs(approval_bias) > 1e-9:
        rows.append(("Active policy effects", approval_bias))

    target = max(0.05, min(0.95, 0.5 + econ_signal * _APPROVAL_ECON_WEIGHT
                            + faction_signal * _APPROVAL_FACTION_WEIGHT + approval_bias))
    return {
        "current": state.player.approval,
        "target": target,
        "rows": rows,
        "sub_economic": sub,
    }


def stability_breakdown(state):
    """
    Government stability already keeps its own per-component breakdown,
    recomputed every turn (engine/stability.py: compute_target_stability
    stores it on state.stability.breakdown). We surface it directly —
    positive contributions are strengths, negative are drains.
    """
    bd = dict(state.stability.breakdown)
    if not bd:
        # Not yet populated (the engine fills it during the first turn's
        # stability phase). Ask the engine for it rather than showing an
        # empty dialog — same function the turn loop calls.
        _target, bd = stability.compute_target_stability(state)
        bd = dict(bd)
    target = sum(bd.values())
    return {
        "current": state.stability.value,
        "target": max(0.05, min(0.95, target)),
        "trend": state.stability.trend,
        "rows": list(bd.items()),
    }


def economic_effects(state):
    """
    Which active long-term modifiers are pushing each economic headline,
    for the 'why did inflation rise' style dispatch. Groups active
    modifiers by their target, returning label + current contribution.
    """
    targets = ["gdp_growth", "unemployment", "inflation",
               "budget_revenue", "budget_expenditure"]
    result = {}
    for t in targets:
        contributors = []
        for m in state.modifiers:
            if m.target != t:
                continue
            val = m.current_value()
            if abs(val) < 1e-9:
                continue
            contributors.append((m.source, val))
        if contributors:
            result[t] = contributors
    return result


def political_capital_breakdown(state):
    """Where next month's political capital comes from. Reuses the engine's
    own upkeep function; the regen weights mirror engine/turn.py
    _regenerate_political_capital (annotated on both sides)."""
    from engine.turn import political_upkeep, PC_REGEN_FLOOR

    p = state.player
    approval_bonus = (p.approval - 0.5) * 10.0        # mirrors _regenerate_political_capital
    coalition_ids = state.coalition_faction_ids()
    members = [f for f in state.country.factions if f.id in coalition_ids]
    coalition_loyalty = (sum(f.loyalty for f in members) / len(members)) if members else 0.0
    coalition_bonus = coalition_loyalty * 5.0
    stability_bonus = (state.stability.value - 0.5) * 4.0
    upkeep, detail = political_upkeep(state)

    rows = [
        ("Base regeneration", p.pc_regen_base),
        ("Public approval", approval_bonus),
        ("Coalition loyalty", coalition_bonus),
        ("Government stability", stability_bonus),
    ]
    for label, cost in (("Governing overhead: laws", detail["laws"]),
                        ("Governing overhead: treaties", detail["treaties"]),
                        ("Governing overhead: sanctions", detail["sanctions"])):
        if cost:
            rows.append((label, -cost))

    raw = p.pc_regen_base + approval_bonus + coalition_bonus + stability_bonus - upkeep
    net = max(PC_REGEN_FLOOR, raw)
    if net > raw:
        rows.append((f"Floor (never below {PC_REGEN_FLOOR:.0f})", net - raw))
    return {
        "current": p.political_capital / 100.0,
        "target": min(1.0, (p.political_capital + net) / 100.0),
        "rows": rows,
        "value_fmt": lambda v: f"{v*100:.0f} / 100",
        "row_fmt": lambda v: f"{v:+.1f} PC",
        "footer": f"Net change next month: {net:+.1f} PC.",
    }


def _economic_breakdown(state, target, base_label, base_value, fmt_pct=True):
    """Structural baseline + every long-term modifier currently pushing an
    economic headline. Contributions come from the live modifiers, never a
    reimplementation of the engine's arithmetic."""
    rows = [(base_label, base_value)]
    for source, val in economic_effects(state).get(target, []):
        rows.append((source, val))
    fmt = (lambda v: f"{v*100:+.2f}%") if fmt_pct else (lambda v: f"{v:+,.0f} M")
    return rows, fmt


def growth_breakdown(state):
    econ = state.country.economy
    rows, fmt = _economic_breakdown(state, "gdp_growth",
                                    "Structural growth rate", econ.structural_growth_rate)
    return {"current": max(0.0, min(1.0, (econ.growth_rate + 0.05) / 0.13)),
            "target": None, "rows": rows,
            "value_fmt": lambda v: f"{econ.growth_rate*100:+.2f}%",
            "row_fmt": fmt,
            "footer": "The headline rate drifts toward its structural baseline "
                      "each month, with active effects layered on top."}


def unemployment_breakdown(state):
    econ = state.country.economy
    rows, fmt = _economic_breakdown(state, "unemployment",
                                    "Structural unemployment", econ.structural_unemployment)
    return {"current": max(0.0, min(1.0, econ.unemployment / 0.30)),
            "target": None, "rows": rows,
            "value_fmt": lambda v: f"{econ.unemployment*100:.1f}%",
            "row_fmt": fmt,
            "footer": "Drifts toward the structural rate; policy effects move it faster."}


def inflation_breakdown(state):
    econ = state.country.economy
    rows, fmt = _economic_breakdown(state, "inflation",
                                    "Structural inflation", econ.structural_inflation)
    return {"current": max(0.0, min(1.0, econ.inflation / 0.15)),
            "target": None, "rows": rows,
            "value_fmt": lambda v: f"{econ.inflation*100:.2f}%",
            "row_fmt": fmt,
            "footer": "Deficits and overheating growth push the structural rate up; "
                      "an anchor pulls it back toward ~2%."}


def _capacity_breakdown(state, target, base_const, current, label):
    rows = [(f"{label} baseline", base_const)]
    for source, val in economic_effects(state).get(target, []):
        rows.append((source, val))
    for m in state.modifiers:
        if m.target == target and abs(m.current_value()) > 1e-9 and \
                not any(src == m.source for src, _ in rows[1:]):
            rows.append((m.source, m.current_value()))
    return {"current": current, "target": None, "rows": rows,
            "value_fmt": lambda v: f"{v:.2f}",
            "row_fmt": lambda v: f"{v:+.3f}",
            "footer": "Baseline plus every long-term effect currently in motion."}


def workforce_breakdown(state):
    from engine.turn import BASE_WORKFORCE_QUALITY
    return _capacity_breakdown(state, "workforce_quality", BASE_WORKFORCE_QUALITY,
                               state.country.economy.workforce_quality, "Workforce")


def bureaucracy_breakdown(state):
    from engine.turn import BASE_BUREAUCRATIC_CAPACITY
    return _capacity_breakdown(state, "bureaucratic_capacity", BASE_BUREAUCRATIC_CAPACITY,
                               state.country.bureaucratic_capacity, "Bureaucratic")


def debt_breakdown(state):
    """What the debt is actually made of: outstanding loans by lender, with
    the remainder as inherited/accumulated public debt."""
    econ = state.country.economy
    rows = []
    loan_total = 0.0
    for loan in econ.loans:
        share = loan.principal / max(1.0, econ.gdp)
        lender = state.world_country(loan.lender_id)
        rows.append((f"Loan from {lender.name if lender else loan.lender_id}", share))
        loan_total += share
    remainder = econ.public_debt_pct - loan_total
    rows.insert(0, ("Accumulated public debt", remainder))
    return {"current": max(0.0, min(1.0, econ.public_debt_pct / 1.5)),
            "target": None, "rows": rows,
            "value_fmt": lambda v: f"{econ.public_debt_pct*100:.0f}% of GDP",
            "row_fmt": lambda v: f"{v*100:+.1f}%",
            "footer": (f"Annual debt service: {econ.total_debt_service():,.0f} M."
                       if econ.loans else "No active foreign loans.")}


# ── Item-scoped breakdowns ───────────────────────────────────────────────
#
# The nine above explain a single headline number. These five explain one
# NAMED thing — a ministry, a household group, a region, the budget, a law —
# so they take an id alongside state and return their own richer shape
# rather than the generic rows/current/target contract MetricBreakdownDialog
# expects. Same rule as everywhere else in this module: read the engine's
# own stored numbers where they exist, and where a value is only ever
# computed inline (a region's pressure-target terms, a household's hardship-
# target terms), reconstruct it with the exact same weights the engine uses,
# annotated back to the real function.

def ministry_breakdown(state, portfolio):
    """Funding, workload by source, capacity, load, backlog and the
    resulting delivery for one cabinet department — everything
    MinistryState/engine/ministries.py already tracks, read straight off."""
    ministry = state.ministries.get(portfolio)
    if ministry is None:
        return None
    return {
        "portfolio": portfolio,
        "funding": ministry.funding,
        "baseline_funding": ministry.baseline_funding,
        "funding_ratio": ministry.funding_ratio,
        "workload": ministry.workload,
        "workload_breakdown": dict(ministry.workload_breakdown),
        "capacity": ministry.capacity,
        "load_ratio": ministry.load_ratio,
        "backlog": ministry.backlog,
        "months_overloaded": ministry.months_overloaded,
        "delivery": ministry.delivery,
        "status": ministry.status_label(),
    }


def household_breakdown(state, group_id, region_id):
    """One social group's lived economic condition in one region — the
    exact fields HouseholdGroupState carries, plus the real-income change
    the model itself tracks (last_real_income_index)."""
    from content.households import GROUP_BY_ID
    from content.regions import ARDENIA_REGION_PROFILES
    # Mirrors engine/households.py: _key — a plain f-string, not a formula,
    # so reconstructing it here carries no drift risk.
    key = f"{region_id}:{group_id}"
    household = state.households.get(key)
    if household is None:
        return None
    group = GROUP_BY_ID.get(group_id, {})
    region_profile = ARDENIA_REGION_PROFILES.get(region_id, {})
    return {
        "group_id": group_id,
        "region_id": region_id,
        "group_name": group.get("name", group_id),
        "region_name": region_profile.get("name", region_id),
        "nominal_income_index": household.nominal_income_index,
        "living_cost_index": household.living_cost_index,
        "real_income_index": household.real_income_index,
        "real_income_change": household.real_income_index - household.last_real_income_index,
        "employment_security": household.employment_security,
        "service_access": household.service_access,
        "hardship": household.hardship,
        "status": household.status_label(),
        "confidence": household.confidence,
        "population_share": household.population_share,
    }


def region_breakdown(state, region_id):
    """What is driving one region's pressure, state reach and unemployment.

    Pressure's contributing terms mirror engine/regions.py: simulate_regions
    exactly — PRESSURE_JOBS_WEIGHT/PRESSURE_CAPACITY_WEIGHT/
    PRESSURE_NATIONAL_WEIGHT are real named constants imported from there
    (promoted out of that function's body for this purpose), not a copied
    number; only the jobs/capacity STRESS terms themselves are recomputed
    here, using the same clamp/threshold engine/regions.py applies.
    """
    from engine import regions as region_engine
    from content.regions import ARDENIA_REGION_PROFILES
    region = state.regions.get(region_id)
    if region is None:
        return None
    profile = ARDENIA_REGION_PROFILES.get(region_id, {})

    jobs_stress = max(0.0, min(1.0, (region.unemployment - 0.055) / 0.23))
    capacity_stress = 1.0 - region.state_reach
    national_stress = max(0.0, min(1.0, (0.58 - state.stability.value) / 0.43))
    pressure_bias = profile.get("pressure_bias", 0.0)

    return {
        "region_id": region_id,
        "region_name": profile.get("name", region_id),
        "control": region.control,
        "pressure": region.pressure,
        "state_reach": region.state_reach,
        "unemployment": region.unemployment,
        "pressure_rows": [
            ("Local unemployment", jobs_stress * region_engine.PRESSURE_JOBS_WEIGHT),
            ("Weak state presence", capacity_stress * region_engine.PRESSURE_CAPACITY_WEIGHT),
            ("National mood", national_stress * region_engine.PRESSURE_NATIONAL_WEIGHT),
            ("Authored/status factors", pressure_bias),
        ],
        "unemployment_gap": profile.get("unemployment_gap", 0.0),
        "reach_offset": profile.get("reach_offset", 0.0),
    }


def budget_breakdown(state):
    """Each envelope, its share of the current plan, how it changed against
    the previous year, and the funding_ratio it produces for whichever
    ministry it feeds — engine/ministries.py: portfolio_funding is the same
    function operating_capacity uses, so this can never disagree with a
    ministry's own reported funding_ratio."""
    from content.budget import BUDGET_ENVELOPES
    active = state.active_budget
    if active is None:
        return None
    previous = state.budget_history[-2] if len(state.budget_history) >= 2 else None
    rows = []
    for item in BUDGET_ENVELOPES:
        envelope_id = item["id"]
        amount = active.allocations.get(envelope_id, 0.0)
        prior_amount = previous.allocations.get(envelope_id) if previous else None
        rows.append({
            "id": envelope_id,
            "name": item["name"],
            "portfolio": item.get("portfolio"),
            "amount": amount,
            "change_from_prior": (amount - prior_amount) if prior_amount is not None else None,
        })
    funding_ratios = {
        portfolio: ministry.funding_ratio
        for portfolio, ministry in state.ministries.items()
    }
    # active.expenditure is the voted appropriation total; the live economy's
    # own Budget (state.country.economy.budget) is where actual revenue and
    # balance are tracked month to month, since laws/loans/crises move
    # spending outside the appropriation envelopes without amending the plan.
    live = state.country.economy.budget
    return {
        "year": active.year,
        "appropriated": active.expenditure,
        "revenue": live.revenue,
        "expenditure": live.expenditure,
        "balance": live.balance,
        "rows": rows,
        "funding_ratios": funding_ratios,
    }


def delivery_chain(state, law_id):
    """For one active law: its authored effect, the responsible ministry's
    delivery, the realised strength of each modifier it installed, and the
    regional state-reach context that delivery depends on.

    "Per-region compliance" has no separate mechanic in this codebase — a
    law's effects are not tracked per region. What IS real and regional is
    state_reach, the capacity the law's home ministry has to actually work
    in each area (engine/regions.py), so that is what is returned under
    per_region: honest context for how unevenly this law's delivery reaches
    the country, not a fabricated compliance percentage.

    The realised fraction is computed by calling the turn engine's own
    dampening function, engine.turn.TurnEngine._implementation_quality_for
    — not a reimplementation of it — so this can never drift from what the
    modifier actually contributes this month.
    """
    from engine.turn import TurnEngine
    law = next((l for l in state.legislature.active_laws if l.id == law_id), None)
    if law is None:
        return None
    ministry = state.ministries.get(law.portfolio) if law.portfolio else None
    quality = TurnEngine()._implementation_quality_for(state, law.portfolio)

    effects = law.effects
    authored = []
    for label, value in (
        ("GDP growth", effects.gdp_growth_delta),
        ("Unemployment", effects.unemployment_delta),
        ("Inflation", effects.inflation_delta),
        ("Budget revenue", effects.budget_revenue_delta),
        ("Budget expenditure", effects.budget_expenditure_delta),
    ):
        if value:
            authored.append((label, value))

    modifiers = []
    for m in state.modifiers:
        if m.source_id != law_id:
            continue
        raw = m.current_value()
        realised = raw * quality if m.institutional else raw
        modifiers.append({
            "target": m.target,
            "raw": raw,
            "realised": realised,
            "phase": m.phase_label(),
        })

    per_region = {
        region_id: region.state_reach
        for region_id, region in state.regions.items()
    } if law.portfolio else {}

    return {
        "law_id": law_id,
        "law_name": law.name,
        "portfolio": law.portfolio,
        "authored_effects": authored,
        "ministry_delivery": ministry.delivery if ministry else None,
        "ministry_status": ministry.status_label() if ministry else None,
        "implementation_quality": quality,
        "modifiers": modifiers,
        "per_region": per_region,
    }


# Which metrics can explain themselves. Both the left panel (which decides
# where to show the ⓘ affordance) and MetricBreakdownDialog read this, so a
# clickable bar can never open an empty dialog. The five item-scoped
# breakdowns above are registered the same way — has_breakdown/breakdown_for
# is the one lookup surface for both kinds; callers of the item-scoped ones
# pass the extra id(s) as keyword arguments.
BREAKDOWNS = {
    "Approval": approval_breakdown,
    "Stability": stability_breakdown,
    "Pol. Capital": political_capital_breakdown,
    "Growth": growth_breakdown,
    "Unemployment": unemployment_breakdown,
    "Inflation": inflation_breakdown,
    "Debt / GDP": debt_breakdown,
    "Workforce Q.": workforce_breakdown,
    "Bureaucracy": bureaucracy_breakdown,
    "Ministry": ministry_breakdown,
    "Household": household_breakdown,
    "Region": region_breakdown,
    "Budget": budget_breakdown,
    "Law": delivery_chain,
}


def has_breakdown(metric_name: str) -> bool:
    return metric_name in BREAKDOWNS


def breakdown_for(metric_name: str, state, **kwargs):
    fn = BREAKDOWNS.get(metric_name)
    return fn(state, **kwargs) if fn else None


# ── Standing alerts ─────────────────────────────────────────────────────────
#
# The situations a government should be told about without having to go
# looking. One computation, two call sites: the always-visible strip in
# ui/app.py and the BriefingPage's CRISES / RECOMMENDATIONS sections.

SEV_CRITICAL = "critical"
SEV_WARNING = "warning"
SEV_ADVICE = "advice"

_SEV_ORDER = {SEV_CRITICAL: 0, SEV_WARNING: 1, SEV_ADVICE: 2}


def crises(state):
    """[(severity, text)] — what is going wrong, worst first."""
    s = state
    out = []
    if s.civil_war:
        out.append((SEV_CRITICAL,
                    "⚠ CIVIL WAR is underway — the state is fracturing and bleeding "
                    "each month. Pull risk back down to end it."))
    elif s.civil_war_risk > 0.6:
        out.append((SEV_CRITICAL,
                    f"⚠ Civil-war risk is CRITICAL ({s.civil_war_risk*100:.0f}%) — the "
                    f"country is close to coming apart."))
    elif s.civil_war_risk > 0.4:
        out.append((SEV_WARNING,
                    f"Civil-war risk is elevated ({s.civil_war_risk*100:.0f}%)."))

    if s.stability.value < 0.30:
        out.append((SEV_CRITICAL,
                    "Government stability is critically low — confidence-vote risk."))

    unrest = stability.compute_unrest(s)
    if unrest > 0.5:
        out.append((SEV_WARNING, f"High civil unrest ({unrest:.2f}) — protests are likely."))
    if s.country.economy.budget.balance < -2000:
        out.append((SEV_WARNING, "Large budget deficit is straining public finances."))
    if s.country.economy.public_debt_pct > 1.0:
        out.append((SEV_WARNING, "Public debt has exceeded annual GDP."))
    if s.country.economy.inflation > 0.08:
        out.append((SEV_WARNING, "Inflation is running high."))
    for f in s.country.factions:
        if f.grievance_pressure() > 0.6:
            out.append((SEV_WARNING, f"{f.name} is deeply aggrieved and agitating."))
    for m in s.cabinet.ministers:
        if m.threat_level() > 0.5:
            out.append((SEV_WARNING,
                        f"{m.name} ({m.portfolio}) is a threat to the government."))
    out.extend(_ministry_overload_warnings(s))
    return out


def _ministry_overload_warnings(state):
    """Telegraph chronic overload BEFORE delivery collapses, not after.

    MinistryState.status_label() only turns "Overloaded"/"Failing" once
    delivery and backlog have already degraded, which can take several
    months of engine/ministries.py: simulate_ministries' recurrence to show
    up — by which point the player had no warning it was coming. This reads
    the same load_ratio/months_overloaded the engine already tracks and
    says so from the very first month capacity falls short, escalating in
    both wording and severity as months_overloaded climbs. It changes no
    threshold or formula ministries.py itself uses — the degradation curve
    is exactly what it already was; this only makes it visible sooner.
    """
    out = []
    for portfolio, ministry in state.ministries.items():
        load = ministry.load_ratio
        months = ministry.months_overloaded
        if load <= 1.0 or months < 1:
            continue
        if months >= 4:
            out.append((SEV_CRITICAL,
                f"{portfolio} has been over capacity for {months} months running, at "
                f"{load:.2f} of capacity. Delivery has been degrading throughout and "
                f"will not recover until funding or workload changes."))
        elif months == 2:
            out.append((SEV_WARNING,
                f"{portfolio} is running at {load:.2f} of capacity. A third month at "
                f"this level will start costing delivery on every programme it carries."))
        elif months == 3:
            out.append((SEV_WARNING,
                f"{portfolio} is running at {load:.2f} of capacity for a third straight "
                f"month — delivery is now sliding."))
        else:  # months == 1: the first month over capacity, said plainly.
            out.append((SEV_WARNING,
                f"{portfolio} is running at {load:.2f} of capacity, its first month over "
                f"capacity. Sustained strain will start costing delivery."))
    return out


def recommendations(state):
    """[(severity, text)] — what to consider doing about it."""
    from models.cabinet import CORE_PORTFOLIOS
    s = state
    out = []
    if not s.player.in_government:
        return [(SEV_ADVICE,
                 "Campaign to rebuild support and reclaim office at the next election.")]
    if s.player.political_capital > 60:
        out.append((SEV_ADVICE,
                    "You have ample political capital — consider advancing legislation."))
    for f in s.country.factions:
        if f.in_coalition and f.loyalty < 0.2:
            out.append((SEV_WARNING, f"Shore up {f.name}: a wavering coalition partner."))
    for p in CORE_PORTFOLIOS:
        if s.cabinet.get(p) is None:
            out.append((SEV_WARNING,
                        f"Fill the vacant {p} portfolio to restore implementation."))
            break
    overloaded = [ministry for ministry in s.ministries.values()
                  if ministry.status_label() in ("Overloaded", "Failing")]
    if overloaded:
        worst = max(overloaded, key=lambda ministry: ministry.backlog)
        out.append((SEV_WARNING,
                    f"{worst.portfolio} is {worst.status_label().lower()}: reduce its workload, "
                    "fund it, or appoint stronger leadership."))
    if s.stability.value < 0.4:
        out.append((SEV_ADVICE,
                    "Stability is fragile — address grievances or court factions."))
    return out


def alerts(state):
    """Everything worth flagging, most severe first — the strip's data."""
    combined = crises(state) + recommendations(state)
    return sorted(combined, key=lambda item: _SEV_ORDER.get(item[0], 3))


def implementation_note(state, portfolio):
    """A short human-readable note on how well a portfolio is currently
    implementing policy — for the cabinet page's 'effectiveness' column."""
    if portfolio is None:
        return "Applies government-wide"
    minister = state.cabinet.get(portfolio)
    if minister is None:
        return "VACANT — reforms underperform badly"
    q = minister.implementation_quality()
    if q > 0.7:  return "Implementing reforms effectively"
    if q > 0.5:  return "Adequate implementation"
    if q > 0.35: return "Struggling to implement"
    return "Barely functional"
