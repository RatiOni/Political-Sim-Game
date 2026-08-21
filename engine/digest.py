"""
The monthly digest: a prose account of what moved this month and why, ONE
causal link back -- not a list of deltas. This is a LENS, exactly like
ui/explain.py, applied on the engine side because it needs to run inside the
monthly pulse (see snapshot()) and both front-ends read the same module.

No new simulation lives here. Every number this module reports is read
straight off GameState or one of the shared engine functions the turn loop
itself calls (engine/stability.py, engine/households.py, engine/regions.py,
engine/ministries.py). Where a genuinely private, inlined expression has to
be reconstructed (the sub-terms of the approval target, the pressure-target
weights, the household hardship-target weights), the constants are copied
here verbatim with a comment naming the real function they mirror -- same
discipline ui/explain.py already uses for its own approval weights. If those
formulas change, these comments are the trail back to what else to update.

monthly_digest() never mutates state and never touches turn_log/turn_news:
say() would push this into the press front page, which is the world talking
about itself. This is the government's own bookkeeping, so every line is
rendered through flavor.render() (log-and-forget), not flavor.say().
"""

from content.regions import ARDENIA_REGION_PROFILES
from content.households import GROUP_BY_ID
from engine import flavor, households, regions, stability
from engine.regions import (PRESSURE_JOBS_WEIGHT as _PRESSURE_JOBS_WEIGHT,
                           PRESSURE_CAPACITY_WEIGHT as _PRESSURE_CAPACITY_WEIGHT)

# -- Materiality thresholds ------------------------------------------------
# A movement smaller than its threshold is not news -- it is not reported at
# all, at any rank. Chosen so ordinary month-to-month drift stays silent and
# a figure has to have genuinely moved to earn a line.
APPROVAL_THRESHOLD = 0.01          # 1 point
STABILITY_THRESHOLD = 0.01         # 1 point
MINISTRY_DELIVERY_THRESHOLD = 0.05
MINISTRY_BACKLOG_THRESHOLD = 0.5
REGION_PRESSURE_THRESHOLD = 0.05
HOUSEHOLD_HARDSHIP_THRESHOLD = 0.05
BUDGET_SHARE_THRESHOLD = 0.02      # 2 points of revenue

MAX_DIGEST_LINES = 5

# -- Mirrored constants -----------------------------------------------------
# engine/turn.py: _update_approval builds its target from three weighted
# signals. Mirrored here (annotated) so the digest can say WHICH of the
# three actually moved the target this month, without engine/turn.py having
# to expose that breakdown itself.
_APPROVAL_ECON_WEIGHT = 0.25
_APPROVAL_FACTION_WEIGHT = 0.15
_APPROVAL_HOUSEHOLD_WEIGHT = 0.12

# engine/stability.py: compute_economic_signal's own internal weights,
# needed to say whether growth, unemployment or inflation drove a change in
# "economic conditions" specifically (ui/explain.py already mirrors these
# same three numbers for the same reason).
_ECON_GROWTH_COEF = 4.0
_ECON_UNEMPLOYMENT_COEF = -0.5
_ECON_INFLATION_COEF = -0.3

# engine/households.py: _hardship_target's own weights for the income/job/
# service stress terms (job_sensitivity/service_dependence scale the last
# two per group, exactly as that function does). Not currently needed beyond
# documentation of the real formula this module's household causes draw on.
_HARDSHIP_INCOME_WEIGHT = 0.35
_HARDSHIP_JOB_BASE = 0.22
_HARDSHIP_JOB_SENSITIVITY_SCALE = 0.025
_HARDSHIP_SERVICE_BASE = 0.18
_HARDSHIP_SERVICE_DEPENDENCE_SCALE = 0.08

# ui/theme.py: PRESSURE_STEPS' four named bands. Mirrored (not imported --
# engine/ may not depend on ui/) purely so a region-pressure digest line can
# name the same word the map legend would show for that value. If the ramp's
# ceilings change, update both.
_PRESSURE_BANDS = ((0.30, "Calm"), (0.50, "Uneasy"), (0.70, "Strained"), (1.01, "Critical"))

