class_name Atmosphere
extends Node3D
## Sky, sun, fog / aerial perspective, ambient light, tonemapping and the quality settings
## that belong to them (shadows, SSAO, glow, volumetrics).

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
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
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
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	env.glow_intensity = 0.35
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
	if section == "graphics":
		apply_settings()


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
	env.fog_density = [0.00016, 0.00011, 0.000085, 0.00007][clampi(vd, 0, 3)]
	if terrain_renderer:
		terrain_renderer.set_lod_scale([0.97, 1.0, 1.12, 1.35][clampi(detail, 0, 3)])
		terrain_renderer.material.set_shader_parameter("shadow_fade_start", dist * 0.55)
		terrain_renderer.material.set_shader_parameter("shadow_fade_end", dist * 0.95)
