"""Compare a native Godot snapshot against one frozen Python oracle fixture.

This is a development-only parity probe.  It compares parsed JSON values, not
source formatting, so the Godot emitter may use its own canonical serializer.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


NUMERIC_TOLERANCE = 1e-9


def _key_path(path: str, key: str) -> str:
    return "%s.%s" % (path, key) if key.isidentifier() else "%s[%r]" % (path, key)


def compare(expected: Any, actual: Any, path: str = "$") -> list[str]:
    """Return every parity mismatch between two parsed JSON values."""
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            return ["%s: expected object, got %s" % (path, type(actual).__name__)]
        mismatches: list[str] = []
        for key in sorted(expected):
            child_path = _key_path(path, key)
            if key not in actual:
                mismatches.append("%s: missing in native" % child_path)
            else:
                mismatches.extend(compare(expected[key], actual[key], child_path))
        for key in sorted(actual):
            if key not in expected:
                mismatches.append("%s: unexpected in native" % _key_path(path, key))
        return mismatches

    if isinstance(expected, list):
        if not isinstance(actual, list):
            return ["%s: expected array, got %s" % (path, type(actual).__name__)]
        mismatches = []
        if len(expected) != len(actual):
            mismatches.append("%s: expected length %d, got %d" % (path, len(expected), len(actual)))
        for index in range(min(len(expected), len(actual))):
            mismatches.extend(compare(expected[index], actual[index], "%s[%d]" % (path, index)))
        return mismatches

    # bool is an int subclass in Python, so it must be classified first.
    if isinstance(expected, bool) or isinstance(actual, bool):
        return [] if type(expected) is type(actual) and expected == actual else [
            "%s: expected %r (%s), got %r (%s)" % (
                path, expected, type(expected).__name__, actual, type(actual).__name__)
        ]

    if isinstance(expected, (int, float)) or isinstance(actual, (int, float)):
        if not isinstance(expected, (int, float)) or not isinstance(actual, (int, float)):
            return ["%s: expected %r (%s), got %r (%s)" % (
                path, expected, type(expected).__name__, actual, type(actual).__name__)]
        # Godot's JSON parser represents every JSON number as a float.  Integer
        # values remain exact, while non-integral values use the documented
        # tolerance; this retains JSON's number type without pretending Python
        # and GDScript expose the same runtime numeric classes.
        if isinstance(expected, int):
            return [] if actual == expected else ["%s: expected %r, got %r" % (path, expected, actual)]
        return [] if abs(expected - actual) <= NUMERIC_TOLERANCE else [
            "%s: expected %r, got %r" % (path, expected, actual)]

    if type(expected) is not type(actual) or expected != actual:
        return ["%s: expected %r (%s), got %r (%s)" % (
            path, expected, type(expected).__name__, actual, type(actual).__name__)]
    return []


def _load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError("%s: %s" % (path, error)) from error


def self_test() -> None:
    assert compare({"country": {"economy": {"gdp": 48000.0}}},
                   {"country": {"economy": {"gdp": 48000.0}}}) == []
    assert compare({"country": {"economy": {"gdp": 48000.0}}},
                   {"country": {"economy": {}}}) == [
        "$.country.economy.gdp: missing in native"]
    assert compare({"country": {"name": "Ardenia"}},
                   {"country": {"name": "Ardenian Republic"}}) == [
        "$.country.name: expected 'Ardenia' (str), got 'Ardenian Republic' (str)"]
    assert compare({"score": 0.2}, {"score": 0.2 + NUMERIC_TOLERANCE / 2}) == []
    assert compare({"score": 0.2}, {"score": 0.2 + NUMERIC_TOLERANCE * 2}) == [
        "$.score: expected 0.2, got 0.200000002"]
    assert compare({"seats": 100}, {"seats": 100.0}) == []
    assert compare({"enabled": True}, {"enabled": 1}) == [
        "$.enabled: expected True (bool), got 1 (int)"]
    assert compare({"country": {}}, {"country": []}) == [
        "$.country: expected object, got list"]
    assert compare({"regions": ["anera", "sela"]},
                   {"regions": ["sela", "anera", "zavost"]}) == [
        "$.regions: expected length 2, got 3",
        "$.regions[0]: expected 'anera' (str), got 'sela' (str)",
        "$.regions[1]: expected 'sela' (str), got 'anera' (str)"]
    assert compare({"ruling_faction_id": None}, {"ruling_faction_id": "ld"}) == [
        "$.ruling_faction_id: expected None (NoneType), got 'ld' (str)"]
    # Keep collecting after the first mismatch.
    assert compare({"a": 1, "b": 2}, {"a": 0, "c": 3}) == [
        "$.a: expected 1, got 0", "$.b: missing in native", "$.c: unexpected in native"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("oracle", nargs="?", type=Path)
    parser.add_argument("native", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        print("native snapshot comparator self-test: PASS")
        return 0
    if args.oracle is None or args.native is None:
        parser.error("oracle and native snapshot paths are required")

    try:
        mismatches = compare(_load(args.oracle), _load(args.native))
    except ValueError as error:
        print("ERROR", error)
        return 2
    if not mismatches:
        print("PARITY PASS", args.oracle, args.native)
        return 0
    print("PARITY FAIL: %d mismatch(es)" % len(mismatches))
    for mismatch in mismatches:
        print(mismatch)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
