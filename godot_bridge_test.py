"""Focused checks for the Godot migration contract."""

import json

from engine import digest, persistence
from engine.campaign import default_config, generate_campaign


def _baseline_fixture():
    state = generate_campaign(default_config())
    return {
        "state": persistence.serialize_state(state),
        "digest": digest.snapshot(state),
    }


# Generated through public campaign, persistence, and digest APIs; never copied
# from a save file.
BASELINE_FIXTURE = _baseline_fixture()


def check(name, fn):
    fn()
    print(f"PASS  {name}")


def canonical_state_is_json_serializable():
    state = generate_campaign(default_config())
    payload = persistence.serialize_state(state)
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    assert json.loads(encoded)["country"]["id"] == "ardenia"
    assert payload["day"] == 1


if __name__ == "__main__":
    checks = [("canonical state is JSON serializable",
               canonical_state_is_json_serializable)]
    for label, test in checks:
        check(label, test)
    print(f"ALL {len(checks)} GODOT BRIDGE CHECKS PASSED")
