shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Plunge-pool surface. Same gentle ripples as water_surface, but (nearly)
// opaque: the pool's voxel basin floor sits only ~0.75 m below the surface,
// so the 0.82 alpha of a normal water sheet lets the floor's voxel grid show
// through as a scattered dotted pattern. At 0.97 the pool reads as a clean
// water surface while staying a little translucent (its depth is real).

uniform vec4 pool_color : source_color = vec4(0.14, 0.42, 0.50, 0.97);
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

	vec3 base = pool_color.rgb + ripple * 0.03;
	ALBEDO = base * COLOR.rgb;
	NORMAL = normalize(vec3(ripple * 0.05, 1.0, ripple * 0.04));
	METALLIC = 0.0;
	ROUGHNESS = 0.14;
	ALPHA = pool_color.a;
}
