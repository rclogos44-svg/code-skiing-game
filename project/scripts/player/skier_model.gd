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
		[-0.22, 0.0, 0.0, 0.0], [-0.215, 0.2, 0.15, 0.16], [-0.18, 0.214, 0.155, 0.165],
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
	return lathe(pts, 1.28, 0.86, 16)


## Park helmet: round shell, the back drops lower than the front, with a short brim over the
## goggles.  Origin at the head centre.
## Park helmet like a modern in-mould shell: smooth and round, sides down over the ears, the back
## lower still.  Origin at the head centre.
static func helmet() -> ArrayMesh:
	var rings := [[-0.09, 0.0, 0.0, 0.0, 0.012]]
	for i in 12:
		var t := float(i) / 11.0
		var a := lerpf(-0.55, PI * 0.5, t)
		var r := 0.142 * cos(a)
		var y := 0.15 * sin(a) + 0.012
		rings.append([y, r * 0.99, r * 1.05, r * 1.12, 0.006 * (1.0 - t)])
	rings.append([0.162, 0.0, 0.0, 0.0])
	return shell(rings, 28)


static func helmet_details() -> Array:
	# brim: a curved peak over the goggles, in the shell colour
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_arc_band(st, -PI * 0.5 - 0.95, -PI * 0.5 + 0.95, 0.055, 0.078, 0.148, 0.175, 0.03, 20)
	st.generate_normals()
	# black: ear pads, vents on top, chin strap
	var dk := SurfaceTool.new()
	dk.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in [-1.0, 1.0]:
		_box(dk, Vector3(x * 0.13 - 0.02, -0.11, -0.04), Vector3(x * 0.13 + 0.02, -0.02, 0.06))  # ear pads
		_box(dk, Vector3(x * 0.118 - 0.005, -0.17, -0.03), Vector3(x * 0.118 + 0.005, -0.1, -0.01))  # strap
	for x in [-0.045, 0.045]:
		_box(dk, Vector3(x - 0.012, 0.128, -0.085), Vector3(x + 0.012, 0.15, -0.035))   # front vents (flush)
	_box(dk, Vector3(-0.01, 0.145, 0.02), Vector3(0.01, 0.163, 0.07))
	_box(dk, Vector3(-0.1, -0.18, -0.06), Vector3(0.1, -0.166, -0.025))           # chin strap
	dk.generate_normals()
	return [st.commit(), dk.commit()]


## Curved band (part of an elliptical cylinder) between angles a0..a1 (0 = +X, -PI/2 = front),
## heights y0..y1, half-axes rx / rz.  Closed with a little thickness.
static func _arc_band(st: SurfaceTool, a0: float, a1: float, y0: float, y1: float, rx: float, rz: float, th := 0.006, segs := 20) -> void:
	for i in segs:
		var u0 := lerpf(a0, a1, float(i) / segs)
		var u1 := lerpf(a0, a1, float(i + 1) / segs)
		for o: float in [0.0, -th]:
			var p00 := Vector3(cos(u0) * (rx + o), y0, sin(u0) * (rz + o))
			var p10 := Vector3(cos(u1) * (rx + o), y0, sin(u1) * (rz + o))
			var p01 := Vector3(cos(u0) * (rx + o), y1, sin(u0) * (rz + o))
			var p11 := Vector3(cos(u1) * (rx + o), y1, sin(u1) * (rz + o))
			for v in ([p00, p01, p10, p10, p01, p11] if o < 0.0 else [p00, p10, p01, p10, p11, p01]):   # outer face outward, inner inward
				st.add_vertex(v)
		# top and bottom lips
		for y: float in [y0, y1]:
			var q0 := Vector3(cos(u0) * rx, y, sin(u0) * rz)
			var q1 := Vector3(cos(u1) * rx, y, sin(u1) * rz)
			var q2 := Vector3(cos(u1) * (rx - th), y, sin(u1) * (rz - th))
			var q3 := Vector3(cos(u0) * (rx - th), y, sin(u0) * (rz - th))
			for v in [q0, q1, q2, q0, q2, q3, q0, q2, q1, q0, q3, q2]:   # both sides
				st.add_vertex(v)


## Big frameless-look goggles over the helmet: [strap, lens, frame].  Origin at the head centre
## (+0.025 up); -Z is forward.  Cylindrical lens wider than the face, black frame behind its edge,
## black strap around the helmet.
static func goggles(k := 1.0) -> Array:
	var strap := SurfaceTool.new()
	strap.begin(Mesh.PRIMITIVE_TRIANGLES)
	_arc_band(strap, -PI * 0.5 + 1.05, PI * 1.5 - 1.05, -0.022, 0.018, 0.152 * k, 0.171 * k, 0.006, 26)
	strap.generate_normals()
	var lens := SurfaceTool.new()
	lens.begin(Mesh.PRIMITIVE_TRIANGLES)
	_arc_band(lens, -PI * 0.5 - 1.0, -PI * 0.5 + 1.0, -0.05, 0.036, 0.142 * k, 0.168 * k, 0.004, 24)
	lens.generate_normals()
	var frame := SurfaceTool.new()
	frame.begin(Mesh.PRIMITIVE_TRIANGLES)
	_arc_band(frame, -PI * 0.5 - 1.1, -PI * 0.5 + 1.1, -0.056, 0.042, 0.137 * k, 0.161 * k, 0.018, 24)
	frame.generate_normals()
	return [strap.commit(), lens.commit(), frame.commit()]


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
		var w := 0.063 - 0.011 * sin(t * PI)  # sidecut: ~126 mm tips, ~104 mm underfoot (wide park ski)
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


