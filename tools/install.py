"""Assemble the Apple Silicon game app from a release payload and your game files."""

import argparse
import json
import platform
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from zipfile import BadZipFile, ZipFile

from game_files import APP_NAME, BASE_APP, CHUNK_SIZE, EDITION, PAYLOAD_NAME, file_index, game_data, safe_path, sha256


def version_tuple(value):
    return tuple(int(part) for part in value.split("."))


def find_base(root, records):
    files = file_index(root)
    needed = {
        (record["base"], record["base_sha256"])
        for record in records if "base" in record
    }
    result = {}
    failures = []
    for name, expected_hash in sorted(needed):
        path = files.get(name.casefold())
        candidates = (path, path.with_name(path.name + ".bak")) if path else ()
        for candidate in candidates:
            if candidate.is_file() and candidate.resolve().is_relative_to(root) and sha256(candidate) == expected_hash:
                result[name, expected_hash] = candidate
                break
        else:
            failures.append(name)
    if failures:
        shown = ", ".join(failures[:8])
        if len(failures) > 8:
            shown += f" and {len(failures) - 8} more"
        raise ValueError(
            f"{len(failures)} base game files are missing or differ from the supported classic PC data: {shown}. "
            "Use a compatible macVC GameData folder from your own classic game."
        )
    return result


def extract_member(package, member, destination):
    with package.open(member) as source, destination.open("wb") as output:
        shutil.copyfileobj(source, output, CHUNK_SIZE)


def write_archive(base, package, record, destination, scratch):
    literal = scratch / "literal"
    extract_member(package, record["member"], literal)
    with base.open("rb") as original, literal.open("rb") as changes, destination.open("wb") as output:
        inputs = {"copy": original, "literal": changes}
        remaining = record["size"]
        for kind, offset, length in record["operations"]:
            if offset < 0 or length < 1 or length > remaining:
                raise ValueError(f"Invalid archive operation in {record['path']}")
            stream = inputs[kind]
            stream.seek(offset)
            remaining -= length
            while length:
                data = stream.read(min(length, CHUNK_SIZE))
                if not data:
                    raise ValueError(f"Truncated archive operation in {record['path']}")
                output.write(data)
                length -= len(data)
        if remaining:
            raise ValueError(f"Incomplete archive operations in {record['path']}")


def install_game_files(package, records, bases, data, scratch):
    data.mkdir(parents=True)
    for record in records:
        relative = safe_path(record["path"])
        destination = data / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        kind = record["kind"]
        if kind == "new":
            extract_member(package, record["member"], destination)
        else:
            base = bases[record["base"], record["base_sha256"]]
            if kind == "base":
                shutil.copyfile(base, destination)
            elif kind == "diff":
                delta = scratch / "delta"
                extract_member(package, record["member"], delta)
                subprocess.run(["/usr/bin/bspatch", str(base), str(destination), str(delta)], check=True)
            elif kind == "archive":
                write_archive(base, package, record, destination, scratch)
            else:
                raise ValueError(f"Unknown patch operation: {kind}")
        if destination.stat().st_size != record["size"] or sha256(destination) != record["sha256"]:
            raise ValueError(f"Checksum mismatch for {relative}")


def install(base, package_path, destination, check_only):
    with ZipFile(package_path) as package:
        manifest = json.loads(package.read("manifest.json"))
        if manifest["version"] != 1:
            raise ValueError("This installer requires a version 1 payload.")
        macos = platform.mac_ver()[0]
        if platform.machine() != "arm64" or not macos or version_tuple(macos) < version_tuple(manifest["minimum_macos"]):
            raise ValueError(f"Use an Apple Silicon Mac running macOS {manifest['minimum_macos']} or later.")
        if not check_only and (destination.exists() or destination.is_symlink()):
            raise FileExistsError(f"Choose a new destination. An installation already exists at {destination}")
        print(f"Checking the classic Vice City files in {base}", flush=True)
        bases = find_base(base, manifest["files"])
        if check_only:
            print("The base files match this release.")
            return
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=".hawking-install-", dir=destination.parent) as temp:
            scratch = Path(temp)
            installation = scratch / "installation"
            app = installation / APP_NAME
            for record in manifest["runtime"]:
                relative = safe_path(record["path"])
                if relative.parts[0] != "Contents" or relative.parts[:3] == ("Contents", "Resources", "GameData"):
                    raise ValueError(f"Invalid runtime path: {relative}")
                path = app / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                extract_member(package, "runtime/" + relative.as_posix(), path)
                if sha256(path) != record["sha256"]:
                    raise ValueError(f"Checksum mismatch for {relative}")
                path.chmod(record["mode"] & (stat.S_IRWXU | stat.S_IRWXG | stat.S_IRWXO))

            print("Assembling and verifying the game files", flush=True)
            install_game_files(package, manifest["files"], bases, installation / "GameData", scratch)
            subprocess.run(["/usr/bin/codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
            subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
            if destination.exists() or destination.is_symlink():
                raise FileExistsError(destination)
            installation.rename(destination)
    print(f"Installed {destination / APP_NAME}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, default=BASE_APP)
    parser.add_argument("--payload", type=Path, default=Path(__file__).resolve().parents[1] / PAYLOAD_NAME)
    parser.add_argument("--destination", type=Path, default=Path.home() / "Applications" / EDITION,
                        help="New folder for the app and its writable GameData")
    parser.add_argument("--check", action="store_true", help="Check game data compatibility without installing")
    args = parser.parse_args()
    try:
        install(game_data(args.base), args.payload.expanduser(), args.destination.expanduser().absolute(), args.check)
    except (OSError, ValueError, KeyError, BadZipFile, subprocess.CalledProcessError) as error:
        print(f"Installation stopped. {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
