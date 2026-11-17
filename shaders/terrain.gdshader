// Ground: grass, creek gravel, roads, freshly dug dirt, exposed bedrock and rocky slopes.
// Vertex color carries per-vertex data from world_terrain.gd:
//   r = dug (disturbed ground), g = bedrock exposed, b = bare gravel (creek bed, bars, roads),
//   a = height above the local water, (h - water + 0.5) / 3, so 1 means far from any water
// Culling is off so the skirts that hide seams between detail levels always draw.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform sampler2D noise_large : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_detail : filter_linear_mipmap, repeat_enable;
// Regions (see world_gen.gd REGIONS): where each is, its grass and rock colors (sRGB), and how
// much bare sand or dirt shows through. They blend like the land does.
uniform vec2 region_center[6];
uniform vec3 region_grass[6];
uniform vec3 region_rock[6];
uniform float region_bare[6];
uniform float region_k = 300.0;
uniform float snow_line = 400.0;

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

	float dmin = 1e9;
	float dist[6];
	for (int r = 0; r < 6; r++) {
		dist[r] = distance(p, region_center[r]);
		dmin = min(dmin, dist[r]);
	}
	vec3 rg = vec3(0.0);
	vec3 rr = vec3(0.0);
	float bare = 0.0;
	float total = 0.0;
	for (int r = 0; r < 6; r++) {
		float w = exp(-(dist[r] - dmin) / region_k);
		rg += region_grass[r] * w;
		rr += region_rock[r] * w;
		bare += region_bare[r] * w;
		total += w;
	}
	rg /= total;
	rr /= total;
	bare /= total;

	vec3 grass = mix(rg * 0.72, rg * 1.15, smoothstep(0.3, 0.75, big));
	grass *= 0.78 + 0.4 * mid * fine;
	grass = mix(grass, vec3(0.40, 0.36, 0.22), smoothstep(0.62, 0.85, mid) * 0.5);
	vec3 sand = mix(vec3(0.60, 0.50, 0.36), vec3(0.72, 0.62, 0.46), fine) * (0.85 + 0.25 * grain);
	grass = mix(grass, sand, clamp(bare + (big - 0.5) * 0.4 * bare, 0.0, 1.0));

	vec3 gravel = mix(vec3(0.42, 0.39, 0.35), vec3(0.60, 0.56, 0.50), grain) * (0.8 + 0.3 * fine);
	vec3 dirt = mix(vec3(0.27, 0.20, 0.14), vec3(0.38, 0.30, 0.21), fine) * (0.85 + 0.25 * grain);
	vec3 rock = rr * mix(0.8, 1.2, mid) * (0.75 + 0.35 * grain);

	float gravel_w = smoothstep(0.2, 0.8, COLOR.b + (fine - 0.5) * 0.4);
	vec3 col = mix(grass, gravel, gravel_w);
	float dug = smoothstep(0.1, 0.6, COLOR.r + (grain - 0.5) * 0.3);
	col = mix(col, mix(dirt, gravel, gravel_w * 0.6), dug);
	float rocky = max(smoothstep(0.42, 0.62, slope + (mid - 0.5) * 0.15), COLOR.g);
	col = mix(col, rock, rocky);
	float snow = smoothstep(snow_line, snow_line + 45.0, world_pos.y + (mid - 0.5) * 40.0) * (1.0 - smoothstep(0.55, 0.8, slope));
	col = mix(col, vec3(0.9, 0.91, 0.94), snow);

	float wet = 1.0 - smoothstep(0.16, 0.26, COLOR.a);
	col *= mix(1.0, 0.5, wet);

	// Colors above are picked in sRGB; the renderer works in linear light.
	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = mix(0.92, 0.3, wet);
	SPECULAR = 0.35;
}
