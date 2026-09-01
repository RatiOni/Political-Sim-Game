"""Nine-region political geography for Ardenia's national map.

Coordinates use the dashboard's stable 0..100 map space.  Each internal
border repeats the same chain in reverse in its neighbour, so the nine faces
tile one east-west silhouette without hairline gaps.  The western and
southwestern outer edges are the only coast; the north, east and southeast
are land frontiers.
"""


REGION_SHAPES = {
    "anera": [
        (14, 28), (19, 25), (25, 23), (31, 20), (38, 22), (45, 18),
        (42, 36), (24, 41),
    ],
    "karsen": [
        (45, 18), (52, 20), (59, 17), (65, 20), (72, 19),
        (74, 34), (58, 38), (42, 36),
    ],
    "zavost": [
        (74, 34), (82, 51), (72, 58), (66, 55), (58, 38),
    ],
    "vashtera": [
        (42, 36), (58, 38), (66, 55), (52, 58), (43, 52),
    ],
    "darev": [
        (72, 19), (78, 22), (82, 27), (84, 33), (87, 34), (88, 38),
        (94, 40), (96, 44), (95, 49), (91, 52), (86, 51), (84, 56),
        (80, 60), (77, 65), (72, 58), (82, 51), (74, 34),
    ],
    "sela": [
        (43, 52), (52, 58), (66, 55), (72, 58), (77, 65),
        (72, 64), (68, 69), (62, 67), (58, 73), (51, 70),
        (46, 76), (40, 73), (38, 66),
    ],
    "kelvet": [
        (29, 62), (38, 66), (40, 73), (34, 79), (28, 77), (22, 78),
        (18, 75), (15, 76), (13, 72), (20, 67),
    ],
    "orvena": [
        (14, 28), (24, 41), (42, 36), (43, 52), (38, 66), (29, 62),
        (25, 52), (12, 51), (11, 46), (13, 41), (12, 36), (14, 32),
    ],
    "vetrenka": [
        (12, 51), (25, 52), (29, 62), (20, 67), (13, 72),
        (11, 68), (12, 62), (10, 57),
    ],
}


# The ceasefire follows the complete shared Vetrenka-Orvena edge.  Exporting
# the polygon chain itself keeps the political overlay and hit geometry from
# telling two subtly different stories after future cartographic edits.
CEASEFIRE_LINE = [(12, 51), (25, 52), (29, 62)]


# Anchors are hand-placed inside the irregular polygons so labels remain
# stable even if the rendering widget later changes its centroid algorithm.
REGION_LABEL_ANCHORS = {
    "anera": (31, 29),
    "karsen": (56, 27),
    "zavost": (72, 46),
    "vashtera": (55, 48),
    "darev": (85, 43),
    "sela": (55, 65),
    "kelvet": (26, 72),
    "orvena": (30, 47),
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
