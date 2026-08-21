import textwrap

from game_state import GameState
from models.cabinet import CORE_PORTFOLIOS
from engine import elections

MODIFIER_TARGET_LABELS = {
    "gdp_growth": "GDP Growth",
    "unemployment": "Unemployment",
    "inflation": "Inflation",
    "approval_bias": "Public Approval",
    "budget_revenue": "Revenue",
    "budget_expenditure": "Expenditure",
    "workforce_quality": "Workforce Quality",
    "bureaucratic_capacity": "Bureaucratic Capacity",
}

# Targets expressed as rates (shown as %) vs absolute amounts (shown as M)
_RATE_TARGETS = {"gdp_growth", "unemployment", "inflation", "approval_bias",
                  "workforce_quality", "bureaucratic_capacity"}


def format_modifier_value(target: str, value: float) -> str:
    if target in _RATE_TARGETS:
        return f"{value*100:+.2f}%"
    return f"{value:+.0f}M"


def bar(value: float, width: int = 20, fill: str = "█", empty: str = "░") -> str:
    """A simple text progress bar."""
    value = max(0.0, min(1.0, value))
    n = int(value * width)
    return fill * n + empty * (width - n)


def signed(value: float, decimals: int = 2) -> str:
    """Format a float with an explicit sign. Normalizes -0.0 to 0.0 first —
    otherwise Python's own formatting renders it as the confusing "+-0.00"."""
    value = value + 0.0
    return f"+{value:.{decimals}f}" if value >= 0 else f"{value:.{decimals}f}"


def pct(value: float, decimals: int = 1) -> str:
    """Format as a percentage."""
    return f"{value * 100:.{decimals}f}%"


def print_guidance(state: GameState):
    """One note from the guided opening, if any is pending.

    Advisory: printing it changes nothing and dismissing is the player's own
    menu choice, so a player who ignores it entirely plays the same game.
    """
    from engine import onboarding
    entry = onboarding.next_guidance(state)
    if entry is None:
        return
    print(f"\n── THE FIRST NINETY DAYS {'─' * 51}")
    print(f"  {entry['title']}")
    for line in textwrap.wrap(entry["body"], width=74):
        print(f"    {line}")
    where = entry.get("page") or entry.get("region")
    if where:
        print(f"    (see: {where})")


def print_digest(state: GameState):
    """"This month": the prose account of what moved and why
    (engine/digest.py), printed once right after a real monthly advance,
    ahead of the front page/turn log. Silent — prints nothing — on the
    first month of a campaign or a save from before this feature existed,
    since state.last_snapshot is empty in both cases and there is nothing
    yet to compare against.
    """
    if not state.last_snapshot:
        return
    from engine import digest as digest_engine
    after = digest_engine.snapshot(state)
    lines = digest_engine.monthly_digest(state, state.last_snapshot, after)
    if not lines:
        return
    print(f"\n  ── THIS MONTH {'─' * 60}")
    for line in lines:
        print(f"  · {line}")


def print_decision_queue(state: GameState):
    """Terminal rendering of the same ordered queue as the GUI Briefing."""
    from engine import decision_queue

    items = decision_queue.build_queue(state)
    print("\n  ── DECISIONS AND DEADLINES " + "─" * 39)
    if not items:
        print("  Nothing currently requires a decision.")
        return
    for item in items[:10]:
        due = f" · {item.due_text}" if item.due_text else ""
        print(f"  [{item.priority.upper():8}] {item.title}{due}")
        print(f"             {item.detail}  → {item.page} · authority: {item.authority}")
    if len(items) > 10:
        print(f"  + {len(items) - 10} lower-priority item(s)")


def print_political_calendar(state: GameState):
    """Known public dates for the next year; hidden follow-ups stay hidden."""
    from engine import political_calendar

    items = political_calendar.build_calendar(state, horizon_days=365, max_items=12)
    print("\n  ── POLITICAL CALENDAR · NEXT 12 MONTHS " + "─" * 29)
    if not items:
        print("  No public commitments are currently dated.")
        return
    for item in items:
        when = item.date.strftime("%d %b %Y").lstrip("0")
        print(f"  {when:11}  {item.kind.upper():10}  {item.title}")
        print(f"               {item.detail}  → {item.page}")


