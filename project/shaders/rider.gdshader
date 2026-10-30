// People on chairs and on the pistes: vertex-coloured low-poly figures; vertex alpha 0 marks the
// jacket, which takes the per-instance colour (MultiMesh custom data).
shader_type spatial;
render_mode cull_back;

varying vec3 v_col;

void vertex() {
	vec3 c = COLOR.rgb;
	if (COLOR.a < 0.5) {
		c = INSTANCE_CUSTOM.rgb;
	}
	v_col = pow(c, vec3(2.2));
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
}
