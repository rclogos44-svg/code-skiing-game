// Jacket fabric that moves: the skier body feeds each piece (body, hood, sleeves) a sway offset
// from a spring driven by acceleration, wind and gravity (SkierBody._cloth), plus a speed flutter.
// Vertices move more the further they are along `w_axis` (the hem, the back of the hood, the cuff),
// or - on the skinned garments - by the weight baked into the vertex colour (red).
// Double-sided: the inside of an open hem or cuff shows the darker lining.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float normal_depth = 0.5;
uniform float roughness = 0.9;
uniform float rim_amount = 0.12;
uniform float lining = 0.45;            // inside faces are this much darker
uniform vec3 sway = vec3(0.0);          // mesh-local displacement (m) at full weight
uniform vec3 w_axis = vec3(0.0, -1.0, 0.0);
uniform float w0 = -0.25;               // weight 0 at dot(VERTEX, w_axis) = w0 ...
uniform float w1 = 0.22;                // ... and 1 at w1
uniform bool color_weight = false;      // skinned garments: weight = vertex colour red
uniform float flutter = 0.0;            // ripple amplitude (m)
uniform float phase = 0.0;

void vertex() {
	float w = color_weight ? COLOR.r : smoothstep(w0, w1, dot(VERTEX, w_axis));
	float ang = atan(VERTEX.z, VERTEX.x);
	float rip = sin(phase + VERTEX.y * 23.0 + ang * 3.0) * 0.7 + sin(phase * 1.7 - VERTEX.y * 37.0 + ang * 5.0) * 0.3;
	VERTEX += sway * (w * w) + NORMAL * (flutter * w * rip);
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 c = texture(albedo_tex, uv).rgb * tint;
	if (!FRONT_FACING) {
		c *= lining;
		NORMAL = -NORMAL;
	} else {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
	ALBEDO = c;
	ROUGHNESS = roughness;
	RIM = rim_amount;
	RIM_TINT = 0.4;
}
