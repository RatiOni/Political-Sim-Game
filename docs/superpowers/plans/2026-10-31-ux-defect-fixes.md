# UX Defect Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every UI/UX defect found in the first-session review before any tutorial work begins: an unmistakable clock, a pause menu with options, real save slots, confirmations, visible feedback, vitals that survive a small window and an open desk, desks that switch freely, data before decoration, player language, sentence-case prose, a digest that explains itself, and a title that settles.

**Architecture:** Every new screen is its own file under `godot/scripts/ui/`; `app.gd` (already 1,975 lines against an 800-line limit) gains wiring only. The four new screens — confirm prompt, pause menu, options, save dialog — share one `Overlay` base that holds the clock while open and owns Escape. Preferences live in a new `Settings` autoload, never in a save. Simulation changes are limited to a pure refactor (`approval_breakdown`) and presentation (`MonthlyDigest`).

**Tech Stack:** Godot 4.7.2, GDScript, the project's own `TestSupport` harness (SceneTree scripts run headless).

**Spec / evidence:** `docs/playtests/2026-10-31-ux-review.md` (findings with screenshots) and the "D's scope" and sub-project A/B sections of `docs/superpowers/specs/2026-10-31-guided-first-year-design.md`. The design decisions below were not separately brainstormed; they are stated as rulings for the owner to veto at plan review.

## Rulings (design decisions — veto at review)

| # | Defect | Ruling |
|---|---|---|
| R1 | Clock state unreadable | The play button names its action (`▶ Play` / `❚❚ Pause`). The date label gains a second line carrying the state (`❚❚ Paused` / `▸▸▸ Speed 3`). Speed pips light as a ladder **only while running**. A stopped clock **pulses** (alpha 1.0↔0.45, 0.6 s) until started. Keys 1–5 already work and are unchanged. |
| R2 | No way out of a campaign | Escape with no desk open opens a **pause menu**: Resume, Save game, Load game, Options, Exit to main menu, Quit to desktop. Window close goes through the same path. |
| R3 | No options | **Options** reachable from the main menu and the pause menu. Display: fullscreen; interface scale 100/115/130% (the largest that keeps a 1280×720 layout is used). Sound: master + mute (the existing `SoundControl`), music-and-ambience, effects. Gameplay: autosave each month (default on). Controls: a read-only key list built from the live `InputMap`. Stored in `user://settings.cfg`. |
| R4 | One unnamed save slot, no confirmations | Slots: **Autosave** + **Slot 1–3** (+ the legacy `godot_slice` save shown as "Earlier save" if present). Each row shows leader, in-game date, saved time. Overwriting asks. Loading or leaving with unsaved progress asks. `S` quick-saves into the current slot; `L` opens the load dialog (it reloaded instantly before). Continue loads the most recent save and is disabled when there is none. |
| R5 | Success feedback invisible | A notice shows the full event ("Saved to Slot 1") in the header for 3 s, green or red, then clears; the footer keeps the last one. Idle shows nothing — no "LIVE SIMULATION / READY". |
| R6 | Compact mode hides the vitals | The national panel stays at 1280×720 at 236 px wide; gauges drop below 260 px of width, figures stay. |
| R7 | Desks lock navigation and hide the vitals | Header destinations stay live while a desk is open: another destination switches, the open desk's own button (shown in amber) closes it. Leaving a budget draft asks first. The national panel stays visible beside every desk. |
| R8 | Decoration outweighs data | Desk data column : room art = 3 : 2. Budget envelopes become one line each (name · slider · figure) so all eight show at 1920×1080. |
| R9 | Developer language | Every player-visible mention of "simulation", "snapshot", "connected", "authorised steps", "static preview", "worker" is rewritten; a test walks every visible label to keep it that way. Save/Load tooltips read their real keys from the `InputMap` (they claimed F5/F9; the keys are S/L). |
| R10 | All-caps prose | A **wrapping** Label keeps its own case; single-line labels stay in capitals. |
| R11 | Digest is bare points | Keep the *improves / deteriorates* wording (it already says whether a move is good). Add the cause: approval and stability name the term that moved them ("driven by unrest") or, for a fall with no mover, the heaviest drag ("weighed down by unrest"); hardship names the hardest-hit group and region. Order by consequence: election, **emergency budget first among the month's own lines**, approval, stability, then the rest; crisis and situation notes before world news; polls last. |
| R12 | Title never settles | The letter wall stops rolling 1.5 s after the word is found and freezes as faint texture. |
| R13 | Small fixes | Menu date reads March 1993 (the campaign's real start); the menu tagline no longer clips at 720p; the region brief's second line shows the region's control status instead of its raw id; abbreviations in the compact brief are spelled out; the three unlabelled option buttons get tooltips; every vital sign explains itself in a tooltip; the fatal-error screen speaks to the player. |

## Global Constraints

- **Godot 4.7.2, GDScript only.** No `.py` file is modified (the Python tree is a frozen reference).
- **Godot binary:** `D:/AI Stuff/Godot/Godot_v4.7.2-stable_win64_console.exe` — written below as `"$GODOT"`. Commands run from the worktree root `D:/Political Sim Game/.worktrees/godot-native-sim`. Set it once per shell: `GODOT="D:/AI Stuff/Godot/Godot_v4.7.2-stable_win64_console.exe"`.
- **After creating any file with a `class_name`, refresh the class cache** before running tests: `"$GODOT" --headless --path godot --import`. A stale cache reports the new class as an undeclared identifier.
- **Run one test:** `"$GODOT" --headless --path godot --script res://tests/<dir>/<file>.gd` — exit code 0 means every check passed; each check prints `PASS  <label>` or `FAIL  <label>`.
- **Shared worktree.** Other sessions work here. Commit with explicit paths only: `git commit -m "..." -- <paths>`. Never `git add -A`, never bare `git stash`. **Never stage `godot/scripts/native/sim/events_sim.gd`** — it belongs to another chat.
- **Commit messages** follow `type: description` and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **`app.gd` gains wiring only.** New behaviour goes in new files under `godot/scripts/ui/`.
- **No label may set the window's minimum width.** Any Label whose text changes at runtime needs `text_overrun_behavior = 3` or wrapping.
- **Nothing on the dashboard changes size when the state changes.**
- **Colours come from `UiPalette`;** amber (`GOLD`) means live, red (`BAD`) means alarm or failure.
- **Bars only for bounded 0..1 values where higher is better.**
- **Tests never touch the player's files:** UI tests use their own save slot and set `autosave_slot = ""`; the settings test uses its own file path.
- **Altered existing tests are recorded** in the task report with the reason. No assertion is weakened to make a build pass.

## Files

| File | Responsibility | Task |
|---|---|---|
| `godot/tests/ui/app_harness.gd` | Boots the real dashboard for UI tests | 1 |
| `godot/scripts/ui/clock_display.gd` | Clock button, date state line, pips, pulse | 1 |
| `godot/scripts/ui/terminal_frame.gd` | (modify) capitals for labels, not prose | 2 |
| `godot/scripts/ui/keys.gd` | Human label for an input action's key | 3 |
| `godot/scripts/ui/ascii/title_reveal.gd` | (modify) the wall settles | 4 |
| `godot/scripts/ui/status_notice.gd` | Transient header notice + footer last notice | 5 |
| `godot/scripts/native/sim/stability_sim.gd` | (modify) `approval_breakdown` | 6 |
| `godot/scripts/native/presentation/monthly_digest.gd` | (modify) causes and order | 6 |
| `godot/scripts/ui/stat_bar.gd` | (modify) no gauge when narrow | 7 |
| `godot/scripts/ui/overlay.gd` | Shared scrim + panel; holds the clock; owns Escape | 8 |
| `godot/scripts/ui/confirm_prompt.gd` | Two- or three-way question | 8 |
| `godot/scripts/ui/audio_buses.gd` | Music and Effects buses under Master | 11 |
| `godot/scripts/settings.gd` | `Settings` autoload: preferences file + apply | 11 |
| `godot/scripts/ui/options_panel.gd` | Options overlay | 12 |
| `godot/scripts/ui/save_dialog.gd` | Save / load slot overlay | 13 |
| `godot/scripts/ui/pause_menu.gd` | Pause overlay | 14 |
| `godot/tools/ux_capture.gd` | Renders a first session for visual review | 15 |
| `godot/scripts/app.gd` | (modify) wiring for all of the above | 1, 3, 5, 7–14 |

---

### Task 0: Clear the worktree for this plan

Another session's audio work is uncommitted in files this plan edits: `godot/project.godot`, `godot/scripts/app.gd`, `godot/scripts/menu.gd`, and untracked `godot/scripts/ambience.gd`, `godot/scripts/ui/sound_control.gd`, `godot/tests/native/test_ambience.gd` (+ their `.uid` files) and `docs/audio_preview/`. Building on top of uncommitted foreign changes makes every later commit carry them.

**Files:** none changed by this task.

- [ ] **Step 1: Look at the tree**

Run: `git status --short`

- [ ] **Step 2: Get the audio work committed — by its owner or with the owner's explicit OK**

This is a stop-and-ask step. If the owner approves committing it as-is, commit exactly these paths and nothing else:

```bash
git add -- godot/project.godot godot/scripts/app.gd godot/scripts/menu.gd godot/scripts/ambience.gd godot/scripts/ambience.gd.uid godot/scripts/ui/sound_control.gd godot/scripts/ui/sound_control.gd.uid godot/tests/native/test_ambience.gd godot/tests/native/test_ambience.gd.uid docs/audio_preview
git commit -m "feat: music and an ambience bed for every scene

Generated in code, like the UI sounds. Committed from the audio session's
working tree before the UX defect pass edits the same files.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- godot/project.godot godot/scripts/app.gd godot/scripts/menu.gd godot/scripts/ambience.gd godot/scripts/ambience.gd.uid godot/scripts/ui/sound_control.gd godot/scripts/ui/sound_control.gd.uid godot/tests/native/test_ambience.gd godot/tests/native/test_ambience.gd.uid docs/audio_preview
```

Leave `godot/scripts/native/sim/events_sim.gd` alone.

- [ ] **Step 3: Refresh the class cache and record the baseline**

```bash
"$GODOT" --headless --path godot --import
for f in godot/tests/native/test_*.gd godot/tests/ui/test_*.gd godot/tests/map/test_*.gd; do
  out="${TMPDIR:-/tmp}/ardenia_test.txt"
  if timeout 900 "$GODOT" --headless --path godot --script "res://${f#godot/}" >"$out" 2>&1; then
    echo "OK    $f"
  else
    echo "FAIL  $f"; grep -E "^FAIL|SCRIPT ERROR" "$out" | head -5
  fi
done
```

Record every failing file in the ledger as **pre-existing**. Known before this plan: `test_world` ("seed 7: courting Krasova never makes it more hostile") and `test_polls` (opposition-start first election). A later task is only responsible for failures that are new against this baseline.

---

### Task 1: The clock reads at a glance (R1)

**Files:**
- Create: `godot/tests/ui/app_harness.gd`
- Create: `godot/scripts/ui/clock_display.gd`
- Modify: `godot/scripts/app.gd` (members, `_ready`, `apply_snapshot`, `_refresh_controls`)
- Modify: `godot/scenes/main.tscn` (`PlayButton`, `DateLabel`)
- Test: `godot/tests/ui/test_clock_display.gd`

**Interfaces:**
- Produces: `ClockDisplay` (Node) — `bind(play: Button, date: Label, pips: Array[Button]) -> void`, `show_state(date_text: String, paused: bool, speed: int, ready: bool) -> void`, `is_pulsing() -> bool`.
- Produces: `app_harness.gd` (preload, no class_name) — `new(tree: SceneTree, slot: String)`, `fresh(role := "contextual") -> Node` (await), `frames(count := 2)` (await), `tick(days: int)` (await), `wipe_slot()`, `finish()`; property `app`.
- Produces: `app._date_text: String` (last date text from the snapshot).

- [ ] **Step 1: Write the harness every new UI test uses**

`godot/tests/ui/app_harness.gd`:

```gdscript
extends RefCounted

## Boots the real dashboard for a UI test: a seeded campaign in the test's own
## save slot, with autosave off, so a test never writes the player's files.

const MAIN := "res://scenes/main.tscn"

var tree: SceneTree
var slot: String
var app: Node


func _init(scene_tree: SceneTree, test_slot: String) -> void:
	tree = scene_tree
	slot = test_slot


func fresh(role: String = "contextual") -> Node:
	if app != null and is_instance_valid(app):
		app.queue_free()
		await frames()
	var flow: Node = tree.root.get_node("GameFlow")
	flow.start_mode = "new"
	flow.pending_role = role
	flow.pending_seed = 424242
	app = (load(MAIN) as PackedScene).instantiate()
	app.save_slot = slot
	if "autosave_slot" in app:
		app.autosave_slot = ""
	tree.root.add_child(app)
	await frames(3)
	return app


func frames(count: int = 2) -> void:
	for _i in range(count):
		await tree.process_frame


func tick(days: int) -> void:
	app._paused = false
	for _i in range(days):
		app._clock_elapsed = 999.0
		app._process(0.0)
		await frames(1)


func wipe_slot() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := "user://saves/%s.json%s" % [slot, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func finish() -> void:
	wipe_slot()
	if app != null and is_instance_valid(app):
		app.queue_free()
```

- [ ] **Step 2: Write the failing test**

`godot/tests/ui/test_clock_display.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")


func _initialize() -> void:
	_run.call_deferred()


func _lit(pips: Array[Button]) -> int:
	var n := 0
	for pip in pips:
		if pip.button_pressed:
			n += 1
	return n


func _run() -> void:
	var t = TestSupportScript.new()
	var play := Button.new()
	var date := Label.new()
	var pips: Array[Button] = []
	for _i in 5:
		var pip := Button.new()
		pip.toggle_mode = true
		pips.append(pip)
		root.add_child(pip)
	root.add_child(play)
	root.add_child(date)
	var clock := ClockDisplay.new()
	root.add_child(clock)
	clock.bind(play, date, pips)

	clock.show_state("1 Mar 1993", true, 3, true)
	t.truth(play.text.to_upper().contains("PLAY"), "a stopped clock's button offers to start it")
	t.truth(date.text.contains("1 Mar 1993") and date.text.to_upper().contains("PAUSED"), "the date says the clock is stopped")
	t.equal(_lit(pips), 0, "no speed pip is lit while the clock is stopped")
	t.truth(clock.is_pulsing(), "a stopped clock pulses until someone starts it")

	clock.show_state("1 Mar 1993", false, 3, true)
	t.truth(play.text.to_upper().contains("PAUSE"), "a running clock's button offers to stop it")
	t.truth(date.text.to_upper().contains("SPEED 3") and not date.text.to_upper().contains("PAUSED"), "the date says how fast time runs")
	t.equal(_lit(pips), 3, "the pips light as a ladder up to the speed")
	t.truth(pips[2].button_pressed and not pips[3].button_pressed, "exactly the first three")
	t.truth(not clock.is_pulsing(), "a running clock does not pulse")
	t.near(date.modulate.a, 1.0, 0.001, "and sits at full brightness")

	clock.show_state("1 Mar 1993", true, 3, false)
	t.truth(not clock.is_pulsing(), "a clock with no campaign behind it does not pulse")

	var h = AppHarness.new(self, "test_clock_display")
	var app: Node = await h.fresh()
	t.truth(app.find_child("DateLabel", true, false).text.to_upper().contains("PAUSED"), "the dashboard opens on a visibly stopped clock")
	app._toggle_pause()
	await h.frames()
	t.truth(app.find_child("DateLabel", true, false).text.to_upper().contains("SPEED 1"), "and says so when it starts")
	h.finish()
	quit(t.finish())
```

- [ ] **Step 3: Run it and watch it fail**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_clock_display.gd`
Expected: a parse error naming `ClockDisplay` (the class does not exist yet), non-zero exit.

- [ ] **Step 4: Write `ClockDisplay`**

`godot/scripts/ui/clock_display.gd`:

```gdscript
class_name ClockDisplay
extends Node

## The clock at a glance. The play button names the action it will take; the
## date's second line carries the state; the speed pips light as a ladder only
## while time runs; and a stopped clock pulses until someone starts it. A lit
## speed pip on a stopped clock used to read as "running".

const PULSE_SECONDS := 0.6
const PULSE_LOW := 0.45

var _play: Button
var _date: Label
var _pips: Array[Button] = []
var _pulse: Tween


func bind(play: Button, date: Label, pips: Array[Button]) -> void:
	_play = play
	_date = date
	_pips = pips


func show_state(date_text: String, paused: bool, speed: int, ready: bool) -> void:
	_play.text = "▶ Play" if paused else "❚❚ Pause"
	_play.tooltip_text = "Start the clock (Space)" if paused else "Stop the clock (Space)"
	var state_line := "❚❚ Paused" if paused else "%s Speed %d" % ["▸".repeat(speed), speed]
	_date.text = "%s\n%s" % [date_text, state_line]
	for i in _pips.size():
		_pips[i].set_pressed_no_signal(ready and not paused and i < speed)
	_set_pulse(ready and paused)


func is_pulsing() -> bool:
	return _pulse != null and _pulse.is_valid() and _pulse.is_running()


func _set_pulse(on: bool) -> void:
	if on == is_pulsing():
		return
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null
	_date.modulate.a = 1.0
	if not on:
		return
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_date, "modulate:a", PULSE_LOW, PULSE_SECONDS)
	_pulse.tween_property(_date, "modulate:a", 1.0, PULSE_SECONDS)
