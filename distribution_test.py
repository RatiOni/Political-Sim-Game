"""Focused checks for the downloadable Windows playtest build."""

import os
import tempfile
from pathlib import Path
from unittest.mock import patch

import app_paths
import version
from engine import persistence
from engine.campaign import default_config, generate_campaign


def check(name, fn):
    fn()
    print(f"PASS  {name}")


def source_and_packaged_paths_are_separate():
    assert app_paths.user_data_root(packaged=False, environ={}) == \
        app_paths.PROJECT_ROOT
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp).resolve()
        assert app_paths.user_data_root(
            packaged=True,
            environ={"ARDENIA_USER_DATA_DIR": str(base)},
        ) == base
        assert app_paths.saves_dir(
            packaged=True,
            environ={"ARDENIA_USER_DATA_DIR": str(base)},
        ) == base / "saves"
        assert app_paths.logs_dir(
            packaged=True,
            environ={"ARDENIA_USER_DATA_DIR": str(base)},
        ) == base / "logs"
        local = app_paths.user_data_root(
            packaged=True,
            environ={"LOCALAPPDATA": str(base)},
        )
        assert local == base / "Ardenia"
    try:
        app_paths.user_data_root(packaged=True, environ={})
    except RuntimeError as exc:
        assert "LOCALAPPDATA" in str(exc)
    else:
        raise AssertionError("packaged mode must reject an unavailable data root")
    with tempfile.TemporaryDirectory() as tmp:
        occupied = Path(tmp) / "not-a-directory"
        occupied.write_text("occupied", encoding="utf-8")
        try:
            app_paths.ensure_directory(occupied)
        except OSError:
            pass
        else:
            raise AssertionError("a file cannot be accepted as a data directory")


def resources_are_read_only_and_independent_of_user_data():
    with tempfile.TemporaryDirectory() as tmp:
        bundle = Path(tmp).resolve()
        assert app_paths.resource_root(
            packaged=True, bundle_root=bundle) == bundle
        assert app_paths.resource_path(
            "content/countries/ardenia.json",
            packaged=True,
            bundle_root=bundle,
        ) == bundle / "content" / "countries" / "ardenia.json"
        assert app_paths.resource_root(packaged=False) == app_paths.PROJECT_ROOT


def persistence_uses_runtime_directory_without_changing_schema():
    with tempfile.TemporaryDirectory() as tmp:
        with patch.dict(os.environ, {
                "ARDENIA_USER_DATA_DIR": str(Path(tmp).resolve())}):
            state = generate_campaign(default_config())
            path = Path(persistence.save_campaign(state, slot="package_path_test"))
            assert path.parent == Path(tmp).resolve() / "saves"
            assert persistence.save_exists("package_path_test")
            listed = persistence.list_saves()
            assert any(item["slot"] == "package_path_test" for item in listed)
            restored = persistence.load_campaign("package_path_test")
            assert persistence.serialize_state(restored) == \
                persistence.serialize_state(state)
            assert persistence.delete_save("package_path_test")
            assert not persistence.save_exists("package_path_test")


def version_controls_tag_archive_and_titles():
    assert version.APP_NAME == "Ardenia"
    assert version.VERSION == "0.1.0-playtest.1"
    assert version.WINDOWS_FILE_VERSION == (0, 1, 0, 1)
    assert version.TAG == "v0.1.0-playtest.1"
    assert version.ARCHIVE_FILENAME == "Ardenia-0.1.0-playtest.1-win64.zip"
    assert version.VERSION in version.window_title()
    assert version.window_title("Ardenia").startswith(
        "Ardenia — a political simulation")
    version.validate_tag(version.TAG)
    try:
        version.validate_tag("v0.1.0-playtest.2")
    except ValueError as exc:
        assert version.TAG in str(exc)
    else:
        raise AssertionError("a mismatched release tag must be rejected")


if __name__ == "__main__":
    checks = [
        ("source and packaged user-data paths are separate",
         source_and_packaged_paths_are_separate),
        ("bundled resources are independent of writable user data",
         resources_are_read_only_and_independent_of_user_data),
        ("persistence resolves its save directory at operation time",
         persistence_uses_runtime_directory_without_changing_schema),
        ("one version controls every public build identity",
         version_controls_tag_archive_and_titles),
    ]
    for label, test in checks:
        check(label, test)
    print(f"ALL {len(checks)} DISTRIBUTION CHECKS PASSED")
