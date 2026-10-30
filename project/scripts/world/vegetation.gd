class_name Vegetation
extends Node3D
## Snowy pine forests and rocks: procedural meshes, instanced per 256 m chunk with MultiMesh
## and distance-based LOD (visibility ranges).  Also feeds the obstacle grid for collisions.

const CHUNK := 256.0

var terrain: TerrainData
var obstacles: Obstacles
var tree_near: Array[Mesh] = []
var tree_mid: Mesh
var tree_far: Mesh
var rock_meshes: Array[Mesh] = []
var tree_mat: StandardMaterial3D
var rock_mat: ShaderMaterial
var _near_nodes: Array[MultiMeshInstance3D] = []
var _mid_nodes: Array[MultiMeshInstance3D] = []
var _far_nodes: Array[MultiMeshInstance3D] = []
var _rock_nodes: Array[MultiMeshInstance3D] = []
var tree_count := 0
var rock_count := 0


func setup(td: TerrainData, obs: Obstacles) -> void:
	terrain = td
	obstacles = obs
	tree_mat = StandardMaterial3D.new()
	tree_mat.vertex_color_use_as_albedo = true
	tree_mat.roughness = 0.88
	tree_mat.albedo_texture = null
	tree_mat.rim_enabled = true
	tree_mat.rim = 0.15
	for v in 3:
		tree_near.append(_pine_mesh(v, true))
	tree_mid = _pine_mesh(1, false, 4, 7)
	tree_far = _pine_mesh(0, false)
	rock_mat = ShaderMaterial.new()
	rock_mat.shader = load("res://shaders/rock.gdshader")
	rock_mat.set_shader_parameter("rock_albedo", load("res://assets/textures/rock_albedo.png"))
	rock_mat.set_shader_parameter("rock_normal", load("res://assets/textures/rock_normal.png"))
	for v in 4:
		rock_meshes.append(_rock_mesh(v))
	_load_trees()
	_load_rocks()
	apply_settings()
	Settings.changed.connect(_on_settings)


func _on_settings(section: String, _key: String) -> void:
	if section == "graphics":
		apply_settings()


func apply_settings() -> void:
	var detail := int(Settings.get_value("graphics", "detail"))
	var near_end: float = [110.0, 150.0, 200.0, 280.0][clampi(detail, 0, 3)]
	var mid_end: float = [320.0, 420.0, 560.0, 750.0][clampi(detail, 0, 3)]
	var far_end: float = [1100.0, 1600.0, 2200.0, 3000.0][clampi(detail, 0, 3)]
	var shadows := int(Settings.get_value("graphics", "shadows")) > 1
	for n in _near_nodes:
		n.visibility_range_end = near_end
		n.visibility_range_end_margin = 30.0
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for n in _mid_nodes:
		n.visibility_range_begin = near_end - 20.0
		n.visibility_range_begin_margin = 30.0
		n.visibility_range_end = mid_end
		n.visibility_range_end_margin = 60.0
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for n in _far_nodes:
		n.visibility_range_begin = mid_end - 40.0
		n.visibility_range_begin_margin = 60.0
		n.visibility_range_end = far_end
		n.visibility_range_end_margin = 200.0
	for n in _rock_nodes:
		n.visibility_range_end = far_end * 0.8
		n.visibility_range_end_margin = 100.0


# ------------------------------------------------------------------ data
func _read_bin(path: String) -> PackedFloat32Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Vegetation: missing " + path)
		return PackedFloat32Array()
	return f.get_buffer(f.get_length()).to_float32_array()


