"""Compatibility façade for Ardenia's layered national cartography.

Country form, political regions, and infrastructure are authored separately
so changing a road cannot accidentally deform a border and adding a region
does not require duplicating the coastline.  Existing UI imports continue to
use this module while new code may import the narrower sources directly.
"""

from ui.ardenia_country_geometry import (
    BORDER_LABELS,
    COASTLINE_SEGMENTS,
    COUNTRY_OUTLINE,
    KESLA_BASIN_PATH,
    LAND_BORDER_SEGMENTS,
    NEIGHBOR_LAND_SHAPES,
    NORTHERN_MOUNTAIN_FRONTIER,
    NORTHERN_MOUNTAIN_RIDGES,
)
from ui.ardenia_infrastructure_geometry import (
    CHECKPOINTS,
    CITY_MARKERS,
    MARKER_STYLE_HINTS,
    PORTS,
    RIVERS,
    RIVER_CROSSINGS,
    ROUTES,
    ROUTE_STYLE_HINTS,
)
from ui.ardenia_region_geometry import (
    CEASEFIRE_LINE,
    REGION_COLORS,
    REGION_LABEL_ANCHORS,
    REGION_MAP_LABELS,
    REGION_MAP_META,
    REGION_SHAPES,
)


# Compatibility aliases for the original widget API.  The river defined by
# the infrastructure layer is authoritative because its crossings and routes
# refer to the same points.
KESLA_POINTS = RIVERS["kesla"]["points"]
NORTHERN_RIDGES = NORTHERN_MOUNTAIN_RIDGES


__all__ = [
    "BORDER_LABELS", "CEASEFIRE_LINE", "CHECKPOINTS", "CITY_MARKERS",
    "COASTLINE_SEGMENTS", "COUNTRY_OUTLINE", "KESLA_BASIN_PATH",
    "KESLA_POINTS", "LAND_BORDER_SEGMENTS", "MARKER_STYLE_HINTS",
    "NEIGHBOR_LAND_SHAPES", "NORTHERN_MOUNTAIN_FRONTIER",
    "NORTHERN_MOUNTAIN_RIDGES", "NORTHERN_RIDGES", "PORTS",
    "REGION_COLORS", "REGION_LABEL_ANCHORS", "REGION_MAP_LABELS",
    "REGION_MAP_META", "REGION_SHAPES", "RIVERS", "RIVER_CROSSINGS",
    "ROUTES", "ROUTE_STYLE_HINTS",
]
