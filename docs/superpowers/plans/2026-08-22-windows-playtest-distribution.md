# Windows Playtest Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a reproducible Windows 10/11 Ardenia playtest ZIP that runs without Python, preserves packaged saves in local application data, records local crash logs, and carries neutral asynchronous-test instructions.

**Architecture:** Keep packaging concerns outside the simulation: root-level helpers own version, paths, logging, and packaged verification; `engine/persistence.py` asks the path helper only when it performs file operations. A committed PyInstaller one-folder definition and safe PowerShell orchestrator produce and verify the artifact, while a tag-gated GitHub Actions workflow publishes it only after source, GUI, package, and version checks pass.

**Tech Stack:** Python 3.14.6, PySide6 6.11.1, PyInstaller 6.16.0, PowerShell 7/Windows PowerShell, GitHub Actions on `windows-latest`, existing assert-based smoke tests.

**Spec:** `docs/superpowers/specs/2026-08-22-windows-playtest-distribution-design.md`

## Global Constraints

- Target only 64-bit Windows 10 and Windows 11 for this milestone.
- Produce a PyInstaller one-folder, windowed build inside a versioned ZIP; do not create a one-file executable or installer.
- Initial version is exactly `0.1.0-playtest.1`; the matching release tag is exactly `v0.1.0-playtest.1`.
- Source mode keeps repository-local `saves/`; packaged mode uses `%LOCALAPPDATA%\Ardenia\saves` and `%LOCALAPPDATA%\Ardenia\logs`.
- `ARDENIA_USER_DATA_DIR` is the sole automated-test/package-verification override for writable user data.
- Do not change `SAVE_VERSION`, serialized fields, simulation mechanics, content, balance, pacing, dashboard hierarchy, or reform behavior.
- No telemetry, account, network upload, updater, installer, code-signing secret, private return-channel address, recording, completed feedback form, or participant data enters the repository or artifact.
- The first build is unsigned; release notes and tester instructions must say so honestly and publish a SHA-256 checksum.
- Public publication is tag-gated. Manual workflow dispatch may produce a private workflow artifact but must never publish a GitHub Release.
- A failed source test, GUI test, build, packaged verification, or tag/version check publishes nothing.
- Existing tests run with `PYTHONUTF8=1` on Windows.
- Use the shared development interpreter at `D:\Political Sim Game\.venv\Scripts\python.exe` from isolated worktrees until the committed dependency files can reproduce the environment.
- Begin execution in a new isolated worktree/branch created from commit `9c42d8e`, not on `main` and not by mutating the completed evidence-first worktree.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `version.py` | One authoritative human version, Windows file version, tag, archive, and title helpers. |
| `app_paths.py` | Source/packaged resource roots plus writable user-data, save, and log paths. |
| `runtime_logging.py` | UTF-8 diagnostic/crash log creation with no transport or UI dependency. |
| `packaged_verify.py` | Deterministic packaged self-check used by the executable and build pipeline. |
| `engine/persistence.py` | Existing save serialization; only its directory lookup becomes runtime-path aware. |
| `gui.py` | Normal GUI entry plus exception-hook and `--verify-build` routing. |
| `ui/menu.py`, `ui/app.py` | Display the authoritative playtest version in top-level window titles. |
| `distribution_test.py` | Fast assert-based tests for paths, version, logging, packet, build definition, and workflow contracts. |
| `ui_smoke_test.py` | Real Qt assertions for versioned titles and unchanged campaign behavior. |
| `requirements.txt` | Pinned runtime dependency. |
| `requirements-build.txt` | Pinned build dependency layered on the runtime dependency. |
| `packaging/ardenia.spec` | One-folder PyInstaller graph, data files, metadata input, and output name. |
| `packaging/render_windows_version.py` | Renders PyInstaller Windows metadata from `version.py`. |
| `scripts/run_ui_smoke_offscreen.py` | Stable modal-patched GUI smoke entry for local and CI use. |
| `scripts/build_windows.ps1` | Safe build, packet copy, packaged verification, ZIP, and checksum orchestration. |
| `distribution/PLAYTEST_README.txt` | Neutral tester launch, recording, SmartScreen, and return instructions. |
| `distribution/FEEDBACK_TEMPLATE.txt` | Plain-text post-session evidence form with no identifying fields. |
| `.github/workflows/windows-playtest-release.yml` | Manual verification artifact and tag-gated public release. |
| `docs/playtests/WINDOWS_RELEASE_CHECKLIST.md` | Owner-facing clean-machine, integration, tag, and release validation checklist. |
| `AGENTS.md`, `CLAUDE.md` | Developer commands, path rules, and release invariants. |

---

### Task 1: Runtime paths and packaged-save isolation

**Files:**
- Create: `app_paths.py`
- Create: `distribution_test.py`
- Modify: `engine/persistence.py:1-41,532-588`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `is_packaged() -> bool`
- Produces: `resource_root(*, packaged: bool | None = None, bundle_root: Path | None = None) -> Path`
- Produces: `resource_path(relative: str | Path, **kwargs) -> Path`
- Produces: `user_data_root(*, packaged: bool | None = None, environ: Mapping[str, str] | None = None) -> Path`
- Produces: `saves_dir(**kwargs) -> Path`, `logs_dir(**kwargs) -> Path`, `ensure_directory(path: Path) -> Path`
- Preserves: `persistence.save_campaign/load_campaign/list_saves/delete_save/save_exists` signatures and JSON shapes.

- [ ] **Step 1: Write failing path and persistence tests**

Create `distribution_test.py` with the focused project-style harness and these initial checks:

```python
"""Focused checks for the downloadable Windows playtest build."""

import os
import tempfile
from pathlib import Path
from unittest.mock import patch

import app_paths
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


if __name__ == "__main__":
    checks = [
        ("source and packaged user-data paths are separate",
         source_and_packaged_paths_are_separate),
        ("bundled resources are independent of writable user data",
         resources_are_read_only_and_independent_of_user_data),
        ("persistence resolves its save directory at operation time",
         persistence_uses_runtime_directory_without_changing_schema),
    ]
    for label, test in checks:
        check(label, test)
    print(f"ALL {len(checks)} DISTRIBUTION CHECKS PASSED")
```

