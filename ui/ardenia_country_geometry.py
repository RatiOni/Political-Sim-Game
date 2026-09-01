"""Presentation-only national geography for the Ardenia dashboard map.

All points use the map's stable 0..100 coordinate space.  The silhouette is an
original east-west country inspired by the geographic *structure* of Georgia:
a broken western coast, a long northern mountain frontier, a central river
basin, an eastern salient, and an irregular southern land border.  It does not
trace any real border and contains no simulation or regional ownership data.

The coastline and land borders are exported separately from ``COUNTRY_OUTLINE``
so a renderer can distinguish sea from neighboring territory.  Neighbor shapes
are deliberately broad background silhouettes intended to be clipped by the
map viewport and painted behind Ardenia.
"""


# Private shared boundary chains keep the outline, coast, and neighboring land
# exact without exposing region polygons.  The outline proceeds clockwise from
# the northwestern end of the coast.
_NORTHERN_BORDER = [
    (14.0, 28.0),
    (19.0, 25.0),
    (25.0, 23.0),
    (31.0, 20.0),
    (38.0, 22.0),
    (45.0, 18.0),
    (52.0, 20.0),
    (59.0, 17.0),
    (65.0, 20.0),
    (72.0, 19.0),
    (78.0, 22.0),
    (82.0, 27.0),
    (84.0, 33.0),
]

_KRASOVAN_BORDER = [
    (84.0, 33.0),
    (87.0, 34.0),
    (88.0, 38.0),
    (94.0, 40.0),
    (96.0, 44.0),
    (95.0, 49.0),
    (91.0, 52.0),
    (86.0, 51.0),
]

_MEROVAN_BORDER = [
    (86.0, 51.0),
    (84.0, 56.0),
    (80.0, 60.0),
    (77.0, 65.0),
    (72.0, 64.0),
    (68.0, 69.0),
    (62.0, 67.0),
    (58.0, 73.0),
    (51.0, 70.0),
    (46.0, 76.0),
    (40.0, 73.0),
    (34.0, 79.0),
    (28.0, 77.0),
    (22.0, 78.0),
]

_WESTERN_COAST = [
    (22.0, 78.0),
    (18.0, 75.0),
    (15.0, 76.0),
    (13.0, 72.0),
    (11.0, 68.0),
    (12.0, 62.0),
    (10.0, 57.0),
    (12.0, 51.0),
    (11.0, 46.0),
    (13.0, 41.0),
    (12.0, 36.0),
    (14.0, 32.0),
    (14.0, 28.0),
]


# COUNTRY_OUTLINE is the complete clockwise national silhouette.  Its final
# chain climbs the coast from Ardenia's southwestern corner back to the north.
COUNTRY_OUTLINE = (
    _NORTHERN_BORDER
    + _KRASOVAN_BORDER[1:]
    + _MEROVAN_BORDER[1:]
    + _WESTERN_COAST[1:]
)


# COASTLINE_SEGMENTS contains only edges facing the Aster Sea.  Keeping this
# explicit prevents renderers from applying surf, glow, or shoreline styling to
# Ardenia's northern, eastern, or southern land frontiers.
COASTLINE_SEGMENTS = [
    list(reversed(_WESTERN_COAST)),
]


# LAND_BORDER_SEGMENTS maps each neighboring country to the precise national
# boundary it shares with Ardenia.  Veldoria owns the mountain frontier,
# Krasova the northeastern/eastern salient, and Merova the southeast and south.
LAND_BORDER_SEGMENTS = {
    "veldoria": list(_NORTHERN_BORDER),
    "krasova": list(_KRASOVAN_BORDER),
    "merova": list(_MEROVAN_BORDER),
}


# NEIGHBOR_LAND_SHAPES are background polygons that continue beyond Ardenia's
# land borders to the viewport edge.  They are not political regions and carry
# no gameplay meaning; they simply make the country sit within a continent.
NEIGHBOR_LAND_SHAPES = {
    "veldoria": [
        (5.0, 4.0),
        (88.0, 4.0),
        (88.0, 26.0),
        (84.0, 33.0),
        *_NORTHERN_BORDER[-2::-1],
        (9.0, 25.0),
        (5.0, 20.0),
    ],
    "krasova": [
        (84.0, 33.0),
        *_KRASOVAN_BORDER[1:],
        (100.0, 55.0),
        (100.0, 24.0),
        (90.0, 25.0),
    ],
    "merova": [
        (86.0, 51.0),
        *_MEROVAN_BORDER[1:],
        (20.0, 98.0),
        (100.0, 98.0),
        (100.0, 52.0),
    ],
}


