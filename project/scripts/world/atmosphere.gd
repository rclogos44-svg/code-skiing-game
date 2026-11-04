class_name Atmosphere
extends Node3D
## Sky, sun, fog / aerial perspective, ambient light, tonemapping and the quality settings
## that belong to them (shadows, SSAO, glow, volumetrics).  Time of day and weather (Settings >
## Graphics) change light colour, sky, clouds and fog; the sun keeps its direction because the
## terrain's long-distance shadows are baked for it.

## time of day: sun colour, sun energy, zenith, horizon, fog colour, ambient energy
const TIMES := {
	"morning": [Color(1.0, 0.88, 0.76), 1.3, Color(0.17, 0.35, 0.70), Color(0.86, 0.82, 0.82), Color(0.80, 0.80, 0.86), 0.9],
	"day": [Color(1.0, 0.965, 0.91), 1.55, Color(0.13, 0.32, 0.68), Color(0.60, 0.74, 0.90), Color(0.66, 0.76, 0.90), 1.0],
	"golden": [Color(1.0, 0.70, 0.42), 1.35, Color(0.18, 0.28, 0.56), Color(1.0, 0.72, 0.52), Color(0.95, 0.76, 0.62), 0.85],
	"dusk": [Color(1.0, 0.58, 0.42), 0.5, Color(0.07, 0.09, 0.22), Color(0.52, 0.46, 0.62), Color(0.40, 0.42, 0.58), 0.55],
}
## weather: cloud cover, sun multiplier, fog density multiplier, height-fog density, grey-out of the sky
const WEATHER := {
	"clear": [0.12, 1.0, 0.8, 0.0008, 0.0],
	"snowing": [0.42, 1.0, 1.0, 0.0008, 0.0],
	"storm": [0.97, 0.35, 7.0, 0.002, 0.75],
	"fog": [0.3, 0.9, 1.2, 0.03, 0.15],
}

var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var terrain_renderer: TerrainRenderer


func setup(td: TerrainData) -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("cloud_noise", load("res://assets/textures/noise.png"))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR if RenderingServer.get_current_rendering_method() == "gl_compatibility" else Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.92
	env.tonemap_white = 8.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.66, 0.76, 0.9)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.12
	env.fog_density = 0.000085
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.0
	env.fog_height = 900.0
	env.fog_height_density = 0.0008
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.025
	env.adjustment_saturation = 1.02
	env.glow_intensity = 0.22
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.4
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	var to_sun := td.sun_dir
	sun.transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD), Vector3.ZERO)
	sun.light_color = Color(1.0, 0.965, 0.91)
	sun.light_energy = 1.55
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	add_child(sun)
	apply_settings()
	Settings.changed.connect(_on_settings)


func _on_settings(section: String, _key: String) -> void:
	if section == "graphics" or section == "world":
		apply_settings()


func _apply_conditions(fog_base: float) -> void:
	var t: Array = TIMES.get(String(Settings.get_value("world", "time_of_day")), TIMES["day"])
	var w: Array = WEATHER.get(String(Settings.get_value("world", "weather")), WEATHER["snowing"])
	var grey := Color(0.62, 0.66, 0.72)
	sun.light_color = t[0]
	sun.light_energy = float(t[1]) * float(w[1])
	sky_mat.set_shader_parameter("zenith_color", (t[2] as Color).lerp(grey * 0.9, w[4]))
	sky_mat.set_shader_parameter("horizon_color", (t[3] as Color).lerp(grey, w[4]))
	sky_mat.set_shader_parameter("cloud_coverage", w[0])
	env.fog_light_color = (t[4] as Color).lerp(Color(0.78, 0.8, 0.84), w[4])
	env.fog_density = fog_base * float(w[2])
	env.fog_height_density = w[3]
	# valley fog sits in the low valleys; otherwise a thin haze high up
	env.fog_height = 650.0 if Settings.get_value("world", "weather") == "fog" else 900.0
	env.ambient_light_energy = float(t[5]) * 0.45
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		sun.light_energy *= 0.30
		env.ambient_light_energy *= 0.45


func apply_settings() -> void:
	var sh := int(Settings.get_value("graphics", "shadows"))
	sun.shadow_enabled = sh > 0
	var dist: float = [120.0, 180.0, 300.0, 450.0, 650.0][clampi(sh, 0, 4)]
	sun.directional_shadow_max_distance = dist
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if sh <= 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.06 if sh > 2 else 0.15
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	env.ssao_enabled = bool(Settings.get_value("graphics", "ssao"))
	env.glow_enabled = bool(Settings.get_value("graphics", "glow"))
	var detail := int(Settings.get_value("graphics", "detail"))
	env.ssil_enabled = detail >= 3
	env.ssil_intensity = 0.6
	env.sdfgi_enabled = false
	var vd := int(Settings.get_value("graphics", "view_distance"))
	_apply_conditions([0.00016, 0.00011, 0.000085, 0.00007][clampi(vd, 0, 3)])
	if terrain_renderer:
		terrain_renderer.set_lod_scale([0.97, 1.0, 1.12, 1.35][clampi(detail, 0, 3)])
		terrain_renderer.material.set_shader_parameter("shadow_fade_start", dist * 0.55)
		terrain_renderer.material.set_shader_parameter("shadow_fade_end", dist * 0.95)
