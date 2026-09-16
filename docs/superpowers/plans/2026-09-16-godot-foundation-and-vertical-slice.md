# Godot Foundation and Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Godot national-dashboard vertical slice that runs the existing Python simulation through a versioned local bridge and proves map interaction, meaningful time, one real reform-objective action, monthly explanation, and save/load without changing simulation balance.

**Architecture:** Keep Python authoritative for this milestone. A small stdlib JSON-lines worker owns one live `GameState`; a presentation adapter emits deliberately bounded snapshots and an allow-listed command registry routes requests into existing engine functions. A standard Godot 4.7.2 project renders those snapshots with GDScript scenes; it never imports Python, reads save internals, or reproduces simulation formulas.

**Tech Stack:** Godot 4.7.2 standard editor at `D:\Godot\Godot_v4.7.2-stable_win64.exe`, GDScript for scenes, Python 3.14.6 simulation runtime, Python standard-library JSON/subprocess protocol, existing PySide6/PyInstaller reference build, assert-based Python checks, Godot headless scene checks.

**Spec:** `docs/superpowers/specs/2026-09-16-godot-migration-program-design.md`

## Global Constraints

- End this plan at migration gate G1; do not port simulation formulas into GDScript or another language in this milestone.
- Do not change balance numbers, RNG chances, monthly phase order, content, save schema, or existing player-operation behavior.
- Keep `engine/player_ops.py` and `TurnEngine` authoritative.
- Bridge requests accept only JSON values and allow-listed command/action ids.
- Godot never receives an arbitrary Python object, module, callable, filesystem path, or unrestricted operation name.
- Godot presentation state may cache selection and layout only; authoritative campaign state remains in Python.
- Preserve the current PySide6 and CLI front ends and their tests.
- Keep monthly economy/household/region simulation monthly; the daily command calls the existing `advance_day()` behavior.
- Target 1920x1080 first, with explicit checks at 1280x720 and Windows 125%/150% scaling.
- Do not package or publish the hybrid build until the G1 acceptance report explicitly approves it.
- Reuse existing Ardenia geometry and content ids; do not redraw or rename the country in this milestone.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `godot/project.godot` | Godot project settings, fixed stretch policy, main scene, input actions. |
| `godot/scenes/main.tscn` | Root game shell: header, alert/decision rail, map, inspector, bottom report area. |
| `godot/scenes/map/ardenia_map.tscn` | National-map node and region hit targets. |
| `godot/scenes/panels/region_brief.tscn` | Selected-region summary and the one objective action entry. |
| `godot/scenes/panels/monthly_report.tscn` | Existing monthly digest presentation. |
| `godot/scripts/app.gd` | Scene orchestration only: submit command, apply snapshot, route selection. |
| `godot/scripts/bridge/simulation_bridge.gd` | Worker process lifetime and JSON-lines request/response transport. |
| `godot/scripts/map/ardenia_map.gd` | Loads exported polygons, draws layers, performs region selection. |
| `godot/scripts/tests/vertical_slice_test.gd` | Headless journey assertions for startup, selection, action, time, and reload. |
| `godot/theme/ardenia_theme.tres` | Shared colour, typography, spacing, focus, and control styling. |
| `godot_bridge/__init__.py` | Marks the bridge package. |
| `godot_bridge/protocol.py` | Protocol version, request validation, response envelopes. |
| `godot_bridge/presentation.py` | `GameState` to bounded client snapshot; no mutation. |
| `godot_bridge/actions.py` | Allow-listed action adapters to existing `player_ops`. |
| `godot_bridge/worker.py` | JSON-lines worker owning one state and dispatching commands. |
| `godot_bridge/export_map.py` | Converts current map constants into one Godot-readable JSON asset. |
| `godot/data/ardenia_map.json` | Generated map geometry and stable ids used by the Godot renderer. |
| `godot_bridge_test.py` | Focused protocol, validation, snapshot, action, time, save/load, and map-export checks. |
| `scripts/run_godot_slice.ps1` | Verified developer launcher for the worker and editor/project. |
| `docs/godot/G1_ACCEPTANCE.md` | Recorded evidence, comparison findings, and proceed/stop decision. |
| `.gitignore` | Ignores Godot import/cache/output directories without ignoring source assets. |

