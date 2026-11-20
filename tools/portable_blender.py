"""Copy Blender projects and move available texture and library paths beside them."""

import json
import shutil
import sys
from pathlib import Path

import bpy


def main():
    source, stage, mapping_path = map(Path, sys.argv[sys.argv.index("--") + 1:])
    names = json.loads(mapping_path.read_text())
    plans = {source / old: stage / new for old, new in names.items()}
    blender_brushes = Path(bpy.utils.system_resource("DATAFILES")) / "assets/brushes"

    def mapped(path):
        if path in plans:
            return plans[path]
        if path.is_relative_to(source):
            return stage / "Dependencies" / path.relative_to(source)
        if path.is_relative_to(blender_brushes):
            return stage / "Dependencies" / "Blender Brushes" / path.name
        return None

    def rebase(raw, old, new):
        absolute = Path(bpy.path.abspath(raw)).resolve()
        if not absolute.is_file() and old.is_relative_to(source / "vehicle_pack/toyota-fortuner-2021"):
            textures = old.parent / "textures"
            matches = [path for path in textures.iterdir() if path.name.casefold() == absolute.name.casefold()]
            if not matches and absolute.suffix.casefold() == ".dds":
                matches = [path for path in textures.iterdir() if path.stem.casefold() == absolute.stem.casefold()]
            if len(matches) == 1:
                absolute = matches[0]
        if absolute.name == "essentials_brushes-gp_draw.blend" and not absolute.is_file():
            absolute = blender_brushes / absolute.name
        target = mapped(absolute)
        if target and absolute.is_file():
            if absolute not in plans and not target.exists():
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(absolute, target)
            return bpy.path.relpath(str(target), start=str(new.parent))
        if absolute.is_relative_to(source):
            return "//Missing references/" + absolute.name
        return raw

    for old, new in plans.items():
        new.parent.mkdir(parents=True, exist_ok=True)
        if old.suffix != ".blend" and ".blend." not in old.name:
            shutil.copyfile(old, new)
            continue
        bpy.ops.wm.open_mainfile(filepath=str(old), load_ui=True, use_scripts=False)
        bpy.context.preferences.filepaths.save_version = 0
        for blocks in (bpy.data.images, bpy.data.libraries, bpy.data.fonts, bpy.data.sounds,
                       bpy.data.movieclips, bpy.data.volumes, bpy.data.cache_files):
            for block in blocks:
                raw = block.filepath
                if raw and raw != "<builtin>" and not block.library and not getattr(block, "packed_file", None):
                    block.filepath = rebase(raw, old, new)
        for block in bpy.data.user_map():
            reference = block.library_weak_reference
            if reference and reference.filepath:
                reference.filepath = rebase(reference.filepath, old, new)
        bpy.ops.wm.save_as_mainfile(filepath=str(new), relative_remap=False, compress=True)


if __name__ == "__main__":
    main()
