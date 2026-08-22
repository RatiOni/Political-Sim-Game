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

import packaged_verify
import runtime_logging
from ui import theme
from ui.menu import RootController
from ui.app import MainWindow
from version import APP_NAME


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
            path = runtime_logging.write_crash_log(
                exc_type, exc_value, traceback_obj)
            detail = f"A crash log was written to:\n{path}"
        except Exception as log_error:
            detail = f"The crash log could not be written:\n{log_error}"
        QMessageBox.critical(
            None, f"{APP_NAME} stopped unexpectedly",
            f"Ardenia encountered an unexpected error.\n\n{detail}")
    sys.excepthook = handle


def main(argv: list[str] | None = None) -> int:
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
    # Keep the controller alive for the lifetime of the app.
    app._controller = controller
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
