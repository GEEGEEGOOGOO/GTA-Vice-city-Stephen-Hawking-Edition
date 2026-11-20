# Build and prepare a GitHub release

## Repository and downloads

Push the `Hawking-Vice-City` Git repository. The installer and packaging tools live here. The companion local folder contains the assembled app, editable models, game development files, and candidate downloads.

| Artifact | Use |
| --- | --- |
| `GTA-Stephen-Hawking-Edition-macOS-arm64.zip` | Player installer, native runtime and game-data patches. It requires the player's own matching base game. |
| `Hawking-Vice-City-Blender-Models.zip` | Editable scenes, available dependencies, and previews. |
| `Hawking-Vice-City-Development.zip` | Engine snapshot, authoring scripts, and game asset exports for maintainers. |
| `GTA Stephen Hawking Edition` directory | Local assembled game. The sibling `GameData` folder contains the base game data for local use. |

Review the rights for each candidate before uploading it. The local collection includes third-party Tumbler and vehicle models, reference images and GTA-derived modifications. The package copies untouched game files from the player's installation and uses deltas for modified files. Review the modified assets and the bundled runtime's licensing terms as well. Preserve the accompanying notices, source and any required attributions when distributing. The BYD asset's source and reported license are recorded beside its model.

Upload cleared ZIPs as GitHub Release assets. GitHub blocks files over 100 MiB in ordinary Git and limits each Release asset to less than 2 GiB. [GitHub large-file documentation](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github), [GitHub Releases documentation](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)

## Build a player payload

Use the existing modified ARM64 reVC engine and a compatible ARM64 SDL2, OpenAL Soft and mpg123. The packaged build uses SDL 2.32.10, OpenAL Soft 1.25.2, and mpg123 1.33.7. Its deployment floor is macOS 26 because of the bundled mpg123 build. The runtime builder needs the Xcode Command Line Tools and a directory containing the third-party notices and any required source information.

```sh
tools/prepare_runtime.sh /path/to/reVC /path/to/SDL2 /path/to/libopenal.1.dylib \
  /path/to/libmpg123.0.dylib /path/to/notices /path/to/runtime.app
python3 -m venv .venv
.venv/bin/python -m pip install bsdiff4
.venv/bin/python tools/build_payload.py \
  --base /path/to/classic/GameData \
  --mod-data /path/to/staged/modded/GameData \
  --runtime /path/to/runtime.app \
  --output /path/to/release/hawking-vice-city-macos-arm64.zip
```

The optional builder flag `--pristine-backups` uses the verified pristine `.bak` copies of the GTA3 archive pair and handling configuration. Use it when creating the payload from this project's local classic installation, which has those three files backed up. The installer can match those same backups if the currently installed files were edited.

Place the generated payload beside `Install on macOS.command`, `README.md`, and the `tools` folder containing `install.py` and `game_files.py`. Zip that folder for players. Install from the extracted ZIP into a new destination to verify the artifact. Record its SHA-256 before sharing it.

The maintainers' archive preserves the current engine source and the mod authoring scripts. The older scripts use paths from the original workspace and may require DragonFF, Blender and local source assets. The staging copy of the vehicle pack installer repairs the seven TXD dictionary headers for this engine and bypasses the older copies in the converted texture archive.
