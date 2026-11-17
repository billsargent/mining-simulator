extends StaticBody3D
## Base for equipment you carry (F) and set down (left mouse). Processing machines (sluice,
## high banker) take shovelfuls into a hopper and catch gold in their riffles; E cleans them
## out into a jar of concentrate. One knob: the sluice angle (mouse wheel).

const Paydirt = preload("res://scripts/gold/paydirt.gd")
const Recovery = preload("res://scripts/machines/recovery.gd")
const Claims = preload("res://scripts/core/claims.gd")
const Terrain = preload("res://scripts/world/world_terrain.gd")
const Parts = preload("res://scripts/machines/parts.gd")
const Hud = preload("res://scripts/ui/hud.gd")

const CARPET := Color(0.16, 0.2, 0.16)
const BLACK_SAND := Color(0.05, 0.05, 0.06)
const FLECKS := 80

var kind := ""
var display_name := ""
var processes := true
var hopper_capacity := 4
var seconds_per_shovel := 1.6
var recovery_bonus := 0.0
var angle := 6.5
var terrain: Terrain
var loaded_on = null                   # the vehicle carrying it, if any
var world_parent: Node                 # where it lives when not on a vehicle
var hopper: Array = []                 # Paydirt waiting to go through
var caught := PackedFloat32Array()     # gold sitting in the riffles
var caught_sand := 0.0
var lost := PackedFloat32Array()       # gold that went out with the tailings
var processed := 0                     # shovelfuls since the last cleanout
var processed_total := 0
var carried := false

var _timer := 0.0
var _rng := RandomNumberGenerator.new()
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var _tilt: Node3D                      # the part that tilts with the angle knob
var _flow: MeshInstance3D
var _carpet_mat: StandardMaterial3D
var _flecks: MultiMesh
var _spray: CPUParticles3D


func setup(t: Terrain) -> void:
	terrain = t
	world_parent = get_parent()
	_rng.randomize()
	add_to_group("machines")
	_build()
	_build_marker()
	_apply_angle()
	_on_processed()


# --- Overridables -----------------------------------------------------------------

func _build() -> void:
	pass


## Why it can't run where it stands for want of water, or "" if it can.
func water_problem() -> String:
	return ""


## Why it can't run where it stands, or "" if it can: water first, then whose ground it is.
func problem() -> String:
	var w := water_problem()
	if w != "":
		return w
	if not Claims.is_owned_at(global_position.x, global_position.z):
		var c := Claims.at(global_position.x, global_position.z)
		if c.is_empty():
			return "this is public land, and machines only run on a claim you own"
		return "%s isn't yours yet (the claims office in town sells it)" % c["name"]
	return ""


func place_at(pos: Vector3, yaw: float) -> void:
	rotation = Vector3(0.0, yaw + PI / 2.0, 0.0)
	global_position = Vector3(pos.x, terrain.height_at(pos.x, pos.z), pos.z)
	_on_moved()


func _on_moved() -> void:
	pass


func _update_visuals(_delta: float) -> void:
	var running := is_running()
	if _flow:
		_flow.visible = running
	if _spray:
		_spray.emitting = running and not hopper.is_empty()
	if carried:
		_marker_mat.albedo_color = Color(0.3, 0.9, 0.4, 0.16) if problem() == "" else Color(1.0, 0.55, 0.2, 0.16)


# --- Processing -------------------------------------------------------------------

func is_running() -> bool:
	return not carried and loaded_on == null and problem() == ""


## Ride on a vehicle: parented to its cargo slot, not running, only hit by the "use" ray.
func load_onto(vehicle, slot: Node3D) -> void:
	loaded_on = vehicle
	carried = false
	reparent(slot, false)
	transform = Transform3D.IDENTITY
	collision_layer = 2
	_marker.visible = false
	for g in find_children("*", "GeometryInstance3D", true, false):
		if g != _marker:
			(g as GeometryInstance3D).transparency = 0.0
	_on_moved()


func unload() -> void:
	loaded_on = null
	reparent(world_parent, true)
	collision_layer = 1


func hopper_space() -> int:
	return hopper_capacity - hopper.size()


func feed(dirt) -> bool:
	if hopper_space() <= 0:
		return false
	hopper.append(dirt)
	return true


func has_concentrate() -> bool:
	return processed > 0


func _physics_process(delta: float) -> void:
	if processes and not hopper.is_empty() and is_running():
		_timer += delta
		if _timer >= seconds_per_shovel:
			_timer = 0.0
			_process_one(hopper.pop_front())
	_update_visuals(delta)


