extends CharacterBody3D
## The prospector: first-person movement, digging, panning, carrying and hauling equipment,
## driving, and a headlamp.

const PanView = preload("res://scripts/panning/pan_view.gd")
const Paydirt = preload("res://scripts/gold/paydirt.gd")
const Terrain = preload("res://scripts/world/world_terrain.gd")
const DepositField = preload("res://scripts/gold/deposit_field.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Inventory = preload("res://scripts/player/inventory.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Claims = preload("res://scripts/core/claims.gd")

const WALK_SPEED := 4.0
const SPRINT_SPEED := 6.8
const WADE_FACTOR := 0.55
const CARRY_FACTOR := 0.8
const ACCEL := 30.0
const JUMP_VELOCITY := 4.4
const MOUSE_SENS := 0.0022
const EYE_HEIGHT := 1.65
const REACH := 3.2
const BUCKET_CAPACITY := 6            # 10 with the big bucket
const DIG_COOLDOWN := 0.55
const DIG_DEPTH := 0.15
const DIG_RADIUS := 0.85
const FEED_RANGE := 4.5
const PAN_PITCH := -0.22
const LAMP_ENERGY := 5.0
const WALK_HELP := "WASD move   Shift sprint   Space jump   LMB dig   E use / pan   F carry   Wheel adjust   R dump bucket   M map   L headlamp   Esc menu"
const DRIVE_HELP := "W/S drive   A/D steer   Space brake   V camera   R flip upright   E get out   M map   Esc menu"

var terrain: Terrain
var deposits: DepositField
var hud: Hud
var inv := Inventory.new()
var clock := ""
var map_open := false
var mine = null                       # the mine interior, while you're inside it
var lamp_charge := 1.0                # headlamp battery; only runs down underground, with hazards on
var air := 1.0                        # how much breath you have left in bad air

var camera: Camera3D
var pan_view: PanView = null
var carrying = null                   # the machine being carried, if any
var driving = null                    # the vehicle being driven, if any

var _col: CollisionShape3D
var _lamp: SpotLight3D
var _pan_dirt = null
var _pan_source := ""
var _target = null                    # what the crosshair is on, if it can be used
var _shovel: Node3D
var _shovel_rest := Transform3D()
var _aim := {}
var _dig_cd := 0.0
var _interact_block := 0.0
var _pitch_before_pan := 0.0
var _look_grace := 0.3                # ignore the mouse jump that comes with capturing the cursor
var _hud_t := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.8
	_col = CollisionShape3D.new()
	_col.shape = shape
	_col.position.y = 0.9
	add_child(_col)
	floor_snap_length = 0.35
	camera = Camera3D.new()
	camera.position.y = EYE_HEIGHT
	camera.fov = 75.0
	camera.near = 0.02
	camera.far = 1500.0
	add_child(camera)
	camera.make_current()
	_lamp = SpotLight3D.new()
	_lamp.spot_range = 32.0
	_lamp.spot_angle = 42.0
	_lamp.spot_attenuation = 0.6
	_lamp.light_energy = LAMP_ENERGY
	_lamp.light_color = Color(1.0, 0.96, 0.88)
	_lamp.position = Vector3(0.1, 0.05, 0.0)
	_lamp.visible = false
	camera.add_child(_lamp)
	_shovel = _make_shovel()
	camera.add_child(_shovel)
	_shovel_rest = _shovel.transform
	Settings.capture_mouse()
	refresh_hud()


func grace() -> void:
	_look_grace = 0.15
	_dig_cd = maxf(_dig_cd, 0.3)


func headlamp_on() -> bool:
	return _lamp.visible


func set_headlamp(on: bool) -> void:
	_lamp.visible = on


## A battery that is nearly flat gives a weak glow; it never goes fully dark.
func apply_lamp() -> void:
	var f := 1.0
	if mine != null and Settings.hazards:
		f = lerpf(0.1, 1.0, clampf(lamp_charge / 0.2, 0.0, 1.0))
	_lamp.light_energy = LAMP_ENERGY * f


func _unhandled_input(event: InputEvent) -> void:
	if driving != null or map_open:
		return
	var captured := Settings.mouse_captured()
	if event is InputEventMouseMotion:
		if captured and pan_view == null and _look_grace <= 0.0:
			var motion := event as InputEventMouseMotion
			rotate_y(-motion.relative.x * MOUSE_SENS)
			camera.rotation.x = clampf(camera.rotation.x - motion.relative.y * MOUSE_SENS, -1.5, 1.5)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if not captured:
			Settings.capture_mouse()
			grace()
			get_viewport().set_input_as_handled()
			return
		if pan_view == null and carrying == null and _target != null and _target.has_method("scroll"):
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_target.scroll(self, 1)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target.scroll(self, -1)
	elif event.is_action_pressed("headlamp"):
		_lamp.visible = not _lamp.visible


func _physics_process(delta: float) -> void:
	_look_grace -= delta
	_dig_cd -= delta
	_interact_block -= delta
	_hud_t -= delta
	if _hud_t <= 0.0:
		_hud_t = 0.2
		refresh_hud()
	if driving != null:
		global_position = driving.seat_position()
		velocity = Vector3.ZERO
		hud.set_prompt("[b]%s[/b]   %d km/h" % [driving.display_name, roundi(driving.speed_kmh())])
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var target := Vector3.ZERO
	if pan_view == null and not map_open:
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var dir := transform.basis * Vector3(input.x, 0.0, input.y)
		dir.y = 0.0
		dir = dir.normalized()
		var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
		if _in_water():
			speed *= WADE_FACTOR
		if carrying != null:
			speed *= CARRY_FACTOR
		target = dir * speed
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta)
	move_and_slide()
	if hud.note_open() and Vector2(velocity.x, velocity.z).length() > 1.0:
		hud.hide_note()
	if pan_view != null or map_open:
		return
	if carrying != null:
		_update_carry()
		return
	_aim = _look_hit()
	_target = _find_interactable(_aim)
	var captured := Settings.mouse_captured()
	if mine != null and global_position.y < mine.global_position.y - 3.0:
		global_position = mine.spawn_point()      # safety net: never fall out of the mine
		velocity = Vector3.ZERO
	if captured and Input.is_action_pressed("dig") and _dig_cd <= 0.0:
		if mine != null:
			_try_chip()
		else:
			_try_dig()
	if Input.is_action_just_pressed("interact") and _interact_block <= 0.0:
		if _target != null:
			_target.interact(self)
			refresh_hud()
			if driving != null:
				return
		else:
			_try_pan()
	if Input.is_action_just_pressed("carry") and _target != null and _target.has_method("set_carried"):
		start_carry(_target)
		return
	if Input.is_action_just_pressed("dump"):
		_dump_bucket()
	_update_prompt()


