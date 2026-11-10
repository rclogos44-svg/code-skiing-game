class_name SkierRig
extends Skeleton3D
## The rider's clothes and gear as skinned meshes, driven straight from SkierBody's joint positions.
## The meshes are built offline by build/gen_rider.py (garments sculpted as distance fields with
## sewn-in folds, open lined hems, baked ambient occlusion, texture atlases for seams and pockets)
## and turned into res://assets/rider/rider_body.res / rider_head.res by import_rider.gd.  The
## bind pose (an easy athletic stance) comes with them in rider.json.
##
## Bones: pelvis, three spine segments, neck, thighs, shins, upper arms, forearms (gloves ride on
## the forearm), the head (helmet, goggles, gaiter) and both boots.  A spine bone's twist is shared
## out between the hips and the shoulders so a wound-up torso doesn't wring the jacket at the waist.

const SPAN := [["pelvis", "waist"], ["waist", "lumbar"], ["lumbar", "thoracic"], ["thoracic", "chest"], ["chest", "head"],
	["hip_l", "knee_l"], ["knee_l", "ankle_l"], ["hip_r", "knee_r"], ["knee_r", "ankle_r"],
	["shoulder_l", "elbow_l"], ["elbow_l", "hand_l"], ["shoulder_r", "elbow_r"], ["elbow_r", "hand_r"]]
const SPINE_TWIST := [0.0, 0.33, 0.66, 1.0, 1.0]

var bind := {}                  # joint name -> bind-pose position (pelvis at the origin, -Z forward)
var meshes := {}                # "rig_body" / "rig_head" -> MeshInstance3D
var surfaces := []              # [{name, material, group, uv_per_m}] from rider.json
var _x_prev := {}               # bone -> last hinge axis (keeps a straight limb from twisting)


static func _frame(head: Vector3, tail: Vector3, hint: Vector3) -> Transform3D:
	var y := (tail - head).normalized()
	var x := hint - y * hint.dot(y)
	if x.length() < 0.05:
		x = Vector3.FORWARD - y * Vector3.FORWARD.dot(y)
	x = x.normalized()
	return Transform3D(Basis(x, y, x.cross(y)), head)


## Bone frames relative to the pelvis joint.  `prev` keeps each limb's hinge axis sign.
func _frames(j: Dictionary, pelvis_b: Basis, torso_b: Basis, head_b: Basis, boot_l: Basis, boot_r: Basis, prev: Dictionary) -> Array:
	var p: Vector3 = j["pelvis"]
	var jj := j.duplicate()
	if not jj.has("waist"):
		jj["waist"] = p + pelvis_b.y * 0.07
	if not jj.has("lumbar"):
		jj["lumbar"] = (jj["waist"] as Vector3).lerp(j["chest"], 0.34)
	if not jj.has("thoracic"):
		jj["thoracic"] = (jj["waist"] as Vector3).lerp(j["chest"], 0.67)
	var out := []
	for i in SPAN.size():
		var h: Vector3 = jj.get(SPAN[i][0], p)
		var t: Vector3 = jj.get(SPAN[i][1], h + Vector3.UP * 0.1)
		var hint: Vector3
		if i < 5:
			hint = pelvis_b.x.slerp(torso_b.x, SPINE_TWIST[i]) if pelvis_b.x.dot(torso_b.x) > -0.95 else torso_b.x
		else:
			# limbs: the hinge axis of the knee / elbow, signed to agree with the body's sideways axis
			var pair := i - 5
			var top: String = SPAN[i - (pair % 2)][0]
			var mid: String = SPAN[i - (pair % 2)][1]
			var end: String = SPAN[i - (pair % 2) + 1][1]
			var ax: Vector3 = ((jj[top] as Vector3) - jj[mid]).cross((jj[end] as Vector3) - jj[mid])
			var side: Vector3 = pelvis_b.x if i <= 8 else torso_b.x
			if ax.length() > 0.004:
				var ref: Vector3 = prev.get(i, side)       # keep the sign it had: no 180 deg sleeve flips
				ax = ax.normalized() * signf(ax.dot(ref) + 1e-6)
				prev[i] = ax
			else:
				ax = prev.get(i, side)
			hint = ax
		out.append(_frame(h - p, t - p, hint))
	out.append(Transform3D(_proper(head_b), (jj["head"] as Vector3) - p))
	out.append(Transform3D(_proper(boot_l), (jj["ankle_l"] as Vector3) - p))
	out.append(Transform3D(_proper(boot_r), (jj["ankle_r"] as Vector3) - p))
	return out


