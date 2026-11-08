# Penumbra

A macOS menu bar app for theme presets.

## Requirements

- macOS 26 or later
- Swift 6.2 or later.

## Build

```sh
./Scripts/build_app.sh
open Build/Penumbra.app
```

## Command-line tool

```sh
alias penumbractl="$PWD/Build/Penumbra.app/Contents/MacOS/penumbractl"
penumbractl add-auto Dusk blue purple ~/Pictures/day.png ~/Pictures/night.png
penumbractl apply Dusk
penumbractl undo
```

## URL scheme

- `penumbra://new` opens the editor for a new preset
- `penumbra://edit?name=Dusk` edits a preset
- `penumbra://apply?name=Dusk` applies a preset

These work from Shortcuts, Raycast, or `open` in Terminal.
