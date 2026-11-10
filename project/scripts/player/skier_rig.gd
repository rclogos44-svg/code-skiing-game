class_name SkierRig
extends Skeleton3D
## Skinned rider clothes: one skeleton driven straight from SkierBody's joint positions, and
## continuous skinned garments (jacket with sleeves, collar, zip and chest pockets; a white shirt
## under it; baggy straight-cut pants) built from cross-section rings in a standing bind pose.
## Joints bend the cloth smoothly instead of meeting as separate pieces with round caps.  The
## jacket's hem is open (its lining shows), and when it rides up the shirt shows under it.

const SPAN := [["pelvis", "waist"], ["waist", "lumbar"], ["lumbar", "thoracic"], ["thoracic", "chest"], ["chest", "head"],
	["hip_l", "knee_l"], ["knee_l", "ankle_l"], ["hip_r", "knee_r"], ["knee_r", "ankle_r"],
	["shoulder_l", "elbow_l"], ["elbow_l", "hand_l"], ["shoulder_r", "elbow_r"], ["elbow_r", "hand_r"]]
const PELVIS := 0
const SP1 := 1
const SP2 := 2
const SP3 := 3
const NECK := 4
const THIGH := {"l": 5, "r": 7}
const SHIN := {"l": 6, "r": 8}
const UARM := {"l": 9, "r": 11}
const FARM := {"l": 10, "r": 12}
const SEGS := 22

var bind := {}                  # joint name -> bind-pose position (pelvis at the origin, -Z forward)
var meshes := {}                # name -> MeshInstance3D
var _x_prev := {}               # bone -> last hinge axis (keeps a straight limb from twisting)


func _init() -> void:
	var s12 := sin(deg_to_rad(12.0))
	var c12 := cos(deg_to_rad(12.0))
	bind = {"pelvis": Vector3.ZERO, "waist": Vector3(0, 0.07, 0), "lumbar": Vector3(0, 0.23, 0), "thoracic": Vector3(0, 0.39, 0),
		"chest": Vector3(0, 0.54, 0), "head": Vector3(0, 0.73, 0)}
	for sd in ["l", "r"]:
		var sg := -1.0 if sd == "l" else 1.0
		bind["hip_" + sd] = Vector3(sg * 0.095, -0.04, 0)
		bind["knee_" + sd] = Vector3(sg * 0.095, -0.48, 0)
		bind["ankle_" + sd] = Vector3(sg * 0.095, -0.91, 0)
		bind["shoulder_" + sd] = Vector3(sg * 0.185, 0.47, 0)
		bind["elbow_" + sd] = bind["shoulder_" + sd] + Vector3(sg * s12, -c12, 0) * 0.29
		bind["hand_" + sd] = bind["elbow_" + sd] + Vector3(sg * s12, -c12, 0) * 0.27
	for i in SPAN.size():
		add_bone("b%d" % i)
		set_bone_rest(i, _frame(bind[SPAN[i][0]], bind[SPAN[i][1]], Vector3.RIGHT))
		reset_bone_pose(i)


static func _frame(head: Vector3, tail: Vector3, hint: Vector3) -> Transform3D:
	var y := (tail - head).normalized()
	var x := hint - y * hint.dot(y)
	if x.length() < 0.05:
		x = Vector3.FORWARD - y * Vector3.FORWARD.dot(y)
	x = x.normalized()
	return Transform3D(Basis(x, y, x.cross(y)), head)


