extends RigidBody3D
## Base for drivable vehicles. Simple, stable physics: each wheel is a ray with a spring and
## damper, tires grip sideways up to a limit, and the engine pushes along the ground.
## E gets in and out, V switches between first person and a chase camera, R flips it back
## upright, Space brakes. Parked vehicles freeze in place, so they stay put while the ground
## under them isn't loaded. Cargo slots hold equipment (see machine.gd load_onto).

const Settings = preload("res://scripts/core/settings.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Sfx = preload("res://scripts/core/sfx.gd")
const Parts = preload("res://scripts/machines/parts.gd")

const MU := 1.0
const SETTLE_TIME := 3.0

var kind := ""
var display_name := ""
var terrain
var driver = null

# Tuning, set by each vehicle.
var wheel_mounts: Array[Vector3] = []     # front left, front right, rear left, rear right
var wheel_radius := 0.3
var wheel_width := 0.24
var rest := 0.28
var spring := 5600.0
var damper := 600.0
var anti_roll := 3000.0
var engine_force := 2600.0
var top_speed := 15.0
var brake_force := 3200.0
var max_steer := 0.55
var com_y := 0.25
var rim_color := Color(0.55, 0.55, 0.56)  # wheel rims (art only)
var seat := Vector3.ZERO                  # where the driver sits (local)
var head := Vector3.ZERO                  # first-person camera (local)
var exit_offset := Vector3(-1.4, 0, 0)    # where you step out (local)
var chase := Vector3(0, 3.0, 7.0)         # chase camera (local)
var cargo_slots: Array[Transform3D] = []
var cargo: Array = []                     # machine or null per slot

var _wheels: Array = []                   # {mesh, comp, spin, steer, drive}
var _slot_nodes: Array[Node3D] = []
var _steer := 0.0
var _cam: Camera3D
var _chase_on := false
var _yaw := 0.0
var _pitch := -0.08
var _lights: Array[SpotLight3D] = []
var _settle := 0.0
var _enter_block := 0.0
var _dark := false


func setup(t) -> void:
	terrain = t
	add_to_group("vehicles")
	_build()
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, com_y, 0.0)
	angular_damp = 1.2
	linear_damp = 0.05
	continuous_cd = true
	for i in wheel_mounts.size():
		var holder := Node3D.new()
		add_child(holder)
		Parts.wheel(holder, wheel_radius, wheel_width, rim_color)
		holder.position = wheel_mounts[i] - Vector3(0, rest * 0.5, 0)
		_wheels.append({"node": holder, "comp": 0.0, "spin": 0.0, "steer": i < 2, "drive": true})
	for s in cargo_slots:
		var n := Node3D.new()
		n.transform = s
		add_child(n)
		_slot_nodes.append(n)
		cargo.append(null)
	_cam = Camera3D.new()
	_cam.fov = Settings.fov
	_cam.add_to_group("fov_camera")
	_cam.near = 0.05
	_cam.far = 1500.0
	_cam.position = head
	add_child(_cam)
	freeze = true


func _build() -> void:
	pass


# --- Driving -------------------------------------------------------------------------------

func enter(player) -> void:
	driver = player
	freeze = false
	sleeping = false
	_enter_block = 0.3
	_yaw = 0.0
	_pitch = -0.08
	_cam.make_current()
	player.begin_driving(self)


func exit() -> void:
	var p = driver
	driver = null
	_settle = SETTLE_TIME
	p.end_driving(_exit_spot(), rotation.y)


