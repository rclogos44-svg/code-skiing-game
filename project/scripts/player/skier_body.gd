class_name SkierBody
extends Node3D
## Procedurally animated skier.  Each frame a pose (joint positions in world space) is computed
## from the physics state - inclination into turns, angulation, tuck, hockey stop, crouch, grabs,
## landing/bump absorption - and two-bone IK places knees and elbows.  When the skier crashes the
## pose comes from a verlet ragdoll instead.  On foot: a walking / hiking gait with the skis on the
## shoulder; on a chairlift: seated.  Body part meshes are then fitted between joints.

const THIGH := 0.44
const SHIN := 0.43
const UPPER_ARM := 0.29
const FOREARM := 0.27
const HIP_HALF := 0.095
const SHOULDER_HALF := 0.185
const TORSO_LEN := 0.50
const ANKLE_H := 0.15
const HEAD_LAYER := 2   # render layer bit hidden in first-person
var skier: Skier
var parts := {}
var head_parts: Array[MeshInstance3D] = []
var joints := {}
var ski_l := Transform3D.IDENTITY
var ski_r := Transform3D.IDENTITY
var boot_l := Basis.IDENTITY
var boot_r := Basis.IDENTITY
var torso_basis := Basis.IDENTITY
var head_basis := Basis.IDENTITY
var ragdoll := SkierRagdoll.new()
var in_ragdoll := false
var ski_detached := false

# smoothed pose parameters
var _p := {}
var _lean := 0.0
var _lean_v := 0.0
var _torso_yaw := 0.0
var _torso_yaw_v := 0.0
var _absorb := 0.0
var _absorb_v := 0.0
var _prev_root := Vector3.ZERO
var _prev_rv := 0.0
var _pole_plant := 0.0
var _plant_side := 1.0
var _last_steer_sign := 0.0
var _stop_pop := 0.0
var _prev_edgeb := 0.0
var _push_ph := 0.0            # double-pole push cycle 0..1 (reach, push, recover)
var _push_amt := 0.0
var _pole_tip := {}           # planted pole tips (world) during the drive
const POLE_LEN := 1.12
var _hands := {}
## Grab poses (preview; not wired to input yet).  Legs are driven ONLY by joint angles inside
## human limits; the ski is locked to the shin by the boot, so where the ski points follows from
## the hip and knee.  Per leg [hip flexion, hip abduction (+ out, - across), hip internal rotation,
## knee flexion] in degrees.  Per hand [ski, along the ski (-tip / +tail, m), edge +1 out / -1 in].
## "free": where the other hand goes (torso frame).  "pitch"/"twist"/"side": spine (deg / rad).
const LEG_LIMITS := {"flex": [-15.0, 125.0], "abd": [-25.0, 45.0], "rot": [-40.0, 40.0], "knee": [0.0, 140.0]}
const BOOT_LEAN := 15.0        # shin leans this far forward of the boot's up axis (deg)
const GRAB_POSES := {
	# relaxed, real-world shapes: knees tucked ~90-110 deg, skis close to parallel with a light
	# tweak, a little twist toward the grab, free arm out to the side for balance
	# reference: the classic X - skis flat, crossed right under the boots and touching (one just on
	# top of the other), knees tucked, left hand across onto the right ski by the boot, right arm high
	"Mute": {"l": ["r", -0.06, 1.0], "free": {"r": Vector3(0.3, 0.42, 0.05)},
		"legs": {"l": [80.0, -10.0, 20.0, 105.0], "r": [85.0, -10.0, 20.0, 108.0]}, "pitch": 36.0, "twist": -0.25, "side": 0.1,
		"skis": {"yaw": {"l": 28.0, "r": -28.0}, "gap": 0.06, "stack": 0.07}},
	"Safety": {"r": ["r", -0.02, 1.0], "free": {"l": Vector3(-0.45, 0.05, -0.1)},
		"legs": {"l": [70.0, 6.0, 5.0, 100.0], "r": [88.0, 12.0, -5.0, 108.0]}, "pitch": 28.0, "twist": 0.12, "side": 0.12},
	"Japan": {"l": ["r", 0.0, 1.0], "free": {"r": Vector3(0.4, 0.22, -0.05)},
		"legs": {"l": [45.0, 5.0, 10.0, 118.0], "r": [55.0, -6.0, 18.0, 125.0]}, "pitch": 22.0, "twist": -0.2, "side": -0.1},
	"Tail": {"r": ["r", 0.6, 1.0], "free": {"l": Vector3(-0.42, 0.08, -0.2)},
		"legs": {"l": [75.0, 5.0, 5.0, 100.0], "r": [92.0, 8.0, -5.0, 95.0]}, "pitch": 24.0, "twist": 0.25, "side": 0.12},
	"Tip": {"l": ["l", -0.52, 1.0], "free": {"r": Vector3(0.42, 0.08, 0.05)},
		"legs": {"l": [100.0, 6.0, 0.0, 80.0], "r": [72.0, 5.0, 5.0, 100.0]}, "pitch": 38.0, "twist": 0.12, "side": -0.08},
	"Truck Driver": {"l": ["l", -0.3, 1.0], "r": ["r", -0.3, 1.0],
		"legs": {"l": [95.0, 8.0, 0.0, 95.0], "r": [95.0, 8.0, 0.0, 95.0]}, "pitch": 38.0, "twist": 0.0, "side": 0.0},
	"Blunt": {"r": ["r", 0.72, 1.0], "free": {"l": Vector3(-0.4, 0.22, -0.05)},
		"legs": {"l": [55.0, 5.0, 5.0, 115.0], "r": [55.0, 10.0, -8.0, 128.0]}, "pitch": 18.0, "twist": 0.25, "side": 0.12},
}
var _grab_bend := 0.0            # extra spine bend (rad) so an out-of-reach hand gets to the ski
var grab_gap := {}               # hand-to-ski distance per hand (m), for checking the poses
var _fk := {}                    # leg forward kinematics for the current grab: hip / knee per side


var _solved := {}                # grab name -> pose solved so the hand really holds the ski
const SPINE_LIMITS := {"pitch": [0.0, 70.0], "twist": [-0.45, 0.45], "side": [-0.3, 0.3]}


## Body-frame geometry of a grab pose: returns the total hand-to-grab-point gap (m) beyond arm reach.
func _grab_gap(g: Dictionary, legs: Dictionary, sp: Array, ph: float, pz: float) -> float:
	var tb := Basis(Vector3.UP, sp[1]) * Basis(Vector3(0, 0, 1), sp[2]) * Basis(Vector3(1, 0, 0), -deg_to_rad(sp[0]))
	var pelvis := Vector3(0, ph, pz)
	var chest := pelvis + tb.y * (0.07 + TORSO_LEN)
	var total := 0.0
	for sd in ["l", "r"]:
		if not g.has(sd):
			continue
		var spec: Array = g[sd]
		var ss := -1.0 if spec[0] == "l" else 1.0
		var fk := _leg_fk(Vector3(ss * HIP_HALF, ph - 0.04, pz), ss, legs[spec[0]])
		var B: Basis = fk[1]
		var pt: Vector3 = (fk[2] as Vector3) + B * Vector3(ss * 0.07 * float(spec[2]), 0.05, float(spec[1]))
		var hs := -1.0 if sd == "l" else 1.0
		var sh := chest - tb.y * 0.07 + tb.x * (hs * SHOULDER_HALF)
		total += maxf((pt - sh).length() - (UPPER_ARM + FOREARM) * 0.95, 0.0)
	return total