---

### Task 1: Pin the toolchain and capture the reference baseline

**Files:**
- Create: `docs/godot/TOOLCHAIN.md`
- Create: `godot_bridge_test.py`
- Modify: `.gitignore`

**Interfaces:**
- Produces: the verified Godot executable path, Godot version, renderer choice, and confirmation that this milestone has no .NET SDK dependency, recorded in `docs/godot/TOOLCHAIN.md`.
- Produces: `BASELINE_FIXTURE` in `godot_bridge_test.py`, generated by existing public APIs rather than copied save internals.
- Consumes: `.venv\Scripts\python.exe`, `engine.campaign.generate_campaign`, `engine.persistence.serialize_state`, and `engine.digest.snapshot`.

- [ ] **Step 1: Record the existing working-tree boundary**

Run:

```powershell
git status --short
git rev-parse HEAD
```

Expected: record the commit in the execution notes and leave all pre-existing modified/untracked files untouched. This repository is currently dirty; do not stage `distribution_test.py`, `docs/playtests/WINDOWS_RELEASE_CHECKLIST.md`, `.hermes/`, `DESIGN.md`, or the HTML design variants unless the user separately assigns them.

- [ ] **Step 2: Inspect the installed Godot and confirm the dependency boundary**

Run the verified installed executable:

```powershell
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --version
```

Expected: Godot reports `4.7.2.stable.official.ed1daf0bf`. Record the output and the deliberate GDScript-plus-Python dependency boundary in `docs/godot/TOOLCHAIN.md`; the standard editor needs no .NET SDK for G1.

- [ ] **Step 3: Run the untouched Python baseline**

Run:

```powershell
& ".venv\Scripts\python.exe" smoke_test.py
& ".venv\Scripts\python.exe" distribution_test.py
& ".venv\Scripts\python.exe" scripts\run_ui_smoke_offscreen.py
```

Expected: each command exits `0`. Record every pass count in `docs/godot/TOOLCHAIN.md`. A hang or failure is investigated before migration code begins; do not redefine it as the new baseline.

- [ ] **Step 4: Write the failing fixture-stability check**

Create `godot_bridge_test.py` with this harness and first check:

```python
"""Focused checks for the Godot migration contract."""

import json

from engine.campaign import default_config, generate_campaign
from engine import persistence


def check(name, fn):
    fn()
    print(f"PASS  {name}")


def canonical_state_is_json_serializable():
    state = generate_campaign(default_config())
    payload = persistence.serialize_state(state)
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    assert json.loads(encoded)["country"]["id"] == "ardenia"
    assert payload["day"] == 1


if __name__ == "__main__":
    checks = [("canonical state is JSON serializable",
               canonical_state_is_json_serializable)]
    for label, test in checks:
        check(label, test)
    print(f"ALL {len(checks)} GODOT BRIDGE CHECKS PASSED")
```

- [ ] **Step 5: Run the focused test**

Run:

```powershell
& ".venv\Scripts\python.exe" godot_bridge_test.py
```

Expected: `ALL 1 GODOT BRIDGE CHECKS PASSED`.

- [ ] **Step 6: Add Godot-only ignores**

Append exactly these source-safe entries to `.gitignore` unless equivalent rules already exist:

```gitignore
godot/.godot/
godot/.mono/
godot/bin/
godot/export/
```

- [ ] **Step 7: Commit the baseline contract**

```powershell
git add .gitignore godot_bridge_test.py docs/godot/TOOLCHAIN.md
git commit -m "test: pin Godot migration baseline"
```

