# Paystreak — Design Plan

*Working title. A paystreak is the gold-rich layer just above bedrock.*

First-person, open-world, single-player gold prospecting. Semi-realistic look (no blocky / pixel art). Engine: **Godot 4**.

## Pitch
You inherit your grandfather's run-down cabin and one small claim in a huge mountain wilderness. Read the rivers, test-pan, dig, and run gear to recover gold; haul concentrates home to clean and pour your own bars. Explore abandoned 1800s mines for quartz veins, following old journals toward the lost mine your grandfather never found. Present day, among the ruins of an old gold rush.

## Pillars
1. **Reading the land.** Gold sits where physics puts it. Knowledge is the best upgrade.
2. **Hands-on, not fiddly.** Shovel, pan, chisel, pour: physical and first-person, but every task is short and readable.
3. **A world worth crossing.** Distance matters; vehicles and waypoints make it manageable.
4. **The payoff at home.** A bucket of dirt becomes a gold bar.

## Simplicity rules (hard constraints)
These exist because other mining sims got buried in repetitive setup work (hand-connecting hoses, plumbing pumps).
- **Setup is one action.** Place the high banker, place the pump in the water: the hose connects itself. Pack up is one action. A kit loads onto a vehicle as one item.
- **No plumbing, priming, wiring, or fittings.**
- **No fuel.** Decided in M5 (#28): a tank to top up adds a chore but no decision, since fuel would always be cheap and close at hand. Machines and vehicles just run. Distance already costs time, and that is enough.
- **One knob per machine at most** (e.g., sluice angle) with a clear green/yellow/red indicator.
- **Short tasks.** A pan takes ~15 s. Once you've mastered a task, later gear can automate it.
- **If a step isn't fun or a decision, cut it.**

## Core loop
Scout → test-pan → set up gear → dig and process → haul concentrates home → clean up → smelt (or keep nuggets) → sell → upgrade gear / vehicles / claims → go farther, deeper, bigger.

## Systems
**Gold and geology.** Layers: overburden → gravel → paystreak → bedrock. Gold concentrates at inside bends, behind boulders, below rapids, at the upstream end of gravel bars, in bedrock cracks, and in ancient bench channels on hillsides. Clues: black sand, iron staining, quartz float, old tailings, pyrite. Material is tracked as data (volume plus gold by size class: flour/fines/flakes/pickers/nuggets, black sand, clay, rock). Floods and spring runoff redeposit fine gold.

**Placer methods** (in progression order): panning → sniping/crevicing → sluice → high banker (signature mid-game) → metal detector → dry washer (desert) → dredge → trommel + excavator (endgame).

**Old mines.** Adits, drifts, shafts, stopes, ore carts. A modular kit with procedural vein placement. Chip quartz veins with hammer and chisel → pry bar → rotary hammer → jackhammer. Hazards are fair and signposted: darkness, rotten timbers, shafts, flooded levels, bad air. None of them kill you, and one setting in the Esc menu turns them all off. Rewards: ore, specimen gold, artifacts, and journals and maps that point to other mines.

**Home base.** Cabin and shed grow into a workshop. Cleanup: classify → pan/shaker table → magnet out black sand → dry → weigh. Smelt with crucible, flux and furnace, then pour a bar (natural gold is ~80–92% pure). Choice: smelt, or sell nuggets and specimens to collectors at a premium. Also a garage, fuel, repair bench and trophy shelf. Satellite camps act as spawn and save points.

**World.** A 2×2 km slice → 8×8 km first release, built to grow. Regions: Home Valley, Foothill Benches, Canyon Country, Alpine Creeks, Desert Washes, Old Mining District. Town: store, assay/buyer, claims office, fuel, mechanic. Day/night, weather that changes river levels, seasons.

**Vehicles.** On foot → dirt bike → ATV + trailer → pickup + trailer → UTV → raft/jon boat → mini-excavator (→ helicopter, stretch goal). Load weight affects handling, winch, fording. Gear snaps onto beds and trailers.

**Navigation.** Paper map that fills in as you explore, compass, handheld GPS. Waypoint pins with icons. A sample log puts every test pan on the map as a heat dot. Flagging tape, a vehicle locator. Fast travel only between owned camps (time skip).

**Economy.** Bars (price × weight × purity), nuggets, specimens, artifacts. Claims: public land is pan/snipe only; a claim unlocks digging and motorized gear. Progression axes: Gear, Access, Knowledge. No RPG stats.

**Story (light).** Grandfather's journal + miners' journals → the lost mine. No combat.

## Technical approach
- Godot 4, GDScript, Jolt physics. Scenes and scripts kept as text.
- Terrain: streamed heightmap world; digging deforms local chunks; saves store per-chunk differences only.
- Deposits: deterministic from seed + rules; computed per chunk on demand.
- Material model: containers hold composition; each processor maps input → concentrate + tailings.
- Rivers expose flow speed/depth for sluices and gold deposition.
- Mines: modular kit, separate streamed scenes.

## Milestones
| # | Name | Done when… |
|---|---|---|
| M1 | Color in the pan | Digging a bucket and panning it in a small test valley feels good |
| M2 | Bucket to bar | Sample → sluice/high banker → cleanup → smelt → sell on one river |
| M3 | Go far | ATV + truck/trailer, map + GPS waypoints, 2×2 km world, day/night |
| M4 | Into the dark | One full old mine: chipping, hazards, ore crushing, journals |
| M5 | Make a living | Claims, shop, upgrades, gold price, nuggets vs. smelt, story start |
| M6 | Big country | 8×8 km, all regions, seasons/floods, dredge/trommel/excavator |
| M7 | Polish / Early Access | Performance, saves, tutorial flow, playtesting |
