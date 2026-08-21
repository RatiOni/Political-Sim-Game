"""
Two metric widgets, for the two jobs the left column actually has.

StatBar is the original compact row (LABEL ▓▓░░ value), still used wherever a
dense list of bounded values is wanted.

VitalStat is the headline treatment: a large value over one thin track, for
the three numbers that decide whether a government survives. The left column
now uses VitalStat for those three and a plain label/value table for the
economy — because a progress bar only means anything for a bounded 0..1 value
where higher is better, which growth, inflation and debt/GDP are not.
"""

from PySide6.QtWidgets import QWidget, QHBoxLayout, QVBoxLayout, QLabel
from PySide6.QtCore import Qt

from ui import theme


class StatBar(QWidget):
    """
    A single metric row: LABEL  ▓▓▓▓▓░░░░  value.

    The bar is drawn as a plain child QLabel with a coloured background
    whose width is set as a percentage — no QProgressBar, so we get exact
    control over the fill colour per-update (QProgressBar chunk colours
    are awkward to restyle every turn).
    """

    def __init__(self, label: str, label_width: int = 116, parent=None):
        super().__init__(parent)
        self._value = 0.0
        self._label_text = label
        self._explainable = False

        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 1, 0, 1)
        layout.setSpacing(8)

        self._label = QLabel(label)
        self._label.setFixedWidth(label_width)
        self._label.setStyleSheet(f"color: {theme.INK_DIM};")

        # The track holds the fill. The fill's width is a percentage of the
        # track, achieved by putting it in a stretch layout and swapping
        # stretch factors — robust across resizes without manual geometry.
        self._track = QWidget()
        self._track.setFixedHeight(10)
        self._track.setStyleSheet(
            f"background: {theme.BG}; border: 1px solid {theme.PANEL_EDGE}; "
            f"border-radius: 4px;")
        track_layout = QHBoxLayout(self._track)
        track_layout.setContentsMargins(1, 1, 1, 1)
        track_layout.setSpacing(0)

        self._fill = QWidget()
        self._empty = QWidget()
        self._empty.setStyleSheet("background: transparent;")
        track_layout.addWidget(self._fill)
        track_layout.addWidget(self._empty)

        self._readout = QLabel("—")
        self._readout.setFixedWidth(58)
        self._readout.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self._readout.setStyleSheet(f"color: {theme.INK};")

        layout.addWidget(self._label)
        layout.addWidget(self._track, stretch=1)
        layout.addWidget(self._readout)

    def set_explainable(self, explainable: bool = True):
        """Mark this metric as having a breakdown: an ⓘ glyph makes the
        affordance visible at rest, and the label underlines on hover so it
        reads as clickable without relying on the cursor alone."""
        self._explainable = explainable
        self._apply_label_style(hover=False)

    def set_label(self, label: str):
        self._label_text = label
        self._apply_label_style(hover=False)

    def _apply_label_style(self, hover: bool):
        if not self._explainable:
            self._label.setText(self._label_text)
            self._label.setStyleSheet(f"color: {theme.INK_DIM};")
            return
        self._label.setText(f"{self._label_text} ⓘ")
        color = theme.ACCENT if hover else theme.INK_DIM
        underline = "text-decoration: underline;" if hover else ""
        self._label.setStyleSheet(f"color: {color}; {underline}")

    def enterEvent(self, event):
        if self._explainable:
            self._apply_label_style(hover=True)
        super().enterEvent(event)

    def leaveEvent(self, event):
        if self._explainable:
            self._apply_label_style(hover=False)
        super().leaveEvent(event)

    def set_value(self, value: float, readout: str, color: str):
        """
        value: 0..1 fill fraction.
        readout: the text shown on the right (already formatted).
        color: the fill colour (caller decides via theme.lerp_status_color).
        """
        self._value = max(0.0, min(1.0, value))
        # Integer stretch factors give the fill/empty split. Scale to 1000
        # for smooth-looking granularity.
        filled = int(self._value * 1000)
        layout = self._track.layout()
        layout.setStretch(0, filled)
        layout.setStretch(1, 1000 - filled)
        self._fill.setStyleSheet(f"background: {color}; border-radius: 3px;")
        self._readout.setText(readout)


