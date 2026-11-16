// Creek water: flowing ripples, clearer in the shallows, darker where deep, foam at the edges.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture;
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_color : source_color = vec3(0.30, 0.34, 0.26);
uniform vec3 deep_color : source_color = vec3(0.05, 0.12, 0.12);
uniform float clarity = 0.8;
uniform vec2 flow = vec2(0.6, 0.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv1 = wpos.xz * 0.18 + flow * TIME * 0.12;
	vec2 uv2 = wpos.xz * 0.43 + vec2(flow.x * 0.8, flow.y + 0.07) * TIME * 0.2;
	NORMAL_MAP = mix(texture(wave_a, uv1).rgb, texture(wave_b, uv2).rgb, 0.5);
	NORMAL_MAP_DEPTH = 0.5;

	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	view_pos.xyz /= view_pos.w;
	float water_depth = clamp(VERTEX.z - view_pos.z, 0.0, 10.0);
	float t = 1.0 - exp(-water_depth / clarity);
	float foam = 1.0 - smoothstep(0.0, 0.06, water_depth);

	vec3 col = mix(shallow_color, deep_color, t);
	col = mix(col, vec3(0.75, 0.78, 0.76), foam * 0.5);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);

	ALBEDO = col;
	ALPHA = clamp(mix(0.25, 0.92, t) + fresnel * 0.5 + foam * 0.3, 0.0, 1.0);
	ROUGHNESS = 0.06;
	SPECULAR = 0.6;
}
