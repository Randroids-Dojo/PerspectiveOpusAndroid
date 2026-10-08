# AGENTS.md

Rules for any coding agent working in Perspective Opus for Android.

## Product

The native Android build of Perspective Opus (the web build is `../PerspectiveOpus`, live at https://perspective-opus.vercel.app). A puzzle platformer where the player switches at any moment between a hand-inked 2D world (the Score) and a lit 3D world (the Stage). This port must play identically and look and sound as close to the web build as a phone allows. Read `docs/PORT.md`, and in the web repo `AGENTS.md`, `docs/ART_DIRECTION.md` and `docs/ARCHITECTURE.md`.

## Rules

1. **No em dashes or en dashes.** Not in code, comments, copy, commits or PRs.
2. **Commit messages read as written by a human.** No AI attribution.
3. **The simulation is a line-for-line port** (`src/game/sim.gd`). It must pass `tests/parity.gd` against the web build's recorded solutions. Never change gameplay here without changing the web build first.
4. **Levels and palettes come from the web build** through `tools/export_levels.ts`. Never hand-edit `assets/data`.
5. **Both worlds, always.** Every thing drawn by one renderer is drawn by the other.
6. **Every input path**: touch, gamepad, keyboard, and the Android back gesture.
7. Typed GDScript, Godot 4.6 (`~/Applications/Godot-4.6/Godot.app/Contents/MacOS/Godot`), Forward Mobile renderer.
8. Never commit keystores, passwords or service account keys.

## Commands

```sh
GODOT=~/Applications/Godot-4.6/Godot.app/Contents/MacOS/Godot
$GODOT --headless --path . --import                       # after adding assets
$GODOT --headless --path . --script tests/parity.gd       # simulation parity with the web build
$GODOT --path . -- --level=overture --mode=2d --x=40 --y=5 --z=3 --shot=/tmp/a.png --frames=60   # screenshot (windowed)
../PerspectiveOpus/node_modules/.bin/tsx tools/export_levels.ts       # re-bake levels and palettes
../PerspectiveOpus/node_modules/.bin/tsx tools/record_solutions.ts    # re-record parity data
```