func _load_trees() -> void:
	var data := _read_bin("res://world/trees.bin")
	var count := data.size() / 4
	tree_count = count
	var chunks := {}
	var nchunk := int(ceil(terrain.world / CHUNK))
	for i in count:
		var x := data[i * 4]
		var z := data[i * 4 + 1]
		var s := data[i * 4 + 2]
		var r := data[i * 4 + 3]
		var key := clampi(int(z / CHUNK), 0, nchunk - 1) * nchunk + clampi(int(x / CHUNK), 0, nchunk - 1)
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(i)
		var y := terrain.height(x, z)
		obstacles.add(x, z, 1.5 * s, y - 0.5, y + 11.0 * s, Obstacles.Kind.TREE)
	for key in chunks:
		var ids: Array = chunks[key]
		var cx := (int(key) % nchunk + 0.5) * CHUNK
		var cz := (int(key) / nchunk + 0.5) * CHUNK
		var center := Vector3(cx, terrain.height(cx, cz), cz)
		var all: Array[Transform3D] = []
		for i in ids:
			all.append(_tree_xform(data, i, center))
		# near LOD: split across the 3 variants
		for v in 3:
			var xf: Array[Transform3D] = []
			for k in all.size():
				if k % 3 == v:
					xf.append(all[k])
			if xf.is_empty():
				continue
			var mmi := _make_mmi(tree_near[v], xf, tree_mat, center)
			_near_nodes.append(mmi)
		_mid_nodes.append(_make_mmi(tree_mid, all, tree_mat, center))
		var far := _make_mmi(tree_far, all, tree_mat, center)
		far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_far_nodes.append(far)


func _tree_xform(arr: PackedFloat32Array, i: int, center: Vector3) -> Transform3D:
	var x := arr[i * 4]
	var z := arr[i * 4 + 1]
	var s := arr[i * 4 + 2]
	var r := arr[i * 4 + 3]
	var y := terrain.height(x, z) - 0.4
	var b := Basis(Vector3.UP, r).scaled(Vector3(s, s * randf_range(0.9, 1.12), s))
	return Transform3D(b, Vector3(x, y, z) - center)


func _load_rocks() -> void:
	var data := _read_bin("res://world/rocks.bin")
	var count := data.size() / 4
	rock_count = count
	var nchunk := int(ceil(terrain.world / CHUNK))
	var chunks := {}
	for i in count:
		var x := data[i * 4]
		var z := data[i * 4 + 1]
		var s := clampf(data[i * 4 + 2], 0.6, 9.0)
		var r := data[i * 4 + 3]
		var key := clampi(int(z / CHUNK), 0, nchunk - 1) * nchunk + clampi(int(x / CHUNK), 0, nchunk - 1)
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append([x, z, s, r])
		var y := terrain.height(x, z)
		obstacles.add(x, z, s * 0.85, y - 1.0, y + s * 0.6, Obstacles.Kind.ROCK)
	for key in chunks:
		var list: Array = chunks[key]
		var cx := (int(key) % nchunk + 0.5) * CHUNK
		var cz := (int(key) / nchunk + 0.5) * CHUNK
		var center := Vector3(cx, terrain.height(cx, cz), cz)
		for v in rock_meshes.size():
			var xf: Array[Transform3D] = []
			for k in list.size():
				if k % rock_meshes.size() != v:
					continue
				var e: Array = list[k]
				var x: float = e[0]
				var z: float = e[1]
				var s: float = e[2]
				var nrm := terrain.normal(x, z, 2.0)
				var y := terrain.height(x, z) - s * 0.35
				var b := Basis(Vector3.UP, e[3])
				# lean the rock with the slope a little
				var tilt := Vector3.UP.cross(nrm)
				if tilt.length() > 0.01:
					b = Basis(tilt.normalized(), Vector3.UP.angle_to(nrm) * 0.6) * b
				b = b.scaled(Vector3(s, s * randf_range(0.55, 0.9), s * randf_range(0.8, 1.2)))
				xf.append(Transform3D(b, Vector3(x, y, z) - center))
			if xf.is_empty():
				continue
			var mmi := _make_mmi(rock_meshes[v], xf, rock_mat, center)
			_rock_nodes.append(mmi)


func _make_mmi(mesh: Mesh, xforms: Array[Transform3D], m: Material, center: Vector3) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.position = center
	add_child(mmi)
	return mmi


