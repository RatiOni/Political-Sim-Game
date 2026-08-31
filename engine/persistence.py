"""
Save / load: GameState ↔ JSON, versioned (SAVE_VERSION) and tolerant —
fields absent from older saves fall back to model defaults. The mapping is
maintained BY HAND: a new field on GameState or a nested model must be added
to serialize_state/deserialize_state here or it silently won't round-trip.
Saves live in saves/; the GUI autosaves each turn to the "autosave" slot.
"""

import os
import json
import dataclasses

import app_paths

from game_state import GameState, Player
from models.country import Country
from models.economy import Economy, Sector, Budget, Loan
from models.faction import Faction, Ideology, Grievance, Demand
from models import roles
from models.wing import Wing
from models.cabinet import Cabinet, Minister
from models.legislature import Legislature, Law, LawEffect
from models.relations import BilateralRelation, Treaty
from models.modifiers import Modifier
from models.events import PendingEvent
from models.stability import GovernmentStability
from models.election import ElectionResult
from models.legacy import GovernmentLegacy
from models.region import RegionState, RegionalProgram
from models.budget import AnnualBudget
from models.ministry import MinistryState
from models.household import HouseholdGroupState
from models.reform import ReformProject
from content.lore import BLOCS as ARDENIAN_BLOCS, BLOC_PROFILES
from engine.regions import initial_region_states, ensure_electoral_support
from engine.budget import ensure_budget_state
from engine.ministries import ensure_ministries
from engine.households import ensure_households


SAVE_VERSION = 1

# The first party-current implementation used these broad labels in Ardenia.
# Recognising the exact old sets lets existing saves enter the canonical bloc
# model safely, without touching modded or otherwise unfamiliar party data.
_LEGACY_ARDENIA_WING_IDS = {
    "liberal_democrats": {"ld_reform", "ld_establishment", "ld_freemarket"},
    "national_conservatives": {"nc_moderates", "nc_traditionalists", "nc_hardliners"},
    "social_democrats": {"sd_thirdway", "sd_mainstream", "sd_left"},
    "agrarian_union": {"agrarian_union_moderate", "agrarian_union_mainstream", "agrarian_union_hardline"},
    "workers_front": {"workers_front_moderate", "workers_front_mainstream", "workers_front_hardline"},
}


# ── Serialisation ───────────────────────────────────────────────────────────

def _budget(b): return {"revenue": b.revenue, "expenditure": b.expenditure}

def _loan(l): return dataclasses.asdict(l)

def _sector(s): return dataclasses.asdict(s)

def _economy(e):
    return {
        "gdp": e.gdp, "growth_rate": e.growth_rate, "inflation": e.inflation,
        "unemployment": e.unemployment, "public_debt_pct": e.public_debt_pct,
        "budget": _budget(e.budget),
        "sectors": [_sector(s) for s in e.sectors],
        "structural_growth_rate": e.structural_growth_rate,
        "structural_unemployment": e.structural_unemployment,
        "structural_inflation": e.structural_inflation,
        "structural_revenue": e.structural_revenue,
        "structural_expenditure": e.structural_expenditure,
        "workforce_quality": e.workforce_quality,
        "trade_revenue_contribution": e.trade_revenue_contribution,
        "loans": [_loan(l) for l in e.loans],
    }

def _grievance(g): return dataclasses.asdict(g)
def _demand(d): return dataclasses.asdict(d)

def _faction(f):
    return {
        "id": f.id, "name": f.name,
        "ideology": {"economic": f.ideology.economic, "social": f.ideology.social},
        "power": f.power, "loyalty": f.loyalty, "seats": f.seats,
        "in_coalition": f.in_coalition, "support": f.support,
        "color": f.color,
        "grievances": [_grievance(g) for g in f.grievances],
        "demands": [_demand(d) for d in f.demands],
        "wings": [_wing(w) for w in f.wings],
        "leader": f.leader,
        "role": f.role,
    }

