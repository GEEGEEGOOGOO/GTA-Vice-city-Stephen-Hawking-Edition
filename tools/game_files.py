"""Shared paths and checksums for the macOS installer and release builder."""

import hashlib
from pathlib import Path, PurePosixPath

EDITION = "GTA Stephen Hawking Edition"
APP_NAME = EDITION + ".app"
PAYLOAD_NAME = "hawking-vice-city-macos-arm64.zip"
CHUNK_SIZE = 1024 * 1024
BASE_APP = Path("/Applications/Grand Theft Auto Vice City.app")


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(CHUNK_SIZE), b""):
            digest.update(chunk)
    return digest.hexdigest()


def game_data(path):
    path = path.expanduser().resolve()
    if path.suffix.casefold() == ".app":
        path = path / "Contents/Resources/GameData"
    if not path.is_dir():
        raise ValueError(f"Cannot find classic Vice City game data at {path}")
    return path


def file_index(root):
    files = {}
    for path in root.rglob("*"):
        relative = path.relative_to(root)
        if any(part.startswith(".") or part.endswith((".bak", ".blend1")) for part in relative.parts):
            continue
        if path.is_file() and path.resolve().is_relative_to(root):
            key = relative.as_posix().casefold()
            if key in files:
                raise ValueError(f"Two game files have the same name ignoring case: {relative}")
            files[key] = path
    return files


def safe_path(name):
    path = PurePosixPath(name)
    if path.is_absolute() or not path.parts or ".." in path.parts or "\\" in name:
        raise ValueError(f"Invalid package path: {name}")
    return path
