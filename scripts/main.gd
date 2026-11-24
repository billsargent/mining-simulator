extends Node3D
## M3 "Go far": generates the 2×2 km world behind a loading screen, then runs the game:
## streaming around the player, day and night, vehicles, the map and compass, saving, and a
## test harness.
##
## Command-line flags (after `--`) for automated checks. Any flag starts a fresh world and
## turns saving off:
##   --selftest                         run the whole loop headless and print results
##   --savetest=write|writev1|read      save round trip across two runs (v2, or an M2-era save)
##   --shot=<file.png>                  save a screenshot and quit
##   --view=base|creek|valley|camp|mine place the camera at a named spot
##   --cam=x,z,yaw,pitch                or at exact coordinates (degrees)
##   --time=<hour>                      set the time of day
##   --pan=fresh|shaken|washing|done    open the pan in a given state
##   --dig=N                            dig a few holes in front of the camera
##   --demo                             set up the sluice, high banker and pump by Cabin Creek
##   --drive=atv|truck                  sit in a vehicle
##   --carry=sluice|pump|high_banker    carry a machine
##   --menu / --map                     open the Esc menu / the map
##   --fps                              print the frame rate for 8 seconds

const WorldGen = preload("res://scripts/world/world_gen.gd")
const WorldTerrain = preload("res://scripts/world/world_terrain.gd")
const Rivers = preload("res://scripts/world/rivers.gd")
const Scatter = preload("res://scripts/world/scatter.gd")
const Roadside = preload("res://scripts/world/roadside.gd")
const Landmarks = preload("res://scripts/world/landmarks.gd")
const DayNight = preload("res://scripts/world/day_night.gd")
const DepositField = preload("res://scripts/gold/deposit_field.gd")
const PanSim = preload("res://scripts/panning/pan_sim.gd")
const Player = preload("res://scripts/player/player.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const PauseMenu = preload("res://scripts/ui/pause_menu.gd")
const MapView = preload("res://scripts/ui/map_view.gd")
const HomeBase = preload("res://scripts/base/home_base.gd")
const Sluice = preload("res://scripts/machines/sluice.gd")
const HighBanker = preload("res://scripts/machines/high_banker.gd")
const Pump = preload("res://scripts/machines/pump.gd")
const Dredge = preload("res://scripts/machines/dredge.gd")
const DryWasher = preload("res://scripts/machines/dry_washer.gd")
const Atv = preload("res://scripts/vehicles/atv.gd")
const Truck = preload("res://scripts/vehicles/truck.gd")
const Trailer = preload("res://scripts/vehicles/trailer.gd")
const Camp = preload("res://scripts/base/camp.gd")
const Trommel = preload("res://scripts/machines/trommel.gd")
const Garnets = preload("res://scripts/gold/garnets.gd")
const Parts = preload("res://scripts/machines/parts.gd")
const WorkLight = preload("res://scripts/base/work_light.gd")
const Excavator = preload("res://scripts/vehicles/excavator.gd")
const Travel = preload("res://scripts/core/travel.gd")
const Weather = preload("res://scripts/world/weather.gd")
const Wildlife = preload("res://scripts/world/wildlife.gd")
const SaveGame = preload("res://scripts/core/save_game.gd")
const Mine = preload("res://scripts/mine/mine.gd")
const OldShaft = preload("res://scripts/world/old_shaft.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Sfx = preload("res://scripts/core/sfx.gd")
const Paydirt = preload("res://scripts/gold/paydirt.gd")
const Town = preload("res://scripts/world/town.gd")
const Claims = preload("res://scripts/core/claims.gd")
const Inventory = preload("res://scripts/player/inventory.gd")
const Market = preload("res://scripts/core/market.gd")
const Recovery = preload("res://scripts/machines/recovery.gd")
const UpdateCheck = preload("res://scripts/core/update_check.gd")

const MINE_DEPTH := -300.0     # the mine interior sits this far below sea level, out of sight

const SEED := 1849
const AUTOSAVE_SECONDS := 60.0
const MAP_PX := 512

var roadside
var world: WorldGen
var deposits: DepositField
var terrain: WorldTerrain
var scatter: Scatter
var base: HomeBase
var town: Town
var weather: Weather
var wildlife: Wildlife
var player: Player
var hud: Hud
var menu: PauseMenu
var map_view: MapView
var day_night: DayNight
var mine: Mine
var side_mine: Mine            # the small mine under one old shaft; only one is kept at a time
var shafts: Array = []         # OldShaft nodes, by index into world.shafts
var ready_to_play := false

var _opts := {}
var _saving := true
var _failures := 0
var _loading: CanvasLayer
var _loading_label: Label
var _loading_bar: ProgressBar
var _dark := false
var _news_day := -1
var _compass_t := 0.0
var _tutor_t := 5.0          # seconds until the next one-time tip may show
var _tutorial_spot := Vector2.ZERO


func _ready() -> void:
	add_to_group("game")
	_opts = _parse_args()
	_saving = _opts.is_empty()
	Settings.persist = _opts.is_empty()
	Settings.grab_mouse = _opts.is_empty() or _opts.has("mouse")
	if not _opts.is_empty() and not _opts.has("mouse") and not _opts.has("show") and DisplayServer.get_name() != "headless":
		# Test and screenshot runs stay out of the way: off screen and never taking focus.
		get_window().unfocusable = true
		get_window().position = Vector2i(20000, 20000)
	Settings.load_file()
	if _opts.has("quality"):
		Settings.quality = clampi(int(_opts["quality"]), 0, 2)
	if _opts.has("scale"):
		Settings.render_scale = clampf(float(_opts["scale"]), 0.5, 1.0)
	if _opts.has("fps"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_setup_input()
	if _opts.is_empty() and Settings.check_updates:
		var uc := UpdateCheck.new()
		uc.found.connect(_on_update)
		add_child(uc)
		uc.start()
	var sfx := Sfx.new()
	sfx.main = self
	add_child(sfx)
	Settings.apply_audio()
	_show_loading()
	await get_tree().process_frame
	await get_tree().process_frame
	# Generate the world on a worker thread so the window stays responsive.
	world = WorldGen.new(SEED)
	var gen := WorkerThreadPool.add_task(world.generate)
	while not WorkerThreadPool.is_task_completed(gen):
		_loading_label.text = "Building the valley...\n%s" % world.progress
		_loading_bar.value = world.progress_frac * 85.0
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(gen)
	_loading_label.text = "Planting the forests..."
	_loading_bar.value = 92.0
	await get_tree().process_frame
	await get_tree().process_frame
	# From here on, everything is set up within one frame, so nothing falls through the
	# ground before it exists.
	var map_holder := [null]
	var map_task := WorkerThreadPool.add_task(func() -> void: map_holder[0] = world.make_map_image(MAP_PX))
	deposits = DepositField.new(world, SEED)
	_build_environment()
	terrain = WorldTerrain.new()
	add_child(terrain)
	terrain.setup(world)
	scatter = Scatter.new()
	scatter.world = world
	scatter.terrain = terrain
	add_child(scatter)
	scatter.layout()
	base = HomeBase.new()
	add_child(base)
	var site: Dictionary = world.sites["base"]
	var pos: Vector2 = site["pos"]
	var facing: Vector2 = site["facing"]
	base.build(terrain, Vector3(pos.x, 0.0, pos.y), Vector3(facing.x, 0.0, facing.y))
	scatter.build_visuals()
	var rivers := Rivers.new()
	add_child(rivers)
	rivers.build(world)
	var landmarks := Landmarks.new()
	add_child(landmarks)
	landmarks.build(terrain, world.sites)
	roadside = Roadside.new()
	add_child(roadside)
	roadside.build(world, terrain)
	for i in world.shafts.size():
		var sh := OldShaft.new()
		add_child(sh)
		sh.build(i, world.shafts[i])
		shafts.append(sh)
	weather = Weather.new()
	add_child(weather)
	weather.setup(day_night)
	town = Town.new()
	add_child(town)
	town.build(terrain, world.sites["town"])
	Claims.setup(world, deposits)
	_garnet_sign()
	_build_bounds()
	hud = Hud.new()
	add_child(hud)
	player = Player.new()
	player.terrain = terrain
	player.deposits = deposits
	player.hud = hud
	add_child(player)
	wildlife = Wildlife.new()
	add_child(wildlife)
	wildlife.setup(terrain, world, day_night, player)
	menu = PauseMenu.new()
	menu.main = self
	add_child(menu)
	WorkerThreadPool.wait_for_task_completion(map_task)
	map_view = MapView.new()
	add_child(map_view)
	map_view.setup(world, map_holder[0], self)
	var load_test: bool = _opts.get("savetest", "") == "read"
	if _opts.has("savetest"):
		SaveGame.path = "user://loadtest.dat"
	if not ((_saving or load_test) and _load_game()):
		_start_fresh()
	Claims.owned = player.inv.claims
	Claims.finds = player.inv.finds
	_apply_gear()
	_build_near_player()
	_loading.queue_free()
	ready_to_play = true
	if not _opts.is_empty():
		print("Loaded in %d ms, %d detail tiles" % [Time.get_ticks_msec(), world.tiles_built])
	day_night.apply()
	if _saving:
		var timer := Timer.new()
		timer.wait_time = AUTOSAVE_SECONDS
		timer.autostart = true
		timer.timeout.connect(save_now)
		add_child(timer)
	_run_harness()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_now()


func _process(delta: float) -> void:
	if not ready_to_play:
		return
	var f := focus_position()
	terrain.focus = f
	scatter.focus = f
	player.clock = day_night.clock_text()
	Market.day = day_night.day
	if _news_day != Market.day:
		_news_day = Market.day
		if Market.news() != "":
			hud.toast(Market.news() + " (Assay office, Sable Crossing.)", Color(0.95, 0.85, 0.5), 7.0)
	var dark := day_night.is_dark()
	if dark != _dark:
		_dark = dark
		for v in get_tree().get_nodes_in_group("vehicles"):
			v.set_dark(dark)
		if dark and not player.headlamp_on() and player.inv.hints.has("night"):
			hud.toast("It's getting dark. L turns on your headlamp.", Color(1.0, 0.9, 0.6), 5.0)
	_tutor_t -= delta
	if _tutor_t <= 0.0:
		_tutor_t = 0.5
		var tip := tutor_hint()
		if not tip.is_empty() and player.inv.first_hint(tip[0]):
			if tip[0] == "lost_mine":
				var c = roadside.trail[0]
				map_view.add_mark(Vector2(c.global_position.x, c.global_position.z), "Crane's note?")
			hud.toast(tip[1], Color(0.75, 0.95, 1.0), 8.0)
			_tutor_t = 20.0        # one tip at a time, with room to breathe between them
	_track_records(f)
	_compass_t -= delta
	if _compass_t <= 0.0:
		_compass_t = 0.05
		_update_compass()
	if not player.inv.goals_done.has("last_chance"):
		var camp: Vector2 = world.sites["camp"]["pos"]
		if Vector2(f.x, f.z).distance_to(camp) < 60.0:
			player.inv.complete_goal("last_chance")
			hud.toast("Last Chance Camp. Someone worked this creek hard, a long time ago.", Color(1.0, 0.9, 0.6), 6.0)


var _last_pos = null


## Distance walked and driven, and garnets found, for the Records page. Jumps (teleports,
## fast travel, the mine) are not counted.
func _track_records(f: Vector3) -> void:
	player.inv.watch_garnets()
	if _last_pos != null:
		var d: float = Vector2(f.x - _last_pos.x, f.z - _last_pos.z).length()
		if d < 10.0:
			if player.driving != null:
				player.inv.driven += d
			else:
				player.inv.walked += d
	_last_pos = f


## Where the world streams around: the player, or the vehicle they drive.
func focus_position() -> Vector3:
	if player.driving != null:
		return player.driving.global_position
	return player.global_position


## Heading of the active camera in radians, clockwise from north (map up).
func heading() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var fwd := -cam.global_basis.z
	return atan2(fwd.x, -fwd.z)


## The one-time tip that fits this moment, as [id, text], or [] for none. Each shows once
## (inventory `hints`, saved). Text uses keyboard words in parentheses; the toast swaps in pad buttons.
func tutor_hint() -> Array:
	var inv = player.inv
	if player.pan_view != null or hud.note_open():
		return []
	var tips := []
	var k := func(key: String) -> String: return "(%s)" % Settings.prompt_key(key)
	var g: Dictionary = inv.goals_done
	if player.mine == null:
		if g.has("journal"):
			var pick := "LB and RB switch between them" if Settings.using_pad else "1 and 2 or the mouse wheel pick one"
			tips.append(["hotbar", "Your tools are on the bar at the bottom: the shovel and the pan. " + pick + ". %s uses the tool in hand; %s works whatever you look at." % [k.call("Left mouse"), k.call("E")]])
		if not inv.bucket.is_empty():
			tips.append(["inventory", "%s shows what you carry: the bucket, your gold and your latest pan notes." % k.call("Tab")])
		if not inv.pan_notes.is_empty():
			tips.append(["pan_notes", "Every pan leaves a note on where to try next. %s lists the last five." % k.call("Tab")])
		if player._in_water() and inv.bucket.size() >= inv.bucket_capacity():
			tips.append(["water_bucket", "Bucket's full and you're in the water: pan right here %s, or take the pan %s and use %s." % [k.call("E"), "(LB/RB)" if Settings.using_pad else "(2)", k.call("Left mouse")]])
		if day_night.is_dark():
			tips.append(["night", "Night's falling. %s turns on your headlamp. Roads are easier than the woods after dark." % k.call("L")])
		if day_night.storm > 0.3:
			tips.append(["storm", "A storm's rolling in. High water will fill the holes you dug near the creek, so finish up or wait it out in the cabin or a tent."])
		var f := focus_position()
		for sh in world.shafts:
			if Vector2(f.x, f.z).distance_to(sh["pos"]) < 30.0:
				tips.append(["shaft", "An old shaft. %s at the collar climbs down the ladder. It's dark down there: bring your headlamp." % k.call("E")])
				break
		if g.has("sold") and not inv.finds.has("trail_0") and not roadside.trail.is_empty():
			tips.append(["lost_mine", "Folks in town talk about Crane's lost mine. They say the trail starts at an old place near your cabin. It's marked on your map %s." % k.call("M")])
		if g.has("hb_running") and not g.has("claim") and inv.money >= _cheapest_claim():
			tips.append(["claims", "You could afford a claim now. The claims office in town sells ground where your machines can run."])
	for t in tips:
		if not inv.hints.has(t[0]):
			return t
	return []


func _cheapest_claim() -> int:
	var best := 1 << 30
	for c in Claims.list:
		if Claims.known(c) and not Claims.is_owned(c["id"]):
			best = mini(best, int(c["price"]))
	return best


## Where the next goal happens, for the guide marker; null where there is no one place.
func goal_target():
	var id := player.inv.next_goal_id()
	var sluice = machine_of("sluice")
	match id:
		"journal":
			return base.journal.global_position
		"pan", "read_creek":
			if _tutorial_spot == Vector2.ZERO:
				var home: Vector2 = world.sites["base"]["pos"]
				_tutorial_spot = deposits.rich_spot_near("Cabin Creek", home, 220.0)
			return _ground3(_tutorial_spot)
		"sluice_placed":
			if sluice != null and sluice.carried:
				return goal_target_spot()
			return sluice.global_position if sluice != null else null
		"sluice_fed", "cleaned":
			return sluice.global_position if sluice != null else null
		"cons_panned":
			return base.wash_tub.global_position
		"smelted":
			return base.furnace.global_position
		"drive":
			var atv = vehicle_of("atv")
			return atv.global_position if atv != null else null
		"sold":
			return town.assay.global_position
		"high_banker":
			return town.store.global_position
		"hb_running":
			var hb = machine_of("high_banker")
			return hb.global_position if hb != null else null
		"last_chance":
			return _ground3(world.sites["camp"]["pos"])
		"mine_enter":
			return _ground3(world.sites["mine"]["pos"])
		"crushed":
			return base.crusher.global_position
		"claim", "ledge":
			return town.claims_office.global_position
		"ledge_gold":
			return _ground3(Claims.by_id("ledge")["pos"])
	return null


## The bar the tutorial sends you to (also where the sluice goes first).
func goal_target_spot() -> Vector3:
	if _tutorial_spot == Vector2.ZERO:
		_tutorial_spot = deposits.rich_spot_near("Cabin Creek", world.sites["base"]["pos"], 220.0)
	return _ground3(_tutorial_spot)


func _ground3(p: Vector2) -> Vector3:
	return Vector3(p.x, terrain.height_at(p.x, p.y), p.y)


func _update_compass() -> void:
	var markers := []
	var goal = goal_target() if player.mine == null else null
	hud.set_guide(goal, get_viewport().get_camera_3d())
	if goal != null:
		markers.append([Vector2(goal.x, goal.z), Color(0.45, 1.0, 0.5), "Next"])
	for i in map_view.waypoints.size():
		markers.append([map_view.waypoints[i], Color(1.0, 0.85, 0.2), str(i + 1)])
	markers.append([world.sites["base"]["pos"], Color(1.0, 0.55, 0.25), "Home"])
	markers.append([world.sites["town"]["pos"], Color(0.75, 0.7, 1.0), "Town"])
	for m in get_tree().get_nodes_in_group("machines"):
		if m.kind == "camp" and not m.carried and m.loaded_on == null:
			markers.append([Vector2(m.global_position.x, m.global_position.z), Color(0.6, 0.9, 0.5), m.camp_name()])
	for m in map_view.marks:
		markers.append([m[0], Color(1.0, 0.45, 0.35), m[1]])
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v != player.driving:
			markers.append([Vector2(v.global_position.x, v.global_position.z), Color(0.5, 0.75, 1.0), v.display_name])
	var f := focus_position()
	hud.compass.update_view(heading(), Vector2(f.x, f.z), markers)


## The mine interior is built the first time it's needed.
func _ensure_mine(carved: PackedInt32Array = PackedInt32Array(), collapsed: bool = false) -> void:
	if mine != null:
		return
	var site: Vector2 = world.sites["mine"]["pos"]
	mine = Mine.new()
	add_child(mine)
	mine.global_position = Vector3(site.x - 2.0, MINE_DEPTH, site.y - 30.0)
	mine.build(carved, collapsed)


func enter_mine() -> void:
	_ensure_mine()
	player.global_position = mine.spawn_point()
	player.rotation = Vector3(0.0, mine.spawn_yaw(), 0.0)
	player.velocity = Vector3.ZERO
	player.mine = mine
	day_night.underground = true
	day_night.apply()
	if not player.headlamp_on():
		player.set_headlamp(true)
	if player.inv.complete_goal("mine_enter"):
		hud.toast("Dark and cold. White quartz veins in the walls can carry gold: chip them with left mouse.", Color(1.0, 0.9, 0.6), 7.0)


## Climb down an old shaft into its small mine. Its rock is built fresh each time (digging in
## the side mines is not saved), and only one side mine exists at a time.
func enter_shaft(i: int) -> void:
	var data: Dictionary = world.shafts[i]
	if side_mine == null or side_mine.shaft_id != data["id"]:
		if side_mine != null:
			side_mine.queue_free()
		side_mine = Mine.new()
		side_mine.layout = "shaft"
		side_mine.layout_seed = data["seed"]
		side_mine.shaft_id = data["id"]
		add_child(side_mine)
		var p: Vector2 = data["pos"]
		side_mine.global_position = Vector3(p.x - 4.0, MINE_DEPTH - 60.0, p.y - 15.0)
		side_mine.build()
	player.global_position = side_mine.spawn_point()
	player.rotation = Vector3(0.0, side_mine.spawn_yaw(), 0.0)
	player.velocity = Vector3.ZERO
	player.mine = side_mine
	day_night.underground = true
	day_night.apply()
	if not player.headlamp_on():
		player.set_headlamp(true)
	hud.toast("Down the ladder. Old drifts, and white quartz in the walls.", Color(1.0, 0.9, 0.6), 4.0)


## The shaft the player is under, if they are in a side mine.
func _current_shaft():
	if player.mine == null or player.mine != side_mine:
		return null
	for sh in shafts:
		if world.shafts[sh.index]["id"] == side_mine.shaft_id:
			return sh
	return null


func exit_mine() -> void:
	var sh = _current_shaft()
	if sh != null:
		var ep: Vector3 = sh.exit_point()
		player.global_position = Vector3(ep.x, terrain.height_at(ep.x, ep.z) + 0.1, ep.z)
		player.rotation = Vector3(0.0, sh.exit_yaw(), 0.0)
		_left_underground()
		return
	var site: Dictionary = world.sites["mine"]
	var pos: Vector2 = (site["pos"] as Vector2) + (site["facing"] as Vector2) * 3.5
	var facing: Vector2 = site["facing"]
	player.global_position = Vector3(pos.x, terrain.height_at(pos.x, pos.y) + 0.1, pos.y)
	player.rotation = Vector3(0.0, atan2(-facing.x, -facing.y), 0.0)
	_left_underground()


func _left_underground() -> void:
	player.velocity = Vector3.ZERO
	player.mine = null
	day_night.underground = false
	day_night.apply()
	hud.set_shade(0.0)
	hud.hide_note()
	player.air = 1.0
	if player.lamp_charge < 0.9 and Settings.hazards:
		hud.toast("You swap fresh batteries into your headlamp.", Color(1.0, 0.9, 0.6), 4.0)
	player.lamp_charge = 1.0
	player.apply_lamp()


## Bad air got you: you wake up at the mouth of the adit an hour later, nothing lost.
func rescue_from_mine(message: String) -> void:
	player.global_position = mine.spawn_point()
	player.rotation = Vector3(0.0, mine.spawn_yaw() + PI, 0.0)
	player.velocity = Vector3.ZERO
	day_night.hours += 1.0
	hud.set_shade(0.0)
	hud.blackout(4.0)
	hud.toast(message, Color(1.0, 0.6, 0.35), 8.0)


## A journal or an old map points at a place: "site:<name>", or the richest ground on a creek.
func mark_place(where: String, label: String) -> void:
	if where.begins_with("site:"):
		map_view.add_mark(world.sites[where.substr(5)]["pos"], label)
	elif where.begins_with("pos:"):
		var xy := where.substr(4).split(",")
		map_view.add_mark(Vector2(float(xy[0]), float(xy[1])), label)
	else:
		map_view.add_mark(rich_spot(where), label)


func rich_spot(river_name: String) -> Vector2:
	return deposits.rich_spot(river_name)


## Travel to a place you own. Time passes with the distance; a vehicle you stand next to comes
## along (with its trailer and cargo).
func fast_travel(dest: Vector3, place: String) -> void:
	var from := player.global_position
	var hours := Travel.hours_for(from, dest)
	var bring = null
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v.kind != "trailer" and v.global_position.distance_to(from) < Travel.BRING_VEHICLE:
			if bring == null or v.global_position.distance_to(from) < bring.global_position.distance_to(from):
				bring = v
	var ground := Vector3(dest.x, terrain.height_at(dest.x, dest.z) + 0.1, dest.z)
	player.global_position = ground
	player.velocity = Vector3.ZERO
	terrain.focus = ground
	scatter.focus = ground
	_build_near_player()
	if bring != null:
		var trailer = null
		for v in get_tree().get_nodes_in_group("vehicles"):
			if v.kind == "trailer" and v.towed_by == bring:
				trailer = v
				v.unhitch()
		var spot := ground + Vector3(4.0, 0.0, 0.0)
		spot.y = terrain.height_at(spot.x, spot.z) + 0.3
		bring.freeze = true
		bring.global_transform = Transform3D(Basis(Vector3.UP, player.rotation.y), spot)
		if trailer != null:
			trailer.freeze = true
			trailer.hitch(bring)
	day_night.advance(hours)
	map_view.reveal_around(ground)
	save_now()
	hud.blackout(1.5)
	hud.toast("You travel to %s. %s later.%s" % [place, Travel._hours_text(hours).replace("min", "minutes"),
		(" The %s came along." % str(bring.display_name).to_lower()) if bring != null else ""], Color(1.0, 0.9, 0.6), 5.0)


## A storm has passed: the creeks ran high and refilled the holes on the bars and banks.
func flood() -> void:
	var n := terrain.flood()
	if n > 0:
		hud.toast("The creeks ran high in the storm. Fresh gravel has washed back onto the bars you worked.", Color(0.75, 0.85, 1.0), 7.0)
	else:
		hud.toast("The creeks ran high in the storm and dropped fresh gravel on the bars.", Color(0.75, 0.85, 1.0), 6.0)


func sleep() -> void:
	day_night.sleep_until_morning()
	save_now()
	hud.toast("You slept until morning. (Game saved.)", Color(1.0, 0.9, 0.6), 4.0)


# --- World setup -------------------------------------------------------------------

func _show_loading() -> void:
	_loading = CanvasLayer.new()
	_loading.layer = 20
	add_child(_loading)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	_loading_label = Label.new()
	_loading_label.text = "Building the valley..."
	_loading_label.add_theme_font_size_override("font_size", 28)
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(_loading_label)
	_loading_bar = ProgressBar.new()
	_loading_bar.show_percentage = false
	_loading_bar.anchor_left = 0.3
	_loading_bar.anchor_right = 0.7
	_loading_bar.anchor_top = 0.62
	_loading_bar.anchor_bottom = 0.62
	_loading_bar.offset_bottom = 14.0
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.2, 0.22, 0.2)
	bg_style.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.68, 0.25)
	fill.set_corner_radius_all(4)
	_loading_bar.add_theme_stylebox_override("background", bg_style)
	_loading_bar.add_theme_stylebox_override("fill", fill)
	_loading.add_child(_loading_bar)


func _start_fresh() -> void:
	var sluice = spawn_machine("sluice")
	sluice.place_at(base.slot_position(0), base.slot_yaw())
	spawn_vehicle("atv").global_transform = _parked(0)
	spawn_vehicle("truck").global_transform = _parked(1)
	player.global_position = base.spawn_point
	player.rotation.y = base.spawn_yaw
	# Grandpa's old map already covers the home valley.
	var home: Vector2 = world.sites["base"]["pos"]
	for off in [Vector2.ZERO, Vector2(0, -250), Vector2(0, -450), Vector2(-200, -350), Vector2(200, -350)]:
		map_view.reveal_around(Vector3(home.x + off.x, 0.0, home.y + off.y))
	# ... and the road to town.
	var town_pos: Vector2 = world.sites["town"]["pos"]
	for k in 7:
		var q := home.lerp(town_pos, k / 6.0)
		map_view.reveal_around(Vector3(q.x, 0.0, q.y))
	hud.toast("Grandpa's claim on Cabin Creek. Your next step is in the top-left corner; the green marker shows where.", Color(1.0, 0.9, 0.6), 8.0)


func _parked(i: int) -> Transform3D:
	var t := base.parking(i)
	t.origin.y = terrain.height_at(t.origin.x, t.origin.z) + 0.12
	return t


func _build_near_player() -> void:
	var f := focus_position()
	terrain.focus = f
	scatter.focus = f
	terrain.build_now()
	scatter.build_near_now()


## A painted sign up the bank from Garnet Beach.
func _garnet_sign() -> void:
	var b := Garnets.beach
	var spot := b
	for k in 16:
		var a := TAU * k / 16.0
		var p := b + Vector2(cos(a), sin(a)) * 9.0
		var e: float = world.river_info(p.x, p.y).x
		if e > 4.0 and e < 14.0:
			spot = p
			break
	var sign := StaticBody3D.new()
	add_child(sign)
	sign.global_position = Vector3(spot.x, terrain.height_at(spot.x, spot.y), spot.y)
	sign.rotation.y = atan2(b.x - spot.x, b.y - spot.y) + PI
	var wood := Parts.wood("sign_post", Color(0.45, 0.33, 0.22))
	for s: float in [-0.6, 0.6]:
		Parts.box(sign, Vector3(0.1, 1.9, 0.1), Vector3(s, 0.95, 0), wood)
	Parts.box(sign, Vector3(1.6, 0.55, 0.05), Vector3(0, 1.55, 0), Parts.wood("sign_board", Color(0.5, 0.38, 0.26)))
	var l := Parts.label(sign, "GARNET BEACH", Vector3(0, 1.6, 0.03), 34)
	l.modulate = Color(0.55, 0.05, 0.1)
	var l2 := Parts.label(sign, "sieve & flip", Vector3(0, 1.42, 0.03), 22)
	l2.modulate = Color(0.2, 0.15, 0.1)
	Parts.collider(sign, Vector3(1.6, 1.9, 0.12), Vector3(0, 0.95, 0))


func spawn_machine(kind: String):
	var m
	match kind:
		"sluice":
			m = Sluice.new()
		"high_banker":
			m = HighBanker.new()
		"pump":
			m = Pump.new()
		"dredge":
			m = Dredge.new()
		"dry_washer":
			m = DryWasher.new()
		"camp":
			m = Camp.new()
		"trommel":
			m = Trommel.new()
		"light_lantern", "light_flood", "light_tower":
			m = WorkLight.new()
			m.set_size(kind.trim_prefix("light_"))
		_:
			return null
	add_child(m)
	m.setup(terrain)
	return m


func spawn_vehicle(kind: String):
	var v
	match kind:
		"atv":
			v = Atv.new()
		"truck":
			v = Truck.new()
		"trailer":
			v = Trailer.new()
		"excavator":
			v = Excavator.new()
		_:
			return null
	add_child(v)
	v.setup(terrain)
	v.set_dark(_dark)
	return v


func machine_of(kind: String):
	for m in get_tree().get_nodes_in_group("machines"):
		if m.kind == kind:
			return m
	return null


func vehicle_of(kind: String):
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v.kind == kind:
			return v
	return null


## Called by the order board.
func deliver(item: String) -> void:
	if item == "high_banker":
		spawn_machine("high_banker").place_at(base.slot_position(1), base.slot_yaw())
		spawn_machine("pump").place_at(base.slot_position(2), base.slot_yaw())
	elif item == "trommel":
		spawn_machine("trommel").place_at(base.to_global(Vector3(-9.0, 0.0, 6.5)), base.slot_yaw())
	elif item == "excavator":
		var t := _parked(0)
		t.origin += t.basis.x * 6.0
		spawn_vehicle("excavator").global_transform = t
	elif item in ["lantern", "flood", "tower"]:
		var n := get_tree().get_nodes_in_group("machines").filter(func(mm): return mm.kind == "light_" + item).size()
		var spot: Vector3 = {"lantern": Vector3(-3.0 - 0.6 * n, 0.0, 3.6), "flood": Vector3(-5.0 - 1.2 * n, 0.0, 5.0),
			"tower": Vector3(-14.0 - 4.0 * n, 0.0, 8.0)}[item]
		spawn_machine("light_" + item).place_at(base.to_global(spot), base.slot_yaw())
	elif item == "camp":
		var tent = spawn_machine("camp")
		var n := 0
		for m in get_tree().get_nodes_in_group("machines"):
			if m.kind == "camp":
				n += 1
		tent.number = n
		tent.place_at(base.to_global(Vector3(-13.0 - 3.5 * n, 0.0, 1.0)), base.slot_yaw())
	elif item == "trailer":
		var t := _parked(1)
		t.origin += t.basis.z * 6.5
		spawn_vehicle("trailer").global_transform = t
	elif item == "dry_washer":
		spawn_machine("dry_washer").place_at(base.to_global(Vector3(-10.8, 0.0, 2.0)), base.slot_yaw())
	elif item == "dredge":
		spawn_machine("dredge").place_at(base.to_global(Vector3(-8.0, 0.0, 2.2)), base.slot_yaw())
	elif item == "crusher":
		base.crusher.set_powered(true)
	_apply_gear()


## Things the player owns that change how the machines work.
func _apply_gear() -> void:
	Recovery.carpet_bonus = 0.12 if player.inv.gear.has("moss") else 0.0
	player.set_bright_lamp(player.inv.gear.has("headlamp"))


func _setup_input() -> void:
	_bind_key("toggle_mouse", KEY_ESCAPE)
	if not InputMap.has_action("dig"):
		InputMap.add_action("dig")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("dig", mb)
	if not InputMap.has_action("scoop"):
		InputMap.add_action("scoop")       # the excavator's bucket: left mouse, or Y on the controller
		var smb := InputEventMouseButton.new()
		smb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("scoop", smb)
	Settings.apply_binds()     # keys, then the controller buttons on every action


func _bind_key(action: StringName, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.fog_enabled = true
	env.fog_density = 0.0016
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.05
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-50.0, 40.0, 0.0)
	moon.light_color = Color(0.55, 0.62, 0.85)
	moon.shadow_enabled = false
	add_child(moon)
	day_night = DayNight.new()
	day_night.env = env
	day_night.sky_mat = sky_mat
	day_night.sun = sun
	day_night.moon = moon
	add_child(day_night)
	day_night.apply()
	Settings.attach(env, sun)
	Settings.apply_graphics(get_tree())


## Invisible walls at the edge of the world.
func _build_bounds() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var s := WorldGen.SIZE
	for w in [[Vector3(s * 0.5, 150.0, 0.5), Vector3(s, 600.0, 1.0)], [Vector3(s * 0.5, 150.0, s - 0.5), Vector3(s, 600.0, 1.0)],
			[Vector3(0.5, 150.0, s * 0.5), Vector3(1.0, 600.0, s)], [Vector3(s - 0.5, 150.0, s * 0.5), Vector3(1.0, 600.0, s)]]:
		var box := BoxShape3D.new()
		box.size = w[1]
		var cs := CollisionShape3D.new()
		cs.shape = box
		cs.position = w[0]
		body.add_child(cs)


# --- Saving ------------------------------------------------------------------------

func save_now() -> void:
	if not _saving or not ready_to_play:
		return
	SaveGame.write(_collect_save())


func _collect_save() -> Dictionary:
	var inv_data: Dictionary = player.inv.to_dict()
	var pending := player.pending_pan()
	if not pending.is_empty():
		(inv_data[pending[0]] as Array).push_front(pending[1].to_dict())
	var vehicles := get_tree().get_nodes_in_group("vehicles")
	var vdata := []
	for v in vehicles:
		vdata.append(v.to_dict())
	var machines := []
	for m in get_tree().get_nodes_in_group("machines"):
		var d: Dictionary = m.to_dict()
		if m.loaded_on != null:
			d["vehicle"] = vehicles.find(m.loaded_on)
			d["slot"] = m.loaded_on.cargo.find(m)
		machines.append(d)
	var ppos := player.global_position
	if player.driving != null:
		ppos = player.driving.to_global(player.driving.exit_offset)
		ppos.y = terrain.height_at(ppos.x, ppos.z) + 0.1
	var under_shaft = _current_shaft()
	if under_shaft != null:
		# Side mines are not saved: a save made down a shaft loads at its collar.
		ppos = under_shaft.exit_point()
		ppos.y = terrain.height_at(ppos.x, ppos.z) + 0.1
	return {
		"player": {"pos": ppos, "yaw": player.rotation.y, "headlamp": player.headlamp_on(), "in_mine": player.mine != null and under_shaft == null,
			"lamp": player.lamp_charge},
		"mine": {"carved": mine.carved if mine != null else PackedInt32Array(), "collapsed": mine != null and mine.hazards.collapsed},
		"inventory": inv_data,
		"digs": terrain.dig_data(),
		"machines": machines,
		"vehicles": vdata,
		"furnace": base.furnace.to_dict(),
		"time": {"hours": day_night.hours, "day": day_night.day, "weather_checked": weather.checked},
		"map": map_view.save_state(),
	}


func _load_game() -> bool:
	var data := SaveGame.read()
	if data.is_empty():
		return false
	if int(data.get("version", 0)) == 1:
		return _migrate_v1(data)
	terrain.restore_digs(data.get("digs", {}))
	var vehicles := []
	for vd in data.get("vehicles", []):
		var v = spawn_vehicle(vd.get("kind", ""))
		if v != null:
			v.from_dict(vd)
		vehicles.append(v)
	for md in data.get("machines", []):
		var m = spawn_machine(md.get("kind", ""))
		if m == null:
			continue
		m.from_dict(md)
		var vi: int = md.get("vehicle", -1)
		if vi >= 0 and vi < vehicles.size() and vehicles[vi] != null:
			vehicles[vi].load_cargo(m, md.get("slot", -1))
	player.inv.from_dict(data.get("inventory", {}))
	base.crusher.set_powered(player.inv.crusher_powered)
	base.furnace.from_dict(data.get("furnace", {}))
	var time: Dictionary = data.get("time", {})
	day_night.hours = time.get("hours", 8.0)
	day_night.day = time.get("day", 1)
	weather.checked = time.get("weather_checked", -1.0)
	map_view.load_state(data.get("map", {}))
	var p: Dictionary = data.get("player", {})
	player.global_position = p.get("pos", base.spawn_point)
	player.rotation.y = p.get("yaw", base.spawn_yaw)
	player.set_headlamp(p.get("headlamp", false))
	var carved: PackedInt32Array = data.get("mine", {}).get("carved", PackedInt32Array())
	player.lamp_charge = p.get("lamp", 1.0)
	var collapsed: bool = data.get("mine", {}).get("collapsed", false)
	if p.get("in_mine", false) or not carved.is_empty() or collapsed:
		_ensure_mine(carved, collapsed)
	if p.get("in_mine", false):
		player.mine = mine
		day_night.underground = true
	player.refresh_hud()
	hud.toast("Welcome back.", Color(1.0, 0.9, 0.6))
	return true


## Saves from M2 were made in the old test valley. Bring the player's progress into the new world.
func _migrate_v1(data: Dictionary) -> bool:
	_start_fresh()
	player.inv.from_dict(data.get("inventory", {}))
	if player.inv.high_banker_bought:
		deliver("high_banker")
	player.refresh_hud()
	hud.toast("The valley has grown! Your money, gold, bars and gear came with you.", Color(1.0, 0.9, 0.6), 8.0)
	return true


func new_game() -> void:
	_saving = false
	SaveGame.delete()
	get_tree().paused = false
	get_tree().reload_current_scene()


## The update check found a newer release. The world may still be loading; wait for the HUD.
func _on_update(tag: String, url: String) -> void:
	while hud == null or menu == null:
		await get_tree().create_timer(1.0).timeout
	menu.show_update(tag, url)
	hud.toast("A new version of Paystreak is out (%s). Esc menu has the link." % tag, Color(0.75, 1.0, 0.7), 8.0)


# --- Test harness ------------------------------------------------------------------

func _parse_args() -> Dictionary:
	var opts := {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else ""
	return opts


func _run_harness() -> void:
	if _opts.is_empty():
		return
	if _opts.has("time"):
		day_night.hours = float(_opts["time"])
		day_night.apply()
	if _opts.has("storm"):
		var sd := 2
		while not Weather.storm_day(sd):
			sd += 1
		day_night.day = sd
		day_night.hours = 16.0
		weather.checked = weather.now()
	if _opts.has("demo"):
		_demo_setup()
	_apply_view()
	if _opts.has("selftest"):
		await _selftest()
		get_tree().quit()
		return
	if _opts.has("savetest"):
		await _savetest(_opts["savetest"])
		get_tree().quit()
		return
	if _opts.has("drivetest"):
		await _drivetest()
		get_tree().quit()
		return
	if _opts.has("fps"):
		for sample in 4:
			await get_tree().create_timer(2.0).timeout
			print("FPS after %ds: %d   (%s)" % [(sample + 1) * 2, Engine.get_frames_per_second(), RenderingServer.get_video_adapter_name()])
		get_tree().quit()
		return
	if _opts.has("shot"):
		if _opts.has("drive"):
			vehicle_of(_opts["drive"]).enter(player)
		for i in 90:
			await get_tree().process_frame
		_apply_view()
		if _opts.has("dig"):
			var fwd := -player.global_basis.z
			for spot in 3:
				var p := player.global_position + fwd * (2.2 + spot * 1.4) + player.global_basis.x * (spot - 1) * 1.2
				for i in int(_opts["dig"]) - spot * 2:
					terrain.dig(p, Player.DIG_DEPTH, Player.DIG_RADIUS)
		if _opts.has("pan"):
			player.debug_pan(_opts["pan"])
		if _opts.has("carry"):
			player.start_carry(machine_of(_opts["carry"]))
		if _opts.has("map"):
			var pp := player.global_position
			for k in 12:
				player.inv.log_sample(pp.x + 40.0 + k * 9.0, pp.z - 60.0 - k * 14.0, [0.0, 0.004, 0.02, 0.06, 0.15, 0.3][k % 6])
			map_view.reveal_around(player.global_position + Vector3(300, 0, 0))
			map_view.reveal_around(player.global_position + Vector3(-300, 0, -300))
			map_view.add_waypoint(Vector2(player.global_position.x + 250.0, player.global_position.z - 120.0))
			map_view.toggle()
		if _opts.has("lamp"):
			player.set_headlamp(true)
		if _opts.get("inmine", "") == "shaft":
			enter_shaft(0)
		elif _opts.has("inmine"):
			enter_mine()
			var spots := {"adit": [Vector3(8, 8.1, 30), -90.0], "vein": [Vector3(40.5, 8.1, 30), -70.0],
				"junction": [Vector3(28, 8.1, 30), -90.0], "lower": [Vector3(63.5, 1.6, 22), 20.0],
				"rot": [Vector3(37.6, 8.1, 46.2), -100.0], "air": [Vector3(60.5, 1.6, 15.7), 90.0],
				"journal": [Vector3(34.9, 8.1, 8.9), -36.0], "read": [Vector3(34.9, 8.1, 8.9), -36.0]}
			var s: Array = spots.get(_opts["inmine"], spots["adit"])
			player.global_position = mine.to_global(s[0])
			player.rotation.y = deg_to_rad(s[1])
			player.camera.rotation.x = -0.25 if _opts["inmine"] in ["journal", "read"] else 0.0
			if _opts["inmine"] == "read":
				for ch in mine.get_children():
					if ch is Mine.Find and ch.kind == "journal":
						ch.interact(player)
		if _opts.has("powered"):
			deliver("crusher")
			var cp: Vector3 = base.crusher.global_position
			var from: Vector3 = cp + base.global_basis.z * 2.4 + base.global_basis.x * 0.8
			_place_player(from, atan2(from.x - cp.x, from.z - cp.z), -0.3)
		if _opts.has("menu") or _opts.has("settings") or _opts.has("records"):
			menu.open()
			if _opts.has("settings"):
				menu._open_settings()
			if _opts.has("records"):
				menu._open_records()
		for i in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(_opts["shot"])
		print("Saved screenshot: ", _opts["shot"])
		get_tree().quit()


func _apply_view() -> void:
	if _opts.has("cam"):
		var c := (_opts["cam"] as String).split_floats(",")
		_place_player(Vector3(c[0], 0.0, c[1]), deg_to_rad(c[2]), deg_to_rad(c[3]))
	elif _opts.has("region"):
		var reg: Array = WorldGen.REGIONS[int(_opts["region"])]
		var rc: Vector2 = (reg[1] as Vector2) * WorldGen.LAYOUT
		_place_player(Vector3(rc.x, 0.0, rc.y), deg_to_rad(float(_opts.get("yaw", "0"))), deg_to_rad(-4.0))
		player.global_position.y += 25.0     # a look from above the ground
	elif _opts.has("view"):
		var from := Vector3.ZERO
		var at := Vector3.ZERO
		var vname: String = _opts["view"]
		if vname.begins_with("place_"):
			# --view=place_<kind>, e.g. place_ruin_cabin, place_sign: the first place of that kind.
			for pl in world.places:
				if pl["kind"] == vname.substr(6):
					var pp: Vector2 = pl["pos"]
					var rp: Vector2 = pl["road"]
					var back := pp + (rp - pp).normalized() * 11.0 + (rp - pp).normalized().orthogonal() * 4.0
					from = Vector3(back.x, 0.0, back.y)
					at = Vector3(pp.x, terrain.height_at(pp.x, pp.y) + 1.0, pp.y)
					break
		match _opts["view"]:
			"base":
				from = base.to_global(Vector3(-3.0, 0.0, 15.0))
				at = base.to_global(Vector3(0.0, 1.5, -1.0))
			"garnet":
				# On Garnet Beach with a sieve just flipped, garnets on top.
				var gb := Garnets.beach
				var dry := gb
				for k in 16:
					var a := TAU * k / 16.0
					var p := gb + Vector2(cos(a), sin(a)) * 3.0
					if world.river_info(p.x, p.y).x > 1.0:
						dry = p
						break
				from = Vector3(dry.x, 0.0, dry.y)
				at = Vector3(gb.x + (gb.x - dry.x) * 3.0, terrain.height_at(gb.x, gb.y) - 0.5, gb.y + (gb.y - dry.y) * 3.0)
				player.inv.gear["sieve"] = true
				player._sieve_step()
				player._sieve_phase = 3
				player._sieve_t = 1.0e6
				player._sieve.rotation.z = PI
				player._sieve_found = [1.4, 0.5, 2.6, 0.35]
				player._show_garnets()
			"parking":
				from = base.to_global(Vector3(2.0, 0.0, 16.0))
				at = base.to_global(Vector3(1.0, 0.5, 3.5))
			"atv", "truck", "atv_back", "truck_back":
				# A vehicle up close, from the front quarter (or the back quarter).
				for v in get_tree().get_nodes_in_group("vehicles"):
					if v.kind == vname.trim_suffix("_back"):
						var near := 3.2 if v.kind == "atv" else 6.5
						var dir := Vector3(0.8, 0.0, 1.0 if vname.ends_with("_back") else -1.0).normalized()
						from = v.to_global(dir * near)
						at = v.to_global(Vector3(0, 0.6, 0))
			"creek":
				var p := world.river_point("Cabin Creek", 0.6, 2.6)
				var q := world.river_point("Cabin Creek", 0.66, 0.0)
				from = Vector3(p.x, 0.0, p.y)
				at = Vector3(q.x, terrain.height_at(q.x, q.y), q.y)
			"gear":
				# With --demo: the sluice, pump and high banker up close.
				var hb: Vector3 = machine_of("high_banker").global_position
				var pu: Vector3 = machine_of("pump").global_position
				var side := Vector3(pu.z - hb.z, 0.0, hb.x - pu.x).normalized()
				from = hb + (pu - hb).normalized() * 1.2 + side * 2.6
				at = hb + Vector3(0.0, 0.5, 0.0)
			"valley":
				var p := world.river_point("Big Sable River", 0.36, 14.0)
				var q := world.river_point("Big Sable River", 0.44, 0.0)
				from = Vector3(p.x, 0.0, p.y)
				at = Vector3(q.x, terrain.height_at(q.x, q.y) - 15.0, q.y)
			"town":
				from = town.to_global(Vector3(6.0, 0.0, 17.0))
				at = town.to_global(Vector3(-2.0, 2.0, -3.0))
			"store":
				from = town.to_global(Vector3(-7.4, 0.0, 0.2))
				at = town.to_global(Vector3(-7.9, 1.5, -3.0))
			"claims":
				from = town.to_global(Vector3(10.2, 0.0, 0.2))
				at = town.to_global(Vector3(10.6, 1.5, -3.0))
			"assay":
				from = town.to_global(Vector3(1.0, 0.0, 0.6))
				at = town.to_global(Vector3(1.4, 1.1, -2.4))
			"dredge":
				var d = machine_of("dredge")
				if d == null:
					d = spawn_machine("dredge")
				var dp := world.river_point("Big Sable River", 0.5, 0.3)
				d.place_at(Vector3(dp.x, 0.0, dp.y), 0.4)
				var p := world.river_point("Big Sable River", 0.503, 1.15)
				from = Vector3(p.x, 0.0, p.y)
				at = d.global_position
			"wash":
				var p := world.river_point("Coyote Wash", 0.5, 4.0)
				var q := world.river_point("Coyote Wash", 0.56, 0.0)
				from = Vector3(p.x, 0.0, p.y)
				at = Vector3(q.x, terrain.height_at(q.x, q.y), q.y)
				var dwp := world.river_point("Coyote Wash", 0.505, 1.6)
				var dwm = spawn_machine("dry_washer")
				dwm.place_at(Vector3(dwp.x, 0.0, dwp.y), 0.6)
				from = Vector3(dwp.x, 0.0, dwp.y) + Vector3(2.5, 0.0, 2.5)
				at = dwm.global_position + Vector3(0, 0.6, 0)
			"trailer":
				if vehicle_of("trailer") == null:
					deliver("trailer")
				var tk = vehicle_of("truck")
				var tl = vehicle_of("trailer")
				if tl.towed_by == null:
					tl.hitch(tk)
				from = tk.to_global(Vector3(-6.5, 0.0, 6.0))
				at = tl.global_position + Vector3(0, 0.8, 0)
			"tent":
				var tents := get_tree().get_nodes_in_group("machines").filter(func(mm): return mm.kind == "camp")
				if tents.is_empty():
					deliver("camp")
					tents = get_tree().get_nodes_in_group("machines").filter(func(mm): return mm.kind == "camp")
				var tp := world.river_point("Willow Creek", 0.5, 6.0)
				tents[0].place_at(Vector3(tp.x, 0.0, tp.y), 0.5)
				from = tents[0].to_global(Vector3(2.5, 0.0, 5.5))
				at = tents[0].global_position + Vector3(0, 0.7, 0)
			"lights":
				# Every kind of light, plus the pickup's headlights left on (use with --time=22).
				for item in ["lantern", "flood", "tower"]:
					if machine_of("light_" + item) == null:
						deliver(item)
				var c := base.to_global(Vector3(-6.0, 0.0, 14.0))
				machine_of("light_lantern").place_at(c + Vector3(-2.0, 0, 0), 0.0)
				machine_of("light_flood").place_at(c + Vector3(3.0, 0, -4.0), 2.6)
				machine_of("light_tower").place_at(c + Vector3(14.0, 0, -12.0), 0.0)
				vehicle_of("truck").lights_left_on = true
				vehicle_of("truck").set_dark(true)
				from = c + Vector3(-4.0, 3.0, 12.0)
				at = c + Vector3(2.0, 0.5, -4.0)
			"trommel":
				if machine_of("trommel") == null:
					deliver("trommel")
					deliver("excavator")
					deliver("high_banker")
				var tp := _v3(world.river_point("Cabin Creek", 0.575, 4.5))
				machine_of("pump").place_at(_v3(world.river_point("Cabin Creek", 0.57, 1.25)), 0.0)
				machine_of("trommel").place_at(tp, 0.0)
				var ex = vehicle_of("excavator")
				var ep := tp + Vector3(0, 0, 5.0)
				ep.y = terrain.height_at(ep.x, ep.z) + 0.3
				ex.freeze = true
				ex.global_transform = Transform3D(Basis(Vector3.UP, 0.6), ep)
				from = tp + Vector3(7.0, 0.0, 9.0)
				at = tp + Vector3(0, terrain.height_at(tp.x, tp.z) + 1.0, 2.5)
			"cabin":
				base.door.set_open(true, true)
				from = base.to_global(Vector3(1.9, 0.1, -0.2))
				at = base.to_global(Vector3(-1.4, 0.6, -3.0))
			"chest":
				base.door.set_open(true, true)
				from = base.to_global(Vector3(-0.2, 0.1, -1.5))
				at = base.to_global(Vector3(-1.4, 0.4, 0.1))
			"door":
				base.door.set_open(true, true)
				from = base.to_global(Vector3(0.9, 0.0, 3.6))
				at = base.to_global(Vector3(0.6, 1.2, -1.0))
			"journal":
				from = base.to_global(Vector3(-1.5, 0.0, 5.6))
				at = base.to_global(Vector3(-1.9, 0.5, 3.3))
			"shaft":
				var sh = shafts[0]
				from = sh.to_global(Vector3(-7.0, 0.0, 5.0))
				at = sh.to_global(Vector3(0, 2.0, 0))
			"camp", "mine":
				var site: Dictionary = world.sites[_opts["view"]]
				var pos: Vector2 = site["pos"]
				var face: Vector2 = site["facing"]
				var p := pos + face * 16.0 + Vector2(-face.y, face.x) * 5.0
				from = Vector3(p.x, 0.0, p.y)
				at = Vector3(pos.x, terrain.height_at(pos.x, pos.y) + 1.0, pos.y)
		from.y = terrain.height_at(from.x, from.z)
		var d := at - (from + Vector3(0, Player.EYE_HEIGHT, 0))
		_place_player(from, atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))


func _place_player(p: Vector3, yaw: float, pitch: float) -> void:
	player.global_position = Vector3(p.x, terrain.height_at(p.x, p.z) + 0.1, p.z)
	player.rotation.y = yaw
	player.camera.rotation.x = pitch
	_build_near_player()


func _demo_setup() -> void:
	machine_of("sluice").place_at(_v3(world.river_point("Cabin Creek", 0.6, 0.5)), 0.0)
	deliver("high_banker")
	machine_of("pump").place_at(_v3(world.river_point("Cabin Creek", 0.57, 1.25)), 0.0)
	machine_of("high_banker").place_at(_v3(world.river_point("Cabin Creek", 0.585, 3.4)), PI)
	for kind in ["sluice", "high_banker"]:
		var m = machine_of(kind)
		var p := m.global_position as Vector3
		for i in 6:
			m.processed_total += 1
			m.feed(deposits.shovelful(p.x, p.z, 0.3, 0.15, 0.0))
		for i in 3:
			m._process_one(deposits.shovelful(p.x, p.z, 0.15, 0.0, 0.0))


## A point across the creek (frac of its half width) near the middle of a claim, for tests.
func _claim_point(id: String, frac: float) -> Vector2:
	var c := Claims.by_id(id)
	var best := Vector2.ZERO
	var best_d := 1.0e9
	for i in 1000:
		var p := world.river_point(c["river"], i / 1000.0, frac)
		var d := p.distance_to(c["pos"])
		if d < best_d:
			best_d = d
			best = p
	return best


func _v3(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


func _check_wildlife() -> void:
	wildlife.clear()
	var pp := player.global_position
	var a: Dictionary = wildlife.spawn("deer", Vector2(pp.x + 50.0, pp.z))
	var n: Node3D = a["node"]
	var on_ground := absf(n.position.y - terrain.height_at(n.position.x, n.position.z)) < 0.05
	wildlife._update(a, 0.1, pp)
	var calm: bool = a["state"] == "graze"
	wildlife._update(a, 0.1, n.position + Vector3(-10.0, 0.0, 0.0))
	var start_x := n.position.x
	for i in 10:
		wildlife._update(a, 0.1, pp)
	var b: Dictionary = wildlife.spawn("bird", Vector2(pp.x, pp.z))
	var high: bool = b["node"].position.y > terrain.height_at(pp.x, pp.z) + 25.0
	_check("a deer grazes, then bounds away when near", on_ground and calm and a["state"] == "flee" and n.position.x > start_x + 5.0)
	day_night.underground = true
	wildlife._process(0.1)
	day_night.underground = false
	_check("birds circle high; no wildlife underground", high and wildlife.animals.is_empty())


func _check(name: String, ok: bool) -> void:
	print("SELFTEST %-38s %s" % [name, "ok" if ok else "FAILED"])
	if not ok:
		_failures += 1


func _selftest() -> void:
	SaveGame.path = "user://selftest.dat"
	_saving = true
	for i in 60:
		await get_tree().physics_frame
	var inv = player.inv
	var pp := player.global_position
	_check("standing on the ground", player.is_on_floor() and absf(pp.y - terrain.height_at(pp.x, pp.z)) < 0.3)
	var cabin_creek := world.river_point("Cabin Creek", 0.6, 0.0)
	_check("Cabin Creek has water", terrain.water_depth(cabin_creek.x, cabin_creek.y) > 0.3)

	# Sluice in the creek, fed by digging right next to it.
	var sluice = machine_of("sluice")
	sluice.place_at(_v3(world.river_point("Cabin Creek", 0.6, 0.5)), 0.0)
	_check("sluice has water", sluice.water_problem() == "")
	var bank := _v3(world.river_point("Cabin Creek", 0.6, 1.3))
	var fed := 0
	for i in 8:
		var res := terrain.dig(bank, Player.DIG_DEPTH, Player.DIG_RADIUS)
		if res["removed"] < 0.02:
			break
		if sluice.feed(deposits.shovelful(res["x"], res["z"], res["top"], res["bottom"], res["bedrock"])):
			fed += 1
	_check("digging stops at bedrock", terrain.dig(bank, Player.DIG_DEPTH, Player.DIG_RADIUS)["removed"] < 0.02)
	_check("dig sounds by ground", Sfx.dig_sound(5.0, 0.0, false) == "dig_clay" and Sfx.dig_sound(0.5, 0.0, false) == "dig_gravel" and Sfx.dig_sound(0.0, 0.0, true) == "dig_bedrock")
	for i in 150:
		await get_tree().physics_frame
	_check("sluice runs on its own", sluice.processed >= 1)
	while not sluice.hopper.is_empty():
		sluice._process_one(sluice.hopper.pop_front())
	print("  fed %d shovels: %d pieces caught, %d lost" % [fed, sluice.caught.size(), sluice.lost.size()])

	# Clean out, pan the concentrate, smelt, sell.
	sluice.interact(player)
	_check("cleanout gives a jar", inv.cons.size() == 1)
	var jar = inv.cons.pop_front()
	var sim := PanSim.new()
	sim.setup(jar, 9)
	var t := 0.0
	while not sim.done and t < 90.0:
		var phase := fmod(t, 3.2)
		sim.step(1.0 / 60.0, phase < 1.2, 18.0 if phase >= 1.2 else 0.0, 0.0)
		t += 1.0 / 60.0
	_check("concentrate pans clean", sim.done)
	inv.add_gold(sim.gold_kept())
	if inv.vial_grams() <= 0.0:
		inv.add_gold(PackedFloat32Array([0.05]))
	var furnace = base.furnace
	furnace.interact(player)
	for i in 100:
		furnace.advance(0.25)
		if furnace.is_molten():
			furnace.interact(player)
		if furnace.is_ready():
			furnace.interact(player)
			break
	_check("smelting makes a bar", inv.bars.size() == 1)
	var money_before: int = inv.money
	town.assay.interact(player)
	_check("the assay office pays for the bar", inv.money > money_before)
	_check("the town stands on level ground by the road", absf(town.street.y - terrain.height_at(town.street.x, town.street.z)) < 0.4
		and world.road_weight(town.to_global(Vector3(0, 0, 28)).x, town.to_global(Vector3(0, 0, 28)).z) > 0.5)
	var p1 := Market.price(1)
	var lo := p1
	var hi := p1
	for d in range(1, 40):
		lo = minf(lo, Market.price(d))
		hi = maxf(hi, Market.price(d))
	_check("the gold price drifts, but not wildly", hi - lo > 8.0 and lo > Market.BASE_PRICE * 0.55 and hi < Market.BASE_PRICE * 1.5)
	var kinds := {}
	var same := true
	for d in range(1, 200):
		kinds[Market.event(d)] = true
		same = same and Market.event(d) == Market.event(d) and Market.price(d) == Market.price(d)
	var calm := true
	for d in range(1, 8):
		calm = calm and Market.event(d) == ""
	_check("price events are fixed by day, bounded, and both kinds happen", same and calm and kinds.has("spike") and kinds.has("slump")
		and Market.price(150) > Market.BASE_PRICE * 0.55 and Market.event_shift(150) <= Market.SPIKE)
	_check("version comparison", UpdateCheck.is_newer("v0.10", "0.9") and UpdateCheck.is_newer("v1.0", "v0.99.1")
		and not UpdateCheck.is_newer("v0.9", "0.9") and not UpdateCheck.is_newer("v0.8", "0.9")
		and UpdateCheck.is_newer("v0.9.1", "0.9") and not UpdateCheck.is_newer("v0.9-beta", "0.9"))
	print("  gold price over 40 days: $%.2f to $%.2f a gram" % [lo, hi])
	base.journal.interact(player)
	_check("Grandpa's journal marks the old mine", map_view.marks.size() == 1
		and (map_view.marks[0][0] as Vector2).distance_to(world.sites["mine"]["pos"]) < 1.0)
	hud.hide_note()

	# Claims: machines only run on ground you own.
	var willow := _v3(_claim_point("willow", 0.5))
	sluice.place_at(willow, 0.0)
	_check("a sluice has water on Willow Creek but won't run: not your claim", sluice.water_problem() == "" and sluice.problem() != "" and not sluice.is_running())
	var open_ground := _v3(world.river_point("Willow Creek", 0.15, 0.5))
	sluice.place_at(open_ground, 0.0)
	_check("nor on public land", sluice.water_problem() == "" and not sluice.is_running())
	sluice.place_at(willow, 0.0)
	inv.money += 1500
	town.claims_office.select("willow")
	town.claims_office.interact(player)
	_check("buying the claim lets it run", inv.claims.has("willow") and sluice.is_running())
	_check("Grandpa's claim covers the cabin and the creek", Claims.is_owned_at(base.center.x, base.center.z)
		and Claims.is_owned_at(cabin_creek.x, cabin_creek.y))

	# Every river and creek works for the sluice, the pump and panning.
	var all_rivers := true
	for r in world.rivers:
		if r.get("dry", false):
			continue
		var n: String = r["name"]
		var hws: PackedFloat32Array = r["hw"]
		sluice.place_at(_v3(world.river_point(n, 0.5, 0.5)), 0.0)
		var sluice_ok: bool = sluice.water_problem() == ""
		var edge := _v3(world.river_point(n, 0.5, 1.0 + 1.5 / hws[hws.size() / 2]))
		player.global_position = Vector3(edge.x, terrain.height_at(edge.x, edge.z) + 0.1, edge.z)
		var pan_ok: bool = player._near_water()
		if not (sluice_ok and pan_ok):
			all_rivers = false
			print("  %s: sluice %s, panning %s" % [n, sluice_ok, pan_ok])
	_check("sluice and panning work on every river", all_rivers)
	sluice.place_at(_v3(world.river_point("Cabin Creek", 0.6, 0.5)), 0.0)
	player.global_position = base.spawn_point

	# High banker and pump.
	inv.money += 900
	town.store.select("high_banker")
	town.store.interact(player)
	var hb = machine_of("high_banker")
	var pump = machine_of("pump")
	_check("high banker and pump delivered", hb != null and pump != null)
	pump.place_at(_v3(world.river_point("Cabin Creek", 0.57, 1.25)), 0.0)
	_check("pump reaches water", pump.water_problem() == "")
	hb.place_at(_v3(world.river_point("Cabin Creek", 0.585, 3.4)), 0.0)
	hb.refresh_pump()
	_check("high banker hooked to the pump", hb.water_problem() == "")
	var pumps_ok := true
	for r in world.rivers:
		if r.get("dry", false):
			continue
		pump.place_at(_v3(world.river_point(r["name"], 0.4, 1.25)), 0.0)
		if pump.water_problem() != "":
			pumps_ok = false
			print("  pump has no water on %s" % r["name"])
	_check("the pump works on every river", pumps_ok)
	pump.place_at(_v3(world.river_point("Cabin Creek", 0.57, 1.25)), 0.0)

	# Vehicles.
	var atv = vehicle_of("atv")
	var truck = vehicle_of("truck")
	_check("ATV and pickup parked at the cabin", atv != null and truck != null)
	player.global_position = atv.global_position + Vector3(2, 0, 0)
	for i in 5:
		await get_tree().physics_frame
	atv.enter(player)
	_check("getting on the ATV", player.driving == atv and not atv.freeze)
	var start: Vector3 = atv.global_position
	Input.action_press("move_forward")
	for i in 120:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	var moved: float = start.distance_to(atv.global_position)
	_check("the ATV drives", moved > 4.0)
	_check("the ATV stays upright", atv.global_basis.y.dot(Vector3.UP) > 0.8)
	Input.action_press("jump")
	for i in 90:
		await get_tree().physics_frame
	Input.action_release("jump")
	_check("the ATV brakes to a stop", atv.linear_velocity.length() < 1.0)
	print("  ATV drove %.1f m from the cabin in 2 s" % moved)
	atv.exit()
	for i in 10:
		await get_tree().physics_frame
	pp = player.global_position
	_check("getting off leaves you on the ground", player.driving == null and absf(pp.y - terrain.height_at(pp.x, pp.z)) < 0.5)

	# Hauling: put the sluice in the pickup, drive, take it off again.
	player.global_position = truck.global_position + Vector3(3, 0, 0)
	player.start_carry(sluice)
	var m = player.carrying
	player.carrying = null
	_check("loading onto the pickup", truck.load_cargo(m) and sluice.loaded_on == truck and not sluice.is_running())
	truck.enter(player)
	Input.action_press("move_forward")
	for i in 90:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	_check("cargo rides along", sluice.global_position.distance_to(truck.global_position) < 3.0)
	print("  pickup drove %.1f m with the sluice in the bed" % truck.global_position.distance_to(start))
	truck.exit()
	player.start_carry(sluice)
	_check("unloading", sluice.loaded_on == null and player.carrying == sluice)
	player._set_down()

	# Map, waypoints, day and night.
	map_view.add_waypoint(Vector2(1000, 1000))
	map_view.add_waypoint(Vector2(1200, 900))
	map_view.remove_waypoint_near(Vector2(1203, 902), 10.0)
	map_view.reveal_around(player.global_position)
	_check("waypoints add and remove, exploration", map_view.waypoints.size() == 1 and map_view.is_explored(player.global_position.x, player.global_position.z)
		and not map_view.is_explored(60.0, 60.0))
	day_night.hours = 23.0
	day_night.apply()
	var dark := day_night.is_dark()
	var day_before := day_night.day
	day_night.sleep_until_morning()
	_check("night falls and sleep skips to morning", dark and day_night.hours == 7.0 and day_night.day == day_before + 1)

	# Save, then read it back.
	truck.load_cargo(machine_of("pump"))
	save_now()
	var data := SaveGame.read()
	var cargo_saved := false
	for md in data.get("machines", []):
		if md.get("kind", "") == "pump" and int(md.get("vehicle", -1)) >= 0:
			cargo_saved = true
	_check("save: version, vehicles, machines, cargo", int(data.get("version", 0)) == SaveGame.VERSION and (data.get("vehicles", []) as Array).size() == 2
		and (data.get("machines", []) as Array).size() == 3 and cargo_saved)
	_check("save: digs, waypoints, time", not (data.get("digs", {}).get("h", {}) as Dictionary).is_empty()
		and (data.get("map", {}).get("waypoints", []) as Array).size() == 1 and data.get("time", {}).get("day", 0) == day_night.day)
	SaveGame.delete()

	# The old mine: go in, stand on the floor, chip rock and vein, crush the ore, come out.
	enter_mine()
	for i in 40:
		await get_tree().physics_frame
	var floor_y: float = mine.global_position.y + Mine.LEVEL1
	_check("inside the mine, standing on the floor", player.mine == mine and player.is_on_floor() and absf(player.global_position.y - floor_y) < 0.4)
	_check("it is dark underground", day_night.underground and not day_night.sun.visible)
	var rock: Dictionary = mine.chip(mine.to_global(Vector3(20.0, 9.0, 31.2)), Vector3(0, 0, -1))
	_check("plain rock chips away", int(rock["rock"]) > 0 and int(rock["vein_a"]) == 0)
	player._aim = {"position": mine.to_global(Vector3(44.2, 9.0, 31.1)), "normal": Vector3(0, 0, -1), "collider": mine._body}
	player._dig_cd = 0.0
	player._try_chip()
	_check("chipping the quartz vein fills the ore sack", inv.ore.size() == 1)
	var small: Dictionary = mine.chip(mine.to_global(Vector3(10.0, 9.0, 31.2)), Vector3(0, 0, -1), 1.0)
	var big: Dictionary = mine.chip(mine.to_global(Vector3(15.0, 9.0, 31.2)), Vector3(0, 0, -1), 1.8)
	_check("better tools bite deeper", int(big["rock"]) > int(small["rock"]) and int(small["rock"]) > 0)
	inv.money += 1900
	town.store.select("pick")
	town.store.interact(player)
	town.store.select("rotary")
	town.store.interact(player)
	_check("the store sells the pick, then the rotary hammer", inv.tool_tier == 2)
	var lower: Dictionary = mine.chip(mine.to_global(Vector3(50.0, 2.5, 13.1)), Vector3(0, 0, 1))
	_check("the lower vein is there", int(lower["vein_b"]) > 0)
	player.global_position = mine.to_global(Vector3(56.0, 5.2, 30.0))
	for i in 60:
		await get_tree().physics_frame
	_check("the ramp holds you", player.is_on_floor() and player.global_position.y > mine.global_position.y + 3.0)
	exit_mine()
	for i in 20:
		await get_tree().physics_frame
	pp = player.global_position
	_check("back outside on the ground", player.mine == null and absf(pp.y - terrain.height_at(pp.x, pp.z)) < 0.5)
	base.crusher.interact(player)
	_check("crushing ore gives a jar to pan", inv.ore.is_empty() and inv.cons.size() == 1)
	save_now()
	_check("mine digging is saved", (SaveGame.read().get("mine", {}).get("carved", PackedInt32Array()) as PackedInt32Array).size() > 3)
	SaveGame.delete()

	# Old shafts in the hills: climb down, stand in the drift, find quartz, climb back out.
	_check("old shafts in the Old Mining District", shafts.size() == world.SHAFT_COUNT
		and world.shafts.all(func(d): return world.region_name(d["pos"].x, d["pos"].y) == "Old Mining District"))
	enter_shaft(0)
	for i in 60:
		await get_tree().physics_frame
	var sfloor: float = side_mine.global_position.y + Mine.LEVEL1
	_check("down the shaft, standing in the drift", player.mine == side_mine and player.is_on_floor()
		and absf(player.global_position.y - sfloor) < 0.4)
	_check("the side mine has quartz and no hazards", side_mine.cells.count(Mine.VEIN_A) > 50 and side_mine.hazards == null)
	var shaft_rock: Dictionary = side_mine.chip(side_mine.to_global(Vector3(4.5, 9.0, 31.7)), Vector3(0, 0, -1))
	_check("side mine rock can be chipped", int(shaft_rock["rock"]) + int(shaft_rock["vein_a"]) + int(shaft_rock["vein_b"]) > 0)
	save_now()
	var sp: Dictionary = SaveGame.read().get("player", {})
	_check("a save down a shaft loads at its collar", not sp.get("in_mine", true)
		and (sp.get("pos", Vector3.ZERO) as Vector3).distance_to(shafts[0].exit_point()) < 1.0)
	SaveGame.delete()
	exit_mine()
	for i in 20:
		await get_tree().physics_frame
	pp = player.global_position
	_check("climbed out beside the shaft", player.mine == null and pp.distance_to(shafts[0].exit_point()) < 1.5
		and absf(pp.y - terrain.height_at(pp.x, pp.z)) < 0.5)
	enter_shaft(1)
	_check("one side mine at a time", side_mine.shaft_id == world.shafts[1]["id"])
	exit_mine()

	# Powered crusher and specimens.
	inv.money += 1200
	town.store.select("crusher")
	town.store.interact(player)
	_check("the powered crusher is delivered", inv.crusher_powered and base.crusher.powered)
	var ore_piece := Paydirt.new()
	for i in 40:
		ore_piece.add_gold(0.01)
	inv.ore.append(ore_piece)
	base.crusher.interact(player)
	_check("the powered crusher frees all the gold", (inv.cons[-1].gold as PackedFloat32Array).size() == 40)
	base.crusher.set_powered(false)
	inv.ore.append(ore_piece)
	base.crusher.interact(player)
	var by_hand: int = (inv.cons[-1].gold as PackedFloat32Array).size()
	_check("pounding by hand loses some", by_hand > 0 and by_hand < 40)
	base.crusher.set_powered(true)
	inv.bars.clear()
	inv.nuggets = PackedFloat32Array()
	inv.specimens = PackedFloat32Array()    # a vein chip earlier may have dropped one at random
	inv.add_specimen(0.4)
	money_before = inv.money
	town.assay.interact(player)
	_check("specimens sell at a premium", inv.specimens.is_empty() and inv.money - money_before == Market.specimen_value(0.4)
		and Market.specimen_value(0.4) > roundi(0.4 * Market.price() * 2.0))

	# The rest of the catalog: each thing changes something.
	inv.money += 1430
	for id in ["classifier", "bucket", "sack", "moss", "detector"]:
		town.store.select(id)
		town.store.interact(player)
	_check("the catalog sells the small gear", inv.gear.size() == 5 and inv.money == money_before + Market.specimen_value(0.4))
	_check("big bucket and big ore sack", inv.bucket_capacity() == 10 and inv.ore_capacity() == 20)
	_check("miner's moss holds more fine gold", Recovery.carpet_bonus > 0.0
		and Recovery.catch_chance(0.002, 6.0) > 0.8 and Recovery.catch_chance(0.2, 6.0) <= 0.995)
	player.global_position = _v3(world.river_point("Cabin Creek", 0.6, 1.2))
	player.global_position.y = terrain.height_at(player.global_position.x, player.global_position.z) + 0.1
	var shovel := Paydirt.new()
	inv.bucket.append(shovel)
	player._try_pan()
	_check("the classifier takes gravel out of the pan", player.pan_view != null and shovel.gravel < 0.5)
	player.pan_view.cancelled.emit()
	player.refresh_hud()
	_check("the detector stays quiet until it is in hand", not ("Detector   " in hud._status.text))
	player.select_tool("detector")
	_check("the hotbar holds the shovel, pan and detector", player.tools().has("detector") and hud._hotbar_key.begins_with("Shovel,Gold pan"))
	_check("the detector reads the ground", "Detector   " in hud._status.text and "yours" in hud._status.text)
	player.cycle_tool(1)
	_check("the hotbar wraps around", player.tool == "shovel" or player.tool == player.tools()[0])
	player.select_tool("shovel")
	player.toggle_inventory()
	_check("the inventory shows what you carry", hud.note_open() and "Bucket" in hud._note_text.text)
	player.toggle_inventory()

	# Journals and old maps.
	enter_mine()
	var journal = null
	for ch in mine.get_children():
		if ch is Mine.Find and ch.kind == "journal":
			journal = ch
	journal.interact(player)
	var spot := rich_spot("Rattlesnake Gulch")
	_check("reading the journal marks a place on the map", hud.note_open() and map_view.marks.size() == 2
		and (map_view.marks[1][0] as Vector2).distance_to(spot) < 1.0)
	_check("the marked place really is rich", deposits.richness(spot.x, spot.y) > 0.8)
	print("  Hendricks' bar: richness %.2f at (%d, %d)" % [deposits.richness(spot.x, spot.y), spot.x, spot.y])
	journal.interact(player)
	journal.interact(player)
	_check("reading it again adds nothing", map_view.marks.size() == 2)
	hud.hide_note()

	# Hazards: lamp battery, bad air, rotten ground; then all of it switched off.
	Settings.hazards = true
	player.set_headlamp(true)
	player.global_position = mine.to_global(Vector3(20.0, 8.2, 30.0))
	for i in 30:
		await get_tree().physics_frame
	_check("the headlamp battery runs down underground", player.lamp_charge < 1.0)
	player.lamp_charge = 0.0
	for i in 3:
		await get_tree().physics_frame
	_check("a flat battery still gives a glow", player._lamp.light_energy > 0.3 and player._lamp.light_energy < 1.0)
	player.global_position = mine.to_global(Vector3(44.0, 1.7, 14.4))
	for i in 60:
		await get_tree().physics_frame
	_check("bad air takes your breath and dims your sight", player.air < 0.98 and hud._shade_level > 0.0)
	player.air = 0.001
	for i in 5:
		await get_tree().physics_frame
	_check("passing out wakes you at the adit, nothing lost", player.global_position.distance_to(mine.spawn_point()) < 2.0 and player.air > 0.9)
	var rot: Vector3 = mine.to_global(Mine.Hazards.ROT_CENTER)
	mine.chip(rot + Vector3(0, 0, 1.2), Vector3(0, 0, -1))
	var dug_before: int = mine.carved.size()
	var fell := false
	for i in 3:
		mine.hazards._stress_wait = 0.0
		fell = mine.hazards.on_chip(rot)
	var c := Mine.Hazards.ROT_CENTER / Mine.CELL
	_check("three blows under rotten timber bring the roof down", fell and mine.hazards.collapsed
		and not mine._open(int(c.x), int(c.y), int(c.z)) and mine.carved.size() < dug_before)
	_check("the cave-in throws you clear", player.global_position.distance_to(rot) > 5.0)
	save_now()
	_check("the cave-in is saved", SaveGame.read().get("mine", {}).get("collapsed", false))
	SaveGame.delete()
	Settings.hazards = false
	player.lamp_charge = 0.3
	player.global_position = mine.to_global(Vector3(44.0, 1.7, 14.4))
	for i in 30:
		await get_tree().physics_frame
	_check("hazards off: full lamp, clean air", player.lamp_charge == 1.0 and player.air == 1.0 and hud._shade_level == 0.0
		and absf(player._lamp.light_energy - Player.LAMP_ENERGY) < 0.01)
	Settings.hazards = true
	exit_mine()
	for i in 20:
		await get_tree().physics_frame

	# The cabin: open the door, walk in, use the chest, sleep in the bunk.
	base.door.set_open(false, true)
	player.global_position = base.to_global(Vector3(0.9, 0.15, 2.2))
	player.rotation.y = base.rotation.y
	player.camera.rotation.x = 0.0
	player.velocity = Vector3.ZERO
	for i in 5:
		await get_tree().physics_frame
	Input.action_press("move_forward")
	for i in 70:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	var shut_z: float = base.to_local(player.global_position).z
	_check("a closed door keeps you out", shut_z > HomeBase.CABIN_Z + HomeBase.CABIN_D * 0.5)
	base.door.interact(player)
	for i in 40:
		await get_tree().physics_frame
	player.global_position = base.to_global(Vector3(0.9, 0.1, 1.3))
	player.velocity = Vector3.ZERO
	Input.action_press("move_forward")
	for i in 70:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	var lp: Vector3 = base.to_local(player.global_position)
	_check("an open door lets you into the cabin", lp.z < HomeBase.CABIN_Z + 0.6 and absf(lp.y - 0.1) < 0.2 and player.is_on_floor())
	print("  walked in to (%.2f, %.2f, %.2f) in the cabin" % [lp.x, lp.y, lp.z])
	inv.bars.append({"grams": 5.0, "purity": 0.9})
	inv.add_gold(PackedFloat32Array([0.05, 0.5]))
	inv.ore.clear()
	inv.ore.append(Paydirt.new())
	inv.garnets = PackedFloat32Array([1.25])
	var jars_before: int = inv.cons.size()
	base.chest.interact(player)
	_check("the chest takes your goods", inv.bars.is_empty() and inv.nuggets.is_empty() and inv.vial.is_empty() and inv.ore.is_empty()
		and inv.cons.is_empty() and inv.chest_bars.size() == 1 and inv.chest_nuggets.size() == 1 and inv.chest_ore.size() == 1
		and inv.garnets.is_empty() and inv.chest_garnets.size() == 1)
	save_now()
	var saved_chest: Dictionary = SaveGame.read().get("inventory", {}).get("chest", {})
	_check("the chest is saved", (saved_chest.get("bars", []) as Array).size() == 1 and (saved_chest.get("cons", []) as Array).size() == jars_before
		and (saved_chest.get("garnets", []) as PackedFloat32Array).size() == 1)
	SaveGame.delete()
	base.chest.scroll(player, 1)
	base.chest.interact(player)
	_check("and gives them back", inv.bars.size() == 1 and inv.nuggets.size() == 1 and inv.ore.size() == 1 and inv.cons.size() == jars_before
		and inv.chest_bars.is_empty() and absf(inv.vial_grams() - 0.05) < 0.001 and inv.garnets.size() == 1)
	# A full ore sack: take what fits, the rest stays put.
	inv.ore.clear()
	for i in inv.ore_capacity() - 1:
		inv.ore.append(Paydirt.new())
	inv.chest_ore = [Paydirt.new(), Paydirt.new(), Paydirt.new()]
	var moved_ore: Array = inv.take_from_chest()
	_check("a full ore sack leaves the rest in the chest", int(moved_ore[1]) == 1 and inv.ore.size() == inv.ore_capacity()
		and inv.chest_ore.size() == 2)
	inv.ore.clear()
	inv.chest_ore = []
	_check("the bunk is inside", base.to_local(base.bed.global_position).z < HomeBase.CABIN_Z)

	# The suction dredge: bought with its permit, floated on your claim, it feeds itself.
	inv.money += 3700
	town.store.select("dredge")
	town.store.interact(player)
	var dredge = machine_of("dredge")
	_check("the dredge is delivered", dredge != null and inv.gear.has("dredge"))
	var shallow := _v3(_claim_point("sable", 2.2))
	dredge.place_at(shallow, 0.0)
	_check("the dredge needs deeper water", dredge.water_problem() != "")
	var deep := _v3(_claim_point("sable", 0.3))
	dredge.place_at(deep, 0.0)
	_check("off your claim it won't run", dredge.water_problem() == "" and not dredge.is_running())
	town.claims_office.select("sable")
	town.claims_office.interact(player)
	var bed_before: float = terrain.height_at(deep.x, deep.z)
	for i in 330:
		await get_tree().physics_frame
	print("  dredge: depth %.2f m, %d shovelfuls through, %d pieces caught, bed down %.2f m" % [terrain.water_depth(deep.x, deep.z),
		dredge.processed_total, dredge.caught.size(), bed_before - terrain.height_at(deep.x, deep.z)])
	_check("on your claim it sucks up the bottom by itself", dredge.is_running() and dredge.processed_total >= 1
		and terrain.height_at(deep.x, deep.z) < bed_before - 0.05)
	dredge.interact(player)
	_check("its riffles clean out into a jar", not dredge.has_concentrate())

	# The dry washer: no water needed, but it has to stand on dry ground on your claim.
	inv.money += 5100
	town.store.select("dry_washer")
	town.store.interact(player)
	var dw = machine_of("dry_washer")
	_check("the dry washer is delivered", dw != null)
	dw.place_at(_v3(world.river_point("Cabin Creek", 0.57, 0.3)), 0.0)
	_check("the dry washer refuses the creek", dw.water_problem() != "")
	var wash := _v3(deposits.rich_spot("Coyote Wash"))
	dw.place_at(wash, 0.0)
	_check("the dry washer is happy in the dry wash, once the claim is yours", dw.water_problem() == "" and not dw.is_running())
	town.claims_office.select("coyote")
	town.claims_office.interact(player)
	for i in 3:
		var res := terrain.dig(wash + Vector3(1.5, 0, 0), Player.DIG_DEPTH, Player.DIG_RADIUS)
		dw.feed(deposits.shovelful(res["x"], res["z"], res["top"], res["bottom"], res["bedrock"]))
	for i in 300:
		await get_tree().physics_frame
	print("  dry washer: %d shovelfuls through, %d pieces caught, %d lost" % [dw.processed_total, dw.caught.size(), dw.lost.size()])
	_check("the dry washer runs and catches gold", dw.is_running() and dw.processed_total == 3 and dw.caught.size() > 0)
	_check("air loses more fine gold than water", Recovery.catch_chance(0.002, 7.0, DryWasher.DRY_PENALTY) < Recovery.catch_chance(0.002, 7.0))
	_check("the metal detector reads the dry wash", deposits.richness(wash.x, wash.z) > 0.8)

	# The trailer: hitch it in one action and tow it behind the pickup.
	var pickup = vehicle_of("truck")
	for cargo_item in pickup.cargo:
		if cargo_item != null:
			pickup.unload_cargo(cargo_item)
	pickup.freeze = true
	pickup.global_transform = _parked(1)
	inv.money += 800
	town.store.select("trailer")
	town.store.interact(player)
	var trailer = vehicle_of("trailer")
	_check("the trailer is delivered behind the pickup", trailer != null)
	player.global_position = trailer.to_global(Vector3(1.5, 0.0, -2.0))
	trailer.interact(player)
	_check("hitching is one action", trailer.towed_by == pickup)
	var tr_start: Vector3 = trailer.global_position
	pickup.enter(player)
	Input.action_press("move_forward")
	for i in 150:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	Input.action_press("jump")
	for i in 60:
		await get_tree().physics_frame
	Input.action_release("jump")
	var gap: float = trailer.to_global(Trailer.TONGUE).distance_to(pickup.to_global(Trailer.BALL))
	print("  towed %.1f m; coupler %.2f m from the ball; trailer up %.2f" % [tr_start.distance_to(trailer.global_position), gap, trailer.global_basis.y.dot(Vector3.UP)])
	_check("the trailer follows on the ball and stays upright", tr_start.distance_to(trailer.global_position) > 4.0 and gap < 0.3
		and trailer.global_basis.y.dot(Vector3.UP) > 0.9)
	pickup.exit()
	for i in 5:
		await get_tree().physics_frame
	trailer.interact(player)
	_check("unhitching", trailer.towed_by == null)
	save_now()
	var saved_trailer := false
	for vd in SaveGame.read().get("vehicles", []):
		if vd.get("kind", "") == "trailer":
			saved_trailer = true
	_check("the trailer is saved", saved_trailer)
	SaveGame.delete()

	# Camps and fast travel: pitch a tent far away, travel there from the bunk with the pickup.
	inv.money += 300
	town.store.select("camp")
	town.store.interact(player)
	var tent = null
	for mach in get_tree().get_nodes_in_group("machines"):
		if mach.kind == "camp":
			tent = mach
	_check("a camp tent is delivered", tent != null)
	var camp_spot := _v3(world.river_point("Willow Creek", 0.5, 6.0))
	tent.place_at(camp_spot, 0.0)
	pickup.freeze = true
	pickup.global_transform = _parked(1)
	player.global_position = base.spawn_point
	var day0: float = day_night.day * 24.0 + day_night.hours
	var dests := Travel.destinations(self, player.global_position)
	_check("the camp is a destination", dests.size() == 1 and str(dests[0][0]) == "Camp 1")
	base.bed.scroll(player, -1)
	base.bed.interact(player)
	for i in 20:
		await get_tree().physics_frame
	var waited: float = day_night.day * 24.0 + day_night.hours - day0
	print("  travelled %.0f m in %.2f hours" % [Vector2(base.spawn_point.x, base.spawn_point.z).distance_to(Vector2(camp_spot.x, camp_spot.z)), waited])
	_check("fast travel takes you to the camp, and time passes", player.global_position.distance_to(tent.arrival_point()) < 3.0
		and waited >= Travel.hours_for(base.spawn_point, camp_spot) - 0.01)
	_check("the pickup came along", pickup.global_position.distance_to(player.global_position) < 8.0)
	_check("you land on the ground", player.is_on_floor() or absf(player.global_position.y - terrain.height_at(player.global_position.x, player.global_position.z)) < 0.5)
	tent.scroll(player, -1)
	tent.interact(player)
	_check("and back to the cabin from the tent", player.global_position.distance_to(base.spawn_point) < 3.0)

	# Storms and floods: dig a bar to bedrock, let a storm pass, and the hole fills with fresh gravel.
	var sd := 2
	while not Weather.storm_day(sd):
		sd += 1
	var bar := _v3(world.river_point("Cabin Creek", 0.58, 1.25))
	var undug := terrain.height_at(bar.x, bar.z)
	for i in 12:
		terrain.dig(bar, Player.DIG_DEPTH, Player.DIG_RADIUS)
	var dug_h := terrain.height_at(bar.x, bar.z)
	var farhole := _v3(world.river_point("Cabin Creek", 0.58, 8.0))
	for i in 3:
		terrain.dig(farhole, Player.DIG_DEPTH, Player.DIG_RADIUS)
	var far_dug := terrain.height_at(farhole.x, farhole.z)
	day_night.day = sd
	day_night.hours = 15.5
	weather.checked = weather.now()
	for i in 3:
		await get_tree().process_frame
	_check("storms come every few days, with rain", weather.amount() > 0.9 and day_night.storm > 0.9)
	day_night.hours = 19.5
	for i in 3:
		await get_tree().process_frame
	var refilled := terrain.height_at(bar.x, bar.z)
	print("  storm on day %d: bar %.2f m deep before, %.2f m after; a hole up the bank stays %.2f m deep" % [sd, undug - dug_h, undug - refilled,
		terrain.height_at(farhole.x, farhole.z) - far_dug + (terrain.height_at(farhole.x, farhole.z) - far_dug) * 0.0])
	_check("a flood refills the holes on the bar", undug - dug_h > 0.3 and absf(refilled - undug) < 0.02)
	_check("but not holes up the bank", absf(terrain.height_at(farhole.x, farhole.z) - far_dug) < 0.01)
	var fresh := terrain.dig(bar, Player.DIG_DEPTH, Player.DIG_RADIUS)
	_check("the refilled bar can be dug again", fresh["removed"] > 0.02)
	day_night.day = sd + 1
	day_night.hours = 23.0
	var floods_while_asleep := weather.storms_between(sd * 24.0 + 10.0, (sd + 1) * 24.0 + 7.0)
	_check("a storm you sleep through still floods", floods_while_asleep == 1)
	day_night.hours = 8.0

	# The trommel and the mini-excavator: the excavator digs and loads the trommel.
	inv.money += 9500
	town.store.select("trommel")
	town.store.interact(player)
	town.store.select("excavator")
	town.store.interact(player)
	var trommel = machine_of("trommel")
	var digger = vehicle_of("excavator")
	_check("trommel and mini-excavator delivered", trommel != null and digger != null)
	machine_of("high_banker").place_at(base.slot_position(1), base.slot_yaw())
	var pmp = machine_of("pump")
	if pmp.loaded_on != null:
		pmp.loaded_on.unload_cargo(pmp)
	pmp.place_at(_v3(world.river_point("Cabin Creek", 0.57, 1.25)), 0.0)
	var tspot := _v3(world.river_point("Cabin Creek", 0.575, 4.5))
	tspot.y = terrain.height_at(tspot.x, tspot.z)
	trommel.place_at(tspot, 0.0)
	trommel.refresh_pump()
	_check("the trommel runs off the pump", trommel.is_running())
	digger.freeze = true
	var dspot := tspot + Vector3(0, 0, 5.0)
	dspot.y = terrain.height_at(dspot.x, dspot.z) + 0.3
	digger.global_transform = Transform3D(Basis(Vector3.UP, 0.0), dspot)
	var dig_at: Vector3 = digger.to_global(Excavator.DIG_AHEAD)
	var before_h := terrain.height_at(dig_at.x, dig_at.z)
	for i in 3:
		digger._cool = 0.0
		digger.action(player)
	print("  excavator: hopper %d/%d after 3 buckets, ground down %.2f m" % [trommel.hopper.size(), trommel.hopper_capacity, before_h - terrain.height_at(dig_at.x, dig_at.z)])
	_check("the excavator digs and loads the trommel", trommel.hopper.size() >= 10 and terrain.height_at(dig_at.x, dig_at.z) < before_h - 0.3)
	for i in 120:
		await get_tree().physics_frame
	_check("the trommel works through it", trommel.processed_total >= 3)

	# Walk.
	player.global_position = base.spawn_point
	player.velocity = Vector3.ZERO
	for i in 5:
		await get_tree().physics_frame
	start = player.global_position
	Input.action_press("move_forward")
	for i in 60:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	_check("walking moves the player", start.distance_to(player.global_position) > 1.5)

	# Onboarding: every early step has a place to point at, and the panning spot is a good one.
	var saved_goals: Dictionary = player.inv.goals_done
	player.inv.goals_done = {}
	var early_ok := true
	for g in ["journal", "pan", "read_creek", "sluice_placed", "sluice_fed", "cleaned", "cons_panned", "smelted", "drive", "sold"]:
		if goal_target() == null:
			print("  no guide target for ", g)
			early_ok = false
		player.inv.goals_done[g] = true
	_check("every step to the first sale has a guide target", early_ok)
	var bar_spot := goal_target_spot()
	var home2: Vector2 = world.sites["base"]["pos"]
	var avg := 0.0
	for i in 20:
		var rp := world.river_point("Cabin Creek", i / 20.0, 0.0)
		avg += deposits.richness(rp.x, rp.y) / 20.0
	_check("the tutorial bar is near the cabin and richer than the creek's average",
		Vector2(bar_spot.x, bar_spot.z).distance_to(home2) < 225.0 and deposits.richness(bar_spot.x, bar_spot.z) > avg)
	player.inv.goals_done = saved_goals

	# Sound: everything is synthesized, loops loop, and playing works.
	var sfx_node = Sfx._i
	var snd_wait := 0
	while not sfx_node._ready_sounds and snd_wait < 600:
		await get_tree().process_frame
		snd_wait += 1
	var sounds_ok: bool = sfx_node._ready_sounds
	for n in ["dig", "pour", "dump", "chip", "splash", "clink", "sell", "goal", "thud", "creak", "roar", "creek", "wind",
			"rain", "swish", "crickets", "drip", "engine", "motor", "water", "bird0", "tune0", "tune1", "tune2"]:
		var w = sfx_node._sounds.get(n)
		if w == null or w.data.size() < 200:
			print("  missing sound ", n)
			sounds_ok = false
	_check("every sound is built", sounds_ok)
	_check("ambience loops", sfx_node._sounds["creek"].loop_mode == AudioStreamWAV.LOOP_FORWARD and sfx_node._amb.size() == 5)
	Sfx.play("dig", player.global_position)
	Sfx.play("sell")
	_check("sounds play", sfx_node._pool3.size() > 0 and sfx_node._pool.size() > 0)

	# Vehicles right themselves: on its side, it's back on its wheels; sunk, it's lifted out.
	var quad = vehicle_of("atv")
	var qp: Vector3 = quad.global_position
	quad.freeze = false
	quad.global_transform = Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(qp.x, terrain.height_at(qp.x, qp.z) + 0.6, qp.z))
	quad.linear_velocity = Vector3.ZERO
	for i in 180:
		await get_tree().physics_frame
	_check("a tipped-over ATV rights itself", quad.global_basis.y.y > 0.8)
	quad.freeze = false
	quad.global_transform = Transform3D(Basis.IDENTITY, Vector3(qp.x, terrain.height_at(qp.x, qp.z) - 0.8, qp.z))
	for i in 30:
		await get_tree().physics_frame
	_check("an ATV sunk in the ground is lifted out", quad.to_global(Vector3(0, quad.com_y, 0)).y > terrain.height_at(quad.global_position.x, quad.global_position.z) - 0.05)
	for i in 120:
		await get_tree().physics_frame
	quad.enter(player)
	for i in 10:
		await get_tree().physics_frame
	quad.exit()
	for i in 90:
		await get_tree().physics_frame
	_check("getting off doesn't knock it over", quad.global_basis.y.y > 0.8 and player.global_position.distance_to(quad.global_position) > 1.0)

	# Settings: rebinding moves the action and swaps a clash; prompts follow the new key.
	Settings.rebind("interact", KEY_G)
	var bound_keys := InputMap.action_get_events("interact").filter(func(e): return e is InputEventKey)
	_check("rebound key works", bound_keys.size() == 1 and bound_keys[0].physical_keycode == KEY_G)
	var pad_ok := true
	for pa in ["move_forward", "jump", "interact", "carry", "dump", "dig", "map", "toggle_mouse", "pan_wash", "pan_dump", "scroll_up", "scroll_down",
			"tool_next", "tool_prev", "inventory", "sprint", "camera", "headlamp", "scoop", "drive_gas", "drive_reverse"]:
		if not InputMap.action_get_events(pa).any(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion):
			pad_ok = false
	_check("controller reaches every action", pad_ok and InputMap.action_get_events("dig").any(func(e): return e is InputEventMouseButton))
	var was_pad := Settings.using_pad
	Settings.using_pad = true
	var pw := Settings.pad_words("Dig (left mouse), wash (right mouse), carry (F). E or walk away")
	_check("free text names pad buttons", not ("mouse" in pw) and "(Y)" in pw and "X or walk away" in pw)
	Settings.using_pad = was_pad
	var slot2 := InputEventJoypadButton.new()
	slot2.device = 2
	slot2.button_index = JOY_BUTTON_X
	slot2.pressed = true
	_check("a controller in any slot works", InputMap.event_is_action(slot2, "interact"))
	var xb := InputEventJoypadButton.new()
	xb.button_index = JOY_BUTTON_X
	xb.pressed = true
	Settings.note_input(xb)
	_check("prompts show controller buttons", Settings.using_pad and Hud.key("E").contains("X") and Settings.help(false).contains("Right stick"))
	Settings.rebind_pad("interact", JOY_BUTTON_Y)
	var ybtn := InputMap.action_get_events("interact").filter(func(e): return e is InputEventJoypadButton)
	_check("a controller button can be moved", ybtn.size() == 1 and ybtn[0].button_index == JOY_BUTTON_Y
		and Settings.pad_button_for("carry") == JOY_BUTTON_X and Hud.key("E").contains("Y"))
	Settings.reset_pad()
	_check("controller buttons reset", Settings.pad_button_for("interact") == JOY_BUTTON_X and Settings.pad_button_for("carry") == JOY_BUTTON_Y)
	map_view.toggle()
	map_view.cursor = Vector2(1000, 1000)
	var wp_before: int = map_view.waypoints.size()
	var abtn := InputEventJoypadButton.new()
	abtn.button_index = JOY_BUTTON_A
	abtn.pressed = true
	map_view._unhandled_input(abtn)
	_check("the controller drops a waypoint on the map", map_view.waypoints.size() == wp_before + 1)
	var xbtn2 := InputEventJoypadButton.new()
	xbtn2.button_index = JOY_BUTTON_X
	xbtn2.pressed = true
	map_view._unhandled_input(xbtn2)
	map_view.toggle()
	_check("and removes it", map_view.waypoints.size() == wp_before and not map_view.visible)
	var kb := InputEventKey.new()
	kb.physical_keycode = KEY_W
	kb.pressed = true
	Settings.note_input(kb)
	_check("keyboard takes prompts back", not Settings.using_pad and Hud.key("E").contains("G"))
	# The pause menu with the controller: D-pad down to Settings, A opens it, B comes back.
	var pad_ev := func(btn: int, down: bool) -> void:
		var e := InputEventJoypadButton.new()
		e.device = 0
		e.button_index = btn
		e.pressed = down
		get_viewport().push_input(e)
	menu.open()
	await get_tree().process_frame
	for btn in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_DOWN]:
		pad_ev.call(btn, true)
		await get_tree().process_frame
		pad_ev.call(btn, false)
		await get_tree().process_frame
	pad_ev.call(JOY_BUTTON_A, true)
	await get_tree().process_frame
	pad_ev.call(JOY_BUTTON_A, false)
	await get_tree().process_frame
	_check("A presses a pause-menu button", menu._opt_panel.visible)
	pad_ev.call(JOY_BUTTON_B, true)
	await get_tree().process_frame
	pad_ev.call(JOY_BUTTON_B, false)
	await get_tree().process_frame
	_check("B goes back", not menu._opt_panel.visible and menu.visible)
	menu._resume()
	Settings.note_input(kb)      # back to keyboard prompts for the checks below
	Input.action_press("drive_gas")
	var gas := Settings.drive_input()
	Input.action_release("drive_gas")
	Input.action_press("drive_reverse")
	var rev := Settings.drive_input()
	Input.action_release("drive_reverse")
	_check("left trigger drives forward, right trigger reverses", gas > 0.9 and rev < -0.9
		and InputMap.action_get_events("drive_gas").any(func(e): return e is InputEventJoypadMotion and e.axis == JOY_AXIS_TRIGGER_LEFT))
	_check("prompts show the new key", Hud.key("E").contains("G"))
	Settings.rebind("interact", KEY_F)
	_check("a clashing key swaps", Settings.key_for("carry") == KEY_G and Settings.key_for("interact") == KEY_F)
	Settings.reset_binds()
	# Roadside places: signposts and old places along the roads, each old place hiding something.
	var n_signs := world.places.filter(func(pl): return pl["kind"] == "sign").size()
	var n_old := world.places.size() - n_signs
	print("  roadside: %d signposts, %d old places, %d hidden stashes" % [n_signs, n_old, roadside.stashes.size()])
	_check("signposts and old places line the roads", n_signs >= 6 and n_old >= 10 and roadside.stashes.size() >= 1)
	var rs_money: int = inv.money
	var found_any := false
	var marks_before: int = map_view.marks.size()
	for rc in roadside.caches:
		if rc in roadside.stashes:
			continue
		rc.interact(player)
		if player.hud.note_open():
			player.hud.hide_note()
		found_any = true
	_check("searching the old places finds things", found_any and inv.money > rs_money and map_view.marks.size() > marks_before)
	var again: int = inv.money
	roadside.caches[0].interact(player)
	_check("a searched place is empty after", inv.money == again and inv.finds.has(roadside.caches[0].id))
	var st = roadside.stashes[0]
	st.interact(player)
	_check("a hidden stash pays well", inv.finds.has(st.id))
	# The lost mine trail: each clue only after the one before, each marks the next, gold at the end.
	var tr: Array = roadside.trail
	var tr_len := 0.0
	for k in range(1, tr.size()):
		tr_len += tr[k].global_position.distance_to(tr[k - 1].global_position)
	print("  lost mine trail: %d steps, %.1f km" % [tr.size(), tr_len / 1000.0])
	_check("the lost mine trail runs across the map", tr.size() == 5 and tr_len > 3500.0)
	if tr.size() == 5:
		tr[2].interact(player)
		_check("a trail clue means nothing out of order", not inv.finds.has(tr[2].id))
		var tr_marks: int = map_view.marks.size()
		var tr_nuggets: int = inv.nuggets.size()
		var mark_ok := true
		for k in tr.size():
			tr[k].interact(player)
			if player.hud.note_open():
				player.hud.hide_note()
			if k < tr.size() - 1:
				var xy: PackedStringArray = tr[k].mark_where.substr(4).split(",")
				var d := Vector2(float(xy[0]), float(xy[1])).distance_to(Vector2(tr[k + 1].global_position.x, tr[k + 1].global_position.z))
				mark_ok = mark_ok and d > 5.0 and d < 60.0
		_check("each trail clue marks the next spot, roughly", mark_ok and map_view.marks.size() == tr_marks + 4)
		_check("the lost mine pays out", tr.all(func(c): return inv.finds.has(c.id)) and inv.nuggets.size() > tr_nuggets)
	_check("keys reset", Settings.key_for("interact") == KEY_E and Settings.key_for("carry") == KEY_F and Hud.key("E").contains("E"))

	# Garnets: buy a sieve, stand on Garnet Beach, scoop, shake, flip; sell them in town.
	inv.money += 100
	town.store.select("sieve")
	town.store.interact(player)
	var gb := Garnets.beach
	var gspot := gb
	for k in 24:
		var a := TAU * k / 24.0
		var gp := gb + Vector2(cos(a), sin(a)) * 2.0
		var ge: float = world.river_info(gp.x, gp.y).x
		if ge > 0.3 and ge < 3.0:
			gspot = gp
			break
	_place_player(Vector3(gspot.x, 0.0, gspot.y), 0.0, 0.0)
	for i in 30:
		await get_tree().physics_frame
	inv.bucket.clear()
	_check("garnet beach is on the map and you can sieve there", world.sites.has("garnet") and inv.gear.has("sieve") and player._on_beach())
	inv.garnets = PackedFloat32Array()
	player._garnet_rng.seed = 4
	var sieved := 0
	for load_i in 12:
		player._sieve_step()
		player._sieve_t = 0.0
		await get_tree().physics_frame
		await get_tree().physics_frame
		player._sieve_step()
		for i in 30:
			await get_tree().physics_frame
		player._sieve_t = 0.0
		await get_tree().physics_frame
		await get_tree().physics_frame
		sieved += 1
	_check("sieving and flipping turns up garnets", inv.garnets.size() > 0 and player._sieve_phase == 0)
	var gmoney: int = inv.money
	var gvalue := 0
	for ct in inv.garnets:
		gvalue += Garnets.value(ct)
	inv.bars.clear()
	inv.nuggets = PackedFloat32Array()
	inv.specimens = PackedFloat32Array()
	town.assay.interact(player)
	_check("the assay office buys garnets", inv.garnets.is_empty() and inv.money == gmoney + gvalue)
	# Lights: the store sells them, they switch with E, save, and vehicles keep headlights on.
	player.inv.money += 5000
	for item in ["lantern", "flood", "tower", "headlamp"]:
		town.store.select(item)
		town.store.interact(player)
	var lan = machine_of("light_lantern")
	_check("lights delivered", lan != null and machine_of("light_flood") != null and machine_of("light_tower") != null)
	_check("bright headlamp", player.lamp_boost > 1.0)
	if lan != null:
		lan.interact(player)
		var ld: Dictionary = lan.to_dict()
		_check("a light switches off and saves so", not lan.on and ld["kind"] == "light_lantern" and ld["on"] == false)
		var lcopy = spawn_machine(ld["kind"])
		lcopy.from_dict(ld)
		_check("a saved light comes back", lcopy.display_name == "Lantern" and not lcopy.on)
		lcopy.queue_free()
		lan.interact(player)
	var ltruck = vehicle_of("truck")
	ltruck.toggle_lights()
	_check("headlights stay on with nobody in", ltruck.driver == null and ltruck._lights[0].visible and ltruck.to_dict()["lights"] == true)
	ltruck.toggle_lights()
	Settings.quality = 0
	Settings.apply_graphics(get_tree())
	_check("low quality turns off shadows", not day_night.sun.shadow_enabled)
	Settings.quality = 2
	Settings.apply_graphics(get_tree())
	_check("high quality has shadows", day_night.sun.shadow_enabled)
	_check_wildlife()
	_check_records()
	_check_pan_notes()
	_check_tutor()
	await _check_ledge()
	print("SELFTEST complete: %d failed" % _failures)