- [ ] **Step 2: Run the focused test and confirm the intended failure**

Run:

```powershell
& "D:\Political Sim Game\.venv\Scripts\python.exe" distribution_test.py
```

Expected: non-zero with `ModuleNotFoundError: No module named 'app_paths'`.

- [ ] **Step 3: Implement `app_paths.py`**

Create the complete pure path helper:

```python
"""Read-only bundle paths and writable Ardenia user-data paths."""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Mapping


PROJECT_ROOT = Path(__file__).resolve().parent
USER_DATA_ENV = "ARDENIA_USER_DATA_DIR"


def is_packaged() -> bool:
    return bool(getattr(sys, "frozen", False))


def resource_root(*, packaged: bool | None = None,
                  bundle_root: Path | None = None) -> Path:
    packaged = is_packaged() if packaged is None else packaged
    if not packaged:
        return PROJECT_ROOT
    root = bundle_root if bundle_root is not None else \
        Path(getattr(sys, "_MEIPASS"))
    return Path(root).resolve()


def resource_path(relative: str | Path, **kwargs) -> Path:
    return resource_root(**kwargs) / Path(relative)


def user_data_root(*, packaged: bool | None = None,
                   environ: Mapping[str, str] | None = None) -> Path:
    env = os.environ if environ is None else environ
    override = env.get(USER_DATA_ENV, "").strip()
    if override:
        return Path(override).expanduser().resolve()
    packaged = is_packaged() if packaged is None else packaged
    if not packaged:
        return PROJECT_ROOT
    local = env.get("LOCALAPPDATA", "").strip()
    if not local:
        raise RuntimeError("LOCALAPPDATA is unavailable; Ardenia cannot store saves.")
    return (Path(local).expanduser().resolve() / "Ardenia")


def saves_dir(**kwargs) -> Path:
    return user_data_root(**kwargs) / "saves"


def logs_dir(**kwargs) -> Path:
    return user_data_root(**kwargs) / "logs"


def ensure_directory(path: Path) -> Path:
    path = Path(path).resolve()
    path.mkdir(parents=True, exist_ok=True)
    if not path.is_dir():
        raise RuntimeError(f"Ardenia could not create data directory: {path}")
    return path
```

- [ ] **Step 4: Route persistence file operations through `app_paths`**

In `engine/persistence.py`, import `app_paths`, remove `_SAVES_DIR`, and replace the file-operation helpers with runtime lookup while leaving serialization untouched:

```python
import app_paths


def _saves_dir():
    return app_paths.saves_dir()


def _ensure_saves_dir():
    return app_paths.ensure_directory(_saves_dir())


def _slot_path(slot: str) -> str:
    safe = "".join(c for c in slot
                   if c.isalnum() or c in ("-", "_")).strip() or "save"
    return str(_saves_dir() / f"{safe}.json")
```

Replace `list_saves()` with the Path-based equivalent while preserving its public shape and corrupt-save behavior:

```python
def list_saves() -> list:
    """Return [{slot, label, date, country, leader}] for the load screen."""
    saves_dir = _saves_dir()
    if not saves_dir.is_dir():
        return []
    out = []
    for path in sorted(saves_dir.iterdir(), key=lambda item: item.name):
        if path.suffix != ".json":
            continue
        slot = path.stem
        try:
            with path.open("r", encoding="utf-8") as fh:
                data = json.load(fh)
            out.append({
                "slot": slot,
                "label": data.get("_label", slot),
                "country": data.get("country", {}).get("name", "?"),
                "leader": data.get("player", {}).get("name", "?"),
                "date": f"{data.get('year','?')}-{data.get('month','?'):0>2}",
                "save_version": data.get("save_version", 0),
            })
        except (json.JSONDecodeError, KeyError, OSError):
            continue
    return out
```

Add `logs/` to `.gitignore` beside `saves/`.

- [ ] **Step 5: Run focused and persistence regression checks**

Run:

```powershell
$env:PYTHONUTF8 = "1"
& "D:\Political Sim Game\.venv\Scripts\python.exe" distribution_test.py
& "D:\Political Sim Game\.venv\Scripts\python.exe" smoke_test.py
```

Expected: all distribution checks pass; `smoke_test.py` exits 0 with no `FAIL` output.

- [ ] **Step 6: Commit Task 1**

```powershell
git add app_paths.py distribution_test.py engine/persistence.py .gitignore
git diff --cached --check
git commit -m "feat: isolate packaged Ardenia user data"
```

---

### Task 2: Authoritative version and visible build identity

**Files:**
- Create: `version.py`
- Modify: `distribution_test.py`
- Modify: `ui/menu.py:18-55`
- Modify: `ui/app.py:7-52,470-475`
- Modify: `ui_smoke_test.py:30-55`

**Interfaces:**
- Produces constants: `APP_NAME`, `VERSION`, `WINDOWS_FILE_VERSION`, `TAG`, `ARCHIVE_FILENAME`
- Produces: `window_title(country_name: str | None = None) -> str`
- Produces: `validate_tag(tag: str) -> None`

- [ ] **Step 1: Add failing version-contract tests**

Add these imports and check to `distribution_test.py`:

```python
import version


def version_controls_tag_archive_and_titles():
    assert version.APP_NAME == "Ardenia"
    assert version.VERSION == "0.1.0-playtest.1"
    assert version.WINDOWS_FILE_VERSION == (0, 1, 0, 1)
    assert version.TAG == "v0.1.0-playtest.1"
    assert version.ARCHIVE_FILENAME == \
        "Ardenia-0.1.0-playtest.1-win64.zip"
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
```

Append it to the `checks` list with label `one version controls every public build identity`.

- [ ] **Step 2: Run and confirm failure**

Run `distribution_test.py` with the shared interpreter.