Expected: only the three assigned paths are committed.

---

### Task 2: Define and validate the bridge protocol

**Files:**
- Create: `godot_bridge/__init__.py`
- Create: `godot_bridge/protocol.py`
- Modify: `godot_bridge_test.py`

**Interfaces:**
- Produces: `PROTOCOL_VERSION = 1`
- Produces: `parse_request(line: str) -> dict`
- Produces: `success(request_id: int, payload: dict) -> dict`
- Produces: `failure(request_id: int | None, code: str, message: str) -> dict`
- Request shape: `{"version": 1, "id": 7, "command": "snapshot", "args": {}}`
- Success shape: `{"version": 1, "id": 7, "ok": true, "payload": {...}}`
- Failure shape: `{"version": 1, "id": 7, "ok": false, "error": {"code": "...", "message": "..."}}`

- [ ] **Step 1: Add failing protocol checks**

Extend `godot_bridge_test.py`:

```python
from godot_bridge.protocol import parse_request, success, failure


def protocol_rejects_untrusted_shapes():
    valid = parse_request(json.dumps({
        "version": 1, "id": 4, "command": "snapshot", "args": {}}))
    assert valid["id"] == 4
    for bad in (
        "not json",
        json.dumps([]),
        json.dumps({"version": 2, "id": 1, "command": "snapshot", "args": {}}),
        json.dumps({"version": 1, "id": True, "command": "snapshot", "args": {}}),
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
```

Add the check to the harness list.

- [ ] **Step 2: Run the focused check and confirm failure**

Run:

```powershell
& ".venv\Scripts\python.exe" godot_bridge_test.py
```

Expected: non-zero with `ModuleNotFoundError: No module named 'godot_bridge'`.

- [ ] **Step 3: Implement the minimal protocol**

Create `godot_bridge/protocol.py`:

```python
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
    if request.get("command") not in COMMANDS:
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
```

Create an empty `godot_bridge/__init__.py`.

- [ ] **Step 4: Run the focused and full Python suites**

Run:

```powershell
& ".venv\Scripts\python.exe" godot_bridge_test.py
& ".venv\Scripts\python.exe" smoke_test.py
```

Expected: both exit `0`; the focused suite reports two checks.

- [ ] **Step 5: Commit the protocol**

```powershell
git add godot_bridge godot_bridge_test.py
git commit -m "feat: define Godot bridge protocol"
```

---

### Task 3: Expose bounded presentation snapshots and real commands

**Files:**
- Create: `godot_bridge/presentation.py`
- Create: `godot_bridge/actions.py`
- Create: `godot_bridge/worker.py`
- Modify: `godot_bridge_test.py`

**Interfaces:**
- Produces: `state_snapshot(state) -> dict`
- Produces: `dispatch(state, engine, command: str, args: dict) -> tuple[GameState, dict]`
- Produces: `Worker.handle(request: dict) -> dict`
- Snapshot top-level keys: `date`, `player`, `headline`, `economy`, `regions`, `factions`, `decisions`, `calendar`, `digest`, `reform`, `dispatches`.
- Commands mutate only by calling existing campaign, turn, persistence, or player-operation APIs.

- [ ] **Step 1: Add failing snapshot and mutation checks**

Extend `godot_bridge_test.py` with:

```python
from engine.turn import TurnEngine
from godot_bridge.presentation import state_snapshot
from godot_bridge.actions import dispatch


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
```

Add both checks to the harness.

- [ ] **Step 2: Run the focused checks and confirm failure**

Run:

```powershell
& ".venv\Scripts\python.exe" godot_bridge_test.py
```

Expected: non-zero because `godot_bridge.presentation` does not exist.

- [ ] **Step 3: Implement the snapshot as a composition of existing read models**

In `godot_bridge/presentation.py`, build the top-level shape from public fields and existing helpers:

