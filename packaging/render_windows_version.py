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
