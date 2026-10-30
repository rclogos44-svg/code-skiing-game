// Round minimap: samples the painted map image around the player, rotated with the camera.
shader_type canvas_item;

uniform vec2 center_uv;     // player position / world size
uniform float radius_uv;    // view radius / world size
uniform float yaw;          // camera yaw (0 = north up)

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float c = cos(yaw);
	float s = sin(yaw);
	vec2 d = vec2(q.x * c + q.y * s, -q.x * s + q.y * c);
	vec2 uv = center_uv + d * radius_uv;
	vec4 col = texture(TEXTURE, uv);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		col = vec4(0.16, 0.19, 0.24, 1.0);
	}
	// soft vignette toward the rim keeps the overlay readable
	col.rgb *= mix(1.0, 0.82, smoothstep(0.55, 1.0, r));
	COLOR = vec4(col.rgb, smoothstep(1.0, 0.975, r));
}