# --- Looking at things --------------------------------------------------------------

func _look_hit() -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_basis.z * REACH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


func _find_interactable(hit: Dictionary):
	if hit.is_empty():
		return null
	var n: Node = hit.get("collider") as Node
	for i in 4:
		if n == null:
			return null
		if n.has_method("interact"):
			return n
		n = n.get_parent()
	return null


func _aiming_at_ground() -> bool:
	if _aim.is_empty():
		return false
	var col: Object = _aim.get("collider")
	return col is Node and (col as Node).is_in_group("terrain")


# --- Driving -----------------------------------------------------------------------

func begin_driving(vehicle) -> void:
	driving = vehicle
	_col.disabled = true
	_shovel.visible = false
	velocity = Vector3.ZERO
	hud.set_help(DRIVE_HELP)
	inv.complete_goal("drive")


func end_driving(spot: Vector3, yaw: float) -> void:
	driving = null
	global_position = spot
	rotation = Vector3(0.0, yaw, 0.0)
	camera.rotation = Vector3.ZERO
	_col.disabled = false
	_shovel.visible = true
	velocity = Vector3.ZERO
	camera.make_current()
	_interact_block = 0.3
	hud.set_help(WALK_HELP)
	hud.set_prompt("")
	grace()


# --- Digging -----------------------------------------------------------------------

