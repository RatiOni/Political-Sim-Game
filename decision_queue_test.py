"""Focused smoke checks for the shared decision-queue lens.

The repository's main smoke suite is deliberately large and sequential.  This
small companion keeps queue development fast while still exercising real
campaign state, government/opposition authority, deadlines, and purity.
"""

import copy
import random

from content.bills import bill_catalog
from content.loader import build_state_for
from engine import budget, decision_queue, player_ops
from engine.campaign import CampaignConfig, generate_campaign
from engine.turn import TurnEngine
from models.events import PendingEvent


def check(name, fn):
    fn()
    print(f"PASS  {name}")


def government_queue_is_pure_and_ordered():
    state = build_state_for("ardenia")
    before = copy.deepcopy(state)
    items = decision_queue.build_queue(state)
    assert state == before, "building the queue mutated GameState"
    assert items == sorted(items, key=lambda item: item.sort_key())
    assert len({item.id for item in items}) == len(items)
    assert any(item.id == "choose_reform_objective" for item in items)
    assert not any(item.id == "cabinet_vacancies" for item in items)


def pending_situation_is_required_and_deadlined():
    state = build_state_for("ardenia")
    event_id = "labour_unrest_spreads"
    state.pending_events = [PendingEvent(event_id, turns_pending=2)]
    item = next(item for item in decision_queue.build_queue(state)
                if item.id == f"situation:{event_id}")
    assert item.priority == decision_queue.PRIORITY_REQUIRED
    assert item.authority == "government"
    assert item.days_remaining == 60
    assert "Defaults" in item.due_text


def player_bill_routes_to_policies():
    state = build_state_for("ardenia")
    bill = next(b for b in bill_catalog()
                if b.id not in {law.id for law in state.legislature.active_laws})
    bill.status = "proposed"
    bill.proposed_by = "player"
    state.legislature.pending_bills.append(bill)
    item = next(item for item in decision_queue.build_queue(state)
                if item.id == f"player_bill:{bill.id}")
    assert item.page == "Policies"
    assert item.authority == "government"
    assert item.priority == decision_queue.PRIORITY_PLANNED


def budget_deadline_escalates():
    state = build_state_for("ardenia")
    state.month = 12
    state.day = 15
    plan = budget.build_proposal(state, {})
    plan.status = "proposed"
    state.pending_budget = plan
    item = next(item for item in decision_queue.build_queue(state)
                if item.id == f"budget_vote:{plan.year}")
    assert item.priority == decision_queue.PRIORITY_REQUIRED
    assert 0 <= item.days_remaining <= 31
    assert item.page == "Policies"


def opposition_response_appears_then_clears():
    random.seed(991)
    state = generate_campaign(CampaignConfig(
        country_id="ardenia",
        party_id="national_conservatives",
        opening_role="opposition",
        background_id="none",
        seed=991,
    ))
    TurnEngine().advance(state)
    bill = player_ops.government_bill(state)
    assert bill is not None
    item_id = f"government_bill_response:{bill.id}"
    items = decision_queue.build_queue(state)
    response = next(item for item in items if item.id == item_id)
    assert response.authority == "opposition"
    assert response.page == "Policies"
    assert response.days_remaining <= 21
    assert any(item.id == "opposition_platform" for item in items)
    assert any(item.id == "shadow_cabinet_vacancies" for item in items)

    result = player_ops.op_oppose_government_bill(state, bill.id)
    assert result.success
    assert not any(item.id == item_id for item in decision_queue.build_queue(state))


def regional_pressure_routes_without_state_change():
    state = build_state_for("ardenia")
    region = state.regions["sela"]
    region.pressure = 0.91
    before = copy.deepcopy(state)
    item = next(item for item in decision_queue.build_queue(state)
                if item.id == "regional_pressure:sela")
    assert item.priority == decision_queue.PRIORITY_URGENT
    assert item.region_id == "sela"
    assert state == before


def optional_filter_keeps_actionable_work():
    state = generate_campaign(CampaignConfig(
        country_id="ardenia",
        party_id="workers_front",
        opening_role="opposition",
        background_id="none",
        seed=992,
    ))
    all_items = decision_queue.build_queue(state)
    compact = decision_queue.build_queue(state, include_optional=False)
    assert any(item.priority == decision_queue.PRIORITY_OPTIONAL for item in all_items)
    assert not any(item.priority in (decision_queue.PRIORITY_OPTIONAL,
                                     decision_queue.PRIORITY_INFORMATION)
                   for item in compact)
    assert any(item.priority == decision_queue.PRIORITY_PLANNED for item in compact)


if __name__ == "__main__":
    checks = [
        ("government queue is pure, unique, and ordered",
         government_queue_is_pure_and_ordered),
        ("pending situations are required decisions with a deadline",
         pending_situation_is_required_and_deadlined),
        ("player legislation routes to the Policies page",
         player_bill_routes_to_policies),
        ("the annual budget escalates as January approaches",
         budget_deadline_escalates),
        ("opposition bill responses appear and clear after a stance",
         opposition_response_appears_then_clears),
        ("regional pressure routes to the map without mutation",
         regional_pressure_routes_without_state_change),
        ("the compact filter removes optional work but keeps plans",
         optional_filter_keeps_actionable_work),
    ]
    for label, test in checks:
        check(label, test)
    print(f"ALL {len(checks)} DECISION QUEUE CHECKS PASSED")