def _wing(w):
    return {
        "id": w.id, "name": w.name,
        "ideology": {"economic": w.ideology.economic, "social": w.ideology.social},
        "strength": w.strength, "loyalty": w.loyalty,
        "kind": w.kind,
        "description": w.description,
        "policy_biases": dict(w.policy_biases),
    }

def _treaty(t): return dataclasses.asdict(t)

def _relation(r):
    return {
        "country_a_id": r.country_a_id, "country_b_id": r.country_b_id,
        "score": r.score, "trade_volume": r.trade_volume,
        "treaties": [_treaty(t) for t in r.treaties],
        "history": list(r.history),
        "sanctioned": r.sanctioned,
    }

def _country(c):
    return {
        "id": c.id, "name": c.name, "regime_type": c.regime_type,
        "population": c.population, "economy": _economy(c.economy),
        "factions": [_faction(f) for f in c.factions],
        "relations": {k: _relation(v) for k, v in c.relations.items()},
        "stability": c.stability, "bureaucratic_capacity": c.bureaucratic_capacity,
        "national_traits": list(c.national_traits), "is_player": c.is_player,
        "agenda": dict(c.agenda),
        "leader_name": c.leader_name,
        "paper": c.paper,
        "capital": c.capital,
        "plan": dict(c.plan),
        "civil_war_risk": c.civil_war_risk, "in_civil_war": c.in_civil_war,
    }

def _law_effect(fx):
    return {
        "gdp_growth_delta": fx.gdp_growth_delta,
        "unemployment_delta": fx.unemployment_delta,
        "inflation_delta": fx.inflation_delta,
        "budget_revenue_delta": fx.budget_revenue_delta,
        "budget_expenditure_delta": fx.budget_expenditure_delta,
        "faction_loyalty_deltas": dict(fx.faction_loyalty_deltas),
        "faction_power_deltas": dict(fx.faction_power_deltas),
        "one_time_debt_pct_delta": fx.one_time_debt_pct_delta,
        # Modifier TEMPLATES must round-trip: a bill that hasn't passed yet
        # (pending_bills, law_history) carries its entire long-term payoff
        # here and nowhere else — dropping them silently gutted every bill
        # proposed before a save. For already-active laws these are inert
        # (their modifiers live in state.modifiers and nothing re-runs
        # activation on load), so serialising them costs only bytes.
        "modifiers": [_modifier(m) for m in fx.modifiers],
    }

def _law(l):
    return {
        "id": l.id, "name": l.name, "description": l.description,
        "status": l.status, "tier": l.tier, "portfolio": l.portfolio,
        "ideology": ({"economic": l.ideology.economic, "social": l.ideology.social}
                     if l.ideology else None),
        "effects": _law_effect(l.effects),
        "lobbying_bonus": dict(l.lobbying_bonus),
        "votes_for": l.votes_for, "votes_against": l.votes_against,
        "turns_active": l.turns_active, "proposed_by": l.proposed_by,
    }

def _legislature(leg):
    return {
        "total_seats": leg.total_seats,
        "seat_distribution": dict(leg.seat_distribution),
        "pending_bills": [_law(l) for l in leg.pending_bills],
        "active_laws": [_law(l) for l in leg.active_laws],
        "law_history": [_law(l) for l in leg.law_history],
    }

def _minister(m): return dataclasses.asdict(m)

def _modifier(m): return dataclasses.asdict(m)

def _pending_event(p): return dataclasses.asdict(p)

def _election_result(er): return dataclasses.asdict(er)

def _legacy(lg):
    return dataclasses.asdict(lg) if lg is not None else None

def _player(p): return dataclasses.asdict(p)

def _region(r): return dataclasses.asdict(r)

def _regional_program(p): return dataclasses.asdict(p)
def _annual_budget(b): return dataclasses.asdict(b) if b is not None else None
def _ministry(m): return dataclasses.asdict(m)
def _household(h): return dataclasses.asdict(h)
def _reform_project(project): return dataclasses.asdict(project) if project is not None else None