```python
from engine import decision_queue, political_calendar, digest, reforms


def state_snapshot(state):
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
```

Implement `_decision_view(item)` with the existing `DecisionItem` fields `id`, `priority`, `tag`, `title`, `detail`, `page`, `authority`, `days_remaining`, `due_text`, and `region_id`. Implement `_calendar_view(state, item)` with `CalendarItem` fields `id`, `date.isoformat()`, `days_from(state)`, `kind`, `tag`, `title`, `detail`, `page`, `authority`, and `decision_id`. Do not add serialization methods to the engine dataclasses solely for the bridge.

- [ ] **Step 4: Implement the allow-listed command adapters**

In `godot_bridge/actions.py`, create one dictionary of concrete adapters:

```python
from engine import persistence, player_ops


def _result(result):
    return {"success": bool(result.success), "message": result.message}


def dispatch(state, engine, command, args):
    if command == "snapshot":
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
        return state, {"result": _result(result),
                       "state": state_snapshot(state)}
    elif command == "save":
        slot = _safe_slot(args.get("slot"))
        persistence.save_campaign(state, slot=slot)
    else:
        raise ValueError("command is not implemented")
    return state, {"state": state_snapshot(state)}
```

Import `state_snapshot`, implement `_safe_slot` with the same alphanumeric/`-`/`_` policy as persistence, and implement `load`, `list_saves`, and `new_campaign` by calling their existing APIs. `load` and `new_campaign` return the newly created `GameState` as the first tuple item; every other command returns the input state. Do not duplicate campaign defaults or save parsing.

For G1, `new_campaign` accepts an empty `args` object only and calls `generate_campaign(default_config())`. Campaign customization remains in the existing PySide6 client until the complete-presentation plan. `Worker.state` begins as `None`; before `new_campaign` or `load`, every state-dependent command returns `no_campaign` without constructing or mutating state.

- [ ] **Step 5: Implement a one-state JSON-lines worker**

`godot_bridge/worker.py` must read one request per stdin line, write one response per stdout line, flush after every response, log diagnostics to stderr, and exit cleanly on `shutdown`. Construct `TurnEngine` once. `Worker.handle()` assigns both values returned by `dispatch()` so `load` and `new_campaign` replace `self.state` authoritatively. Catch `ValueError` as a safe `bad_request`; catch unexpected exceptions as `internal_error` without serializing a traceback to the client. The process exit log may retain the traceback through existing local logging.

- [ ] **Step 6: Run bridge, full simulation, and persistence checks**

Run:

```powershell
& ".venv\Scripts\python.exe" godot_bridge_test.py
& ".venv\Scripts\python.exe" smoke_test.py
& ".venv\Scripts\python.exe" distribution_test.py
```

Expected: all exit `0`; focused checks report four or more passes.

- [ ] **Step 7: Commit the authoritative bridge**

```powershell
git add godot_bridge godot_bridge_test.py
git commit -m "feat: expose simulation to Godot vertical slice"
```

---

### Task 4: Export the existing national map contract

**Files:**
- Create: `godot_bridge/export_map.py`
- Create: `godot/data/ardenia_map.json`
- Modify: `godot_bridge_test.py`

**Interfaces:**
- Produces: `export_map() -> dict`
- Output keys: `outline`, `regions`, `labels`, `cities`, `routes`, `ports`, `ceasefire_line`, `neighbors`.
- Coordinates remain in the existing normalized `0..100` authoring space.
- Region ids exactly match `GameState.regions` and `content.lore.REGIONS`.

- [ ] **Step 1: Add a failing map-contract check**

Add:

```python
from godot_bridge.export_map import export_map


def map_export_preserves_live_region_ids():
    state = generate_campaign(default_config())
    payload = export_map()
    exported = {item["id"] for item in payload["regions"]}
    assert exported == set(state.regions)
    assert len(exported) == 9
    assert all(len(item["points"]) >= 3 for item in payload["regions"])
    assert all(0 <= coordinate <= 100
               for item in payload["regions"]
               for point in item["points"] for coordinate in point)
```

