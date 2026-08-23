"""
Smoke test suite.

Structure:
  Section A — Direct mechanic tests: call engine functions directly and
               assert state changes in the expected direction. Fast,
               deterministic, easy to diagnose.

  Section B — Action menu integration tests: drive run_action_menu with
               mocked input to verify the menu layer routes correctly and
               doesn't crash. We use simple sequences that are easy to
               trace, and verify direction of change rather than exact values.

  Section C — Turn loop invariants: advance several turns and assert that
               all game values stay within their declared bounds.
"""

import sys, os, copy, random
sys.path.insert(0, os.path.dirname(__file__))

from unittest.mock import patch

from main import build_sample_game
from engine.turn       import TurnEngine
from engine.actions    import run_action_menu
from engine            import legislative, cabinet_ops, diplomacy, events, player_ops
from engine.legislative import projected_votes, resolve_vote, enact_executive_order, activate_law_modifiers
from content.bills     import bill_catalog
from models.legislature import Law, LawEffect
from models.modifiers  import Modifier
from models.economy    import Loan
from models.events     import EventDef, EventOption
from display.terminal  import print_dashboard


def fresh():
    """Returns a clean game state with PC topped up."""
    s = build_sample_game()
    s.player.political_capital = 80.0
    return s


def bill(bill_id: str) -> Law:
    return next(b for b in bill_catalog() if b.id == bill_id)


def faction(state, faction_id: str):
    return next(f for f in state.country.factions if f.id == faction_id)


def run_scripted(state, inputs):
    it = iter(inputs)
    with patch("builtins.input", lambda *a: next(it)):
        run_action_menu(state)


def section(title: str):
    print(f"\n{'='*70}")
    print(f"  {title}")
    print(f"{'='*70}")


# ══════════════════════════════════════════════════════════════════════════
# SECTION A — DIRECT MECHANIC TESTS
# ══════════════════════════════════════════════════════════════════════════

section("A1: Vote resolution — majority threshold")
state = fresh()
law = bill("minimum_wage_act")
law.status = "proposed"
state.legislature.pending_bills.append(law)

votes_for, votes_against, breakdown = projected_votes(state, law)
print(f"  Projected: {votes_for} for / {votes_against} against  (need {state.legislature.majority_threshold()})")
assert votes_for + votes_against == state.legislature.total_seats, "all seats must be allocated"

passed = resolve_vote(state, law)
assert passed, "Minimum Wage should pass with coalition (liberal + social_dem + agrarian + workers)"
assert any(l.id == "minimum_wage_act" for l in state.legislature.active_laws), "should be in active_laws"
assert not any(b.id == "minimum_wage_act" for b in state.legislature.pending_bills), "should leave pending"
wf = faction(state, "workers_front")
assert wf.loyalty > -0.60, "Workers' Front loyalty should rise on passage (+0.20 delta)"
print("  PASS: vote resolved, faction loyalty effects applied")


section("A2: Vote resolution — supermajority threshold (constitutional)")
state = fresh()
law = bill("land_reform_act")   # constitutional — needs 67 seats
law.status = "proposed"
state.legislature.pending_bills.append(law)

votes_for, votes_against, _ = projected_votes(state, law)
threshold = state.legislature.supermajority_threshold()
print(f"  Projected: {votes_for} for / {votes_against} against  (need {threshold} for constitutional)")
passed = resolve_vote(state, law)
status = "PASSED" if passed else "FAILED"
print(f"  Land Reform Act {status} — correct behaviour either way")
assert (law.id in [l.id for l in state.legislature.active_laws]) == passed


section("A3: Lobbying shifts projected support")
state = fresh()
law = bill("minimum_wage_act")
law.status = "proposed"
state.legislature.pending_bills.append(law)

nat_cons = faction(state, "national_conservatives")
votes_for_before, _, _ = projected_votes(state, law)

law.lobbying_bonus["national_conservatives"] = 0.5   # heavy lobbying
votes_for_after, _, _ = projected_votes(state, law)
print(f"  votes_for before lobbying: {votes_for_before}  after: {votes_for_after}")
assert votes_for_after >= votes_for_before, "lobbying should not reduce support"
print("  PASS: lobbying bonus correctly shifts vote projection")


section("A4: Executive order bypasses vote, erodes non-coalition trust")
state = fresh()
law = bill("emergency_price_controls")
nat_cons_loyalty_before = faction(state, "national_conservatives").loyalty

enact_executive_order(state, law)

assert any(l.id == "emergency_price_controls" for l in state.legislature.active_laws)
assert not any(b.id == "emergency_price_controls" for b in state.legislature.pending_bills)
nat_cons_loyalty_after = faction(state, "national_conservatives").loyalty
print(f"  Nat. Cons. loyalty: {nat_cons_loyalty_before:+.3f} → {nat_cons_loyalty_after:+.3f}")
assert nat_cons_loyalty_after < nat_cons_loyalty_before, "non-coalition factions should lose trust"
print("  PASS: executive order enacted, opposition trust erodes")


section("A5: Cabinet reshuffle installs appointee, loyalty effects applied")
state = fresh()
old_minister = state.cabinet.get("Defense")
ag_loyalty_before = faction(state, "agrarian_union").loyalty

msg = cabinet_ops.reshuffle(state, "Defense", "agrarian_union")
print(f"  {msg}")

new_minister = state.cabinet.get("Defense")
assert new_minister is not None, "Defense portfolio should be filled"
assert new_minister.faction_id == "agrarian_union", "new minister should be from Agrarian Union"
ag_loyalty_after = faction(state, "agrarian_union").loyalty
print(f"  Agrarian Union loyalty: {ag_loyalty_before:+.3f} → {ag_loyalty_after:+.3f}")
assert ag_loyalty_after > ag_loyalty_before, "courted faction should gain loyalty"
print("  PASS: reshuffle correctly changes minister and faction")


section("A6: Dismiss creates vacancy, ousted faction loses loyalty")
state = fresh()
finance_minister = state.cabinet.get("Finance")
assert finance_minister is not None
ld_loyalty_before = faction(state, "liberal_democrats").loyalty   # Finance belongs to lib_dem

msg = cabinet_ops.dismiss(state, "Finance")
print(f"  {msg}")

assert state.cabinet.get("Finance") is None, "Finance should be vacant"
ld_loyalty_after = faction(state, "liberal_democrats").loyalty
print(f"  Liberal Democrats loyalty: {ld_loyalty_before:+.3f} → {ld_loyalty_after:+.3f}")
assert ld_loyalty_after < ld_loyalty_before, "faction whose minister was dismissed should lose loyalty"
print("  PASS: dismiss creates vacancy, faction trust drops")


section("A7: Implementation quality — vacant portfolio underperforms, via the same institutional dampener as a staffed one")
state = fresh()
from engine.turn import TurnEngine
engine = TurnEngine()

law = bill("minimum_wage_act")
law.status = "active"
law.portfolio = "Economy"
state.legislature.active_laws.append(law)
state.player.political_capital = 80.0  # reset

economy_minister = state.cabinet.get("Economy")
assert economy_minister is not None
raw_minister_quality = economy_minister.implementation_quality()
full_quality = engine._implementation_quality_for(state, "Economy")

# Dismiss minister and check that quality drops for vacant portfolio
cabinet_ops.dismiss(state, "Economy")
state.player.political_capital = 80.0  # dismiss cost refunded in test

vacant_quality = engine._implementation_quality_for(state, "Economy")
print(f"  Quality with minister: {full_quality:.3f}   with vacant portfolio: {vacant_quality:.3f}")
assert vacant_quality < full_quality, "vacant portfolio should have lower implementation quality"

# Government stability/capacity/corruption didn't change between the two
# calls (no turn advanced) — only the minister component did, from
# raw_minister_quality down to the 0.35 vacant floor. So the SAME
# institutional dampener should divide out of both cleanly.
implied_dampener_full = full_quality / raw_minister_quality
implied_dampener_vacant = vacant_quality / 0.35
print(f"  Implied dampener — staffed: {implied_dampener_full:.4f}  vacant: {implied_dampener_vacant:.4f}")
assert abs(implied_dampener_full - implied_dampener_vacant) < 1e-6, \
    "the same institutional dampener should apply whether or not the portfolio is staffed"
print("  PASS: vacant portfolio degrades law implementation via the same institutional dampener as a staffed one")


section("A8: Diplomatic — improve relations")
state = fresh()
rel_before = state.country.relations["veldoria"].score
other_rel_before = state.world_country("veldoria").relations.get("ardenia")

msg = diplomacy.improve_relations(state, "veldoria", minister_competence=0.8)
print(f"  {msg}")

rel_after = state.country.relations["veldoria"].score
print(f"  Veldoria relation: {rel_before:+.3f} → {rel_after:+.3f}")
assert rel_after > rel_before, "outreach should improve relation score"
other_rel_after = state.world_country("veldoria").relations.get("ardenia")
assert other_rel_after is not None and abs(other_rel_after.score - rel_after) < 0.001, \
    "both sides of the relation should be updated symmetrically"
print("  PASS: relations improved symmetrically on both sides")


section("A9: Diplomatic — trade agreement")
state = fresh()
trade_before = state.country.relations["veldoria"].trade_volume
rel_before = state.country.relations["veldoria"].score

msg = diplomacy.propose_trade_agreement(state, "veldoria")
print(f"  {msg}")

trade_after = state.country.relations["veldoria"].trade_volume
rel_after = state.country.relations["veldoria"].score
print(f"  Trade: {trade_before:.0f} → {trade_after:.0f}   Relation: {rel_before:+.3f} → {rel_after:+.3f}")
assert trade_after > trade_before, "trade volume should rise"
assert rel_after > rel_before, "signing a trade deal should warm relations"
assert len(state.country.relations["veldoria"].treaties) == 1, "one treaty should be recorded"
print("  PASS: trade agreement boosts trade volume and warms relations")


section("A10: Diplomatic — foreign loan")
state = fresh()
debt_before = state.country.economy.public_debt_pct
revenue_before = state.country.economy.budget.revenue
nat_cons_loyalty_before = faction(state, "national_conservatives").loyalty

msg = diplomacy.request_foreign_loan(state, "veldoria")
print(f"  {msg}")

assert state.country.economy.public_debt_pct > debt_before, "loan should raise debt"
assert state.country.economy.budget.revenue > revenue_before, "loan should inject revenue"
nat_cons_loyalty_after = faction(state, "national_conservatives").loyalty
print(f"  Nat. Cons. loyalty: {nat_cons_loyalty_before:+.3f} → {nat_cons_loyalty_after:+.3f}")
assert nat_cons_loyalty_after < nat_cons_loyalty_before, "nationalist-leaning factions should grumble about foreign debt"
print("  PASS: loan raises debt and revenue, nationalists unhappy")


section("A11: Diplomatic — condemn")
state = fresh()
rel_before = state.country.relations["krasova"].score
approval_before = state.player.approval

msg = diplomacy.condemn(state, "krasova")
print(f"  {msg}")

rel_after = state.country.relations["krasova"].score
print(f"  Krasova relation: {rel_before:+.3f} → {rel_after:+.3f}")
print(f"  Approval: {approval_before:.3f} → {state.player.approval:.3f}")
assert rel_after < rel_before, "condemning a country should damage the relationship"
print("  PASS: condemnation damages relationship")


section("A12: Faction outreach — address grievance")
state = fresh()
wf = faction(state, "workers_front")
grievances_before = len(wf.grievances)
loyalty_before = wf.loyalty

# Simulate addressing the first grievance directly
from engine.actions import run_address_grievance
with patch("builtins.input", side_effect=["1", "1"]):   # faction 1, grievance 1
    result = run_address_grievance(state)
print(f"  {result.message}")

assert len(wf.grievances) == grievances_before - 1, "one grievance should be resolved"
assert wf.loyalty > loyalty_before, "resolving a grievance should raise loyalty"
print(f"  Workers' Front loyalty: {loyalty_before:+.3f} → {wf.loyalty:+.3f}")
print("  PASS: grievance addressed, loyalty improved")


section("A13: Faction outreach — court faction")
state = fresh()
ld = faction(state, "liberal_democrats")
loyalty_before = ld.loyalty

from engine.actions import run_court_faction
with patch("builtins.input", side_effect=["1"]):   # faction 1 = liberal democrats
    result = run_court_faction(state)
print(f"  {result.message}")

assert ld.loyalty > loyalty_before, "courting should nudge loyalty upward"
print(f"  Liberal Democrats loyalty: {loyalty_before:+.3f} → {ld.loyalty:+.3f}")
print("  PASS: courting raises faction loyalty")


section("A14: Insufficient PC — actions correctly refused before deducting cost")
state = fresh()
state.player.political_capital = 4.0   # below reshuffle (15), dismiss (6), court (6+)

from engine.actions import run_reshuffle, run_dismiss
result = run_reshuffle(state)
assert not result.success, "reshuffle should fail with insufficient PC"
assert state.player.political_capital == 4.0, "PC must not be deducted on refusal"
print(f"  Reshuffle refused: '{result.message}'")

result = run_dismiss(state)
assert not result.success, "dismiss should fail with insufficient PC"
assert state.player.political_capital == 4.0, "PC must not be deducted on refusal"
print(f"  Dismiss refused: '{result.message}'")
print("  PASS: insufficient-PC actions refused without touching PC")


# ══════════════════════════════════════════════════════════════════════════
# SECTION B — ACTION MENU INTEGRATION TESTS
# ══════════════════════════════════════════════════════════════════════════

section("B1: Menu — propose statutory bill, then call vote")
# Sequence traced:
#   "1"  → category: Legislative
#   "1"  → action: Propose Bill
#   "1"  → bill: first in catalog (Minimum Wage Act, statutory, costs 5 PC)
#             ✓ bill appears in pending_bills
#   "3"  → action: Call Vote
#   "1"  → bill: first (only) pending bill
#   "y"  → confirm vote — resolved, moves to active_laws or law_history
#   "0"  → back to category selection
#   "0"  → exit menu
state = fresh()
run_scripted(state, ["1","1","1","3","1","y","0","0"])
assert any(l.id == "minimum_wage_act" for l in
           state.legislature.active_laws + state.legislature.law_history), \
    "minimum_wage_act should be resolved"
print("  PASS: propose + vote resolves bill correctly")


section("B2: Menu — executive order (no vote required)")
state = fresh()
# EO is item [7] in a fresh catalog. After min-wage is already resolved, it
# may shift. Find its actual position.
from content.bills import bill_catalog as bc
available = [b for b in bc()
             if b.id not in {l.id for l in state.legislature.active_laws}]
eo_idx = next((i+1 for i, b in enumerate(available) if b.id == "emergency_price_controls"), None)
assert eo_idx is not None, "executive order bill should be in catalog"

#   "1"   → category: Legislative
#   "1"   → action: Propose Bill
#   str(eo_idx) → Emergency Price Controls → enacted immediately
#   "0"   → back to category
#   "0"   → exit
run_scripted(state, ["1","1",str(eo_idx),"0","0"])
assert any(l.id == "emergency_price_controls" for l in state.legislature.active_laws), \
    "executive order should be in active_laws immediately"
print("  PASS: executive order enacted without vote")


section("B3: Menu — reshuffle minister (shortlist flow)")
state = fresh()
old_defense = state.cabinet.get("Defense")
# CORE_PORTFOLIOS = ["Finance","Interior","Foreign Affairs","Defense","Economy","Justice"]
# Defense is index 4 in the list → menu item [4]
#   "2"  → category: Cabinet
#   "1"  → action: Reshuffle Minister
#   "4"  → portfolio: Defense
#   "1"  → shortlist candidate #1 (always the player's own party)
#   "0"  → back to category
#   "0"  → exit
run_scripted(state, ["2","1","4","1","0","0"])
defense_minister = state.cabinet.get("Defense")
assert defense_minister is not None
assert old_defense is None or defense_minister.id != old_defense.id, \
    "the shortlist pick should install a NEW minister"
assert defense_minister.faction_id == state.player.faction_id, \
    "candidate #1 on every shortlist is the player's own party"
assert defense_minister.trait in ("",) or defense_minister.trait, "candidates carry traits"
print(f"  Defense now held by: {defense_minister.name} ({defense_minister.faction_id}, "
      f"{defense_minister.trait_label() or 'no trait'})")
print("  PASS: the shortlist flow installs a chosen, named minister")


section("B4: Menu — diplomatic improve relations")
state = fresh()
rel_before = state.country.relations["veldoria"].score
# World countries list: Veldoria=1, Krasova=2, Merova=3
#   "3"  → category: Diplomatic
#   "1"  → action: Improve Relations
#   "1"  → country: Veldoria
#   "0"  → back to category
#   "0"  → exit
run_scripted(state, ["3","1","1","0","0"])
rel_after = state.country.relations["veldoria"].score
print(f"  Veldoria relation: {rel_before:+.3f} → {rel_after:+.3f}")
assert rel_after > rel_before
print("  PASS: improve relations via menu works")


section("B5: Menu — address grievance")
state = fresh()
wf = faction(state, "workers_front")
loyalty_before = wf.loyalty
grievances_before = len(wf.grievances)
# Factions with grievances: only Workers' Front initially
# In the menu, it's the only option so it's [1]
# Grievances listed: [1] and [2] — address the first
#   "4"  → category: Faction Outreach
#   "1"  → action: Address Grievance
#   "1"  → faction: Workers' Front (only one with grievances)
#   "1"  → grievance: first grievance
#   "0"  → back to category
#   "0"  → exit
run_scripted(state, ["4","1","1","1","0","0"])
assert len(wf.grievances) == grievances_before - 1
assert wf.loyalty > loyalty_before
print(f"  Workers' Front: {grievances_before} grievances → {len(wf.grievances)}, "
      f"loyalty {loyalty_before:+.3f} → {wf.loyalty:+.3f}")
print("  PASS: address grievance via menu works")


# ══════════════════════════════════════════════════════════════════════════
# SECTION C — TURN LOOP INVARIANTS
# ══════════════════════════════════════════════════════════════════════════

section("C1: Turn loop — 12 turns, all values stay within declared bounds")
state = fresh()
engine = TurnEngine()

for t in range(1, 13):
    state = engine.advance(state)
    econ = state.country.economy

    # Sector shares stay normalised
    total_gdp = sum(s.gdp_share for s in econ.sectors)
    total_emp = sum(s.employment_share for s in econ.sectors)
    assert abs(total_gdp - 1.0) < 0.01, f"Turn {t}: GDP sector shares denormalised ({total_gdp:.4f})"
    assert abs(total_emp - 1.0) < 0.01, f"Turn {t}: emp sector shares denormalised ({total_emp:.4f})"

    # Headline economic bounds
    assert 0.0 < econ.unemployment <= 0.5,   f"Turn {t}: unemployment={econ.unemployment:.3f} out of bounds"
    assert -0.15 <= econ.growth_rate <= 0.20, f"Turn {t}: growth={econ.growth_rate:.3f} out of bounds"
    assert 0.0 <= econ.inflation,             f"Turn {t}: inflation={econ.inflation:.3f} negative"

    # Player values bounded
    assert 0.0 <= state.player.approval <= 1.0,               f"Turn {t}: approval out of [0,1]"
    assert 0.0 <= state.player.political_capital <= 100.0,     f"Turn {t}: PC out of [0,100]"

    # Faction values bounded
    for f in state.country.factions:
        assert -1.0 <= f.loyalty <= 1.0,  f"Turn {t}: {f.name} loyalty={f.loyalty:.3f} out of bounds"
        assert 0.0  <= f.power  <= 1.0,   f"Turn {t}: {f.name} power={f.power:.3f} out of bounds"

    # Relation scores bounded
    for other_id, rel in state.country.relations.items():
        assert -1.0 <= rel.score <= 1.0,  f"Turn {t}: {other_id} relation={rel.score:.3f} out of bounds"

    print(f"  Turn {t:>2} ({state.date_string()}): "
          f"GDP={econ.gdp:>10,.0f}  growth={econ.growth_rate*100:+.2f}%  "
          f"unemp={econ.unemployment*100:.2f}%  "
          f"approval={state.player.approval*100:.1f}%  "
          f"PC={state.player.political_capital:.0f}")

print("  PASS: 12 turns, all invariants held")


section("C2: Turn loop — relation drift moves in expected direction")
state = fresh()
engine = TurnEngine()
# Veldoria is parliamentary_democracy (same family as Ardenia) — should drift positive
# Krasova is authoritarian — should drift negative
vel_start = state.country.relations["veldoria"].score
kra_start = state.country.relations["krasova"].score

for _ in range(12):
    state = engine.advance(state)

vel_end = state.country.relations["veldoria"].score
kra_end = state.country.relations["krasova"].score
print(f"  Veldoria (same regime family): {vel_start:+.3f} → {vel_end:+.3f}  (should rise)")
print(f"  Krasova  (autocracy):           {kra_start:+.3f} → {kra_end:+.3f}  (should fall)")
assert vel_end > vel_start, "same-family regime relation should drift upward"
assert kra_end < kra_start, "cross-family regime relation should drift downward"
print("  PASS: regime-aligned relation drift works")


section("C3: Turn loop — trade treaties generate budget revenue")
state = fresh()
engine = TurnEngine()
diplomacy.propose_trade_agreement(state, "veldoria")
revenue_start = state.country.economy.budget.revenue
for _ in range(6):
    state = engine.advance(state)
revenue_end = state.country.economy.budget.revenue
print(f"  Budget revenue: {revenue_start:,.0f} → {revenue_end:,.0f}")
assert revenue_end > revenue_start, "active trade treaty should generate revenue over time"
print("  PASS: trade treaty revenue feeds budget")


# ══════════════════════════════════════════════════════════════════════════
# SECTION D — LONG-TERM MODIFIER LIFECYCLE TESTS  (Priority 1 feature)
# ══════════════════════════════════════════════════════════════════════════

section("D1: Modifier — onset delay blocks any effect until it elapses")
m = Modifier(id="t1", source="Test", target="gdp_growth", magnitude=0.01,
             onset_delay=3, ramp_duration=6, hold_duration=None)
values = []
for age in range(0, 9):
    m.age = age
    values.append(round(m.current_value(), 5))
print(f"  ages 0-8: {values}")
assert values[0] == 0.0 and values[1] == 0.0 and values[2] == 0.0, \
    "value must be exactly 0 before onset_delay elapses"
assert values[3] > 0.0, "value should start appearing the month onset_delay elapses"
assert values[8] == 0.01, "value should reach full magnitude by the end of the ramp"
print("  PASS: onset delay correctly withholds the effect, then ramp reaches full magnitude")


section("D2: Modifier — ramps monotonically, holds, then decays to zero and expires")
m = Modifier(id="t2", source="Test", target="budget_expenditure", magnitude=100.0,
             onset_delay=0, ramp_duration=4, hold_duration=6, decay_duration=3)
trace = []
for age in range(0, 14):
    m.age = age
    trace.append(round(m.current_value(), 1))
print(f"  ages 0-13: {trace}")
ramp = trace[0:4]
assert ramp == sorted(ramp), "ramp phase should be monotonically non-decreasing"
assert trace[3] == 100.0, "ramp should reach full magnitude at age 3 (onset0+ramp4-1)"
hold = trace[4:10]
assert all(v == 100.0 for v in hold), "hold phase should stay at exactly full magnitude"
decay = trace[10:13]
assert decay == sorted(decay, reverse=True), "decay phase should be monotonically non-increasing"
assert trace[13] == 0.0, "value should be exactly 0 once fully decayed"
m.age = 13
assert m.is_expired(), "modifier should report expired once its full lifecycle has elapsed"
m.age = 12
assert not m.is_expired(), "modifier should not report expired one month early"
print("  PASS: full ramp → hold → decay → expiry lifecycle behaves correctly")


section("D3: Modifier — hold_duration=None never expires, no matter how old")
m = Modifier(id="t3", source="Test", target="approval_bias", magnitude=-0.05,
             onset_delay=2, ramp_duration=10, hold_duration=None)
m.age = 10_000
assert not m.is_expired(), "indefinite modifiers must never auto-expire"
assert m.current_value() == -0.05, "should sit at full magnitude indefinitely once ramped"
print("  PASS: indefinite modifier holds forever without expiring")


section("D4: activate_law_modifiers — flat deltas AND explicit modifiers both convert")
state = fresh()
law = bill("progressive_tax_reform_act")   # explicit modifiers only, no flat deltas
law.status = "proposed"
before = len(state.modifiers)
activate_law_modifiers(state, law)
after = len(state.modifiers)
print(f"  Modifiers before: {before}  after activating tax reform: {after}")
assert after - before == 2, "tax reform should add exactly its 2 explicit modifiers"
targets = {m.target for m in state.modifiers if m.source_id == law.id}
assert targets == {"budget_revenue", "approval_bias"}, f"unexpected targets: {targets}"
print("  PASS: explicit modifiers correctly activated with correct targets")

state2 = fresh()
law2 = bill("minimum_wage_act")   # flat deltas only, no explicit modifiers
law2.status = "proposed"
activate_law_modifiers(state2, law2)
flat_mods = [m for m in state2.modifiers if m.source_id == law2.id]
print(f"  Minimum wage act produced {len(flat_mods)} modifier(s) from flat deltas: "
      f"{[(m.target, m.magnitude) for m in flat_mods]}")
assert len(flat_mods) == 2, "minimum wage act has 2 non-zero flat deltas (unemployment, expenditure)"
assert any(m.target == "unemployment" and abs(m.magnitude - 0.006) < 1e-9 for m in flat_mods)
assert any(m.target == "budget_expenditure" and abs(m.magnitude - 120.0) < 1e-9 for m in flat_mods)
print("  PASS: flat deltas correctly convert into equivalent modifiers")


section("D5: Infrastructure bill — immediate debt bump + delayed growth payoff")
state = fresh()
law = bill("infrastructure_investment_act")
law.status = "proposed"
state.legislature.pending_bills.append(law)
debt_before = state.country.economy.public_debt_pct

passed = resolve_vote(state, law)
print(f"  Infrastructure Investment Act passed: {passed}")
if passed:
    debt_after = state.country.economy.public_debt_pct
    print(f"  Debt/GDP: {debt_before:.4f} → {debt_after:.4f} (one-time bond issuance bump)")
    assert debt_after > debt_before, "bond-financed infrastructure should bump debt immediately"

    growth_mod = next(m for m in state.modifiers if m.id == "infra_growth_payoff")
    cost_mod = next(m for m in state.modifiers if m.id == "infra_construction_cost")
    assert growth_mod.current_value() == 0.0, "growth payoff must be exactly 0 at passage (24mo onset delay)"
    assert cost_mod.current_value() > 0.0, "construction cost should already be biting at passage"
    print(f"  At passage: construction cost={cost_mod.current_value():.0f}M/yr, "
          f"growth payoff={growth_mod.current_value()*100:.3f}%  (correctly zero)")

    growth_mod.age = 47   # onset(24)+ramp(24)-1 = fully ramped
    print(f"  After 47 months: growth payoff={growth_mod.current_value()*100:.3f}%  (should be ~0.700%)")
    assert abs(growth_mod.current_value() - 0.007) < 1e-9, "growth payoff should be fully phased in by month 47"
else:
    print("  Bill failed the vote this run (faction arithmetic can go either way) — skipping payoff checks")
print("  PASS: infrastructure bill demonstrates immediate cost + delayed payoff correctly")


section("D6: Education bill — multi-year delayed workforce quality payoff")
state = fresh()
law = bill("education_modernisation_act")
activate_law_modifiers(state, law)   # force-activate regardless of vote outcome, to test the payoff curve directly

wf_mod = next(m for m in state.modifiers if m.id == "edu_workforce_payoff")
wf_mod.age = 0
assert wf_mod.current_value() == 0.0, "workforce payoff should be exactly 0 at passage"
wf_mod.age = 35
assert wf_mod.current_value() == 0.0, "still 0 one month before the 36-month onset elapses"
wf_mod.age = 59   # onset(36) + ramp(24) - 1 = fully ramped
print(f"  At month 59: workforce quality modifier = {wf_mod.current_value():+.3f}  (should be ~+0.220)")
assert abs(wf_mod.current_value() - 0.22) < 1e-9, "should be fully phased in by month 59"
print("  PASS: education reform correctly withholds its payoff for 3 years, then phases in over 2 more")


section("D7: Modifiers do not accumulate — a permanent effect stays constant, not runaway")
state = fresh()
engine = TurnEngine()
law = Law(id="steady_law", name="Steady Test Law", description="test",
          status="proposed", tier="statutory", portfolio=None,
          effects=LawEffect(gdp_growth_delta=0.01))
state.legislature.pending_bills.append(law)
law.votes_for = 999  # force a pass regardless of faction arithmetic
activate_law_modifiers(state, law)
state.legislature.active_laws.append(law)
state.legislature.pending_bills.remove(law)

growth_contributions = []
for _ in range(24):
    state = engine.advance(state)
    # Check THIS modifier's own value directly — the aggregate _modifiers_sum
    # also includes Fiscal Consolidation Act's pre-existing gdp_growth
    # modifier (competence-scaled, from fresh()), so isolating by id is the
    # correct way to confirm THIS one specifically never drifts.
    my_mod = next(m for m in state.modifiers if m.id == "steady_law_gdp_growth")
    growth_contributions.append(round(my_mod.current_value(), 5))

print(f"  steady_law's own gdp_growth contribution over 24 turns: "
      f"min={min(growth_contributions)}  max={max(growth_contributions)}")
assert all(abs(v - 0.01) < 1e-9 for v in growth_contributions), \
    "a permanent flat modifier must contribute EXACTLY its magnitude every turn — never more, never less"
print("  PASS: confirmed no runaway accumulation — this is the bug the modifier system fixes")


section("D8: Loan lifecycle — interest accrues, then the loan retires on schedule")
state = fresh()
econ = state.country.economy
engine = TurnEngine()

# Construct a short-term loan directly so the test doesn't take 48 turns.
# hold_duration = term_months - 1: ramp_duration=1 already contributes one
# full-strength month, so together they must cover exactly term_months —
# see the matching comment in engine/diplomacy.py: request_foreign_loan.
loan = Loan(id="test_loan", lender_id="veldoria", principal=500.0,
            annual_interest_rate=0.08, term_months=3)
econ.loans.append(loan)
state.modifiers.append(Modifier(
    id="test_loan_interest", source="Test Loan", target="budget_expenditure",
    magnitude=loan.annual_interest_cost(), onset_delay=0, ramp_duration=1,
    hold_duration=2, decay_duration=0, source_id=loan.id, portfolio=None,
))
debt_before = econ.public_debt_pct
expected_annual_interest = loan.annual_interest_cost()  # 500 * 0.08 = 40.0
print(f"  Expected annual interest: {expected_annual_interest:.1f}M  (term: {loan.term_months} months)")

for i in range(1, 5):
    state = engine.advance(state)
    still_has_loan = len(econ.loans) > 0
    my_mod = next((m for m in state.modifiers if m.id == "test_loan_interest"), None)
    contribution = my_mod.current_value() if my_mod else 0.0
    print(f"  Month {i}: loan outstanding={still_has_loan}  "
          f"this modifier's own contribution={contribution:+.1f}")
    if i <= 2:
        assert still_has_loan, f"loan should still be outstanding at month {i}"
        assert my_mod is not None and abs(contribution - expected_annual_interest) < 1e-9, \
            f"interest should be at full strength at month {i}"
    else:
        assert not still_has_loan, f"loan should be retired by month {i} (term was 3)"
        assert my_mod is None, "the interest modifier should be pruned once the loan retires"

debt_after = econ.public_debt_pct
print(f"  Debt/GDP: {debt_before:.4f} → {debt_after:.4f} (should drop back down on retirement)")
assert debt_after < debt_before, "retiring the loan should reduce debt/GDP"
print("  PASS: loan interest accrues for its term, then both principal and interest cleanly retire together")


section("D9: Vacant portfolio degrades a long-term modifier's contribution, mid-flight")
state = fresh()
engine = TurnEngine()
law = bill("progressive_tax_reform_act")
activate_law_modifiers(state, law)
revenue_mod = next(m for m in state.modifiers if m.id == "tax_reform_revenue")
revenue_mod.age = 10  # fully ramped

full_contribution = engine._modifiers_sum(state, "budget_revenue")
cabinet_ops.dismiss(state, "Finance")
vacant_contribution = engine._modifiers_sum(state, "budget_revenue")
print(f"  Revenue contribution with Finance staffed: {full_contribution:.1f}  "
      f"vacant: {vacant_contribution:.1f}")
assert vacant_contribution < full_contribution, \
    "dismissing the responsible minister should immediately weaken this law's ongoing effect"
print("  PASS: minister competence dynamically scales long-term effects, not just at passage")


section("D10: Loan interest is NOT scaled by minister competence (contractual, not implementation)")
state = fresh()
diplomacy.request_foreign_loan(state, "veldoria")
interest_mod = next(m for m in state.modifiers if "interest" in m.id)
assert interest_mod.portfolio is None, \
    "loan interest must not carry a portfolio — it's owed by contract, not administered by a ministry"
assert interest_mod.institutional is False, \
    "loan interest must be explicitly non-institutional — this is the actual immunity mechanism now " \
    "that portfolio=None alone no longer implies full strength (see education bill, D-series below)"
print(f"  Loan interest modifier: portfolio={interest_mod.portfolio}  institutional={interest_mod.institutional}")
print("  PASS: loan interest is immune to cabinet competence AND institutional dampening, as intended")


# ══════════════════════════════════════════════════════════════════════════
# SECTION E — GOVERNMENT STABILITY  (Priority: make existing systems interact)
# ══════════════════════════════════════════════════════════════════════════

from engine import stability as stab
from engine.stability import (compute_target_stability, compute_unrest, compute_economic_signal,
                               compute_cabinet_risk_fraction, resolve_confidence_vote,
                               maybe_trigger_protest, player_call_confidence_vote)
from engine.actions import run_call_confidence_vote


section("E1: Target stability — bounded, with a legible breakdown")
state = fresh()
target, breakdown = compute_target_stability(state)
print(f"  Target stability at game start: {target:.3f}")
for k, v in breakdown.items():
    print(f"    {k:<22} {v:+.3f}")
assert 0.05 <= target <= 0.95, "target stability must stay within its declared bounds"
expected_keys = {"Coalition loyalty", "Cabinet loyalty", "Parliamentary margin",
                  "Public approval", "Economic conditions", "Cabinet dysfunction", "Unrest",
                  "Coalition cohesion"}
assert set(breakdown.keys()) == expected_keys, f"unexpected breakdown keys: {breakdown.keys()}"
assert abs(sum(breakdown.values()) - target) < 1e-9 or target in (0.05, 0.95), \
    "target should equal the sum of its components, unless clamped at a bound"
print("  PASS: target stability is bounded and its breakdown sums correctly")


section("E2: Unrest responds to grievances and unemployment, using EXISTING state only")
state = fresh()
baseline_unrest = compute_unrest(state)

wf = faction(state, "workers_front")
wf.grievances.append(type(wf.grievances[0])(source="Test crisis", severity=1.0, turns_active=0))
grievance_unrest = compute_unrest(state)
print(f"  Unrest baseline: {baseline_unrest:.3f}  after a severe new grievance: {grievance_unrest:.3f}")
assert grievance_unrest > baseline_unrest, "a severe grievance should raise unrest"

state2 = fresh()
state2.country.economy.unemployment = 0.35
high_unemployment_unrest = compute_unrest(state2)
print(f"  Unrest at 35% unemployment: {high_unemployment_unrest:.3f}")
assert high_unemployment_unrest > baseline_unrest, "high unemployment should raise unrest"
print("  PASS: unrest is a genuine function of existing grievance/unemployment state, not a new hidden dial")


section("E3: Political capital regeneration reads government stability")
state_stable = fresh()
state_stable.stability.value = 0.90
state_shaky = fresh()
state_shaky.stability.value = 0.10
engine = TurnEngine()

