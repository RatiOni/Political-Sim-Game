"""Versioned JSON-lines contract used by the local Godot client."""

import json


PROTOCOL_VERSION = 1
COMMANDS = frozenset({
    "new_campaign", "snapshot", "advance_day", "advance_month",
    "adopt_objective", "save", "load", "list_saves", "shutdown",
})


def parse_request(line: str) -> dict:
    try:
        request = json.loads(line)
    except json.JSONDecodeError as exc:
        raise ValueError("request is not valid JSON") from exc
    if not isinstance(request, dict):
        raise ValueError("request must be an object")
    if request.get("version") != PROTOCOL_VERSION:
        raise ValueError("unsupported protocol version")
    if type(request.get("id")) is not int or request["id"] < 0:
        raise ValueError("request id must be a non-negative integer")
    command = request.get("command")
    if not isinstance(command, str) or command not in COMMANDS:
        raise ValueError("command is not allowed")
    if not isinstance(request.get("args", {}), dict):
        raise ValueError("args must be an object")
    request.setdefault("args", {})
    return request


def success(request_id: int, payload: dict) -> dict:
    return {"version": PROTOCOL_VERSION, "id": request_id,
            "ok": True, "payload": payload}


def failure(request_id, code: str, message: str) -> dict:
    return {"version": PROTOCOL_VERSION, "id": request_id,
            "ok": False, "error": {"code": code, "message": message}}
