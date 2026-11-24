extends RefCounted
## Twinkling gold: a cheap shader for flakes and flecks. Each piece (and each facet of it)
## catches the light now and then as it moves or the view shifts, flashing bright.

const SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 albedo : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.72, 0.2, 1.0);
uniform float glow_energy = 0.6;
uniform float sparkle = 6.0;
uniform float rate = 1.6;
varying float phase;
varying vec3 facet;

void vertex() {
	phase = fract(sin(float(INSTANCE_ID) * 12.9898 + 4.1) * 43758.5453) * 6.2831;
	facet = NORMAL;
}

void fragment() {
	ALBEDO = albedo.rgb;
	METALLIC = 0.75;
	ROUGHNESS = 0.25;
	SPECULAR = 0.8;
	// Facets catch the light at different moments; the view angle shifts them too.
	float f = dot(facet, vec3(3.1, 5.7, 2.3)) + phase + dot(VIEW, NORMAL) * 4.0;
	float tw = pow(max(sin(TIME * rate * (0.7 + 0.6 * fract(phase)) + f), 0.0), 40.0);
	EMISSION = glow.rgb * glow_energy + vec3(1.0, 0.93, 0.7) * tw * sparkle;
}
"""

static var _shader: Shader


static func material(energy: float = 0.6, sparkle: float = 6.0) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("glow_energy", energy)
	m.set_shader_parameter("sparkle", sparkle)
	return m
