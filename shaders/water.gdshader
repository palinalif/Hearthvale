shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.08, 0.52, 0.57, 0.72);
uniform float wave_scale = 0.18;
uniform float wave_speed = 0.42;

void vertex() {
	float wave = sin((VERTEX.x + TIME * wave_speed) * 1.7) * wave_scale;
	wave += cos((VERTEX.z - TIME * wave_speed * 0.7) * 2.2) * wave_scale * 0.45;
	VERTEX.y += wave;
}

void fragment() {
	float ripple = 0.5 + 0.5 * sin((UV.x + UV.y) * 28.0 + TIME * wave_speed * 3.0);
	ALBEDO = water_color.rgb + vec3(0.02, 0.08, 0.07) * ripple;
	ROUGHNESS = 0.16;
	METALLIC = 0.04;
	ALPHA = water_color.a;
}
