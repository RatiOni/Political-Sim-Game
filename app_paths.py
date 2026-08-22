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
