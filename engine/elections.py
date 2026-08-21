"""
Election mechanics. Results are never rolled: turnout-weighted support
(accumulated all term via engine/turn.py) resolves into seats, a government
forms around the largest party's cheapest coherent majority, and the player
can genuinely win or lose office.
"""

from typing import Optional

from datetime import date

from models.election import ElectionResult
from models.cabinet import CORE_PORTFOLIOS
from engine import cabinet_ops, stability, opposition, regions, budget

TERM_LENGTH_TURNS = 48          # a 4-year parliamentary term
ELECTORAL_THRESHOLD = 0.03      # a party below 3% of the vote wins no seats at all
SNAP_ELECTION_STABILITY_FLOOR = 0.08  # stability this catastrophic forces an election outright

# ── Turnout model ──────────────────────────────────────────────────────────
# Deterministic: each party's base turns out per its electoral momentum
# (stability.faction_performance_signal). Seats come from votes CAST, so
# differential turnout moves real seats; national turnout is emergent.
VOTING_AGE_FRACTION = 0.72      # share of population eligible to vote
TURNOUT_BASELINE = 0.65         # a politically average party's base turnout
TURNOUT_SENSITIVITY = 0.35      # how hard motivation swings turnout off the baseline
TURNOUT_FLOOR = 0.35            # even a demoralized base isn't zero
TURNOUT_CEIL = 0.92             # even a furious one isn't total


# ── Seat allocation ──────────────────────────────────────────────────────

def _allocate_seats(factions, total_seats: int, weights: Optional[dict] = None) -> dict:
    """
    Largest-remainder proportional allocation; always sums to total_seats,
    and parties under ELECTORAL_THRESHOLD (as a share of total weight) win
    nothing. `weights` = faction_id -> weight (hold_election passes votes
    actually cast); omitted → raw Faction.support (turnout-free path).
    """
    weight_of = (lambda f: max(0.0, weights.get(f.id, 0.0))) if weights is not None \
        else (lambda f: max(0.0, f.support))

    total_weight = sum(weight_of(f) for f in factions) or 1.0
    qualifying = [f for f in factions if weight_of(f) / total_weight >= ELECTORAL_THRESHOLD]
    if not qualifying:
        qualifying = list(factions)  # nobody cleared the bar — seat everyone anyway rather than nobody

    total_qualifying = sum(weight_of(f) for f in qualifying)
    if total_qualifying <= 0:
        base = total_seats // len(qualifying)
        seats = {f.id: base for f in qualifying}
        remainder = total_seats - sum(seats.values())
        for i in range(remainder):
            seats[qualifying[i % len(qualifying)].id] += 1
    else:
        exact = {f.id: (weight_of(f) / total_qualifying) * total_seats for f in qualifying}
        seats = {fid: int(v) for fid, v in exact.items()}
        remainder = total_seats - sum(seats.values())
        fractional = sorted(exact.items(), key=lambda kv: -(kv[1] - int(kv[1])))
        for i in range(remainder):
            fid = fractional[i % len(fractional)][0]
            seats[fid] += 1

    for f in factions:
        seats.setdefault(f.id, 0)  # sub-threshold factions explicitly wiped out, not just absent
    return seats


# ── Turnout ──────────────────────────────────────────────────────────────

def _party_enthusiasm(state, faction) -> float:
    """0..1 fraction of THIS party's base that actually turns out, driven by
    the same electoral-momentum signal as monthly support drift."""
    perf = stability.faction_performance_signal(state, faction)
    platform = opposition.election_turnout_bonus(state, faction)
    return max(TURNOUT_FLOOR, min(
        TURNOUT_CEIL, TURNOUT_BASELINE + perf * TURNOUT_SENSITIVITY + platform))


