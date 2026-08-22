"""Focused checks for the downloadable Windows playtest build."""

from datetime import datetime
import os
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

import app_paths
import gui
import packaged_verify
import runtime_logging
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


def crash_logs_are_local_versioned_and_readable():
    with tempfile.TemporaryDirectory() as tmp:
        with patch.dict(os.environ, {
                "ARDENIA_USER_DATA_DIR": str(Path(tmp).resolve())}):
            try:
                raise RuntimeError("packaged failure marker")
            except RuntimeError as exc:
                path = runtime_logging.write_crash_log(
                    type(exc), exc, exc.__traceback__,
                    when=datetime(2026, 8, 22, 12, 34, 56))
            assert path.name == "crash-20260822-123456.txt"
            text = path.read_text(encoding="utf-8")
            assert "0.1.0-playtest.1" in text
            assert "RuntimeError: packaged failure marker" in text
            assert str(path).startswith(str(Path(tmp).resolve()))


def packaged_verifier_uses_isolated_saves_and_required_files():
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PySide6.QtWidgets import QApplication
    app = QApplication.instance() or QApplication([])
    with tempfile.TemporaryDirectory() as data_tmp, \
            tempfile.TemporaryDirectory() as dist_tmp:
        dist = Path(dist_tmp)
        (dist / "PLAYTEST_README.txt").write_text("test", encoding="utf-8")
        (dist / "FEEDBACK_TEMPLATE.txt").write_text("test", encoding="utf-8")
        with patch.dict(os.environ, {
                "ARDENIA_USER_DATA_DIR": str(Path(data_tmp).resolve())}):
            report = packaged_verify.verify_build(app, dist)
            assert "government campaign" in report
            assert "opposition campaign" in report
            assert not persistence.save_exists("_package_verify_government")
            assert not persistence.save_exists("_package_verify_opposition")
            assert not list((Path(data_tmp) / "logs").glob("verification-*.txt"))
        (dist / "FEEDBACK_TEMPLATE.txt").unlink()
        try:
            packaged_verify.verify_build(app, dist)
        except FileNotFoundError as exc:
            assert "FEEDBACK_TEMPLATE.txt" in str(exc)
        else:
            raise AssertionError("missing tester files must fail verification")


def packaged_verifier_rejects_invalid_restored_campaign():
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PySide6.QtWidgets import QApplication
    app = QApplication.instance() or QApplication([])
    with tempfile.TemporaryDirectory() as data_tmp, \
            tempfile.TemporaryDirectory() as dist_tmp:
        dist = Path(dist_tmp)
        (dist / "PLAYTEST_README.txt").write_text("test", encoding="utf-8")
        (dist / "FEEDBACK_TEMPLATE.txt").write_text("test", encoding="utf-8")
        invalid = generate_campaign(default_config())
        invalid.country.id = "krasova"
        with patch.dict(os.environ, {
                "ARDENIA_USER_DATA_DIR": str(Path(data_tmp).resolve())}), \
                patch.object(packaged_verify.persistence, "load_campaign",
                             return_value=invalid):
            try:
                packaged_verify.verify_build(app, dist)
            except RuntimeError as exc:
                assert "restored campaign" in str(exc)
            else:
                raise AssertionError("invalid restored campaign must fail verification")
            assert not persistence.save_exists("_package_verify_government")
            assert not persistence.save_exists("_package_verify_opposition")


def fatal_hook_reports_when_log_creation_fails():
    original = sys.excepthook
    try:
        with patch.object(runtime_logging, "write_crash_log",
                          side_effect=OSError("read-only data directory")), \
                patch.object(gui.QMessageBox, "critical") as critical:
            gui.install_exception_hook()
            try:
                raise RuntimeError("fatal marker")
            except RuntimeError as exc:
                sys.excepthook(type(exc), exc, exc.__traceback__)
            message = critical.call_args.args[2]
            assert "could not be written" in message
            assert "read-only data directory" in message
    finally:
        sys.excepthook = original


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
        ("crash logs are local, versioned and readable",
         crash_logs_are_local_versioned_and_readable),
        ("packaged verification isolates temporary saves and files",
         packaged_verifier_uses_isolated_saves_and_required_files),
        ("packaged verification rejects invalid restored campaigns",
         packaged_verifier_rejects_invalid_restored_campaign),
        ("fatal hook reports log failures", fatal_hook_reports_when_log_creation_fails),
    ]
    for label, test in checks:
        check(label, test)
    print(f"ALL {len(checks)} DISTRIBUTION CHECKS PASSED")
