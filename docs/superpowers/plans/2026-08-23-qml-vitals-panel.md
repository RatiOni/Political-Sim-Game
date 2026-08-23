# QML Vitals Panel (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the "YOUR GOVERNMENT" vitals (Approval, Stability, Political
Capital, Attention) in `LeftPanel` with a QML-rendered equivalent, proving the
Widgets→QML migration path end-to-end and delivering the modifier-visibility
+ motion-as-truth differentiator on Approval — the one headline vital with
real itemized `Modifier` data.

**Architecture:** A `QQuickWidget` is embedded inside the existing
`LeftPanel` (still a `QWidget`), replacing only the Tier-1 vitals section.
Four `VitalStatModel(QObject)` bridge instances are pushed into the QML
context; `refresh()` updates their properties from `GameState` exactly where
it already does today. QML consumes those properties declaratively and
animates transitions itself — no Python-side animation code. Pure force
(modifier) computation lives in a new Qt-free module so it stays testable the
way the rest of this codebase's logic is. `models/`, `content/`, `engine/`
are untouched.

**Tech Stack:** PySide6 6.11.1 (`QtQuick`, `QtQuickWidgets`, `QtQml` —
already present, confirmed via `python -c "from PySide6 import QtQuickWidgets"`),
Public Sans v2.001 (OFL-1.1) bundled as `.ttf` files, this project's existing
hand-rolled assert/print test style (no pytest).

**Spec:** [DESIGN.md](../../../DESIGN.md) — Typography, Color, Motion, and
"The Modifier-Visibility System" sections in particular.

## Global Constraints
- Single font family: Public Sans (Regular/Medium/SemiBold/Bold). No serif,
  no separate mono family — DESIGN.md's typography section is explicit that
  the two-register split was proposed and declined.
- Burgundy palette (`ui/theme.py`) hex values are ported verbatim into QML —
  no new hues invented for surfaces/text/semantic colors.
- No feature flags. `LeftPanel`'s public interface (`refresh(state)`,
  `metric_clicked` Signal) does not change — nothing outside `LeftPanel`
  should need to know its internals became QML.
- The force-glyph only appears where the engine has real itemized `Modifier`
  data (Approval, via `target == "approval_bias"`). Stability and Political
  Capital get the QML visual/motion upgrade but never a fabricated glyph.
- No pytest. Tests are appended to `smoke_test.py` (plain `assert` + `print`,
  next `section()` letter) and `ui_smoke_test.py` (`check(name, fn)` calls
  inserted before the summary block), matching this repo's existing style.

---

### Task 1: Bundle Public Sans and port the burgundy tokens to QML

**Files:**
- Create: `ui/assets/fonts/PublicSans-Regular.ttf`
- Create: `ui/assets/fonts/PublicSans-Medium.ttf`
- Create: `ui/assets/fonts/PublicSans-SemiBold.ttf`
- Create: `ui/assets/fonts/PublicSans-Bold.ttf`
- Create: `ui/qml/Theme.qml`
- Test: `ui_smoke_test.py` (append a check before the summary block)

**Interfaces:**
- Produces: a QML singleton `Theme` (imported as `import "."` within
  `ui/qml/`) exposing `readonly property` color strings and
  `readonly property string fontFamily: "Public Sans"` — every later QML
  task in this plan binds to `Theme.<name>` rather than hardcoding hex.

- [ ] **Step 1: Download and place the font files**

```bash
mkdir -p "ui/assets/fonts"
cd "ui/assets/fonts"
curl -fL -o public-sans.zip "https://github.com/uswds/public-sans/releases/download/v2.001/public-sans-v2.001.zip"
unzip -o -j public-sans.zip "fonts/ttf/PublicSans-Regular.ttf" "fonts/ttf/PublicSans-Medium.ttf" "fonts/ttf/PublicSans-SemiBold.ttf" "fonts/ttf/PublicSans-Bold.ttf" -d .
rm public-sans.zip
cd ../../..
ls ui/assets/fonts
```

Expected: `PublicSans-Regular.ttf`, `PublicSans-Medium.ttf`,
`PublicSans-SemiBold.ttf`, `PublicSans-Bold.ttf` present, each a non-zero-size
binary file.

- [ ] **Step 2: Declare the QML module**

Create `ui/qml/qmldir`:

```
module ui.qml
singleton Theme 1.0 Theme.qml
```

- [ ] **Step 3: Write `Theme.qml` porting every token from `ui/theme.py`**

