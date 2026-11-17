# Paystreak

*Working title. A paystreak is the gold-rich layer just above bedrock.*

A first-person, open-world gold prospecting game made with Godot 4. Read the creek, dig down to bedrock, pan for color, run a sluice and a high banker, then clean up your concentrate at the cabin, pour a bar and sell it. The goal is hands-on prospecting without fiddly busywork: setting up gear is one action, and every machine has at most one knob.

See [DESIGN.md](DESIGN.md) for the full plan and roadmap.

## Status

| Milestone | State |
|---|---|
| M1 Color in the pan: digging, gold that sinks to bedrock, panning | Done |
| M2 Bucket to bar: sluice, high banker and pump, cabin cleanup, furnace, selling, saving | Done |
| M3 Go far: 2×2 km world, ATV and pickup, map and waypoints, day and night | In review |
| M4 to M7: old mines, economy and claims, the full world, polish | Planned |

## Running it

1. Install [Godot 4.7](https://godotengine.org/) (the standard build, not .NET).
2. Double-click `Play.bat` (Godot must be on PATH as `godot`, or set the `GODOT` variable), or run `godot --path .` in this folder.

The game saves on its own every minute and when you quit. Esc opens the menu.

## Controls

| Key | Action |
|---|---|
| WASD, Shift, Space | Move, sprint, jump |
| Left mouse | Dig (straight into a nearby running machine, or into your bucket) |
| E | Use / pan at the water's edge |
| F | Pick up or set down equipment |
| Mouse wheel | Adjust a sluice's angle |
| R | Dump your bucket |
| M | Map: left click drops a waypoint, right click removes one |
| L | Headlamp |
| Esc | Menu |

Driving (E on a vehicle to get in): W/S drive, A/D steer, Space brake, V camera, R flip upright, E get out. To haul equipment, carry it to a vehicle and left click.

While panning: hold left mouse to shake (gold sinks), hold right mouse to tilt and wash, move the mouse forward and back to set the tilt, Q to dump the pan.

## Checks

Run headless with the Godot console build:

```
godot --headless --path . --script res://tests/test_pan.gd
godot --headless --path . --script res://tests/test_deposits.gd
godot --headless --path . --script res://tests/test_recovery.gd
godot --headless --path . --script res://tests/test_world.gd
godot --headless --path . -- --selftest
godot --headless --path . -- --drivetest
```

`scripts/main.gd` lists more harness flags (screenshots, frame rate, save round trip).

## Contributing

Work is tracked as GitHub issues and lands through pull requests. See [CONTRIBUTING.md](CONTRIBUTING.md).