def serialize_state(state: GameState) -> dict:
    return {
        "save_version": SAVE_VERSION,
        "year": state.year, "month": state.month, "day": state.day,
        "day_index": state.day_index, "turn": state.turn,
        "player": _player(state.player),
        "country": _country(state.country),
        "world": [_country(c) for c in state.world],
        "regions": {region_id: _region(region)
                    for region_id, region in state.regions.items()},
        "regional_programs": [_regional_program(program)
                              for program in state.regional_programs],
        "legislature": _legislature(state.legislature),
        "cabinet": [_minister(m) for m in state.cabinet.ministers],
        "shadow_cabinet": [_minister(m) for m in state.shadow_cabinet.ministers],
        "domestic_politics": dict(state.domestic_politics),
        "active_budget": _annual_budget(state.active_budget),
        "pending_budget": _annual_budget(state.pending_budget),
        "budget_history": [_annual_budget(b) for b in state.budget_history],
        "ministries": {portfolio: _ministry(ministry)
                       for portfolio, ministry in state.ministries.items()},
        "households": {household_id: _household(household)
                       for household_id, household in state.households.items()},
        "reform_project": _reform_project(state.reform_project),
        # Plain dict of primitives already — no dataclass helper needed.
        "last_snapshot": dict(state.last_snapshot),
        "attention_spent": int(state.attention_spent),
        "modifiers": [_modifier(m) for m in state.modifiers],
        "pending_events": [_pending_event(p) for p in state.pending_events],
        "event_fire_history": dict(state.event_fire_history),
        "scheduled_events": [dict(s) for s in state.scheduled_events],
        "cooldowns": dict(state.cooldowns),
        "insurgency_pressure": state.insurgency_pressure,
        "world_arcs": dict(state.world_arcs),
        "stability": {"value": state.stability.value, "trend": state.stability.trend,
                       "breakdown": dict(state.stability.breakdown)},
        "civil_war_risk": state.civil_war_risk,
        "civil_war": state.civil_war,
        "civil_war_breakdown": dict(state.civil_war_breakdown),
        "ruling_faction_id": state.ruling_faction_id,
        "last_election_turn": state.last_election_turn,
        "election_history": [_election_result(er) for er in state.election_history],
        "event_history": list(state.event_history),
        "legacy": _legacy(state.legacy),
        # Obsolete presentation-only keys are not allowed to linger when an
        # older campaign is loaded and saved again.
        "campaign_meta": {k: v for k, v in state.campaign_meta.items()
                          if k != "portrait"},
    }


# ── Deserialisation ─────────────────────────────────────────────────────────

def _load_budget(d): return Budget(revenue=d["revenue"], expenditure=d["expenditure"])

def _load_economy(d):
    e = Economy(
        gdp=d["gdp"], growth_rate=d["growth_rate"], inflation=d["inflation"],
        unemployment=d["unemployment"], public_debt_pct=d["public_debt_pct"],
        budget=_load_budget(d["budget"]),
        sectors=[Sector(**s) for s in d.get("sectors", [])],
    )
    # Overwrite structural baselines and extras from the save (post_init seeded
    # them from headline values; the saved run-time values are authoritative).
    for attr in ["structural_growth_rate", "structural_unemployment", "structural_inflation",
                 "structural_revenue", "structural_expenditure", "workforce_quality",
                 "trade_revenue_contribution"]:
        if attr in d and d[attr] is not None:
            setattr(e, attr, d[attr])
    e.loans = [Loan(**l) for l in d.get("loans", [])]
    return e

