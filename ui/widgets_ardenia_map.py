"""Interactive national map for Ardenia's main dashboard.

The dashboard is a view from inside the country: regions, routes, cities and
the ceasefire line are actionable context. The wider world remains in the
simulation and the Diplomacy desk rather than occupying the centre of play.
"""

from PySide6.QtWidgets import QWidget, QToolTip
from PySide6.QtGui import (QBrush, QColor, QFont, QPainter, QPainterPath, QPen,
                           QPolygonF)
from PySide6.QtCore import QPointF, Qt, Signal

from content import lore
from content.regions import CONTROL_LABELS, REGIONAL_ISSUES
from engine import regions as region_engine
from ui import theme
from ui.ardenia_map_geometry import (
    BORDER_LABELS, CEASEFIRE_LINE, CHECKPOINTS, CITY_MARKERS,
    COASTLINE_SEGMENTS, COUNTRY_OUTLINE, KESLA_POINTS, LAND_BORDER_SEGMENTS,
    NEIGHBOR_LAND_SHAPES, NORTHERN_MOUNTAIN_FRONTIER, NORTHERN_RIDGES, PORTS,
    REGION_COLORS, REGION_LABEL_ANCHORS, REGION_MAP_META, REGION_MAP_LABELS,
    REGION_SHAPES, ROUTES, ROUTE_STYLE_HINTS,
)