# ------------------------------------------------------------------ procedural meshes
func _pine_mesh(variant: int, detailed: bool, lod_layers := 2, lod_segs := 5) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + variant * 13
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var height := 11.0 + variant * 1.2
	var trunk_col := Color(0.24, 0.17, 0.12)
	# trunk
	var ts := 7 if detailed else 0
	for i in ts:
		var a0 := TAU * i / ts
		var a1 := TAU * (i + 1) / ts
		var r0 := 0.28
		var r1 := 0.05
		var p00 := Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
		var p10 := Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
		var p01 := Vector3(cos(a0) * r1, height, sin(a0) * r1)
		var p11 := Vector3(cos(a1) * r1, height, sin(a1) * r1)
		for p in [p00, p01, p10, p10, p01, p11]:
			st.set_color(trunk_col)
			st.add_vertex(p)
	# branch layers: drooping skirts, dark green underneath, snow on top
	var layers := (7 + variant) if detailed else lod_layers
	var segs := 11 if detailed else lod_segs
	var green := Color(0.10, 0.20, 0.14)
	var green2 := Color(0.13, 0.25, 0.17)
	var snow := Color(0.93, 0.95, 0.98)
	for l in layers:
		var t := float(l) / layers
		var base_y := lerpf(1.1, height * 0.86, t)
		var r := lerpf(2.5 + variant * 0.2, 0.55, pow(t, 0.9))
		var top_y := base_y + lerpf(2.2, 1.6, t) * (1.0 if detailed else 1.35)
		var droop := -0.45 * (1.0 - t)
		var apex := Vector3(0, top_y, 0)
		var ring: Array[Vector3] = []
		for s in segs:
			var a := TAU * s / segs + rng.randf_range(-0.12, 0.12) + l * 0.7
			var rr := r * rng.randf_range(0.82, 1.12)
			ring.append(Vector3(cos(a) * rr, base_y + droop + rng.randf_range(-0.15, 0.15), sin(a) * rr))
		var mid_y := base_y + 0.05
		for s in segs:
			var a: Vector3 = ring[s]
			var b: Vector3 = ring[(s + 1) % segs]
			# jagged edge: notch between tips
			var mid := (a + b) * 0.5 * 0.72
			mid.y = mid_y + 0.25
			var snow_amt := clampf(0.55 + 0.4 * (1.0 - t) * 0.5 + rng.randf_range(-0.15, 0.15), 0.0, 1.0)
			var top_col := green2.lerp(snow, snow_amt)
			var tip_col := green.lerp(snow, snow_amt * 0.7)
			# upper surface (apex -> a -> mid -> b)
			for tri in [[apex, mid, a], [apex, b, mid]]:
				st.set_color(top_col)
				st.add_vertex(tri[0])
				st.set_color(tip_col)
				st.add_vertex(tri[1])
				st.set_color(tip_col)
				st.add_vertex(tri[2])
			# underside (dark)
			if not detailed:
				continue
			var under := Vector3(0, base_y + 0.3, 0)
			for tri in [[under, a, mid], [under, mid, b]]:
				st.set_color(green * 0.6)
				st.add_vertex(tri[0])
				st.set_color(green)
				st.add_vertex(tri[1])
				st.set_color(green)
				st.add_vertex(tri[2])
	# snowy tip
	st.generate_normals()
	return st.commit()


func _rock_mesh(variant: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = 100 + variant
	noise.frequency = 1.3
	noise.fractal_octaves = 4
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 20
	sm.rings = 12
	var arrays := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var stretch := Vector3(1.0 + variant * 0.12, 0.9, 1.0 - variant * 0.07)
	for i in verts.size():
		var v := verts[i]
		var d := 1.0 + noise.get_noise_3dv(v * 1.0) * 0.38
		# flatten facets a bit for a fractured look
		d = lerpf(d, round(d * 4.0) / 4.0, 0.35)
		verts[i] = v * d * stretch
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for k in idx.size():
		st.add_vertex(verts[idx[k]])
	st.generate_normals()
	return st.commit()
