shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform vec4 fall_color : source_color = vec4(0.62, 0.80, 0.88, 0.70);
uniform float fall_speed = 3.0;
uniform float height = 3.0;
uniform float top_level = 4.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// --- hash / value-noise / fbm (all procedural, no textures) ---------------
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f); // smoothstep fade
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

// 3-octave value fbm in [0, 1].
float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 3; i++) {
		v += a * noise2(p);
		p = p * 2.13 + vec2(11.7, 5.3);
		a *= 0.5;
	}
	return clamp(v, 0.0, 1.0);
}

void fragment() {
	float span = max(0.001, height);
	// 0 at the crest (lip), 1 at the impact (river bed).
	float band = clamp((top_level - wp.y) / span, 0.0, 1.0);

	// --- cascading strands -------------------------------------------------
	// Thin vertical strands anchored to world x/z so neighbouring sheets
	// read as one curtain; the y term scrolls the pattern DOWNWARD over
	// time (feature at y moves to y - t*speed). z mixes in a per-sheet
	// offset so columns desynchronise instead of strobing in unison.
	float drop = wp.y + TIME * fall_speed * 4.0;
	float strand = fbm2(vec2(wp.x * 6.5 + wp.z * 3.2, drop * 0.55));
	// Higher-frequency break-up: shreds the smooth strands into broken
	// filaments and ripples travelling at a slightly different speed.
	float shred = fbm2(vec2(wp.x * 17.0 + wp.z * 9.1, (wp.y + TIME * fall_speed * 5.2) * 1.35));
	float h = strand * 0.68 + shred * 0.32; // strand height field

	// --- crest foam (water breaking over the lip) --------------------------
	float crest_mask = 1.0 - smoothstep(0.0, 0.14, band);
	float crest_churn = fbm2(vec2(wp.x * 22.0 + wp.z * 11.0, wp.y * 2.0 - TIME * 2.6));
	float foam = crest_mask * smoothstep(0.38, 0.72, crest_churn);
	foam += crest_mask * smoothstep(0.10, 0.0, band) * 0.6; // bright lip line

	// --- impact splash (churning at the plunge) -----------------------------
	float splash_mask = smoothstep(0.72, 0.97, band);
	float splash_churn = fbm2(vec2(wp.x * 26.0 + wp.z * 13.0, (wp.y + TIME * fall_speed * 6.5) * 2.2));
	float splash = splash_mask * smoothstep(0.38, 0.82, splash_churn);
	foam += splash_mask * smoothstep(1.0, 0.93, band) * 0.5; // bright impact line

	float white = clamp(foam * 0.95 + splash * 0.85 + smoothstep(0.72, 0.9, h) * 0.3, 0.0, 0.95);

	// --- colour -------------------------------------------------------------
	// Pale cyan body, brightened along strand crests, mixed to white where
	// churning (crest, splash, strand peaks).
	vec3 col = fall_color.rgb * (0.68 + 0.55 * h);
	col = mix(col, vec3(1.0), white);

	// --- pseudo-normal + fresnel + moving glint -----------------------------
	// Screen-space pseudo-normal from the derivatives of the strand height
	// field (view space, camera looks toward +z here): double-sided safe,
	// it never flips with the face orientation.
	float k = 2.2;
	vec3 n = normalize(vec3(dFdx(h) * k, -dFdy(h) * k, 1.0));
	vec3 v = vec3(0.0, 0.0, 1.0); // camera direction in view space
	float fresnel = pow(1.0 - clamp(abs(dot(n, v)), 0.0, 1.0), 3.0); // grazing light
	vec3 light = normalize(vec3(0.35, 0.75, 0.55)); // fixed view-space key light
	vec3 hv = normalize(light + v);
	float glint = pow(clamp(dot(n, hv), 0.0, 1.0), 90.0) * 0.55;
	col += fresnel * 0.16 + glint;

	col *= COLOR.rgb;

	// --- varied alpha --------------------------------------------------------
	// Opaque where churning, more transparent between strands; the bottom
	// reads as a bright splash instead of the old flat fade.
	float alpha = fall_color.a * (0.5 + 0.5 * h) + white * 0.45 + splash * 0.2;
	alpha = clamp(alpha, 0.0, 0.98);

	// The scene does not flag this material transparent, so punch hard
	// holes wherever the water is thin: the sheet breaks into discrete
	// cascading strands over the pool instead of an opaque white wall.
	// Crest and splash stay solid — their alpha exceeds the scissor.
	if (alpha < 0.40) {
		discard;
	}

	ALBEDO = col;
	ALPHA = alpha;
}
