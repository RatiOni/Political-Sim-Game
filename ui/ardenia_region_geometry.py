"""Nine-region political geography for Ardenia's national map.

Coordinates use the dashboard's stable 0..100 map space.  Each internal
border repeats the same chain in reverse in its neighbour, so the nine faces
tile one east-west silhouette without hairline gaps.  The western and
southwestern outer edges are the only coast; the north, east and southeast
are land frontiers.
"""


def _join(*chains):
    """Join shared border chains without duplicating their meeting points."""
    points = []
    for chain in chains:
        if points and points[-1] == chain[0]:
            points.extend(chain[1:])
        else:
            points.extend(chain)
    if len(points) > 1 and points[0] == points[-1]:
        points.pop()
    return points


# Administrative borders follow plausible terrain rather than shortest-line
# polygon cuts.  Every chain is shared verbatim by its two regions, reversed in
# one face, so painting and hit-testing cannot develop gaps between them.
_ANERA_KARSEN = [
    (45, 18), (45, 24), (43, 28), (44, 32), (43, 35),
]
_ANERA_VASHTERA = [
    (43, 35), (41, 37), (39, 39), (37, 41), (35, 43),
]
_ANERA_ORVENA = [
    (14, 28), (16, 32), (18, 34), (20, 38),
    (24, 40), (28, 42), (32, 42), (35, 43),
]
_KARSEN_DAREV = [
    (72, 19), (72, 23), (73, 26), (72, 30), (74, 34),
]
_KARSEN_ZAVOST = [
    (74, 34), (71, 35), (68, 35), (65, 37), (62, 37), (59, 39),
]
_KARSEN_VASHTERA = [
    (59, 39), (55, 40), (52, 39), (48, 38), (46, 36), (43, 35),
]
_VASHTERA_ZAVOST = [
    (59, 39), (61, 42), (61, 46), (63, 49), (63, 54),
]
_ZAVOST_DAREV = [
    (74, 34), (76, 37), (76, 41), (78, 44), (78, 48), (81, 53),
]
_ZAVOST_SELA = [
    (81, 53), (77, 54), (74, 56), (70, 55), (67, 56), (63, 54),
]
_VASHTERA_SELA = [
    (63, 54), (60, 55), (57, 55), (54, 57), (50, 56), (46, 56),
]
_VASHTERA_ORVENA = [
    (35, 43), (37, 46), (39, 48), (40, 52), (43, 54), (46, 56),
]
_DAREV_SELA = [
    (81, 53), (80, 56), (78, 59), (77, 62), (77, 65),
]
_SELA_KELVET = [
    (46, 76), (43, 73), (42, 70), (40, 68), (37, 66),
]
_SELA_ORVENA = [
    (37, 66), (39, 63), (41, 61), (43, 59), (46, 56),
]
_KELVET_ORVENA = [
    (37, 66), (34, 65), (31, 63), (29, 62), (27, 62),
]
_KELVET_VETRENKA = [
    (13, 72), (16, 70), (19, 69), (22, 66), (24, 64), (27, 62),
]
_ORVENA_VETRENKA = [
    (12, 51), (15, 52), (18, 51), (21, 54),
    (23, 57), (25, 59), (27, 62),
]


