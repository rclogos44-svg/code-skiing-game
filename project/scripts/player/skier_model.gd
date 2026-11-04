class_name SkierModel
extends RefCounted
## Procedural meshes for the skier (no external modelling tools).  All limb meshes are built
## along +Y from the joint (y = 0) to the child joint (y = length).

const SEGS := 14


static func mat(color: Color, rough := 0.7, metal := 0.0, extra := {}) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if extra.has("rim"):
		m.rim_enabled = true
		m.rim = extra["rim"]
		m.rim_tint = 0.4
	if extra.has("clearcoat"):
		m.clearcoat_enabled = true
		m.clearcoat = extra["clearcoat"]
		m.clearcoat_roughness = 0.2
	return m


## Revolves a profile of Vector2(radius, y) around Y.  sx/sz scale the cross-section (ellipse).
static func lathe(profile: Array, sx := 1.0, sz := 1.0, segs := SEGS, z_bulge := 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := profile.size()
	for i in rings:
		var r: float = profile[i].x
		var y: float = profile[i].y
		for s in segs + 1:
			var a := TAU * float(s) / segs
			var cx := cos(a) * r * sx
			var cz := sin(a) * r * sz
			if z_bulge != 0.0 and cz < 0.0:
				cz *= 1.0 + z_bulge
			st.set_uv(Vector2(float(s) / segs, float(i) / (rings - 1)))
			st.add_vertex(Vector3(cx, y, cz))
	for i in rings - 1:
		for s in segs:
			var a := i * (segs + 1) + s
			var b := a + segs + 1
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(b + 1)
			st.add_index(b)
	st.generate_normals()
	return st.commit()


static func capsule_profile(r0: float, r1: float, length: float, caps := 4, mid := []) -> Array:
	var pts := []
	for i in caps + 1:
		var a := -PI * 0.5 + PI * 0.5 * float(i) / caps
		pts.append(Vector2(r0 * cos(a), r0 * sin(a)))
	for m in mid:
		pts.append(m)
	for i in caps + 1:
		var a := PI * 0.5 * float(i) / caps
		pts.append(Vector2(r1 * cos(a), length + r1 * sin(a)))
	return pts


static func limb(r0: float, r1: float, length: float, sx := 1.0, sz := 1.0) -> ArrayMesh:
	var mid := [Vector2(lerpf(r0, r1, 0.3) * 1.04, length * 0.3), Vector2(lerpf(r0, r1, 0.7) * 1.02, length * 0.7)]
	return lathe(capsule_profile(r0, r1, length, 4, mid), sx, sz)


static func sphere(r: float, sx := 1.0, sy := 1.0, sz := 1.0, rings := 8) -> ArrayMesh:
	var pts := []
	for i in rings + 1:
		var a := -PI * 0.5 + PI * float(i) / rings
		pts.append(Vector2(r * cos(a), r * sin(a) * sy))
	return lathe(pts, sx, sz)


static func torso() -> ArrayMesh:
	# waist (y=0) to neck base (y=0.52); wider at the chest, jacket hem flare at bottom
	var pts := [
		Vector2(0.0, -0.06), Vector2(0.13, -0.055), Vector2(0.165, -0.02), Vector2(0.173, 0.06),
		Vector2(0.17, 0.12), Vector2(0.18, 0.15), Vector2(0.17, 0.18), Vector2(0.178, 0.30), Vector2(0.182, 0.40), Vector2(0.165, 0.47),
		Vector2(0.11, 0.515), Vector2(0.075, 0.535), Vector2(0.0, 0.54),
	]
	return lathe(pts, 1.18, 0.72, 18)


static func pelvis() -> ArrayMesh:
	var pts := [Vector2(0.0, -0.10), Vector2(0.10, -0.095), Vector2(0.155, -0.04), Vector2(0.165, 0.04),
		Vector2(0.15, 0.10), Vector2(0.0, 0.11)]
	return lathe(pts, 1.12, 0.78, 16)


static func helmet() -> ArrayMesh:
	var pts := []
	for i in 9:
		var a := -0.35 + (PI * 0.5 + 0.35) * float(i) / 8.0
		pts.append(Vector2(0.128 * cos(a), 0.128 * sin(a) * 1.05))
	pts.insert(0, Vector2(0.118, -0.07))
	return lathe(pts, 0.95, 1.08, 20, 0.05)


static func goggles() -> Array:
	# strap band + curved lens in front (-Z is forward)
	var band := SurfaceTool.new()
	band.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lens := SurfaceTool.new()
	lens.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 24
	for s in segs:
		var a0 := TAU * float(s) / segs
		var a1 := TAU * float(s + 1) / segs
		var r := 0.135
		var front0 := -sin(a0) > 0.55
		var front1 := -sin(a1) > 0.55
		var st := lens if (front0 and front1) else band
		var h0 := -0.012 if not (front0 and front1) else -0.035
		var h1 := 0.022 if not (front0 and front1) else 0.032
		var rr := r + (0.012 if (front0 and front1) else 0.0)
		var p00 := Vector3(cos(a0) * rr * 0.95, h0, sin(a0) * rr * 1.1)
		var p10 := Vector3(cos(a1) * rr * 0.95, h0, sin(a1) * rr * 1.1)
		var p01 := Vector3(cos(a0) * rr * 0.95, h1, sin(a0) * rr * 1.1)
		var p11 := Vector3(cos(a1) * rr * 0.95, h1, sin(a1) * rr * 1.1)
		st.add_vertex(p00)
		st.add_vertex(p01)
		st.add_vertex(p10)
		st.add_vertex(p10)
		st.add_vertex(p01)
		st.add_vertex(p11)
	band.generate_normals()
	lens.generate_normals()
	return [band.commit(), lens.commit()]


static func boot() -> ArrayMesh:
	# shell around the ankle joint (origin), sole at y=-0.10, toe toward -Z
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := 0.058
	var parts := [
		[Vector3(-hw, -0.10, -0.19), Vector3(hw, -0.02, 0.13)],     # foot shell
		[Vector3(-hw * 1.05, -0.06, -0.07), Vector3(hw * 1.05, 0.17, 0.10)],  # cuff
	]
	for p in parts:
		_box(st, p[0], p[1])
	st.generate_normals()
	return st.commit()


static func _box(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var v := [
		Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z), Vector3(a.x, b.y, a.z),
		Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z),
	]
	var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]
	for f in faces:
		st.add_vertex(v[f[0]])
		st.add_vertex(v[f[1]])
		st.add_vertex(v[f[2]])
		st.add_vertex(v[f[0]])
		st.add_vertex(v[f[2]])
		st.add_vertex(v[f[3]])