## Drive each vehicle along the valley road and report speed, distance and how level it stayed.
func _drivetest() -> void:
	var road: PackedVector2Array = world.roads[1]["pts"]
	for kind in ["atv", "truck"]:
		var v = vehicle_of(kind)
		var a := road[120]
		var b := road[121]
		var dir := (b - a).normalized()
		v.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(a.x, terrain.height_at(a.x, a.y) + 0.8, a.y))
		player.global_position = v.global_position
		_build_near_player()
		v.enter(player)
		for i in 30:
			await get_tree().physics_frame
		var start: Vector3 = v.global_position
		var line := ""
		var worst := 1.0
		Input.action_press("move_forward")
		for i in 480:
			await get_tree().physics_frame
			worst = minf(worst, v.global_basis.y.dot(Vector3.UP))
			if i % 60 == 59:
				line += " %d" % roundi(v.speed_kmh())
		Input.action_release("move_forward")
		Input.action_press("move_right")
		Input.action_press("move_forward")
		for i in 90:
			await get_tree().physics_frame
			worst = minf(worst, v.global_basis.y.dot(Vector3.UP))
		Input.action_release("move_right")
		Input.action_release("move_forward")
		Input.action_press("jump")
		var stop_frames := 0
		while v.linear_velocity.length() > 0.5 and stop_frames < 600:
			await get_tree().physics_frame
			stop_frames += 1
		Input.action_release("jump")
		print("DRIVETEST %-6s km/h each second:%s | %.0f m | least upright %.2f | stopped in %.1f s" % [
			kind, line, start.distance_to(v.global_position), worst, stop_frames / 60.0])
		v.exit()
		for i in 5:
			await get_tree().physics_frame