## Where to step out: the exit side if there's room for a person there, else the other side,
## behind, or in front. Stepping out into the vehicle would shove it over.
func _exit_spot() -> Vector3:
	var side := exit_offset
	var tries := [side, Vector3(-side.x, 0, side.z), side * 1.5, Vector3(0, 0, 2.6), Vector3(0, 0, -2.6),
		Vector3(-side.x * 1.5, 0, side.z)]
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 1.5
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.exclude = [get_rid()]
	var space := get_world_3d().direct_space_state
	var first := Vector3.ZERO
	for k in tries.size():
		var spot: Vector3 = global_position + global_basis.get_rotation_quaternion() * tries[k]
		spot.y = terrain.height_at(spot.x, spot.z) + 0.1
		if k == 0:
			first = spot
		q.transform = Transform3D(Basis.IDENTITY, spot + Vector3(0, 1.0, 0))
		var hit := false
		for r in space.intersect_shape(q, 8):
			if r["collider"] == self or (r["collider"] is Node and (r["collider"] as Node).is_in_group("vehicles")):
				hit = true
				break
		if not hit:
			return spot
	return first


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func seat_position() -> Vector3:
	return to_global(seat)


func _unhandled_input(event: InputEvent) -> void:
	if driver == null or not Settings.mouse_captured():
		return
	if event is InputEventMouseMotion and not _chase_on:
		var motion := event as InputEventMouseMotion
		_yaw = clampf(_yaw - motion.relative.x * Settings.look_speed(), -1.9, 1.9)
		_pitch = clampf(_pitch - motion.relative.y * Settings.look_speed() * (-1.0 if Settings.invert_y else 1.0), -1.1, 0.9)


var _engine_snd: AudioStreamPlayer3D


const TIPPED_UP := 0.35         # up vector's height below which a vehicle counts as on its side
const RIGHT_DELAY := 1.2        # seconds tipped and still before it's set back on its wheels
var _tipped_t := 0.0


func _physics_process(delta: float) -> void:
	_enter_block -= delta
	if driver != null and not _chase_on and not driver.map_open:
		var look := Settings.pad_look(delta)
		_yaw = clampf(_yaw - look.x, -1.9, 1.9)
		_pitch = clampf(_pitch - look.y, -1.1, 0.9)
	_engine_sound()
	_keep_upright(delta)
	if driver != null:
		_driver_controls()
	elif not freeze:
		_settle -= delta
		var far: bool = terrain.focus.distance_to(global_position) > 45.0
		if far or (_settle <= 0.0 and linear_velocity.length() < 0.25):
			freeze = true
	if freeze:
		return
	_drive(delta)


## Vehicles never stay on their side or sunk into the ground: a tipped vehicle that has come
## to rest is set back on its wheels, one below the ground is lifted out, and a hard lean while
## moving gets a push back toward upright.
func _keep_upright(delta: float) -> void:
	if kind == "trailer" and get("towed_by") != null:
		return       # the pickup decides; the hitch would fight a reset
	var up := global_basis.y
	var p := global_position
	var ground: float = terrain.height_at(p.x, p.z)
	var body_y := to_global(Vector3(0.0, com_y, 0.0)).y
	if body_y < ground - 0.05 and terrain.water_depth(p.x, p.z) <= 0.0:
		_set_upright()
		return
	if up.y < TIPPED_UP:
		if linear_velocity.length() < 1.5 or freeze:
			_tipped_t += delta
			if _tipped_t > RIGHT_DELAY:
				_set_upright()
		return
	_tipped_t = 0.0
	if not freeze and up.y < 0.8:
		# Roll assist: torque back toward level, stronger the further it leans.
		var axis := up.cross(Vector3.UP)
		apply_torque(axis * mass * 18.0 * (1.0 - up.y))


func _set_upright() -> void:
	_tipped_t = 0.0
	freeze = false
	_flip_upright()
	_settle = SETTLE_TIME


## Idle when someone sits in it; revs up with speed and throttle.
func _engine_sound() -> void:
	if kind == "trailer":
		return
	if _engine_snd == null:
		_engine_snd = Sfx.loop_on(self, "engine", 7.0)
	var on := driver != null
	var speed := linear_velocity.length()
	var throttle := absf(Settings.drive_input()) if on and not driver.map_open else 0.0
	var pitch := 0.8 + clampf(speed / maxf(top_speed, 1.0), 0.0, 1.2) * 1.1 + throttle * 0.25
	if kind == "truck":
		pitch *= 0.75
	elif kind == "excavator":
		pitch *= 0.6
	Sfx.run_loop(_engine_snd, on, -8.0 + throttle * 4.0, pitch)