## Ski centred at origin, running along Z (tip at -Z), top surface at y = 0.018.
static func ski() -> Array:
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := 1.76
	var steps := 40
	var thick := 0.018
	var pts_l := []
	var pts_r := []
	var ys := []
	for i in steps + 1:
		var t := float(i) / steps            # 0 = tail, 1 = tip
		var z := lerpf(length * 0.45, -length * 0.55, t)
		var w := 0.052 - 0.012 * sin(t * PI)  # sidecut
		var y := 0.0
		if t > 0.88:
			var k := (t - 0.88) / 0.12
			y = 0.075 * k * k
			w *= 1.0 - 0.45 * k * k
		elif t < 0.06:
			var k2 := (0.06 - t) / 0.06
			y = 0.025 * k2 * k2
		pts_l.append(Vector3(-w, y, z))
		pts_r.append(Vector3(w, y, z))
		ys.append(y)
	for i in steps:
		var a0: Vector3 = pts_l[i]
		var b0: Vector3 = pts_r[i]
		var a1: Vector3 = pts_l[i + 1]
		var b1: Vector3 = pts_r[i + 1]
		var up := Vector3(0, thick, 0)
		# top
		top.add_vertex(a0 + up)
		top.add_vertex(a1 + up)
		top.add_vertex(b0 + up)
		top.add_vertex(b0 + up)
		top.add_vertex(a1 + up)
		top.add_vertex(b1 + up)
		# bottom
		top.add_vertex(a0)
		top.add_vertex(b0)
		top.add_vertex(a1)
		top.add_vertex(b0)
		top.add_vertex(b1)
		top.add_vertex(a1)
		# sides
		for pair in [[a0, a1], [b1, b0]]:
			var p0: Vector3 = pair[0]
			var p1: Vector3 = pair[1]
			top.add_vertex(p0)
			top.add_vertex(p1)
			top.add_vertex(p0 + up)
			top.add_vertex(p0 + up)
			top.add_vertex(p1)
			top.add_vertex(p1 + up)
	top.generate_normals()
	# binding plate + toe/heel pieces
	var bind := SurfaceTool.new()
	bind.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(bind, Vector3(-0.035, thick, -0.24), Vector3(0.035, thick + 0.03, 0.20))
	_box(bind, Vector3(-0.04, thick, -0.28), Vector3(0.04, thick + 0.055, -0.22))
	_box(bind, Vector3(-0.04, thick, 0.16), Vector3(0.04, thick + 0.06, 0.24))
	bind.generate_normals()
	return [top.commit(), bind.commit()]


static func pole() -> Array:
	# along +Y from grip (0) to tip (1.18)
	var shaft := lathe([Vector2(0.0, 0.0), Vector2(0.0095, 0.0), Vector2(0.0095, 1.10), Vector2(0.006, 1.17), Vector2(0.0, 1.19)], 1.0, 1.0, 8)
	var grip := lathe(capsule_profile(0.019, 0.017, 0.13, 2), 1.0, 1.0, 10)
	var basket := lathe([Vector2(0.0, 1.06), Vector2(0.05, 1.075), Vector2(0.052, 1.085), Vector2(0.0, 1.09)], 1.0, 1.0, 12)
	return [shaft, grip, basket]


static func clothing(r0: float, r1: float, length: float) -> ArrayMesh:
	# Fabric gathers at elbows/knees and the cuff, rather than smooth capsule limbs.
	var mid := []
	for i in range(1, 10):
		var t := float(i) / 10.0
		var gather := 1.0 + 0.075 * sin(t * TAU * 3.5) * smoothstep(0.2, 0.9, t)
		mid.append(Vector2(lerpf(r0, r1, t) * gather, length * t))
	return lathe(capsule_profile(r0, r1, length, 4, mid), 1.0, 0.95, 18)