Expected: non-zero with `ModuleNotFoundError: No module named 'version'`.

- [ ] **Step 3: Implement `version.py`**

```python
"""Authoritative public build identity for Ardenia."""

APP_NAME = "Ardenia"
VERSION = "0.1.0-playtest.1"
WINDOWS_FILE_VERSION = (0, 1, 0, 1)
TAG = f"v{VERSION}"
ARCHIVE_FILENAME = f"{APP_NAME}-{VERSION}-win64.zip"


def window_title(country_name=None):
    subject = country_name or APP_NAME
    return f"{subject} — a political simulation — {VERSION}"


def validate_tag(tag):
    if tag != TAG:
        raise ValueError(f"release tag {tag!r} does not match {TAG!r}")
```

- [ ] **Step 4: Put the version in real Qt title bars**

Import `window_title` in `ui/menu.py`, call `self.setWindowTitle(window_title())` in `RootController.__init__`, and replace both `MainWindow` title assignments in `ui/app.py` with:

```python
self.setWindowTitle(window_title(self.state.country.name))
```

Update `ui_smoke_test.py` so the existing MainWindow and RootController construction checks assert `VERSION` appears in each top-level title. Use real objects rather than checking source text.

- [ ] **Step 5: Run focused and real-GUI checks**

Run:

```powershell
$env:QT_QPA_PLATFORM = "offscreen"
$env:PYTHONUTF8 = "1"
& "D:\Political Sim Game\.venv\Scripts\python.exe" distribution_test.py
& "D:\Political Sim Game\.venv\Scripts\python.exe" -c "from PySide6.QtWidgets import QDialog,QMessageBox; QDialog.exec=lambda self,*a,**k:0; QMessageBox.exec=lambda self,*a,**k:0; QMessageBox.information=lambda *a,**k:0; import ui_smoke_test; ui_smoke_test.main()"
```

Expected: distribution checks pass and all UI smoke checks pass with zero skips.

- [ ] **Step 6: Commit Task 2**

```powershell
git add version.py distribution_test.py ui/menu.py ui/app.py ui_smoke_test.py
git diff --cached --check
git commit -m "feat: expose authoritative playtest version"
```

---

### Task 3: Local crash logs and packaged self-verification

**Files:**
- Create: `runtime_logging.py`
- Create: `packaged_verify.py`
- Modify: `gui.py`
- Modify: `distribution_test.py`

**Interfaces:**
- Produces: `write_log(prefix: str, body: str, *, when: datetime | None = None) -> Path`
- Produces: `write_crash_log(exc_type, exc_value, traceback_obj, *, when: datetime | None = None) -> Path`
- Produces: `verify_build(app: QApplication, distribution_root: Path | None = None) -> list[str]`
- Produces: `run_verify_build(app: QApplication) -> int`
- Produces: `gui.install_exception_hook() -> None`
- Changes: `gui.main(argv: list[str] | None = None) -> int`

- [ ] **Step 1: Add failing diagnostic and verification tests**

Add imports and checks to `distribution_test.py`:

```python
from datetime import datetime
import sys

import gui
import packaged_verify
import runtime_logging


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
```

Append all three functions to `checks`.

- [ ] **Step 2: Run and confirm failure**

Run `distribution_test.py`.

Expected: non-zero with missing `packaged_verify` or `runtime_logging`.

- [ ] **Step 3: Implement pure local logging**

Create `runtime_logging.py`:

```python
"""Local diagnostic logs; this module performs no network operations."""

from datetime import datetime
import platform
import traceback

import app_paths
from version import VERSION


def write_log(prefix, body, *, when=None):
    when = when or datetime.now()
    folder = app_paths.ensure_directory(app_paths.logs_dir())
    path = folder / f"{prefix}-{when:%Y%m%d-%H%M%S}.txt"
    path.write_text(body, encoding="utf-8")
    return path


def write_crash_log(exc_type, exc_value, traceback_obj, *, when=None):
    body = "\n".join([
        f"Ardenia version: {VERSION}",
        f"Operating system: {platform.platform()}",
        f"Python runtime: {platform.python_version()}",
        "",
        "".join(traceback.format_exception(
            exc_type, exc_value, traceback_obj)).rstrip(),
        "",
    ])
    return write_log("crash", body, when=when)
```

- [ ] **Step 4: Implement deterministic packaged verification**

Create `packaged_verify.py` with a side-effect-clean verification sequence. Use `try/finally` to delete both temporary save slots and the verification log even after an assertion fails:

```python
from pathlib import Path
import sys
import traceback

import app_paths
import runtime_logging
from content.loader import build_state_for
from engine import persistence
from engine.campaign import CampaignConfig, generate_campaign
from ui.menu import RootController


REQUIRED_TESTER_FILES = ("PLAYTEST_README.txt", "FEEDBACK_TEMPLATE.txt")
VERIFY_SLOTS = ("_package_verify_government", "_package_verify_opposition")


def verify_build(app, distribution_root=None):
    root = Path(distribution_root or Path(sys.executable).resolve().parent)
    for name in REQUIRED_TESTER_FILES:
        if not (root / name).is_file():
            raise FileNotFoundError(f"packaged Ardenia is missing {name}")
    country_json = app_paths.resource_path("content/countries/ardenia.json")
    if not country_json.is_file():
        raise FileNotFoundError(f"packaged Ardenia is missing {country_json}")

    report = []
    marker = None
    try:
        RootController()
        app.processEvents()
        foreign = build_state_for("krasova")
        assert foreign.country.id == "krasova"
        for role, slot in zip(("government", "opposition"), VERIFY_SLOTS):
            state = generate_campaign(CampaignConfig(
                country_id="ardenia", opening_role=role,
                background_id="none", seed=220826))
            persistence.save_campaign(state, slot=slot)
            restored = persistence.load_campaign(slot)
            assert restored.country.id == "ardenia"
            assert restored.player.in_government == state.player.in_government
            report.append(f"{role} campaign")
        marker = runtime_logging.write_log(
            "verification", "Ardenia packaged verification\n")
        assert marker.read_text(encoding="utf-8").startswith("Ardenia")
        report.append("resources, saves and logs")
        return report
    finally:
        for slot in VERIFY_SLOTS:
            persistence.delete_save(slot)
        if marker is not None and marker.exists():
            marker.unlink()


def run_verify_build(app):
    try:
        verify_build(app)
        return 0
    except Exception:
        try:
            runtime_logging.write_log(
                "verification-failed", traceback.format_exc())
        finally:
            return 1
```

