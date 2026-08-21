"""Geometry regression checks for the 1080p dashboard.

Windows commonly presents a 1920x1080 display to Qt as roughly 1536x816
logical pixels at 125% scaling. This is the size that exposed the map/assembly
overlap even though an unscaled offscreen test looked healthy.
"""

import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtGui import QFontDatabase
from PySide6.QtWidgets import QApplication, QDialog, QMessageBox

from engine.campaign import default_config, generate_campaign
from ui import theme
from ui.app import MainWindow


LOGICAL_1080P_WIDTH = 1536
LOGICAL_1080P_HEIGHT = 816


def check(name, fn):
    fn()
    print(f"PASS  {name}")


app = QApplication.instance() or QApplication([])
QFontDatabase.addApplicationFont(r"C:\Windows\Fonts\segoeui.ttf")
app.setStyleSheet(theme.stylesheet())
QDialog.exec = lambda self, *args, **kwargs: 0
QMessageBox.exec = lambda self, *args, **kwargs: 0
QMessageBox.information = lambda *args, **kwargs: 0


def build_window():
    state = generate_campaign(default_config())
    window = MainWindow(state=state)
    window.resize(LOGICAL_1080P_WIDTH, LOGICAL_1080P_HEIGHT)
    window.show()
    app.processEvents()
    return window


def _assert_middle_is_separated(window):
    map_rect = window._map.geometry()
    assembly_rect = window._factions.geometry()
    assert map_rect.bottom() < assembly_rect.top(), (
        f"map ends at {map_rect.bottom()}, assembly begins at {assembly_rect.top()}")
    assert window._left.height() >= window._left.minimumSizeHint().height()
    assert window._right.height() == window._left.height()


def opening_dashboard_fits_scaled_1080p():
    window = build_window()
    try:
        assert window.width() == LOGICAL_1080P_WIDTH
        assert window.height() == LOGICAL_1080P_HEIGHT
        assert window.minimumSizeHint().height() <= LOGICAL_1080P_HEIGHT
        assert not window._digest.isVisible()
        assert window._map.height() >= 340
        assert window._log.height() < 180
        _assert_middle_is_separated(window)
    finally:
        window.close()


def busiest_narrative_month_still_fits():
    window = build_window()
    try:
        window._digest.set_digest([
            "Household confidence fell as living costs outpaced wage growth.",
            "Interior delivery weakened because regional commitments exceeded capacity.",
            "The deficit widened as programme spending reached the monthly accounts.",
            "Regional pressure rose most sharply in Anera and Zavost.",
            "Government approval followed household conditions lower.",
        ])
        window._log.set_dispatches([
            "The government publishes its monthly account.",
            "The chamber prepares for a division.",
            "Regional administrators report uneven conditions.",
            "Foreign ministries continue consultations.",
        ])
        app.processEvents()

        assert window.height() == LOGICAL_1080P_HEIGHT
        assert window.minimumSizeHint().height() <= LOGICAL_1080P_HEIGHT
        assert window._digest.isVisible()
        assert window._map.height() >= 300
        assert window._digest.geometry().right() < window._log.geometry().left()
        _assert_middle_is_separated(window)
    finally:
        window.close()


if __name__ == "__main__":
    checks = [
        ("opening dashboard fits a 1080p screen at 125% scaling",
         opening_dashboard_fits_scaled_1080p),
        ("five digest lines and four dispatches do not crush the map",
         busiest_narrative_month_still_fits),
    ]
    for label, test in checks:
        check(label, test)
    print(f"ALL {len(checks)} DASHBOARD LAYOUT CHECKS PASSED")

