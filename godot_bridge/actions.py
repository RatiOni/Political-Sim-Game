"""Allow-listed adapters from bridge commands to authoritative engine APIs."""

from engine import persistence, player_ops
from engine.campaign import CampaignConfig, default_config, generate_campaign
from godot_bridge.presentation import state_snapshot


# The argument keys each command accepts. A request naming any other key is
# rejected before any state-mutating branch runs — this is the allow-list
# that closes the "advance_day accepted {'unexpected': true} and still
# advanced day_index" gap found during G1 acceptance.
ALLOWED_ARGS = {
    "new_campaign": frozenset({"seed"}),
    "load": frozenset({"slot"}),
    "list_saves": frozenset(),
    "snapshot": frozenset(),
    "advance_day": frozenset(),
    "advance_month": frozenset(),
    "adopt_objective": frozenset({"objective_id"}),
    "save": frozenset({"slot"}),
}


def _result(result):
    return {"success": bool(result.success), "message": result.message}


def _safe_slot(slot):
    if (not isinstance(slot, str) or not slot
            or any(not (char.isalnum() or char in "-_") for char in slot)):
        raise ValueError("slot must contain only letters, numbers, '-' or '_'")
    return slot


def _campaign_seed(args: dict):
    """The optional explicit seed for new_campaign, or None for the current
    per-launch-random default. Bool is rejected: it is a subclass of int in
    Python but never a meaningful seed value."""
    if "seed" not in args:
        return None
    seed = args["seed"]
    if isinstance(seed, bool) or not isinstance(seed, int):
        raise ValueError("seed must be an integer")
    return seed


def dispatch(state, engine, command: str, args: dict):
    """Run one known command and return the authoritative state plus payload."""
    if not isinstance(args, dict):
        raise ValueError("args must be an object")

    allowed = ALLOWED_ARGS.get(command)
    if allowed is None:
        raise ValueError("command is not implemented")
    unexpected = set(args) - allowed
    if unexpected:
        raise ValueError(f"unexpected argument(s): {sorted(unexpected)}")

    if command == "new_campaign":
        seed = _campaign_seed(args)
        if seed is None:
            state = generate_campaign(default_config())
        else:
            state = generate_campaign(CampaignConfig(
                country_id="ardenia", background_id="none",
                difficulty_id="normal", seed=seed))
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