REGION_SHAPES = {
    "anera": _join(
        [(14, 28), (19, 25), (25, 23), (31, 20), (38, 22), (45, 18)],
        _ANERA_KARSEN,
        _ANERA_VASHTERA,
        list(reversed(_ANERA_ORVENA)),
    ),
    "karsen": _join(
        [(45, 18), (52, 20), (59, 17), (65, 20), (72, 19)],
        _KARSEN_DAREV,
        _KARSEN_ZAVOST,
        _KARSEN_VASHTERA,
        list(reversed(_ANERA_KARSEN)),
    ),
    "vashtera": _join(
        list(reversed(_KARSEN_VASHTERA)),
        _VASHTERA_ZAVOST,
        _VASHTERA_SELA,
        list(reversed(_VASHTERA_ORVENA)),
        list(reversed(_ANERA_VASHTERA)),
    ),
    "zavost": _join(
        list(reversed(_KARSEN_ZAVOST)),
        _ZAVOST_DAREV,
        _ZAVOST_SELA,
        list(reversed(_VASHTERA_ZAVOST)),
    ),
    "darev": _join(
        [
            (72, 19), (78, 22), (82, 27), (84, 33), (87, 34), (88, 38),
            (94, 40), (96, 44), (95, 49), (91, 52), (86, 51), (84, 56),
            (80, 60), (77, 65),
        ],
        list(reversed(_DAREV_SELA)),
        list(reversed(_ZAVOST_DAREV)),
        list(reversed(_KARSEN_DAREV)),
    ),
    "sela": _join(
        list(reversed(_ZAVOST_SELA)),
        _DAREV_SELA,
        [
            (77, 65), (72, 64), (68, 69), (62, 67),
            (58, 73), (51, 70), (46, 76),
        ],
        _SELA_KELVET,
        _SELA_ORVENA,
        list(reversed(_VASHTERA_SELA)),
    ),
    "kelvet": _join(
        [
            (46, 76), (40, 73), (34, 79), (28, 77), (22, 78),
            (18, 75), (15, 76), (13, 72),
        ],
        _KELVET_VETRENKA,
        list(reversed(_KELVET_ORVENA)),
        list(reversed(_SELA_KELVET)),
    ),
    "orvena": _join(
        [
            (14, 28), (14, 32), (12, 36), (13, 41),
            (11, 46), (12, 51),
        ],
        _ORVENA_VETRENKA,
        list(reversed(_KELVET_ORVENA)),
        _SELA_ORVENA,
        list(reversed(_VASHTERA_ORVENA)),
        list(reversed(_ANERA_ORVENA)),
    ),
    "vetrenka": _join(
        _ORVENA_VETRENKA,
        list(reversed(_KELVET_VETRENKA)),
        [(13, 72), (11, 68), (12, 62), (10, 57), (12, 51)],
    ),
}


# The ceasefire follows the complete shared Vetrenka-Orvena edge.  Exporting
# the polygon chain itself keeps the political overlay and hit geometry from
# telling two subtly different stories after future cartographic edits.
CEASEFIRE_LINE = list(_ORVENA_VETRENKA)


# Anchors are hand-placed inside the irregular polygons so labels remain
# stable even if the rendering widget later changes its centroid algorithm.
REGION_LABEL_ANCHORS = {
    "anera": (31, 29),
    "karsen": (56, 27),
    "zavost": (72, 46),
    "vashtera": (55, 48),
    "darev": (85, 43),
    "sela": (57, 64),
    "kelvet": (26, 72),
    "orvena": (29, 50),
    "vetrenka": (17, 58),
}


REGION_MAP_LABELS = {
    "anera": "ANERA",
    "karsen": "KARSEN",
    # The capital city label can stand in for the compact capital basin.
    "vashtera": "",
    "zavost": "ZAVOST",
    "darev": "DAREV",
    "sela": "SELA",
    "kelvet": "KELVET",
    "orvena": "ORVENA",
    "vetrenka": "VETRENKA",
}


REGION_COLORS = {
    "anera": "#455467",
    "karsen": "#536173",
    "vashtera": "#526a86",
    "zavost": "#596473",
    "darev": "#665f63",
    "sela": "#68775d",
    "kelvet": "#416d70",
    "orvena": "#5f6f61",
    "vetrenka": "#76555c",
}


REGION_MAP_META = {
    "anera": "Northwestern highlands · monasteries · weak state reach",
    "karsen": "North-central passes · winter roads · local brokers",
    "vashtera": "Capital basin · ministries · media",
    "zavost": "Eastern industry · unions · rail corridor",
    "darev": "Far-eastern frontier · market towns · border security",
    "sela": "Central grain basin · land claims · rural credit",
    "kelvet": "Southern trade route · customs · warm-water access",
    "orvena": "Loyalist foothills · displaced families · western port",
    "vetrenka": "Western separatist coast · ceasefire territory",
}