- [ ] **Step 2: Run and confirm the missing-module failure**

Run `& ".venv\Scripts\python.exe" godot_bridge_test.py`.

Expected: non-zero because `godot_bridge.export_map` does not exist.

- [ ] **Step 3: Implement the thin exporter**

Import the existing constants from `ui.ardenia_map_geometry` and `ui.ardenia_region_geometry`, convert tuples to JSON lists, and sort region records by stable id. The exporter must contain no second copy of polygon coordinates. Its `__main__` path writes UTF-8 JSON only to `godot/data/ardenia_map.json` beneath the repository.

- [ ] **Step 4: Generate and verify the asset**

Run:

```powershell
& ".venv\Scripts\python.exe" -m godot_bridge.export_map
& ".venv\Scripts\python.exe" godot_bridge_test.py
git diff --check
```

Expected: JSON is generated deterministically; all checks pass; running the exporter twice creates no diff.

- [ ] **Step 5: Commit the map contract**

```powershell
git add godot_bridge/export_map.py godot/data/ardenia_map.json godot_bridge_test.py
git commit -m "feat: export Ardenia map for Godot"
```

---

### Task 5: Build the Godot shell and static map

**Files:**
- Create: `godot/project.godot`
- Create: `godot/scenes/main.tscn`
- Create: `godot/scenes/map/ardenia_map.tscn`
- Create: `godot/scenes/panels/region_brief.tscn`
- Create: `godot/scenes/panels/monthly_report.tscn`
- Create: `godot/scripts/app.gd`
- Create: `godot/scripts/map/ardenia_map.gd`
- Create: `godot/theme/ardenia_theme.tres`
- Create: `godot/scripts/tests/vertical_slice_test.gd`

**Interfaces:**
- Produces signal: `ArdeniaMap.region_selected(region_id: String)`.
- Produces method: `ArdeniaMap.apply_snapshot(regions: Array, selected_id: String) -> void`.
- Produces method: `App.apply_snapshot(snapshot: Dictionary) -> void`.
- Consumes: `res://data/ardenia_map.json` and the snapshot shape from Task 3.

- [ ] **Step 1: Create a failing headless scene check**

`vertical_slice_test.gd` loads `main.tscn`, asserts required named nodes exist (`DateLabel`, `PlayButton`, `SpeedControls`, `DecisionQueue`, `ArdeniaMap`, `RegionBrief`, `MonthlyReport`), invokes a test-only static snapshot fixture, selects `vashtera`, and asserts that the region brief displays Vashtera's id and live pressure. Exit `0` on success and non-zero on any assertion.

- [ ] **Step 2: Run the headless check and confirm failure**

Run:

```powershell
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path godot --script res://scripts/tests/vertical_slice_test.gd
```

Expected: non-zero because `main.tscn` does not exist.

- [ ] **Step 3: Create the project and theme foundation**

Configure `project.godot` with:

- `main_scene="res://scenes/main.tscn"`;
- viewport size `1920x1080`;
- stretch mode `canvas_items` and aspect `expand`;
- keyboard actions for pause, speed 1–5, escape/back, next decision, save, and load;
- the `gl_compatibility` renderer for the broadest Windows playtest compatibility; and
- no network permissions or autoloads beyond `SimulationBridge` in Task 6.

Create one theme resource with the established dark paper/ink palette, shared type scale, 44-pixel minimum interactive target height, visible focus outline, and no per-control duplicate colour literals in scenes.

- [ ] **Step 4: Build the information hierarchy**

Construct the root with these stable regions:

```text
Header: country / office / date / pause and speed
Alert and decision rail: required and urgent items
Body left: national vitals and assembly summary
Body centre: Ardenia map
Body right: selected-region brief and action
Bottom: monthly governing report and dispatches
```