```qml
pragma Singleton
import QtQuick

QtObject {
    readonly property string fontFamily: "Public Sans"

    // Base palette — verbatim from ui/theme.py, do not invent new hues here.
    readonly property color bg: "#301d26"
    readonly property color panelBg: "#3e2732"
    readonly property color panelRaised: "#4f333f"
    readonly property color panelEdge: "#70455a"
    readonly property color ink: "#fdf4f7"
    readonly property color inkDim: "#dcbcc7"
    readonly property color inkFaint: "#ac8794"

    readonly property color accent: "#f0b365"
    readonly property color accentSoft: "#5c3a44"
    readonly property color highlight: "#f7d99b"
    readonly property color trackBg: "#211219"
    readonly property color rowLine: "#4a2f3b"

    // Semantic status colours
    readonly property color good: "#5fd3a4"
    readonly property color okay: "#98d98a"
    readonly property color warn: "#f0c66e"
    readonly property color bad: "#f0916b"
    readonly property color critical: "#ef5d6b"
    readonly property color neutral: "#9a8792"

    // Motion — DESIGN.md "Motion" section
    readonly property int durationMicro: 80
    readonly property int durationShort: 200
    readonly property int durationMediumMin: 350
    readonly property int durationMediumMax: 900

    function lerpStatusColor(value, higherIsBetter) {
        var v = Math.max(0.0, Math.min(1.0, value));
        if (!higherIsBetter) v = 1.0 - v;
        if (v >= 0.75) return good;
        if (v >= 0.55) return okay;
        if (v >= 0.35) return warn;
        if (v >= 0.20) return bad;
        return critical;
    }
}
```

- [ ] **Step 4: Register the fonts and write the load-check in `ui_smoke_test.py`**

In `ui_smoke_test.py`, add near the top (after the existing imports, before
`def main():`):

```python
from PySide6.QtGui import QFontDatabase
```

Insert this check inside `main()`, before the final
`print("\n" + "=" * 60)` summary block (immediately after the existing
`_launch_from_campaign` check):

```python
    def _public_sans_fonts_load():
        import glob
        font_files = sorted(glob.glob(
            os.path.join(os.path.dirname(__file__), "ui", "assets", "fonts", "*.ttf")))
        assert len(font_files) == 4, f"expected 4 Public Sans .ttf files, found {len(font_files)}"
        families = set()
        for path in font_files:
            font_id = QFontDatabase.addApplicationFont(path)
            assert font_id != -1, f"Qt rejected font file: {path}"
            families.update(QFontDatabase.applicationFontFamilies(font_id))
        assert "Public Sans" in families, f"no 'Public Sans' family registered, got {families}"
    check("Public Sans font files load into QFontDatabase", _public_sans_fonts_load)
```

- [ ] **Step 5: Run it**

```bash
.venv\Scripts\python.exe ui_smoke_test.py
```

Expected: `Public Sans font files load into QFontDatabase` shows `PASS`. (The
final `game window launches` check may still show earlier failures unrelated
to this change — only confirm the new check passes at this step.)

- [ ] **Step 6: Commit**

```bash
git add ui/assets/fonts ui/qml/Theme.qml ui/qml/qmldir ui_smoke_test.py
git commit -m "feat: bundle Public Sans and port burgundy tokens to a QML Theme singleton"
```

---

### Task 2: Pure-Python modifier force computation

**Files:**
- Create: `ui/modifier_glyph.py`
- Test: `smoke_test.py` (append new section at file end)

**Interfaces:**
- Consumes: `state.modifiers` (`list[models.modifiers.Modifier]`),
  `Modifier.target`, `Modifier.current_value()`, `Modifier.phase_label()`,
  `Modifier.onset_delay/ramp_duration/hold_duration/decay_duration/age`
  (all existing, `models/modifiers.py`).
- Produces: `approval_forces(state) -> list[dict]`, each dict shaped
  `{"source": str, "phase": "onset"|"ramp"|"hold"|"decay", "sign": "positive"|"negative", "strength": float}`
  — `strength` is `abs(current_value())`, used by Task 3/4 to scale glyph
  tick length. Later tasks (the economy-table follow-on, out of scope here)
  reuse this exact shape via a generalized `forces_for(state, target)`.

- [ ] **Step 1: Write the failing test**

Append to the end of `smoke_test.py`:

```python

# ══════════════════════════════════════════════════════════════════════════
# SECTION AI — MODIFIER-VISIBILITY GLYPH DATA
# ══════════════════════════════════════════════════════════════════════════

section("AI1: approval_forces classifies every lifecycle phase correctly")

from ui import modifier_glyph
from models.modifiers import Modifier

class _AIState:
    def __init__(self, modifiers):
        self.modifiers = modifiers

onset_mod = Modifier(id="m1", source="Pending reform", target="approval_bias",
                      magnitude=0.05, onset_delay=3, ramp_duration=2, age=1)
ramp_mod = Modifier(id="m2", source="New law phasing in", target="approval_bias",
                     magnitude=0.08, onset_delay=0, ramp_duration=4, age=1)
hold_mod = Modifier(id="m3", source="Popular reform", target="approval_bias",
                     magnitude=0.10, onset_delay=0, ramp_duration=1,
                     hold_duration=6, age=3)
decay_mod = Modifier(id="m4", source="Scandal fading", target="approval_bias",
                      magnitude=-0.06, onset_delay=0, ramp_duration=1,
                      hold_duration=2, decay_duration=4, age=4)
unrelated_mod = Modifier(id="m5", source="Inflation shock", target="inflation",
                          magnitude=0.02, ramp_duration=1, age=0)

state = _AIState([onset_mod, ramp_mod, hold_mod, decay_mod, unrelated_mod])
forces = modifier_glyph.approval_forces(state)

by_source = {f["source"]: f for f in forces}
assert len(forces) == 4, f"expected 4 approval-targeted forces, got {len(forces)}: {forces}"
assert "Inflation shock" not in by_source, "a non-approval modifier leaked into approval_forces"

assert by_source["Pending reform"]["phase"] == "onset"
assert by_source["New law phasing in"]["phase"] == "ramp"
assert by_source["Popular reform"]["phase"] == "hold"
assert by_source["Scandal fading"]["phase"] == "decay"

assert by_source["Pending reform"]["sign"] == "positive"
assert by_source["Popular reform"]["sign"] == "positive"
assert by_source["Scandal fading"]["sign"] == "negative", \
    "a negative-magnitude modifier must report sign='negative' even while its current_value is still small during decay"

assert abs(by_source["Popular reform"]["strength"] - hold_mod.current_value()) < 1e-9

print(f"  {len(forces)} forces classified: "
      f"{sorted((f['source'], f['phase'], f['sign']) for f in forces)}")
print("  PASS: onset/ramp/hold/decay and sign are read straight off Modifier, nothing reimplemented")
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
.venv\Scripts\python.exe smoke_test.py
```

Expected: `FAIL` / `ModuleNotFoundError: No module named 'ui.modifier_glyph'`
(or `ImportError`) — the section itself should raise before reaching any
assert, since the module doesn't exist yet.

- [ ] **Step 3: Write `ui/modifier_glyph.py`**

```python
"""
Pure, read-only computation of which Modifiers are currently pushing a given
stat, and what lifecycle phase each is in — the data behind the
modifier-visibility glyph (see DESIGN.md: "The Modifier-Visibility System").

Same discipline as ui/explain.py: no Qt import here, no mutation, and the
phase/value math is never reimplemented — it's read straight off Modifier.
"""

_PHASE_KEYWORDS = (
    ("pending", "onset"),
    ("phasing in", "ramp"),
    ("fading", "decay"),
    ("expired", "decay"),
)


def _phase_key(modifier) -> str:
    """Modifier.phase_label() is a human sentence ('phasing in (2/4mo)');
    this maps it to the fixed vocabulary the glyph/QML side switches on,
    without duplicating the lifecycle arithmetic phase_label() already does."""
    label = modifier.phase_label()
    for keyword, phase in _PHASE_KEYWORDS:
        if label.startswith(keyword):
            return phase
    return "hold"  # phase_label() returns exactly "active" for the hold phase


def forces_for(state, target: str) -> list[dict]:
    """Every Modifier currently targeting `target`, classified by phase and
    sign. Order is stable (insertion order of state.modifiers) so a glyph's
    tick order doesn't shuffle between refreshes."""
    out = []
    for m in state.modifiers:
        if m.target != target:
            continue
        out.append({
            "source": m.source,
            "phase": _phase_key(m),
            "sign": "positive" if m.magnitude >= 0 else "negative",
            "strength": abs(m.current_value()),
        })
    return out


def approval_forces(state) -> list[dict]:
    """The one instantiation of forces_for wired up in Phase 1 — Approval is
    the sole headline vital with real itemized Modifier data
    (target == "approval_bias"; see DESIGN.md's honesty note on why
    Stability and Political Capital don't get this)."""
    return forces_for(state, "approval_bias")
```

- [ ] **Step 4: Run the test again to confirm it passes**

```bash
.venv\Scripts\python.exe smoke_test.py
```

