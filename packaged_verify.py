"""Self-checks for the packaged Windows playtest build."""

from pathlib import Path
import sys
import traceback

from PySide6.QtWidgets import QApplication

import app_paths
import runtime_logging
from content.loader import build_state_for
from engine import persistence
from engine.campaign import CampaignConfig, generate_campaign
from ui.menu import RootController


REQUIRED_TESTER_FILES = ("PLAYTEST_README.txt", "FEEDBACK_TEMPLATE.txt")
VERIFY_SLOTS = ("_package_verify_government", "_package_verify_opposition")


def verify_build(app: QApplication,
                 distribution_root: Path | None = None) -> list[str]:
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
        try:
            for slot in VERIFY_SLOTS:
                persistence.delete_save(slot)
        finally:
            if marker is not None and marker.exists():
                marker.unlink()


def run_verify_build(app: QApplication) -> int:
    try:
        verify_build(app)
        return 0
    except Exception:
        try:
            runtime_logging.write_log(
                "verification-failed", traceback.format_exc())
        except Exception:
            pass
        return 1
