extends Node3D
## Storms and floods. Every few days a storm rolls in for the afternoon: grey sky, dim light,
## rain. When it passes, the creeks have run high, and holes you dug on the bars and banks are
## filled back in with fresh gravel, carrying new gold. Floods are never missed: a storm that
## ended while you slept or traveled still counts.

const START := 14.0           # storms run from 2 pm ...
const END := 19.0             # ... to 7 pm
const RAMP := 0.75            # hours to roll in and to clear

var day_night
var checked := -1.0           # absolute hour (day * 24 + hours) up to which storms are counted
var _rain: CPUParticles3D
var _was_raining := false


## Storms are fixed by the day number, so they are the same every game.
static func storm_day(d: int) -> bool:
	return d >= 2 and (hash(d * 7919 + 1849) % 100) < 34


func setup(dn) -> void:
	day_night = dn
	_rain = CPUParticles3D.new()
	_rain.amount = 2200
	_rain.lifetime = 1.0
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(22, 1, 22)
	_rain.direction = Vector3(0.08, -1, 0.02)
	_rain.spread = 2.0
	_rain.gravity = Vector3(0, -22, 0)
	_rain.initial_velocity_min = 14.0
	_rain.initial_velocity_max = 18.0
	_rain.local_coords = false
	var quad := QuadMesh.new()
	quad.size = Vector2(0.015, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.75, 0.8, 0.85, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	quad.material = mat
	_rain.mesh = quad
	_rain.emitting = false
	add_child(_rain)


func now() -> float:
	return day_night.day * 24.0 + day_night.hours


## How stormy it is right now (0..1).
func amount() -> float:
	if not storm_day(day_night.day):
		return 0.0
	var h: float = day_night.hours
	return smoothstep(START, START + RAMP, h) * (1.0 - smoothstep(END - RAMP, END, h))


## Storms that ended after `from` and up to `to` (absolute hours).
func storms_between(from: float, to: float) -> int:
	var n := 0
	for d in range(maxi(1, floori(from / 24.0)), floori(to / 24.0) + 1):
		var end := d * 24.0 + END
		if storm_day(d) and end > from and end <= to:
			n += 1
	return n


func _process(_delta: float) -> void:
	var main = get_parent()
	if main == null or not main.ready_to_play:
		return
	var a := 0.0 if day_night.underground else amount()
	day_night.storm = a
	var focus: Vector3 = main.focus_position()
	_rain.global_position = focus + Vector3(0, 12, 0)
	var raining := a > 0.25
	_rain.emitting = raining
	if raining and not _was_raining and main.hud != null:
		main.hud.toast("Rain's coming down. The creeks will run high tonight.", Color(0.75, 0.85, 1.0), 5.0)
	_was_raining = raining
	var t := now()
	if checked < 0.0:
		checked = t
	if t > checked:
		var n := storms_between(checked, t)
		checked = t
		if n > 0:
			main.flood()
