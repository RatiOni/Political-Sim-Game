import random
from datetime import date, timedelta

from game_state import GameState
from engine import (stability, elections, events, worldsim, crisis, parties,
                    flavor, roleplay, domestic_ai, opposition, regions, budget,
                    ministries, households, digest)
from models.country import REGIME_FAMILIES  # shared regime taxonomy (relation drift)
from models.relations import MAX_TRADE_VOLUME, cap_trade_volume

TREND_GROWTH = 0.02             # "normal" annual growth, used by the Okun's-law unemployment link
BASE_WORKFORCE_QUALITY = 0.5    # workforce_quality baseline before any long-term modifiers
BASE_BUREAUCRATIC_CAPACITY = 0.75  # bureaucratic_capacity baseline before any long-term modifiers
WORKFORCE_GROWTH_FACTOR = 0.03  # max structural growth bonus/penalty from workforce quality at the extremes
TRADE_CUSTOMS_RATE = 0.05       # annual revenue contribution per unit of active trade volume
TRADE_VOLUME_CEILING = MAX_TRADE_VOLUME   # max trade volume at a perfect (1.0) relationship
TRADE_VOLUME_APPROACH = 0.04    # monthly fraction of the gap to that ceiling closed
SUPPORT_DRIFT_RATE = 0.006      # max monthly electoral-support share shift from performance alone

# Organic inflation (monthly drift on the structural rate):
INFLATION_ANCHOR = 0.02             # long-run credibility anchor the rate reverts toward
INFLATION_REVERSION = 0.008         # monthly pull toward the anchor
DEFICIT_INFLATION_FACTOR = 0.003    # monthly push per unit of deficit-to-revenue ratio
OVERHEAT_INFLATION_FACTOR = 0.010   # monthly push per unit of growth above trend
STRUCTURAL_INFLATION_MAX = 0.60     # hyperinflation ceiling for the structural rate


# Governing overhead: what each standing commitment costs from the monthly
# political-capital gain. The floor guarantees a government is never fully
# paralysed — but an empire of laws and treaties governs slowly.
PC_UPKEEP_LAW = 0.8
PC_UPKEEP_TREATY = 0.6
PC_UPKEEP_SANCTIONS = 1.0
PC_REGEN_FLOOR = 3.0


def political_upkeep(state):
    """(total, breakdown) — the PC-per-turn cost of everything the
    government currently maintains. Shared by the turn engine and both UIs."""
    laws = len(state.legislature.active_laws)
    treaties = sum(len(r.treaties) for r in state.country.relations.values())
    sanctions = sum(1 for r in state.country.relations.values() if r.sanctioned)
    breakdown = {
        "laws": laws * PC_UPKEEP_LAW,
        "treaties": treaties * PC_UPKEEP_TREATY,
        "sanctions": sanctions * PC_UPKEEP_SANCTIONS,
    }
    return sum(breakdown.values()), breakdown