```

- [ ] **Step 5: Wire it into the dashboard**

In `godot/scripts/app.gd`, add two members directly after `var _sound := SoundControl.new()`:

```gdscript
var _clock := ClockDisplay.new()
var _date_text := ""
```

In `_ready()`, directly after `%DateLabel.add_theme_color_override("font_color", UiPalette.GOLD)`, add:

```gdscript
	_clock.name = "ClockDisplay"
	add_child(_clock)
	var pips: Array[Button] = []
	for index in range(5):
		pips.append(find_child("Speed%d" % (index + 1)) as Button)
	_clock.bind(%PlayButton, %DateLabel, pips)
```

In `apply_snapshot()`, replace:

```gdscript
	%DateLabel.text = "▌ %s ▌" % str(snapshot.get("date", {}).get("text", "Awaiting snapshot"))
```

with:

```gdscript
	_date_text = str(snapshot.get("date", {}).get("text", ""))
```

In `_refresh_controls()`, replace:

```gdscript
	%PlayButton.text = "Paused" if _paused else "Playing ×%d" % _speed
	for index in range(5):
		var button = find_child("Speed%d" % (index + 1))
		button.disabled = not ready
		button.button_pressed = index + 1 == _speed
```

with:

```gdscript
	for index in range(5):
		(find_child("Speed%d" % (index + 1)) as Button).disabled = not ready
	_clock.show_state(_date_text, _paused, _speed, ready)
```

In `godot/scenes/main.tscn`, in the `[node name="DateLabel" ...]` block change `text = "Awaiting snapshot"` to `text = ""` and add the line `vertical_alignment = 1`. In the `[node name="PlayButton" ...]` block change `text = "Paused"` to `text = "▶ Play"` and `tooltip_text = "Space: pause / resume. Disabled in this static preview."` to `tooltip_text = "Start the clock (Space)"`.

- [ ] **Step 6: Refresh the class cache, run the test, see it pass**

Run: `"$GODOT" --headless --path godot --import` then `"$GODOT" --headless --path godot --script res://tests/ui/test_clock_display.gd`
Expected: every line `PASS`, exit 0.

- [ ] **Step 7: Run the existing dashboard test for regressions**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_app_behaviour.gd`
Expected: same result as the Task 0 baseline.

- [ ] **Step 8: Commit**

```bash
git add -- godot/scripts/ui/clock_display.gd godot/tests/ui/app_harness.gd godot/tests/ui/test_clock_display.gd godot/scripts/app.gd godot/scenes/main.tscn
git commit -m "fix: the clock says whether it is running and how fast

The play button named its state (PAUSED) instead of its action, and the
speed-1 pip stayed lit while paused, so a stopped clock read as running.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- godot/scripts/ui/clock_display.gd godot/tests/ui/app_harness.gd godot/tests/ui/test_clock_display.gd godot/scripts/app.gd godot/scenes/main.tscn
```

(Include the `.uid` files Godot generated for the new scripts in both the `add` and the commit path list.)

---

### Task 2: Capitals for labels, sentence case for prose (R10)

**Files:**
- Modify: `godot/scripts/ui/terminal_frame.gd` (`capitalise`)
- Test: `godot/tests/ui/test_sentence_case.gd`

**Interfaces:**
- Produces: the rule *a Label with `autowrap_mode != AUTOWRAP_OFF` keeps its case*. Later tasks rely on it for every prose label they add: set `autowrap_mode` **before** `add_child`.

- [ ] **Step 1: Write the failing test**

`godot/tests/ui/test_sentence_case.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t = TestSupportScript.new()
	var h = AppHarness.new(self, "test_sentence_case")
	var app: Node = await h.fresh()
	var report: Label = app.find_child("ReportText", true, false)
	t.truth(not report.uppercase, "the monthly report is prose and keeps its case")
	var intro: Label = app.find_child("BudgetIntro", true, false)
	t.truth(not intro.uppercase, "the budget's instructions are prose")
	var heading: Label = app.find_child("AssemblyHeading", true, false)
	t.truth(heading.uppercase, "a heading stays in capitals")

	var prose := Label.new()
	prose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	app.add_child(prose)
	var tag := Label.new()
	app.add_child(tag)
	await h.frames()
	t.truth(not prose.uppercase, "a wrapping label added later keeps its case")
	t.truth(tag.uppercase, "a one-line label added later is set in capitals")
	h.finish()
	quit(t.finish())
```

- [ ] **Step 2: Run it and watch it fail**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_sentence_case.gd`
Expected: `FAIL  the monthly report is prose and keeps its case` (every Label is uppercased today).

- [ ] **Step 3: Implement**

In `godot/scripts/ui/terminal_frame.gd`, replace the whole `capitalise` function:

```gdscript
static func capitalise(root: Node) -> void:
	for node in root.find_children("*", "Label", true, false):
		(node as Label).uppercase = true
	root.get_tree().node_added.connect(func(node: Node) -> void:
		if node is Label:
			(node as Label).uppercase = true)
```

with:

```gdscript
static func capitalise(root: Node) -> void:
	for node in root.find_children("*", "Label", true, false):
		_capitalise_label(node as Label)
	root.get_tree().node_added.connect(func(node: Node) -> void:
		if node is Label:
			_capitalise_label(node as Label))


## Labels are set in capitals; prose is not. A wrapping label is prose, and
## capitals slow reading over more than a line, so it keeps its own case.
static func _capitalise_label(label: Label) -> void:
	label.uppercase = label.autowrap_mode == TextServer.AUTOWRAP_OFF
```

- [ ] **Step 4: Run the test, see it pass**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_sentence_case.gd`
Expected: all `PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add -- godot/scripts/ui/terminal_frame.gd godot/tests/ui/test_sentence_case.gd
git commit -m "fix: set prose in sentence case, keep capitals for labels

Every label was uppercased, including the monthly report and desk
instructions. Capitals suit a one-line label and slow down a paragraph.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- godot/scripts/ui/terminal_frame.gd godot/tests/ui/test_sentence_case.gd
```

---

### Task 3: Player language and self-explaining terms (R9, R13)

**Files:**
- Create: `godot/scripts/ui/keys.gd`
- Modify: `godot/scripts/app.gd` (`_ready`, `apply_snapshot`, `_vital_row`, `_compact_region_status`, `_refresh_region`, `_show_blocking_error`)
- Modify: `godot/scripts/native/native_game.gd` (`_build_snapshot` region row)
- Modify: `godot/scenes/panels/budget_panel.tscn`, `godot/scenes/panels/region_brief.tscn`, `godot/scenes/panels/diplomacy_panel.tscn`, `godot/scenes/panels/opposition_panel.tscn`, `godot/scenes/menu.tscn`, `godot/scenes/main.tscn`
- Test: `godot/tests/ui/test_player_copy.gd`

**Interfaces:**
- Produces: `Keys.label(action: String) -> String` — the first key bound to an `InputMap` action, e.g. `"S"`, `"Space"`, `"Escape"`; `"—"` when unbound.
- Produces: region snapshot rows gain `"control_label": String`.
- Produces: `app.VITAL_TERMS: Dictionary` (vital key → tooltip).

- [ ] **Step 1: Write the failing test**

`godot/tests/ui/test_player_copy.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")

## Words that describe the machinery rather than the republic.
const BANNED := ["simulation", "snapshot", "connected", "authorised steps", "static preview", "worker"]
const VITALS := ["stability", "approval", "capital", "growth", "unemployment", "inflation", "debt", "revenue", "expenditure", "balance"]


func _initialize() -> void:
	_run.call_deferred()


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out


func _sweep(t, app: Node, where: String) -> void:
	for node in _walk(app):
		if not (node is Control) or not (node as Control).is_visible_in_tree():
			continue
		var words: Array[String] = [String((node as Control).tooltip_text)]
		if node is Label:
			words.append((node as Label).text)
		elif node is Button:
			words.append((node as Button).text)
		for text in words:
			var lower := text.to_lower()
			for banned in BANNED:
				if lower.contains(banned):
					t.truth(false, "%s: '%s' in %s says '%s'" % [where, banned, node.name, text])


func _run() -> void:
	var t = TestSupportScript.new()
	var h = AppHarness.new(self, "test_player_copy")
	var app: Node = await h.fresh()
	_sweep(t, app, "dashboard")
	for opener in ["_open_budget", "_open_legislation", "_open_diplomacy", "_open_records", "_open_region_panel"]:
		app.call(opener)
		await h.frames(4)
		_sweep(t, app, opener)
	t.truth(true, "every visible label and tooltip was swept")

	var region_line: String = app.find_child("RegionId", true, false).text
	t.truth(region_line != "vashtera" and region_line.length() > 8, "the region brief names the region's standing, not its id")
	for key in VITALS:
		t.truth(String(app._vital_row(key).tooltip_text).length() > 20, "the %s figure explains itself" % key)
	for choice in ["CountryChoice", "PledgeChoice", "ShadowChoice"]:
		var button: Control = app.find_child(choice, true, false)
		t.truth(button != null and button.tooltip_text != "", "%s says what it chooses" % choice)
	var save_tip: String = app.find_child("SaveButton", true, false).tooltip_text
	t.truth(save_tip.contains("%s)" % Keys.label("save")) and not save_tip.contains("F5"), "the save tooltip names the real key")
	h.finish()
	quit(t.finish())
```

- [ ] **Step 2: Run it and watch it fail**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_player_copy.gd`
Expected: a parse error naming `Keys` — then, once Step 3 adds it, failures for "simulation" and "connected".

- [ ] **Step 3: Write `Keys`**

`godot/scripts/ui/keys.gd`:

```gdscript
class_name Keys
extends RefCounted

## The key a player presses for an action, read from the live InputMap so a
## tooltip can never promise a key that is not bound (the save button once
## said F5; the key was S).

static func label(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			return OS.get_keycode_string(code)
	return "—"
```

- [ ] **Step 4: Rewrite the developer copy**

In `godot/scripts/app.gd` `apply_snapshot()`, replace:

```gdscript
		label.text = "No decisions waiting."
```

with:

```gdscript
		label.text = "Nothing needs your decision right now."
```

and replace:

```gdscript
	%MonthlyReport.find_child("ReportText").text = _lines(snapshot.get("digest", []), "No monthly report yet. Advance a day once connected.")
```

with:

```gdscript
	%MonthlyReport.find_child("ReportText").text = _lines(snapshot.get("digest", []), "Your first monthly report arrives at the end of the month. Start the clock to get there.")
```

In `_refresh_region()`, replace:

```gdscript
	%RegionBrief.find_child("RegionId").text = selected_region_id
```

with:

```gdscript
	%RegionBrief.find_child("RegionId").text = ""
```

replace:

```gdscript
	%RegionBrief.find_child("RegionMetrics").text = "No regional snapshot received."
```

with:

```gdscript
	%RegionBrief.find_child("RegionMetrics").text = "No regional figures yet."
```

and directly after the line `%RegionBrief.find_child("RegionName").text = str(region.get("name", selected_region_id.capitalize()))` add:

```gdscript
		%RegionBrief.find_child("RegionId").text = str(region.get("control_label", ""))
```

Replace the body of `_compact_region_status()` format string:

```gdscript
	return "P %.0f%% · U %.1f%% · Reach %.0f%%" % [
```

with:

```gdscript
	return "Pressure %.0f%% · Jobless %.1f%% · Reach %.0f%%" % [
```

In `_show_blocking_error()`, replace:

```gdscript
	label.text = "SIMULATION UNAVAILABLE\n\n%s\n\nThis is a native-state failure with no worker to retry. Restart the application." % message
```

with:

```gdscript
	label.text = "THE GAME HIT AN ERROR\n\n%s\n\nYour last save is untouched. Restart Ardenia to carry on from it." % message
```

In `godot/scripts/native/native_game.gd` `_build_snapshot()`, in the `regions.append({ ... })` dictionary, directly after the `"control": region.control,` line add:

```gdscript
			"control_label": String(regional_catalog.get("control_labels", {}).get(region.control, region.control.capitalize())),
```

In `godot/scenes/panels/budget_panel.tscn`, replace the `BudgetIntro` text line with:

```
text = "Move each envelope to set next year's spending. When the plan is right, table it and call the vote."
```

In `godot/scenes/panels/region_brief.tscn`, replace the `SourceNote` text line with:

```
text = "Pressure is how close a region is to trouble. State reach is how much of the state's work actually arrives there."
```

In `godot/scenes/menu.tscn`, replace `text = "MINISTERIAL WIRE  ·  JUNE 1993"` with `text = "MINISTERIAL WIRE  ·  MARCH 1993"`, and in the `[node name="Footer" ...]` block add `custom_minimum_size = Vector2(0, 40)` and `vertical_alignment = 1` so the tagline sits clear of the window edge.

In `godot/scenes/main.tscn`, in the `[node name="PreviewStatus" ...]` block replace `text = "STATIC PREVIEW"` with `text = ""`.

- [ ] **Step 5: Give the unlabelled controls and the vital signs their words**

In `godot/scenes/panels/diplomacy_panel.tscn`, in the `[node name="CountryChoice" ...]` block add `tooltip_text = "The country to deal with"`. In `godot/scenes/panels/opposition_panel.tscn`, add `tooltip_text = "A pledge to add to your platform"` to `PledgeChoice` and `tooltip_text = "The portfolio to fill in your shadow cabinet"` to `ShadowChoice`.

In `godot/scripts/app.gd`, add after the `const DATE_WIDTH_WIDE := 192` line:

```gdscript
## What each vital sign means, in the player's terms, on hover.
const VITAL_TERMS := {
	"stability": "How secure your government is. It moves toward a level set by coalition and cabinet loyalty, your majority, public approval, the economy and unrest.",
	"approval": "How the public rates your government. Each month it drifts toward a level set by the economy, party loyalty, household mood and public services.",
	"capital": "What you spend to act: tabling a budget or a bill, launching a programme, lobbying a party. It refills each month.",
	"growth": "How fast the economy is growing, per year.",
	"unemployment": "The share of the workforce without work.",
	"inflation": "How fast prices are rising, per year.",
	"debt": "Public debt as a share of the economy. Every deficit adds to it.",
	"revenue": "What the state collects in a year.",
	"expenditure": "What the state spends in a year.",
	"balance": "Revenue minus spending. A negative balance is a deficit, and adds to the debt.",
}
```

In `_vital_row()`, directly after `row.size_flags_horizontal = Control.SIZE_EXPAND_FILL` add:

```gdscript
	row.tooltip_text = VITAL_TERMS.get(key, "")
```

In `_ready()`, directly after `find_child("LoadButton").pressed.connect(_do_load)` add:

```gdscript
	find_child("SaveButton").tooltip_text = "Save the campaign (%s)" % Keys.label("save")
	find_child("LoadButton").tooltip_text = "Load a saved campaign (%s)" % Keys.label("load")
```

- [ ] **Step 6: Refresh the cache, run the test, see it pass**

Run: `"$GODOT" --headless --path godot --import` then `"$GODOT" --headless --path godot --script res://tests/ui/test_player_copy.gd`
Expected: all `PASS`, exit 0. If a sweep failure names another string, rewrite that string in the player's terms and re-run; do not add it to an allow-list.

- [ ] **Step 7: Commit**

```bash
git add -- godot/scripts/ui/keys.gd godot/tests/ui/test_player_copy.gd godot/scripts/app.gd godot/scripts/native/native_game.gd godot/scenes/panels/budget_panel.tscn godot/scenes/panels/region_brief.tscn godot/scenes/panels/diplomacy_panel.tscn godot/scenes/panels/opposition_panel.tscn godot/scenes/menu.tscn godot/scenes/main.tscn
git commit -m "fix: speak to the player, not about the machinery

Removes 'simulation', 'snapshot', 'once connected' and 'authorised steps'
from the player's view, names each vital sign's meaning on hover, shows a
region's standing instead of its id, and reads key hints from the InputMap
(the save tooltip said F5; the key is S).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- godot/scripts/ui/keys.gd godot/tests/ui/test_player_copy.gd godot/scripts/app.gd godot/scripts/native/native_game.gd godot/scenes/panels/budget_panel.tscn godot/scenes/panels/region_brief.tscn godot/scenes/panels/diplomacy_panel.tscn godot/scenes/panels/opposition_panel.tscn godot/scenes/menu.tscn godot/scenes/main.tscn
```

---

### Task 4: The title settles (R12)

**Files:**
- Modify: `godot/scripts/ui/ascii/title_reveal.gd` (`_process`)
- Test: `godot/tests/ui/test_title_reveal.gd`

**Interfaces:**
- Produces: `TitleReveal.SETTLE_SECONDS := 1.5`; after `finish + SETTLE_SECONDS` the node stops processing and `_wall` no longer changes.

- [ ] **Step 1: Write the failing test**