# Budget balance read as a share of revenue -- bands shared with
# ui/widgets_common.py's named-band display so the digest and the Policies
# page can never disagree about what "a deficit" means.
BUDGET_BALANCE_BANDS = (
    (-0.15, "Deep deficit"), (-0.05, "Deficit"), (0.0, "Balanced"),
    (0.05, "Surplus"), (999.0, "Strong surplus"),
)

# Household hardship bands, in worsening order -- mirrors
# models/household.py: HouseholdGroupState.status_label() so a crossing can
# be named directly by index rather than re-deriving the thresholds.
_HARDSHIP_BAND_ORDER = ["Secure", "Insecure", "Under strain", "Severe hardship"]


def _clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def _plural(n: int, noun: str) -> str:
    return f"{n} {noun}" if n == 1 else f"{n} {noun}s"


def _band_word(value, bands):
    for ceiling, label in bands:
        if value < ceiling:
            return label
    return bands[-1][1]


def _faction_signal(state) -> float:
    """Power-weighted average faction loyalty. Mirrors the identical inline
    computation in engine/turn.py: _update_approval (and ui/explain.py:
    approval_breakdown, which mirrors the same thing for the same reason --
    there is no shared function to call instead)."""
    total_power = sum(f.power for f in state.country.factions)
    if total_power <= 0:
        return 0.0
    return sum(f.loyalty * f.power for f in state.country.factions) / total_power


def _household_mood(state) -> float:
    """Mirrors engine/turn.py: _update_approval's household_mood term,
    including the in-opposition sign flip."""
    mood = (households.national_confidence(state) - 0.5) * 2.0
    if not state.player.in_government:
        mood *= -1.0
    return mood


def snapshot(state) -> dict:
    """Capture the headline values needed to describe a month's change.

    Plain, JSON-safe data only (floats, ints, strings, and dicts/lists of
    those) -- this is exactly what GameState.last_snapshot persists. Every
    value here is either read directly off the live state or produced by an
    engine function the turn loop itself already calls; nothing is invented
    for this snapshot alone.
    """
    econ = state.country.economy
    stab_breakdown = dict(state.stability.breakdown)
    if not stab_breakdown:
        # Not yet populated this campaign (first turn). Ask the engine for
        # it the same way ui/explain.py: stability_breakdown does.
        _target, stab_breakdown = stability.compute_target_stability(state)
        stab_breakdown = dict(stab_breakdown)

    out = {
        "turn": state.turn,
        "month": state.month,
        "year": state.year,
        "in_government": bool(state.player.in_government),
        "approval": state.player.approval,
        "stability": state.stability.value,
        "stability_breakdown": stab_breakdown,
        "econ_signal": stability.compute_economic_signal(econ),
        "faction_signal": _faction_signal(state),
        "household_mood": _household_mood(state),
        "growth": econ.growth_rate,
        "unemployment": econ.unemployment,
        "inflation": econ.inflation,
        "debt": econ.public_debt_pct,
        "revenue": econ.budget.revenue,
        "balance": econ.budget.balance,
        "regional_pressure": regions.national_pressure(state),
        "avg_state_reach": regions.average_state_reach(state),
        "national_hardship": households.national_hardship(state),
        "national_confidence": households.national_confidence(state),
        "national_real_income": households.national_real_income(state),
        "national_service_access": households.national_service_access(state),
        "ministries": {
            portfolio: {
                "delivery": m.delivery,
                "backlog": m.backlog,
                "load_ratio": m.load_ratio,
                "funding_ratio": m.funding_ratio,
                "months_overloaded": m.months_overloaded,
                "status": m.status_label(),
            }
            for portfolio, m in state.ministries.items()
        },
        "regions": {
            region_id: {
                "pressure": r.pressure,
                "state_reach": r.state_reach,
                "unemployment": r.unemployment,
            }
            for region_id, r in state.regions.items()
        },
        "households": {
            key: {
                "hardship": h.hardship,
                "confidence": h.confidence,
                "real_income": h.real_income_index,
                "service_access": h.service_access,
                "employment_security": h.employment_security,
                "status": h.status_label(),
                "population_share": h.population_share,
            }
            for key, h in state.households.items()
        },
    }
    return out


