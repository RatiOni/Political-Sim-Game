"""Freeze deterministic Python oracle fixtures for the native Godot port.

This is a development-only exporter.  The shipped Godot project reads the
committed JSON it produces and never launches this script or Python.
"""

from __future__ import annotations

import argparse
import inspect
import json
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
FIXTURE_DIR = ROOT / "godot" / "data" / "native" / "fixtures"
SEED = 424242
WINDOWS_ABSOLUTE_PATH = re.compile(r"^[A-Za-z]:[\\/]")

if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from content.bills import bill_catalog
from content.budget import BUDGET_ENVELOPES
from content.campaign_content import all_backgrounds, all_difficulties
from content.events import event_catalog
from content.households import HOUSEHOLD_GROUPS
from content.opening_programmes import OPENING_PROGRAMMES
from content.reforms import REFORM_OBJECTIVES
from content.regions import ARDENIA_REGION_PROFILES
from content.traits import all_traits
from engine import player_ops
from engine.campaign import CampaignConfig, generate_campaign
from engine.persistence import serialize_state


# These labels are copied from TurnEngine's authoritative monthly-pulse
# docstring.  The native implementation consumes this contract in later gates.
MONTHLY_PHASES = [
    "Advance time",
    "Apply a voted annual budget, or a continuing settlement, at January rollover",
    "Regenerate political capital",
    "If the player is in opposition, advance the domestic government's legislative programme (introduction → response window → vote)",
    "Recalculate ministry workload, capacity, delivery and backlog",
    "Update economy (workforce → sectors → fiscal baseline → organic inflation → modifiers onto headline stats → compound GDP)",
    "Player↔world relation drift + trade growth",
    "World simulation — other countries drift, relate, act (engine/worldsim.py)",
    "Process loans",
    "Faction loyalty drift",
    "Age grievances",
    "Update regional labour, state reach and pressure (engine/regions.py)",
    "Update household incomes, costs, security, services and confidence",
    "Recalculate approval, then government stability (engine/stability.py)",
    "Cabinet update and scandal check",
    "Protest check",
    "Forced confidence-vote check",
    "Civil-war pressure check (engine/crisis.py)",
    "National electoral support drift, regional electorate movement, then intra-party wing drift (engine/parties.py)",
    "Snap election check, then scheduled election check",
    "Track active law duration",
    "Dynamic event check (engine/events.py), then the rival's jibe watch (engine/roleplay.py)",
    "Age modifiers, then pending events — always last, so this turn's calculations used start-of-turn values",
]


def _canonical_json(value: dict) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False) + "\n"


def _assert_portable(value: Any) -> None:
    """Reject data that would make a committed fixture machine-specific."""
    if isinstance(value, dict):
        for key, item in value.items():
            _assert_portable(key)
            _assert_portable(item)
    elif isinstance(value, list):
        for item in value:
            _assert_portable(item)
    elif isinstance(value, str):
        assert str(ROOT) not in value, "fixture contains an absolute repository path"
        assert not value.startswith("/"), "fixture contains an absolute POSIX path"
        assert not WINDOWS_ABSOLUTE_PATH.match(value), "fixture contains an absolute Windows path"


def export_fixture(path: Path, value: dict) -> None:
    """Write one canonical fixture with stable keys, UTF-8, and one newline."""
    _assert_portable(value)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(_canonical_json(value), encoding="utf-8", newline="\n")


def _ids(items: list[Any]) -> list[str]:
    return sorted(item["id"] if isinstance(item, dict) else item.id for item in items)


def _catalogs() -> dict:
    return {
        "backgrounds": _ids(all_backgrounds()),
        "bills": _ids(bill_catalog()),
        "budget_envelopes": _ids(BUDGET_ENVELOPES),
        "difficulties": _ids(all_difficulties()),
        "events": _ids(event_catalog()),
        "household_groups": _ids(HOUSEHOLD_GROUPS),
        "opening_programmes": _ids(OPENING_PROGRAMMES),
        "reform_objectives": _ids(REFORM_OBJECTIVES),
        "regions": sorted(ARDENIA_REGION_PROFILES),
        "traits": _ids(all_traits()),
    }


def _public_operations() -> list[str]:
    return sorted(
        name for name, member in inspect.getmembers(player_ops, inspect.isfunction)
        if name.startswith("op_") and member.__module__ == player_ops.__name__
    )


def _source_commit() -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True,
        capture_output=True, check=True,
    )
    return result.stdout.strip()


def _campaign_fixture(opening_role: str) -> dict:
    config = CampaignConfig(
        country_id="ardenia",
        background_id="none",
        difficulty_id="normal",
        seed=SEED,
        opening_role=opening_role,
    )
    # Some legacy construction helpers still draw from Python's module-level
    # RNG.  Isolate and restore it here so fixture output remains reproducible
    # without changing the live engine's random-stream behaviour.
    previous_rng_state = random.getstate()
    try:
        random.seed(SEED)
        return serialize_state(generate_campaign(config))
    finally:
        random.setstate(previous_rng_state)


def _fixture_spec(filename: str, opening_role: str, state: dict) -> dict:
    return {
        "file": filename,
        "opening_role": opening_role,
        "player_in_government": state["player"]["in_government"],
        "seed": SEED,
        "state_keys": sorted(state),
    }


def export_all(output_dir: Path = FIXTURE_DIR) -> None:
    government = _campaign_fixture("government")
    opposition = _campaign_fixture("opposition")
    assert government["player"]["in_government"] is True
    assert opposition["player"]["in_government"] is False

    government_name = "campaign_government_seed_424242.json"
    opposition_name = "campaign_opposition_seed_424242.json"
    export_fixture(output_dir / government_name, government)
    export_fixture(output_dir / opposition_name, opposition)
    export_fixture(output_dir / "manifest.json", {
        "schema_version": 1,
        "source_commit": _source_commit(),
        "catalogs": _catalogs(),
        "operations": _public_operations(),
        "monthly_phases": MONTHLY_PHASES,
        "fixtures": {
            "campaign_government_seed_424242": _fixture_spec(
                government_name, "government", government),
            "campaign_opposition_seed_424242": _fixture_spec(
                opposition_name, "opposition", opposition),
        },
        "non_persistent_state_keys": {
            "turn_log": "ephemeral; cleared each turn and not serialized",
            "turn_news": "ephemeral; cleared each turn and not serialized",
        },
    })


def self_test() -> None:
    """Prove complete exported fixtures remain byte-stable and portable."""
    with tempfile.TemporaryDirectory() as first_dir, tempfile.TemporaryDirectory() as second_dir:
        first_root = Path(first_dir)
        second_root = Path(second_dir)
        export_all(first_root)
        export_all(second_root)
        first_paths = sorted(path.relative_to(first_root) for path in first_root.rglob("*.json"))
        second_paths = sorted(path.relative_to(second_root) for path in second_root.rglob("*.json"))
        assert first_paths == second_paths, "fixture file sets differ"
        for relative_path in first_paths:
            first_bytes = (first_root / relative_path).read_bytes()
            second_bytes = (second_root / relative_path).read_bytes()
            assert first_bytes == second_bytes, "canonical exports differ: %s" % relative_path
            assert first_bytes.endswith(b"\n"), "canonical export lacks trailing newline"
            assert str(ROOT).encode("utf-8") not in first_bytes, "repository path leaked"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--write", action="store_true",
                        help="write fixtures (the default when not self-testing)")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        print("oracle fixture exporter self-test: PASS")
        return
    export_all()
    print("oracle fixtures: written")


if __name__ == "__main__":
    main()