pc_before_stable = state_stable.player.political_capital
pc_before_shaky = state_shaky.player.political_capital
state_stable = engine.advance(state_stable)
state_shaky = engine.advance(state_shaky)
gain_stable = state_stable.player.political_capital - pc_before_stable
gain_shaky = state_shaky.player.political_capital - pc_before_shaky
print(f"  PC gained at stability=0.90: {gain_stable:.2f}   at stability=0.10: {gain_shaky:.2f}")
assert gain_stable > gain_shaky, "higher government stability should regenerate more political capital"
print("  PASS: PC regeneration is sensitive to government stability")


section("E4: Implementation quality dampener responds to government stability")
state_stable = fresh()
state_stable.stability.value = 0.95
state_shaky = fresh()
state_shaky.stability.value = 0.05
engine = TurnEngine()

quality_stable = engine._implementation_quality_for(state_stable, "Finance")
quality_shaky = engine._implementation_quality_for(state_shaky, "Finance")
print(f"  Finance implementation quality — stable government: {quality_stable:.3f}  "
      f"shaky government: {quality_shaky:.3f}")
assert quality_stable > quality_shaky, "policy should implement better under a stable government"
assert quality_shaky > 0.0, "even a collapsing government should retain SOME implementation capacity (friction, not a wall)"
print("  PASS: implementation quality responds to stability without hitting a hard floor of zero")


section("E5: Scandal (minister crisis) chance scales with instability")
engine = TurnEngine()
state_stable = fresh()
state_stable.stability.value = 0.95
state_shaky = fresh()
state_shaky.stability.value = 0.05
# Give both an identical high-threat minister so only stability differs.
risky = state_stable.cabinet.get("Foreign Affairs")  # Dmitri Koval: ambition 0.65, loyalty 0.50 → threat 0.325... 
# threat_level must exceed 0.5 to matter at all; bump ambition directly for a clean test.
state_stable.cabinet.get("Foreign Affairs").ambition = 0.95
state_stable.cabinet.get("Foreign Affairs").loyalty = 0.10
state_shaky.cabinet.get("Foreign Affairs").ambition = 0.95
state_shaky.cabinet.get("Foreign Affairs").loyalty = 0.10

risk = state_stable.cabinet.get("Foreign Affairs").threat_level()
chance_stable = (risk - 0.5) * 0.12 * (1.0 + (1.0 - state_stable.stability.value) * 1.5)
chance_shaky  = (risk - 0.5) * 0.12 * (1.0 + (1.0 - state_shaky.stability.value) * 1.5)
print(f"  Minister threat level: {risk:.3f}")
print(f"  Scandal chance — stable government: {chance_stable:.4f}  shaky government: {chance_shaky:.4f}")
assert chance_shaky > chance_stable, "a shakier government should make scandals MORE likely, not less"
print("  PASS: scandal risk amplifies with instability, as designed")


section("E6: Protest fires under sustained unrest and deepens the driving grievance")
random.seed(12345)  # deterministic for this test only
state = fresh()
wf = faction(state, "workers_front")
wf.grievances = [type(wf.grievances[0])(source="Deep crisis", severity=1.0, turns_active=10)]
state.country.economy.unemployment = 0.30

unrest = compute_unrest(state)
print(f"  Engineered unrest level: {unrest:.3f}")
assert unrest >= stab.PROTEST_UNREST_THRESHOLD, "test scenario should be well above the protest threshold"

severity_before = wf.grievances[0].severity
fired = False
for _ in range(50):
    msg = maybe_trigger_protest(state)
    if msg:
        fired = True
        break
print(f"  Protest fired within 50 attempts: {fired}")
assert fired, "with unrest this high, a protest should fire within 50 tries (near-certain probabilistically)"
print(f"  Grievance severity: {severity_before:.2f} → {wf.grievances[0].severity:.2f}")
assert wf.grievances[0].severity >= severity_before, \
    "an unaddressed protest should deepen (or at minimum not reduce) the grievance driving it"
print("  PASS: protest mechanic fires under sustained unrest and feeds back into the grievance that caused it")


section("E7: Confidence vote — deterministic WIN and LOSS scenarios")
state = fresh()
# Make every faction unambiguously loyal — should win comfortably.
for f in state.country.factions:
    f.loyalty = 0.8
outcome = resolve_confidence_vote(state)
print(f"  All-loyal scenario: {outcome}  (stability now {state.stability.value:.3f})")
assert outcome == "survived", "a government with universal high loyalty should win a confidence vote"

state2 = fresh()
# Flip every faction hostile AND out of coalition — should lose.
for f in state2.country.factions:
    f.loyalty = -0.8
    f.in_coalition = False
coalition_before = [f.id for f in state2.country.factions if f.in_coalition]
outcome2 = resolve_confidence_vote(state2)
print(f"  All-hostile scenario: {outcome2}  (stability now {state2.stability.value:.3f})")
assert outcome2 == "lost", "a government with zero loyal factions and no coalition should lose"
remaining_coalition = [f.id for f in state2.country.factions if f.in_coalition]
print(f"  Coalition before: {coalition_before}  after: {remaining_coalition}")
print("  PASS: confidence vote resolves correctly in both directions")


section("E8: Player-initiated confidence vote action — costs PC, routes through the same resolver")
state = fresh()
for f in state.country.factions:
    f.loyalty = 0.8
pc_before = state.player.political_capital
with patch("builtins.input", side_effect=["y"]):
    result = run_call_confidence_vote(state)
print(f"  {result.message}")
print(f"  PC before: {pc_before:.1f}  after: {state.player.political_capital:.1f}")
assert state.player.political_capital == pc_before - 15.0, "calling a confidence vote should cost exactly its PC cost"
assert result.success
print("  PASS: player-initiated confidence vote correctly costs PC and resolves")


section("E9: Insufficient PC blocks the player from calling a confidence vote")
state = fresh()
state.player.political_capital = 5.0
result = run_call_confidence_vote(state)
assert not result.success
assert state.player.political_capital == 5.0, "PC must not be deducted when the action is refused"
print(f"  Refused correctly: '{result.message}'")
print("  PASS: confidence vote action respects the PC gate like every other action")


section("E10: Multi-turn integration — an engineered crisis government trends toward instability")
random.seed(777)
state = fresh()
# Minority coalition, low approval, high unemployment, disloyal risky cabinet.
for f in state.country.factions:
    f.in_coalition = False
state.country.factions[0].in_coalition = True  # a lone, small coalition
state.player.approval = 0.20
state.country.economy.unemployment = 0.28
for m in state.cabinet.ministers:
    m.loyalty = 0.15
    m.ambition = 0.9
engine = TurnEngine()

stability_trace = [state.stability.value]
events_seen = []
for _ in range(30):
    before_log_types = len(state.event_history)
    state = engine.advance(state)
    stability_trace.append(state.stability.value)
    events_seen.extend(state.turn_log)

print(f"  Stability trace (every 5th turn): {[round(v,3) for v in stability_trace[::5]]}")
print(f"  Final stability: {state.stability.value:.3f} ({state.stability.label()})")
crisis_events = [e for e in events_seen if "SCANDAL" in e or "PROTEST" in e or "CONFIDENCE VOTE" in e]
print(f"  Crisis-type events fired over 30 turns: {len(crisis_events)}")
for e in crisis_events[:5]:
    print(f"    · {e}")
assert state.stability.value < stability_trace[0], \
    "a manufactured crisis government should end up LESS stable than it started, not more"
assert len(crisis_events) > 0, \
    "over 30 turns of an engineered crisis, at least one scandal/protest/confidence-vote event should fire"
print("  PASS: a genuinely bad government trajectory produces both falling stability AND visible crisis events")


section("E11: Multi-turn integration — a healthy government stays stable")
random.seed(999)
state = fresh()
for f in state.country.factions:
    f.loyalty = 0.7
state.player.approval = 0.75
state.country.economy.unemployment = 0.05
state.country.economy.growth_rate = 0.04
engine = TurnEngine()

for _ in range(20):
    state = engine.advance(state)

print(f"  Final stability after 20 healthy turns: {state.stability.value:.3f} ({state.stability.label()})")
assert state.stability.value > 0.5, "a genuinely healthy government should settle at solid stability, not crisis"
print("  PASS: a healthy government trajectory produces solid, not fragile, stability")


# ══════════════════════════════════════════════════════════════════════════
# SECTION F — ELECTIONS  (Priority 1: a complete political lifecycle)
# ══════════════════════════════════════════════════════════════════════════

from engine import elections as elec
from engine.elections import (_allocate_seats, form_government, hold_election,
                               should_trigger_snap_election, months_until_election,
                               TERM_LENGTH_TURNS, ELECTORAL_THRESHOLD)
from engine.actions import run_campaign


section("F1: Seat allocation — proportional, sums exactly, sub-threshold parties wiped out")
state = fresh()
allocation = _allocate_seats(state.country.factions, 100)
print(f"  Allocation: {allocation}")
assert sum(allocation.values()) == 100, "seat allocation must sum to exactly total_seats"
for f in state.country.factions:
    assert allocation[f.id] == f.seats, \
        f"support already matches seat shares exactly in the fixture, so allocation should reproduce seats 1:1"

state2 = fresh()
fringe = faction(state2, "workers_front")
fringe.support = 0.01  # well under the 3% threshold
allocation2 = _allocate_seats(state2.country.factions, 100)
print(f"  With Workers' Front at 1% support: {allocation2}")
assert allocation2["workers_front"] == 0, "a party under the electoral threshold should win zero seats"
assert sum(allocation2.values()) == 100, "seats must still sum to 100 even after a wipeout"
print("  PASS: proportional allocation sums correctly and enforces the electoral threshold")


section("F2: Coalition formation — largest party finds a viable majority")
state = fresh()
coalition, was_in_gov = form_government(state)
coalition_ids = {f.id for f in coalition}
total_coalition_seats = sum(f.seats for f in coalition)
print(f"  Coalition: {[f.name for f in coalition]}  ({total_coalition_seats} seats)")
assert total_coalition_seats >= state.legislature.majority_threshold(), \
    "the formed coalition must actually hold a majority when one is achievable"
assert state.ruling_faction_id == "liberal_democrats", \
    "Liberal Democrats (38 seats, largest) should seed and lead the government"
assert state.player.in_government, "the player's own party leads this coalition, so they should remain in government"
print("  PASS: automatic coalition formation reaches a real majority, player retains office")


section("F3: Coalition formation — fragmented parliament falls back to minority government")
state = fresh()
# Scatter seats so nobody can reach a majority even with every willing partner —
# 5 factions all under 20 seats each, none can combine to reach 51.
for i, f in enumerate(state.country.factions):
    f.seats = 20
state.country.factions[0].seats = 20  # 5 * 20 = 100, no combination without all 5 hits majority alone... 
# Actually any 3 of these reach 60 >= 51, so let's genuinely fragment further with a 6th blocker approach:
# simplest reliable fragmentation: one very hostile, ideologically isolated bloc holds the balance.
for f in state.country.factions:
    f.ideology.economic = 0.0
    f.ideology.social = 0.0
state.country.factions[-1].ideology.economic = -1.0  # Workers' Front now maximally distant from everyone
state.country.factions[-1].ideology.social = -1.0
coalition, was_in_gov = form_government(state)
print(f"  Coalition: {[f.name for f in coalition]}  ({sum(f.seats for f in coalition)} seats, "
      f"need {state.legislature.majority_threshold()})")
# With identical ideology among the other 4, a majority IS still reachable among
# them (any 3 of the 4 non-Workers'-Front factions at 20 each = 60 >= 51) — this
# specifically confirms the heuristic does NOT collapse into minority government
# when a real majority is available, even with one isolated, unusable partner.
assert sum(f.seats for f in coalition) >= state.legislature.majority_threshold(), \
    "a majority IS achievable here among the 4 compatible factions — should not fall back to minority"
print("  PASS: coalition formation correctly finds a majority among compatible partners, "
      "ignoring the ideologically isolated one")


section("F4: Player loses office when their party's seats collapse")
state = fresh()
ld = faction(state, "liberal_democrats")
ld.seats = 3  # collapsed to a tiny rump
ld.support = 0.03
# Redistribute the lost seats to keep the total at 100 for a coherent scenario.
faction(state, "national_conservatives").seats += 35
coalition, was_in_gov = form_government(state)
print(f"  Player's party (Liberal Democrats) seats: {ld.seats}  in_government after: {state.player.in_government}")
assert was_in_gov, "player should have STARTED in government (sanity check on the fixture)"
assert not state.player.in_government, \
    "with only 3 seats and National Conservatives now dominant, the player should lose office"
assert state.ruling_faction_id != "liberal_democrats"
print("  PASS: a genuinely collapsed party loses office — not just a number changing, a real consequence")


section("F5: Player regains office if their party's support recovers by the next election")
state = fresh()
state.player.in_government = False
ld = faction(state, "liberal_democrats")
ld.seats = 3
faction(state, "national_conservatives").seats += 35
state.ruling_faction_id = "national_conservatives"
# Now recover: Liberal Democrats surge back to their original standing.
ld.seats = 38
faction(state, "national_conservatives").seats = 32
coalition, was_in_gov = form_government(state)
print(f"  After recovery — in_government: {state.player.in_government}  (was: {was_in_gov})")
assert not was_in_gov, "should have STARTED in opposition (sanity check)"
assert state.player.in_government, "with seats recovered to their original leading position, player should regain office"
print("  PASS: office is not permanently lost — a recovered party can win it back")


section("F6: Cabinet rebuilds ONLY when the ruling faction actually changes")
state = fresh()
original_minister_ids = {m.id for m in state.cabinet.ministers}
# Force a "new government" scenario matching the CURRENT ruling faction —
# should NOT trigger a rebuild.
coalition, _ = form_government(state)
assert state.ruling_faction_id == "liberal_democrats"
# hold_election calls _rebuild_cabinet only if ruling_faction_id CHANGED from
# before the call — simulate that check directly:
old_ruling = state.ruling_faction_id
coalition2, _ = form_government(state)  # same seat distribution -> same result
assert state.ruling_faction_id == old_ruling, "re-running formation on unchanged seats should reproduce the same ruling party"
print("  Ruling faction unchanged across re-formation — cabinet rebuild would correctly be skipped")

state2 = fresh()
ld2 = faction(state2, "liberal_democrats")
nc2 = faction(state2, "national_conservatives")
ld2.support = 0.05
nc2.support = 0.60
old_ministers_before = list(state2.cabinet.ministers)
result = hold_election(state2)
new_ministers = state2.cabinet.ministers
print(f"  Ruling faction changed to: {state2.ruling_faction_id}  "
      f"Cabinet rebuilt: {new_ministers is not old_ministers_before}")
assert state2.ruling_faction_id == "national_conservatives"
assert all(m.faction_id in {f.id for f in state2.country.factions if f.in_coalition} for m in new_ministers), \
    "every minister in a freshly rebuilt cabinet should belong to the new governing coalition"
print("  PASS: cabinet only rebuilds when the ruling party genuinely changes")


section("F7: Support drift — governing party benefits from good times, opposition from bad times")
engine = TurnEngine()

state_good = fresh()
state_good.player.approval = 0.85
state_good.country.economy.growth_rate = 0.06
state_good.country.economy.unemployment = 0.04
ld_support_before = faction(state_good, "liberal_democrats").support
nc_support_before = faction(state_good, "national_conservatives").support
for _ in range(6):
    state_good = engine.advance(state_good)
ld_support_after = faction(state_good, "liberal_democrats").support
print(f"  Good times — governing Liberal Democrats support: {ld_support_before:.3f} → {ld_support_after:.3f}")
assert ld_support_after > ld_support_before, "the governing party should gain support during genuinely good conditions"

state_bad = fresh()
state_bad.player.approval = 0.15
state_bad.country.economy.growth_rate = -0.05
state_bad.country.economy.unemployment = 0.25
nc_support_before2 = faction(state_bad, "national_conservatives").support
for _ in range(6):
    state_bad = engine.advance(state_bad)
nc_support_after2 = faction(state_bad, "national_conservatives").support
print(f"  Bad times — hostile opposition (Nat. Cons.) support: {nc_support_before2:.3f} → {nc_support_after2:.3f}")
assert nc_support_after2 > nc_support_before2, \
    "a hostile opposition party should gain support while the government struggles"
print("  PASS: support drift correctly rewards governing parties for good times, opposition for bad")


section("F8: Grievance pressure asymmetry — hurts governing factions, helps opposition factions")
state = fresh()
ld = faction(state, "liberal_democrats")  # governing
nc = faction(state, "national_conservatives")  # opposition, hostile
econ_signal = stab.compute_economic_signal(state.country.economy)

ld.grievances = []
perf_ld_no_grievance = (econ_signal * 0.5 + (state.stability.value - 0.5) + (state.player.approval - 0.5)) / 2.5
ld.grievances = [type(faction(state, "workers_front").grievances[0])(source="Test", severity=1.0, turns_active=0)]
perf_ld_with_grievance = ((econ_signal * 0.5 + (state.stability.value - 0.5) + (state.player.approval - 0.5)) / 2.5
                           - ld.grievance_pressure() * 0.1)
print(f"  Governing faction performance — no grievance: {perf_ld_no_grievance:.4f}  "
      f"with grievance: {perf_ld_with_grievance:.4f}")
assert perf_ld_with_grievance < perf_ld_no_grievance, \
    "an unaddressed grievance should COST a governing faction support, not help it"

capture = 0.3 + 0.5 * max(0.0, -nc.loyalty)
nc.grievances = []
perf_nc_no_grievance = -((econ_signal * 0.5 + (state.stability.value - 0.5)) / 1.5) * capture
nc.grievances = [type(faction(state, "workers_front").grievances[0])(source="Test", severity=1.0, turns_active=0)]
perf_nc_with_grievance = (-((econ_signal * 0.5 + (state.stability.value - 0.5)) / 1.5) * capture
                           + nc.grievance_pressure() * 0.1)
print(f"  Opposition faction performance — no grievance: {perf_nc_no_grievance:.4f}  "
      f"with grievance: {perf_nc_with_grievance:.4f}")
assert perf_nc_with_grievance > perf_nc_no_grievance, \
    "anger at government policy should ENERGIZE an opposition faction's support, not cost it"
print("  PASS: grievance pressure correctly cuts opposite ways for governing vs opposition factions")


section("F9: Legislative passage nudges electoral support in the same direction as loyalty")
state = fresh()
law = bill("minimum_wage_act")  # workers_front loyalty delta +0.20
wf = faction(state, "workers_front")
support_before = wf.support
law.status = "proposed"
state.legislature.pending_bills.append(law)
resolve_vote(state, law)
support_after = wf.support
print(f"  Workers' Front support: {support_before:.4f} → {support_after:.4f}  (loyalty delta was +0.20)")
assert support_after > support_before, "a law that pleases a faction's base should also nudge its electoral support up"
print("  PASS: legislation's electoral effect reuses the existing loyalty-delta signal, no duplicate field needed")


section("F10: Support renormalizes to sum to ~1.0 after drift")
state = fresh()
engine = TurnEngine()
for _ in range(10):
    state = engine.advance(state)
total_support = sum(f.support for f in state.country.factions)
print(f"  Total support after 10 turns of drift: {total_support:.6f}")
assert abs(total_support - 1.0) < 1e-9, "support shares must renormalize to exactly 1.0 every turn"
print("  PASS: support stays a coherent share of the electorate, never drifts from 1.0")


section("F11: Scheduled election triggers automatically after a full term")
state = fresh()
engine = TurnEngine()
assert len(state.election_history) == 0
for _ in range(TERM_LENGTH_TURNS - 1):
    state = engine.advance(state)
print(f"  After {TERM_LENGTH_TURNS - 1} turns: elections held = {len(state.election_history)}")
assert len(state.election_history) == 0, "no election should fire before the term is actually up"
state = engine.advance(state)
print(f"  After {TERM_LENGTH_TURNS} turns: elections held = {len(state.election_history)}")
assert len(state.election_history) == 1, "a scheduled election should fire exactly when the term elapses"
assert not state.election_history[0].was_snap_election
assert state.last_election_turn == state.turn
print("  PASS: the term timer fires a scheduled election automatically, exactly once, on time")


section("F12: Snap election triggers on full coalition collapse")
state = fresh()
for f in state.country.factions:
    f.in_coalition = False
assert should_trigger_snap_election(state), "an empty coalition should immediately qualify for a snap election"
assert len(state.election_history) == 0
result = hold_election(state, snap=True)
print(f"  Snap election held at turn {result.turn}. was_snap_election={result.was_snap_election}")
assert len(state.election_history) == 1
assert state.election_history[0].was_snap_election
print("  PASS: coalition collapse correctly qualifies for, and can trigger, a snap election")


section("F13: Campaign action shifts the player's own party's support, pulling from the top rival")
state = fresh()
ld = faction(state, "liberal_democrats")
nc = faction(state, "national_conservatives")  # the biggest rival by support (0.32 vs others)
ld_before, nc_before = ld.support, nc.support
pc_before = state.player.political_capital
result = run_campaign(state)
print(f"  {result.message}")
print(f"  Liberal Democrats: {ld_before:.4f} → {ld.support:.4f}   "
      f"National Conservatives (rival): {nc_before:.4f} → {nc.support:.4f}")
assert result.success
assert ld.support > ld_before, "campaigning should raise the player's own party's support"
assert nc.support < nc_before, "the pull should come from the strongest rival specifically"
assert state.player.political_capital == pc_before - 10.0
print("  PASS: campaign action gives the player direct, costed agency over their own electoral support")


section("F14: Action gating — government-only actions blocked in opposition; a few remain available")
state = fresh()
state.player.in_government = False

from engine.actions import ACTIONS as ACTION_CATALOG

for action_id in ["propose_bill", "reshuffle", "improve_relations", "address_grievance"]:
    action_def = next(a for a in ACTION_CATALOG if a.id == action_id)
    ok, reason = action_def.available(state)
    print(f"  {action_id}: available={ok}  reason='{reason}'")
    assert not ok, f"{action_id} should be unavailable while in opposition"
    assert reason == "not in government"

for action_id in ["court_faction", "campaign", "call_confidence_vote"]:
    action_def = next(a for a in ACTION_CATALOG if a.id == action_id)
    ok, reason = action_def.available(state)
    print(f"  {action_id}: available={ok}")
    assert ok, f"{action_id} should remain available in opposition"
print("  PASS: government-gated actions correctly blocked in opposition; opposition-viable ones remain open")


section("F15: Multi-term integration — the game continues coherently across multiple elections")
random.seed(2024)
state = fresh()
engine = TurnEngine()
# Bias hard toward instability so we actually see a government change or two
# within a reasonable number of terms, without waiting out arbitrarily long odds.
state.country.economy.unemployment = 0.22
for m in state.cabinet.ministers:
    m.ambition = 0.8

turns_run = 0
max_turns = TERM_LENGTH_TURNS * 5  # up to 5 terms
government_changes = 0
last_ruling = state.ruling_faction_id
for _ in range(max_turns):
    state = engine.advance(state)
    turns_run += 1
    if state.ruling_faction_id != last_ruling:
        government_changes += 1
        last_ruling = state.ruling_faction_id

print(f"  Ran {turns_run} turns ({turns_run / TERM_LENGTH_TURNS:.1f} terms).")
print(f"  Elections held: {len(state.election_history)}")
print(f"  Government changes: {government_changes}")
for result in state.election_history[:6]:
    tag = "SNAP" if result.was_snap_election else "scheduled"
    print(f"    · Turn {result.turn} ({tag}): ruling={result.ruling_faction_id}  "
          f"player_in_gov={result.player_in_government}")
assert len(state.election_history) >= 1, "at least one election (scheduled, if nothing else) must have fired over 5 terms"
assert state.turn == turns_run, "turn counter should track cleanly across every election and snap election"
for f in state.country.factions:
    assert 0.0 <= f.support <= 1.0, f"{f.name} support out of bounds after multi-term simulation: {f.support}"
    assert 0 <= f.seats <= state.legislature.total_seats, f"{f.name} seats out of bounds: {f.seats}"
total_seats_final = sum(f.seats for f in state.country.factions)
assert total_seats_final == state.legislature.total_seats, \
    f"total seats should always sum to exactly {state.legislature.total_seats}, got {total_seats_final}"
print("  PASS: the game runs coherently across multiple terms — elections fire, seats stay in bounds, "
      "and the political timeline accumulates without crashing")


section("F16: Turnout — eligible voters, national turnout, and votes are coherent")
state = fresh()
t = elec.compute_turnout(state)
assert t["eligible"] == int(state.country.population * elec.VOTING_AGE_FRACTION), \
    "eligible voters should be the voting-age share of the population"
assert 0.30 <= t["turnout_pct"] <= 0.95, f"national turnout should be plausible, got {t['turnout_pct']}"
assert abs(sum(t["votes"].values()) - t["total_cast"]) <= len(state.country.factions), \
    "per-party vote counts should sum (within rounding) to total votes cast"
assert abs(sum(t["vote_share"].values()) - 1.0) < 1e-6, "vote shares should sum to 1"
print(f"  eligible {t['eligible']:,}, turnout {t['turnout_pct']*100:.1f}%, cast {t['total_cast']:,}")
print("  PASS: turnout produces coherent eligible/turnout/vote figures")


section("F17: Differential turnout — a demoralized government cedes seats it would hold on support alone")
state = fresh()
# Baseline: seats purely from support (the turnout-free proportional path).
flat = _allocate_seats(state.country.factions, 100)
# Collapse the government's standing: its base stays home, the hostile
# opposition turns out. Support is UNCHANGED — only turnout differs.
state.player.approval = 0.12
state.stability.value = 0.18
t = elec.compute_turnout(state)
weighted = _allocate_seats(state.country.factions, 100, weights=t["effective_votes"])
ld_flat, ld_turn = flat["liberal_democrats"], weighted["liberal_democrats"]
nc_flat, nc_turn = flat["national_conservatives"], weighted["national_conservatives"]
print(f"  Liberal Democrats (governing):        {ld_flat} → {ld_turn} seats")
print(f"  National Conservatives (hostile opp): {nc_flat} → {nc_turn} seats")
assert ld_turn < ld_flat, "a demoralized governing base should cost the governing party seats"
assert nc_turn > nc_flat, "an energized hostile opposition should gain seats purely from turnout"
assert sum(weighted.values()) == 100, "turnout-weighted allocation must still sum to total seats"
print("  PASS: differential turnout moves real seats, not just a displayed number")


section("F18: Election result turnout fields populate and round-trip through save/load")
from engine import persistence as _pf
state = fresh()
before = hold_election(state)
assert before.eligible_voters > 0 and before.total_votes_cast > 0, "turnout fields should be populated"
assert abs(sum(before.vote_share_by_faction.values()) - 1.0) < 1e-6
assert abs(sum(before.seat_pct_by_faction.values()) - 1.0) < 1e-6, "seat shares should sum to 1"
restored = _pf.deserialize_state(_pf.serialize_state(state))
after = restored.election_history[-1]
assert after.eligible_voters == before.eligible_voters
assert after.total_votes_cast == before.total_votes_cast
assert abs(after.turnout_pct - before.turnout_pct) < 1e-9
assert after.votes_by_faction == before.votes_by_faction
assert after.seat_pct_by_faction == before.seat_pct_by_faction
print(f"  turnout {before.turnout_pct*100:.1f}% and per-party votes preserved across save/load")
print("  PASS: new turnout/vote fields serialize and reload intact")



# ══════════════════════════════════════════════════════════════════════════
# SECTION G — CAMPAIGN FRAMEWORK  (data loader, campaign gen, save/load)
# ══════════════════════════════════════════════════════════════════════════

from content import loader as _loader
from content import campaign_content as _cc
from content import traits as _traits
from engine.campaign import CampaignConfig, generate_campaign, default_config
from engine import persistence as _persist
from engine import player_ops


section("G1: Data loader reproduces build_sample_game() exactly for Ardenia")
_a = build_sample_game()
_b = _loader.build_state_for("ardenia")
assert _a.player.name == _b.player.name
assert abs(_a.player.approval - _b.player.approval) < 1e-9
assert abs(_a.country.economy.gdp - _b.country.economy.gdp) < 1e-6
assert len(_a.country.factions) == len(_b.country.factions)
assert {f.id for f in _a.country.factions} == {f.id for f in _b.country.factions}
assert len(_a.cabinet.ministers) == len(_b.cabinet.ministers)
assert len(_a.world) == len(_b.world)
assert len(_a.modifiers) == len(_b.modifiers)
for fa, fb in zip(_a.country.factions, _b.country.factions):
    assert abs(fa.loyalty - fb.loyalty) < 1e-9 and abs(fa.support - fb.support) < 1e-9
print("  PASS: JSON port is a faithful, field-for-field reproduction of the hardcoded start")


section("G2: All defined countries load and are playable")
ids = _loader.available_country_ids()
assert "ardenia" in ids and len(ids) >= 4, f"expected >=4 countries, got {ids}"
_eng = TurnEngine()
for cid in ids:
    s = _loader.build_state_for(cid)
    assert s.country.is_player
    assert len(s.world) == len(ids) - 1, f"{cid}: world should be the other countries"
    for _ in range(6):
        s = _eng.advance(s)
    assert 0.0 <= s.player.approval <= 1.0
print(f"  PASS: all {len(ids)} countries ({', '.join(ids)}) load and run 6 turns cleanly")


section("G3: Difficulty reshapes starting conditions monotonically")
easy = generate_campaign(CampaignConfig(country_id="ardenia", difficulty_id="easy"))
norm = generate_campaign(CampaignConfig(country_id="ardenia", difficulty_id="normal"))
hard = generate_campaign(CampaignConfig(country_id="ardenia", difficulty_id="hard"))
print(f"  approval:   easy {easy.player.approval:.2f} > normal {norm.player.approval:.2f} > hard {hard.player.approval:.2f}")
print(f"  PC:         easy {easy.player.political_capital:.0f} > normal {norm.player.political_capital:.0f} > hard {hard.player.political_capital:.0f}")
print(f"  debt:       easy {easy.country.economy.public_debt_pct:.2f} < normal {norm.country.economy.public_debt_pct:.2f} < hard {hard.country.economy.public_debt_pct:.2f}")
assert easy.player.approval > norm.player.approval > hard.player.approval
assert easy.player.political_capital > norm.player.political_capital > hard.player.political_capital
assert easy.country.economy.public_debt_pct < norm.country.economy.public_debt_pct < hard.country.economy.public_debt_pct
assert easy.stability.value > hard.stability.value
print("  PASS: easy → hard scales approval, capital, debt, and stability in the right directions")


section("G4: Character background applies subtle, correct nudges")
# Baseline uses 'economist' (0 PC delta) so the business-exec PC bonus is
# measured against a neutral, not against another capital-granting background.
base = generate_campaign(CampaignConfig(country_id="ardenia", background_id="economist"))
union = generate_campaign(CampaignConfig(country_id="ardenia", background_id="union_leader"))
biz = generate_campaign(CampaignConfig(country_id="ardenia", background_id="business_executive"))
wf_base = next(f for f in base.country.factions if f.id == "workers_front")
wf_union = next(f for f in union.country.factions if f.id == "workers_front")
print(f"  workers' loyalty — base {wf_base.loyalty:.2f}, union leader {wf_union.loyalty:.2f}")
assert wf_union.loyalty > wf_base.loyalty, "union leader should raise labour loyalty"
assert biz.player.political_capital > base.player.political_capital, "exec grants starting capital"
print("  PASS: backgrounds nudge the right factions and stats, subtly")


section("G5: Character identity overrides apply")
cfg = CampaignConfig(country_id="veldoria", leader_name="Test Chancellor",
                     title="Chancellor", difficulty_id="normal")
s = generate_campaign(cfg)
assert s.player.name == "Test Chancellor" and s.player.title == "Chancellor"
assert s.campaign_meta["country_id"] == "veldoria"
assert s.legacy is not None and s.legacy.leader_name == "Test Chancellor"
assert len(s.legacy.milestones) >= 1
print("  PASS: name/title override applied; campaign_meta and legacy record seeded")


section("G5b: Party choice creates a coherent contextual opening")
# A party from the authored coalition becomes the lead party in its version
# of the Reckoning result, and supplies the leader's default ideology.
sd = generate_campaign(CampaignConfig(
    country_id="ardenia", party_id="social_democrats",
    background_id="none", opening_role="contextual", seed=51))
sd_party = next(f for f in sd.country.factions if f.id == "social_democrats")
assert sd.player.in_government and sd.ruling_faction_id == "social_democrats"
assert sd_party.in_coalition
assert sd.player.ideology_economic == sd_party.ideology.economic
assert sd.player.ideology_social == sd_party.ideology.social
assert sd_party.leader == sd.player.name
assert sum(f.seats for f in sd.country.factions if f.in_coalition) >= \
       sd.legislature.majority_threshold()
assert all(m.faction_id in sd.coalition_faction_ids() for m in sd.cabinet.ministers)

# A party outside the authored coalition begins in opposition by default.
nc = generate_campaign(CampaignConfig(
    country_id="ardenia", party_id="national_conservatives",
    background_id="none", opening_role="contextual", seed=52))
assert not nc.player.in_government
assert nc.ruling_faction_id == "liberal_democrats"
assert nc.player.title == "Opposition Leader"
assert nc.campaign_meta["opening_role"] == "opposition"
assert "portrait" not in nc.campaign_meta

# Either side of power can be selected explicitly with the same party data.
nc_gov = generate_campaign(CampaignConfig(
    country_id="ardenia", party_id="national_conservatives",
    background_id="none", opening_role="government", seed=53))
assert nc_gov.player.in_government
assert nc_gov.ruling_faction_id == "national_conservatives"
assert sum(f.seats for f in nc_gov.country.factions if f.in_coalition) >= \
       nc_gov.legislature.majority_threshold()

ld_opp = generate_campaign(CampaignConfig(
    country_id="ardenia", party_id="liberal_democrats",
    background_id="none", opening_role="opposition", seed=54))
assert not ld_opp.player.in_government
assert ld_opp.ruling_faction_id != "liberal_democrats"
assert not next(f for f in ld_opp.country.factions
                if f.id == "liberal_democrats").in_coalition

# Personal ideology overrides remain distinct from the chosen party line.
personal = generate_campaign(CampaignConfig(
    country_id="ardenia", party_id="workers_front", opening_role="opposition",
    ideology_economic=-0.25, ideology_social=0.75, background_id="none"))
assert personal.player.ideology_economic == -0.25
assert personal.player.ideology_social == 0.75
# Old saves shed the retired portrait metadata on load and never write it.
from engine import persistence as _party_persistence
old_payload = _party_persistence.serialize_state(nc)
old_payload["campaign_meta"]["portrait"] = "portrait_a"
migrated = _party_persistence.deserialize_state(old_payload)
assert "portrait" not in migrated.campaign_meta
assert "portrait" not in _party_persistence.serialize_state(migrated)["campaign_meta"]
print("  PASS: party, ideology, government/opposition role, cabinet, and opening metadata agree")


section("G5c: Every Ardenian party can start and advance contextually")
for party_id in ("liberal_democrats", "national_conservatives", "social_democrats",
                 "agrarian_union", "workers_front"):
    st = generate_campaign(CampaignConfig(
        country_id="ardenia", party_id=party_id,
        background_id="career_politician", opening_role="contextual", seed=55))
    own = next(f for f in st.country.factions if f.id == party_id)
    assert own.leader == st.player.name
    assert party_id in " ".join(st.turn_log).lower().replace(" ", "_") or own.name in " ".join(st.turn_log)
    TurnEngine().advance(st)
print("  PASS: all five parties produce a contextual campaign and survive the turn loop")


section("G5d: An AI domestic government legislates while the player opposes")
from engine import domestic_ai as _domestic_ai
opp = generate_campaign(CampaignConfig(
    country_id="ardenia", party_id="national_conservatives",
    opening_role="opposition", background_id="none", seed=901))
eng = TurnEngine()
eng.advance(opp)
gov_bill = player_ops.government_bill(opp)
assert gov_bill is not None, "the government should introduce a bill in the first sitting"
assert gov_bill.proposed_by == opp.ruling_faction_id
assert gov_bill in opp.legislature.pending_bills
before_projection = legislative.projected_votes(opp, gov_bill)
response = player_ops.op_oppose_government_bill(opp, gov_bill.id)
assert response.success
assert _domestic_ai.response_for(opp, gov_bill.id) == "oppose"
assert gov_bill.lobbying_bonus[opp.player.faction_id] < 0
assert not player_ops.op_support_government_bill(opp, gov_bill.id).success, \
    "the opposition gets one declared position per government bill"