func _try_dig() -> void:
	if not _aiming_at_ground():
		return
	_dig_cd = DIG_COOLDOWN
	var machine = _feedable_machine()
	if machine == null and inv.bucket.size() >= inv.bucket_capacity():
		hud.toast("Bucket's full. Pan it at the water [E], dump it [R], or dump it into a machine.")
		return
	var p: Vector3 = _aim["position"]
	var res := terrain.dig(p, DIG_DEPTH, DIG_RADIUS)
	if res["removed"] < 0.02:
		hud.toast("Solid bedrock. Nothing left to dig here.")
		return
	var dirt := deposits.shovelful(res["x"], res["z"], res["top"], res["bottom"], res["bedrock"])
	_animate_dig()
	if machine != null:
		machine.feed(dirt)
		hud.toast("Into the %s hopper  (%d/%d)" % [machine.display_name.to_lower(), machine.hopper.size(), machine.hopper_capacity], Color(0.75, 0.9, 1.0), 1.2)
		on_machine_fed(machine)
	else:
		inv.bucket.append(dirt)
	if res["at_bedrock"]:
		hud.toast("Down to bedrock. This is where the gold settles.", Color(1.0, 0.9, 0.6))
	refresh_hud()


func _aiming_at_rock() -> bool:
	if _aim.is_empty():
		return false
	var col: Object = _aim.get("collider")
	return col is Node and (col as Node).is_in_group("mine")


## Chip the mine wall. Plain rock just breaks away; quartz vein goes in the ore sack.
func _try_chip() -> void:
	if not _aiming_at_rock():
		return
	# Hammer and chisel, miner's pick, rotary hammer: each is quicker and bites deeper.
	var tier: int = clampi(inv.tool_tier, 0, 2)
	_dig_cd = [0.95, 0.6, 0.28][tier]
	if inv.ore.size() >= inv.ore_capacity():
		hud.toast("Your ore sack is full. Take it home to the ore crusher.")
		return
	var res: Dictionary = mine.chip(_aim["position"], _aim["normal"], [1.0, 1.45, 1.8][tier])
	_animate_dig()
	var vein: int = int(res["vein_a"]) + int(res["vein_b"])
	if vein > 0:
		var expected := 1.1 * float(res["vein_a"]) + 2.4 * float(res["vein_b"])
		var pieces := int(expected) + (1 if randf() < expected - int(expected) else 0)
		var chunk := Paydirt.new()
		chunk.black_sand = 0.25
		for i in pieces:
			chunk.add_gold(deposits.piece(true))
		inv.ore.append(chunk)
		inv.complete_goal("ore")
		hud.toast("Quartz ore into the sack  (%d/%d)" % [inv.ore.size(), inv.ore_capacity()], Color(1.0, 0.95, 0.8), 1.5)
		# Now and then a piece comes away with gold showing in the quartz: a specimen.
		var rich: bool = int(res["vein_b"]) > 0
		if randf() < (0.12 if rich else 0.06):
			inv.add_specimen(randf_range(0.15, 0.6) * (1.4 if rich else 1.0))
			hud.toast("A specimen: gold showing in the quartz! Collectors pay extra for these. Ship it whole.", Color(1.0, 0.85, 0.3), 6.0)
	mine.hazards.on_chip(_aim["position"])
	refresh_hud()


## The nearest running machine with room in its hopper, if one is close enough to shovel into.
func _feedable_machine():
	var best = null
	var best_d := FEED_RANGE
	for m in get_tree().get_nodes_in_group("machines"):
		if not m.processes or not m.is_running() or m.hopper_space() <= 0:
			continue
		var d := global_position.distance_to(m.global_position)
		if d < best_d:
			best = m
			best_d = d
	return best


func _dump_bucket() -> void:
	if inv.bucket.is_empty():
		return
	inv.bucket.clear()
	hud.toast("Dumped the bucket.")
	refresh_hud()


func _animate_dig() -> void:
	var tw := create_tween()
	tw.tween_property(_shovel, "transform", _shovel_rest.translated_local(Vector3(0.0, -0.06, -0.22)), 0.1)
	tw.tween_property(_shovel, "transform", _shovel_rest, 0.28)