## Coordinate descent over the grabbing legs' joint angles and the spine, all clamped to human
## limits: stay close to the styled pose, but the hand must reach the ski.
func _solve_grab(name: String, ph: float, pz: float) -> Dictionary:
	var g: Dictionary = GRAB_POSES[name]
	var legs := {"l": (g["legs"]["l"] as Array).duplicate(), "r": (g["legs"]["r"] as Array).duplicate()}
	var sp := [float(g["pitch"]), float(g["twist"]), float(g["side"])]
	var legs0 := {"l": (g["legs"]["l"] as Array).duplicate(), "r": (g["legs"]["r"] as Array).duplicate()}
	var sp0 := sp.duplicate()
	var keys := ["flex", "abd", "rot", "knee"]
	var grabbed := []
	for sd in ["l", "r"]:
		if g.has(sd) and not grabbed.has(g[sd][0]):
			grabbed.append(g[sd][0])
	if g.has("skis"):
		grabbed = ["l", "r"]
	var cost := func(lg: Dictionary, s2: Array) -> float:
		var c := pow(_grab_gap(g, lg, s2, ph, pz), 2.0) * 4000.0
		if g.has("skis"):
			c += _ski_target_cost(g["skis"], lg, ph, pz)
		for side in ["l", "r"]:
			for i in 4:
				c += pow((float(lg[side][i]) - float(legs0[side][i])) / 40.0, 2.0) * 1.0
		c += pow((s2[0] - sp0[0]) / 40.0, 2.0) * 0.12 + pow((s2[1] - sp0[1]) / 0.6, 2.0) * 0.25 + pow((s2[2] - sp0[2]) / 0.5, 2.0) * 0.25
		return c
	var best: float = cost.call(legs, sp)
	for step in [12.0, 6.0, 3.0, 1.5]:
		for it in 30:
			var improved := false
			for side in grabbed:
				for i in 4:
					for dirn in [-1.0, 1.0]:
						var v: float = float(legs[side][i]) + dirn * step
						var lim: Array = LEG_LIMITS[keys[i]]
						v = clampf(v, lim[0], lim[1])
						var old: float = legs[side][i]
						legs[side][i] = v
						var c: float = cost.call(legs, sp)
						if c < best - 1e-6:
							best = c
							improved = true
						else:
							legs[side][i] = old
			var sp_steps := [step, step / 60.0, step / 60.0]
			var sp_keys := ["pitch", "twist", "side"]
			for i in 3:
				for dirn in [-1.0, 1.0]:
					var lim2: Array = SPINE_LIMITS[sp_keys[i]]
					var old2: float = sp[i]
					sp[i] = clampf(sp[i] + dirn * sp_steps[i], lim2[0], lim2[1])
					var c2: float = cost.call(legs, sp)
					if c2 < best - 1e-6:
						best = c2
						improved = true
					else:
						sp[i] = old2
			if not improved:
				break
	return {"legs": legs, "pitch": sp[0], "twist": sp[1], "side": sp[2], "gap": _grab_gap(g, legs, sp, ph, pz)}


## How far the skis are from a target shape: yaw of each ski (deg, + = tip to the right), flat
## (no pitch / roll), centres `gap` apart horizontally and the left ski `stack` m above the right.
func _ski_target_cost(t: Dictionary, legs: Dictionary, ph: float, pz: float) -> float:
	var c := 0.0
	var cen := {}
	for sd in ["l", "r"]:
		var ss := -1.0 if sd == "l" else 1.0
		var fk := _leg_fk(Vector3(ss * HIP_HALF, ph - 0.04, pz), ss, legs[sd])
		var B: Basis = fk[1]
		var tip := -B.z
		var yaw := rad_to_deg(atan2(tip.x, -tip.z))
		c += pow((yaw - float(t["yaw"][sd])) / 8.0, 2.0) * 3.0
		c += (pow(tip.y / 0.15, 2.0) + pow(B.x.y / 0.15, 2.0)) * 2.0       # flat skis
		cen[sd] = fk[2]
	var dl: Vector3 = cen["l"] - cen["r"]
	c += pow((Vector2(dl.x, dl.z).length() - float(t["gap"])) / 0.04, 2.0) * 2.0
	c += pow((dl.y - float(t["stack"])) / 0.03, 2.0) * 2.0
	return c


## Leg forward kinematics in the body frame (x right, y up, -z forward). Returns [knee, ski basis,
## ski centre].  Angles are clamped to LEG_LIMITS.
func _leg_fk(hip: Vector3, sgn: float, a: Array) -> Array:
	var flex := deg_to_rad(clampf(float(a[0]), LEG_LIMITS["flex"][0], LEG_LIMITS["flex"][1]))
	var abd := deg_to_rad(clampf(float(a[1]), LEG_LIMITS["abd"][0], LEG_LIMITS["abd"][1]))
	var rot := deg_to_rad(clampf(float(a[2]), LEG_LIMITS["rot"][0], LEG_LIMITS["rot"][1]))
	var knee_f := deg_to_rad(clampf(float(a[3]), LEG_LIMITS["knee"][0], LEG_LIMITS["knee"][1]))
	# hamstrings: with a straight knee the hip only folds to ~75 deg; bending the knee frees it
	flex = minf(flex, deg_to_rad(75.0) + knee_f * 0.8)
	var H := Basis(Vector3(1, 0, 0), flex) * Basis(Vector3(0, 0, 1), sgn * abd) * Basis(Vector3.UP, sgn * rot)
	var knee := hip + H * Vector3(0, -THIGH, 0)
	var S := H * Basis(Vector3(1, 0, 0), -knee_f)           # knee is a hinge: the shin folds back
	var ankle := knee + S * Vector3(0, -SHIN, 0)
	var B := S * Basis(Vector3(1, 0, 0), deg_to_rad(BOOT_LEAN))   # boot locked to the shin
	var ski_c := ankle - B.y * ANKLE_H - B.z * 0.03
	return [knee, B, ski_c]
var preview_grab := ""
var _ag := ""                     # grab pose being shown (preview or the skier's live grab)
var _gw := 0.0                    # how far into it (blends in and out)              # spring-smoothed hand offsets: arms settle after the body


func setup(s: Skier) -> void:
	skier = s
	top_level = true
	global_transform = Transform3D.IDENTITY
	_build()
	ragdoll.terrain = s.terrain
	for k in ["layout", "ftuck", "chatter", "pelvis_h", "pelvis_z", "pitch", "counter", "hand_spread", "plow", "feet_up", "arms_air", "tuck", "grab_l", "grab_r", "brake", "edgeb"]:
		_p[k] = 0.0
	_p["pelvis_h"] = 0.9
	for gname in GRAB_POSES:
		_solved[gname] = _solve_grab(gname, 0.86, 0.06)