# ------------------------------------------------------------------ build
## Rings: [distance along the path, half width, front depth, back depth, {bone: weight}, sway weight,
## optional centre shift toward the back].  The path runs from `start` along `dir` in the bind pose.
func _tube(st: SurfaceTool, start: Vector3, dir: Vector3, rings: Array, v_scale := 2.0) -> void:
	var x0 := (Vector3.RIGHT - dir * dir.dot(Vector3.RIGHT)).normalized()
	var z0 := x0.cross(dir)
	var base := st.get_meta("n", 0) as int
	for ri in rings.size():
		var r: Array = rings[ri]
		var c: Vector3 = start + dir * float(r[0]) + z0 * (float(r[6]) if r.size() > 6 else 0.0)
		var bones := PackedInt32Array()
		var wts := PackedFloat32Array()
		var wd: Dictionary = r[4]
		for b in wd:
			bones.append(int(b))
			wts.append(float(wd[b]))
		while bones.size() < 4:
			bones.append(0)
			wts.append(0.0)
		for k in SEGS + 1:
			var a := TAU * float(k) / SEGS
			var sn := sin(a)
			var p := c + x0 * (cos(a) * float(r[1])) + z0 * (sn * (float(r[2]) if sn < 0.0 else float(r[3])))
			st.set_uv(Vector2(float(k) / SEGS, float(r[0]) * v_scale))
			st.set_color(Color(float(r[5]), 0, 0))
			st.set_bones(bones)
			st.set_weights(wts)
			st.add_vertex(p)
	for ri in rings.size() - 1:
		for k in SEGS:
			var a0 := base + ri * (SEGS + 1) + k
			var b0 := a0 + SEGS + 1
			for idx in [a0, a0 + 1, b0, a0 + 1, b0 + 1, b0]:
				st.add_index(idx)
	st.set_meta("n", base + rings.size() * (SEGS + 1))


## A small raised patch on the jacket front (zip strip, pocket, flap): x range, y range (bind
## pose), lifted `lift` m off a front surface of half width `a` and front depth `f` at those heights.
func _patch(st: SurfaceTool, x0: float, x1: float, y0: float, y1: float, a: float, f: float, lift: float, wd: Dictionary, sway_w: float) -> void:
	var base := st.get_meta("n", 0) as int
	var bones := PackedInt32Array()
	var wts := PackedFloat32Array()
	for b in wd:
		bones.append(int(b))
		wts.append(float(wd[b]))
	while bones.size() < 4:
		bones.append(0)
		wts.append(0.0)
	var nx := 4
	var ny := 4
	for j in ny + 1:
		for i in nx + 1:
			var x := lerpf(x0, x1, float(i) / nx)
			var y := lerpf(y0, y1, float(j) / ny)
			var ca := clampf(x / a, -0.98, 0.98)
			var z := -sqrt(1.0 - ca * ca) * f - lift
			st.set_uv(Vector2(float(i) / nx, float(j) / ny))
			st.set_color(Color(sway_w * (1.0 - float(j) / ny * 0.3), 0, 0))
			st.set_bones(bones)
			st.set_weights(wts)
			st.add_vertex(Vector3(x, y, z))
	for j in ny:
		for i in nx:
			var a0 := base + j * (nx + 1) + i
			var b0 := a0 + nx + 1
			for idx in [a0, a0 + 1, b0, a0 + 1, b0 + 1, b0]:
				st.add_index(idx)
	st.set_meta("n", base + (nx + 1) * (ny + 1))


func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_meta("n", 0)
	return st


func _instance(name: String, st: SurfaceTool, m: Material) -> MeshInstance3D:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.material_override = m
	var sk := Skin.new()
	for i in SPAN.size():
		sk.add_bind(i, get_bone_rest(i).affine_inverse())
	mi.skin = sk
	add_child(mi)
	mi.skeleton = NodePath("..")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	meshes[name] = mi
	return mi