`godot/tests/ui/test_title_reveal.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t = TestSupportScript.new()
	var reveal := TitleReveal.new()
	reveal.size = Vector2(600, 180)
	root.add_child(reveal)
	var fired := [false]
	reveal.revealed.connect(func() -> void: fired[0] = true)
	for _i in range(60):
		reveal._process(0.1)
	t.truth(fired[0], "the word is revealed")
	t.truth(not reveal.is_processing(), "and the wall stops once it has settled")
	var frozen := reveal._wall.duplicate()
	reveal._process(0.1)
	t.equal(reveal._wall, frozen, "the settled wall no longer changes")
	quit(t.finish())
```

- [ ] **Step 2: Run it and watch it fail**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_title_reveal.gd`
Expected: `FAIL  and the wall stops once it has settled`.

- [ ] **Step 3: Implement**

In `godot/scripts/ui/ascii/title_reveal.gd`, add after `const START := 0.35`:

```gdscript
## How long after the word is found the wall keeps rolling before it freezes.
const SETTLE_SECONDS := 1.5
```

and replace the whole `_process` function with:

```gdscript
func _process(delta: float) -> void:
	_clock += delta
	var finish := START + word.length() * LETTER_GAP + 0.5
	# Once the word is found and the wall has faded, it stops rolling: letters
	# changing forever beside the game's name read as unfinished.
	var settled := _clock >= finish + SETTLE_SECONDS
	if not settled and _clock - _rolled_at >= ROLL_SECONDS:
		_rolled_at = _clock
		_wall.resize(rows * cols)
		for i in _wall.size():
			_wall[i] = ALPHABET[_rng.randi_range(0, ALPHABET.length() - 1)]
	if not _done and _clock >= finish:
		_done = true
		revealed.emit()
	queue_redraw()
	if settled:
		set_process(false)
```

- [ ] **Step 4: Run the test, see it pass**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_title_reveal.gd`
Expected: all `PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add -- godot/scripts/ui/ascii/title_reveal.gd godot/tests/ui/test_title_reveal.gd
git commit -m "fix: the title's letter wall settles instead of rolling forever

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- godot/scripts/ui/ascii/title_reveal.gd godot/tests/ui/test_title_reveal.gd
```

---

### Task 5: Feedback the player can see (R5)

**Files:**
- Create: `godot/scripts/ui/status_notice.gd`
- Modify: `godot/scripts/app.gd` (members, `_ready`, `_process`, `_choose_situation_option`, `_do_new_campaign`, `_do_save`, `_do_load`, `_start_selected_program`, `_show_blocking_error`; delete `_set_status`)
- Test: `godot/tests/ui/test_status_notice.gd`

**Interfaces:**
- Produces: `StatusNotice` (Node) — `bind(header: Label, footer: Label) -> void`, `say(message: String, failed := false) -> void`, property `seconds: float = 3.0`.
- Produces: `app._notice: StatusNotice`. **`app._set_status` is removed;** later tasks call `_notice.say(...)`.

- [ ] **Step 1: Write the failing test**

`godot/tests/ui/test_status_notice.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t = TestSupportScript.new()
	var header := Label.new()
	var footer := Label.new()
	root.add_child(header)
	root.add_child(footer)
	var notice := StatusNotice.new()
	root.add_child(notice)
	notice.bind(header, footer)
	notice.seconds = 0.1
	t.equal(header.text, "", "an idle header says nothing")
	notice.say("Saved to Slot 1")
	t.equal(header.text, "Saved to Slot 1", "the whole notice shows, not its last word")
	t.equal(header.get_theme_color("font_color"), UiPalette.GOOD, "a success is green")
	await create_timer(0.3).timeout
	t.equal(header.text, "", "and clears after a moment")
	t.truth(footer.text.contains("Saved to Slot 1"), "while the footer keeps the last notice")
	notice.say("Save failed: disk full", true)
	t.equal(header.get_theme_color("font_color"), UiPalette.BAD, "a failure is red")

	var h = AppHarness.new(self, "test_status_notice")
	var app: Node = await h.fresh()
	await h.tick(2)
	t.equal(app.find_child("PreviewStatus", true, false).text, "", "a day passing says nothing in the header")
	app._do_save()
	t.truth(app.find_child("PreviewStatus", true, false).text.to_upper().contains("SAVED"), "a save says so")
	h.finish()
	quit(t.finish())
```

- [ ] **Step 2: Run it and watch it fail**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_status_notice.gd`
Expected: a parse error naming `StatusNotice`.

- [ ] **Step 3: Write `StatusNotice`**

`godot/scripts/ui/status_notice.gd`:

```gdscript
class_name StatusNotice
extends Node

## One line of feedback for what the player just did: in the header for a few
## seconds, green or red, then gone; the footer keeps the last one. The header
## used to keep only a message's last word, so "SAVED / READY" showed "READY"
## and a save looked like nothing had happened.

var seconds := 3.0
var _header: Label
var _footer: Label
var _timer := Timer.new()


func bind(header: Label, footer: Label) -> void:
	_header = header
	_footer = footer
	_timer.one_shot = true
	_timer.timeout.connect(func() -> void: _header.text = "")
	add_child(_timer)
	_header.text = ""
	_footer.text = "MINISTERIAL WIRE"


func say(message: String, failed: bool = false) -> void:
	_header.text = message
	_header.add_theme_color_override("font_color", UiPalette.BAD if failed else UiPalette.GOOD)
	_footer.text = "MINISTERIAL WIRE  /  %s" % message
	_timer.start(seconds)
```

- [ ] **Step 4: Replace every status call**

In `godot/scripts/app.gd` add a member after `var _date_text := ""`:

```gdscript
var _notice := StatusNotice.new()
```

In `_ready()`, directly after the three `TerminalFrame.` lines, add:

```gdscript
	_notice.name = "StatusNotice"
	add_child(_notice)
	_notice.bind(find_child("PreviewStatus"), find_child("Footer"))
```

Then make these exact replacements:

| Find | Replace with |
|---|---|
| `_set_status("ADVANCE FAILED / %s" % result.get("error", "Unknown error"))` | `_notice.say("Could not advance: %s" % result.get("error", "unknown error"), true)` |
| the two lines `else:` / `_set_status("LIVE SIMULATION / READY")` inside `_process` | delete both lines (the `if bool(result.get("month_rolled", false)):` block moves out one level, under `if not result.get("ok", false): ... ` as an `elif`): see below |
| `_set_status("DECIDED / %s" % result.get("message", ""))` | `_notice.say("Decided: %s" % result.get("message", ""))` |
| `_set_status("WORKING / NEW CAMPAIGN")` | delete the line |
| `_set_status("NEW CAMPAIGN FAILED / %s" % result.get("error", "Unknown error"))` | `_notice.say("Could not start the campaign: %s" % result.get("error", "unknown error"), true)` |
| `_set_status("LIVE SIMULATION / READY")` in `_do_new_campaign` | delete the line |
| `_set_status("SAVE FAILED / %s" % result.get("error", "Unknown error"))` | `_notice.say("Save failed: %s" % result.get("error", "unknown error"), true)` |
| `_set_status("SAVED / READY")` | `_notice.say("Saved")` |
| `_set_status("LOAD FAILED / %s" % result.get("error", "Unknown error"))` | `_notice.say("Load failed: %s" % result.get("error", "unknown error"), true)` |
| `_set_status("LOADED / READY")` | `_notice.say("Loaded")` |
| `_set_status("PROGRAMME REFUSED / %s" % result.get("error", "Unknown error"))` | `_notice.say("Programme refused: %s" % result.get("error", "unknown error"), true)` |
| `_set_status("PROGRAMME LAUNCHED / READY")` | `_notice.say("Programme launched")` |
| `_set_status("NATIVE SIMULATION FAILED")` | `_notice.say("Error", true)` |

The advance block in `_process` becomes exactly:

```gdscript
		var result: Dictionary = _game.advance_day()
		_flush_snapshot()
		if not result.get("ok", false):
			_notice.say("Could not advance: %s" % result.get("error", "unknown error"), true)
		elif bool(result.get("month_rolled", false)):
			_sfx_cue("month_rollover")
		_refresh_controls()
```

Delete the whole `_set_status` function. Confirm none remain:

Run: `grep -n "_set_status" godot/scripts/app.gd`
Expected: no output.

- [ ] **Step 5: Refresh the cache, run the test, see it pass**

Run: `"$GODOT" --headless --path godot --import` then `"$GODOT" --headless --path godot --script res://tests/ui/test_status_notice.gd`
Expected: all `PASS`, exit 0.

- [ ] **Step 6: Run the dashboard regression test**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_app_behaviour.gd`
Expected: matches the baseline.

- [ ] **Step 7: Commit**

```bash
git add -- godot/scripts/ui/status_notice.gd godot/tests/ui/test_status_notice.gd godot/scripts/app.gd
git commit -m "fix: say what just happened, in full, where the player looks

The header kept only a status's last word, so a save showed READY. Idle
status lines about the engine are gone.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- godot/scripts/ui/status_notice.gd godot/tests/ui/test_status_notice.gd godot/scripts/app.gd
```

---

### Task 6: A monthly report that explains itself (R11)

**Files:**
- Modify: `godot/scripts/native/sim/stability_sim.gd` (add `approval_breakdown`, use it in `update_approval`)
- Modify: `godot/scripts/native/presentation/monthly_digest.gd`
- Modify: `godot/scripts/native/native_game.gd` (`close_month` digest order)
- Modify: `godot/tests/native/test_stability_and_digest.gd` (`_test_digest_direction_wording`) — **altered test, see Step 6**
- Test: `godot/tests/native/test_digest_causes.gd`

**Interfaces:**
- Produces: `StabilitySim.approval_breakdown(state: GameState) -> Dictionary` with keys exactly `"The economy"`, `"Party loyalty"`, `"Household mood"`, `"Public services"`, `"Policy effects"`; `update_approval`'s target is `0.5 + sum(values)`, clamped as before.
- Produces: `MonthlyDigest._cause(before_terms: Dictionary, after_terms: Dictionary, delta: float) -> String` (returns `""` or a clause starting `", "`).

- [ ] **Step 1: Write the failing test**

`godot/tests/native/test_digest_causes.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const MonthlyDigestScript = preload("res://scripts/native/presentation/monthly_digest.gd")
const StabilitySimScript = preload("res://scripts/native/sim/stability_sim.gd")
const HouseholdsSimScript = preload("res://scripts/native/sim/households_sim.gd")


func _initialize() -> void:
	_run.call_deferred()


func _state() -> GameState:
	var game: Node = root.get_node("NativeGame")
	game.new_campaign({"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal", "opening_role": "contextual", "seed": 424242})
	return game._state


func _run() -> void:
	var t = TestSupportScript.new()

	# The named terms are exactly what approval moves toward.
	var state := _state()
	var terms: Dictionary = StabilitySimScript.approval_breakdown(state)
	t.equal(terms.keys(), ["The economy", "Party loyalty", "Household mood", "Public services", "Policy effects"], "approval names its five terms")
	var target := 0.5
	for value in terms.values():
		target += float(value)
	target = clampf(target, 0.05, 0.95)
	var expected := clampf(state.player.approval + (target - state.player.approval) * 0.05, 0.0, 1.0)
	StabilitySimScript.update_approval(state)
	t.near(state.player.approval, expected, 1e-12, "update_approval moves toward the sum of its named terms")

	# Causes.
	t.equal(MonthlyDigestScript._cause({"Unrest": -0.05, "Coalition loyalty": 0.20}, {"Unrest": -0.09, "Coalition loyalty": 0.20}, -0.01),
		", driven by unrest", "a fall names the term that fell")
	t.equal(MonthlyDigestScript._cause({"The economy": 0.01}, {"The economy": 0.03}, 0.01),
		", driven by the economy", "a rise names the term that rose")
	t.equal(MonthlyDigestScript._cause({"Unrest": -0.09, "Coalition loyalty": 0.2}, {"Unrest": -0.09, "Coalition loyalty": 0.2}, -0.01),
		", weighed down by unrest", "a fall with nothing moving names the heaviest drag")
	t.equal(MonthlyDigestScript._cause({"Coalition loyalty": 0.2}, {"Coalition loyalty": 0.2}, 0.01),
		"", "a rise with nothing moving names nothing rather than something structural")

	# The emergency comes first.
	state = _state()
	var before: Dictionary = MonthlyDigestScript.capture(state)
	state.active_budget.source = "continuing"
	state.player.approval -= 0.01
	var lines: Array[String] = MonthlyDigestScript.build(state, before)
	t.truth(lines[0].begins_with("The state is running on an emergency budget"), "an emergency budget leads the report")
	t.truth(lines[1].begins_with("Public approval deteriorates"), "ahead of approval")

	# Hardship names who.
	state = _state()
	before = MonthlyDigestScript.capture(state)
	for household in state.households.values():
		household.hardship += 0.10
	lines = MonthlyDigestScript.build(state, before)
	var hardship := ""
	for line in lines:
		if line.begins_with("Household hardship"):
			hardship = line
	var worst: HouseholdGroupState = HouseholdsSimScript.hardest_hit(state, 1)[0]
	t.truth(hardship.contains(", hardest for ") and hardship.contains(" in "), "rising hardship says who it hits hardest")
	t.truth(not hardship.contains(worst.group_id) and not hardship.contains(worst.region_id), "by name, not by id")

	# Polls close the month's report.
	state = _state()
	var game: Node = root.get_node("NativeGame")
	game.next_month(state)
	var digest: Array = state.monthly_digest
	t.truth(not digest.is_empty() and String(digest[-1]).begins_with("Polls:"), "the polls line comes last")
	quit(t.finish())
```

- [ ] **Step 2: Run it and watch it fail**

Run: `"$GODOT" --headless --path godot --script res://tests/native/test_digest_causes.gd`
Expected: script error on `approval_breakdown` (does not exist).

- [ ] **Step 3: Name approval's terms**

In `godot/scripts/native/sim/stability_sim.gd`, replace the whole `update_approval` function with:

```gdscript
static func update_approval(state: GameState) -> void:
	if state.player == null or state.country == null or state.country.economy == null:
		return
	var target := 0.5
	for value in approval_breakdown(state).values():
		target += float(value)
	target = clampf(target, 0.05, 0.95)
	state.player.approval = clampf(state.player.approval + (target - state.player.approval) * 0.05, 0.0, 1.0)


## The terms approval moves toward, by name, so the monthly report can say
## which one moved it. `update_approval` sums exactly these.
static func approval_breakdown(state: GameState) -> Dictionary:
	var faction_signal := 0.0
	var approval_bias := 0.0
	if state.player.in_government:
		var power_total := 0.0
		for faction in state.country.factions:
			power_total += faction.power
			faction_signal += faction.loyalty * faction.power
		if power_total > 0.0:
			faction_signal /= power_total
		for modifier in state.modifiers:
			if modifier.target == "approval_bias":
				approval_bias += modifier.current_value()
	var household_mood := (HouseholdsSimScript.national_confidence(state) - 0.5) * 2.0
	if not state.player.in_government:
		household_mood *= -1.0
	var services_mood := (HouseholdsSimScript.national_service_access(state) - SERVICES_EXPECTED) * SERVICES_APPROVAL_WEIGHT
	if not state.player.in_government:
		services_mood *= -1.0
	return {
		"The economy": economic_signal(state) * 0.25,
		"Party loyalty": faction_signal * 0.15,
		"Household mood": household_mood * 0.12,
		"Public services": services_mood,
		"Policy effects": approval_bias,
	}
```

The sum is taken in the same order as the old inline expression, so approval is unchanged to the last bit.

- [ ] **Step 4: Give the digest causes and an order**

Replace the whole of `godot/scripts/native/presentation/monthly_digest.gd` with:

