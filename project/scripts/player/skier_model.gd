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


## Rings of [y, half width, front depth, back depth, z shift] swept into a closed body: the front
## (-Z) and back can bulge differently, so a chest, shoulder blades or a helmet's lower back read.
static func shell(rings: Array, segs := 22) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings.size():
		var r: Array = rings[i]
		for k in segs + 1:
			var a := TAU * float(k) / segs
			var sz := sin(a)
			var depth: float = r[2] if sz < 0.0 else r[3]
			var zs: float = r[4] if r.size() > 4 else 0.0
			st.set_uv(Vector2(float(k) / segs, float(i) / (rings.size() - 1)))
			st.add_vertex(Vector3(cos(a) * float(r[1]), float(r[0]), sz * depth + zs))
	for i in rings.size() - 1:
		for k in segs:
			var a0 := i * (segs + 1) + k
			var b0 := a0 + segs + 1
			for idx in [a0, a0 + 1, b0, a0 + 1, b0 + 1, b0]:
				st.add_index(idx)
	st.generate_normals()
	return st.commit()


static func torso() -> ArrayMesh:
	# waist (y=0) to neck base (y=0.54): a long baggy jacket, hem at mid-thigh, broad shoulders,
	# a chest in front and a rounded upper back (shoulder joints sit at y=0.43, x=+-0.185)
	return shell([
		[-0.31, 0.0, 0.0, 0.0], [-0.305, 0.2, 0.15, 0.16], [-0.27, 0.218, 0.158, 0.168],
		[-0.12, 0.2, 0.145, 0.155], [0.04, 0.188, 0.135, 0.145], [0.18, 0.2, 0.148, 0.15],
		[0.30, 0.222, 0.158, 0.155, 0.005], [0.39, 0.238, 0.148, 0.16, 0.01], [0.45, 0.225, 0.12, 0.15, 0.015],
		[0.5, 0.17, 0.09, 0.12, 0.015], [0.53, 0.1, 0.07, 0.085, 0.01], [0.545, 0.0, 0.0, 0.0],
	])


## Hood down: a rolled cowl of fabric lying on the shoulders behind the neck, with an opening.
static func hood() -> Array:
	var cowl := shell([
		[-0.06, 0.0, 0.0, 0.0, 0.07], [-0.055, 0.1, 0.03, 0.07, 0.07], [-0.02, 0.15, 0.05, 0.11, 0.06],
		[0.04, 0.155, 0.05, 0.12, 0.05], [0.1, 0.13, 0.04, 0.1, 0.05], [0.14, 0.08, 0.02, 0.06, 0.05],
		[0.155, 0.0, 0.0, 0.0, 0.05],
	], 18)
	# the opening: a dark lining crescent facing up and forward
	var rim := shell([[0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.1, 0.035, 0.075], [0.012, 0.1, 0.035, 0.075], [0.012, 0.0, 0.0, 0.0]], 18)
	return [cowl, rim]


## Small daypack, centred on its back face.
static func backpack() -> ArrayMesh:
	return shell([
		[-0.2, 0.0, 0.0, 0.0, 0.05], [-0.195, 0.12, 0.02, 0.07, 0.05], [-0.15, 0.14, 0.02, 0.1, 0.05],
		[0.12, 0.14, 0.02, 0.1, 0.05], [0.18, 0.12, 0.02, 0.075, 0.05], [0.2, 0.0, 0.0, 0.0, 0.05],
	], 16)


static func pelvis() -> ArrayMesh:
	var pts := [Vector2(0.0, -0.10), Vector2(0.10, -0.095), Vector2(0.155, -0.04), Vector2(0.165, 0.04),
		Vector2(0.15, 0.10), Vector2(0.0, 0.11)]
	return lathe(pts, 1.12, 0.78, 16)


## Park helmet: round shell, the back drops lower than the front, with a short brim over the
## goggles.  Origin at the head centre.
static func helmet() -> ArrayMesh:
	var rings := []
	for i in 10:
		var t := float(i) / 9.0
		var a := lerpf(-0.42, PI * 0.5, t)
		var r := 0.137 * cos(a)
		var y := 0.142 * sin(a) + 0.01
		var back_drop := (1.0 - t) * 0.03
		rings.append([y - back_drop * 0.5, r * 0.98, r * 1.04, r * 1.1, 0.004])
	rings.append([0.152, 0.0, 0.0, 0.0])
	rings[0] = [rings[0][0] - 0.02, rings[0][1] * 0.97, rings[0][2] * 0.92, rings[0][3] * 1.06, 0.01]
	rings.insert(0, [rings[0][0], 0.0, 0.0, 0.0])
	return shell(rings, 24)


## Helmet details: brim, ear pads, chin strap, vents.  Returns [brim+pads (shell colour), vents+strap].
static func helmet_details() -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(-0.095, 0.075, -0.17), Vector3(0.095, 0.088, -0.12))        # brim over the goggles
	for x in [-1.0, 1.0]:
		_box(st, Vector3(x * 0.128 - 0.018, -0.07, -0.04), Vector3(x * 0.128 + 0.018, 0.01, 0.05))  # ear pads
	st.generate_normals()
	var dk := SurfaceTool.new()
	dk.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in [-0.05, 0.0, 0.05]:
		_box(dk, Vector3(x - 0.008, 0.138, -0.07), Vector3(x + 0.008, 0.156, 0.06))   # vents
	for x in [-1.0, 1.0]:
		_box(dk, Vector3(x * 0.112 - 0.006, -0.16, -0.03), Vector3(x * 0.112 + 0.006, -0.06, -0.01))  # strap
	_box(dk, Vector3(-0.11, -0.172, -0.06), Vector3(0.11, -0.158, -0.02))
	dk.generate_normals()
	return [st.commit(), dk.commit()]


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
		var front0 := -sin(a0) > 0.42
		var front1 := -sin(a1) > 0.42
		var st := lens if (front0 and front1) else band
		var h0 := -0.014 if not (front0 and front1) else -0.042
		var h1 := 0.024 if not (front0 and front1) else 0.038
		var rr := r + (0.016 if (front0 and front1) else 0.004)
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
	var hw := 0.064
	var parts := [
		[Vector3(-hw, -0.10, -0.2), Vector3(hw, -0.02, 0.14)],      # foot shell
		[Vector3(-hw * 1.08, -0.06, -0.08), Vector3(hw * 1.08, 0.19, 0.11)],  # cuff
		[Vector3(-hw * 1.12, 0.02, -0.09), Vector3(hw * 1.12, 0.05, 0.05)],   # buckle strap
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
		elif t < 0.1:
			# twin-tip: the tail turns up too
			var k2 := (0.1 - t) / 0.1
			y = 0.06 * k2 * k2
			w *= 1.0 - 0.35 * k2 * k2
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