## Anatomical limb along +Y (joint at 0, next joint at `length`): rings [y, half width, back
## depth, front depth].  Placed by SkierBody._seg with the body's x as the hint, a limb pointing
## down has its local +Z facing forward, so the "front" depth is the shell's +Z side.
static func anat(rings: Array) -> ArrayMesh:
	var r2 := []
	for r in rings:
		r2.append([r[0], r[1], r[2], r[3]])
	return shell(r2, 18)


static func thigh() -> ArrayMesh:      # baggy snow pants over a quad / hamstring shape
	# very wide straight-leg pants (player's reference): no taper at all, the fabric hangs off the hips
	return anat([[-0.07, 0.0, 0.0, 0.0], [-0.05, 0.122, 0.116, 0.116], [0.0, 0.146, 0.142, 0.146], [0.1, 0.151, 0.15, 0.156],
		[0.2, 0.15, 0.15, 0.156], [0.3, 0.147, 0.148, 0.153], [0.4, 0.143, 0.146, 0.149], [0.44, 0.14, 0.143, 0.146],
		[0.47, 0.1, 0.1, 0.1], [0.49, 0.0, 0.0, 0.0]])


static func shin() -> ArrayMesh:       # pant leg over the calf, wider again where it stacks on the boot
	# wide leg that blouses out over the boot and is gathered in at the ankle (elastic cuff), with a
	# couple of soft folds above the cuff - one smooth piece, no separate stack or knee bulge
	return anat([[-0.03, 0.0, 0.0, 0.0], [-0.01, 0.134, 0.142, 0.142], [0.06, 0.137, 0.146, 0.144], [0.15, 0.14, 0.149, 0.146],
		[0.24, 0.146, 0.153, 0.15], [0.31, 0.153, 0.158, 0.156], [0.35, 0.157, 0.161, 0.159], [0.375, 0.151, 0.155, 0.153],
		[0.395, 0.152, 0.156, 0.154], [0.415, 0.136, 0.14, 0.138], [0.432, 0.114, 0.118, 0.118], [0.44, 0.105, 0.11, 0.11],
		[0.445, 0.0, 0.0, 0.0]])


static func upper_arm() -> ArrayMesh:  # jacket sleeve over deltoid / biceps
	return anat([[-0.05, 0.0, 0.0, 0.0], [-0.03, 0.062, 0.062, 0.062], [0.03, 0.072, 0.066, 0.07], [0.12, 0.066, 0.06, 0.068],
		[0.22, 0.06, 0.056, 0.061], [0.29, 0.056, 0.054, 0.056], [0.31, 0.0, 0.0, 0.0]])


static func forearm() -> ArrayMesh:
	return anat([[-0.02, 0.0, 0.0, 0.0], [0.0, 0.054, 0.054, 0.054], [0.06, 0.057, 0.056, 0.056], [0.17, 0.052, 0.05, 0.05],
		[0.25, 0.05, 0.049, 0.049], [0.27, 0.05, 0.049, 0.049], [0.28, 0.0, 0.0, 0.0]])


## Glove: flat mitt from the wrist (y=0) to the fingertips, width along x; plus a separate thumb.
static func glove() -> Array:
	var mitt := shell([[0.0, 0.0, 0.0, 0.0], [0.005, 0.042, 0.028, 0.028], [0.05, 0.05, 0.033, 0.034], [0.11, 0.049, 0.032, 0.031],
		[0.16, 0.04, 0.026, 0.025], [0.18, 0.026, 0.018, 0.018], [0.188, 0.0, 0.0, 0.0]], 16)
	var thumb := lathe(capsule_profile(0.018, 0.016, 0.06, 3), 1.0, 1.0, 10)
	var gauntlet := lathe([Vector2(0.0, -0.09), Vector2(0.062, -0.09), Vector2(0.066, -0.04), Vector2(0.055, 0.0), Vector2(0.0, 0.0)], 1.05, 0.95, 14)
	return [mitt, thumb, gauntlet]


## Neck gaiter pulled up over the chin (head frame, origin at the head centre, -Z forward).
static func gaiter() -> ArrayMesh:
	return shell([[-0.2, 0.0, 0.0, 0.0], [-0.195, 0.07, 0.075, 0.07], [-0.15, 0.072, 0.09, 0.068], [-0.09, 0.08, 0.112, 0.08],
		[-0.05, 0.083, 0.116, 0.088], [-0.035, 0.08, 0.11, 0.087], [-0.03, 0.0, 0.0, 0.0]], 20)