def compute_turnout(state) -> dict:
    """
    Resolves who actually shows up on election day. Returns a dict with:
      eligible          voting-age population (int)
      effective_votes   faction_id -> votes cast for it (float; the weights
                        _allocate_seats is fed)
      votes             faction_id -> votes cast (int, for display)
      vote_share        faction_id -> share of votes actually cast (0..1)
      total_cast        total votes cast (int)
      turnout_pct       total_cast / eligible — emergent national turnout
    """
    factions = state.country.factions
    eligible = max(1, int(state.country.population * VOTING_AGE_FRACTION))

    regional_vote_share = {}
    regional_turnout = {}
    regional_access = {}
    if state.regions:
        regions.ensure_electoral_support(state)
        effective = {f.id: 0.0 for f in factions}
        for region_id in state.regions:
            weight = regions.population_weight(region_id)
            potential = eligible * weight
            access = regions.electoral_access(state, region_id)
            local_support = regions.projected_party_support(state, region_id)
            local_effective = {}
            for faction in factions:
                votes_cast = (local_support.get(faction.id, 0.0)
                              * _party_enthusiasm(state, faction)
                              * potential * access)
                local_effective[faction.id] = votes_cast
                effective[faction.id] += votes_cast
            local_cast = sum(local_effective.values())
            regional_vote_share[region_id] = {
                faction_id: (value / local_cast if local_cast else 0.0)
                for faction_id, value in local_effective.items()
            }
            regional_turnout[region_id] = local_cast / potential if potential else 0.0
            regional_access[region_id] = access
    else:
        total_support = sum(max(0.0, f.support) for f in factions) or 1.0
        effective = {}
        for f in factions:
            base_share = max(0.0, f.support) / total_support
            effective[f.id] = base_share * _party_enthusiasm(state, f) * eligible

    total_cast = sum(effective.values())
    if total_cast <= 0:  # degenerate guard — treat as a floor-turnout election
        total_cast = eligible * TURNOUT_FLOOR

    votes = {fid: int(round(v)) for fid, v in effective.items()}
    vote_share = {fid: (v / total_cast if total_cast else 0.0) for fid, v in effective.items()}
    return {
        "eligible": eligible,
        "effective_votes": effective,
        "votes": votes,
        "vote_share": vote_share,
        "total_cast": int(round(total_cast)),
        "turnout_pct": min(1.0, total_cast / eligible),
        "regional_vote_share": regional_vote_share,
        "regional_turnout": regional_turnout,
        "regional_access": regional_access,
    }


# ── Government formation ─────────────────────────────────────────────────

def _build_coalition_around(seed, factions, threshold) -> Optional[list]:
    """Greedily adds the seed's ideologically nearest partners, in order,
    until a majority is reached. Returns None if even every willing
    partner can't get there."""
    coalition = [seed]
    seats = seed.seats
    if seats >= threshold:
        return coalition

    candidates = sorted(
        [f for f in factions if f.id != seed.id and f.seats > 0],
        key=lambda f: seed.ideology.distance_to(f.ideology),
    )
    for candidate in candidates:
        if seats >= threshold:
            break
        coalition.append(candidate)
        seats += candidate.seats

    return coalition if seats >= threshold else None


def form_government(state):
    """
    Re-forms the government from scratch: largest party tries first,
    cascading down; if nobody reaches a majority the largest governs as a
    minority. Returns (coalition, was_in_government-before-this-call).
    """
    factions = [f for f in state.country.factions if f.seats > 0]
    threshold = state.legislature.majority_threshold()

    for f in state.country.factions:
        f.in_coalition = False

    seed_order = sorted(factions, key=lambda f: -f.seats)
    coalition = None
    for seed in seed_order:
        candidate = _build_coalition_around(seed, factions, threshold)
        if candidate is not None:
            coalition = candidate
            break

    if coalition is None:
        coalition = [seed_order[0]] if seed_order else list(state.country.factions[:1])

    for f in coalition:
        f.in_coalition = True

    ruling = max(coalition, key=lambda f: f.seats)
    state.ruling_faction_id = ruling.id

    # "In government" means LEADING it — being reduced to junior partner is
    # a real loss of office.
    was_in_government = state.player.in_government
    state.player.in_government = (ruling.id == state.player.faction_id)

    return coalition, was_in_government