```gdscript
class_name MonthlyDigest
extends RefCounted

## The month's report on what keeps a government in office. Lines run in order
## of consequence — an emergency budget first — and approval, stability and
## hardship say what moved them, so the report reads as an account rather than
## a list of numbers.

const HouseholdsSimScript = preload("res://scripts/native/sim/households_sim.gd")
const StabilitySimScript = preload("res://scripts/native/sim/stability_sim.gd")

## A term has to move at least this much in a month to be named as the cause.
const CAUSE_THRESHOLD := 0.001


static func capture(state: GameState) -> Dictionary:
	var econ := state.country.economy
	return {
		"approval": state.player.approval,
		"stability": state.stability_value,
		"growth": econ.growth_rate,
		"unemployment": econ.unemployment,
		"inflation": econ.inflation,
		"regional_pressure": StabilitySimScript.national_pressure(state),
		"household_confidence": HouseholdsSimScript.national_confidence(state),
		"household_hardship": HouseholdsSimScript.national_hardship(state),
		"debt": econ.public_debt_pct,
		"approval_terms": StabilitySimScript.approval_breakdown(state),
		"stability_terms": StabilitySimScript.stability_breakdown(state),
	}


static func build(state: GameState, before: Dictionary) -> Array[String]:
	if before.is_empty():
		return []
	var after := capture(state)
	var lines: Array[String] = []
	if BudgetSim.is_emergency(state):
		lines.append("The state is running on an emergency budget (month %d): no new programmes, every ministry overloaded, and the cost rises each month. Pass a budget to end it." % maxi(1, state.active_budget.emergency_months))
	var approval_delta := float(after["approval"]) - float(before.get("approval", 0.0))
	_append_change(lines, "Public approval", float(before.get("approval", 0.0)), float(after["approval"]), 0.002, true,
		_cause(before.get("approval_terms", {}), after["approval_terms"], approval_delta))
	var stability_delta := float(after["stability"]) - float(before.get("stability", 0.0))
	_append_change(lines, "Government stability", float(before.get("stability", 0.0)), float(after["stability"]), 0.002, true,
		_cause(before.get("stability_terms", {}), after["stability_terms"], stability_delta))
	_append_change(lines, "Inflation", float(before.get("inflation", 0.0)), float(after["inflation"]), 0.002, false)
	_append_change(lines, "Regional pressure", float(before.get("regional_pressure", 0.0)), float(after["regional_pressure"]), 0.003, false)
	var hardship_before := float(before.get("household_hardship", 0.0))
	var hardship_after := float(after["household_hardship"])
	_append_change(lines, "Household hardship", hardship_before, hardship_after, 0.003, false,
		_hardest_hit(state) if hardship_after > hardship_before else "")
	_append_change(lines, "Public debt", float(before.get("debt", after["debt"])), float(after["debt"]), 0.002, false)
	return lines


static func _append_change(lines: Array[String], label: String, before: float, after: float, threshold: float, higher_is_better: bool, cause: String = "") -> void:
	var delta := after - before
	if absf(delta) < threshold:
		return
	var improves := delta > 0.0 if higher_is_better else delta < 0.0
	var direction := "improves" if improves else "deteriorates"
	lines.append("%s %s (%+.1f points)%s." % [label, direction, delta * 100.0, cause])


## The term that moved the reading the way it went; for a fall with nothing
## moving, the heaviest drag on it. A rise with nothing moving names nothing:
## the largest positive term is structural and saying it every month says
## nothing.
static func _cause(before_terms: Dictionary, after_terms: Dictionary, delta: float) -> String:
	if after_terms.is_empty() or delta == 0.0:
		return ""
	var direction := signf(delta)
	var moved := ""
	var moved_by := CAUSE_THRESHOLD
	for term in after_terms:
		var change := (float(after_terms[term]) - float(before_terms.get(term, after_terms[term]))) * direction
		if change > moved_by:
			moved = String(term)
			moved_by = change
	if moved != "":
		return ", driven by %s" % moved.to_lower()
	if direction > 0.0:
		return ""
	var heaviest := ""
	var weight := 0.0
	for term in after_terms:
		if float(after_terms[term]) < weight:
			heaviest = String(term)
			weight = float(after_terms[term])
	return ", weighed down by %s" % heaviest.to_lower() if heaviest != "" else ""


static func _hardest_hit(state: GameState) -> String:
	var worst: Array = HouseholdsSimScript.hardest_hit(state, 1)
	if worst.is_empty():
		return ""
	var household: HouseholdGroupState = worst[0]
	var catalogs: Dictionary = ContentRepository.load_all().get("catalogs", {})
	var group_name := household.group_id.capitalize()
	for group in catalogs.get("household_groups", {}).get("groups", []):
		if String(group.get("id", "")) == household.group_id:
			group_name = String(group.get("name", group_name))
	var profile: Dictionary = catalogs.get("regions_and_programs", {}).get("region_profiles", {}).get(household.region_id, {})
	var region_name := String(profile.get("name", household.region_id.capitalize()))
	return ", hardest for %s in %s" % [group_name.to_lower(), region_name]
```

- [ ] **Step 5: Order the whole month by consequence**

In `godot/scripts/native/native_game.gd` `close_month()`, replace:

```gdscript
	state.monthly_digest = MonthlyDigestScript.build(state, before)
	election_notes.append_array(state.monthly_digest)
	election_notes.append(poll_line)
	state.monthly_digest = election_notes
	state.monthly_digest.append_array(world_notes)
	state.monthly_digest.append_array(crisis_notes)
	state.monthly_digest.append_array(situation_notes)
```

with:

```gdscript
	# In order of consequence: an election, the month's own reckoning (an
	# emergency budget first), crises and situations, the world, then polls.
	state.monthly_digest = election_notes
	state.monthly_digest.append_array(MonthlyDigestScript.build(state, before))
	state.monthly_digest.append_array(crisis_notes)
	state.monthly_digest.append_array(situation_notes)
	state.monthly_digest.append_array(world_notes)
	if poll_line != "":
		state.monthly_digest.append(poll_line)
```

- [ ] **Step 6: Update the direction-wording test (altered test)**

The old test pinned whole sentences. Its intent — each line says *improves* or *deteriorates* according to whether the movement is good — is unchanged; lines may now carry a cause after the figure. In `godot/tests/native/test_stability_and_digest.gd`, inside `_test_digest_direction_wording`, replace:

```gdscript
	t.equal(rising, [
		"Public approval improves (+1.0 points).",
		"Government stability improves (+1.0 points).",
		"Inflation deteriorates (+1.0 points).",
		"Regional pressure deteriorates (+10.0 points).",
		"Household hardship deteriorates (+10.0 points).",
	], "digest interprets positive movement according to the metric")
```

with:

```gdscript
	_starts(t, rising, [
		"Public approval improves (+1.0 points)",
		"Government stability improves (+1.0 points)",
		"Inflation deteriorates (+1.0 points)",
		"Regional pressure deteriorates (+10.0 points)",
		"Household hardship deteriorates (+10.0 points)",
	], "digest interprets positive movement according to the metric")
```

and replace:

```gdscript
	t.equal(falling, [
		"Public approval deteriorates (-1.0 points).",
		"Government stability deteriorates (-1.0 points).",
		"Inflation improves (-1.0 points).",
		"Regional pressure improves (-10.0 points).",
		"Household hardship improves (-10.0 points).",
	], "digest interprets negative movement according to the metric")
```

with:

```gdscript
	_starts(t, falling, [
		"Public approval deteriorates (-1.0 points)",
		"Government stability deteriorates (-1.0 points)",
		"Inflation improves (-1.0 points)",
		"Regional pressure improves (-10.0 points)",
		"Household hardship improves (-10.0 points)",
	], "digest interprets negative movement according to the metric")
```

and add this helper above `_initialize`:

```gdscript
func _starts(t, lines: Array[String], starts: Array, label: String) -> void:
	t.equal(lines.size(), starts.size(), "%s: one line per moved metric" % label)
	for i in mini(lines.size(), starts.size()):
		t.truth(lines[i].begins_with(String(starts[i])) and lines[i].ends_with("."), "%s: %s" % [label, starts[i]])
```

- [ ] **Step 7: Run both tests, see them pass**

Run: `"$GODOT" --headless --path godot --script res://tests/native/test_digest_causes.gd` and `"$GODOT" --headless --path godot --script res://tests/native/test_stability_and_digest.gd`
Expected: all `PASS`, exit 0 for both.

- [ ] **Step 8: Run the simulation suite for regressions**

Run the Task 0 loop restricted to `godot/tests/native/test_*.gd`.
Expected: matches the baseline. `approval_breakdown` changes no number; if any approval-dependent test moves, Step 3 summed in a different order — fix the order, not the test.

- [ ] **Step 9: Commit**

```bash
git add -- godot/scripts/native/sim/stability_sim.gd godot/scripts/native/presentation/monthly_digest.gd godot/scripts/native/native_game.gd godot/tests/native/test_stability_and_digest.gd godot/tests/native/test_digest_causes.gd
git commit -m "feat: the monthly report says why things moved

Approval and stability name what moved them, hardship names who it hits
hardest, and the report runs in order of consequence. The emergency-budget
line was appended last and fell below the fold of the report band; it now
leads. approval_breakdown is a pure extraction: approval is unchanged.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- godot/scripts/native/sim/stability_sim.gd godot/scripts/native/presentation/monthly_digest.gd godot/scripts/native/native_game.gd godot/tests/native/test_stability_and_digest.gd godot/tests/native/test_digest_causes.gd
```

---

### Task 7: Vital signs at 1280×720 (R6)

**Files:**
- Modify: `godot/scripts/ui/stat_bar.gd` (gauge guard)
- Modify: `godot/scripts/app.gd` (constants, `_resize_layout`, `_refresh_rooms`, `_refresh_region`; add `_is_compact`)
- Test: `godot/tests/ui/test_compact_vitals.gd`

**Interfaces:**
- Produces: `StatBar.GAUGE_MIN_WIDTH := 260.0`, `StatBar.shows_gauge() -> bool`.
- Produces: `app._is_compact() -> bool` — the one compact test, measured on the **effective** layout size (`window size / content_scale_factor`), used everywhere compactness is decided. Task 11's interface scale depends on it.
- Produces: `app.NATIONAL_WIDTH_WIDE := 288`, `app.NATIONAL_WIDTH_COMPACT := 236`.

- [ ] **Step 1: Write the failing test**

`godot/tests/ui/test_compact_vitals.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t = TestSupportScript.new()
	var h = AppHarness.new(self, "test_compact_vitals")
	var app: Node = await h.fresh()
	root.size = Vector2i(1280, 720)
	app._resize_layout()
	await h.frames(3)
	t.truth(app._is_compact(), "1280x720 is a compact layout")
	var national: Control = app.find_child("NationalPanel", true, false)
	t.truth(national.visible, "the government's vital signs survive a small window")
	t.equal(national.custom_minimum_size.x, float(app.NATIONAL_WIDTH_COMPACT), "in a narrower column")
	t.truth(app._vital_row("approval").visible, "approval is still on screen")

	root.size = Vector2i(1920, 1080)
	app._resize_layout()
	await h.frames(3)
	t.truth(not app._is_compact(), "1920x1080 is not compact")
	t.equal(national.custom_minimum_size.x, float(app.NATIONAL_WIDTH_WIDE), "and the column widens again")

	var bar := StatBar.new()
	root.add_child(bar)
	bar.set_meter("Stability", 0.5, "50%", UiPalette.GOOD)
	bar.size = Vector2(200, 22)
	t.truth(not bar.shows_gauge(), "a narrow meter drops its gauge and keeps its figure")
	bar.size = Vector2(300, 22)
	t.truth(bar.shows_gauge(), "a wide one keeps it")
	h.finish()
	quit(t.finish())
```

- [ ] **Step 2: Run it and watch it fail**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_compact_vitals.gd`
Expected: script error on `_is_compact`.

- [ ] **Step 3: Let `StatBar` drop its gauge when narrow**

In `godot/scripts/ui/stat_bar.gd`, add after `const ROW_H := 22`:

```gdscript
## Below this width the gauge would run into the figure; the figure stays.
const GAUGE_MIN_WIDTH := 260.0
```

add a function after `_ready`:

```gdscript
func shows_gauge() -> bool:
	return value >= 0.0 and size.x >= GAUGE_MIN_WIDTH
```

and in `_draw()` replace:

```gdscript
	if value < 0.0:
		return
```

with:

```gdscript
	if not shows_gauge():
		return
```

- [ ] **Step 4: Keep the national panel in compact mode, decided in one place**

In `godot/scripts/app.gd`, add after `const DATE_WIDTH_WIDE := 192`:

```gdscript
const NATIONAL_WIDTH_WIDE := 288
const NATIONAL_WIDTH_COMPACT := 236
```

Add this function directly above `func _resize_layout()`:

```gdscript
## The one test for a small layout, on the size the layout actually gets:
## the window divided by the interface scale.
func _is_compact() -> bool:
	var view := Vector2(get_window().size) / maxf(get_window().content_scale_factor, 0.01)
	return view.x < COMPACT_MAX_WIDTH or view.y < COMPACT_MAX_HEIGHT
```

In `_resize_layout()`, replace:

```gdscript
	var compact := get_window().size.x < COMPACT_MAX_WIDTH or get_window().size.y < COMPACT_MAX_HEIGHT
```

with:

```gdscript
	var compact := _is_compact()
```

and replace:

```gdscript
	find_child("NationalPanel").visible = not compact and not _desk_open()
```

with:

```gdscript
	var national := find_child("NationalPanel") as Control
	national.visible = not _desk_open()
	national.custom_minimum_size.x = NATIONAL_WIDTH_COMPACT if compact else NATIONAL_WIDTH_WIDE
```

In `_refresh_rooms()`, replace `var compact := get_window().size.y < COMPACT_MAX_HEIGHT` with `var compact := _is_compact()`. In `_refresh_region()`, replace `if get_window().size.x < 1500 or get_window().size.y < 850:` with `if _is_compact():`.

- [ ] **Step 5: Run the test, see it pass**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_compact_vitals.gd`
Expected: all `PASS`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add -- godot/scripts/ui/stat_bar.gd godot/scripts/app.gd godot/tests/ui/test_compact_vitals.gd
git commit -m "fix: keep the government's vital signs at 1280x720

Compact mode hid the whole national panel: approval, stability, political
capital, the economy and the assembly, with no other way to see them.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- godot/scripts/ui/stat_bar.gd godot/scripts/app.gd godot/tests/ui/test_compact_vitals.gd
```

---

### Task 8: Overlays and the confirm prompt (foundation for R2, R4, R7)

**Files:**
- Create: `godot/scripts/ui/overlay.gd`
- Create: `godot/scripts/ui/confirm_prompt.gd`
- Modify: `godot/scripts/app.gd` (`_clock_held`, `_input`, `_unhandled_key_input`)
- Test: `godot/tests/ui/test_overlays.gd`

**Interfaces:**
- Produces: `Overlay` (Control) — `body: VBoxContainer`, `set_title(text: String)`, `close()`, signal `closed`, `const GROUP := &"overlay"`, `static any_open(tree: SceneTree) -> bool`; Escape (`back`) calls overridable `_on_back()` (default `close()`).
- Produces: `ConfirmPrompt` (Overlay) — `static ask(host: Node, title: String, text: String, choices: Array) -> ConfirmPrompt` where `choices` is `[[id, label], ...]` (first = default, last = Escape); signal `chosen(choice: String)`; buttons named `Choice_<id>`.
- Produces: while any overlay is open the clock is held and the dashboard ignores its own keys.

- [ ] **Step 1: Write the failing test**

`godot/tests/ui/test_overlays.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")


func _initialize() -> void:
	_run.call_deferred()


func _day(app: Node) -> int:
	return int(app.snapshot.get("date", {}).get("day_index", -1))


func _run() -> void:
	var t = TestSupportScript.new()
	var h = AppHarness.new(self, "test_overlays")
	var app: Node = await h.fresh()
	var answer := [""]
	var prompt := ConfirmPrompt.ask(app, "Discard?", "Something was left unfinished.", [["yes", "Discard"], ["no", "Keep"]])
	prompt.chosen.connect(func(choice: String) -> void: answer[0] = choice)
	await h.frames()
	t.truth(Overlay.any_open(self), "a prompt counts as an open overlay")
	t.truth(app._clock_held(), "and holds the clock")
	var day := _day(app)
	await h.tick(3)
	t.equal(_day(app), day, "no day passes under a prompt")
	(prompt.find_child("Choice_yes", true, false) as Button).pressed.emit()
	await h.frames()
	t.equal(answer[0], "yes", "a pressed answer is reported")
	t.truth(not Overlay.any_open(self), "and the prompt is gone")
	t.truth(not app._clock_held(), "and the clock is free")

	var second := ConfirmPrompt.ask(app, "Leave?", "Progress will be lost.", [["leave", "Leave"], ["stay", "Stay"]])
	second.chosen.connect(func(choice: String) -> void: answer[0] = choice)
	await h.frames()
	var escape := InputEventAction.new()
	escape.action = "back"
	escape.pressed = true
	Input.parse_input_event(escape)
	await h.frames(3)
	t.equal(answer[0], "stay", "Escape takes the last, safe answer")
	t.truth(not app._desk_open(), "and does not also act on the dashboard")
	h.finish()
	quit(t.finish())
```

- [ ] **Step 2: Run it and watch it fail**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_overlays.gd`
Expected: parse error naming `ConfirmPrompt`.

- [ ] **Step 3: Write the overlay base**

`godot/scripts/ui/overlay.gd`:

```gdscript
class_name Overlay
extends Control

## A centred panel over a scrim. While any overlay is open the clock holds and
## the dashboard ignores its own keys; Escape belongs to the newest overlay.
## The confirm prompt, pause menu, options and save dialog are all overlays.

signal closed

const GROUP := &"overlay"

var body := VBoxContainer.new()
var _title := Label.new()


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(GROUP)
	var scrim := ColorRect.new()
	scrim.color = Color(UiPalette.WINDOW, 0.78)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	centre.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	_title.theme_type_variation = &"Title"
	body.add_child(_title)


func set_title(text: String) -> void:
	_title.text = text


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("back"):
		get_viewport().set_input_as_handled()
		_on_back()


func _on_back() -> void:
	close()


func close() -> void:
	remove_from_group(GROUP)
	closed.emit()
	queue_free()


static func any_open(tree: SceneTree) -> bool:
	return not tree.get_nodes_in_group(GROUP).is_empty()
```

