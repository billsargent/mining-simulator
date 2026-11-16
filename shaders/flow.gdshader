// Water running down a sluice: ripples streaming toward +x (the outlet).
shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D ripple : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.45, 0.42, 0.34);
uniform float speed = 1.4;

void fragment() {
	vec2 uv = UV * vec2(2.5, 0.8) - vec2(TIME * speed, 0.0);
	vec2 uv2 = UV * vec2(5.0, 1.6) - vec2(TIME * speed * 1.6, 0.3);
	vec3 n1 = texture(ripple, uv).rgb;
	vec3 n2 = texture(ripple, uv2).rgb;
	NORMAL_MAP = mix(n1, n2, 0.5);
	NORMAL_MAP_DEPTH = 1.0;
	float foam = smoothstep(0.58, 0.8, n2.r);
	ALBEDO = mix(tint, vec3(0.85), foam * 0.35);
	ALPHA = 0.55 + foam * 0.25;
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
}