class VitalStat(QWidget):
    """
    A headline metric:  label ............... 48%
                        ▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░

    Same set_value / set_label / set_explainable surface as StatBar, so the
    left panel can swap one for the other without special-casing. The value is
    large and the track deliberately thin — the number is the message, the bar
    only says roughly where in the range it sits.

    `qualifier` is a short word shown beside the figure at normal weight
    (Stability's "Fragile"), because a word alone with no number was the least
    readable thing in the old column.
    """

    def __init__(self, label: str, parent=None):
        super().__init__(parent)
        self._value = 0.0
        self._label_text = label
        self._explainable = False

        layout = QVBoxLayout(self)
        # Headline, not hero card: three of these must coexist with the
        # economy table on a 1080p display at Windows' common 125% scale.
        layout.setContentsMargins(0, 1, 0, 1)
        layout.setSpacing(3)

        row = QHBoxLayout()
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(8)
        self._label = QLabel(label)
        self._label.setStyleSheet(
            f"color: {theme.INK_DIM}; font-size: {theme.FONT_SIZE_PT}pt;")
        self._readout = QLabel("—")
        self._readout.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self._readout.setTextFormat(Qt.RichText)
        row.addWidget(self._label)
        row.addStretch(1)
        row.addWidget(self._readout)
        layout.addLayout(row)

        self._track = QWidget()
        self._track.setFixedHeight(5)
        self._track.setStyleSheet(
            f"background: {theme.TRACK_BG}; border-radius: 3px;")
        track_layout = QHBoxLayout(self._track)
        track_layout.setContentsMargins(0, 0, 0, 0)
        track_layout.setSpacing(0)
        self._fill = QWidget()
        self._empty = QWidget()
        self._empty.setStyleSheet("background: transparent;")
        track_layout.addWidget(self._fill)
        track_layout.addWidget(self._empty)
        layout.addWidget(self._track)

    def set_explainable(self, explainable: bool = True):
        self._explainable = explainable
        self._apply_label_style(hover=False)

    def set_label(self, label: str):
        self._label_text = label
        self._apply_label_style(hover=False)

    def _apply_label_style(self, hover: bool):
        size = f"font-size: {theme.FONT_SIZE_PT}pt;"
        if not self._explainable:
            self._label.setText(self._label_text)
            self._label.setStyleSheet(f"color: {theme.INK_DIM}; {size}")
            return
        self._label.setText(f"{self._label_text} ⓘ")
        color = theme.ACCENT if hover else theme.INK_DIM
        underline = "text-decoration: underline;" if hover else ""
        self._label.setStyleSheet(f"color: {color}; {size} {underline}")

    def enterEvent(self, event):
        if self._explainable:
            self._apply_label_style(hover=True)
        super().enterEvent(event)

    def leaveEvent(self, event):
        if self._explainable:
            self._apply_label_style(hover=False)
        super().leaveEvent(event)

    def set_value(self, value: float, readout: str, color: str,
                  qualifier: str = "", qualifier_color: str = None):
        self._value = max(0.0, min(1.0, value))
        filled = int(self._value * 1000)
        layout = self._track.layout()
        layout.setStretch(0, filled)
        layout.setStretch(1, 1000 - filled)
        self._fill.setStyleSheet(f"background: {color}; border-radius: 3px;")

        text = (f"<span style='font-size:{theme.FONT_SIZE_LG}pt; font-weight:600; "
                f"color:{theme.INK};'>{readout}</span>")
        if qualifier:
            text += (f" <span style='font-size:{theme.FONT_SIZE_SM}pt; "
                     f"color:{qualifier_color or color};'>{qualifier}</span>")
        self._readout.setText(text)
