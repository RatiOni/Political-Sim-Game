"""Bounded, JSON-ready read model for presentation clients."""

from engine import decision_queue, digest, political_calendar, reforms


def _decision_view(item):
    return {
        "id": item.id,
        "priority": item.priority,
        "tag": item.tag,
        "title": item.title,
        "detail": item.detail,
        "page": item.page,
        "authority": item.authority,
        "days_remaining": item.days_remaining,
        "due_text": item.due_text,
        "region_id": item.region_id,
    }


def _calendar_view(state, item):
    return {
        "id": item.id,
        "date": item.date.isoformat(),
        "days_from": item.days_from(state),
        "kind": item.kind,
        "tag": item.tag,
        "title": item.title,
        "detail": item.detail,
        "page": item.page,
        "authority": item.authority,
        "decision_id": item.decision_id,
    }


def _reform_view(state, reform_engine):
    project = state.reform_project
    active = None
    if project is not None:
        definition = reform_engine.OBJECTIVE_BY_ID.get(project.objective_id, {})
        live = reform_engine.diagnose_objective(state, project.objective_id)
        active = {
            "id": project.id,
            "objective_id": project.objective_id,
            "name": definition.get("name", project.objective_id),
            "status": project.status,
            "diagnosis_score": project.diagnosis_score,
            "current_score": live.get("score", 0.0),
        }

    objectives = []
    for objective in reform_engine.ranked_objectives(state):
        objectives.append({
            "id": objective["id"],
            "name": objective["name"],
            "portfolio": objective["portfolio"],
            "body": objective["body"],
            "score": objective["score"],
            "urgency": reform_engine.urgency_label(objective["score"]),
        })
    return {"active": active, "objectives": objectives}


def state_snapshot(state):
    """Return only the state needed by the Godot vertical slice."""
    economy = state.country.economy
    return {
        "date": {"text": state.date_string(), "year": state.year,
                 "month": state.month, "day": state.day,
                 "day_index": state.day_index, "turn": state.turn},
        "player": {"name": state.player.name, "title": state.player.title,
                   "party_id": state.player.faction_id,
                   "in_government": state.player.in_government,
                   "approval": state.player.approval,
                   "political_capital": state.player.political_capital},
        "headline": {"stability": state.stability.label(),
                     "attention_spent": state.attention_spent},
        "economy": {"growth": economy.growth_rate,
                    "unemployment": economy.unemployment,
                    "inflation": economy.inflation,
                    "debt": economy.public_debt_pct,
                    "revenue": economy.budget.revenue,
                    "expenditure": economy.budget.expenditure},
        "regions": [
            {"id": item.id, "pressure": item.pressure,
             "unemployment": item.unemployment,
             "state_reach": item.state_reach}
            for item in sorted(state.regions.values(), key=lambda row: row.id)
        ],
        "factions": [
            {"id": faction.id, "name": faction.name, "seats": faction.seats,
             "support": faction.support, "loyalty": faction.loyalty,
             "in_coalition": faction.in_coalition, "color": faction.color}
            for faction in state.country.factions
        ],
        "decisions": [_decision_view(item)
                      for item in decision_queue.build_queue(state)],
        "calendar": [_calendar_view(state, item)
                     for item in political_calendar.build_calendar(
                         state, horizon_days=365, max_items=12)],
        "digest": (digest.monthly_digest(
            state, state.last_snapshot, digest.snapshot(state))
            if state.last_snapshot else []),
        "reform": _reform_view(state, reforms),
        "dispatches": list(state.turn_log),
    }
