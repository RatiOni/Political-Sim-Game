"""Focused checks for the Godot migration contract."""

import json

from engine import digest, persistence
from engine.campaign import default_config, generate_campaign
from godot_bridge.protocol import parse_request, success, failure


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


def protocol_rejects_untrusted_shapes():
    valid = parse_request(json.dumps({
        "version": 1, "id": 4, "command": "snapshot", "args": {}}))
    assert valid["id"] == 4
    for bad in (
        "not json",
        json.dumps([]),
        json.dumps({"version": 2, "id": 1, "command": "snapshot", "args": {}}),
        json.dumps({"version": 1, "id": True, "command": "snapshot", "args": {}}),
        json.dumps({"version": 1, "id": 1, "command": "__import__", "args": {}}),
        json.dumps({"version": 1, "id": 1, "command": "snapshot", "args": []}),
    ):
        try:
            parse_request(bad)
        except ValueError:
            pass
        else:
            raise AssertionError(f"unsafe request accepted: {bad}")
    assert success(4, {"ready": True})["ok"] is True
    assert failure(4, "bad_request", "No")["ok"] is False


if __name__ == "__main__":
    checks = [("canonical state is JSON serializable",
               canonical_state_is_json_serializable),
              ("protocol rejects untrusted shapes",
               protocol_rejects_untrusted_shapes)]
    for label, test in checks:
        check(label, test)
    print(f"ALL {len(checks)} GODOT BRIDGE CHECKS PASSED")
