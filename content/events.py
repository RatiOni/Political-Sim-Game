"""
Event catalog — situations with player choices, written to work in ANY of
the nine countries rather than only Ardenia.

Nothing here names a country's parties or neighbours directly. Faction
effects address canonical ROLES (models/roles.py: "@labour", "@nationalist",
…), resolved against whichever faction plays that part in the country being
played (engine/legislative.py: resolve_faction_key). Diplomatic effects use
target sentinels (TARGET_COOLEST, TARGET_MOST_HOSTILE) resolved against the
relation that actually triggered the event (engine/events.py:
resolve_relation_target). Both degrade safely: a role or target with no
local equivalent is skipped rather than crashing.

EventOption.effects is a LawEffect; relation_deltas additionally moves
bilateral relations, which LawEffect has no concept of.
"""

import random

from models.events import (EventDef, EventOption, TARGET_MOST_HOSTILE,
                           TARGET_COOLEST)
from models.roles import (ROLE_LABOUR, ROLE_BUSINESS, ROLE_NATIONALIST,
                          ROLE_AGRARIAN, ROLE_REFORM, ROLE_ESTABLISHMENT)
from models.legislature import LawEffect
from models.modifiers import Modifier


def _has_serious_grievance(state) -> bool:
    return any(g.severity >= 0.45 for f in state.country.factions for g in f.grievances)


def _any_cool_relation(state) -> bool:
    """Any neighbour we are on less-than-warm terms with — whoever that is
    in this country becomes the event's target (TARGET_COOLEST)."""
    return any(rel.score < 0.3 for rel in state.country.relations.values())


def _any_disloyal_minister(state) -> bool:
    return any(m.loyalty < 0.5 for m in state.cabinet.ministers)


def _has_opposition(state) -> bool:
    return any(not f.in_coalition for f in state.country.factions)


def _has_active_trade(state) -> bool:
    return any(r.trade_volume > 500 for r in state.country.relations.values())


def _never(state) -> bool:
    """Chain-only events: reachable exclusively via a follow_up."""
    return False


def _fiscal_strain(state) -> bool:
    econ = state.country.economy
    return econ.public_debt_pct > 0.70 or econ.inflation > 0.08


def _labour_pressure(state) -> bool:
    econ = state.country.economy
    return econ.unemployment > 0.13 or econ.inflation > 0.09


def _budget_surplus(state) -> bool:
    return state.country.economy.budget.balance > 300.0


def _weak_state(state) -> bool:
    return state.country.bureaucratic_capacity < 0.6


def _any_bad_relation(state) -> bool:
    return any(r.score < -0.3 for r in state.country.relations.values())


def _neighbour_in_civil_war(state) -> bool:
    return any(c.in_civil_war for c in state.world)


def _shaky_government(state) -> bool:
    return state.stability.value < 0.5


def _has_active_law(state) -> bool:
    return bool(state.legislature.active_laws)


def _own_party(state):
    return next((f for f in state.country.factions
                 if f.id == state.player.faction_id), None)


def _restless_own_party(state) -> bool:
    """The player's own party's leading wing has turned against them."""
    party = _own_party(state)
    if party is None:
        return False
    dom = party.dominant_wing()
    return dom is not None and dom.loyalty < 0.35


def _challenge_face_down(state):
    party = _own_party(state)
    dom = party.dominant_wing() if party else None
    if dom is not None:
        dom.loyalty = max(-1.0, dom.loyalty - 0.08)   # cowed, and resentful


def _challenge_accommodate(state):
    party = _own_party(state)
    dom = party.dominant_wing() if party else None
    if dom is None:
        return
    state.player.ideology_economic += (dom.ideology.economic
                                       - state.player.ideology_economic) * 0.15
    state.player.ideology_social += (dom.ideology.social
                                     - state.player.ideology_social) * 0.15
    dom.loyalty = min(1.0, dom.loyalty + 0.25)


def _challenge_purge(state):
    party = _own_party(state)
    dom = party.dominant_wing() if party else None
    if dom is None:
        return
    dom.strength = max(0.0, dom.strength - 0.15)
    party.normalize_wings()
    for w in party.wings:
        w.loyalty = max(-1.0, w.loyalty - 0.10)
    state.stability.value = max(0.05, state.stability.value - 0.05)


# ── Opposition politics ──────────────────────────────────────────────────

def _shift_party_support(state, own_delta: float, ruling_delta: float = 0.0):
    """Move real electoral support, then restore a coherent national share."""
    own = _own_party(state)
    ruling = next((f for f in state.country.factions
                   if f.id == state.ruling_faction_id), None)
    if own is not None:
        own.support = max(0.01, min(0.85, own.support + own_delta))
    if ruling is not None and ruling is not own:
        ruling.support = max(0.01, min(0.85, ruling.support + ruling_delta))
    total = sum(f.support for f in state.country.factions) or 1.0
    for faction in state.country.factions:
        faction.support /= total


def _opposition_claims_retreat(state):
    from engine import opposition
    _shift_party_support(state, 0.012, -0.008)
    opposition.adjust_credibility(state, 0.025)


def _opposition_offers_alternative(state):
    from engine import opposition
    _shift_party_support(state, 0.007, -0.004)
    opposition.adjust_credibility(state, 0.04)


def _opposition_misses_retreat(state):
    from engine import opposition
    opposition.adjust_credibility(state, -0.01)


def _by_election_national_push(state):
    from engine import opposition
    _shift_party_support(state, 0.014, -0.009)
    opposition.adjust_credibility(state, 0.02)


def _by_election_local_push(state):
    from engine import opposition
    _shift_party_support(state, 0.008, -0.004)
    opposition.adjust_credibility(state, 0.03)


def _by_election_stand_down(state):
    from engine import opposition
    _shift_party_support(state, -0.003, 0.005)
    opposition.adjust_credibility(state, -0.015)


# ── The Vasca question (bespoke Ardenian content) ───────────────────────────
#
# Dorin Vasca — first president, driven out of Vashtera in the Turn of the
# Year, never captured (content/lore.py). This arc is written for Ardenia
# alone and uses its literal faction ids rather than roles: it is a specific
# story about specific parties, not reusable content.
#
#   vasca_stirs                     (real condition, once per campaign)
#     ├─ crackdown ─────┐
#     ├─ lead_it (former_general) ──┤  outcome decided by the security
#     │                             │  services' actual effectiveness
#     │            ┌────────────────┴──→ vasca_crackdown_works ── END
#     │            └───────────────────→ vasca_crackdown_fails
#     │                                    ├─ escalate ──→ vasca_last_stand
#     │                                    └─ pull back ── END (unresolved)
#     ├─ amnesty ───────→ vasca_amnesty_holds ── END (best case)
#     │              └──→ vasca_regroups ──→ vasca_last_stand
#     └─ downplay ──────→ vasca_emboldened ──→ vasca_last_stand
#
# vasca_last_stand resolves three ways, one of which is deliberately no
# resolution at all.

VASCA_MIN_TURN = 8          # the wound should feel recently closed, not raw

# Events written for Ardenia specifically. These are the ONLY events allowed
# to name literal faction ids instead of canonical roles — they are one-off
# stories about particular parties, not reusable content — and every one of
# them must be gated so it cannot fire anywhere else. Section T enforces both
# halves of that bargain.
ARDENIA_ONLY_EVENTS = {
    "vasca_stirs",
    "vasca_crackdown_works",
    "vasca_crackdown_fails",
    "vasca_amnesty_holds",
    "vasca_regroups",
    "vasca_emboldened",
    "vasca_last_stand",
    "vetrenka_friction",
    "vetrenka_crossroads",
    "vetrenka_settled",
    "vetrenka_talks_fail",
    "vetrenka_retaken",
    "vetrenka_rout",
    "vetrenka_partition",
    "vetrenka_normalised",
    "vetrenka_backlash",
}


def _vasca_resolved(state) -> bool:
    return bool(state.campaign_meta.get("vasca_resolved"))


def _mark_vasca_resolved(state, outcome: str):
    state.campaign_meta["vasca_resolved"] = outcome


def _vasca_stirring(state) -> bool:
    """The west starts talking again when the government looks weak enough
    to be worth testing — and never in the opening months."""
    if state.country.id != "ardenia" or not state.player.in_government:
        return False
    if state.turn < VASCA_MIN_TURN or _vasca_resolved(state):
        return False
    return (state.stability.value < 0.65
            or state.player.approval < 0.50
            or state.civil_war_risk > 0.25)


def _insurgency(state, delta: float):
    state.insurgency_pressure = max(0.0, min(1.0, state.insurgency_pressure + delta))


def _security_effectiveness(state) -> float:
    """0..1 — how well the state can actually reach into the west. The
    ministries that would run such an operation, dampened by how much
    authority the government has left."""
    from models.cabinet import CORE_PORTFOLIOS   # noqa: F401  (documents intent)
    scores = []
    for portfolio in ("Interior", "Defense"):
        minister = state.cabinet.get(portfolio)
        scores.append(minister.implementation_quality() if minister else 0.30)
    ministries = sum(scores) / len(scores)
    return max(0.0, min(1.0, ministries * 0.6 + state.stability.value * 0.4))


def _schedule(state, event_id: str, delay: int):
    state.scheduled_events.append(
        {"event_id": event_id, "due_turn": state.turn + delay, "chance": 1.0})


def _vasca_say(state, key: str):
    from engine import flavor
    flavor.say(state, key, region="the west")


# ── Root choices ────────────────────────────────────────────────────────

def _vasca_crackdown(state, bonus: float = 0.0):
    """A sweep of the western districts. Whether it works is decided by the
    security services' real effectiveness, not a coin flip."""
    _vasca_say(state, "vasca_operation")
    odds = min(0.92, _security_effectiveness(state) + bonus)
    if random.random() < odds:
        _schedule(state, "vasca_crackdown_works", 2)
    else:
        _insurgency(state, 0.30)
        _schedule(state, "vasca_crackdown_fails", 2)


def _vasca_lead_personally(state):
    """A former general goes west himself. Better odds, and he owns it."""
    _vasca_crackdown(state, bonus=0.20)


def _vasca_amnesty(state):
    """Terms for the rank and file, nothing for Vasca. Works when there is
    enough public goodwill to make surrender look like sense rather than
    surrender."""
    _vasca_say(state, "vasca_amnesty")
    odds = 0.35 + state.player.approval * 0.5
    if random.random() < odds:
        _insurgency(state, -0.15)
        _schedule(state, "vasca_amnesty_holds", 3)
    else:
        _schedule(state, "vasca_regroups", 4)


def _vasca_downplay(state):
    _insurgency(state, 0.15)
    _schedule(state, "vasca_emboldened", 4)


# ── Second-tier outcomes ────────────────────────────────────────────────

def _vasca_taken(state):
    _insurgency(state, -0.45)
    _mark_vasca_resolved(state, "captured")
    _vasca_say(state, "vasca_captured")


def _vasca_amnesty_worked(state):
    _insurgency(state, -0.25)
    _mark_vasca_resolved(state, "isolated")
    _vasca_say(state, "vasca_isolated")


def _vasca_backlash(state):
    _insurgency(state, 0.20)
    state.stability.value = max(0.05, state.stability.value - 0.04)


def _vasca_pull_back(state):
    """Stop digging. The remnant survives and so does the question."""
    _insurgency(state, 0.05)


def _vasca_grows(state):
    _insurgency(state, 0.20)