func build(jacket: Material, shirt: Material, pants: Material, trim: Material) -> void:
	# --- jacket body: hip-length, roomy, straight hem open at the bottom; square-ish shoulders
	# sloping to a stand collar.  Sway weight 1 at the hem, 0 from the chest up.
	var st := _begin()
	var pw := {PELVIS: 0.75, SP1: 0.25}
	_tube(st, Vector3.ZERO, Vector3.UP, [
		[-0.15, 0.212, 0.142, 0.158, pw, 1.0], [-0.12, 0.21, 0.14, 0.156, pw, 0.95],
		[-0.04, 0.204, 0.135, 0.15, {PELVIS: 0.5, SP1: 0.5}, 0.75], [0.07, 0.198, 0.132, 0.144, {PELVIS: 0.15, SP1: 0.85}, 0.5],
		[0.18, 0.2, 0.134, 0.14, {SP1: 0.6, SP2: 0.4}, 0.25], [0.3, 0.208, 0.138, 0.136, {SP2: 0.7, SP3: 0.3}, 0.08],
		[0.4, 0.222, 0.136, 0.132, {SP2: 0.2, SP3: 0.8}, 0.0], [0.465, 0.228, 0.124, 0.124, {SP3: 1.0}, 0.0],
		[0.51, 0.19, 0.105, 0.112, {SP3: 1.0}, 0.0], [0.545, 0.12, 0.086, 0.094, {SP3: 0.8, NECK: 0.2}, 0.0],
		[0.565, 0.086, 0.078, 0.084, {SP3: 0.5, NECK: 0.5}, 0.0], [0.6, 0.082, 0.074, 0.08, {SP3: 0.3, NECK: 0.7}, 0.0],
		[0.635, 0.078, 0.072, 0.077, {SP3: 0.2, NECK: 0.8}, 0.0],
	], 2.4)
	# sleeves: from inside the shoulder to the wrist, roomy, bending at the elbow, a cuff at the end
	for sd in ["l", "r"]:
		var sh: Vector3 = bind["shoulder_" + sd]
		var dir: Vector3 = (bind["elbow_" + sd] - sh).normalized()
		var u: int = UARM[sd]
		var f: int = FARM[sd]
		_tube(st, sh, dir, [
			[-0.07, 0.072, 0.074, 0.074, {SP3: 0.85, u: 0.15}, 0.0], [-0.02, 0.076, 0.078, 0.078, {SP3: 0.45, u: 0.55}, 0.0],
			[0.04, 0.074, 0.075, 0.075, {SP3: 0.1, u: 0.9}, 0.02], [0.15, 0.07, 0.071, 0.071, {u: 1.0}, 0.05],
			[0.25, 0.066, 0.067, 0.067, {u: 0.85, f: 0.15}, 0.08], [0.29, 0.064, 0.065, 0.065, {u: 0.5, f: 0.5}, 0.1],
			[0.33, 0.062, 0.063, 0.063, {u: 0.15, f: 0.85}, 0.12], [0.44, 0.059, 0.06, 0.06, {f: 1.0}, 0.18],
			[0.52, 0.058, 0.058, 0.058, {f: 1.0}, 0.22], [0.545, 0.05, 0.05, 0.05, {f: 1.0}, 0.22], [0.556, 0.049, 0.049, 0.049, {f: 1.0}, 0.22],
		], 2.4)
	_instance("rig_jacket", st, jacket)
	# --- zip down the front and two flapped chest pockets (same sway weights as the jacket there)
	var dt := _begin()
	_patch(dt, -0.007, 0.007, -0.15, 0.04, 0.204, 0.137, 0.003, {PELVIS: 0.5, SP1: 0.5}, 0.85)
	_patch(dt, -0.007, 0.007, 0.04, 0.3, 0.2, 0.134, 0.003, {SP1: 0.6, SP2: 0.4}, 0.2)
	_patch(dt, -0.007, 0.007, 0.3, 0.6, 0.12, 0.12, 0.003, {SP3: 1.0}, 0.0)
	for sg in [-1.0, 1.0]:
		_patch(dt, sg * 0.04 - 0.05, sg * 0.04 + 0.05, 0.25, 0.35, 0.212, 0.137, 0.004, {SP2: 0.5, SP3: 0.5}, 0.0)
		_patch(dt, sg * 0.04 - 0.054, sg * 0.04 + 0.054, 0.33, 0.37, 0.218, 0.137, 0.009, {SP3: 1.0}, 0.0)
	_instance("rig_details", dt, trim)
	# --- white shirt: a little shorter than the jacket and tucked inside it; shows when the hem lifts
	var ss := _begin()
	_tube(ss, Vector3.ZERO, Vector3.UP, [
		[-0.125, 0.196, 0.128, 0.142, {PELVIS: 0.75, SP1: 0.25}, 0.0], [-0.05, 0.19, 0.124, 0.138, {PELVIS: 0.5, SP1: 0.5}, 0.0],
		[0.1, 0.186, 0.122, 0.132, {PELVIS: 0.1, SP1: 0.9}, 0.0], [0.3, 0.194, 0.126, 0.126, {SP2: 0.7, SP3: 0.3}, 0.0],
		[0.45, 0.205, 0.114, 0.114, {SP3: 1.0}, 0.0], [0.53, 0.1, 0.075, 0.08, {SP3: 0.8, NECK: 0.2}, 0.0],
	], 2.0)
	_instance("rig_shirt", ss, shirt)
	# --- pants: a roomy seat and two straight, wide legs that stack a little over the boots
	var ps := _begin()
	_tube(ps, Vector3.ZERO, Vector3.UP, [
		[-0.16, 0.225, 0.14, 0.16, {PELVIS: 1.0}, 0.0, 0.01], [-0.06, 0.218, 0.135, 0.155, {PELVIS: 1.0}, 0.0, 0.01],
		[0.04, 0.198, 0.125, 0.14, {PELVIS: 0.8, SP1: 0.2}, 0.0], [0.09, 0.19, 0.12, 0.13, {PELVIS: 0.6, SP1: 0.4}, 0.0],
	], 2.0)
	for sd in ["l", "r"]:
		var t: int = THIGH[sd]
		var s: int = SHIN[sd]
		_tube(ps, bind["hip_" + sd] + Vector3(0, 0.05, 0), Vector3.DOWN, [
			[0.0, 0.14, 0.138, 0.15, {PELVIS: 0.7, t: 0.3}, 0.0], [0.08, 0.137, 0.135, 0.145, {PELVIS: 0.35, t: 0.65}, 0.0],
			[0.2, 0.132, 0.13, 0.136, {t: 1.0}, 0.0], [0.36, 0.128, 0.126, 0.13, {t: 1.0}, 0.0],
			[0.45, 0.126, 0.124, 0.126, {t: 0.8, s: 0.2}, 0.0], [0.49, 0.125, 0.123, 0.124, {t: 0.5, s: 0.5}, 0.0],
			[0.53, 0.124, 0.122, 0.122, {t: 0.2, s: 0.8}, 0.0], [0.68, 0.121, 0.12, 0.12, {s: 1.0}, 0.0],
			[0.83, 0.122, 0.122, 0.121, {s: 1.0}, 0.0], [0.9, 0.128, 0.13, 0.126, {s: 1.0}, 0.0],
			[0.95, 0.132, 0.134, 0.13, {s: 1.0}, 0.0], [0.99, 0.13, 0.132, 0.128, {s: 1.0}, 0.0],
		], 2.0)
	_instance("rig_pants", ps, pants)


