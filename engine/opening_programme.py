"""First-ninety-day programme selection and progress.

The programme never applies effects.  It recognises ordinary player actions
and live state, presenting a short role-appropriate route through systems that
already own all political and economic consequences.
"""

from content.opening_programmes import OPENING_PROGRAMMES, PROGRAMME_BY_ID


PROGRAMME_DEADLINE_DAY = 90
SELECTION_DEADLINE_DAY = 30


def role_for(state) -> str:
    return "government" if state.player.in_government else "opposition"


def record(state):
    value = state.campaign_meta.get("opening_programme")
    return value if isinstance(value, dict) else None


def selected(state):
    current = record(state)
    if not current:
        return None
    return PROGRAMME_BY_ID.get(current.get("id"))


def candidates(state) -> list:
    if selected(state) is not None or state.day_index > PROGRAMME_DEADLINE_DAY:
        return []
    role = role_for(state)
    return [programme for programme in OPENING_PROGRAMMES
            if programme["role"] == role]


def select(state, programme_id: str):
    programme = PROGRAMME_BY_ID.get(programme_id)
    if programme is None:
        return False, "That opening programme does not exist."
    if selected(state) is not None:
        return False, "Your first ninety-day programme is already settled."
    if state.day_index > PROGRAMME_DEADLINE_DAY:
        return False, "The opening ninety-day window has passed."
    if programme["role"] != role_for(state):
        return False, "That programme does not match your present political office."
    state.campaign_meta["opening_programme"] = {
        "id": programme_id,
        "selected_day": state.day_index,
        "actions": [],
    }
    return True, f"{programme['name']} adopted as the first ninety-day programme."


def note_action(state, action_id: str):
    current = record(state)
    if not current or not action_id:
        return
    actions = current.setdefault("actions", [])
    if action_id not in actions:
        actions.append(action_id)


def _all_player_bill_ids(state) -> set:
    bills = list(state.legislature.pending_bills)
    bills += list(state.legislature.active_laws)
    bills += list(state.legislature.law_history)
    return {bill.id for bill in bills if getattr(bill, "proposed_by", None) == "player"}


def task_complete(state, task: dict) -> bool:
    check = task.get("check")
    current = record(state) or {}
    actions = set(current.get("actions", []))

    if check == "action":
        return task.get("action_id") in actions
    if check == "reform_objective":
        project = state.reform_project
        adopted = {action.removeprefix("reform_objective:")
                   for action in actions if action.startswith("reform_objective:")}
        if project is not None:
            adopted.add(project.objective_id)
        return bool(adopted & set(task.get("objective_ids", [])))
    if check == "propose_bill":
        proposed = _all_player_bill_ids(state)
        proposed.update(action.removeprefix("propose_bill:")
                        for action in actions if action.startswith("propose_bill:"))
        return bool(proposed & set(task.get("bill_ids", [])))
    if check == "regional_programme":
        allowed = set(task.get("programme_ids", []))
        launched = {programme.program_id for programme in state.regional_programs}
        launched.update(action.removeprefix("regional_programme:")
                        for action in actions if action.startswith("regional_programme:"))
        return bool(launched & allowed)
    if check == "pledge":
        agenda = state.domestic_politics.get("opposition_agenda", {})
        return bool(agenda.get("pledges")) or "publish_pledge" in actions
    if check == "shadow_minister":
        return bool(state.shadow_cabinet.ministers) or "appoint_shadow" in actions
    if check == "pledge_campaign":
        agenda = state.domestic_politics.get("opposition_agenda", {})
        return ("campaign_pledge" in actions or
                any(int(pledge.get("campaigns", 0)) > 0
                    for pledge in agenda.get("pledges", [])))
    if check == "regional_campaign":
        return ("regional_campaign" in actions or
                any(str(key).startswith("regional_campaign:")
                    for key in state.cooldowns))
    return False


def progress(state) -> dict:
    programme = selected(state)
    if programme is None:
        return {
            "programme": None,
            "completed": 0,
            "total": 0,
            "tasks": [],
            "days_remaining": max(0, PROGRAMME_DEADLINE_DAY - state.day_index),
            "status": "unselected" if state.day_index <= PROGRAMME_DEADLINE_DAY else "missed",
        }

    tasks = [(task, task_complete(state, task)) for task in programme["tasks"]]
    completed = sum(1 for _task, done in tasks if done)
    stored_role = programme["role"]
    if stored_role != role_for(state):
        status = "superseded"
    elif completed == len(tasks):
        status = "complete"
    elif state.day_index > PROGRAMME_DEADLINE_DAY:
        status = "expired"
    else:
        status = "active"
    return {
        "programme": programme,
        "completed": completed,
        "total": len(tasks),
        "tasks": tasks,
        "days_remaining": max(0, PROGRAMME_DEADLINE_DAY - state.day_index),
        "status": status,
    }


def next_incomplete_task(state):
    for task, done in progress(state)["tasks"]:
        if not done:
            return task
    return None