def _load_faction(d):
    ideology = Ideology(economic=d["ideology"]["economic"], social=d["ideology"]["social"])
    return Faction(
        id=d["id"], name=d["name"],
        ideology=ideology,
        power=d["power"], loyalty=d["loyalty"], seats=d["seats"],
        in_coalition=d.get("in_coalition", False), support=d.get("support", 0.2),
        color=d.get("color"),
        grievances=[Grievance(**g) for g in d.get("grievances", [])],
        demands=[Demand(**dm) for dm in d.get("demands", [])],
        wings=[_load_wing(w) for w in d.get("wings", [])],
        leader=d.get("leader", ""),
        # Older saves predate roles; recompute rather than leaving it blank.
        role=d.get("role") or roles.classify(ideology),
    )

def _load_wing(d):
    return Wing(
        id=d["id"], name=d["name"],
        ideology=Ideology(economic=d["ideology"]["economic"], social=d["ideology"]["social"]),
        strength=d.get("strength", 0.0), loyalty=d.get("loyalty", 0.6),
        kind=d.get("kind", "wing"),
        description=d.get("description", ""),
        policy_biases=dict(d.get("policy_biases", {})),
    )


def _upgrade_ardenian_currents(country):
    """Replace only the known pre-canon Ardenian spectra in an old save.

    A save that already contains named blocs, or custom party data, is left
    alone. The canonical data remains the one source for names, prose and
    policy interests.
    """
    if country.id != "ardenia":
        return
    by_party = {}
    for bloc in ARDENIAN_BLOCS:
        by_party.setdefault(bloc["parent_id"], []).append(bloc)
    for faction in country.factions:
        legacy_ids = _LEGACY_ARDENIA_WING_IDS.get(faction.id)
        if legacy_ids is None or {w.id for w in faction.wings} != legacy_ids:
            continue
        faction.wings = [
            Wing(
                id=bloc["id"], name=bloc["name"],
                ideology=Ideology(**BLOC_PROFILES[bloc["id"]]["ideology"]),
                strength=BLOC_PROFILES[bloc["id"]]["strength"],
                loyalty=BLOC_PROFILES[bloc["id"]]["loyalty"],
                kind="bloc", description=bloc["body"],
                policy_biases=dict(BLOC_PROFILES[bloc["id"]]["policy_biases"]),
            )
            for bloc in by_party.get(faction.id, [])
        ]

def _load_relation(d):
    # Tolerate both the current field names and any legacy short forms.
    a_id = d.get("country_a_id", d.get("country_a"))
    b_id = d.get("country_b_id", d.get("country_b"))
    r = BilateralRelation(a_id, b_id,
                          score=d.get("score", 0.0), trade_volume=d.get("trade_volume", 0.0))
    r.treaties = [Treaty(**t) for t in d.get("treaties", [])]
    r.history = list(d.get("history", []))
    r.sanctioned = d.get("sanctioned", False)
    return r

def _load_country(d):
    c = Country(
        id=d["id"], name=d["name"], regime_type=d["regime_type"],
        population=d["population"], economy=_load_economy(d["economy"]),
        factions=[_load_faction(f) for f in d.get("factions", [])],
        stability=d.get("stability", 0.7),
        bureaucratic_capacity=d.get("bureaucratic_capacity", 0.75),
        national_traits=list(d.get("national_traits", [])),
        agenda=dict(d.get("agenda", {})),
        leader_name=d.get("leader_name", ""),
        paper=d.get("paper", ""),
        capital=d.get("capital", ""),
        plan=dict(d.get("plan", {})),
        civil_war_risk=d.get("civil_war_risk", 0.0),
        in_civil_war=d.get("in_civil_war", False),
        is_player=d.get("is_player", False),
    )
    c.relations = {k: _load_relation(v) for k, v in d.get("relations", {}).items()}
    return c