- [ ] **Step 5: Route GUI startup and fatal errors**

Refactor `gui.py` so `main()` returns an exit code and accepts an optional argument list. Install the hook only for normal GUI operation; verification catches and reports its own failures:

```python
from version import APP_NAME


def install_exception_hook():
    def handle(exc_type, exc_value, traceback_obj):
        try:
            path = runtime_logging.write_crash_log(
                exc_type, exc_value, traceback_obj)
            detail = f"A crash log was written to:\n{path}"
        except Exception as log_error:
            detail = f"The crash log could not be written:\n{log_error}"
        QMessageBox.critical(
            None, f"{APP_NAME} stopped unexpectedly",
            f"Ardenia encountered an unexpected error.\n\n{detail}")
    sys.excepthook = handle


def main(argv=None):
    argv = list(sys.argv if argv is None else argv)
    verifying = "--verify-build" in argv
    qt_argv = [item for item in argv if item != "--verify-build"]
    app = QApplication(qt_argv)
    app.setStyleSheet(theme.stylesheet())
    if verifying:
        return packaged_verify.run_verify_build(app)
    install_exception_hook()
    controller = AppController()
    controller.show_menu()
    app._controller = controller
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
```

Import `QMessageBox`, `packaged_verify`, and `runtime_logging` explicitly. Do not leave the old nested `sys.exit(app.exec())` inside `main()`.

- [ ] **Step 6: Run focused, GUI, and full regression checks**

Run:

```powershell
$env:PYTHONUTF8 = "1"
& "D:\Political Sim Game\.venv\Scripts\python.exe" distribution_test.py
$env:QT_QPA_PLATFORM = "offscreen"
& "D:\Political Sim Game\.venv\Scripts\python.exe" -c "from PySide6.QtWidgets import QDialog,QMessageBox; QDialog.exec=lambda self,*a,**k:0; QMessageBox.exec=lambda self,*a,**k:0; QMessageBox.information=lambda *a,**k:0; QMessageBox.warning=lambda *a,**k:0; QMessageBox.critical=lambda *a,**k:0; import ui_smoke_test; ui_smoke_test.main()"
& "D:\Political Sim Game\.venv\Scripts\python.exe" smoke_test.py
```

Expected: all exit 0. Confirm `git status --short` shows no files under the temporary data directories and no committed crash logs.

- [ ] **Step 7: Commit Task 3**

```powershell
git add runtime_logging.py packaged_verify.py gui.py distribution_test.py
git diff --cached --check
git commit -m "feat: verify and diagnose packaged builds"
```

---

### Task 4: Tester packet and reproducible local Windows build

**Files:**
- Create: `requirements.txt`
- Create: `requirements-build.txt`
- Create: `packaging/ardenia.spec`
- Create: `packaging/render_windows_version.py`
- Create: `scripts/run_ui_smoke_offscreen.py`
- Create: `scripts/build_windows.ps1`
- Create: `distribution/PLAYTEST_README.txt`
- Create: `distribution/FEEDBACK_TEMPLATE.txt`
- Modify: `distribution_test.py`

**Interfaces:**
- Consumes: `version.VERSION`, `version.WINDOWS_FILE_VERSION`, `version.ARCHIVE_FILENAME`
- Consumes: `Ardenia.exe --verify-build`, `ARDENIA_USER_DATA_DIR`
- Produces: `dist/Ardenia/Ardenia.exe`
- Produces: `dist/Ardenia-0.1.0-playtest.1-win64.zip`
- Produces: `dist/Ardenia-0.1.0-playtest.1-win64.zip.sha256`

- [ ] **Step 1: Add failing artifact-definition and tester-neutrality tests**

Add a repository-root constant and these checks to `distribution_test.py`:

```python
PROJECT_ROOT = Path(__file__).resolve().parent


def build_definition_is_pinned_and_one_folder():
    assert (PROJECT_ROOT / "requirements.txt").read_text(
        encoding="utf-8").strip() == "PySide6==6.11.1"
    build_requirements = (PROJECT_ROOT / "requirements-build.txt").read_text(
        encoding="utf-8")
    assert "-r requirements.txt" in build_requirements
    assert "PyInstaller==6.16.0" in build_requirements
    spec = (PROJECT_ROOT / "packaging/ardenia.spec").read_text(
        encoding="utf-8")
    assert "COLLECT(" in spec and 'name="Ardenia"' in spec
    assert "console=False" in spec
    assert "content/countries" in spec
    assert "--onefile" not in spec
    script = (PROJECT_ROOT / "scripts/build_windows.ps1").read_text(
        encoding="utf-8")
    assert "--verify-build" in script
    assert "Get-FileHash" in script
    assert "ARDENIA_USER_DATA_DIR" in script


def public_packet_is_neutral_private_and_versioned():
    guide = (PROJECT_ROOT / "distribution/PLAYTEST_README.txt").read_text(
        encoding="utf-8")
    form = (PROJECT_ROOT / "distribution/FEEDBACK_TEMPLATE.txt").read_text(
        encoding="utf-8")
    lower = (guide + form).lower()
    for forbidden in ("regional inequality", "purchasing power",
                      "suzerain", "paradox", "correct choice"):
        assert forbidden not in lower
    for required in ("0.1.0-playtest.1", "45 minutes", "screen recording",
                     "webcam", "microphone", "private channel", "smartscreen"):
        assert required in lower
    for field in ("your role", "your goal", "first meaningful action",
                  "opponent", "tradeoff", "consequence",
                  "passage of time", "wanted to do"):
        assert field in form.lower()
    assert "email address:" not in form.lower()
    assert "full name:" not in form.lower()
```