def _rebuild_cabinet(state, coalition, preferred=None):
    """New ruling party → new cabinet: portfolios cycle across coalition
    members (largest first), using the same candidate generation as
    player-initiated reshuffles."""
    preferred = list(preferred or ())
    state.cabinet.ministers = []
    ordered = sorted(coalition, key=lambda f: -f.seats)
    for i, portfolio in enumerate(CORE_PORTFOLIOS):
        nominee = next((m for m in preferred if m.portfolio == portfolio), None)
        if nominee is not None:
            state.cabinet.ministers.append(nominee)
        else:
            faction = ordered[i % len(ordered)]
            state.cabinet.ministers.append(
                cabinet_ops.generate_candidate(faction, portfolio, state))


def configure_government(state, ruling_faction_id: str, excluded_ids=None):
    """Install a government around a requested lead party.

    Campaign generation uses this for alternate opening results. It follows
    the election system's ideological-neighbour coalition logic.
    """
    excluded = set(excluded_ids or ())
    factions = [f for f in state.country.factions
                if f.seats > 0 and f.id not in excluded]
    seed = next((f for f in factions if f.id == ruling_faction_id), None)
    if seed is None:
        return []

    coalition = _build_coalition_around(
        seed, factions, state.legislature.majority_threshold())
    if coalition is None:
        coalition = [seed]

    for f in state.country.factions:
        f.in_coalition = f in coalition
    state.ruling_faction_id = seed.id
    state.player.in_government = (seed.id == state.player.faction_id)
    _rebuild_cabinet(state, coalition)
    return coalition


# ── Election resolution ──────────────────────────────────────────────────

def hold_election(state, snap: bool = False) -> ElectionResult:
    old_seats = {f.id: f.seats for f in state.country.factions}
    old_ruling_id = state.ruling_faction_id
    total_seats = state.legislature.total_seats

    opposition.prepare_election(state)

    # Who actually turns out decides who wins — seats come from votes cast,
    # not from raw support (see compute_turnout).
    turnout = compute_turnout(state)
    seat_allocation = _allocate_seats(state.country.factions, total_seats,
                                      weights=turnout["effective_votes"])
    for f in state.country.factions:
        f.seats = seat_allocation.get(f.id, 0)
    state.legislature.seat_distribution = dict(seat_allocation)

    coalition, was_in_government = form_government(state)
    government_changed = (state.ruling_faction_id != old_ruling_id)
    if government_changed:
        from engine import domestic_ai
        domestic_ai.lapse_pending_government_bills(state)
        preferred = state.shadow_cabinet.ministers if state.player.in_government else None
        _rebuild_cabinet(state, coalition, preferred=preferred)

    result = ElectionResult(
        turn=state.turn,
        date=state.date_string(),
        was_snap_election=snap,
        seat_changes={fid: seat_allocation.get(fid, 0) - old_seats.get(fid, 0) for fid in old_seats},
        final_seats=dict(seat_allocation),
        support_snapshot={f.id: f.support for f in state.country.factions},
        ruling_faction_id=state.ruling_faction_id,
        coalition_faction_ids=[f.id for f in coalition],
        player_in_government=state.player.in_government,
        player_lost_office=(was_in_government and not state.player.in_government),
        player_gained_office=(not was_in_government and state.player.in_government),
        eligible_voters=turnout["eligible"],
        total_votes_cast=turnout["total_cast"],
        turnout_pct=turnout["turnout_pct"],
        votes_by_faction=dict(turnout["votes"]),
        vote_share_by_faction=dict(turnout["vote_share"]),
        seat_pct_by_faction={fid: (seat_allocation.get(fid, 0) / total_seats if total_seats else 0.0)
                             for fid in seat_allocation},
        regional_vote_share={region_id: dict(shares) for region_id, shares
                             in turnout["regional_vote_share"].items()},
        regional_turnout=dict(turnout["regional_turnout"]),
        regional_access=dict(turnout["regional_access"]),
    )

    if state.player.in_government:
        state.player.elections_won += 1
        state.player.political_capital = min(100.0, state.player.political_capital + 30.0)
        state.player.title = state.campaign_meta.get("government_title", state.player.title)
    else:
        state.player.title = "Opposition Leader"

    opposition.after_election(state, was_in_government)
    if government_changed:
        budget.on_government_change(state)
    if state.player.in_government:
        state.shadow_cabinet.ministers = []

    # An election is a partial reset point: stability moves halfway back
    # toward a neutral 0.55 — softened, not wiped clean.
    state.stability.value = max(0.05, min(0.95, state.stability.value * 0.5 + 0.55 * 0.5))

    state.last_election_turn = state.turn
    state.election_history.append(result)
    _log_election_result(state, result)

    return result