Use containers and size flags; do not position information panels with hard-coded screen coordinates. The map itself may draw normalized geometry inside its allocated control rectangle.

- [ ] **Step 5: Render and select the map**

`ardenia_map.gd` reads the generated JSON once, converts normalized points through one shared transform, draws the country outline, regions, routes, cities, ceasefire line, labels, hover, and selected state, and uses the same transformed polygons for hit testing. Pressure changes fill intensity; the renderer contains no pressure formula.

- [ ] **Step 6: Pass headless and visual-size checks**

Run the headless test at default size, then launch editor/game windows at 1920x1080 and 1280x720. At 1920x1080, no label or panel overlaps the map; at 1280x720, secondary panes scroll or collapse while date, pause, decision queue, map, and selected-region headline remain accessible. Record screenshots for the acceptance report outside Git unless intentionally approved as documentation assets.

- [ ] **Step 7: Commit the static Godot slice**

```powershell
git add godot/project.godot godot/scenes godot/scripts/app.gd godot/scripts/map godot/scripts/tests godot/theme
git commit -m "feat: build Godot national dashboard shell"
```

---

### Task 6: Connect the live simulation and complete the journey

**Files:**
- Create: `godot/scripts/bridge/simulation_bridge.gd`
- Modify: `godot/project.godot`
- Modify: `godot/scripts/app.gd`
- Modify: `godot/scripts/tests/vertical_slice_test.gd`
- Create: `scripts/run_godot_slice.ps1`
- Modify: `godot_bridge_test.py`

**Interfaces:**
- Produces signal: `SimulationBridge.response_received(request_id: int, payload: Dictionary)`.
- Produces signal: `SimulationBridge.bridge_failed(message: String)`.
- Produces method: `request(command: String, args: Dictionary = {}) -> int`.
- Produces method: `shutdown() -> void`.
- Consumes: protocol version `1` and exact envelopes from Task 2.

- [ ] **Step 1: Add worker round-trip checks**

Use `subprocess.Popen` in `godot_bridge_test.py` to start `python -m godot_bridge.worker`, send `new_campaign`, `snapshot`, `adopt_objective`, `advance_day`, `save`, `load`, and `shutdown` lines, and assert each response id matches its request, each response is exactly one JSON line, objective state survives reload, and the process exits `0`. Set `ARDENIA_USER_DATA_DIR` to `tempfile.TemporaryDirectory()` so the check never touches developer saves.

- [ ] **Step 2: Run the worker check and confirm its first failure**

Run `& ".venv\Scripts\python.exe" godot_bridge_test.py`.

Expected: fail until every worker command and environment-isolated persistence path is complete.

- [ ] **Step 3: Implement the Godot bridge autoload**

Use Godot's process-with-pipes API proven by the pinned Task 1 version. Start exactly:

```text
.venv\Scripts\python.exe -u -m godot_bridge.worker
```

from the repository root in developer mode. Write one compact JSON request plus newline, assign monotonically increasing integer ids, buffer partial stdout until newline, parse only response objects matching protocol version `1`, and surface EOF/process failure through `bridge_failed`. Never use a shell string; pass executable and arguments separately.

- [ ] **Step 4: Route the playable journey through commands**

On startup, `app.gd` requests `new_campaign` then renders the returned snapshot. Controls submit:

- pause/play and speed: client-side timer state;
- clock tick: `advance_day`;
- next month: `advance_month` only when exposed as a developer comparison control;
- region click: presentation selection only;
- adopt objective: `adopt_objective` with the selected objective id;
- save/load: named safe slot commands; and
- application exit: `shutdown` with a short timeout before process termination.

Disable mutating controls while a request is in flight. Display bridge failures as a blocking local error with the log location; never continue against stale state after the worker dies.

- [ ] **Step 5: Add a deterministic fake bridge for headless scene testing**