# -- Candidate line generators ----------------------------------------------
#
# Each returns a list of (materiality, key, fields) tuples. `materiality` is
# the movement expressed as a multiple of that metric's own threshold -- a
# score of 1.0 is exactly at the reporting floor, 3.0 is three times as
# material -- so scores from different categories can be ranked against each
# other on one list. `key`/`fields` name a content/dispatches.py TEMPLATES
# pool and the values to render it with.

def _dominant_agreeing(delta: float, terms: list):
    """Pick the largest-magnitude term, but ONLY from those whose own delta
    points the same way as the metric actually moved.

    Approval and stability are lerped 5-6% per month toward a target built
    from these terms, so a term's month-over-month delta can point one way
    while the lerped value still moves the other way, catching up to an
    older target that a different, unchanged term dominated. Picking the
    largest delta without this filter can name a cause that contradicts the
    direction just reported ("approval fell... sentiment warmed"). Falls
    back to the largest-magnitude term if nothing agrees (rare — the metric
    is reversing direction this exact month).
    """
    agreeing = [t for t in terms if t[1] * delta > 0]
    pool = agreeing if agreeing else terms
    return max(pool, key=lambda t: abs(t[1]))[0]


def _approval_candidates(before, after):
    delta = after["approval"] - before["approval"]
    if abs(delta) < APPROVAL_THRESHOLD:
        return []

    d_econ = (after["econ_signal"] - before["econ_signal"]) * _APPROVAL_ECON_WEIGHT
    d_faction = (after["faction_signal"] - before["faction_signal"]) * _APPROVAL_FACTION_WEIGHT
    d_house = (after["household_mood"] - before["household_mood"]) * _APPROVAL_HOUSEHOLD_WEIGHT
    dominant = _dominant_agreeing(
        delta, [("economy", d_econ), ("faction", d_faction), ("household", d_house)])

    cause = None
    if dominant == "economy":
        cause = _economic_cause(before, after)
    elif dominant == "household":
        cause = _household_cause(before, after)
    if cause is None:
        cause = ("coalition sentiment has cooled toward the government" if d_faction < 0
                 else "coalition sentiment has warmed toward the government")

    key = "digest_approval_up" if delta > 0 else "digest_approval_down"
    fields = {"points": f"{abs(delta) * 100:.1f}", "cause": cause}
    return [(abs(delta) / APPROVAL_THRESHOLD, key, fields)]


def _economic_cause(before, after) -> str:
    """Which of growth/unemployment/inflation moved the economic signal."""
    d_growth = ((after["growth"] - before["growth"]) * _ECON_GROWTH_COEF
                * _APPROVAL_ECON_WEIGHT)
    d_unemp = ((after["unemployment"] - before["unemployment"]) * _ECON_UNEMPLOYMENT_COEF
               * _APPROVAL_ECON_WEIGHT)
    d_infl = ((after["inflation"] - before["inflation"]) * _ECON_INFLATION_COEF
              * _APPROVAL_ECON_WEIGHT)
    label, _value = max(
        (("growth, now running at {:+.1f}%".format(after["growth"] * 100), d_growth),
         ("unemployment, now at {:.1f}%".format(after["unemployment"] * 100), d_unemp),
         ("inflation, now at {:.1f}%".format(after["inflation"] * 100), d_infl)),
        key=lambda item: abs(item[1]))
    return f"the economy: {label}"