def _log_election_result(state, result: ElectionResult):
    tag = "SNAP ELECTION" if result.was_snap_election else "GENERAL ELECTION"
    ruling = next((f for f in state.country.factions
                   if f.id == result.ruling_faction_id), None)
    state.turn_news.append(("election", {
        "tag": tag,
        "winner_party": ruling.name if ruling else "a new coalition",
        "winner_leader": (ruling.leader if ruling and ruling.leader else "its leadership"),
        "turnout": f"{result.turnout_pct * 100:.1f}",
        "player_won": result.player_in_government,
        "lost_office": result.player_lost_office,
        "gained_office": result.player_gained_office,
    }, f"{tag} — {result.date}"))
    state.log(f"═══ {tag} — {result.date} ═══")
    state.log(f"  Turnout: {result.turnout_pct*100:.1f}%  "
              f"({result.total_votes_cast:,} of {result.eligible_voters:,} eligible)")
    for f in sorted(state.country.factions, key=lambda x: -x.seats):
        change = result.seat_changes.get(f.id, 0)
        arrow = f"+{change}" if change > 0 else str(change)
        gov_tag = "  [GOVERNING]" if f.in_coalition else ""
        seat_pct = result.seat_pct_by_faction.get(f.id, 0.0) * 100
        vote_pct = result.vote_share_by_faction.get(f.id, 0.0) * 100
        state.log(f"  {f.name}: {f.seats} seats ({arrow}) · {seat_pct:.0f}% of chamber · "
                  f"{vote_pct:.1f}% of vote{gov_tag}")

    if result.regional_vote_share:
        state.log("  REGIONAL COUNT")
        faction_names = {faction.id: faction.name for faction in state.country.factions}
        for region_id, shares in result.regional_vote_share.items():
            access = result.regional_access.get(region_id, 0.0)
            if access <= 0.0 or not any(shares.values()):
                state.log(f"    {regions.region_name(region_id)}: no administered poll")
                continue
            winner_id, winner_share = max(shares.items(), key=lambda item: item[1])
            state.log(f"    {regions.region_name(region_id)}: "
                      f"{faction_names.get(winner_id, winner_id)} {winner_share*100:.1f}% · "
                      f"access {access*100:.0f}%")

    if result.player_lost_office:
        state.log(f"⚠ YOU HAVE LOST OFFICE. A new government forms without you.")
        ruling = next((f for f in state.country.factions
                       if f.id == result.ruling_faction_id), None)
        if ruling is not None:
            from engine import flavor
            flavor.say(state, "election_winner_quote",
                       leader=ruling.leader or "Its leadership", party=ruling.name)
    elif result.player_gained_office:
        state.log("YOU HAVE RETURNED TO OFFICE, forming a new government.")
    elif result.player_in_government:
        state.log("Your government has been RETURNED to power.")
    else:
        state.log("You remain in opposition.")


def should_trigger_snap_election(state) -> bool:
    coalition_collapsed = len(state.coalition_faction_ids()) == 0
    stability_catastrophic = state.stability.value <= SNAP_ELECTION_STABILITY_FLOOR
    return coalition_collapsed or stability_catastrophic


def months_until_election(state) -> int:
    return max(0, TERM_LENGTH_TURNS - (state.turn - state.last_election_turn))


def days_until_election(state) -> int:
    """Exact calendar countdown to the month in which the term expires."""
    remaining_months = months_until_election(state)
    if remaining_months <= 0:
        return 0
    month_index = (state.month - 1) + remaining_months
    target_year = state.year + month_index // 12
    target_month = month_index % 12 + 1
    target = date(target_year, target_month, 1)
    return max(0, (target - state.calendar_date()).days)