func _process_one(dirt) -> void:
	for m in dirt.gold:
		if _rng.randf() < Recovery.catch_chance(m, angle, recovery_bonus):
			caught.append(m)
		else:
			lost.append(m)
	caught_sand += dirt.black_sand
	processed += 1
	processed_total += 1
	_on_processed()


## Empty the riffles into a jar of concentrate: black sand, some fine sand, and the gold.
func clean_out() -> Paydirt:
	var jar := Paydirt.new()
	jar.gold = caught
	jar.black_sand = 1.0
	jar.gravel = 0.0
	jar.sand = 0.45
	caught = PackedFloat32Array()
	caught_sand = 0.0
	processed = 0
	_on_processed()
	return jar


func _on_processed() -> void:
	if _carpet_mat:
		_carpet_mat.albedo_color = CARPET.lerp(BLACK_SAND, clampf(caught_sand / 6.0, 0.0, 0.85))
	if _flecks:
		_flecks.visible_instance_count = mini(caught.size(), FLECKS)


# --- Interaction ------------------------------------------------------------------

func prompt(player) -> String:
	var t := "[b]%s[/b]   %s" % [display_name, _status_bb()]
	if processes:
		t += "\nHopper %d/%d    Gold in the riffles: %d pieces    Angle %.1f°  %s" % [
			hopper.size(), hopper_capacity, caught.size(), angle, _zone_bb()]
	var acts := PackedStringArray()
	if loaded_on != null:
		return t + "\n" + Hud.key("F") + " Take it off the " + str(loaded_on.display_name).to_lower()
	if processes:
		if not player.inv.bucket.is_empty() and hopper_space() > 0:
			acts.append(Hud.key("E") + " Dump your bucket in")
		elif has_concentrate():
			acts.append(Hud.key("E") + " Clean out the riffles")
		acts.append(Hud.key("Wheel") + " Angle")
	acts.append(Hud.key("F") + " Pick up")
	return t + "\n" + "     ".join(acts)


func interact(player) -> void:
	if not processes:
		player.hud.toast(info_text())
		return
	var inv = player.inv
	if not inv.bucket.is_empty() and hopper_space() > 0:
		var n := 0
		while not inv.bucket.is_empty() and hopper_space() > 0:
			hopper.append(inv.bucket.pop_front())
			n += 1
		var msg := "Dumped %d shovelful%s into the %s." % [n, "" if n == 1 else "s", display_name.to_lower()]
		var why := problem()
		if why != "":
			msg += " It isn't running yet: " + why + "."
		player.hud.toast(msg)
		player.on_machine_fed(self)
	elif has_concentrate():
		inv.cons.append(clean_out())
		player.hud.toast("Cleaned out the riffles into a jar of concentrate. Pan it at the wash tub by the cabin (or at the creek).", Color(1.0, 0.9, 0.6), 6.0)
		player.on_cleaned_out(self)
	else:
		player.hud.toast("Feed it by digging right next to it, or dump a bucket in with E.")


func scroll(_player, dir: int) -> void:
	angle = clampf(angle + 0.5 * dir, 0.0, 15.0)
	_apply_angle()


func info_text() -> String:
	return ""


func set_carried(c: bool) -> void:
	carried = c
	collision_layer = 0 if c else (2 if loaded_on != null else 1)
	_marker.visible = c
	for g in find_children("*", "GeometryInstance3D", true, false):
		if g != _marker:
			(g as GeometryInstance3D).transparency = 0.2 if c else 0.0


func _apply_angle() -> void:
	if _tilt:
		_tilt.rotation.z = -deg_to_rad(angle)


func _status_bb() -> String:
	if carried:
		return ""
	if loaded_on != null:
		return "[color=#a0c8ff]On the %s[/color]" % str(loaded_on.display_name).to_lower()
	var why := problem()
	if why != "":
		return "[color=#ffa060]Not running: %s[/color]" % why
	if not processes:
		return "[color=#80dd80]Pumping[/color]"
	if hopper.is_empty():
		return "[color=#a0c8a0]Running: feed it[/color]"
	return "[color=#80dd80]Running[/color]"


func _zone_bb() -> String:
	match Recovery.zone(angle):
		0:
			return "[color=#80dd80]good flow[/color]"
		1:
			return "[color=#e0d060]%s[/color]" % ("a bit steep" if angle > Recovery.SWEET_HI else "a bit shallow")
	return "[color=#ff6a6a]losing gold: %s[/color]" % ("too steep" if angle > Recovery.SWEET_HI else "riffles packing up")


# --- Shared model parts -----------------------------------------------------------

