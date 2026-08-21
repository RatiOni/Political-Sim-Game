"""Authored guidance for a new player's first months.

A path IN, not a tutorial and not a script. Each entry introduces ONE system
that has just become relevant, says what it is and why it matters in the
game's own register, and points at the desk page or region where it lives.
Nothing here applies an effect, gates an action, or demands an order of play:
guidance is advisory, dismissible, and gone for good once dismissed.

This is deliberately separate from content/opening_programmes.py, which is a
different job. A programme gives the player an OBJECTIVE — three tasks worth
doing in the first ninety days. Guidance explains where the machinery IS.
They are complementary, and an entry here never restates a programme task.

Each entry:
    id       stable, stored in campaign_meta once dismissed
    title    a short line, sentence case
    body     two or three sentences, the game's voice
    page     the desk page it points at, or None
    region   a region id to select on the map, or None
    trigger  a plain predicate on state — turn number, or a system first
             becoming live. Pure and read-only; engine/onboarding.py calls
             it and nothing else.
"""


def _in_government(state) -> bool:
    return bool(state.player.in_government)


def _has_pending_bill(state) -> bool:
    return bool(state.legislature.pending_bills)


def _has_pressured_region(state) -> bool:
    return any(region.pressure >= 0.55 for region in state.regions.values())


def _has_strained_ministry(state) -> bool:
    return any(ministry.status_label() != "Effective"
               for ministry in state.ministries.values())


def _budget_season(state) -> bool:
    """The annual settlement is January-gated, so it becomes the live question
    in the autumn — before the window, not after it has closed."""
    return state.month >= 9 or state.pending_budget is not None


GUIDANCE = [
    {
        "id": "the_chamber",
        "title": "The chamber is where policy becomes law",
        "body": (
            "Nothing you intend matters until it survives a division. Bills are "
            "drafted on the Policies desk, and the seat strip along the bottom of "
            "the dashboard tells you whether the arithmetic is there before you "
            "spend anything on it. A bill you cannot pass costs you capital and "
            "standing both."
        ),
        "page": "Policies",
        "region": None,
        "trigger": lambda state: _in_government(state),
    },
    {
        "id": "attention",
        "title": "A government can only do three things a month",
        "body": (
            "Political capital is what the chamber will let you spend. Attention "
            "is what your government has room to actually do — three major "
            "initiatives in a month, and following through on something already "
            "started is free. It is the difference between affording a policy and "
            "having the month to pursue it."
        ),
        "page": None,
        "region": None,
        "trigger": lambda state: True,
    },
    {
        "id": "the_map",
        "title": "Pressure is the map telling you where the state is losing",
        "body": (
            "Every region carries its own unemployment, state reach and political "
            "pressure, and the map colours the third of those. A region shading "
            "toward Strained is not scenery — it is unrest feeding the national "
            "picture, and an electorate drifting. Click one to see what is driving it."
        ),
        "page": None,
        "region": "zavost",
        "trigger": lambda state: state.turn >= 2 and _has_pressured_region(state),
    },
    {
        "id": "ministries",
        "title": "A ministry can be funded and still fail to deliver",
        "body": (
            "Departments have a workload as well as a budget. When what a ministry "
            "is carrying exceeds what it can carry, delivery falls and a backlog "
            "builds that money alone will not clear quickly. The Cabinet desk shows "
            "each department's load against its capacity."
        ),
        "page": "Cabinet",
        "region": None,
        "trigger": lambda state: state.turn >= 3 and _has_strained_ministry(state),
    },
    {
        "id": "the_budget",
        "title": "The budget is settled once a year",
        "body": (
            "Appropriations are voted for the year ahead and take effect on the "
            "first of January. It is the largest lever you have and the one with "
            "the longest reach, so the composition matters more than the total. "
            "Mid-year there is only the supplementary, which is deliberately dear."
        ),
        "page": "Policies",
        "region": None,
        "trigger": lambda state: _in_government(state) and _budget_season(state),
    },
]

GUIDANCE_BY_ID = {entry["id"]: entry for entry in GUIDANCE}
