"""Focused contract checks for Ardenia's nine-region expansion."""

import unittest
from collections import Counter

from content.regions import ARDENIA_REGION_PROFILES
from engine.campaign import default_config, generate_campaign
from engine.persistence import deserialize_state, serialize_state
from engine.regions import ensure_region_states, initial_region_states
from ui.ardenia_region_geometry import (
    CEASEFIRE_LINE,
    REGION_COLORS,
    REGION_LABEL_ANCHORS,
    REGION_MAP_LABELS,
    REGION_MAP_META,
    REGION_SHAPES,
)
from ui.ardenia_country_geometry import COUNTRY_OUTLINE
from ui.ardenia_infrastructure_geometry import CHECKPOINTS, CITY_MARKERS, RIVERS


EXPECTED_REGIONS = {
    "anera", "karsen", "vashtera", "zavost", "darev",
    "sela", "kelvet", "orvena", "vetrenka",
}
EXPECTED_NAMES = {
    "karsen": "Karsen",
    "orvena": "Orvena",
    "darev": "Darev",
}
REQUIRED_PROFILE_FIELDS = {
    "name", "population_weight", "unemployment_gap",
    "initial_unemployment", "reach_offset", "initial_state_reach",
    "initial_pressure", "pressure_bias", "control", "party_support",
    "issue_id", "issue_name", "issue_body",
}


def _edge(a, b):
    return tuple(sorted((a, b)))


def _point_on_segment(point, a, b, epsilon=1e-9):
    px, py = point
    ax, ay = a
    bx, by = b
    cross = (px - ax) * (by - ay) - (py - ay) * (bx - ax)
    if abs(cross) > epsilon:
        return False
    return (min(ax, bx) - epsilon <= px <= max(ax, bx) + epsilon
            and min(ay, by) - epsilon <= py <= max(ay, by) + epsilon)


def _contains(polygon, point):
    inside = False
    previous = polygon[-1]
    for current in polygon:
        if _point_on_segment(point, previous, current):
            return True
        x1, y1 = previous
        x2, y2 = current
        px, py = point
        if ((y1 > py) != (y2 > py)):
            crossing_x = (x2 - x1) * (py - y1) / (y2 - y1) + x1
            if px < crossing_x:
                inside = not inside
        previous = current
    return inside


