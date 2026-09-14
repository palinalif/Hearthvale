shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Warm desaturated meadow palette proposed for Hearthvale.
// Variation stays discrete and fine-grained: no smooth value-noise gradients,
// and no metre-scale tiles. Terrain authority remains on the native 0.125 grid.
uniform vec4 grass_light : source_color = vec4(0.820, 0.867, 0.549, 1.0); // #d1dd8c rare light accent
uniform vec4 grass_lift : source_color = vec4(0.694, 0.788, 0.490, 1.0);  // #b1c97d lifted green
uniform vec4 grass_mid : source_color = vec4(0.588, 0.729, 0.400, 1.0);   // #96ba66 base
uniform vec4 grass_dark : source_color = vec4(0.502, 0.647, 0.384, 1.0);  // #80a562 shadow
uniform vec4 grass_edge : source_color = vec4(0.408, 0.557, 0.322, 1.0);  // #688e52 deep shadow
uniform float detail_cell = 0.0625;
uniform float meadow_patch = 0.25;

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
	// The proposed #96ba66 is the dominant field colour. Quarter-metre cells
	// provide restrained voxel-like breakup without returning to chunky patches.
	vec2 patch_cell = floor((world_position.xz + vec2(0.07, 0.11)) / meadow_patch);
	float patch = hash21(patch_cell + vec2(7.0, 19.0));
	vec3 top = grass_mid.rgb;
	if (patch < 0.10) {
		top = mix(grass_mid.rgb, grass_dark.rgb, 0.34);
	} else if (patch < 0.24) {
		top = mix(grass_mid.rgb, grass_dark.rgb, 0.14);
	} else if (patch > 0.95) {
		top = mix(grass_mid.rgb, grass_light.rgb, 0.16);
	} else if (patch > 0.78) {
		top = mix(grass_mid.rgb, grass_lift.rgb, 0.16);
	}

	// A broad, very low-strength region bias prevents uniform wallpaper while
	// staying subtle enough that it does not read as large square patches.
	vec2 region_cell = floor((world_position.xz + vec2(0.8, -1.1)) / 1.5);
	float region = hash21(region_cell + vec2(23.0, 5.0));
	if (region < 0.18) {
		top = mix(top, grass_dark.rgb, 0.035);
	} else if (region > 0.84) {
		top = mix(top, grass_lift.rgb, 0.035);
	}

	// Sparse decorative-scale accents add texture only when viewed close-up.
	vec2 detail = floor((world_position.xz + vec2(0.0005)) / detail_cell);
	float fine = hash21(detail + vec2(31.0, 11.0));
	if (fine < 0.012) {
		top = mix(top, grass_dark.rgb, 0.12);
	} else if (fine > 0.994) {
		top = mix(top, grass_light.rgb, 0.08);
	}

	float top_face = smoothstep(0.72, 0.96, world_normal.y);
	vec3 base = mix(grass_edge.rgb, top, top_face);
	ALBEDO = base * COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
