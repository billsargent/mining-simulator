extends Node
## A 30-minute day. The sun crosses the sky, dusk turns the sky warm, and nights are dark blue
## with moonlight: dark, but playable with the headlamp (L) and vehicle headlights.

const DAY_SECONDS := 1800.0
const DAY_TOP := Color(0.30, 0.48, 0.76)
const DAY_HORIZON := Color(0.70, 0.76, 0.82)
const DUSK_TOP := Color(0.25, 0.28, 0.48)
const DUSK_HORIZON := Color(0.93, 0.62, 0.40)
const NIGHT_TOP := Color(0.035, 0.055, 0.12)
const NIGHT_HORIZON := Color(0.1, 0.13, 0.21)

var hours := 8.0
var day := 1
var underground := false
var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D


func _process(delta: float) -> void:
	hours += delta * 24.0 / DAY_SECONDS
	if hours >= 24.0:
		hours -= 24.0
		day += 1
	apply()


## Degrees above the horizon (negative at night).
func sun_elevation() -> float:
	return 62.0 * sin((hours - 6.0) / 12.0 * PI)


func is_dark() -> bool:
	return sun_elevation() < 3.0


func clock_text() -> String:
	var h := int(hours)
	var m := int((hours - h) * 60.0)
	var suffix := "am" if h < 12 else "pm"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "Day %d   %d:%02d %s" % [day, h12, m, suffix]


## Skip to 7 in the morning.
func sleep_until_morning() -> void:
	if hours >= 7.0:
		day += 1
	hours = 7.0
	apply()


func apply() -> void:
	var elev := sun_elevation()
	var along := clampf((hours - 6.0) / 12.0, 0.0, 1.0)
	sun.rotation_degrees = Vector3(-maxf(elev, 2.0), -170.0 + 110.0 * along, 0.0)
	var day_f := smoothstep(-4.0, 8.0, elev)
	sun.light_energy = 1.25 * day_f
	sun.visible = day_f > 0.01
	sun.light_color = Color(1.0, 0.62, 0.38).lerp(Color(1.0, 0.95, 0.86), smoothstep(2.0, 25.0, elev))
	var night_f := 1.0 - smoothstep(-6.0, 2.0, elev)
	moon.light_energy = 0.32 * night_f
	moon.visible = night_f > 0.01
	var top: Color
	var horizon: Color
	if elev >= 0.0:
		var t := smoothstep(0.0, 20.0, elev)
		top = DUSK_TOP.lerp(DAY_TOP, t)
		horizon = DUSK_HORIZON.lerp(DAY_HORIZON, t)
	else:
		var t := smoothstep(0.0, 10.0, -elev)
		top = DUSK_TOP.lerp(NIGHT_TOP, t)
		horizon = DUSK_HORIZON.lerp(NIGHT_HORIZON, t)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon * 0.85
	sky_mat.ground_bottom_color = top * 0.4
	env.fog_light_color = horizon
	env.ambient_light_energy = lerpf(4.0, 1.0, day_f)
	if underground:
		# No sky down here: only lamps, and a trace of light so walls aren't pure black.
		sun.visible = false
		moon.visible = false
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.5, 0.48, 0.45)
		env.ambient_light_energy = 0.16
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		env.fog_light_color = Color.BLACK
		env.fog_aerial_perspective = 0.0
		env.fog_sky_affect = 0.0
		env.fog_density = 0.006
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.fog_aerial_perspective = 0.55
		env.fog_sky_affect = 0.25
		env.fog_density = 0.0016
