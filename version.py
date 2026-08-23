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