Expected: Section `AI1` prints `PASS`, and the whole suite still ends with
its usual all-clear summary (no earlier section regressed).

- [ ] **Step 5: Commit**

```bash
git add ui/modifier_glyph.py smoke_test.py
git commit -m "feat: pure-Python computation of active-modifier forces for the visibility glyph"
```

---

### Task 3: QML bridge — `VitalStatModel`

**Files:**
- Create: `ui/qml_bridge.py`
- Test: `smoke_test.py` (append new section)

**Interfaces:**
- Consumes: `ui.modifier_glyph.approval_forces` (Task 2),
  `ui.theme.lerp_status_color` (existing).
- Produces: `VitalStatModel(QObject)` with Qt Properties `label` (str),
  `value` (float, 0..1), `readoutText` (str), `fillColor` (str hex),
  `qualifier` (str), `qualifierColor` (str hex), `forces` (QVariantList of
  the Task-2 dict shape), `animMs` (int), `explainable` (bool),
  `metricName` (str) — and Signal `clicked(str)`, emitted by a `@Slot()`
  method `activate()` that QML calls on click. Every property has a Qt
  `Signal` pair (`xChanged`) so QML bindings stay reactive. `refresh_from`
  is a plain Python method (not exposed to QML) that Task 5 calls from
  `LeftPanel.refresh()`.

- [ ] **Step 1: Write the failing test**

Append to `smoke_test.py`:

```python

section("AI2: VitalStatModel derives its animation duration from the dominant active force")

from ui.qml_bridge import VitalStatModel, ms_for_phase

no_forces_ms = ms_for_phase([])
assert no_forces_ms == 200, f"flat 'value tick' duration should be 200ms, got {no_forces_ms}"

ramp_forces = [{"source": "x", "phase": "ramp", "sign": "positive", "strength": 0.05}]
ramp_ms = ms_for_phase(ramp_forces)
assert 350 <= ramp_ms <= 900, f"a ramping force should map into the 350-900ms band, got {ramp_ms}"

mixed_forces = [
    {"source": "a", "phase": "hold", "sign": "positive", "strength": 0.02},
    {"source": "b", "phase": "decay", "sign": "negative", "strength": 0.09},
]
mixed_ms = ms_for_phase(mixed_forces)
assert 350 <= mixed_ms <= 900, f"the dominant (largest-strength) force should drive duration, got {mixed_ms}"
# 'b' has the larger strength (0.09 > 0.02), so it should dominate over 'a'.
solo_decay_ms = ms_for_phase([mixed_forces[1]])
assert mixed_ms == solo_decay_ms, "the dominant force alone should reproduce the mixed-list duration"

model = VitalStatModel("Approval", metric_name="Approval")
model.refresh_from(value=0.48, readout="48%", color="#f0c66e",
                    qualifier="", qualifier_color=None,
                    forces=ramp_forces)
assert model.value == 0.48
assert model.readoutText == "48%"
assert model.fillColor == "#f0c66e"
assert len(model.forces) == 1
assert model.animMs == ramp_ms

clicks = []
model.clicked.connect(lambda name: clicks.append(name))
model.activate()
assert clicks == ["Approval"], f"clicking an explainable vital should emit its metric name, got {clicks}"
print("  PASS: duration tracks the dominant active force; click still emits the metric name")
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
.venv\Scripts\python.exe smoke_test.py
```

Expected: `FAIL` / `ModuleNotFoundError: No module named 'ui.qml_bridge'`.

- [ ] **Step 3: Write `ui/qml_bridge.py`**

