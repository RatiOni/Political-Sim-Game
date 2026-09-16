"""Native content exporter - Task 1 of the Godot rebuild.

Reads the frozen Python content modules (content/*.py, content/lore/*.py) and
emits one JSON file per catalog under godot/data/native/, plus a
catalog_manifest.json index. This is the ONLY writer of godot/data/native/**.

This script never modifies the Python source; it only imports and reads it.
Python callables (event conditions/requires/appliers) cannot be serialized as
data, so they are exported as stable symbolic string ids (their function
name, without the leading underscore) - Task 2's native game systems will
implement the actual behaviour in GDScript against those ids.

Usage:
    python scripts/native_port/export_native_content.py --write
"""

import argparse
import json
import os
import sys
from dataclasses import fields, is_dataclass
from types import FunctionType

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

OUT_ROOT = os.path.join(REPO_ROOT, "godot", "data", "native")
SCHEMA_VERSION = 1


def to_jsonable(obj):
    if obj is None or isinstance(obj, (str, int, float, bool)):
        return obj
    if isinstance(obj, FunctionType):
        return obj.__name__.lstrip("_")
    if is_dataclass(obj) and not isinstance(obj, type):
        return {f.name: to_jsonable(getattr(obj, f.name)) for f in fields(obj)}
    if isinstance(obj, dict):
        return {str(k): to_jsonable(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple, set, frozenset)):
        items = [to_jsonable(v) for v in obj]
        if isinstance(obj, (set, frozenset)):
            items.sort(key=lambda v: json.dumps(v, sort_keys=True))
        return items
    raise TypeError("export_native_content: don't know how to serialize %r (%s)" % (obj, type(obj)))


def _write_json(rel_path, data):
    full_path = os.path.join(OUT_ROOT, rel_path)
    os.makedirs(os.path.dirname(full_path), exist_ok=True)
    with open(full_path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, indent=2, sort_keys=False, ensure_ascii=False)
        fh.write("\n")


def _id_count(data):
    if isinstance(data, list):
        return len(data)
    if isinstance(data, dict):
        list_members = [v for v in data.values() if isinstance(v, list)]
        if list_members:
            return sum(len(v) for v in list_members)
        return len(data)
    return 1


def export_countries(manifest_files, id_counts):
    from content import loader
    from content.lore import BLOCS, BLOC_PROFILES
    from models import roles
    from models.faction import Ideology

    def bloc_wings_for(faction_id):
        out = []
        for bloc in BLOCS:
            if bloc["parent_id"] != faction_id:
                continue
            profile = BLOC_PROFILES[bloc["id"]]
            out.append({
                "id": bloc["id"],
                "name": bloc["name"],
                "ideology": dict(profile["ideology"]),
                "strength": profile["strength"],
                "loyalty": profile["loyalty"],
                "kind": "bloc",
                "description": bloc["body"],
                "policy_biases": dict(profile["policy_biases"]),
            })
        return out

    for country_id in loader.available_country_ids():
        data = loader.load_country_data(country_id)
        factions = data.get("factions", [])
        for faction in factions:
            ideology = Ideology(economic=faction["ideology"]["economic"],
                                 social=faction["ideology"]["social"])
            faction["role"] = roles.classify(ideology)
            if data["id"] == "ardenia":
                blocs = bloc_wings_for(faction["id"])
                if blocs:
                    faction["wings"] = blocs

        rel_path = os.path.join("countries", country_id + ".json").replace(os.sep, "/")
        _write_json(rel_path, data)
        manifest_files.append(rel_path)
        id_counts[rel_path] = len(factions)