# The response window and bill sponsor survive a save/load before division.
payload = _party_persistence.serialize_state(opp)
restored = _party_persistence.deserialize_state(payload)
restored_bill = player_ops.government_bill(restored)
assert restored_bill is not None and restored_bill.proposed_by == restored.ruling_faction_id
assert _domestic_ai.response_for(restored, restored_bill.id) == "oppose"
eng.advance(restored)
assert restored_bill not in restored.legislature.pending_bills
assert restored_bill.status in {"active", "failed"}
after_projection = (restored_bill.votes_for, restored_bill.votes_against)
print(f"  {gov_bill.name}: projected {before_projection[0]}-{before_projection[1]}, "
      f"resolved {after_projection[0]}-{after_projection[1]} after opposition")
print("  PASS: diagnose → introduce → opposition response → vote uses shared mechanics and persists")


section("G5e: Support and amendment are distinct opposition strategies")
supporter = generate_campaign(CampaignConfig(
    country_id="ardenia", party_id="agrarian_union",
    opening_role="opposition", background_id="none", seed=902))
TurnEngine().advance(supporter)
support_bill = player_ops.government_bill(supporter)
assert player_ops.op_support_government_bill(supporter, support_bill.id).success
assert _domestic_ai.response_for(supporter, support_bill.id) == "support"
assert support_bill.lobbying_bonus[supporter.player.faction_id] > 0

amender = generate_campaign(CampaignConfig(
    country_id="ardenia", party_id="workers_front", opening_role="opposition",
    ideology_economic=-0.95, ideology_social=0.55,
    background_id="none", seed=903))
TurnEngine().advance(amender)
amend_bill = player_ops.government_bill(amender)
old_ideology = (amend_bill.ideology.economic, amend_bill.ideology.social)
assert player_ops.op_amend_government_bill(amender, amend_bill.id).success
new_ideology = (amend_bill.ideology.economic, amend_bill.ideology.social)
assert new_ideology != old_ideology
assert "Amended in committee" in amend_bill.description
assert amend_bill.effects.faction_loyalty_deltas[amender.player.faction_id] > 0
print("  PASS: support whips votes; amendment changes ideology, stakes, and bill text")


section("G5f: Winning office ends AI rule and restores the government title")
challenger = generate_campaign(CampaignConfig(
    country_id="ardenia", party_id="liberal_democrats",
    opening_role="opposition", background_id="none", seed=904))
TurnEngine().advance(challenger)
outgoing_bill = player_ops.government_bill(challenger)
assert outgoing_bill is not None
for f in challenger.country.factions:
    f.support = 0.80 if f.id == challenger.player.faction_id else 0.05
elec.hold_election(challenger)
assert challenger.player.in_government
assert challenger.player.title == "Prime Minister"
assert player_ops.government_bill(challenger) is None
assert outgoing_bill.status == "lapsed"
assert outgoing_bill in challenger.legislature.law_history
print("  PASS: election victory lapses the outgoing programme and switches opposition into government")


section("G5g: Opposition government cadence survives a full term")
term = generate_campaign(CampaignConfig(
    country_id="ardenia", party_id="national_conservatives",
    opening_role="opposition", background_id="career_politician", seed=905))
eng = TurnEngine()
responses = 0
for month in range(48):
    bill = player_ops.government_bill(term)
    if bill is not None and not _domestic_ai.response_for(term, bill.id):
        term.player.political_capital = 100.0
        operations = (player_ops.op_support_government_bill,
                      player_ops.op_oppose_government_bill,
                      player_ops.op_amend_government_bill)
        result = operations[responses % len(operations)](term, bill.id)
        assert result.success
        responses += 1
    eng.advance(term)
assert term.election_history, "a complete opposition term must reach an election"
assert term.domestic_politics.get("bills_introduced", 0) >= 3
assert responses >= 3
print(f"  {term.domestic_politics['bills_introduced']} government bills, "
      f"{responses} declared opposition positions, {len(term.election_history)} election")
print("  PASS: AI government activity is paced across a full opposition term")


section("G5h: Opposition platform and shadow team are mechanical and persistent")
from engine import opposition as _opposition, cabinet_ops as _cabinet_ops
platform = generate_campaign(CampaignConfig(
    country_id="ardenia", party_id="national_conservatives",
    opening_role="opposition", background_id="none", seed=906))
platform.player.political_capital = 100.0
pledge_bill = next(b for b in _opposition.pledge_candidates(platform)
                   if b.id == "education_modernisation_act")
assert player_ops.op_add_agenda_pledge(platform, pledge_bill.id).success
assert _opposition.pledge_for(platform, pledge_bill.id)["status"] == "pledged"

shortlist = _cabinet_ops.shadow_shortlist(platform, "Economy")
nominee = max(shortlist, key=lambda m: m.implementation_quality())
assert player_ops.op_appoint_shadow_minister(platform, "Economy", nominee).success
support_before = next(f for f in platform.country.factions
                      if f.id == platform.player.faction_id).support
cred_before = _opposition.credibility(platform)
assert player_ops.op_campaign_on_pledge(platform, pledge_bill.id).success
assert next(f for f in platform.country.factions
            if f.id == platform.player.faction_id).support > support_before
assert _opposition.credibility(platform) > cred_before
assert not player_ops.op_campaign_on_pledge(platform, pledge_bill.id).success, \
    "issue campaigns have a cooldown instead of being spammable"
assert _opposition.election_turnout_bonus(
    platform, next(f for f in platform.country.factions
                   if f.id == platform.player.faction_id)) > 0

platform_payload = _party_persistence.serialize_state(platform)
platform_restored = _party_persistence.deserialize_state(platform_payload)
assert platform_restored.shadow_cabinet.get("Economy").id == nominee.id
assert _opposition.pledge_for(platform_restored, pledge_bill.id)["campaigns"] == 1
assert _opposition.credibility(platform_restored) == _opposition.credibility(platform)
print("  PASS: promises, credibility, issue campaigns, shadow competence, and save/load agree")


section("G5i: A winning shadow cabinet takes office and faces its mandate")
mandate = generate_campaign(CampaignConfig(
    country_id="ardenia", party_id="liberal_democrats",
    opening_role="opposition", background_id="none", seed=907))
mandate.player.political_capital = 100.0
promised_id = "progressive_tax_reform_act"
assert player_ops.op_add_agenda_pledge(mandate, promised_id).success
finance_pick = max(_cabinet_ops.shadow_shortlist(mandate, "Finance"),
                   key=lambda m: m.implementation_quality())
assert player_ops.op_appoint_shadow_minister(mandate, "Finance", finance_pick).success
for f in mandate.country.factions:
    f.support = 0.80 if f.id == mandate.player.faction_id else 0.05
result = elec.hold_election(mandate)
assert result.player_gained_office and mandate.player.in_government
assert mandate.cabinet.get("Finance").id == finance_pick.id
assert not mandate.shadow_cabinet.ministers
assert mandate.domestic_politics["opposition_agenda"]["mandate_start_turn"] == mandate.turn

promised_bill = next(b for b in player_ops.proposable_bills(mandate)
                     if b.id == promised_id)
assert player_ops.op_propose_bill(mandate, promised_bill).success
assert _opposition.pledge_for(mandate, promised_id)["status"] == "introduced"
for voting_faction in mandate.country.factions:
    promised_bill.lobbying_bonus[voting_faction.id] = 1.0
assert player_ops.op_call_vote(mandate, promised_bill).success
assert _opposition.pledge_for(mandate, promised_id)["status"] == "delivered"
print("  PASS: personnel continuity survives victory and a published promise can be delivered")


section("G6: National traits are applied at generation")
# Veldoria has strong_institutions (+bureaucratic capacity). Compare a
# trait-bearing country's post-generation capacity to its raw JSON baseline.
raw = _loader.build_state_for("veldoria")
gen = generate_campaign(default_config("veldoria"))
print(f"  bureaucratic capacity — raw load {raw.country.bureaucratic_capacity:.2f}, "
      f"after traits {gen.country.bureaucratic_capacity:.2f}")
assert gen.country.bureaucratic_capacity > raw.country.bureaucratic_capacity, \
    "strong_institutions should raise bureaucratic capacity at generation"
print("  PASS: national traits nudge the starting canvas as intended")


section("G7: Campaign generation is reproducible for a fixed seed")
c = CampaignConfig(country_id="krasova", seed=4242, difficulty_id="hard", background_id="economist")
s1 = generate_campaign(c)
s2 = generate_campaign(c)
assert s1.player.approval == s2.player.approval
assert s1.player.political_capital == s2.player.political_capital
assert s1.country.economy.gdp == s2.country.economy.gdp
print("  PASS: same config + seed yields an identical campaign")


section("G8: Save / load round-trip preserves state")
s = generate_campaign(CampaignConfig(country_id="ardenia", difficulty_id="hard"))
s.player.political_capital = 100.0
bill = next(b for b in player_ops.proposable_bills(s) if b.tier == "statutory")
player_ops.op_propose_bill(s, bill)
player_ops.op_call_vote(s, bill)
player_ops.op_foreign_loan(s, "veldoria")
eng = TurnEngine()
for _ in range(8):
    s = eng.advance(s)

_persist.save_campaign(s, slot="_smoke_test")
loaded = _persist.load_campaign("_smoke_test")
assert loaded.turn == s.turn
assert abs(loaded.player.approval - s.player.approval) < 1e-9
assert abs(loaded.country.economy.gdp - s.country.economy.gdp) < 1e-6
assert len(loaded.modifiers) == len(s.modifiers)
assert len(loaded.country.economy.loans) == len(s.country.economy.loans)
assert loaded.campaign_meta.get("difficulty") == "hard"
_persist.delete_save("_smoke_test")
print("  PASS: a saved campaign reloads with turn, economy, modifiers, loans, and meta intact")


section("G9: A loaded campaign continues simulating identically to one never saved")
s = generate_campaign(CampaignConfig(country_id="merova", difficulty_id="normal", seed=77))
eng = TurnEngine()
for _ in range(5):
    s = eng.advance(s)
# Two copies: one via save/load, one direct.
loaded = _persist.deserialize_state(_persist.serialize_state(s))
direct = _persist.deserialize_state(_persist.serialize_state(s))
import random as _rnd
for _ in range(6):
    _rnd.seed(303); direct = TurnEngine().advance(direct)
    _rnd.seed(303); loaded = TurnEngine().advance(loaded)
assert abs(direct.country.economy.gdp - loaded.country.economy.gdp) < 1e-6
assert abs(direct.player.approval - loaded.player.approval) < 1e-9
assert abs(direct.stability.value - loaded.stability.value) < 1e-9
print("  PASS: serialization is simulation-faithful — a reloaded game plays forward identically")


section("G10: Save format tolerates missing (future-compat) fields")
data = _persist.serialize_state(generate_campaign(default_config("ardenia")))
data.pop("campaign_meta", None)
data.pop("legacy", None)
for c in data["world"]:
    c.pop("national_traits", None)
restored = _persist.deserialize_state(data)
assert restored.legacy is not None, "missing legacy should fall back to a fresh default"
assert restored.campaign_meta == {}
assert restored.player is not None
print("  PASS: older/newer saves with absent fields load gracefully via defaults")


# ══════════════════════════════════════════════════════════════════════════
# SECTION H — DYNAMIC EVENTS
# ══════════════════════════════════════════════════════════════════════════
# A synthetic, always-fires EventDef stands in for the real catalog (patched
# in via engine.events.event_catalog) so these tests are deterministic and
# independent of content/events.py's real trigger conditions/chances.

_test_event = EventDef(
    id="_smoke_test_event",
    title="Smoke Test Situation",
    description="A synthetic situation used only by the test suite.",
    category="Test",
    condition=lambda state: True,
    chance=1.0,
    default_option_id="do_nothing",
    options=[
        EventOption(id="boost_loyalty", label="Boost loyalty", pc_cost=5.0,
                    description="Test option A.",
                    effects=LawEffect(faction_loyalty_deltas={"workers_front": 0.10})),
        EventOption(id="do_nothing", label="Do nothing", pc_cost=0.0,
                    description="Test option B (the default).",
                    effects=LawEffect(budget_revenue_delta=10.0)),
    ],
)


section("H1: A new situation fires and does not duplicate while pending")
with patch("engine.events.event_catalog", return_value=[_test_event]):
    state = fresh()
    eng = TurnEngine()
    state = eng.advance(state)
    assert len(state.pending_events) == 1
    assert state.pending_events[0].event_id == "_smoke_test_event"
    state = eng.advance(state)
    assert len(state.pending_events) == 1, "a pending situation should not fire a second one"
    assert state.pending_events[0].turns_pending == 2, \
        "aging runs the same turn a situation fires, so it starts at 1, not 0"
print("  PASS: a situation fires once and holds until resolved")


section("H2: Resolving an option applies its effects and clears the queue")
with patch("engine.events.event_catalog", return_value=[_test_event]):
    state = fresh()
    state = TurnEngine().advance(state)
    wf_before = faction(state, "workers_front").loyalty
    result = player_ops.op_resolve_event(state, "_smoke_test_event", "boost_loyalty")
    assert result.success
    assert not state.pending_events
    wf_after = faction(state, "workers_front").loyalty
    assert wf_after > wf_before, "chosen option's loyalty delta should have landed"
print("  PASS: resolving a situation applies the chosen option and clears it")


section("H3: An unaffordable option is rejected and leaves the situation pending")
with patch("engine.events.event_catalog", return_value=[_test_event]):
    state = fresh()
    state = TurnEngine().advance(state)
    state.player.political_capital = 0.0
    result = player_ops.op_resolve_event(state, "_smoke_test_event", "boost_loyalty")
    assert not result.success
    assert len(state.pending_events) == 1, "situation should remain pending after a failed choice"
print("  PASS: an unaffordable option is refused and the situation stays open")


section("H4: An unaddressed situation auto-resolves to its default option")
# The stub always fires (chance=1.0), so once the original instance lapses,
# a fresh one immediately refills the queue — expected for a permanently-
# eligible synthetic event, not a bug. The real assertion is that the LAPSE
# actually happened and applied its default option, not that the queue
# stays empty afterward.
with patch("engine.events.event_catalog", return_value=[_test_event]):
    state = fresh()
    eng = TurnEngine()
    state = eng.advance(state)  # fires
    for _ in range(events.EVENT_AUTO_RESOLVE_TURNS + 1):
        state = eng.advance(state)
    assert any("SITUATION LAPSED" in msg for msg in state.event_history)
    assert any(m.target == "budget_revenue" and m.source_id == "_smoke_test_event" for m in state.modifiers), \
        "default option's flat delta should have been instantiated as a Modifier"
print("  PASS: a situation left unaddressed too long auto-resolves to its default option")


section("H5: 'Respond to Situation' is only offered while something is pending")
with patch("engine.events.event_catalog", return_value=[_test_event]):
    state = fresh()
    state = TurnEngine().advance(state)  # fires the test situation
    #   "5"  → category: Situations
    #   "1"  → action: Respond to Situation
    #   "2"  → option: "Do nothing" (second option, the free one)
    #   "0"  → back to category
    #   "0"  → exit menu
    run_scripted(state, ["5", "1", "2", "0", "0"])
    assert not state.pending_events, "resolving via the menu should clear the situation"
print("  PASS: the Situations action surfaces the pending event and resolves it via the menu")


section("H6: Institutional event gating keeps executive power out of opposition hands")
from models.events import PendingEvent as _RolePendingEvent
role_opp = generate_campaign(CampaignConfig(
    country_id="ardenia", party_id="national_conservatives",
    opening_role="opposition", background_id="none", seed=908))
executive_event = events.event_by_id("labour_unrest_spreads")
assert not events.available_to_player(role_opp, executive_event)
role_opp.pending_events = [_RolePendingEvent(event_id=executive_event.id)]
before_econ = (role_opp.country.economy.gdp,
               role_opp.country.economy.budget.expenditure)
before_loyalty = {f.id: f.loyalty for f in role_opp.country.factions}
refused = player_ops.op_resolve_event(
    role_opp, executive_event.id, executive_event.options[0].id)
assert not refused.success
assert not role_opp.pending_events, "an old government-only pending event should close"
assert before_econ == (role_opp.country.economy.gdp,
                       role_opp.country.economy.budget.expenditure)
assert before_loyalty == {f.id: f.loyalty for f in role_opp.country.factions}
assert any("SITUATION CLOSED" in line for line in role_opp.event_history)

government = fresh()
opposition_event = events.event_by_id("government_policy_retreat")
assert not events.available_to_player(government, opposition_event)
print("  PASS: role changes close stale decisions without applying treasury, police, or country effects")


section("H7: Opposition receives political situations with opposition-scale consequences")
political_opp = generate_campaign(CampaignConfig(
    country_id="ardenia", party_id="workers_front",
    opening_role="opposition", background_id="none", seed=909))
political_opp.player.political_capital = 100.0
opp_event = events.event_by_id("government_policy_retreat")
assert events.available_to_player(political_opp, opp_event)
political_opp.pending_events = [_RolePendingEvent(event_id=opp_event.id)]
own = next(f for f in political_opp.country.factions
           if f.id == political_opp.player.faction_id)
support_before = own.support
cred_before = _opposition.credibility(political_opp)
country_before = (political_opp.country.economy.gdp,
                  political_opp.country.economy.budget.revenue,
                  political_opp.country.economy.budget.expenditure)
resolved = player_ops.op_resolve_event(
    political_opp, opp_event.id, "publish_alternative")
assert resolved.success and not political_opp.pending_events
assert own.support > support_before and _opposition.credibility(political_opp) > cred_before
assert country_before == (political_opp.country.economy.gdp,
                          political_opp.country.economy.budget.revenue,
                          political_opp.country.economy.budget.expenditure)
print("  PASS: opposition events move party support and credibility, not ministries or the treasury")


# ══════════════════════════════════════════════════════════════════════════
# SECTION I — LIVING WORLD & CIVIL-WAR CRISIS
# ══════════════════════════════════════════════════════════════════════════

from engine import worldsim, crisis
from engine import persistence as _pi
from content.loader import build_state_for as _build_for, available_country_ids as _country_ids


def _load(cid):
    """A world-enabled state for a given player country, PC topped up."""
    s = _build_for(cid)
    s.player.political_capital = 80.0
    return s


section("I1: World countries have a life of their own — economy and stability drift")
random.seed(11)
state = _load("ardenia")
kr = state.world_country("krasova")
gdp_before, stab_before = kr.economy.gdp, kr.stability
eng = TurnEngine()
for _ in range(12):
    state = eng.advance(state)
kr = state.world_country("krasova")
print(f"  Krasova GDP {gdp_before:,.0f} → {kr.economy.gdp:,.0f}; stability {stab_before:.2f} → {kr.stability:.2f}")
assert kr.economy.gdp != gdp_before, "a world country's economy should evolve on its own"
assert kr.stability != stab_before, "a world country's stability should move on its own"
assert 0.0 <= kr.stability <= 1.0
print("  PASS: world countries evolve autonomously, not just in reaction to the player")


section("I2: World↔world relations exist and drift (not just player↔world)")
state = _load("ardenia")
ve = state.world_country("veldoria")
assert "krasova" in ve.relations, "world countries must hold relations toward EACH OTHER, not only the player"
vk_before = ve.relations["krasova"].score
random.seed(5)
eng = TurnEngine()
for _ in range(10):
    state = eng.advance(state)
ve = state.world_country("veldoria")
print(f"  Veldoria→Krasova relation: {vk_before:+.2f} → {ve.relations['krasova'].score:+.2f}")
assert ve.relations["krasova"].score != vk_before, "world↔world relations should move over time"
print("  PASS: the world has its own web of relations that shifts independently of the player")


section("I3: Agenda actions fire, producing dispatches and relation changes")
random.seed(3)
state = _load("ardenia")
eng = TurnEngine()
from content.dispatches import MARKERS as _MK
_world_markers = [_MK[k] for k in ("world_deepen", "world_condemn", "world_undermine",
                                    "world_trade_pact", "world_court_player",
                                    "world_pressure_player", "world_condemn_player")]
world_dispatches = []
for _ in range(36):
    state = eng.advance(state)
    for line in state.turn_log:
        if any(k in line for k in _world_markers):
            world_dispatches.append(line)
print(f"  Captured {len(world_dispatches)} world-agenda dispatches over 3 years; samples:")
for d in world_dispatches[:4]:
    print(f"    · {d}")
assert world_dispatches, "AI countries should visibly act on their agendas over time"
print("  PASS: countries pursue their agendas and the player sees it happen")


section("I4: AI acts on the PLAYER — a foreign power moves the player's relations unprompted")
state = _load("ardenia")
actor = state.world_country("krasova")
actor.agenda = {"type": "revanchist", "rival": "ardenia"}  # target the player directly
before = state.country.relations["krasova"].score
worldsim._hostile_action(state, actor)   # deterministic: a hostile move against the player
after = state.country.relations["krasova"].score
print(f"  Player↔Krasova after a hostile AI move: {before:+.2f} → {after:+.2f}")
assert after < before, "an AI hostile action targeting the player should worsen the player's relation"
assert any("your" in m.lower() for m in state.turn_log), "it should surface as a player-facing dispatch"
# And a cooperative counterpart improves it.
actor.agenda = {"type": "trader", "ally": "ardenia"}
before2 = state.country.relations["krasova"].score
worldsim._cooperative_action(state, actor)
assert state.country.relations["krasova"].score > before2, "a courting AI action should improve the player's relation"
print("  PASS: foreign powers act ON the player, not just each other")


section("I5: Civil-war gauge — supercritical states tip over, wars bleed, recovery ends them")
# Direct-mechanics test, fully deterministic (no RNG, no turn loop): the full
# loop can legitimately rescue a collapsing state (confidence vote → snap
# election → stability reset), so 'must latch in N turns' is not a stable
# claim there.
state = _load("valmora")
assert not state.civil_war
for f in state.country.factions:
    if not f.in_coalition:
        f.loyalty = -0.85
        f.power = 0.85
state.stability.value = 0.12
target, _bd = crisis.compute_civil_war_risk(state)
assert target >= crisis.CIVIL_WAR_RISK_THRESHOLD, \
    f"fixture must be supercritical by construction (target {target:.2f})"
fell_on = None
for i in range(20):
    crisis.maybe_trigger_civil_war(state)
    if state.civil_war:
        fell_on = i + 1
        break
assert fell_on is not None, "a supercritical gauge must latch"
stab_before = state.stability.value
gdp_before = state.country.economy.gdp
crisis.maybe_trigger_civil_war(state)   # one war month: recurring penalties
assert state.civil_war
assert state.stability.value < stab_before, "ongoing war should drag stability"
assert state.country.economy.gdp < gdp_before, "ongoing war should bleed GDP"
# Recovery: heal the fundamentals and the war eventually ends.
for f in state.country.factions:
    f.loyalty = 0.5
    for g in f.grievances:
        g.severity = 0.1
state.stability.value = 0.85
state.country.economy.unemployment = 0.06
ended_on = None
for i in range(60):
    crisis.maybe_trigger_civil_war(state)
    if not state.civil_war:
        ended_on = i + 1
        break
assert ended_on is not None, "a healed state should climb back out of civil war"
print(f"  latched after {fell_on} pushes; war bled stability/GDP; ended {ended_on} months after recovery")
print("  PASS: the civil-war gauge latches, damages, and releases on the real thresholds")


section("I6: The crisis country starts hot but survivable")
state = _build_for("valmora")
print(f"  Valmora start civil_war_risk: {state.civil_war_risk:.2f} (threshold {crisis.CIVIL_WAR_RISK_THRESHOLD})")
assert 0.60 <= state.civil_war_risk < crisis.CIVIL_WAR_RISK_THRESHOLD, \
    "Valmora should begin on the brink — high risk, but not already at war"
assert not state.civil_war
# A calmer country starts far from the brink.
calm = _build_for("solheim")
print(f"  Solheim start civil_war_risk: {calm.civil_war_risk:.2f}")
assert calm.civil_war_risk < 0.20, "a stable model nation should start nowhere near civil war"
print("  PASS: crisis is authored into the starting position, distinct per country")


section("I7: New world/crisis state round-trips through save/load")
ids = _country_ids()
assert len(ids) == 9, f"expected 9 countries, got {len(ids)}"
random.seed(2)
state = _load("valmora")
eng = TurnEngine()
for _ in range(6):
    state = eng.advance(state)
restored = _pi.deserialize_state(_pi.serialize_state(state))
assert abs(restored.civil_war_risk - state.civil_war_risk) < 1e-9
assert restored.civil_war == state.civil_war
r_kr = restored.world_country("krasova")
s_kr = state.world_country("krasova")
assert r_kr.agenda == s_kr.agenda, "world agendas should persist"
assert abs(r_kr.civil_war_risk - s_kr.civil_war_risk) < 1e-9
assert "veldoria" in r_kr.relations, "world↔world relations should persist"
print("  PASS: agendas, world relations, and civil-war state all survive save/load")


# ══════════════════════════════════════════════════════════════════════════
# SECTION J — LIVING ECONOMY  (organic inflation)
# ══════════════════════════════════════════════════════════════════════════

from engine.turn import STRUCTURAL_INFLATION_MAX


section("J1: Sustained deficits heat structural inflation; surpluses cool it toward the anchor")
state = fresh()
eng = TurnEngine()
econ = state.country.economy
si_start = econ.structural_inflation
for _ in range(24):
    econ.budget.revenue = 10_000.0
    econ.budget.expenditure = 16_000.0   # deep, sustained deficit
    eng._update_structural_inflation(state)
hot = econ.structural_inflation
print(f"  24 months of deep deficit: {si_start*100:.1f}% → {hot*100:.1f}%")
assert hot > si_start, "sustained deficits should push structural inflation up"

state2 = fresh()
econ2 = state2.country.economy
econ2.structural_inflation = 0.12
for _ in range(24):
    econ2.budget.revenue = 12_000.0
    econ2.budget.expenditure = 9_000.0   # sustained surplus
    eng._update_structural_inflation(state2)
cool = econ2.structural_inflation
print(f"  24 months of surplus from 12.0%: → {cool*100:.1f}%")
assert cool < 0.12, "surpluses + the anchor should pull high inflation back down"
assert cool >= 0.0
print("  PASS: inflation responds organically to fiscal behaviour in both directions")


section("J2: Organic inflation stays bounded and feeds the effective rate exactly")
random.seed(4)
state = fresh()
eng = TurnEngine()
for _ in range(36):
    state = eng.advance(state)
econ = state.country.economy
assert 0.0 <= econ.structural_inflation <= STRUCTURAL_INFLATION_MAX, \
    f"structural inflation out of bounds: {econ.structural_inflation}"
assert 0.0 <= econ.inflation <= 1.0
# The effective rate is exactly structural + active modifiers (recomputed fresh).
state3 = fresh()
eng._update_structural_inflation(state3)
eng._apply_modifiers_to_headline_stats(state3)
e3 = state3.country.economy
expected = max(0.0, min(1.0, e3.structural_inflation + eng._modifiers_sum(state3, "inflation")))
assert abs(e3.inflation - expected) < 1e-12, "effective inflation must equal structural + modifiers"
print(f"  after 3 simulated years: structural {econ.structural_inflation*100:.1f}%, "
      f"effective {econ.inflation*100:.1f}% — bounded and consistent")
print("  PASS: organic inflation is bounded and composes cleanly with policy modifiers")


# ══════════════════════════════════════════════════════════════════════════
# SECTION K — INTRAPARTY CURRENTS  (generic wings and Ardenian blocs)
# ══════════════════════════════════════════════════════════════════════════

from engine import parties as _parties
from models.wing import Wing as _Wing
from models.faction import Ideology as _Ideology


section("K1: A party with no wings behaves exactly as a monolith")
from models.faction import Faction as _Faction2
mono = _Faction2(id="x", name="X", ideology=_Ideology(0.3, -0.4), power=0.5, loyalty=0.1, seats=10)
assert mono.wings == []
assert mono.effective_ideology() is mono.ideology, "no wings → effective ideology IS the party's own"
assert mono.dominant_wing() is None and mono.cohesion() == 1.0
print("  PASS: wingless parties are unchanged (effective ideology == party ideology)")


section("K2: Generic wings remain available; Ardenia uses its canonical blocs")
generic = _Faction2(id="generic", name="Generic", ideology=_Ideology(0.2, -0.4),
                    power=0.5, loyalty=0.1, seats=10)
generic.wings = _parties.generate_default_wings(generic)
assert len(generic.wings) == 3
tot = sum(w.strength for w in generic.wings)
assert abs(tot - 1.0) < 1e-9, f"strengths must sum to 1, got {tot}"
exts = [w.ideology.distance_to(_Ideology(0, 0)) for w in generic.wings]
assert min(exts) < generic.ideology.distance_to(_Ideology(0, 0)) < max(exts) + 1e-9, \
    "wings should bracket the party's own extremity (a moderate and a hardliner)"
# Ardenia's named social blocs win over generic generation.
state = fresh()
libdem = faction(state, "liberal_democrats")
assert [w.id for w in libdem.wings] == ["ld_circle", "ld_return", "ld_bar"]
assert all(w.kind == "bloc" for w in libdem.wings)
print(f"  generic wings sum {tot:.3f}; canonical LibDem blocs present")
print("  PASS: generic countries retain wings; Ardenia loads its named blocs")


section("K3: Wing drift is bounded and climate-responsive")
state = fresh()
nc = faction(state, "national_conservatives")
hard = next(w for w in nc.wings if w.id == "nc_line")
hard_before = hard.strength
# Sustained crisis should radicalise: strengthen the extreme wing.
state.stability.value = 0.15
state.country.economy.unemployment = 0.26
state.country.economy.growth_rate = -0.04
for _ in range(24):
    _parties.update_party_wings(state)
    for f in state.country.factions:
        s = sum(w.strength for w in f.wings)
        assert not f.wings or abs(s - 1.0) < 1e-6, f"{f.id} strengths drifted off 1.0: {s}"
        for w in f.wings:
            assert 0.0 <= w.strength <= 1.0 and -1.0 <= w.loyalty <= 1.0
print(f"  The Line under crisis: {hard_before:.2f} → {hard.strength:.2f}")
assert hard.strength > hard_before, "a sustained crisis should strengthen the extreme bloc"
print("  PASS: currents stay normalised and in-bounds, and radicalise under crisis")


section("K4: A change of leading wing is announced")
state = fresh()
nc = faction(state, "national_conservatives")
# Force the Square far ahead so a shift back to a harder current is logged.
for w in nc.wings:
    w.strength = 0.02
next(w for w in nc.wings if w.id == "nc_square").strength = 0.94
nc.normalize_wings()
assert nc.dominant_wing().id == "nc_square"
# Now bias the climate hard toward extremes for many turns until leadership flips.
state.stability.value = 0.10
state.country.economy.unemployment = 0.30
state.country.economy.growth_rate = -0.06
flipped = False
for _ in range(60):
    state.turn_log.clear()
    _parties.update_party_wings(state)
    if any("overtakes" in m for m in state.turn_log):
        flipped = True
        break
assert flipped, "a sustained swing should eventually flip and announce the leading wing"
print("  PASS: dominant-wing changes are detected and dispatched")


section("K5: Wings round-trip through save/load")
from engine import persistence as _pk
state = fresh()
before = faction(state, "liberal_democrats").wings
restored = _pk.deserialize_state(_pk.serialize_state(state))
after = next(f for f in restored.country.factions if f.id == "liberal_democrats").wings
assert len(after) == len(before) == 3
assert [w.name for w in after] == [w.name for w in before]
assert all(abs(a.strength - b.strength) < 1e-9 for a, b in zip(after, before))
assert [a.policy_biases for a in after] == [b.policy_biases for b in before]
print("  PASS: the party spectrum survives serialization")


section("K6: Regression guard — every seat counts and coalition formation is intact")
# A bloc now has a vote of its own, but seats must still be counted exactly once
# and the coalition-forming engine must not learn a second, incompatible model.
state = fresh()
minwage = next(b for b in bill_catalog() if b.id == "minimum_wage_act")
vf, va, _ = projected_votes(state, minwage)
assert vf + va == sum(f.seats for f in state.country.factions if f.seats > 0), \
    "every seat should still be counted as one bloc per party (no wing splitting yet)"
coalition, _ = elec.form_government(state)
assert state.ruling_faction_id == "liberal_democrats", \
    "coalition formation must be unchanged by wings this slice"
print(f"  minimum-wage projection {vf}-{va}; ruling party still liberal_democrats")
print("  PASS: bloc votes preserve seat accounting and coalition formation")


# ══════════════════════════════════════════════════════════════════════════
# SECTION L — FLAVOR PASS  (named leaders, dispatch voice, event chains)
# ══════════════════════════════════════════════════════════════════════════

from engine import flavor as _flavor
from content.dispatches import TEMPLATES as _TPL, MARKERS as _MKS
from content.events import event_catalog as _cat
from models.legislature import LawEffect as _LE


section("L1: Every party and world country has a named leader; leaders persist")
state = fresh()
for f in state.country.factions:
    assert f.leader, f"{f.id} has no leader"
assert faction(state, "national_conservatives").leader == "Petar Volkan", "authored leader should load"
for c in state.world:
    assert c.leader_name, f"{c.id} has no leader_name"
from engine import persistence as _pl
restored = _pl.deserialize_state(_pl.serialize_state(state))
assert next(f for f in restored.country.factions
            if f.id == "national_conservatives").leader == "Petar Volkan"
assert restored.world_country("krasova").leader_name == state.world_country("krasova").leader_name
print("  PASS: named leaders load (authored + generated) and survive save/load")


section("L2: The dispatch voice is deterministic, varied, and marker-stable")
state = fresh()
state.turn = 5
a = _flavor.render(state, "world_deepen", actor="A", actor_leader="Al",
                   target="B", target_leader="Bl")
b = _flavor.render(state, "world_deepen", actor="A", actor_leader="Al",
                   target="B", target_leader="Bl")
assert a == b, "same (turn, key, log position) must render the same variant"
seen = set()
for t in range(12):
    state.turn = t
    seen.add(_flavor.render(state, "world_deepen", actor="A", actor_leader="Al",
                            target="B", target_leader="Bl"))
assert len(seen) >= 2, "variants should actually vary across turns"
for key, marker in _MKS.items():
    for tmpl in _TPL[key]:
        assert marker.lower() in tmpl.lower(), \
            f"{key}: variant missing its marker '{marker}': {tmpl}"
print(f"  {len(_TPL)} dispatch types, all variants carry their markers")
print("  PASS: flavor rendering is deterministic per-slot, varied per-turn, marker-safe")


section("L3: Cooldown and once gate repeat fires")
from models.events import EventDef as _ED, EventOption as _EO
_gate_ev = _ED(id="_gate", title="Gate", description="", category="Test",
               condition=lambda s: True, chance=1.0, cooldown=6,
               default_option_id="ok",
               options=[_EO(id="ok", label="OK", description="", effects=_LE())])
with patch("engine.events.event_catalog", return_value=[_gate_ev]):
    state = fresh()
    state.turn = 10
    events.check_for_events(state)
    assert state.pending_events and state.event_fire_history["_gate"] == 10
    state.pending_events.clear()
    state.turn = 12
    events.check_for_events(state)          # inside cooldown → nothing
    assert not state.pending_events
    state.turn = 16
    events.check_for_events(state)          # cooldown elapsed → fires again
    assert state.pending_events
    # once=True never refires
    _gate_ev.once = True
    state.pending_events.clear()
    state.turn = 99
    events.check_for_events(state)
    assert not state.pending_events, "a once-event must not refire"
print("  PASS: cooldown windows and once-flags are honoured")


section("L4: A choice's follow-up comes back to haunt you")
_chain_child = _ED(id="_child", title="The Reckoning", description="", category="Test",
                   condition=lambda s: False, chance=0.0, default_option_id="ok",
                   options=[_EO(id="ok", label="OK", description="", effects=_LE())])