```python
"""
QObject bridges that expose Python/GameState-derived data to QML as
reactive Properties. Kept thin on purpose: all the actual computation
(what a vital's value/color/forces are) still happens in ui/panel_left.py
and ui/modifier_glyph.py exactly as before — this module only re-shapes
that data for QML's property-binding system.
"""

from PySide6.QtCore import QObject, Signal, Slot, Property


def ms_for_phase(forces: list[dict]) -> int:
    """Motion-as-truth duration (DESIGN.md: 'Motion'). No active force ->
    the flat 200ms value-tick. Otherwise the DOMINANT force (largest
    |current_value|) maps its phase onto the 350-900ms band: hold reads as
    an already-settled value (fast, near 350ms), onset/ramp/decay read as
    something still moving (slower, near 900ms) so the player's eye can
    actually track the change happening."""
    if not forces:
        return 200
    dominant = max(forces, key=lambda f: f["strength"])
    phase_weight = {"onset": 1.0, "ramp": 1.0, "decay": 0.85, "hold": 0.0}
    weight = phase_weight.get(dominant["phase"], 0.5)
    return int(350 + weight * (900 - 350))


class VitalStatModel(QObject):
    labelChanged = Signal()
    valueChanged = Signal()
    readoutTextChanged = Signal()
    fillColorChanged = Signal()
    qualifierChanged = Signal()
    qualifierColorChanged = Signal()
    forcesChanged = Signal()
    animMsChanged = Signal()
    explainableChanged = Signal()

    clicked = Signal(str)

    def __init__(self, label: str, metric_name: str = None, parent=None):
        super().__init__(parent)
        self._label = label
        self._metric_name = metric_name
        self._value = 0.0
        self._readout_text = ""
        self._fill_color = "#9a8792"
        self._qualifier = ""
        self._qualifier_color = None
        self._forces = []
        self._anim_ms = 200
        self._explainable = metric_name is not None

    def refresh_from(self, value: float, readout: str, color: str,
                      qualifier: str = "", qualifier_color: str = None,
                      forces: list = None):
        forces = forces or []
        self._value = max(0.0, min(1.0, value))
        self._readout_text = readout
        self._fill_color = color
        self._qualifier = qualifier
        self._qualifier_color = qualifier_color or color
        self._forces = forces
        self._anim_ms = ms_for_phase(forces)
        for signal in (self.valueChanged, self.readoutTextChanged,
                       self.fillColorChanged, self.qualifierChanged,
                       self.qualifierColorChanged, self.forcesChanged,
                       self.animMsChanged):
            signal.emit()

    @Slot()
    def activate(self):
        if self._explainable:
            self.clicked.emit(self._metric_name)

    label = Property(str, lambda self: self._label, notify=labelChanged)
    value = Property(float, lambda self: self._value, notify=valueChanged)
    readoutText = Property(str, lambda self: self._readout_text, notify=readoutTextChanged)
    fillColor = Property(str, lambda self: self._fill_color, notify=fillColorChanged)
    qualifier = Property(str, lambda self: self._qualifier, notify=qualifierChanged)
    qualifierColor = Property(str, lambda self: self._qualifier_color or self._fill_color,
                               notify=qualifierColorChanged)
    forces = Property("QVariantList", lambda self: self._forces, notify=forcesChanged)
    animMs = Property(int, lambda self: self._anim_ms, notify=animMsChanged)
    explainable = Property(bool, lambda self: self._explainable, notify=explainableChanged)
```

- [ ] **Step 4: Run the test again to confirm it passes**

```bash
.venv\Scripts\python.exe smoke_test.py
```

Expected: Section `AI2` prints `PASS`.

- [ ] **Step 5: Commit**

```bash
git add ui/qml_bridge.py smoke_test.py
git commit -m "feat: QML bridge exposing vital-stat data as reactive Qt properties"
```

---

### Task 4: The QML components — `ForceGlyph`, `VitalStat`, `VitalsPanel`

**Files:**
- Create: `ui/qml/ForceGlyph.qml`
- Create: `ui/qml/VitalStat.qml`
- Create: `ui/qml/VitalsPanel.qml`
- Modify: `ui/qml/qmldir` (register the three new types)
- Test: `ui_smoke_test.py` (append a check before the summary block)

**Interfaces:**
- Consumes: `Theme` singleton (Task 1), a `VitalStatModel`-shaped object
  bound as a QML context/root property (Task 3) — `VitalStat.qml` expects a
  property named `model` of that shape.
- Produces: `VitalsPanel.qml` expects four context properties named
  `approvalModel`, `stabilityModel`, `pcModel`, `attentionModel` — Task 5
  binds these to four real `VitalStatModel` instances.

- [ ] **Step 1: Write `ForceGlyph.qml`**

```qml
import QtQuick
import "." as Ui

Row {
    id: root
    property var forces: []
    spacing: 2
    height: forces.length > 0 ? 6 : 0
    visible: forces.length > 0

    Repeater {
        model: root.forces
        delegate: Rectangle {
            required property var modelData
            width: 10
            height: 4
            radius: 2
            color: {
                var base = modelData.sign === "positive" ? Ui.Theme.good : Ui.Theme.critical;
                switch (modelData.phase) {
                    case "onset": return Ui.Theme.inkFaint;
                    case "ramp":  return Qt.lighter(base, 1.15);
                    case "hold":  return base;
                    case "decay": return Qt.lighter(Ui.Theme.inkFaint, 1.0);
                    default: return Ui.Theme.inkFaint;
                }
            }
            opacity: modelData.phase === "decay" ? 0.6 : 1.0

            Behavior on color { ColorAnimation { duration: Ui.Theme.durationMediumMin } }
            Behavior on opacity { NumberAnimation { duration: Ui.Theme.durationMediumMin } }
        }
    }
}
```

