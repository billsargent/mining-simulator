// Distant trees, drawn in 512 m blocks (one draw each). Near trees are drawn per 128 m region
// and hidden past scatter.gd NEAR_TREES; this hides a far tree while its own region is still
// close enough for the near trees, so the two never both show or both go missing.
shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform vec3 albedo : source_color = vec3(0.12, 0.18, 0.1);
uniform float region = 128.0;
uniform float near_end = 220.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec2 r0 = floor(origin.xz / region) * region;
	vec2 d = max(max(r0 - cam.xz, cam.xz - (r0 + region)), vec2(0.0));
	if (length(d) < near_end) {
		VERTEX = vec3(0.0);   // all corners on one point: the tree draws nothing
	}
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
}