Append both checks.

- [ ] **Step 2: Run and confirm missing-file failure**

Run `distribution_test.py`.

Expected: non-zero on the first missing requirements or packaging file.

- [ ] **Step 3: Add pinned dependencies and Windows metadata renderer**

Create `requirements.txt`:

```text
PySide6==6.11.1
```

Create `requirements-build.txt`:

```text
-r requirements.txt
PyInstaller==6.16.0
```

Create `packaging/render_windows_version.py`:

```python
"""Render PyInstaller Windows metadata from Ardenia's version module."""

from pathlib import Path
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPOSITORY_ROOT))

from PyInstaller.utils.win32.versioninfo import (
    FixedFileInfo, StringFileInfo, StringStruct, StringTable,
    VarFileInfo, VarStruct, VSVersionInfo,
)
from version import VERSION, WINDOWS_FILE_VERSION


def render(output_path):
    info = VSVersionInfo(
        ffi=FixedFileInfo(
            filevers=WINDOWS_FILE_VERSION,
            prodvers=WINDOWS_FILE_VERSION,
            mask=0x3F,
            flags=0x0,
            OS=0x40004,
            fileType=0x1,
            subtype=0x0,
            date=(0, 0),
        ),
        kids=[
            StringFileInfo([
                StringTable("040904B0", [
                    StringStruct("CompanyName", "Ardenia Project"),
                    StringStruct("FileDescription",
                                 "Ardenia political simulation playtest"),
                    StringStruct("FileVersion", VERSION),
                    StringStruct("InternalName", "Ardenia"),
                    StringStruct("OriginalFilename", "Ardenia.exe"),
                    StringStruct("ProductName", "Ardenia"),
                    StringStruct("ProductVersion", VERSION),
                ])
            ]),
            VarFileInfo([VarStruct("Translation", [1033, 1200])]),
        ],
    )
    path = Path(output_path).resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(str(info), encoding="utf-8")
    return path


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: render_windows_version.py OUTPUT_PATH")
    render(sys.argv[1])
```

The string-table language/codepage pair is English/Unicode. Do not duplicate the version literal inside this renderer.

- [ ] **Step 4: Add the one-folder PyInstaller specification**

Create `packaging/ardenia.spec` with repository-root `pathex`, `gui.py` as the only entry script, the rendered `build/windows-version.txt`, and the country JSON directory as data:

```python
from pathlib import Path

project_root = Path(SPECPATH).parent

a = Analysis(
    [str(project_root / "gui.py")],
    pathex=[str(project_root)],
    binaries=[],
    datas=[(str(project_root / "content" / "countries"), "content/countries")],
    hiddenimports=[],
    hookspath=[],
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="Ardenia",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    version=str(project_root / "build" / "windows-version.txt"),
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name="Ardenia",
)
```

Do not add speculative hidden imports. Let the packaged self-check expose a proven missing import before adding one.

- [ ] **Step 5: Add the stable offscreen GUI runner**

Create `scripts/run_ui_smoke_offscreen.py`:

```python
import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QDialog, QMessageBox

QDialog.exec = lambda self, *args, **kwargs: 0
QMessageBox.exec = lambda self, *args, **kwargs: 0
QMessageBox.information = lambda *args, **kwargs: 0
QMessageBox.warning = lambda *args, **kwargs: 0
QMessageBox.critical = lambda *args, **kwargs: 0

import ui_smoke_test

ui_smoke_test.main()
```

- [ ] **Step 6: Write the neutral tester guide and form**

Create `distribution/PLAYTEST_README.txt` with this complete content:

```text
THIS BUILD
Ardenia 0.1.0-playtest.1 is an unsigned Windows 10/11 early playtest.
Download it only from https://github.com/RatiOni/Political-Sim-Game/releases.
The release page publishes a SHA-256 checksum for the ZIP.

DOWNLOAD AND START
Extract the complete ZIP before opening Ardenia.exe. Keep Ardenia.exe beside
the bundled runtime files. Python, Git, and installation are not required.

THE 45-MINUTE SESSION
Start a screen recording before launching Ardenia. A webcam is not required
and microphone commentary is optional. Play independently for 45 minutes in
whatever way makes sense to you. Do not read development documents or ask for
strategy help during the session. You may stop early; record that honestly.

AFTER PLAYING
Only after the session, complete FEEDBACK_TEMPLATE.txt. Return the recording
and completed form through the private channel supplied by the organizer.

WINDOWS SMARTSCREEN
This early build is unsigned. Windows may show "Windows protected your PC."
Confirm that the ZIP came from the official release page and that its SHA-256
matches. Then choose "More info" and "Run anyway" only if you trust this
specific download. This warning does not make arbitrary unsigned files safe.

SAVES AND CRASH LOGS
Packaged saves are stored in %LOCALAPPDATA%\Ardenia\saves. Crash logs are
stored in %LOCALAPPDATA%\Ardenia\logs. Replacing the extracted Ardenia folder
does not remove those saves. If the game crashes, include the relevant log
when returning feedback through the private channel.

PRIVACY
Ardenia sends nothing automatically. The game has no telemetry, account, or
automatic crash upload. A webcam is not required and microphone commentary is
optional. Participation is voluntary; stop at any time. Send recordings and
completed feedback privately, never through a public GitHub issue.
```

Create `distribution/FEEDBACK_TEMPLATE.txt` with this complete neutral form:

```text
ARDENIA 0.1.0-playtest.1 — ASYNCHRONOUS PLAYTEST FEEDBACK

Complete this only after playing. Return it and the screen recording through
the organizer's private channel. Do not post either as a public GitHub issue.
Do not add your full name, email address, or account name.

CONSENT
May the organizer retain this completed form as anonymized research? yes / no
May the organizer retain the submitted screen recording? yes / no

SESSION FACTS
Windows version:
Display resolution and scaling, if known:
Government or opposition opening:
Campaign party, difficulty, and seed, if known:
Actual session length:
Did you stop before 45 minutes? If so, when and why?
Was microphone commentary recorded? yes / no

YOUR EXPERIENCE
1. In your own words, what happened during the session?

2. What did you think your role was?

3. What was your goal when you stopped?

4. What was your first meaningful action? Approximately how long did it take
   before you made it?

5. Where did you search, wait, let time pass, or feel unsure what to do?
   Give approximate times from the screen recording when possible.

6. What was the first objective you chose, if any, and why?

7. Who or what seemed to oppose you or pull events in another direction?

8. Which choice required a tradeoff or giving something up, if any?

9. What consequence do you think followed from one of your choices, if any?

10. What felt important while you were playing?

11. What did you want to do that you could not do?

12. What did you expect to happen next?

13. How did the passage of time feel? Answer in your own words first.

14. After answering above, which is closest to how you would want time to
    advance: daily real-time / next meaningful decision/date / monthly
    advancement / another approach / no preference? Why?

15. Did anything make the game appear unfinished or unavailable? What?

16. Describe any crash, display, performance, control, or accessibility issue.
    Include the approximate recording time and crash-log filename if relevant.

17. What is the one thing you would most want changed before playing again?

END OF FORM
```

- [ ] **Step 7: Implement the safe local build orchestrator**

Create `scripts/build_windows.ps1` with this complete orchestration shape:

```powershell
param([string]$Python = "python")
$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$buildDir = [IO.Path]::GetFullPath((Join-Path $repoRoot "build"))
$distDir = [IO.Path]::GetFullPath((Join-Path $repoRoot "dist"))

function Assert-RepositoryChild([string]$Candidate) {
    $full = [IO.Path]::GetFullPath($Candidate)
    $prefix = $repoRoot.TrimEnd('\') + '\'
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing packaging operation outside repository: $full"
    }
    return $full
}

$buildDir = Assert-RepositoryChild $buildDir
$distDir = Assert-RepositoryChild $distDir
$verifyData = Assert-RepositoryChild (Join-Path $buildDir "verify-user-data")
$oldQt = $env:QT_QPA_PLATFORM
$oldData = $env:ARDENIA_USER_DATA_DIR

function Invoke-Checked([scriptblock]$Command, [string]$Label) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE" }
}

Push-Location $repoRoot
try {
    $toolchain = & $Python -c `
        "import sys,PySide6,PyInstaller; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}|{PySide6.__version__}|{PyInstaller.__version__}')"
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect packaging toolchain" }
    if ($toolchain.Trim() -ne "3.14.6|6.11.1|6.16.0") {
        throw "Unsupported packaging toolchain: $toolchain"
    }

    foreach ($target in @($buildDir, $distDir)) {
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
    }
    New-Item -ItemType Directory -Path $buildDir | Out-Null

    Invoke-Checked {
        & $Python packaging\render_windows_version.py build\windows-version.txt
    } "Windows version rendering"
    Invoke-Checked {
        & $Python -m PyInstaller --clean --noconfirm packaging\ardenia.spec
    } "PyInstaller"

    $packageDir = Join-Path $distDir "Ardenia"
    if (-not (Test-Path -LiteralPath (Join-Path $packageDir "Ardenia.exe"))) {
        throw "PyInstaller did not produce dist\Ardenia\Ardenia.exe"
    }
    Copy-Item -LiteralPath distribution\PLAYTEST_README.txt -Destination $packageDir
    Copy-Item -LiteralPath distribution\FEEDBACK_TEMPLATE.txt -Destination $packageDir

    New-Item -ItemType Directory -Path $verifyData | Out-Null
    $env:QT_QPA_PLATFORM = "offscreen"
    $env:ARDENIA_USER_DATA_DIR = $verifyData
    $process = Start-Process -FilePath (Join-Path $packageDir "Ardenia.exe") `
        -ArgumentList "--verify-build" -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        throw "Packaged verification failed with exit code $($process.ExitCode)"
    }
    Remove-Item -LiteralPath $verifyData -Recurse -Force

    $archiveName = (& $Python -c "import version; print(version.ARCHIVE_FILENAME").Trim()
    if ($LASTEXITCODE -ne 0) { throw "Could not read archive version" }
    $archivePath = Assert-RepositoryChild (Join-Path $distDir $archiveName)
    Compress-Archive -LiteralPath $packageDir -DestinationPath $archivePath
    $hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLower()
    $checksumPath = Assert-RepositoryChild "$archivePath.sha256"
    Set-Content -LiteralPath $checksumPath `
        -Value "$hash  $([IO.Path]::GetFileName($archivePath))" -Encoding ascii
    Write-Host "Package: $archivePath"
    Write-Host "Checksum: $checksumPath"
}
finally {
    if ($null -eq $oldQt) { Remove-Item Env:QT_QPA_PLATFORM -ErrorAction SilentlyContinue }
    else { $env:QT_QPA_PLATFORM = $oldQt }
    if ($null -eq $oldData) { Remove-Item Env:ARDENIA_USER_DATA_DIR -ErrorAction SilentlyContinue }
    else { $env:ARDENIA_USER_DATA_DIR = $oldData }
    Pop-Location
}
```

The recursive removals are limited to the already resolved and validated repository `build/`, `dist/`, and verification-data paths. Do not add a caller-supplied output-directory parameter.

- [ ] **Step 8: Install build dependencies and run the real local package cycle**

Run:

```powershell
& "D:\Political Sim Game\.venv\Scripts\python.exe" -m pip install -r requirements-build.txt
& "D:\Political Sim Game\.venv\Scripts\python.exe" distribution_test.py
powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1 -Python "D:\Political Sim Game\.venv\Scripts\python.exe"
```

Expected: distribution checks pass; `dist/Ardenia/Ardenia.exe`, the versioned ZIP, and `.sha256` exist; packaged verification exits 0; no verification saves/logs remain.

If PyInstaller 6.16.0 refuses Python 3.14.6, stop the task and report the compatibility blocker. Do not loosen or silently change the pin; revise the approved spec/plan with an explicitly supported pinned release first.

- [ ] **Step 9: Commit Task 4**

```powershell
git add requirements.txt requirements-build.txt packaging scripts distribution distribution_test.py
git diff --cached --check
git commit -m "build: package Ardenia for Windows playtests"
```

---

### Task 5: Tag-gated GitHub Actions release

**Files:**
- Create: `.github/workflows/windows-playtest-release.yml`
- Modify: `distribution_test.py`

**Interfaces:**
- Consumes: `scripts/build_windows.ps1`, `scripts/run_ui_smoke_offscreen.py`, `version.TAG`, `version.ARCHIVE_FILENAME`
- Produces on manual dispatch: private GitHub Actions artifact only
- Produces on matching tag push: public GitHub Release with ZIP and SHA-256 asset

- [ ] **Step 1: Add a failing workflow-contract check**

Add to `distribution_test.py`:

```python
def release_workflow_is_manual_or_tag_only():
    workflow = (PROJECT_ROOT / ".github/workflows/windows-playtest-release.yml") \
        .read_text(encoding="utf-8")
    assert "workflow_dispatch:" in workflow
    assert "v*-playtest.*" in workflow
    assert "pull_request:" not in workflow
    assert "branches:" not in workflow
    assert "scripts/build_windows.ps1" in workflow
    assert "scripts/run_ui_smoke_offscreen.py" in workflow
    assert "git diff --check" in workflow
    assert "gh release create" in workflow
    assert "github.event_name == 'push'" in workflow
    assert "github.sha" in workflow
    assert "actions/upload-artifact@v4" in workflow
