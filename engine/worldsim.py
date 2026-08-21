"""
World simulation: each non-player country drifts (economy, stability),
holds world↔world relations, and acts on its data-defined agenda each turn —
cooperating, undermining, trading, condemning, courting or pressuring the
player — surfaced as dispatches. Seedable RNG; at most one agenda action per
country per turn. TurnEngine calls in; nothing here imports the engine back.
"""

import random

from engine import stability, crisis, flavor
from models.relations import Treaty, MAX_TRADE_VOLUME, cap_trade_volume
from models.country import REGIME_FAMILIES

# Chance any one country takes an agenda action in a given turn.
# Agenda archetypes → how aggressive they are (0..1; feeds the deliberation
# scoring in _national_interest). Targets are resolved from relations at
# planning time; an authored rival/ally on the Country.agenda overrides.
AGENDAS = {
    "hegemon":    0.55,   # throws weight at the strongest, rewards clients
    "revanchist": 0.80,   # nurses a grudge, mostly hostile toward its rival
    "trader":     0.15,   # overwhelmingly cooperative, chases commerce
    "reformer":   0.35,   # courts fellow democracies, needles autocrats
    "survivor":   0.20,   # defensive, shelters under the strongest power
    "ideologue":  0.55,   # befriends its own camp, condemns the other
}

# Fallback agenda by regime, when a country's JSON declares none.
_DEFAULT_AGENDA_BY_REGIME = {
    "parliamentary_democracy": "trader",
    "presidential_democracy": "reformer",
    "hybrid_regime": "survivor",
    "authoritarian": "hegemon",
    "totalitarian": "hegemon",
}

# Short human-readable posture labels, for the UI.
_AGENDA_LABELS = {
    "hegemon":    "Hegemon — projects power over the region",
    "revanchist": "Revanchist — nurses a grudge, presses its rival",
    "trader":     "Trader — chases commerce and open ties",
    "reformer":   "Reformer — courts democracies, needles autocrats",
    "survivor":   "Survivor — seeks shelter under a stronger power",
    "ideologue":  "Ideologue — befriends its camp, condemns the other",
}


def _clamp(v, lo=-1.0, hi=1.0):
    return max(lo, min(hi, v))


# ── Public entry point ──────────────────────────────────────────────────────

def simulate_world(state):
    """One turn of autonomous life for every world country. Called by
    TurnEngine.advance() after the player's own country has been simulated."""
    for country in state.world:
        _drift_economy(country)
        _drift_stability(country)
        # Player sanctions bleed the target monthly.
        rel = state.country.relations.get(country.id)
        if rel is not None and rel.sanctioned:
            country.economy.growth_rate -= 0.003
            country.stability = max(0.05, country.stability - 0.003)
    _update_world_relations(state)
    _pursue_agendas(state)
    _update_world_arcs(state)
    for rel in state.country.relations.values():
        for treaty in rel.treaties:
            treaty.turns_active += 1
    for country in state.world:
        crisis.maybe_trigger_country_civil_war(state, country)


# ── Named developments: axes and feuds ──────────────────────────────────────

AXIS_FORM_THRESHOLD = 0.7      # relation needed (plus a trade pact) to form an axis
FEUD_FORM_THRESHOLD = -0.7
AXIS_BREAK_THRESHOLD = 0.3     # an axis dissolves if the pair cools below this
FEUD_BREAK_THRESHOLD = -0.3


