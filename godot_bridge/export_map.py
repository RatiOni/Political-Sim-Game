"""Export Ardenia's authored map geometry for the Godot client."""

import json
from pathlib import Path

from ui.ardenia_map_geometry import (
    BORDER_LABELS,
    CITY_MARKERS,
    COUNTRY_OUTLINE,
    NEIGHBOR_LAND_SHAPES,
    PORTS,
    ROUTES,
)
from ui.ardenia_region_geometry import (
    CEASEFIRE_LINE,
    REGION_LABEL_ANCHORS,
    REGION_MAP_LABELS,
    REGION_SHAPES,
)


def _json_value(value):
    if isinstance(value, tuple):
        return [_json_value(item) for item in value]
    if isinstance(value, list):
        return [_json_value(item) for item in value]
    if isinstance(value, dict):
        return {key: _json_value(item) for key, item in value.items()}
    return value


def _records(items):
    return [dict(id=item_id, **_json_value(value))
            for item_id, value in sorted(items.items())]


def export_map() -> dict:
    """Return the JSON-safe, normalized map contract used by Godot."""
    return {
        "outline": _json_value(COUNTRY_OUTLINE),
        "regions": [
            {"id": region_id, "points": _json_value(REGION_SHAPES[region_id])}
            for region_id in sorted(REGION_SHAPES)
        ],
        "labels": [
            {"id": region_id, "name": REGION_MAP_LABELS[region_id],
             "point": _json_value(REGION_LABEL_ANCHORS[region_id])}
            for region_id in sorted(REGION_SHAPES)
        ] + _json_value(BORDER_LABELS),
        "cities": _records(CITY_MARKERS),
        "routes": sorted((_json_value(route) for route in ROUTES),
                         key=lambda route: route["id"]),
        "ports": _records(PORTS),
        "ceasefire_line": _json_value(CEASEFIRE_LINE),
        "neighbors": [
            {"id": neighbor_id, "points": _json_value(points)}
            for neighbor_id, points in sorted(NEIGHBOR_LAND_SHAPES.items())
        ],
    }


def main() -> None:
    output = Path(__file__).resolve().parent.parent / "godot" / "data" / "ardenia_map.json"
    with output.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write(json.dumps(export_map(), indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