def print_briefing(state: GameState):
    print_opening_programme(state)
    print_decision_queue(state)
    print_political_calendar(state)


def print_opening_programme(state: GameState):
    """Terminal account of the selected programme and its live progress."""
    from engine import opening_programme

    report = opening_programme.progress(state)
    print("\n  ── FIRST NINETY DAYS " + "─" * 45)
    if report["status"] == "unselected":
        print(f"  No programme chosen · {report['days_remaining']} day(s) remain in the opening window.")
        for programme in opening_programme.candidates(state):
            print(f"  • {programme['name']}: {programme['body']}")
        print("  Choose one through Actions → Leadership.")
        return
    if report["status"] == "missed":
        print("  The opening programme window passed without a declared programme.")
        return

    programme = report["programme"]
    status = report["status"].replace("_", " ").upper()
    timing = (f"{report['days_remaining']} day(s) remain"
              if report["status"] == "active" else status)
    print(f"  {programme['name']} · {report['completed']}/{report['total']} complete · {timing}")
    print(f"  {programme['body']}")
    for task, done in report["tasks"]:
        mark = "✓" if done else "·"
        print(f"  {mark} {task['name']} — {task['body']}  → {task['page']}")


def print_dashboard(state: GameState):
    econ   = state.country.economy
    player = state.player
    leg    = state.legislature
    gov    = state.stability
    W      = 64  # display width

    print("\n" + "═" * W)
    if player.in_government:
        print(f"  {state.country.name.upper()}  ·  {player.title} {player.name}  ·  {state.date_string()}  ·  Turn {state.turn}")
    else:
        ruling = next((f for f in state.country.factions if f.id == state.ruling_faction_id), None)
        ruling_name = ruling.name if ruling else "an unknown party"
        print(f"  {state.country.name.upper()}  ·  {player.name}, OPPOSITION LEADER  ·  {state.date_string()}  ·  Turn {state.turn}")
        print(f"  Governing party: {ruling_name}")
    print("═" * W)

    # ── Player status ───────────────────────────────────────────
    print(f"\n  APPROVAL      {bar(player.approval)}  {pct(player.approval)}")
    from engine.turn import political_upkeep
    upkeep, _ = political_upkeep(state)
    upkeep_note = f"  (upkeep -{upkeep:.1f}/mo)" if upkeep > 0 else ""
    print(f"  POL. CAPITAL  {bar(player.political_capital / 100)}  {player.political_capital:.0f} / 100{upkeep_note}")
    trend_arrow = "▲" if gov.trend > 0.002 else ("▼" if gov.trend < -0.002 else "─")
    print(f"  STABILITY     {bar(gov.value)}  {gov.value:.2f}  {gov.label()} {trend_arrow}")
    from engine import roleplay
    rival = roleplay.current_rival(state)
    if rival is not None and rival.leader:
        print(f"  RIVAL         {rival.leader}  ({rival.name})")

    # ── Economy ─────────────────────────────────────────────────
    print(f"\n  ── ECONOMY {'─' * (W - 12)}")
    print(f"  GDP           {econ.gdp:>12,.0f} M")
    print(f"  Growth        {signed(econ.growth_rate * 100)}% annual")
    print(f"  Inflation     {pct(econ.inflation)}")
    print(f"  Unemployment  {pct(econ.unemployment)}")
    print(f"  Workforce Q.  {bar(econ.workforce_quality, width=10)}  {econ.workforce_quality:.2f}")
    print(f"  Bureaucracy   {bar(state.country.bureaucratic_capacity, width=10)}  {state.country.bureaucratic_capacity:.2f}")
    bal = econ.budget.balance
    print(f"  Budget        {signed(bal, 0)} M  ({'surplus' if bal >= 0 else 'DEFICIT'})")
    print(f"  Debt / GDP    {pct(econ.public_debt_pct, 0)}")
    if econ.loans:
        print(f"  Debt Service  {econ.total_debt_service():>+.0f} M/yr  ({len(econ.loans)} active loan(s))")

    if state.households:
        from engine import households
        from content.households import GROUP_BY_ID
        from content.regions import ARDENIA_REGION_PROFILES
        print(f"\n  ── HOUSEHOLD ECONOMY {'─' * (W - 23)}")
        print(f"  Real income   {households.national_real_income(state)*100:>6.1f}  (start = 100)")
        print(f"  Living costs  {households.national_living_cost(state)*100:>6.1f}  (start = 100)")
        print(f"  Hardship      {households.national_hardship(state)*100:>6.1f}% pressure")
        print(f"  Services      {households.national_service_access(state)*100:>6.1f}% access")
        print(f"  Confidence    {households.national_confidence(state)*100:>6.1f}%")
        for household in households.hardest_hit(state, 3):
            group_name = GROUP_BY_ID[household.group_id]["name"]
            region_name = ARDENIA_REGION_PROFILES[household.region_id]["name"]
            print(f"  • {group_name}, {region_name}: {household.status_label().lower()} "
                  f"(income {household.real_income_index*100:.0f}, "
                  f"services {household.service_access*100:.0f}%)")

    # ── Legislature ──────────────────────────────────────────────
    coalition_ids    = state.coalition_faction_ids()
    coalition_seats  = leg.coalition_seats(coalition_ids)
    majority         = leg.majority_threshold()

    print(f"\n  ── LEGISLATURE  (majority: {majority} of {leg.total_seats} seats) {'─' * 16}")
    seat_bar_fill = coalition_seats / leg.total_seats
    print(f"  Coalition     {bar(seat_bar_fill)}  {coalition_seats} / {leg.total_seats} seats")
    if coalition_seats < majority:
        shortfall = majority - coalition_seats
        print(f"  ⚠  MINORITY GOVERNMENT — need {shortfall} more seat(s) for majority")
    months_left = elections.months_until_election(state)
    print(f"  Next election in {months_left} month(s)"
          f"{'  ⚠ collapse risk — could come sooner' if elections.should_trigger_snap_election(state) else ''}")

    # ── Government stability breakdown ────────────────────────────
    if gov.breakdown:
        print(f"\n  ── GOVERNMENT STABILITY {'─' * (W - 25)}")
        for name, contribution in gov.breakdown.items():
            print(f"  {name:<22} {signed(contribution):>7}")
        if state.stability.value < 0.30:
            print(f"  ⚠  CRISIS — confidence vote risk rising")

    # ── Factions ─────────────────────────────────────────────────
    print(f"\n  ── FACTIONS {'─' * (W - 13)}")
    print(f"  {'NAME':<24} {'SEATS':>5} {'SUPPORT':>8}  {'LOYALTY':>17}  {'POWER':>5}  STATUS")
    print(f"  {'─' * (W - 2)}")
    for f in sorted(state.country.factions, key=lambda x: -x.seats):
        loyalty_display = bar(max(0.0, f.loyalty), width=8)
        loyalty_num     = f"{f.loyalty:+.2f}"
        if f.in_coalition:
            status = "COALITION"
        elif f.is_hostile():
            status = "HOSTILE"
        else:
            status = "neutral"
        gp = f.grievance_pressure()
        grievance_flag = " ⚠" if gp > 0.5 else ""
        print(f"  {f.name:<24} {f.seats:>5} {f.support*100:>7.1f}%  {loyalty_display} {loyalty_num:>6}  "
              f"{f.power:.2f}   {status}{grievance_flag}")

    # ── Party wings ──────────────────────────────────────────────
    parties_with_wings = [f for f in state.country.factions if len(f.wings) >= 2]
    if parties_with_wings:
        print(f"\n  ── PARTY WINGS {'─' * (W - 16)}")
        for f in sorted(parties_with_wings, key=lambda x: -x.seats):
            dom = f.dominant_wing()
            print(f"  {f.name}  ({f.effective_ideology().label()}, cohesion {f.cohesion()*100:.0f}%)")
            for w in sorted(f.wings, key=lambda x: -x.strength):
                lead = " ★" if dom and w.id == dom.id else "  "
                print(f"   {lead} {w.name:<26} {bar(w.strength, width=10)} {w.strength*100:>4.0f}%  "
                      f"loy {w.loyalty:+.2f}")

    # ── Cabinet ──────────────────────────────────────────────────
    print(f"\n  ── CABINET {'─' * (W - 12)}")
    print(f"  {'PORTFOLIO':<18} {'MINISTER':<20} {'COMP':>5}  {'LOY':>5}  RISK")
    print(f"  {'─' * (W - 2)}")
    for portfolio in CORE_PORTFOLIOS:
        m = state.cabinet.get(portfolio)
        if m is None:
            print(f"  {portfolio:<18} {'— VACANT —':<20} {'':>5}   {'':>5}   ⚠ vacant")
        else:
            risk = "⚠ HIGH" if m.threat_level() > 0.5 else ""
            print(f"  {portfolio:<18} {m.name:<20} {m.competence:.2f}   {m.loyalty:.2f}   {risk}")

    # ── Active legislation ────────────────────────────────────────
    if leg.active_laws:
        print(f"\n  ── ACTIVE LEGISLATION {'─' * (W - 23)}")
        for law in leg.active_laws:
            tier_tag = {"constitutional": "C", "statutory": "S", "executive_order": "E"}.get(law.tier, "?")
            print(f"  [{tier_tag}] {law.name:<40} (month {law.turns_active})")

    # ── Pending legislation ──────────────────────────────────────
    if leg.pending_bills:
        print(f"\n  ── PENDING LEGISLATION {'─' * (W - 24)}")
        for law in leg.pending_bills:
            tier_tag = {"constitutional": "C", "statutory": "S", "executive_order": "E"}.get(law.tier, "?")
            lobby_note = f", {len(law.lobbying_bonus)} faction(s) lobbied" if law.lobbying_bonus else ""
            print(f"  [{tier_tag}] {law.name:<40} (awaiting vote{lobby_note})")

    # ── Active loans ──────────────────────────────────────────────
    if econ.loans:
        print(f"\n  ── ACTIVE LOANS {'─' * (W - 17)}")
        for loan in econ.loans:
            lender = state.world_country(loan.lender_id)
            lender_name = lender.name if lender else loan.lender_id
            print(f"  {lender_name:<18} {loan.principal:>8,.0f}M @ {loan.annual_interest_rate*100:>4.1f}%   "
                  f"{loan.months_remaining():>3} mo remaining")

    # ── Long-term effects in motion ─────────────────────────────────
    if state.modifiers:
        print(f"\n  ── LONG-TERM EFFECTS IN MOTION {'─' * (W - 32)}")
        for m in sorted(state.modifiers, key=lambda x: (x.source, x.target)):
            label = MODIFIER_TARGET_LABELS.get(m.target, m.target)
            value = format_modifier_value(m.target, m.current_value())
            phase = m.phase_label()
            print(f"  {m.source:<32} {label:<16} {value:>8}  {phase}")

    # ── World ─────────────────────────────────────────────────────
    if state.world:
        print(f"\n  ── WORLD RELATIONS {'─' * (W - 20)}")
        print(f"  {'COUNTRY':<20} {'REGIME':<26} {'RELATION':>10}  TRADE")
        print(f"  {'─' * (W - 2)}")
        for wc in state.world:
            rel = state.country.get_relation(wc.id)
            if rel:
                status  = rel.status_label()
                trade   = f"{rel.trade_volume:,.0f} M"
            else:
                status  = "unknown"
                trade   = "—"
            print(f"  {wc.name:<20} {wc.regime_type:<26} {status:>10}  {trade}")

    # ── Front page + turn log ─────────────────────────────────────
    if state.turn_log:
        from engine import press
        page = press.front_page(state)
        print(f"\n  ── {page['masthead'].upper()} · {page['dateline']} {'─' * max(1, W - len(page['masthead']) - len(page['dateline']) - 10)}")
        print(f"  ▌ {page['lead']['headline']}")
        for h in page["headlines"][:2]:
            print(f"  ▪ {h}")
        print(f"\n  ── THIS TURN {'─' * (W - 14)}")
        for entry in state.turn_log:
            print(f"  · {entry}")

    print("\n" + "═" * W + "\n")