def _update_world_arcs(state):
    """Multi-month named developments: when a pair of countries grows close
    enough (with trade) an 'axis' forms — once — and is remembered; deep
    hostility hardens into a 'feud'. Arcs dissolve when conditions reverse.
    Deterministic; one dispatch per transition."""
    countries = [state.country] + list(state.world)
    for i, a in enumerate(countries):
        for b in countries[i + 1:]:
            rel = a.relations.get(b.id)
            if rel is None:
                continue
            key = "|".join(sorted([a.id, b.id]))
            arc = state.world_arcs.get(key)
            has_trade = any(t.type == "trade" for t in rel.treaties)

            if arc is None:
                if rel.score > AXIS_FORM_THRESHOLD and has_trade:
                    state.world_arcs[key] = "axis"
                    flavor.say(state, "world_axis", a=a.name, b=b.name)
                elif rel.score < FEUD_FORM_THRESHOLD:
                    state.world_arcs[key] = "feud"
                    flavor.say(state, "world_feud", a=a.name, b=b.name)
            elif arc == "axis" and rel.score < AXIS_BREAK_THRESHOLD:
                del state.world_arcs[key]
                flavor.say(state, "world_arc_ends", a=a.name, b=b.name, kind="axis")
            elif arc == "feud" and rel.score > FEUD_BREAK_THRESHOLD:
                del state.world_arcs[key]
                flavor.say(state, "world_arc_ends", a=a.name, b=b.name, kind="feud")


# ── Internal drift ──────────────────────────────────────────────────────────

def _drift_economy(country):
    """Light monthly economic motion: compound GDP, and let the headline
    rates wander gently back toward their structural baselines."""
    econ = country.economy
    econ.gdp *= (1.0 + econ.growth_rate / 12.0)
    econ.growth_rate += (econ.structural_growth_rate - econ.growth_rate) * 0.10
    econ.inflation += (econ.structural_inflation - econ.inflation) * 0.05
    econ.unemployment += (econ.structural_unemployment - econ.unemployment) * 0.05


def _drift_stability(country):
    """Nudge a world country's stability toward a target set by its own
    economic health and how much of its politics is turned against it."""
    econ_signal = stability.compute_economic_signal(country.economy)
    hostile = sum(f.opposition_strength() for f in country.factions)
    target = 0.60 + econ_signal * 0.15 - min(0.40, hostile * 0.30)
    target = max(0.05, min(0.95, target))
    country.stability += (target - country.stability) * 0.05


def _update_world_relations(state):
    """World↔world relation drift by regime alignment (same idiom as the
    player↔world drift in engine/turn.py), plus trade growth on trade pacts.
    Player↔world is handled by the turn engine, so this covers only pairs
    among the world countries themselves."""
    world = state.world
    for i, a in enumerate(world):
        for b in world[i + 1:]:
            rel_ab = a.relations.get(b.id)
            rel_ba = b.relations.get(a.id)
            if rel_ab is None:
                continue
            same_camp = REGIME_FAMILIES.get(a.regime_type) == REGIME_FAMILIES.get(b.regime_type)
            drift = 0.0015 if same_camp else -0.0008
            rel_ab.score = _clamp(rel_ab.score + drift)
            if rel_ba:
                rel_ba.score = rel_ab.score
            if any(t.type == "trade" for t in rel_ab.treaties):
                # Same saturating approach as the player's pacts
                # (engine/turn.py) — world trade converges, never snowballs.
                ceiling = max(0.0, rel_ab.score) * MAX_TRADE_VOLUME
                rel_ab.trade_volume = cap_trade_volume(
                    rel_ab.trade_volume + (ceiling - rel_ab.trade_volume) * 0.04)
                if rel_ba:
                    rel_ba.trade_volume = rel_ab.trade_volume


# ── Agendas: countries acting on their own interests ────────────────────────

def _country_by_id(state, cid):
    if cid == state.country.id:
        return state.country
    return state.world_country(cid)


def _agenda_type(country) -> str:
    declared = country.agenda.get("type") if country.agenda else None
    if declared in AGENDAS:
        return declared
    return _DEFAULT_AGENDA_BY_REGIME.get(country.regime_type, "survivor")


def describe_agenda(state, country) -> str:
    """A one-line, name-resolved posture description for the UI."""
    parts = [_AGENDA_LABELS.get(_agenda_type(country), _agenda_type(country).title())]
    agenda = country.agenda or {}
    rival = _country_by_id(state, agenda["rival"]) if agenda.get("rival") else None
    ally = _country_by_id(state, agenda["ally"]) if agenda.get("ally") else None
    if rival is not None:
        parts.append(f"rival: {rival.name}")
    if ally is not None:
        parts.append(f"ally: {ally.name}")
    return " · ".join(parts)