def _public_administration_ministries(before, after):
    """Interior (60%) and Finance (40%) are what turns an appropriation into
    an actual public service -- engine/households.py:
    _public_administration_delivery. Returns the one whose delivery fell
    furthest, if either did."""
    candidates = []
    for portfolio, weight in (("Interior", 0.60), ("Finance", 0.40)):
        b = before.get("ministries", {}).get(portfolio)
        a = after.get("ministries", {}).get(portfolio)
        if b is None or a is None:
            continue
        drop = b["delivery"] - a["delivery"]
        candidates.append((drop * weight, portfolio, a))
    if not candidates:
        return None
    drop, portfolio, ministry_after = max(candidates, key=lambda c: c[0])
    if drop <= 0.01:
        return None
    return portfolio, ministry_after


def _household_cause(before, after) -> str:
    """Name the household-service story: a concurrent Interior/Finance
    delivery drop if there is one, else the strongest hardship driver among
    the households that actually moved."""
    admin = _public_administration_ministries(before, after)
    worst_group, worst_delta, worst_region = _worst_household_move(before, after)
    if admin is not None:
        portfolio, ministry_after = admin
        clause = (f"{portfolio}'s delivery is down to {ministry_after['delivery']:.2f} "
                  f"after {_plural(ministry_after['months_overloaded'], 'month')} over capacity")
        if worst_group is not None:
            clause += f"; service access dropped in {worst_region}"
        return clause
    if worst_group is not None:
        return (f"service and hardship conditions worsened in {worst_region}, "
                f"hardest on {worst_group}")
    return "household confidence shifted nationally"


def _region_display_name(region_id: str) -> str:
    profile = ARDENIA_REGION_PROFILES.get(region_id)
    return profile["name"] if profile else region_id.title()


def _worst_household_move(before, after):
    """(group display name, hardship delta, region display name) for the
    household record whose hardship moved most, or (None, None, None)."""
    worst = None
    for key, a in after.get("households", {}).items():
        b = before.get("households", {}).get(key)
        if b is None:
            continue
        delta = a["hardship"] - b["hardship"]
        if worst is None or abs(delta) > abs(worst[1]):
            worst = (key, delta)
    if worst is None:
        return None, None, None
    key, delta = worst
    region_id, group_id = key.split(":", 1) if ":" in key else (None, key)
    group_name = GROUP_BY_ID.get(group_id, {}).get("name", group_id)
    region_name = _region_display_name(region_id) if region_id else ""
    return group_name, delta, region_name


def _stability_candidates(before, after):
    delta = after["stability"] - before["stability"]
    if abs(delta) < STABILITY_THRESHOLD:
        return []
    before_bd = before.get("stability_breakdown", {})
    after_bd = after.get("stability_breakdown", {})
    components = set(before_bd) | set(after_bd)
    if components:
        terms = [(c, after_bd.get(c, 0.0) - before_bd.get(c, 0.0)) for c in components]
        component = _dominant_agreeing(delta, terms)
        component_delta = dict(terms)[component]
        cause = _stability_component_cause(component, component_delta, before, after)
    else:
        cause = "the balance of coalition, cabinet and economy"
    key = "digest_stability_up" if delta > 0 else "digest_stability_down"
    fields = {"points": f"{abs(delta) * 100:.1f}", "cause": cause}
    return [(abs(delta) / STABILITY_THRESHOLD, key, fields)]


