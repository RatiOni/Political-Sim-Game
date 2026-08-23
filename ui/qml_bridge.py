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
    actually track the change happening.

    Deliberate Phase-1 simplification: DESIGN.md describes duration as
    derived from "the modifier's real remaining ramp/decay window" (i.e.
    months-to-ms), but this only buckets by lifecycle *phase* (exactly 3
    distinct outputs: 200 / ~730 / 350). A real months-remaining -> ms
    mapping is follow-up-plan scope, not something to build here."""
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

    def __init__(self, label: str, metric_name: str | None = None, parent=None):
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
                      qualifier: str = "", qualifier_color: str | None = None,
                      forces: list[dict] | None = None):
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

    def set_label(self, text: str):
        """Reactively relabel this vital (e.g. Stability -> "Gov. stability"
        while in opposition). label is otherwise read-only via Property, so
        this is the one sanctioned way to change it after construction."""
        if text == self._label:
            return
        self._label = text
        self.labelChanged.emit()

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