- [ ] **Step 4: Write the confirm prompt**

`godot/scripts/ui/confirm_prompt.gd`:

```gdscript
class_name ConfirmPrompt
extends Overlay

## A question with two or three answers. The first answer is the default
## (Enter); the last is the way out (Escape). Await `chosen` for the answer.

signal chosen(choice: String)

var _cancel := ""


static func ask(host: Node, title: String, text: String, choices: Array) -> ConfirmPrompt:
	var prompt := ConfirmPrompt.new()
	prompt.set_title(title)
	var line := Label.new()
	line.name = "PromptText"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(400, 0)
	line.text = text
	prompt.body.add_child(line)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	prompt.body.add_child(row)
	for pair in choices:
		var button := Button.new()
		button.name = "Choice_%s" % String(pair[0])
		button.text = String(pair[1])
		button.custom_minimum_size = Vector2(0, 44)
		button.pressed.connect(prompt._choose.bind(String(pair[0])))
		row.add_child(button)
	prompt._cancel = String(choices[-1][0])
	host.add_child(prompt)
	(row.get_child(0) as Button).grab_focus.call_deferred()
	return prompt


func _on_back() -> void:
	_choose(_cancel)


func _choose(choice: String) -> void:
	chosen.emit(choice)
	close()
```

- [ ] **Step 5: Hold the clock and step aside for overlays**

In `godot/scripts/app.gd`, replace the body of `_clock_held()`:

```gdscript
	return _situation_open or (_budget_open and not _budget_adjustments.is_empty())
```

with:

```gdscript
	return _situation_open or (_budget_open and not _budget_adjustments.is_empty()) \
		or Overlay.any_open(get_tree())
```

In `_input()`, directly after `if _fatal or snapshot.is_empty():` / `return`, add:

```gdscript
	if Overlay.any_open(get_tree()):
		return
```

and make the same addition as the first statement of `_unhandled_key_input()`:

```gdscript
	if Overlay.any_open(get_tree()):
		return
```

- [ ] **Step 6: Refresh the cache, run the test, see it pass**

Run: `"$GODOT" --headless --path godot --import` then `"$GODOT" --headless --path godot --script res://tests/ui/test_overlays.gd`
Expected: all `PASS`, exit 0.

- [ ] **Step 7: Commit**

```bash
git add -- godot/scripts/ui/overlay.gd godot/scripts/ui/confirm_prompt.gd godot/scripts/app.gd godot/tests/ui/test_overlays.gd
git commit -m "feat: overlays and a confirm prompt that hold the clock

The project had no confirmation dialog anywhere. One overlay base gives the
prompt, and the pause menu, options and save dialog to come, the same scrim,
clock hold and Escape handling.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- godot/scripts/ui/overlay.gd godot/scripts/ui/confirm_prompt.gd godot/scripts/app.gd godot/tests/ui/test_overlays.gd
```

(Include the generated `.uid` files.)

---

### Task 9: Desks switch freely and keep the vitals in view (R7)

**Files:**
- Modify: `godot/scripts/app.gd` (`_ready` header wiring; `_open_budget`, `_open_legislation`, `_open_diplomacy`, `_open_records`, `_open_region_panel`, `_open_situation`, `_open_opposition`; `_refresh_controls`; `_resize_layout`; `_input`; add `_close_all_desks`, `_open_desk_name`, `_may_leave_desk`, `_go_to_desk`, `_request_close_desk`)
- Modify: `godot/tests/ui/test_app_behaviour.gd` (`_test_header_buttons_follow_the_open_desk`) — **altered test, see Step 6**
- Test: `godot/tests/ui/test_desk_navigation.gd`

**Interfaces:**
- Consumes: `ConfirmPrompt.ask`, `Overlay.GROUP` (Task 8).
- Produces: `app._go_to_desk(desk: String)` (await) for `"budget"`, `"legislation"`, `"diplomacy"`, `"records"`; `app._open_desk_name() -> String`; `app._request_close_desk()` (await); `app._close_all_desks()`. The guided year will call `_go_to_desk`.

- [ ] **Step 1: Write the failing test**

`godot/tests/ui/test_desk_navigation.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")


func _initialize() -> void:
	_run.call_deferred()


func _prompt() -> Node:
	var open := get_nodes_in_group(Overlay.GROUP)
	return open[0] if not open.is_empty() else null


func _run() -> void:
	var t = TestSupportScript.new()
	var h = AppHarness.new(self, "test_desk_navigation")
	var app: Node = await h.fresh()

	await app._go_to_desk("records")
	await app._go_to_desk("budget")
	await h.frames()
	t.truth(app._budget_open and not app._records_open, "switching from the record to the budget leaves one desk open")
	t.truth(not app.find_child("LegislationButton", true, false).disabled, "other destinations stay live beside an open desk")
	t.truth(app.find_child("NationalPanel", true, false).visible, "the vital signs stay in view beside a desk")
	await app._go_to_desk("budget")
	await h.frames()
	t.equal(app._open_desk_name(), "", "the open desk's own button closes it")

	await app._go_to_desk("budget")
	app._budget_adjustments["defense"] = 0.05
	app._go_to_desk("diplomacy")
	await h.frames()
	var prompt := _prompt()
	t.truth(prompt != null, "leaving a budget draft asks first")
	(prompt.find_child("Choice_stay", true, false) as Button).pressed.emit()
	await h.frames()
	t.truth(app._budget_open and not app._diplomacy_open, "keeping the draft stays on the budget")
	app._go_to_desk("diplomacy")
	await h.frames()
	(_prompt().find_child("Choice_discard", true, false) as Button).pressed.emit()
	await h.frames()
	t.truth(app._diplomacy_open and not app._budget_open, "discarding it moves on")

	app._situation_open = true
	await app._go_to_desk("records")
	t.truth(not app._situation_open, "opening any desk closes every other kind")
	h.finish()
	quit(t.finish())
```

- [ ] **Step 2: Run it and watch it fail**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_desk_navigation.gd`
Expected: script error on `_go_to_desk`.

- [ ] **Step 3: One way to close every desk**

In `godot/scripts/app.gd`, add directly above `func _open_budget()`:

```gdscript
## Every desk closes through here before another opens, so two can never be
## open at once (the record used to stay open under the budget).
func _close_all_desks() -> void:
	_budget_open = false
	_legislation_open = false
	_situation_open = false
	_diplomacy_open = false
	_opposition_open = false
	_records_open = false
	_region_panel_open = false


func _open_desk_name() -> String:
	if _budget_open:
		return "budget"
	if _legislation_open or _opposition_open:
		return "legislation"
	if _diplomacy_open:
		return "diplomacy"
	if _records_open:
		return "records"
	if _situation_open:
		return "situation"
	if _region_panel_open:
		return "region"
	return ""


## A budget draft that has not been tabled is the one thing a desk change can
## throw away, so leaving it asks.
func _may_leave_desk() -> bool:
	if not (_budget_open and not _budget_adjustments.is_empty()):
		return true
	var prompt := ConfirmPrompt.ask(self, "Discard the budget draft?",
		"You have moved envelopes that have not been tabled. Leaving the desk throws the changes away.",
		[["discard", "Discard draft"], ["stay", "Keep editing"]])
	var choice: String = await prompt.chosen
	return choice == "discard"


## Header destinations switch desks directly; the open desk's own button
## closes it.
func _go_to_desk(desk: String) -> void:
	var already := _open_desk_name() == desk
	if not await _may_leave_desk():
		return
	if already:
		_sfx_cue("navigation")
		_close_all_desks()
		_reset_budget_draft()
		_resize_layout()
		return
	match desk:
		"budget":
			_open_budget()
		"legislation":
			_open_legislation()
		"diplomacy":
			_open_diplomacy()
		"records":
			_open_records()


func _request_close_desk() -> void:
	if await _may_leave_desk():
		_close_open_desk()
```

Now make each opener close everything first. In each of the seven functions below, replace the listed run of flag assignments with the single line `_close_all_desks()`:

| Function | Replace these lines | With |
|---|---|---|
| `_open_budget` | `_diplomacy_open = false` / `_legislation_open = false` / `_situation_open = false` / `_opposition_open = false` | `_close_all_desks()` |
| `_open_legislation` | `_diplomacy_open = false` / `_budget_open = false` / `_situation_open = false` / `_opposition_open = false` | `_close_all_desks()` |
| `_open_diplomacy` | `_budget_open = false` / `_legislation_open = false` / `_situation_open = false` / `_opposition_open = false` | `_close_all_desks()` |
| `_open_records` | `_budget_open = false` / `_legislation_open = false` / `_situation_open = false` / `_opposition_open = false` / `_diplomacy_open = false` / `_region_panel_open = false` | `_close_all_desks()` |
| `_open_region_panel` | `_budget_open = false` / `_legislation_open = false` / `_situation_open = false` / `_opposition_open = false` / `_diplomacy_open = false` / `_records_open = false` | `_close_all_desks()` |
| `_open_situation` | `_diplomacy_open = false` / `_budget_open = false` / `_legislation_open = false` / `_opposition_open = false` | `_close_all_desks()` |
| `_open_opposition` | `_budget_open = false` / `_legislation_open = false` / `_situation_open = false` / `_diplomacy_open = false` | `_close_all_desks()` |

Each function's own `_x_open = true` line stays, after `_close_all_desks()`.

- [ ] **Step 4: Rewire the header and Escape**

In `_ready()`, replace these four connections:

```gdscript
	%BudgetButton.pressed.connect(_open_budget)
```
```gdscript
	%LegislationButton.pressed.connect(_open_legislation)
```
```gdscript
	%DiplomacyButton.pressed.connect(_open_diplomacy)
```
```gdscript
	%RecordsButton.pressed.connect(_open_records)
```

with, respectively:

```gdscript
	%BudgetButton.pressed.connect(_go_to_desk.bind("budget"))
```
```gdscript
	%LegislationButton.pressed.connect(_go_to_desk.bind("legislation"))
```
```gdscript
	%DiplomacyButton.pressed.connect(_go_to_desk.bind("diplomacy"))
```
```gdscript
	%RecordsButton.pressed.connect(_go_to_desk.bind("records"))
```

and replace `%BudgetPanel.find_child("CloseBudgetButton").pressed.connect(_close_budget)` with `%BudgetPanel.find_child("CloseBudgetButton").pressed.connect(_request_close_desk)`.

In `_input()`, replace:

```gdscript
	elif event.is_action_pressed("back") and _desk_open():
		_close_open_desk()
		get_viewport().set_input_as_handled()
```

with:

```gdscript
	elif event.is_action_pressed("back") and _desk_open():
		get_viewport().set_input_as_handled()
		_request_close_desk()
```

In `_refresh_controls()`, replace:

```gdscript
	%BudgetButton.disabled = not ready or _desk_open()
	%LegislationButton.disabled = not ready or _desk_open()
	%LegislationButton.text = "Legislation" if _in_government() else "Opposition"
	%DiplomacyButton.disabled = not ready or _desk_open()
	%RecordsButton.disabled = not ready or _desk_open()
```

with:

```gdscript
	%LegislationButton.text = "Legislation" if _in_government() else "Opposition"
	var open_desk := _open_desk_name()
	for pair in [["BudgetButton", "budget"], ["LegislationButton", "legislation"],
			["DiplomacyButton", "diplomacy"], ["RecordsButton", "records"]]:
		var button := find_child(pair[0]) as Button
		button.disabled = not ready
		# The open desk's own destination is lit: it is also the way to close it.
		if open_desk == pair[1]:
			button.add_theme_color_override("font_color", UiPalette.GOLD)
		else:
			button.remove_theme_color_override("font_color")
```

In `_resize_layout()`, replace `national.visible = not _desk_open()` (from Task 7) with `national.visible = true`.

- [ ] **Step 5: Run the new test, see it pass**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_desk_navigation.gd`
Expected: all `PASS`, exit 0.

- [ ] **Step 6: Update the header test (altered test)**

`_test_header_buttons_follow_the_open_desk` asserted the lockout this task removes on purpose. In `godot/tests/ui/test_app_behaviour.gd`, replace the whole function with:

```gdscript
func _test_header_buttons_follow_the_open_desk(t) -> void:
	await _fresh()
	app._paused = true
	app._open_budget()
	await _frames()
	t.truth(not app.find_child("LegislationButton", true, false).disabled, "an open desk does not lock the other destinations")
	app._close_budget()
	await _frames()
	t.truth(not app.find_child("LegislationButton", true, false).disabled, "and they stay live once it closes, even while paused")
```

Record in the task report: *the old assertion pinned the lockout that R7 removes; the replacement asserts the destinations stay reachable in both states.*

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_app_behaviour.gd`
Expected: matches the baseline apart from this function, which passes.

- [ ] **Step 7: Commit**

```bash
git add -- godot/scripts/app.gd godot/tests/ui/test_desk_navigation.gd godot/tests/ui/test_app_behaviour.gd
git commit -m "fix: desks switch directly and the vital signs stay beside them

Opening a desk disabled every other destination and hid approval at the
moment it mattered. Also fixes a latent bug: four desk openers left the
record open underneath. Leaving an untabled budget draft now asks.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- godot/scripts/app.gd godot/tests/ui/test_desk_navigation.gd godot/tests/ui/test_app_behaviour.gd
```

---

### Task 10: Data before decoration on the desks (R8)

**Files:**
- Modify: `godot/scripts/app.gd` (`_refresh_rooms`, `_budget_slider_row`)
- Modify: `godot/scenes/panels/budget_panel.tscn` (`SpendingChart` height)
- Test: `godot/tests/ui/test_desk_layout.gd`

**Interfaces:**
- Produces: `_budget_slider_row(envelope: Dictionary) -> HBoxContainer` (was `VBoxContainer`); children keep the names `EnvelopeName`, `Adjustment_<id>`, `EnvelopeAmount`, so `_sync_budget_sliders` is unchanged.

- [ ] **Step 1: Write the failing test**

`godot/tests/ui/test_desk_layout.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t = TestSupportScript.new()
	var h = AppHarness.new(self, "test_desk_layout")
	var app: Node = await h.fresh()
	root.size = Vector2i(1920, 1080)
	app._resize_layout()
	await app._go_to_desk("budget")
	await h.frames(8)
	var scroll: Control = app.find_child("EnvelopeScroll", true, false)
	var view: Rect2 = scroll.get_global_rect()
	var rows := app.find_child("BudgetRows", true, false).get_children()
	t.equal(rows.size(), 8, "the budget has eight envelopes")
	for row in rows:
		var r: Rect2 = (row as Control).get_global_rect()
		t.truth(r.end.y <= view.end.y + 1.0, "%s is on screen without scrolling" % row.name)
	var room: Control = app.find_child("BudgetPanel", true, false).find_child("Room", true, false)
	var column: Control = room.get_parent().get_child(0)
	t.truth(column.size.x >= 0.55 * (column.size.x + room.size.x), "the desk's controls take most of its width")
	h.finish()
	quit(t.finish())
```

- [ ] **Step 2: Run it and watch it fail**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_desk_layout.gd`
Expected: failures on the lower envelopes and on the column width.

- [ ] **Step 3: Give the data column the larger share**

In `_refresh_rooms()`, replace:

```gdscript
		column.custom_minimum_size.x = (460 if compact else 560) + (180 if panel_name == "BudgetPanel" else 0)
```

with:

```gdscript
		# Data before decoration: the desk's controls take three parts of the
		# width to the room's two, and never less than their minimum.
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_stretch_ratio = 3.0
		view.size_flags_stretch_ratio = 2.0
		column.custom_minimum_size.x = 460 if compact else 560
```

- [ ] **Step 4: One line per envelope**

Replace the whole `_budget_slider_row` function with:

```gdscript
## One line per envelope — name, slider, figure — so all eight fit on the desk
## at 1920x1080. Two-line rows pushed the largest envelope below the fold.
func _budget_slider_row(envelope: Dictionary) -> HBoxContainer:
	var envelope_id := str(envelope.get("id", ""))
	var steps: Array[float] = []
	for value in envelope.get("allowed_adjustments", [0.0]):
		steps.append(float(value))
	steps.sort()
	var row := HBoxContainer.new()
	row.name = "BudgetRow_%s" % envelope_id
	row.set_meta("envelope_id", envelope_id)
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.name = "EnvelopeName"
	label.text = str(envelope.get("name", envelope_id.capitalize()))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_stretch_ratio = 2.0
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = str(envelope.get("body", ""))
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	var slider := HSlider.new()
	slider.name = "Adjustment_%s" % envelope_id
	slider.custom_minimum_size = Vector2(0, 30)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_stretch_ratio = 3.0
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.min_value = steps[0]
	slider.max_value = steps[-1]
	# ponytail: uniform step from the catalogue; the sim only accepts its listed steps.
	slider.step = steps[1] - steps[0] if steps.size() > 1 else 1.0
	slider.tick_count = steps.size()
	slider.ticks_on_borders = true
	slider.value_changed.connect(_on_budget_slider.bind(envelope_id))
	var amount := Label.new()
	amount.name = "EnvelopeAmount"
	amount.custom_minimum_size = Vector2(190, 0)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	row.add_child(slider)
	row.add_child(amount)
	return row
```

