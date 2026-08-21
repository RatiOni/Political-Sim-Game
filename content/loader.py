"""
Country data loading: content/countries/*.json → model objects. Adding or
editing a country is a content edit, not a code edit. build_state_for(id)
assembles a full GameState with that country as the player and every other
defined country as the world.
"""

import os
import json

from models.faction import Faction, Ideology, Grievance, Demand
from models import roles
from models.wing import Wing
from models.economy import Economy, Sector, Budget
from models.cabinet import Cabinet, Minister
from models.legislature import Legislature, Law, LawEffect
from models.relations import BilateralRelation
from models.country import Country
from game_state import GameState, Player
from engine import (legislative, crisis, parties, cabinet_ops, regions,
                    budget as budget_engine, ministries, households)
from content.lore import BLOCS as ARDENIAN_BLOCS, BLOC_PROFILES


_COUNTRIES_DIR = os.path.join(os.path.dirname(__file__), "countries")


# ── Raw data access ────────────────────────────────────────────────────────

def _country_path(country_id: str) -> str:
    return os.path.join(_COUNTRIES_DIR, f"{country_id}.json")


def available_country_ids() -> list:
    if not os.path.isdir(_COUNTRIES_DIR):
        return []
    return sorted(f[:-5] for f in os.listdir(_COUNTRIES_DIR) if f.endswith(".json"))


def load_country_data(country_id: str) -> dict:
    with open(_country_path(country_id), "r", encoding="utf-8") as fh:
        return json.load(fh)


def list_country_summaries() -> list:
    """Lightweight list for the selection screen: id, name, and meta block."""
    out = []
    for cid in available_country_ids():
        data = load_country_data(cid)
        out.append({
            "id": data["id"],
            "name": data["name"],
            "regime_type": data.get("regime_type", "unknown"),
            "meta": data.get("meta", {}),
            "national_traits": data.get("national_traits", []),
        })
    return out


# ── Model construction ──────────────────────────────────────────────────────

def _build_economy(econ_data: dict) -> Economy:
    budget = Budget(revenue=econ_data["budget"]["revenue"],
                    expenditure=econ_data["budget"]["expenditure"])
    sectors = [Sector(s["id"], s["name"], s["gdp_share"], s["growth_rate"],
                      s["employment_share"], list(s.get("aligned_faction_ids", [])))
               for s in econ_data.get("sectors", [])]
    return Economy(
        gdp=econ_data["gdp"],
        growth_rate=econ_data["growth_rate"],
        inflation=econ_data["inflation"],
        unemployment=econ_data["unemployment"],
        public_debt_pct=econ_data["public_debt_pct"],
        budget=budget,
        sectors=sectors,
    )


def _build_faction(f: dict) -> Faction:
    ideology = Ideology(economic=f["ideology"]["economic"], social=f["ideology"]["social"])
    return Faction(
        id=f["id"], name=f["name"],
        ideology=ideology,
        # Every faction is classified into a canonical role from its own
        # ideology, so events can address roles instead of country-specific
        # faction ids (models/roles.py).
        role=roles.classify(ideology),
        power=f["power"], loyalty=f["loyalty"], seats=f["seats"],
        in_coalition=f.get("in_coalition", False),
        support=f.get("support", 0.2),
        color=f.get("color"),
        grievances=[Grievance(g["source"], g["severity"], g.get("turns_active", 0))
                    for g in f.get("grievances", [])],
        demands=[Demand(d["description"], d.get("urgency", 0.5), d.get("law_id"))
                 for d in f.get("demands", [])],
        wings=[_build_wing(w) for w in f.get("wings", [])],
        leader=f.get("leader", ""),
    )


def _build_wing(w: dict) -> Wing:
    return Wing(
        id=w["id"], name=w["name"],
        ideology=Ideology(economic=w["ideology"]["economic"], social=w["ideology"]["social"]),
        strength=w["strength"], loyalty=w.get("loyalty", 0.6),
        kind=w.get("kind", "wing"),
        description=w.get("description", ""),
        policy_biases=dict(w.get("policy_biases", {})),
    )


def _ardenian_bloc_wings(faction_id: str) -> list:
    """Build a party's live currents from the single canon data source."""
    out = []
    for bloc in ARDENIAN_BLOCS:
        if bloc["parent_id"] != faction_id:
            continue
        profile = BLOC_PROFILES[bloc["id"]]
        out.append(Wing(
            id=bloc["id"],
            name=bloc["name"],
            ideology=Ideology(**profile["ideology"]),
            strength=profile["strength"],
            loyalty=profile["loyalty"],
            kind="bloc",
            description=bloc["body"],
            policy_biases=dict(profile["policy_biases"]),
        ))
    return out


