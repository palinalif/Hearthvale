shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, alpha_blend;

uniform vec4 fall_color : source_color = vec4(0.62, 0.80, 0.88, 0.70);
uniform float fall_speed = 3.0;
uniform float height = 3.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float span = max(0.001, height);
	// Streaks anchored to world x/z so the whole curtain moves together.
	float t = mod(wp.x * 0.35 + wp.z * 0.35, 1.0);
	float band = clamp((span - wp.y) / span, 0.0, 1.0);   // 0 at the top, 1 at the base
	float scroll = mod(band * 8.0 + TIME * fall_speed, 1.0);
	float streak = sin((t * 12.0 + scroll) * 6.2831) * 0.5 + 0.5;
	// Foam gathers toward the base where the water hits the pool.
	float foam = smoothstep(0.55, 1.0, band) * 0.55;
	vec3 base = mix(fall_color.rgb, vec3(1.0), clamp(foam + streak * 0.08, 0.0, 0.9));
	ALBEDO = base * COLOR.rgb;
	NORMAL = normalize(vec3(0.0, 0.0, 1.0));
	METALLIC = 0.0;
	ROUGHNESS = 0.24;
	ALPHA = fall_color.a * (0.72 + 0.28 * streak);
}
