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
