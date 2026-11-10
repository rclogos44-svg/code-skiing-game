shader_type spatial;
// Mountain rock (granite): triplanar in world space at two scales - a 2.4 m detail tile and a 21 m
// macro tile that breaks up the repetition across big boulders - with faint banding along the
// strata, lichen-dark streaks, roughness following the texture, and snow where it settles: on
// faces turned up (patchy, with an irregular edge, never painted on the walls) and drifted round
// the base where the rock meets the slope.  Rocks are MultiMesh instances sunk 35 % of their size.
render_mode diffuse_burley;

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.46, 0.44, 0.42);
uniform vec3 tint_warm : source_color = vec3(0.52, 0.46, 0.4);
uniform vec3 snow_color : source_color = vec3(0.92, 0.95, 1.0);
uniform float snow_level = 0.7;       // faces with an up-component past this hold snow
uniform float detail_scale = 2.4;     // m per detail tile
uniform float macro_scale = 21.0;     // m per macro tile
uniform float drift = 0.05;           // base drift height, fraction of the rock's size (about a quarter of what shows)

varying vec3 v_wpos;
varying vec3 v_wnrm;
varying float v_above;                // height above the snow line at the rock's base (in rock sizes)

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float size = length(MODEL_MATRIX[0].xyz);
	v_above = (v_wpos.y - MODEL_MATRIX[3].y) / max(size, 0.01) - 0.35;
}

vec3 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy).rgb * w.x + texture(t, p.xz).rgb * w.y + texture(t, p.xy).rgb * w.z;
}

void fragment() {
	vec3 n = normalize(v_wnrm);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = v_wpos / detail_scale;
	vec3 c = tri(rock_albedo, p, w);
	// the texture's own average (its smallest mip): variations are measured against it
	vec3 avg = max(textureLod(rock_albedo, vec2(0.5), 12.0).rgb, vec3(0.02));
	// macro: the same texture very large, as a slow light / dark and warm / cold variation
	vec3 m = tri(rock_albedo, v_wpos / macro_scale + vec3(0.37, 0.11, 0.73), w);
	float macro = clamp((m.r - avg.r) / avg.r, -1.0, 1.0) * 0.5;
	vec3 base = mix(tint, tint_warm, clamp(0.5 + macro, 0.0, 1.0)) * (1.0 + 0.3 * macro);
	// strata: faint bands running along the rock (they tilt with the bedding)
	float band = sin(v_wpos.y * 3.1 + v_wpos.x * 0.6 + macro * 4.0) * 0.5 + 0.5;
	base *= 0.93 + 0.1 * band;
	// darker streaks down the walls (lichen / water stains)
	float st = texture(rock_albedo, vec2(v_wpos.x * 0.21 + v_wpos.z * 0.17, v_wpos.y * 0.035)).g;
	float streak = smoothstep(0.25, 0.6, (st - avg.g) / avg.g) * (1.0 - abs(n.y));
	vec3 rock = c * base * 2.2 * (1.0 - 0.25 * streak);
	// normal detail
	vec2 nx = texture(rock_normal, p.zy).rg * 2.0 - 1.0;
	vec2 ny = texture(rock_normal, p.xz).rg * 2.0 - 1.0;
	vec2 nz = texture(rock_normal, p.xy).rg * 2.0 - 1.0;
	vec3 pn = normalize(n + (vec3(0.0, nx.y, nx.x) * w.x * sign(n.x) + vec3(ny.x, 0.0, ny.y) * w.y + vec3(nz.x, nz.y, 0.0) * w.z * sign(n.z)) * 0.85);
	// snow on what faces up, with a patchy, irregular edge (texture detail + macro noise); the walls
	// stay bare however tall the rock is
	float edge = clamp((c.g - avg.g) / avg.g, -1.0, 1.0) * 0.1 + macro * 0.14;
	float snow_up = smoothstep(snow_level - 0.06, snow_level + 0.1, mix(n.y, pn.y, 0.4) + edge);
	// drifted round the base on the gentler faces (not up the walls)
	float base_drift = smoothstep(drift, 0.0, v_above + edge * 0.1) * smoothstep(0.25, 0.6, n.y);
	float snow = clamp(max(snow_up, base_drift), 0.0, 1.0);
	ALBEDO = mix(rock, snow_color, snow);
	ROUGHNESS = mix(0.8 + 0.15 * clamp(1.0 - c.r / avg.r, -1.0, 1.0), 0.82, snow);
	SPECULAR = mix(0.35, 0.45, snow);
	NORMAL = normalize((VIEW_MATRIX * vec4(mix(pn, n, snow * 0.7), 0.0)).xyz);
}