- [ ] **Step 2: Write `VitalStat.qml`**

```qml
import QtQuick
import "." as Ui

Column {
    id: root
    required property var model
    width: parent ? parent.width : 240
    spacing: 3

    Row {
        width: root.width
        Text {
            id: labelText
            text: root.model.explainable ? root.model.label + " ⓘ" : root.model.label
            color: mouseArea.containsMouse ? Ui.Theme.accent : Ui.Theme.inkDim
            font.family: Ui.Theme.fontFamily
            font.pixelSize: 13
        }
        Item { width: root.width - labelText.width - readout.width; height: 1 }
        Text {
            id: readout
            text: root.model.readoutText + (root.model.qualifier ? " " + root.model.qualifier : "")
            color: Ui.Theme.ink
            font.family: Ui.Theme.fontFamily
            font.pixelSize: 14
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignRight
        }
    }

    Rectangle {
        width: root.width
        height: 5
        radius: 3
        color: Ui.Theme.trackBg

        Rectangle {
            id: fill
            height: parent.height
            radius: 3
            color: root.model.fillColor
            width: parent.width * root.model.value

            Behavior on width { NumberAnimation { duration: root.model.animMs; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: root.model.animMs } }
        }
    }

    Ui.ForceGlyph { forces: root.model.forces }

    MouseArea {
        id: mouseArea
        anchors.top: parent.top
        width: root.width
        height: 20
        hoverEnabled: true
        cursorShape: root.model.explainable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.model.activate()
    }
}
```

- [ ] **Step 3: Write `VitalsPanel.qml`**

```qml
import QtQuick
import "." as Ui

Column {
    width: parent ? parent.width : 240
    spacing: 8

    Ui.VitalStat { model: approvalModel; width: parent.width }
    Ui.VitalStat { model: stabilityModel; width: parent.width }
    Ui.VitalStat { model: pcModel; width: parent.width }
    Ui.VitalStat { model: attentionModel; width: parent.width }
}
```

- [ ] **Step 4: Register the new types in `ui/qml/qmldir`**

```
module ui.qml
singleton Theme 1.0 Theme.qml
ForceGlyph 1.0 ForceGlyph.qml
VitalStat 1.0 VitalStat.qml
VitalsPanel 1.0 VitalsPanel.qml
```

- [ ] **Step 5: Write the load smoke-check**

Add to `ui_smoke_test.py`, near the top:

```python
from PySide6.QtQuickWidgets import QQuickWidget
from PySide6.QtCore import QUrl
```

Insert this check before the final summary block (after the Public Sans
check from Task 1):

```python
    def _vitals_panel_qml_loads():
        from ui.qml_bridge import VitalStatModel
        quick = QQuickWidget()
        quick.setResizeMode(QQuickWidget.ResizeMode.SizeRootObjectToView)
        ctx = quick.rootContext()
        approval = VitalStatModel("Approval", metric_name="Approval")
        stability = VitalStatModel("Stability")
        pc = VitalStatModel("Political capital")
        attention = VitalStatModel("Attention")
        ctx.setContextProperty("approvalModel", approval)
        ctx.setContextProperty("stabilityModel", stability)
        ctx.setContextProperty("pcModel", pc)
        ctx.setContextProperty("attentionModel", attention)
        qml_path = os.path.join(os.path.dirname(__file__), "ui", "qml", "VitalsPanel.qml")
        quick.setSource(QUrl.fromLocalFile(qml_path))
        app.processEvents()
        assert quick.status() == QQuickWidget.Status.Ready, \
            f"VitalsPanel.qml failed to load, status={quick.status()}, errors={quick.errors()}"
        assert quick.errors() == [], f"QML reported errors: {quick.errors()}"
    check("VitalsPanel.qml loads with no QML errors", _vitals_panel_qml_loads)
```

- [ ] **Step 6: Run it**

```bash
.venv\Scripts\python.exe ui_smoke_test.py
```

Expected: `VitalsPanel.qml loads with no QML errors` shows `PASS`. If it
`FAIL`s, the printed `quick.errors()` list gives exact file:line QML syntax
errors — fix those before moving on; this step is not allowed to pass with
warnings suppressed.

- [ ] **Step 7: Commit**

