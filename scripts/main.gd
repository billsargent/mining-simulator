extends Node3D
## M2 "Bucket to bar": the test valley with Grandpa's place, equipment, saving, and a test harness.
##
## Command-line flags (after `--`) for automated checks. Any flag starts a fresh world and
## turns saving off:
##   --selftest                         run the whole loop headless and print results
##   --shot=<file.png>                  save a screenshot and quit
##   --cam=x,z,yaw,pitch                place the player first (angles in degrees)
##   --pan=fresh|shaken|washing|done    open the pan in a given state
##   --dig=N                            dig a few holes in front of the camera
##   --demo                             set up the sluice, high banker and pump by the creek
##   --fps                              print the frame rate for 8 seconds

const Valley = preload("res://scripts/world/valley.gd")
const Terrain = preload("res://scripts/world/terrain.gd")
const Scatter = preload("res://scripts/world/scatter.gd")
const DepositField = preload("res://scripts/gold/deposit_field.gd")
const PanSim = preload("res://scripts/panning/pan_sim.gd")
const Player = preload("res://scripts/player/player.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const PauseMenu = preload("res://scripts/ui/pause_menu.gd")
const Tex = preload("res://scripts/util/tex.gd")
const HomeBase = preload("res://scripts/base/home_base.gd")
const Sluice = preload("res://scripts/machines/sluice.gd")
const HighBanker = preload("res://scripts/machines/high_banker.gd")
const Pump = preload("res://scripts/machines/pump.gd")
const SaveGame = preload("res://scripts/core/save_game.gd")

const SEED := 1849
const BASE_X := 118.0
const BASE_DIST := 22.0          # metres from the creek's centerline to the cabin yard
const AUTOSAVE_SECONDS := 60.0

var valley: Valley
var deposits: DepositField
var terrain: Terrain
var scatter: Scatter
var base: HomeBase
var player: Player
var hud: Hud
var menu: PauseMenu

var _opts := {}
var _saving := true
var _failures := 0


func _ready() -> void:
	add_to_group("game")
	_opts = _parse_args()
	_saving = _opts.is_empty()
	_setup_input()
	valley = Valley.new(SEED)
	deposits = DepositField.new(valley, SEED)
	_build_environment()
	terrain = Terrain.new()
	terrain.valley = valley
	add_child(terrain)
	terrain.generate()
	base = HomeBase.new()
	add_child(base)
	var site := _base_site()
	base.build(terrain, site[0], site[1])
	_build_water()
	_build_bounds()
	scatter = Scatter.new()
	scatter.terrain = terrain
	scatter.valley = valley
	scatter.deposits = deposits
	scatter.exclude(base.center, 15.0, 10.5)
	add_child(scatter)
	scatter.build(SEED)
	hud = Hud.new()
	add_child(hud)
	player = Player.new()
	player.terrain = terrain
	player.deposits = deposits
	player.hud = hud
	add_child(player)
	menu = PauseMenu.new()
	menu.main = self
	add_child(menu)
	var load_test: bool = _opts.get("savetest", "") == "read"
	if _opts.has("savetest"):
		SaveGame.path = "user://loadtest.dat"
	if not ((_saving or load_test) and _load_game()):
		_start_fresh()
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


# --- World setup -------------------------------------------------------------------

## The cabin sits on the north floodplain, facing the creek. Returns [center, facing].
func _base_site() -> Array:
	var dz := valley.center_dz(BASE_X)
	var z := valley.center_z(BASE_X) + BASE_DIST * sqrt(1.0 + dz * dz)
	return [Vector3(BASE_X, 0.0, z), Vector3(dz, 0.0, -1.0).normalized()]


func _start_fresh() -> void:
	var sluice = spawn_machine("sluice")
	sluice.place_at(base.slot_position(0), base.slot_yaw())
	player.global_position = base.spawn_point
	player.rotation.y = base.spawn_yaw
	hud.toast("Grandpa's claim. Your next step is always in the top-left corner.", Color(1.0, 0.9, 0.6), 8.0)


func spawn_machine(kind: String):
	var m
	match kind:
		"sluice":
			m = Sluice.new()
		"high_banker":
			m = HighBanker.new()
		"pump":
			m = Pump.new()
		_:
			return null
	add_child(m)
	m.setup(terrain, valley)
	return m


func machine_of(kind: String):
	for m in get_tree().get_nodes_in_group("machines"):
		if m.kind == kind:
			return m
	return null


## Called by the order board.
func deliver(item: String) -> void:
	if item == "high_banker":
		spawn_machine("high_banker").place_at(base.slot_position(1), base.slot_yaw())
		spawn_machine("pump").place_at(base.slot_position(2), base.slot_yaw())


func _setup_input() -> void:
	_bind_key("move_forward", KEY_W)
	_bind_key("move_back", KEY_S)
	_bind_key("move_left", KEY_A)
	_bind_key("move_right", KEY_D)
	_bind_key("sprint", KEY_SHIFT)
	_bind_key("jump", KEY_SPACE)
	_bind_key("interact", KEY_E)
	_bind_key("carry", KEY_F)
	_bind_key("dump", KEY_R)
	_bind_key("pan_dump", KEY_Q)
	_bind_key("toggle_mouse", KEY_ESCAPE)
	if not InputMap.has_action("dig"):
		InputMap.add_action("dig")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("dig", mb)


func _bind_key(action: StringName, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.48, 0.76)
	sky_mat.sky_horizon_color = Color(0.70, 0.76, 0.82)
	sky_mat.ground_horizon_color = Color(0.58, 0.60, 0.58)
	sky_mat.ground_bottom_color = Color(0.25, 0.24, 0.22)
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
	env.fog_light_color = Color(0.68, 0.74, 0.82)
	env.fog_density = 0.0035
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.05
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -128.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(Valley.SIZE, Valley.SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("wave_a", Tex.noise(0.02, 11, 256, true, 3.0))
	mat.set_shader_parameter("wave_b", Tex.noise(0.035, 12, 256, true, 2.0))
	var water := MeshInstance3D.new()
	water.mesh = plane
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(Valley.SIZE * 0.5, Valley.WATER_LEVEL, Valley.SIZE * 0.5)
	add_child(water)


## Invisible walls at the edge of the test map.
func _build_bounds() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var s := Valley.SIZE
	var walls := [
		[Vector3(s * 0.5, 50.0, 0.5), Vector3(s, 200.0, 1.0)],
		[Vector3(s * 0.5, 50.0, s - 0.5), Vector3(s, 200.0, 1.0)],
		[Vector3(0.5, 50.0, s * 0.5), Vector3(1.0, 200.0, s)],
		[Vector3(s - 0.5, 50.0, s * 0.5), Vector3(1.0, 200.0, s)],
	]
	for w in walls:
		var box := BoxShape3D.new()
		box.size = w[1]
		var cs := CollisionShape3D.new()
		cs.shape = box
		cs.position = w[0]
		body.add_child(cs)


# --- Saving ------------------------------------------------------------------------

func save_now() -> void:
	if not _saving:
		return
	var inv_data: Dictionary = player.inv.to_dict()
	var pending := player.pending_pan()
	if not pending.is_empty():
		(inv_data[pending[0]] as Array).push_front(pending[1].to_dict())
	var machines := []
	for m in get_tree().get_nodes_in_group("machines"):
		machines.append(m.to_dict())
	SaveGame.write({
		"player": {"pos": player.global_position, "yaw": player.rotation.y},
		"inventory": inv_data,
		"terrain": {"heights": terrain.heights, "dug": terrain.dug_amount},
		"machines": machines,
		"furnace": base.furnace.to_dict(),
	})


func _load_game() -> bool:
	var data := SaveGame.read()
	if data.is_empty():
		return false
	var t: Dictionary = data.get("terrain", {})
	var h: PackedFloat32Array = t.get("heights", PackedFloat32Array())
	if h.size() != terrain.heights.size():
		return false
	terrain.restore(h, t.get("dug", PackedFloat32Array()))
	scatter.hide_dug_grass()
	for md in data.get("machines", []):
		var m = spawn_machine(md.get("kind", ""))
		if m != null:
			m.from_dict(md)
	player.inv.from_dict(data.get("inventory", {}))
	base.furnace.from_dict(data.get("furnace", {}))
	var p: Dictionary = data.get("player", {})
	player.global_position = p.get("pos", base.spawn_point)
	player.rotation.y = p.get("yaw", base.spawn_yaw)
	player.refresh_hud()
	hud.toast("Welcome back.", Color(1.0, 0.9, 0.6))
	return true


func new_game() -> void:
	_saving = false
	SaveGame.delete()
	get_tree().paused = false
	get_tree().reload_current_scene()


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
	if _opts.has("demo"):
		_demo_setup()
	if _opts.has("cam"):
		_apply_cam(_opts["cam"])
	if _opts.has("selftest"):
		await _selftest()
		get_tree().quit()
		return
	if _opts.has("savetest"):
		await get_tree().physics_frame
		if _opts["savetest"] == "write":
			_saving = true
			var x := BASE_X + 4.0
			machine_of("sluice").place_at(_creek_point(x, 0.55), 0.0)
			machine_of("sluice").feed(deposits.shovelful(x, 120.0, 0.2, 0.05, 0.0))
			for i in 4:
				terrain.dig(_creek_point(x, 1.3), Player.DIG_DEPTH, Player.DIG_RADIUS)
			player.inv.money = 123
			player.inv.add_gold(PackedFloat32Array([0.01, 0.02, 0.5]))
			player.inv.bars.append({"grams": 2.5, "purity": 0.86})
			player.inv.complete_goal("pan")
			player.global_position = _creek_point(x, 2.0) + Vector3(0, 1.0, 0)
			save_now()
			print("SAVETEST wrote: money 123, vial 0.030 g, 1 nugget, 1 bar, sluice in creek with 1 in hopper, 4 digs")
		else:
			var s = machine_of("sluice")
			var dig_spot := _creek_point(BASE_X + 4.0, 1.3)
			print("SAVETEST read: money %d, vial %.3f g, nuggets %d, bars %d, goal 'pan' done %s" % [
				player.inv.money, player.inv.vial_grams(), player.inv.nuggets.size(), player.inv.bars.size(), player.inv.goals_done.has("pan")])
			print("SAVETEST read: machines %d, sluice running %s, hopper %d, dug %.2f, player at creek %s" % [
				get_tree().get_nodes_in_group("machines").size(), s.is_running(), s.hopper.size(),
				terrain.dug_at(dig_spot.x, dig_spot.z), player.global_position.distance_to(_creek_point(BASE_X + 4.0, 2.0)) < 2.0])
			SaveGame.delete()
		get_tree().quit()
		return
	if _opts.has("fps"):
		for sample in 4:
			await get_tree().create_timer(2.0).timeout
			print("FPS after %ds: %d   (%s)" % [(sample + 1) * 2, Engine.get_frames_per_second(), RenderingServer.get_video_adapter_name()])
		get_tree().quit()
		return
	if _opts.has("shot"):
		for i in 60:
			await get_tree().process_frame
		if _opts.has("cam"):
			_apply_cam(_opts["cam"])
		if _opts.has("dig"):
			var fwd := -player.global_basis.z
			for spot in 3:
				var p := player.global_position + fwd * (2.2 + spot * 1.4) + player.global_basis.x * (spot - 1) * 1.2
				for i in int(_opts["dig"]) - spot * 2:
					terrain.dig(p, Player.DIG_DEPTH, Player.DIG_RADIUS)
			for i in 10:
				await get_tree().process_frame
		if _opts.has("pan"):
			player.debug_pan(_opts["pan"])
			for i in 30:
				await get_tree().process_frame
		if _opts.has("carry"):
			player.start_carry(machine_of(_opts["carry"]))
			for i in 20:
				await get_tree().process_frame
		if _opts.has("menu"):
			menu.open()
			for i in 5:
				await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(_opts["shot"])
		print("Saved screenshot: ", _opts["shot"])
		get_tree().quit()


func _apply_cam(spec: String) -> void:
	var c := spec.split_floats(",")
	player.position = Vector3(c[0], terrain.height_at(c[0], c[1]) + 0.1, c[1])
	player.rotation.y = deg_to_rad(c[2])
	player.camera.rotation.x = deg_to_rad(c[3])


## A point across the creek at x: frac 0 = centerline, 1 = water's edge on the cabin side.
func _creek_point(x: float, frac: float) -> Vector3:
	var dz := valley.center_dz(x)
	return Vector3(x, 0.0, valley.center_z(x) + frac * valley.half_width(x) * sqrt(1.0 + dz * dz))


func _demo_setup() -> void:
	var x := BASE_X + 4.0
	machine_of("sluice").place_at(_creek_point(x, 0.55), 0.0)
	deliver("high_banker")
	machine_of("pump").place_at(_creek_point(x + 9.0, 1.15), 0.0)
	machine_of("high_banker").place_at(_creek_point(x + 11.0, 3.2), PI)
	for kind in ["sluice", "high_banker"]:
		var m = machine_of(kind)
		var p := m.global_position as Vector3
		for i in 6:
			m.processed_total += 1
			m.feed(deposits.shovelful(p.x, p.z, 0.3, 0.15, 0.0))
		for i in 3:
			m._process_one(deposits.shovelful(p.x, p.z, 0.15, 0.0, 0.0))


func _check(name: String, ok: bool) -> void:
	print("SELFTEST %-34s %s" % [name, "ok" if ok else "FAILED"])
	if not ok:
		_failures += 1


func _selftest() -> void:
	SaveGame.path = "user://selftest.dat"
	_saving = true
	for i in 60:
		await get_tree().physics_frame
	var inv = player.inv
	var pp := player.global_position
	_check("standing on the ground", absf(pp.y - terrain.height_at(pp.x, pp.z)) < 0.25)

	# Sluice in the creek, fed by digging right next to it.
	var x := BASE_X + 4.0
	var sluice = machine_of("sluice")
	sluice.place_at(_creek_point(x, 0.55), 0.0)
	_check("sluice has water", sluice.water_problem() == "")
	var bank := _creek_point(x, 1.2)
	var fed := 0
	for i in 8:
		var res := terrain.dig(bank, Player.DIG_DEPTH, Player.DIG_RADIUS)
		if res["removed"] < 0.02:
			break
		if sluice.feed(deposits.shovelful(res["x"], res["z"], res["top"], res["bottom"], res["bedrock"])):
			fed += 1
	for i in 150:
		await get_tree().physics_frame
	_check("sluice runs on its own", sluice.processed >= 1)
	while not sluice.hopper.is_empty():
		sluice._process_one(sluice.hopper.pop_front())
	print("  fed %d shovels: %d pieces caught, %d lost" % [fed, sluice.caught.size(), sluice.lost.size()])

	# Clean out and pan the concentrate.
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
	print("  concentrate: %d pieces in, %d kept in %.1fs; vial %.3f g, %d nuggets" % [
		jar.gold.size(), sim.gold_kept().size(), t, inv.vial_grams(), inv.nuggets.size()])
	if inv.vial_grams() <= 0.0:
		inv.add_gold(PackedFloat32Array([0.05]))

	# Smelt and sell.
	var furnace = base.furnace
	var grams: float = inv.vial_grams()
	furnace.interact(player)
	for i in 100:
		furnace.advance(0.25)
		if furnace.is_molten():
			furnace.interact(player)
		if furnace.is_ready():
			furnace.interact(player)
			break
	_check("smelting makes a bar", inv.bars.size() == 1 and inv.vial_grams() == 0.0)
	var money_before: int = inv.money
	base.ship_box.interact(player)
	_check("shipping pays", inv.money > money_before and inv.bars.is_empty())
	print("  %.3f g melted, sold for $%d" % [grams, inv.money - money_before])

	# Order and set up the high banker and pump.
	inv.money += 400
	base.order_board.interact(player)
	var hb = machine_of("high_banker")
	var pump = machine_of("pump")
	_check("high banker and pump delivered", hb != null and pump != null)
	pump.place_at(_creek_point(x + 9.0, 1.15), 0.0)
	_check("pump reaches water", pump.water_problem() == "")
	hb.place_at(_creek_point(x + 11.0, 3.2), 0.0)
	hb.refresh_pump()
	_check("high banker hooked to the pump", hb.water_problem() == "")
	pump.place_at(_creek_point(x + 70.0, 1.15), 0.0)
	hb.refresh_pump()
	_check("too far from the pump: no water", hb.water_problem() != "")

	# Carry and set down through the player.
	player.start_carry(sluice)
	_check("carrying turns the sluice off", not sluice.is_running())
	player._set_down()
	_check("set down again", player.carrying == null)

	# Save, then read it back.
	save_now()
	var data := SaveGame.read()
	_check("save round trip", int(data.get("inventory", {}).get("money", -1)) == inv.money and (data.get("machines", []) as Array).size() == 3)
	SaveGame.delete()

	# Walk.
	var start := player.global_position
	Input.action_press("move_forward")
	for i in 60:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	_check("walking moves the player", start.distance_to(player.global_position) > 1.5)
	print("SELFTEST complete: %d failed" % _failures)
