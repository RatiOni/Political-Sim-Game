import QtQuick
import "." as Ui

Row {
    id: root
    property var forces: []
    spacing: 2
    height: forces.length > 0 ? 6 : 0
    visible: forces.length > 0

    // Linear colour blend — QML has no builtin colour lerp. Used by the decay
    // phase below to fade a tick's sign colour toward INK_FAINT rather than
    // leaving it fully saturated.
    function mixColor(a, b, t) {
        return Qt.rgba(
            a.r + (b.r - a.r) * t,
            a.g + (b.g - a.g) * t,
            a.b + (b.b - a.b) * t,
            a.a + (b.a - a.a) * t);
    }

    Repeater {
        model: root.forces
        delegate: Rectangle {
            required property var modelData
            // Phase 1: tick width is fixed regardless of `modelData.strength`.
            // DESIGN.md's Visual Language calls for ticks "length-coded
            // loosely to relative strength" — the strength field is computed
            // and present in the data (ui/modifier_glyph.py) but not yet
            // consumed here. Deliberately unimplemented; real width scaling
            // is a follow-up-plan decision, not something to improvise here.
            width: 10
            height: 4
            radius: 2
            color: {
                var base = modelData.sign === "positive" ? Ui.Theme.good : Ui.Theme.critical;
                switch (modelData.phase) {
                    case "onset": return Ui.Theme.inkFaint;
                    case "ramp":  return Qt.lighter(base, 1.15);
                    case "hold":  return base;
                    // decay -> sign colour fading toward INK_FAINT (DESIGN.md
                    // Color § new tokens). A factor-1.0 Qt.lighter() call is a
                    // no-op, so decay used to render identically regardless
                    // of sign — this blends halfway toward inkFaint instead,
                    // which fades the tick while still hinting its sign.
                    case "decay": return root.mixColor(base, Ui.Theme.inkFaint, 0.5);
                    default: return Ui.Theme.inkFaint;
                }
            }
            opacity: modelData.phase === "decay" ? 0.6 : 1.0

            Behavior on color { ColorAnimation { duration: Ui.Theme.durationMediumMin } }
            Behavior on opacity { NumberAnimation { duration: Ui.Theme.durationMediumMin } }
        }
    }
}