def _load_law(d):
    fx = d.get("effects", {})
    effect = LawEffect(
        gdp_growth_delta=fx.get("gdp_growth_delta", 0.0),
        unemployment_delta=fx.get("unemployment_delta", 0.0),
        inflation_delta=fx.get("inflation_delta", 0.0),
        budget_revenue_delta=fx.get("budget_revenue_delta", 0.0),
        budget_expenditure_delta=fx.get("budget_expenditure_delta", 0.0),
        faction_loyalty_deltas=dict(fx.get("faction_loyalty_deltas", {})),
        faction_power_deltas=dict(fx.get("faction_power_deltas", {})),
        one_time_debt_pct_delta=fx.get("one_time_debt_pct_delta", 0.0),
        modifiers=[_load_modifier(m) for m in fx.get("modifiers", [])],
    )
    ideo = d.get("ideology")
    law = Law(
        id=d["id"], name=d["name"], description=d.get("description", ""),
        status=d.get("status", "active"), tier=d.get("tier", "statutory"),
        portfolio=d.get("portfolio"), effects=effect,
        ideology=(Ideology(economic=ideo["economic"], social=ideo["social"])
                  if ideo else None),
        votes_for=d.get("votes_for", 0), votes_against=d.get("votes_against", 0),
        turns_active=d.get("turns_active", 0), proposed_by=d.get("proposed_by", "player"),
    )
    law.lobbying_bonus = dict(d.get("lobbying_bonus", {}))
    return law

def _load_legislature(d):
    leg = Legislature(
        total_seats=d["total_seats"],
        seat_distribution=dict(d.get("seat_distribution", {})),
        active_laws=[_load_law(l) for l in d.get("active_laws", [])],
    )
    leg.pending_bills = [_load_law(l) for l in d.get("pending_bills", [])]
    leg.law_history = [_load_law(l) for l in d.get("law_history", [])]
    return leg

def _load_player(d):
    known = {f.name for f in dataclasses.fields(Player)}
    return Player(**{k: v for k, v in d.items() if k in known})

def _load_modifier(d):
    known = {f.name for f in dataclasses.fields(Modifier)}
    return Modifier(**{k: v for k, v in d.items() if k in known})

def _load_pending_event(d):
    known = {f.name for f in dataclasses.fields(PendingEvent)}
    return PendingEvent(**{k: v for k, v in d.items() if k in known})

def _load_minister(d):
    known = {f.name for f in dataclasses.fields(Minister)}
    return Minister(**{k: v for k, v in d.items() if k in known})

def _load_legacy(d):
    if d is None:
        return None
    known = {f.name for f in dataclasses.fields(GovernmentLegacy)}
    lg = GovernmentLegacy(**{k: v for k, v in d.items() if k in known})
    # Tuples become lists through JSON; normalise every (date_str, value)
    # history list back, not just milestones.
    for field_name in ("gdp_history", "approval_history", "coalition_history", "milestones"):
        entries = getattr(lg, field_name, None)
        if entries:
            setattr(lg, field_name, [tuple(x) if isinstance(x, list) else x for x in entries])
    return lg

def _load_election_result(d):
    known = {f.name for f in dataclasses.fields(ElectionResult)}
    return ElectionResult(**{k: v for k, v in d.items() if k in known})

def _load_region(d):
    known = {f.name for f in dataclasses.fields(RegionState)}
    return RegionState(**{k: v for k, v in d.items() if k in known})

def _load_regional_program(d):
    known = {f.name for f in dataclasses.fields(RegionalProgram)}
    return RegionalProgram(**{k: v for k, v in d.items() if k in known})

def _load_annual_budget(d):
    if d is None:
        return None
    known = {f.name for f in dataclasses.fields(AnnualBudget)}
    return AnnualBudget(**{k: v for k, v in d.items() if k in known})

def _load_ministry(d):
    known = {f.name for f in dataclasses.fields(MinistryState)}
    return MinistryState(**{k: v for k, v in d.items() if k in known})

def _load_household(d):
    known = {f.name for f in dataclasses.fields(HouseholdGroupState)}
    return HouseholdGroupState(**{k: v for k, v in d.items() if k in known})