def _others(state, actor):
    """Every country the actor can act on — the player included."""
    pool = [c for c in state.world if c.id != actor.id]
    pool.append(state.country)  # AI can act on the player, too
    return pool


def _relation_score(actor, other) -> float:
    rel = actor.relations.get(other.id)
    return rel.score if rel else 0.0


def _pick_rival(state, actor):
    """Authored rival if present, else the country the actor likes least."""
    rid = actor.agenda.get("rival") if actor.agenda else None
    if rid:
        rival = _country_by_id(state, rid)
        if rival is not None and rival.id != actor.id:
            return rival
    pool = _others(state, actor)
    return min(pool, key=lambda c: _relation_score(actor, c)) if pool else None


def _pick_ally(state, actor):
    """Authored ally if present, else the country the actor likes most."""
    aid = actor.agenda.get("ally") if actor.agenda else None
    if aid:
        ally = _country_by_id(state, aid)
        if ally is not None and ally.id != actor.id:
            return ally
    pool = _others(state, actor)
    return max(pool, key=lambda c: _relation_score(actor, c)) if pool else None


def _adjust(state, actor, target, delta):
    """Symmetrically shift the actor↔target relation."""
    ra = actor.relations.get(target.id)
    rb = target.relations.get(actor.id)
    if ra is not None:
        ra.score = _clamp(ra.score + delta)
        if rb is not None:
            rb.score = ra.score
    elif rb is not None:
        rb.score = _clamp(rb.score + delta)


def _lname(country) -> str:
    return country.leader_name or f"{country.name}'s leadership"


def _is_player(state, country) -> bool:
    return country.id == state.country.id


def _national_interest(state, actor, atype):
    """The behind-the-curtain filter: what serves this country best right
    now? Deterministic — returns (objective, target_country_or_None)."""
    if actor.in_civil_war or actor.stability < 0.35:
        return "consolidate", None
    if atype == "survivor" and actor.stability <= 0.6:
        return "consolidate", None

    # A grudge outranks everything: whoever sanctions you is the problem.
    for other in _others(state, actor):
        rel = actor.relations.get(other.id)
        if rel is not None and rel.sanctioned:
            return "undermine", other

    if atype == "trader":
        best = _pick_ally(state, actor)
        if best is not None:
            rel = actor.relations.get(best.id)
            has_trade = bool(rel and any(t.type == "trade" for t in rel.treaties))
            return ("court" if has_trade else "trade"), best
        return "consolidate", None

    if AGENDAS[atype] >= 0.5:
        rival = _pick_rival(state, actor)
        if rival is not None:
            rel = actor.relations.get(rival.id)
            if atype == "hegemon" and rel is not None and rel.score < -0.8:
                # The rivalry is bottomed out — spend the cycle on the sphere.
                ally = _pick_ally(state, actor)
                if ally is not None:
                    return "court", ally
            return "undermine", rival

    ally = _pick_ally(state, actor)
    if ally is not None:
        return "court", ally
    return "consolidate", None


def _make_plan(state, actor, stagger=None):
    """Deliberate: evaluate the national interest, commit to a plan, and set
    when it matures. First-ever plans are staggered by country index so the
    opening months are quiet; later cycles carry a small jitter (the one RNG
    draw in the scheduler)."""
    atype = _agenda_type(actor)
    objective, target = _national_interest(state, actor, atype)
    if stagger is not None:
        matures = state.turn + 2 + (stagger % 4)
    else:
        matures = state.turn + 3 + random.randint(0, 2)
    actor.plan = {"objective": objective,
                  "target": target.id if target is not None else None,
                  "matures_turn": matures}
    # Threats and deals leak; courtesies and quiet housekeeping don't.
    if target is not None and objective in ("undermine", "trade"):
        tname = state.country.name if _is_player(state, target) else target.name
        flavor.say(state, "world_deliberates",
                   actor=actor.name, actor_leader=_lname(actor), target=tname)


