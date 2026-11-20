# GTA Stephen Hawking Edition

An Apple Silicon mod for classic Grand Theft Auto: Vice City. Drive Stephen Hawking's wheelchair, find the custom autorickshaw and bicycle, and spawn the Ambassador, Tumbler, and seven replacement vehicles.

## Install and play on Mac

1. Get your own classic PC Vice City game files. The supported input is the tested classic build prepared as a macVC `GameData` folder. The installer checks the exact game files it needs. The Definitive Edition uses different assets. [macVC setup guide](https://github.com/gtamac/macVC#install)
2. Use an Apple Silicon Mac with macOS 26 or later and Python 3.9 or later. Install Python if needed. [Python for macOS](https://www.python.org/downloads/macos/)
3. Download `GTA-Stephen-Hawking-Edition-macOS-arm64.zip` from the project's GitHub Releases and extract it. Open **Install on macOS.command** with the bundled payload beside it. If the classic game is elsewhere, select its `GameData` folder or specify it in Terminal.
4. Open **GTA Stephen Hawking Edition** inside the **GTA Stephen Hawking Edition** folder in your home folder's **Applications** directory and choose **New Game**. Keep the app and its **GameData** folder together. The app contains its native libraries. The installer assembles and verifies a separate copy using the player's game files.

From the extracted player download, you can run this in Terminal.

```sh
zsh "./Install on macOS.command" --base "/path/to/GameData"
```

Add `--check` to verify a copy without installing. The installer also accepts a macVC `.app` as the base. Use `--destination "$HOME/Applications/Another Hawking Install"` to install beside an existing copy.

## Controls and vehicles

- Use **WASD** or the **arrow keys** to drive the wheelchair. Hold **Shift** to go faster. Press **F** or **Return** to enter or exit a vehicle. See **Options → Controller Setup** for the rest of the bindings.
- Type **AMBASSADOR** during play for the Ambassador or **PANZER** for the Tumbler. The Tumbler boosts while you hold the horn and accelerate.
- Type **WAGONR**, **ALTO**, **POLO**, **MARUTI**, **GYPSY**, **FORTUNER**, or **JCB** during play for the seven-car pack.

The game stores this edition's saves and settings in
`~/Library/Application Support/Hawking Vice City/Library/Application Support/reVC`.

## Project files

- [Blender model catalog](models/README.md)
- [Build and prepare a GitHub release](docs/RELEASE.md)
- [Mac verification](docs/VERIFICATION.md)