def _stability_component_cause(component: str, component_delta: float, before, after) -> str:
    if component == "Unrest":
        # "Unrest" is stored as a NEGATIVE contribution (-unrest*0.15), so a
        # component_delta > 0 means unrest fell (stability-positive) and
        # < 0 means it rose — this decides which wording, not just which
        # driver, so a rising-stability month can never read as a warning.
        d_house = (after["national_hardship"] - before["national_hardship"]) * 0.35
        d_region = (after["regional_pressure"] - before["regional_pressure"]) * 0.50
        driver = "regional pressure" if abs(d_region) >= abs(d_house) else "household hardship"
        return f"easing {driver}" if component_delta > 0 else f"worsening {driver}"
    if component == "Coalition cohesion":
        return "a coalition growing less united"
    if component == "Coalition loyalty":
        return "the coalition's own mood toward the government"
    if component == "Cabinet loyalty":
        return "the cabinet's loyalty to the government"
    if component == "Cabinet dysfunction":
        return "friction inside the cabinet"
    if component == "Parliamentary margin":
        return "the government's margin in the chamber"
    if component == "Economic conditions":
        return _economic_cause(before, after)
    if component == "Public approval":
        return "the public mood feeding back into it"
    return component.lower()


def _ministry_candidates(before, after):
    out = []
    for portfolio, a in after.get("ministries", {}).items():
        b = before.get("ministries", {}).get(portfolio)
        if b is None:
            continue
        d_delivery = a["delivery"] - b["delivery"]
        d_backlog = a["backlog"] - b["backlog"]
        band_changed = a["status"] != b["status"]
        score = abs(d_delivery) / MINISTRY_DELIVERY_THRESHOLD
        score = max(score, abs(d_backlog) / MINISTRY_BACKLOG_THRESHOLD)
        if band_changed:
            score = max(score, 1.0)
        if score < 1.0:
            continue
        key = "digest_ministry_down" if d_delivery < 0 else "digest_ministry_up"
        if d_delivery < 0 and a["months_overloaded"] > 0:
            cause = f"running at {a['load_ratio']:.2f} of capacity"
        elif d_delivery < 0:
            cause = f"backlog rising to {a['backlog']:.1f}"
        elif b["months_overloaded"] > 0 and a["months_overloaded"] == 0:
            cause = "capacity has caught back up with its workload"
        else:
            cause = f"funding restored to {a['funding_ratio'] * 100:.0f}% of baseline"
        fields = {"portfolio": portfolio, "delivery": f"{a['delivery']:.2f}",
                  "band": a["status"].lower(), "cause": cause}
        out.append((score, key, fields))
    out.sort(key=lambda c: -c[0])
    return out[:2]


def _region_candidates(before, after):
    out = []
    for region_id, a in after.get("regions", {}).items():
        b = before.get("regions", {}).get(region_id)
        if b is None:
            continue
        d_pressure = a["pressure"] - b["pressure"]
        band_before = _band_word(b["pressure"], _PRESSURE_BANDS)
        band_after = _band_word(a["pressure"], _PRESSURE_BANDS)
        score = abs(d_pressure) / REGION_PRESSURE_THRESHOLD
        if band_before != band_after:
            score = max(score, 1.0)
        if score < 1.0:
            continue

        d_jobs = (_clamp((a["unemployment"] - 0.055) / 0.23)
                  - _clamp((b["unemployment"] - 0.055) / 0.23))
        d_capacity = -(a["state_reach"] - b["state_reach"])
        if abs(d_jobs * _PRESSURE_JOBS_WEIGHT) >= abs(d_capacity * _PRESSURE_CAPACITY_WEIGHT):
            cause = f"local unemployment is {a['unemployment'] * 100:.1f}%"
        else:
            cause = f"state presence there has fallen to {a['state_reach'] * 100:.0f}%"

        overloaded = [portfolio for portfolio, m in after.get("ministries", {}).items()
                     if m["months_overloaded"] >= 2]
        if overloaded:
            worst_portfolio = overloaded[0]
            months = after["ministries"][worst_portfolio]["months_overloaded"]
            cause += f", and {worst_portfolio} has been over capacity for {_plural(months, 'month')} running"

        key = "digest_region_up" if d_pressure > 0 else "digest_region_down"
        fields = {"region": _region_display_name(region_id),
                  "value": f"{a['pressure']:.2f}", "band": band_after, "cause": cause}
        out.append((score, key, fields))
    out.sort(key=lambda c: -c[0])
    return out[:2]