func _build_marker() -> void:
	var disk := CylinderMesh.new()
	disk.top_radius = 0.9
	disk.bottom_radius = 0.9
	disk.height = 0.02
	disk.radial_segments = 32
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker = MeshInstance3D.new()
	_marker.mesh = disk
	_marker.material_override = _marker_mat
	_marker.position.y = 0.05
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)


## A sluice bed running from x = 0 to x = length along the parent's +X: floor, sides,
## carpet, riffles, flowing water, gold flecks that build up, and spray at the outlet.
func _build_bed(parent: Node3D, length: float, width: float) -> void:
	var alu := Parts.aluminum()
	Parts.box(parent, Vector3(length, 0.008, width), Vector3(length * 0.5, 0.0, 0.0), alu)
	for s: float in [-1.0, 1.0]:
		Parts.box(parent, Vector3(length, 0.13, 0.008), Vector3(length * 0.5, 0.065, s * width * 0.5), alu)
	_carpet_mat = StandardMaterial3D.new()
	_carpet_mat.albedo_color = CARPET
	_carpet_mat.roughness = 1.0
	Parts.box(parent, Vector3(length - 0.1, 0.006, width - 0.01), Vector3(length * 0.5 + 0.05, 0.007, 0.0), _carpet_mat)
	var riffles := int(length / 0.1) - 2
	for i in riffles:
		Parts.box(parent, Vector3(0.012, 0.022, width - 0.01), Vector3(0.2 + i * 0.1, 0.02, 0.0), alu, Vector3(0, 0, -0.45))
	var plane := PlaneMesh.new()
	plane.size = Vector2(length, width - 0.01)
	_flow = MeshInstance3D.new()
	_flow.mesh = plane
	_flow.material_override = Parts.flow_material()
	_flow.position = Vector3(length * 0.5, 0.045, 0.0)
	_flow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(_flow)
	# Gold caught in the upper riffles shows up as flecks.
	var fleck := SphereMesh.new()
	fleck.radius = 1.0
	fleck.height = 2.0
	fleck.radial_segments = 6
	fleck.rings = 3
	_flecks = MultiMesh.new()
	_flecks.transform_format = MultiMesh.TRANSFORM_3D
	_flecks.mesh = fleck
	_flecks.instance_count = FLECKS
	for i in FLECKS:
		var x := 0.15 + length * 0.5 * pow(_rng.randf(), 1.6)
		var z := _rng.randf_range(-width * 0.4, width * 0.4)
		var s := _rng.randf_range(0.003, 0.006)
		_flecks.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s * 0.4, s)), Vector3(x, 0.014, z)))
	_flecks.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _flecks
	mmi.material_override = Parts.gold()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	# Muddy water and tailings spilling out of the end.
	var drop := SphereMesh.new()
	drop.radius = 0.012
	drop.height = 0.024
	drop.radial_segments = 6
	drop.rings = 3
	var drop_mat := Parts.mat("muddy_water", Color(0.42, 0.36, 0.28), 0.3)
	_spray = CPUParticles3D.new()
	_spray.mesh = drop
	_spray.material_override = drop_mat
	_spray.amount = 32
	_spray.lifetime = 0.6
	_spray.emitting = false
	_spray.direction = Vector3(1.0, 0.2, 0.0)
	_spray.spread = 20.0
	_spray.initial_velocity_min = 0.5
	_spray.initial_velocity_max = 0.9
	_spray.gravity = Vector3(0, -6.0, 0)
	_spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_spray.emission_box_extents = Vector3(0.01, 0.01, width * 0.4)
	_spray.position = Vector3(length, 0.03, 0.0)
	parent.add_child(_spray)


# --- Saving -----------------------------------------------------------------------

func to_dict() -> Dictionary:
	var hop := []
	for d in hopper:
		hop.append(d.to_dict())
	return {
		"kind": kind, "pos": global_position, "yaw": rotation.y, "angle": angle,
		"hopper": hop, "caught": caught, "caught_sand": caught_sand,
		"processed": processed, "processed_total": processed_total,
	}


func from_dict(d: Dictionary) -> void:
	angle = d.get("angle", angle)
	hopper.clear()
	for hd in d.get("hopper", []):
		var p := Paydirt.new()
		p.load_dict(hd)
		hopper.append(p)
	caught = d.get("caught", PackedFloat32Array())
	caught_sand = d.get("caught_sand", 0.0)
	processed = d.get("processed", 0)
	processed_total = d.get("processed_total", 0)
	rotation = Vector3(0.0, d.get("yaw", 0.0), 0.0)
	global_position = d.get("pos", global_position)
	_apply_angle()
	_on_processed()
	_on_moved()
