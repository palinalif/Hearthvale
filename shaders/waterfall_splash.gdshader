shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

// Soft elliptical foam bed where a cascade lands. Replaces the old
// hard-edged flat square decal: a churning bright core fading to a
// transparent rim, animated by drifting noise so the foam never reads
// as a painted sticker.
uniform vec2 center = vec2(0.0, 0.0);
uniform vec2 radius = vec2(2.0, 2.0);
uniform float strength = 0.55;

varying vec2 p;

void vertex() {
	vec4 w = (MODEL_MATRIX * vec4(VERTEX, 1.0));
	p = w.xz;
}

float hash21(vec2 q) {
	return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise2(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

void fragment() {
	vec2 e = (p - center) / max(radius, vec2(0.001));
	float d = length(e);
	// Drifting churn in the core; calm at the rim.
	float churn = noise2(e * 6.0 + vec2(TIME * 1.4, -TIME * 1.1))
		* (1.0 - smoothstep(0.0, 1.0, d));
	float alpha = strength * (1.0 - smoothstep(0.55, 1.0, d)) * (0.55 + 0.65 * churn);
	if (alpha < 0.03) {
		discard;
	}
	ALBEDO = vec3(0.92, 0.98, 1.0) * (0.75 + 0.25 * churn) * COLOR.rgb;
	ALPHA = alpha;
}
