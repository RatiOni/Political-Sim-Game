"""Focused household coverage for Ardenia's nine-region expansion."""

from content.households import HOUSEHOLD_GROUPS, REGIONAL_HOUSEHOLD_SHARES
from content.loader import build_state_for
from engine import households


EXPECTED_REGION_IDS = {
    "anera", "darev", "karsen", "kelvet", "orvena", "sela", "vashtera",
    "vetrenka", "zavost",
}


def test_household_distributions_cover_every_region():
    assert set(REGIONAL_HOUSEHOLD_SHARES) == EXPECTED_REGION_IDS
    group_ids = {group["id"] for group in HOUSEHOLD_GROUPS}
    for region_id, shares in REGIONAL_HOUSEHOLD_SHARES.items():
        assert set(shares) == group_ids, region_id
        assert abs(sum(shares.values()) - 1.0) < 1e-9, region_id


def test_household_repair_adds_only_missing_records():
    state = build_state_for("ardenia")
    original = state.households["vashtera:urban_workers"]
    original.real_income_index = 0.731
    state.households.pop("darev:urban_workers")

    households.ensure_households(state)

    assert state.households["vashtera:urban_workers"].real_income_index == 0.731
    assert "darev:urban_workers" in state.households
    assert len(state.households) == len(EXPECTED_REGION_IDS) * len(HOUSEHOLD_GROUPS)
    count = len(state.households)
    households.ensure_households(state)
    assert len(state.households) == count


if __name__ == "__main__":
    test_household_distributions_cover_every_region()
    print("PASS: household distributions cover every region")
    test_household_repair_adds_only_missing_records()
    print("PASS: household repair adds only missing records")