## All-black park outfit: long baggy hooded jacket, baggy pants stacked over the boots, black
## helmet with orange goggles, black gloves and charcoal twin-tips.  Slightly different blacks and
## roughness keep the jacket, pants and gear readable.
func _build() -> void:
	var jacket := SkierModel.fabric(Color(0.07, 0.072, 0.08), 0.62, 60.0, 0.45, 0.25)
	var jacket_dark := SkierModel.mat(Color(0.11, 0.115, 0.125), 0.8)
	var pants := SkierModel.fabric(Color(0.04, 0.042, 0.046), 0.85, 90.0, 0.6, 0.18)
	var helmet := SkierModel.mat(Color(0.56, 0.57, 0.55), 0.55, 0.0, {"clearcoat": 0.3})
	var skin := SkierModel.mat(Color(0.85, 0.66, 0.55), 0.6)
	var lens := SkierModel.mat(Color(0.12, 0.32, 0.85), 0.04, 0.85, {"clearcoat": 1.0})
	var strap := SkierModel.mat(Color(0.03, 0.03, 0.035), 0.6)
	var glove := SkierModel.fabric(Color(0.05, 0.05, 0.055), 0.5, 40.0, 0.4, 0.15)
	var gaiter := SkierModel.fabric(Color(0.17, 0.175, 0.19), 0.95, 120.0, 0.6, 0.1)
	var metal := SkierModel.mat(Color(0.7, 0.72, 0.75), 0.3, 0.9)
	var boot := SkierModel.mat(Color(0.13, 0.135, 0.15), 0.35, 0.0, {"clearcoat": 0.5})
	var bind := SkierModel.mat(Color(0.12, 0.12, 0.13), 0.4, 0.4)
	var pole_m := SkierModel.mat(Color(0.75, 0.77, 0.8), 0.3, 0.8)
	var grip_m := SkierModel.mat(Color(0.1, 0.1, 0.1), 0.6)
	var accent := SkierModel.mat(Color(0.16, 0.165, 0.18), 0.7)
	_add("pelvis", SkierModel.pelvis(), pants)
	_add("torso", SkierModel.torso(), jacket)
	var hd := SkierModel.hood()
	_add("hood", hd[0], jacket)
	_add("hood_rim", hd[1], SkierModel.mat(Color(0.2, 0.205, 0.22), 0.9))
	_add("backpack", SkierModel.backpack(), SkierModel.mat(Color(0.14, 0.145, 0.16), 0.75))
	_add("collar", SkierModel.lathe([Vector2(0.0, -0.01), Vector2(0.085, -0.01), Vector2(0.08, 0.06), Vector2(0.0, 0.06)], 1.0, 1.0, 12), jacket_dark)
	_add("neck", SkierModel.limb(0.05, 0.048, 0.08), skin)
	_add("gaiter", SkierModel.gaiter(), gaiter, true)
	_add("jacket_details", SkierModel.jacket_details(), strap)
	_add("head", SkierModel.sphere(0.105, 0.95, 1.12, 1.05), skin, true)
	_add("helmet", SkierModel.helmet(), helmet, true)
	var hdet := SkierModel.helmet_details()
	_add("helmet_trim", hdet[0], helmet, true)
	_add("helmet_dark", hdet[1], strap, true)
	var g := SkierModel.goggles()
	_add("goggle_band", g[0], strap, true)
	_add("goggle_lens", g[1], lens, true)
	_add("goggle_frame", g[2], strap, true)
	for side in ["l", "r"]:
		_add("uarm_" + side, SkierModel.upper_arm(), jacket)
		_add("farm_" + side, SkierModel.forearm(), jacket)
		var gl := SkierModel.glove()
		_add("hand_" + side, gl[0], glove)
		_add("thumb_" + side, gl[1], glove)
		_add("cuff_" + side, gl[2], glove)
		_add("pocket_" + side, SkierModel.cargo_pocket(), pants)
		var bh := SkierModel.boot_hardware()
		_add("buckles_" + side, bh[0], metal)
		_add("bootstrap_" + side, bh[1], strap)
		# joints: rounded caps so knees, elbows and shoulders bend like joints, not pipes
		_add("shoulder_cap_" + side, SkierModel.sphere(0.072, 1.0, 1.0, 1.0), jacket)
		_add("elbow_cap_" + side, SkierModel.sphere(0.053), jacket)
		_add("knee_cap_" + side, SkierModel.sphere(0.096, 1.0, 1.0, 1.05), pants)
		_add("stack_" + side, SkierModel.lathe([Vector2(0.0, -0.02), Vector2(0.105, -0.02), Vector2(0.118, 0.03), Vector2(0.108, 0.09), Vector2(0.0, 0.09)], 1.0, 1.1, 14), pants)
		_add("thigh_" + side, SkierModel.thigh(), pants)
		_add("shin_" + side, SkierModel.shin(), pants)
		_add("boot_" + side, SkierModel.boot(), boot)
		var sk := SkierModel.ski()
		var flex := ShaderMaterial.new()
		flex.shader = load("res://shaders/ski_flex.gdshader")
		_add("ski_" + side, sk[0], flex)
		_add("bind_" + side, sk[1], bind)
		var pl := SkierModel.pole()
		_add("pole_" + side, pl[0], pole_m)
		_add("grip_" + side, pl[1], grip_m)
		_add("basket_" + side, pl[2], grip_m)
	# a stripe of accent colour on the jacket
	_add("stripe", SkierModel.lathe([Vector2(0.0, 0.0), Vector2(0.18, 0.0), Vector2(0.183, 0.035), Vector2(0.0, 0.035)], 1.19, 0.73, 18), accent)
	parts["stripe"].visible = false        # read as a toy band round the chest; the zip and pockets replace it


func _add(name: String, mesh: Mesh, m: Material, head := false) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if head:
		mi.layers = 1 << (HEAD_LAYER - 1)
		head_parts.append(mi)
	add_child(mi)
	parts[name] = mi


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if skier == null:
		return
	var dt := minf(delta, 0.05)
	if skier.is_crashed:
		if not in_ragdoll:
			_start_ragdoll()
		_pose_from_ragdoll()
	else:
		if in_ragdoll:
			in_ragdoll = false
			ski_detached = false
		match skier.mode:
			Skier.Mode.WALK:
				_compute_walk(dt)
			Skier.Mode.LIFT:
				_compute_seated(dt)
			_:
				_compute_pose(dt)
	_apply_parts()


func _physics_process(dt: float) -> void:
	if in_ragdoll:
		ragdoll.step(dt)


func _sm(key: String, target: float, rate: float, dt: float) -> float:
	var v: float = _p[key]
	v = lerpf(v, target, 1.0 - exp(-rate * dt))
	_p[key] = v
	return v


