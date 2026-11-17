// Orange safety netting for the park fences: a knotted diamond mesh cut out with alpha scissor,
// UV in metres (x along the fence, y up from the snow).
shader_type spatial;
render_mode cull_disabled;

uniform vec3 net_color : source_color = vec3(1.0, 0.36, 0.04);
uniform float cell = 0.16;          // mesh opening (m)
uniform float strand = 0.022;       // strand width (m)

void fragment() {
	vec2 p = UV / cell;
	vec2 d = vec2(p.x + p.y, p.x - p.y);          // diamonds
	vec2 f = abs(fract(d) - 0.5);
	float w = strand / cell * 1.4;
	float on = step(0.5 - w, max(f.x, f.y));
	// solid hem bands top and bottom
	on = max(on, step(UV.y, 0.06));
	on = max(on, step(1.24, UV.y));
	if (on < 0.5) {
		discard;
	}
	ALBEDO = net_color * (0.85 + 0.15 * step(1.24, UV.y));
	ROUGHNESS = 0.7;
	SPECULAR = 0.3;
}
