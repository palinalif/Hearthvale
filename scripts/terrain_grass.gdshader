shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Concept-direction meadow grass. Terrain authority remains on the native
// 0.125 grid, while the smallest presentation breakup matches the 0.0625
// decorative grid. The reference meadow is much dustier than the old game
// green: broad, softly blended olive patches do most of the colour work and
// tiny cells only add a restrained close-range texture.
uniform vec4 grass_mid : source_color = vec4(0.490, 0.565, 0.305, 1.0);
uniform vec4 grass_light : source_color = vec4(0.565, 0.635, 0.335, 1.0);
uniform vec4 grass_dark : source_color = vec4(0.390, 0.465, 0.245, 1.0);
uniform vec4 grass_edge : source_color = vec4(0.315, 0.375, 0.215, 1.0);
uniform float detail_cell = 0.0625;

varying vec3 world_position;
varying vec3 world_normal;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	// Layer two smooth fields. The 2.5 m field creates calm meadow regions while
	// the 0.5 m field adds visible local variation without exposing terrain-cell
	// boundaries. Colour moves through an olive palette instead of merely
	// brightening/darkening one saturated green.
	float broad = value_noise(world_position.xz / 2.5);
	float local = value_noise(world_position.xz / 0.5 + vec2(19.7, 41.3));
	float field = clamp(0.5 + (broad - 0.5) * 0.82 + (local - 0.5) * 0.28, 0.0, 1.0);
	vec3 patch_colour = mix(grass_dark.rgb, grass_light.rgb, smoothstep(0.08, 0.92, field));
	vec3 top = mix(grass_mid.rgb, patch_colour, 0.52);

	// Fine variation uses the same 0.0625 visual cadence as decorative assets.
	// It is deliberately sparse and weak: this should read as texture only once
	// the player gets close, not as noise across the whole meadow.
	vec2 detail = floor((world_position.xz + vec2(0.0005)) / detail_cell);
	float fine = hash21(detail + vec2(31.0, 11.0));
	if (fine < 0.070) {
		top = mix(top, grass_dark.rgb, 0.11);
	} else if (fine > 0.955) {
		top = mix(top, grass_light.rgb, 0.09);
	}

	float top_face = smoothstep(0.72, 0.96, world_normal.y);
	vec3 base = mix(grass_edge.rgb, top, top_face);
	ALBEDO = base * COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