func _compute_pose(dt: float) -> void:
	var s := skier
	var root := s.visual_xform()
	var up := root.basis.y
	# yaw revert after a switch landing: body keeps spinning to face forward
	if absf(s.revert) > 0.001:
		root.basis = Basis(up, s.revert) * root.basis
	# flips: the whole body rotates about its centre of mass
	if s.airborne and absf(s.air_pitch) > 0.001:
		var piv := root.origin + up * 0.9
		var fr := Basis(root.basis.x.normalized(), -s.air_pitch)
		root = Transform3D(fr * root.basis, piv + fr * (root.origin - piv))
		up = root.basis.y
	# visual sink in deep powder
	var powder := s.surface.r * (1.0 - s.surface.g) if not s.airborne else 0.0
	root.origin -= up * powder * 0.16 * (1.0 - clampf(s.speed / 25.0, 0.0, 0.6))
	# bump absorption: pelvis lags behind sudden vertical root motion
	var rv := (root.origin.y - _prev_root.y) / maxf(dt, 0.001)
	if _prev_root == Vector3.ZERO or root.origin.distance_to(_prev_root) > 5.0:
		rv = 0.0
		_prev_rv = 0.0
	var ra := (rv - _prev_rv) / maxf(dt, 0.001)
	_prev_root = root.origin
	_prev_rv = rv
	if not s.airborne:
		_absorb_v += (-_absorb * 90.0 - _absorb_v * 13.0 - clampf(ra, -60.0, 60.0) * 0.35) * dt
		_absorb = clampf(_absorb + _absorb_v * dt, -0.22, 0.08)
	else:
		_absorb = lerpf(_absorb, 0.0, 1.0 - exp(-5.0 * dt))
		_absorb_v = 0.0
	# inclination: a critically damped spring toward the lean that balances the measured
	# sideways acceleration -> smooth roll-in, smooth edge change, no snapping
	var lean_t := s.lean_angle() if not s.airborne else 0.0
	var w_lean := 9.0
	_lean_v += (w_lean * w_lean * (lean_t - _lean) - 2.0 * w_lean * _lean_v) * dt
	_lean = clampf(_lean + _lean_v * dt, -0.9, 0.9)
	var L := Transform3D(root.basis * Basis(Vector3(0, 0, 1), -_lean), root.origin)
	# upper body faces the direction of travel: when the skis pivot underneath, the torso lags
	# behind instead of snapping, and it counter-rotates slightly toward the outside of the turn
	var torso_t := 0.0
	if not s.airborne and s.speed > 1.5:
		# hockey stop: the skis pivot underneath while the upper body keeps facing downhill
		var lim := lerpf(0.7, 1.3, maxf(s.edge_brake, 1.0 if s.grind_slide and s.is_grinding() else 0.0))
		torso_t = clampf(wrapf(s.travel_yaw - s.heading, -PI, PI), -lim, lim) * lerpf(0.75, 0.9, s.edge_brake) + _lean * 0.22
	# winding up for a spin: shoulders coil against the spin (Left held -> shoulders left -> right 360)
	torso_t += s.wind * 0.55
	# in the air the head and shoulders lead the spin and the hips follow
	if s.airborne:
		torso_t -= clampf(s.spin_vel * 0.09, -0.6, 0.6)
	var w_t := 7.0
	_torso_yaw_v += (w_t * w_t * (torso_t - _torso_yaw) - 2.0 * w_t * _torso_yaw_v) * dt
	_torso_yaw = clampf(_torso_yaw + _torso_yaw_v * dt, -0.9, 0.9)
	var turn_amt := absf(_lean)

	# ---- targets
	var tuck := _sm("tuck", s.tuck, 6.0, dt)
	var brake := _sm("brake", 0.0, 6.0, dt)
	var edgeb := _sm("edgeb", s.edge_brake, 9.0, dt)
	# hockey stop entry: a quick unweighting "pop", then down into a low, flexed stance
	if s.edge_brake > 0.05 and _prev_edgeb <= 0.05:
		_stop_pop = 1.0
	_prev_edgeb = s.edge_brake
	_stop_pop = maxf(_stop_pop - dt * 5.0, 0.0)
	var gear := sin(clampf(s.gear_anim, 0.0, 1.0) * PI)
	var air := 1.0 if s.airborne else 0.0
	var gl := _sm("grab_l", s.grab_l, 10.0, dt)
	var gr := _sm("grab_r", s.grab_r, 10.0, dt)
	var grab := maxf(gl, gr)
	var ph := 0.86 - 0.22 * tuck - 0.24 * s.charge - 0.30 * s.compression + _absorb - 0.15 * edgeb + 0.07 * _stop_pop - 0.3 * gear
	# flex through the turn, extend through the edge change (pelvis rises as the lean passes zero)
	ph -= 0.12 * turn_amt
	# double-pole push: reach forward, plant, crunch and drive the arms back past the hips, recover
	_push_amt = lerpf(_push_amt, 1.0 if s.pushing > 0.5 else 0.0, 1.0 - exp(-8.0 * dt))
	_push_ph = s.push_phase
	var drive := _push_drive()                       # 0 at the reach, 1 at the end of the push
	ph = lerpf(ph, 0.88 - 0.10 * drive, _push_amt)
	ph = _sm("pelvis_h", ph, 14.0, dt)
	# weight shift: forward drives the shins and chest over the tips, back sits on the tails
	var lf := s.lean_fa
	var pz := _sm("pelvis_z", 0.06 + 0.10 * tuck + 0.05 * s.charge + 0.05 * edgeb + 0.13 * maxf(-lf, 0.0) - 0.05 * maxf(lf, 0.0), 10.0, dt)
	var pitch := deg_to_rad(27.0 + 38.0 * tuck + 22.0 * s.charge + 25.0 * s.compression + 32.0 * grab * air + 4.0 * edgeb + 30.0 * gear + 12.0 * lf * (1.0 - air))
	pitch += deg_to_rad(8.0 + 40.0 * drive) * _push_amt
	# grab pose: the preview, or the live grab while airborne; blends in/out with the hold
	var live := s.grab_name if s.airborne and (s.grab_l > 0.3 or s.grab_r > 0.3) else ""
	var want := preview_grab if preview_grab != "" else live
	if want != "":
		if _ag != "" and want != _ag and preview_grab == "":
			_gw *= 0.6                      # switching grabs: ease out of the old one, into the new
		_ag = want
	_gw = 1.0 if preview_grab != "" else lerpf(_gw, 1.0 if want != "" else 0.0, 1.0 - exp(-7.0 * dt))
	if _gw < 0.01:
		_ag = ""
	if GRAB_POSES.has(_ag):
		if not _solved.has(_ag):
			_solved[_ag] = _solve_grab(_ag, 0.86, 0.06)
		pitch = lerpf(pitch, deg_to_rad(float(_solved[_ag]["pitch"])), _gw)
	pitch = _sm("pitch", pitch, 10.0, dt) + deg_to_rad(45.0) * _p["ftuck"]
	# angulation: legs take the full inclination, the torso stays much more upright
	var counter := _lean * 0.58
	var plow := _sm("plow", 0.0, 8.0, dt)
	# flips stay laid out (long body); holding tuck pulls the knees in
	var ftuck := _sm("ftuck", s.flip_tuck if s.airborne else 0.0, 9.0, dt)
	var feet_up := _sm("feet_up", air * (0.05 + 0.26 * grab + 0.42 * ftuck), 8.0, dt)
	# layout flip: body long from the shoulders to the knees, knees bent so the shins and skis fold
	# back behind the thighs and the skis run parallel to the body; opens up again to land
	var near_land := absf(roundf(s.air_pitch / TAU) * TAU - s.air_pitch) < deg_to_rad(55.0) and absf(s.air_pitch) > PI
	var lay_t := air * smoothstep(1.2, 2.5, absf(s.flip_vel)) * (0.0 if near_land else 1.0) * (1.0 - ftuck)
	if absf(s.air_pitch) < deg_to_rad(25.0):
		lay_t *= absf(s.air_pitch) / deg_to_rad(25.0)
	var layout := _sm("layout", lay_t, 7.0, dt)
	var arms_air := _sm("arms_air", air * (1.0 - grab), 5.0, dt)

	# ---- feet / skis
	var stance := 0.115 + 0.05 * turn_amt + 0.05 * edgeb
	var fwd_off := 0.02
	for side: float in [-1.0, 1.0]:
		# the inside ski leads a little (right turn: right ski ahead)
		var lead := (-0.12 * side * _lean) if not s.airborne else 0.0
		var foot_local := Vector3(side * stance, feet_up, fwd_off + lead)
		# folded leg: ankle behind the knee at knee height, ski sole facing back
		foot_local = foot_local.lerp(Vector3(side * 0.11, 0.40, 0.40 + ANKLE_H), layout)
		var gp: Dictionary = GRAB_POSES.get(_ag, {})
		var sd_key := "l" if side < 0.0 else "r"
		var fk := []
		if not gp.is_empty():
			var hip_local := Vector3(side * HIP_HALF, ph - 0.04, pz)
			fk = _leg_fk(hip_local, side, _solved[_ag]["legs"][sd_key])
			foot_local = foot_local.lerp(fk[2], _gw)
			_fk["hip_" + sd_key] = L * hip_local
			_fk["knee_" + sd_key] = L * (fk[0] as Vector3)
		var foot := L * foot_local
		if not s.airborne:
			# both skis stay on the snow: raise/lower each foot onto the ground plane
			var dy := (foot - root.origin).dot(up)
			var lup := L.basis.y
			foot -= lup * (dy / maxf(lup.dot(up), 0.3))
		var yaw := plow * side
		var sb := L.basis * Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), -PI * 0.5 * layout)
		if not gp.is_empty():
			sb = sb.orthonormalized().slerp((L.basis * (fk[1] as Basis)).orthonormalized(), _gw)
		if not s.airborne:
			# pitch each ski to the snow under its own tip and tail (uneven ground)
			var tip := foot - sb.z * 0.85
			var tail := foot + sb.z * 0.85
			var dh := s.terrain.height(tip.x, tip.z) - s.terrain.height(tail.x, tail.z)
			var plane := tip.y - tail.y
			var pitch_fix := clampf(atan2(dh - plane, 1.7), -0.35, 0.35)
			sb = Basis(sb.x, pitch_fix) * sb
		if not s.airborne:
			# chatter: skis vibrate on hard snow at speed and when they skid or land
			var ch := _sm("chatter", clampf(s.speed / 22.0, 0.0, 1.0) * (0.25 + s.skid) + s.compression * 0.6, 12.0, dt)
			var ph2 := s.time * 61.0 + side * 1.7
			sb = Basis(sb.x, sin(ph2) * 0.012 * ch) * Basis(sb.z, sin(ph2 * 1.37) * 0.015 * ch) * sb
			# never let the base or an edge dip into the snow: lift the ski onto the highest of
			# tip, middle and tail on both edges (+1.5 cm so the ski reads as sitting on top)
			var lift := 0.0
			for zz: float in [-0.8, 0.0, 0.7]:
				for xx: float in [-0.06, 0.06]:
					var q := foot + sb * Vector3(xx, 0.0, zz)
					lift = maxf(lift, s.terrain.height(q.x, q.z) + 0.015 - q.y)
			foot += up * lift
		var ski_xf := Transform3D(sb, foot)
		if side < 0.0:
			ski_l = ski_xf
			boot_l = sb
		else:
			ski_r = ski_xf
			boot_r = sb
		joints["ankle_" + ("l" if side < 0.0 else "r")] = foot + sb.y * ANKLE_H + sb.z * 0.03

	# ---- pelvis & hips
	var pelvis := L * Vector3(0.0, ph, pz)
	joints["pelvis"] = pelvis
	var gpt: Dictionary = _solved.get(_ag, {})
	var g_twist := float(gpt.get("twist", 0.0)) * _gw
	var g_side := float(gpt.get("side", 0.0)) * _gw
	var tb := L.basis * Basis(Vector3.UP, _torso_yaw + g_twist) * Basis(Vector3(0, 0, 1), counter + g_side) * Basis(Vector3(1, 0, 0), -pitch)
	torso_basis = tb.orthonormalized()
	var hip_basis := (L.basis * Basis(Vector3.UP, _torso_yaw * 0.45) * Basis(Vector3(0, 0, 1), counter * 0.3)).orthonormalized()
	var max_leg := (THIGH + SHIN) * 0.985
	for sd in ["l", "r"]:
		var sgn := -1.0 if sd == "l" else 1.0
		var hip := pelvis + hip_basis.x * (sgn * HIP_HALF) - hip_basis.y * 0.04
		var ank: Vector3 = joints["ankle_" + sd]
		var d := ank - hip
		if d.length() > max_leg:
			# keep feet planted: pull the hip toward the ankle instead of stretching the leg
			hip = ank - d.normalized() * max_leg
		joints["hip_" + sd] = hip
		var pole_dir := L.basis * Vector3(sgn * 0.25, 0.0, -1.0)
		var pole_pt := hip + pole_dir
		if GRAB_POSES.has(_ag) and _fk.has("knee_" + sd):
			# knees point where the hip rotation puts them (the grab's joint angles)
			var fkk: Vector3 = _fk["knee_" + sd]
			pole_pt = pole_pt.lerp(fkk + (fkk - (hip + ank) * 0.5), _gw)
		joints["knee_" + sd] = ik2(hip, ank, THIGH, SHIN, pole_pt)
	pelvis = (joints["hip_l"] + joints["hip_r"]) * 0.5 + hip_basis.y * 0.04
	joints["pelvis"] = pelvis
	var waist := pelvis + tb.y * 0.07
	joints["waist"] = waist
	var chest := waist + tb.y * TORSO_LEN
	joints["chest"] = chest
	# head keeps the eyes level and looks into the turn
	var hb := tb * Basis(Vector3.UP, -_lean * 0.35) * Basis(Vector3(0, 0, 1), _lean * 0.3) * Basis(Vector3(1, 0, 0), pitch * 0.8 - deg_to_rad(6.0))
	head_basis = hb.orthonormalized()
	joints["head"] = chest + hb.y * 0.19
	# ---- arms
	var plant_side := _update_pole_plant(dt)
	for sd in ["l", "r"]:
		var sgn := -1.0 if sd == "l" else 1.0
		var sh := chest - tb.y * 0.07 + tb.x * (sgn * SHOULDER_HALF)
		joints["shoulder_" + sd] = sh
		var hand_local := Vector3(sgn * 0.13, -0.38, -0.30)
		# inside hand forward and up, outside hand lower and back (balance through the turn)
		var inside := clampf(sgn * _lean / 0.6, -1.0, 1.0) * (1.0 - air)
		hand_local += Vector3(0.0, 0.06, -0.10) * inside
		hand_local = hand_local.lerp(Vector3(sgn * 0.10, -0.32, -0.42), tuck)
		hand_local = hand_local.lerp(Vector3(sgn * 0.27, -0.30, -0.42), edgeb)
		hand_local = hand_local.lerp(Vector3(sgn * 0.42, -0.22, -0.14), arms_air)
		hand_local = hand_local.lerp(Vector3(sgn * 0.15, -0.5, -0.32), ftuck)   # tucked flip: hands to the shins
		hand_local = hand_local.lerp(Vector3(sgn * 0.40, -0.05, -0.05), layout * 0.6)  # layout: arms wide
		if _push_amt > 0.02:
			# reach: hands forward at chest height -> push: driven down and back past the hips
			var reach_p := Vector3(sgn * 0.19, -0.06, -0.6)          # arms out in front, nearly straight
			var end_p := Vector3(sgn * 0.22, -0.55, 0.26)            # driven back past the hips
			var hp := reach_p.lerp(end_p, drive)
			if _push_ph > 0.65:
				hp += Vector3(0.0, 0.12, 0.0) * sin((_push_ph - 0.65) / 0.35 * PI)  # swing back through, up
			hand_local = hand_local.lerp(hp, _push_amt)
		if plant_side == sgn:
			hand_local = hand_local.lerp(Vector3(sgn * 0.16, -0.34, -0.48), _pole_plant)
		if s.is_grinding():
			# arms out for balance on a rail, swaying with it
			hand_local = hand_local.lerp(Vector3(sgn * 0.48, -0.12 + 0.12 * sgn * s.rail_balance, -0.2), 0.85)
		if s.sketchy > 0.0:
			# close call: arms windmill to catch the balance
			var a := s.time * 13.0 + (0.0 if sgn > 0.0 else PI)
			hand_local = hand_local.lerp(Vector3(sgn * 0.5, -0.05 + 0.25 * sin(a), -0.15 + 0.25 * cos(a)), clampf(s.sketchy / 0.3, 0.0, 1.0))
		# loose arms: hands follow their target through a spring, a beat behind the body
		var hv: Vector3 = _hands.get(sd + "_v", Vector3.ZERO)
		var hc: Vector3 = _hands.get(sd, hand_local)
		hv += (196.0 * (hand_local - hc) - 28.0 * hv) * dt
		hc += hv * dt
		_hands[sd] = hc
		_hands[sd + "_v"] = hv
		var hand := sh + tb * hc
		var g := gl if sd == "l" else gr
		var gpose: Dictionary = GRAB_POSES.get(_ag, {})
		if not gpose.is_empty():
			g = _gw if gpose.has(sd) else 0.0
			if gpose.has("free") and gpose["free"].has(sd):
				hand = hand.lerp(sh + tb * (gpose["free"][sd] as Vector3), _gw)   # the free arm styles it out
		if g > 0.01 and gpose.has(sd):
			var spec: Array = gpose[sd]
			var gs := -1.0 if spec[0] == "l" else 1.0
			var sx2: Transform3D = ski_l if spec[0] == "l" else ski_r
			hand = hand.lerp(sx2.origin + sx2.basis * Vector3(gs * 0.07 * float(spec[2]), 0.05, float(spec[1])), g)
			grab_gap[sd] = maxf((hand - sh).length() - (UPPER_ARM + FOREARM), 0.0)
		elif g > 0.01:
			var sxf := ski_l if sd == "l" else ski_r
			var kind := s.grab_kind_l if sd == "l" else s.grab_kind_r
			var along := {"tip": -0.72, "tail": 0.62}.get(kind, -0.12) as float
			var grab_pt := sxf.origin + sxf.basis * Vector3(sgn * 0.07, 0.10, along)
			hand = hand.lerp(grab_pt, g)
		var elbow_pole := sh + tb * Vector3(sgn * 0.5, -0.2, 0.45)
		var el := ik2(sh, hand, UPPER_ARM, FOREARM, elbow_pole)
		joints["elbow_" + sd] = el
		var reach := (hand - sh).length()
		if reach > UPPER_ARM + FOREARM:
			hand = sh + (hand - sh).normalized() * (UPPER_ARM + FOREARM)
		joints["hand_" + sd] = hand
		# pole direction
		var pd := Vector3(sgn * 0.08, -0.62, 0.78)
		pd = pd.lerp(Vector3(sgn * 0.08, 0.25, 1.0), tuck)
		pd = pd.lerp(Vector3(sgn * 0.45, -0.55, 0.7), arms_air)
		pd = pd.lerp(Vector3(sgn * 0.3, -0.8, 0.45), edgeb)
		if plant_side == sgn:
			pd = pd.lerp(Vector3(sgn * 0.1, -0.96, -0.15), _pole_plant)
		var planted := false
		if _push_amt > 0.5 and not s.airborne and _push_ph > 0.22 and _push_ph < 0.68:
			# plant: the tip goes into the snow just behind the hand, then stays put while the
			# skier slides past it and the arms drive back
			if not _pole_tip.has(sd):
				var fw := -L.basis.z
				fw = Vector3(fw.x, 0.0, fw.z).normalized()
				var gnd := s.terrain.height(hand.x, hand.z)
				var hh := maxf(hand.y - gnd, 0.1)
				var back := sqrt(maxf(POLE_LEN * POLE_LEN - hh * hh, 0.04))
				var tip := hand - fw * back * 0.6 + L.basis.x * (sgn * 0.08)
				tip.y = s.terrain.height(tip.x, tip.z) - 0.04
				_pole_tip[sd] = tip
			var tipw: Vector3 = _pole_tip[sd]
			var tg := hand - tipw
			if absf(tg.length() - POLE_LEN) > 0.001:     # the hand stays on the grip of a planted pole
				hand = tipw + tg.normalized() * POLE_LEN
				joints["hand_" + sd] = hand
				joints["elbow_" + sd] = ik2(sh, hand, UPPER_ARM, FOREARM, elbow_pole)
			planted = true
		else:
			_pole_tip.erase(sd)
		if _push_amt > 0.02 and not planted:
			# recovery: poles swing forward, baskets trailing, ready for the next plant
			var rt := (_push_ph + 0.32) / 0.54 if _push_ph < 0.22 else (_push_ph - 0.68) / 0.54
			var swing := Vector3(sgn * 0.05, -0.4, 0.92).lerp(Vector3(sgn * 0.06, -0.96, 0.25), smoothstep(0.0, 1.0, clampf(rt, 0.0, 1.0)))
			pd = pd.lerp(swing, _push_amt)
		if g > 0.01:
			pd = pd.lerp(Vector3(sgn * 0.6, 0.2, 0.7), g)
		joints["pole_dir_" + sd] = (tb * pd).normalized()
		if planted:
			joints["pole_dir_" + sd] = (_pole_tip[sd] - hand).normalized()
		joints["pole_grip_" + sd] = hand - joints["pole_dir_" + sd] * 0.06