# ── Resolution ──────────────────────────────────────────────────────────

def _vasca_storm(state):
    """He is found dead afterwards. Nobody agrees how, and nobody ever
    will — the arc's most deliberately unresolved resolution."""
    _insurgency(state, -0.40)
    _mark_vasca_resolved(state, "dead")
    _vasca_say(state, "vasca_dead")


def _vasca_exile(state):
    _insurgency(state, -0.35)
    _mark_vasca_resolved(state, "exiled")
    _vasca_say(state, "vasca_exiled")


def _vasca_unresolved(state):
    """No ending. The west stays the west."""
    _insurgency(state, 0.10)
    _vasca_say(state, "vasca_unresolved")


# ── Vetrenka: the frozen conflict (bespoke Ardenian content) ────────────────
#
# The coastal region Ardenia lost in 1992 and has never recognised losing
# (content/lore.py). Two layers, deliberately different in rhythm from the
# Vasca arc: a RECURRING friction event that never resolves anything, and
# one pivotal chain that finally can — because that is what a frozen
# conflict actually feels like to govern.
#
#   vetrenka_friction        (repeatable, cooldown-gated, 3 incident flavours)
#        …after enough of them…
#   vetrenka_crossroads      (once, needs FRICTION_BEFORE_CROSSROADS incidents)
#     ├─ settlement ─→ vetrenka_talks_open ─┬─→ vetrenka_settled     (closed)
#     │                                     └─→ vetrenka_talks_fail  (worse than before)
#     ├─ reassert ───→ vetrenka_offensive ──┬─→ vetrenka_retaken     (won, and holding it)
#     │                                     └─→ vetrenka_rout        (Krasova comes in)
#     └─ formalise ──→ vetrenka_partition ──┬─→ vetrenka_normalised  (it becomes ordinary)
#                                           └─→ vetrenka_backlash    (the country doesn't forgive it)
#
# The cheapest path is also the default one, so a government that never
# engages with Vetrenka lets the line harden by inattention — and then finds
# out whether the country will wear it.

FRICTION_BEFORE_CROSSROADS = 3
VETRENKA_INCIDENTS_KEY = "vetrenka_incidents"
VETRENKA_STATUS_KEY = "vetrenka_status"
KRASOVA = "krasova"          # the separatists' backer (lore.CORE_SUCCESSOR_STATE)


def _vetrenka_status(state):
    return state.campaign_meta.get(VETRENKA_STATUS_KEY)


def _vetrenka_open(state) -> bool:
    """True while the conflict is still frozen — every path out of it sets a
    status, and nothing here fires again afterwards."""
    return (state.country.id == "ardenia"
            and state.player.in_government
            and _vetrenka_status(state) is None)


def _vetrenka_friction_due(state) -> bool:
    return _vetrenka_open(state)


def _vetrenka_crossroads_ready(state) -> bool:
    """Nothing shifts until the line of contact has cost the government
    something several times over."""
    return (_vetrenka_open(state)
            and state.campaign_meta.get(VETRENKA_INCIDENTS_KEY, 0) >= FRICTION_BEFORE_CROSSROADS)


def _vetrenka_say(state, key: str):
    from engine import flavor
    from content import lore
    flavor.say(state, key, region=lore.SEPARATIST_REGION)


def _count_incident(state):
    state.campaign_meta[VETRENKA_INCIDENTS_KEY] = \
        state.campaign_meta.get(VETRENKA_INCIDENTS_KEY, 0) + 1
    _vetrenka_say(state, "vetrenka_incident")


def _set_vetrenka(state, status: str, dispatch: str):
    state.campaign_meta[VETRENKA_STATUS_KEY] = status
    # The regional layer follows explicit political outcomes; sovereignty is
    # never flipped by its passive monthly decimals. Values are immediate
    # post-crisis conditions and will subsequently move through the ordinary
    # deterministic regional pulse.
    region = getattr(state, "regions", {}).get("vetrenka")
    if region is not None:
        outcome = {
            "settled": ("autonomous", "postwar_framework", 0.28, 0.48),
            "talks_failed": ("separatist", "unsettled_ceasefire", 0.03, 0.94),
            "retaken": ("state", "occupation_and_return", 0.32, 0.76),
            "routed": ("separatist", "worsened_ceasefire", 0.02, 0.98),
            "partitioned": ("separatist", "hardened_partition", 0.03, 0.58),
            "partitioned_contested": ("separatist", "contested_partition", 0.03, 0.82),
        }.get(status)
        if outcome is not None:
            region.control, region.issue_id, region.state_reach, region.pressure = outcome
    _vetrenka_say(state, dispatch)


# ── Recurring friction ──────────────────────────────────────────────────

def _vetrenka_absorb(state):
    _count_incident(state)


def _vetrenka_respond(state):
    _count_incident(state)
    _insurgency(state, 0.06)


def _vetrenka_protest(state):
    _count_incident(state)


# ── The crossroads ──────────────────────────────────────────────────────

def _vetrenka_open_talks(state):
    _vetrenka_say(state, "vetrenka_talks")
    # Mediation works when the government has the standing to sell a
    # compromise at home and the country is calm enough to try.
    #
    # Measured across 25 campaigns, a government arrives here with approval
    # 0.47-0.50 and stability 0.41-0.51 — a narrow band. So this reads
    # DEVIATION from that ordinary case rather than the raw values: a typical
    # government gets a shade better than a coin flip, and only a government
    # that has actually built something gets good odds.
    odds = (0.55
            + (state.player.approval - 0.49) * 1.4
            + (state.stability.value - 0.48) * 0.7)
    odds = max(0.12, min(0.90, odds))
    if random.random() < odds:
        _schedule(state, "vetrenka_settled", 4)
    else:
        _schedule(state, "vetrenka_talks_fail", 3)


def _vetrenka_launch_offensive(state):
    _vetrenka_say(state, "vetrenka_offensive")
    # An army that was pushed out of the region a year ago, against a
    # separatist force with a foreign patron. The odds are not good, and
    # they turn on whether the state can actually fight. Centred on the ~0.25
    # a typical government reaches (this is a war you already lost once), and
    # steep enough that a genuinely well-run Interior and Defense is felt.
    odds = 0.25 + (_security_effectiveness(state) - 0.25) * 1.8
    odds = max(0.08, min(0.70, odds))
    if random.random() < odds:
        _schedule(state, "vetrenka_retaken", 3)
    else:
        _schedule(state, "vetrenka_rout", 2)


def _vetrenka_formalise(state):
    _schedule(state, "vetrenka_partition", 2)


# ── Endings ─────────────────────────────────────────────────────────────

def _vetrenka_settle(state):
    _insurgency(state, -0.20)
    _set_vetrenka(state, "settled", "vetrenka_settled")


def _vetrenka_talks_failed(state):
    _insurgency(state, 0.10)
    state.stability.value = max(0.05, state.stability.value - 0.03)
    _set_vetrenka(state, "talks_failed", "vetrenka_talks_failed")


def _vetrenka_won(state):
    _insurgency(state, 0.25)          # holding it is its own problem
    _set_vetrenka(state, "retaken", "vetrenka_retaken")


def _vetrenka_lost(state):
    _insurgency(state, 0.35)
    state.stability.value = max(0.05, state.stability.value - 0.08)
    _set_vetrenka(state, "routed", "vetrenka_rout")


def _vetrenka_partitioned(state):
    """The line hardens. Whether the country wears it is not a question of
    whether the nationalists are angry — they will be, always, that is what
    they are for — but of whether this government has the standing to make an
    unpopular thing boring, against a bench big enough to keep it in the news.
    Only a genuinely secure government gets away with it quietly."""
    _insurgency(state, -0.10)
    _vetrenka_say(state, "vetrenka_partition")
    total = sum(f.seats for f in state.country.factions) or 1
    natcon = next((f for f in state.country.factions
                   if f.id == "national_conservatives"), None)
    opposition_bench = (natcon.seats / total) if natcon else 0.0
    standing = state.player.approval + state.stability.value * 0.5 - opposition_bench
    if standing > 0.70:
        _schedule(state, "vetrenka_normalised", 5)
    else:
        _schedule(state, "vetrenka_backlash", 4)


def _vetrenka_normal(state):
    _set_vetrenka(state, "partitioned", "vetrenka_normalised")


def _vetrenka_backlash_lands(state):
    state.stability.value = max(0.05, state.stability.value - 0.05)
    _set_vetrenka(state, "partitioned_contested", "vetrenka_backlash")


# ── The schemer arc (a multi-step character story) ──────────────────────────
#
# models/cabinet.py already grows a schemer's ambition every turn and
# turn.py fires a minister_restless warning past threat 0.5 — a mechanical
# arc with no narrative resolution. These helpers give it one. The arc is
# country-neutral: it binds to whichever cabinet minister carries the
# "schemer" trait when each step fires, and every step degrades to a quiet
# no-op if that minister has already resigned or been dismissed mid-arc.

def _arc_schemer(state):
    """The most dangerous schemer currently in cabinet, or None."""
    schemers = [m for m in state.cabinet.ministers if m.trait == "schemer"]
    if not schemers:
        return None
    return max(schemers, key=lambda m: m.threat_level())


def _schemer_plotting(state) -> bool:
    """Entry condition: the existing restless-minister threshold, but only
    for a schemer — their growth curve is the arc's fuse."""
    if not state.player.in_government:
        return False
    m = _arc_schemer(state)
    return m is not None and m.threat_level() > 0.5


def _arc_say(state, key: str):
    m = _arc_schemer(state)
    if m is None:
        return None
    from engine import flavor   # lazy: content -> engine only at apply time
    flavor.say(state, key, minister=m.name, portfolio=m.portfolio)
    return m


def _schemer_noted(state):
    _arc_say(state, "schemer_arc")


def _schemer_buy_off(state):
    m = _arc_say(state, "schemer_bought")
    if m is not None:
        # Loyal now — and the ambition that made them dangerous is intact,
        # so the resentment keeps ticking underneath (schemer growth
        # continues; the arc can re-arm years later).
        m.loyalty = min(0.95, m.loyalty + 0.35)


def _schemer_resign(state):
    m = _arc_schemer(state)
    if m is None:
        return
    from engine import cabinet_ops   # lazy, same precedent as loader
    _arc_say(state, "schemer_neutralized")
    cabinet_ops.dismiss(state, m.portfolio)


def _schemer_crush(state):
    m = _arc_schemer(state)
    if m is None:
        return
    from engine import cabinet_ops
    _arc_say(state, "schemer_neutralized")
    cabinet_ops.dismiss(state, m.portfolio)
    state.stability.value = max(0.05, state.stability.value - 0.04)


def _schemer_expose(state):
    m = _arc_schemer(state)
    if m is None:
        return
    from engine import cabinet_ops
    _arc_say(state, "schemer_neutralized")
    cabinet_ops.dismiss(state, m.portfolio)


def _schemer_ascend(state):
    m = _arc_say(state, "schemer_ascendant")
    if m is None:
        return
    party = _own_party(state)
    dom = party.dominant_wing() if party else None
    if dom is not None:
        # Their allies inside your party are emboldened — the formal
        # leadership challenge this schedules lands on softened ground.
        dom.loyalty = max(-1.0, dom.loyalty - 0.15)


def _bg(bg_id: str):
    """requires-callable: option open only to a given character background."""
    def check(state) -> bool:
        return state.campaign_meta.get("background") == bg_id
    return check


