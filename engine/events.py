"""
Dynamic events: a condition gates eligibility, a per-turn chance fires at
most ONE pending situation at a time, and resolution routes through
legislative.apply_effect_bundle (an EventOption's effects are a LawEffect).
Unaddressed situations auto-resolve to their default option after
EVENT_AUTO_RESOLVE_TURNS so the queue can never stall a playthrough.
"""

import random

from game_state import GameState
from models.events import PendingEvent, TARGET_MOST_HOSTILE, TARGET_COOLEST
from engine import legislative, diplomacy
from content.events import event_catalog

EVENT_AUTO_RESOLVE_TURNS = 3


def event_by_id(event_id: str):
    return next((e for e in event_catalog() if e.id == event_id), None)


def option_by_id(event, option_id: str):
    return next((o for o in event.options if o.id == option_id), None)


def available_options(state, event) -> list:
    """The options open to THIS player: an option's `requires` callable
    (background, ideology, ...) gates it. Defaults are never gated."""
    return [o for o in event.options if o.requires is None or o.requires(state)]


def available_to_player(state, event) -> bool:
    """Whether the player's current institutional role owns this decision."""
    if event is None:
        return False
    audience = getattr(event, "audience", "government")
    if audience == "any":
        return True
    if audience == "opposition":
        return not state.player.in_government
    return state.player.in_government


def prune_ineligible_pending(state: GameState):
    """Close stale decisions after an election or when loading an old save.

    Crucially, no default consequence is applied: the player no longer owns
    the ministry or treasury that the event expected them to command.
    """
    kept = []
    for pending in state.pending_events:
        event = event_by_id(pending.event_id)
        if available_to_player(state, event):
            kept.append(pending)
        elif event is not None:
            state.log(f'SITUATION CLOSED — "{event.title}" now belongs to the '
                      f'{"sitting government" if not state.player.in_government else "opposition"}.')
    state.pending_events = kept


def _fire(state: GameState, event):
    state.pending_events.append(PendingEvent(event_id=event.id))
    state.event_fire_history[event.id] = state.turn
    msg = f"SITUATION — {event.title}"
    state.log(msg)
    state.turn_news.append(("situation", {"title": event.title,
                                          "category": event.category}, msg))


def _pool_eligible(state: GameState, event) -> bool:
    """Random-pool gating: once/cooldown history, then the event's condition."""
    if not available_to_player(state, event):
        return False
    last = state.event_fire_history.get(event.id)
    if last is not None:
        if event.once:
            return False
        if state.turn - last < event.cooldown:
            return False
    return event.condition(state)


def check_for_events(state: GameState):
    """Called once per turn from TurnEngine.advance(). Fires at most one new
    situation (nothing while one is pending). Scheduled follow-ups — the
    delayed consequences of earlier choices — take priority over the random
    pool and bypass condition/cooldown gating; a follow-up that fails its
    chance roll simply never materialises."""
    prune_ineligible_pending(state)
    if state.pending_events:
        return

    due = [s for s in state.scheduled_events if s.get("due_turn", 0) <= state.turn]
    if due:
        state.scheduled_events = [s for s in state.scheduled_events
                                  if s.get("due_turn", 0) > state.turn]
        fired = False
        for i, sched in enumerate(due):
            event = event_by_id(sched.get("event_id"))
            if event is None:
                continue
            if not available_to_player(state, event):
                continue
            if not fired and random.random() < sched.get("chance", 1.0):
                _fire(state, event)
                fired = True
            elif not fired:
                pass  # failed its roll — consequence never materialises
            else:
                # Another follow-up was also due; try again next turn.
                sched["due_turn"] = state.turn + 1
                state.scheduled_events.append(sched)
        if fired:
            return

    for event in event_catalog():
        if not _pool_eligible(state, event):
            continue
        if random.random() < event.chance:
            _fire(state, event)
            return


def resolve_relation_target(state, country_id: str):
    """Map a relation_deltas key to a real country id (None = no valid target).

    Content can name a country outright, or use a sentinel that resolves to
    whoever actually triggered the situation in the country being played.
    """
    if country_id == TARGET_MOST_HOSTILE:
        hostile = [(cid, rel.score) for cid, rel in state.country.relations.items()
                   if rel.score < -0.3]
        if not hostile:
            return None
        return min(hostile, key=lambda kv: kv[1])[0]
    if country_id == TARGET_COOLEST:
        relations = [(cid, rel.score) for cid, rel in state.country.relations.items()]
        if not relations:
            return None
        return min(relations, key=lambda kv: kv[1])[0]
    return country_id


def _apply_option(state: GameState, event, option):
    legislative.apply_effect_bundle(state, option.effects, event.title, event.id, event.portfolio)
    for country_id, delta in option.relation_deltas.items():
        target = resolve_relation_target(state, country_id)
        if target is None:
            continue
        diplomacy.adjust_relation(state, target, delta, note=f"{event.title} ({state.date_string()}).")
    if option.on_apply is not None:
        option.on_apply(state)
    if option.follow_up:
        state.scheduled_events.append({
            "event_id": option.follow_up["event_id"],
            "due_turn": state.turn + int(option.follow_up.get("delay", 3)),
            "chance": float(option.follow_up.get("chance", 1.0)),
        })


def resolve_event(state: GameState, pending: PendingEvent, option) -> str:
    """
    Applies a chosen option's consequences and clears the pending entry.
    Returns a human-readable outcome message; callers (engine/player_ops.py)
    wrap this in an ActionResult, same convention as diplomacy/cabinet_ops.
    """
    event = event_by_id(pending.event_id)
    if not available_to_player(state, event):
        prune_ineligible_pending(state)
        return "That decision now belongs to another office. No effects were applied."
    _apply_option(state, event, option)
    state.pending_events = [p for p in state.pending_events if p.event_id != pending.event_id]
    msg = f"SITUATION RESOLVED — \"{event.title}\": {option.label}"
    state.log(msg)
    state.turn_news.append(("situation_resolved", {"title": event.title,
                                                   "option": option.label}, msg))
    return f"{option.label} — {option.description}"


def age_pending_events(state: GameState):
    """
    Ages every pending situation by one turn; anything left unresolved
    past EVENT_AUTO_RESOLVE_TURNS auto-applies its own default option
    rather than sitting in the queue forever.
    """
    prune_ineligible_pending(state)
    still_pending = []
    for pending in state.pending_events:
        pending.turns_pending += 1
        if pending.turns_pending > EVENT_AUTO_RESOLVE_TURNS:
            event = event_by_id(pending.event_id)
            option = option_by_id(event, event.default_option_id)
            _apply_option(state, event, option)
            msg = (f"SITUATION LAPSED — \"{event.title}\" went unaddressed; "
                   f"\"{option.label}\" happens by default.")
            state.log(msg)
            state.turn_news.append(("situation_lapsed", {"title": event.title,
                                                         "option": option.label}, msg))
        else:
            still_pending.append(pending)
    state.pending_events = still_pending