def _load_reform_project(d):
    if d is None:
        return None
    known = {f.name for f in dataclasses.fields(ReformProject)}
    return ReformProject(**{k: v for k, v in d.items() if k in known})


def deserialize_state(data: dict) -> GameState:
    player = _load_player(data["player"])
    country = _load_country(data["country"])
    world = [_load_country(c) for c in data.get("world", [])]
    _upgrade_ardenian_currents(country)
    for world_country in world:
        _upgrade_ardenian_currents(world_country)
    legislature = _load_legislature(data["legislature"])
    cabinet = Cabinet(ministers=[_load_minister(m) for m in data.get("cabinet", [])])

    state = GameState(
        year=data["year"], month=data["month"],
        player=player, country=country, world=world,
        regions={region_id: _load_region({**region_data, "id": region_id})
                 for region_id, region_data in data.get("regions", {}).items()},
        regional_programs=[_load_regional_program(program)
                           for program in data.get("regional_programs", [])],
        legislature=legislature, cabinet=cabinet,
    )
    # Campaigns saved before the regional layer receive Ardenia's canonical
    # starting conditions. Other countries remain empty until authored.
    if not state.regions:
        state.regions = initial_region_states(
            country.id, {faction.id: faction.support for faction in country.factions})
    ensure_electoral_support(state)
    state.day = data.get("day", 1)
    # Old saves only knew months. A monotonic approximate elapsed day keeps
    # the new clock coherent without changing any month-based cooldowns.
    state.day_index = data.get("day_index", data.get("turn", 0) * 30)
    state.turn = data.get("turn", 0)
    state.shadow_cabinet = Cabinet(
        ministers=[_load_minister(m) for m in data.get("shadow_cabinet", [])])
    state.modifiers = [_load_modifier(m) for m in data.get("modifiers", [])]
    state.pending_events = [_load_pending_event(p) for p in data.get("pending_events", [])]
    state.event_fire_history = dict(data.get("event_fire_history", {}))
    state.scheduled_events = [dict(s) for s in data.get("scheduled_events", [])]
    state.cooldowns = dict(data.get("cooldowns", {}))
    state.domestic_politics = dict(data.get("domestic_politics", {}))
    state.active_budget = _load_annual_budget(data.get("active_budget"))
    state.pending_budget = _load_annual_budget(data.get("pending_budget"))
    state.budget_history = [_load_annual_budget(b)
                            for b in data.get("budget_history", []) if b is not None]
    ensure_budget_state(state)
    state.ministries = {portfolio: _load_ministry({**ministry_data,
                                                   "portfolio": portfolio})
                        for portfolio, ministry_data in data.get("ministries", {}).items()}
    ensure_ministries(state)
    state.households = {household_id: _load_household({**household_data,
                                                       "id": household_id})
                        for household_id, household_data in data.get("households", {}).items()}
    ensure_households(state)
    state.reform_project = _load_reform_project(data.get("reform_project"))
    # Missing on saves written before the monthly digest existed — an empty
    # dict is exactly "nothing to compare against yet", not a crash.
    state.last_snapshot = dict(data.get("last_snapshot", {}))
    # Saves written before government attention existed simply lack the key;
    # 0 means "nothing committed yet this month", which is the safe default.
    state.attention_spent = int(data.get("attention_spent", 0))
    state.insurgency_pressure = data.get("insurgency_pressure", 0.0)
    state.world_arcs = dict(data.get("world_arcs", {}))

    st = data.get("stability", {})
    state.stability = GovernmentStability(
        value=st.get("value", 0.55), trend=st.get("trend", 0.0),
        breakdown=dict(st.get("breakdown", {})))

    state.civil_war_risk = data.get("civil_war_risk", 0.0)
    state.civil_war = data.get("civil_war", False)
    state.civil_war_breakdown = dict(data.get("civil_war_breakdown", {}))
    state.ruling_faction_id = data.get("ruling_faction_id", player.faction_id)
    state.last_election_turn = data.get("last_election_turn", 0)
    state.election_history = [_load_election_result(er) for er in data.get("election_history", [])]
    state.event_history = list(data.get("event_history", []))
    # Only override the post_init-created legacy if the save actually carried
    # one — an older save without a legacy keeps the fresh default rather than
    # having it clobbered to None.
    if data.get("legacy") is not None:
        state.legacy = _load_legacy(data["legacy"])
    state.campaign_meta = dict(data.get("campaign_meta", {}))
    state.campaign_meta.pop("portrait", None)  # migrate pre-removal saves
    return state


