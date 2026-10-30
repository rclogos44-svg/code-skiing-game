shader_type spatial;
// Triplanar rock with a snow cap on upward facing surfaces (world space).
render_mode diffuse_burley;

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.46, 0.44, 0.42);
uniform vec3 snow_color : source_color = vec3(0.92, 0.95, 1.0);
uniform float snow_level = 0.38;

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_wnrm);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float s = 1.0 / 3.5;
	vec3 p = v_wpos * s;
	vec3 c = texture(rock_albedo, p.zy).rgb * w.x + texture(rock_albedo, p.xz).rgb * w.y + texture(rock_albedo, p.xy).rgb * w.z;
	vec2 nx = texture(rock_normal, p.zy).rg * 2.0 - 1.0;
	vec2 ny = texture(rock_normal, p.xz).rg * 2.0 - 1.0;
	vec2 nz = texture(rock_normal, p.xy).rg * 2.0 - 1.0;
	vec3 pn = normalize(n + (vec3(0.0, nx.y, nx.x) * w.x * sign(n.x) + vec3(ny.x, 0.0, ny.y) * w.y + vec3(nz.x, nz.y, 0.0) * w.z * sign(n.z)) * 0.8);
	float snow = smoothstep(snow_level - 0.08, snow_level + 0.12, pn.y + (c.r - 0.45) * 0.4);
	ALBEDO = mix(c * tint * 2.2, snow_color, snow);
	ROUGHNESS = mix(0.88, 0.8, snow);
	NORMAL = normalize((VIEW_MATRIX * vec4(mix(pn, n, snow * 0.6), 0.0)).xyz);
}
