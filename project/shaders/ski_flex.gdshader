// Ski top sheet that flexes: under load the tip and tail bend up relative to the boot
// (and slightly the other way when unweighted in the air).
shader_type spatial;
render_mode cull_disabled;

uniform vec4 albedo : source_color = vec4(0.95, 0.95, 0.95, 1.0);
uniform float bend = 0.0;

void vertex() {
	float t = clamp(VERTEX.z / 0.88, -1.2, 1.2);
	VERTEX.y += bend * 0.07 * t * t;
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.3;
	SPECULAR = 0.6;
}
