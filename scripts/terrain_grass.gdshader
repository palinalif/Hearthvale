shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Concept-direction meadow grass. Terrain authority remains on the native
// 0.125 grid, while presentation breakup matches the 0.0625 decorative grid.
// Most of the surface deliberately stays calm: authored foliage, shadows and
// terrace edges carry the stronger contrast instead of noisy terrain mottling.
uniform vec4 grass_mid : source_color = vec4(0.565, 0.655, 0.290, 1.0);
uniform vec4 grass_light : source_color = vec4(0.620, 0.698, 0.318, 1.0);
uniform vec4 grass_dark : source_color = vec4(0.482, 0.573, 0.255, 1.0);
uniform vec4 grass_edge : source_color = vec4(0.427, 0.494, 0.255, 1.0);
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
	// Broad variation is smooth and only about +/- 1.5%, so the meadow reads as
	// one material rather than a patchwork of terrain cells.
	float broad = value_noise(world_position.xz / 1.5);
	vec3 top = grass_mid.rgb * mix(0.985, 1.015, broad);

	// Fine variation uses the same 0.0625 visual cadence as decorative assets,
	// but only a few cells receive a very gentle accent. This gives close-range
	// voxel texture without making the whole field sparkle or checkerboard.
	vec2 detail = floor((world_position.xz + vec2(0.0005)) / detail_cell);
	float fine = hash21(detail + vec2(31.0, 11.0));
	if (fine < 0.055) {
		top = mix(top, grass_dark.rgb, 0.16);
	} else if (fine > 0.965) {
		top = mix(top, grass_light.rgb, 0.12);
	}

	float top_face = smoothstep(0.72, 0.96, world_normal.y);
	vec3 base = mix(grass_edge.rgb, top, top_face);
	ALBEDO = base * COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