The scene test injects a small fake implementing only `request()` and emitting the same response signal. It must exercise UI flow without spawning Python. The separate worker round-trip check remains responsible for the real process boundary.

- [ ] **Step 6: Create the verified developer launcher**

`scripts/run_godot_slice.ps1` resolves the repository root, verifies the recorded Godot executable exists, verifies `.venv\Scripts\python.exe`, runs `godot_bridge_test.py`, and launches `godot --path godot`. It does not download dependencies, edit saves, kill unrelated processes, or package a release.

- [ ] **Step 7: Run the complete G1 automated checks**

Run:

```powershell
& ".venv\Scripts\python.exe" godot_bridge_test.py
& ".venv\Scripts\python.exe" smoke_test.py
& ".venv\Scripts\python.exe" distribution_test.py
& ".venv\Scripts\python.exe" scripts\run_ui_smoke_offscreen.py
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path godot --script res://scripts/tests/vertical_slice_test.gd
```

Expected: all commands exit `0`; existing pass counts do not drop.

- [ ] **Step 8: Commit the live slice**

```powershell
git add godot/scripts/bridge godot/scripts/app.gd godot/scripts/tests godot/project.godot scripts/run_godot_slice.ps1 godot_bridge_test.py
git commit -m "feat: connect Godot slice to Ardenia simulation"
```

---

### Task 7: Evaluate migration gate G1

**Files:**
- Create: `docs/godot/G1_ACCEPTANCE.md`
- Modify: `docs/superpowers/specs/2026-09-16-godot-migration-program-design.md` only if the evidence changes an architectural decision.

**Interfaces:**
- Produces: one explicit outcome: `PROCEED`, `REVISE`, or `STOP`.
- Produces: recorded evidence for correctness, usability, performance, development cost, and distribution risk.

- [ ] **Step 1: Run matched Python and Godot sessions**

Use the same campaign configuration and seed. In each client: select the same region, adopt the same objective, advance to the next month, inspect the monthly explanation, save, exit, reload, and verify the date/objective/region/economy headline. Record only observable differences.

- [ ] **Step 2: Complete the acceptance table**

`G1_ACCEPTANCE.md` must record:

| Area | Acceptance condition |
| --- | --- |
| Simulation | Serialized authoritative state matches after the matched command sequence |
| Safety | Unknown commands and invalid args fail without mutation |
| Reliability | Worker exit, client exit, save/load, and bridge failure recover cleanly |
| Readability | 1920x1080 has no overlap; primary loop remains usable at 1280x720 and 125%/150% scaling |
| Game feel | Map selection, time, decision arrival, action acknowledgment, and month-end change are clearer than the reference client |
| Performance | Input remains responsive and a normal snapshot update produces no visible stall |
| Scope | No balance, content, save schema, or simulation phase was changed to make the demo work |
| Cost | Remaining presentation surfaces can reuse the bridge/snapshot/theme pattern without per-screen protocol invention |

- [ ] **Step 3: Make the gate decision**

- `PROCEED`: all conditions pass; write the next separate plan for complete presentation migration.
- `REVISE`: simulation is correct and architecture remains viable, but named failed conditions need a bounded correction before proceeding.
- `STOP`: Godot does not materially improve the experience, or process/distribution complexity exceeds the benefit; retain the Python game and remove only the unshipped experimental branch/worktree through normal Git review.

- [ ] **Step 4: Run final checks and commit the evidence**

Run:

```powershell
git diff --check
& ".venv\Scripts\python.exe" godot_bridge_test.py
& ".venv\Scripts\python.exe" smoke_test.py
```

Then:

```powershell
git add docs/godot/G1_ACCEPTANCE.md docs/superpowers/specs/2026-09-16-godot-migration-program-design.md
git commit -m "docs: record Godot migration gate G1"
```

Expected: the acceptance document contains evidence and one gate outcome, not an aspirational summary.
