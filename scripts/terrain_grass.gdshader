shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Literal reference-picked meadow palette pass.
// Terrain authority remains on the native 0.125 grid, while presentation
// accents align to the 0.0625 decorative cadence. Broad calm olive patches
// carry most of the variation; tiny cells are only a finishing texture.
uniform vec4 grass_light : source_color = vec4(0.635, 0.714, 0.357, 1.0); // #a2b65b
uniform vec4 grass_warm : source_color = vec4(0.580, 0.667, 0.294, 1.0);  // #94aa4b
uniform vec4 grass_mid : source_color = vec4(0.522, 0.604, 0.271, 1.0);   // #859a45
uniform vec4 grass_dark : source_color = vec4(0.376, 0.459, 0.216, 1.0);  // #607537
uniform vec4 grass_edge : source_color = vec4(0.271, 0.349, 0.176, 1.0);  // #45592d
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
	float broad = value_noise(world_position.xz / 2.5);
	float local = value_noise((world_position.xz + vec2(17.3, -9.1)) / 0.55);
	vec3 top;
	if (broad < 0.28) {
		top = mix(grass_edge.rgb, grass_dark.rgb, smoothstep(0.02, 0.28, broad));
	} else if (broad < 0.56) {
		top = mix(grass_dark.rgb, grass_mid.rgb, smoothstep(0.28, 0.56, broad));
	} else if (broad < 0.82) {
		top = mix(grass_mid.rgb, grass_warm.rgb, smoothstep(0.56, 0.82, broad));
	} else {
		top = mix(grass_warm.rgb, grass_light.rgb, smoothstep(0.82, 0.98, broad));
	}

	// Gentle intra-patch drift: enough to read from normal gameplay distance,
	// but not enough to become speckled or checkerboard-like.
	top = mix(top, grass_mid.rgb, 0.18);
	top = mix(top, grass_dark.rgb, 0.08 * smoothstep(0.0, 0.45, local));
	top = mix(top, grass_warm.rgb, 0.08 * smoothstep(0.55, 1.0, local));

	vec2 detail = floor((world_position.xz + vec2(0.0005)) / detail_cell);
	float fine = hash21(detail + vec2(31.0, 11.0));
	if (fine < 0.05) {
		top = mix(top, grass_dark.rgb, 0.18);
	} else if (fine > 0.975) {
		top = mix(top, grass_light.rgb, 0.12);
	}

	float top_face = smoothstep(0.72, 0.96, world_normal.y);
	vec3 base = mix(grass_edge.rgb, top, top_face);
	ALBEDO = base * COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