def _build_law(l: dict) -> Law:
    fx = l.get("effects", {})
    effect = LawEffect(
        gdp_growth_delta=fx.get("gdp_growth_delta", 0.0),
        unemployment_delta=fx.get("unemployment_delta", 0.0),
        inflation_delta=fx.get("inflation_delta", 0.0),
        budget_revenue_delta=fx.get("budget_revenue_delta", 0.0),
        budget_expenditure_delta=fx.get("budget_expenditure_delta", 0.0),
        faction_loyalty_deltas=dict(fx.get("faction_loyalty_deltas", {})),
        faction_power_deltas=dict(fx.get("faction_power_deltas", {})),
        one_time_debt_pct_delta=fx.get("one_time_debt_pct_delta", 0.0),
    )
    ideo = l.get("ideology")
    return Law(
        id=l["id"], name=l["name"], description=l.get("description", ""),
        status=l.get("status", "active"), tier=l.get("tier", "statutory"),
        portfolio=l.get("portfolio"),
        ideology=(Ideology(economic=ideo["economic"], social=ideo["social"])
                  if ideo else None),
        effects=effect,
        votes_for=l.get("votes_for", 0), votes_against=l.get("votes_against", 0),
        turns_active=l.get("turns_active", 0),
        proposed_by=l.get("proposed_by", "player"),
    )


def build_country(data: dict, is_player: bool) -> Country:
    """Build a Country from its dict; factions load for world countries too."""
    economy = _build_economy(data["economy"])
    factions = [_build_faction(f) for f in data.get("factions", [])]
    # Ardenia's political currents are Part I canon. Do not keep a parallel
    # generic-wing layer for them: the Circle, the Works and the Line are the
    # live seat-holding actors. Other countries continue to use authored or
    # generated generic wings until they receive their own canon.
    if data["id"] == "ardenia":
        for faction in factions:
            blocs = _ardenian_bloc_wings(faction.id)
            if blocs:
                faction.wings = blocs
    country = Country(
        id=data["id"], name=data["name"],
        regime_type=data["regime_type"],
        population=data["population"],
        economy=economy,
        factions=factions,
        stability=data.get("meta", {}).get("stability_value", 0.7),
        bureaucratic_capacity=data.get("bureaucratic_capacity", 0.75),
        national_traits=list(data.get("national_traits", [])),
        agenda=dict(data.get("agenda", {})),
        leader_name=data.get("default_player", {}).get("name", ""),
        paper=data.get("meta", {}).get("paper", ""),
        capital=data.get("meta", {}).get("capital", ""),
        is_player=is_player,
    )
    return country


def build_player(data: dict) -> Player:
    dp = data["default_player"]
    return Player(
        name=dp["name"], title=dp["title"], faction_id=dp["faction_id"],
        ideology_economic=dp.get("ideology_economic", 0.0),
        ideology_social=dp.get("ideology_social", 0.0),
        approval=dp.get("approval", 0.5),
        political_capital=dp.get("political_capital", 45.0),
        pc_regen_base=dp.get("pc_regen_base", 10.0),
    )


# Fallback personalities for authored cabinets whose JSON predates traits.
# Deterministic round-robin — no RNG draw, so seeded test trajectories are
# untouched — with the schemer placed early enough that even a small cabinet
# contains one (the schemer arc in content/events.py needs somebody to
# scheme). An explicit "trait" in the JSON always wins.
_FALLBACK_TRAITS = ["technocrat", "loyalist", "schemer", "grandee", "firebrand"]


def _build_cabinet(data: dict) -> Cabinet:
    ministers = [Minister(m["id"], m["name"], m["portfolio"], m["faction_id"],
                          competence=m["competence"], loyalty=m["loyalty"],
                          ambition=m["ambition"],
                          trait=m.get("trait",
                                      _FALLBACK_TRAITS[i % len(_FALLBACK_TRAITS)]))
                 for i, m in enumerate(data.get("cabinet", []))]
    return Cabinet(ministers=ministers)


def _build_legislature(data: dict, factions: list) -> Legislature:
    laws = [_build_law(l) for l in data.get("starting_laws", [])]
    for law in laws:
        law.status = "active"
    return Legislature(
        total_seats=sum(f.seats for f in factions) or 100,
        seat_distribution={f.id: f.seats for f in factions},
        active_laws=laws,
    )


