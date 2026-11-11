# Warring Hands

*Childhood Game Gone Aggro*

A touch-first, multiplayer rock-paper-scissors RTS for tablets. Cut your screen into panes to watch and command several parts of the battlefield at once.

See [docs/DESIGN.md](docs/DESIGN.md) for the full design.

## Status
Early prototype:
- A pastel 2.5D island (3D world, placeholder billboard units)
- Screen panes: grab a side tab and swipe across to **cut**, drag a divider to **resize**, drag it all the way to **merge**
- Each pane has its own camera: two fingers to pan and pinch-zoom
- Terrain: lakes, forests and plateaus; units find their way around them (selected units show their route)
- Economy: HQ, gathering stone / wood / metal, build factories, train units; destroy the enemy HQ to win
- Combat: rock beats scissors beats paper beats rock (counter hits do double damage); units fight enemies they spot
- Units: tap or lasso to select, tap the ground (in any pane) to move; selection bar with hand icons and counts

## Open the project
1. Install [Godot 4.6](https://godotengine.org/download) (standard version, not .NET).
2. In Godot, **Import** and pick this folder's `project.godot`.
3. Press **Play**. On a computer: left mouse acts as one finger (cut / resize), mouse wheel zooms, right-drag pans.

## Layout
```
scenes/       Godot scenes (.tscn)
scripts/      GDScript code (.gd)
scripts/sim/  Game simulation (deterministic, lockstep-ready)
tests/        Automated tests (run: tests/run_tests.sh)
assets/       Game art (hand sprites)
art_source/   Original art sheets (not shipped in the game)
tools/        Helper scripts (e.g. cutting sprites from the art sheet)
docs/         Design notes
.github/      Automatic builds
```

## Automatic builds
Every push to `main` runs GitHub Actions, which:
- runs the tests (the web build is only published if they pass)
- exports a **web build** and publishes it to GitHub Pages
- exports an **Android debug APK**, downloadable from the run's *Artifacts*

One-time setup on GitHub: **Settings → Pages → Source: GitHub Actions**.

iOS builds are made on a Mac: export from Godot to an Xcode project, then build in Xcode.

## Art files
Art is stored as regular Git files (they're small). If art grows past a few
MB per file, consider Git LFS.
