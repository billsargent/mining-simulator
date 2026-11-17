extends CharacterBody3D
## The prospector: first-person movement, digging, panning, carrying and hauling equipment,
## driving, and a headlamp.
const Sfx = preload("res://scripts/core/sfx.gd")

const PanView = preload("res://scripts/panning/pan_view.gd")
const Paydirt = preload("res://scripts/gold/paydirt.gd")
const Terrain = preload("res://scripts/world/world_terrain.gd")
const DepositField = preload("res://scripts/gold/deposit_field.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Inventory = preload("res://scripts/player/inventory.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Claims = preload("res://scripts/core/claims.gd")
const Garnets = preload("res://scripts/gold/garnets.gd")
const Tex = preload("res://scripts/util/tex.gd")

const WALK_SPEED := 4.0
const SPRINT_SPEED := 6.8
const WADE_FACTOR := 0.55
const CARRY_FACTOR := 0.8
const ACCEL := 30.0
const JUMP_VELOCITY := 4.4
const EYE_HEIGHT := 1.65
const REACH := 3.2
const BUCKET_CAPACITY := 6            # 10 with the big bucket
const DIG_COOLDOWN := 0.55
const DIG_DEPTH := 0.15
const DIG_RADIUS := 0.85
const FEED_RANGE := 4.5
const PAN_PITCH := -0.22
const LAMP_ENERGY := 5.0
var lamp_boost := 1.0                 # 1.8 with the bright headlamp from the store

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
	camera.fov = Settings.fov
	camera.add_to_group("fov_camera")
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
	_lamp.light_energy = LAMP_ENERGY * lamp_boost * f


func _unhandled_input(event: InputEvent) -> void:
	if driving != null or map_open:
		return
	var captured := Settings.mouse_captured()
	if event is InputEventMouseMotion:
		if captured and pan_view == null and _look_grace <= 0.0:
			var motion := event as InputEventMouseMotion
			rotate_y(-motion.relative.x * Settings.look_speed())
			camera.rotation.x = clampf(camera.rotation.x - motion.relative.y * Settings.look_speed() * (-1.0 if Settings.invert_y else 1.0), -1.5, 1.5)
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
	elif event.is_action_pressed("scroll_up") or event.is_action_pressed("scroll_down"):
		if pan_view == null and carrying == null and _target != null and _target.has_method("scroll"):
			_target.scroll(self, 1 if event.is_action_pressed("scroll_up") else -1)


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
		var line := "[b]%s[/b]   %d km/h" % [driving.display_name, roundi(driving.speed_kmh())]
		if driving.has_method("action"):
			line += "
" + driving.drive_hint()
			if Input.is_action_just_pressed("scoop") and Settings.mouse_captured() and not map_open:
				driving.action(self)
		hud.set_prompt(line)
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var target := Vector3.ZERO
	if pan_view == null and not map_open:
		var look := Settings.pad_look(delta)
		if look != Vector2.ZERO:
			rotate_y(-look.x)
			camera.rotation.x = clampf(camera.rotation.x - look.y, -1.5, 1.5)
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var dir := transform.basis * Vector3(input.x, 0.0, input.y)
		dir.y = 0.0
		dir = dir.normalized()
		var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
		if _in_water():
			speed *= WADE_FACTOR
		if carrying != null:
			speed *= CARRY_FACTOR
			if carrying.has_method("carry_factor"):
				speed *= carrying.carry_factor()
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
	elif mine == null and driving == null:
		# Safety net: after a long jump (leaving the mine, a teleport) the ground's collision can
		# take a moment to build. Never let the player drop through it meanwhile.
		var g := terrain.height_at(global_position.x, global_position.z)
		if global_position.y < g - 0.5:
			global_position.y = g + 0.05
			velocity.y = 0.0
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
	if Input.is_action_just_pressed("carry") and _target != null and _target.has_method("toggle_lights"):
		_target.toggle_lights()
	elif Input.is_action_just_pressed("carry") and _target != null and _target.has_method("set_carried"):
		start_carry(_target)
		return
	if Input.is_action_just_pressed("dump"):
		_dump_bucket()
	_update_sieve(delta)
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
	hud.set_help(Settings.help(true))
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
	hud.set_help(Settings.help(false))
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
	Sfx.play("dig", p)
	if machine != null:
		Sfx.play("pour", machine.global_position, -4.0)
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
	Sfx.play("chip", _aim["position"], 0.0, [1.0, 0.9, 1.15][tier])
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
	elif randf() < Garnets.MINE_CHANCE * float(res.get("rock", 1)):
		# The schist round the veins carries a garnet now and then.
		var ct := Garnets.carats(_garnet_rng)
		inv.garnets.append(ct)
		hud.toast("A garnet came out of the rock: %.2f carats. The assay office buys them." % ct, Color(0.95, 0.4, 0.45), 4.0)
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
	Sfx.play("dump", global_position)
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


func on_cleaned_out(machine) -> void:
	Sfx.play("pour", machine.global_position)
	inv.complete_goal("cleaned")


# --- Panning -----------------------------------------------------------------------

func _try_pan() -> void:
	if _sieve_phase > 0 or (inv.gear.has("sieve") and _on_beach() and inv.bucket.is_empty()):
		_sieve_step()
		return
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
	Sfx.play("splash", null, -4.0)
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
		if inv.goals_done.has("pan") and (kept.size() >= 3 or inv.pans >= 8):
			if inv.complete_goal("read_creek"):
				msg += "
Good showing! That's how you read a creek: look for where the water slows."
		var src: Vector3 = _pan_dirt.source
		if src != Vector3.ZERO:
			inv.log_sample(src.x, src.z, grams)
	if not lost.is_empty():
		msg += "   (%d washed out)" % lost.size()
	if not kept.is_empty():
		Sfx.play("clink", null, -10.0 if biggest < 0.05 else -4.0, 1.4)
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
	if _sieve_phase == 1:
		hud.set_prompt("Shaking the sieve under water...  the heavy garnets sink to the bottom")
		return
	if _sieve_phase == 2:
		hud.set_prompt(Hud.key("E") + " Flip the sieve")
		return
	if _sieve_phase == 3:
		return
	if _on_beach() and inv.bucket.is_empty():
		if inv.gear.has("sieve"):
			parts.append(Hud.key("E") + " Scoop gravel into the garnet sieve")
		else:
			parts.append("Garnet Beach: buy a garnet sieve at the general store to look for garnets")
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


# --- Garnet sieve -------------------------------------------------------------------------------

var _sieve: Node3D
var _sieve_phase := 0          # 0 idle, 1 shaking, 2 ready to flip, 3 showing what came up
var _sieve_t := 0.0
var _sieve_found := []
var _garnet_rng := RandomNumberGenerator.new()
const SIEVE_SHAKE := 6.0


func _on_beach() -> bool:
	return mine == null and terrain != null and Garnets.on_beach(terrain.world, global_position.x, global_position.z)


func _sieve_step() -> void:
	match _sieve_phase:
		0:
			if _sieve == null:
				_sieve = _make_sieve()
				camera.add_child(_sieve)
			_sieve.visible = true
			_sieve.rotation = Vector3(-0.5, 0, 0)
			_sieve.get_node("Rim").visible = true
			_sieve.get_node("Screen").visible = true
			for c in _sieve.get_node("Stones").get_children():
				c.queue_free()
			_shovel.visible = false
			_sieve_phase = 1
			_sieve_t = SIEVE_SHAKE
			Sfx.play("splash", null, -4.0)
		2:
			var rich := Garnets.beach_richness(global_position.x, global_position.z)
			_sieve_found = Garnets.sieve_load(_garnet_rng, rich)
			_sieve_phase = 3
			_sieve_t = 2.8
			Sfx.play("dump", null, -6.0)
			var tw := create_tween()
			tw.tween_property(_sieve, "rotation:z", PI, 0.35)
			tw.tween_callback(_show_garnets)


func _show_garnets() -> void:
	# The sieve comes away: what's left is the pile, upright, with the garnets on top.
	_sieve.rotation = Vector3(0.75, 0.0, 0.0)
	_sieve.get_node("Rim").visible = false
	_sieve.get_node("Screen").visible = false
	var stones: Node3D = _sieve.get_node("Stones")
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.45, 0.03, 0.07)
	red.metallic_specular = 1.0
	red.roughness = 0.15
	var i := 0
	for ct in _sieve_found:
		var m := MeshInstance3D.new()
		var sp := SphereMesh.new()
		var r := 0.01 + 0.006 * sqrt(ct)
		sp.radius = r
		sp.height = r * 1.6
		sp.radial_segments = 6
		sp.rings = 3
		m.mesh = sp
		m.material_override = red
		var a := i * 2.4
		m.position = Vector3(cos(a) * 0.018 * i, 0.035, sin(a) * 0.018 * i)    # on top of the pile, in the middle
		stones.add_child(m)
		i += 1
	if _sieve_found.is_empty():
		hud.toast("No garnets in that one. Try another scoop.", Color(0.85, 0.85, 0.85), 2.0)
	else:
		var total := 0.0
		for ct in _sieve_found:
			inv.garnets.append(ct)
			total += ct
		hud.toast("%d garnet%s on top of the pile: %.2f carats." % [_sieve_found.size(), "" if _sieve_found.size() == 1 else "s", total],
			Color(0.95, 0.4, 0.45), 3.0)
		Sfx.play("clink", null, -6.0)
	refresh_hud()