## Push stroke progress: quick reach (0->0.25), long drive (0.25->0.65), relaxed recovery back.
func _push_drive() -> float:
	var p := _push_ph
	if p < 0.25:
		return 0.0
	if p < 0.65:
		return smoothstep(0.25, 0.65, p)
	return 1.0 - smoothstep(0.65, 1.0, p)


# ------------------------------------------------------------------ on foot
## Walking / hiking in ski boots, skis over the right shoulder, both poles in the left hand.
func _compute_walk(dt: float) -> void:
	var s := skier
	var root := s.visual_xform()
	var B := root.basis
	var o := root.origin
	var up := Vector3.UP
	var fwd := -B.z
	var right := B.x
	var move := clampf(s.speed / 1.0, 0.0, 1.0)
	var jog := clampf((s.speed - Skier.WALK_SPEED) / (Skier.JOG_SPEED - Skier.WALK_SPEED), 0.0, 1.0)
	var ph := s.walk_phase
	var stride := lerpf(0.22, 0.36, jog) * move
	var lift_h := lerpf(0.10, 0.17, jog) * move
	var dip := sin(clampf(s.gear_anim, 0.0, 1.0) * PI)
	# grade along the walking direction: lean into the hill when hiking up
	var g := s.terrain.height(o.x + fwd.x * 0.8, o.z + fwd.z * 0.8) - s.terrain.height(o.x - fwd.x * 0.8, o.z - fwd.z * 0.8)
	var grade := atan2(g, 1.6)
	_lean = lerpf(_lean, 0.0, 1.0 - exp(-8.0 * dt))
	_lean_v = 0.0
	_torso_yaw = lerpf(_torso_yaw, 0.0, 1.0 - exp(-8.0 * dt))
	# feet: alternate swing / stance, heel-to-toe pitch
	var ground_y := 0.0
	for side: float in [-1.0, 1.0]:
		var phi := ph + (0.0 if side < 0.0 else PI)
		var swing := maxf(cos(phi), 0.0)
		var foot := o + right * (side * 0.11) + fwd * (sin(phi) * stride + 0.03)
		var gy := s.terrain.height(foot.x, foot.z)
		ground_y += gy * 0.5
		foot.y = gy + swing * lift_h
		var fb := Basis(right, -0.5 * swing * move + grade * 0.6) * B
		var ank := foot + up * ANKLE_H
		joints["ankle_" + ("l" if side < 0.0 else "r")] = ank
		if side < 0.0:
			boot_l = fb
		else:
			boot_r = fb
	# pelvis: bobs twice per cycle, sinks when bending down to the bindings
	var bob := (1.0 - cos(2.0 * ph)) * 0.5 * lerpf(0.03, 0.05, jog) * move
	var pel_h := 1.03 - 0.05 * jog - bob - 0.36 * dip
	var pelvis := Vector3(o.x, maxf(ground_y, o.y) + pel_h, o.z) + fwd * (0.04 + 0.05 * jog)
	var pitch := deg_to_rad(5.0 + 10.0 * jog + 45.0 * dip) + maxf(grade, 0.0) * 0.7
	var twist := 0.10 * sin(ph) * move
	var tb := (B * Basis(Vector3.UP, twist) * Basis(Vector3(1, 0, 0), -pitch)).orthonormalized()
	torso_basis = tb
	var hip_basis := (B * Basis(Vector3.UP, -twist * 0.6)).orthonormalized()
	var max_leg := (THIGH + SHIN) * 0.985
	for sd in ["l", "r"]:
		var sgn := -1.0 if sd == "l" else 1.0
		var hip := pelvis + hip_basis.x * (sgn * HIP_HALF) - hip_basis.y * 0.04
		var ank: Vector3 = joints["ankle_" + sd]
		var d := ank - hip
		if d.length() > max_leg:
			hip = ank - d.normalized() * max_leg
		joints["hip_" + sd] = hip
		joints["knee_" + sd] = ik2(hip, ank, THIGH, SHIN, hip + fwd + right * (sgn * 0.15))
	pelvis = (joints["hip_l"] + joints["hip_r"]) * 0.5 + hip_basis.y * 0.04
	joints["pelvis"] = pelvis
	var waist := pelvis + tb.y * 0.07
	joints["waist"] = waist
	var chest := waist + tb.y * TORSO_LEN
	joints["chest"] = chest
	var hb := (B * Basis(Vector3(1, 0, 0), -0.08 + maxf(grade, 0.0) * 0.3)).orthonormalized()
	head_basis = hb
	joints["head"] = chest + hb.y * 0.19
	# arms: right hand steadies the skis on the shoulder, left arm swings with the poles
	var swing_l := sin(ph + PI) * lerpf(0.16, 0.26, jog) * move
	for sd in ["l", "r"]:
		var sgn := -1.0 if sd == "l" else 1.0
		var sh := chest - tb.y * 0.07 + tb.x * (sgn * SHOULDER_HALF)
		joints["shoulder_" + sd] = sh
		var hand: Vector3
		if sd == "r":
			hand = sh + tb * Vector3(-0.02, 0.12, -0.22)
		else:
			hand = sh + tb * Vector3(-0.12, -0.50, -0.06 - swing_l)
		hand = hand.lerp(sh + tb * Vector3(sgn * 0.12, -0.55, -0.35), dip)
		joints["elbow_" + sd] = ik2(sh, hand, UPPER_ARM, FOREARM, sh + tb * Vector3(sgn * 0.5, -0.3, 0.4))
		if (hand - sh).length() > UPPER_ARM + FOREARM:
			hand = sh + (hand - sh).normalized() * (UPPER_ARM + FOREARM)
		joints["hand_" + sd] = hand
	# both poles in the left hand, used like a hiking stick
	var hl: Vector3 = joints["hand_l"]
	var pdir := (B * Vector3(-0.06, -0.97, 0.10 - swing_l * 0.6)).normalized()
	for sd in ["l", "r"]:
		joints["pole_dir_" + sd] = pdir
		joints["pole_grip_" + sd] = hl - pdir * 0.06 + right * (0.02 if sd == "r" else -0.02)
	# skis on the right shoulder: bases together, tips forward and down
	var shr: Vector3 = joints["shoulder_r"]
	var sb := (tb * Basis(Vector3(1, 0, 0), -0.42) * Basis(Vector3(0, 0, 1), PI * 0.5)).orthonormalized()
	var center := shr + tb.y * 0.09 + tb.x * 0.02 + fwd * 0.05
	if dip > 0.5:
		# mid transition: skis still on the snow beside the boots
		center = Vector3(o.x, ground_y, o.z) + right * 0.35
		sb = B
	ski_l = Transform3D(sb, center + sb.y * 0.012)
	ski_r = Transform3D(sb, center - sb.y * 0.012)


