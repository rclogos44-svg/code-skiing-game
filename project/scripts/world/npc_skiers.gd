extends Node3D
## Other skiers on the pistes: low-poly figures (one MultiMesh) carving S-turns down the marked
## runs at their own pace, leaning into each turn.  Purely visual - they never collide.

const COUNT := 18
const JACKETS := [Color(0.9, 0.2, 0.15), Color(0.15, 0.45, 0.9), Color(0.95, 0.75, 0.1), Color(0.2, 0.65, 0.35),
	Color(0.55, 0.25, 0.75), Color(0.95, 0.45, 0.1), Color(0.1, 0.12, 0.16), Color(0.92, 0.92, 0.95), Color(0.0, 0.6, 0.65)]

var terrain: TerrainData
var _paths: Array = []        # {pts: PackedVector2Array, cum: PackedFloat32Array, len, width}
var _npcs: Array = []         # {path, s, speed, amp, wave, phase}
var _mm: MultiMesh


func setup(td: TerrainData, shader_mat: Material) -> void:
	terrain = td
	for p in td.layout.get("pistes", []):
		var pts := PackedVector2Array()
		for q in p["pts"]:
			pts.append(Vector2(q[0], q[1]))
		var cum := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
		_paths.append({"pts": pts, "cum": cum, "len": cum[cum.size() - 1], "width": float(p["width"]),
			"diff": String(p["difficulty"])})
	if _paths.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = _skier_mesh()
	_mm.instance_count = COUNT
	for i in COUNT:
		var pi := i % _paths.size()
		var path: Dictionary = _paths[pi]
		var fast := {"green": 0.7, "blue": 0.9, "red": 1.05, "black": 1.15}.get(path["diff"], 1.0) as float
		_npcs.append({"path": pi, "s": rng.randf() * float(path["len"]), "speed": rng.randf_range(6.0, 11.0) * fast,
			"amp": float(path["width"]) * rng.randf_range(0.18, 0.32), "wave": rng.randf_range(24.0, 40.0),
			"phase": rng.randf() * TAU, "lean": 0.0})
		_mm.set_instance_custom_data(i, JACKETS[rng.randi() % JACKETS.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = shader_mat
	mmi.custom_aabb = AABB(Vector3(-1, -1, -1) * 1e5, Vector3.ONE * 2e5)
	add_child(mmi)


func _sample(path: Dictionary, s: float) -> Array:
	var pts: PackedVector2Array = path["pts"]
	var cum: PackedFloat32Array = path["cum"]
	var i := clampi(cum.bsearch(s, true) - 1, 0, pts.size() - 2)
	var t := (s - cum[i]) / maxf(cum[i + 1] - cum[i], 0.001)
	return [pts[i].lerp(pts[i + 1], t), (pts[i + 1] - pts[i]).normalized()]


func _process(delta: float) -> void:
	if _mm == null:
		return
	var dt := minf(delta, 0.1)
	for i in _npcs.size():
		var n: Dictionary = _npcs[i]
		var path: Dictionary = _paths[n["path"]]
		var s: float = n["s"] + n["speed"] * dt
		if s > float(path["len"]) - 2.0:
			s = 0.0                     # back up the lift for another run
		n["s"] = s
		var smp := _sample(path, s)
		var c: Vector2 = smp[0]
		var tan: Vector2 = smp[1]
		var nrm := Vector2(-tan.y, tan.x)
		var k := TAU / float(n["wave"])
		var arg := s * k + float(n["phase"])
		var amp: float = n["amp"]
		var pos2 := c + nrm * (amp * sin(arg))
		var dir2 := (tan + nrm * (amp * k * cos(arg))).normalized()
		# lean into the turn: lateral acceleration of the S-curve
		var lat := -amp * k * k * sin(arg) * float(n["speed"]) * float(n["speed"])
		n["lean"] = lerpf(float(n["lean"]), clampf(atan2(lat, 9.81), -0.8, 0.8), 1.0 - exp(-6.0 * dt))
		var y := terrain.height(pos2.x, pos2.y)
		var fwd := Vector3(dir2.x, 0.0, dir2.y)
		var b := Basis.looking_at(fwd, Vector3.UP) * Basis(Vector3(0, 0, 1), -float(n["lean"]))
		_mm.set_instance_transform(i, Transform3D(b, Vector3(pos2.x, y, pos2.y)))


## A skier in a relaxed athletic stance (origin between the boots on the snow, facing -Z).
## Vertex alpha 0 marks the jacket (per-instance colour).
func _skier_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pants := Color(0.16, 0.18, 0.24)
	var jacket := Color(1, 1, 1, 0)
	var dark := Color(0.1, 0.1, 0.12)
	var helmet := Color(0.9, 0.91, 0.93)
	var ski := Color(0.85, 0.85, 0.88)
	for x in [-0.12, 0.12]:
		_cbox(st, Vector3(x - 0.045, 0.0, -0.95), Vector3(x + 0.045, 0.03, 0.8), ski)
		_cbox(st, Vector3(x - 0.07, 0.03, -0.16), Vector3(x + 0.07, 0.24, 0.14), dark)       # boot
		_cbox(st, Vector3(x - 0.065, 0.24, -0.2), Vector3(x + 0.065, 0.6, -0.04), pants)     # shin (forward)
		_cbox(st, Vector3(x - 0.08, 0.58, -0.16), Vector3(x + 0.08, 0.98, 0.06), pants)      # thigh
	_cbox(st, Vector3(-0.2, 0.92, -0.22), Vector3(0.2, 1.48, 0.08), jacket)                   # torso (leaning)
	for x in [-0.27, 0.27]:
		_cbox(st, Vector3(x - 0.055, 1.0, -0.42), Vector3(x + 0.055, 1.38, -0.18), jacket)    # arms forward
		_cbox(st, Vector3(x - 0.012, 0.08, -0.5), Vector3(x + 0.012, 1.02, -0.46), dark)      # pole
	_cbox(st, Vector3(-0.115, 1.5, -0.24), Vector3(0.115, 1.74, 0.0), helmet)
	_cbox(st, Vector3(-0.1, 1.56, -0.26), Vector3(0.1, 1.62, -0.23), Color(1.0, 0.55, 0.15))
	st.generate_normals()
	return st.commit()


func _cbox(st: SurfaceTool, a: Vector3, b: Vector3, c: Color) -> void:
	st.set_color(c)
	SkierModel._box(st, a, b)
