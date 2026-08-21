"""
The political map — a custom-painted widget drawing the procedurally
generated continent (ui/map_geometry.py). Countries are polygons in an
abstract 0..100 space, scaled to fit on every paint, filled by their live
relation to the player (gold for you, blue→red for the rest). Clicking a
country emits country_selected. The drawing code assumes nothing about the
shapes beyond "a list of (x, y) points", so swapping in different geometry
touches only map_geometry.py.
"""

from PySide6.QtWidgets import QWidget, QToolTip
from PySide6.QtGui import QPainter, QBrush, QPen, QColor, QPolygonF, QFont
from PySide6.QtCore import Qt, QPointF, Signal

from ui import theme
from ui.map_geometry import COUNTRY_SHAPES, COUNTRY_LABEL_ANCHOR


class MapWidget(QWidget):
    country_selected = Signal(str)   # emits a country_id

    def __init__(self, state, parent=None):
        super().__init__(parent)
        self.state = state
        self._selected_id = None
        self._hover_id = None
        self.setMinimumSize(460, 300)
        self.setMouseTracking(True)

    # ── Public API ─────────────────────────────────────────────────────────

    def set_state(self, state):
        self.state = state
        self.update()

    def set_selected(self, country_id):
        self._selected_id = country_id
        self.update()

    # ── Geometry ───────────────────────────────────────────────────────────

    def _scaled_polygon(self, shape) -> QPolygonF:
        """Scale a 0..100-space shape into a centred square with a margin."""
        margin = 12
        w = self.width() - 2 * margin
        h = self.height() - 2 * margin
        side = min(w, h)
        off_x = margin + (w - side) / 2
        off_y = margin + (h - side) / 2
        poly = QPolygonF()
        for (x, y) in shape:
            poly.append(QPointF(off_x + x / 100.0 * side, off_y + y / 100.0 * side))
        return poly

    def _country_at(self, pos):
        for cid, shape in COUNTRY_SHAPES.items():
            if self._scaled_polygon(shape).containsPoint(QPointF(pos), Qt.OddEvenFill):
                return cid
        return None

    def _fill_for(self, country_id) -> QColor:
        if country_id == self.state.country.id:
            return QColor(theme.REL_PLAYER)
        rel = self.state.country.get_relation(country_id)
        return QColor(theme.relation_color(rel.score if rel else None))

    def _display_name(self, country_id) -> str:
        if country_id == self.state.country.id:
            return self.state.country.name
        c = self.state.world_country(country_id)
        return c.name if c else country_id

    # ── Painting ─────────────────────────────────────────────────────────────

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.fillRect(self.rect(), QColor(theme.PANEL_BG))

        # Sea backdrop so the map reads as a distinct surface.
        painter.setBrush(QBrush(QColor(theme.MAP_SEA)))
        painter.setPen(QPen(QColor(theme.PANEL_EDGE), 1))
        painter.drawRoundedRect(self.rect().adjusted(1, 1, -2, -2), 8, 8)

        name_font = QFont()
        name_font.setPointSize(theme.FONT_SIZE_SM)

        for cid, shape in COUNTRY_SHAPES.items():
            poly = self._scaled_polygon(shape)
            fill = self._fill_for(cid)
            if cid == self._hover_id:
                fill = fill.lighter(120)

            painter.setBrush(QBrush(fill))
            if cid == self._selected_id:
                painter.setPen(QPen(QColor(theme.INK), 3))
            else:
                painter.setPen(QPen(QColor(theme.MAP_SEA), 1.5))
            painter.drawPolygon(poly)

            ax, ay = COUNTRY_LABEL_ANCHOR.get(cid, (50, 50))
            anchor = self._scaled_polygon([(ax, ay)]).at(0)
            painter.setFont(name_font)
            painter.setPen(QPen(QColor(theme.INK)))
            label = self._display_name(cid)
            fm = painter.fontMetrics()
            painter.drawText(int(anchor.x() - fm.horizontalAdvance(label) / 2),
                             int(anchor.y() + fm.height() / 2), label)

        painter.end()

    # ── Interaction ──────────────────────────────────────────────────────────

    def mousePressEvent(self, event):
        cid = self._country_at(event.position().toPoint())
        if cid:
            self._selected_id = cid
            self.country_selected.emit(cid)
            self.update()

    def mouseMoveEvent(self, event):
        pos = event.position().toPoint()
        cid = self._country_at(pos)
        if cid != self._hover_id:
            self._hover_id = cid
            self.update()
        if cid:
            self.setCursor(Qt.PointingHandCursor)
            if cid == self.state.country.id:
                tip = f"{self.state.country.name} (you)"
            else:
                rel = self.state.country.get_relation(cid)
                c = self.state.world_country(cid)
                status = rel.status_label() if rel else "unknown"
                tip = f"{c.name if c else cid} — {status}"
            QToolTip.showText(event.globalPosition().toPoint(), tip, self)
        else:
            self.setCursor(Qt.ArrowCursor)

    def leaveEvent(self, event):
        if self._hover_id is not None:
            self._hover_id = None
            self.update()
