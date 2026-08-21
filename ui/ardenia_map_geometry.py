"""Hand-authored presentation geometry for Ardenia's national dashboard map.

Coordinates are in a stable 0..100 map space. The outline is original: a
compact east-west country with a northern mountain wall and a southern coast,
not a traced real-world border. Region ids come from content.lore.geography
and are intentionally ready for future regional simulation.
"""

# One national silhouette, drawn above the regional polygons as a clear
# recognised border. The southern chain of points is the warm coast.
COUNTRY_OUTLINE = [
    (10, 45), (13, 33), (22, 19), (40, 12), (58, 10), (73, 17),
    (90, 23), (95, 35), (91, 45), (94, 56), (87, 64), (86, 75),
    (75, 85), (60, 88), (47, 92), (33, 88), (24, 84), (16, 76),
    (11, 63),
]

# The six regions tile the national silhouette. Shared points deliberately
# match so every administrative boundary renders as one clean line.
REGION_SHAPES = {
    "anera": [
        (10, 45), (13, 33), (22, 19), (40, 12), (47, 17), (45, 32),
        (35, 41), (26, 52), (16, 55), (11, 63),
    ],
    "vashtera": [
        (47, 17), (58, 10), (73, 17), (70, 35), (61, 43), (51, 46),
        (35, 41), (45, 32),
    ],
    "zavost": [
        (73, 17), (90, 23), (95, 35), (91, 45), (94, 56), (87, 64),
        (75, 58), (64, 59), (65, 49), (61, 43), (70, 35),
    ],
    "sela": [
        (35, 41), (51, 46), (61, 43), (65, 49), (64, 59), (51, 70),
        (35, 69), (26, 60), (26, 52),
    ],
    "kelvet": [
        (64, 59), (75, 58), (87, 64), (86, 75), (75, 85), (60, 88),
        (50, 80), (51, 70),
    ],
    "vetrenka": [
        (11, 63), (16, 55), (26, 52), (26, 60), (35, 69), (51, 70),
        (50, 80), (47, 92), (33, 88), (24, 84), (16, 76),
    ],
}

# Hand-placed label anchors, retained for reference only. The map now labels
# each region at its polygon's own area centroid (widgets_ardenia_map.py:
# _centroid), because hand-guessed anchors drifted out of their shapes and
# were a direct cause of Vashtera colliding with ANERA and ZAVOST.
REGION_LABEL_ANCHORS = {
    "anera": (23, 34),
    "vashtera": (57, 26),
    "zavost": (78, 40),
    "sela": (43, 57),
    "kelvet": (70, 70),
    "vetrenka": (28, 72),
}

# Formal names remain in lore; cartographic labels make room for cities,
# routes and the ceasefire without turning the dashboard into a wall of text.
REGION_MAP_LABELS = {
    "anera": "ANERA",
    # The capital marker and city name already identify this small district.
    "vashtera": "",
    "zavost": "ZAVOST",
    "sela": "SELA",
    "kelvet": "KELVET",
    "vetrenka": "VETRENKA",
}

# Presentation colours are deliberately subdued so the political overlays,
# city markers and ceasefire line remain legible.
REGION_COLORS = {
    "anera": "#455467",
    "vashtera": "#526a86",
    "zavost": "#596473",
    "sela": "#68775d",
    "kelvet": "#416d70",
    "vetrenka": "#76555c",
}

# Short map-facing facts. Fuller prose remains in content/lore/geography.py.
REGION_MAP_META = {
    "anera": "Highlands · monasteries · weak state reach",
    "vashtera": "Capital district · ministries · media",
    "zavost": "Industry · unions · Krasovan border",
    "sela": "Grain plain · land claims · rural credit",
    "kelvet": "Ports · customs · trade and contraband",
    "vetrenka": "Ceasefire territory · outside Vashtera's control",
}

CITY_MARKERS = {
    "vashtera_city": {"name": "Vashtera", "region_id": "vashtera", "point": (52, 38), "capital": True},
    "duvinsk": {"name": "Duvinsk", "region_id": "zavost", "point": (76, 47)},
    "tavri": {"name": "Tavri", "region_id": "kelvet", "point": (70, 80)},
    "rovets": {"name": "Rovets", "region_id": "sela", "point": (42, 62)},
    "kavor": {"name": "Kavor", "region_id": "anera", "point": (27, 45)},
    "ostrena": {"name": "Ostrena", "region_id": "vetrenka", "point": (27, 76)},
}

# The Kesla is the visible national spine. Routes are strategic hints only in
# this presentation step; they are not yet simulation inputs.
KESLA_POINTS = [(55, 14), (54, 24), (52, 38), (50, 50), (56, 64), (70, 80)]
ROUTES = [
    {"id": "vashtera_duvinsk_rail", "kind": "rail", "points": [(52, 38), (65, 43), (79, 47)]},
    {"id": "vashtera_tavri_road", "kind": "road", "points": [(52, 38), (50, 50), (56, 64), (70, 80)]},
    {"id": "sela_road", "kind": "road", "points": [(42, 62), (50, 50), (52, 38)]},
    {"id": "zovar_line", "kind": "pipeline", "points": [(94, 45), (79, 47), (65, 43), (52, 38)]},
]

CEASEFIRE_LINE = [(18, 59), (26, 64), (35, 69), (44, 75)]
NORTHERN_RIDGES = [
    [(18, 31), (25, 23), (32, 28), (39, 19)],
    [(39, 19), (47, 17), (54, 14), (63, 16), (70, 21)],
]

# Labels beyond Ardenia's border. They give foreign pressure a spatial place
# without returning the dashboard to a continent map.
BORDER_LABELS = [
    {"id": "veldoria", "name": "VELDORIA", "point": (31, 6)},
    {"id": "krasova", "name": "KRASOVA", "point": (98, 42)},
    {"id": "merova", "name": "MEROVA", "point": (88, 92)},
]
