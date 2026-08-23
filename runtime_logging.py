"""Local diagnostic logs; this module performs no network operations."""

from datetime import datetime
from pathlib import Path
import platform
import traceback
from types import TracebackType

import app_paths
from version import VERSION


def write_log(prefix: str, body: str, *, when: datetime | None = None) -> Path:
    when = when or datetime.now()
    folder = app_paths.ensure_directory(app_paths.logs_dir())
    path = folder / f"{prefix}-{when:%Y%m%d-%H%M%S}.txt"
    path.write_text(body, encoding="utf-8")
    return path


def write_crash_log(exc_type: type[BaseException], exc_value: BaseException,
                    traceback_obj: TracebackType | None, *,
                    when: datetime | None = None) -> Path:
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