## Whether the wheels hold the vehicle still when nothing drives it (a towed trailer rolls).
func _hold_still() -> bool:
	return true


func _driver_controls() -> void:
	if driver.map_open:
		return
	if _enter_block <= 0.0 and Input.is_action_just_pressed("interact"):
		exit()
		return
	if Input.is_action_just_pressed("camera"):
		_chase_on = not _chase_on
	if Input.is_action_just_pressed("dump"):
		_flip_upright()
	if _chase_on:
		_cam.position = chase
		_cam.look_at(global_position + global_basis.y * 1.2)
	else:
		_cam.position = head
		_cam.rotation = Vector3(_pitch, _yaw, 0.0)


func _flip_upright() -> void:
	var yaw := atan2(-global_basis.z.x, -global_basis.z.z)
	var p := global_position
	global_transform = Transform3D(Basis(Vector3.UP, yaw + PI), Vector3(p.x, terrain.height_at(p.x, p.z) + 1.2, p.z))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _drive(dt: float) -> void:
	var throttle := 0.0
	var steer_in := 0.0
	var handbrake := false
	if driver != null and not driver.map_open:
		throttle = Settings.drive_input()
		steer_in = Input.get_axis("move_right", "move_left")
		handbrake = Input.is_action_pressed("jump")
	var b := global_basis
	var up := b.y
	var fwd := -b.z
	var speed := linear_velocity.dot(fwd)
	_steer = move_toward(_steer, steer_in * max_steer / (1.0 + absf(speed) * 0.06), dt * 2.5)
	var space := get_world_3d().direct_space_state
	var water := maxf(0.0, terrain.water_depth(global_position.x, global_position.z))
	var drive_scale := 0.5 if water > 0.35 else 1.0
	var comps := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var forces := []
	for i in _wheels.size():
		var w: Dictionary = _wheels[i]
		var origin := global_transform * wheel_mounts[i]
		var q := PhysicsRayQueryParameters3D.create(origin, origin - up * (rest + wheel_radius))
		q.exclude = [get_rid()]
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		var travel := rest
		if hit.is_empty():
			w["comp"] = 0.0
			forces.append(null)
		else:
			var dist := origin.distance_to(hit["position"])
			var comp := rest + wheel_radius - dist
			travel = maxf(0.0, dist - wheel_radius)
			var comp_vel := (comp - float(w["comp"])) / dt
			w["comp"] = comp
			comps[i] = comp
			var susp := maxf(0.0, comp * spring + comp_vel * damper)
			forces.append([hit["position"], susp])
		var node: Node3D = w["node"]
		node.position = wheel_mounts[i] - Vector3(0, travel, 0)
		node.rotation = Vector3(float(w["spin"]), _steer if w["steer"] else 0.0, 0.0)
	# Anti-roll: push the more compressed side down less, the other more.
	for axle in [[0, 1], [2, 3]]:
		var diff := comps[axle[0]] - comps[axle[1]]
		for k in 2:
			var f = forces[axle[k]]
			if f != null:
				f[1] = maxf(0.0, f[1] + (diff if k == 0 else -diff) * anti_roll)
	var grounded := 0
	for i in _wheels.size():
		var f = forces[i]
		if f == null:
			continue
		grounded += 1
		var w: Dictionary = _wheels[i]
		var contact: Vector3 = f[0]
		var susp: float = f[1]
		var rel := contact - global_position
		apply_force(up * susp, rel)
		var wfwd := fwd.rotated(up, _steer) if w["steer"] else fwd
		var wright := wfwd.cross(up).normalized()
		var pv := linear_velocity + angular_velocity.cross(rel)
		var lat := pv.dot(wright)
		var lon := pv.dot(wfwd)
		var grip := susp * MU
		var lat_f := clampf(-lat * mass * 0.25 / dt * 0.6, -grip, grip)
		var lon_f := 0.0
		if handbrake:
			lon_f = -signf(lon) * minf(absf(lon) * mass * 0.25 / dt * 0.5, brake_force * 0.25)
		elif absf(throttle) > 0.05:
			if throttle * speed < -0.5:
				lon_f = throttle * brake_force * 0.25            # pressing against the motion brakes
			else:
				lon_f = throttle * engine_force * 0.25 * drive_scale
		elif absf(speed) < 1.0 and _hold_still():
			lon_f = -lon * mass * 0.25 / dt * 0.3                # hold still on slopes
		else:
			lon_f = -lon * mass * 0.02                           # rolling resistance
		lon_f = clampf(lon_f, -grip, grip)
		apply_force(wright * lat_f + wfwd * lon_f, rel)
		w["spin"] = float(w["spin"]) - lon * dt / wheel_radius
	# Air drag sets the top speed; water slows you a lot more.
	var v := linear_velocity
	apply_central_force(-v * v.length() * engine_force / (top_speed * top_speed))
	if water > 0.25:
		apply_central_force(-v * mass * 0.6 * minf(water, 1.0))
	_update_lights()


