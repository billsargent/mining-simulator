# Paystreak (working title)

First-person open-world gold prospecting game in **Godot 4.7 / GDScript** (Jolt physics). Design spec: `DESIGN.md` â€” read its "Simplicity rules" before adding any mechanic.

Keep all scenes and resources text-based, and build in code where practical so everything can be changed without the Godot editor.

Work is tracked on GitHub: follow `CONTRIBUTING.md` (labelled issues, sub-issue tables, one PR per feature).

## Running
- `Play.bat` launches the game; `Edit.bat` opens the Godot editor. Both expect Godot 4.7 on PATH as `godot` (or the `GODOT` variable).
- For headless runs and to see printed output on Windows, use the console build `godot_console`. The commands below say `godot`.
- The player's save is `user://save.dat`. Any command-line flag disables saving and loading, so tests never touch it.

## Checks (run after changes)
- Panning balance: `godot --headless --path . --script res://tests/test_pan.gd`
- Gold distribution: `godot --headless --path . --script res://tests/test_deposits.gd`
- Sluice recovery by angle: `godot --headless --path . --script res://tests/test_recovery.gd`
- Whole loop (dig, sluice, cleanout, pan, smelt, sell, order, high banker + pump, carry, save, walk): `godot --headless --path . -- --selftest`
- Save/load round trip: `godot --headless --path . -- --savetest=write`, then `-- --savetest=read`
- Screenshot (needs a window, not headless): `godot --path . -- --shot=<png> [--cam=x,z,yaw,pitch] [--demo] [--pan=fresh|shaken|washing|done] [--dig=N] [--carry=sluice] [--menu]`
  - `--demo` puts the sluice in the creek and sets up the high banker and pump by the cabin. Good camera spots: cabin `--cam=111.2,134.2,-145.4,-6`; equipment `--cam=125,133,-10,-14`.
- Frame rate: `godot --path . -- --fps [--cam=...]`

## M3 additions (big world)
- More checks: `tests/test_world.gd` (generation, roads, `-- --map=<png>` saves the map image), `-- --drivetest`, `-- --savetest=write|writev1|read`.
- Screenshot views: `--view=base|parking|creek|valley|camp|mine`, plus `--time=<hour>`, `--drive=atv|truck`, `--map`, `--lamp`.
- `scripts/world/world_gen.gd` is the single source of truth for the land: rivers, fields, roads, pads; `surface()`/`sample()` are thread-safe. `world_terrain.gd` streams it (quadtree render nodes, 32 m collision tiles, dig tiles), `rivers.gd` builds water ribbons, `scatter.gd` streams grass/colliders, `day_night.gd`, `landmarks.gd`.
- `scripts/vehicles/`: `vehicle.gd` (raycast suspension, cargo slots), `atv.gd`, `truck.gd`. `scripts/ui/map_view.gd`, `compass.gd`.
- Gotcha: fields that are interpolated separately (weight and height) must both be valid past the edge of a band, or blending punches pits (see `_stamp_band`).
- Gotcha: packed arrays passed to functions are copies; write results back to the member.
- The old `valley.gd` / `terrain.gd` are gone; ignore mentions of them below.

## M4 additions (mine)
- `scripts/mine/mine.gd`: carvable rock on a 0.5 m grid (cells: rock, open, two vein kinds), chunked meshes with smooth normals, `chip()`. It sits far below the world; `main.enter_mine()` / `exit_mine()` teleport and switch `day_night.underground`.
- Ore goes in `inv.ore`; `scripts/base/crusher.gd` turns it into a jar to pan. Screenshot inside with `--inmine=adit|vein|junction|lower`.
- Gotcha: with culling off, faces must still be wound toward the open side or they light as back faces.
- `scripts/mine/hazards.gd`: lamp battery, bad air (lower drift, west end), rotten ground (south drift; `mine.fill()` caves it in). All of it obeys `Settings.hazards` (`scripts/core/settings.gd`, stored in `user://settings.cfg`, toggled in the Esc menu; not read or written when any flag is given).
- `scripts/mine/find.gd`: journal, old map, note. Reading one calls `mark_place` on the `"game"` group, which puts the richest spot of a creek (`main.rich_spot`) on the map (`map_view.marks`).
- Specimens (`inv.specimens`) drop now and then from vein chips and sell whole at the ship box. The crusher by hand frees 65% of the gold; the powered one from the order board frees all of it.
- More screenshot views: `--inmine=rot|air|journal|read`, `--powered` (powered crusher at the cabin).

## Code layout
- `scripts/main.gd`: builds the world, spawns machines, save/load, and the test harness flags above.
- `scripts/world/`: `valley.gd` (creek, bars, bench), `terrain.gd` (deformable chunked heightmap with a bedrock floor; `dig`, `flatten`, `restore`), `scatter.gd` (rocks, trees, grass; exclusion zones).
- `scripts/gold/`: `deposit_field.gd` (where the gold is, deterministic by seed), `paydirt.gd` (a shovelful or a jar of concentrate).
- `scripts/panning/`: `pan_sim.gd` (pure simulation, testable headless), `pan_view.gd` (the 3D pan and its controls).
- `scripts/machines/`: `machine.gd` base (carry/place, hopper, riffles, angle knob, save), `sluice.gd`, `high_banker.gd` (auto-hose to nearest pump), `pump.gd`, `recovery.gd` (catch chance by size and angle), `parts.gd` (shared materials and mesh helpers).
- `scripts/base/`: `home_base.gd` (cabin, porch, shed, equipment slots) and stations `wash_tub.gd`, `furnace.gd`, `ship_box.gd`, `order_board.gd`.
- `scripts/player/`: `player.gd`, `inventory.gd` (money, bucket, concentrate jars, vial, nuggets, bars, goals).
- `scripts/ui/`: `hud.gd` (bbcode prompts via `Hud.key("E")`), `pause_menu.gd`. `scripts/core/save_game.gd`.

## Conventions
- Anything the player can use implements `prompt(player) -> String` (bbcode) and `interact(player)`; optional `scroll(player, dir)` and `set_carried(bool)`.
- Machines are found through the `"machines"` group; the order board calls `deliver()` on the `"game"` group.

## Gotchas
- Colors hard-coded in shaders are sRGB; convert with `pow(c, vec3(2.2))` (uniforms with `source_color` convert automatically).
- Scripts use `const X = preload(...)` instead of `class_name`, so headless `--script` runs work without an editor import. Machine subclasses use `extends "res://scripts/machines/machine.gd"`.
- Keep references to nodes that get methods called on them untyped (`var m = ...`) or typed with their preloaded script, not as plain `Node`.
- To change another object's packed array, call a method on that object (e.g. `Paydirt.add_gold`, `Inventory.add_gold`). Appending through a property may not persist.
- In bbcode prompts, write literal brackets as `[lb]`/`[rb]` (`Hud.key()` does this).
- CPUParticles3D ignored vertex colors here; color particles through the material's albedo instead.