```

Append it to `checks`.

- [ ] **Step 2: Run and confirm missing-workflow failure**

Run `distribution_test.py`.

Expected: non-zero with `FileNotFoundError` for the workflow.

- [ ] **Step 3: Implement the workflow**

Create `.github/workflows/windows-playtest-release.yml` with:

```yaml
name: Windows playtest release

on:
  push:
    tags:
      - "v*-playtest.*"
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build-and-verify:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.14.6"
          architecture: "x64"
          cache: "pip"
      - name: Install pinned dependencies
        run: python -m pip install -r requirements-build.txt
      - name: Validate source and release tag
        shell: pwsh
        run: |
          git diff --check
          python distribution_test.py
          if ("${{ github.event_name }}" -eq "push") {
            python -c "import version; version.validate_tag('${{ github.ref_name }}')"
          }
      - name: Run engine suite
        run: python smoke_test.py
        env:
          PYTHONUTF8: "1"
      - name: Run GUI suite offscreen
        run: python scripts/run_ui_smoke_offscreen.py
        env:
          PYTHONUTF8: "1"
          QT_QPA_PLATFORM: "offscreen"
      - name: Build and verify Windows package
        shell: pwsh
        run: scripts/build_windows.ps1 -Python python
      - name: Upload inspected workflow artifact
        uses: actions/upload-artifact@v4
        with:
          name: Ardenia-Windows-playtest
          path: |
            dist/Ardenia-*-win64.zip
            dist/Ardenia-*-win64.zip.sha256
          if-no-files-found: error
      - name: Publish tag-gated GitHub Release
        if: github.event_name == 'push'
        shell: pwsh
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          $version = python -c "import version; print(version.VERSION)"
          $commit = "${{ github.sha }}"
          $zip = "dist/Ardenia-$version-win64.zip"
          $sha = "$zip.sha256"
          $notes = @"
          Ardenia $version is an unsigned Windows 10/11 early playtest build.
          Source commit: $commit

          Download the ZIP, verify it with the attached SHA-256 file, extract the
          complete Ardenia folder, and run Ardenia.exe. Python and Git are not
          required. Windows SmartScreen may warn because this build is unsigned.

          Saves: %LOCALAPPDATA%\Ardenia\saves
          Crash logs: %LOCALAPPDATA%\Ardenia\logs

          Follow PLAYTEST_README.txt inside the archive. Return recordings and
          completed feedback only through the organizer's private channel.
          "@
          $notesPath = "dist/release-notes.md"
          Set-Content -LiteralPath $notesPath -Value $notes -Encoding utf8
          gh release create "${{ github.ref_name }}" $zip $sha `
            --verify-tag --title "Ardenia $version — Windows playtest" `
            --notes-file $notesPath
```

Keep the trigger exactly tag/manual. Do not add a branch push or pull-request release trigger. The workflow may run only the committed commands; it must not download an installer, upload telemetry, or use a repository secret beyond the scoped GitHub token.

- [ ] **Step 4: Validate the workflow contract and syntax-facing invariants**

Run `distribution_test.py` and `git diff --check`.

Then inspect the workflow with:

```powershell
Select-String -Path .github\workflows\windows-playtest-release.yml -Pattern "pull_request|branches|gh release create|github.event_name"
```

Expected: no `pull_request`/`branches` trigger; publication has the push-event condition.

- [ ] **Step 5: Commit Task 5**

```powershell
git add .github/workflows/windows-playtest-release.yml distribution_test.py
git diff --cached --check
git commit -m "ci: publish verified Windows playtest tags"
```

---

### Task 6: Release documentation and end-to-end rehearsal

**Files:**
- Create: `docs/playtests/WINDOWS_RELEASE_CHECKLIST.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `distribution_test.py`

**Interfaces:**
- Consumes all prior build/release interfaces.
- Produces the owner checklist used before the first immutable public tag.

- [ ] **Step 1: Add a failing documentation-contract test**

Add to `distribution_test.py`:

```python
def release_checklist_requires_clean_machine_and_frozen_sample():
    checklist = (PROJECT_ROOT / "docs/playtests/WINDOWS_RELEASE_CHECKLIST.md") \
        .read_text(encoding="utf-8").lower()
    for required in ("clean windows", "without python", "government",
                     "opposition", "autosave", "manual save", "load",
                     "replace the extracted", "sha-256", "smartscreen",
                     "freeze the build", "v0.1.0-playtest.1"):
        assert required in checklist
```