# --- Equipment ---------------------------------------------------------------------

func start_carry(machine) -> void:
	if machine.loaded_on != null:
		machine.loaded_on.unload_cargo(machine)
	carrying = machine
	machine.set_carried(true)
	_shovel.visible = false
	hud.toast("Carrying the %s. Left mouse (or F) sets it down, also onto a vehicle." % machine.display_name.to_lower())


func _update_carry() -> void:
	var from := camera.global_position
	var dir := -camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 6.0)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var hit_node: Node = null
	if not hit.is_empty():
		hit_node = hit.get("collider") as Node
	var captured := Settings.mouse_captured()
	var pressed := captured and (Input.is_action_just_pressed("dig") or Input.is_action_just_pressed("carry"))
	# Aiming at a vehicle with room: load it on.
	if hit_node != null and hit_node.is_in_group("vehicles") and from.distance_to(hit["position"]) < 4.0:
		var v = hit_node
		if v.free_slot() >= 0:
			hud.set_prompt("[b]Carrying: %s[/b]\n%s Load it onto the %s" % [carrying.display_name, Hud.key("Left mouse"), str(v.display_name)])
			if pressed:
				var m = carrying
				carrying = null
				v.load_cargo(m)
				_shovel.visible = true
				_dig_cd = 0.4
				_interact_block = 0.2
				inv.complete_goal("haul")
				hud.toast("Loaded the %s onto the %s." % [m.display_name.to_lower(), str(v.display_name)], Color(0.6, 1.0, 0.6))
			return
		hud.set_prompt("[b]Carrying: %s[/b]\nThe %s is full." % [carrying.display_name, str(v.display_name)])
		return
	var p: Vector3
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	if hit_node == null or not hit_node.is_in_group("terrain"):
		p = global_position + flat * 3.0
	else:
		p = hit["position"]
	var off := Vector2(p.x - global_position.x, p.z - global_position.z)
	if off.length() < 1.8:
		off = Vector2(flat.x, flat.z) * 1.8
		p = Vector3(global_position.x + off.x, p.y, global_position.z + off.y)
	carrying.place_at(p, rotation.y)
	var problem: String = carrying.problem()
	var t := "[b]Carrying: %s[/b]\n" % carrying.display_name
	if problem == "":
		t += "[color=#80dd80]It will run here.[/color]"
	else:
		t += "[color=#ffa060]It won't run here: %s.[/color]" % problem
	t += "\n%s Set it down" % Hud.key("Left mouse")
	hud.set_prompt(t)
	if pressed:
		_set_down()


func _set_down() -> void:
	var m = carrying
	carrying = null
	m.set_carried(false)
	_shovel.visible = true
	_dig_cd = 0.4
	_interact_block = 0.2
	var problem: String = m.problem()
	if problem == "":
		hud.toast("%s set up and ready." % m.display_name, Color(0.6, 1.0, 0.6))
		if m.kind == "sluice":
			inv.complete_goal("sluice_placed")
	else:
		hud.toast("Set down. It won't run here: %s." % problem, Color(1.0, 0.7, 0.4))
	refresh_hud()


func on_machine_fed(machine) -> void:
	if not machine.is_running():
		return
	if machine.kind == "sluice":
		inv.complete_goal("sluice_fed")
	elif machine.kind == "high_banker":
		inv.complete_goal("hb_running")


func on_cleaned_out(_machine) -> void:
	inv.complete_goal("cleaned")


# --- Panning -----------------------------------------------------------------------

func _try_pan() -> void:
	if inv.bucket.is_empty() and inv.cons.is_empty():
		hud.toast("Nothing to pan. Dig some gravel first (left mouse).")
		return
	if mine != null or not _near_water():
		hud.toast("You need water to pan. Get to the edge of a creek, or use the wash tub at the cabin.")
		return
	if not inv.bucket.is_empty():
		var dirt = inv.bucket.pop_front()
		if inv.gear.has("classifier") and dirt.gravel > 0.45:
			dirt.gravel = 0.45        # the screen keeps the big gravel out of the pan
		start_panning(dirt, "bucket")
	else:
		start_panning(inv.cons.pop_front(), "cons")


