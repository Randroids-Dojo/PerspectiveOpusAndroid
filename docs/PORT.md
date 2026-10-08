# How the port is built

Godot 4.6, Forward Mobile, typed GDScript. Landscape. Base UI size 844x390 with `canvas_items` stretch and `expand` aspect.

```
main.tscn          Main (App)            src/app.gd: loop, fixed 120 Hz simulation, camera, renderers, audio
                     Input (InputRouter)  src/core/input_router.gd
                     Stage (Node3D)       src/render3d/  the 3D world
                     Page (CanvasLayer 1) src/render2d/  the 2D page, composited over the stage
                     Audio (Node)         src/audio/
                     UI (CanvasLayer 10)  src/ui/        menus, HUD, touch controls, director
src/game/          level.gd, sim.gd, view.gd, v3.gd   (ports of the web build's src/game)
assets/data/       levels/*.json and palettes.json baked from the web build
tests/parity.gd    replays the web build's recorded solutions (tests/data) and checks every snapshot
tools/             TypeScript tools that run the web build's code (export_levels, record_solutions, ...)
```

## Coordinates

One cell is one unit; x right, y up, z depth with **z = 0 at the front** (nearest the viewer). Godot's camera looks down -Z, so, exactly like the web build, the Stage keeps its world in a node with `scale.z = -1` and builds everything in simulation coordinates inside it. The camera and anything outside that node use `(x, y, -z)`.

## The renderer contract

Both `Stage` and `Page` implement:

```gdscript
func resize(view: View) -> void
func load_level(game: Sim, palette: Dictionary) -> void      # every level start and the title scene
func set_world_visible(v: bool) -> void
func render(game: Sim, view: View, frame: Dictionary) -> void
```

`frame` holds `alpha` (interpolation 0..1 between simulation steps), `dt`, `game_dt`, `now`, `events` (this frame's simulation events, same shapes as the web build's `GameEvent`), `beat` (music beats or -1), `quality` ("low", "medium", "high") and `paused`.

`View` (src/game/view.gd) is the shared camera. `view.stage_pose()` gives the stage camera; `view.world_to_page(x, y)` the page projection in UI pixels (`view.ppu` UI pixels per unit). At `view.swing == 0` they agree, which is what lets `view.wipe` (0 = page covers all, 1 = page fully open) reveal one world over the other through an ink-edged hole centred at `view.wipe_origin`. The page owns the wipe.

Reading the simulation: see the web build's `docs/ARCHITECTURE.md` "Reading the simulation"; the GDScript names are snake_case (`game.player.pos` is a `V3` with 64-bit `x y z`; `game.notes_taken`, `game.gate_vis`, `game.key_vis`, `game.drum_hit`, `game.platforms[i].body`, `game.discords[i]`, `game.level.decor`, ...).

## Development flags

`--level=<id|0..5|title|gallery> --mode=2d|3d --palette=<id> --x= --y= --z= --switch-at=<frame> --shot=<png> --frames=<n>`. Screenshots need a window (not `--headless`); they work on this Mac.