func _update_sieve(delta: float) -> void:
	if _sieve_phase == 0:
		return
	if not _on_beach() and _sieve_phase < 3:
		_end_sieve()
		hud.toast("You left the beach. Sieve put away.")
		return
	_sieve_t -= delta
	if _sieve_phase == 1:
		var t := Time.get_ticks_msec() / 1000.0
		_sieve.position = Vector3(0.0, -0.3, -0.5) + Vector3(sin(t * 34.0) * 0.012, 0.0, cos(t * 27.0) * 0.01)
		_sieve.rotation.y = sin(t * 3.0) * 0.4
		if _sieve_t <= 0.0:
			_sieve_phase = 2
			_sieve.position = Vector3(0.0, -0.3, -0.5)
	elif _sieve_phase == 3 and _sieve_t <= 0.0:
		_end_sieve()


func _end_sieve() -> void:
	_sieve_phase = 0
	if _sieve != null:
		_sieve.visible = false
	_shovel.visible = carrying == null


func _make_sieve() -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0.0, -0.3, -0.5)
	var wood := StandardMaterial3D.new()
	Tex.dress_as(wood, "rough_wood", 8.0, Color(0.52, 0.38, 0.24), 0.5)
	var rim := TorusMesh.new()
	rim.inner_radius = 0.19
	rim.outer_radius = 0.215
	rim.rings = 32
	rim.ring_segments = 6
	var rm := MeshInstance3D.new()
	rm.mesh = rim
	rm.material_override = wood
	rm.scale = Vector3(1, 2.2, 1)
	rm.name = "Rim"
	root.add_child(rm)
	var mesh := StandardMaterial3D.new()
	mesh.albedo_color = Color(0.25, 0.25, 0.25)
	mesh.metallic = 0.6
	var screen := CylinderMesh.new()
	screen.top_radius = 0.19
	screen.bottom_radius = 0.19
	screen.height = 0.004
	var sm := MeshInstance3D.new()
	sm.mesh = screen
	sm.material_override = mesh
	sm.position.y = -0.025
	sm.name = "Screen"
	root.add_child(sm)
	var gravel := StandardMaterial3D.new()
	Tex.dress_as(gravel, "gravel", 14.0, Color(0.55, 0.5, 0.45))
	var pile := SphereMesh.new()
	pile.radius = 0.17
	pile.height = 0.08
	var pm := MeshInstance3D.new()
	pm.mesh = pile
	pm.material_override = gravel
	pm.position.y = -0.005
	root.add_child(pm)
	var stones := Node3D.new()
	stones.name = "Stones"
	root.add_child(stones)
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## The bright headlamp from the store: stronger, reaching further, a little wider.
func set_bright_lamp(bright: bool) -> void:
	lamp_boost = 1.8 if bright else 1.0
	_lamp.spot_range = 60.0 if bright else 32.0
	_lamp.spot_angle = 48.0 if bright else 42.0
	_lamp.light_energy = LAMP_ENERGY * lamp_boost


