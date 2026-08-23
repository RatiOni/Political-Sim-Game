import os
from pathlib import Path
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from PySide6.QtWidgets import QDialog, QMessageBox

QDialog.exec = lambda self, *args, **kwargs: 0
QMessageBox.exec = lambda self, *args, **kwargs: 0
QMessageBox.information = lambda *args, **kwargs: 0
QMessageBox.warning = lambda *args, **kwargs: 0
QMessageBox.critical = lambda *args, **kwargs: 0

import ui_smoke_test

ui_smoke_test.main()