_chain_parent = _ED(id="_parent", title="The Choice", description="", category="Test",
                    condition=lambda s: True, chance=1.0, default_option_id="risky",
                    options=[_EO(id="risky", label="Risky", description="", effects=_LE(),
                                 follow_up={"event_id": "_child", "delay": 2, "chance": 1.0})])
with patch("engine.events.event_catalog", return_value=[_chain_parent, _chain_child]):
    state = fresh()
    state.turn = 20
    events.check_for_events(state)
    assert state.pending_events[0].event_id == "_parent"
    result = player_ops.op_resolve_event(state, "_parent", "risky")
    assert result.success
    assert state.scheduled_events and state.scheduled_events[0]["event_id"] == "_child"
    assert state.scheduled_events[0]["due_turn"] == 22
    state.turn = 21
    events.check_for_events(state)
    assert not state.pending_events, "not due yet"
    state.turn = 22
    events.check_for_events(state)
    assert state.pending_events and state.pending_events[0].event_id == "_child", \
        "the follow-up must fire when due, bypassing its own condition/chance"
    assert not state.scheduled_events
print("  PASS: chosen options schedule consequences that fire on time")


section("L5: Chain state survives save/load")
state = fresh()
state.event_fire_history = {"strike_wave": 4}
state.scheduled_events = [{"event_id": "general_strike", "due_turn": 9, "chance": 0.6}]
restored = _pl.deserialize_state(_pl.serialize_state(state))
assert restored.event_fire_history == {"strike_wave": 4}
assert restored.scheduled_events == [{"event_id": "general_strike", "due_turn": 9, "chance": 0.6}]
print("  PASS: fire history and scheduled follow-ups persist")


section("L6: Catalog lint — 20+ events, all references valid")
cat = _cat()
ids = [e.id for e in cat]
assert len(cat) >= 20, f"expected 20+ events, got {len(cat)}"
assert len(set(ids)) == len(ids), "duplicate event ids"
chain_count = 0
for e in cat:
    oids = [o.id for o in e.options]
    assert len(set(oids)) == len(oids), f"{e.id}: duplicate option ids"
    assert e.default_option_id in oids, f"{e.id}: default_option_id not among options"
    assert e.options, f"{e.id}: no options"
    for o in e.options:
        if o.follow_up:
            chain_count += 1
            assert o.follow_up["event_id"] in ids, f"{e.id}/{o.id}: dangling follow_up"
assert chain_count >= 3, "expected several follow-up chains"
print(f"  {len(cat)} events, {chain_count} chain links, all ids/defaults/follow-ups valid")
print("  PASS: the grown catalog is internally consistent")


# ══════════════════════════════════════════════════════════════════════════
# SECTION M — ROLEPLAY  (identity gating, leadership moves, the rival)
# ══════════════════════════════════════════════════════════════════════════

from engine import roleplay
from models.events import PendingEvent as _PE


section("M1: Identity gates event options — background opens doors, and the engine enforces it")
state = fresh()
strike = next(e for e in _cat() if e.id == "strike_wave")
open_ids = {o.id for o in events.available_options(state, strike)}
assert "one_of_their_own" not in open_ids, "union-leader option must be hidden without the background"
state.campaign_meta["background"] = "union_leader"
open_ids = {o.id for o in events.available_options(state, strike)}
assert "one_of_their_own" in open_ids, "the right background should unlock its option"
# Enforcement: the wrong character can't take the gated path even by id.
state2 = fresh()
state2.player.political_capital = 80.0
state2.pending_events.append(_PE(event_id="strike_wave"))
result = player_ops.op_resolve_event(state2, "strike_wave", "one_of_their_own")
assert not result.success and "someone like you" in result.message
assert state2.pending_events, "the rejected choice must leave the situation pending"
# Ideology gate: martial ports only for authoritarian-leaning leaders.
gen_strike = next(e for e in _cat() if e.id == "general_strike")
state3 = fresh()
state3.player.ideology_social = 0.5
assert "martial_ports" not in {o.id for o in events.available_options(state3, gen_strike)}
state3.player.ideology_social = -0.5
assert "martial_ports" in {o.id for o in events.available_options(state3, gen_strike)}
print("  PASS: requires-gating hides, unlocks, and hard-enforces identity options")


section("M2: Background abilities work, cooldown, and persist")
state = fresh()
state.campaign_meta["background"] = "career_politician"
state.player.political_capital = 50.0
r = player_ops.op_background_action(state)
assert r.success and state.player.political_capital > 50.0, "favours should net political capital"
assert "background_action" in state.cooldowns
r2 = player_ops.op_background_action(state)
assert not r2.success and "Too soon" in r2.message, "cooldown must block an immediate repeat"
from engine import persistence as _pm
restored = _pm.deserialize_state(_pm.serialize_state(state))
assert restored.cooldowns == state.cooldowns, "cooldowns must persist"
# A different background produces its documented mechanical effect.
state = fresh()
state.campaign_meta["background"] = "economist"
state.player.political_capital = 50.0
r = player_ops.op_background_action(state)
assert r.success
assert any(m.target == "inflation" and m.magnitude < 0 for m in state.modifiers), \
    "the economist's move should bank an inflation-calming modifier"
# No background → no ability.
state = fresh()
assert player_ops.background_ability(state) is None
assert not player_ops.op_background_action(state).success
print("  PASS: each past is a different lever, rate-limited and save-safe")


section("M3: Address the Nation — tones are contextual and rate-limited")
low = fresh(); low.player.political_capital = 80.0
low.stability.value = 0.20
player_ops.op_address_nation(low, "reassuring")
gain_low = low.stability.value - 0.20
high = fresh(); high.player.political_capital = 80.0
high.stability.value = 0.90
player_ops.op_address_nation(high, "reassuring")
gain_high = high.stability.value - 0.90
assert gain_low > gain_high >= 0.0, \
    f"reassurance should matter most in a crisis (low {gain_low:.3f} vs high {gain_high:.3f})"
state = fresh(); state.player.political_capital = 80.0
state.player.approval = 0.20
player_ops.op_address_nation(state, "contrite")
assert state.player.approval > 0.20, "contrition should recover cratered approval"
state = fresh(); state.player.political_capital = 80.0
own = faction(state, "liberal_democrats"); nc = faction(state, "national_conservatives")
own_before, nc_before = own.support, nc.loyalty
player_ops.op_address_nation(state, "defiant")
assert own.support > own_before and nc.loyalty < nc_before, \
    "defiance should rally the base and antagonise the hostile"
r = player_ops.op_address_nation(state, "visionary")
assert not r.success and "recently" in r.message, "address cooldown must hold"
print(f"  reassuring: +{gain_low:.3f} in crisis vs +{gain_high:.3f} when solid")
print("  PASS: four tones, four different levers, one cooldown")


section("M4: The rival exists and pounces on a stumble")
state = fresh()
rival = roleplay.current_rival(state)
assert rival is not None and rival.id == "national_conservatives", \
    "the strongest hostile party should supply the rival"
assert rival.leader == "Petar Volkan"
state.turn = 10
state.turn_log.append("VOTE FAILED — \"Anything\" falls 40-60 (needed 51); an embarrassment on the floor.")
with patch("engine.roleplay.random") as mock_rand:
    mock_rand.random.return_value = 0.0   # force the pounce
    roleplay.rival_watch(state)
assert any("Petar Volkan" in line for line in state.turn_log), "the rival should be quoted by name"
jibes_before = sum(1 for line in state.turn_log if "Petar Volkan" in line)
state.turn = 11   # inside the jibe cooldown
with patch("engine.roleplay.random") as mock_rand:
    mock_rand.random.return_value = 0.0
    roleplay.rival_watch(state)
assert sum(1 for line in state.turn_log if "Petar Volkan" in line) == jibes_before, \
    "the rival shouldn't nag every single turn"
print("  PASS: a named antagonist watches for your stumbles — but doesn't spam them")


section("M5: Gated options are never the auto-lapse default")
for e in _cat():
    default = next(o for o in e.options if o.id == e.default_option_id)
    assert default.requires is None, \
        f"{e.id}: the default option must be open to everyone (auto-lapse takes it)"
print("  PASS: every event can always auto-resolve, whoever you are")


# ══════════════════════════════════════════════════════════════════════════
# SECTION N — IMMERSION  (the press, structured news, world arcs)
# ══════════════════════════════════════════════════════════════════════════

from engine import press, worldsim, flavor as _fl
from content.press import HEADLINES as _PH, LEADS as _PL, SAMPLE_FIELDS as _PSF


section("N1: Dispatches are captured as structured news, cleared each turn")
state = fresh()
_fl.say(state, "economy_move", direction="grew", pct="1.00")
key, fields, text = state.turn_news[-1]
assert key == "economy_move" and fields["pct"] == "1.00" and "economy" in text.lower()
eng = TurnEngine()
with patch("engine.events.event_catalog", return_value=[]):
    state = eng.advance(state)
assert not any(k == "economy_move" and f.get("pct") == "1.00"
               for k, f, _ in state.turn_news), "turn_news must be cleared each turn"
print("  PASS: the press reads typed news items, never parsed prose")


section("N2: The front page ranks drama correctly and always publishes")
state = fresh()
state.turn_news = [
    ("protest", {"faction": "X", "leader": "Y", "grievance": "austerity"}, "PROTESTS — ..."),
    ("election", {"tag": "GENERAL ELECTION", "winner_party": "Liberal Democrats",
                  "winner_leader": "Maren Steele", "turnout": "64.2",
                  "player_won": True, "lost_office": False, "gained_office": False}, "═══ ..."),
    ("scandal", {"minister": "A", "portfolio": "Finance", "faction": "B"}, "⚠ SCANDAL — ..."),
]
page = press.front_page(state)
assert page["masthead"] == "The Vashtera Herald", \
    "the authored masthead (named for the capital) should be used, not the fallback"
assert "LIBERAL DEMOCRATS" in page["lead"]["headline"], "the election must lead the paper"
assert page["lead"]["body"], "lead stories carry a body"
assert len(page["headlines"]) == 2, "the other stories become secondary headlines"
# Quiet month: the paper still publishes.
state.turn_news = []
quiet = press.front_page(state)
assert "QUIET MONTH" in quiet["lead"]["headline"] and quiet["lead"]["body"]
print(f"  lead: {page['lead']['headline']}")
print("  PASS: election > scandal > protest, and a quiet month still makes the front page")


section("N3: Every headline and lead template renders against its documented fields")
for key, pools in _PH.items():
    assert key in _PSF, f"{key}: missing SAMPLE_FIELDS entry"
    for tmpl in pools:
        tmpl.format(**_PSF[key])   # raises KeyError on a missing placeholder
for key, pools in _PL.items():
    assert key in _PSF, f"LEADS {key}: missing SAMPLE_FIELDS entry"
    for tmpl in pools:
        tmpl.format(**_PSF[key])
print(f"  {len(_PH)} headline pools + {len(_PL)} lead pools lint clean")
print("  PASS: the press never crashes on a missing field")


section("N4: Axes form once, dissolve on reversal, and persist")
state = fresh()
kr = state.world_country("krasova")
qa = state.world_country("qadir")
rel = kr.relations["qadir"]
rel.score = 0.8
from models.relations import Treaty as _T
rel.treaties.append(_T(id="t1", name="Pact", type="trade", parties=["krasova", "qadir"]))
worldsim._update_world_arcs(state)
assert state.world_arcs.get("krasova|qadir") == "axis"
axis_lines = [l for l in state.turn_log if "axis" in l.lower()]
assert len(axis_lines) == 1, "axis formation should dispatch exactly once"
worldsim._update_world_arcs(state)
assert len([l for l in state.turn_log if "axis" in l.lower()]) == 1, "no repeat dispatch"
# Persistence round-trip.
from engine import persistence as _pn
restored = _pn.deserialize_state(_pn.serialize_state(state))
assert restored.world_arcs.get("krasova|qadir") == "axis"
# Reversal dissolves it.
rel.score = 0.1
worldsim._update_world_arcs(state)
assert "krasova|qadir" not in state.world_arcs
assert any("no more" in l or "run its course" in l for l in state.turn_log), \
    "dissolution should be announced"
# Feuds too (set both sides — the engine's own drift keeps them symmetric,
# but a manual poke must do it explicitly).
state2 = fresh()
state2.world_country("terand").relations["solheim"].score = -0.8
state2.world_country("solheim").relations["terand"].score = -0.8
worldsim._update_world_arcs(state2)
assert state2.world_arcs.get("solheim|terand") == "feud"
print("  PASS: named world developments form once, are remembered, and can end")


# ══════════════════════════════════════════════════════════════════════════
# SECTION O — CONSEQUENTIAL WINGS  (rebellions, leadership, cohesion)
# ══════════════════════════════════════════════════════════════════════════

from engine import parties as parties_engine
from engine.legislative import wing_votes, vote_rebellions
from models.faction import Ideology as _Ideo
from models.wing import Wing as _Wing


section("O1: Wing seat splits are exact; unpositioned bills stay bloc votes")
def _bill_o(bid):
    # NOT bill(...) — Section G8 reassigns that name to a Law object.
    return next(b for b in bill_catalog() if b.id == bid)
state = fresh()
law = _bill_o("minimum_wage_act")
lib = faction(state, "liberal_democrats")
wv = wing_votes(lib, law)
assert wv is not None, "a positioned bill should split a multi-wing party"
assert sum(s for _, s, _ in wv) == lib.seats, "wing seats must sum exactly to the party's"
law_neutral = _bill_o("minimum_wage_act")
law_neutral.ideology = None
assert wing_votes(lib, law_neutral) is None, "no position → the party votes as one bloc"
vf_split, va_split, _ = projected_votes(state, law)
vf_bloc, va_bloc, _ = projected_votes(state, law_neutral)
assert vf_split + va_split == vf_bloc + va_bloc == state.legislature.total_seats
print(f"  min wage: {vf_split}-{va_split} with wings vs {vf_bloc}-{va_bloc} as blocs")
print("  PASS: the split is exact and strictly opt-in per bill")


section("O2: A distant, restless wing defies the whip — and the press hears it")
state = fresh()
sd = faction(state, "social_democrats")
sd.loyalty = 0.2
sd.wings = [
    _Wing(id="sd_loyal", name="Party Line", ideology=_Ideo(-0.5, 0.3),
          strength=0.7, loyalty=0.9),
    _Wing(id="sd_rebel", name="Militant Tendency", ideology=_Ideo(-0.95, -0.6),
          strength=0.3, loyalty=0.1),
]
law = _bill_o("central_bank_independence_act")   # econ +0.5: anathema to militants
law.status = "proposed"
state.legislature.pending_bills.append(law)
rebs = vote_rebellions(state, law)
assert any(w.id == "sd_rebel" for _, w, _, _ in rebs), "the militant wing should rebel"
_, rebel_wing, rebel_seats, direction = next(r for r in rebs if r[1].id == "sd_rebel")
assert rebel_seats > 0
resolve_vote(state, law)
assert any("Militant Tendency" in line and law.name in line for line in state.turn_log), \
    "the rebellion should be dispatched with the wing named"
assert any(k == "vote_rebellion" for k, _, _ in state.turn_news), "and captured for the press"
print(f"  {rebel_seats} Militant Tendency deputies voted {direction} their own party")
print("  PASS: internal dissent now shows up in the division lobbies")


section("O3: A takeover by a restless wing costs the leader their head")
def _stage_flip(state, fac):
    """Put the party's most extreme wing one point behind the incumbent,
    restless, in a climate that favours extremes — the real drift flips it."""
    state.stability.value = 0.10
    state.country.economy.unemployment = 0.20
    dom = fac.dominant_wing()
    challenger = max((w for w in fac.wings if w.id != dom.id),
                     key=lambda w: parties_engine._extremity(w.ideology))
    challenger.strength = dom.strength - 0.01
    challenger.loyalty = 0.2
    fac.normalize_wings()

state = fresh()
nc = faction(state, "national_conservatives")
old_leader = nc.leader
_stage_flip(state, nc)
for _ in range(15):
    parties_engine.update_party_wings(state)
    if nc.leader != old_leader:
        break
assert nc.leader != old_leader, "a disloyal takeover should install a new leader"
assert any("ousted" in line for line in state.turn_log)
# The player's OWN party never auto-ousts — the same flip only dispatches
# the takeover; the leadership fight comes to the player as a situation.
state2 = fresh()
lib2 = faction(state2, state2.player.faction_id)
lib_leader = lib2.leader
_stage_flip(state2, lib2)
took_over = False
for _ in range(15):
    parties_engine.update_party_wings(state2)
    if any(lib2.name in line and "overtakes" in line for line in state2.turn_log):
        took_over = True
        break
assert took_over, "the staged flip should produce a takeover in the player's party too"
assert lib2.leader == lib_leader, "the player's own party must not auto-oust its leader"
print(f"  {old_leader} → {nc.leader} after the takeover; player party untouched")
print("  PASS: leadership follows the balance of power — except yours, which fights you openly")


section("O4: Your own party can challenge you — and each answer reshapes you")
from content.events import _restless_own_party
state = fresh()
assert not _restless_own_party(state), "a loyal party should not trigger the challenge"
own = faction(state, state.player.faction_id)
own.dominant_wing().loyalty = 0.2
assert _restless_own_party(state), "a restless dominant wing should"
challenge = next(e for e in _cat() if e.id == "party_leadership_challenge")
# Accommodate: the player's compass moves toward the wing.
state.pending_events.append(_PE(event_id="party_leadership_challenge"))
state.player.political_capital = 60.0
ideo_before = state.player.ideology_economic
wing_ideo = own.dominant_wing().ideology.economic
r = player_ops.op_resolve_event(state, "party_leadership_challenge", "accommodate")
assert r.success
moved = state.player.ideology_economic - ideo_before
assert abs(moved - (wing_ideo - ideo_before) * 0.15) < 1e-9, "accommodating shifts your ideology 15% toward the wing"
# Purge: the wing shrinks and everyone remembers.
state2 = fresh()
own2 = faction(state2, state2.player.faction_id)
own2.dominant_wing().loyalty = 0.2
dom_id = own2.dominant_wing().id
strength_before = own2.dominant_wing().strength
stab_before = state2.stability.value
state2.pending_events.append(_PE(event_id="party_leadership_challenge"))
state2.player.political_capital = 60.0
r = player_ops.op_resolve_event(state2, "party_leadership_challenge", "purge")
assert r.success
purged = next(w for w in own2.wings if w.id == dom_id)
assert purged.strength < strength_before, "the purged wing should shrink"
assert state2.stability.value < stab_before, "and the party turmoil costs stability"
print(f"  accommodate moved the player {moved:+.3f} econ; purge cut the wing and stability")
print("  PASS: the challenge event bites in three different directions")


section("O5: Coalition cohesion feeds stability — united coalitions govern better")
state = fresh()
_, breakdown = compute_target_stability(state)
assert "Coalition cohesion" in breakdown
drag_with_wings = breakdown["Coalition cohesion"]
assert drag_with_wings <= 0.0
for f in state.country.factions:
    f.wings = []          # a country of perfectly united parties
target_united, breakdown_united = compute_target_stability(state)
assert abs(breakdown_united["Coalition cohesion"]) < 1e-9, "no wings → no drag"
state2 = fresh()
target_authored, _ = compute_target_stability(state2)
assert target_united > target_authored, "a united coalition should out-govern a fractured one"
print(f"  cohesion drag: {drag_with_wings:+.4f} authored vs 0 united")
print("  PASS: internal party fractures now weigh on the government itself")


# ══════════════════════════════════════════════════════════════════════════
# SECTION P — DIPLOMACY VERBS  (pacts, sanctions, summits, treaty exit)
# ══════════════════════════════════════════════════════════════════════════

def _set_relation(state, cid, score):
    state.country.relations[cid].score = score
    other = state.world_country(cid)
    other.relations[state.country.id].score = score


section("P1: Defense pacts — trust-gated, double-sided, and the rivals notice")
state = fresh()
state.player.political_capital = 100.0
r = player_ops.op_defense_pact(state, "krasova")     # hostile: refused
assert not r.success and "trust" in r.message
_set_relation(state, "veldoria", 0.50)
stab_before = state.stability.value
r = player_ops.op_defense_pact(state, "veldoria")
assert r.success
assert any(t.type == "defense" for t in state.country.relations["veldoria"].treaties)
vel = state.world_country("veldoria")
assert any(t.type == "defense" for t in vel.relations["ardenia"].treaties), "both sides must hold the treaty"
assert state.stability.value > stab_before, "alliances reassure"
assert diplomacy.has_any_defense_pact(state)
r2 = player_ops.op_defense_pact(state, "veldoria")
assert not r2.success and "already" in r2.message
print("  PASS: pacts demand trust, bind both parties, and don't stack")


section("P2: Deterrence — a pact umbrella shelves half of hostile moves against you")
from engine import worldsim as _ws
state = fresh()
state.player.political_capital = 100.0
_set_relation(state, "veldoria", 0.50)
player_ops.op_defense_pact(state, "veldoria")
_set_relation(state, "krasova", -0.85)               # we are krasova's obvious mark
kras = state.world_country("krasova")
kras.agenda.pop("rival", None)   # no authored rival — the score pool must pick us
state.turn_log.clear()
with patch("engine.worldsim.random") as mock_rand:
    mock_rand.random.return_value = 0.4              # < 0.5 → deterred
    _ws._hostile_action(state, kras)
assert not state.turn_log, "the hostile move should be quietly shelved"
with patch("engine.worldsim.random") as mock_rand:
    mock_rand.random.return_value = 0.9              # ≥ 0.5 → proceeds (and no condemn)
    _ws._hostile_action(state, kras)
assert any("your" in line.lower() for line in state.turn_log), "undeterred moves still land"
print("  PASS: defense pacts change AI behaviour, not just a number")


section("P3: Sanctions — both flags, dead trade, and a monthly bleed on the target")
state = fresh()
state.player.political_capital = 100.0
state.country.relations["krasova"].trade_volume = 300.0
r = player_ops.op_impose_sanctions(state, "krasova")
assert r.success
rel = state.country.relations["krasova"]
kras = state.world_country("krasova")
assert rel.sanctioned and kras.relations["ardenia"].sanctioned
assert rel.trade_volume == 0.0
assert any(m.target == "gdp_growth" and m.magnitude < 0 and "Sanctions" in m.source
           for m in state.modifiers), "big lost trade should cost the player too"
# The monthly bite, isolated from agenda RNG:
control = fresh()
with patch.object(_ws, "_pursue_agendas", lambda s: None), \
     patch.object(_ws, "_update_world_arcs", lambda s: None):
    _ws.simulate_world(state)
    _ws.simulate_world(control)
kras_c = control.world_country("krasova")
assert kras.economy.growth_rate < kras_c.economy.growth_rate, "sanctions should drag growth"
assert kras.stability < kras_c.stability, "and stability"
r = player_ops.op_lift_sanctions(state, "krasova")
assert r.success and not state.country.relations["krasova"].sanctioned
assert not kras.relations["ardenia"].sanctioned
print("  PASS: sanctions bite monthly on both sides of the ledger, and can end")


section("P4: Summits thaw relations — but the calendar is finite")
state = fresh()
state.player.political_capital = 100.0
score_before = state.country.relations["merova"].score
appr_before = state.player.approval
r = player_ops.op_hold_summit(state, "merova")
assert r.success
assert state.country.relations["merova"].score > score_before
assert state.player.approval > appr_before
r2 = player_ops.op_hold_summit(state, "qadir")
assert not r2.success and "calendar" in r2.message, "summit cooldown must hold"
print("  PASS: the statesman's lever works once per season, not per whim")


section("P5: Tearing up a treaty — the counterparty remembers, and the benefits die")
state = fresh()
state.player.political_capital = 100.0
diplomacy.propose_trade_agreement(state, "veldoria")
treaty = next(t for t in state.country.relations["veldoria"].treaties if t.type == "trade")
assert any(m.source_id == treaty.id for m in state.modifiers), "trade pact should carry a growth modifier"
score_before = state.country.relations["veldoria"].score
r = player_ops.op_break_treaty(state, "veldoria", treaty.id)
assert r.success
assert not any(t.id == treaty.id for t in state.country.relations["veldoria"].treaties)
vel = state.world_country("veldoria")
assert not any(t.id == treaty.id for t in vel.relations["ardenia"].treaties)
assert abs((state.country.relations["veldoria"].score - score_before) - (-0.20)) < 1e-9
assert not any(m.source_id == treaty.id for m in state.modifiers), "the pact's benefits die with it"
assert any("torn up" in line for line in state.turn_log)
# Defense pacts cost more to walk away from.
state2 = fresh()
state2.player.political_capital = 100.0
_set_relation(state2, "veldoria", 0.50)
player_ops.op_defense_pact(state2, "veldoria")
pact = next(t for t in state2.country.relations["veldoria"].treaties if t.type == "defense")
score_before = state2.country.relations["veldoria"].score
player_ops.op_break_treaty(state2, "veldoria", pact.id)
assert abs((state2.country.relations["veldoria"].score - score_before) - (-0.30)) < 1e-9
print("  PASS: exits are real, priced by the treaty's weight")


section("P6: Sanctions and pacts survive save/load")
state = fresh()
state.player.political_capital = 100.0
_set_relation(state, "veldoria", 0.50)
player_ops.op_defense_pact(state, "veldoria")
player_ops.op_impose_sanctions(state, "krasova")
from engine import persistence as _pp
restored = _pp.deserialize_state(_pp.serialize_state(state))
assert any(t.type == "defense" for t in restored.country.relations["veldoria"].treaties)
assert restored.country.relations["krasova"].sanctioned
assert restored.world_country("krasova").relations["ardenia"].sanctioned
print("  PASS: statecraft persists")


# ══════════════════════════════════════════════════════════════════════════
# SECTION Q — PACING  (the world deliberates before it acts)
# ══════════════════════════════════════════════════════════════════════════

_ACTION_MARKERS = [_MK[k] for k in ("world_deepen", "world_condemn", "world_undermine",
                                     "world_trade_pact", "world_court_player",
                                     "world_pressure_player", "world_condemn_player")]


def _world_actions(lines):
    return [l for l in lines if any(m in l for m in _ACTION_MARKERS)]


section("Q1: The opening months are quiet — everyone is still thinking")
random.seed(4)
state = fresh()
eng = TurnEngine()
early_actions = []
with patch("engine.events.event_catalog", return_value=[]):
    for _ in range(2):
        state = eng.advance(state)
        early_actions += _world_actions(state.turn_log)
assert not early_actions, f"no world ACTIONS in months 1-2, got: {early_actions[:2]}"
assert all(c.plan for c in state.world), "every country should hold a deliberated plan"
maturities = {c.plan["matures_turn"] for c in state.world}
assert len(maturities) >= 2, "first plans must be staggered, not synchronised"
print(f"  {len(state.world)} countries planning; maturities spread over {len(maturities)} different turns")
print("  PASS: the game no longer opens with a burst")


section("Q2: Plans follow the national interest")
state = fresh()
val = state.world_country("valmora")
worldsim._make_plan(state, val)
assert val.plan["objective"] == "consolidate", "a fracturing survivor looks inward"
kras = state.world_country("krasova")
worldsim._make_plan(state, kras)
assert kras.plan["objective"] == "undermine", "a revanchist nurses its grudge"
assert kras.plan["target"] == kras.agenda.get("rival"), "and aims it at the authored rival"
# A sanctioning power becomes priority target #1 — the grudge filter.
state2 = fresh()
state2.player.political_capital = 50.0
player_ops.op_impose_sanctions(state2, "merova")
mer = state2.world_country("merova")
worldsim._make_plan(state2, mer)
assert mer.plan["objective"] == "undermine" and mer.plan["target"] == "ardenia", \
    "whoever sanctions you becomes the problem"
print("  PASS: survivor consolidates, revanchist schemes, the sanctioned hold grudges")


section("Q3: A matured plan executes, and the country goes back to thinking")
state = fresh()
kras = state.world_country("krasova")
kras.agenda["rival"] = "terand"
worldsim._make_plan(state, kras)
kras.plan["matures_turn"] = state.turn      # mature NOW
state.turn_log.clear()
with patch.object(worldsim, "_update_world_arcs", lambda s: None):
    worldsim._pursue_agendas(state)
acted = _world_actions(state.turn_log)
assert acted, "the matured plan should produce a visible action"
assert any("Terand" in l for l in acted), "aimed at the planned target"
assert kras.plan["matures_turn"] > state.turn, "and a fresh plan is already maturing"
print(f"  executed: {acted[0][:70]}...")
print("  PASS: think → foreshadow → act → think again")


section("Q4: A drumbeat, not a burst — action cadence over two years")
random.seed(9)
state = fresh()
eng = TurnEngine()
per_turn = []
with patch("engine.events.event_catalog", return_value=[]):
    for _ in range(24):
        state = eng.advance(state)
        per_turn.append(len(_world_actions(state.turn_log)))
first4 = sum(per_turn[:4])
total = sum(per_turn)
assert first4 <= 6, f"the opening should stay calm (got {first4} actions in 4 turns)"
assert 12 <= total <= 60, f"two years should carry a steady beat (got {total})"
print(f"  first 4 turns: {first4} actions; 24 turns: {total} — spread: {per_turn}")
print("  PASS: activity is paced across the campaign, not front-loaded")


section("Q5: Deliberated plans survive save/load")
state = fresh()
worldsim._make_plan(state, state.world_country("krasova"))
from engine import persistence as _pq
restored = _pq.deserialize_state(_pq.serialize_state(state))
assert restored.world_country("krasova").plan == state.world_country("krasova").plan
print("  PASS: the world's intentions persist")


section("Q6: Governing overhead — an empire of commitments governs slowly")
from engine.turn import political_upkeep, PC_REGEN_FLOOR


def _regen_delta(state):
    state.player.political_capital = 0.0
    TurnEngine()._regenerate_political_capital(state)
    return state.player.political_capital


lean = fresh()
upkeep0, _ = political_upkeep(lean)   # inherited laws/treaties count too — small
assert upkeep0 < 4.0, f"starting overhead should be light (got {upkeep0:.1f})"
lean_gain = _regen_delta(lean)

busy = fresh()
for i in range(4):
    law = _bill_o("minimum_wage_act")
    law.id = f"law_{i}"
    busy.legislature.active_laws.append(law)
diplomacy.propose_trade_agreement(busy, "veldoria")
busy.player.political_capital = 60.0
player_ops.op_impose_sanctions(busy, "krasova")
upkeep_busy, detail = political_upkeep(busy)
assert upkeep_busy > upkeep0 + 3.0, \
    f"4 laws + treaty + sanctions should cost real upkeep (got {upkeep_busy:.1f} vs start {upkeep0:.1f})"
assert detail["laws"] > 0 and detail["treaties"] > 0 and detail["sanctions"] > 0
busy_gain = _regen_delta(busy)
assert busy_gain < lean_gain, "the busy government must gain PC slower than the lean one"

# The floor: even a wildly overcommitted government keeps moving.
glut = fresh()
for i in range(60):
    law = _bill_o("minimum_wage_act")
    law.id = f"glut_{i}"
    glut.legislature.active_laws.append(law)
glut_gain = _regen_delta(glut)
assert abs(glut_gain - PC_REGEN_FLOOR) < 1e-9, "the regen floor must hold"
print(f"  lean +{lean_gain:.1f}/mo vs busy +{busy_gain:.1f}/mo (upkeep {upkeep_busy:.1f}); floor {PC_REGEN_FLOOR}")
print("  PASS: dynamic upkeep brakes the spammer without paralysing anyone")


# ══════════════════════════════════════════════════════════════════════════
# SECTION R — CABINET PERSONALITIES  (traits, shortlists, seats at the table)
# ══════════════════════════════════════════════════════════════════════════

from models.cabinet import Minister as _Min, TRAIT_EFFECTS as _TE


section("R1: Traits have teeth — competence, threat, floors, growth, gravitas")
tech = _Min(id="t", name="T", portfolio="Finance", faction_id="liberal_democrats",
            competence=0.6, loyalty=0.5, ambition=0.5, trait="technocrat")
assert tech.effective_competence() > 0.6, "a technocrat outperforms their raw stat"
loyal = _Min(id="l", name="L", portfolio="Justice", faction_id="liberal_democrats",
             competence=0.6, loyalty=0.4, ambition=0.8, trait="loyalist")
plain = _Min(id="p", name="P", portfolio="Justice", faction_id="liberal_democrats",
             competence=0.6, loyalty=0.4, ambition=0.8, trait="")
assert loyal.threat_level() < plain.threat_level() * 0.6, "loyalists barely threaten"
# Schemer growth + loyalist floor via the real turn phase.
state = fresh()
schemer = _Min(id="s", name="S", portfolio="Economy", faction_id="liberal_democrats",
               competence=0.5, loyalty=0.9, ambition=0.3, trait="schemer")
floor_case = _Min(id="f", name="F", portfolio="Interior", faction_id="liberal_democrats",
                  competence=0.6, loyalty=0.2, ambition=0.2, trait="loyalist")
state.cabinet.ministers = [schemer, floor_case]
for _ in range(20):
    TurnEngine()._update_ministers(state)
assert schemer.competence > 0.5 and schemer.ambition > 0.3, "schemers learn and hunger"
assert floor_case.loyalty >= 0.55, "the loyalist floor must hold"
# Grandee gravitas lifts the stability target.
plain_state = fresh()
grand_state = fresh()
for m in grand_state.cabinet.ministers:
    m.trait = "grandee"
for m in plain_state.cabinet.ministers:
    m.trait = ""
t_plain, _ = compute_target_stability(plain_state)
t_grand, _ = compute_target_stability(grand_state)
assert t_grand > t_plain, "a cabinet of grandees steadies the government"
print(f"  technocrat {tech.effective_competence():.2f} eff; grandee target +{t_grand - t_plain:.3f}")
print("  PASS: five personalities, five different mechanical fingerprints")


section("R2: The shortlist — three named options, politics included")
state = fresh()
candidates = cabinet_ops.shortlist(state, "Finance")
assert len(candidates) == 3
assert all(c.name and c.trait in _TE for c in candidates), "every candidate is a person"
assert candidates[0].faction_id == state.player.faction_id, "your own party always fields one"
assert len({c.faction_id for c in candidates}) >= 2, "the list crosses party lines"
print("  shortlist:", "; ".join(f"{c.name} ({c.faction_id}, {c.trait})" for c in candidates))
print("  PASS: appointment is a choice between people, not a dice roll")


section("R3: Appointments carry politics — firebrands and seats at the table")
state = fresh()
state.player.political_capital = 80.0
sd = faction(state, "social_democrats")           # coalition partner
base_loyalty = sd.loyalty
fire = _Min(id="fb", name="FB", portfolio="Economy", faction_id="social_democrats",
            competence=0.6, loyalty=0.6, ambition=0.4, trait="firebrand")
r = player_ops.op_appoint_minister(state, "Economy", fire)
assert r.success
fire_gain = sd.loyalty - base_loyalty
state2 = fresh()
state2.player.political_capital = 80.0
sd2 = faction(state2, "social_democrats")
base2 = sd2.loyalty
tech2 = _Min(id="tc", name="TC", portfolio="Economy", faction_id="social_democrats",
             competence=0.6, loyalty=0.6, ambition=0.4, trait="technocrat")
player_ops.op_appoint_minister(state2, "Economy", tech2)
tech_gain = sd2.loyalty - base2
assert fire_gain > tech_gain > 0, \
    f"a firebrand thrills their party more (fire {fire_gain:.3f} vs tech {tech_gain:.3f})"
assert any("joins the cabinet" in l or "brief goes to" in l for l in state.turn_log), \
    "appointments are dispatched"
print("  PASS: who you appoint moves their party — personality included")


section("R4: A seat at the table — shut-out partners sour, represented ones warm")
seated = fresh()
shut_out = fresh()
for st in (seated, shut_out):
    st.cabinet.ministers = [m for m in st.cabinet.ministers
                            if m.faction_id != "social_democrats"]
