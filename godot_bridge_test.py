"""Focused checks for the Godot migration contract."""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from content.lore import REGIONS
from engine import digest, persistence
from engine.campaign import default_config, generate_campaign
from engine.turn import TurnEngine
from godot_bridge.actions import dispatch
from godot_bridge.export_map import export_map
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


def map_export_preserves_live_region_ids():
    state = generate_campaign(default_config())
    payload = export_map()
    exported = {item["id"] for item in payload["regions"]}
    assert set(payload) == {"outline", "regions", "labels", "cities", "routes",
                            "ports", "ceasefire_line", "neighbors"}
    assert exported == set(state.regions) == {region["id"] for region in REGIONS}
    assert len(exported) == 9
    assert all(len(item["points"]) >= 3 for item in payload["regions"])
    assert all(0 <= coordinate <= 100
               for item in payload["regions"]
               for point in item["points"] for coordinate in point)
    asset = Path(__file__).parent / "godot" / "data" / "ardenia_map.json"
    assert json.loads(asset.read_text(encoding="utf-8")) == payload


def protocol_rejects_untrusted_shapes():
    valid = parse_request(json.dumps({
        "version": 1, "id": 4, "command": "snapshot", "args": {}}))
    assert valid["id"] == 4
    for bad in (
        "not json",
        json.dumps([]),
        json.dumps({"version": 2, "id": 1, "command": "snapshot", "args": {}}),
        json.dumps({"version": 1, "id": True, "command": "snapshot", "args": {}}),
        json.dumps({"version": 1, "id": 1, "command": [], "args": {}}),
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


def worker_survives_an_invalid_command_shape():
    process = subprocess.Popen(
        [sys.executable, "-u", "-m", "godot_bridge.worker"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8")

    def exchange(request):
        process.stdin.write(json.dumps(request) + "\n")
        process.stdin.flush()
        line = process.stdout.readline()
        assert line, "worker exited without returning a response"
        return json.loads(line)

    try:
        created = exchange({
            "version": 1, "id": 10, "command": "new_campaign", "args": {}})
        assert created["ok"] is True

        rejected = exchange({
            "version": 1, "id": 11, "command": [], "args": {}})
        assert rejected["id"] == 11
        assert rejected["ok"] is False
        assert rejected["error"]["code"] == "bad_request"

        recovered = exchange({
            "version": 1, "id": 12, "command": "snapshot", "args": {}})
        assert recovered["ok"] is True
        assert recovered["payload"]["state"]["date"]["day_index"] == 0

        stopped = exchange({
            "version": 1, "id": 13, "command": "shutdown", "args": {}})
        assert stopped["ok"] is True
        process.stdin.close()
        assert process.wait(timeout=15) == 0
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


def worker_round_trip_preserves_saved_objective():
    with tempfile.TemporaryDirectory() as user_data:
        environment = os.environ.copy()
        environment["ARDENIA_USER_DATA_DIR"] = user_data
        process = subprocess.Popen(
            [sys.executable, "-u", "-m", "godot_bridge.worker"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", env=environment)

        def exchange(request_id, command, args=None):
            request = {"version": 1, "id": request_id,
                       "command": command, "args": args or {}}
            process.stdin.write(json.dumps(request, separators=(",", ":")) + "\n")
            process.stdin.flush()
            line = process.stdout.readline()
            assert line.endswith("\n"), "worker response was not one JSON line"
            response = json.loads(line)
            assert response["id"] == request_id
            assert response["version"] == 1
            return response

        try:
            assert exchange(20, "new_campaign")["ok"] is True
            initial = exchange(21, "snapshot")
            assert initial["payload"]["state"]["reform"]["active"] is None
            adopted = exchange(22, "adopt_objective", {
                "objective_id": "reduce_regional_inequality"})
            assert adopted["payload"]["result"]["success"] is True
            advanced = exchange(23, "advance_day")
            saved_day = advanced["payload"]["state"]["date"]["day_index"]
            assert exchange(24, "save", {"slot": "godot_slice"})["ok"] is True
            loaded = exchange(25, "load", {"slot": "godot_slice"})
            state = loaded["payload"]["state"]
            assert state["date"]["day_index"] == saved_day
            assert state["reform"]["active"]["objective_id"] == \
                "reduce_regional_inequality"
            assert exchange(26, "shutdown")["payload"] == {"shutdown": True}
            process.stdin.close()
            assert process.wait(timeout=15) == 0
            assert "Traceback" not in process.stderr.read()
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


def _spawn_worker():
    return subprocess.Popen(
        [sys.executable, "-u", "-m", "godot_bridge.worker"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8")


def _exchange(process, request_id, command, args=None):
    request = {"version": 1, "id": request_id,
               "command": command, "args": args or {}}
    process.stdin.write(json.dumps(request, separators=(",", ":")) + "\n")
    process.stdin.flush()
    line = process.stdout.readline()
    assert line, "worker exited without returning a response"
    response = json.loads(line)
    assert response["id"] == request_id
    return response


def _stop(process):
    try:
        if process.poll() is None:
            _exchange(process, 999, "shutdown")
            process.stdin.close()
            process.wait(timeout=15)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


def seeded_new_campaign_is_reproducible_across_fresh_workers():
    with tempfile.TemporaryDirectory() as user_data:
        environment = os.environ.copy()
        environment["ARDENIA_USER_DATA_DIR"] = user_data
        processes = [subprocess.Popen(
            [sys.executable, "-u", "-m", "godot_bridge.worker"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, encoding="utf-8",
            env=environment) for _ in range(2)]
        try:
            snapshots = []
            for process in processes:
                created = _exchange(process, 1, "new_campaign",
                                    {"seed": 424242})
                assert created["ok"] is True
                snapshot = _exchange(process, 2, "snapshot")
                assert snapshot["ok"] is True
                snapshots.append(snapshot["payload"])
            assert (json.dumps(snapshots[0], sort_keys=True)
                    == json.dumps(snapshots[1], sort_keys=True))
        finally:
            for process in processes:
                _stop(process)

        process = _spawn_worker()
        try:
            rejected_bool = _exchange(
                process, 1, "new_campaign", {"seed": True})
            assert rejected_bool["ok"] is False
            assert rejected_bool["error"]["code"] == "bad_request"
            rejected_str = _exchange(
                process, 2, "new_campaign", {"seed": "abc"})
            assert rejected_str["ok"] is False
            assert rejected_str["error"]["code"] == "bad_request"
        finally:
            _stop(process)


def unexpected_arguments_are_rejected_without_mutation():
    process = _spawn_worker()
    try:
        assert _exchange(process, 1, "new_campaign")["ok"] is True
        before = _exchange(process, 2, "snapshot")
        day_index = before["payload"]["state"]["date"]["day_index"]

        rejected_day = _exchange(
            process, 3, "advance_day", {"unexpected": True})
        assert rejected_day["ok"] is False
        assert rejected_day["error"]["code"] == "bad_request"

        rejected_objective = _exchange(process, 4, "adopt_objective", {
            "objective_id": "reduce_regional_inequality", "extra": 1})
        assert rejected_objective["ok"] is False
        assert rejected_objective["error"]["code"] == "bad_request"

        after = _exchange(process, 5, "snapshot")
        assert after["payload"]["state"]["date"]["day_index"] == day_index
        assert after["payload"]["state"]["reform"]["active"] is None
    finally:
        _stop(process)


if __name__ == "__main__":
    checks = [("canonical state is JSON serializable",
               canonical_state_is_json_serializable),
              ("map export preserves live region ids",
               map_export_preserves_live_region_ids),
              ("protocol rejects untrusted shapes",
               protocol_rejects_untrusted_shapes),
              ("snapshot is bounded and read only",
               snapshot_is_bounded_and_read_only),
              ("allowed commands use existing engine paths",
               allowed_commands_use_existing_engine_paths),
              ("worker requires an explicit campaign",
               worker_requires_an_explicit_campaign),
               ("worker survives an invalid command shape",
                worker_survives_an_invalid_command_shape),
               ("worker round trip preserves saved objective",
                worker_round_trip_preserves_saved_objective),
               ("seeded new_campaign is reproducible across fresh workers",
                seeded_new_campaign_is_reproducible_across_fresh_workers),
               ("unexpected arguments are rejected without mutation",
                unexpected_arguments_are_rejected_without_mutation)]
    for label, test in checks:
        check(label, test)
    print(f"ALL {len(checks)} GODOT BRIDGE CHECKS PASSED")
