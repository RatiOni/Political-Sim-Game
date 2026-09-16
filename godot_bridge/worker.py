"""One-state JSON-lines worker used by the local Godot client."""

import json
import sys
import traceback

from engine.turn import TurnEngine
from godot_bridge.actions import dispatch
from godot_bridge.protocol import failure, parse_request, success


STATE_COMMANDS = frozenset({
    "snapshot", "advance_day", "advance_month", "adopt_objective", "save",
})


class Worker:
    def __init__(self):
        self.state = None
        self.engine = TurnEngine()

    def handle(self, request: dict) -> dict:
        request_id = request.get("id")
        command = request.get("command")
        if command == "shutdown":
            return success(request_id, {"shutdown": True})
        if self.state is None and command in STATE_COMMANDS:
            return failure(request_id, "no_campaign", "No campaign is active.")
        try:
            self.state, payload = dispatch(
                self.state, self.engine, command, request.get("args", {}))
            return success(request_id, payload)
        except ValueError as exc:
            return failure(request_id, "bad_request", str(exc))
        except Exception:
            traceback.print_exc(file=sys.stderr)
            return failure(request_id, "internal_error", "The bridge request failed.")


def _request_id(line):
    try:
        candidate = json.loads(line)
    except Exception:
        return None
    return candidate.get("id") if isinstance(candidate, dict) else None


def main() -> int:
    worker = Worker()
    print("Ardenia bridge worker started.", file=sys.stderr, flush=True)
    for line in sys.stdin:
        try:
            request = parse_request(line)
            response = worker.handle(request)
        except ValueError as exc:
            response = failure(_request_id(line), "bad_request", str(exc))
            request = None
        except Exception:
            traceback.print_exc(file=sys.stderr)
            response = failure(
                _request_id(line), "internal_error", "The bridge request failed.")
            request = None

        print(json.dumps(response, separators=(",", ":")), flush=True)
        if request is not None and request["command"] == "shutdown":
            break
    print("Ardenia bridge worker stopped.", file=sys.stderr, flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