class RegionExpansionTests(unittest.TestCase):
    def test_all_nine_profiles_are_mechanically_complete(self):
        self.assertEqual(set(ARDENIA_REGION_PROFILES), EXPECTED_REGIONS)
        self.assertAlmostEqual(
            sum(p["population_weight"] for p in ARDENIA_REGION_PROFILES.values()),
            1.0,
        )
        for region_id, profile in ARDENIA_REGION_PROFILES.items():
            self.assertFalse(REQUIRED_PROFILE_FIELDS - set(profile), region_id)
            self.assertEqual(profile["name"], EXPECTED_NAMES.get(region_id, profile["name"]))
            self.assertAlmostEqual(sum(profile["party_support"].values()), 1.0)
            self.assertEqual(set(profile["party_support"]), {
                "liberal_democrats", "national_conservatives",
                "social_democrats", "agrarian_union", "workers_front",
            })

    def test_initial_state_contains_every_authored_region(self):
        states = initial_region_states("ardenia")
        self.assertEqual(set(states), EXPECTED_REGIONS)
        for region_id, state in states.items():
            self.assertEqual(state.id, region_id)
            self.assertAlmostEqual(sum(state.party_support.values()), 1.0)

    def test_old_six_region_state_is_additively_upgraded(self):
        state = generate_campaign(default_config())
        original_vashtera = state.regions["vashtera"]
        original_vashtera.pressure = 0.987
        state.regions = {
            region_id: region
            for region_id, region in state.regions.items()
            if region_id not in {"karsen", "orvena", "darev"}
        }

        ensure_region_states(state)

        self.assertEqual(set(state.regions), EXPECTED_REGIONS)
        self.assertIs(state.regions["vashtera"], original_vashtera)
        self.assertEqual(state.regions["vashtera"].pressure, 0.987)

    def test_deserializing_six_region_save_preserves_live_values(self):
        state = generate_campaign(default_config())
        saved = serialize_state(state)
        saved["regions"]["vashtera"]["pressure"] = 0.876
        for region_id in ("karsen", "orvena", "darev"):
            saved["regions"].pop(region_id)

        restored = deserialize_state(saved)

        self.assertEqual(set(restored.regions), EXPECTED_REGIONS)
        self.assertEqual(restored.regions["vashtera"].pressure, 0.876)

    def test_region_geometry_covers_the_same_nine_ids(self):
        for mapping in (
            REGION_SHAPES, REGION_LABEL_ANCHORS, REGION_MAP_LABELS,
            REGION_COLORS, REGION_MAP_META,
        ):
            self.assertEqual(set(mapping), EXPECTED_REGIONS)
        for region_id, polygon in REGION_SHAPES.items():
            self.assertGreaterEqual(len(polygon), 4, region_id)
            for x, y in polygon:
                self.assertGreaterEqual(x, 0.0)
                self.assertLessEqual(x, 100.0)
                self.assertGreaterEqual(y, 0.0)
                self.assertLessEqual(y, 100.0)

    def test_region_union_uses_exact_country_outline_and_shared_borders(self):
        edge_counts = Counter()
        for polygon in REGION_SHAPES.values():
            for index, point in enumerate(polygon):
                edge_counts[_edge(point, polygon[(index + 1) % len(polygon)])] += 1

        outline_edges = {
            _edge(point, COUNTRY_OUTLINE[(index + 1) % len(COUNTRY_OUTLINE)])
            for index, point in enumerate(COUNTRY_OUTLINE)
            if point != COUNTRY_OUTLINE[(index + 1) % len(COUNTRY_OUTLINE)]
        }
        self.assertEqual(
            {edge for edge, count in edge_counts.items() if count == 1},
            outline_edges,
        )
        self.assertTrue(all(count in (1, 2) for count in edge_counts.values()))

    def test_ceasefire_is_the_exact_vetrenka_orvena_boundary(self):
        vetrenka_edges = {
            _edge(point, REGION_SHAPES["vetrenka"][(index + 1)
                                                   % len(REGION_SHAPES["vetrenka"])])
            for index, point in enumerate(REGION_SHAPES["vetrenka"])
        }
        orvena_edges = {
            _edge(point, REGION_SHAPES["orvena"][(index + 1)
                                                 % len(REGION_SHAPES["orvena"])])
            for index, point in enumerate(REGION_SHAPES["orvena"])
        }
        shared = vetrenka_edges & orvena_edges
        ceasefire_edges = {
            _edge(point, CEASEFIRE_LINE[index + 1])
            for index, point in enumerate(CEASEFIRE_LINE[:-1])
        }
        self.assertEqual(ceasefire_edges, shared)

    def test_every_city_marker_lies_in_its_declared_region(self):
        for city_id, city in CITY_MARKERS.items():
            polygon = REGION_SHAPES[city["region_id"]]
            self.assertTrue(
                _contains(polygon, city["point"]),
                f"{city_id} at {city['point']} is outside {city['region_id']}",
            )

    def test_rivers_and_checkpoints_stay_inside_the_playable_country(self):
        for river_id, river in RIVERS.items():
            for point in river["points"]:
                self.assertTrue(
                    _contains(COUNTRY_OUTLINE, point),
                    f"{river_id} point {point} is outside Ardenia",
                )
        for checkpoint_id, checkpoint in CHECKPOINTS.items():
            polygon = REGION_SHAPES[checkpoint["region_id"]]
            self.assertTrue(
                _contains(polygon, checkpoint["point"]),
                f"{checkpoint_id} at {checkpoint['point']} is outside "
                f"{checkpoint['region_id']}",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