## Orthonormal and right-handed (a mirrored basis has no rotation to give a bone).
static func _proper(b: Basis) -> Basis:
	var o := b.orthonormalized()
	if o.determinant() < 0.0:
		o.z = -o.z
	return o


## Loads the meshes and bind pose; `mats` maps a material key (jacket, pants, helmet, ...) to the
## material for those surfaces.  Returns false if the assets are missing.
func build(mats: Dictionary, head_layer: int) -> bool:
	var txt := FileAccess.get_file_as_string("res://assets/rider/rider.json")
	var meta = JSON.parse_string(txt) if txt != "" else null
	if meta == null:
		push_error("SkierRig: res://assets/rider/rider.json missing - run build/gen_rider.py")
		return false
	for k in meta["bind"]:
		var a: Array = meta["bind"][k]
		bind[k] = Vector3(a[0], a[1], a[2])
	surfaces = meta["surfaces"]
	var names: Array = meta["bones"]
	for n in names:
		add_bone(n)
	var bb := {}
	for k in ["boot_l", "boot_r"]:
		var a: Array = meta.get("bind_bases", {}).get(k, [1, 0, 0, 0, 1, 0, 0, 0, 1])
		bb[k] = Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]))
	var rest := _frames(bind, Basis(), Basis(), Basis(), bb["boot_l"], bb["boot_r"], {})
	for i in names.size():
		set_bone_rest(i, rest[i])
		reset_bone_pose(i)
	var sk := Skin.new()
	for i in names.size():
		sk.add_bind(i, (rest[i] as Transform3D).affine_inverse())
	for g in ["body", "head"]:
		var mesh: ArrayMesh = load("res://assets/rider/rider_%s.res" % g)
		if mesh == null:
			push_error("SkierRig: rider_%s.res missing" % g)
			return false
		var mi := MeshInstance3D.new()
		mi.name = "rig_" + g
		mi.mesh = mesh
		mi.skin = sk
		mi.custom_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3, 3, 3))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for si in mesh.get_surface_count():
			var key := mesh.surface_get_name(si).get_slice(":", 0)
			if mats.has(key):
				mi.set_surface_override_material(si, mats[key])
		if g == "head":
			mi.layers = 1 << (head_layer - 1)
		add_child(mi)
		mi.skeleton = NodePath("..")
		meshes["rig_" + g] = mi
	return true


## UV units per metre of a garment's atlas (for tiling the weave at a real-world size).
func uv_per_m(garment: String) -> float:
	for s in surfaces:
		if s["name"] == garment:
			return float(s["uv_per_m"])
	return 1.0


# ------------------------------------------------------------------ pose
## Put every bone where the joints are this frame: the skeleton sits at the pelvis (no rotation,
## so skeleton space is world-aligned), each bone runs head joint -> tail joint.
func update(j: Dictionary, pelvis_b: Basis, torso_b: Basis, head_b: Basis, boot_l: Basis, boot_r: Basis) -> void:
	if not j.has("pelvis") or not j.has("chest") or not j.has("head"):
		return
	global_transform = Transform3D(Basis(), j["pelvis"])
	var f := _frames(j, pelvis_b, torso_b, head_b, boot_l, boot_r, _x_prev)
	for i in f.size():
		var t: Transform3D = f[i]
		set_bone_pose_position(i, t.origin)
		set_bone_pose_rotation(i, t.basis.get_rotation_quaternion())