func start_panning(dirt, source: String = "bucket") -> void:
	_pan_dirt = dirt
	_pan_source = source
	pan_view = PanView.new()
	pan_view.setup(dirt, hud)
	camera.add_child(pan_view)
	pan_view.finished.connect(_on_pan_finished)
	pan_view.cancelled.connect(_on_pan_cancelled)
	_shovel.visible = false
	_pitch_before_pan = camera.rotation.x
	create_tween().tween_property(camera, "rotation:x", PAN_PITCH, 0.35)
	hud.show_pan(true)
	hud.set_prompt("")
	refresh_hud()


## What's in the pan right now, so a save can put it back: [source, dirt] or [].
func pending_pan() -> Array:
	if pan_view == null or _pan_dirt == null:
		return []
	return [_pan_source, _pan_dirt]


func _on_pan_finished(kept: PackedFloat32Array, lost: PackedFloat32Array, _black_sand: int) -> void:
	inv.add_gold(kept)
	inv.pans += 1
	var grams := 0.0
	var biggest := 0.0
	for m in kept:
		grams += m
		biggest = maxf(biggest, m)
	var msg: String
	if _pan_source == "cons":
		msg = "Concentrate cleaned up. A magnet pulls out the black sand: %d pieces, %.3f g of gold." % [kept.size(), grams]
		inv.complete_goal("cons_panned")
	elif kept.is_empty():
		msg = "Pan %d: no gold in that one." % inv.pans
	else:
		msg = "Pan %d: %d piece%s of gold, %.3f g" % [inv.pans, kept.size(), "" if kept.size() == 1 else "s", grams]
	if _pan_source == "bucket":
		inv.complete_goal("pan")
		var src: Vector3 = _pan_dirt.source
		if src != Vector3.ZERO:
			inv.log_sample(src.x, src.z, grams)
	if not lost.is_empty():
		msg += "   (%d washed out)" % lost.size()
	if biggest >= Inventory.NUGGET_MASS:
		msg += "\nA nugget! %.2f g" % biggest
	elif biggest >= 0.05:
		msg += "\nA nice picker in there: %.2f g" % biggest
	hud.toast(msg, Color(1.0, 0.85, 0.4), 5.0)
	_end_panning()


func _on_pan_cancelled() -> void:
	hud.toast("Dumped the pan.")
	_end_panning()


func _end_panning() -> void:
	pan_view.queue_free()
	pan_view = null
	_pan_dirt = null
	_shovel.visible = true
	create_tween().tween_property(camera, "rotation:x", _pitch_before_pan, 0.3)
	hud.show_pan(false)
	_interact_block = 0.25
	refresh_hud()


func _near_water() -> bool:
	var fwd := -global_basis.z
	for d: float in [0.0, 0.8, 1.6, 2.4]:
		var p := global_position + fwd * d
		if terrain.water_depth(p.x, p.z) > 0.02:
			return true
	for ring: float in [1.2, 2.2]:
		for k in 10:
			var a := TAU * k / 10.0
			var p := global_position + Vector3(cos(a), 0.0, sin(a)) * ring
			if terrain.water_depth(p.x, p.z) > 0.02:
				return true
	return false


func _in_water() -> bool:
	return mine == null and terrain.water_depth(global_position.x, global_position.z) > 0.15


# --- HUD and visuals ---------------------------------------------------------------

func _update_prompt() -> void:
	if _target != null:
		hud.set_prompt(_target.prompt(self))
		return
	var parts := PackedStringArray()
	if mine != null:
		var tool_name: String = ["hammer and chisel", "miner's pick", "rotary hammer"][clampi(inv.tool_tier, 0, 2)]
		hud.set_prompt(Hud.key("Left mouse") + " Chip the rock with your %s (white quartz carries gold)" % tool_name if _aiming_at_rock() else "")
		return
	if _near_water():
		if not inv.bucket.is_empty():
			parts.append(Hud.key("E") + " Pan a shovelful")
		elif not inv.cons.is_empty():
			parts.append(Hud.key("E") + " Pan a jar of concentrate")
	if _aiming_at_ground():
		var machine = _feedable_machine()
		if machine != null:
			parts.append(Hud.key("Left mouse") + " Dig into the %s" % machine.display_name.to_lower())
		elif inv.bucket.size() < inv.bucket_capacity():
			parts.append(Hud.key("Left mouse") + " Dig")
		else:
			parts.append("Bucket full: " + Hud.key("R") + " dump it")
	hud.set_prompt("      ".join(parts))