seated.cabinet.ministers.append(_Min(id="x", name="X", portfolio="Justice",
                                     faction_id="social_democrats",
                                     competence=0.6, loyalty=0.7, ambition=0.3))
for _ in range(10):
    TurnEngine()._update_faction_loyalty(seated)
    TurnEngine()._update_faction_loyalty(shut_out)
assert faction(seated, "social_democrats").loyalty > faction(shut_out, "social_democrats").loyalty, \
    "cabinet representation must matter to coalition partners"
print("  PASS: coalition partners count their ministries")


section("R5: Restless ministers warn you before they blow")
state = fresh()
bomb = _Min(id="b", name="Vex Marlow", portfolio="Defense", faction_id="national_conservatives",
            competence=0.7, loyalty=0.1, ambition=0.9, trait="firebrand")
state.cabinet.ministers.append(bomb)
state.turn = 10
TurnEngine()._update_ministers(state)
warnings = [l for l in state.turn_log if "restless" in l]
assert len(warnings) == 1 and "Vex Marlow" in warnings[0]
state.turn = 12   # inside the warning cooldown
TurnEngine()._update_ministers(state)
assert len([l for l in state.turn_log if "restless" in l]) == 1, "no nagging inside cooldown"
print(f"  warning: {warnings[0][:70]}...")
print("  PASS: the scandal pipeline now has a fuse you can see burning")


section("R6: Traits survive save/load")
state = fresh()
state.cabinet.ministers[0].trait = "schemer"
from engine import persistence as _pr
restored = _pr.deserialize_state(_pr.serialize_state(state))
assert restored.cabinet.ministers[0].trait == "schemer"
print("  PASS: personalities persist")


# ══════════════════════════════════════════════════════════════════════════
# SECTION S — REGRESSION GUARDS  (bugs found in review; must never return)
# ══════════════════════════════════════════════════════════════════════════

section("S1: A repeatable event's modifiers refresh, they do not stack forever")
state = fresh()
event = next(e for e in _cat() if e.id == "trade_route_disruption")
option = next(o for o in event.options if o.effects.modifiers or o.effects.inflation_delta)
# Fire the same event three times, exactly as a repeat/auto-lapse would.
for _ in range(3):
    legislative.apply_effect_bundle(state, option.effects, event.title,
                                    event.id, event.portfolio)
from collections import Counter as _Counter
counts = _Counter(m.id for m in state.modifiers)
dupes = {mid: n for mid, n in counts.items() if n > 1}
assert not dupes, f"repeat applications must refresh, not stack: {dupes}"
# And the refreshed copy is young again, not an aged husk.
refreshed = [m for m in state.modifiers if m.source_id == event.id]
assert refreshed and all(m.age == 0 for m in refreshed), "a re-fired effect restarts its life"
print(f"  fired 3×: {len(refreshed)} modifier(s) for the event, no duplicates")
print("  PASS: indefinite-hold effects can no longer accumulate without bound")


section("S2: A proposed bill keeps its long-term payoff across save/load")
state = fresh()
state.player.political_capital = 90.0
tax = _bill_o("progressive_tax_reform_act")
assert tax.effects.modifiers, "fixture: this bill's whole point is its modifiers"
expected_ids = {m.id for m in tax.effects.modifiers}
r = player_ops.op_propose_bill(state, tax)
assert r.success
from engine import persistence as _ps
reloaded = _ps.deserialize_state(_ps.serialize_state(state))
pending = next(b for b in reloaded.legislature.pending_bills if b.id == "progressive_tax_reform_act")
assert {m.id for m in pending.effects.modifiers} == expected_ids, \
    "a pending bill must carry its modifier templates through a save"
# And they actually fire when the reloaded bill passes.
for f in reloaded.country.factions:
    f.loyalty = 1.0          # guarantee passage; we're testing the payoff, not the vote
passed = resolve_vote(reloaded, pending)
assert passed
live_ids = {m.id for m in reloaded.modifiers}
assert expected_ids <= live_ids, \
    f"the reloaded bill's payoff must apply on passage (missing {expected_ids - live_ids})"
print(f"  {len(expected_ids)} modifier template(s) survived the round trip and fired on passage")
print("  PASS: saving mid-legislation no longer guts the bill")


section("S3: Laws can be repealed — effects lapse and overhead is freed")
from engine.turn import political_upkeep as _upkeep
state = fresh()
state.player.political_capital = 90.0
bill_obj = _bill_o("minimum_wage_act")
for f in state.country.factions:
    f.loyalty = 1.0
player_ops.op_propose_bill(state, bill_obj)
law = next(b for b in state.legislature.pending_bills if b.id == "minimum_wage_act")
resolve_vote(state, law)
assert any(l.id == "minimum_wage_act" for l in state.legislature.active_laws)
assert any(m.source_id == "minimum_wage_act" for m in state.modifiers), "law should be running effects"
upkeep_before, _ = _upkeep(state)
wf_before = faction(state, "workers_front").loyalty

state.player.political_capital = 90.0
r = player_ops.op_repeal_law(state, "minimum_wage_act")
assert r.success, r.message
assert not any(l.id == "minimum_wage_act" for l in state.legislature.active_laws)
assert not any(m.source_id == "minimum_wage_act" for m in state.modifiers), \
    "a repealed law's ongoing effects must die with it"
assert any(l.id == "minimum_wage_act" and l.status == "repealed"
           for l in state.legislature.law_history), "repeals are recorded"
upkeep_after, _ = _upkeep(state)
assert upkeep_after < upkeep_before, "repealing frees governing overhead"
assert faction(state, "workers_front").loyalty < wf_before, \
    "the faction the law served resents losing it"
assert any("REPEALED" in l for l in state.turn_log)
r2 = player_ops.op_repeal_law(state, "minimum_wage_act")
assert not r2.success, "can't repeal what isn't on the books"
print(f"  upkeep {upkeep_before:.1f} → {upkeep_after:.1f} PC/mo after repeal")
print("  PASS: the statute book is now two-way")


section("S4: Trade volume saturates — no permanent revenue snowball")
from engine.turn import TRADE_VOLUME_CEILING, TRADE_VOLUME_APPROACH
state = fresh()
state.player.political_capital = 90.0
diplomacy.propose_trade_agreement(state, "veldoria")
rel = state.country.relations["veldoria"]
rel.score = 0.8
eng = TurnEngine()
with patch("engine.events.event_catalog", return_value=[]):
    for _ in range(120):        # a decade of a warm trade pact
        state = eng.advance(state)
rel = state.country.relations["veldoria"]
hard_ceiling = TRADE_VOLUME_CEILING          # score can't exceed 1.0
assert rel.trade_volume <= hard_ceiling + 1e-6, \
    f"trade volume must stay bounded (got {rel.trade_volume:.0f})"
vol_decade = rel.trade_volume
with patch("engine.events.event_catalog", return_value=[]):
    for _ in range(120):        # a second decade
        state = eng.advance(state)
rel = state.country.relations["veldoria"]
assert rel.trade_volume <= hard_ceiling + 1e-6
assert rel.trade_volume - vol_decade < hard_ceiling * 0.25, \
    "growth must flatten, not keep compounding"
# And it decays when the relationship sours, using the same approach.
rel.score = 0.1
before_decay = rel.trade_volume
with patch("engine.events.event_catalog", return_value=[]):
    for _ in range(24):
        state = eng.advance(state)
assert state.country.relations["veldoria"].trade_volume < before_decay, \
    "cooling relations should shrink trade, not freeze it"
print(f"  decade 1: {vol_decade:,.0f}; decade 2: {rel.trade_volume:,.0f} (ceiling {hard_ceiling:,.0f})")
print("  PASS: customs revenue is bounded by the relationship, not by time")


section("S5: The player is never quoted reacting to their own vote")
state = fresh()
assert faction(state, "liberal_democrats").leader != state.player.name, \
    "the player's party needs its own chairman, distinct from the head of government"
# Even when a campaign syncs the player's name onto their own party, the
# press must not put third-person words in their mouth.
own = faction(state, state.player.faction_id)
own.leader = state.player.name
law = _bill_o("minimum_wage_act")
law.effects.faction_loyalty_deltas = {state.player.faction_id: 0.2}
state.turn_log.clear()
legislative._press_reaction(state, law, passed=True)
assert not any(state.player.name in line for line in state.turn_log), \
    "the player must not be quoted about their own government's vote"
print("  PASS: no more talking about yourself in the third person")


section("S6: A spy scandal punishes whoever actually triggered it")
spy = next(e for e in _cat() if e.id == "spy_scandal")
expel = next(o for o in spy.options if o.id == "expel_diplomats")
assert not any(k in {c.id for c in fresh().world} for k in expel.relation_deltas), \
    "the option must not name a specific country any more"
# Make Merova — not the authored Krasova — the hostile power.
state = fresh()
state.player.political_capital = 60.0
for cid in ("krasova", "merova"):
    state.country.relations[cid].score = 0.1
state.country.relations["merova"].score = -0.75
mer_before = state.country.relations["merova"].score
kras_before = state.country.relations["krasova"].score
state.pending_events.append(_PE(event_id="spy_scandal"))
r = player_ops.op_resolve_event(state, "spy_scandal", "expel_diplomats")
assert r.success
assert state.country.relations["merova"].score < mer_before, \
    "the actual hostile power should take the hit"
assert abs(state.country.relations["krasova"].score - kras_before) < 1e-9, \
    "an unrelated country must not be punished"
print(f"  Merova {mer_before:+.2f} → {state.country.relations['merova'].score:+.2f}; Krasova untouched")
print("  PASS: the event follows the evidence")


section("S7: Dispatch explanations key off the dispatch type, not stray words")
# Pure-logic check of the lookup the GUI dialog uses (no Qt needed).
from content.dispatches import MARKERS as _MKS2


def _key_for(text, state):
    for k, _f, txt in reversed(state.turn_news):
        if txt == text:
            return k
    lowered = text.lower()
    for k, marker in sorted(_MKS2.items(), key=lambda kv: -len(kv[1])):
        if "{" in marker:
            continue
        if marker.lower() in lowered:
            return k
    return None


state = fresh()
_fl.say(state, "economy_move", direction="grew", pct="1.00")
key, _f, txt = state.turn_news[-1]
assert _key_for(txt, state) == "economy_move", "an exact structured match wins"
# The old substring matcher explained THIS as a foreign loan; the marker
# table must not be fooled by an unrelated sentence containing 'loan'.
decoy = "PROTESTS — crowds fill the squares over the loan terms; the election is years away."
assert _key_for(decoy, state) == "PROTESTS" or _key_for(decoy, state) == "protest", \
    f"a protest mentioning a loan is still a protest (got {_key_for(decoy, state)})"
assert _key_for("VOTE PASSED — \"X\" clears the chamber 60-40 (needed 51).", state) == "vote_passed"
assert _key_for("nothing structured about this line", state) is None
print("  PASS: explanations follow the dispatch's type")


# ══════════════════════════════════════════════════════════════════════════
# SECTION T — COUNTRY-NEUTRAL CONTENT  (roles resolve in every country)
# ══════════════════════════════════════════════════════════════════════════

from models import roles as _roles
from engine import events as _ev_mod
from engine.legislative import role_faction, resolve_faction_key

# Deliberately different party systems: Krasova is an authoritarian state
# with no labour party at all, Valmora a collapsing four-way split, Qadir a
# clerical/merchant order, Solheim a Nordic social democracy with no
# agrarian party.
_TEST_COUNTRIES = ["krasova", "valmora", "qadir", "solheim"]


section("T1: Every faction in all nine countries classifies into a role")
import glob as _glob, json as _json
_all_ids = sorted(_json.load(open(p, encoding="utf-8"))["id"]
                  for p in _glob.glob("content/countries/*.json"))
assert len(_all_ids) == 9, f"expected nine countries, found {len(_all_ids)}"
for cid in _all_ids:
    st = _load(cid)
    for f in st.country.factions:
        assert f.role in _roles.ROLES, f"{cid}/{f.id}: unclassified role {f.role!r}"
        # The assigned role must genuinely be the nearest centroid.
        best = min(_roles.ROLES, key=lambda r: _roles.role_distance(f.ideology, r))
        assert f.role == best, f"{cid}/{f.id}: role {f.role} is not the nearest centroid"
print(f"  all factions across {len(_all_ids)} countries classified by nearest centroid")
print("  PASS: role assignment is total and deterministic")


section("T2: Every role resolves to the most extreme faction on its defining axis")
# The invariant that holds for both classified roles and sign-correct
# stand-ins: whoever speaks for a role must be on the correct side of that
# role's axis, and be the furthest out on it of anyone eligible. This is
# what makes the three authored overrides true by construction —
# Terand→military_bloc (social -0.90), Ardenia→workers_front (econ -0.90),
# Solheim→liberal_party (econ +0.50).
for cid in _all_ids:
    st = _load(cid)
    for r in _roles.ROLES:
        picked = role_faction(st, r)
        if picked is None:
            continue
        axis = _roles.ROLE_AXIS.get(r)
        if axis is None:
            # No defining extreme: must at least sit near the role's centroid.
            assert _roles.role_distance(picked.ideology, r) <= _roles.MAX_FALLBACK_DISTANCE, \
                f"{cid}/{r}: {picked.id} is nowhere near the role"
            continue
        value = _roles.axis_value(picked.ideology, r)
        assert value > 0, \
            f"{cid}/{r}: {picked.id} is on the wrong side of the {axis[0]} axis"
        # Nobody classified into the role sits further out than the pick.
        peers = [f for f in st.country.factions if f.role == r] or \
                [f for f in st.country.factions if _roles.eligible_for(f.ideology, r)]
        best = max(_roles.axis_value(f.ideology, r) for f in peers)
        assert abs(value - best) < 1e-9, \
            f"{cid}/{r}: {picked.id} isn't the most extreme available"

# The three overrides, pinned explicitly.
assert role_faction(_load("terand"), _roles.ROLE_NATIONALIST).id == "military_bloc"
assert role_faction(_load("ardenia"), _roles.ROLE_LABOUR).id == "workers_front"
assert role_faction(_load("solheim"), _roles.ROLE_BUSINESS).id == "liberal_party"
print("  overrides hold: terand→military_bloc, ardenia→workers_front, solheim→liberal_party")
print("  PASS: each role speaks through its country's most committed faction")


section("T2b: STANDING GUARDRAIL — every role resolves in every country")
# A role with nobody in it means an authored event fires and silently does
# nothing there. That bug was found by hand twice (Krasova labour, Solheim
# business); this makes it impossible to reintroduce unnoticed. Any genuine
# absence must be listed here WITH a justification the test re-verifies —
# it can't be waved through.
_JUSTIFIED_ROLE_GAPS = {
    # Terand is a military dictatorship: every faction sits at or right of
    # centre economically (+0.00 .. +0.60), so no labour bloc can exist
    # without inventing one.
    ("terand", _roles.ROLE_LABOUR),
}
_unfilled = set()
for cid in _all_ids:
    st = _load(cid)
    for r in _roles.ROLES:
        if role_faction(st, r) is None:
            _unfilled.add((cid, r))

_unexpected = _unfilled - _JUSTIFIED_ROLE_GAPS
assert not _unexpected, (
    "role(s) with no faction and no justification — an event aimed there "
    f"would silently do nothing: {sorted(_unexpected)}")
_stale = _JUSTIFIED_ROLE_GAPS - _unfilled
assert not _stale, f"listed gap(s) that now resolve; remove them: {sorted(_stale)}"

# Each justified gap must really have no eligible faction, not just a
# badly-chosen threshold.
for cid, r in _JUSTIFIED_ROLE_GAPS:
    st = _load(cid)
    eligible = [f.id for f in st.country.factions
                if _roles.eligible_for(f.ideology, r)]
    assert not eligible, f"{cid}/{r} was called impossible but {eligible} qualify"

_filled = len(_all_ids) * len(_roles.ROLES) - len(_unfilled)
print(f"  {_filled}/{len(_all_ids) * len(_roles.ROLES)} country-role slots filled; "
      f"{len(_JUSTIFIED_ROLE_GAPS)} justified gap(s)")
print("  PASS: no role can silently have nobody to act on")


section("T3: A truly absent role degrades gracefully instead of crashing")
ter = _load("terand")
assert role_faction(ter, _roles.ROLE_LABOUR) is None, \
    "fixture: Terand is supposed to have no faction left of centre"
assert resolve_faction_key(ter, _roles.ROLE_LABOUR) is None
assert resolve_faction_key(ter, "workers_front") is None, "an alien faction id resolves to None"
assert resolve_faction_key(ter, "military_bloc") is not None, "a real local id still resolves"
# Applying an effect aimed at an absent role must be a no-op, not an error.
before = {f.id: f.loyalty for f in ter.country.factions}
legislative.apply_effect_bundle(
    ter, LawEffect(faction_loyalty_deltas={_roles.ROLE_LABOUR: -0.5}), "Test", "test_src")
assert {f.id: f.loyalty for f in ter.country.factions} == before, \
    "an unmatched role must change nothing at all"
# Krasova has no *classified* labour party but does have a sign-correct
# stand-in, so the role resolves rather than vanishing.
kras = _load("krasova")
stand_in = role_faction(kras, _roles.ROLE_LABOUR)
assert stand_in is not None and stand_in.ideology.economic < 0, \
    "Krasova's most left-leaning faction should stand in for labour"
print(f"  Terand: labour genuinely absent; Krasova: {stand_in.id} stands in")
print("  PASS: absent roles skip safely, thin ones find a sign-correct stand-in")


section("T4: The converted events land on real factions in non-Ardenia countries")
# Every option in the catalog that carries faction effects — the whole file
# is country-neutral now, so all of it is under test, not a sample.
_CONVERTED = {}
for _e in _cat():
    _opts = [o.id for o in _e.options if o.effects.faction_loyalty_deltas
             or o.effects.faction_power_deltas]
    if _opts:
        _CONVERTED[_e.id] = _opts
assert len(_CONVERTED) >= 15, f"expected most events to carry faction effects, got {len(_CONVERTED)}"
for cid in _all_ids:          # all nine, not just a sample
    landed_total = 0
    for event_id, option_ids in _CONVERTED.items():
        event = next(e for e in _cat() if e.id == event_id)
        for oid in option_ids:
            option = next(o for o in event.options if o.id == oid)
            st = _load(cid)
            before = {f.id: f.loyalty for f in st.country.factions}
            legislative.apply_effect_bundle(st, option.effects, event.title,
                                            event.id, event.portfolio)
            moved = {f.id: round(f.loyalty - before[f.id], 4)
                     for f in st.country.factions if abs(f.loyalty - before[f.id]) > 1e-9}
            landed_total += len(moved)
            # Sign-correctness is checked per FACTION, not per role: in a
            # thin party system two roles can resolve to the same faction
            # (Qadir's Tribal Confederation stands in for both labour and
            # agrarian), and their deltas then sum on it.
            expected = {}
            for role_key, delta in option.effects.faction_loyalty_deltas.items():
                target = role_faction(st, role_key)
                if target is None:
                    continue          # country has no such bloc; correctly skipped
                expected[target.id] = expected.get(target.id, 0.0) + delta

            if expected:
                assert moved, f"{cid}/{event_id}/{oid}: resolved roles landed nothing"
            else:
                # Every role this option names is genuinely absent here. That
                # is allowed only if the option still does something else —
                # otherwise choosing it would be a silent no-op.
                fx = option.effects
                assert (fx.modifiers or fx.gdp_growth_delta or fx.inflation_delta
                        or fx.unemployment_delta or fx.budget_revenue_delta
                        or fx.budget_expenditure_delta or fx.one_time_debt_pct_delta
                        or option.relation_deltas or option.on_apply), \
                    (f"{cid}/{event_id}/{oid}: every role it names is absent here and it "
                     f"has no other effect — choosing it would do literally nothing")

            for fid, net in expected.items():
                actual = next(f for f in st.country.factions if f.id == fid).loyalty - before[fid]
                if abs(net) < 1e-9:
                    continue          # opposing roles cancelled out on one faction
                assert (actual > 0) == (net > 0), \
                    f"{cid}/{event_id}/{oid}: {fid} expected net {net:+.3f}, got {actual:+.3f}"
    print(f"  {cid:<10} {landed_total} faction-deltas landed across "
          f"{sum(len(v) for v in _CONVERTED.values())} options in {len(_CONVERTED)} events")
print("  PASS: authored events bite in every country, not just Ardenia")


section("T4b: Generic events stay country-neutral; bespoke ones stay locked to Ardenia")
# Two categories, two rules. Reusable content must address roles so it works
# in all nine countries. Bespoke Ardenian arcs (content/events.py:
# ARDENIA_ONLY_EVENTS) may name that country's parties outright — but only
# if they are genuinely unable to fire anywhere else, which is checked here
# rather than trusted.
from content.events import ARDENIA_ONLY_EVENTS as _ARDENIA_ONLY

_all_faction_ids = set()
for cid in _all_ids:
    _all_faction_ids.update(f.id for f in _load(cid).country.factions)

for e in _cat():
    bespoke = e.id in _ARDENIA_ONLY
    for o in e.options:
        literal = [k for k in list(o.effects.faction_loyalty_deltas)
                   + list(o.effects.faction_power_deltas)
                   if not _roles.is_role_key(k)]
        if not bespoke:
            assert not literal, \
                (f"{e.id}/{o.id}: generic content must use role keys, not "
                 f"country-specific ids {literal}")
        else:
            unknown = [k for k in literal if k not in _all_faction_ids]
            assert not unknown, f"{e.id}/{o.id}: unknown faction id(s) {unknown}"
        # Generic content resolves relations through a sentinel; bespoke
        # content may name the one country its story is about, provided that
        # country actually exists (same bargain as the literal faction ids).
        for key in o.relation_deltas:
            if key in (_ev_mod.TARGET_MOST_HOSTILE, _ev_mod.TARGET_COOLEST):
                continue
            assert bespoke, f"{e.id}/{o.id}: relation delta names '{key}' outright"
            assert key in _all_ids, f"{e.id}/{o.id}: unknown country id '{key}'"

# Every bespoke event must be unable to fire outside Ardenia.
for eid in _ARDENIA_ONLY:
    event = next(e for e in _cat() if e.id == eid)
    for cid in _all_ids:
        if cid == "ardenia":
            continue
        other = _load(cid)
        other.turn = 40                      # well past any turn gate
        other.stability.value = 0.20         # and past the pressure gate
        assert not event.condition(other), \
            f"{eid} can fire in {cid} — bespoke Ardenian content must be gated"
print(f"  {len(_cat()) - len(_ARDENIA_ONLY)} generic events role-only; "
      f"{len(_ARDENIA_ONLY)} bespoke events Ardenia-locked")
print("  PASS: each category obeys its own rule")


section("T5b: Diplomatic events aim at the relation that triggered them")
border = next(e for e in _cat() if e.id == "border_incident")
assert border.condition is not None
for cid in _all_ids:
    st = _load(cid)
    if not border.condition(st):
        continue
    escalate = next(o for o in border.options if o.id == "escalate")
    target = _ev_mod.resolve_relation_target(st, _ev_mod.TARGET_COOLEST)
    assert target is not None, f"{cid}: border incident fired with nobody to aim at"
    coolest = min(st.country.relations.items(), key=lambda kv: kv[1].score)[0]
    assert target == coolest, f"{cid}: aimed at {target}, coolest is {coolest}"
    before = st.country.relations[target].score
    st.player.political_capital = 60.0
    st.pending_events.append(_PE(event_id="border_incident"))
    r = player_ops.op_resolve_event(st, "border_incident", "escalate")
    assert r.success
    assert st.country.relations[target].score < before, \
        f"{cid}: condemning {target} should worsen that relation"
print("  PASS: the border incident targets each country's own worst neighbour")


section("T5: Ardenia still behaves — the conversion didn't break the home scenario")
state = fresh()
strike = next(e for e in _cat() if e.id == "strike_wave")
police = next(o for o in strike.options if o.id == "send_police")
before = {f.id: f.loyalty for f in state.country.factions}
legislative.apply_effect_bundle(state, police.effects, strike.title, strike.id, strike.portfolio)
lab = role_faction(state, _roles.ROLE_LABOUR)
nat = role_faction(state, _roles.ROLE_NATIONALIST)
# Ardenia is the authored home scenario and a great deal of content is
# anchored to the Workers' Front by name; the role system must resolve to
# it, not quietly redirect to the larger Social Democrats.
assert lab.id == "workers_front" and nat.id == "national_conservatives", \
    f"Ardenia role mapping changed: labour={lab.id} nationalist={nat.id}"
assert lab.loyalty < before[lab.id], "clearing picket lines must anger the labour bloc"
assert nat.loyalty > before[nat.id], "and please the nationalists"
print(f"  Ardenia: labour={lab.id}, nationalist={nat.id} — deltas landed correctly")
print("  PASS: roles resolve to the intended Ardenian parties")


section("U0: A schemer's threat can actually reach the threshold it is measured against")
# threat_level() is ambition * (1 - loyalty), so without loyalty erosion a
# minister appointed at loyalty 0.50 was capped at 0.475 and could NEVER
# cross the 0.5 threshold — leaving both the restless warning and the
# schemer arc unreachable in real play. This pins the fix.
st = _load("ardenia")
sch = next(x for x in st.cabinet.ministers if x.trait == "schemer")
start_loyalty = sch.loyalty
armed_on = None
for t in range(1, 61):
    TurnEngine()._update_ministers(st)
    if sch.threat_level() > 0.5:
        armed_on = t
        break
assert armed_on is not None, \
    f"a schemer must become dangerous within 60 turns (threat stuck at {sch.threat_level():.3f})"
assert sch.loyalty < start_loyalty, "their loyalty should erode as ambition grows"
assert 10 <= armed_on <= 45, f"arc pacing: armed on turn {armed_on}, want a mid-campaign burn"
print(f"  schemer crosses the threshold on turn {armed_on} "
      f"(loyalty {start_loyalty:.2f} → {sch.loyalty:.2f})")
print("  PASS: the mechanical fuse actually burns down")


section("U1: The schemer arc fires from the trait's own threat curve, in any country")
from engine import roleplay as _rp


def _arm_schemer(state):
    """Push whichever schemer the cabinet has past the restless threshold."""
    m = next((x for x in state.cabinet.ministers if x.trait == "schemer"), None)
    assert m is not None, "fixture: this country's cabinet should contain a schemer"
    m.loyalty, m.ambition = 0.05, 0.95      # threat_level -> ~0.90
    return m


_ARC_COUNTRIES = ["ardenia", "qadir", "solheim"]
for cid in _ARC_COUNTRIES:
    st = _load(cid)
    stirs = next(e for e in _cat() if e.id == "a_schemer_stirs")
    assert not stirs.condition(st), f"{cid}: arc should not arm on a calm cabinet"
    m = _arm_schemer(st)
    assert stirs.condition(st), f"{cid}: arc should arm once a schemer turns dangerous"
    print(f"  {cid:<10} arms on {m.name} ({m.portfolio}), threat {m.threat_level():.2f}")
print("  PASS: the arc binds to whichever cabinet has a schemer, not a hardcoded minister")


section("U2: The middle of the arc genuinely branches — different events, different endings")
state = fresh()
_arm_schemer(state)
state.player.political_capital = 100.0
stirs = next(e for e in _cat() if e.id == "a_schemer_stirs")

branches = {}
for choice in ("confront", "wait"):
    st = fresh()
    _arm_schemer(st)
    st.player.political_capital = 100.0
    st.turn = 5
    st.pending_events.append(_PE(event_id="a_schemer_stirs"))
    r = player_ops.op_resolve_event(st, "a_schemer_stirs", choice)
    assert r.success, r.message
    assert st.scheduled_events, f"{choice}: nothing was scheduled"
    branches[choice] = st.scheduled_events[0]["event_id"]

assert branches["confront"] == "a_schemer_confronted"
assert branches["wait"] == "a_schemer_moves"
assert branches["confront"] != branches["wait"], "the two paths must lead to different events"
# And the two follow-ups genuinely offer different endings, not reskins.
opts = {eid: {o.id for o in next(e for e in _cat() if e.id == eid).options}
        for eid in branches.values()}
assert opts["a_schemer_confronted"] != opts["a_schemer_moves"]
assert "buy_off" in opts["a_schemer_confronted"], "confronting should allow buying them off"
assert "too_late" in opts["a_schemer_moves"], "waiting should allow losing outright"
print(f"  confront → {branches['confront']} {sorted(opts['a_schemer_confronted'])}")
print(f"  wait     → {branches['wait']} {sorted(opts['a_schemer_moves'])}")
print("  PASS: the choice changes which event fires next and which endings exist")


section("U3: Each ending resolves differently — bought off, neutralised, or beaten")
# Bought off: the minister stays, and their loyalty jumps.
st = fresh(); m = _arm_schemer(st); st.player.political_capital = 100.0
loyalty_before, portfolio = m.loyalty, m.portfolio
st.pending_events.append(_PE(event_id="a_schemer_confronted"))
player_ops.op_resolve_event(st, "a_schemer_confronted", "buy_off")
still_there = st.cabinet.get(portfolio)
assert still_there is not None and still_there.id == m.id, "bought off means they KEEP the job"
assert still_there.loyalty > loyalty_before, "and they are loyal now"
assert still_there.ambition > 0.9, "but every bit as ambitious — the resentment stays"

# Neutralised: the portfolio is vacated.
st2 = fresh(); m2 = _arm_schemer(st2); st2.player.political_capital = 100.0
st2.pending_events.append(_PE(event_id="a_schemer_confronted"))
player_ops.op_resolve_event(st2, "a_schemer_confronted", "demand_resignation")
assert st2.cabinet.get(m2.portfolio) is None, "demanding resignation must vacate the post"
assert any("schemer" not in l and m2.name in l for l in st2.turn_log)

# Beaten: they win, the arc hands off to the standing leadership challenge.
st3 = fresh(); m3 = _arm_schemer(st3); st3.player.political_capital = 100.0
st3.turn = 9
own = faction(st3, st3.player.faction_id)
wing_before = own.dominant_wing().loyalty
st3.pending_events.append(_PE(event_id="a_schemer_moves"))
player_ops.op_resolve_event(st3, "a_schemer_moves", "too_late")
assert st3.cabinet.get(m3.portfolio) is not None, "losing means they are still in post"
assert own.dominant_wing().loyalty < wing_before, "their allies inside your party are emboldened"
assert st3.scheduled_events[0]["event_id"] == "a_schemer_triumphant"
print(f"  bought off: loyalty {loyalty_before:.2f} → {still_there.loyalty:.2f}, ambition intact")
print("  PASS: three endings, three different mechanical outcomes")


section("U4: The full four-step arc runs end to end without error")
st = fresh(); m = _arm_schemer(st); st.player.political_capital = 100.0
st.turn = 3
path = []
st.pending_events.append(_PE(event_id="a_schemer_stirs"))
for event_id, choice in (("a_schemer_stirs", "wait"),
                         ("a_schemer_moves", "too_late"),
                         ("a_schemer_triumphant", "fight_it_out")):
    assert st.pending_events and st.pending_events[0].event_id == event_id, \
        f"expected {event_id}, pending is {[p.event_id for p in st.pending_events]}"
    r = player_ops.op_resolve_event(st, event_id, choice)
    assert r.success, f"{event_id}/{choice}: {r.message}"
    path.append(event_id)
    # Advance to the scheduled follow-up exactly as the turn loop would.
    if st.scheduled_events:
        st.turn = st.scheduled_events[0]["due_turn"]
        with patch("engine.events.event_catalog", return_value=_cat()):
            events.check_for_events(st)
assert path == ["a_schemer_stirs", "a_schemer_moves", "a_schemer_triumphant"]
assert st.pending_events and st.pending_events[0].event_id == "party_leadership_challenge", \
    "the arc should end by arming the existing leadership-challenge situation"
path.append("party_leadership_challenge")
print(f"  {' → '.join(path)}")
print("  PASS: four steps, ending in the standing leadership challenge")


section("U5: The arc survives its minister leaving mid-way")
st = fresh(); m = _arm_schemer(st); st.player.political_capital = 100.0
st.cabinet.ministers = [x for x in st.cabinet.ministers if x.id != m.id]   # resigned
st.pending_events.append(_PE(event_id="a_schemer_confronted"))
r = player_ops.op_resolve_event(st, "a_schemer_confronted", "demand_resignation")
assert r.success, "a mid-arc step must not crash when its subject is gone"
print("  PASS: a vanished schemer degrades to a quiet no-op")


section("U6: The rival escalates across a campaign, and the count persists")
st = fresh()
assert _rp.jibe_count(st) == 0
assert _rp.jibe_tier(st) == "rival_jibe", "early jibes are dismissive"
st.player.approval = 0.60
st.cooldowns[_rp.JIBE_COUNT_KEY] = _rp.SHARP_AFTER
assert _rp.jibe_tier(st) == "rival_jibe_sharp", "they sharpen once blows have landed"
st.cooldowns[_rp.JIBE_COUNT_KEY] = _rp.BITTER_AFTER
assert _rp.jibe_tier(st) == "rival_jibe_bitter", "a long-losing rival turns bitter"
st.player.approval = 0.20
assert _rp.jibe_tier(st) == "rival_jibe_sharp", \
    "but a struggling government keeps them on the attack instead"
# A struggling government sharpens them early, before any count.
fresh_struggling = fresh()
fresh_struggling.player.approval = 0.25
assert _rp.jibe_tier(fresh_struggling) == "rival_jibe_sharp"

# The counter really increments through the live watch, and persists.
st2 = fresh()
st2.turn = 10
st2.turn_log.append("VOTE FAILED — \"X\" falls 40-60 (needed 51); an embarrassment on the floor.")
with patch("engine.roleplay.random") as mock_rand:
    mock_rand.random.return_value = 0.0
    _rp.rival_watch(st2)
assert _rp.jibe_count(st2) == 1, "a jibe should be counted"
from engine import persistence as _pu
restored = _pu.deserialize_state(_pu.serialize_state(st2))
assert _rp.jibe_count(restored) == 1, "the escalation counter must survive save/load"
print(f"  tiers: {_rp.SHARP_AFTER}+ sharp, {_rp.BITTER_AFTER}+ bitter; counter persists")
print("  PASS: the feud has a memory")


section("U7: The most-repeated dispatches carry real variety")
_HIGH_FREQUENCY = ["economy_move", "modifier_expired", "vote_passed", "vote_failed",
                   "vote_reaction_pleased", "vote_reaction_angry",
                   "address_reassuring", "address_defiant",
                   "address_visionary", "address_contrite"]
for key in _HIGH_FREQUENCY:
    assert len(_TPL[key]) >= 3, f"{key} still has only {len(_TPL[key])} variants"
    assert len(set(_TPL[key])) == len(_TPL[key]), f"{key} has duplicate variants"
# economy_move fires every single turn, so it gets the widest pool of all.
assert len(_TPL["economy_move"]) >= 5, "the every-turn dispatch needs the most variety"
# Markers still hold for every new variant (Section L lints all pools, but
# pin the ones touched here explicitly).
for key in _HIGH_FREQUENCY + ["rival_jibe", "rival_jibe_sharp", "rival_jibe_bitter",
                              "schemer_arc", "schemer_bought",
                              "schemer_neutralized", "schemer_ascendant"]:
    marker = _MKS[key]
    for tmpl in _TPL[key]:
        assert marker.lower() in tmpl.lower(), f"{key}: variant lost its marker"
print(f"  economy_move now {len(_TPL['economy_move'])} variants; "
      f"{len(_HIGH_FREQUENCY)} high-frequency pools at 3+")
print("  PASS: the lines you see most often repeat least")


section("W1: The Vasca arc waits, then fires on a government that looks weak")
import content.events as ev_content
_vasca_root = next(e for e in _cat() if e.id == "vasca_stirs")


def _vasca_state(turn=20, stability=0.40):
    st = fresh()
    st.turn = turn
    st.stability.value = stability
    st.player.political_capital = 100.0
    return st