def _max_social(x: float):
    """requires-callable: option open only to authoritarian-leaning leaders."""
    def check(state) -> bool:
        return state.player.ideology_social <= x
    return check


def event_catalog() -> list:
    """
    Returns a fresh set of authored events. Called fresh each time (see
    engine/events.py) so firing/resolving one never mutates a shared object.
    """
    return [
        EventDef(
            id="labour_unrest_spreads",
            title="Labour Unrest Spreads",
            description="Strikes and demonstrations are building around a grievance that's gone "
                        "unaddressed too long. The Interior Ministry wants a decision.",
            category="Faction",
            condition=_has_serious_grievance,
            chance=0.15,
            portfolio="Interior",
            default_option_id="ignore",
            options=[
                EventOption(
                    id="crackdown", label="Crack down on the unrest", pc_cost=8,
                    description="Riot police clear the demonstrations. Order returns fast, at a cost "
                               "to your standing with the streets and the wider public.",
                    effects=LawEffect(
                        faction_loyalty_deltas={ROLE_LABOUR: -0.15, ROLE_REFORM: -0.05,
                                                ROLE_NATIONALIST: 0.06},
                        modifiers=[Modifier(
                            id="unrest_crackdown_approval", source="Labour Unrest Spreads",
                            target="approval_bias", magnitude=-0.03,
                            onset_delay=0, ramp_duration=1, hold_duration=6, decay_duration=4,
                            portfolio="Interior",
                        )],
                    ),
                ),
                EventOption(
                    id="negotiate", label="Negotiate with organizers", pc_cost=14,
                    description="Open a direct channel with strike leaders and offer concessions. "
                               "Costs the treasury, buys goodwill.",
                    effects=LawEffect(
                        budget_expenditure_delta=90.0,
                        faction_loyalty_deltas={ROLE_LABOUR: 0.14, ROLE_AGRARIAN: 0.04},
                    ),
                ),
                EventOption(
                    id="ignore", label="Let it run its course", pc_cost=0,
                    description="You take no action. The unrest simmers a while longer and public "
                               "patience wears thin.",
                    effects=LawEffect(
                        faction_loyalty_deltas={ROLE_LABOUR: -0.04},
                        modifiers=[Modifier(
                            id="unrest_ignore_approval", source="Labour Unrest Spreads",
                            target="approval_bias", magnitude=-0.015,
                            onset_delay=0, ramp_duration=1, hold_duration=4, decay_duration=2,
                        )],
                    ),
                ),
            ],
        ),

        EventDef(
            id="border_incident",
            title="Shots on the Ceasefire Line",
            description="A patrol traded fire across the line last night. Nobody died, both "
                        "sides say the other started it, and the ceasefire nobody signed in "
                        "good faith held by about forty minutes. Foreign Affairs is waiting "
                        "on your response.",
            category="Diplomatic",
            condition=_any_cool_relation,
            chance=0.10,
            portfolio="Foreign Affairs",
            default_option_id="protest_formally",
            options=[
                EventOption(
                    id="protest_formally", label="Lodge a formal protest", pc_cost=6,
                    description="A stern note through the usual channels. Firm, restrained, "
                               "and unlikely to satisfy anyone who lost a cousin in 1992.",
                    # Aimed at whichever neighbour the standoff is actually
                    # with (engine/events.py: resolve_relation_target).
                    effects=LawEffect(), relation_deltas={TARGET_COOLEST: -0.04},
                ),
                EventOption(
                    id="escalate", label="Name them from the podium", pc_cost=5,
                    description="Say out loud what everyone believes about who armed the "
                               "separatists. The chamber will love it. The embassy will not.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_NATIONALIST: 0.05}),
                    relation_deltas={TARGET_COOLEST: -0.12},
                ),
                EventOption(
                    id="de_escalate", label="Seek quiet de-escalation", pc_cost=10,
                    description="Back-channel talks, no cameras, no communiqué. Cheaper than "
                               "the alternative and impossible to claim credit for.",
                    effects=LawEffect(), relation_deltas={TARGET_COOLEST: 0.06},
                ),
            ],
        ),

        EventDef(
            id="cabinet_corruption_expose",
            title="Cabinet Corruption Exposé",
            description="An investigative report alleges a minister used their office for personal "
                        "gain. The story is spreading fast.",
            category="Cabinet",
            condition=_any_disloyal_minister,
            chance=0.10,
            default_option_id="defend",
            options=[
                EventOption(
                    id="defend", label="Publicly defend the minister", pc_cost=10,
                    description="You back your minister publicly. If the story holds up, this could "
                               "look very bad later.",
                    effects=LawEffect(modifiers=[Modifier(
                        id="expose_defend_approval", source="Cabinet Corruption Exposé",
                        target="approval_bias", magnitude=-0.02,
                        onset_delay=0, ramp_duration=1, hold_duration=8, decay_duration=4,
                    )]),
                ),
                EventOption(
                    id="quiet_resignation", label="Ask for a quiet resignation", pc_cost=6,
                    description="A minister steps down before the story can grow. A brief "
                               "embarrassment, then it passes.",
                    effects=LawEffect(modifiers=[Modifier(
                        id="expose_resign_approval", source="Cabinet Corruption Exposé",
                        target="approval_bias", magnitude=-0.01,
                        onset_delay=0, ramp_duration=1, hold_duration=3, decay_duration=2,
                    )]),
                ),
                EventOption(
                    id="launch_inquiry", label="Launch an independent inquiry", pc_cost=12,
                    description="Slower, more credible, and out of your hands once it starts.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_REFORM: 0.04,
                                                               ROLE_NATIONALIST: 0.03}),
                ),
            ],
        ),

        EventDef(
            id="bumper_harvest",
            title="Bumper Harvest",
            description="An unusually strong harvest has left the country with a real, if modest, "
                        "surplus. A rare piece of good news for the Economy Ministry to manage.",
            category="Economic",
            condition=lambda state: True,
            chance=0.06,
            portfolio="Economy",
            default_option_id="stockpile",
            options=[
                EventOption(
                    id="stockpile", label="Stockpile the surplus", pc_cost=0,
                    description="Bank the gains against leaner years ahead.",
                    effects=LawEffect(one_time_debt_pct_delta=-0.015),
                ),
                EventOption(
                    id="export", label="Export the surplus", pc_cost=4,
                    description="Sell abroad for quick revenue.",
                    effects=LawEffect(budget_revenue_delta=150.0,
                                      faction_loyalty_deltas={ROLE_AGRARIAN: 0.05}),
                ),
                EventOption(
                    id="subsidize", label="Subsidize consumer prices", pc_cost=6,
                    description="Pass the windfall straight to households.",
                    effects=LawEffect(inflation_delta=-0.003,
                                      faction_loyalty_deltas={ROLE_LABOUR: 0.06,
                                                              ROLE_AGRARIAN: 0.04}),
                ),
            ],
        ),

        EventDef(
            id="currency_speculators_circle",
            title="Currency Speculators Circle",
            description="Investors are testing the currency's resolve, betting on either inflation "
                        "or debt forcing your hand. Finance wants direction.",
            category="Economic",
            condition=lambda state: (state.country.economy.inflation > 0.05
                                     or state.country.economy.public_debt_pct > 0.6),
            chance=0.12,
            portfolio="Finance",
            default_option_id="do_nothing",
            options=[
                EventOption(
                    id="rate_hike", label="Raise interest rates sharply", pc_cost=10,
                    description="Defends the currency, chokes growth.",
                    effects=LawEffect(gdp_growth_delta=-0.006, inflation_delta=-0.01),
                ),
                EventOption(
                    id="capital_controls", label="Impose capital controls", pc_cost=14,
                    description="Blunt and unpopular with investors, but it buys room to breathe.",
                    effects=LawEffect(
                        one_time_debt_pct_delta=-0.01,
                        faction_loyalty_deltas={ROLE_NATIONALIST: -0.05,
                                                ROLE_REFORM: -0.04},
                    ),
                ),
                EventOption(
                    id="do_nothing", label="Ride it out", pc_cost=0,
                    description="Let the market find its own level. Risky if it doesn't stop on its own.",
                    effects=LawEffect(inflation_delta=0.006),
                ),
            ],
        ),

        EventDef(
            id="rivals_scandal",
            title="A Rival's Scandal",
            description="An opposition figure has been caught in an embarrassing scandal of their "
                        "own. How you handle it is entirely your call.",
            category="Faction",
            condition=_has_opposition,
            chance=0.08,
            default_option_id="stay_above_it",
            options=[
                EventOption(
                    id="press_advantage", label="Press the political advantage", pc_cost=8,
                    description="Hammer the story in the press. Good for you, ugly politics.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_REFORM: 0.05},
                                      faction_power_deltas={ROLE_NATIONALIST: -0.03}),
                ),
                EventOption(
                    id="stay_above_it", label="Stay above the fray", pc_cost=0,
                    description="Say nothing. Voters may reward the restraint — or may not notice at all.",
                    effects=LawEffect(modifiers=[Modifier(
                        id="rival_scandal_restraint_approval", source="A Rival's Scandal",
                        target="approval_bias", magnitude=0.008,
                        onset_delay=0, ramp_duration=1, hold_duration=6, decay_duration=3,
                    )]),
                ),
            ],
        ),

        EventDef(
            id="trade_route_disruption",
            title="Trade Route Disruption",
            description="The corridors the Union built all run the wrong way for an "
                        "independent country, and one of them has just closed. Your busiest "
                        "trade relationship is rippling. Someone will feel the pinch.",
            category="Economic",
            condition=_has_active_trade,
            chance=0.09,
            portfolio="Economy",
            default_option_id="pass_to_consumers",
            options=[
                EventOption(
                    id="absorb_cost", label="Absorb the cost domestically", pc_cost=6,
                    description="Subsidize affected industries directly rather than let supply "
                               "chains break.",
                    effects=LawEffect(budget_expenditure_delta=60.0,
                                      faction_loyalty_deltas={ROLE_NATIONALIST: 0.03}),
                ),
                EventOption(
                    id="pass_to_consumers", label="Let prices adjust", pc_cost=0,
                    description="Let the market absorb the shock. Cheaper for the state, harder on "
                               "households.",
                    effects=LawEffect(inflation_delta=0.004,
                                      faction_loyalty_deltas={ROLE_LABOUR: -0.05}),
                ),
            ],
        ),

        # ═════════════════ Economic ═════════════════
        EventDef(
            id="bank_run",
            title="Run on the Provincial Bank",
            description="Depositors are queueing around the block at one of the country's larger "
                        "banks. If the panic spreads to the rest of the system, this stops being "
                        "one bank's problem.",
            category="Economic",
            condition=_fiscal_strain, chance=0.08, portfolio="Finance",
            default_option_id="let_it_fail",
            options=[
                EventOption(
                    id="guarantee", label="Guarantee all deposits", pc_cost=10,
                    description="The treasury stands behind every account. Expensive, but the "
                               "queues disperse by evening.",
                    effects=LawEffect(budget_expenditure_delta=180.0,
                                      modifiers=[Modifier(
                                          id="bank_guarantee_calm", source="Run on the Provincial Bank",
                                          target="approval_bias", magnitude=0.01,
                                          onset_delay=0, ramp_duration=1, hold_duration=4, decay_duration=2)]),
                ),
                EventOption(
                    id="arrange_rescue", label="Arrange a private rescue", pc_cost=14,
                    description="Twist the arms of the big banking houses to absorb their failing "
                               "rival. Cheaper for the state; the bankers will remember the favour "
                               "they did you.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_BUSINESS: 0.06,
                                                               ROLE_ESTABLISHMENT: 0.04,
                                                               ROLE_REFORM: 0.03}),
                ),
                EventOption(
                    id="let_it_fail", label="Let it fail", pc_cost=0,
                    description="Depositors take the loss and the panic burns through the economy.",
                    effects=LawEffect(gdp_growth_delta=-0.005,
                                      faction_loyalty_deltas={ROLE_LABOUR: -0.08,
                                                              ROLE_BUSINESS: -0.04}),
                ),
                EventOption(
                    id="stake_reputation", label="Stake your reputation on the numbers", pc_cost=5,
                    description="You ran monetary policy for a decade. Go on television with the "
                               "balance sheet and dare the panic to argue with you.",
                    requires=_bg("economist"),
                    effects=LawEffect(modifiers=[Modifier(
                        id="bankrun_credibility", source="Run on the Provincial Bank",
                        target="inflation", magnitude=-0.005,
                        onset_delay=0, ramp_duration=1, hold_duration=4, decay_duration=2)]),
                ),
            ],
        ),
        EventDef(
            id="strike_wave",
            title="Strike Wave",
            description="Walkouts are spreading plant to plant — pay packets can't keep up, and the "
                        "unions smell weakness. The next few days decide whether this stays economic "
                        "or becomes political.",
            category="Economic",
            condition=_labour_pressure, chance=0.10, portfolio="Economy",
            default_option_id="hold_firm",
            options=[
                EventOption(
                    id="wage_deal", label="Negotiate a wage deal", pc_cost=12,
                    description="Buy industrial peace with a settlement. Costs the budget, calms "
                               "the shop floor.",
                    effects=LawEffect(budget_expenditure_delta=140.0,
                                      faction_loyalty_deltas={ROLE_LABOUR: 0.10,
                                                              ROLE_BUSINESS: -0.04}),
                ),
                EventOption(
                    id="hold_firm", label="Hold firm", pc_cost=0,
                    description="No concessions under pressure. The unions may fold — or escalate.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_LABOUR: -0.06,
                                                              ROLE_NATIONALIST: 0.04}),
                    follow_up={"event_id": "general_strike", "delay": 3, "chance": 0.6},
                ),
                EventOption(
                    id="send_police", label="Clear the picket lines", pc_cost=8,
                    description="Order and open gates by the weekend — and a wound that will fester.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_LABOUR: -0.14,
                                                              ROLE_NATIONALIST: 0.06}),
                    follow_up={"event_id": "general_strike", "delay": 2, "chance": 0.4},
                ),
                EventOption(
                    id="one_of_their_own", label="Speak to them as one of their own", pc_cost=4,
                    description="You carried a union card before you carried a red box. Walk in "
                               "without minders and settle it the old way.",
                    requires=_bg("union_leader"),
                    # The approval bump is role-independent on purpose: the
                    # country sees a strike settled in person even where no
                    # organised labour bloc exists to be grateful.
                    effects=LawEffect(faction_loyalty_deltas={ROLE_LABOUR: 0.12},
                                      modifiers=[Modifier(
                                          id="strike_settled_in_person", source="Strike Wave",
                                          target="approval_bias", magnitude=0.012,
                                          onset_delay=0, ramp_duration=1, hold_duration=4,
                                          decay_duration=2)]),
                ),
            ],
        ),
        EventDef(
            id="general_strike",
            title="General Strike",
            description="It happened: the unions have called everyone out. Ports, rails, mills — "
                        "the country is standing still, and everyone remembers how you handled the "
                        "first wave.",
            category="Economic",
            condition=_never, chance=0.0, portfolio="Interior",
            default_option_id="wait_out",
            options=[
                EventOption(
                    id="capitulate", label="Concede the unions' demands", pc_cost=8,
                    description="End it today at the treasury's expense.",
                    effects=LawEffect(budget_expenditure_delta=260.0,
                                      faction_loyalty_deltas={ROLE_LABOUR: 0.12,
                                                              ROLE_BUSINESS: -0.05}),
                ),
                EventOption(
                    id="wait_out", label="Wait them out", pc_cost=0,
                    description="Strikers don't get paid either. A grinding month for everyone.",
                    effects=LawEffect(gdp_growth_delta=-0.008,
                                      modifiers=[Modifier(
                                          id="general_strike_approval", source="General Strike",
                                          target="approval_bias", magnitude=-0.03,
                                          onset_delay=0, ramp_duration=1, hold_duration=4, decay_duration=3)]),
                ),
                EventOption(
                    id="emergency_powers", label="Declare essential-services orders", pc_cost=15,
                    description="Force the ports and power stations open by decree. Effective, "
                               "authoritarian, unforgotten.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_LABOUR: -0.12,
                                                              ROLE_REFORM: -0.06,
                                                              ROLE_NATIONALIST: 0.08}),
                ),
                EventOption(
                    id="martial_ports", label="Put the ports under military control", pc_cost=18,
                    description="Not a review, not an order — soldiers on the docks by morning. "
                               "Only a leader of your temperament would dare.",
                    requires=_max_social(-0.2),
                    effects=LawEffect(gdp_growth_delta=0.002,
                                      faction_loyalty_deltas={ROLE_LABOUR: -0.16,
                                                              ROLE_REFORM: -0.10,
                                                              ROLE_NATIONALIST: 0.10},
                                      modifiers=[Modifier(
                                          id="martial_ports_approval", source="General Strike",
                                          target="approval_bias", magnitude=-0.015,
                                          onset_delay=1, ramp_duration=2, hold_duration=6,
                                          decay_duration=3)]),
                ),
            ],
        ),
        EventDef(
            id="budget_windfall",
            title="Revenue Windfall",
            description="The mid-year figures are in and the treasury has collected meaningfully "
                        "more than forecast. Everyone in cabinet has a plan for it by lunchtime.",
            category="Economic",
            condition=_budget_surplus, chance=0.07, portfolio="Finance",
            default_option_id="pay_down_debt",
            options=[
                EventOption(
                    id="pay_down_debt", label="Pay down debt", pc_cost=0,
                    description="Quietly responsible.",
                    effects=LawEffect(one_time_debt_pct_delta=-0.02),
                ),
                EventOption(
                    id="public_works", label="Announce public works", pc_cost=6,
                    description="Visible cranes in every district by spring.",
                    effects=LawEffect(budget_expenditure_delta=120.0,
                                      modifiers=[Modifier(
                                          id="windfall_works_approval", source="Revenue Windfall",
                                          target="approval_bias", magnitude=0.015,
                                          onset_delay=1, ramp_duration=2, hold_duration=6, decay_duration=3)]),
                ),
                EventOption(
                    id="tax_rebate", label="A one-off tax rebate", pc_cost=6,
                    description="Cheques in the post with the government's compliments.",
                    effects=LawEffect(budget_revenue_delta=-100.0,
                                      faction_loyalty_deltas={ROLE_REFORM: 0.05,
                                                              ROLE_NATIONALIST: 0.05}),
                ),
            ],
        ),

        # ═════════════════ Political ═════════════════
        EventDef(
            id="defection_drama",
            title="A Deputy Crosses the Floor",
            description="A sitting deputy has renounced their party whip live on the evening news, "
                        "citing 'a crisis of conscience'. Their old party wants blood; every other "
                        "party wants the seat.",
            category="Political",
            condition=_has_opposition, chance=0.06, audience="any",
            default_option_id="stay_out",
            options=[
                EventOption(
                    id="woo_defector", label="Court the defector", pc_cost=8,
                    description="A warm handshake for the cameras — and their vote, most days.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_REFORM: 0.04,
                                                              ROLE_NATIONALIST: -0.06}),
                ),
                EventOption(
                    id="stay_out", label="Stay out of it", pc_cost=0,
                    description="Party quarrels are best watched from a safe distance.",
                    effects=LawEffect(),
                ),
            ],
        ),
        EventDef(
            id="government_policy_retreat",
            title="The Government Retreats",
            description="After weeks of pressure, the government has abandoned one of its "
                        "headline proposals. You cannot issue orders from opposition — but you "
                        "can decide what political meaning the retreat will carry.",
            category="Opposition",
            condition=lambda state: not state.player.in_government,
            chance=0.08, cooldown=10, audience="opposition",
            default_option_id="let_pass",
            options=[
                EventOption(
                    id="claim_victory", label="Claim the retreat as your victory", pc_cost=6,
                    description="Put your front bench on every broadcast and argue that sustained "
                                "opposition forced the reversal.",
                    on_apply=_opposition_claims_retreat,
                ),
                EventOption(
                    id="publish_alternative", label="Publish the alternative", pc_cost=8,
                    description="Use the opening to explain what your party would do instead. A "
                                "slower gain, but a stronger claim to be ready for office.",
                    on_apply=_opposition_offers_alternative,
                ),
                EventOption(
                    id="let_pass", label="Let the government own its confusion", pc_cost=0,
                    description="Say little and trust voters to notice. Most will not.",
                    on_apply=_opposition_misses_retreat,
                ),
            ],
        ),
        EventDef(
            id="opposition_by_election",
            title="A By-Election Opening",
            description="A vacant constituency has produced an unexpected contest. This is not "
                        "a decision about the country; it is a test of how your opposition party "
                        "spends its limited people, money, and attention.",
            category="Opposition",
            condition=lambda state: (not state.player.in_government
                                     and (_own_party(state) is not None)
                                     and _own_party(state).seats > 0),
            chance=0.06, cooldown=14, audience="opposition",
            default_option_id="stand_down",
            options=[
                EventOption(
                    id="national_push", label="Turn it into a national referendum", pc_cost=10,
                    description="Flood the district with organisers and make the government defend "
                                "its national record.",
                    on_apply=_by_election_national_push,
                ),
                EventOption(
                    id="local_push", label="Run a disciplined local campaign", pc_cost=6,
                    description="Keep the leader away, select a credible local voice, and build "
                                "the organisation for the general election.",
                    on_apply=_by_election_local_push,
                ),
                EventOption(
                    id="stand_down", label="Conserve resources", pc_cost=0,
                    description="Save the war chest for the national contest and surrender the "
                                "initiative today.",
                    on_apply=_by_election_stand_down,
                ),
            ],
        ),
        EventDef(
            id="corruption_expose_media",
            title="The Procurement Files",
            description="A newspaper has published a cache of documents suggesting ministry "
                        "contracts have been steered to friends of officials for years. The story "
                        "has a name, a logo, and no intention of going away.",
            category="Political",
            condition=_weak_state, chance=0.08, portfolio="Justice",
            default_option_id="ride_it_out",
            options=[
                EventOption(
                    id="full_inquiry", label="Order a full public inquiry", pc_cost=12,
                    description="Let the chips fall. Credible — and once it starts, it doesn't "
                               "answer to you.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_REFORM: 0.05,
                                                              ROLE_ESTABLISHMENT: -0.03}),
                    follow_up={"event_id": "corruption_trial", "delay": 5, "chance": 1.0},
                ),
                EventOption(
                    id="sack_officials", label="Sack the named officials", pc_cost=8,
                    description="Swift, visible, and conveniently shallow.",
                    effects=LawEffect(modifiers=[Modifier(
                        id="procurement_sack_approval", source="The Procurement Files",
                        target="approval_bias", magnitude=0.008,
                        onset_delay=0, ramp_duration=1, hold_duration=3, decay_duration=2)]),
                ),
                EventOption(
                    id="ride_it_out", label="Ride it out", pc_cost=0,
                    description="Newspapers need a new front page every day. Eventually.",
                    effects=LawEffect(modifiers=[Modifier(
                        id="procurement_silence_approval", source="The Procurement Files",
                        target="approval_bias", magnitude=-0.02,
                        onset_delay=0, ramp_duration=2, hold_duration=6, decay_duration=3)]),
                ),
                EventOption(
                    id="prosecute_yourself", label="Take the brief yourself", pc_cost=10,
                    description="You argued before the high court for twenty years. Stand at the "
                               "podium, walk the country through the evidence, and make the case "
                               "no hired counsel could.",
                    requires=_bg("lawyer"),
                    effects=LawEffect(faction_loyalty_deltas={ROLE_REFORM: 0.06,
                                                              ROLE_ESTABLISHMENT: -0.03},
                                      modifiers=[Modifier(
                                          id="procurement_lawyer_credibility",
                                          source="The Procurement Files",
                                          target="approval_bias", magnitude=0.02,
                                          onset_delay=0, ramp_duration=2, hold_duration=6,
                                          decay_duration=3)]),
                    follow_up={"event_id": "corruption_trial", "delay": 4, "chance": 1.0},
                ),
            ],
        ),
        EventDef(
            id="corruption_trial",
            title="The Procurement Trial Verdict",
            description="The inquiry you ordered has ended in court, and the verdict lands today. "
                        "Senior officials are going to prison — including two appointed under your "
                        "government's watch.",
            category="Political",
            condition=_never, chance=0.0, portfolio="Justice",
            default_option_id="accept_verdict",
            options=[
                EventOption(
                    id="accept_verdict", label="Welcome the verdict", pc_cost=0,
                    description="Justice done, whatever it costs the government's friends.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_REFORM: 0.06,
                                                               ROLE_LABOUR: 0.04},
                                      modifiers=[Modifier(
                                          id="trial_credibility", source="The Procurement Trial",
                                          target="approval_bias", magnitude=0.015,
                                          onset_delay=0, ramp_duration=2, hold_duration=8, decay_duration=4)]),
                ),
                EventOption(
                    id="pardon_quietly", label="Arrange quiet pardons", pc_cost=15,
                    description="Loyalty repaid — if it stays quiet, which these things never do.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_REFORM: -0.08,
                                                               ROLE_LABOUR: -0.06},
                                      modifiers=[Modifier(
                                          id="pardon_scandal", source="The Procurement Trial",
                                          target="approval_bias", magnitude=-0.03,
                                          onset_delay=1, ramp_duration=2, hold_duration=8, decay_duration=4)]),
                ),
            ],
        ),
        EventDef(
            id="judicial_crisis",
            title="The Court Strikes Back",
            description="The high court has ruled a pillar of the government's legislative programme "
                        "unconstitutional in part. The justices are daring you to make it a fight.",
            category="Political",
            condition=_has_active_law, chance=0.05, portfolio="Justice",
            default_option_id="comply",
            options=[
                EventOption(
                    id="comply", label="Comply with the ruling", pc_cost=0,
                    description="Rule of law means losing gracefully sometimes.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_REFORM: 0.04},
                                      budget_revenue_delta=-60.0),
                ),
                EventOption(
                    id="attack_court", label="Denounce the court", pc_cost=10,
                    description="'Unelected judges against the people's government.' The base loves "
                               "it; the institutions do not.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_NATIONALIST: 0.05,
                                                               ROLE_REFORM: -0.07}),
                ),
            ],
        ),
        EventDef(
            id="media_empire",
            title="The Chairman's Offer",
            description="The owner of the country's largest media group requests a private dinner. "
                        "Over dessert he offers 'a fairer hearing' for the government — and mentions, "
                        "in passing, a broadcasting regulation he'd like relaxed.",
            category="Political",
            condition=lambda state: True, chance=0.05,
            default_option_id="decline",
            options=[
                EventOption(
                    id="take_deal", label="Reach an understanding", pc_cost=5,
                    description="Warmer coverage within the week. He will collect eventually.",
                    effects=LawEffect(modifiers=[Modifier(
                        id="media_honeymoon", source="The Chairman's Offer",
                        target="approval_bias", magnitude=0.02,
                        onset_delay=0, ramp_duration=2, hold_duration=8, decay_duration=4)],
                        faction_loyalty_deltas={ROLE_REFORM: -0.04}),
                ),
                EventOption(
                    id="decline", label="Decline politely", pc_cost=0,
                    description="Dinner was excellent; the answer is no.",
                    effects=LawEffect(),
                ),
            ],
        ),

        # ═════════════════ Diplomatic ═════════════════
        EventDef(
            id="spy_scandal",
            title="A Spy in the Ministry",
            description="Counter-intelligence has caught an agent inside the defence ministry. "
                        "The handler is known to them — the networks the old Union left behind "
                        "were never rolled up, only reassigned. How loudly do you want this "
                        "to get?",
            category="Diplomatic",
            condition=_any_bad_relation, chance=0.07, portfolio="Foreign Affairs",
            default_option_id="quiet_protest",
            options=[
                EventOption(
                    id="expel_diplomats", label="Expel their diplomats", pc_cost=8,
                    description="A public row, embassy staff on the next flight home.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_NATIONALIST: 0.05}),
                    # Aimed at whichever hostile power actually triggered this,
                    # not a hardcoded one (engine/events.py: TARGET_MOST_HOSTILE).
                    relation_deltas={TARGET_MOST_HOSTILE: -0.10},
                ),
                EventOption(
                    id="quiet_protest", label="Handle it quietly", pc_cost=4,
                    description="A discreet démarche and a traded prisoner. The public never knows.",
                    effects=LawEffect(),
                    relation_deltas={TARGET_MOST_HOSTILE: -0.03},
                ),
                EventOption(
                    id="double_agent", label="Turn the agent", pc_cost=12,
                    description="Feed them what you want believed. Risky, invisible, delicious.",
                    effects=LawEffect(modifiers=[Modifier(
                        id="double_agent_edge", source="A Spy in the Ministry",
                        target="approval_bias", magnitude=0.005,
                        onset_delay=2, ramp_duration=2, hold_duration=6, decay_duration=2)]),
                ),
            ],
        ),
        EventDef(
            id="refugee_crisis",
            title="Refugees at the Border",
            description="A neighbour's civil war has arrived at your frontier: thousands of families "
                        "with everything they own on their backs. The border guards are asking for "
                        "orders.",
            category="Diplomatic",
            condition=_neighbour_in_civil_war, chance=0.30, portfolio="Interior",
            default_option_id="camps",
            options=[
                EventOption(
                    id="open_borders", label="Open the border", pc_cost=8,
                    description="Do the decent thing and absorb the cost — economic and political.",
                    effects=LawEffect(budget_expenditure_delta=90.0,
                                      faction_loyalty_deltas={ROLE_REFORM: 0.06,
                                                              ROLE_LABOUR: 0.04,
                                                              ROLE_NATIONALIST: -0.08}),
                    follow_up={"event_id": "integration_debate", "delay": 6, "chance": 0.8},
                ),
                EventOption(
                    id="camps", label="Build border camps", pc_cost=6,
                    description="Shelter without settlement — the compromise that satisfies no one.",
                    effects=LawEffect(budget_expenditure_delta=50.0),
                ),
                EventOption(
                    id="close_border", label="Seal the border", pc_cost=4,
                    description="Turn them back. The pictures will be terrible.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_NATIONALIST: 0.07,
                                                              ROLE_AGRARIAN: 0.03,
                                                              ROLE_REFORM: -0.08},
                                      modifiers=[Modifier(
                                          id="border_shame", source="Refugees at the Border",
                                          target="approval_bias", magnitude=-0.01,
                                          onset_delay=0, ramp_duration=1, hold_duration=5, decay_duration=3)]),
                ),
            ],
        ),
        EventDef(
            id="integration_debate",
            title="The Integration Question",
            description="Months on, the families you admitted are settling in — and the question of "
                        "work permits, schools, and citizenship has reached the floor of the "
                        "assembly, trailed by every prejudice in the country.",
            category="Diplomatic",
            condition=_never, chance=0.0,
            default_option_id="slow_path",
            options=[
                EventOption(
                    id="full_integration", label="Fast-track work permits", pc_cost=8,
                    description="New taxpayers by year's end; new voters someday.",
                    effects=LawEffect(gdp_growth_delta=0.002,
                                      faction_loyalty_deltas={ROLE_REFORM: 0.05,
                                                              ROLE_LABOUR: 0.04,
                                                              ROLE_NATIONALIST: -0.06}),
                ),
                EventOption(
                    id="slow_path", label="A cautious, staged path", pc_cost=4,
                    description="Reviews, quotas, and committees. Slow satisfies the middle.",
                    effects=LawEffect(),
                ),
            ],
        ),

        # ═════════════════ Social ═════════════════
        EventDef(
            id="student_movement",
            title="The Students Are Marching",
            description="A student movement has grown out of the universities — idealistic, loud, "
                        "and photogenic. Their demands are a mix of the impossible and the overdue.",
            category="Social",
            condition=lambda state: state.country.economy.unemployment > 0.09, chance=0.06,
            default_option_id="meet_leaders",
            options=[
                EventOption(
                    id="meet_leaders", label="Meet their leaders", pc_cost=5,
                    description="Tea, cameras, and one achievable concession.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_LABOUR: 0.04,
                                                              ROLE_REFORM: 0.03}),
                ),
                EventOption(
                    id="dismiss_them", label="Dismiss them as naive", pc_cost=0,
                    description="'They'll grow up.' Their parents vote, though.",
                    effects=LawEffect(modifiers=[Modifier(
                        id="student_dismissal", source="The Students Are Marching",
                        target="approval_bias", magnitude=-0.008,
                        onset_delay=0, ramp_duration=1, hold_duration=4, decay_duration=2)]),
                ),
            ],
        ),
        EventDef(
            id="faith_and_state",
            title="Faith and State",
            description="A dispute over religious symbols in public schools has escalated from a "
                        "local quarrel into a national argument about what kind of country this is.",
            category="Social",
            condition=lambda state: True, chance=0.04,
            default_option_id="local_choice",
            options=[
                EventOption(
                    id="secular_line", label="Hold a firm secular line", pc_cost=6,
                    description="The state has no favourite gods.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_REFORM: 0.05,
                                                               ROLE_NATIONALIST: -0.06}),
                ),
                EventOption(
                    id="tradition_line", label="Defend tradition", pc_cost=6,
                    description="Some things predate the republic and will outlast it.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_NATIONALIST: 0.06,
                                                               ROLE_REFORM: -0.05}),
                ),
                EventOption(
                    id="local_choice", label="Leave it to local councils", pc_cost=2,
                    description="Federalism: the art of making problems someone else's.",
                    effects=LawEffect(),
                ),
            ],
        ),

        # ═════════════════ Wildcard ═════════════════
        EventDef(
            id="natural_disaster",
            title="The River Breaks Its Banks",
            description="A week of rain has put three districts underwater. Farms, mills, and homes "
                        "are gone; the cameras are already there, and so must you be.",
            category="Wildcard",
            condition=lambda state: True, chance=0.03, portfolio="Interior",
            default_option_id="standard_relief",
            options=[
                EventOption(
                    id="full_mobilisation", label="Full national mobilisation", pc_cost=10,
                    description="Army engineers, emergency housing, a visibly present government.",
                    effects=LawEffect(budget_expenditure_delta=160.0,
                                      modifiers=[Modifier(
                                          id="disaster_leadership", source="The River Breaks Its Banks",
                                          target="approval_bias", magnitude=0.02,
                                          onset_delay=0, ramp_duration=1, hold_duration=5, decay_duration=3)]),
                ),
                EventOption(
                    id="standard_relief", label="Standard relief effort", pc_cost=4,
                    description="Competent, procedural, forgettable.",
                    effects=LawEffect(budget_expenditure_delta=80.0),
                ),
            ],
        ),
        EventDef(
            id="assassination_scare",
            title="A Shot Outside the Assembly",
            description="A gunman was wrestled down metres from a cabinet minister this morning. "
                        "Nobody was hurt — this time. The security services want sweeping new powers "
                        "by tonight.",
            category="Wildcard",
            condition=_shaky_government, chance=0.05, portfolio="Interior",
            default_option_id="measured_review",
            options=[
                EventOption(
                    id="security_crackdown", label="Grant the sweeping powers", pc_cost=8,
                    description="Safer streets, colder civil liberties.",
                    effects=LawEffect(faction_loyalty_deltas={ROLE_NATIONALIST: 0.06,
                                                               ROLE_REFORM: -0.06,
                                                               ROLE_LABOUR: -0.04}),
                ),
                EventOption(
                    id="measured_review", label="A measured security review", pc_cost=4,
                    description="Fix the failures without rewriting the constitution overnight.",
                    effects=LawEffect(),
                ),
                EventOption(
                    id="soldiers_composure", label="A soldier's composure", pc_cost=2,
                    description="You've been shot at by professionals. Walk the same route "
                               "tomorrow, unhurried, and let the country draw its own conclusion.",
                    requires=_bg("former_general"),
                    effects=LawEffect(modifiers=[Modifier(
                        id="scare_composure", source="A Shot Outside the Assembly",
                        target="approval_bias", magnitude=0.015,
                        onset_delay=0, ramp_duration=1, hold_duration=5, decay_duration=3)]),
                ),
            ],
        ),
        EventDef(
            id="party_leadership_challenge",
            title="A Challenge From Within",
            description="Your own party's leading wing has run out of patience with you. A letter "
                        "with too many signatures is circulating, and tonight's party meeting has "
                        "one unwritten agenda item: whether you still speak for them.",
            category="Political",
            condition=_restless_own_party, chance=0.5, cooldown=18, audience="any",
            default_option_id="face_down",
            options=[
                EventOption(
                    id="face_down", label="Face them down", pc_cost=12,
                    description="Walk into the meeting alone and remind them who wins them "
                               "elections. It works — this time — and it costs them nothing "
                               "to hate you quietly.",
                    on_apply=_challenge_face_down,
                ),
                EventOption(
                    id="accommodate", label="Bend toward the wing", pc_cost=5,
                    description="Adopt half their platform as your own. Cheaper than a war — "
                               "but you become a little more like them.",
                    on_apply=_challenge_accommodate,
                ),
                EventOption(
                    id="purge", label="Purge the ringleaders", pc_cost=18,
                    description="Deselect them, demote them, brief against them. The wing "
                               "shrinks; the whole party remembers how.",
                    effects=LawEffect(modifiers=[Modifier(
                        id="purge_fallout", source="A Challenge From Within",
                        target="approval_bias", magnitude=-0.01,
                        onset_delay=0, ramp_duration=1, hold_duration=5, decay_duration=3)]),
                    on_apply=_challenge_purge,
                ),
            ],
        ),

        # ═══════════════ VETRENKA: THE FROZEN CONFLICT ═══════════════
        EventDef(
            id="vetrenka_friction",
            title="Another Week on the Line",
            description="The ceasefire holds the way it always holds. This week it was the "
                        "usual: shooting across the contact line that both sides insist "
                        "began with the other, a dispute over men held since 1992, and a "
                        "Krasovan 'peacekeeping' convoy on a road it has no business "
                        "using. The Foreign Ministry wants to know how loudly to object.",
            category="Diplomatic",
            # The 6-turn cooldown does the pacing; the chance only decides how
            # promptly it lands once eligible. Measured over 20 full terms,
            # 0.40 is where every campaign sees the line at least three times
            # (0.28 left some governments barely aware there was a war on) and
            # above it the cooldown, not the roll, is the binding constraint.
            condition=_vetrenka_friction_due, chance=0.40, cooldown=6,
            portfolio="Foreign Affairs",
            default_option_id="absorb",
            options=[
                EventOption(
                    id="absorb", label="Absorb it and say nothing", pc_cost=0,
                    description="Log the violation, brief nobody, move on. It costs nothing "
                               "this week and a little of something harder to name.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"national_conservatives": -0.05}),
                    on_apply=_vetrenka_absorb,
                ),
                EventOption(
                    id="protest", label="Protest through the mediators", pc_cost=5,
                    description="Put it on the record with the monitors and the embassies. "
                               "Nothing changes on the ground, but the file grows, and one "
                               "day the file may matter.",
                    effects=LawEffect(),
                    relation_deltas={KRASOVA: -0.03},
                    on_apply=_vetrenka_protest,
                ),
                EventOption(
                    id="respond", label="Respond in kind", pc_cost=8,
                    description="Return fire, close the road, hold their convoy at the "
                               "checkpoint for a day. The line quietens for a fortnight "
                               "afterwards. It always does. It never lasts.",
                    effects=LawEffect(
                        budget_expenditure_delta=40.0,
                        faction_loyalty_deltas={"national_conservatives": 0.06,
                                                "social_democrats": -0.04}),
                    relation_deltas={KRASOVA: -0.06},
                    on_apply=_vetrenka_respond,
                ),
            ],
        ),
        EventDef(
            id="vetrenka_crossroads",
            title="Someone Offers to Mediate",
            description="A delegation from the international monitors has asked for a "
                        "meeting, and everyone knows what about. After a year of incidents "
                        "on the line, there is an appetite abroad for a framework — and the "
                        "quiet suggestion that if Ardenia will not discuss one, others will "
                        "discuss it without her. The chamber has been arguing about "
                        "Vetrenka since before this government existed. Now it has to "
                        "decide.",
            category="Diplomatic",
            condition=_vetrenka_crossroads_ready, chance=0.5, once=True,
            portfolio="Foreign Affairs",
            default_option_id="formalise",
            options=[
                EventOption(
                    id="settlement", label="Enter the peace process", pc_cost=18,
                    description="Negotiate in good faith, with mediators in the room and "
                               "the possibility of an outcome nobody in the chamber has "
                               "publicly accepted. Slow, expensive, and the only path that "
                               "closes this.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"national_conservatives": -0.10,
                                                "liberal_democrats": 0.06,
                                                "social_democrats": 0.06}),
                    on_apply=_vetrenka_open_talks,
                ),
                EventOption(
                    id="reassert", label="Prepare to retake the region", pc_cost=25,
                    description="Reject the framework, mobilise, and finish the war the "
                               "State Council lost. The army is not what it was in 1992 — "
                               "and neither, everyone assumes, is the force waiting on the "
                               "other side.",
                    effects=LawEffect(
                        budget_expenditure_delta=260.0,
                        faction_loyalty_deltas={"national_conservatives": 0.14,
                                                "social_democrats": -0.10,
                                                "liberal_democrats": -0.06}),
                    relation_deltas={KRASOVA: -0.15},
                    on_apply=_vetrenka_launch_offensive,
                ),
                EventOption(
                    id="formalise", label="Freeze it properly", pc_cost=10,
                    description="Accept the line as an administrative fact without ever "
                               "saying the word recognition. Trade resumes, the shooting "
                               "mostly stops, and a fifth of the country stays gone for as "
                               "long as anyone can see.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"national_conservatives": -0.16,
                                                "liberal_democrats": 0.04}),
                    relation_deltas={KRASOVA: 0.10},
                    on_apply=_vetrenka_formalise,
                ),
            ],
        ),
        EventDef(
            id="vetrenka_settled",
            title="The Framework Is Initialled",
            description="It took eleven months, four venues and a formula on the status "
                        "question so carefully worded that both delegations were able to "
                        "tell their capitals they had won. The shooting stops. The "
                        "displaced get a mechanism. Nobody gets to say the word they "
                        "wanted to say.",
            category="Diplomatic",
            condition=_never, chance=0.0,
            default_option_id="sign_it",
            options=[
                EventOption(
                    id="sign_it", label="Sign it", pc_cost=8,
                    description="Put your name on the thing that ends it, and accept that "
                               "the name on it will be the one history argues about.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"national_conservatives": -0.14,
                                                "liberal_democrats": 0.08,
                                                "social_democrats": 0.08},
                        modifiers=[Modifier(
                            id="vetrenka_peace_dividend", source="The Framework Is Initialled",
                            target="approval_bias", magnitude=0.025,
                            onset_delay=1, ramp_duration=3, hold_duration=None,
                            decay_duration=0)]),
                    relation_deltas={KRASOVA: 0.20},
                    on_apply=_vetrenka_settle,
                ),
            ],
        ),
        EventDef(
            id="vetrenka_talks_fail",
            title="The Talks Collapse",
            description="They collapsed over the sequencing of a paragraph nobody outside "
                        "the room could explain. What everyone understood was the "
                        "photograph of the empty table, and the fact that the government "
                        "spent a year of its authority on it and came home with the "
                        "paragraph unresolved.",
            category="Diplomatic",
            condition=_never, chance=0.0,
            default_option_id="walk_away",
            options=[
                EventOption(
                    id="walk_away", label="Blame them and walk away", pc_cost=4,
                    description="Publish your version first. The line goes back to what it "
                               "was, only colder, and next time the mediators call somebody "
                               "else will take the meeting.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"national_conservatives": 0.05},
                        modifiers=[Modifier(
                            id="vetrenka_failed_talks", source="The Talks Collapse",
                            target="approval_bias", magnitude=-0.025,
                            onset_delay=0, ramp_duration=2, hold_duration=8, decay_duration=4)]),
                    relation_deltas={KRASOVA: -0.08},
                    on_apply=_vetrenka_talks_failed,
                ),
            ],
        ),
        EventDef(
            id="vetrenka_retaken",
            title="The Flag Over Vetrenka",
            description="Nine days, further than anyone in the ministry privately expected, "
                        "and the separatist command has withdrawn across the water rather "
                        "than be encircled. Ardenian troops are in the regional capital. "
                        "What the pictures do not show is the third of the population that "
                        "left with them, and the fact that the region is now a place your "
                        "army has to hold.",
            category="Diplomatic",
            condition=_never, chance=0.0,
            default_option_id="garrison",
            options=[
                EventOption(
                    id="garrison", label="Hold it and govern it", pc_cost=14,
                    description="Occupation, administration, reconstruction, and an "
                               "insurgency that has simply changed address.",
                    effects=LawEffect(
                        budget_expenditure_delta=200.0,
                        faction_loyalty_deltas={"national_conservatives": 0.16,
                                                "social_democrats": -0.06},
                        modifiers=[Modifier(
                            id="vetrenka_victory", source="The Flag Over Vetrenka",
                            target="approval_bias", magnitude=0.03,
                            onset_delay=0, ramp_duration=1, hold_duration=8, decay_duration=6)]),
                    relation_deltas={KRASOVA: -0.20},
                    on_apply=_vetrenka_won,
                ),
            ],
        ),
        EventDef(
            id="vetrenka_rout",
            title="The Offensive Breaks",
            description="It went wrong on the second day and comprehensively by the fourth. "
                        "Krasovan aircraft were over the corridor within a week — "
                        "'protecting peacekeepers', a phrase their foreign ministry had "
                        "clearly prepared some time ago. The line is now further inland "
                        "than it was, and the government is explaining why.",
            category="Diplomatic",
            condition=_never, chance=0.0,
            default_option_id="accept_ceasefire",
            options=[
                EventOption(
                    id="accept_ceasefire", label="Take the ceasefire offered", pc_cost=6,
                    description="Sign what is put in front of you, on worse terms than the "
                               "one you rejected, and survive the week.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"national_conservatives": -0.12,
                                                "social_democrats": -0.08,
                                                "workers_front": -0.06},
                        modifiers=[Modifier(
                            id="vetrenka_defeat", source="The Offensive Breaks",
                            target="approval_bias", magnitude=-0.045,
                            onset_delay=0, ramp_duration=1, hold_duration=10, decay_duration=6)]),
                    relation_deltas={KRASOVA: -0.25},
                    on_apply=_vetrenka_lost,
                ),
            ],
        ),
        EventDef(
            id="vetrenka_partition",
            title="A Line on the Map, Quietly",
            description="No treaty, no ceremony, no word said aloud. Customs posts become "
                        "permanent, the crossing reopens on published hours, and the "
                        "official maps go to the printers with a dotted line where a "
                        "border is not. The National Conservatives have called it the "
                        "second February Intervention, which is unfair, and effective.",
            category="Diplomatic",
            condition=_never, chance=0.0,
            default_option_id="let_it_stand",
            options=[
                EventOption(
                    id="let_it_stand", label="Let it stand", pc_cost=0,
                    description="Say nothing, sign nothing, change nothing. The cheapest "
                               "thing this government will ever do, and the one it will be "
                               "remembered for.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"national_conservatives": -0.18,
                                                "liberal_democrats": 0.05,
                                                "social_democrats": 0.04},
                        modifiers=[Modifier(
                            id="vetrenka_surrendered", source="A Line on the Map, Quietly",
                            target="approval_bias", magnitude=-0.02,
                            onset_delay=0, ramp_duration=2, hold_duration=None,
                            decay_duration=0)]),
                    relation_deltas={KRASOVA: 0.15},
                    on_apply=_vetrenka_partitioned,
                ),
            ],
        ),
        EventDef(
            id="vetrenka_normalised",
            title="The Crossing Opens on Schedule",
            description="Five months on, the extraordinary has become the timetable. "
                        "Lorries queue at the crossing on published hours, families visit "
                        "on day permits, and the argument about what to call the line has "
                        "moved from the chamber to the letters page. Nobody has forgiven "
                        "it. Everybody has stopped organising against it.",
            category="Diplomatic",
            condition=_never, chance=0.0,
            default_option_id="say_nothing",
            options=[
                EventOption(
                    id="say_nothing", label="Say nothing and let it settle", pc_cost=0,
                    description="Do not defend it, do not repeat it, do not give it a name. "
                               "It survives on being boring.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"national_conservatives": -0.04,
                                                "liberal_democrats": 0.04}),
                    on_apply=_vetrenka_normal,
                ),
            ],
        ),
        EventDef(
            id="vetrenka_backlash",
            title="\"Who Gave It Away?\"",
            description="The National Conservatives have found their campaign and it is a "
                        "single question, asked at every rally, printed on every leaflet, "
                        "put to every minister who steps outside. Veterans' associations "
                        "have joined it. So, quietly, have people who voted for this "
                        "government. There is no rebutting the question, because the "
                        "answer is you.",
            category="Domestic",
            condition=_never, chance=0.0,
            default_option_id="ride_it_out",
            options=[
                EventOption(
                    id="ride_it_out", label="Ride it out", pc_cost=6,
                    description="Take the losses, refuse the fight you cannot win, and hope "
                               "the question gets old before the government does.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"national_conservatives": -0.10,
                                                "social_democrats": -0.05},
                        modifiers=[Modifier(
                            id="vetrenka_betrayal", source="\"Who Gave It Away?\"",
                            target="approval_bias", magnitude=-0.04,
                            onset_delay=0, ramp_duration=2, hold_duration=12,
                            decay_duration=8)]),
                    on_apply=_vetrenka_backlash_lands,
                ),
            ],
        ),

        # ═══════════════ THE VASCA QUESTION ═══════════════
        EventDef(
            id="vasca_stirs",
            title="The West Is Talking Again",
            description="A customs post in the western districts was raided in the night — "
                        "weapons taken, nobody hurt, nobody caught. Two days later a "
                        "recording surfaced in the markets: an older man's voice, unhurried, "
                        "talking about a republic that was stolen twice. The Interior "
                        "Ministry will not say on the record that it is Dorin Vasca. They "
                        "will not say it isn't.",
            category="Political",
            condition=_vasca_stirring, chance=0.22, once=True,
            portfolio="Interior",
            default_option_id="downplay",
            options=[
                EventOption(
                    id="crackdown", label="Send the security services west", pc_cost=16,
                    description="Sweep the districts, arrest the network, finish what the "
                               "Turn of the Year left undone. If the ministries are up to "
                               "it. They may not be.",
                    effects=LawEffect(
                        budget_expenditure_delta=110.0,
                        faction_loyalty_deltas={"national_conservatives": 0.08,
                                                "liberal_democrats": -0.04,
                                                "social_democrats": -0.05}),
                    on_apply=_vasca_crackdown,
                ),
                EventOption(
                    id="amnesty", label="Offer terms to the rank and file", pc_cost=12,
                    description="Amnesty for anyone who walks out of the hills by spring; "
                               "nothing at all for Vasca himself. Isolate the man from the "
                               "grievance. The National Conservatives will call it "
                               "surrender before you finish announcing it.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"national_conservatives": -0.10,
                                                "social_democrats": 0.06,
                                                "liberal_democrats": 0.04}),
                    on_apply=_vasca_amnesty,
                ),
                EventOption(
                    id="downplay", label="Call it banditry and move on", pc_cost=0,
                    description="A criminal matter for the district police. Say the name as "
                               "little as possible; a ghost you refuse to discuss is still a "
                               "ghost, and cheaper this month.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"national_conservatives": -0.05}),
                    on_apply=_vasca_downplay,
                ),
                EventOption(
                    id="lead_it", label="Go west and run it yourself", pc_cost=20,
                    description="You commanded men in that country once. Take the operation "
                               "personally, and take the consequences personally with it.",
                    requires=_bg("former_general"),
                    effects=LawEffect(
                        budget_expenditure_delta=90.0,
                        faction_loyalty_deltas={"national_conservatives": 0.10,
                                                "liberal_democrats": -0.03},
                        modifiers=[Modifier(
                            id="vasca_personal_command", source="The West Is Talking Again",
                            target="approval_bias", magnitude=0.015,
                            onset_delay=0, ramp_duration=1, hold_duration=5, decay_duration=3)]),
                    on_apply=_vasca_lead_personally,
                ),
            ],
        ),
        EventDef(
            id="vasca_crackdown_works",
            title="They Took Him Near the Border",
            description="It was ordinary in the end. A roadblock, a car that turned around "
                        "too slowly, and an old man in the back seat who gave a false name "
                        "to soldiers young enough to be his grandchildren. He asked to be "
                        "allowed to walk to the vehicle himself. They let him.",
            category="Political",
            condition=_never, chance=0.0,
            default_option_id="public_trial",
            options=[
                EventOption(
                    id="public_trial", label="Try him in open court", pc_cost=10,
                    description="Everything on the record, in front of the cameras, for as "
                               "long as it takes. It will be ugly, and it will be the most "
                               "convincing thing this republic has done.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"liberal_democrats": 0.08,
                                                "social_democrats": 0.05,
                                                "national_conservatives": -0.04},
                        modifiers=[Modifier(
                            id="vasca_trial_legitimacy", source="They Took Him Near the Border",
                            target="approval_bias", magnitude=0.02,
                            onset_delay=1, ramp_duration=2, hold_duration=10, decay_duration=4)]),
                    on_apply=_vasca_taken,
                ),
                EventOption(
                    id="quiet_detention", label="Hold him quietly", pc_cost=6,
                    description="No trial, no platform, no martyr. Also no answer to the "
                               "question of what kind of state does that.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"liberal_democrats": -0.06,
                                                "national_conservatives": 0.05}),
                    on_apply=_vasca_taken,
                ),
            ],
        ),
        EventDef(
            id="vasca_crackdown_fails",
            title="The Sweep Comes Back Empty",
            description="Three weeks, four districts, two hundred arrests and not one of "
                        "them him. What the operation did find was every family in the west "
                        "with a story about soldiers in their kitchen at four in the "
                        "morning. Recruitment in the hills has never been easier.",
            category="Political",
            condition=_never, chance=0.0,
            default_option_id="pull_back",
            options=[
                EventOption(
                    id="escalate", label="Go back in harder", pc_cost=18,
                    description="Double the deployment and accept what that means. The "
                               "alternative is admitting the first attempt was a mistake, "
                               "which is politically worse and factually true.",
                    effects=LawEffect(
                        budget_expenditure_delta=140.0,
                        faction_loyalty_deltas={"national_conservatives": 0.07,
                                                "social_democrats": -0.08,
                                                "workers_front": -0.05}),
                    on_apply=_vasca_backlash,
                    follow_up={"event_id": "vasca_last_stand", "delay": 3, "chance": 1.0},
                ),
                EventOption(
                    id="pull_back", label="Withdraw and say little", pc_cost=4,
                    description="Pull the units back to barracks and let the story die of "
                               "boredom. The west remains the west.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"national_conservatives": -0.08},
                        modifiers=[Modifier(
                            id="vasca_failed_sweep", source="The Sweep Comes Back Empty",
                            target="approval_bias", magnitude=-0.02,
                            onset_delay=0, ramp_duration=1, hold_duration=6, decay_duration=3)]),
                    on_apply=_vasca_pull_back,
                ),
            ],
        ),
        EventDef(
            id="vasca_amnesty_holds",
            title="They Come Down From the Hills",
            description="Not all of them, and not at once. But through the spring they came "
                        "down in ones and twos — men who had been fighting for a president "
                        "nobody had seen in a year, and who wanted, mostly, to go home. "
                        "What is left up there is smaller than it was, older, and no longer "
                        "an army.",
            category="Political",
            condition=_never, chance=0.0,
            default_option_id="let_it_lie",
            options=[
                EventOption(
                    id="formalise", label="Write the amnesty into law", pc_cost=12,
                    description="Make it permanent and make it public, so the next man who "
                               "considers the hills knows exactly what the door back looks "
                               "like.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"social_democrats": 0.06,
                                                "liberal_democrats": 0.05,
                                                "national_conservatives": -0.07},
                        modifiers=[Modifier(
                            id="vasca_amnesty_law", source="They Come Down From the Hills",
                            target="approval_bias", magnitude=0.015,
                            onset_delay=1, ramp_duration=2, hold_duration=12, decay_duration=4)]),
                    on_apply=_vasca_amnesty_worked,
                ),
                EventOption(
                    id="let_it_lie", label="Take the win quietly", pc_cost=0,
                    description="No ceremony, no legislation, no chance for anyone to make "
                               "a speech about it. Some victories keep better in the dark.",
                    on_apply=_vasca_amnesty_worked,
                ),
            ],
        ),
        EventDef(
            id="vasca_regroups",
            title="He Used the Winter",
            description="The amnesty emptied the fringes of his movement and left the core "
                        "of it — and the core, it turns out, was what mattered. They spent "
                        "the quiet months organising. The customs posts are being hit again, "
                        "competently this time, by men who know which nights the patrols "
                        "change.",
            category="Political",
            condition=_never, chance=0.0,
            default_option_id="hold_the_line",
            options=[
                EventOption(
                    id="hold_the_line", label="Reinforce and contain", pc_cost=12,
                    description="Hold the district boundaries, protect the posts, and accept "
                               "that this is now a standing commitment rather than a problem "
                               "you are solving.",
                    effects=LawEffect(
                        budget_expenditure_delta=100.0,
                        faction_loyalty_deltas={"national_conservatives": 0.04}),
                    on_apply=_vasca_grows,
                    follow_up={"event_id": "vasca_last_stand", "delay": 4, "chance": 1.0},
                ),
                EventOption(
                    id="second_offer", label="Offer him terms directly", pc_cost=15,
                    description="Stop pretending he is a criminal matter and treat him as "
                               "what he is: a man with a following, who might yet be bought "
                               "with something other than money.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"national_conservatives": -0.12,
                                                "liberal_democrats": -0.03}),
                    on_apply=_vasca_grows,
                    follow_up={"event_id": "vasca_last_stand", "delay": 2, "chance": 1.0},
                ),
            ],
        ),
        EventDef(
            id="vasca_emboldened",
            title="A Government That Does Not Look",
            description="Calling it banditry worked for about a season. It is harder now: "
                        "the western districts have stopped forwarding tax receipts, two "
                        "district administrators have resigned citing their families, and "
                        "the recording in the markets has been followed by three more. He "
                        "is no longer denying it is him.",
            category="Political",
            condition=_never, chance=0.0,
            default_option_id="keep_ignoring",
            options=[
                EventOption(
                    id="belated_action", label="Act now, late", pc_cost=20,
                    description="Everything the security option would have cost in the "
                               "autumn, plus a year of him recruiting on your indifference.",
                    effects=LawEffect(
                        budget_expenditure_delta=160.0,
                        faction_loyalty_deltas={"national_conservatives": 0.05,
                                                "social_democrats": -0.05}),
                    on_apply=_vasca_grows,
                    follow_up={"event_id": "vasca_last_stand", "delay": 3, "chance": 1.0},
                ),
                EventOption(
                    id="keep_ignoring", label="Still not a national question", pc_cost=0,
                    description="Say nothing again. The west is a long way from Vashtera "
                               "and the budget is due.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"national_conservatives": -0.06,
                                                "liberal_democrats": -0.04},
                        modifiers=[Modifier(
                            id="vasca_neglect", source="A Government That Does Not Look",
                            target="approval_bias", magnitude=-0.02,
                            onset_delay=0, ramp_duration=2, hold_duration=8, decay_duration=4)]),
                    on_apply=_vasca_grows,
                    follow_up={"event_id": "vasca_last_stand", "delay": 5, "chance": 1.0},
                ),
            ],
        ),
        EventDef(
            id="vasca_last_stand",
            title="The Compound at Drevna",
            description="They have him located — a farm compound above the Drevna valley, "
                        "thirty or forty men, and a road in that can be watched but not "
                        "easily driven. For the first time since the Turn of the Year, the "
                        "government knows where Dorin Vasca is sleeping. What happens next "
                        "is a decision, not an intelligence problem.",
            category="Political",
            condition=_never, chance=0.0,
            default_option_id="let_it_lie",
            options=[
                EventOption(
                    id="storm_it", label="Take the compound", pc_cost=18,
                    description="Go in before dawn and end it. Whatever is written about "
                               "how it ended will be written afterwards, by people who "
                               "weren't there.",
                    effects=LawEffect(
                        budget_expenditure_delta=90.0,
                        faction_loyalty_deltas={"national_conservatives": 0.08,
                                                "social_democrats": -0.06,
                                                "liberal_democrats": -0.04}),
                    on_apply=_vasca_storm,
                ),
                EventOption(
                    id="negotiate_exit", label="Offer him a plane", pc_cost=14,
                    description="Safe passage, a third country, and a public statement that "
                               "costs him more than prison would. He is old and he is tired "
                               "and he has read the same histories you have.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"national_conservatives": -0.10,
                                                "social_democrats": 0.05,
                                                "liberal_democrats": 0.05}),
                    on_apply=_vasca_exile,
                ),
                EventOption(
                    id="let_it_lie", label="Watch the road and wait", pc_cost=0,
                    description="Do nothing, keep the compound under observation, and let "
                               "the question stay open for whoever governs next.",
                    effects=LawEffect(
                        faction_loyalty_deltas={"national_conservatives": -0.06}),
                    on_apply=_vasca_unresolved,
                ),
            ],
        ),

        # ═══════════════ THE SCHEMER ARC ═══════════════
        #
        # Four steps, and the middle one genuinely branches: confronting the
        # minister leads to a different third event than letting them run,
        # with different endings available. Entry is gated on the schemer
        # trait's own threat curve (models/cabinet.py + turn.py), so it
        # fires in whichever country's cabinet actually has a schemer.
        #
        #   step 1  a_schemer_stirs      (pool, once)
        #     ├─ confront ──→ step 2a  a_schemer_confronted
        #     │                 ├─ buy them off ──→ ENDS (loyal, resentful)
        #     │                 └─ demand resignation ──→ ENDS (neutralised)
        #     └─ wait     ──→ step 2b  a_schemer_moves
        #                       ├─ crush late ──→ ENDS (neutralised, costly)
        #                       ├─ expose them ──→ ENDS (neutralised)
        #                       └─ too late ──→ step 3  a_schemer_triumphant
        #                                        └─ hands off to
        #                                           party_leadership_challenge
        EventDef(
            id="a_schemer_stirs",
            title="A Minister Is Counting Votes",
            description="Your whips report a pattern: one of your ministers has been holding "
                        "meetings that appear on no diary, with people who have no business "
                        "in their department. Nothing provable. Everything obvious.",
            category="Political",
            condition=_schemer_plotting, chance=0.45, cooldown=24,
            default_option_id="wait",
            options=[
                EventOption(
                    id="confront", label="Confront them privately", pc_cost=8,
                    description="Summon them, alone, and let them know you know. It forces "
                               "their hand — one way or the other.",
                    on_apply=_schemer_noted,
                    follow_up={"event_id": "a_schemer_confronted", "delay": 2, "chance": 1.0},
                ),
                EventOption(
                    id="wait", label="Let it play out", pc_cost=0,
                    description="Say nothing. Watch who visits them. A plot you can see is "
                               "worth more than one you've driven underground — until it isn't.",
                    on_apply=_schemer_noted,
                    follow_up={"event_id": "a_schemer_moves", "delay": 3, "chance": 1.0},
                ),
            ],
        ),
        EventDef(
            id="a_schemer_confronted",
            title="The Minister Denies Everything",
            description="They sat across from you and denied all of it, pleasantly, for forty "
                        "minutes. Then, at the door, they mentioned how many colleagues share "
                        "their concerns about the government's direction. It was not a threat. "
                        "It was an invoice.",
            category="Political",
            condition=_never, chance=0.0,
            default_option_id="buy_off",
            options=[
                EventOption(
                    id="buy_off", label="Pay the invoice", pc_cost=14,
                    description="Give them the brief they want and the standing that comes "
                               "with it. They will be loyal, and they will never forget that "
                               "you blinked.",
                    on_apply=_schemer_buy_off,
                ),
                EventOption(
                    id="demand_resignation", label="Demand their resignation", pc_cost=16,
                    description="End it now, publicly, while you still hold the initiative. "
                               "Their allies will not forgive it.",
                    effects=LawEffect(modifiers=[Modifier(
                        id="schemer_purge_cost", source="A Minister Is Counting Votes",
                        target="approval_bias", magnitude=-0.012,
                        onset_delay=0, ramp_duration=1, hold_duration=5, decay_duration=3)]),
                    on_apply=_schemer_resign,
                ),
            ],
        ),
        EventDef(
            id="a_schemer_moves",
            title="The Numbers Are Real",
            description="You let it run, and now you can see the shape of it: a bloc of names, "
                        "a date, and a candidate. Your minister has stopped pretending to count "
                        "and started pretending to be reluctant.",
            category="Political",
            condition=_never, chance=0.0,
            default_option_id="too_late",
            options=[
                EventOption(
                    id="crush_late", label="Break them now, whatever it costs", pc_cost=22,
                    description="Sack them and everyone who signed. It works. The party will "
                               "be smaller and angrier, and so will you.",
                    on_apply=_schemer_crush,
                ),
                EventOption(
                    id="expose", label="Put the whole thing in the papers", pc_cost=10,
                    description="Brief the lobby correspondents yourself. Plots die in "
                               "daylight — and so does the fiction that your house is in order.",
                    effects=LawEffect(modifiers=[Modifier(
                        id="schemer_exposed_press", source="The Numbers Are Real",
                        target="approval_bias", magnitude=-0.02,
                        onset_delay=0, ramp_duration=1, hold_duration=4, decay_duration=3)]),
                    on_apply=_schemer_expose,
                ),
                EventOption(
                    id="too_late", label="There is nothing left to do", pc_cost=0,
                    description="You have no votes to spare and no time to find them. It "
                               "happens now, and it happens to you.",
                    on_apply=_schemer_ascend,
                    follow_up={"event_id": "a_schemer_triumphant", "delay": 1, "chance": 1.0},
                ),
            ],
        ),
        EventDef(
            id="a_schemer_triumphant",
            title="Your Minister Has the Numbers",
            description="It is done in a committee room with the lights on. Your minister has "
                        "the signatures, the press has the story, and the party has a question "
                        "to answer about who leads it.",
            category="Political",
            condition=_never, chance=0.0,
            default_option_id="concede_ground",
            options=[
                EventOption(
                    id="concede_ground", label="Give ground and survive", pc_cost=6,
                    description="Concede the policy, keep the office, and let them believe "
                               "they won. Most of politics is deciding what losing looks like.",
                    on_apply=_schemer_ascend,
                    # Hands off to the standing leadership-challenge situation:
                    # the arc ends by arming the mechanic that already exists.
                    follow_up={"event_id": "party_leadership_challenge",
                               "delay": 2, "chance": 0.9},
                ),
                EventOption(
                    id="fight_it_out", label="Make them do it in the open", pc_cost=18,
                    description="No deal. Let them table the motion and count the votes in "
                               "front of the cameras. You may lose. They will bleed either way.",
                    effects=LawEffect(modifiers=[Modifier(
                        id="schemer_open_fight", source="Your Minister Has the Numbers",
                        target="approval_bias", magnitude=-0.015,
                        onset_delay=0, ramp_duration=1, hold_duration=6, decay_duration=3)]),
                    on_apply=_schemer_ascend,
                    follow_up={"event_id": "party_leadership_challenge",
                               "delay": 1, "chance": 1.0},
                ),
            ],
        ),
    ]
