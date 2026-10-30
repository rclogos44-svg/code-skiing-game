class_name TerrainRenderer
extends Node3D
## CDLOD terrain: a quadtree of LOD nodes is selected on the CPU every time the camera moves;
## every selected quarter-node is one instance of a shared 16x16 grid patch inside a single
## MultiMesh.  The vertex shader displaces the grid from the heightmap and geomorphs vertices
## between LOD levels, so there are no cracks or popping.  Must stay at the world origin.

const PATCH_QUADS := 16
const LEVELS := 10
const LEAF_NODE := 64.0                      # node size at level 0 (=> 2 m vertex spacing)
const ROOT_SIZE := LEAF_NODE * 512.0         # 32768 m
const MAX_PATCHES := 4096
const STRIDE := 16                           # 12 transform floats + 4 custom floats

var terrain: TerrainData
var material: ShaderMaterial
var lod_scale := 1.0
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _buf := PackedFloat32Array()
var _count := 0
var _ranges := PackedFloat32Array()
var _morph := PackedVector2Array()
var _last_cam := Vector3(INF, INF, INF)
var _root_origin := Vector2.ZERO
var lod_camera: Node3D = null              # what drives LOD (usually the active Camera3D)


func setup(td: TerrainData) -> void:
	terrain = td
	_root_origin = Vector2(td.world * 0.5 - ROOT_SIZE * 0.5, td.world * 0.5 - ROOT_SIZE * 0.5)
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	_create_textures()
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = _build_patch_mesh()
	_mm.instance_count = MAX_PATCHES
	_mm.visible_instance_count = 0
	_buf.resize(MAX_PATCHES * STRIDE)
	_buf.fill(0.0)
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "TerrainMesh"
	_mmi.multimesh = _mm
	_mmi.material_override = material
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_mmi.custom_aabb = AABB(Vector3(-20000, -1000, -20000), Vector3(46000, 8000, 46000))
	_mmi.extra_cull_margin = 16384.0
	add_child(_mmi)
	set_lod_scale(1.0)


func set_lod_scale(s: float) -> void:
	lod_scale = s
	_ranges.resize(LEVELS)
	_morph.resize(LEVELS)
	# crack-free geomorphing needs range >= 2.36 x node size (151 m at level 0)
	var base := 155.0 * maxf(s, 1.0)
	for l in LEVELS:
		_ranges[l] = base * pow(2.0, l)
	var morph_arr: Array = []
	for l in LEVELS:
		var prev := 0.0 if l == 0 else _ranges[l - 1]
		var start := prev + (_ranges[l] - prev) * 0.6
		var end := _ranges[l] * 0.97
		_morph[l] = Vector2(start, end)
		morph_arr.append(Vector2(start, end))
	if material:
		material.set_shader_parameter("morph_ranges", PackedVector2Array(morph_arr))
	_last_cam = Vector3(INF, INF, INF)


func _create_textures() -> void:
	# heights are 16-bit values packed into RG8 texels (portable: no float textures needed, e.g. WebGL)
	var img := Image.create_from_data(terrain.n, terrain.n, false, Image.FORMAT_RG8, terrain.heights)
	var far := Image.create_from_data(terrain.far_n, terrain.far_n, false, Image.FORMAT_RG8, terrain.far_heights)
	var core_tex := ImageTexture.create_from_image(img)
	material.set_shader_parameter("height_core", core_tex)
	material.set_shader_parameter("height_far", ImageTexture.create_from_image(far))
	if OS.has_feature("web") or Game.test_mode != "":
		var back := core_tex.get_image()
		var px := back.get_pixel(1536, 1536) if back else Color()
		var gpu_h := (roundf(px.r * 255.0) * 256.0 + roundf(px.g * 255.0)) * terrain.h_scale + terrain.h_min
		print("[terrain] height texture %dx%d format %d, decoded(1536,1536)=%.2f cpu=%.2f" % [core_tex.get_width(), core_tex.get_height(),
			back.get_format() if back else -1, gpu_h, terrain.core_sample(1536 * terrain.n + 1536)])
	material.set_shader_parameter("core_min", terrain.h_min)
	material.set_shader_parameter("core_scale", terrain.h_scale)
	material.set_shader_parameter("far_min", terrain.far_min)
	material.set_shader_parameter("far_scale", terrain.far_scale)
	material.set_shader_parameter("core_n", terrain.n)
	material.set_shader_parameter("core_spacing", terrain.sp)
	material.set_shader_parameter("world_size", terrain.world)
	material.set_shader_parameter("far_n", terrain.far_n)
	material.set_shader_parameter("far_spacing", terrain.far_sp)
	material.set_shader_parameter("far_origin", terrain.far_origin)
	material.set_shader_parameter("normal_core", load("res://world/normal.png"))
	material.set_shader_parameter("surface_tex", load("res://world/surface.png"))
	material.set_shader_parameter("bake_tex", load("res://world/bake.png"))
	material.set_shader_parameter("far_bake_tex", load("res://world/far_bake.png"))
	material.set_shader_parameter("snow_normal", load("res://assets/textures/snow_normal.png"))
	material.set_shader_parameter("rock_albedo", load("res://assets/textures/rock_albedo.png"))
	material.set_shader_parameter("rock_normal", load("res://assets/textures/rock_normal.png"))
	material.set_shader_parameter("noise_tex", load("res://assets/textures/noise.png"))