In `godot/scenes/panels/budget_panel.tscn`, in the `[node name="SpendingChart" ...]` block change `custom_minimum_size = Vector2(0, 120)` to `custom_minimum_size = Vector2(0, 96)`.

- [ ] **Step 5: Run the test, see it pass**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_desk_layout.gd`
Expected: all `PASS`. If the last one or two rows still overflow, lower the slider row height in 2 px steps (minimum 26) and then `SpendingChart` in 8 px steps (minimum 80) until the test passes; record the final values in the report. Do not shrink text.

- [ ] **Step 6: Run the dashboard and player-copy tests**

Run `test_app_behaviour.gd` and `test_player_copy.gd`.
Expected: no new failures.

- [ ] **Step 7: Commit**

```bash
git add -- godot/scripts/app.gd godot/scenes/panels/budget_panel.tscn godot/tests/ui/test_desk_layout.gd
git commit -m "fix: desks give the data the larger share of the width

The room art took most of each desk and the budget's largest envelope,
health and welfare, sat below the fold at 1920x1080. Envelopes are now one
line each and the controls take three fifths of the desk.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- godot/scripts/app.gd godot/scenes/panels/budget_panel.tscn godot/tests/ui/test_desk_layout.gd
```

---

### Task 11: The settings store and separate audio buses (R3, part 1)

**Files:**
- Create: `godot/scripts/ui/audio_buses.gd`
- Create: `godot/scripts/settings.gd`
- Modify: `godot/project.godot` (`[autoload]`)
- Modify: `godot/scripts/ambience.gd` (`_player`), `godot/scripts/ui_sfx.gd` (`_ready`)
- Modify: `godot/scripts/app.gd` (`_ready`: relayout on settings change)
- Test: `godot/tests/native/test_settings.gd`

**Interfaces:**
- Produces: `AudioBuses.ensure(bus: StringName) -> StringName` — creates the bus under Master on first use.
- Produces: autoload `Settings` — `get_value(key: String) -> Variant`, `set_value(key: String, value: Variant) -> void`, signal `changed(key: String)`, property `path: String`, `load_from_disk()`, `apply_all()`, `static fitting_scale(chosen: float, window_size: Vector2) -> float`, `const UI_SCALES: Array[float] = [1.0, 1.15, 1.3]`. Keys exactly: `display/fullscreen` (bool), `display/ui_scale` (float), `audio/music` (float 0..1), `audio/effects` (float 0..1), `gameplay/autosave` (bool). The guided year will add `guide/default` and `guide/completed_year`.
- Master volume and mute stay owned by `Ambience` (`user://audio.cfg`), unchanged.

- [ ] **Step 1: Write the failing test**

`godot/tests/native/test_settings.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const SettingsScript = preload("res://scripts/settings.gd")
const TEST_PATH := "user://test_settings.cfg"


func _initialize() -> void:
	_run.call_deferred()


func _fresh() -> Node:
	var settings: Node = SettingsScript.new()
	settings.path = TEST_PATH
	settings.load_from_disk()
	return settings


func _run() -> void:
	var t = TestSupportScript.new()
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	var settings := _fresh()
	t.equal(settings.get_value("gameplay/autosave"), true, "autosave is on by default")
	t.equal(settings.get_value("display/ui_scale"), 1.0, "the interface starts at 100%")
	var heard := [""]
	settings.changed.connect(func(key: String) -> void: heard[0] = key)
	settings.set_value("gameplay/autosave", false)
	settings.set_value("audio/music", 0.25)
	t.equal(heard[0], "audio/music", "a change is announced")
	var again := _fresh()
	t.equal(again.get_value("gameplay/autosave"), false, "a preference survives a restart")
	t.near(float(again.get_value("audio/music")), 0.25, 0.0001, "so does a volume")

	var music := AudioServer.get_bus_index(AudioBuses.ensure(&"Music"))
	t.truth(music >= 0, "music has its own bus")
	t.equal(AudioServer.get_bus_send(music), &"Master", "under the master volume")
	t.near(AudioServer.get_bus_volume_db(music), linear_to_db(0.25), 0.01, "at the chosen level")
	t.equal(AudioServer.get_bus_index(AudioBuses.ensure(&"Music")), music, "asking twice does not make a second bus")

	t.equal(SettingsScript.fitting_scale(1.3, Vector2(1920, 1080)), 1.3, "130% fits a 1080p window")
	t.equal(SettingsScript.fitting_scale(1.3, Vector2(1280, 720)), 1.0, "but not a 720p one, which keeps 100%")
	t.equal(SettingsScript.fitting_scale(1.3, Vector2(1600, 900)), 1.15, "a middling window gets the largest scale that fits")
	DirAccess.remove_absolute(TEST_PATH)
	settings.free()
	again.free()
	quit(t.finish())
```

- [ ] **Step 2: Run it and watch it fail**

Run: `"$GODOT" --headless --path godot --script res://tests/native/test_settings.gd`
Expected: load error for `res://scripts/settings.gd`.

- [ ] **Step 3: Write the audio buses helper**

`godot/scripts/ui/audio_buses.gd`:

```gdscript
class_name AudioBuses
extends RefCounted

## Music and effects get their own buses under Master so the player can set
## them apart. Created on first use; asking again returns the same bus.

static func ensure(bus: StringName) -> StringName:
	if AudioServer.get_bus_index(bus) < 0:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, &"Master")
	return bus
```

- [ ] **Step 4: Write the settings store**

`godot/scripts/settings.gd`:

```gdscript
extends Node

## The player's preferences: display, the music and effects levels below the
## master, and autosave. One file between sessions, applied at start. Master
## volume and mute stay with `Ambience`, which already owns them. Campaign
## state never lives here, and preferences never live in a save.

signal changed(key: String)

const PATH := "user://settings.cfg"
const UI_SCALES: Array[float] = [1.0, 1.15, 1.3]
## The smallest layout the dashboard is built for; a scale that would leave
## less than this is not used.
const MIN_LAYOUT := Vector2(1280, 720)
const DEFAULTS := {
	"display/fullscreen": false,
	"display/ui_scale": 1.0,
	"audio/music": 0.8,
	"audio/effects": 0.8,
	"gameplay/autosave": true,
}

var path := PATH
var _values := {}


func _ready() -> void:
	load_from_disk()
	apply_all()
	get_tree().root.size_changed.connect(_apply_ui_scale)


func load_from_disk() -> void:
	_values = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	for key: String in DEFAULTS:
		var parts := key.split("/")
		var stored: Variant = config.get_value(parts[0], parts[1], DEFAULTS[key])
		if DEFAULTS[key] is float and (stored is float or stored is int):
			_values[key] = float(stored)
		elif typeof(stored) == typeof(DEFAULTS[key]):
			_values[key] = stored


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_error("Unknown setting '%s'" % key)
		return
	_values[key] = value
	var config := ConfigFile.new()
	for stored_key: String in _values:
		var parts := stored_key.split("/")
		config.set_value(parts[0], parts[1], _values[stored_key])
	config.save(path)
	apply_all()
	changed.emit(key)


func apply_all() -> void:
	_set_bus_volume(&"Music", float(get_value("audio/music")))
	_set_bus_volume(&"Effects", float(get_value("audio/effects")))
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(get_value("display/fullscreen")) \
			else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	_apply_ui_scale()


func _apply_ui_scale() -> void:
	if not is_inside_tree():
		return
	var window := get_tree().root
	window.content_scale_factor = fitting_scale(float(get_value("display/ui_scale")), Vector2(window.size))


## The largest scale, up to the one chosen, that still leaves the dashboard
## its minimum layout.
static func fitting_scale(chosen: float, window_size: Vector2) -> float:
	var best := 1.0
	for scale in UI_SCALES:
		if scale <= chosen + 0.001 and window_size.x / scale >= MIN_LAYOUT.x \
				and window_size.y / scale >= MIN_LAYOUT.y:
			best = maxf(best, scale)
	return best


static func _set_bus_volume(bus: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(AudioBuses.ensure(bus))
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(index, linear <= 0.0)
```

- [ ] **Step 5: Register it and route the sounds**

In `godot/project.godot`, in the `[autoload]` section, add the line `Settings="*res://scripts/settings.gd"` directly after the `GameFlow=` line (before `UiSfx` and `Ambience`).

In `godot/scripts/ambience.gd`, in `_player()`, replace `player.bus = &"Master"` with `player.bus = AudioBuses.ensure(&"Music")`.

In `godot/scripts/ui_sfx.gd`, in `_ready()`, replace `player.bus = &"Master"` with `player.bus = AudioBuses.ensure(&"Effects")`.

In `godot/scripts/app.gd` `_ready()`, directly after `get_window().size_changed.connect(_resize_layout)`, add:

```gdscript
	var settings := get_node_or_null("/root/Settings")
	if settings != null:
		settings.changed.connect(func(_key: String) -> void: _resize_layout())
```

- [ ] **Step 6: Refresh the cache, run the tests, see them pass**

Run: `"$GODOT" --headless --path godot --import`, then `test_settings.gd` and `godot/tests/native/test_ambience.gd`, `godot/tests/native/test_ui_sfx.gd`.
Expected: all `PASS`, exit 0.

- [ ] **Step 7: Commit**

```bash
git add -- godot/scripts/ui/audio_buses.gd godot/scripts/settings.gd godot/project.godot godot/scripts/ambience.gd godot/scripts/ui_sfx.gd godot/scripts/app.gd godot/tests/native/test_settings.gd
git commit -m "feat: a settings store, and music and effects on their own buses

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- godot/scripts/ui/audio_buses.gd godot/scripts/settings.gd godot/project.godot godot/scripts/ambience.gd godot/scripts/ui_sfx.gd godot/scripts/app.gd godot/tests/native/test_settings.gd
```

(Include the generated `.uid` files.)

---

### Task 12: The options screen (R3, part 2)

**Files:**
- Create: `godot/scripts/ui/options_panel.gd`
- Modify: `godot/scenes/menu.tscn` (add `OptionsButton`), `godot/scripts/menu.gd`
- Test: `godot/tests/ui/test_options_panel.gd`

**Interfaces:**
- Consumes: `Overlay` (Task 8), `Settings` (Task 11), `SoundControl` (existing), `Keys.label` (Task 3).
- Produces: `OptionsPanel` (Overlay) — `static open(host: Node) -> OptionsPanel`; controls named `Fullscreen` (CheckButton), `UiScale` (OptionButton), `MusicVolume` and `EffectsVolume` (HSlider), `Autosave` (CheckButton), `KeyRow_<action>` (Label rows), `DoneButton`.

- [ ] **Step 1: Write the failing test**

`godot/tests/ui/test_options_panel.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const KEY_ACTIONS := ["pause", "next_decision", "save", "load", "back"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t = TestSupportScript.new()
	var settings: Node = root.get_node("Settings")
	var saved_path: String = settings.path
	settings.path = "user://test_options_settings.cfg"
	var host := Control.new()
	root.add_child(host)
	var panel := OptionsPanel.open(host)
	await process_frame
	t.truth(Overlay.any_open(self), "options open as an overlay")

	var autosave: CheckButton = panel.find_child("Autosave", true, false)
	autosave.button_pressed = not bool(settings.get_value("gameplay/autosave"))
	t.equal(settings.get_value("gameplay/autosave"), autosave.button_pressed, "the autosave switch is the setting")
	var music: HSlider = panel.find_child("MusicVolume", true, false)
	music.value = 0.3
	t.near(float(settings.get_value("audio/music")), 0.3, 0.0001, "the music slider is the setting")
	var scale: OptionButton = panel.find_child("UiScale", true, false)
	t.equal(scale.item_count, 3, "three interface scales are offered")

	for action in KEY_ACTIONS:
		var row: Label = panel.find_child("KeyRow_%s" % action, true, false)
		t.truth(row != null and row.text.contains(Keys.label(action)), "the key list shows the real key for %s" % action)

	(panel.find_child("DoneButton", true, false) as Button).pressed.emit()
	await process_frame
	t.truth(not Overlay.any_open(self), "Done closes the options")
	DirAccess.remove_absolute(settings.path)
	settings.path = saved_path
	settings.load_from_disk()
	quit(t.finish())
```

- [ ] **Step 2: Run it and watch it fail**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_options_panel.gd`
Expected: parse error naming `OptionsPanel`.

- [ ] **Step 3: Write the options panel**

`godot/scripts/ui/options_panel.gd`:

```gdscript
class_name OptionsPanel
extends Overlay

## Display, sound, autosave and the key list. Every control writes straight to
## `Settings` (master volume and mute to `Ambience`, through the same control
## the header uses). The key list is read from the live InputMap.

const SettingsScript = preload("res://scripts/settings.gd")
const KEY_ROWS := [
	["pause", "Start or stop the clock"],
	["next_decision", "Go to the next waiting decision"],
	["save", "Save into the current slot"],
	["load", "Choose a save to load"],
	["back", "Close a desk, or open this menu"],
]


static func open(host: Node) -> OptionsPanel:
	var panel := OptionsPanel.new()
	panel.set_title("Options")
	var settings := host.get_node("/root/Settings")

	panel._section("Display")
	var fullscreen := CheckButton.new()
	fullscreen.name = "Fullscreen"
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = bool(settings.get_value("display/fullscreen"))
	fullscreen.toggled.connect(func(on: bool) -> void: settings.set_value("display/fullscreen", on))
	panel.body.add_child(fullscreen)
	var scale := OptionButton.new()
	scale.name = "UiScale"
	scale.tooltip_text = "Interface scale"
	for value: float in SettingsScript.UI_SCALES:
		scale.add_item("Interface %d%%" % roundi(value * 100.0))
		if is_equal_approx(value, float(settings.get_value("display/ui_scale"))):
			scale.select(scale.item_count - 1)
	scale.item_selected.connect(func(index: int) -> void: settings.set_value("display/ui_scale", SettingsScript.UI_SCALES[index]))
	panel.body.add_child(scale)
	panel._note("Larger scales need a larger window; Ardenia uses the largest that fits.")

	panel._section("Sound")
	var master := SoundControl.new()
	master.tooltip_text = "Master volume"
	panel.body.add_child(master)
	panel._slider("MusicVolume", "Music and ambience", "audio/music", settings)
	panel._slider("EffectsVolume", "Effects", "audio/effects", settings)

	panel._section("Gameplay")
	var autosave := CheckButton.new()
	autosave.name = "Autosave"
	autosave.text = "Autosave at the start of each month"
	autosave.button_pressed = bool(settings.get_value("gameplay/autosave"))
	autosave.toggled.connect(func(on: bool) -> void: settings.set_value("gameplay/autosave", on))
	panel.body.add_child(autosave)

	panel._section("Controls")
	var speeds := Label.new()
	speeds.name = "KeyRow_speeds"
	speeds.text = "%s – %s    Set the clock speed" % [Keys.label("speed_1"), Keys.label("speed_5")]
	panel.body.add_child(speeds)
	for row in KEY_ROWS:
		var line := Label.new()
		line.name = "KeyRow_%s" % row[0]
		line.text = "%s    %s" % [Keys.label(row[0]), row[1]]
		panel.body.add_child(line)

	var done := Button.new()
	done.name = "DoneButton"
	done.text = "Done"
	done.custom_minimum_size = Vector2(0, 44)
	done.pressed.connect(panel.close)
	panel.body.add_child(done)
	host.add_child(panel)
	done.grab_focus.call_deferred()
	return panel


func _section(text: String) -> void:
	var heading := Label.new()
	heading.theme_type_variation = &"Section"
	heading.text = text
	body.add_child(heading)


func _note(text: String) -> void:
	var note := Label.new()
	note.theme_type_variation = &"Muted"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(400, 0)
	note.text = text
	body.add_child(note)


func _slider(node_name: String, text: String, key: String, settings: Node) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(180, 0)
	slider.value = float(settings.get_value(key))
	slider.value_changed.connect(func(v: float) -> void: settings.set_value(key, v))
	row.add_child(label)
	row.add_child(slider)
	body.add_child(row)
```

- [ ] **Step 4: Put Options on the main menu**

In `godot/scenes/menu.tscn`, insert directly before the `[node name="QuitButton" ...]` block:

```
[node name="OptionsButton" type="Button" parent="Center/Plate/Layout"]
unique_name_in_owner = true
custom_minimum_size = Vector2(360, 48)
layout_mode = 2
text = "Options"

```

In `godot/scripts/menu.gd` `_ready()`, directly after `%ContinueButton.pressed.connect(_continue_campaign)` add:

```gdscript
	%OptionsButton.pressed.connect(func() -> void:
		_sfx_cue("navigation")
		OptionsPanel.open(self))
```

- [ ] **Step 5: Refresh the cache, run the test, see it pass**

Run: `"$GODOT" --headless --path godot --import` then `"$GODOT" --headless --path godot --script res://tests/ui/test_options_panel.gd`
Expected: all `PASS`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add -- godot/scripts/ui/options_panel.gd godot/scenes/menu.tscn godot/scripts/menu.gd godot/tests/ui/test_options_panel.gd
git commit -m "feat: an options screen — display, sound, autosave and the keys

