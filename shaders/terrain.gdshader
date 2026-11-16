// Ground: grass, creek gravel, freshly dug dirt, exposed bedrock and rocky slopes.
// Vertex color carries per-vertex data from terrain.gd:
//   r = dug (disturbed ground), g = bedrock exposed, b = bare gravel (creek bed / bars)
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_large : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_detail : filter_linear_mipmap, repeat_enable;
uniform float water_level = 0.08;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz;
	float big = texture(noise_large, p * 0.012).r;
	float mid = texture(noise_detail, p * 0.09).r;
	float fine = texture(noise_detail, p * 0.8).r;
	float grain = texture(noise_detail, p * 4.5).r;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);

	vec3 grass = mix(vec3(0.17, 0.24, 0.08), vec3(0.30, 0.33, 0.13), smoothstep(0.3, 0.75, big));
	grass *= 0.78 + 0.4 * mid * fine;
	grass = mix(grass, vec3(0.40, 0.36, 0.22), smoothstep(0.62, 0.85, mid) * 0.5);

	vec3 gravel = mix(vec3(0.42, 0.39, 0.35), vec3(0.60, 0.56, 0.50), grain) * (0.8 + 0.3 * fine);
	vec3 dirt = mix(vec3(0.27, 0.20, 0.14), vec3(0.38, 0.30, 0.21), fine) * (0.85 + 0.25 * grain);
	vec3 rock = mix(vec3(0.33, 0.32, 0.31), vec3(0.50, 0.48, 0.45), mid) * (0.75 + 0.35 * grain);

	float gravel_w = smoothstep(0.2, 0.8, COLOR.b + (fine - 0.5) * 0.4);
	vec3 col = mix(grass, gravel, gravel_w);
	float dug = smoothstep(0.1, 0.6, COLOR.r + (grain - 0.5) * 0.3);
	col = mix(col, mix(dirt, gravel, gravel_w * 0.6), dug);
	float rocky = max(smoothstep(0.42, 0.62, slope + (mid - 0.5) * 0.15), COLOR.g);
	col = mix(col, rock, rocky);

	float wet = 1.0 - smoothstep(water_level - 0.02, water_level + 0.25, world_pos.y);
	col *= mix(1.0, 0.5, wet);

	// Colors above are picked in sRGB; the renderer works in linear light.
	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = mix(0.92, 0.3, wet);
	SPECULAR = 0.35;
}