# ── File operations ─────────────────────────────────────────────────────────

def _saves_dir():
    return app_paths.saves_dir()


def _ensure_saves_dir():
    return app_paths.ensure_directory(_saves_dir())

def _slot_path(slot: str) -> str:
    safe = "".join(c for c in slot if c.isalnum() or c in ("-", "_")).strip() or "save"
    return str(_saves_dir() / f"{safe}.json")

def save_campaign(state: GameState, slot: str = "manual") -> str:
    _ensure_saves_dir()
    path = _slot_path(slot)
    data = serialize_state(state)
    # A little human-readable header for the load screen.
    data["_label"] = f"{state.player.name} — {state.country.name} — {state.date_string()}"
    # Write-then-replace, not write-in-place: the GUI autosaves every single
    # turn, so this is the most exposed write in the game. Truncating the
    # real file (the old "w" open) means a failure mid-write — disk full,
    # a killed process, power loss — leaves a corrupt, unloadable file where
    # the last GOOD save used to be. os.replace() is atomic on the same
    # volume on both POSIX and Windows: a crash mid-write leaves either the
    # old file or the fully-written new one, never a truncated hybrid.
    tmp_path = f"{path}.tmp"
    with open(tmp_path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=1)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp_path, path)
    return path

def load_campaign(slot: str = "manual") -> GameState:
    path = _slot_path(slot)
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    save_version = data.get("save_version", 0)
    if save_version > SAVE_VERSION:
        # An OLDER save than this build understands degrades gracefully by
        # design (missing fields -> model defaults). A NEWER one is the
        # opposite case: fields this build has never heard of may have been
        # renamed or restructured, and ".get(key, default)" can't tell
        # "genuinely absent" from "moved" — it silently produces a
        # plausible-looking but wrong campaign instead of failing loud.
        import warnings
        warnings.warn(
            f"Save '{slot}' was written by a newer version (save_version="
            f"{save_version}, this build understands up to {SAVE_VERSION}). "
            "Some fields may load with wrong values rather than the save's "
            "actual last-known state.", RuntimeWarning, stacklevel=2)
    return deserialize_state(data)

def list_saves() -> list:
    """Return [{slot, label, date, country, leader}] for the load screen."""
    saves_dir = _saves_dir()
    if not saves_dir.is_dir():
        return []
    out = []
    for path in sorted(saves_dir.iterdir(), key=lambda item: item.name):
        if path.suffix != ".json":
            continue
        slot = path.stem
        try:
            with path.open("r", encoding="utf-8") as fh:
                data = json.load(fh)
            out.append({
                "slot": slot,
                "label": data.get("_label", slot),
                "country": data.get("country", {}).get("name", "?"),
                "leader": data.get("player", {}).get("name", "?"),
                "date": f"{data.get('year','?')}-{data.get('month','?'):0>2}",
                "save_version": data.get("save_version", 0),
            })
        except (json.JSONDecodeError, KeyError, OSError):
            continue  # skip corrupt/unreadable saves rather than crashing the menu
    return out

def delete_save(slot: str) -> bool:
    path = _slot_path(slot)
    if os.path.exists(path):
        os.remove(path)
        return True
    return False

def save_exists(slot: str) -> bool:
    return os.path.exists(_slot_path(slot))