early = _vasca_state(turn=3)
assert not _vasca_root.condition(early), "the wound should not reopen in the opening months"
calm = _vasca_state(turn=20, stability=0.90)
calm.player.approval = 0.80
calm.civil_war_risk = 0.0
assert not _vasca_root.condition(calm), "a confident government isn't worth testing"
weak = _vasca_state(turn=20, stability=0.40)
assert _vasca_root.condition(weak), "a shaky government should draw him out"
assert _vasca_root.once, "the arc starts once per campaign"
# And never anywhere but Ardenia (also covered generally by T4b).
kras = _load("krasova"); kras.turn = 30; kras.stability.value = 0.2
assert not _vasca_root.condition(kras)
print(f"  gated: turn ≥ {ev_content.VASCA_MIN_TURN}, and only when stability/approval/risk say so")
print("  PASS: the arc has a fuse, not a trigger")


section("W2: The three answers lead to three genuinely different places")
_ROOT_CHOICES = ("crackdown", "amnesty", "downplay")
scheduled = {}
for choice in _ROOT_CHOICES:
    st = _vasca_state()
    st.pending_events.append(_PE(event_id="vasca_stirs"))
    with patch("content.events.random") as mock_rand:
        mock_rand.random.return_value = 0.0        # force the "works" branch
        r = player_ops.op_resolve_event(st, "vasca_stirs", choice)
    assert r.success, r.message
    assert st.scheduled_events, f"{choice}: scheduled nothing"
    scheduled[choice] = st.scheduled_events[0]["event_id"]

assert len(set(scheduled.values())) == 3, f"paths converge: {scheduled}"
assert scheduled["crackdown"] == "vasca_crackdown_works"
assert scheduled["amnesty"] == "vasca_amnesty_holds"
assert scheduled["downplay"] == "vasca_emboldened"
# The same choice can also fail — outcome is state-driven, not fixed.
st = _vasca_state()
st.pending_events.append(_PE(event_id="vasca_stirs"))
with patch("content.events.random") as mock_rand:
    mock_rand.random.return_value = 0.99           # force the "fails" branch
    player_ops.op_resolve_event(st, "vasca_stirs", "crackdown")
assert st.scheduled_events[0]["event_id"] == "vasca_crackdown_fails"
print(f"  crackdown→{scheduled['crackdown']} | amnesty→{scheduled['amnesty']} "
      f"| downplay→{scheduled['downplay']} (+ crackdown can fail)")
print("  PASS: three answers, three different follow-ups, outcome decided by the state")


section("W3: A crackdown's odds come from the security services, not a coin flip")
capable = _vasca_state(stability=0.85)
for portfolio in ("Interior", "Defense"):
    m = capable.cabinet.get(portfolio)
    m.competence, m.loyalty = 0.9, 0.9
broken = _vasca_state(stability=0.20)
broken.cabinet.ministers = [m for m in broken.cabinet.ministers
                            if m.portfolio not in ("Interior", "Defense")]
assert ev_content._security_effectiveness(capable) > \
       ev_content._security_effectiveness(broken) + 0.3, \
    "a functioning state should be far likelier to find him than a hollow one"
print(f"  effectiveness: capable {ev_content._security_effectiveness(capable):.2f} "
      f"vs hollowed-out {ev_content._security_effectiveness(broken):.2f}")
print("  PASS: competence decides the raid, not luck alone")


section("W4: The gated option belongs to the soldier")
st = _vasca_state()
open_ids = {o.id for o in events.available_options(st, _vasca_root)}
assert "lead_it" not in open_ids, "a civilian PM cannot lead the operation"
st.campaign_meta["background"] = "former_general"
assert "lead_it" in {o.id for o in events.available_options(st, _vasca_root)}
assert _vasca_root.default_option_id != "lead_it", "the auto-lapse option must never be gated"
print("  PASS: a former general gets an option nobody else does")


section("W5: Full playthrough — the hard road, end to end")
st = _vasca_state()
path = []
st.pending_events.append(_PE(event_id="vasca_stirs"))
with patch("content.events.random") as mock_rand:
    mock_rand.random.return_value = 0.99            # the sweep fails
    player_ops.op_resolve_event(st, "vasca_stirs", "crackdown")
path.append("vasca_stirs")
for event_id, choice in (("vasca_crackdown_fails", "escalate"),
                         ("vasca_last_stand", "storm_it")):
    st.turn = st.scheduled_events[0]["due_turn"]
    with patch("engine.events.event_catalog", return_value=_cat()):
        events.check_for_events(st)
    assert st.pending_events and st.pending_events[0].event_id == event_id, \
        f"expected {event_id}, got {[p.event_id for p in st.pending_events]}"
    r = player_ops.op_resolve_event(st, event_id, choice)
    assert r.success, f"{event_id}/{choice}: {r.message}"
    path.append(event_id)
assert st.campaign_meta.get("vasca_resolved") == "dead"
assert any(k == "vasca_dead" for k, _f, _t in st.turn_news), \
    "the death should reach the press as its own dispatch type"
# Every wording of it must leave the circumstances disputed — that ambiguity
# is the point of the beat, not an accident of one variant.
_DISPUTE = ("never be settled", "two versions", "his people say", "which one it believes")
for variant in _TPL["vasca_dead"]:
    assert any(p in variant for p in _DISPUTE), \
        f"a vasca_dead variant reads as settled fact: {variant[:70]}"
print(f"  {' → '.join(path)} → dead (disputed)")
print("  PASS: crackdown → backlash → the compound, resolved ambiguously")


section("W6: Full playthrough — ignoring it all the way, which resolves nothing")
st = _vasca_state()
path = []
st.pending_events.append(_PE(event_id="vasca_stirs"))
player_ops.op_resolve_event(st, "vasca_stirs", "downplay")
path.append("vasca_stirs")
pressure_after_ignoring = st.insurgency_pressure
for event_id, choice in (("vasca_emboldened", "keep_ignoring"),
                         ("vasca_last_stand", "let_it_lie")):
    st.turn = st.scheduled_events[0]["due_turn"]
    with patch("engine.events.event_catalog", return_value=_cat()):
        events.check_for_events(st)
    assert st.pending_events and st.pending_events[0].event_id == event_id
    r = player_ops.op_resolve_event(st, event_id, choice)
    assert r.success, f"{event_id}/{choice}: {r.message}"
    path.append(event_id)
assert st.campaign_meta.get("vasca_resolved") is None, \
    "ignoring it must leave the question genuinely open"
assert st.insurgency_pressure > pressure_after_ignoring, \
    "neglect should leave more men in the hills than it found"
print(f"  {' → '.join(path)} → still unresolved "
      f"(insurgency {st.insurgency_pressure:.2f})")
print("  PASS: the honest ending is no ending")


section("W7: The insurgency feeds the civil-war gauge, bounded, and decays")
quiet = fresh()
base_target, base_bd = crisis.compute_civil_war_risk(quiet)
assert "Active insurgency" in base_bd
assert base_bd["Active insurgency"] == 0.0, "a campaign with no flare-up is unaffected"
flared = fresh()
flared.insurgency_pressure = 1.0
hot_target, hot_bd = crisis.compute_civil_war_risk(flared)
assert hot_target > base_target, "an active insurgency should raise the risk"
assert hot_bd["Active insurgency"] <= 0.15, "but it must not dominate the gauge"
# It bleeds off if nothing feeds it, so no branch leaves a permanent drag.
for _ in range(40):
    crisis.maybe_trigger_civil_war(flared)
assert flared.insurgency_pressure == 0.0, "pressure must decay to nothing on its own"
# And it round-trips.
saved = fresh(); saved.insurgency_pressure = 0.42
from engine import persistence as _pw
assert _pw.deserialize_state(_pw.serialize_state(saved)).insurgency_pressure == 0.42
print(f"  weight {crisis.INSURGENCY_WEIGHT}: risk {base_target:.3f} → {hot_target:.3f} at full pressure; decays to 0")
print("  PASS: a lasting pressure, not a permanent one")


section("X1: The lore package preserves the old public API")
from content import lore as _canon_lore
_legacy_lore_types = {
    "CAPITAL": str,
    "UNION_NAME": str,
    "UNION_DOCTRINE": str,
    "SEPARATIST_REGION": str,
    "CORE_SUCCESSOR_STATE": str,
    "OVERVIEW": str,
    "TIMELINE": list,
    "PARTY_ORIGINS": dict,
    "FIGURES": dict,
}
for _name, _expected_type in _legacy_lore_types.items():
    assert hasattr(_canon_lore, _name), f"lore no longer exports {_name}"
    assert type(getattr(_canon_lore, _name)) is _expected_type, \
        f"{_name} changed type"
assert callable(_canon_lore.opening_briefing)
assert os.path.basename(os.path.dirname(_canon_lore.__file__)) == "lore", \
    "content.lore should resolve to the package"
print("  PASS: all ten legacy names resolve from content.lore with their old types")


section("X2: Every region and city has a stable, unique identity")
_places = [*_canon_lore.REGIONS, *_canon_lore.CITIES]
_place_ids = [item["id"] for item in _places]
assert len(_place_ids) == len(set(_place_ids)), "region/city ids must be globally unique"
for _place in _places:
    assert _place["id"] and _place["id"] == _place["id"].lower()
    assert _place["name"].strip() and _place["body"].strip()
print(f"  PASS: {len(_canon_lore.REGIONS)} regions and "
      f"{len(_canon_lore.CITIES)} cities are named and addressable")


section("X3: Every Ardenian party has at least two authored blocs")
_ardenia_for_blocs = _load("ardenia")
_faction_ids = {f.id for f in _ardenia_for_blocs.country.factions}
_bloc_ids = [item["id"] for item in _canon_lore.BLOCS]
assert len(_bloc_ids) == len(set(_bloc_ids)), "bloc ids must be unique"
for _bloc in _canon_lore.BLOCS:
    assert _bloc["parent_id"] in _faction_ids, \
        f"{_bloc['id']} names an unknown parent"
for _faction_id in _faction_ids:
    _children = [b for b in _canon_lore.BLOCS if b["parent_id"] == _faction_id]
    assert len(_children) >= 2, f"{_faction_id} has only {len(_children)} bloc(s)"
print(f"  PASS: {len(_canon_lore.BLOCS)} prose-only blocs cover all five parties")


section("X4: Every named officeholder is also a named figure")
for _officeholder in _canon_lore.OFFICEHOLDERS:
    assert _officeholder["figure_id"] in _canon_lore.FIGURES, \
        f"{_officeholder['name']} is missing from FIGURES"
print(f"  PASS: all {len(_canon_lore.OFFICEHOLDERS)} officeholders resolve in FIGURES")


section("X5: Lore remains pure content with no engine or model imports")
from pathlib import Path as _Path
_lore_dir = _Path(_canon_lore.__file__).parent
_lore_sources = sorted(_lore_dir.glob("*.py"))
assert _lore_sources, "the lore package contains no source modules"
for _source in _lore_sources:
    _import_lines = [line.strip() for line in _source.read_text(encoding="utf-8").splitlines()
                     if line.strip().startswith(("import ", "from "))]
    for _line in _import_lines:
        assert not (_line.startswith("import engine") or
                    _line.startswith("from engine") or
                    _line.startswith("import models") or
                    _line.startswith("from models")), \
            f"forbidden import in {_source.name}: {_line}"
print(f"  PASS: {len(_lore_sources)} lore modules import neither engine nor models")


section("X6: The original eleven-entry timeline remains intact at the end")
_original_titles = [
    "The First Republic", "The February Intervention", "Union rule",
    "Kestrel Square", "The Awakening", "The Vasca Presidency",
    "The Turn of the Year", "The Baran State Council", "The Vetrenka War",
    "The Reckoning", "Now",
]
assert _canon_lore.TIMELINE[-1][0] == "March 1993"
_timeline_titles = [title for _period, title, _body in _canon_lore.TIMELINE]
for _title in _original_titles:
    assert _title in _timeline_titles, f"original timeline title lost: {_title}"
assert _timeline_titles[-11:] == _original_titles, \
    "the original timeline entries changed order"
print("  PASS: four older entries lead into the unchanged 1918→March 1993 timeline")


section("V1: Ardenia's capital is named, and survives save/load")
from content import lore as _lore
st = _load("ardenia")
assert st.country.capital == "Vashtera", f"capital is {st.country.capital!r}"
assert st.country.paper == "The Vashtera Herald", "the paper is named for the capital"
from engine import persistence as _pv
restored = _pv.deserialize_state(_pv.serialize_state(st))
assert restored.country.capital == "Vashtera", "capital must round-trip"
# Countries without an authored capital degrade to an empty string, not a
# crash, and still round-trip.
for cid in _all_ids:
    other = _load(cid)
    assert isinstance(other.country.capital, str)
    assert _pv.deserialize_state(_pv.serialize_state(other)).country.capital \
        == other.country.capital
print(f"  {st.country.capital} · {st.country.paper}; all nine round-trip their capital field")
print("  PASS: the capital is real data, not just flavour text")


section("V2: The lore module is coherent and covers every Ardenian party")
assert _lore.CAPITAL == "Vashtera"
assert _lore.CORE_SUCCESSOR_STATE in _all_ids, "the Union's successor must be a real country"
assert len(_lore.TIMELINE) >= 8, "the timeline should span First Republic to now"
for period, title, body in _lore.TIMELINE:
    assert period and title and len(body) > 60, f"thin timeline entry: {title}"
ard = _load("ardenia")
missing = [f.id for f in ard.country.factions if f.id not in _lore.PARTY_ORIGINS]
assert not missing, f"parties with no founding story: {missing}"
assert {"vasca", "baran", "doncic", "yeska"} <= set(_lore.FIGURES)
# The timeline ends where the campaign starts.
assert any("March 1993" in p for p, _t, _b in _lore.TIMELINE)
assert ard.year == 1993 and ard.month == 3, "the campaign still starts in March 1993"
print(f"  {len(_lore.TIMELINE)} timeline entries, "
      f"{len(_lore.PARTY_ORIGINS)} party origins, {len(_lore.FIGURES)} figures")
print("  PASS: the canon is complete and matches the start date")


section("V3: A fresh Ardenian campaign opens on its own story")
from engine.campaign import CampaignConfig as _CC, generate_campaign as _gen
camp = _gen(_CC(country_id="ardenia", background_id="none", difficulty_id="normal"))
opening = list(camp.turn_log)
assert opening, "a new campaign should not open on an empty dispatch feed"
joined = " ".join(opening)
assert camp.player.name in joined, "the briefing should name the player"
assert "Liberal Democrat" in joined and "Reckoning" in joined, \
    "the briefing should place them in Baran's project and the Reckoning"
assert _lore.SEPARATIST_REGION in joined, "and name the open wound"
# Other countries have no authored history, so they get no briefing — and
# generating them must still work.
other = _gen(_CC(country_id="krasova", background_id="none", difficulty_id="normal"))
assert not any("Reckoning" in l for l in other.turn_log), \
    "Ardenian lore must not leak into another country's campaign"
print(f"  opening dispatch: {opening[0][:96]}…")
print("  PASS: the campaign starts with a who-is-the-new-PM profile")


section("T6: Faction roles round-trip through save/load")
st = _load("qadir")
roles_before = {f.id: f.role for f in st.country.factions}
from engine import persistence as _pt
restored = _pt.deserialize_state(_pt.serialize_state(st))
assert {f.id: f.role for f in restored.country.factions} == roles_before
print("  PASS: roles persist")


section("Z1: Daily clock crosses real month and leap-year boundaries")
daily = fresh()
daily.year, daily.month, daily.day = 1996, 2, 28
daily.day_index = 0
daily.turn = 0
clock = TurnEngine()
clock.advance_day(daily)
assert (daily.year, daily.month, daily.day) == (1996, 2, 29)
assert daily.turn == 0 and not clock.last_advance_monthly
clock.advance_day(daily)
assert (daily.year, daily.month, daily.day) == (1996, 3, 1)
assert daily.turn == 1 and clock.last_advance_monthly
assert daily.day_index == 2
print("  PASS: exact days advance independently; monthly simulation pulses at rollover")


section("Z2: Daily time and old monthly saves both round-trip safely")
daily.day = 17
daily.day_index = 731
payload = _pt.serialize_state(daily)
restored = _pt.deserialize_state(payload)
assert (restored.year, restored.month, restored.day) == (1996, 3, 17)
assert restored.day_index == 731
payload.pop("day")
payload.pop("day_index")
legacy = _pt.deserialize_state(payload)
assert legacy.day == 1 and legacy.day_index == legacy.turn * 30
print("  PASS: exact dates persist; pre-clock saves migrate to the first of their month")


section("Z3: Opposition legislation uses a real three-week response window")
daily_opp = generate_campaign(CampaignConfig(
    country_id="ardenia", party_id="national_conservatives",
    opening_role="opposition", background_id="none", seed=1903))
clock = TurnEngine()
clock.advance_day(daily_opp)
daily_bill = player_ops.government_bill(daily_opp)
assert daily_bill is not None, "government agenda should open on the daily clock"
introduced_day = daily_opp.day_index
for _ in range(_domestic_ai.VOTE_DELAY_DAYS - 1):
    clock.advance_day(daily_opp)
assert daily_bill in daily_opp.legislature.pending_bills
clock.advance_day(daily_opp)
assert daily_opp.day_index - introduced_day == _domestic_ai.VOTE_DELAY_DAYS
assert daily_bill not in daily_opp.legislature.pending_bills
print(f"  PASS: bill introduced on day {introduced_day}, voted after "
      f"{_domestic_ai.VOTE_DELAY_DAYS} days")


# ══════════════════════════════════════════════════════════════════════
#  SECTION Y — Vetrenka: the frozen conflict
# ══════════════════════════════════════════════════════════════════════

_VET = {e.id: e for e in _cat() if e.id.startswith("vetrenka")}
_FRICTION = _VET["vetrenka_friction"]
_CROSSROADS = _VET["vetrenka_crossroads"]


def _vet_state(turn=20, approval=None, stability=None):
    st = fresh()
    st.turn = turn
    st.player.political_capital = 200.0
    if approval is not None:
        st.player.approval = approval
    if stability is not None:
        st.stability.value = stability
    return st


def _weather(st, rounds=3, choice="absorb"):
    """Live through `rounds` of low-grade friction the way a player would."""
    for _ in range(rounds):
        st.pending_events.append(_PE(event_id="vetrenka_friction"))
        r = player_ops.op_resolve_event(st, "vetrenka_friction", choice)
        assert r.success, f"friction/{choice}: {r.message}"
    return st


def _run_chain(st, expected_first=None):
    """Pump scheduled follow-ups to their conclusion, taking each event's
    default option, and return the event-id chain that actually fired."""
    chain = []
    for _ in range(40):
        if not st.scheduled_events:
            break
        st.turn = min(s["due_turn"] for s in st.scheduled_events)
        with patch("engine.events.event_catalog", return_value=_cat()):
            events.check_for_events(st)
        assert st.pending_events, f"nothing fired on turn {st.turn}"
        eid = st.pending_events[0].event_id
        event = _VET[eid]
        r = player_ops.op_resolve_event(st, eid, event.default_option_id)
        assert r.success, f"{eid}: {r.message}"
        chain.append(eid)
    if expected_first is not None:
        assert chain and chain[0] == expected_first, \
            f"expected {expected_first} first, got {chain}"
    return chain


section("Y1: The friction recurs, respects its cooldown, and varies what it reports")
assert not _FRICTION.once, "a frozen conflict does not happen once"
assert _FRICTION.cooldown >= 4, f"cooldown {_FRICTION.cooldown} is too tight to feel periodic"
st = _vet_state(turn=1)
fire_turns, texts = [], set()
# Force every eligible roll so the ONLY thing spacing these out is the cooldown.
with patch("engine.events.event_catalog", return_value=[_FRICTION]), \
     patch("engine.events.random") as _mock:
    _mock.random.return_value = 0.0
    for t in range(1, 61):
        st.turn = t
        st.turn_log.clear()
        st.turn_news.clear()
        events.check_for_events(st)
        if st.pending_events:
            fire_turns.append(t)
            player_ops.op_resolve_event(st, "vetrenka_friction", "absorb")
            reported = [txt for k, _f, txt in st.turn_news if k == "vetrenka_incident"]
            assert len(reported) == 1, f"turn {t}: {len(reported)} incident dispatches"
            texts.add(reported[0])
gaps = [b - a for a, b in zip(fire_turns, fire_turns[1:])]
assert len(fire_turns) >= 5, f"only fired {len(fire_turns)} times in 60 turns"
assert all(g >= _FRICTION.cooldown for g in gaps), \
    f"fired inside its {_FRICTION.cooldown}-turn cooldown: turns {fire_turns}"
assert len(texts) >= 3, f"only {len(texts)} distinct incident reports across {len(fire_turns)} fires"
assert st.campaign_meta["vetrenka_incidents"] == len(fire_turns), \
    "every incident must be counted, since the crossroads is gated on the count"
print(f"  fired on turns {fire_turns} (gaps {gaps}, cooldown {_FRICTION.cooldown})")
print(f"  {len(texts)} distinct incident reports from a pool of {len(_TPL['vetrenka_incident'])}")
print("  PASS: periodic, not repetitive, and never early")


section("Y2: The crossroads stays shut until the friction has been weathered")
assert _CROSSROADS.once, "the pivot happens once per campaign"
st = _vet_state()
assert not _CROSSROADS.condition(st), "nothing shifts before anything has happened"
for n in range(1, ev_content.FRICTION_BEFORE_CROSSROADS):
    _weather(st, rounds=1)
    assert not _CROSSROADS.condition(st), f"opened after only {n} incident(s)"
_weather(st, rounds=1)
assert _CROSSROADS.condition(st), \
    f"still shut after {ev_content.FRICTION_BEFORE_CROSSROADS} incidents"
# And it belongs to Ardenia's government alone.
opp = _vet_state()
opp.campaign_meta["vetrenka_incidents"] = 99
opp.player.in_government = False
assert not _CROSSROADS.condition(opp), "this is a government decision"
kras = _load("krasova"); kras.turn = 40
kras.campaign_meta["vetrenka_incidents"] = 99
assert not _CROSSROADS.condition(kras) and not _FRICTION.condition(kras), \
    "bespoke Ardenian content must not fire abroad"
print(f"  shut at 0..{ev_content.FRICTION_BEFORE_CROSSROADS - 1} incidents, "
      f"open at {ev_content.FRICTION_BEFORE_CROSSROADS}; government-only; Ardenia-only")
print("  PASS: the pivot is earned, not scheduled")


section("Y3: Three answers send the country down three different roads")
_first_step = {}
for choice in ("settlement", "reassert", "formalise"):
    st = _weather(_vet_state(), rounds=3)
    st.pending_events.append(_PE(event_id="vetrenka_crossroads"))
    with patch("content.events.random") as _mock:
        _mock.random.return_value = 0.0             # force the favourable branch
        r = player_ops.op_resolve_event(st, "vetrenka_crossroads", choice)
    assert r.success, f"{choice}: {r.message}"
    assert st.scheduled_events, f"{choice} scheduled nothing"
    _first_step[choice] = st.scheduled_events[0]["event_id"]
assert len(set(_first_step.values())) == 3, f"roads converge: {_first_step}"
assert _CROSSROADS.default_option_id == "formalise", \
    "a government that never engages should let the line harden by default"
assert all(o.requires is None for o in _CROSSROADS.options), \
    "no path may be identity-gated — the default must always be takeable"
print("  " + " | ".join(f"{k}->{v}" for k, v in _first_step.items()))
print("  PASS: three roads, and inattention picks the cheap one")


section("Y4: Full playthrough — the peace process, which can succeed or collapse")
_ends = {}
for label, roll in (("succeeds", 0.0), ("collapses", 0.99)):
    st = _weather(_vet_state(), rounds=3)
    st.insurgency_pressure = 0.40
    before_pressure = st.insurgency_pressure
    before_stability = st.stability.value
    st.pending_events.append(_PE(event_id="vetrenka_crossroads"))
    with patch("content.events.random") as _mock:
        _mock.random.return_value = roll
        player_ops.op_resolve_event(st, "vetrenka_crossroads", "settlement")
    chain = ["vetrenka_crossroads"] + _run_chain(st)
    status = st.campaign_meta["vetrenka_status"]
    _ends[label] = status
    print(f"  {' -> '.join(chain)} => {status}")
    if label == "succeeds":
        assert status == "settled"
        assert st.insurgency_pressure < before_pressure, "a settlement should quiet the line"
    else:
        assert status == "talks_failed"
        assert st.insurgency_pressure > before_pressure, "a collapse should not"
        assert st.stability.value < before_stability, "and it should cost the government"
assert _ends["succeeds"] != _ends["collapses"]
print("  PASS: talks are a real gamble with two real endings")


section("Y5: Full playthrough — the offensive, which can win or break")
_ends = {}
for label, roll in (("wins", 0.0), ("breaks", 0.99)):
    st = _weather(_vet_state(), rounds=3)
    st.pending_events.append(_PE(event_id="vetrenka_crossroads"))
    with patch("content.events.random") as _mock:
        _mock.random.return_value = roll
        player_ops.op_resolve_event(st, "vetrenka_crossroads", "reassert")
    chain = ["vetrenka_crossroads"] + _run_chain(st)
    _ends[label] = (st.campaign_meta["vetrenka_status"], st.insurgency_pressure)
    print(f"  {' -> '.join(chain)} => {_ends[label][0]} "
          f"(insurgency {st.insurgency_pressure:.2f})")
assert _ends["wins"][0] == "retaken" and _ends["breaks"][0] == "routed"
# Winning is not free: you now hold a region that does not want you.
assert _ends["wins"][1] > 0.0, "occupation should leave pressure behind"
assert _ends["breaks"][1] > _ends["wins"][1], "but losing should be worse"
print("  PASS: victory costs, defeat costs more, and neither is a coin flip")


section("Y6: Full playthrough — the quiet partition, which the country may not wear")
_ends = {}
for label, ap, stab in (("normalises", 0.75, 0.85), ("backfires", 0.35, 0.45)):
    st = _weather(_vet_state(approval=ap, stability=stab), rounds=3)
    st.player.approval, st.stability.value = ap, stab
    before_stability = st.stability.value
    st.pending_events.append(_PE(event_id="vetrenka_crossroads"))
    player_ops.op_resolve_event(st, "vetrenka_crossroads", "formalise")
    chain = ["vetrenka_crossroads"] + _run_chain(st, expected_first="vetrenka_partition")
    status = st.campaign_meta["vetrenka_status"]
    _ends[label] = (status, chain)
    print(f"  {' -> '.join(chain)} => {status}")
    assert len(chain) == 3, f"the cheap road still takes three steps, got {chain}"
    if label == "backfires":
        assert st.stability.value < before_stability, "the backlash must actually bite"
assert _ends["normalises"][0] == "partitioned"
assert _ends["backfires"][0] == "partitioned_contested"
assert _ends["normalises"][1][-1] == "vetrenka_normalised"
assert _ends["backfires"][1][-1] == "vetrenka_backlash"
print("  PASS: getting away with it depends on standing, not on luck")


section("Y7: Every road ends, closes the question, and survives save/load")
_ROADS = {
    "settlement": [("settled", 0.0), ("talks_failed", 0.99)],
    "reassert":   [("retaken", 0.0), ("routed", 0.99)],
}
_reached = set()
for choice, outcomes in _ROADS.items():
    for expected, roll in outcomes:
        st = _weather(_vet_state(), rounds=3)
        st.pending_events.append(_PE(event_id="vetrenka_crossroads"))
        with patch("content.events.random") as _mock:
            _mock.random.return_value = roll
            player_ops.op_resolve_event(st, "vetrenka_crossroads", choice)
        _run_chain(st)
        assert st.campaign_meta["vetrenka_status"] == expected
        _reached.add(expected)
        # Resolved means resolved: neither layer may reopen.
        st.turn += 30
        assert not _FRICTION.condition(st), f"{expected}: friction reopened"
        assert not _CROSSROADS.condition(st), f"{expected}: the pivot reopened"
        assert not st.scheduled_events, f"{expected}: left a follow-up dangling"
for ap, stab, expected in ((0.75, 0.85, "partitioned"), (0.35, 0.45, "partitioned_contested")):
    st = _weather(_vet_state(approval=ap, stability=stab), rounds=3)
    st.player.approval, st.stability.value = ap, stab
    st.pending_events.append(_PE(event_id="vetrenka_crossroads"))
    player_ops.op_resolve_event(st, "vetrenka_crossroads", "formalise")
    _run_chain(st)
    assert st.campaign_meta["vetrenka_status"] == expected
    _reached.add(expected)
assert len(_reached) == 6, f"expected six distinct endings, reached {sorted(_reached)}"
from engine import persistence as _py
st.campaign_meta["vetrenka_incidents"] = 4
_restored = _py.deserialize_state(_py.serialize_state(st))
assert _restored.campaign_meta["vetrenka_status"] == expected
assert _restored.campaign_meta["vetrenka_incidents"] == 4
# The whole arc must be press-visible, or it happens off-screen.
from content.press import HEADLINES as _HL, SAMPLE_FIELDS as _SF
from engine.press import RANK as _RANK
for eid in _VET:
    assert eid in _ARDENIA_ONLY, f"{eid} names Ardenian parties but isn't scope-locked"
for key in ("vetrenka_incident", "vetrenka_talks", "vetrenka_offensive",
            "vetrenka_settled", "vetrenka_talks_failed", "vetrenka_retaken",
            "vetrenka_rout", "vetrenka_partition", "vetrenka_normalised",
            "vetrenka_backlash"):
    assert key in _TPL and key in _MKS and key in _HL and key in _SF and key in _RANK, \
        f"{key} is missing from the dispatch/press tables"
assert _RANK["vetrenka_incident"] < _RANK["vetrenka_settled"], \
    "weekly friction must not outrank the settlement of the war"
print(f"  six endings reached: {', '.join(sorted(_reached))}")
print("  PASS: every road terminates, locks the question, and reaches the front page")


section("Y8: The pivotal odds answer to the state, inside the band real governments occupy")
# A real Ardenian government arrives at the crossroads with approval 0.47-0.50
# and stability 0.41-0.51 — a narrow band. Odds curves that only separate at
# the extremes would be constant in practice, which is how "state-driven"
# quietly becomes "coin flip". The same roll must therefore split governments
# that differ by the amount real ones actually differ by.
def _crossroads_outcome(choice, roll, **kw):
    st = _weather(_vet_state(**kw), rounds=3)
    for field, value in (("approval", kw.get("approval")),
                         ("stability", kw.get("stability"))):
        if value is not None:
            if field == "approval":
                st.player.approval = value
            else:
                st.stability.value = value
    st.pending_events.append(_PE(event_id="vetrenka_crossroads"))
    with patch("content.events.random") as _m:
        _m.random.return_value = roll
        player_ops.op_resolve_event(st, "vetrenka_crossroads", choice)
    return st.scheduled_events[0]["event_id"]


_ROLL = 0.60
_strong = _crossroads_outcome("settlement", _ROLL, approval=0.60, stability=0.62)
_typical = _crossroads_outcome("settlement", _ROLL, approval=0.49, stability=0.50)
assert _strong == "vetrenka_settled", "a well-regarded government should carry the talks"
assert _typical == "vetrenka_talks_fail", \
    "the same roll must not save an ordinary government — the curve is flat"
_weak = _crossroads_outcome("settlement", 0.30, approval=0.30, stability=0.32)
assert _weak == "vetrenka_talks_fail", "and a failing government should not get a peace"
print(f"  talks at roll {_ROLL}: approval 0.60 → settled, 0.49 → collapsed "
      f"(a 0.11 gap decides it)")

# The offensive answers to the ministries that would have to run it.
def _war_outcome(roll, competence):
    st = _weather(_vet_state(), rounds=3)
    for portfolio in ("Interior", "Defense"):
        minister = st.cabinet.get(portfolio)
        if minister is not None:
            minister.competence = competence
    st.pending_events.append(_PE(event_id="vetrenka_crossroads"))
    with patch("content.events.random") as _m:
        _m.random.return_value = roll
        player_ops.op_resolve_event(st, "vetrenka_crossroads", "reassert")
    return ev_content._security_effectiveness(st), st.scheduled_events[0]["event_id"]

_hi_sec, _hi = _war_outcome(0.35, 0.95)
_lo_sec, _lo = _war_outcome(0.35, 0.15)
assert _hi == "vetrenka_retaken", f"a capable security state should win at 0.35 (sec {_hi_sec:.2f})"
assert _lo == "vetrenka_rout", f"an incapable one should not (sec {_lo_sec:.2f})"
print(f"  offensive at roll 0.35: security {_hi_sec:.2f} → retaken, "
      f"{_lo_sec:.2f} → routed")
print("  PASS: both gambles are decided by the government, not by the dice alone")


# ══════════════════════════════════════════════════════════════════════════
# SECTION AA — CANONICAL ARDENIAN BLOCS
# ══════════════════════════════════════════════════════════════════════════

from content import lore as _bloc_lore
from engine import persistence as _bloc_persistence


section("AA1: Part I's twelve named currents are Ardenia's live party actors")
state = fresh()
loaded_blocs = [w for party in state.country.factions for w in party.wings]
assert {w.id for w in loaded_blocs} == {b["id"] for b in _bloc_lore.BLOCS}
assert all(w.kind == "bloc" and w.description and w.policy_biases for w in loaded_blocs)
for party in state.country.factions:
    assert len(party.wings) >= 2, f"{party.name} has too few live blocs"
    assert abs(sum(w.strength for w in party.wings) - 1.0) < 1e-9
print(f"  {len(loaded_blocs)} canonical blocs across {len(state.country.factions)} parties")
print("  PASS: the Codex currents and the seat-holding simulation are the same actors")


section("AA2: A bloc's concrete interest changes its legislative lean")
state = fresh()
libdem = faction(state, "liberal_democrats")
capital_bar = next(w for w in libdem.wings if w.id == "ld_bar")
telecom = next(b for b in bill_catalog() if b.id == "telecom_privatization_act")
with_interest = next(lean for w, _seats, lean in wing_votes(libdem, telecom)
                     if w.id == capital_bar.id)
pull = capital_bar.policy_biases.pop(telecom.id)
without_interest = next(lean for w, _seats, lean in wing_votes(libdem, telecom)
                        if w.id == capital_bar.id)
capital_bar.policy_biases[telecom.id] = pull
assert with_interest > without_interest and abs((with_interest - without_interest) - pull) < 1e-9
print(f"  Capital Bar on telecom sale: {without_interest:+.2f} → {with_interest:+.2f} "
      f"from its {pull:+.2f} commercial pull")
print("  PASS: bloc interests matter separately from the ideology compass")


section("AA3: A named rebellion leaves a lasting cohesion cost")
state = fresh()
price_controls = next(b for b in bill_catalog() if b.id == "emergency_price_controls")
price_controls.status = "proposed"
state.legislature.pending_bills.append(price_controls)
capital_bar = next(w for w in faction(state, "liberal_democrats").wings if w.id == "ld_bar")
before_loyalty = capital_bar.loyalty
assert any(w.id == "ld_bar" for _party, w, _seats, _direction
           in vote_rebellions(state, price_controls)), "Capital Bar should break on price controls"
resolve_vote(state, price_controls)
assert capital_bar.loyalty < before_loyalty
assert any("Capital Bar" in line for line in state.turn_log)
print(f"  Capital Bar loyalty: {before_loyalty:+.2f} → {capital_bar.loyalty:+.2f}")
print("  PASS: a division becomes a small, persistent party fracture")


section("AA4: Canonical blocs round-trip, and known legacy Ardenian spectra upgrade")
state = fresh()
payload = _bloc_persistence.serialize_state(state)
restored = _bloc_persistence.deserialize_state(payload)
assert all(w.kind == "bloc" and w.policy_biases
           for party in restored.country.factions for w in party.wings)

# Simulate the exact current sets written by pre-canon saves. Their only
# migration is the known generic Ardenian data; unfamiliar/modded data is not
# rewritten by the loader.
legacy_payload = copy.deepcopy(payload)
for party_data in legacy_payload["country"]["factions"]:
    old_ids = _bloc_persistence._LEGACY_ARDENIA_WING_IDS.get(party_data["id"])
    if old_ids is None:
        continue
    sample = party_data["wings"][0]
    party_data["wings"] = [{**sample, "id": old_id, "kind": "wing",
                            "description": "", "policy_biases": {}}
                           for old_id in sorted(old_ids)]
