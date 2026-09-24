shader_type spatial;
render_mode cull_disabled, unshaded;

// Shallow plunge-pool and reservoir surface. Opaque and unshaded: the
// sunlit Mobile path turned the shallow surface ochre like the underlying bed.
// Depth-tinted vertex colors supply the variation without terrain bleed.

uniform vec4 pool_color : source_color = vec4(0.14, 0.42, 0.50, 1.0);
uniform vec2 flow_dir = vec2(1.0, 0.0);
uniform float flow_speed = 0.35;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 d = flow_dir;
	if (length(d) < 0.0001)
		d = vec2(1.0, 0.0);
	d = normalize(d);
	vec2 p = vec2(wp.x, wp.z);
	float t = TIME * flow_speed;
	// two gentle crossing ripples; the pool is calm (no streaks, no splashes)
	float ripple = sin(dot(p, d) * 6.0 - t * 3.0) * 0.5
		+ sin(dot(p, vec2(-d.y, d.x)) * 9.0 + t * 2.0) * 0.3;

	vec3 base = mix(pool_color.rgb, COLOR.rgb, 0.55);
	ALBEDO = clamp(base + ripple * 0.018, vec3(0.0), vec3(1.0));
}
