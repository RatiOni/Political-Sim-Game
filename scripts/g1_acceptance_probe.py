"""Reproduce the automated evidence used by the Godot G1 gate."""

import argparse
import json
import os
import random
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from engine import persistence
from engine.campaign import default_config, generate_campaign
from engine.turn import TurnEngine
from godot_bridge.actions import dispatch
from godot_bridge.worker import Worker


def _canonical(state):
    return json.dumps(persistence.serialize_state(state), sort_keys=True,
                      separators=(",", ":"))


def _seed_is_process_stable():
    command = (
        "from engine.campaign import default_config; "
        "print(default_config().resolved_seed())"
    )
    seeds = [subprocess.check_output(
        [sys.executable, "-c", command], cwd=ROOT, text=True).strip()
        for _ in range(3)]
    passed = len(set(seeds)) == 1
    print(f"{'PASS' if passed else 'FAIL'}  default seed is process-stable: {seeds}")
    return passed


def _controlled_state_parity():
    random.seed(20260916)
    reference = generate_campaign(default_config())
    reference, _ = dispatch(reference, TurnEngine(), "adopt_objective", {
        "objective_id": "reduce_regional_inequality"})
    reference, reference_payload = dispatch(
        reference, TurnEngine(), "advance_month", {})

    random.seed(20260916)
    worker = Worker()
    worker.handle({"version": 1, "id": 1, "command": "new_campaign", "args": {}})
    worker.handle({"version": 1, "id": 2, "command": "adopt_objective", "args": {
        "objective_id": "reduce_regional_inequality"}})
    worker_payload = worker.handle({
        "version": 1, "id": 3, "command": "advance_month", "args": {}})

    passed = _canonical(reference) == _canonical(worker.state)
    print(f"{'PASS' if passed else 'FAIL'}  controlled Python/worker state parity")
    print("  reference:", reference.date_string(),
          reference.reform_project.objective_id,
          reference_payload["state"]["economy"],
          f"digest_lines={len(reference_payload['state']['digest'])}")
    print("  worker:   ", worker.state.date_string(),
          worker.state.reform_project.objective_id,
          worker_payload["payload"]["state"]["economy"],
          f"digest_lines={len(worker_payload['payload']['state']['digest'])}")
    return passed


def _invalid_inputs_do_not_mutate():
    state = generate_campaign(default_config())
    before = _canonical(state)
    unknown_rejected = False
    try:
        dispatch(state, TurnEngine(), "not_allowed", {})
    except ValueError:
        unknown_rejected = True
    unknown_safe = unknown_rejected and _canonical(state) == before
    print(f"{'PASS' if unknown_safe else 'FAIL'}  unknown command rejected without mutation")

    state = generate_campaign(default_config())
    before = _canonical(state)
    invalid_rejected = False
    try:
        dispatch(state, TurnEngine(), "advance_day", {"unexpected": True})
    except ValueError:
        invalid_rejected = True
    invalid_safe = invalid_rejected and _canonical(state) == before
    print(f"{'PASS' if invalid_safe else 'FAIL'}  invalid args rejected without mutation"
          f" (day={state.day_index})")
    return unknown_safe and invalid_safe


def _worker_lifecycle_and_performance():
    with tempfile.TemporaryDirectory() as user_data:
        environment = os.environ.copy()
        environment["ARDENIA_USER_DATA_DIR"] = user_data

        def start_worker():
            return subprocess.Popen(
                [sys.executable, "-u", "-m", "godot_bridge.worker"],
                cwd=ROOT, env=environment, stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                encoding="utf-8")

        process = start_worker()

        def exchange(target, request_id, command, args=None):
            request = {"version": 1, "id": request_id, "command": command,
                       "args": args or {}}
            started = time.perf_counter()
            target.stdin.write(json.dumps(request, separators=(",", ":")) + "\n")
            target.stdin.flush()
            response = json.loads(target.stdout.readline())
            return response, (time.perf_counter() - started) * 1000

        created, startup_ms = exchange(process, 1, "new_campaign")
        timings = [exchange(process, request_id, "snapshot")[1]
                   for request_id in range(2, 102)]
        exchange(process, 102, "adopt_objective", {
            "objective_id": "reduce_regional_inequality"})
        advanced, _ = exchange(process, 103, "advance_month")
        saved_state = advanced["payload"]["state"]
        saved_vashtera = next((row for row in saved_state["regions"]
                               if row["id"] == "vashtera"), None)
        exchange(process, 104, "save", {"slot": "g1_probe"})
        exchange(process, 105, "shutdown")
        process.stdin.close()
        first_exit = process.wait(timeout=15)
        first_errors = process.stderr.read()

        process = start_worker()
        loaded, _ = exchange(process, 1, "load", {"slot": "g1_probe"})
        exchange(process, 2, "shutdown")
        process.stdin.close()
        second_exit = process.wait(timeout=15)
        second_errors = process.stderr.read()
        loaded_state = loaded["payload"]["state"]
        loaded_vashtera = next((row for row in loaded_state["regions"]
                                if row["id"] == "vashtera"), None)
        readback_matches = all((
            loaded_state["date"] == saved_state["date"],
            loaded_state["reform"]["active"]["objective_id"]
            == "reduce_regional_inequality",
            loaded_state["economy"] == saved_state["economy"],
            saved_vashtera is not None,
            loaded_vashtera == saved_vashtera,
        ))
        lifecycle_passed = all((
            created["ok"], first_exit == 0, second_exit == 0,
            "Traceback" not in first_errors, "Traceback" not in second_errors,
            readback_matches,
        ))
        print(f"{'PASS' if lifecycle_passed else 'FAIL'}  fresh-worker save/load and clean shutdown")
        print("  loaded:", loaded_state["date"]["text"],
              loaded_state["reform"]["active"]["objective_id"],
              loaded_state["economy"], f"vashtera={loaded_vashtera}")
        print("  latency_ms:", f"startup={startup_ms:.3f}",
              f"snapshot_median={statistics.median(timings):.3f}",
              f"snapshot_max={max(timings):.3f}")
        return lifecycle_passed


def _capture_reference(output_directory):
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PySide6.QtGui import QFontDatabase
    from PySide6.QtWidgets import QApplication
    from ui.app import MainWindow

    output = Path(output_directory).resolve()
    output.mkdir(parents=True, exist_ok=True)
    app = QApplication.instance() or QApplication([])
    for font in (r"C:\Windows\Fonts\arial.ttf",
                 r"C:\Windows\Fonts\arialbd.ttf"):
        QFontDatabase.addApplicationFont(font)
    for width, height in ((1920, 1080), (1280, 720)):
        window = MainWindow(state=generate_campaign(default_config()))
        window.resize(width, height)
        window.show()
        app.processEvents()
        actual = window.size()
        path = output / f"qt-reference-{width}x{height}.png"
        if not window.grab().save(str(path)):
            raise RuntimeError(f"could not save {path}")
        print("CAPTURE", path, f"requested={width}x{height}",
              f"actual={actual.width()}x{actual.height()}")
        window.close()
        app.processEvents()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture-dir")
    args = parser.parse_args()
    results = [
        _seed_is_process_stable(),
        _controlled_state_parity(),
        _invalid_inputs_do_not_mutate(),
        _worker_lifecycle_and_performance(),
    ]
    if args.capture_dir:
        _capture_reference(args.capture_dir)
    passed = sum(results)
    print(f"G1 AUTOMATED PROBES: {passed}/{len(results)} conditions passed")
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