# ------------------------------------------------------------------ chairlift
func _compute_seated(dt: float) -> void:
	var s := skier
	var root := s.visual_xform()
	var B := root.basis
	var o := root.origin
	var up := B.y
	var fwd := -B.z
	var right := B.x
	_lean = 0.0
	_lean_v = 0.0
	_torso_yaw = 0.0
	var t := s.time
	var pelvis := o + up * 0.13 - fwd * 0.08
	var tb := (B * Basis(Vector3(1, 0, 0), 0.10)).orthonormalized()
	torso_basis = tb
	var dangle := sin(t * 1.3) * 0.05
	for sd in ["l", "r"]:
		var sgn := -1.0 if sd == "l" else 1.0
		var hip := pelvis + right * (sgn * HIP_HALF) - up * 0.04
		joints["hip_" + sd] = hip
		var knee := hip + fwd * 0.42 + up * 0.03 + right * (sgn * 0.03)
		joints["knee_" + sd] = knee
		var ank := knee + fwd * (0.12 + dangle * sgn) - up * 0.40
		joints["ankle_" + sd] = ank
		var sb := (B * Basis(Vector3(1, 0, 0), -0.32 + dangle * sgn)).orthonormalized()
		var xf := Transform3D(sb, ank - sb.y * ANKLE_H - sb.z * 0.03)
		if sd == "l":
			ski_l = xf
			boot_l = sb
		else:
			ski_r = xf
			boot_r = sb
	joints["pelvis"] = pelvis
	var waist := pelvis + tb.y * 0.07
	joints["waist"] = waist
	var chest := waist + tb.y * TORSO_LEN
	joints["chest"] = chest
	# looking around at the view
	var look := 0.55 * sin(t * 0.21) + 0.2 * sin(t * 0.67)
	var hb := (tb * Basis(Vector3.UP, look) * Basis(Vector3(1, 0, 0), -0.12 + 0.08 * sin(t * 0.37))).orthonormalized()
	head_basis = hb
	joints["head"] = chest + hb.y * 0.19
	for sd in ["l", "r"]:
		var sgn := -1.0 if sd == "l" else 1.0
		var sh := chest - tb.y * 0.07 + tb.x * (sgn * SHOULDER_HALF)
		joints["shoulder_" + sd] = sh
		var knee: Vector3 = joints["knee_" + sd]
		var hand := knee - fwd * 0.14 + up * 0.11 + right * (sgn * 0.02)
		joints["elbow_" + sd] = ik2(sh, hand, UPPER_ARM, FOREARM, sh + right * (sgn * 0.5) - fwd * 0.3)
		joints["hand_" + sd] = hand
		var pdir := (fwd * 0.35 - up * 0.9 + right * (sgn * 0.05)).normalized()
		joints["pole_dir_" + sd] = pdir
		joints["pole_grip_" + sd] = hand - pdir * 0.06


