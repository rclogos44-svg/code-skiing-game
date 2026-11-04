shader_type spatial;
// SUMMIT terrain: CDLOD geomorphing + slope-aware snow / ice / rock material with
// baked long-distance sun shadows, snow sparkle and groomed corduroy.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D height_core : filter_nearest, repeat_disable;
uniform sampler2D height_far : filter_nearest, repeat_disable;
uniform sampler2D normal_core : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D surface_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D bake_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D far_bake_tex : filter_linear, repeat_disable;
uniform sampler2D snow_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

uniform float core_min = 0.0;
uniform float core_scale = 1.0;
uniform float far_min = 0.0;
uniform float far_scale = 1.0;
uniform int core_n = 3073;
uniform float core_spacing = 2.0;
uniform float world_size = 6144.0;
uniform int far_n = 577;
uniform float far_spacing = 32.0;
uniform float far_origin = -6144.0;
uniform vec3 lod_cam = vec3(0.0);
uniform vec2 morph_ranges[10];
uniform float shadow_fade_start = 250.0;
uniform float shadow_fade_end = 450.0;
uniform vec3 snow_tint : source_color = vec3(0.84, 0.89, 0.95);
uniform vec3 shade_tint : source_color = vec3(0.80, 0.86, 0.98);
uniform vec3 ice_tint : source_color = vec3(0.70, 0.82, 0.95);
uniform vec3 rock_tint : source_color = vec3(0.42, 0.40, 0.38);
uniform float sparkle_strength = 0.45;

varying vec3 v_world;
varying float v_sun;
varying float v_sparkle;
varying float v_wrap;
varying float v_bounce;

float hc(ivec2 i) {
	i = clamp(i, ivec2(0), ivec2(core_n - 1));
	vec2 t = texelFetch(height_core, i, 0).rg;
	return (round(t.r * 255.0) * 256.0 + round(t.g * 255.0)) * core_scale + core_min;
}

float hf(ivec2 i) {
	i = clamp(i, ivec2(0), ivec2(far_n - 1));
	vec2 t = texelFetch(height_far, i, 0).rg;
	return (round(t.r * 255.0) * 256.0 + round(t.g * 255.0)) * far_scale + far_min;
}