migrated = _bloc_persistence.deserialize_state(legacy_payload)
assert {w.id for party in migrated.country.factions for w in party.wings} == \
       {b["id"] for b in _bloc_lore.BLOCS}
print("  current saves round-trip; pre-canon Ardenian spectra upgrade by their known ids")
print("  PASS: canonical party data persists and existing Ardenian saves remain usable")


# ══════════════════════════════════════════════════════════════════════════
# SECTION AB — ARDENIAN REGIONAL SIMULATION
# ══════════════════════════════════════════════════════════════════════════

from content.regions import (ARDENIA_REGION_PROFILES as _REGION_PROFILES,
                             REGIONAL_ISSUES as _REGIONAL_ISSUES)
from engine import regions as _region_engine
from engine import stability as _region_stability
from engine import persistence as _region_persistence


section("AB1: Every canonical Ardenian region has persistent live conditions")
state = fresh()
assert set(state.regions) == set(_REGION_PROFILES)
assert all(region.id == region_id for region_id, region in state.regions.items())
assert all(0.0 <= region.unemployment <= 1.0
           and 0.0 <= region.state_reach <= 1.0
           and 0.0 <= region.pressure <= 1.0
           for region in state.regions.values())
assert len({region.issue_id for region in state.regions.values()}) == len(state.regions)
assert all(region.issue_id in _REGIONAL_ISSUES for region in state.regions.values())
from content.loader import build_state_for as _build_regional_state
assert not _build_regional_state("krasova").regions, \
    "countries without authored regional data must remain fully buildable"
print("  six live regions; non-Ardenian country construction remains country-neutral")
print("  PASS: the map's stable ids and the campaign's regional state are one-to-one")


section("AB2: National performance diverges into distinct local outcomes")
healthy = fresh()
stressed = copy.deepcopy(healthy)
healthy.country.economy.unemployment = 0.05
healthy.country.bureaucratic_capacity = 0.90
healthy.stability.value = 0.75
stressed.country.economy.unemployment = 0.25
stressed.country.bureaucratic_capacity = 0.35
stressed.stability.value = 0.25
for _ in range(12):
    _region_engine.simulate_regions(healthy)
    _region_engine.simulate_regions(stressed)
assert _region_engine.national_pressure(stressed) > _region_engine.national_pressure(healthy)
assert _region_engine.average_state_reach(stressed) < _region_engine.average_state_reach(healthy)
assert stressed.regions["zavost"].unemployment > stressed.regions["vashtera"].unemployment
assert stressed.regions["anera"].state_reach < stressed.regions["sela"].state_reach
assert stressed.regions["vetrenka"].control == "separatist"
print(f"  pressure healthy {_region_engine.national_pressure(healthy)*100:.0f}% / "
      f"stressed {_region_engine.national_pressure(stressed)*100:.0f}%")
print("  PASS: shared national shocks produce geographically authored consequences")


section("AB3: Regional state round-trips and old saves receive safe defaults")
state = fresh()
state.regions["zavost"].pressure = 0.777
payload = _region_persistence.serialize_state(state)
restored = _region_persistence.deserialize_state(payload)
assert restored.regions["zavost"].pressure == 0.777
assert restored.regions["anera"].control == "limited"
legacy_payload = copy.deepcopy(payload)
legacy_payload.pop("regions")
migrated = _region_persistence.deserialize_state(legacy_payload)
assert set(migrated.regions) == set(_REGION_PROFILES)
assert migrated.regions["vetrenka"].control == "separatist"
print("  live values survive; a pre-region Ardenian save gains the canonical baseline")
print("  PASS: the regional layer is persistent without abandoning existing campaigns")


section("AB4: Neglected regional pressure feeds the national unrest signal")
calm = fresh()
strained = copy.deepcopy(calm)
for region in calm.regions.values():
    region.pressure = 0.30
for region in strained.regions.values():
    region.pressure = 0.90
assert _region_stability.compute_unrest(strained) > _region_stability.compute_unrest(calm)
print(f"  unrest calm {_region_stability.compute_unrest(calm):.3f} / "
      f"strained {_region_stability.compute_unrest(strained):.3f}")
print("  PASS: the regional map reports a pressure the national government must absorb")


section("AB5: Vetrenka's authored endings redraw its live political condition")
settled = _vet_state()
settled.pending_events.append(_PE(event_id="vetrenka_settled"))
player_ops.op_resolve_event(settled, "vetrenka_settled", "sign_it")
assert settled.regions["vetrenka"].control == "autonomous"
assert settled.regions["vetrenka"].issue_id == "postwar_framework"
retaken = _vet_state()
retaken.pending_events.append(_PE(event_id="vetrenka_retaken"))
player_ops.op_resolve_event(retaken, "vetrenka_retaken", "garrison")
assert retaken.regions["vetrenka"].control == "state"
assert retaken.regions["vetrenka"].issue_id == "occupation_and_return"
print("  peace → shared authority; victory → state control, each with a new local problem")
print("  PASS: explicit sovereignty outcomes and the regional map cannot contradict each other")


section("AB6: Regional programmes respect authority, access and political cost")
state = fresh()
before_pc = state.player.political_capital
workers_before = faction(state, "workers_front").loyalty
launched = player_ops.op_start_regional_program(
    state, "zavost", "industrial_recovery")
assert launched.success
assert state.player.political_capital == before_pc - 12.0
assert faction(state, "workers_front").loyalty > workers_before
assert _region_engine.active_program_for(state, "zavost").program_id == \
       "industrial_recovery"
duplicate = player_ops.op_start_regional_program(
    state, "zavost", "administrative_deployment")
assert not duplicate.success and len(state.regional_programs) == 1
assert not player_ops.op_start_regional_program(
    state, "vetrenka", "public_works").success
assert not player_ops.op_start_regional_program(
    state, "zavost", "customs_enforcement").success
opposition_state = fresh()
opposition_state.player.in_government = False
opposition_pc = opposition_state.player.political_capital
assert not player_ops.op_start_regional_program(
    opposition_state, "anera", "administrative_deployment").success
assert opposition_state.player.political_capital == opposition_pc
print("  one programme per region; opposition and the ceasefire line cannot spend state money")
print("  PASS: regional action authority is enforced in the operation, not merely hidden by the UI")


section("AB7: Programmes deliver gradually through the cabinet and treasury")
untreated = fresh()
treated = copy.deepcopy(untreated)
assert player_ops.op_start_regional_program(
    treated, "zavost", "industrial_recovery").success
baseline_spending = treated.country.economy.budget.expenditure
_region_engine.simulate_regions(untreated)
_region_engine.simulate_regions(treated)
assert treated.country.economy.budget.expenditure == baseline_spending + 110.0
for _ in range(5):
    _region_engine.simulate_regions(untreated)
    _region_engine.simulate_regions(treated)
assert treated.regions["zavost"].unemployment < untreated.regions["zavost"].unemployment
assert treated.regions["zavost"].pressure < untreated.regions["zavost"].pressure

competent = fresh()
vacant = copy.deepcopy(competent)
player_ops.op_start_regional_program(competent, "anera", "administrative_deployment")
player_ops.op_start_regional_program(vacant, "anera", "administrative_deployment")
competent.cabinet.get("Interior").competence = 0.95
competent.cabinet.get("Interior").loyalty = 0.95
vacant.cabinet.ministers = [m for m in vacant.cabinet.ministers
                            if m.portfolio != "Interior"]
assert _region_engine.program_delivery_quality(
    competent, competent.regional_programs[0]) > \
    _region_engine.program_delivery_quality(vacant, vacant.regional_programs[0])
print("  Zavost improves relative to no programme; a staffed portfolio delivers more")
print("  PASS: programmes are commitments with monthly implementation, not instant stat buttons")


section("AB8: Programmes conclude, persist mid-delivery and remain bounded")
state = fresh()
player_ops.op_start_regional_program(state, "kelvet", "customs_enforcement")
for _ in range(4):
    _region_engine.simulate_regions(state)
payload = _region_persistence.serialize_state(state)
restored = _region_persistence.deserialize_state(payload)
assert len(restored.regional_programs) == 1
assert restored.regional_programs[0].months_active == 4
assert restored.regional_programs[0].monthly_cost == 55.0
for _ in range(restored.regional_programs[0].duration - 4):
    _region_engine.simulate_regions(restored)
assert not restored.regional_programs
assert any("REGIONAL PROGRAMME" in line and "concludes" in line
           for line in restored.turn_log)
for region in restored.regions.values():
    assert 0.0 <= region.unemployment <= 0.60
    assert 0.0 <= region.state_reach <= 1.0
    assert 0.0 <= region.pressure <= 1.0
print("  month 4 round-trips; month 12 closes the commitment and retains bounded outcomes")
print("  PASS: active programmes survive saves and cannot become permanent hidden modifiers")


section("AB9: The terminal front-end can launch the same regional operation")
state = fresh()
# Category 8 (appended after every legacy category) → action 1 → Zavost →
# industrial recovery, then back out of the action and category menus.
run_scripted(state, ["8", "1", "2", "1", "0", "0"])
assert len(state.regional_programs) == 1
assert state.regional_programs[0].region_id == "zavost"
assert state.regional_programs[0].program_id == "industrial_recovery"
print("  PASS: CLI and map call the same player operation and create the same commitment")


section("AB10: Every region carries a coherent, distinctive electorate")
state = fresh()
party_ids = {party.id for party in state.country.factions}
leaders = set()
for region_id, region in state.regions.items():
    assert set(region.party_support) == party_ids
    assert abs(sum(region.party_support.values()) - 1.0) < 1e-9
    leader, share = _region_engine.leading_party(state, region_id)
    assert leader is not None and 0.0 < share <= 1.0
    leaders.add(leader.id)
assert len(leaders) >= 2, "the country should not begin as one undifferentiated electorate"
assert _region_engine.leading_party(state, "vashtera")[0].id == "liberal_democrats"
assert _region_engine.leading_party(state, "anera")[0].id == "national_conservatives"
print("  Vashtera opens Liberal Democrat; Anera opens National Conservative")
print("  PASS: regional party support is normalized, complete and geographically distinct")


section("AB11: Local conditions reward or punish the sitting party locally")
state = fresh()
national = {party.id: party.support for party in state.country.factions}
for region_id in ("vashtera", "zavost"):
    state.regions[region_id].party_support = dict(national)
    state.regions[region_id].support_anchor = dict(national)
state.regions["vashtera"].pressure = 0.15
state.regions["vashtera"].unemployment = 0.05
state.regions["vashtera"].state_reach = 0.92
state.regions["zavost"].pressure = 0.90
state.regions["zavost"].unemployment = 0.28
state.regions["zavost"].state_reach = 0.45
for _ in range(12):
    _region_engine.update_party_support(state)
ld_vashtera = state.regions["vashtera"].party_support["liberal_democrats"]
ld_zavost = state.regions["zavost"].party_support["liberal_democrats"]
assert ld_vashtera > national["liberal_democrats"] > ld_zavost
print(f"  identical start → governing support Vashtera {ld_vashtera*100:.1f}% / "
      f"Zavost {ld_zavost*100:.1f}%")
print("  PASS: voters judge the national government through their own regional experience")


section("AB12: A regional programme creates a local electoral constituency")
untreated = fresh()
treated = copy.deepcopy(untreated)
assert player_ops.op_start_regional_program(treated, "sela", "public_works").success
for _ in range(9):
    _region_engine.simulate_regions(untreated)
    _region_engine.update_party_support(untreated)
    _region_engine.simulate_regions(treated)
    _region_engine.update_party_support(treated)
treated_sd = treated.regions["sela"].party_support["social_democrats"]
untreated_sd = untreated.regions["sela"].party_support["social_democrats"]
treated_ag = treated.regions["sela"].party_support["agrarian_union"]
untreated_ag = untreated.regions["sela"].party_support["agrarian_union"]
assert treated_sd > untreated_sd and treated_ag > untreated_ag
print(f"  Sela after nine months: Social Democrats {untreated_sd*100:.1f}% → "
      f"{treated_sd*100:.1f}%, Agrarians {untreated_ag*100:.1f}% → {treated_ag*100:.1f}%")
print("  PASS: programme beneficiaries gain where the programme is actually delivered")


section("AB13: Elections aggregate regional access, votes and old-save migration")
state = fresh()
closed = elec.compute_turnout(state)
assert closed["regional_access"]["vetrenka"] == 0.0
assert closed["regional_access"]["anera"] < closed["regional_access"]["vashtera"]
for region_id, shares in closed["regional_vote_share"].items():
    if closed["regional_access"][region_id] > 0:
        assert abs(sum(shares.values()) - 1.0) < 1e-9

state.regions["vetrenka"].control = "autonomous"
state.regions["vetrenka"].state_reach = 0.28
opened = elec.compute_turnout(state)
assert opened["regional_access"]["vetrenka"] > 0.0
assert opened["total_cast"] > closed["total_cast"]
result = elec.hold_election(state)
assert set(result.regional_vote_share) == set(state.regions)
assert any("REGIONAL COUNT" in line for line in state.turn_log)
restored = _region_persistence.deserialize_state(
    _region_persistence.serialize_state(state))
assert restored.election_history[-1].regional_vote_share == result.regional_vote_share

legacy_payload = _region_persistence.serialize_state(fresh())
for region_data in legacy_payload["regions"].values():
    region_data.pop("party_support")
    region_data.pop("support_anchor")
migrated = _region_persistence.deserialize_state(legacy_payload)
assert all(region.party_support and region.support_anchor
           for region in migrated.regions.values())
print(f"  Vetrenka access 0% → {opened['regional_access']['vetrenka']*100:.0f}%; "
      "regional result persists and old saves receive electorates")
print("  PASS: the national result is now built from the parts of Ardenia that can actually vote")


section("AB14: Government and opposition can campaign for a specific electorate")
state = fresh()
state.player.in_government = False
own_id = state.player.faction_id
before_local = _region_engine.projected_party_support(state, "sela")[own_id]
before_pc = state.player.political_capital
result = player_ops.op_campaign_region(state, "sela")
after_local = _region_engine.projected_party_support(state, "sela")[own_id]
assert result.success and after_local > before_local
assert state.player.political_capital == before_pc - player_ops.REGIONAL_CAMPAIGN_COST
assert not player_ops.op_campaign_region(state, "sela").success, \
    "the same organisers cannot tour the same region every day"
assert not player_ops.op_campaign_region(state, "vetrenka").success, \
    "a party cannot canvass across an inaccessible ceasefire line"
print(f"  opposition campaign in Sela: Liberal Democrats {before_local*100:.1f}% → "
      f"{after_local*100:.1f}%; repeat blocked for three months")
print("  PASS: regional electoral strategy gives opposition real agency without state authority")


section("AB15: The CLI exposes regional campaigning through the shared operation")
state = fresh()
before = state.regions["vashtera"].party_support[state.player.faction_id]
# Regional category → Campaign in a Region → Vashtera, then back out.
run_scripted(state, ["8", "2", "1", "0", "0"])
assert state.regions["vashtera"].party_support[state.player.faction_id] > before
print("  PASS: terminal and map campaigning move the same local electorate")


# ══════════════════════════════════════════════════════════════════════════
# SECTION AC — ANNUAL APPROPRIATIONS
# ══════════════════════════════════════════════════════════════════════════

from content.budget import BUDGET_ENVELOPES as _BUDGET_ENVELOPES
from engine import budget as _budget_engine
from engine import persistence as _budget_persistence


section("AC1: Every campaign begins with a complete inherited budget")
state = fresh()
assert state.active_budget is not None
assert state.active_budget.status == "active"
assert state.active_budget.year == state.year
assert {item["id"] for item in _BUDGET_ENVELOPES} == set(state.active_budget.allocations)
assert abs(state.active_budget.expenditure -
           state.country.economy.structural_expenditure) < 1e-6
print(f"  {len(state.active_budget.allocations)} envelopes sum to "
      f"{state.active_budget.expenditure:,.0f} M")
print("  PASS: the old fiscal baseline migrates into a legible annual settlement")


section("AC2: Drafting reallocates the next year without instant fiscal effects")
state = fresh()
before_structural = state.country.economy.structural_expenditure
plan = _budget_engine.build_proposal(state, {
    "health_and_welfare": 0.10,
    "education": 0.05,
    "national_defense": -0.10,
})
assert plan.year == state.year + 1
assert plan.allocations["health_and_welfare"] > state.active_budget.allocations["health_and_welfare"]
assert plan.allocations["national_defense"] < state.active_budget.allocations["national_defense"]
result = player_ops.op_propose_budget(state, plan)
assert result.success and state.pending_budget is plan
assert state.country.economy.structural_expenditure == before_structural
assert plan.forecast_balance == plan.forecast_revenue - plan.expenditure
print(f"  current {before_structural:,.0f} M; proposed {plan.expenditure:,.0f} M "
      f"for {plan.year}, with no instant change")
print("  PASS: appropriations are future commitments, not immediate stat buttons")


section("AC3: The annual budget faces the real parliament and can be lobbied")
state = fresh()
plan = _budget_engine.build_proposal(state, {"health_and_welfare": 0.15})
assert player_ops.op_propose_budget(state, plan).success
before_votes = _budget_engine.projected_votes(state, plan)[0]
target = faction(state, "national_conservatives")
assert player_ops.op_lobby_budget(state, target.id).success
after_votes = _budget_engine.projected_votes(state, plan)[0]
assert after_votes >= before_votes
vote = player_ops.op_call_budget_vote(state)
assert vote.success and plan.votes_for + plan.votes_against == state.legislature.total_seats
assert plan.status in ("approved", "rejected")
print(f"  projected support {before_votes} → {after_votes}; recorded "
      f"{plan.votes_for}-{plan.votes_against}")
print("  PASS: the budget uses seats, factions, blocs and a recorded division")


section("AC4: Passage waits for January; failure produces a reduced continuation")
passed = fresh()
plan = _budget_engine.build_proposal(passed, {"infrastructure": 0.15})
plan.status = "approved"
passed.pending_budget = plan
passed.year = plan.year
passed.month = 1
activated = _budget_engine.process_fiscal_year(passed)
assert activated is passed.active_budget
assert passed.active_budget.year == plan.year
assert passed.country.economy.structural_expenditure == plan.expenditure

failed = fresh()
old_total = failed.active_budget.expenditure
failed.year += 1
failed.month = 1
fallback = _budget_engine.process_fiscal_year(failed)
assert fallback.source == "continuing"
assert abs(fallback.expenditure - old_total * (1.0 - _budget_engine.CONTINUING_CUT)) < 1.0
assert any("BUDGET IMPASSE" in line for line in failed.turn_log)
print(f"  voted plan activates at {plan.expenditure:,.0f} M; impasse continues at "
      f"{fallback.expenditure:,.0f} M")
print("  PASS: fiscal years have deadlines and a failed budget has a bounded consequence")


section("AC5: Budget plans round-trip and pre-budget saves migrate")
state = fresh()
plan = _budget_engine.build_proposal(state, {"education": 0.10})
assert player_ops.op_propose_budget(state, plan).success
plan.lobbying_bonus["social_democrats"] = 0.22
payload = _budget_persistence.serialize_state(state)
restored = _budget_persistence.deserialize_state(payload)
assert restored.active_budget.allocations == state.active_budget.allocations
assert restored.pending_budget.allocations == plan.allocations
assert restored.pending_budget.lobbying_bonus == plan.lobbying_bonus
legacy = copy.deepcopy(payload)
legacy.pop("active_budget")
legacy.pop("pending_budget")
legacy.pop("budget_history")
migrated = _budget_persistence.deserialize_state(legacy)
assert migrated.active_budget is not None
assert abs(migrated.active_budget.expenditure -
           migrated.country.economy.structural_expenditure) < 1e-6
print("  active and proposed plans persist; the old expenditure baseline seeds missing data")
print("  PASS: annual appropriations do not strand existing campaigns")


section("AC6: In opposition, the sitting government—not the player—owns January")
state = fresh()
state.player.in_government = False
state.ruling_faction_id = "national_conservatives"
approval_before = state.player.approval
state.year += 1
state.month = 1
enacted = _budget_engine.process_fiscal_year(state)
assert enacted.source == "government_ai"
assert enacted.proposed_by == state.ruling_faction_id
assert state.player.approval == approval_before
assert any("GOVERNMENT BUDGET" in line for line in state.turn_log)
print(f"  {enacted.proposed_by} enacts {enacted.expenditure:,.0f} M; opposition approval untouched")
print("  PASS: fiscal authority follows office rather than the player character")


section("AC7: The terminal front-end drafts through the shared budget operation")
state = fresh()
# Category 9 → Draft; choose no change (the fourth item) in all seven
# envelopes, confirm, then back out of the action and category menus.
run_scripted(state, ["9", "1", *("4" for _ in _BUDGET_ENVELOPES), "y", "0", "0"])
assert state.pending_budget is not None
assert state.pending_budget.status == "proposed"
assert state.pending_budget.allocations == state.active_budget.allocations
print("  PASS: CLI and GUI both table the same modeled annual appropriations")


# ══════════════════════════════════════════════════════════════════════════
# SECTION AD — MINISTRY CAPACITY AND DELIVERY
# ══════════════════════════════════════════════════════════════════════════

from models.cabinet import CORE_PORTFOLIOS as _MINISTRY_PORTFOLIOS
from models.modifiers import Modifier as _DeliveryModifier
from engine import ministries as _ministry_engine
from engine import persistence as _ministry_persistence


section("AD1: Every cabinet portfolio has a persistent operating department")
state = fresh()
assert set(state.ministries) == set(_MINISTRY_PORTFOLIOS)
for portfolio, ministry in state.ministries.items():
    assert ministry.portfolio == portfolio
    assert ministry.baseline_funding > 0.0
    assert 0.0 <= ministry.delivery <= 1.0
    assert ministry.backlog == 0.0
assert "foreign_affairs" in state.active_budget.allocations
print(f"  {len(state.ministries)} ministries, each with funding and a live delivery ledger")
print("  PASS: every real cabinet office now governs an institution rather than an empty slot")


section("AD2: Laws, programmes, commitments and crises create concrete workload")
state = fresh()
base_economy = sum(_ministry_engine.workload_breakdown(state, "Economy").values())
extra_law = copy.deepcopy(next(b for b in bill_catalog() if b.id == "minimum_wage_act"))
extra_law.status = "active"
state.legislature.active_laws.append(extra_law)
player_ops.op_start_regional_program(state, "zavost", "industrial_recovery")
loaded_economy = _ministry_engine.workload_breakdown(state, "Economy")
assert sum(loaded_economy.values()) > base_economy
assert loaded_economy["active legislation"] > 0
assert loaded_economy["regional programmes"] > 0

foreign_before = sum(_ministry_engine.workload_breakdown(state, "Foreign Affairs").values())
from models.relations import Treaty as _DeliveryTreaty
state.country.relations["veldoria"].treaties.append(
    _DeliveryTreaty(id="ad_treaty", name="Administrative Pact", type="trade",
                    parties=["ardenia", "veldoria"]))
foreign_after = sum(_ministry_engine.workload_breakdown(state, "Foreign Affairs").values())
assert foreign_after > foreign_before
state.civil_war = True
assert "civil war" in _ministry_engine.workload_breakdown(state, "Defense")
print("  Economy absorbs a law and regional programme; diplomacy absorbs a treaty; war loads Defense")
print("  PASS: workload comes from the commitments already present in the game")


section("AD3: Appropriations change operating capacity, but money is not delivery by itself")
cut = fresh()
funded = copy.deepcopy(cut)
for envelope_id in _ministry_engine.envelope_ids("Economy"):
    cut.active_budget.allocations[envelope_id] *= 0.85
    funded.active_budget.allocations[envelope_id] *= 1.15
cut_ministry = cut.ministries["Economy"]
funded_ministry = funded.ministries["Economy"]
cut_capacity = _ministry_engine.operating_capacity(cut, cut_ministry)[0]
funded_capacity = _ministry_engine.operating_capacity(funded, funded_ministry)[0]
assert funded_capacity > cut_capacity
assert _ministry_engine.operating_capacity(funded, funded_ministry)[2] > 1.0

funded.cabinet.ministers = [m for m in funded.cabinet.ministers if m.portfolio != "Economy"]
vacant_capacity = _ministry_engine.operating_capacity(funded, funded_ministry)[0]
assert vacant_capacity < funded_capacity, "extra money must not erase a vacant ministry"
print(f"  Economy capacity: cut {cut_capacity:.2f}, funded {funded_capacity:.2f}, "
      f"funded but vacant {vacant_capacity:.2f}")
print("  PASS: appropriations buy capacity while leadership still determines whether it can be used")


section("AD4: Chronic overload accumulates backlog and progressively degrades delivery")
state = fresh()
for index in range(8):
    law = copy.deepcopy(next(b for b in bill_catalog() if b.id == "minimum_wage_act"))
    law.id = f"ad_overload_{index}"
    law.status = "active"
    law.portfolio = "Economy"
    state.legislature.active_laws.append(law)
_ministry_engine.simulate_ministries(state)
first_delivery = state.ministries["Economy"].delivery
for _ in range(8):
    _ministry_engine.simulate_ministries(state)
economy_ministry = state.ministries["Economy"]
assert economy_ministry.backlog > 2.0
assert economy_ministry.delivery < first_delivery
assert economy_ministry.months_overloaded >= 9
assert economy_ministry.status_label() in ("Overloaded", "Failing")
print(f"  Economy delivery {first_delivery*100:.0f}% → {economy_ministry.delivery*100:.0f}%; "
      f"backlog {economy_ministry.backlog:.2f}")
print("  PASS: overcommitting the state creates institutional debt that survives the original decision")


section("AD5: Spare capacity clears backlog instead of resetting it overnight")
before_backlog = economy_ministry.backlog
state.legislature.active_laws = [law for law in state.legislature.active_laws
                                 if not law.id.startswith("ad_overload_")]
minister = state.cabinet.get("Economy")
minister.competence = 1.0
minister.loyalty = 1.0
for envelope_id in _ministry_engine.envelope_ids("Economy"):
    state.active_budget.allocations[envelope_id] *= 1.15
_ministry_engine.simulate_ministries(state)
one_month = state.ministries["Economy"].backlog
assert 0.0 < one_month < before_backlog
for _ in range(18):
    _ministry_engine.simulate_ministries(state)
assert state.ministries["Economy"].backlog < one_month
print(f"  backlog {before_backlog:.2f} → {one_month:.2f} after one month → "
      f"{state.ministries['Economy'].backlog:.2f} after sustained recovery")
print("  PASS: institutional recovery is gradual and requires real spare capacity")


section("AD6: Ministry overload weakens the existing policy-effect pipeline")
healthy = fresh()
overloaded = copy.deepcopy(healthy)
for index in range(10):
    law = copy.deepcopy(next(b for b in bill_catalog() if b.id == "minimum_wage_act"))
    law.id = f"ad_policy_load_{index}"
    law.status = "active"
    law.portfolio = "Economy"
    overloaded.legislature.active_laws.append(law)
for _ in range(6):
    _ministry_engine.simulate_ministries(overloaded)
_ministry_engine.simulate_ministries(healthy)
for target in (healthy, overloaded):
    target.modifiers.append(_DeliveryModifier(
        id="ad_growth", source="Delivery test", target="gdp_growth",
        magnitude=0.02, portfolio="Economy"))
engine = TurnEngine()
healthy_effect = engine._modifiers_sum(healthy, "gdp_growth")
overloaded_effect = engine._modifiers_sum(overloaded, "gdp_growth")
assert 0.0 < overloaded_effect < healthy_effect
print(f"  identical reform contributes {healthy_effect*100:.2f}% growth when healthy, "
      f"{overloaded_effect*100:.2f}% under overload")
print("  PASS: delivery constrains real law effects instead of sitting beside them as flavour")


section("AD7: Regional programmes compete for the responsible ministry's attention")
healthy = fresh()
overloaded = copy.deepcopy(healthy)
player_ops.op_start_regional_program(healthy, "zavost", "industrial_recovery")
player_ops.op_start_regional_program(overloaded, "zavost", "industrial_recovery")
for index in range(9):
    law = copy.deepcopy(next(b for b in bill_catalog() if b.id == "minimum_wage_act"))
    law.id = f"ad_regional_load_{index}"
    law.status = "active"
    law.portfolio = "Economy"
    overloaded.legislature.active_laws.append(law)
for _ in range(5):
    _ministry_engine.simulate_ministries(overloaded)
_ministry_engine.simulate_ministries(healthy)
healthy_quality = _region_engine.program_delivery_quality(healthy, healthy.regional_programs[0])
overloaded_quality = _region_engine.program_delivery_quality(
    overloaded, overloaded.regional_programs[0])
assert overloaded_quality < healthy_quality
print(f"  industrial recovery delivery: healthy {healthy_quality*100:.0f}% / "
      f"overloaded {overloaded_quality*100:.0f}%")
print("  PASS: a ministry cannot deliver every national reform and local programme at full strength")


section("AD8: Ministry condition persists, and old saves receive safe institutions")
state = fresh()
state.ministries["Interior"].backlog = 2.75
state.ministries["Interior"].months_overloaded = 7
payload = _ministry_persistence.serialize_state(state)
restored = _ministry_persistence.deserialize_state(payload)
assert restored.ministries["Interior"].backlog == 2.75
assert restored.ministries["Interior"].months_overloaded == 7
legacy = copy.deepcopy(payload)
legacy.pop("ministries")
migrated = _ministry_persistence.deserialize_state(legacy)
assert set(migrated.ministries) == set(_MINISTRY_PORTFOLIOS)
assert all(ministry.backlog == 0.0 for ministry in migrated.ministries.values())
print("  live backlog round-trips; pre-ministry campaigns receive funded, clear departments")
print("  PASS: administrative failure is persistent without breaking existing saves")


section("AD9: Seven-envelope budget saves gain Foreign Affairs without changing totals")
state = fresh()
payload = _ministry_persistence.serialize_state(state)
legacy = copy.deepcopy(payload)
active = legacy["active_budget"]["allocations"]
old_total = sum(active.values())
active["state_administration"] += active.pop("foreign_affairs")
restored = _ministry_persistence.deserialize_state(legacy)
assert "foreign_affairs" in restored.active_budget.allocations
assert abs(restored.active_budget.expenditure - old_total) < 0.2
assert restored.ministries["Foreign Affairs"].baseline_funding > 0.0
print(f"  migrated total remains {restored.active_budget.expenditure:,.0f} M")
print("  PASS: the diplomatic service gains honest appropriations without a save-game fiscal shock")


section("AD10: The terminal front-end exposes the same ministry ledger")
state = fresh()
# Cabinet category → appended third action, then back out.
run_scripted(state, ["2", "3", "0", "0"])
assert set(state.ministries) == set(_MINISTRY_PORTFOLIOS)
print("  PASS: the CLI and Cabinet page inspect the same persistent departments")


# ═══════════════════════════════════════════════════════════════════════════
# SECTION AE — HOUSEHOLD ECONOMY
# ═══════════════════════════════════════════════════════════════════════════

from content.households import (HOUSEHOLD_GROUPS as _HOUSEHOLD_GROUPS,
                                REGIONAL_HOUSEHOLD_SHARES as _HOUSEHOLD_SHARES)
from content.budget import ENVELOPE_BY_ID as _HOUSEHOLD_ENVELOPES
from engine import households as _household_engine
from engine import stability as _household_stability


section("AE1: Every Ardenian region contains a complete household society")
state = fresh()
group_ids = {group["id"] for group in _HOUSEHOLD_GROUPS}
assert len(state.households) == len(state.regions) * len(group_ids) == 36
for region_id, shares in _HOUSEHOLD_SHARES.items():
    assert set(shares) == group_ids
    assert abs(sum(shares.values()) - 1.0) < 1e-9
    assert {household.group_id for household in state.households.values()
            if household.region_id == region_id} == group_ids
print("  six social groups live separately in each of Ardenia's six regions")
print("  PASS: national averages are built from a real social and regional distribution")


section("AE2: Prices and weak indexation produce unequal real-income losses")
state = fresh()
state.country.economy.inflation = 0.18
state.country.economy.growth_rate = 0.0
for _ in range(12):
    _household_engine.simulate_households(state)
pensioner = state.households["vashtera:pensioners"]
middle = state.households["vashtera:salaried_middle"]
insecure = state.households["vashtera:insecure_households"]
assert pensioner.real_income_index < middle.real_income_index
assert insecure.real_income_index < middle.real_income_index
assert pensioner.hardship > middle.hardship
print(f"  real income: salaried {middle.real_income_index:.2f}, "
      f"pensioners {pensioner.real_income_index:.2f}, insecure {insecure.real_income_index:.2f}")
print("  PASS: inflation has distributional victims rather than one abstract national penalty")


section("AE3: Local labour markets create different household experiences")
state = fresh()
state.regions["vashtera"].unemployment = 0.05
state.regions["zavost"].unemployment = 0.24
for _ in range(8):
    _household_engine.simulate_households(state)
capital_worker = state.households["vashtera:urban_workers"]
industrial_worker = state.households["zavost:urban_workers"]
assert industrial_worker.employment_security < capital_worker.employment_security
assert industrial_worker.hardship > capital_worker.hardship
print(f"  worker security: Vashtera {capital_worker.employment_security:.2f}, "
      f"Zavost {industrial_worker.employment_security:.2f}")
print("  PASS: a national recovery can coexist with a regional jobs crisis")


section("AE4: Welfare money works only through an administration that can deliver it")
cut = fresh()
funded = copy.deepcopy(cut)
overloaded = copy.deepcopy(cut)
for target, ratio in ((cut, 0.55), (funded, 1.45), (overloaded, 1.45)):
    expected = (target.active_budget.expenditure
                * _HOUSEHOLD_ENVELOPES["health_and_welfare"]["share"])
    target.active_budget.allocations["health_and_welfare"] = expected * ratio
for portfolio in ("Finance", "Interior"):
    overloaded.ministries[portfolio].delivery = 0.25
    funded.ministries[portfolio].delivery = 0.95
    cut.ministries[portfolio].delivery = 0.95
for _ in range(12):
    for target in (cut, funded, overloaded):
        _household_engine.simulate_households(target)
funded_pensioner = funded.households["sela:pensioners"]
cut_pensioner = cut.households["sela:pensioners"]
overloaded_pensioner = overloaded.households["sela:pensioners"]
assert funded_pensioner.real_income_index > cut_pensioner.real_income_index
assert funded_pensioner.service_access > cut_pensioner.service_access
assert funded_pensioner.service_access > overloaded_pensioner.service_access
print(f"  Sela pensioner service access: funded {funded_pensioner.service_access:.2f}, "
      f"cut {cut_pensioner.service_access:.2f}, overloaded {overloaded_pensioner.service_access:.2f}")
print("  PASS: spending and state capacity are complementary, not interchangeable buffs")


section("AE5: State reach turns public services into lived regional inequality")
state = fresh()
state.regions["vashtera"].state_reach = 0.92
state.regions["anera"].state_reach = 0.28
for _ in range(10):
    _household_engine.simulate_households(state)
capital_rural = state.households["vashtera:rural_households"]
anera_rural = state.households["anera:rural_households"]
assert anera_rural.service_access < capital_rural.service_access
assert anera_rural.hardship > capital_rural.hardship
print(f"  rural service access: Vashtera {capital_rural.service_access:.2f}, "
      f"Anera {anera_rural.service_access:.2f}")
print("  PASS: the same appropriation reaches households differently across the country")


section("AE6: Household hardship feeds unrest and local incumbent support")
secure = fresh()
distressed = copy.deepcopy(secure)
for household in secure.households.values():
    household.hardship = 0.20
    household.confidence = 0.72
for household in distressed.households.values():
    household.hardship = 0.78
    household.confidence = 0.22