def _pair_relation(data_by_id: dict, a_id: str, b_id: str):
    """The (score, trade_volume) for a country pair, taking whichever side
    stated it in its default_relations (they're symmetric), or neutral."""
    a_rel = data_by_id.get(a_id, {}).get("default_relations", {}).get(b_id)
    b_rel = data_by_id.get(b_id, {}).get("default_relations", {}).get(a_id)
    src = a_rel or b_rel or {}
    return src.get("score", 0.0), src.get("trade_volume", 0.0)


def _wire_all_relations(countries_by_id: dict, data_by_id: dict):
    """Bilateral relation objects for EVERY country pair, both ways — the
    world-sim moves world↔world relations, not just player↔world."""
    ids = list(countries_by_id.keys())
    for i, a_id in enumerate(ids):
        for b_id in ids[i + 1:]:
            score, trade = _pair_relation(data_by_id, a_id, b_id)
            countries_by_id[a_id].relations[b_id] = BilateralRelation(
                a_id, b_id, score=score, trade_volume=trade)
            countries_by_id[b_id].relations[a_id] = BilateralRelation(
                b_id, a_id, score=score, trade_volume=trade)


def build_state_for(player_country_id: str, start_year: int = 1993, start_month: int = 3) -> GameState:
    """Complete GameState: chosen country as player, all others as the world."""
    player_data = load_country_data(player_country_id)

    player_country = build_country(player_data, is_player=True)
    # Every party the player inspects gets an intra-party spectrum and a named
    # leader; authored content (in the JSON) wins, otherwise generated. No
    # GameState exists yet, so collisions are tracked locally.
    claimed = {p.leader for p in player_country.factions if p.leader}
    claimed.add(player_data.get("default_player", {}).get("name", ""))
    for party in player_country.factions:
        if not party.wings:
            party.wings = parties.generate_default_wings(party)
        if not party.leader:
            party.leader = cabinet_ops.generate_name(used=claimed)
            claimed.add(party.leader)
    player = build_player(player_data)
    cabinet = _build_cabinet(player_data)
    legislature = _build_legislature(player_data, player_country.factions)

    # The world: every other country that has a data file. Neighbours listed
    # in the file come first (and are the ones with default relations), but
    # any other defined country is still part of the world.
    neighbour_ids = player_data.get("neighbours", [])
    other_ids = [cid for cid in available_country_ids() if cid != player_country_id]
    ordered = [cid for cid in neighbour_ids if cid in other_ids] + \
              [cid for cid in other_ids if cid not in neighbour_ids]

    world_data = {cid: load_country_data(cid) for cid in ordered}
    world = [build_country(world_data[cid], is_player=False) for cid in ordered]

    # Wire a relation between EVERY pair of countries (player↔world and
    # world↔world), so the AI world-sim has a bilateral object to move on
    # both sides of every relationship.
    data_by_id = {player_country_id: player_data, **world_data}
    countries_by_id = {player_country.id: player_country, **{c.id: c for c in world}}
    _wire_all_relations(countries_by_id, data_by_id)

    state = GameState(
        year=start_year, month=start_month,
        player=player,
        country=player_country,
        world=world,
        regions=regions.initial_region_states(
            player_country_id,
            {faction.id: faction.support for faction in player_country.factions}),
        legislature=legislature,
        cabinet=cabinet,
    )
    budget_engine.ensure_budget_state(state)
    ministries.ensure_ministries(state)
    households.ensure_households(state)

    # Pre-seeded active laws bypassed the propose→vote path, so switch their
    # long-term modifiers on here (without the passage loyalty shock).
    for law in legislature.active_laws:
        legislative.activate_law_modifiers(state, law)

    # Authored meta.stability_value seeds the player's REAL GovernmentStability
    # (not just the world-country float), so a crisis country's instability
    # reaches the system the player actually plays against.
    meta_stability = player_data.get("meta", {}).get("stability_value")
    if meta_stability is not None:
        state.stability.value = float(meta_stability)

    # Prime civil-war risk so a country authored in crisis starts hot instead
    # of waiting for the gauge to fill from zero.
    state.civil_war_risk, state.civil_war_breakdown = crisis.compute_civil_war_risk(state)
    for c in state.world:
        c.civil_war_risk = crisis.compute_country_civil_war_risk(c)

    return state
