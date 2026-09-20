shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Warm desaturated meadow palette with coherent per-patch tone variation.
//
// The palette and the coherent patch scales are published by
// scripts/m1_patch_generator.gd from scripts/grass_tone.gd, which also mirrors
// this model on the CPU for tuft tinting and determinism tests. The tone is a
// smooth multi-scale field only: an independent per-cell jitter used to alias
// into a fine diagonal moire across the whole meadow at gameplay distance, so
// voxel-level texture comes from the scattered tufts, not from this shader.
// Nothing here flattens, tiles or replaces the volumetric terrain: this is a
// material over the existing native grass voxel faces, and terrain authority
// remains on the native 0.125 grid.
uniform vec4 tone_0 : source_color = vec4(0.490, 0.588, 0.369, 1.0);
uniform vec4 tone_1 : source_color = vec4(0.537, 0.639, 0.388, 1.0);
uniform vec4 tone_2 : source_color = vec4(0.584, 0.686, 0.427, 1.0);
uniform vec4 tone_3 : source_color = vec4(0.635, 0.722, 0.471, 1.0);
uniform vec4 tone_4 : source_color = vec4(0.722, 0.788, 0.565, 1.0);
uniform vec4 tone_side_shade : source_color = vec4(0.431, 0.522, 0.337, 1.0);
uniform float tone_span = 4.0;
uniform float tone_base = 2.0;
uniform vec3 tone_scales = vec3(6.0, 1.5, 0.5);
uniform vec3 tone_weights = vec3(0.45, 0.35, 0.20);
varying vec3 world_position;
varying vec3 world_normal;
varying float tone_index;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Smooth value noise: correlated neighbours give soft hand-painted drift
// instead of a hard per-cell coin flip.
float lattice(vec2 point, float scale, float salt) {
	vec2 p = point / scale;
	vec2 base = floor(p);
	vec2 fraction = p - base;
	vec2 blend = fraction * fraction * (3.0 - 2.0 * fraction);
	float low = mix(hash21(base + vec2(salt, 0.0)), hash21(base + vec2(1.0, salt)), blend.x);
	float high = mix(hash21(base + vec2(0.0, salt + 1.0)), hash21(base + vec2(1.0, salt + 1.0)), blend.x);
	return mix(low, high, blend.y);
}

vec3 meadow_palette(float index) {
	float clamped = clamp(index, 0.0, tone_span);
	if (clamped <= 1.0) return mix(tone_0.rgb, tone_1.rgb, clamped);
	if (clamped <= 2.0) return mix(tone_1.rgb, tone_2.rgb, clamped - 1.0);
	if (clamped <= 3.0) return mix(tone_2.rgb, tone_3.rgb, clamped - 2.0);
	return mix(tone_3.rgb, tone_4.rgb, clamped - 3.0);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	// Evaluated per vertex and interpolated across the voxel face, so the field
	// reads as broad patches rather than as one flat tone per cube.
	float deviation = 0.0;
	deviation += (lattice(world_position.xz, tone_scales.x, 17.0) - 0.5) * 2.0 * tone_weights.x;
	deviation += (lattice(world_position.xz, tone_scales.y, 23.0) - 0.5) * 2.0 * tone_weights.y;
	deviation += (lattice(world_position.xz, tone_scales.z, 29.0) - 0.5) * 2.0 * tone_weights.z;
	tone_index = clamp(tone_base + deviation * tone_base, 0.0, tone_span);
}

void fragment() {
	// Coherent field only: no per-cell salt-and-pepper, which aliased into a
	// visible diagonal moire across the meadow at gameplay camera distance.
	vec3 top = meadow_palette(clamp(tone_index, 0.0, tone_span));
	float top_face = smoothstep(0.72, 0.96, world_normal.y);
	vec3 base = mix(tone_side_shade.rgb, top, top_face);
	ALBEDO = base * COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
