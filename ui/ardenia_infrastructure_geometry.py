"""Presentation-only infrastructure geometry for Ardenia's national map.

All points use the map's stable 0..100 coordinate space.  This module has no
engine or content imports: renderers may opt into the data without turning a
road, port, or checkpoint into simulation state.

The layout assumes an east-west country with the Aster Sea on the west and
southwest, a central-eastern capital basin, northern mountains, and an eastern
industrial/frontier corridor.  City and route ids are stable integration keys;
the concise labels here are cartographic metadata, not city lore.
"""


CITY_MARKERS = {
    # Existing cities.  Their ids and established region associations remain
    # stable even where the revised national projection moves their markers.
    "vashtera_city": {
        "name": "Vashtera",
        "region_id": "vashtera",
        "point": (62, 48),
        "city_type": "capital",
        "importance": "national",
        "capital": True,
    },
    "duvinsk": {
        "name": "Duvinsk",
        "region_id": "zavost",
        "point": (76, 47),
        "city_type": "industrial_city",
        "importance": "national",
    },
    "tavri": {
        "name": "Tavri",
        "region_id": "kelvet",
        "point": (22, 73),
        "city_type": "port_city",
        "importance": "national",
    },
    "rovets": {
        "name": "Rovets",
        "region_id": "sela",
        "point": (49, 65),
        "city_type": "agricultural_market",
        "importance": "regional",
    },
    "kavor": {
        "name": "Kavor",
        "region_id": "anera",
        "point": (32, 30),
        "city_type": "highland_town",
        "importance": "regional",
    },
    "ostrena": {
        "name": "Ostrena",
        "region_id": "vetrenka",
        "point": (15, 55),
        "city_type": "disputed_coastal_city",
        "importance": "regional",
    },

    # Proposed secondary cities for the expanded nine-region map.
    "karvel": {
        "name": "Karvel",
        "region_id": "karsen",
        "point": (49, 22),
        "city_type": "mountain_gateway",
        "importance": "regional",
    },
    "lestara": {
        "name": "Lestara",
        "region_id": "karsen",
        "point": (54, 36),
        "city_type": "rail_junction",
        "importance": "regional",
    },
    "ordel": {
        "name": "Ordel",
        "region_id": "orvena",
        "point": (35, 53),
        "city_type": "foothill_market",
        "importance": "regional",
    },
    "selvara": {
        "name": "Selvara",
        "region_id": "orvena",
        "point": (13, 37),
        "city_type": "coastal_port",
        "importance": "regional",
    },
    "meradin": {
        "name": "Meradin",
        "region_id": "darev",
        "point": (81, 58),
        "city_type": "frontier_garrison",
        "importance": "regional",
    },
    "azren": {
        "name": "Azren",
        "region_id": "darev",
        "point": (87, 39),
        "city_type": "energy_hub",
        "importance": "regional",
    },
}


# Rivers are presentation context for bridges and transport bottlenecks.  The
# Kesla descends from Karsen, crosses the Vashtera basin and Sela plain, then
# reaches the Aster Sea in the southwest.
RIVERS = {
    "kesla": {
        "name": "Kesla",
        "points": [
            (49, 22), (52, 29), (54, 36), (58, 42), (62, 48),
            (57, 56), (49, 65), (39, 70), (29, 72), (22, 73), (15, 73),
        ],
        "mouth": "aster_sea",
    },
}


# Endpoints always name CITY_MARKERS ids.  Checkpoint connections are exposed
# separately through ``checkpoint_ids`` so a route still has two city anchors.
ROUTES = [
    {
        "id": "aster_trunk_road",
        "name": "Aster Trunk Road",
        "kind": "road",
        "endpoints": ("selvara", "meradin"),
        "points": [
            (13, 37), (24, 44), (35, 53), (48, 51), (62, 48),
            (76, 47), (81, 54), (81, 58),
        ],
        "checkpoint_ids": ("vetrenka_east_gate", "darev_frontier_post"),
    },
    {
        "id": "southern_grain_road",
        "name": "Southern Grain Road",
        "kind": "road",
        "endpoints": ("tavri", "vashtera_city"),
        "points": [(22, 73), (35, 70), (49, 65), (55, 57), (62, 48)],
    },
    {
        "id": "karsen_pass_road",
        "name": "Karsen Pass Road",
        "kind": "mountain_road",
        "endpoints": ("vashtera_city", "karvel"),
        "points": [(62, 48), (58, 42), (54, 36), (51, 29), (49, 22)],
        "checkpoint_ids": ("karsen_pass_post",),
        "seasonal": True,
    },
    {
        "id": "western_coast_road",
        "name": "Western Coast Road",
        "kind": "road",
        "endpoints": ("tavri", "selvara"),
        "points": [(22, 73), (17, 66), (15, 55), (12, 46), (13, 37)],
        "checkpoint_ids": ("ostrena_ceasefire_post", "vetrenka_east_gate"),
    },
    {
        "id": "darev_frontier_road",
        "name": "Darev Frontier Road",
        "kind": "road",
        "endpoints": ("duvinsk", "azren"),
        "points": [(76, 47), (83, 43), (87, 39)],
        "checkpoint_ids": ("azren_border_post",),
    },
    {
        "id": "aster_main_rail",
        "name": "Aster Main Line",
        "kind": "rail",
        "endpoints": ("tavri", "azren"),
        "points": [
            (22, 73), (35, 69), (49, 65), (55, 57), (62, 48),
            (70, 46), (76, 47), (84, 43), (87, 39),
        ],
    },
    {
        "id": "karsen_freight_rail",
        "name": "Karsen Freight Spur",
        "kind": "rail",
        "endpoints": ("vashtera_city", "lestara"),
        "points": [(62, 48), (59, 43), (54, 36)],
        "constrained": "gorge",
    },
    {
        "id": "orvena_coast_rail",
        "name": "Orvena Coast Spur",
        "kind": "rail",
        "endpoints": ("tavri", "ordel"),
        "points": [(22, 73), (28, 64), (35, 53)],
    },
    {
        "id": "aster_energy_pipeline",
        "name": "Aster Energy Pipeline",
        "kind": "pipeline",
        "endpoints": ("tavri", "azren"),
        "points": [
            (22, 73), (34, 75), (49, 65), (59, 59), (68, 55),
            (76, 47), (83, 42), (87, 39),
        ],
    },
]