```bash
git add ui/qml
git commit -m "feat: QML VitalStat/ForceGlyph/VitalsPanel components"
```

---

### Task 5: Wire the QML panel into `LeftPanel`

**Files:**
- Modify: `ui/panel_left.py:115-217` (the `LeftPanel.__init__`/`refresh`
  Tier-1 section)
- Test: `ui_smoke_test.py` (existing `MainWindow constructs with all panels`
  and `game window launches from a generated campaign` checks are the
  regression gate — no new check needed, but Step 4 below adds one targeted
  check)

**Interfaces:**
- Consumes: `VitalStatModel` (Task 3), `ui.modifier_glyph.approval_forces`
  (Task 2), `ui/qml/VitalsPanel.qml` (Task 4).
- Produces: `LeftPanel.metric_clicked` (Signal(str)) and `LeftPanel.refresh(state)`
  keep their exact existing signatures — `ui/app.py` requires no changes.

- [ ] **Step 1: Replace the Tier-1 construction block**

In `ui/panel_left.py`, remove the `_vital()` helper and the block from
`# ── Tier 1: the three that decide whether you survive ─────────────`
through the `for widget in (...)` loop (current lines ~138-160), replacing
with:

```python
        # ── Tier 1: the three that decide whether you survive ─────────────
        # QML-hosted (see DESIGN.md) — the only place the modifier-visibility
        # force-glyph currently applies is Approval, which is why only its
        # model is built with a metric_name.
        self._approval_model = VitalStatModel("Approval", metric_name="Approval")
        self._stability_model = VitalStatModel("Stability")
        self._pc_model = VitalStatModel("Political capital")
        self._attention_model = VitalStatModel("Attention")
        for model in (self._approval_model, self._stability_model,
                      self._pc_model, self._attention_model):
            model.clicked.connect(self.metric_clicked)

        self._role_title = _section_title("YOUR GOVERNMENT")
        layout.addWidget(self._role_title)
        layout.addSpacing(4)

        self._vitals_quick = QQuickWidget()
        self._vitals_quick.setResizeMode(QQuickWidget.ResizeMode.SizeRootObjectToView)
        self._vitals_quick.setFixedHeight(150)
        ctx = self._vitals_quick.rootContext()
        ctx.setContextProperty("approvalModel", self._approval_model)
        ctx.setContextProperty("stabilityModel", self._stability_model)
        ctx.setContextProperty("pcModel", self._pc_model)
        ctx.setContextProperty("attentionModel", self._attention_model)
        qml_path = os.path.join(os.path.dirname(os.path.dirname(__file__)),
                                 "ui", "qml", "VitalsPanel.qml")
        self._vitals_quick.setSource(QUrl.fromLocalFile(qml_path))
        layout.addWidget(self._vitals_quick)
```

Note `.clicked.connect(self.metric_clicked)` connects a `Signal(str)`
directly to another `Signal(str)` — PySide6 supports signal-to-signal
connection, re-emitting with the same argument, exactly like the old
`_ClickableVital.clicked.connect(self.metric_clicked)` pattern this replaces.

- [ ] **Step 2: Add the new imports**

At the top of `ui/panel_left.py`, add:

```python
import os
from PySide6.QtCore import QUrl
from PySide6.QtQuickWidgets import QQuickWidget
from ui.qml_bridge import VitalStatModel
from ui import modifier_glyph
```

- [ ] **Step 3: Update `refresh()` to push into the new models**

In `LeftPanel.refresh`, replace the three `self._v_approval.set_value(...)`,
`self._v_stability.set_value(...)`, `self._v_pc.set_value(...)` calls (and
the `self._v_attention.set_value(...)` call already further down) with:

```python
        self._approval_model.refresh_from(
            p.approval, f"{p.approval*100:.0f}%",
            theme.lerp_status_color(p.approval),
            forces=modifier_glyph.approval_forces(state))
        self._stability_model.refresh_from(
            state.stability.value, f"{state.stability.value*100:.0f}%",
            theme.lerp_status_color(state.stability.value),
            qualifier=state.stability.label())
        self._pc_model.refresh_from(
            p.political_capital / 100.0, f"{p.political_capital:.0f}",
            theme.lerp_status_color(p.political_capital / 100.0))

        from engine import player_ops as ops
        left = ops.attention_remaining(state)
        total = ops.MONTHLY_ATTENTION
        self._attention_model.refresh_from(
            left / max(1, total), f"{left} / {total}",
            theme.lerp_status_color(left / max(1, total)),
            qualifier=("committed" if left == 0 else "this month"),
            qualifier_color=theme.CRITICAL if left == 0 else None)
```