def _execute_plan(state, actor):
    plan = actor.plan
    target = _country_by_id(state, plan.get("target")) if plan.get("target") else None
    objective = plan.get("objective")
    if objective == "consolidate":
        actor.stability = min(0.95, actor.stability + 0.01)
    elif objective == "undermine":
        _hostile_action(state, actor, target=target)
    elif objective in ("court", "trade"):
        _cooperative_action(state, actor, target=target)


def _pursue_agendas(state):
    """The deliberation loop: countries think, foreshadow, act when their
    plan matures, then think again — a steady drumbeat instead of dice."""
    for i, actor in enumerate(state.world):
        if not actor.plan:
            _make_plan(state, actor, stagger=i)
            continue
        if state.turn >= actor.plan.get("matures_turn", 0):
            _execute_plan(state, actor)
            _make_plan(state, actor)


def _hostile_action(state, actor, target=None):
    target = target if target is not None else _pick_rival(state, actor)
    if target is None:
        return
    # Deterrence: a player under a defense-pact umbrella is a riskier mark —
    # half of would-be hostile moves against them are quietly shelved.
    if _is_player(state, target):
        from engine import diplomacy as _dip
        if _dip.has_any_defense_pact(state) and random.random() < 0.5:
            return
    condemn = random.random() < 0.35
    if _is_player(state, target):
        if condemn:
            _adjust(state, actor, target, -0.12)
            flavor.say(state, "world_condemn_player",
                       actor=actor.name, actor_leader=_lname(actor))
        else:
            _adjust(state, actor, target, -0.06)
            flavor.say(state, "world_pressure_player",
                       actor=actor.name, actor_leader=_lname(actor))
    else:
        _adjust(state, actor, target, -0.12 if condemn else -0.06)
        flavor.say(state, "world_condemn" if condemn else "world_undermine",
                   actor=actor.name, actor_leader=_lname(actor),
                   target=target.name, target_leader=_lname(target))


def _cooperative_action(state, actor, target=None):
    target = target if target is not None else _pick_ally(state, actor)
    if target is None:
        return
    if _is_player(state, target):
        rel_p = state.country.relations.get(actor.id)
        if rel_p is not None and rel_p.sanctioned:
            return   # nobody courts the power that is strangling their trade
    rel = actor.relations.get(target.id)
    has_trade = bool(rel and any(t.type == "trade" for t in rel.treaties))
    # A trade pact if the ground is friendly and none exists yet; otherwise
    # just warmer ties.
    if rel and rel.score > 0.1 and not has_trade and random.random() < 0.5:
        _sign_trade_pact(state, actor, target)
    else:
        _adjust(state, actor, target, 0.06 if _is_player(state, target) else 0.05)
        if _is_player(state, target):
            flavor.say(state, "world_court_player",
                       actor=actor.name, actor_leader=_lname(actor))
        else:
            flavor.say(state, "world_deepen",
                       actor=actor.name, actor_leader=_lname(actor),
                       target=target.name, target_leader=_lname(target))


def _sign_trade_pact(state, actor, target):
    treaty = Treaty(
        id=f"trade_{actor.id}_{target.id}",
        name=f"{actor.name}–{target.name} Trade Pact",
        type="trade",
        parties=[actor.id, target.id],
    )
    for a, b in ((actor, target), (target, actor)):
        rel = a.relations.get(b.id)
        if rel is not None:
            rel.treaties.append(treaty)
            rel.trade_volume = cap_trade_volume(rel.trade_volume + 200.0)
    _adjust(state, actor, target, 0.05)
    if _is_player(state, target):
        flavor.say(state, "world_trade_pact",
                   actor=actor.name, actor_leader=_lname(actor),
                   target="your government", target_leader=state.player.name)
    else:
        flavor.say(state, "world_trade_pact",
                   actor=actor.name, actor_leader=_lname(actor),
                   target=target.name, target_leader=_lname(target))