class TurnEngine:
    """
    Advances the exact calendar by days while running the established heavy
    simulation as a monthly pulse. ``advance_day`` drives the live GUI clock;
    ``advance`` remains the one-month compatibility entry point used by the
    terminal frontend and mechanics tests. Monthly phases run in order:

      1. Advance time
      2. Apply a voted annual budget, or a continuing settlement, at January rollover
      3. Regenerate political capital
      4. If the player is in opposition, advance the domestic government's
         legislative programme (introduction → response window → vote)
      5. Recalculate ministry workload, capacity, delivery and backlog
      6. Update economy (workforce → sectors → fiscal baseline → organic
         inflation → modifiers onto headline stats → compound GDP)
      7. Player↔world relation drift + trade growth
      8. World simulation — other countries drift, relate, act (engine/worldsim.py)
      9. Process loans
     10. Faction loyalty drift
     11. Age grievances
     12. Update regional labour, state reach and pressure (engine/regions.py)
     13. Update household incomes, costs, security, services and confidence
     14. Recalculate approval, then government stability (engine/stability.py)
     15. Cabinet update and scandal check
     16. Protest check
     17. Forced confidence-vote check
     18. Civil-war pressure check (engine/crisis.py)
     19. National electoral support drift, regional electorate movement, then
         intra-party wing drift (engine/parties.py)
     20. Snap election check, then scheduled election check
     21. Track active law duration
     22. Dynamic event check (engine/events.py), then the rival's jibe
         watch (engine/roleplay.py)
     23. Age modifiers, then pending events — always last, so this turn's
         calculations used start-of-turn values.
    """

    def __init__(self):
        self.last_advance_monthly = False

    def advance_day(self, state: GameState) -> GameState:
        """Advance one calendar day, running a monthly pulse at rollover."""
        state.turn_log.clear()
        state.turn_news.clear()
        previous_month = state.month
        self._advance_calendar_day(state)
        state.day_index += 1
        # The first genuinely daily subsystem: opposition-facing government
        # legislation can be introduced and voted between month boundaries.
        self._simulate_domestic_government(state)
        self.last_advance_monthly = state.month != previous_month
        if self.last_advance_monthly:
            self._run_monthly_pulse(state)
        return state

    def advance(self, state: GameState) -> GameState:
        """Advance directly to the first day of the next month.

        This stable API preserves the old monthly semantics for the CLI and
        existing integrations while the GUI uses ``advance_day``.
        """
        state.turn_log.clear()
        state.turn_news.clear()
        self._advance_to_next_month(state)
        self.last_advance_monthly = True
        self._run_monthly_pulse(state)
        return state

    def _run_monthly_pulse(self, state: GameState):
        # Captured before anything below mutates state, so it is exactly
        # last month's ending position — the "before" half of the digest a
        # caller builds once this pulse returns (engine/digest.py). Persisted
        # on GameState so it survives save/load; overwritten fresh every
        # pulse, never accumulated.
        state.last_snapshot = digest.snapshot(state)
        state.turn += 1  # first, so state.turn == "the turn being processed" throughout
        # A new month is a fresh diary: whatever the government committed its
        # attention to last month is spent and gone. Deliberately a reset, not
        # an accrual — unspent attention does not bank (engine/player_ops.py:
        # MONTHLY_ATTENTION).
        state.attention_spent = 0
        budget.process_fiscal_year(state)
        self._regenerate_political_capital(state)
        self._simulate_domestic_government(state)
        opposition.monthly_update(state)
        ministries.simulate_ministries(state)
        self._update_economy(state)
        self._update_relations(state)
        self._simulate_world(state)
        self._process_loans(state)
        self._update_faction_loyalty(state)
        self._age_grievances(state)
        regions.simulate_regions(state)
        households.simulate_households(state)
        self._update_approval(state)
        self._update_stability(state)
        self._update_ministers(state)
        self._minister_crisis_check(state)
        self._check_protests(state)
        self._check_confidence_vote(state)
        self._check_civil_war(state)
        self._update_faction_support(state)
        regions.update_party_support(state)
        self._update_party_wings(state)
        self._check_snap_election(state)
        self._check_scheduled_election(state)
        self._track_active_laws(state)
        self._check_for_new_events(state)
        self._rival_watch(state)
        self._age_modifiers(state)
        self._age_pending_events(state)

    # ── Long-term modifier plumbing ──────────────────────────────────────────

    def _modifiers_sum(self, state: GameState, target: str) -> float:
        """Fresh sum of every active modifier's current contribution to a stat —
        recomputed each turn, never accumulated, so effects stay bounded."""
        total = 0.0
        for m in state.modifiers:
            if m.target != target:
                continue
            value = m.current_value()
            if m.institutional:
                value *= self._implementation_quality_for(state, m.portfolio)
            total += value
        return total

    def _implementation_quality_for(self, state: GameState, portfolio) -> float:
        """Minister competence/loyalty (0.35 floor when vacant, 1.0 when no
        portfolio applies) dampened — not multiplied down — by general
        government capacity (bureaucracy, cabinet risk, stability)."""
        if portfolio is None:
            minister_component = 1.0
        else:
            minister = state.cabinet.get(portfolio)
            minister_component = 0.35 if minister is None else minister.implementation_quality()

        capacity = state.country.bureaucratic_capacity
        corruption_drag = stability.compute_cabinet_risk_fraction(state) * 0.3
        institutional_health = max(0.0, min(1.0,
            (capacity - corruption_drag) * 0.5 + state.stability.value * 0.5))
        dampener = 0.5 + 0.5 * institutional_health

        return (minister_component * dampener
                * ministries.policy_delivery_factor(state, portfolio))

    def _age_modifiers(self, state: GameState):
        still_active = []
        for m in state.modifiers:
            m.age += 1
            if m.is_expired():
                flavor.say(state, "modifier_expired", source=m.source, target=m.target)
            else:
                still_active.append(m)
        state.modifiers = still_active

    # ── Phases ─────────────────────────────────────────────────────────────

    def _advance_calendar_day(self, state: GameState):
        next_day = state.calendar_date() + timedelta(days=1)
        state.year, state.month, state.day = (
            next_day.year, next_day.month, next_day.day)

    def _advance_to_next_month(self, state: GameState):
        current = state.calendar_date()
        if state.month == 12:
            next_month = date(state.year + 1, 1, 1)
        else:
            next_month = date(state.year, state.month + 1, 1)
        state.day_index += (next_month - current).days
        state.year, state.month, state.day = (
            next_month.year, next_month.month, next_month.day)

    def _regenerate_political_capital(self, state: GameState):
        """PC regen from approval, coalition loyalty, and stability — read as
        they stand at the start of the turn (last turn's ending values) —
        minus governing overhead: every standing law, treaty, and sanctions
        regime consumes a slice of the government's attention."""
        approval_bonus = (state.player.approval - 0.5) * 10.0

        coalition_ids = state.coalition_faction_ids()
        coalition_loyalty = 0.0
        if coalition_ids:
            members = [f for f in state.country.factions if f.id in coalition_ids]
            if members:
                coalition_loyalty = sum(f.loyalty for f in members) / len(members)
        coalition_bonus = coalition_loyalty * 5.0

        stability_bonus = (state.stability.value - 0.5) * 4.0

        upkeep, _detail = political_upkeep(state)
        regen = (state.player.pc_regen_base + approval_bonus + coalition_bonus
                 + stability_bonus - upkeep)
        regen = max(PC_REGEN_FLOOR, regen)
        state.player.political_capital = min(100.0, state.player.political_capital + regen)
        # No dispatch: PC is bookkeeping, visible on the stat bar and turn summary.

    def _update_economy(self, state: GameState):
        self._update_workforce_quality(state)
        self._update_bureaucratic_capacity(state)
        self._update_sectors(state)
        self._update_structural_fiscal_baseline(state)
        self._update_structural_inflation(state)
        self._apply_modifiers_to_headline_stats(state)
        self._compound_gdp(state)

    def _simulate_domestic_government(self, state: GameState):
        domestic_ai.simulate_domestic_government(state)

    def _update_workforce_quality(self, state: GameState):
        """Slow-moving stat driven only by long-term modifiers (e.g. education reform)."""
        econ = state.country.economy
        econ.workforce_quality = max(0.0, min(1.0,
            BASE_WORKFORCE_QUALITY + self._modifiers_sum(state, "workforce_quality")))

    def _update_bureaucratic_capacity(self, state: GameState):
        """Live modifier target, same pattern as workforce quality."""
        state.country.bureaucratic_capacity = max(0.0, min(1.0,
            BASE_BUREAUCRATIC_CAPACITY + self._modifiers_sum(state, "bureaucratic_capacity")))

    def _update_sectors(self, state: GameState):
        """Sectors + workforce quality set the STRUCTURAL growth rate; sector
        fortunes shift GDP/employment shares and aligned factions' power."""
        econ = state.country.economy
        if not econ.sectors:
            return

        weighted_growth = sum(s.gdp_share * s.growth_rate for s in econ.sectors)
        workforce_bonus = (econ.workforce_quality - 0.5) * WORKFORCE_GROWTH_FACTOR
        target_growth = weighted_growth + workforce_bonus
        econ.structural_growth_rate += (target_growth - econ.structural_growth_rate) * 0.25

        for sector in econ.sectors:
            relative = sector.growth_rate - weighted_growth
            sector.gdp_share = max(0.01, sector.gdp_share + relative * 0.01)
            sector.employment_share = max(0.01, sector.employment_share +
                                           (sector.gdp_share - sector.employment_share) * 0.04)

        total_gdp_share = sum(s.gdp_share for s in econ.sectors)
        total_emp_share = sum(s.employment_share for s in econ.sectors)
        if total_gdp_share > 0:
            for s in econ.sectors:
                s.gdp_share /= total_gdp_share
        if total_emp_share > 0:
            for s in econ.sectors:
                s.employment_share /= total_emp_share

        for sector in econ.sectors:
            for fid in sector.aligned_faction_ids:
                faction = next((f for f in state.country.factions if f.id == fid), None)
                if faction:
                    faction.power = max(0.0, min(1.0, faction.power + sector.growth_rate * 0.015))

    def _update_structural_fiscal_baseline(self, state: GameState):
        """Tax/cost base drift with GDP; customs revenue recomputed fresh from
        current trade volume so it tracks relationships instead of ratcheting."""
        econ = state.country.economy
        monthly_structural_growth = econ.structural_growth_rate / 12.0
        econ.structural_revenue *= (1.0 + monthly_structural_growth)
        econ.structural_expenditure *= (1.0 + monthly_structural_growth)
        budget.sync_active_total(state, econ.structural_expenditure)

        total_trade_revenue = 0.0
        for rel in state.country.relations.values():
            if any(t.type == "trade" for t in rel.treaties):
                total_trade_revenue += rel.trade_volume * TRADE_CUSTOMS_RATE
        econ.trade_revenue_contribution = total_trade_revenue

    def _update_structural_inflation(self, state: GameState):
        """Organic inflation: deficits push it up, overheating growth pushes it
        up, an anchor pulls it toward ~2%. Reads start-of-turn budget figures."""
        econ = state.country.economy
        revenue = max(1.0, econ.budget.revenue)
        deficit_ratio = (econ.budget.expenditure - econ.budget.revenue) / revenue
        deficit_ratio = max(-0.5, min(1.5, deficit_ratio))
        overheat = econ.growth_rate - TREND_GROWTH

        drift = (deficit_ratio * DEFICIT_INFLATION_FACTOR
                 + overheat * OVERHEAT_INFLATION_FACTOR
                 + (INFLATION_ANCHOR - econ.structural_inflation) * INFLATION_REVERSION)
        econ.structural_inflation = max(0.0, min(STRUCTURAL_INFLATION_MAX,
                                                 econ.structural_inflation + drift))

    def _apply_modifiers_to_headline_stats(self, state: GameState):
        """Effective stats = structural baseline + active modifiers, assigned
        fresh (`=`, never `+=`) so long-lived laws can't compound on themselves."""
        econ = state.country.economy

        econ.growth_rate = econ.structural_growth_rate + self._modifiers_sum(state, "gdp_growth")
        econ.growth_rate = max(-0.15, min(0.20, econ.growth_rate))

        # Unemployment: the structural level is nudged by an Okun's-law-style
        # link to the EFFECTIVE growth rate (so policy-driven growth gains
        # eventually show up here too), then policy modifiers are layered on.
        growth_gap = econ.growth_rate - TREND_GROWTH
        econ.structural_unemployment -= growth_gap * 0.3
        econ.structural_unemployment = max(0.01, min(0.50, econ.structural_unemployment))
        econ.unemployment = econ.structural_unemployment + self._modifiers_sum(state, "unemployment")
        econ.unemployment = max(0.01, min(0.50, econ.unemployment))

        # structural_inflation moves organically each turn (deficits, overheating,
        # anchor — see _update_structural_inflation); policy modifiers layer on top.
        econ.inflation = econ.structural_inflation + self._modifiers_sum(state, "inflation")
        econ.inflation = max(0.0, min(1.0, econ.inflation))

        econ.budget.revenue = (econ.structural_revenue + econ.trade_revenue_contribution
                                + self._modifiers_sum(state, "budget_revenue"))
        econ.budget.expenditure = econ.structural_expenditure + self._modifiers_sum(state, "budget_expenditure")

    def _compound_gdp(self, state: GameState):
        econ = state.country.economy
        monthly_growth = econ.growth_rate / 12.0
        econ.gdp *= (1.0 + monthly_growth)

        if abs(monthly_growth) > 0.003:
            direction = "grew" if monthly_growth > 0 else "contracted"
            flavor.say(state, "economy_move",
                       direction=direction, pct=f"{abs(monthly_growth)*100:.2f}")

    def _update_relations(self, state: GameState):
        """Player↔world drift by regime alignment; trade treaties grow their own
        volume (its budget contribution lands in the fiscal baseline phase)."""
        player = state.country

        for other in state.world:
            rel = player.relations.get(other.id)
            if rel is None:
                continue

            same_camp = REGIME_FAMILIES.get(player.regime_type) == REGIME_FAMILIES.get(other.regime_type)
            drift = 0.0015 if same_camp else -0.0008
            rel.score = max(-1.0, min(1.0, rel.score + drift))

            other_rel = other.relations.get(player.id)
            if other_rel:
                other_rel.score = rel.score

            if (rel.treaties and any(t.type == "trade" for t in rel.treaties)
                    and not rel.sanctioned):
                # Trade saturates: a partner economy is finite, so volume
                # converges on a ceiling set by how warm the relationship is
                # rather than compounding forever. The same approach runs in
                # reverse when relations cool, so trade decays without a
                # separate branch.
                ceiling = max(0.0, rel.score) * TRADE_VOLUME_CEILING
                rel.trade_volume = cap_trade_volume(
                    rel.trade_volume + (ceiling - rel.trade_volume) * TRADE_VOLUME_APPROACH)
                if other_rel:
                    other_rel.trade_volume = rel.trade_volume

    def _process_loans(self, state: GameState):
        """Amortise loans; retire finished ones (their interest Modifier expires
        on its own — its hold_duration matches the loan term)."""
        econ = state.country.economy
        still_active = []
        for loan in econ.loans:
            loan.months_elapsed += 1
            if loan.is_due():
                econ.public_debt_pct = max(0.0, econ.public_debt_pct - loan.principal / econ.gdp)
                lender = state.world_country(loan.lender_id)
                lender_name = lender.name if lender else loan.lender_id
                state.log(f"Loan from {lender_name} (originally {loan.principal:.0f}M) "
                          f"fully repaid — debt servicing costs end.")
            else:
                still_active.append(loan)
        econ.loans = still_active

    def _update_faction_loyalty(self, state: GameState):
        """Loyalty drifts toward an ideological-distance baseline — political
        gravity, independent of events."""
        pe = state.player.ideology_economic
        ps = state.player.ideology_social

        for faction in state.country.factions:
            fe = faction.ideology.economic
            fs = faction.ideology.social

            distance = ((fe - pe) ** 2 + (fs - ps) ** 2) ** 0.5
            max_distance = 2.83

            baseline = 1.0 - (distance / max_distance) * 2.0
            baseline = max(-1.0, min(1.0, baseline))

            # A seat at the cabinet table matters to coalition partners:
            # represented ones warm slightly; shut-out ones sour.
            if faction.in_coalition and faction.id != state.player.faction_id:
                has_seat = any(m.faction_id == faction.id
                               for m in state.cabinet.ministers)
                faction.loyalty = max(-1.0, min(1.0, faction.loyalty
                                                + (0.002 if has_seat else -0.004)))

            drift_rate = 0.015
            faction.loyalty += (baseline - faction.loyalty) * drift_rate
            faction.loyalty = max(-1.0, min(1.0, faction.loyalty))

    def _age_grievances(self, state: GameState):
        for faction in state.country.factions:
            for grievance in faction.grievances:
                grievance.turns_active += 1
                if grievance.turns_active > 4:
                    grievance.severity = min(1.0, grievance.severity + 0.015)

    def _update_ministers(self, state: GameState):
        """Personality drift + early warnings. Schemers learn and hunger;
        loyalists never waver below their floor; a minister whose threat has
        crossed the line briefs against you BEFORE the scandal roll can
        claim them (per-portfolio cooldown so it doesn't nag)."""
        from models.cabinet import trait_effect
        for m in state.cabinet.ministers:
            grow = trait_effect(m.trait, "grows", None)
            if grow:
                m.competence = min(0.90, m.competence + grow[0])
                m.ambition = min(0.95, m.ambition + grow[1])
            drift = trait_effect(m.trait, "loyalty_drift", 0.0)
            if drift:
                m.loyalty = max(0.05, min(1.0, m.loyalty + drift))
            floor = trait_effect(m.trait, "loyalty_floor", None)
            if floor is not None and m.loyalty < floor:
                m.loyalty = floor
            if m.threat_level() > 0.5:
                key = f"minister_warn_{m.portfolio}"
                last = state.cooldowns.get(key)
                if last is None or state.turn - last >= 6:
                    state.cooldowns[key] = state.turn
                    flavor.say(state, "minister_restless",
                               minister=m.name, portfolio=m.portfolio,
                               trait=m.trait_label() or "minister")

    def _minister_crisis_check(self, state: GameState):
        """Scandal roll per threatening minister; instability amplifies the
        chance, and a resignation costs loyalty, approval, and stability."""
        instability_multiplier = 1.0 + (1.0 - state.stability.value) * 1.5

        for minister in list(state.cabinet.ministers):
            risk = minister.threat_level()
            if risk < 0.5:
                continue
            chance = (risk - 0.5) * 0.12 * instability_multiplier
            if random.random() < chance:
                state.cabinet.ministers.remove(minister)
                faction = next((f for f in state.country.factions if f.id == minister.faction_id), None)
                if faction:
                    faction.loyalty = max(-1.0, faction.loyalty - 0.1)
                state.player.approval = max(0.0, state.player.approval - 0.03)
                state.stability.value = max(0.05, state.stability.value - 0.08)
                flavor.say(state, "scandal",
                           minister=minister.name, portfolio=minister.portfolio,
                           faction=faction.name if faction else "their own principles")

    def _update_approval(self, state: GameState):
        """Lagging lerp toward a target set by the shared economic signal,
        power-weighted faction loyalty, and active approval_bias modifiers."""
        econ = state.country.economy
        econ_signal = stability.compute_economic_signal(econ)

        total_power = sum(f.power for f in state.country.factions)
        if total_power > 0:
            weighted = sum(f.loyalty * f.power for f in state.country.factions)
            faction_signal = weighted / total_power
        else:
            faction_signal = 0.0

        approval_bias = self._modifiers_sum(state, "approval_bias")

        household_mood = (households.national_confidence(state) - 0.5) * 2.0
        if not state.player.in_government:
            household_mood *= -1.0

        target = (0.5 + econ_signal * 0.25 + faction_signal * 0.15
                  + household_mood * 0.12 + approval_bias)
        target = max(0.05, min(0.95, target))

        state.player.approval += (target - state.player.approval) * 0.05

    def _update_stability(self, state: GameState):
        """Lerp toward compute_target_stability's aggregate (engine/stability.py),
        same slow-moving idiom as approval."""
        target, breakdown = stability.compute_target_stability(state)
        old_value = state.stability.value
        state.stability.value += (target - old_value) * 0.06
        state.stability.trend = state.stability.value - old_value
        state.stability.breakdown = breakdown

    def _check_protests(self, state: GameState):
        stability.maybe_trigger_protest(state)

    def _check_confidence_vote(self, state: GameState):
        stability.maybe_trigger_confidence_vote(state)

    def _update_faction_support(self, state: GameState):
        """Electoral support (distinct from loyalty) drifts on the shared
        performance signal (stability.faction_performance_signal); legislation's
        one-time nudge happens at passage in engine/legislative.py."""
        for faction in state.country.factions:
            performance = stability.faction_performance_signal(state, faction)
            faction.support += performance * SUPPORT_DRIFT_RATE
            faction.support = max(0.01, min(0.85, faction.support))

        total = sum(f.support for f in state.country.factions)
        if total > 0:
            for f in state.country.factions:
                f.support /= total

    def _check_snap_election(self, state: GameState):
        if elections.should_trigger_snap_election(state):
            elections.hold_election(state, snap=True)

    def _check_scheduled_election(self, state: GameState):
        if state.last_election_turn == state.turn:
            return  # a snap election already fired this exact turn
        if state.turn - state.last_election_turn >= elections.TERM_LENGTH_TURNS:
            elections.hold_election(state, snap=False)

    def _track_active_laws(self, state: GameState):
        for law in state.legislature.active_laws:
            law.turns_active += 1

    def _update_party_wings(self, state: GameState):
        parties.update_party_wings(state)

    def _simulate_world(self, state: GameState):
        worldsim.simulate_world(state)

    def _check_civil_war(self, state: GameState):
        crisis.maybe_trigger_civil_war(state)

    def _check_for_new_events(self, state: GameState):
        events.check_for_events(state)

    def _rival_watch(self, state: GameState):
        roleplay.rival_watch(state)

    def _age_pending_events(self, state: GameState):
        events.age_pending_events(state)
