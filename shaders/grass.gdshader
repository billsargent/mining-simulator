// Grass clumps: blades are cut out procedurally from crossed quads and sway in the wind.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.09, 0.13, 0.04);
uniform vec3 tip_color : source_color = vec3(0.38, 0.42, 0.16);
uniform vec3 dry_color : source_color = vec3(0.55, 0.49, 0.29);

varying float v_rand;

void vertex() {
	v_rand = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	float top = 1.0 - UV.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.6 + wp.x * 0.3 + wp.z * 0.21) * 0.07
		+ sin(TIME * 3.3 + wp.x * 1.1 + wp.z * 0.7) * 0.025;
	mat3 to_local = inverse(mat3(MODEL_MATRIX));
	VERTEX += to_local * (vec3(sway, 0.0, sway * 0.5) * top * top);
	NORMAL = normalize(to_local * vec3(0.0, 1.0, 0.0));
}

void fragment() {
	float top = 1.0 - UV.y;
	float x = UV.x * 26.0;
	float id = floor(x);
	float rnd = fract(sin(id * 78.233 + v_rand * 311.7) * 43758.5453);
	float blade_h = 0.35 + 0.65 * rnd;
	float lean = (rnd - 0.5) * 1.6;
	float fx = fract(x) - 0.5 - lean * top * top;
	float w = 0.3 * (1.0 - pow(top / blade_h, 1.5));
	if (top > blade_h || abs(fx) > w) {
		discard;
	}
	vec3 c = mix(base_color, tip_color, smoothstep(0.0, 0.9, top / blade_h));
	c = mix(c, dry_color, step(0.85, fract(rnd * 7.13 + v_rand)) * 0.7);
	c *= mix(0.45, 1.0, smoothstep(0.0, 0.4, top));
	ALBEDO = c * (0.85 + 0.3 * v_rand);
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.15, 0.2, 0.06);
}
