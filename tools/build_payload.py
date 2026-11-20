"""Build the separate release payload from your base game and tested mod build."""

import argparse
import hashlib
import json
import shutil
from pathlib import Path
from tempfile import TemporaryDirectory
from zipfile import ZIP_DEFLATED, ZipFile

import bsdiff4

from game_files import file_index, game_data, sha256

SECTOR = 2048
MINIMUM_OS = "26.0"
PRISTINE_BACKUPS = {"models/gta3.dir", "models/gta3.img", "data/handling.cfg"}
GENERATED_FILES = {"audio/sound.cache"}


def sector_index(path):
    entries = {}
    with path.open("rb") as source:
        for offset, data in enumerate(iter(lambda: source.read(SECTOR), b"")):
            entries.setdefault(hashlib.sha256(data).digest(), offset * SECTOR)
    return entries


def archive_delta(path, source_index, literal):
    """Reuse original IMG sectors and send only blocks missing from the base archive."""
    operations = []
    literal_offset = 0
    with path.open("rb") as target, literal.open("wb") as output:
        for data in iter(lambda: target.read(SECTOR), b""):
            offset = source_index.get(hashlib.sha256(data).digest())
            kind = "copy" if offset is not None else "literal"
            if offset is None:
                offset = literal_offset
                output.write(data)
                literal_offset += len(data)
            if operations and operations[-1][0] == kind and sum(operations[-1][1:]) == offset:
                operations[-1][2] += len(data)
            else:
                operations.append([kind, offset, len(data)])
    return operations


def write_payload(base_root, mod_root, runtime, output_path, use_backups):
    base_files = file_index(base_root)
    if use_backups:
        for name in PRISTINE_BACKUPS:
            original = base_files[name]
            backup = original.with_name(original.name + ".bak")
            if not backup.is_file():
                raise ValueError(f"Missing requested clean backup: {backup}")
            base_files[name] = backup
    mods = file_index(mod_root)
    archive_source = base_files["models/gta3.img"]
    archive_index = sector_index(archive_source)
    archive_sha = sha256(archive_source)
    manifest = {"version": 1, "minimum_macos": MINIMUM_OS, "files": [], "runtime": []}

    if output_path.exists():
        raise FileExistsError(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(dir=output_path.parent) as staging, ZipFile(
        Path(staging) / "payload.zip", "w", compression=ZIP_DEFLATED, compresslevel=3
    ) as package:
        work = Path(staging)
        for index, (key, source) in enumerate(sorted(mods.items())):
            if key in GENERATED_FILES:
                continue
            relative = source.relative_to(mod_root).as_posix()
            checksum = sha256(source)
            record = {"path": relative, "sha256": checksum, "size": source.stat().st_size}
            base = base_files.get(key)
            member = f"patches/{index}"
            if key in {"models/gta3.img", "models/txd.img"}:
                literal = work / "literals"
                record.update(
                    kind="archive", base="models/gta3.img", base_sha256=archive_sha,
                    member=member, operations=archive_delta(source, archive_index, literal),
                )
                package.write(literal, member)
            elif base is None:
                record.update(kind="new", member=member)
                package.write(source, member)
            else:
                base_sha = sha256(base)
                record.update(base=relative, base_sha256=base_sha)
                if checksum == base_sha:
                    record["kind"] = "base"
                else:
                    record.update(kind="diff", member=member)
                    print(f"Delta for {relative}", flush=True)
                    bsdiff4.file_diff(str(base), str(source), str(work / "delta"))
                    package.write(work / "delta", member)
            if record["kind"] != "base" and record["kind"] != "diff":
                print(f"{record['kind'].capitalize()} {relative}", flush=True)
            manifest["files"].append(record)

        for source in sorted(runtime.rglob("*")):
            if source.is_symlink():
                raise ValueError(f"Bundle external dependencies as regular files: {source}")
            if source.is_file():
                relative = source.relative_to(runtime).as_posix()
                package.write(source, "runtime/" + relative)
                manifest["runtime"].append({
                    "path": relative, "sha256": sha256(source), "mode": source.stat().st_mode & 0o777,
                })
        package.writestr("manifest.json", json.dumps(manifest, separators=(",", ":")))
        package.close()
        shutil.move(work / "payload.zip", output_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True, type=Path)
    parser.add_argument("--mod-data", required=True, type=Path)
    parser.add_argument("--runtime", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--pristine-backups", action="store_true", help="Use the clean .bak archive and handling files")
    args = parser.parse_args()
    write_payload(game_data(args.base), game_data(args.mod_data), args.runtime, args.output, args.pristine_backups)


if __name__ == "__main__":
    main()