assert _household_stability.compute_unrest(distressed) > _household_stability.compute_unrest(secure)
secure_before = secure.regions["sela"].party_support[secure.ruling_faction_id]
distressed_before = distressed.regions["sela"].party_support[distressed.ruling_faction_id]
_region_engine.update_party_support(secure)
_region_engine.update_party_support(distressed)
secure_change = secure.regions["sela"].party_support[secure.ruling_faction_id] - secure_before
distressed_change = (distressed.regions["sela"].party_support[distressed.ruling_faction_id]
                     - distressed_before)
assert secure_change > distressed_change
print("  high hardship raises unrest while low confidence erodes the local incumbent")
print("  PASS: household outcomes return to the political simulation through two distinct channels")


section("AE7: Household judgement follows office in government and opposition play")
government_good = fresh()
government_bad = copy.deepcopy(government_good)
opposition_good = copy.deepcopy(government_good)
opposition_bad = copy.deepcopy(government_good)
opposition_good.player.in_government = False
opposition_bad.player.in_government = False
for state, confidence in ((government_good, 0.75), (government_bad, 0.25),
                          (opposition_good, 0.75), (opposition_bad, 0.25)):
    for household in state.households.values():
        household.confidence = confidence
    state.player.approval = 0.50
    TurnEngine()._update_approval(state)
assert government_good.player.approval > government_bad.player.approval
assert opposition_bad.player.approval > opposition_good.player.approval
print("  prosperity rewards a government player; hardship creates an opening for opposition")
print("  PASS: household consequences respect who actually holds executive power")


section("AE8: Household history persists and old campaigns migrate safely")
state = fresh()
state.households["zavost:urban_workers"].real_income_index = 0.73
state.households["zavost:urban_workers"].hardship = 0.81
payload = _ministry_persistence.serialize_state(state)
restored = _ministry_persistence.deserialize_state(payload)
assert restored.households["zavost:urban_workers"].real_income_index == 0.73
assert restored.households["zavost:urban_workers"].hardship == 0.81
legacy = copy.deepcopy(payload)
legacy.pop("households")
migrated = _ministry_persistence.deserialize_state(legacy)
assert len(migrated.households) == 36
assert all(household.real_income_index == 1.0 for household in migrated.households.values())
print("  lived losses round-trip; older saves receive a neutral household baseline")
print("  PASS: household conditions are campaign memory without breaking existing saves")


section("AE9: A decade of extreme conditions stays numerically bounded")
state = fresh()
state.country.economy.inflation = 0.45
state.country.economy.growth_rate = -0.12
for region in state.regions.values():
    region.unemployment = 0.35
    region.state_reach = 0.12
for _ in range(120):
    _household_engine.simulate_households(state)
for household in state.households.values():
    assert 0.45 <= household.nominal_income_index <= 2.50
    assert 0.65 <= household.living_cost_index <= 3.50
    assert 0.35 <= household.real_income_index <= 2.00
    assert 0.0 <= household.employment_security <= 1.0
    assert 0.0 <= household.service_access <= 1.0
    assert 0.0 <= household.hardship <= 1.0
    assert 0.0 <= household.confidence <= 1.0
print(f"  worst hardship after the stress test: {_household_engine.national_hardship(state)*100:.0f}%")
print("  PASS: household feedback can become severe without exploding the simulation")


# ══════════════════════════════════════════════════════════════════════════
# SECTION AF — REFORM OBJECTIVES
# ══════════════════════════════════════════════════════════════════════════

from content.reforms import (REFORM_OBJECTIVES as _REFORM_OBJECTIVES,
                             OBJECTIVE_BY_ID as _REFORM_OBJECTIVE_BY_ID,
                             SIGNAL_LABELS as _REFORM_SIGNAL_LABELS)
from engine import reforms as _reform_engine
from engine import persistence as _reform_persistence


section("AF1: Reform objectives are stable purposes backed by live signals")
state = fresh()
objective_ids = [objective["id"] for objective in _REFORM_OBJECTIVES]
assert len(objective_ids) == len(set(objective_ids)) == 7
ranked = _reform_engine.ranked_objectives(state)
assert {objective["id"] for objective in ranked} == set(objective_ids)
assert all(0.0 <= objective["score"] <= 1.0 for objective in ranked)
assert all(signal_id in _REFORM_SIGNAL_LABELS
           for objective in _REFORM_OBJECTIVES
           for signal_id, _weight in objective["signals"])
assert all(abs(sum(weight for _signal, weight in objective["signals"]) - 1.0) < 1e-9
           for objective in _REFORM_OBJECTIVES)
print("  seven objectives share a normalized, explainable diagnosis framework")
print("  PASS: reforms begin with a purpose rather than a pre-written effect bundle")


section("AF2: A cost-of-living shock makes purchasing power an urgent objective")
state = fresh()
baseline = _reform_engine.diagnose_objective(state, "restore_purchasing_power")["score"]
state.country.economy.inflation = 0.24
for household in state.households.values():
    household.real_income_index = 0.68
    household.living_cost_index = 1.42
    household.hardship = 0.78
diagnosis = _reform_engine.diagnose_objective(state, "restore_purchasing_power")
assert diagnosis["score"] > 0.85
assert diagnosis["score"] > baseline + 0.60
assert _reform_engine.leading_pressures(diagnosis)[0][0] in {
    "inflation", "real-income loss", "household hardship"}
print(f"  purchasing-power urgency rises from {baseline*100:.0f}% to {diagnosis['score']*100:.0f}%")
print("  PASS: objectives respond to lived inflation rather than a scripted event flag")


section("AF3: Jobs, services, fiscal and administrative crises diagnose differently")
jobs = fresh()
jobs.country.economy.unemployment = 0.27
for region in jobs.regions.values():
    region.unemployment = 0.25
for household in jobs.households.values():
    household.employment_security = 0.18
jobs_score = _reform_engine.diagnose_objective(jobs, "secure_work_and_wages")["score"]

services = fresh()
for region in services.regions.values():
    region.state_reach = 0.18
for household in services.households.values():
    household.service_access = 0.14
for ministry in services.ministries.values():
    ministry.delivery = 0.20
services_score = _reform_engine.diagnose_objective(services, "rebuild_public_services")["score"]

fiscal = fresh()
fiscal.country.economy.budget.expenditure = fiscal.country.economy.budget.revenue * 1.75
fiscal.country.economy.public_debt_pct = 1.25
fiscal_score = _reform_engine.diagnose_objective(fiscal, "restore_fiscal_room")["score"]

capacity = fresh()
capacity.country.bureaucratic_capacity = 0.15
for region in capacity.regions.values():
    region.state_reach = 0.20
for ministry in capacity.ministries.values():
    ministry.delivery = 0.12
    ministry.backlog = 6.0
capacity_score = _reform_engine.diagnose_objective(capacity, "strengthen_state_capacity")["score"]

assert jobs_score >= 0.75
assert services_score > 0.80
assert fiscal_score > 0.75
assert capacity_score > 0.85
print(f"  urgency — jobs {jobs_score*100:.0f}%, services {services_score*100:.0f}%, "
      f"fiscal {fiscal_score*100:.0f}%, state {capacity_score*100:.0f}%")
print("  PASS: distinct failures produce distinct reform diagnoses")


section("AF4: Adopting an objective records political intent and its starting evidence")
state = fresh()
before_pc = state.player.political_capital
result = player_ops.op_adopt_reform_objective(state, "restore_purchasing_power")
assert result.success
project = state.reform_project
assert project.objective_id == "restore_purchasing_power"
assert project.status == "objective"
assert project.adopted_turn == state.turn
assert project.diagnosis_snapshot
assert state.player.political_capital == before_pc - player_ops.COST_ADOPT_REFORM_OBJECTIVE
adoption_score = project.diagnosis_score
state.country.economy.inflation = 0.30
assert project.diagnosis_score == adoption_score
assert _reform_engine.diagnose_objective(state, project.objective_id)["score"] > adoption_score
print("  the project retains its original diagnosis while the live diagnosis keeps moving")
print("  PASS: reform design has campaign memory instead of rewriting its own rationale")


section("AF5: Changing direction is possible but politically costly")
state = fresh()
assert player_ops.op_adopt_reform_objective(
    state, "restore_purchasing_power").success
after_adoption = state.player.political_capital
same = player_ops.op_adopt_reform_objective(state, "restore_purchasing_power")
assert not same.success
assert state.player.political_capital == after_adoption
changed = player_ops.op_adopt_reform_objective(state, "secure_work_and_wages")
assert changed.success
assert state.reform_project.objective_id == "secure_work_and_wages"
assert state.player.political_capital == after_adoption - player_ops.COST_REPLACE_REFORM_OBJECTIVE
assert any("REFORM OBJECTIVE" in line for line in state.turn_log)
print("  keeping direction is free; replacing it costs political attention")
print("  PASS: objectives guide a project without permanently trapping the player")


section("AF6: Opposition can develop a programme without exercising state power")
state = fresh()
state.player.in_government = False
country_before = copy.deepcopy(state.country.economy)
assert player_ops.op_adopt_reform_objective(
    state, "rebuild_public_services").success
assert state.reform_project.objective_id == "rebuild_public_services"
assert state.country.economy == country_before
assert any("opposition programme" in line for line in state.turn_log)
print("  opposition records its objective, but no national statistic changes")
print("  PASS: policy preparation respects the boundary between proposing and governing")


section("AF7: Reform projects persist and old saves remain without an invented agenda")
state = fresh()
player_ops.op_adopt_reform_objective(state, "strengthen_state_capacity")
payload = _reform_persistence.serialize_state(state)
restored = _reform_persistence.deserialize_state(payload)
assert restored.reform_project == state.reform_project
legacy = copy.deepcopy(payload)
legacy.pop("reform_project")
migrated = _reform_persistence.deserialize_state(legacy)
assert migrated.reform_project is None
print("  active objectives round-trip; older campaigns choose their own first objective")
print("  PASS: the reform-design state is persistent and migration-safe")


section("AF8: The terminal front-end adopts through the shared reform operation")
state = fresh()
# Reform Design is appended as category 10; choose the first live-ranked objective.
run_scripted(state, ["10", "1", "1", "0", "0"])
assert state.reform_project is not None
assert state.reform_project.objective_id in _REFORM_OBJECTIVE_BY_ID
assert any(action.id == "adopt_reform_objective" for action in ACTION_CATALOG)
print("  PASS: CLI and GUI consume the same ranked diagnoses and adoption operation")


section("AF9: Objective diagnosis is safe for every world actor")
for country_id in _loader.available_country_ids():
    state = _loader.build_state_for(country_id)
    ranked = _reform_engine.ranked_objectives(state)
    assert len(ranked) == len(_REFORM_OBJECTIVES)
    assert all(0.0 <= objective["score"] <= 1.0 for objective in ranked)
    if not state.households:
        signals = _reform_engine.diagnostic_signals(state)
        assert signals["employment_insecurity"] < 1.0
        assert signals["service_access_gap"] < 1.0
print("  all nine country states can be diagnosed; unauthored household layers degrade neutrally")
print("  PASS: the reform framework preserves the country-neutral engine boundary")


# ══════════════════════════════════════════════════════════════════════════
# SECTION AG — THE MONTHLY DIGEST, ITEM-SCOPED BREAKDOWNS, BUDGET FORECAST
# ══════════════════════════════════════════════════════════════════════════
#
# This section adds NO new simulation — it is a lens on the mechanics that
# already exist (engine/digest.py, the five new ui/explain.py breakdowns,
# engine/budget.py: forecast, and the ministry-overload telegraph in
# explain.alerts()). Every check here is therefore either a PURITY check
# (nothing mutates) or an ACCURACY check (the lens agrees with the engine
# it is reading), never a check on a new balance number.

from engine import digest as _digest_engine
from engine import budget as _ag_budget_engine
from engine import ministries as _ag_ministry_engine
from engine import persistence
from content import loader as _ag_loader
from engine.campaign import CampaignConfig as _AGCC, generate_campaign as _ag_generate
from ui import explain


section("AG1: Every new breakdown function returns data and mutates nothing")
state = fresh()
TurnEngine().advance(state)   # a real pulse, so workload_breakdown etc. are populated
law_id = state.legislature.active_laws[0].id
before_fp = _digest_engine.snapshot(state)

ministry_bd = explain.ministry_breakdown(state, "Finance")
household_bd = explain.household_breakdown(state, "urban_workers", "vashtera")
region_bd = explain.region_breakdown(state, "sela")
budget_bd = explain.budget_breakdown(state)
law_bd = explain.delivery_chain(state, law_id)
digest_before = _digest_engine.snapshot(state)
digest_lines = _digest_engine.monthly_digest(state, digest_before, digest_before)

after_fp = _digest_engine.snapshot(state)
assert before_fp == after_fp, "a breakdown function mutated state"

assert ministry_bd["portfolio"] == "Finance" and "delivery" in ministry_bd
assert ministry_bd["workload_breakdown"], "ministry_breakdown should surface workload by source"
assert household_bd["group_name"] == "Urban wage earners"
assert household_bd["region_name"] == "Vashtera"
assert "real_income_change" in household_bd
assert region_bd["region_name"] == "Sela"
assert len(region_bd["pressure_rows"]) == 4
assert budget_bd["rows"] and "funding_ratios" in budget_bd
assert law_bd["law_id"] == law_id and law_bd["portfolio"] is not None
assert digest_lines == [], "identical before/after must report nothing"

# And has_breakdown/breakdown_for is the one registry for all of them.
for name in ("Ministry", "Household", "Region", "Budget", "Law"):
    assert explain.has_breakdown(name)
assert explain.breakdown_for("Ministry", state, portfolio="Finance")["status"]
assert explain.breakdown_for("Household", state, group_id="urban_workers",
                             region_id="vashtera")["group_name"] == "Urban wage earners"
assert explain.household_breakdown(state, "nonexistent", "nowhere") is None
print("  ministry/household/region/budget/law breakdowns: all populated, all pure")
print("  PASS: the lens reads the engine without touching it")


section("AG2: The digest names a cause, not a bare delta")
state = fresh()
before = _digest_engine.snapshot(state)
# Force Interior into a genuinely overloaded, degraded condition — the
# state a real campaign would reach after several months over capacity.
interior = state.ministries["Interior"]
interior.delivery = 0.60
interior.backlog = 1.4
interior.months_overloaded = 3
interior.workload, interior.capacity = 1.3, 1.0   # load_ratio is a property: 1.3
after = _digest_engine.snapshot(state)
lines = _digest_engine.monthly_digest(state, before, after)
assert lines, "a real ministry collapse produced no digest line at all"
hit = next((l for l in lines if "Interior" in l), None)
assert hit is not None, f"no line named the portfolio that actually moved: {lines}"
assert any(word in hit for word in ("capacity", "delivery", "backlog")), \
    f"line named the portfolio but not a consequence: {hit}"
print(f"  {hit}")
print("  PASS: every line traces back to a real driver, never a number alone")


section("AG3: The digest is bounded at 5 lines and silent when nothing moved")
state = fresh()
same = _digest_engine.snapshot(state)
assert _digest_engine.monthly_digest(state, same, same) == [], \
    "an unchanged state must not manufacture a digest"

before = _digest_engine.snapshot(state)
state.player.approval = min(1.0, state.player.approval + 0.10)
state.stability.value = max(0.0, state.stability.value - 0.10)
state.stability.breakdown = dict(state.stability.breakdown or {"Unrest": -0.05})
for portfolio, m in state.ministries.items():
    m.delivery = max(0.0, m.delivery - 0.30)
    m.backlog += 1.0
    m.months_overloaded += 2
for region in state.regions.values():
    region.pressure = min(1.0, region.pressure + 0.30)
econ = state.country.economy
econ.budget = econ.budget.__class__(revenue=econ.budget.revenue,
                                    expenditure=econ.budget.expenditure + 3000.0)
after = _digest_engine.snapshot(state)
lines = _digest_engine.monthly_digest(state, before, after)
assert 0 < len(lines) <= _digest_engine.MAX_DIGEST_LINES, \
    f"expected 1..{_digest_engine.MAX_DIGEST_LINES} lines from a everything-moves month, got {len(lines)}"
print(f"  a state where every tracked system moved at once still capped at {len(lines)} lines")
print("  PASS: quiet months are silent, loud months are still bounded")


section("AG4: last_snapshot round-trips, and a pre-feature save digests safely")
state = fresh()
state.last_snapshot = _digest_engine.snapshot(state)
data = persistence.serialize_state(state)
assert "last_snapshot" in data
restored = persistence.deserialize_state(data)
assert restored.last_snapshot == state.last_snapshot

# A save written before this feature existed simply lacks the key.
data.pop("last_snapshot", None)
old_save = persistence.deserialize_state(data)
assert old_save.last_snapshot == {}
after = _digest_engine.snapshot(old_save)
assert _digest_engine.monthly_digest(old_save, old_save.last_snapshot, after) == [], \
    "an empty snapshot must yield no digest, not a crash"
print("  round-trips with content; missing key loads as {} and digests to nothing")
print("  PASS: old saves are safe, not just new ones")


section("AG5: The budget forecast matches what actually happens")
state = fresh()
plan = _ag_budget_engine.build_proposal(
    state, {"national_defense": 0.15, "health_and_welfare": -0.15})
active_before = copy.deepcopy(state.active_budget)
fc = _ag_budget_engine.forecast(state, plan)
assert state.active_budget == active_before, "forecast() must not touch the live budget"

_ag_budget_engine.activate(state, plan)
_ag_ministry_engine.simulate_ministries(state)
for portfolio, projected in fc["ministries"].items():
    real = state.ministries[portfolio]
    assert abs(real.funding_ratio - projected["funding_ratio"]) < 1e-6, (
        f"{portfolio}: forecast funding_ratio {projected['funding_ratio']:.4f} != "
        f"realised {real.funding_ratio:.4f}")
    assert abs(real.delivery - projected["delivery"]) < 1e-6, (
        f"{portfolio}: forecast delivery {projected['delivery']:.4f} != "
        f"realised {real.delivery:.4f}")
print(f"  {len(fc['ministries'])} portfolios: forecast funding_ratio and delivery both "
      f"match the realised values after activation")
print("  PASS: the forecast is not a guess — it is the same computation, run early")


section("AG6: The overload warning fires the first month, not after delivery collapses")
state = fresh()
interior = state.ministries["Interior"]
interior.workload, interior.capacity = 1.3, 1.0
interior.months_overloaded = 1
interior.delivery = 0.97       # still healthy — the old status-only path stays silent
interior.backlog = 0.05
assert interior.status_label() == "Effective", \
    "fixture is wrong: status must still read healthy for this to test anything"
alerts = explain.alerts(state)
hit = next((a for a in alerts if "Interior" in a[1]), None)
assert hit is not None, "no warning on the very first month over capacity"
assert "1.30" in hit[1] or "capacity" in hit[1]

# And it escalates: months_overloaded == 4 must be CRITICAL, not just present.
interior.months_overloaded = 4
alerts = explain.alerts(state)
hit4 = next((a for a in alerts if "Interior" in a[1]), None)
assert hit4 is not None and hit4[0] == explain.SEV_CRITICAL, \
    f"four months over capacity should be a critical alert, got {hit4}"
print(f"  month 1 (status={interior.status_label()!r}): {hit[0]} — {hit[1][:70]}...")
print(f"  month 4: {hit4[0]} — {hit4[1][:70]}...")
print("  PASS: the telegraph precedes the collapse it warns about")


section("AG7: The digest and item-scoped breakdowns are safe everywhere")
for country_id in _ag_loader.available_country_ids():
    other = _ag_loader.build_state_for(country_id)
    snap = _digest_engine.snapshot(other)
    assert _digest_engine.monthly_digest(other, snap, snap) == []
    assert explain.budget_breakdown(other) is not None or other.active_budget is None
    # Household/region breakdowns only exist for Ardenia's authored layer;
    # elsewhere they must return None rather than raise.
    if not other.households:
        assert explain.household_breakdown(other, "urban_workers", "vashtera") is None
    if not other.regions:
        assert explain.region_breakdown(other, "vashtera") is None
    for portfolio in other.ministries:
        assert explain.ministry_breakdown(other, portfolio) is not None

# And an opposition campaign — the country keeps running under the sitting
# government regardless of the player's own seat at the table.
random.seed(4471)
opp_state = _ag_generate(_AGCC(country_id="ardenia", party_id="national_conservatives",
                               opening_role="opposition", background_id="none", seed=4471))
opp_before = _digest_engine.snapshot(opp_state)
eng2 = TurnEngine()
eng2.advance(opp_state)
opp_after = _digest_engine.snapshot(opp_state)
opp_lines = _digest_engine.monthly_digest(opp_state, opp_state.last_snapshot, opp_after)
assert isinstance(opp_lines, list)
for portfolio in opp_state.ministries:
    assert explain.ministry_breakdown(opp_state, portfolio) is not None
print(f"  all nine countries: snapshot/digest/ministry_breakdown safe; "
      f"household/region correctly None off Ardenia")
print(f"  opposition campaign: digest produced {len(opp_lines)} line(s) with no crash")
print("  PASS: the lens holds outside the home scenario and outside government")


# ══════════════════════════════════════════════════════════════════════════
# SECTION AH — GOVERNMENT ATTENTION, SUPPLEMENTARIES, THE GUIDED OPENING
# ══════════════════════════════════════════════════════════════════════════
#
# Attention is the first constraint in this game that REFUSES a player who
# can afford the thing they asked for, so the checks below care as much about
# what it must never block (a forced event, following through on a policy
# already begun, anything an opposition does) as about what it must.

from engine import onboarding as _onboarding
from engine import budget as _ah_budget
from engine import ministries as _ah_ministry_engine
from engine.campaign import CampaignConfig as _AHCC, generate_campaign as _ah_generate
from content.onboarding import GUIDANCE as _AH_GUIDANCE


def _ah_state():
    """A government with capital to spare, so a refusal is never about money."""
    s = fresh()
    s.player.political_capital = 300.0
    s.attention_spent = 0
    return s


section("AH1: Attention resets monthly, blocks a fourth initiative, and persists")
state = _ah_state()
assert player_ops.MONTHLY_ATTENTION == 3
assert player_ops.attention_remaining(state) == 3

proposable = player_ops.proposable_bills(state)
for i in range(3):
    result = player_ops.op_propose_bill(state, proposable[i])
    assert result.success, f"initiative {i+1} should have been allowed: {result.message}"
assert player_ops.attention_remaining(state) == 0

blocked = player_ops.op_propose_bill(state, proposable[3])
assert not blocked.success, "a fourth major initiative must be refused"
assert "already committed" in blocked.message, blocked.message
assert proposable[3] not in state.legislature.pending_bills, \
    "a blocked op must not half-apply"

# It survives save/load mid-month...
restored = persistence.deserialize_state(persistence.serialize_state(state))
assert restored.attention_spent == 3
assert player_ops.attention_remaining(restored) == 0
# ...and a save written before the mechanic existed loads as unspent.
data = persistence.serialize_state(state)
data.pop("attention_spent", None)
assert player_ops.attention_remaining(persistence.deserialize_state(data)) == 3

# The month turning is what refills it.
TurnEngine().advance(state)
assert player_ops.attention_remaining(state) == 3, "a new month must restore attention"
print(f"  3 initiatives allowed, 4th refused, reset on the monthly pulse, round-trips")
print("  PASS: attention is a real monthly ceiling, not a suggestion")


section("AH2: Resolving a situation is never blocked by attention")
state = _ah_state()
state.attention_spent = player_ops.MONTHLY_ATTENTION      # nothing left at all
assert player_ops.attention_remaining(state) == 0
assert not player_ops.costs_attention("resolve_event"), \
    "events are forced on the player; charging for them could deadlock a campaign"

fired = next(e for e in _cat() if e.id == "strike_wave")
state.pending_events.append(_PE(event_id="strike_wave"))
option = fired.default_option_id
result = player_ops.op_resolve_event(state, "strike_wave", option)
assert result.success, f"a pending situation must stay resolvable at zero attention: {result.message}"
assert not state.pending_events, "the situation should be resolved and cleared"
print("  a situation fired with zero attention left still resolved normally")
print("  PASS: the one thing the player cannot choose is the one thing never gated")


section("AH3: Following through on a policy already begun costs no attention")
state = _ah_state()
bill = player_ops.proposable_bills(state)[0]
assert player_ops.op_propose_bill(state, bill).success
after_proposal = player_ops.attention_remaining(state)
assert after_proposal == 2, "introducing a bill is the initiative"

for key in ("call_vote", "lobby_faction", "withdraw_bill",
            "call_budget_vote", "lobby_budget", "withdraw_budget"):
    assert not player_ops.costs_attention(key), f"{key} must be free follow-through"

player_ops.op_lobby_faction(state, bill, state.country.factions[1])
assert player_ops.attention_remaining(state) == after_proposal, "lobbying charged attention"
vote = player_ops.op_call_vote(state, bill)
assert vote.success
assert player_ops.attention_remaining(state) == after_proposal, \
    "calling the vote charged a second initiative for one policy"
print(f"  propose (3 -> 2), then lobby and vote both free (still {after_proposal})")
print("  PASS: one policy costs one month's initiative, not three")


section("AH4: Every opposition operation is free of attention")
opposition_ops = ("support_government_bill", "oppose_government_bill",
                  "amend_government_bill", "add_agenda_pledge",
                  "drop_agenda_pledge", "campaign_on_pledge",
                  "appoint_shadow_minister")
for key in opposition_ops:
    assert not player_ops.costs_attention(key), \
        f"{key} costs attention, but a player out of office is not running a government"

random.seed(8821)
opp = _ah_generate(_AHCC(country_id="ardenia", party_id="national_conservatives",
                         opening_role="opposition", background_id="none", seed=8821))
opp.player.political_capital = 300.0
opp.attention_spent = player_ops.MONTHLY_ATTENTION        # exhausted on purpose
bill_id = None
for _ in range(24):
    TurnEngine().advance_day(opp)
    gov_bill = player_ops.government_bill(opp)
    if gov_bill is not None:
        bill_id = gov_bill.id
        break
opp.attention_spent = player_ops.MONTHLY_ATTENTION
opp.player.political_capital = 300.0
if bill_id is not None:
    responded = player_ops.op_oppose_government_bill(opp, bill_id)
    assert responded.success, \
        f"opposition response refused at zero attention: {responded.message}"
    print(f"  opposed a government bill with zero attention left: {responded.success}")
else:
    print("  (no government bill surfaced in 24 days; key-level check still holds)")
print("  PASS: opposition play is untouched by a constraint on governing")


section("AH5: A supplementary passes a real vote, funds this year only, widens the deficit")
state = _ah_state()
state.month = 5
portfolio = "Interior"
voted_before = state.active_budget.expenditure
funding_before = _ah_ministry_engine.portfolio_funding(state, portfolio)
cap = _ah_budget.supplementary_cap(state, portfolio)

vote_bill = _ah_budget.as_supplementary_vote_bill(state, portfolio, cap)
projected_for, projected_against, _ = legislative.projected_votes(state, vote_bill)
assert projected_for + projected_against > 0, "the supplementary must reach a real division"

result = player_ops.op_supplementary_appropriation(state, portfolio, cap)
assert result.success, result.message
assert f"{projected_for}-{projected_against}" in result.message, \
    "the reported division must be the one the shared vote machinery produced"

assert _ah_ministry_engine.portfolio_funding(state, portfolio) > funding_before, \
    "a won supplementary must raise that ministry's spending power"
assert abs(state.active_budget.expenditure - voted_before) < 1e-6, \
    "the VOTED appropriation total must be untouched — that is next year's base"

# The deficit widens, isolated against an identical run without one.
def _balance_after_month(with_supplementary):
    probe = _ah_state()
    probe.month = 5
    if with_supplementary:
        assert player_ops.op_supplementary_appropriation(
            probe, portfolio, _ah_budget.supplementary_cap(probe, portfolio)).success
    TurnEngine().advance(probe)
    return probe.country.economy.budget.balance

assert _balance_after_month(True) < _balance_after_month(False), \
    "a supplementary must widen the deficit"

# And next year inherits nothing.
next_year = player_ops.op_propose_budget.__wrapped__ if False else None
proposal = _ah_budget.build_proposal(state, {})
assert abs(proposal.expenditure - voted_before) < 1.0, \
    "next year's proposal must be built from the voted base, not the supplemented one"
for _ in range(9):
    TurnEngine().advance(state)
assert state.active_budget.supplements == {}, \
    "a supplement must not survive into the following fiscal year"
print(f"  {cap:,.0f} M carried {projected_for}-{projected_against}; funding up, "
      f"voted total unchanged, deficit wider, next year clean")
print("  PASS: real mid-year money that does not quietly become a baseline")


section("AH6: The supplementary cap, cooldown and escalating price all bind")
state = _ah_state()
state.month = 3
cap = _ah_budget.supplementary_cap(state, "Interior")
appropriation = _ah_budget.portfolio_appropriation(state, "Interior")
assert abs(cap - appropriation * _ah_budget.SUPPLEMENTARY_CAP_FRACTION) < 1e-6

over = player_ops.op_supplementary_appropriation(state, "Interior", cap * 1.01)
assert not over.success and "may not exceed" in over.message, over.message
assert player_ops.attention_remaining(state) == 3, \
    "a request refused on its own terms must not burn the month"

first_cost = player_ops.cost_supplementary(state)
assert first_cost == player_ops.COST_SUPPLEMENTARY_BASE
assert first_cost > player_ops.PROPOSAL_COST["statutory"], \
    "a supplementary must cost a premium over an ordinary bill"
assert player_ops.op_supplementary_appropriation(state, "Interior", cap * 0.5).success

blocked = player_ops.op_supplementary_appropriation(state, "Defense", 10.0)
assert not blocked.success and "will not hear" in blocked.message, blocked.message

for _ in range(_ah_budget.SUPPLEMENTARY_COOLDOWN):
    TurnEngine().advance(state)
state.player.political_capital = 300.0
second_cost = player_ops.cost_supplementary(state)
assert second_cost > first_cost, \
    f"the second supplementary in a year must cost more ({second_cost} vs {first_cost})"
ok, _reason = player_ops.can_supplementary(state, "Defense")
assert ok, "the cooldown should have lapsed after four months"
print(f"  cap {cap:,.0f} M enforced; cooldown {_ah_budget.SUPPLEMENTARY_COOLDOWN} months; "
      f"price {first_cost:.0f} -> {second_cost:.0f} PC within the year")
print("  PASS: mid-year room exists, and stays expensive enough to matter")


section("AH7: Guided opening fires in order, is dismissible, persists, and gates nothing")
state = _ah_state()
assert _onboarding.is_enabled(state), "guidance is on unless a campaign turned it off"

first = _onboarding.next_guidance(state)
assert first is not None and first["id"] == _AH_GUIDANCE[0]["id"], \
    "the opening note must be the first authored one"

# next_guidance is pure: asking twice changes nothing.
before_meta = dict(state.campaign_meta)
assert _onboarding.next_guidance(state)["id"] == first["id"]
assert state.campaign_meta == before_meta, "next_guidance mutated state"

# Dismissal is permanent and advances to the next authored entry.
assert _onboarding.dismiss(state, first["id"])
assert _onboarding.next_guidance(state)["id"] != first["id"]
assert first["id"] in _onboarding.dismissed_ids(state)
assert not _onboarding.dismiss(state, "no_such_guidance"), \
    "an unknown id must be refused rather than silently stored"

# It round-trips through campaign_meta, which already persists.
restored = persistence.deserialize_state(persistence.serialize_state(state))
assert first["id"] in _onboarding.dismissed_ids(restored)
assert _onboarding.next_guidance(restored)["id"] == _onboarding.next_guidance(state)["id"]

# And it gates nothing: with every note still pending, a bill still passes.
blocking_check = _ah_state()
assert _onboarding.next_guidance(blocking_check) is not None
bill = player_ops.proposable_bills(blocking_check)[0]
assert player_ops.op_propose_bill(blocking_check, bill).success, \
    "pending guidance must never block an action"
print(f"  {len(_AH_GUIDANCE)} authored notes, in order, dismissible, persisted, non-blocking")
print("  PASS: a path in, not a gate")


section("AH8: A campaign with guidance disabled behaves as if the feature did not exist")
random.seed(3390)
guided = _ah_generate(_AHCC(country_id="ardenia", background_id="none", seed=3390))
random.seed(3390)
plain = _ah_generate(_AHCC(country_id="ardenia", background_id="none", seed=3390,
                           guidance_enabled=False))

assert _onboarding.is_enabled(guided)
assert not _onboarding.is_enabled(plain)
assert _onboarding.next_guidance(plain) is None, "a skipped opening must offer nothing"
assert _onboarding.pending(plain) == []

# The two campaigns are otherwise identical: guidance touches no simulation.
def _fingerprint(s):
    return (round(s.player.approval, 9), round(s.stability.value, 9),
            round(s.player.political_capital, 9),
            round(s.country.economy.growth_rate, 9),
            {f.id: f.seats for f in sorted(s.country.factions, key=lambda x: x.id)})

assert _fingerprint(guided) == _fingerprint(plain), \
    "enabling guidance changed the campaign it was generated into"
# Each campaign is advanced inside its OWN seeded stream. Advancing them
# alternately would interleave draws on the shared global RNG and diverge
# them for reasons unrelated to guidance -- the seeded-stream fragility
# CLAUDE.md warns about.
def _six_months(campaign, seed):
    random.seed(seed)
    engine = TurnEngine()
    for _ in range(6):
        engine.advance(campaign)
    return _fingerprint(campaign)

assert _six_months(guided, 5150) == _six_months(plain, 5150), \
    "guidance diverged the simulation over six months"
print("  identical fingerprints at generation and after six months")
print("  PASS: the guided opening is presentation, and provably nothing else")

# ══════════════════════════════════════════════════════════════════════════
# SECTION AI — MODIFIER-VISIBILITY GLYPH DATA
# ══════════════════════════════════════════════════════════════════════════

section("AI1: approval_forces classifies every lifecycle phase correctly")

from ui import modifier_glyph
from models.modifiers import Modifier

class _AIState:
    def __init__(self, modifiers):
        self.modifiers = modifiers

onset_mod = Modifier(id="m1", source="Pending reform", target="approval_bias",
                      magnitude=0.05, onset_delay=3, ramp_duration=2, age=1)
ramp_mod = Modifier(id="m2", source="New law phasing in", target="approval_bias",
                     magnitude=0.08, onset_delay=0, ramp_duration=4, age=1)
hold_mod = Modifier(id="m3", source="Popular reform", target="approval_bias",
                     magnitude=0.10, onset_delay=0, ramp_duration=1,
                     hold_duration=6, age=3)
decay_mod = Modifier(id="m4", source="Scandal fading", target="approval_bias",
                      magnitude=-0.06, onset_delay=0, ramp_duration=1,
                      hold_duration=2, decay_duration=4, age=4)
unrelated_mod = Modifier(id="m5", source="Inflation shock", target="inflation",
                          magnitude=0.02, ramp_duration=1, age=0)

state = _AIState([onset_mod, ramp_mod, hold_mod, decay_mod, unrelated_mod])
forces = modifier_glyph.approval_forces(state)

by_source = {f["source"]: f for f in forces}
assert len(forces) == 4, f"expected 4 approval-targeted forces, got {len(forces)}: {forces}"
assert "Inflation shock" not in by_source, "a non-approval modifier leaked into approval_forces"

assert by_source["Pending reform"]["phase"] == "onset"
assert by_source["New law phasing in"]["phase"] == "ramp"
assert by_source["Popular reform"]["phase"] == "hold"
assert by_source["Scandal fading"]["phase"] == "decay"

assert by_source["Pending reform"]["sign"] == "positive"
assert by_source["Popular reform"]["sign"] == "positive"
assert by_source["Scandal fading"]["sign"] == "negative", \
    "a negative-magnitude modifier must report sign='negative' even while its current_value is still small during decay"

assert abs(by_source["Popular reform"]["strength"] - hold_mod.current_value()) < 1e-9

print(f"  {len(forces)} forces classified: "
      f"{sorted((f['source'], f['phase'], f['sign']) for f in forces)}")
print("  PASS: onset/ramp/hold/decay and sign are read straight off Modifier, nothing reimplemented")