class ArdeniaMapWidget(QWidget):
    """A clickable Ardenian political map, keyed by stable region ids."""

    region_selected = Signal(str)

    def __init__(self, state, parent=None):
        super().__init__(parent)
        self.state = state
        self._selected_id = None
        self._hover_id = None
        self._regions = {item["id"]: item for item in lore.REGIONS}
        self.setMinimumSize(460, 300)
        self.setMouseTracking(True)

    # ── Public API ─────────────────────────────────────────────────────────

    def set_state(self, state):
        self.state = state
        self.update()

    def set_selected(self, region_id):
        self._selected_id = region_id
        self.update()

    # ── Geometry ───────────────────────────────────────────────────────────

    # Reserved band along the top for the legend, so a region can never be
    # drawn underneath it.
    LEGEND_BAND = 24
    # Ardenia is a long west-east state.  A 1.45 projection made the accepted
    # silhouette read as a compact badge once nine regions, cities and routes
    # were placed inside it.  The wider projection gives the western coast,
    # capital basin and eastern frontier distinct geographic room without
    # changing the shared normalized coordinates used by hit-testing.
    MAP_ASPECT = 1.68

    def _transform(self):
        """Fit Ardenia at its canonical broad east-west aspect ratio.

        The old square transform made the same coordinates look almost round
        and left most of a wide dashboard panel unused.  Keeping the aspect in
        the presentation transform means geometry stays in the simple 0..100
        authoring space while every route, marker and click target receives the
        identical projection.
        """
        margin = 14
        top = margin + self.LEGEND_BAND
        usable_w = max(1, self.width() - 2 * margin)
        usable_h = max(1, self.height() - top - margin)
        map_w = min(usable_w, usable_h * self.MAP_ASPECT)
        map_h = map_w / self.MAP_ASPECT
        off_x = margin + (usable_w - map_w) / 2
        off_y = top + (usable_h - map_h) / 2
        return map_w, map_h, off_x, off_y

    def _point(self, point):
        map_w, map_h, off_x, off_y = self._transform()
        x, y = point
        return QPointF(off_x + x / 100.0 * map_w,
                       off_y + y / 100.0 * map_h)

    def _polygon(self, points):
        return QPolygonF([self._point(point) for point in points])

    def _region_at(self, pos):
        point = QPointF(pos)
        for region_id, shape in REGION_SHAPES.items():
            if self._polygon(shape).containsPoint(point, Qt.OddEvenFill):
                return region_id
        return None

    # ── Painting helpers ───────────────────────────────────────────────────

    @staticmethod
    def _pen(color, width=1.0, style=Qt.SolidLine):
        pen = QPen(QColor(color), width)
        pen.setStyle(style)
        pen.setCapStyle(Qt.RoundCap)
        pen.setJoinStyle(Qt.RoundJoin)
        return pen

    def _draw_polyline(self, painter, points, pen):
        poly = QPolygonF([self._point(point) for point in points])
        painter.setPen(pen)
        painter.setBrush(Qt.NoBrush)
        painter.drawPolyline(poly)

    def _draw_geographic_context(self, painter):
        """Place Ardenia on land while leaving the Aster Sea to its west.

        A sea-coloured rectangle behind an isolated national polygon made the
        old dashboard read as an island.  Neighbor silhouettes now continue
        the northern, eastern and southern land frontiers to the viewport.
        """
        painter.setPen(Qt.NoPen)
        painter.setBrush(QBrush(QColor(theme.MAP_NEIGHBOR_LAND)))
        for shape in NEIGHBOR_LAND_SHAPES.values():
            painter.drawPolygon(self._polygon(shape))

    def _draw_regions(self, painter):
        for region_id, shape in REGION_SHAPES.items():
            polygon = self._polygon(shape)
            if self._outside_administration(region_id):
                # Control status is not a degree of pressure, so it is not
                # given a pressure colour: hatch over neutral grey, which
                # reads as "not ours to measure" at a glance.
                painter.setBrush(QBrush(QColor(theme.OUTSIDE_ADMIN)))
                painter.setPen(Qt.NoPen)
                painter.drawPolygon(polygon)
                painter.save()
                path = QPainterPath()
                path.addPolygon(polygon)
                painter.setClipPath(path)
                painter.setPen(self._pen(theme.OUTSIDE_ADMIN_LINE, 1.1))
                self._draw_hatch(painter, polygon.boundingRect())
                painter.restore()
            else:
                fill = self._region_fill(region_id)
                if region_id == self._hover_id:
                    fill = fill.lighter(118)
                painter.setBrush(QBrush(fill))
                painter.setPen(Qt.NoPen)
                painter.drawPolygon(polygon)

            if region_id == self._selected_id:
                border, width = theme.HIGHLIGHT, 2.4
            elif region_id == self._hover_id:
                border, width = theme.ACCENT, 2.0
            else:
                border, width = theme.BG, 1.6
            painter.setBrush(Qt.NoBrush)
            painter.setPen(self._pen(border, width))
            painter.drawPolygon(polygon)

        # Draw the whole outline quietly, then distinguish sea from sovereign
        # land frontiers.  The player can now understand Ardenia's position
        # without reading a label.
        painter.setBrush(Qt.NoBrush)
        painter.setPen(self._pen(theme.INK_DIM, 1.0))
        painter.drawPolygon(self._polygon(COUNTRY_OUTLINE))
        for points in LAND_BORDER_SEGMENTS.values():
            self._draw_polyline(
                painter, points, self._pen(theme.MAP_LAND_BORDER, 1.8))
        for points in COASTLINE_SEGMENTS:
            self._draw_polyline(
                painter, points, self._pen(theme.MAP_COASTLINE, 2.6))

    @staticmethod
    def _draw_hatch(painter, rect, spacing=7.0):
        """45° hatching across a clipped bounding rect."""
        start = rect.left() - rect.height()
        end = rect.right() + rect.height()
        x = start
        while x < end:
            painter.drawLine(QPointF(x, rect.bottom()),
                             QPointF(x + rect.height(), rect.top()))
            x += spacing

    def _region_state(self, region_id):
        return getattr(self.state, "regions", {}).get(region_id)

    # Only genuinely un-administered territory is hatched. "limited" (Anera)
    # and "autonomous" are administered — weakly, or jointly — and their
    # pressure readings are real, so hatching them would throw away live
    # information. See content/regions.py: CONTROL_LABELS.
    OUTSIDE_CONTROL = {"separatist"}

    def _outside_administration(self, region_id) -> bool:
        region = self._region_state(region_id)
        if region is None:
            return False
        return region.control in self.OUTSIDE_CONTROL

    def _region_fill(self, region_id):
        """The regional-pressure ramp, and nothing else.

        This used to blend an authored geographic tint with the shared
        good→critical status ramp, which meant the map's fills were competing
        with the same colours used for stat bars and party identity. One
        colour system per job: a map polygon means pressure.
        """
        region = self._region_state(region_id)
        if region is None:
            return QColor(REGION_COLORS[region_id])
        if self._outside_administration(region_id):
            return QColor(theme.OUTSIDE_ADMIN)
        return QColor(theme.pressure_color(region.pressure))

    def _draw_terrain_and_routes(self, painter):
        # Northern ridges stay deliberately quiet: terrain informs politics,
        # but should not turn a strategy dashboard into a decorative map.
        ridge_pen = self._pen("#8e7885", 1.1)
        self._draw_polyline(
            painter, NORTHERN_MOUNTAIN_FRONTIER,
            self._pen("#aa919b", 1.45, Qt.DashLine))
        for ridge in NORTHERN_RIDGES:
            self._draw_polyline(painter, ridge, ridge_pen)

        self._draw_polyline(painter, KESLA_POINTS, self._pen("#5f9fb5", 2.2))

        for route in ROUTES:
            kind = route["kind"]
            hints = ROUTE_STYLE_HINTS[kind]
            line_style = {
                "solid": Qt.SolidLine,
                "dotted": Qt.DotLine,
                "dashed": Qt.DashLine,
                "dash_dot": Qt.DashDotLine,
            }[hints["line"]]
            pen = self._pen(hints["color"], hints["width"], line_style)
            self._draw_polyline(painter, route["points"], pen)

        self._draw_polyline(painter, CEASEFIRE_LINE, self._pen(theme.CRITICAL, 2.4, Qt.DashLine))

        # Infrastructure symbols stay subordinate to cities.  Their presence
        # makes the roads legible as a network without adding permanent text.
        painter.setPen(self._pen(theme.BG, 1.0))
        painter.setBrush(QBrush(QColor(theme.MAP_CITY_LABEL)))
        for port in PORTS.values():
            point = self._point(port["point"])
            painter.drawRect(int(point.x() - 2.5), int(point.y() - 2.5), 5, 5)
        painter.setPen(self._pen(theme.HIGHLIGHT, 1.6))
        for checkpoint in CHECKPOINTS.values():
            point = self._point(checkpoint["point"])
            painter.drawLine(QPointF(point.x() - 3, point.y() - 3),
                             QPointF(point.x() + 3, point.y() + 3))


    def _halo_text(self, painter, x, y, text, color, halo=3.5,
                   align_centre=False):
        """Draw text with a dark outline under the fill.

        Label collision was the map's most visible problem — region names
        landing on city names, city names landing on neighbours. A halo does
        not stop two labels overlapping, but it does stop either of them
        disappearing into the fill or into each other, which is what made the
        overlaps unreadable rather than merely close.
        """
        metrics = painter.fontMetrics()
        if align_centre:
            x -= metrics.horizontalAdvance(text) / 2.0
        path = QPainterPath()
        path.addText(QPointF(x, y), painter.font(), text)
        painter.setBrush(Qt.NoBrush)
        pen = QPen(QColor(theme.BG), halo)
        pen.setJoinStyle(Qt.RoundJoin)
        painter.setPen(pen)
        painter.drawPath(path)
        painter.setPen(Qt.NoPen)
        painter.setBrush(QBrush(QColor(color)))
        painter.drawPath(path)

    def _centroid(self, points):
        """Area centroid of a region polygon — labels sit where the shape
        actually is, rather than at a hand-guessed anchor."""
        pts = [self._point(p) for p in points]
        area = 0.0
        cx = cy = 0.0
        for i in range(len(pts)):
            a, b = pts[i], pts[(i + 1) % len(pts)]
            cross = a.x() * b.y() - b.x() * a.y()
            area += cross
            cx += (a.x() + b.x()) * cross
            cy += (a.y() + b.y()) * cross
        if abs(area) < 1e-6:
            return QPointF(sum(p.x() for p in pts) / len(pts),
                           sum(p.y() for p in pts) / len(pts))
        area *= 0.5
        return QPointF(cx / (6.0 * area), cy / (6.0 * area))

    def _draw_labels(self, painter):
        region_font = QFont()
        region_font.setPointSize(theme.FONT_SIZE_SM)
        region_font.setBold(True)
        region_font.setLetterSpacing(QFont.AbsoluteSpacing, 1.6)
        painter.setFont(region_font)
        for region_id in REGION_SHAPES:
            label = REGION_MAP_LABELS[region_id]
            if not label:
                continue
            point = self._point(REGION_LABEL_ANCHORS[region_id])
            self._halo_text(painter, point.x(), point.y(), label,
                            theme.MAP_REGION_LABEL, halo=3.5, align_centre=True)

        # City labels are noise until they are relevant: only the capital is
        # permanently named, the rest appear for the region under the cursor
        # or the one currently selected.
        city_font = QFont()
        city_font.setPointSize(max(7, theme.FONT_SIZE_SM - 1))
        city_font.setLetterSpacing(QFont.PercentageSpacing, 100)
        painter.setFont(city_font)
        for city in CITY_MARKERS.values():
            point = self._point(city["point"])
            is_capital = bool(city.get("capital"))
            painter.setBrush(QBrush(QColor(
                theme.HIGHLIGHT if is_capital else theme.MAP_CITY_DOT)))
            painter.setPen(self._pen(theme.BG, 1.4))
            size = 4.4 if is_capital else 3.0
            painter.drawEllipse(point, size, size)

            shown = (is_capital
                     or city["region_id"] == self._hover_id
                     or city["region_id"] == self._selected_id)
            if not shown:
                continue
            # Offset to the RIGHT of the dot with a real gap, never centred
            # on it: a label centred on its own marker is guaranteed to
            # collide with the marker it is labelling.
            self._halo_text(painter, point.x() + size + 4.5,
                            point.y() + 4.0, city["name"], theme.MAP_CITY_LABEL, halo=3.0)

        border_font = QFont()
        border_font.setPointSize(max(6, theme.FONT_SIZE_SM - 2))
        border_font.setLetterSpacing(QFont.AbsoluteSpacing, 2.4)
        painter.setFont(border_font)
        for item in BORDER_LABELS:
            point = self._point(item["point"])
            if item["id"] == "aster_sea":
                continue
            self._halo_text(painter, point.x(), point.y(), item["name"],
                            theme.MAP_FOREIGN, halo=3.0, align_centre=True)

        sea_font = QFont()
        sea_font.setPointSize(max(6, theme.FONT_SIZE_SM - 2))
        sea_font.setItalic(True)
        sea_font.setLetterSpacing(QFont.AbsoluteSpacing, 2.0)
        painter.setFont(sea_font)
        sea_item = next(item for item in BORDER_LABELS
                        if item["id"] == "aster_sea")
        sea = self._point(sea_item["point"])
        self._halo_text(painter, sea.x(), sea.y(), "ASTER SEA", theme.MAP_SEA_LABEL, halo=2.5)

    def _draw_legend(self, painter):
        """Every state named in words, including the one that isn't a
        pressure level at all."""
        font = QFont()
        font.setPointSize(max(6, theme.FONT_SIZE_SM - 2))
        painter.setFont(font)
        metrics = painter.fontMetrics()

        entries = [(color, name) for _ceiling, color, name in theme.PRESSURE_STEPS]
        entries.append((theme.OUTSIDE_ADMIN, "Outside administration"))

        widths = [11 + 4 + metrics.horizontalAdvance(name) for _c, name in entries]
        x = max(10.0, self.width() - 12.0 - sum(widths) - 12 * (len(entries) - 1))
        y = 14.0
        for (color, name), width in zip(entries, widths):
            painter.setPen(Qt.NoPen)
            painter.setBrush(QBrush(QColor(color)))
            painter.drawRoundedRect(QPointF(x, y - 8).x(), y - 8, 11, 11, 2, 2)
            if name == "Outside administration":
                painter.setBrush(Qt.NoBrush)
                painter.setPen(self._pen(theme.OUTSIDE_ADMIN_LINE, 1.0, Qt.DashLine))
                painter.drawRect(int(x), int(y - 8), 11, 11)
            painter.setPen(self._pen(theme.INK_FAINT, 1.0))
            painter.setBrush(Qt.NoBrush)
            painter.drawText(QPointF(x + 15, y + 1), name)
            x += width + 12

    # ── Painting and interaction ───────────────────────────────────────────

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.fillRect(self.rect(), QColor(theme.PANEL_BG))
        painter.setBrush(QBrush(QColor(theme.MAP_SEA)))
        painter.setPen(self._pen(theme.PANEL_EDGE, 1.0))
        painter.drawRoundedRect(self.rect().adjusted(1, 1, -2, -2), 8, 8)

        self._draw_geographic_context(painter)
        self._draw_regions(painter)
        self._draw_terrain_and_routes(painter)
        self._draw_labels(painter)
        self._draw_legend(painter)
        painter.end()

    def mousePressEvent(self, event):
        region_id = self._region_at(event.position().toPoint())
        if region_id is not None:
            self._selected_id = region_id
            self.region_selected.emit(region_id)
            self.update()

    def mouseMoveEvent(self, event):
        region_id = self._region_at(event.position().toPoint())
        if region_id != self._hover_id:
            self._hover_id = region_id
            self.update()
        if region_id is None:
            self.setCursor(Qt.ArrowCursor)
            return
        self.setCursor(Qt.PointingHandCursor)
        region = self._regions[region_id]
        live = self._region_state(region_id)
        if live is None:
            detail = REGION_MAP_META[region_id]
        else:
            issue = REGIONAL_ISSUES[live.issue_id]
            leading, leading_share = region_engine.leading_party(self.state, region_id)
            political_line = (
                f"Polling: {leading.name} {leading_share*100:.0f}% · electoral access "
                f"{region_engine.electoral_access(self.state, region_id)*100:.0f}%"
                if leading is not None else "No administered electorate"
            )
            detail = (
                f"{REGION_MAP_META[region_id]}\n"
                f"Pressure {live.pressure*100:.0f}% · unemployment "
                f"{live.unemployment*100:.1f}% · state reach {live.state_reach*100:.0f}%\n"
                f"{political_line}\n"
                f"{CONTROL_LABELS[live.control]} · {issue['name']}"
            )
        QToolTip.showText(
            event.globalPosition().toPoint(),
            f"{region['name']}\n{detail}",
            self,
        )

    def leaveEvent(self, event):
        if self._hover_id is not None:
            self._hover_id = None
            self.update()