def _household_candidates(before, after):
    """Named band crossings only -- the household groups whose status word
    actually changed this month, grouped when the same crossing happened in
    more than one region at once."""
    crossings = {}
    for key, a in after.get("households", {}).items():
        b = before.get("households", {}).get(key)
        if b is None or a["status"] == b["status"]:
            continue
        region_id, group_id = key.split(":", 1) if ":" in key else (None, key)
        group_name = GROUP_BY_ID.get(group_id, {}).get("name", group_id)
        region_name = _region_display_name(region_id) if region_id else ""
        if a["status"] in _HARDSHIP_BAND_ORDER and b["status"] in _HARDSHIP_BAND_ORDER:
            worsened = _HARDSHIP_BAND_ORDER.index(a["status"]) > _HARDSHIP_BAND_ORDER.index(b["status"])
        else:
            worsened = True
        crossings.setdefault((group_name, b["status"], a["status"]), []).append(
            (region_name, abs(a["hardship"] - b["hardship"]), worsened))

    out = []
    for (group_name, before_status, after_status), regions_hit in crossings.items():
        magnitude = max(abs_delta for _r, abs_delta, _w in regions_hit)
        score = magnitude / HOUSEHOLD_HARDSHIP_THRESHOLD
        if score < 1.0:
            continue
        region_names = sorted({r for r, _d, _w in regions_hit if r})
        where = region_names[0] if len(region_names) == 1 else " and ".join(region_names[:2])
        worsened = regions_hit[0][2]
        key = "digest_household_worse" if worsened else "digest_household_better"
        fields = {"group": group_name.lower(), "region": where,
                  "before": before_status, "after": after_status}
        out.append((score, key, fields))
    out.sort(key=lambda c: -c[0])
    return out[:2]


def _budget_candidates(before, after):
    b_revenue = before.get("revenue", 0.0) or 1.0
    a_revenue = after.get("revenue", 0.0) or 1.0
    share_before = before.get("balance", 0.0) / b_revenue
    share_after = after.get("balance", 0.0) / a_revenue
    delta = share_after - share_before
    if abs(delta) < BUDGET_SHARE_THRESHOLD:
        return []
    band = _band_word(share_after, BUDGET_BALANCE_BANDS)
    d_revenue = after["revenue"] - before["revenue"]
    a_expenditure = after["revenue"] - after["balance"]
    b_expenditure = before["revenue"] - before["balance"]
    d_expenditure = a_expenditure - b_expenditure
    if abs(d_revenue) >= abs(d_expenditure):
        cause = f"revenue moved to {after['revenue']:,.0f} M"
    else:
        cause = f"expenditure moved to {a_expenditure:,.0f} M"
    key = "digest_budget_worse" if delta < 0 else "digest_budget_better"
    fields = {"balance": f"{after['balance']:+,.0f}", "band": band.lower(), "cause": cause}
    return [(abs(delta) / BUDGET_SHARE_THRESHOLD, key, fields)]


def monthly_digest(state, before: dict, after: dict) -> list[str]:
    """The prose account of what moved this month and why.

    `before`/`after` are two snapshot() dicts. Returns at most
    MAX_DIGEST_LINES lines, ranked by how far each movement was past its own
    materiality threshold; nothing below that threshold is ever included, so
    a quiet month returns []. Never mutates state, never logs -- the caller
    decides where the text goes.
    """
    if not before:
        return []

    candidates = []
    candidates += _approval_candidates(before, after)
    candidates += _stability_candidates(before, after)
    candidates += _ministry_candidates(before, after)
    candidates += _region_candidates(before, after)
    candidates += _household_candidates(before, after)
    candidates += _budget_candidates(before, after)

    candidates.sort(key=lambda c: -c[0])
    lines = []
    for _score, key, fields in candidates[:MAX_DIGEST_LINES]:
        lines.append(flavor.render(state, key, **fields))
    return lines
