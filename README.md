# Warring Hands

*Childhood Game Gone Aggro*

A touch-first, multiplayer rock-paper-scissors RTS for tablets. Cut your screen into panes to watch and command several parts of the battlefield at once.

See [docs/DESIGN.md](docs/DESIGN.md) for the full design.

## Status
Early prototype:
- A pastel 2.5D island (3D world, placeholder billboard units)
- Screen panes: grab a side tab and swipe across to **cut**, drag a divider to **resize**, drag it all the way to **merge**
- Each pane has its own camera: two fingers to pan and pinch-zoom

## Open the project
1. Install [Godot 4.6](https://godotengine.org/download) (standard version, not .NET).
2. In Godot, **Import** and pick this folder's `project.godot`.
3. Press **Play**. On a computer: left mouse acts as one finger (cut / resize), mouse wheel zooms, right-drag pans.

## Layout
```
scenes/    Godot scenes (.tscn)
scripts/   GDScript code (.gd)
docs/      Design notes
.github/   Automatic builds
```

## Automatic builds
Every push to `main` runs GitHub Actions, which:
- exports a **web build** and publishes it to GitHub Pages
- exports an **Android debug APK**, downloadable from the run's *Artifacts*

One-time setup on GitHub: **Settings → Pages → Source: GitHub Actions**.

iOS builds are made on a Mac: export from Godot to an Xcode project, then build in Xcode.

## Large files
Art, audio and fonts are tracked with Git LFS (see `.gitattributes`). Run `git lfs install` once on your machine.
