"""Package a compiled Windows runtime with the graphical installer."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from zipfile import ZipFile

from game_files import sha256


def keep_record(record):
    name = record["path"].lower()
    return name not in {"gta-vc.exe", "mss32.dll", "readme.txt", "mp3/mp3report.txt"} and not name.startswith(
        ("readme/", "mss/", "icons/")
    )


def build(args):
    repository = Path(__file__).resolve().parents[1]
    launcher = args.engine.resolve()
    output = args.output.resolve()
    player = args.player_zip.resolve()
    source = args.engine_source.resolve()
    with tempfile.TemporaryDirectory() as directory:
        stage = Path(directory)
        project = stage / "installer"
        shutil.copytree(repository / "installer/windows", project)
        resources = project / "resources"
        runtime = resources / "runtime"
        supplements = resources / "base"
        runtime.mkdir(parents=True)
        inner = f"{player.stem}/hawking-vice-city-macos-arm64.zip"
        with ZipFile(player) as outer, outer.open(inner) as entry, (stage / "payload.zip").open("wb") as temporary:
            shutil.copyfileobj(entry, temporary)
        with ZipFile(stage / "payload.zip") as payload:
            manifest = json.loads(payload.read("manifest.json"))
            (resources / "package.json").write_text(json.dumps({
                "URL": args.url,
                "SHA256": sha256(player),
                "InnerPath": inner,
                "Size": player.stat().st_size,
            }))
        records = [record for record in manifest["files"] if keep_record(record)]
        needed = {r["base"].lower(): r["base_sha256"] for r in records if "base" in r}
        (resources / "manifest.json").write_text(json.dumps({"version": manifest["version"], "files": records}))

        gamefiles = source / "gamefiles"
        candidates = {path.relative_to(gamefiles).as_posix().lower(): path
                      for path in gamefiles.rglob("*") if path.is_file()}
        if args.rickwheel:
            candidates["models/generic/rickwheel.dff"] = args.rickwheel
        for relative, path in candidates.items():
            if relative in needed and sha256(path) == needed[relative]:
                target = supplements / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)

        components = {
            "GTA Stephen Hawking Edition.exe": launcher,
            "OpenAL32.dll": source / "vendor/openal-soft/dist/Win64/OpenAL32.dll",
            "libmpg123-0.dll": source / "vendor/mpg123/dist/Win64/libmpg123-0.dll",
            "Notices/reVC-LICENSE.md": source / "LICENSE.md",
            "Notices/librw-LICENSE": source / "vendor/librw/LICENSE",
            "Notices/OpenAL-Soft-COPYING": source / "vendor/openal-soft/COPYING",
        }
        for name, path in components.items():
            target = runtime / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)

        output.parent.mkdir(parents=True, exist_ok=True)
        go = str(args.go.resolve()) if args.go else "go"
        if args.test_base:
            # Exercise the same manifest, copy and delta code on the build host.
            (project / "install_fixture_test.go").write_text("""
package main
import ("os"; "path/filepath"; "testing")
func TestAssembleRelease(t *testing.T) {
    dest:=filepath.Join(t.TempDir(),"Hawking")
    if err:=install(os.Getenv("HAWKING_TEST_BASE"),dest,os.Getenv("HAWKING_TEST_ZIP"),func(message string){t.Log(message)});err!=nil{
        t.Fatal(err)
    }
    if _,err:=os.Stat(filepath.Join(dest,edition+".exe"));err!=nil{t.Fatal(err)}
}
""")
            subprocess.run([go, "test", "-v", "."], cwd=project,
                           env={**os.environ, "HAWKING_TEST_BASE": str(args.test_base.resolve()),
                                "HAWKING_TEST_ZIP": str(player)}, check=True)

        subprocess.run([go, "build", "-trimpath", "-ldflags=-s -w -H windowsgui", "-o", str(output), "."],
                       cwd=project, env={**os.environ, "CGO_ENABLED": "0", "GOOS": "windows", "GOARCH": "amd64"},
                       check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--engine-source", required=True, type=Path)
    parser.add_argument("--player-zip", required=True, type=Path)
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--rickwheel", type=Path)
    parser.add_argument("--go", type=Path)
    parser.add_argument("--test-base", type=Path)
    build(parser.parse_args())


if __name__ == "__main__":
    main()
