shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 palette_color : source_color = vec4(1.0);
uniform vec2 wind_shear = vec2(0.0);

void vertex() {
	// One affine deformation for every palette surface. Greedy-face T junctions
	// stay coincident; ground-contact vertices remain exactly stationary.
	VERTEX.xz += wind_shear * VERTEX.y;
	// Inverse-transpose of the shear, so sunlight and shadows follow the lean.
	NORMAL = normalize(vec3(NORMAL.x,
		NORMAL.y - dot(wind_shear, NORMAL.xz), NORMAL.z));
}

void fragment() {
	ALBEDO = palette_color.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
