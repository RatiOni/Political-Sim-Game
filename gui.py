"""


Graphical entry point (PySide6): python gui.py
Opens on the main menu — New Game runs the campaign wizard, Load Game picks
a save; AppController keeps the menu and game window alive and switches
between them.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from PySide6.QtWidgets import QApplication

from ui import theme
from ui.menu import RootController
from ui.app import MainWindow


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


def main():
    app = QApplication(sys.argv)
    app.setStyleSheet(theme.stylesheet())
    controller = AppController()
    controller.show_menu()
    # Keep the controller alive for the lifetime of the app.
    app._controller = controller
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
