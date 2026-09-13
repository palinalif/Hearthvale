shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Desaturated, reference-derived meadow palette.
// The terrain remains on the native 0.125 grid; the shader only changes visual
// presentation. Broad patches are deliberately quantized rather than smoothly
// interpolated, with sparse 0.0625 detail to match decorative asset cadence.
uniform vec4 grass_light : source_color = vec4(0.667, 0.714, 0.502, 1.0); // #aab67f
uniform vec4 grass_warm : source_color = vec4(0.616, 0.667, 0.443, 1.0);  // #9daa71
uniform vec4 grass_mid : source_color = vec4(0.553, 0.604, 0.404, 1.0);   // #8d9a67
uniform vec4 grass_dark : source_color = vec4(0.408, 0.459, 0.314, 1.0);  // #687550
uniform vec4 grass_edge : source_color = vec4(0.302, 0.349, 0.247, 1.0);  // #4d593f
uniform float detail_cell = 0.0625;
uniform float meadow_patch = 1.0;

varying vec3 world_position;
varying vec3 world_normal;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	// Calm, discrete meadow patches. Most patches stay close to the midtone;
	// dark/light variants are uncommon so the ground does not compete with props.
	vec2 patch_cell = floor((world_position.xz + vec2(0.17, 0.41)) / meadow_patch);
	float patch = hash21(patch_cell + vec2(7.0, 19.0));
	vec3 top = grass_mid.rgb;
	if (patch < 0.14) {
		top = mix(grass_mid.rgb, grass_dark.rgb, 0.42);
	} else if (patch < 0.36) {
		top = mix(grass_mid.rgb, grass_dark.rgb, 0.18);
	} else if (patch > 0.91) {
		top = mix(grass_mid.rgb, grass_light.rgb, 0.28);
	} else if (patch > 0.70) {
		top = mix(grass_mid.rgb, grass_warm.rgb, 0.24);
	}

	// A second larger grid breaks obvious square repetition without introducing
	// smooth gradients. It only nudges the selected patch colour.
	vec2 region_cell = floor((world_position.xz + vec2(1.3, -0.8)) / 3.0);
	float region = hash21(region_cell + vec2(23.0, 5.0));
	if (region < 0.22) {
		top = mix(top, grass_dark.rgb, 0.08);
	} else if (region > 0.82) {
		top = mix(top, grass_warm.rgb, 0.07);
	}

	// Decorative-scale finish: sparse individual cells, never a full-field noise.
	vec2 detail = floor((world_position.xz + vec2(0.0005)) / detail_cell);
	float fine = hash21(detail + vec2(31.0, 11.0));
	if (fine < 0.018) {
		top = mix(top, grass_dark.rgb, 0.16);
	} else if (fine > 0.991) {
		top = mix(top, grass_light.rgb, 0.10);
	}

	float top_face = smoothstep(0.72, 0.96, world_normal.y);
	vec3 base = mix(grass_edge.rgb, top, top_face);
	ALBEDO = base * COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