# ------------------------------------------------------------------ pose
## Put every bone where the joints are this frame: the skeleton sits at the pelvis, each bone runs
## head joint -> tail joint, twisted by the limb's hinge (knee / elbow) or the body's sideways axis.
func update(j: Dictionary, pelvis_b: Basis, torso_b: Basis) -> void:
	if not j.has("pelvis") or not j.has("chest"):
		return
	var p: Vector3 = j["pelvis"]
	global_transform = Transform3D(Basis(), p)
	var jj := j.duplicate()
	if not jj.has("waist"):
		jj["waist"] = p + pelvis_b.y * 0.07
	if not jj.has("lumbar"):
		jj["lumbar"] = (jj["waist"] as Vector3).lerp(j["chest"], 0.34)
	if not jj.has("thoracic"):
		jj["thoracic"] = (jj["waist"] as Vector3).lerp(j["chest"], 0.67)
	for i in SPAN.size():
		var h: Vector3 = jj.get(SPAN[i][0], p)
		var t: Vector3 = jj.get(SPAN[i][1], h + Vector3.UP * 0.1)
		var hint: Vector3 = pelvis_b.x if i == PELVIS else torso_b.x
		if i >= 5:
			# limbs: the hinge axis of the knee / elbow, signed to agree with the body's sideways axis
			var pair := i - 5
			var top: String = SPAN[i - (pair % 2)][0]
			var mid: String = SPAN[i - (pair % 2)][1]
			var end: String = SPAN[i - (pair % 2) + 1][1]
			var ax: Vector3 = ((jj[top] as Vector3) - jj[mid]).cross((jj[end] as Vector3) - jj[mid])
			var side: Vector3 = pelvis_b.x if i <= 8 else torso_b.x
			if ax.length() > 0.004:
				var ref: Vector3 = _x_prev.get(i, side)       # keep the sign it had: no 180 deg sleeve flips
				ax = ax.normalized() * signf(ax.dot(ref) + 1e-6)
				_x_prev[i] = ax
			else:
				ax = _x_prev.get(i, side)
			hint = ax
		var f := _frame(h - p, t - p, hint)
		set_bone_pose_position(i, f.origin)
		set_bone_pose_rotation(i, f.basis.get_rotation_quaternion())