# NORTHERN_MOUNTAIN_FRONTIER is the high-level crest that follows the Veldorian
# border.  It is separated from the decorative ridges so a renderer can give
# the frontier a stronger stroke without turning every ridge into a border.
NORTHERN_MOUNTAIN_FRONTIER = [
    (17.0, 28.0),
    (24.0, 25.0),
    (31.0, 22.0),
    (38.0, 24.0),
    (45.0, 20.0),
    (52.0, 22.0),
    (59.0, 19.0),
    (66.0, 22.0),
    (73.0, 21.0),
    (80.0, 27.0),
]


# NORTHERN_MOUNTAIN_RIDGES supplies secondary broken relief lines below the
# frontier.  The gaps create passes into the central basin and avoid a single
# decorative zig-zag reading as a wall icon.
NORTHERN_MOUNTAIN_RIDGES = [
    [(18.0, 32.0), (23.0, 29.0), (28.0, 31.0), (33.0, 25.0), (38.0, 28.0)],
    [(35.0, 30.0), (41.0, 25.0), (47.0, 28.0), (52.0, 23.0), (57.0, 27.0)],
    [(55.0, 28.0), (61.0, 23.0), (66.0, 27.0), (72.0, 24.0), (78.0, 30.0)],
]


# KESLA_BASIN_PATH is the major river's centerline, running from northern
# headwaters through the central basin to its Aster Sea mouth in the southwest.
KESLA_BASIN_PATH = [
    (59.0, 21.0),
    (56.0, 28.0),
    (54.0, 35.0),
    (50.0, 42.0),
    (46.0, 49.0),
    (40.0, 55.0),
    (34.0, 61.0),
    (27.0, 66.0),
    (20.0, 69.0),
    (13.0, 72.0),
]


# BORDER_LABEL_ANCHORS gives uncluttered label positions outside Ardenia.  The
# Aster Sea anchor is included here because it is the western geographic edge,
# even though it has no land silhouette or land-border segment.
BORDER_LABEL_ANCHORS = {
    "veldoria": (48.0, 8.0),
    "krasova": (96.0, 29.0),
    "merova": (76.0, 91.0),
    "aster_sea": (4.5, 54.0),
}


# BORDER_LABELS is a renderer-ready ordered form of the anchors.  Names are the
# project's existing proper nouns; the order follows north, east, south, west.
BORDER_LABELS = [
    {"id": "veldoria", "name": "VELDORIA", "point": BORDER_LABEL_ANCHORS["veldoria"]},
    {"id": "krasova", "name": "KRASOVA", "point": BORDER_LABEL_ANCHORS["krasova"]},
    {"id": "merova", "name": "MEROVA", "point": BORDER_LABEL_ANCHORS["merova"]},
    {"id": "aster_sea", "name": "ASTER SEA", "point": BORDER_LABEL_ANCHORS["aster_sea"]},
]


def _validate_geometry():
    """Fail fast if edited presentation data leaves the normalized map space."""

    point_groups = {
        "COUNTRY_OUTLINE": [COUNTRY_OUTLINE],
        "COASTLINE_SEGMENTS": COASTLINE_SEGMENTS,
        "LAND_BORDER_SEGMENTS": list(LAND_BORDER_SEGMENTS.values()),
        "NEIGHBOR_LAND_SHAPES": list(NEIGHBOR_LAND_SHAPES.values()),
        "NORTHERN_MOUNTAIN_FRONTIER": [NORTHERN_MOUNTAIN_FRONTIER],
        "NORTHERN_MOUNTAIN_RIDGES": NORTHERN_MOUNTAIN_RIDGES,
        "KESLA_BASIN_PATH": [KESLA_BASIN_PATH],
        "BORDER_LABEL_ANCHORS": [list(BORDER_LABEL_ANCHORS.values())],
    }
    for name, groups in point_groups.items():
        for points in groups:
            if len(points) < 2:
                raise ValueError(f"{name} contains an unusable point sequence")
            for point in points:
                if len(point) != 2 or not all(0.0 <= value <= 100.0 for value in point):
                    raise ValueError(f"{name} contains an invalid map point: {point!r}")

    if set(LAND_BORDER_SEGMENTS) != {"veldoria", "krasova", "merova"}:
        raise ValueError("Ardenia's land borders must use only its three established neighbors")
    if set(NEIGHBOR_LAND_SHAPES) != set(LAND_BORDER_SEGMENTS):
        raise ValueError("Every land border needs one neighboring background silhouette")
    if any(x > 22.0 for segment in COASTLINE_SEGMENTS for x, _y in segment):
        raise ValueError("Sea coastline must remain confined to western Ardenia")


_validate_geometry()
