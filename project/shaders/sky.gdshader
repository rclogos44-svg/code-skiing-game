shader_type sky;
// Alpine sky: altitude gradient, sun disk and glow, static procedural cloud layer.
render_mode use_debanding;

uniform vec3 zenith_color : source_color = vec3(0.13, 0.32, 0.68);
uniform vec3 horizon_color : source_color = vec3(0.60, 0.74, 0.90);
uniform vec3 ground_color : source_color = vec3(0.50, 0.58, 0.68);
uniform float sun_size = 0.7;
uniform float sun_glow = 0.6;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_coverage = 0.42;
uniform float cloud_scale = 0.32;
uniform float exposure = 1.0;

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		float t = pow(1.0 - h, 4.0);
		col = mix(zenith_color, horizon_color, t);
	} else {
		col = mix(horizon_color, ground_color, clamp(-h * 5.0, 0.0, 1.0));
	}
	float sun_d = 0.0;
	if (LIGHT0_ENABLED) {
		sun_d = dot(d, LIGHT0_DIRECTION);
		float halo = pow(max(sun_d, 0.0), 8.0) * 0.18 + pow(max(sun_d, 0.0), 120.0) * sun_glow;
		col += LIGHT0_COLOR * halo;
		if (!AT_CUBEMAP_PASS) {
			float disk = smoothstep(cos(radians(sun_size)), cos(radians(sun_size * 0.7)), sun_d);
			col += LIGHT0_COLOR * LIGHT0_ENERGY * disk * 12.0;
		}
	}
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * cloud_scale;
		float n = texture(cloud_noise, uv * 0.35).r * 0.62 + texture(cloud_noise, uv * 1.3 + 0.21).g * 0.28 + texture(cloud_noise, uv * 4.1 + 0.6).b * 0.10;
		float c = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.28, n);
		c *= smoothstep(0.0, 0.18, h);
		float lit = 0.75 + 0.35 * max(sun_d, 0.0);
		vec3 cloud_col = mix(vec3(0.82, 0.86, 0.92), vec3(1.0, 0.98, 0.95), lit - 0.6) * lit;
		col = mix(col, cloud_col, c * 0.85);
	}
	COLOR = col * exposure;
}