Remove the now-redundant `from engine import player_ops as ops` import
further down in the old Tier-1 attention block if it becomes a duplicate
(keep whichever one is textually first; Python tolerates the duplicate
either way, but only one should remain for clarity).

- [ ] **Step 4: Add a regression-targeted check to `ui_smoke_test.py`**

Insert before the final summary block:

```python
    def _left_panel_vitals_refresh_and_click():
        # Built against a fresh sample state rather than reusing the
        # MainWindow fixture, so this check is independent of whichever
        # earlier check ran (or didn't) first.
        from ui.panel_left import LeftPanel
        from main import build_sample_game
        st = build_sample_game()
        panel = LeftPanel(st)
        app.processEvents()
        clicked = []
        panel.metric_clicked.connect(lambda name: clicked.append(name))
        panel.refresh(st)
        assert panel._approval_model.readoutText.endswith("%")
        panel._approval_model.activate()
        assert clicked == ["Approval"], f"expected a click-through from QML to LeftPanel.metric_clicked, got {clicked}"
    check("LeftPanel's QML vitals refresh and forward clicks", _left_panel_vitals_refresh_and_click)
```

- [ ] **Step 5: Run the full UI smoke suite**

```bash
.venv\Scripts\python.exe ui_smoke_test.py
```

Expected: every check shows `PASS`, including the new one and the
pre-existing `MainWindow constructs with all panels` and
`game window launches from a generated campaign + autosaves` checks (this is
the regression gate — those two exercising the real `LeftPanel` inside a
real `MainWindow` is what proves the swap didn't break anything upstream).

- [ ] **Step 6: Manual verification**

```bash
.venv\Scripts\python.exe gui.py
```

Confirm by eye: the Approval/Stability/Political capital/Attention vitals
render in the new Public Sans font on the burgundy track; Approval shows a
small tick row under its bar once any modifier targets `approval_bias`
(triggerable in a fresh campaign by advancing a turn after passing a bill
with an approval effect); clicking Approval still opens the same
`MetricBreakdownDialog` as before.

- [ ] **Step 7: Commit**

```bash
git add ui/panel_left.py ui_smoke_test.py
git commit -m "feat: wire the QML vitals panel into LeftPanel, replacing the Widgets Tier-1 vitals"
```

---

## What Phase 1 deliberately does not cover

Per the writing-plans Scope Check, this plan is intentionally one bounded
slice, not the whole migration:

- The Tier-2 economy table (`_EconRow`, five rows) stays Widgets. It's the
  *richest* home for the force-glyph (all five rows have real itemized
  modifier data via `ui/explain.py: economic_effects`) and should be the
  next plan, reusing `modifier_glyph.forces_for` and `VitalStatModel`
  unchanged.
- The map, assembly strip, right panel, dispatch feed, and the desk overlay
  (`ui/dock.py` and its six system pages) are untouched and stay Widgets
  until their own plans.
- No visual QA/screenshot pass against `docs/ardenia_ui_mockup.html` is
  included — that mockup itself still shows the pre-QML navy palette and
  should be regenerated (or retired in favor of a direct `gui.py` screenshot)
  in a follow-on documentation task, not this one.

## Self-Review

**Spec coverage:** DESIGN.md's Typography (Public Sans, no serif/mono split)
→ Task 1. Color (burgundy ported verbatim) → Task 1. Motion (duration
derived from dominant active force) → Task 3. The Modifier-Visibility System
(itemized only where honest — Approval, not Stability/PC) → Task 2 + Task 5.
Layout/Spacing (grid-disciplined, no reflow) → carried forward by construction
(the QQuickWidget has a fixed height, same discipline as every other
dashboard element per `CLAUDE.md`'s "Nothing on the dashboard may change
size" rule).

**Placeholder scan:** clean — no TODO/TBD markers, and every code block is
the final version an implementer runs as written (two drafting artifacts
caught in review — a stray dead branch in Task 5 Step 4 and an unresolved
placeholder assertion in Task 2 Step 1 — were removed, not left flagged for
later cleanup).

**Type consistency:** `VitalStatModel.refresh_from(value, readout, color,
qualifier, qualifier_color, forces)` (Task 3) is called with that exact
keyword shape in both the Task 4 smoke check and the Task 5 `refresh()`
rewrite. `modifier_glyph.approval_forces(state) -> list[dict]` (Task 2) is
the exact type both `VitalStatModel.forces` (Task 3) and `ForceGlyph.qml`'s
`forces` property (Task 4) consume.