float height_core_at(vec2 p) {
	vec2 g = p / core_spacing;
	ivec2 i = ivec2(floor(g));
	vec2 f = g - vec2(i);
	float a = hc(i);
	float b = hc(i + ivec2(1, 0));
	float c = hc(i + ivec2(0, 1));
	float d = hc(i + ivec2(1, 1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float height_far_at(vec2 p) {
	vec2 g = clamp((p - vec2(far_origin)) / far_spacing, vec2(0.0), vec2(float(far_n) - 1.001));
	ivec2 i = ivec2(floor(g));
	vec2 f = g - vec2(i);
	float a = hf(i);
	float b = hf(i + ivec2(1, 0));
	float c = hf(i + ivec2(0, 1));
	float d = hf(i + ivec2(1, 1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

bool in_core(vec2 p) {
	return p.x >= 0.0 && p.y >= 0.0 && p.x <= world_size && p.y <= world_size;
}

float terrain_h(vec2 p) {
	return in_core(p) ? height_core_at(p) : height_far_at(p);
}

vec3 terrain_n(vec2 p, float e) {
	float l = terrain_h(p - vec2(e, 0.0));
	float r = terrain_h(p + vec2(e, 0.0));
	float d = terrain_h(p - vec2(0.0, e));
	float u = terrain_h(p + vec2(0.0, e));
	return normalize(vec3(l - r, 2.0 * e, d - u));
}

void vertex() {
	vec2 origin = INSTANCE_CUSTOM.xy;
	float psize = INSTANCE_CUSTOM.z;
	int level = int(INSTANCE_CUSTOM.w + 0.5);
	vec2 grid = VERTEX.xz * 16.0;
	vec2 wp = origin + VERTEX.xz * psize;
	float dist = distance(wp, lod_cam.xz);
	vec2 mr = morph_ranges[level];
	float k = clamp((dist - mr.x) / max(mr.y - mr.x, 1.0), 0.0, 1.0);
	grid -= fract(grid * 0.5) * 2.0 * k;
	wp = origin + grid / 16.0 * psize;
	float h = terrain_h(wp);
	VERTEX = vec3(wp.x, h, wp.y);
	float spacing = psize / 16.0;
	NORMAL = terrain_n(wp, max(spacing, 2.0));
	v_world = VERTEX;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 triplanar_rock(vec3 wp, vec3 n, out vec3 nrm) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float s = 1.0 / 7.0;
	vec3 cx = texture(rock_albedo, wp.zy * s).rgb;
	vec3 cy = texture(rock_albedo, wp.xz * s).rgb;
	vec3 cz = texture(rock_albedo, wp.xy * s).rgb;
	vec2 nx = texture(rock_normal, wp.zy * s).rg * 2.0 - 1.0;
	vec2 ny = texture(rock_normal, wp.xz * s).rg * 2.0 - 1.0;
	vec2 nz = texture(rock_normal, wp.xy * s).rg * 2.0 - 1.0;
	// whiteout-style blend of tangent normals into world space
	vec3 tx = vec3(0.0, nx.y, nx.x) * sign(n.x);
	vec3 ty = vec3(ny.x, 0.0, ny.y);
	vec3 tz = vec3(nz.x, nz.y, 0.0) * sign(n.z);
	nrm = normalize(n + (tx * w.x + ty * w.y + tz * w.z) * 0.9);
	return cx * w.x + cy * w.y + cz * w.z;
}

void fragment() {
	vec3 wp = v_world;
	vec2 p = wp.xz;
	float cam_dist = length(wp - CAMERA_POSITION_WORLD);
	vec3 n;
	vec4 surf;
	vec4 bake;
	if (in_core(p)) {
		vec2 nr = texture(normal_core, p / world_size).rg * 2.0 - 1.0;
		n = vec3(nr.x, sqrt(max(1.0 - dot(nr, nr), 0.0)), nr.y);
		vec2 suv = (p / 4.0 + 0.5) / 1537.0;
		surf = texture(surface_tex, suv);
		bake = texture(bake_tex, suv);
	} else {
		n = terrain_n(p, 24.0);
		vec2 fuv = (p - vec2(far_origin)) / (far_spacing * float(far_n - 1));
		float fb = texture(far_bake_tex, fuv).r;
		bake = vec4(fb, 0.85, smoothstep(0.66, 0.5, n.y), 1.0);
		surf = vec4(0.6, 0.0, 0.15, 0.0);
	}
	float slope = 1.0 - n.y;
	vec4 nz1 = texture(noise_tex, p / 260.0);
	vec4 nz2 = texture(noise_tex, p / 37.0);
	// --- rock exposure
	float rock = max(bake.b, smoothstep(0.30, 0.42, slope + (nz2.r - 0.5) * 0.12));
	// snow clings to the flatter parts of rock faces
	rock *= smoothstep(0.12, 0.30, slope + (nz1.g - 0.5) * 0.15);
	// --- snow detail normals (two scales, fades with distance)
	float detail_fade = 1.0 - smoothstep(60.0, 450.0, cam_dist);
	vec2 dn1 = texture(snow_normal, p / 3.1).rg * 2.0 - 1.0;
	vec2 dn2 = texture(snow_normal, p / 23.0 + 0.37).rg * 2.0 - 1.0;
	float powder = surf.r;
	float groomed = surf.g;
	float ice = surf.b;
	vec2 dn = dn1 * (0.35 + 0.35 * powder) * detail_fade + dn2 * 0.45;
	// groomed corduroy along the fall line
	vec2 fall = normalize(-n.xz + vec2(1e-4));
	vec2 perp = vec2(-fall.y, fall.x);
	float cord_phase = dot(p, perp) * 6.2831 / 0.11;
	float cord_fade = groomed * (1.0 - smoothstep(8.0, 45.0, cam_dist));
	dn += perp * cos(cord_phase) * 0.35 * cord_fade;
	vec3 sn = normalize(n + vec3(dn.x, 0.0, dn.y) * 0.55);
	// --- albedo / roughness
	float macro = nz1.r * 0.6 + nz2.g * 0.4;
	vec3 snow = snow_tint * (0.95 + 0.07 * macro);
	snow = mix(snow, snow * vec3(0.97, 0.985, 1.0), powder * 0.5);
	snow = mix(snow, snow * 0.93, groomed * 0.6);
	snow = mix(snow, ice_tint, ice * 0.55);
	// forest floor: needles and shade
	snow = mix(snow, snow * vec3(0.86, 0.88, 0.9), surf.a * 0.55);
	// Wind-combed snow and powder retain distinct microstructure, with distance filtering.
	float wind_ripple = sin(dot(p, vec2(0.75, 0.66)) * 2.4 + nz2.g * 4.0);
	snow *= 1.0 + wind_ripple * 0.025 * ice * detail_fade;
	float rough = mix(0.88, 0.68, groomed) + (nz2.r - 0.5) * 0.08;
	rough = mix(rough, 0.32, ice * 0.8);
	vec3 rn;
	vec3 rcol = triplanar_rock(wp, n, rn) * rock_tint * 2.6;
	rcol *= 0.85 + 0.3 * nz2.b;
	float rock_mask = clamp(rock * (0.85 + 0.3 * nz2.a), 0.0, 1.0);
	// snow dusting on rock top faces
	float dust = smoothstep(0.55, 0.85, dot(rn, vec3(0.0, 1.0, 0.0))) * 0.6;
	rock_mask *= 1.0 - dust;
	vec3 albedo = mix(snow, rcol, rock_mask);
	vec3 nf = normalize(mix(sn, rn, rock_mask));
	float rough_f = mix(rough, 0.9, rock_mask);
	float spec_f = mix(0.35, 0.2, rock_mask);
	// frozen lakes: glassy blue-grey ice with cracks and wind-blown snow drifts
	float lake = clamp(1.0 - bake.a, 0.0, 1.0);
	if (lake > 0.001) {
		vec4 nz3 = texture(noise_tex, p / 23.0 + 0.5);
		float crack = smoothstep(0.035, 0.0, abs(nz3.b - 0.5)) + smoothstep(0.02, 0.0, abs(nz2.r - 0.5)) * 0.6;
		vec3 ice_col = vec3(0.40, 0.58, 0.74) * (0.88 + 0.24 * nz1.g);
		ice_col = mix(ice_col, vec3(0.86, 0.92, 0.97), clamp(crack, 0.0, 1.0) * 0.55);
		float drift = smoothstep(0.80, 0.97, nz3.r + nz2.g * 0.12) * 0.85;
		vec3 lake_col = mix(ice_col, snow, drift);
		albedo = mix(albedo, lake_col, lake);
		rough_f = mix(rough_f, mix(0.2, 0.72, drift), lake);
		spec_f = mix(spec_f, mix(0.32, 0.3, drift), lake);
		nf = normalize(mix(nf, normalize(n + vec3(dn1.x, 0.0, dn1.y) * 0.04), lake * (1.0 - drift)));
	}
	ALBEDO = albedo;
	ROUGHNESS = rough_f;
	SPECULAR = spec_f;
	NORMAL = normalize((VIEW_MATRIX * vec4(nf, 0.0)).xyz);
	AO = mix(1.0, bake.g, 0.6 - 0.25 * rock_mask);
	AO_LIGHT_AFFECT = 0.0;
	// baked terrain shadows take over where real-time shadows end
	float fade = smoothstep(shadow_fade_start, shadow_fade_end, cam_dist);
	v_sun = mix(1.0, bake.r, mix(0.35, 1.0, fade));
	// sparkle: sparse glints that shimmer with view direction
	vec2 sg = p * 22.0;
	vec2 cell = floor(sg);
	vec2 cf = fract(sg) - 0.5;
	float hsh = hash12(cell + vec2(0.0));
	float dotm = smoothstep(0.32, 0.08, length(cf));
	v_sparkle = step(0.994, hsh) * dotm * (1.0 - rock_mask) * (1.0 - smoothstep(3.0, 18.0, cam_dist)) * sparkle_strength * (1.0 - groomed * 0.6);
	v_wrap = (1.0 - rock_mask) * 0.25;
	// light bounced off the surrounding sunlit snow fills steep faces and shaded slopes
	v_bounce = (0.10 + 0.22 * rock_mask) * smoothstep(0.08, 0.7, slope);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float diff = clamp((ndl + v_wrap) / (1.0 + v_wrap), 0.0, 1.0);
	float sh = min(ATTENUATION, v_sun);
	DIFFUSE_LIGHT += (diff * sh + v_bounce) * LIGHT_COLOR / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float r = max(ROUGHNESS, 0.05);
	float a2 = r * r * r * r;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float spec = a2 / (PI * dd * dd) * 0.06;
	SPECULAR_LIGHT += (spec * clamp(ndl, 0.0, 1.0) + v_sparkle * pow(clamp(dot(NORMAL, h), 0.0, 1.0), 64.0) * 2.0 * step(0.0, ndl)) * sh * LIGHT_COLOR / PI;
}
