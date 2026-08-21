"""
SeatArcWidget: a custom-painted parliament hemicycle — one dot per seat,
coalition seated first (each bloc ordered by economic ideology), a dashed
radial marking the majority line. Used by the bottom strip and the election
results dialog alike.
"""

import math

from PySide6.QtWidgets import QWidget
from PySide6.QtGui import QPainter, QColor, QPen, QBrush
from PySide6.QtCore import Qt, QPointF

from ui import theme


class SeatArcWidget(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._seats = []       # faction_id per seat, in left→right seating order
        self._colors = {}
        self._total = 0
        self._majority = 0
        self.setMinimumSize(240, 118)

    def set_data(self, factions, total_seats, majority_threshold, colors):
        coalition = sorted([f for f in factions if f.in_coalition and f.seats > 0],
                           key=lambda f: f.ideology.economic)
        opposition = sorted([f for f in factions if not f.in_coalition and f.seats > 0],
                            key=lambda f: f.ideology.economic)
        seats = []
        for f in coalition + opposition:
            seats.extend([f.id] * f.seats)
        self._seats = seats
        self._colors = dict(colors)
        self._total = total_seats
        self._majority = majority_threshold

        coalition_seats = sum(f.seats for f in coalition)
        tip = [f"{total_seats} seats · majority {majority_threshold}",
               f"Government: {coalition_seats} seats "
               f"({'majority' if coalition_seats >= majority_threshold else 'MINORITY'})"]
        for f in coalition + opposition:
            tip.append(f"  {f.name}: {f.seats}")
        self.setToolTip("\n".join(tip))
        self.update()

    def _seat_positions(self, n: int, cx: float, cy: float,
                        r_inner: float, r_outer: float):
        """Returns n (angle, radius) points across the hemicycle, ordered
        left→right (angle π down to 0)."""
        nrows = max(2, int(round(math.sqrt(max(1, n) / 2.0))))
        radii = [r_inner + (r_outer - r_inner) * (i / (nrows - 1) if nrows > 1 else 0.0)
                 for i in range(nrows)]
        wsum = sum(radii) or 1.0
        per_row = [max(1, int(round(n * r / wsum))) for r in radii]
        # Nudge row counts so they sum to exactly n.
        while sum(per_row) > n:
            per_row[per_row.index(max(per_row))] -= 1
        while sum(per_row) < n:
            per_row[per_row.index(min(per_row))] += 1

        positions = []
        for rad, cnt in zip(radii, per_row):
            if cnt == 1:
                angles = [math.pi / 2]
            else:
                angles = [math.pi - (k / (cnt - 1)) * math.pi for k in range(cnt)]
            for a in angles:
                positions.append((a, rad))
        positions.sort(key=lambda ar: -ar[0])  # π (far left) → 0 (far right)
        return positions

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.fillRect(self.rect(), QColor(theme.PANEL_BG))

        n = len(self._seats)
        if n == 0:
            painter.end()
            return

        w, h = self.width(), self.height()
        cx, cy = w / 2.0, h - 6.0
        r_outer = min(w / 2.0 - 8.0, h - 12.0)
        r_inner = r_outer * 0.45
        positions = self._seat_positions(n, cx, cy, r_inner, r_outer)

        dot_r = max(2.4, r_outer * 0.036)
        for (angle, rad), fid in zip(positions, self._seats):
            x = cx + rad * math.cos(angle)
            y = cy - rad * math.sin(angle)
            painter.setBrush(QBrush(QColor(self._colors.get(fid, theme.NEUTRAL))))
            painter.setPen(QPen(QColor(theme.BG), 1))
            painter.drawEllipse(QPointF(x, y), dot_r, dot_r)

        # Majority line: the angular position of the majority-th seat from the
        # left. A governing bloc coloured past this line has its majority.
        if 0 < self._majority <= len(positions):
            angle = positions[self._majority - 1][0]
            x1 = cx + (r_inner * 0.75) * math.cos(angle)
            y1 = cy - (r_inner * 0.75) * math.sin(angle)
            x2 = cx + (r_outer + 7) * math.cos(angle)
            y2 = cy - (r_outer + 7) * math.sin(angle)
            painter.setPen(QPen(QColor(theme.INK), 1, Qt.DashLine))
            painter.drawLine(QPointF(x1, y1), QPointF(x2, y2))

        painter.end()
