"""Allow-listed adapters from bridge commands to authoritative engine APIs."""

from engine import persistence, player_ops
from engine.campaign import default_config, generate_campaign
from godot_bridge.presentation import state_snapshot


def _result(result):
    return {"success": bool(result.success), "message": result.message}


def _safe_slot(slot):
    if (not isinstance(slot, str) or not slot
            or any(not (char.isalnum() or char in "-_") for char in slot)):
        raise ValueError("slot must contain only letters, numbers, '-' or '_'")
    return slot


def dispatch(state, engine, command: str, args: dict):
    """Run one known command and return the authoritative state plus payload."""
    if not isinstance(args, dict):
        raise ValueError("args must be an object")

    if command == "new_campaign":
        if args:
            raise ValueError("new_campaign does not accept arguments")
        state = generate_campaign(default_config())
    elif command == "load":
        state = persistence.load_campaign(slot=_safe_slot(args.get("slot")))
    elif command == "list_saves":
        return state, {"saves": persistence.list_saves()}
    elif state is None:
        raise ValueError("no campaign is active")
    elif command == "snapshot":
        pass
    elif command == "advance_day":
        engine.advance_day(state)
    elif command == "advance_month":
        engine.advance(state)
    elif command == "adopt_objective":
        objective_id = args.get("objective_id")
        if not isinstance(objective_id, str):
            raise ValueError("objective_id must be a string")
        result = player_ops.op_adopt_reform_objective(state, objective_id)
        return state, {"result": _result(result), "state": state_snapshot(state)}
    elif command == "save":
        persistence.save_campaign(state, slot=_safe_slot(args.get("slot")))
    else:
        raise ValueError("command is not implemented")
    return state, {"state": state_snapshot(state)}