func refresh_hud() -> void:
	var extra := PackedStringArray()
	if mine == null and not Claims.list.is_empty():
		var p := global_position if driving == null else (driving.global_position as Vector3)
		extra.append(terrain.world.region_name(p.x, p.z))
		var c := Claims.at(p.x, p.z)
		if c.is_empty():
			extra.append("Public land: pan and shovel only")
		elif Claims.is_owned(c["id"]):
			extra.append("%s: yours" % c["name"])
		else:
			extra.append("%s: for sale, $%d" % [c["name"], c["price"]])
		if inv.gear.has("detector") and driving == null:
			var r: float = deposits.richness(p.x, p.z)
			var bars := clampi(ceili(r / 0.3), 0, 6)
			extra.append("Detector   %s%s   %s" % ["|".repeat(bars), ".".repeat(6 - bars),
				["nothing", "a trace", "some color", "fair ground", "good ground", "rich ground", "very rich ground"][bars]])
	if mine != null and Settings.hazards:
		extra.append("Headlamp battery   %d%%" % roundi(lamp_charge * 100.0))
		if air < 0.995:
			extra.append("Air   %d%%   get back to good air!" % roundi(air * 100.0))
	hud.set_status(inv, inv.bucket_capacity(), clock, extra)
	hud.set_goal(inv.next_goal())


func _make_shovel() -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0.34, -0.36, -0.5)
	root.rotation = Vector3(deg_to_rad(-28.0), deg_to_rad(10.0), deg_to_rad(-6.0))
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.46, 0.31, 0.18)
	wood.roughness = 0.75
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.36, 0.37, 0.38)
	steel.metallic = 0.8
	steel.roughness = 0.45
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.016
	shaft.bottom_radius = 0.018
	shaft.height = 1.0
	shaft.radial_segments = 10
	root.add_child(_part(shaft, wood, Vector3(0, 0, -0.25), Vector3(deg_to_rad(90.0), 0, 0)))
	var blade := BoxMesh.new()
	blade.size = Vector3(0.22, 0.008, 0.27)
	root.add_child(_part(blade, steel, Vector3(0, -0.012, -0.86), Vector3(deg_to_rad(-12.0), 0, 0)))
	var grip := CylinderMesh.new()
	grip.top_radius = 0.022
	grip.bottom_radius = 0.022
	grip.height = 0.12
	root.add_child(_part(grip, wood, Vector3(0, 0, 0.27), Vector3(0, 0, deg_to_rad(90.0))))
	return root


func _part(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- Test hooks (used by the harness in main.gd) ------------------------------------

func debug_pan(mode: String) -> void:
	var dirt := Paydirt.new()
	dirt.black_sand = 0.22
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 14:
		dirt.add_gold(rng.randf_range(0.002, 0.03))
	dirt.add_gold(0.14)
	start_panning(dirt)
	pan_view.scripted = true
	var sim := pan_view.sim
	var dt := 1.0 / 60.0
	match mode:
		"shaken":
			for i in 120:
				sim.step(dt, true, 0.0, 0.0)
		"washing":
			for i in 90:
				sim.step(dt, true, 0.0, 0.0)
			for i in 70:
				sim.step(dt, false, 18.0, 0.0)
			pan_view.washing = true
			pan_view.wash_target = 18.0
			pan_view.tilt = 18.0
		"done":
			var t := 0.0
			while not sim.done and t < 90.0:
				var phase := fmod(t, 3.2)
				sim.step(dt, phase < 1.2, 18.0 if phase >= 1.2 else 0.0, 0.0)
				t += dt