There was no options menu at all. The key list is read from the InputMap so
it can never disagree with the bindings.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- godot/scripts/ui/options_panel.gd godot/scenes/menu.tscn godot/scripts/menu.gd godot/tests/ui/test_options_panel.gd
```

(Include the generated `.uid` file.)

---

### Task 13: Save slots, confirmations and autosave (R4)

**Files:**
- Modify: `godot/scripts/native/state/save_store.gd` (meta, slots)
- Modify: `godot/scripts/native/native_game.gd` (`save` writes meta)
- Create: `godot/scripts/ui/save_dialog.gd`
- Modify: `godot/scripts/app.gd` (`SAVE_SLOT`, members, `_ready`, `_process`, `_do_new_campaign`, `_do_save`, `_do_load`, `_unhandled_key_input`; add `_has_unsaved_progress`, `_open_save_dialog`, `_autosave`)
- Modify: `godot/scripts/game_flow.gd`, `godot/scripts/menu.gd`
- Test: `godot/tests/native/test_save_slots.gd`, `godot/tests/ui/test_save_dialog.gd`

**Interfaces:**
- Produces: `SaveStore.save_slot(slot: String, state: GameState, meta: Dictionary = {}) -> Dictionary`; `SaveStore.AUTOSAVE_SLOT := "autosave"`, `SaveStore.MANUAL_SLOTS`, `SaveStore.LEGACY_SLOT := "godot_slice"`; `static player_slots() -> Array[String]`; `static slot_label(slot: String) -> String`; `static slot_info(slot: String) -> Dictionary` (`slot`, `exists`, and when it exists `saved_unix: int`, `date_text: String`, `leader: String`); `static most_recent_slot(slots: Array[String]) -> String`.
- Produces: `SaveDialog` (Overlay) — `static open(host: Node, mode: String, unsaved: bool, slots: Array[String] = []) -> SaveDialog` (an empty `slots` means `SaveStore.player_slots()`); signal `finished(slot: String)` (`""` when cancelled); rows named `Slot_<slot>`.
- Produces: `app.autosave_slot: String` (default `SaveStore.AUTOSAVE_SLOT`, `""` disables), `app._has_unsaved_progress() -> bool`, `app._open_save_dialog(mode: String)` (await). `GameFlow.continue_slot: String`.

- [ ] **Step 1: Write the failing store test**

`godot/tests/native/test_save_slots.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const SLOTS: Array[String] = ["zz_slots_a", "zz_slots_b"]


func _initialize() -> void:
	_run.call_deferred()


func _wipe() -> void:
	for slot in SLOTS:
		for suffix in ["", ".tmp", ".bak"]:
			var path := "user://saves/%s.json%s" % [slot, suffix]
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


func _run() -> void:
	var t = TestSupportScript.new()
	_wipe()
	var game: Node = root.get_node("NativeGame")
	game.new_campaign({"country_id": "ardenia", "background_id": "none", "difficulty_id": "normal", "opening_role": "contextual", "seed": 424242})
	t.equal(SaveStore.slot_info(SLOTS[0])["exists"], false, "an unused slot is empty")
	t.equal(SaveStore.most_recent_slot(SLOTS), "", "and there is nothing to continue")
	t.truth(game.save(SLOTS[0]).get("ok", false), "a campaign saves")
	var info := SaveStore.slot_info(SLOTS[0])
	t.equal(info["date_text"], "1 Mar 1993", "the slot knows the campaign's date")
	t.truth(String(info["leader"]) != "", "and whose campaign it is")
	t.truth(game.load(SLOTS[0]).get("ok", false), "a save with its label still loads")
	OS.delay_msec(1100)
	SaveStore.save_slot(SLOTS[1], game._state)
	t.equal(SaveStore.slot_info(SLOTS[1])["date_text"], "", "a save without a label reads as unlabelled, not broken")
	t.equal(SaveStore.most_recent_slot(SLOTS), SLOTS[1], "the newest save is the one to continue")
	t.equal(SaveStore.slot_label("autosave"), "Autosave", "slots have player names")
	t.equal(SaveStore.slot_label("slot_2"), "Slot 2", "numbered ones too")
	t.equal(SaveStore.slot_label("godot_slice"), "Earlier save", "and the old single save")
	var slots := SaveStore.player_slots()
	t.equal(slots.slice(0, 4), ["autosave", "slot_1", "slot_2", "slot_3"], "the player's slots, autosave first")
	_wipe()
	quit(t.finish())
```

- [ ] **Step 2: Run it and watch it fail**

Run: `"$GODOT" --headless --path godot --script res://tests/native/test_save_slots.gd`
Expected: script error on `slot_info`.

- [ ] **Step 3: Teach the save store about slots**

In `godot/scripts/native/state/save_store.gd`, add after `const SLOT_PATTERN := ...`:

```gdscript
const AUTOSAVE_SLOT := "autosave"
const MANUAL_SLOTS: Array[String] = ["slot_1", "slot_2", "slot_3"]
## The single slot the game used before slots existed.
const LEGACY_SLOT := "godot_slice"
```

Change the signature `static func save_slot(slot: String, state: GameState) -> Dictionary:` to `static func save_slot(slot: String, state: GameState, meta: Dictionary = {}) -> Dictionary:` and replace `var payload := {"version": SAVE_FORMAT_VERSION, "state": state.to_dict()}` with `var payload := {"version": SAVE_FORMAT_VERSION, "meta": meta, "state": state.to_dict()}`.

Add at the end of the file:

```gdscript
## The slots a player sees: autosave, the three manual slots, and the old
## single save if one is on disk.
static func player_slots() -> Array[String]:
	var slots: Array[String] = [AUTOSAVE_SLOT]
	slots.append_array(MANUAL_SLOTS)
	if FileAccess.file_exists(_path_for(LEGACY_SLOT, "")):
		slots.append(LEGACY_SLOT)
	return slots


static func slot_label(slot: String) -> String:
	if slot == AUTOSAVE_SLOT:
		return "Autosave"
	if slot == LEGACY_SLOT:
		return "Earlier save"
	if slot.begins_with("slot_"):
		return "Slot %s" % slot.trim_prefix("slot_")
	return slot.capitalize()


## What a slot holds, for a list: whose campaign, its date, when it was saved.
## A save written before labels existed reports empty strings, not an error.
static func slot_info(slot: String) -> Dictionary:
	var path := _path_for(slot, "")
	if not is_valid_slot(slot) or not FileAccess.file_exists(path):
		return {"slot": slot, "exists": false}
	var info := {"slot": slot, "exists": true, "saved_unix": FileAccess.get_modified_time(path),
		"date_text": "", "leader": ""}
	var parsed: Variant = _read_payload(path)
	if parsed is Dictionary and (parsed as Dictionary).get("meta") is Dictionary:
		var meta: Dictionary = parsed["meta"]
		info["date_text"] = String(meta.get("date_text", ""))
		info["leader"] = String(meta.get("leader", ""))
	return info


static func most_recent_slot(slots: Array[String]) -> String:
	var best := ""
	var best_time := -1
	for slot in slots:
		var info := slot_info(slot)
		if bool(info["exists"]) and int(info["saved_unix"]) > best_time:
			best = slot
			best_time = int(info["saved_unix"])
	return best
```

In `godot/scripts/native/native_game.gd` `save()`, replace `var result := SaveStoreScript.save_slot(slot, _state)` with:

```gdscript
	var meta := {"date_text": _date_text(_state),
		"leader": _state.player.name if _state.player != null else ""}
	var result := SaveStoreScript.save_slot(slot, _state, meta)
```

- [ ] **Step 4: Run the store test, see it pass**

Run: `"$GODOT" --headless --path godot --script res://tests/native/test_save_slots.gd`, then `godot/tests/native/test_native_persistence.gd`.
Expected: all `PASS` in both (persistence still round-trips).

- [ ] **Step 5: Write the failing dialog test**

`godot/tests/ui/test_save_dialog.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")
const SLOTS: Array[String] = ["zz_dialog_a", "zz_dialog_b"]


func _initialize() -> void:
	_run.call_deferred()


func _wipe() -> void:
	for slot in SLOTS:
		for suffix in ["", ".tmp", ".bak"]:
			var path := "user://saves/%s.json%s" % [slot, suffix]
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


func _newest_overlay() -> Node:
	var open := get_nodes_in_group(Overlay.GROUP)
	return open[-1] if not open.is_empty() else null


func _run() -> void:
	var t = TestSupportScript.new()
	_wipe()
	var h = AppHarness.new(self, SLOTS[0])
	var app: Node = await h.fresh()
	app._do_save()
	t.truth(not app._has_unsaved_progress(), "a fresh save leaves nothing unsaved")
	await h.tick(2)
	t.truth(app._has_unsaved_progress(), "two days later there is")

	var got := ["unset"]
	var dialog := SaveDialog.open(app, "save", false, SLOTS)
	dialog.finished.connect(func(slot: String) -> void: got[0] = slot)
	await h.frames()
	var used: Button = dialog.find_child("Slot_%s" % SLOTS[0], true, false)
	t.truth(used.text.contains("1 Mar 1993"), "a used slot shows its campaign's date")
	used.pressed.emit()
	await h.frames()
	t.truth(_newest_overlay() is ConfirmPrompt, "saving over a used slot asks first")
	(_newest_overlay().find_child("Choice_cancel", true, false) as Button).pressed.emit()
	await h.frames()
	t.equal(got[0], "unset", "and cancelling saves nothing")
	(dialog.find_child("Slot_%s" % SLOTS[1], true, false) as Button).pressed.emit()
	await h.frames()
	t.equal(got[0], SLOTS[1], "an empty slot is taken without a question")

	var loading := SaveDialog.open(app, "load", true, SLOTS)
	await h.frames()
	t.truth((loading.find_child("Slot_%s" % SLOTS[1], true, false) as Button).disabled, "an empty slot cannot be loaded")
	(loading.find_child("Slot_%s" % SLOTS[0], true, false) as Button).pressed.emit()
	await h.frames()
	t.truth(_newest_overlay() is ConfirmPrompt, "loading over unsaved progress asks first")
	(_newest_overlay().find_child("Choice_cancel", true, false) as Button).pressed.emit()
	await h.frames()
	loading.close()
	await h.frames()

	var key := InputEventKey.new()
	key.physical_keycode = KEY_L
	key.pressed = true
	Input.parse_input_event(key)
	await h.frames(3)
	t.truth(_newest_overlay() is SaveDialog, "the load key opens the list instead of reloading at once")
	h.finish()
	_wipe()
	quit(t.finish())
```

- [ ] **Step 6: Run it and watch it fail**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_save_dialog.gd`
Expected: script error on `_has_unsaved_progress` / parse error on `SaveDialog`.

- [ ] **Step 7: Write the save dialog**

`godot/scripts/ui/save_dialog.gd`:

```gdscript
class_name SaveDialog
extends Overlay

## Choose a slot to save into or load from. Each row says whose campaign it
## holds, its date in the game and when it was saved. Saving over a used slot
## and loading over unsaved progress both ask first. `finished` reports the
## chosen slot, or "" when the player backs out.

signal finished(slot: String)

var mode := "save"
var unsaved := false
var _host: Node


static func open(host: Node, mode: String, unsaved: bool, slots: Array[String] = []) -> SaveDialog:
	if slots.is_empty():
		slots = SaveStore.player_slots()
	var dialog := SaveDialog.new()
	dialog.mode = mode
	dialog.unsaved = unsaved
	dialog._host = host
	dialog.set_title("Save the campaign" if mode == "save" else "Load a campaign")
	for slot in slots:
		var info := SaveStore.slot_info(slot)
		var button := Button.new()
		button.name = "Slot_%s" % slot
		button.custom_minimum_size = Vector2(520, 48)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = dialog._row_text(slot, info)
		var read_only := mode == "save" and (slot == SaveStore.AUTOSAVE_SLOT or slot == SaveStore.LEGACY_SLOT)
		button.disabled = read_only or (mode == "load" and not bool(info["exists"]))
		button.pressed.connect(dialog._pick.bind(slot, info))
		dialog.body.add_child(button)
	var cancel := Button.new()
	cancel.name = "CancelButton"
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 44)
	cancel.pressed.connect(dialog._finish.bind(""))
	dialog.body.add_child(cancel)
	host.add_child(dialog)
	cancel.grab_focus.call_deferred()
	return dialog


func _row_text(slot: String, info: Dictionary) -> String:
	var label := SaveStore.slot_label(slot)
	if not bool(info["exists"]):
		return "%s   ·   Empty" % label
	# File times are UTC; the player reads their own clock.
	var bias_minutes := int(Time.get_time_zone_from_system().get("bias", 0))
	var local_unix := int(info["saved_unix"]) + bias_minutes * 60
	var saved := Time.get_datetime_string_from_unix_time(local_unix, true).substr(0, 16)
	var who := String(info["leader"]) if String(info["leader"]) != "" else "A campaign"
	var when := String(info["date_text"])
	if when == "":
		return "%s   ·   %s   ·   saved %s" % [label, who, saved]
	return "%s   ·   %s, %s   ·   saved %s" % [label, who, when, saved]


func _pick(slot: String, info: Dictionary) -> void:
	if mode == "save" and bool(info["exists"]):
		var prompt := ConfirmPrompt.ask(_host, "Overwrite %s?" % SaveStore.slot_label(slot),
			"It holds %s. Saving here replaces it." % _row_text(slot, info).get_slice("·", 1).strip_edges(),
			[["overwrite", "Overwrite"], ["cancel", "Cancel"]])
		var overwrite: String = await prompt.chosen
		if overwrite != "overwrite":
			return
	elif mode == "load" and unsaved:
		var prompt := ConfirmPrompt.ask(_host, "Load this save?",
			"Progress since your last save will be lost.",
			[["load", "Load"], ["cancel", "Cancel"]])
		var answer: String = await prompt.chosen
		if answer != "load":
			return
	_finish(slot)


func _on_back() -> void:
	_finish("")


func _finish(slot: String) -> void:
	finished.emit(slot)
	close()
```

- [ ] **Step 8: Wire slots, unsaved progress and autosave into the dashboard**

In `godot/scripts/game_flow.gd`, add `var continue_slot := ""`.

In `godot/scripts/app.gd`:

Replace `const SAVE_SLOT := "godot_slice"` with `const SAVE_SLOT := "slot_1"`.

Add members after `var _notice := StatusNotice.new()`:

```gdscript
## The slot autosave writes; "" turns it off (tests do this).
var autosave_slot := SaveStore.AUTOSAVE_SLOT
var _saved_hash := 0
```

Add these functions directly above `func _do_save()`:

```gdscript
func _has_unsaved_progress() -> bool:
	return not snapshot.is_empty() and snapshot.hash() != _saved_hash


func _open_save_dialog(mode: String) -> void:
	if _fatal or snapshot.is_empty():
		return
	var dialog := SaveDialog.open(self, mode, _has_unsaved_progress())
	var slot: String = await dialog.finished
	if slot == "":
		return
	save_slot = slot
	if mode == "save":
		_do_save()
	else:
		_do_load()


func _autosave() -> void:
	if autosave_slot == "":
		return
	var settings := get_node_or_null("/root/Settings")
	if settings != null and not bool(settings.get_value("gameplay/autosave")):
		return
	var result: Dictionary = _game.save(autosave_slot)
	if result.get("ok", false):
		_saved_hash = snapshot.hash()
		_notice.say("Autosaved")
	else:
		_notice.say("Autosave failed: %s" % result.get("error", "unknown error"), true)
```

In `_do_save()`, replace `_notice.say("Saved")` with:

```gdscript
		_saved_hash = snapshot.hash()
		_notice.say("Saved to %s" % SaveStore.slot_label(save_slot))
```

In `_do_load()`, directly after the final `apply_snapshot(load_snap)` add `_saved_hash = snapshot.hash()`. In `_do_new_campaign()`, directly after its `apply_snapshot(new_snap)` add `_saved_hash = snapshot.hash()`.

In `_process()`, replace:

```gdscript
		elif bool(result.get("month_rolled", false)):
			_sfx_cue("month_rollover")
```

with:

```gdscript
		elif bool(result.get("month_rolled", false)):
			_sfx_cue("month_rollover")
			_autosave()
```

In `_ready()`, replace `find_child("SaveButton").pressed.connect(_do_save)` with `find_child("SaveButton").pressed.connect(_open_save_dialog.bind("save"))` and `find_child("LoadButton").pressed.connect(_do_load)` with `find_child("LoadButton").pressed.connect(_open_save_dialog.bind("load"))`; change the two tooltip lines added in Task 3 to:

```gdscript
	find_child("SaveButton").tooltip_text = "Choose a slot to save into (quick save: %s)" % Keys.label("save")
	find_child("LoadButton").tooltip_text = "Choose a save to load (%s)" % Keys.label("load")
```

and replace:

```gdscript
	if GameFlow.start_mode == "continue":
		_starting = true
		_do_load()
```

with:

```gdscript
	if GameFlow.start_mode == "continue":
		if GameFlow.continue_slot != "":
			save_slot = GameFlow.continue_slot
		_starting = true
		_do_load()
