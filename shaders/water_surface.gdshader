shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.16, 0.44, 0.52, 0.82);
uniform vec2 flow_dir = vec2(1.0, 0.0);
uniform float flow_speed = 0.5;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 d = flow_dir;
	if (length(d) < 0.0001) d = vec2(1.0, 0.0);
	d = normalize(d);
	vec2 p = vec2(wp.x, wp.z);
	float t = TIME * flow_speed;
	// gentle moving ripple along the flow direction plus a slower cross ripple
	float ripple = sin(dot(p, d) * 6.0 - t * 3.0) * 0.5
		+ sin(dot(p, vec2(-d.y, d.x)) * 9.0 + t * 2.0) * 0.3;
	vec3 base = water_color.rgb + ripple * 0.03;
	ALBEDO = base * COLOR.rgb;
	NORMAL = normalize(vec3(ripple * 0.05, 1.0, ripple * 0.04));
	METALLIC = 0.0;
	ROUGHNESS = 0.16;
	ALPHA = water_color.a;
}
