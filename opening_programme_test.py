"""Focused checks for the first-ninety-day campaign programme."""

import copy
import random

from content.bills import bill_catalog
from engine import (cabinet_ops, decision_queue, opening_programme,
                    opposition, persistence, player_ops, political_calendar)
from engine.campaign import CampaignConfig, generate_campaign
from models.cabinet import CORE_PORTFOLIOS


def check(name, fn):
    fn()
    print(f"PASS  {name}")


def government_selection_is_role_specific_and_single_use():
    state = generate_campaign(CampaignConfig(
        country_id="ardenia", opening_role="government",
        background_id="none", seed=1201))
    candidates = opening_programme.candidates(state)
    assert len(candidates) == 3
    assert {item["role"] for item in candidates} == {"government"}
    wrong = player_ops.op_select_opening_programme(
        state, "opposition_government_in_waiting")
    assert not wrong.success
    chosen = player_ops.op_select_opening_programme(
        state, "government_jobs_regions")
    assert chosen.success
    assert not opening_programme.candidates(state)
    assert not player_ops.op_select_opening_programme(
        state, "government_working_state").success


def government_progress_comes_from_real_actions():
    state = generate_campaign(CampaignConfig(
        country_id="ardenia", opening_role="government",
        background_id="none", seed=1202))
    assert player_ops.op_select_opening_programme(
        state, "government_jobs_regions").success
    assert player_ops.op_adopt_reform_objective(
        state, "secure_work_and_wages").success

    programme_target = None
    for region_id in state.regions:
        available = dict(player_ops.regional_programs_for(state, region_id))
        if "public_works" in available:
            programme_target = region_id
            break
    assert programme_target is not None
    assert player_ops.op_start_regional_program(
        state, programme_target, "public_works").success

    bill = next(item for item in bill_catalog()
                if item.id == "infrastructure_investment_act")
    assert player_ops.op_propose_bill(state, bill).success
    report = opening_programme.progress(state)
    assert report["status"] == "complete"
    assert report["completed"] == report["total"] == 3
    assert not any(item.id.startswith("opening_programme:")
                   for item in decision_queue.build_queue(state))


def opposition_progress_uses_party_authority():
    random.seed(1203)
    state = generate_campaign(CampaignConfig(
        country_id="ardenia", party_id="national_conservatives",
        opening_role="opposition", background_id="none", seed=1203))
    candidates = opening_programme.candidates(state)
    assert len(candidates) == 3
    assert {item["role"] for item in candidates} == {"opposition"}
    assert player_ops.op_select_opening_programme(
        state, "opposition_government_in_waiting").success

    bill = opposition.pledge_candidates(state)[0]
    assert player_ops.op_add_agenda_pledge(state, bill.id).success
    portfolio = (bill.portfolio if bill.portfolio in CORE_PORTFOLIOS else "Economy")
    minister = cabinet_ops.shadow_shortlist(state, portfolio)[0]
    assert player_ops.op_appoint_shadow_minister(
        state, portfolio, minister).success
    assert player_ops.op_campaign_on_pledge(state, bill.id).success
    report = opening_programme.progress(state)
    assert report["status"] == "complete"
    assert report["completed"] == 3


def programme_round_trips_without_new_persistence_shape():
    state = generate_campaign(CampaignConfig(
        country_id="ardenia", opening_role="government",
        background_id="none", seed=1204))
    assert player_ops.op_select_opening_programme(
        state, "government_household_settlement").success
    assert player_ops.op_address_nation(state, "visionary").success
    restored = persistence.deserialize_state(persistence.serialize_state(state))
    assert restored.campaign_meta["opening_programme"] == \
        state.campaign_meta["opening_programme"]
    report = opening_programme.progress(restored)
    completed = {task["id"] for task, done in report["tasks"] if done}
    assert "household_address" in completed


def queue_and_calendar_share_the_public_deadline():
    state = generate_campaign(CampaignConfig(
        country_id="ardenia", opening_role="government",
        background_id="none", seed=1205))
    before = copy.deepcopy(state)
    selection = next(item for item in decision_queue.build_queue(state)
                     if item.id == "select_opening_programme")
    assert selection.priority == decision_queue.PRIORITY_REQUIRED
    assert selection.days_remaining == opening_programme.SELECTION_DEADLINE_DAY
    assert state == before
    calendar = political_calendar.build_calendar(state)
    assert any(item.decision_id == selection.id for item in calendar)

    assert player_ops.op_select_opening_programme(
        state, "government_working_state").success
    task = next(item for item in decision_queue.build_queue(state)
                if item.id.startswith("opening_programme:"))
    assert task.days_remaining == opening_programme.PROGRAMME_DEADLINE_DAY
    assert task.authority == "government"


def expired_and_superseded_programmes_stop_nagging():
    state = generate_campaign(CampaignConfig(
        country_id="ardenia", opening_role="government",
        background_id="none", seed=1206))
    state.day_index = 91
    assert opening_programme.progress(state)["status"] == "missed"
    assert not opening_programme.candidates(state)
    assert not any(item.id == "select_opening_programme"
                   for item in decision_queue.build_queue(state))

    state = generate_campaign(CampaignConfig(
        country_id="ardenia", opening_role="government",
        background_id="none", seed=1207))
    assert player_ops.op_select_opening_programme(
        state, "government_household_settlement").success
    state.player.in_government = False
    assert opening_programme.progress(state)["status"] == "superseded"
    assert not any(item.id.startswith("opening_programme:")
                   for item in decision_queue.build_queue(state))


if __name__ == "__main__":
    checks = [
        ("government programmes are role-specific and chosen once",
         government_selection_is_role_specific_and_single_use),
        ("government achievements come from ordinary simulation actions",
         government_progress_comes_from_real_actions),
        ("opposition achievements use party and shadow-cabinet authority",
         opposition_progress_uses_party_authority),
        ("programme metadata survives the existing persistence path",
         programme_round_trips_without_new_persistence_shape),
        ("the queue and calendar share programme deadlines",
         queue_and_calendar_share_the_public_deadline),
        ("expired or superseded programmes stop generating work",
         expired_and_superseded_programmes_stop_nagging),
    ]
    for label, test in checks:
        check(label, test)
    print(f"ALL {len(checks)} OPENING PROGRAMME CHECKS PASSED")
