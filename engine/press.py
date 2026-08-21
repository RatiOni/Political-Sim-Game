"""
The press: turns a turn's structured news (GameState.turn_news) into a
newspaper front page — masthead, lead story, secondary headlines, briefs,
and the numbers box. Read-only over state; variant choice uses the same
local hash-seeded Random idiom as engine/flavor.py.
"""

import random

from content.press import HEADLINES, LEADS

# Drama ranking: what leads the paper when several things happened at once.
RANK = {
    "election": 100,
    "civil_war_out": 95,
    "world_civil_war_out": 90,
    "confidence_vote": 85,
    "civil_war_end": 82,
    "scandal": 80,
    "situation": 70,
    "civil_war_ongoing": 65,
    "vote_failed": 60,
    "exec_order": 58,
    "law_repealed": 56,
    "vote_passed": 55,
    "protest": 50,
    "situation_lapsed": 47,
    "situation_resolved": 45,
    "wing_takeover": 40,
    "minister_restless": 42,
    "minister_appointed": 32,
    # The schemer arc: a plot against the government outranks routine news,
    # and its climax outranks the plot.
    # The Vasca question — the biggest domestic story this republic has.
    "vasca_dead": 96,
    "vasca_captured": 94,
    "vasca_exiled": 88,
    "vasca_unresolved": 72,
    "vasca_isolated": 66,
    "vasca_operation": 64,
    "vasca_amnesty": 60,
    # Vetrenka — the war nobody declared over. Its resolution outranks
    # everything; its weekly friction is background noise by design.
    "vetrenka_retaken": 98,
    "vetrenka_rout": 97,
    "vetrenka_settled": 95,
    "vetrenka_offensive": 92,
    "vetrenka_partition": 86,
    "vetrenka_backlash": 74,
    "vetrenka_normalised": 44,
    "vetrenka_talks_failed": 76,
    "vetrenka_talks": 70,
    "vetrenka_incident": 18,
    "schemer_ascendant": 78,
    "schemer_neutralized": 68,
    "schemer_bought": 52,
    "schemer_arc": 44,
    "world_axis": 38,
    "world_feud": 38,
    "world_arc_ends": 35,
    "address_reassuring": 30, "address_defiant": 30,
    "address_visionary": 30, "address_contrite": 30,
    "world_civil_war_end": 28,
    "world_condemn_player": 26, "world_pressure_player": 26,
    "world_court_player": 24, "world_trade_pact": 24,
    "world_condemn": 22, "world_undermine": 22, "world_deepen": 20,
    "economy_move": 15,
    "world_deliberates": 12,
}

MAX_SECONDARY_HEADLINES = 4


def _pick(state, pool, salt, **fields) -> str:
    rng = random.Random(hash((state.turn, "press", salt)) & 0xffffffff)
    return rng.choice(pool).format(**fields)


def masthead_for(state) -> str:
    return state.country.paper or f"The {state.country.name} Herald"


def front_page(state, before=None, after=None) -> dict:
    """
    {masthead, dateline, lead: {headline, body}, headlines: [str],
     briefs: [str], numbers: (before, after) | None}
    """
    items = [(RANK.get(key, 10), i, key, fields, text)
             for i, (key, fields, text) in enumerate(state.turn_news)
             if key in HEADLINES]
    items.sort(key=lambda t: (-t[0], t[1]))

    if items:
        _, _, lead_key, lead_fields, _ = items[0]
        lead_headline = _pick(state, HEADLINES[lead_key], f"h:{lead_key}", **lead_fields).upper()
        body_pool = LEADS.get(lead_key)
        lead_body = (_pick(state, body_pool, f"b:{lead_key}", **lead_fields)
                     if body_pool else "")
    else:
        lead_headline = _pick(state, [f"a quiet month in {state.country.name}"],
                              "h:quiet").upper()
        lead_body = _pick(state, LEADS["quiet"], "b:quiet")

    headlines = []
    for _, idx, key, fields, _ in items[1:1 + MAX_SECONDARY_HEADLINES]:
        headlines.append(_pick(state, HEADLINES[key], f"h:{key}:{idx}", **fields).upper())

    used = {t[1] for t in items[:1 + MAX_SECONDARY_HEADLINES]}
    briefs = [text for i, (key, fields, text) in enumerate(state.turn_news)
              if i not in used]

    return {
        "masthead": masthead_for(state),
        "dateline": state.date_string(),
        "lead": {"headline": lead_headline, "body": lead_body},
        "headlines": headlines,
        "briefs": briefs,
        "numbers": (before, after) if before and after else None,
    }
