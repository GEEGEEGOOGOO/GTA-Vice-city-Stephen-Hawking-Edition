# GTA Stephen Hawking Edition

An Apple Silicon mod for classic Grand Theft Auto: Vice City. Drive Stephen Hawking's wheelchair, find the custom autorickshaw and bicycle, and spawn the Ambassador, Tumbler, and seven replacement vehicles.

## Download for macOS

[Download GTA Stephen Hawking Edition v1.0.0 for Apple Silicon (633 MiB)](https://github.com/GEEGEEGOOGOO/GTA-Vice-city-Stephen-Hawking-Edition/releases/download/v1.0.0/GTA-Stephen-Hawking-Edition-macOS-arm64.zip)

### Requirements

- An Apple Silicon Mac (M1 or newer) running macOS 26 or later.
- Python 3.9 or later. [Get Python for macOS](https://www.python.org/downloads/macos/)
- Your own copy of the original PC release of Vice City with matching game files. Use the macVC guide to prepare a `Grand Theft Auto Vice City.app` containing the original game's `GameData` folder. The installer checks those files before assembling the mod. [macVC setup guide](https://github.com/gtamac/macVC#install)

### Install and play

1. **Extract the download.** Double-click the ZIP in Finder and open the extracted folder. Keep **Install on macOS.command** and the bundled `hawking-vice-city-macos-arm64.zip` together.
2. **Run the installer.** Double-click **Install on macOS.command**. It automatically checks the macVC app in **Applications**. If it asks you to choose a folder, select the classic game's **GameData** folder, the one that contains `data` and `models`. Wait for Terminal to report **Installed**.
3. **Open the modded game.** In Finder, press **Command–Shift–G**, enter `~/Applications/GTA Stephen Hawking Edition`, and open **GTA Stephen Hawking Edition.app**. Keep the app and its **GameData** folder together if you move the installation.
4. **Start playing.** Choose **Start Game → New Game**.

### Install from Terminal

If Finder won't open the installer, open Terminal and run these commands. Adjust the first path if you extracted the ZIP somewhere else.

```sh
cd "$HOME/Downloads/GTA-Stephen-Hawking-Edition-macOS-arm64"
zsh "./Install on macOS.command"
```

To select a different copy of the base game, pass its macVC app or `GameData` folder explicitly.

```sh
zsh "./Install on macOS.command" --base "/path/to/GameData"
```

If the installer reports missing or different game files, run the installer with `--check` to verify the base game without installing. To install alongside an existing copy, add `--destination "$HOME/Applications/Another Hawking Install"`.

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
