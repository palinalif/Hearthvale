shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Warm olive meadow grass with restrained voxel-scale variation. The native
// terrain/save grid is unchanged; this is presentation only, so existing grass
// voxels receive the same treatment as fresh worlds.
uniform vec4 grass_mid : source_color = vec4(0.565, 0.655, 0.290, 1.0);
uniform vec4 grass_light : source_color = vec4(0.620, 0.698, 0.318, 1.0);
uniform vec4 grass_dark : source_color = vec4(0.482, 0.573, 0.255, 1.0);
uniform vec4 grass_edge : source_color = vec4(0.427, 0.494, 0.255, 1.0);
uniform float terrain_cell = 0.125;

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
	vec2 cell = floor((world_position.xz + vec2(0.0005)) / terrain_cell);
	float fine = hash21(cell);
	float broad = hash21(floor(cell / 6.0) + vec2(17.0, 29.0));

	vec3 top = grass_mid.rgb;
	if (fine < 0.22) {
		top = grass_dark.rgb;
	} else if (fine > 0.78) {
		top = grass_light.rgb;
	}
	top *= mix(0.965, 1.035, broad);

	float top_face = smoothstep(0.72, 0.96, world_normal.y);
	vec3 base = mix(grass_edge.rgb, top, top_face);
	ALBEDO = base * COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