## Ski-boot buckles and power strap (boot frame: origin at the ankle, toe toward -Z).
static func boot_hardware() -> Array:
	var buckles := SurfaceTool.new()
	buckles.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in [-0.04, 0.05, 0.12]:
		_box(buckles, Vector3(0.062, y, -0.07), Vector3(0.078, y + 0.022, 0.03))      # on the outside of the shell
	buckles.generate_normals()
	var strap := SurfaceTool.new()
	strap.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(strap, Vector3(-0.072, 0.165, -0.1), Vector3(0.072, 0.2, 0.12))
	_box(strap, Vector3(-0.04, -0.03, -0.105), Vector3(0.04, 0.17, -0.085))           # tongue
	strap.generate_normals()
	return [buckles.commit(), strap.commit()]


## Jacket details in the torso frame: front zip, two chest-pocket zips, hem band.
static func jacket_details() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# front depth of the torso shell at height y (see torso())
	var prof := [[-0.205, 0.155], [-0.12, 0.145], [0.04, 0.135], [0.18, 0.148], [0.3, 0.158], [0.39, 0.148], [0.45, 0.12], [0.5, 0.09]]
	for i in prof.size() - 1:
		var y0: float = prof[i][0]
		var y1: float = prof[i + 1][0]
		var dz: float = maxf(prof[i][1], prof[i + 1][1]) + 0.004
		_box(st, Vector3(-0.007, y0, -dz - 0.006), Vector3(0.007, y1, -dz + 0.004))
	for x in [-1.0, 1.0]:
		_box(st, Vector3(x * 0.06 - 0.045, 0.27, -0.168), Vector3(x * 0.06 + 0.045, 0.282, -0.155))
	st.generate_normals()
	return st.commit()


## Cargo pocket (thigh frame: y along the thigh, x outward is set when placed).
static func cargo_pocket() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(-0.012, -0.07, -0.055), Vector3(0.012, 0.07, 0.055))
	_box(st, Vector3(-0.016, 0.055, -0.058), Vector3(0.016, 0.075, 0.058))           # flap
	st.generate_normals()
	return st.commit()


## Fabric material: colour + roughness with a procedural micro-weave normal map.
static func fabric(color: Color, rough: float, weave := 90.0, strength := 0.5, rim := 0.2) -> StandardMaterial3D:
	var m := mat(color, rough, 0.0, {"rim": rim})
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_CELLULAR
	nz.frequency = 0.08
	var tex := NoiseTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 4.0
	tex.noise = nz
	m.normal_enabled = true
	m.normal_texture = tex
	m.normal_scale = strength
	m.uv1_scale = Vector3(weave / 10.0, weave / 10.0, 1.0)
	return m


## Baggy park pants in a light grey with darker grey patches (camo-like), fine twill weave on top.
## The patch texture is large (uv1 scale ~1.5 over a limb); the weave normal is fine noise.
static func patched_fabric(base: Color, patch: Color, rough: float, rim := 0.15) -> StandardMaterial3D:
	var m := mat(base, rough, 0.0, {"rim": rim})
	var pn := FastNoiseLite.new()
	pn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	pn.frequency = 0.03
	pn.seed = 7
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.66, 0.69, 1.0])
	ramp.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(patch.r / base.r, patch.g / base.g, patch.b / base.b), Color(patch.r / base.r, patch.g / base.g, patch.b / base.b)])
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = pn
	tex.color_ramp = ramp
	m.albedo_texture = tex
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_CELLULAR
	nz.frequency = 0.5
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 4.0
	nt.noise = nz
	m.normal_enabled = true
	m.normal_texture = nt
	m.normal_scale = 0.5
	m.uv1_scale = Vector3(1.5, 1.5, 1.0)
	return m


## Knit beanie (origin at the head centre, -Z forward): slouches a little to the back, with a
## folded cuff round the bottom. Returns [crown, cuff].
static func beanie() -> Array:
	var rings := [[0.006, 0.0, 0.0, 0.0]]
	for i in 11:
		var a := PI * 0.5 * float(i) / 10.0
		var c := cos(a)
		rings.append([0.006 + 0.13 * sin(a), 0.108 * c + 0.002, 0.117 * c + 0.002, 0.13 * c + 0.002, 0.016 * sin(a)])
	rings.append([0.14, 0.0, 0.0, 0.0, 0.016])
	var crown := shell(rings, 26)
	var cuff := shell([[-0.042, 0.0, 0.0, 0.0], [-0.042, 0.113, 0.121, 0.124], [-0.03, 0.117, 0.125, 0.128],
		[0.0, 0.118, 0.126, 0.13], [0.012, 0.115, 0.123, 0.127], [0.016, 0.0, 0.0, 0.0]], 26)
	return [crown, cuff]