func _make_shovel() -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0.34, -0.36, -0.5)
	root.rotation = Vector3(deg_to_rad(-28.0), deg_to_rad(10.0), deg_to_rad(-6.0))
	# An old round-point shovel: worn ash handle, dark steel, rubbed bright at the cutting edge.
	var wood := StandardMaterial3D.new()
	Tex.dress_as(wood, "rough_wood", 6.0, Color(0.50, 0.36, 0.22), 0.5)
	wood.roughness = 0.7
	var steel := StandardMaterial3D.new()
	Tex.dress_as(steel, "rust", 4.0, Color(0.50, 0.46, 0.42), 0.6)
	steel.metallic = 0.45
	steel.roughness = 0.55
	var bright := StandardMaterial3D.new()
	bright.albedo_color = Color(0.62, 0.62, 0.60)
	bright.metallic = 0.9
	bright.roughness = 0.3
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.016
	shaft.bottom_radius = 0.018
	shaft.height = 0.98
	shaft.radial_segments = 12
	root.add_child(_part(shaft, wood, Vector3(0, 0, -0.24), Vector3(deg_to_rad(90.0), 0, 0)))
	# Steel socket where the handle goes into the blade, tapering down.
	var sock := CylinderMesh.new()
	sock.top_radius = 0.021
	sock.bottom_radius = 0.03
	sock.height = 0.16
	sock.radial_segments = 12
	root.add_child(_part(sock, steel, Vector3(0, -0.004, -0.78), Vector3(deg_to_rad(90.0), 0, 0)))
	var blade := MeshInstance3D.new()
	blade.mesh = _shovel_blade(false)
	blade.material_override = steel
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blade.position = Vector3(0, -0.01, -0.85)
	blade.rotation = Vector3(deg_to_rad(-14.0), 0, 0)
	root.add_child(blade)
	var edge := MeshInstance3D.new()
	edge.mesh = _shovel_blade(true)
	edge.material_override = bright
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blade.add_child(edge)
	# D-handle: two cheeks from a ferrule and a cross grip.
	var fer := CylinderMesh.new()
	fer.top_radius = 0.02
	fer.bottom_radius = 0.02
	fer.height = 0.05
	root.add_child(_part(fer, steel, Vector3(0, 0, 0.25), Vector3(deg_to_rad(90.0), 0, 0)))
	for side in [-1.0, 1.0]:
		var cheek := BoxMesh.new()
		cheek.size = Vector3(0.012, 0.02, 0.13)
		root.add_child(_part(cheek, wood, Vector3(side * 0.035, 0, 0.32), Vector3(0, deg_to_rad(side * 18.0), 0)))
	var grip := CylinderMesh.new()
	grip.top_radius = 0.016
	grip.bottom_radius = 0.016
	grip.height = 0.1
	root.add_child(_part(grip, wood, Vector3(0, 0, 0.385), Vector3(0, 0, deg_to_rad(90.0))))
	return root