```

In `_unhandled_key_input()`, replace:

```gdscript
	elif event.is_action_pressed("load"):
		_do_load()
		get_viewport().set_input_as_handled()
```

with:

```gdscript
	elif event.is_action_pressed("load"):
		get_viewport().set_input_as_handled()
		_open_save_dialog("load")
```

In `godot/scripts/menu.gd` `_ready()`, directly after `%ContinueButton.pressed.connect(_continue_campaign)` add:

```gdscript
	%ContinueButton.disabled = SaveStore.most_recent_slot(SaveStore.player_slots()) == ""
```

and in `_continue_campaign()`, directly after `GameFlow.start_mode = "continue"` add:

```gdscript
	GameFlow.continue_slot = SaveStore.most_recent_slot(SaveStore.player_slots())
```

- [ ] **Step 9: Refresh the cache, run both tests, see them pass**

Run: `"$GODOT" --headless --path godot --import`, then `test_save_dialog.gd`, `test_save_slots.gd`, `test_app_behaviour.gd`.
Before running, isolate the existing dashboard test from the player's autosave: in `godot/tests/ui/test_app_behaviour.gd` `_fresh()`, directly after `app.save_slot = TEST_SLOT`, add `app.autosave_slot = ""`. Record it in the report as a test-isolation change (without it a month rollover in that test writes `user://saves/autosave.json`).

Expected: all `PASS`; `test_app_behaviour.gd` matches the baseline.

- [ ] **Step 10: Commit**

```bash
git add -- godot/scripts/native/state/save_store.gd godot/scripts/native/native_game.gd godot/scripts/ui/save_dialog.gd godot/scripts/app.gd godot/scripts/game_flow.gd godot/scripts/menu.gd godot/tests/native/test_save_slots.gd godot/tests/ui/test_save_dialog.gd godot/tests/ui/test_app_behaviour.gd
git commit -m "feat: save slots that say what they hold, and questions before loss

One unnamed slot became autosave plus three; each row shows whose campaign,
its date and when it was saved. Overwriting and loading over unsaved
progress ask first. L opens the list instead of reloading instantly.
Continue picks the newest save and is off when there is none.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- godot/scripts/native/state/save_store.gd godot/scripts/native/native_game.gd godot/scripts/ui/save_dialog.gd godot/scripts/app.gd godot/scripts/game_flow.gd godot/scripts/menu.gd godot/tests/native/test_save_slots.gd godot/tests/ui/test_save_dialog.gd godot/tests/ui/test_app_behaviour.gd
```

(Include the generated `.uid` file.)

---

### Task 14: The pause menu and the ways out (R2)

**Files:**
- Create: `godot/scripts/ui/pause_menu.gd`
- Modify: `godot/scripts/app.gd` (`_ready`, `_input`, `_notification`; add `_open_pause_menu`, `_on_pause_action`, `_leave`, `_exit_tree`)
- Test: `godot/tests/ui/test_pause_menu.gd`

**Interfaces:**
- Consumes: `Overlay`, `ConfirmPrompt` (Task 8), `OptionsPanel` (Task 12), `_open_save_dialog`, `_has_unsaved_progress` (Task 13).
- Produces: `PauseMenu` (Overlay) — `static open(host: Node) -> PauseMenu`, signal `action(id: String)` with ids `resume`, `save`, `load`, `options`, `main_menu`, `quit`; buttons `Entry_<id>`.
- Produces: `app._leave(target: String)` (await) for `"menu"` / `"quit"`.

- [ ] **Step 1: Write the failing test**

`godot/tests/ui/test_pause_menu.gd`:

```gdscript
extends SceneTree

const TestSupportScript = preload("res://scripts/native/testing/test_support.gd")
const AppHarness = preload("res://tests/ui/app_harness.gd")


func _initialize() -> void:
	_run.call_deferred()


func _overlays() -> Array[Node]:
	return get_nodes_in_group(Overlay.GROUP)


func _escape() -> void:
	var ev := InputEventAction.new()
	ev.action = "back"
	ev.pressed = true
	Input.parse_input_event(ev)


func _run() -> void:
	var t = TestSupportScript.new()
	var h = AppHarness.new(self, "test_pause_menu")
	var app: Node = await h.fresh()
	_escape()
	await h.frames(3)
	t.truth(_overlays().size() == 1 and _overlays()[0] is PauseMenu, "Escape on the dashboard opens the pause menu")
	t.truth(app._clock_held(), "and the clock holds under it")
	for id in ["resume", "save", "load", "options", "main_menu", "quit"]:
		t.truth(_overlays()[0].find_child("Entry_%s" % id, true, false) != null, "it offers %s" % id)
	_escape()
	await h.frames(3)
	t.truth(_overlays().is_empty(), "Escape again resumes")

	await app._go_to_desk("records")
	_escape()
	await h.frames(3)
	t.truth(_overlays().is_empty() and not app._desk_open(), "with a desk open, Escape closes the desk instead")

	await h.tick(2)
	t.truth(app._has_unsaved_progress(), "two days of unsaved play")
	app._leave("menu")
	await h.frames()
	var prompt: Node = _overlays()[-1] if not _overlays().is_empty() else null
	t.truth(prompt is ConfirmPrompt, "leaving with unsaved progress asks")
	t.truth(prompt.find_child("Choice_save", true, false) != null and prompt.find_child("Choice_leave", true, false) != null, "offering to save first or leave anyway")
	(prompt.find_child("Choice_cancel", true, false) as Button).pressed.emit()
	await h.frames()
	t.truth(is_instance_valid(app) and app.is_inside_tree(), "and cancelling stays in the game")
	h.finish()
	quit(t.finish())
```

- [ ] **Step 2: Run it and watch it fail**

Run: `"$GODOT" --headless --path godot --script res://tests/ui/test_pause_menu.gd`
Expected: first check fails (Escape does nothing on the dashboard today), or a parse error naming `PauseMenu`.

- [ ] **Step 3: Write the pause menu**

`godot/scripts/ui/pause_menu.gd`:

```gdscript
class_name PauseMenu
extends Overlay

## Escape on the dashboard: everything that is not governing — save, load,
## options and the ways out. The clock holds while it is open. Save, load and
## options open over it and return to it.

signal action(id: String)

const ENTRIES := [
	["resume", "Resume"], ["save", "Save game"], ["load", "Load game"],
	["options", "Options"], ["main_menu", "Exit to main menu"], ["quit", "Quit to desktop"],
]


static func open(host: Node) -> PauseMenu:
	var menu := PauseMenu.new()
	menu.set_title("Paused")
	for entry in ENTRIES:
		var button := Button.new()
		button.name = "Entry_%s" % entry[0]
		button.text = String(entry[1])
		button.custom_minimum_size = Vector2(360, 44)
		button.pressed.connect(menu._pick.bind(String(entry[0])))
		menu.body.add_child(button)
	host.add_child(menu)
	(menu.body.get_child(1) as Button).grab_focus.call_deferred()
	return menu


func _on_back() -> void:
	_pick("resume")


func _pick(id: String) -> void:
	action.emit(id)
	if id == "resume":
		close()
```

- [ ] **Step 4: Wire Escape, the ways out, and the window's close button**

In `godot/scripts/app.gd` `_input()`, replace:

```gdscript
	elif event.is_action_pressed("back") and _desk_open():
		get_viewport().set_input_as_handled()
		_request_close_desk()
```

with:

```gdscript
	elif event.is_action_pressed("back"):
		get_viewport().set_input_as_handled()
		if _desk_open():
			_request_close_desk()
		else:
			_open_pause_menu()
```

Add these functions directly above `func _input(`:

```gdscript
func _open_pause_menu() -> void:
	_sfx_cue("navigation")
	var menu := PauseMenu.open(self)
	menu.action.connect(_on_pause_action.bind(menu))


func _on_pause_action(id: String, menu: PauseMenu) -> void:
	match id:
		"save":
			_open_save_dialog("save")
		"load":
			await _open_save_dialog("load")
			if is_instance_valid(menu):
				menu.close()
		"options":
			OptionsPanel.open(self)
		"main_menu":
			_leave("menu")
		"quit":
			_leave("quit")


## Every way out of a campaign comes through here, so unsaved progress is
## always offered a save first.
func _leave(target: String) -> void:
	if _has_unsaved_progress():
		var verb := "exit" if target == "menu" else "quit"
		var prompt := ConfirmPrompt.ask(self, "Unsaved progress",
			"Progress since your last save will be lost.",
			[["save", "Save and %s" % verb], ["leave", "Leave without saving"], ["cancel", "Cancel"]])
		var choice: String = await prompt.chosen
		if choice == "cancel":
			return
		if choice == "save":
			_do_save()
			if _has_unsaved_progress():
				return
	if target == "quit":
		get_tree().quit()
	else:
		get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _exit_tree() -> void:
	get_tree().set_auto_accept_quit(true)
```

In `_ready()`, as its first line add:

```gdscript
	get_tree().set_auto_accept_quit(false)
```

and replace the body of `_notification()`:

```gdscript
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()
```

with:

```gdscript
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_leave("quit")
```

- [ ] **Step 5: Refresh the cache, run the test, see it pass**

Run: `"$GODOT" --headless --path godot --import` then `"$GODOT" --headless --path godot --script res://tests/ui/test_pause_menu.gd`
Expected: all `PASS`, exit 0.

- [ ] **Step 6: Run every UI test**

Run the Task 0 loop restricted to `godot/tests/ui/test_*.gd`.
Expected: everything passes except what the baseline recorded.

- [ ] **Step 7: Commit**

```bash
git add -- godot/scripts/ui/pause_menu.gd godot/scripts/app.gd godot/tests/ui/test_pause_menu.gd
git commit -m "feat: a pause menu, and a way back to the main menu

There was no route out of a campaign except closing the window. Escape on
the dashboard opens save, load, options and the ways out; leaving, quitting
and the window's close button all offer to save unsaved progress first.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- godot/scripts/ui/pause_menu.gd godot/scripts/app.gd godot/tests/ui/test_pause_menu.gd
```

(Include the generated `.uid` file.)

---

### Task 15: Verify the whole pass by eye and by suite

**Files:**
- Create: `godot/tools/ux_capture.gd`
- Modify: `docs/playtests/2026-10-31-ux-review.md` (add a "Status after the defect pass" section)

**Interfaces:**
- Produces: `godot/tools/ux_capture.gd` — renders a first session to PNGs: `"$GODOT" --path godot --resolution <WxH> --script res://tools/ux_capture.gd -- --out=<absolute dir>`. The guided-year plan reuses it.

- [ ] **Step 1: Write the capture tool**

`godot/tools/ux_capture.gd`:

```gdscript
extends SceneTree

## Renders a first session for visual review: the menu settled, the dashboard,
## the clock running, each desk, the pause menu, options, the save list and a
## month later. Windowed (not headless) so text and art actually render.
## Usage: --resolution 1920x1080 --script res://tools/ux_capture.gd -- --out=C:/path

const SLOT := "zz_ux_capture"

var out := ""
var step := 0
var app: Node


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if out == "":
		push_error("ux_capture: pass -- --out=<directory>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _shot(name: String) -> void:
	step += 1
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%02d_%s.png" % [out, step, name])
	print("shot %02d %s" % [step, name])


func _close_overlays() -> void:
	for node in get_nodes_in_group(Overlay.GROUP):
		(node as Overlay).close()
	await _frames(3)


func _run() -> void:
	var menu: Node = (load("res://scenes/menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await _frames(240)
	await _shot("menu")
	OptionsPanel.open(menu)
	await _frames(6)
	await _shot("options_from_menu")
	menu.queue_free()
	await _frames(2)

	var flow: Node = root.get_node("GameFlow")
	flow.start_mode = "new"
	flow.pending_role = "contextual"
	flow.pending_seed = 424242
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	app.save_slot = SLOT
	app.autosave_slot = ""
	root.add_child(app)
	await _frames(12)
	await _shot("dashboard_paused")
	app._toggle_pause()
	app._set_speed(3)
	await _frames(4)
	await _shot("dashboard_running_speed_3")
	app._toggle_pause()
	for desk in ["budget", "legislation", "diplomacy", "records"]:
		await app._go_to_desk(desk)
		await _frames(8)
		await _shot("desk_%s" % desk)
	await app._go_to_desk("records")
	app._open_pause_menu()
	await _frames(6)
	await _shot("pause_menu")
	await _close_overlays()
	SaveDialog.open(app, "load", true)
	await _frames(6)
	await _shot("load_dialog")
	await _close_overlays()
	app._paused = false
	for _i in range(32):
		app._clock_elapsed = 999.0
		app._process(0.0)
		await _frames(1)
	app._paused = true
	await _frames(4)
	await _shot("after_one_month")
	for suffix in ["", ".tmp", ".bak"]:
		var path := "user://saves/%s.json%s" % [SLOT, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	quit(0)
```

- [ ] **Step 2: Refresh the cache and run the full suite**

Run: `"$GODOT" --headless --path godot --import`, then the Task 0 loop over all test directories.
Expected: every file passes except those recorded as pre-existing in the Task 0 baseline. Any new failure is fixed before continuing.

- [ ] **Step 3: Capture at both sizes**

```bash
OUT="C:/Users/pc/AppData/Local/Temp/claude/ux_after"
"$GODOT" --path godot --resolution 1920x1080 --script res://tools/ux_capture.gd -- --out="$OUT/1920"
"$GODOT" --path godot --resolution 1280x720 --script res://tools/ux_capture.gd -- --out="$OUT/1280"
```

- [ ] **Step 4: Review every frame against the rulings**

Open each PNG and tick each line; any "no" is a defect to fix in the task that owns it:

- [ ] `dashboard_paused`: date line 2 reads PAUSED and pulses between frames; play button reads PLAY; no speed pip lit.
- [ ] `dashboard_running_speed_3`: date line 2 reads `▸▸▸ SPEED 3`; pips 1–3 lit; button reads PAUSE.
- [ ] Both sizes: the national panel with approval, stability and political capital is visible on the dashboard **and** beside every desk.
- [ ] `desk_budget`: all eight envelopes visible at 1920; the controls take more width than the art.
- [ ] No frame contains "simulation", "snapshot", "connected", "STATIC PREVIEW" or "READY".
- [ ] Prose (report, instructions, notes) is in sentence case; labels in capitals.
- [ ] `pause_menu`, `options_from_menu`, `load_dialog`: readable, themed, nothing clipped at 1280×720.
- [ ] `after_one_month`: the report's first lines explain causes ("driven by", "weighed down by", "hardest for").
- [ ] `menu`: title legible and static; tagline fully inside the window at 720p; date reads March 1993.

- [ ] **Step 5: Record the outcome in the review**

Append to `docs/playtests/2026-10-31-ux-review.md`:

```markdown
## Status after the defect pass

Fixed by `docs/superpowers/plans/2026-10-31-ux-defect-fixes.md`; re-captured
at 1920×1080 and 1280×720 with `godot/tools/ux_capture.gd`.

| Finding | Status |
|---|---|
| 1. Turn one tells the player nothing | **Open** — the guided first year's job |
| 2. The primary verb is not labelled | Fixed (Task 1) |
| 3. Vitals vanish at 1280×720 | Fixed (Task 7) |
| 4. A year passes before the game admits it | Partly — the emergency line now leads the report (Task 6); deadlines in the rail are the guided year's |
| 5. Budget asks without explaining | **Open** — consequence preview is a separate slice |
| 6. Three commit buttons, no order | Withdrawn — the review misread it; vote and withdraw stay disabled until tabling |
| 7. Decoration outweighs data | Fixed (Task 10) |
| 8. Digest is arithmetic | Fixed (Task 6) |
| 9. Changing desks costs two actions | Fixed (Task 9) |
| Copy table | Fixed (Task 3) |
| Title never settles | Fixed (Task 4) |
| Tagline clipped | Fixed (Task 3) |
| Unlabelled option buttons | Fixed (Task 3) |
| No pause menu / options / confirmations / save slots | Fixed (Tasks 8, 11–14) |
```

Fill each "Fixed" line only after Step 4 confirms it by eye; otherwise write what is still wrong.

- [ ] **Step 6: Commit**

```bash
git add -- godot/tools/ux_capture.gd docs/playtests/2026-10-31-ux-review.md
git commit -m "docs: record the defect pass, and keep the capture tool

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- godot/tools/ux_capture.gd docs/playtests/2026-10-31-ux-review.md
```

(Include the generated `.uid` file.)

---

## Not in this plan

- **Budget consequence preview** (review finding 5). Showing what cutting an envelope does to households and ministries before the vote needs the engine to project effects it does not project today, and a decision about which consequences to show. It needs its own short design before it can be planned. (Finding 6 was withdrawn: the commit buttons already enforce their order.)
- **The guided first year.** Its plan is written once this one lands, because it builds on interfaces created here: `Overlay`, `Settings` (`guide/default`, `guide/completed_year`), `StatusNotice`, `_go_to_desk`, the compact vitals and `ux_capture.gd`. Spec: `docs/superpowers/specs/2026-10-31-guided-first-year-design.md` (approved).
- **A government cabinet desk** — recorded as a gap in the spec.
- **Hit targets, hover states and mouse feel** — still need a human at the keyboard.