func _savetest(mode: String) -> void:
	await get_tree().physics_frame
	if mode == "write":
		_saving = true
		machine_of("sluice").place_at(_v3(world.river_point("Cabin Creek", 0.6, 0.5)), 0.0)
		vehicle_of("truck").load_cargo(spawn_machine("pump"))
		for i in 4:
			terrain.dig(_v3(world.river_point("Cabin Creek", 0.6, 1.3)), Player.DIG_DEPTH, Player.DIG_RADIUS)
		player.inv.money = 123
		player.inv.log_sample(900.0, 1300.0, 0.05)
		map_view.add_waypoint(Vector2(1500, 600))
		day_night.hours = 19.5
		save_now()
		print("SAVETEST wrote v2: money 123, sluice in creek, pump on the pickup, 4 digs, 1 sample, 1 waypoint, 7:30 pm, pickup at %s" %
			vehicle_of("truck").global_position.snapped(Vector3.ONE * 0.01))
	elif mode == "writev1":
		var f := FileAccess.open_compressed(SaveGame.path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
		f.store_var({"version": 1, "inventory": {"money": 777, "high_banker_bought": true, "goals": {"pan": true, "sold": true},
			"vial": PackedFloat32Array([0.01, 0.02]), "nuggets": PackedFloat32Array([0.6]), "bars": [{"grams": 2.5, "purity": 0.86}]}})
		f.close()
		print("SAVETEST wrote an M2-era save: money 777, vial 0.030 g, 1 nugget, 1 bar, goals pan+sold, high banker bought")
	else:
		var truck = vehicle_of("truck")
		var on_truck := 0
		for c in truck.cargo:
			if c != null:
				on_truck += 1
		var spot := world.river_point("Cabin Creek", 0.6, 1.3)
		var explored := 0
		for b in map_view.explored:
			if b > 0:
				explored += 1
		print("SAVETEST read: money %d, vial %.3f g, nuggets %d, bars %d, goals %d, samples %d, waypoints %d, explored cells %d, time %s" % [
			player.inv.money, player.inv.vial_grams(), player.inv.nuggets.size(), player.inv.bars.size(), player.inv.goals_done.size(),
			player.inv.samples.size(), map_view.waypoints.size(), explored, day_night.clock_text()])
		print("SAVETEST read: machines %d (on the pickup %d), high banker %s, dug %.2f, pickup at %s" % [
			get_tree().get_nodes_in_group("machines").size(), on_truck, machine_of("high_banker") != null,
			terrain.dug_at(spot.x, spot.y), truck.global_position.snapped(Vector3.ONE * 0.01)])
		SaveGame.delete()


func _check_tutor() -> void:
	var inv = player.inv
	var saved_goals: Dictionary = inv.goals_done.duplicate()
	var saved_hints: Dictionary = inv.hints.duplicate()
	var saved_bucket: Array = inv.bucket.duplicate()
	inv.goals_done = {"journal": true}
	inv.hints = {}
	inv.bucket = []
	_check("tutor: hotbar tip after the journal", tutor_hint().size() == 2 and tutor_hint()[0] == "hotbar")
	var once: bool = inv.first_hint("hotbar") and not inv.first_hint("hotbar")
	var next := tutor_hint()
	_check("tutor: a tip shows once", once and (next.is_empty() or next[0] != "hotbar"))
	inv.hints = {"hotbar": true, "inventory": true, "pan_notes": true, "night": true, "storm": true, "water_bucket": true}
	var old_pos := player.global_position
	var sh: Vector2 = world.shafts[0]["pos"]
	player.global_position = Vector3(sh.x + 10.0, old_pos.y, sh.y)
	_check("tutor: near an old shaft", tutor_hint().size() == 2 and tutor_hint()[0] == "shaft")
	player.global_position = old_pos
	inv.goals_done = {"journal": true, "sold": true}
	inv.hints["shaft"] = true
	var saved_finds: Dictionary = inv.finds
	inv.finds = {}
	_check("tutor: lost mine trail after the first sale", tutor_hint().size() == 2 and tutor_hint()[0] == "lost_mine")
	var Inv = load("res://scripts/player/inventory.gd")
	var copy = Inv.new()
	copy.from_dict(inv.to_dict())
	var d: Dictionary = inv.to_dict()
	d.erase("hints")
	var old = Inv.new()
	old.from_dict(d)
	_check("tutor: tips saved; old saves load with none", copy.hints.has("shaft") and old.hints.is_empty())
	var was_pad := Settings.using_pad
	Settings.using_pad = true
	var pw := Settings.pad_words("(E) (2) (Tab) (left click) left mouse")
	_check("tutor: goal words for the controller", pw == "(X) (LB/RB) (D-pad down) (A) RT")
	Settings.using_pad = was_pad
	inv.goals_done = saved_goals
	inv.hints = saved_hints
	inv.bucket = saved_bucket
	inv.finds = saved_finds


func _check_pan_notes() -> void:
	var PanNote = load("res://scripts/gold/pan_note.gd")
	var spot: Vector2 = deposits.rich_spot("Cabin Creek")
	var pn: Array = PanNote.make(deposits, spot.x, spot.y, PackedFloat32Array([0.004, 0.006, 0.08]))
	_check("pan notes: colors, size and a hint", str(pn[0]).begins_with("3 colors, coarse") and str(pn[1]).length() > 10)
	var far: Array = PanNote.make(deposits, spot.x + 900.0, spot.y + 900.0, PackedFloat32Array())
	_check("pan notes: empty pan away from water", far[0] == "No colors." and str(far[1]).length() > 10)
	var inv = player.inv
	for i in 12:
		inv.add_pan_note("note %d" % i)
	_check("pan notes: log keeps the newest", inv.pan_notes.size() == inv.PAN_NOTES_MAX and inv.pan_notes[-1] == "note 11")
	var d: Dictionary = inv.to_dict()
	var Inv = load("res://scripts/player/inventory.gd")
	var copy = Inv.new()
	copy.from_dict(d)
	_check("pan notes: saved and loaded", copy.pan_notes == inv.pan_notes)
	d.erase("pan_notes")
	var old = Inv.new()
	old.from_dict(d)
	_check("pan notes: old save loads empty", old.pan_notes.is_empty())
	print("  pan note: ", pn[0], " ", pn[1], " | ", far[1])


## The endgame: Dutch's Ledge is hidden until a mine find tells of it, costs a fortune, and
## its first gold ends the story.
func _check_ledge() -> void:
	var inv = player.inv
	var ledge := Claims.by_id("ledge")
	_check("Dutch's Ledge is on the books", not ledge.is_empty() and ledge["price"] == Claims.LEDGE_PRICE)
	var saved_finds: Dictionary = inv.finds.duplicate()
	inv.finds.erase("journal")
	inv.finds.erase("note")
	_check("the ledge stays hidden until a mine find tells of it", not Claims.known(ledge))
	inv.finds["note"] = true
	_check("the last note reveals it", Claims.known(ledge))
	for g in Inventory.GOALS:
		if g[0] != "ledge" and g[0] != "ledge_gold":
			inv.goals_done[g[0]] = true
	_check("the guide points at the claims office", inv.next_goal_id() == "ledge"
		and (goal_target() as Vector3).distance_to(town.claims_office.global_position) < 1.0)
	inv.money = Claims.LEDGE_PRICE - 1
	town.claims_office.select("ledge")
	town.claims_office.interact(player)
	_check("the ledge can't be bought short of the price", not inv.claims.has("ledge"))
	inv.money += 1
	town.claims_office.interact(player)
	_check("buying the ledge takes the money", inv.claims.has("ledge") and inv.money == 0 and inv.goals_done.has("ledge"))
	var gt = goal_target()
	_check("then the guide points at the ledge", inv.next_goal_id() == "ledge_gold"
		and gt != null and Vector2(gt.x, gt.z).distance_to(ledge["pos"]) < 1.0)
	var p: Vector2 = ledge["pos"]
	_check("the ledge is the richest ground", deposits.richness(p.x, p.y) > deposits.richness(world.sites["camp"]["pos"].x, world.sites["camp"]["pos"].y))
	player._found_ledge()
	_check("its first gold ends the story", inv.goals_done.has("ledge_gold") and hud.note_open() and inv.next_goal_id() == "")
	hud.hide_note()
	for k in saved_finds:
		inv.finds[k] = saved_finds[k]
	await get_tree().process_frame


func _check_records() -> void:
	var inv = player.inv
	var g0: float = inv.gold_found
	inv.add_gold(PackedFloat32Array([0.1, 7.5]))
	_check("records: gold found and biggest nugget", is_equal_approx(inv.gold_found, g0 + 7.6) and inv.biggest_nugget >= 7.5)
	var e0: int = inv.earned
	inv.record_sale(100, 50)
	inv.record_sale(50, 50)
	inv.record_sale(20, 51)
	_check("records: earnings and best day", inv.earned == e0 + 170 and inv.best_day >= 150 and inv.best_day_no != 51)
	var n0: int = inv.garnets_found
	inv.garnets.append(1.0)
	inv.watch_garnets()
	inv.watch_garnets()
	_check("records: garnets counted once", inv.garnets_found == n0 + 1)
	var d: Dictionary = inv.to_dict()
	var Inv = load("res://scripts/player/inventory.gd")
	var copy = Inv.new()
	copy.from_dict(d)
	_check("records: saved and loaded", copy.earned == inv.earned and copy.best_day == inv.best_day and copy.garnets_found == inv.garnets_found
		and is_equal_approx(copy.gold_found, inv.gold_found))
	d.erase("records")
	var old = Inv.new()
	old.from_dict(d)
	_check("records: old save loads with zeros", old.earned == 0 and old.gold_found == 0.0 and old.walked == 0.0)
	menu.open()
	menu._open_records()
	_check("records page opens", menu._rec_panel.visible and menu._rec_grid.get_child_count() >= 18)
	menu._resume()
