"""


Graphical entry point (PySide6): python gui.py
Opens on the main menu — New Game runs the campaign wizard, Load Game picks
a save; AppController keeps the menu and game window alive and switches
between them.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from PySide6.QtWidgets import QApplication, QMessageBox
from PySide6.QtGui import QFontDatabase

import app_paths
import packaged_verify
import runtime_logging
from ui import theme
from ui.menu import RootController
from ui.app import MainWindow
from version import APP_NAME


# The four Public Sans weights DESIGN.md's Typography section calls for
# (Regular/Medium/SemiBold/Bold) — bundled under ui/assets/fonts so QML's
# `font.family: "Public Sans"` (ui/qml/Theme.qml) and Widgets' FONT_FAMILY
# (ui/theme.py) resolve to the real face instead of a system substitute.
PUBLIC_SANS_WEIGHTS = ("Regular", "Medium", "SemiBold", "Bold")


def register_bundled_fonts() -> None:
    for weight in PUBLIC_SANS_WEIGHTS:
        path = app_paths.resource_path(f"ui/assets/fonts/PublicSans-{weight}.ttf")
        font_id = QFontDatabase.addApplicationFont(str(path))
        if font_id == -1:
            runtime_logging.write_log(
                "font-registration-failed", f"Qt rejected font file: {path}\n")


class AppController:
    """Holds references to the menu and the active game window and switches
    between them. Without this, either window would be garbage-collected the
    moment the local variable fell out of scope."""

    def __init__(self):
        self.menu = RootController()
        self.menu.campaign_ready.connect(self._launch_game)
        self.game_window = None

    def show_menu(self):
        self.menu.show()

    def _launch_game(self, state):
        self.menu.hide()
        self.game_window = MainWindow(state=state, on_exit_to_menu=self._return_to_menu)
        self.game_window.show()

    def _return_to_menu(self):
        if self.game_window is not None:
            self.game_window.close()
            self.game_window = None
        self.menu.show()


def install_exception_hook() -> None:
    def handle(exc_type, exc_value, traceback_obj):
        try:
            try:
                path = runtime_logging.write_crash_log(
                    exc_type, exc_value, traceback_obj)
                detail = f"A crash log was written to:\n{path}"
            except Exception as log_error:
                detail = f"The crash log could not be written:\n{log_error}"
            if not app_paths.is_packaged():
                sys.__excepthook__(exc_type, exc_value, traceback_obj)
            QMessageBox.critical(
                None, f"{APP_NAME} stopped unexpectedly",
                f"Ardenia encountered an unexpected error.\n\n{detail}")
        finally:
            QApplication.exit(1)
    sys.excepthook = handle


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv if argv is None else argv)
    verifying = "--verify-build" in argv
    qt_argv = [item for item in argv if item != "--verify-build"]
    app = QApplication(qt_argv)
    register_bundled_fonts()
    app.setStyleSheet(theme.stylesheet())
    if verifying:
        return packaged_verify.run_verify_build(app)
    install_exception_hook()
    controller = AppController()
    controller.show_menu()
    # Keep the controller alive for the lifetime of the app.
    app._controller = controller
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
