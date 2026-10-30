// Speed streaks: thin radial lines rushing toward the screen edges at high speed.
shader_type canvas_item;

uniform float amount = 0.0;
uniform float t = 0.0;
uniform float aspect = 1.78;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 p = UV - 0.5;
	p.x *= aspect;
	float r = length(p);
	float a = atan(p.y, p.x) / 6.2831853 + 0.5;
	float spoke = floor(a * 90.0);
	float on = step(0.82, hash(spoke));
	float phase = fract(r * 1.6 - t * (2.0 + hash(spoke + 7.0) * 2.0) + hash(spoke + 3.0));
	float streak = on * smoothstep(0.0, 0.25, phase) * smoothstep(0.7, 0.3, phase);
	float width = 1.0 - smoothstep(0.0, 0.14, abs(fract(a * 90.0) - 0.5));
	float mask = smoothstep(0.30, 0.65, r);
	COLOR = vec4(1.0, 1.0, 1.0, streak * width * mask * amount * 0.28);
}
