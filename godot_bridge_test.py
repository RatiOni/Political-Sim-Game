"""Focused checks for the Godot migration contract."""

import json

from engine import digest, persistence
from engine.campaign import default_config, generate_campaign
from engine.turn import TurnEngine
from godot_bridge.actions import dispatch
from godot_bridge.presentation import state_snapshot
from godot_bridge.protocol import parse_request, success, failure
from godot_bridge.worker import Worker


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


def snapshot_is_bounded_and_read_only():
    state = generate_campaign(default_config())
    before = persistence.serialize_state(state)
    view = state_snapshot(state)
    assert set(view) == {"date", "player", "headline", "economy", "regions",
                         "factions", "decisions", "calendar", "digest",
                         "reform", "dispatches"}
    assert view["player"]["in_government"] is True
    assert view["regions"]
    assert persistence.serialize_state(state) == before


def allowed_commands_use_existing_engine_paths():
    state = generate_campaign(default_config())
    turn_engine = TurnEngine()
    state, result = dispatch(state, turn_engine, "adopt_objective",
                             {"objective_id": "reduce_regional_inequality"})
    assert result["result"]["success"] is True
    assert state.reform_project.objective_id == "reduce_regional_inequality"
    previous_day = state.day_index
    state, advanced = dispatch(state, turn_engine, "advance_day", {})
    assert state.day_index == previous_day + 1
    assert advanced["state"]["date"]["day_index"] == state.day_index
    try:
        dispatch(state, turn_engine, "python_eval", {"code": "1 + 1"})
    except ValueError:
        pass
    else:
        raise AssertionError("unknown action reached the simulation")


def worker_requires_an_explicit_campaign():
    worker = Worker()
    blocked = worker.handle({
        "version": 1, "id": 1, "command": "snapshot", "args": {}})
    assert blocked["error"]["code"] == "no_campaign"
    assert worker.state is None

    rejected = worker.handle({
        "version": 1, "id": 2, "command": "new_campaign",
        "args": {"country_id": "ardenia"}})
    assert rejected["error"]["code"] == "bad_request"
    assert worker.state is None

    created = worker.handle({
        "version": 1, "id": 3, "command": "new_campaign", "args": {}})
    assert created["ok"] is True
    assert worker.state.country.id == "ardenia"


if __name__ == "__main__":
    checks = [("canonical state is JSON serializable",
               canonical_state_is_json_serializable),
              ("protocol rejects untrusted shapes",
               protocol_rejects_untrusted_shapes),
              ("snapshot is bounded and read only",
               snapshot_is_bounded_and_read_only),
              ("allowed commands use existing engine paths",
               allowed_commands_use_existing_engine_paths),
              ("worker requires an explicit campaign",
               worker_requires_an_explicit_campaign)]
    for label, test in checks:
        check(label, test)
    print(f"ALL {len(checks)} GODOT BRIDGE CHECKS PASSED")