func _update_pole_plant(dt: float) -> float:
	var s := skier
	var sgn := signf(s.steer) if absf(s.steer) > 0.35 else 0.0
	if sgn != 0.0 and sgn != _last_steer_sign and not s.airborne and s.speed > 2.0 and s.speed < 22.0 and s.tuck < 0.3:
		_pole_plant = 1.0
		_plant_side = sgn
	if sgn != 0.0:
		_last_steer_sign = sgn
	_pole_plant = maxf(_pole_plant - dt * 2.6, 0.0)
	return _plant_side if _pole_plant > 0.0 else 0.0


static func ik2(a: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var d := target - a
	var dist := clampf(d.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := d.normalized() if d.length() > 0.0001 else Vector3.DOWN
	var c := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var bend := pole - a
	bend = bend - dir * bend.dot(dir)
	if bend.length() < 0.0001:
		bend = dir.cross(Vector3.RIGHT)
	bend = bend.normalized()
	return a + dir * (l1 * c) + bend * (l1 * sqrt(1.0 - c * c))


# ------------------------------------------------------------------ ragdoll
func _start_ragdoll() -> void:
	if not joints.has("ankle_r"):
		_compute_pose(0.016)
	in_ragdoll = true
	var v := skier.vel
	ski_detached = v.length() > 11.0
	ragdoll.start(joints, ski_l, ski_r, v, ski_detached)


func _pose_from_ragdoll() -> void:
	var f := Engine.get_physics_interpolation_fraction()
	for k in ragdoll.names:
		joints[k] = ragdoll.get_pos(k, f)
	var j_chest: Vector3 = joints["chest"]
	var j_pelvis: Vector3 = joints["pelvis"]
	var j_shr: Vector3 = joints["shoulder_r"]
	var j_shl: Vector3 = joints["shoulder_l"]
	var j_head: Vector3 = joints["head"]
	var up := (j_chest - j_pelvis).normalized()
	var right := (j_shr - j_shl).normalized()
	var fwd := right.cross(up).normalized()
	right = up.cross(fwd).normalized()
	torso_basis = Basis(right, up, -fwd).orthonormalized()
	var hup := (j_head - j_chest).normalized()
	head_basis = Basis(right, hup, right.cross(hup).normalized() * -1.0).orthonormalized()
	joints["waist"] = j_pelvis + torso_basis.y * 0.07
	for sd in ["l", "r"]:
		var sgn := -1.0 if sd == "l" else 1.0
		joints["pole_dir_" + sd] = ragdoll.pole_dir(sd)
		joints["pole_grip_" + sd] = joints["hand_" + sd] - joints["pole_dir_" + sd] * 0.06
	ski_l = ragdoll.ski_xform("l", f)
	ski_r = ragdoll.ski_xform("r", f)
	boot_l = ski_l.basis
	boot_r = ski_r.basis


# ------------------------------------------------------------------ mesh placement
func _seg(name: String, a: Vector3, b: Vector3, side_hint: Vector3) -> void:
	var mi: MeshInstance3D = parts[name]
	var y := b - a
	var length := y.length()
	if length < 0.0001:
		return
	y /= length
	var x := side_hint - y * side_hint.dot(y)
	if x.length() < 0.001:
		x = y.cross(Vector3.FORWARD)
	x = x.normalized()
	var z := x.cross(y).normalized()
	mi.global_transform = Transform3D(Basis(x, y, z), a)


func _apply_parts() -> void:
	# skis bend under load (landings, crouching on the tails) and spring back in the air
	var bend := clampf(skier.compression * 1.2 + skier.tail_load * 0.6 + skier.charge * 0.3, 0.0, 1.2)
	if skier.airborne:
		bend = -0.15
	for sd in ["l", "r"]:
		(parts["ski_" + sd].material_override as ShaderMaterial).set_shader_parameter("bend", bend)
	var tb := torso_basis
	parts["pelvis"].global_transform = Transform3D(tb, joints["pelvis"])
	parts["torso"].global_transform = Transform3D(tb, joints["waist"])
	parts["stripe"].global_transform = Transform3D(tb, joints["waist"] + tb.y * 0.27)
	parts["collar"].global_transform = Transform3D(tb, joints["chest"] - tb.y * 0.02)
	parts["hood"].global_transform = Transform3D(tb, joints["chest"] - tb.y * 0.07 + tb.z * 0.05)
	parts["hood_rim"].global_transform = Transform3D(tb * Basis(Vector3(1, 0, 0), -0.35), joints["chest"] + tb.y * 0.075 + tb.z * 0.1)
	parts["backpack"].global_transform = Transform3D(tb, joints["waist"] + tb.y * 0.16 + tb.z * 0.11)
	parts["neck"].global_transform = Transform3D(head_basis, joints["chest"])
	var hb := head_basis
	var hc: Vector3 = joints["head"]
	parts["head"].global_transform = Transform3D(hb, hc)
	parts["helmet"].global_transform = Transform3D(hb, hc + hb.y * 0.015)
	parts["goggle_band"].global_transform = Transform3D(hb, hc + hb.y * 0.025)
	parts["goggle_lens"].global_transform = Transform3D(hb, hc + hb.y * 0.025)
	parts["goggle_frame"].global_transform = Transform3D(hb, hc + hb.y * 0.025)
	parts["gaiter"].global_transform = Transform3D(hb, hc)
	parts["jacket_details"].global_transform = Transform3D(tb, joints["waist"])
	parts["helmet_trim"].global_transform = Transform3D(hb, hc + hb.y * 0.015)
	parts["helmet_dark"].global_transform = Transform3D(hb, hc + hb.y * 0.015)
	for sd in ["l", "r"]:
		var sgn := -1.0 if sd == "l" else 1.0
		var side_x := tb.x * sgn
		_seg("uarm_" + sd, joints["shoulder_" + sd], joints["elbow_" + sd], tb.x)
		_seg("farm_" + sd, joints["elbow_" + sd], joints["hand_" + sd] - (joints["hand_" + sd] - joints["elbow_" + sd]).normalized() * 0.06, tb.x)
		var farm_dir: Vector3 = (joints["hand_" + sd] - joints["elbow_" + sd]).normalized()
		_seg("cuff_" + sd, joints["hand_" + sd] - farm_dir * 0.03, joints["hand_" + sd] + farm_dir * 0.02, tb.z)
		_seg("hand_" + sd, joints["hand_" + sd] - farm_dir * 0.03, joints["hand_" + sd] + farm_dir * 0.05, tb.z)
		var hxf: Transform3D = parts["hand_" + sd].global_transform
		parts["thumb_" + sd].global_transform = Transform3D(hxf.basis * Basis(Vector3(0, 0, 1), 0.5 * sgn), hxf.origin + hxf.basis * Vector3(-0.04, 0.04, 0.0))
		var sxf: Transform3D = ski_l if sd == "l" else ski_r
		_seg("thigh_" + sd, joints["hip_" + sd], joints["knee_" + sd], tb.x)
		var txf: Transform3D = parts["thigh_" + sd].global_transform
		parts["pocket_" + sd].global_transform = Transform3D(txf.basis, txf.origin + txf.basis * Vector3(sgn * 0.108, 0.24, 0.0))
		parts["knee_cap_" + sd].global_transform = Transform3D(tb, joints["knee_" + sd])
		parts["elbow_cap_" + sd].global_transform = Transform3D(tb, joints["elbow_" + sd])
		parts["shoulder_cap_" + sd].global_transform = Transform3D(tb, joints["shoulder_" + sd])
		var bb: Basis = boot_l if sd == "l" else boot_r
		parts["stack_" + sd].global_transform = Transform3D(bb, joints["ankle_" + sd] + bb.y * 0.1)
		_seg("shin_" + sd, joints["knee_" + sd], joints["ankle_" + sd], tb.x)
		parts["boot_" + sd].global_transform = Transform3D(boot_l if sd == "l" else boot_r, joints["ankle_" + sd])
		var bxf := Transform3D((boot_l if sd == "l" else boot_r) * Basis(Vector3(1, 0, 0) if sd == "r" else Vector3(1, 0, 0), 0.0) * (Basis.FLIP_X if sd == "l" else Basis.IDENTITY), joints["ankle_" + sd])
		parts["buckles_" + sd].global_transform = bxf
		parts["bootstrap_" + sd].global_transform = Transform3D(boot_l if sd == "l" else boot_r, joints["ankle_" + sd])
		var ski_center := sxf.origin + sxf.basis.z * 0.02
		if in_ragdoll and ski_detached:
			ski_center = sxf.origin
		parts["ski_" + sd].global_transform = Transform3D(sxf.basis, ski_center)
		parts["bind_" + sd].global_transform = Transform3D(sxf.basis, ski_center)
		var pdir: Vector3 = joints["pole_dir_" + sd]
		var grip_pos: Vector3 = joints.get("pole_grip_" + sd, joints["hand_" + sd] - pdir * 0.06)
		var pb := _basis_y(pdir, tb.x)
		parts["pole_" + sd].global_transform = Transform3D(pb, grip_pos)
		parts["grip_" + sd].global_transform = Transform3D(pb, grip_pos)
		parts["basket_" + sd].global_transform = Transform3D(pb, grip_pos)


static func _basis_y(y: Vector3, hint: Vector3) -> Basis:
	y = y.normalized()
	var x := hint - y * hint.dot(y)
	if x.length() < 0.001:
		x = y.cross(Vector3.FORWARD)
	x = x.normalized()
	return Basis(x, y, x.cross(y).normalized())


func set_first_person(on: bool) -> void:
	for mi in head_parts:
		mi.visible = not on