## The blade: dished across, pointed at the tip, with a little thickness. With `edge_only`,
## just the worn strip along the cutting edge, raised a hair so it sits on top.
func _shovel_blade(edge_only: bool) -> ArrayMesh:
	const W := 0.115     # half width
	const L := 0.29      # length, socket to point
	const DISH := 0.028  # how deep the dish is at the middle
	var cols := 9
	var rows := 12
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shape := func(u: float, v: float, lift: float) -> Vector3:
		# v 0 at the socket, 1 at the point. The width narrows to the point over the last 40%.
		var half := W * (1.0 - smoothstep(0.55, 1.0, v) * 0.9) * (0.82 + 0.18 * smoothstep(0.0, 0.2, v))
		var x := u * half
		var y := DISH * (u * u) * (1.0 - 0.6 * v) + lift
		return Vector3(x, y, -v * L)
	for face in [0, 1]:
		var off := 0.0 if face == 0 else -0.004
		for j in rows:
			var v0 := float(j) / rows
			var v1 := float(j + 1) / rows
			if edge_only and v1 < 0.8:
				continue
			for i in cols:
				var u0 := -1.0 + 2.0 * i / cols
				var u1 := -1.0 + 2.0 * (i + 1) / cols
				var lift := off + (0.0015 if edge_only else 0.0)
				var a: Vector3 = shape.call(u0, v0, lift)
				var b: Vector3 = shape.call(u1, v0, lift)
				var c: Vector3 = shape.call(u0, v1, lift)
				var d: Vector3 = shape.call(u1, v1, lift)
				var tris := [a, c, b, b, c, d] if face == 0 else [a, b, c, b, d, c]
				for p in tris:
					st.add_vertex(p)
	st.generate_normals()
	return st.commit()


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