def export_catalogs(manifest_files, id_counts):
    from content.bills import bill_catalog
    from content.budget import BUDGET_ENVELOPES, BUDGET_ADJUSTMENTS
    from content.traits import all_traits
    from content.reforms import REFORM_OBJECTIVES, SIGNAL_LABELS
    from content.events import event_catalog, ARDENIA_ONLY_EVENTS
    from content.households import HOUSEHOLD_GROUPS, REGIONAL_HOUSEHOLD_SHARES
    from content.regions import (CONTROL_LABELS, ARDENIA_NATIONAL_SUPPORT_BASELINE,
                                  ARDENIA_REGION_PROFILES, REGIONAL_ISSUES,
                                  REGIONAL_PROGRAMS)
    from content.campaign_content import all_backgrounds, all_difficulties
    from content.dispatches import TEMPLATES, MARKERS
    from content.press import HEADLINES, LEADS, SAMPLE_FIELDS

    catalogs = {
        "bills.json": to_jsonable(bill_catalog()),
        "budget.json": {
            "envelopes": to_jsonable(BUDGET_ENVELOPES),
            "adjustments": to_jsonable(list(BUDGET_ADJUSTMENTS)),
        },
        "traits.json": to_jsonable(all_traits()),
        "reform_objectives.json": {
            "objectives": to_jsonable(REFORM_OBJECTIVES),
            "signal_labels": to_jsonable(SIGNAL_LABELS),
        },
        "events.json": {
            "events": to_jsonable(event_catalog()),
            "ardenia_only_events": to_jsonable(ARDENIA_ONLY_EVENTS),
        },
        "household_groups.json": {
            "groups": to_jsonable(HOUSEHOLD_GROUPS),
            "regional_shares": to_jsonable(REGIONAL_HOUSEHOLD_SHARES),
        },
        "regions_and_programs.json": {
            "control_labels": to_jsonable(CONTROL_LABELS),
            "national_support_baseline": to_jsonable(ARDENIA_NATIONAL_SUPPORT_BASELINE),
            "region_profiles": to_jsonable(ARDENIA_REGION_PROFILES),
            "regional_issues": to_jsonable(REGIONAL_ISSUES),
            "regional_programs": to_jsonable(REGIONAL_PROGRAMS),
        },
        "backgrounds.json": to_jsonable(all_backgrounds()),
        "difficulties.json": to_jsonable(all_difficulties()),
        "dispatch_pools.json": {
            "templates": to_jsonable(TEMPLATES),
            "markers": to_jsonable(MARKERS),
        },
        "press_templates.json": {
            "headlines": to_jsonable(HEADLINES),
            "leads": to_jsonable(LEADS),
            "sample_fields": to_jsonable(SAMPLE_FIELDS),
        },
    }

    for name, data in catalogs.items():
        rel_path = os.path.join("catalogs", name).replace(os.sep, "/")
        _write_json(rel_path, data)
        manifest_files.append(rel_path)
        id_counts[rel_path] = _id_count(data)


def export_lore(manifest_files, id_counts):
    from content.lore import timeline, geography, society, institutions, economy, parties, figures

    lore_files = {
        "timeline.json": {"timeline": to_jsonable(timeline.TIMELINE)},
        "geography.json": {
            "country_profile": to_jsonable(geography.COUNTRY_PROFILE),
            "kesla": to_jsonable(geography.KESLA),
            "ceasefire_line": to_jsonable(geography.CEASEFIRE_LINE),
            "regions": to_jsonable(geography.REGIONS),
            "cities": to_jsonable(geography.CITIES),
        },
        "society.json": {
            "peoples": to_jsonable(society.PEOPLES),
            "demography": to_jsonable(society.DEMOGRAPHY),
            "social_order": to_jsonable(society.SOCIAL_ORDER),
            "language_and_script": to_jsonable(society.LANGUAGE_AND_SCRIPT),
            "religion": to_jsonable(society.RELIGION),
        },
        "institutions.json": {
            "constitutional_order": to_jsonable(institutions.CONSTITUTIONAL_ORDER),
            "institutions": to_jsonable(institutions.INSTITUTIONS),
            "officeholders": to_jsonable(institutions.OFFICEHOLDERS),
            "law_and_power": to_jsonable(institutions.LAW_AND_POWER),
            "media_and_civil_society": to_jsonable(institutions.MEDIA_AND_CIVIL_SOCIETY),
        },
        "economy.json": {
            "economic_picture": to_jsonable(economy.ECONOMIC_PICTURE),
            "sectors": to_jsonable(economy.SECTORS),
            "kron": to_jsonable(economy.KRON),
            "energy": to_jsonable(economy.ENERGY),
            "foreign_obligations": to_jsonable(economy.FOREIGN_OBLIGATIONS),
            "present_day": to_jsonable(economy.PRESENT_DAY),
        },
        "parties.json": {
            "party_origins": to_jsonable(parties.PARTY_ORIGINS),
            "blocs": to_jsonable(parties.BLOCS),
            "bloc_profiles": to_jsonable(parties.BLOC_PROFILES),
        },
        "figures.json": {"figures": to_jsonable(figures.FIGURES)},
    }

    for name, data in lore_files.items():
        rel_path = os.path.join("lore", name).replace(os.sep, "/")
        _write_json(rel_path, data)
        manifest_files.append(rel_path)
        id_counts[rel_path] = _id_count(data)


def export_all():
    manifest_files = []
    id_counts = {}

    export_countries(manifest_files, id_counts)
    export_catalogs(manifest_files, id_counts)
    export_lore(manifest_files, id_counts)

    manifest_files.sort()
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "files": manifest_files,
        "id_counts": {k: id_counts[k] for k in manifest_files},
    }
    with open(os.path.join(OUT_ROOT, "catalog_manifest.json"), "w",
              encoding="utf-8", newline="\n") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=False, ensure_ascii=False)
        fh.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true",
                         help="write godot/data/native/**/*.json (the only supported mode)")
    args = parser.parse_args()
    if not args.write:
        print("Nothing to do without --write (this is the only writer of "
              "godot/data/native/**/*.json).", file=sys.stderr)
        return 1
    export_all()
    print("Exported native content to " + OUT_ROOT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