PORTS = {
    "tavri_deepwater_port": {
        "name": "Tavri Deepwater Port",
        "city_id": "tavri",
        "point": (20.5, 75),
        "water": "aster_sea",
        "port_type": "deepwater_commercial",
        "importance": "national",
    },
    "selvara_harbour": {
        "name": "Selvara Harbour",
        "city_id": "selvara",
        "point": (11.5, 37.5),
        "water": "aster_sea",
        "port_type": "regional_mixed",
        "importance": "regional",
    },
    "ostrena_roadstead": {
        "name": "Ostrena Roadstead",
        "city_id": "ostrena",
        "point": (13.5, 56),
        "water": "aster_sea",
        "port_type": "limited_roadstead",
        "importance": "local",
    },
}


CHECKPOINTS = {
    "ostrena_ceasefire_post": {
        "name": "Ostrena Ceasefire Post",
        "point": (17, 62),
        "region_id": "vetrenka",
        "kind": "ceasefire",
    },
    "vetrenka_east_gate": {
        "name": "East Gate",
        "point": (24, 44),
        "region_id": "orvena",
        "kind": "internal_control",
    },
    "karsen_pass_post": {
        "name": "Karvel Pass Post",
        "point": (49, 21),
        "region_id": "karsen",
        "kind": "mountain_border",
    },
    "darev_frontier_post": {
        "name": "Meradin Frontier Post",
        "point": (82, 57),
        "region_id": "darev",
        "kind": "border",
    },
    "azren_border_post": {
        "name": "Azren Border Post",
        "point": (87, 36),
        "region_id": "darev",
        "kind": "border",
    },
}


RIVER_CROSSINGS = {
    "lestara_gorge_bridge": {
        "name": "Lestara Gorge Bridge",
        "river_id": "kesla",
        "point": (54, 36),
        "region_id": "karsen",
        "kind": "road_rail_bridge",
        "route_ids": ("karsen_pass_road", "karsen_freight_rail"),
    },
    "vashtera_central_bridge": {
        "name": "Vashtera Central Bridge",
        "river_id": "kesla",
        "point": (62, 48),
        "region_id": "vashtera",
        "kind": "road_rail_bridge",
        "route_ids": ("aster_trunk_road", "aster_main_rail"),
    },
    "rovets_freight_bridge": {
        "name": "Rovets Freight Bridge",
        "river_id": "kesla",
        "point": (49, 65),
        "region_id": "sela",
        "kind": "road_rail_pipeline_crossing",
        "route_ids": (
            "southern_grain_road", "aster_main_rail", "aster_energy_pipeline",
        ),
    },
}


# Suggested visual hierarchy.  Qt-specific pen objects deliberately stay in
# the renderer; these hints are portable to another front-end.
ROUTE_STYLE_HINTS = {
    "road": {"color": "#a89c93", "width": 1.05, "line": "dotted", "layer": 30},
    "mountain_road": {"color": "#b6a49a", "width": 1.05, "line": "dashed", "layer": 30},
    "rail": {"color": "#c3aeb8", "width": 1.35, "line": "dashed", "layer": 32},
    "pipeline": {"color": "#d3a95a", "width": 1.50, "line": "dash_dot", "layer": 31},
    "river": {"color": "#5f9fb5", "width": 2.20, "line": "solid", "layer": 20},
}

MARKER_STYLE_HINTS = {
    "city": {"layer": 50},
    "port": {"symbol": "anchor", "layer": 48},
    "checkpoint": {"symbol": "bar", "layer": 47},
    "river_crossing": {"symbol": "bridge", "layer": 49},
}