func _build_patch_mesh() -> ArrayMesh:
	var q := PATCH_QUADS
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for z in q + 1:
		for x in q + 1:
			verts.append(Vector3(float(x) / q, 0.0, float(z) / q))
	for z in q:
		for x in q:
			var i := z * (q + 1) + x
			# alternate the diagonal for a more isotropic triangulation
			if (x + z) % 2 == 0:
				idx.append_array([i, i + 1, i + q + 2, i, i + q + 2, i + q + 1])
			else:
				idx.append_array([i, i + 1, i + q + 1, i + 1, i + q + 2, i + q + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.custom_aabb = AABB(Vector3(-20000, -1000, -20000), Vector3(46000, 8000, 46000))
	return m


func _process(_delta: float) -> void:
	if terrain == null:
		return
	var cam: Node3D = lod_camera
	if cam == null or not is_instance_valid(cam):
		cam = get_viewport().get_camera_3d()
	if cam == null:
		return
	update_lod(cam.global_position)


func update_lod(cam_pos: Vector3, force := false) -> void:
	if not force and cam_pos.distance_squared_to(_last_cam) < 0.25:
		return
	_last_cam = cam_pos
	_count = 0
	_select(_root_origin.x, _root_origin.y, ROOT_SIZE, LEVELS - 1, Vector2(cam_pos.x, cam_pos.z))
	_mm.buffer = _buf
	_mm.visible_instance_count = _count
	material.set_shader_parameter("lod_cam", cam_pos)


func patch_count() -> int:
	return _count


func _dist_rect(x: float, z: float, size: float, c: Vector2) -> float:
	var dx := maxf(maxf(x - c.x, c.x - (x + size)), 0.0)
	var dz := maxf(maxf(z - c.y, c.y - (z + size)), 0.0)
	return sqrt(dx * dx + dz * dz)


func _select(x: float, z: float, size: float, level: int, c: Vector2) -> bool:
	var d := _dist_rect(x, z, size, c)
	if d > _ranges[level]:
		return false
	if level == 0:
		_add_node(x, z, size, 0)
		return true
	if d > _ranges[level - 1]:
		_add_node(x, z, size, level)
		return true
	var h := size * 0.5
	for qz in 2:
		for qx in 2:
			var cx := x + qx * h
			var cz := z + qz * h
			if not _select(cx, cz, h, level - 1, c):
				_add_patch(cx, cz, h, level)
	return true


func _add_node(x: float, z: float, size: float, level: int) -> void:
	var h := size * 0.5
	_add_patch(x, z, h, level)
	_add_patch(x + h, z, h, level)
	_add_patch(x, z + h, h, level)
	_add_patch(x + h, z + h, h, level)


func _add_patch(x: float, z: float, size: float, level: int) -> void:
	if _count >= MAX_PATCHES:
		return
	var o := _count * STRIDE
	# identity basis, zero origin (vertices are generated in world space by the shader)
	_buf[o + 0] = 1.0
	_buf[o + 1] = 0.0
	_buf[o + 2] = 0.0
	_buf[o + 3] = 0.0
	_buf[o + 4] = 0.0
	_buf[o + 5] = 1.0
	_buf[o + 6] = 0.0
	_buf[o + 7] = 0.0
	_buf[o + 8] = 0.0
	_buf[o + 9] = 0.0
	_buf[o + 10] = 1.0
	_buf[o + 11] = 0.0
	_buf[o + 12] = x
	_buf[o + 13] = z
	_buf[o + 14] = size
	_buf[o + 15] = float(level)
	_count += 1