Append it to `checks`.

- [ ] **Step 2: Run and confirm missing-checklist failure**

Run `distribution_test.py`.

Expected: non-zero with missing `WINDOWS_RELEASE_CHECKLIST.md`.

- [ ] **Step 3: Write the exact owner release checklist**

Create `docs/playtests/WINDOWS_RELEASE_CHECKLIST.md` with these ordered gates:

1. confirm the candidate commit and `version.py` values;
2. run `distribution_test.py`, full UTF-8 `smoke_test.py`, and offscreen UI runner;
3. run the local PowerShell build and compare the generated SHA-256;
4. use a clean Windows 10/11 environment without Python to extract and launch;
5. generate both a government and opposition campaign;
6. advance time, trigger autosave, create a manual save, close, reopen, and load;
7. replace the extracted program folder and confirm the save remains under `%LOCALAPPDATA%`;
8. confirm title, packet, filename, checksum, and release notes all say `0.1.0-playtest.1`;
9. confirm the documented unsigned SmartScreen experience;
10. integrate the reviewed branch into `main` before tagging;
11. push `v0.1.0-playtest.1`, watch the GitHub workflow, download the public ZIP, and independently verify its hash;
12. freeze the build for the six-to-eight-session sample, separating any emergency replacement by a new version.

Include blank checkbox syntax and an evidence field beneath each manual gate. Include rollback instructions: if the public workflow fails, do not recreate the same tag against different code; fix on `main`, increment the playtest version, and publish a new immutable tag.

- [ ] **Step 4: Update developer documentation**

Add a concise `Windows playtest distribution` section to both `AGENTS.md` and `CLAUDE.md` with:

```text
Focused distribution checks:
  .venv\Scripts\python.exe distribution_test.py
Local Windows package:
  powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1 -Python .venv\Scripts\python.exe
Manual workflow dispatch builds a private artifact. Only v*-playtest.* tags
publish. Packaged saves/logs live under %LOCALAPPDATA%\Ardenia; source saves
remain in saves/. A new public asset always receives a new version/tag.
```

Document that `ARDENIA_USER_DATA_DIR` is test/build-only, and that no private feedback address or participant material is committed.

- [ ] **Step 5: Run every source and package verification on the final tree**

Run, without piping away the Python exit code:

```powershell
$env:PYTHONUTF8 = "1"
& "D:\Political Sim Game\.venv\Scripts\python.exe" distribution_test.py
& "D:\Political Sim Game\.venv\Scripts\python.exe" smoke_test.py
$env:QT_QPA_PLATFORM = "offscreen"
& "D:\Political Sim Game\.venv\Scripts\python.exe" scripts\run_ui_smoke_offscreen.py
powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1 -Python "D:\Political Sim Game\.venv\Scripts\python.exe"
git diff --check
git status --short
```

Expected: all three Python test processes and the build process exit 0; UI reports zero failures/skips; `git diff --check` is silent; only Task 6 tracked changes are present before staging; the ZIP and checksum are ignored build outputs.

- [ ] **Step 6: Inspect the actual generated archive**

Expand the generated ZIP into a newly created repository-local ignored directory such as `build/archive-inspection`, after resolving and verifying it is under `build/`. Confirm:

- top-level folder is `Ardenia/`;
- `Ardenia.exe`, `PLAYTEST_README.txt`, and `FEEDBACK_TEMPLATE.txt` exist;
- no `saves/`, `logs/`, `.git/`, `.venv/`, `.pyc`, completed feedback, or participant file is present;
- the SHA-256 file matches a fresh `Get-FileHash` result; and
- running the extracted `Ardenia.exe --verify-build` with a fresh `ARDENIA_USER_DATA_DIR` exits 0.

Remove only the validated `build/archive-inspection` directory after inspection.

- [ ] **Step 7: Commit Task 6**

```powershell
git add docs/playtests/WINDOWS_RELEASE_CHECKLIST.md AGENTS.md CLAUDE.md distribution_test.py
git diff --cached --check
git commit -m "docs: define Windows playtest release gate"
```

- [ ] **Step 8: Stop for the clean-machine and integration gates**

Report the candidate ZIP path, SHA-256, exact commit, automated results, and the uncompleted manual clean-Windows checklist items. Do not push the public version tag from the feature branch. Invoke `superpowers:finishing-a-development-branch` so the user chooses how to integrate the reviewed implementation.

---

## Post-Integration Publication Runbook

This runbook is intentionally after feature-branch completion. Execute it only when the reviewed implementation is present on `main` and the owner has recorded the clean-Windows manual checks in `docs/playtests/WINDOWS_RELEASE_CHECKLIST.md` or an equivalent private release record.

1. Confirm `main` is clean and contains the reviewed implementation commit.
2. Run the full Task 6 verification commands on `main`.
3. Confirm `git tag --list v0.1.0-playtest.1` is empty locally and remotely.
4. Create the immutable annotated tag:

   ```powershell
   git tag -a v0.1.0-playtest.1 -m "Ardenia 0.1.0-playtest.1"
   ```

5. Push only that tag:

   ```powershell
   git push origin v0.1.0-playtest.1
   ```

6. Watch the `Windows playtest release` workflow. A failure publishes nothing; fix forward with a new version rather than moving the tag.
7. Download the published ZIP and SHA-256 from the public GitHub Release.
8. Recompute the hash locally and compare it byte-for-byte with the published checksum.
9. Extract the public asset and run `Ardenia.exe --verify-build` with a fresh isolated `ARDENIA_USER_DATA_DIR`.
10. Publish/share the GitHub Release URL only after those checks pass, then freeze that version for the baseline sample.

Do not delete or replace a release asset after sessions use it. Any release-blocking correction becomes `0.1.0-playtest.2` with tag `v0.1.0-playtest.2`, and the evidence synthesis records which participant used which build.
