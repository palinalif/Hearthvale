shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(1.0);
uniform float wind_strength = 0.0;
uniform float mesh_height = 1.0;

const float WIND_PERIOD = 12.0;
const float TAU_VALUE = 6.28318530718;

void vertex() {
	// INSTANCE_CUSTOM.r stores a stable phase in [0, 1). Every palette
	// surface in one planted asset receives the same phase and height, so
	// greedy-mesh seams remain closed while separate plants move independently.
	float phase = INSTANCE_CUSTOM.r * TAU_VALUE;
	float t = TAU_VALUE * mod(TIME, WIND_PERIOD) / WIND_PERIOD;
	float x = 0.72 * sin(t + phase)
		+ 0.20 * sin(2.0 * t + phase * 0.7)
		+ 0.08 * sin(3.0 * t + phase * 1.3);
	float z = 0.25 * sin(t + phase + 0.8)
		+ 0.10 * sin(2.0 * t + phase + 1.7);
	vec2 shear = vec2(x, z) * wind_strength / max(mesh_height, 0.0625);
	VERTEX.xz += shear * VERTEX.y;
	NORMAL = normalize(vec3(NORMAL.x,
		NORMAL.y - dot(shear, NORMAL.xz), NORMAL.z));
}

void fragment() {
	ALBEDO = base_color.rgb * COLOR.rgb;
	ALPHA = base_color.a * COLOR.a;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
