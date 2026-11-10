// The rider's clothes and gear (meshes from build/gen_rider.py).  Vertex colour carries baked data:
//   r = sway weight of the first cloth spring, g = ambient occlusion, b = part id (0 base,
//   0.5 accent, 1 lining / liner / sole), a = sway weight of the second spring.
//   Jacket: r = sleeve ends and the bloused waist, a = the hood.  Pants: r / a = left / right leg.
// Jacket and pants read a texture atlas: R = fabric shading (x2), G = accent mask (zips, tabs),
// B = third colour (logo, belt); its normal map holds the seams, stitching, flaps and pockets.  A
// tiled twill normal adds the weave on top.  Colours are uniforms, so outfits are just parameters.
// SkierBody's cloth springs (skeleton space) swing the fabric; above walking speed it ripples.
shader_type spatial;
render_mode cull_back;

uniform bool use_atlas = false;
uniform sampler2D atlas_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D atlas_nrm : hint_normal, filter_linear_mipmap;
uniform sampler2D detail_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 main_color : source_color = vec3(0.5);
uniform vec3 accent_color : source_color = vec3(0.05);
uniform vec3 third_color : source_color = vec3(0.9);
uniform vec3 dark_color : source_color = vec3(0.04);
uniform float roughness = 0.85;
uniform float accent_roughness = 0.6;
uniform float metallic = 0.0;
uniform float accent_metallic = 0.0;
uniform float specular = 0.35;
uniform float detail_scale = 80.0;      // weave tiles per UV unit
uniform float detail_strength = 0.35;
uniform float sheen = 0.18;             // soft fabric rim light
uniform float clearcoat_amt = 0.0;
uniform vec3 sway = vec3(0.0);
uniform vec3 sway2 = vec3(0.0);
uniform float flutter = 0.0;
uniform float flutter2 = 0.0;
uniform float phase = 0.0;

void vertex() {
	float w = COLOR.r;
	float w2 = COLOR.a;
	float rip = sin(phase + VERTEX.y * 23.0 + VERTEX.x * 9.0) * 0.7 + sin(phase * 1.7 - VERTEX.y * 37.0 + VERTEX.z * 11.0) * 0.3;
	float rip2 = sin(phase * 1.9 + VERTEX.x * 31.0 - VERTEX.y * 17.0) * 0.6 + sin(phase * 2.7 + VERTEX.z * 29.0) * 0.4;
	VERTEX += sway * (w * w) + sway2 * (w2 * w2) + NORMAL * (flutter * w * rip + flutter2 * w2 * rip2);
}

void fragment() {
	float id = COLOR.b;
	float acc = (id > 0.25 && id < 0.75) ? 1.0 : 0.0;
	vec3 base = mix(main_color, accent_color, acc);
	float rough = mix(roughness, accent_roughness, acc);
	float metal = mix(metallic, accent_metallic, acc);
	vec3 n1 = vec3(0.0, 0.0, 1.0);
	if (use_atlas) {
		vec4 a = texture(atlas_tex, UV);
		base = mix(main_color, accent_color, a.g);
		base = mix(base, third_color, a.b);
		base *= a.r * 2.0;
		rough = mix(roughness, accent_roughness, a.g);
		n1 = texture(atlas_nrm, UV).rgb * 2.0 - 1.0;
	}
	if (id > 0.75) {
		base = dark_color;
		rough = 0.9;
		metal = 0.0;
	}
	vec3 n2 = texture(detail_nrm, UV * detail_scale).rgb * 2.0 - 1.0;
	n2.xy *= detail_strength;
	vec3 n = normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
	float ao = COLOR.g;
	ALBEDO = base * mix(1.0, ao, 0.55);
	AO = ao;
	AO_LIGHT_AFFECT = 0.3;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = specular;
	NORMAL_MAP = n * 0.5 + 0.5;
	RIM = sheen;
	RIM_TINT = 0.6;
	CLEARCOAT = clearcoat_amt;
	CLEARCOAT_ROUGHNESS = 0.15;
}