func _update_lights() -> void:
	var on := (driver != null and _dark) or lights_left_on
	for l in _lights:
		l.visible = on


## Called by the day/night cycle.
func set_dark(dark: bool) -> void:
	_dark = dark
	_update_lights()


func _add_headlight(pos: Vector3) -> void:
	var l := SpotLight3D.new()
	l.position = pos
	l.spot_range = 45.0
	l.spot_angle = 32.0
	l.light_energy = 3.0
	l.light_color = Color(1.0, 0.95, 0.85)
	l.visible = false
	add_child(l)
	_lights.append(l)
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.97, 0.85)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.95, 0.8)
	lamp.emission_energy_multiplier = 1.5
	Parts.cyl(self, 0.07, 0.04, pos + Vector3(0, 0, -0.02), lamp, Vector3(PI / 2.0, 0, 0), -1.0, 10)


# --- Interaction and cargo -------------------------------------------------------------------

func prompt(_player) -> String:
	var t := "[b]%s[/b]" % display_name
	var names := PackedStringArray()
	for c in cargo:
		if c != null:
			names.append(str(c.display_name).to_lower())
	if not names.is_empty():
		t += "   carrying: " + ", ".join(names)
	t += "\n" + Hud.key("E") + " Drive"
	if not _lights.is_empty():
		t += "     " + Hud.key("F") + (" Headlights off" if lights_left_on else " Leave the headlights on")
	return t


## Headlights left on light up whatever the vehicle faces, with nobody in it. They never run
## the battery down.
var lights_left_on := false


func toggle_lights() -> void:
	if _lights.is_empty():
		return
	lights_left_on = not lights_left_on
	_update_lights()
	Sfx.play("click", global_position)


func interact(player) -> void:
	if driver == null:
		enter(player)


func free_slot() -> int:
	for i in cargo.size():
		if cargo[i] == null:
			return i
	return -1


func load_cargo(machine, slot: int = -1) -> bool:
	if slot < 0:
		slot = free_slot()
	if slot < 0 or slot >= cargo.size() or cargo[slot] != null:
		return false
	cargo[slot] = machine
	machine.load_onto(self, _slot_nodes[slot])
	return true


func unload_cargo(machine) -> void:
	var i := cargo.find(machine)
	if i >= 0:
		cargo[i] = null
	machine.unload()


# --- Saving --------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"kind": kind, "xform": global_transform, "lights": lights_left_on}


func from_dict(d: Dictionary) -> void:
	global_transform = d.get("xform", global_transform)
	lights_left_on = d.get("lights", false)
	_update_lights()
