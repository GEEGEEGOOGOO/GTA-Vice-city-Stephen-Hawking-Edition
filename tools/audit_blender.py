"""Open project files with Blender's script auto-run disabled and list dependencies."""

import json
import sys
from pathlib import Path

import bpy


def main():
    root, models, report = map(Path, sys.argv[sys.argv.index("--") + 1:])
    results = []
    for name in json.loads(models.read_text()):
        path = root / name
        entry = {"file": name}
        try:
            bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False, use_scripts=False)
            entry["blender"] = ".".join(map(str, bpy.data.version))
            entry["scenes"] = [scene.name for scene in bpy.data.scenes]
            entry["external"] = []
            for raw in sorted(set(bpy.utils.blend_paths(packed=False))):
                resolved = Path(bpy.path.abspath(raw)).resolve()
                entry["external"].append({
                    "reference": raw,
                    "path": str(resolved),
                    "available": resolved.exists(),
                })
        except Exception as error:
            entry["error"] = str(error)
        results.append(entry)
    report.write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
