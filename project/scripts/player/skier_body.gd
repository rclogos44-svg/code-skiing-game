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
const PALM := 0.06         # wrist joint to the middle of the glove's palm: a grab holds the ski there
const HIP_HALF := 0.095
const SHOULDER_HALF := 0.185
const TORSO_LEN := 0.47
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
var _pole_tip := {}
var _pole_dir_s := {}
var _pole_done := {}          # this stroke's plant is over for that pole (it reached the end of the arm)         # smoothed pole directions (no snapping when a pole leaves the snow)           # planted pole tips (world) during the drive
const POLE_LEN := 1.12
var _hands := {}
## Grab poses (preview; not wired to input yet).  Legs are driven ONLY by joint angles inside
## human limits; the ski is locked to the shin by the boot, so where the ski points follows from
## the hip and knee.  Per leg [hip flexion, hip abduction (+ out, - across), hip internal rotation,
## knee flexion] in degrees.  Per hand [ski, along the ski (-tip / +tail, m), edge +1 out / -1 in].
## "free": where the other hand goes (torso frame).  "pitch"/"twist"/"side": spine (deg / rad).
## Optional 5th leg angle "ankle": boot flex on top of BOOT_LEAN (a ski boot gives ~15 deg forward,
## very little back).
const LEG_LIMITS := {"flex": [-15.0, 125.0], "abd": [-25.0, 45.0], "rot": [-40.0, 40.0], "knee": [0.0, 140.0], "ankle": [-5.0, 15.0]}
const BOOT_LEAN := 15.0        # shin leans this far forward of the boot's up axis (deg)
const GRAB_POSES := {
	# relaxed, real-world shapes: knees tucked ~90-110 deg, skis close to parallel with a light
	# tweak, a little twist toward the grab, free arm out to the side for balance
	# copied from the reference photo (mirrored to the left hand): upright spine curving toward the
	# grab, chest turned to it, left hand down the left side onto the right ski just ahead of the
	# boot, right arm straight up, knees tucked high with the skis crossed in a flat X under the
	# boots, whole body tilted off-axis
	"Mute": {"l": ["r", -0.3, 1.0], "free": {"r": Vector3(0.1, 0.56, 0.06)},
		"legs": {"l": [105.0, 15.0, 10.0, 118.0], "r": [112.0, -20.0, 25.0, 122.0]}, "pitch": 12.0, "pitch_w": 25.0, "legs_w": 0.15,
		"twist": 0.4, "side": 0.08, "curve": 0.62,
		"skis": {"yaw": {"l": 28.0, "r": -28.0}, "gap": 0.06, "stack": 0.07, "side_off": -0.15}, "hips_yaw": 0.1, "roll": -0.38,
		"time_in": 0.75},
	"Safety": {"r": ["r", -0.02, 1.0], "free": {"l": Vector3(-0.45, 0.05, -0.1)},
		"legs": {"l": [70.0, 6.0, 5.0, 100.0], "r": [88.0, 12.0, -5.0, 108.0]}, "pitch": 28.0, "twist": 0.12, "side": 0.12},
	# the ski Japan (ski glossaries / coaching: "right hand under the right knee, grabbing the left
	# ski on the inside edge under the boot"; "the opposite ski, at the back of the binding, the hand
	# passing behind the leg, often folding the grabbed leg"): the RIGHT hand goes down between the
	# legs, behind the right knee, and holds the LEFT ski's inside edge at the back of the binding;
	# the left knee folds right up so that ski is pulled up with its tail high behind him and tip
	# down in front; he crunches over the grab, chest turned to it, left arm up and back
	"Japan": {"r": ["l", 0.15, -1.0], "free": {"l": Vector3(-0.35, 0.3, 0.1)},
		"legs": {"l": [100.0, -22.0, 10.0, 140.0, 0.0], "r": [100.0, 16.0, 0.0, 100.0, 0.0]}, "pitch": 60.0, "pitch_w": 0.3, "pitch_max": 90.0,
		"legs_w": 0.4, "lock": ["abd", "rot"], "twist": 0.25, "twist_w": 6.0, "side": 0.0, "side_w": 6.0,
		"shoulders": {"r": Vector3(-0.03, -0.07, -0.06)},
		"along_range": [0.08, 0.22], "reach": 0.95, "ski_up": {"l": -30.0}, "time_in": 0.65},
	# tail grab from the reference photos: body upright (no off-axis tilt); knees bent right up so
	# the skis stand upright, tips down, out to his RIGHT side and a little behind (hips rotated in,
	# feet out); the upper back turns and leans toward them, the right shoulder drops back, he looks
	# back over it at the skis and the right hand takes the tail; left arm forward for balance
	"Tail": {"r": ["r", 0.68, 1.0], "free": {"l": Vector3(-0.12, 0.22, -0.48)},
		"legs": {"l": [30.0, 10.0, -32.0, 122.0, 5.0], "r": [30.0, -5.0, 30.0, 120.0, 5.0]}, "pitch": 12.0, "pitch_w": 6.0,
		"legs_w": 3.0, "twist": -0.55, "twist_dist": [0.1, 0.5, 1.0], "side": -0.05, "curve": -0.32, "time_in": 0.65,
		"look": 1.0, "shoulders": {"r": Vector3(0.02, -0.045, 0.08), "l": Vector3(0.0, 0.02, -0.04)}, "auto_grip": true,
		"reach": 0.95, "along_range": [0.42, 0.6], "fixed_legs": true, "side_w": 40.0, "twist_w": 6.0},
	# the hand really holds the TIP (the last ~15 cm, where it turns up): the left leg kicks out
	# forward and a little to the side, nearly straight, so the ski stands tip-up ~70 deg in front
	# and the tip comes to the hand; chest leans in a little, right arm back for balance
	"Tip": {"l": ["l", -0.8, 1.0], "free": {"r": Vector3(0.35, 0.12, 0.3)},
		"legs": {"l": [75.0, 18.0, 0.0, 10.0, 15.0], "r": [80.0, 5.0, 5.0, 105.0, 0.0]}, "pitch": 42.0, "pitch_w": 0.3,
		"legs_w": 4.0, "twist": -0.2, "side": 0.1, "along_range": [-0.86, -0.76], "reach": 0.97, "auto_grip": true, "time_in": 0.6,
		"ski_up": {"l": 60.0}},
	# truck driver = a double nose grab: each hand on the front of its own ski just ahead of the toe
	# piece, legs pushed out long in front and the skis tipped up steeply, parallel, like a steering
	# wheel in his hands (as in the halfpipe photo of a front grab with the skis held upright)
	"Truck Driver": {"l": ["l", -0.3, 1.0], "r": ["r", -0.3, 1.0],
		"legs": {"l": [80.0, 3.0, 0.0, 30.0, 5.0], "r": [80.0, 3.0, 0.0, 30.0, 5.0]}, "pitch": 40.0, "pitch_w": 0.3,
		"legs_w": 0.5, "lock": ["abd", "rot"], "twist": 0.0, "twist_w": 60.0, "side": 0.0, "side_w": 60.0,
		"along_range": [-0.45, -0.2], "reach": 0.95, "auto_grip": true, "ski_up": {"l": 65.0, "r": 65.0}, "ski_up_w": 6.0,
		"time_in": 0.6},
	# blunt = the TRUE tail: the right hand holds the very end of the right ski; that knee folds so the
	# tail comes up beside his hip, the chest turns and drops a little toward it, left arm forward
	"Blunt": {"r": ["r", 0.76, 1.0], "free": {"l": Vector3(-0.15, 0.1, -0.5)},
		"legs": {"l": [60.0, 5.0, 5.0, 100.0], "r": [45.0, 12.0, -10.0, 135.0, 5.0]}, "pitch": 20.0, "pitch_w": 0.5,
		"legs_w": 1.0, "twist": -0.35, "side": -0.1, "along_range": [0.73, 0.78], "reach": 0.95, "auto_grip": true,
		"time_in": 0.65},
}
var _grab_bend := 0.0            # extra spine bend (rad) so an out-of-reach hand gets to the ski
var grab_gap := {}
var arm_clear := {}              # arm-to-ski clearance per grabbing hand (m, < 0 = through the ski)
var _elbow_k := {}               # elbow swing chosen to keep a grabbing arm clear of the skis               # hand-to-ski distance per hand (m), for checking the poses
var _fk := {}                    # leg forward kinematics for the current grab: hip / knee per side


var _solved := {}                # grab name -> pose solved so the hand really holds the ski
const SPINE_LIMITS := {"pitch": [0.0, 70.0], "twist": [-0.7, 0.7], "side": [-0.3, 0.3]}
const NECK_YAW := 80.0            # how far the head turns on the shoulders (deg)
const NECK_PITCH := [-50.0, 35.0] # down / up (deg)


## Where the hand holds the ski (ski centre / basis): the pose's edge, or with auto_grip whichever
## edge and face is nearest the shoulder, so the arm doesn't reach through the ski to the far side.
static func grip_point(ski_c: Vector3, B: Basis, ss: float, spec: Array, sh: Vector3, auto: bool) -> Vector3:
	var along := float(spec[1])
	if not auto:
		return ski_c + B * Vector3(ss * 0.07 * float(spec[2]), 0.05, along)
	var best := ski_c
	var bd := INF
	for e in [1.0, -1.0]:
		for f in [0.05, -0.035]:
			var p: Vector3 = ski_c + B * Vector3(e * 0.07, f, along)
			if p.distance_to(sh) < bd:
				bd = p.distance_to(sh)
				best = p
	return best


## Smallest gap (m) between an arm (upper arm, and the forearm short of the gripping hand) and the
## skis, treating the arm and each ski as rounded bars; < 0 means the arm goes through a ski.
func _arm_ski_clearance(sh: Vector3, el: Vector3, hand: Vector3) -> float:
	var fa_end := hand + (el - hand).normalized() * 0.13
	var best := INF
	for sx: Transform3D in [ski_l, ski_r]:
		var a: Vector3 = sx.origin + sx.basis.z * 0.79
		var b: Vector3 = sx.origin - sx.basis.z * 0.95
		for seg in [[sh, el], [el, fa_end]]:
			var cp := Geometry3D.get_closest_points_between_segments(seg[0], seg[1], a, b)
			best = minf(best, cp[0].distance_to(cp[1]))
	return best - 0.12


## Body-frame geometry of a grab pose: returns the total hand-to-grab-point gap (m) beyond arm reach.
func _grab_gap(g: Dictionary, legs: Dictionary, sp: Array, ph: float, pz: float, al := {}) -> float:
	var total := 0.0
	for d in _grab_dists(g, legs, sp, ph, pz, al):
		total += maxf(float(d) - (UPPER_ARM + FOREARM) * 0.95, 0.0)
	return total


## Shoulder-to-grip distances (m) of the grabbing hands for a candidate pose; `al` overrides where
## along the ski each hand grips (solver variable for poses with "along_range").
func _grab_dists(g: Dictionary, legs: Dictionary, sp: Array, ph: float, pz: float, al := {}) -> Array:
	var sb3 := spine_bases(Basis(Vector3.UP, -float(g.get("hips_yaw", 0.0))), sp[2], float(g.get("curve", 0.0)), deg_to_rad(sp[0]),
		sp[1], g.get("twist_dist", [1.0, 1.0, 1.0]))
	var tb: Basis = sb3[2]
	var pelvis := Vector3(0, ph, pz)
	var chest := pelvis + (sb3[0] as Basis).y * 0.23 + (sb3[1] as Basis).y * 0.16 + tb.y * (TORSO_LEN - 0.32)
	var out := []
	for sd in ["l", "r"]:
		if not g.has(sd):
			continue
		var spec: Array = (g[sd] as Array).duplicate()
		if al.has(sd):
			spec[1] = al[sd]
		var ss := -1.0 if spec[0] == "l" else 1.0
		var fk := _leg_fk(Vector3(ss * HIP_HALF, ph - 0.04, pz), ss, legs[spec[0]])
		var B: Basis = fk[1]
		var hs := -1.0 if sd == "l" else 1.0
		var sh := chest - tb.y * 0.07 + tb.x * (hs * SHOULDER_HALF) + tb * (g.get("shoulders", {}).get(sd, Vector3.ZERO) as Vector3)
		var pt := grip_point(fk[2], B, ss, spec, sh, bool(g.get("auto_grip", false)))
		out.append((pt - sh).length() - PALM)      # the wrist stops a palm short of the ski
	return out


## Coordinate descent over the grabbing legs' joint angles and the spine, all clamped to human
## limits: stay close to the styled pose, but the hand must reach the ski.
func _solve_grab(name: String, ph: float, pz: float) -> Dictionary:
	var g: Dictionary = GRAB_POSES[name]
	var legs := {"l": (g["legs"]["l"] as Array).duplicate(), "r": (g["legs"]["r"] as Array).duplicate()}
	var sp := [float(g["pitch"]), float(g["twist"]), float(g["side"])]
	var legs0 := {"l": (g["legs"]["l"] as Array).duplicate(), "r": (g["legs"]["r"] as Array).duplicate()}
	var sp0 := sp.duplicate()
	var keys := ["flex", "abd", "rot", "knee", "ankle"]
	var grabbed := []
	for sd in ["l", "r"]:
		if g.has(sd) and not grabbed.has(g[sd][0]):
			grabbed.append(g[sd][0])
	if g.has("skis"):
		grabbed = ["l", "r"]
	if g.get("fixed_legs", false):
		grabbed = []              # the legs are set exactly; only the grip and the upper body adjust
	# optional: the hand's grip point along the ski is free within "along_range", and the arm should
	# be this straight ("reach" = shoulder-to-hand distance / arm length; 0.975 ~ 155 deg elbow)
	var al := {}
	if g.has("along_range"):
		for sd in ["l", "r"]:
			if g.has(sd):
				al[sd] = float(g[sd][1])
	var cost := func(lg: Dictionary, s2: Array) -> float:
		var c := pow(_grab_gap(g, lg, s2, ph, pz, al), 2.0) * 4000.0
		if g.has("reach"):
			for d in _grab_dists(g, lg, s2, ph, pz, al):
				c += pow((float(d) - float(g["reach"]) * (UPPER_ARM + FOREARM)) / 0.02, 2.0)
		if g.has("skis"):
			c += _ski_target_cost(g["skis"], lg, ph, pz)
		if g.has("ski_up"):
			# how steeply a ski points tip-up (deg above horizontal, body frame)
			for sd2 in g["ski_up"]:
				var ss2 := -1.0 if sd2 == "l" else 1.0
				var fk2 := _leg_fk(Vector3(ss2 * HIP_HALF, ph - 0.04, pz), ss2, lg[sd2])
				var up_deg := rad_to_deg(asin(clampf(-(fk2[1] as Basis).z.y, -1.0, 1.0)))
				c += pow((up_deg - float(g["ski_up"][sd2])) / 5.0, 2.0) * float(g.get("ski_up_w", 3.0))
		for side in ["l", "r"]:
			for i in (lg[side] as Array).size():
				c += pow((float(lg[side][i]) - float(legs0[side][i])) / 40.0, 2.0) * float(g.get("legs_w", 1.0))
		c += pow((s2[0] - sp0[0]) / 40.0, 2.0) * float(g.get("pitch_w", 0.12)) + pow((s2[1] - sp0[1]) / 0.6, 2.0) * float(g.get("twist_w", 0.25)) \
			+ pow((s2[2] - sp0[2]) / 0.5, 2.0) * float(g.get("side_w", 0.25))
		return c
	var best: float = cost.call(legs, sp)
	for step in [12.0, 6.0, 3.0, 1.5]:
		for it in 30:
			var improved := false
			for side in grabbed:
				for i in (legs[side] as Array).size():
					if (g.get("lock", []) as Array).has(keys[i]):
						continue          # e.g. keep the skis parallel: hip swing / rotation stay as set
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
			for sd in al:
				for dirn in [-1.0, 1.0]:
					var old3: float = al[sd]
					var rng: Array = g["along_range"]
					al[sd] = clampf(old3 + dirn * step / 100.0, float(rng[0]), float(rng[1]))
					var c3: float = cost.call(legs, sp)
					if c3 < best - 1e-6:
						best = c3
						improved = true
					else:
						al[sd] = old3
			var sp_steps := [step, step / 60.0, step / 60.0]
			var sp_keys := ["pitch", "twist", "side"]
			for i in 3:
				for dirn in [-1.0, 1.0]:
					var lim2: Array = SPINE_LIMITS[sp_keys[i]]
					if i == 0 and g.has("pitch_max"):
						lim2 = [lim2[0], float(g["pitch_max"])]     # a crunched grab (Japan) bends further
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
	return {"legs": legs, "pitch": sp[0], "twist": sp[1], "side": sp[2], "gap": _grab_gap(g, legs, sp, ph, pz, al), "along": al}


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
	if t.has("side_off"):     # where the X sits sideways from the body centre (- = his left)
		var mid: Vector3 = (cen["l"] + cen["r"]) * 0.5
		c += pow((mid.x - float(t["side_off"])) / 0.05, 2.0) * 3.0
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
	var ank_f := clampf(float(a[4]), LEG_LIMITS["ankle"][0], LEG_LIMITS["ankle"][1]) if a.size() > 4 else 0.0
	var B := S * Basis(Vector3(1, 0, 0), deg_to_rad(BOOT_LEAN + ank_f))   # boot on the shin (+ boot flex)
	var ski_c := ankle - B.y * ANKLE_H - B.z * 0.03
	return [knee, B, ski_c]
var preview_grab := ""
## Cloth pieces that move: [weight axis (mesh-local), weight 0 at, weight 1 at] - the hem of the
## body, the back of the hood, the cuff end of each sleeve; and which spring drives each.
## Cloth springs: [stiffness, damping ratio, air drag, max offset (m), landing kick (s), inertia].
## Each hangs on its own anchor point on the body (see _cloth_anchor): sleeves / waist and hood
## (jacket), and each baggy pant leg.  The hood is loose and bouncy, the pants heavier, the sleeves
## tight.  Inertia < 1: fabric lying on the body is partly carried along by friction.
const CLOTH_SPRING := {"sleeves": [180.0, 0.32, 0.01, 0.03, 0.02, 0.5], "hood": [55.0, 0.2, 0.018, 0.09, 0.1, 0.4],
	"pant_l": [95.0, 0.26, 0.014, 0.05, 0.045, 0.5], "pant_r": [95.0, 0.26, 0.014, 0.05, 0.045, 0.5]}
var _cloth := {}                # spring -> [offset, velocity, anchor pos, anchor vel, anchor acc] (world)
var _cloth_air := false
var _cloth_vy := 0.0
var _cloth_hood_flap := 0.0
var _cloth_pant_flap := 0.0
var _look_side := 1.0           # riding switch: +1 looking over the left shoulder, -1 the right
var _look_hold := 0.0
var _cloth_prev := Vector3.ZERO
var _cloth_phase := 0.0
var _cloth_flutter := 0.0
const HIDDEN_PARTS := ["stripe", "backpack", "helmet", "helmet_trim", "helmet_dark", "stack_l", "stack_r", "pocket_l", "pocket_r",
	# the clothes are the skinned SkierRig garments now; these rigid pieces stay built but hidden
	"pelvis", "torso", "collar", "jacket_details", "uarm_l", "uarm_r", "farm_l", "farm_r", "thigh_l", "thigh_r", "shin_l", "shin_r",
	"shoulder_cap_l", "shoulder_cap_r", "elbow_cap_l", "elbow_cap_r", "knee_cap_l", "knee_cap_r",
	# head, gloves and boots are part of the skinned rider (SkierRig) now
	"head", "beanie", "beanie_cuff", "goggle_band", "goggle_lens", "goggle_frame", "gaiter", "neck", "hood", "hood_rim",
	"hand_l", "hand_r", "thumb_l", "thumb_r", "cuff_l", "cuff_r", "boot_l", "boot_r", "buckles_l", "buckles_r",
	"bootstrap_l", "bootstrap_r"]
## The rider's outfit (sRGB): sage park jacket with black zips and tabs, khaki pants, black helmet
## with orange-mirror goggles, navy gaiter, black gloves, charcoal boots.  (Matte charcoal helmet.)
const OUTFIT := {
	"jacket": {"main_color": Color(0.4, 0.45, 0.33), "accent_color": Color(0.05, 0.05, 0.055), "third_color": Color(0.88, 0.88, 0.84),
		"dark_color": Color(0.07, 0.075, 0.07), "roughness": 0.8, "accent_roughness": 0.45, "sheen": 0.22},
	"pants": {"main_color": Color(0.64, 0.58, 0.46), "accent_color": Color(0.27, 0.26, 0.24), "third_color": Color(0.07, 0.07, 0.075),
		"dark_color": Color(0.16, 0.15, 0.13),
		"roughness": 0.86, "accent_roughness": 0.7, "sheen": 0.2},
	"helmet": {"main_color": Color(0.13, 0.135, 0.14), "dark_color": Color(0.03, 0.03, 0.03), "roughness": 0.62, "clearcoat_amt": 0.08,
		"specular": 0.3, "detail_strength": 0.0, "sheen": 0.08},
	"goggle_frame": {"main_color": Color(0.06, 0.06, 0.065), "accent_color": Color(0.02, 0.02, 0.02), "roughness": 0.45,
		"detail_strength": 0.0, "sheen": 0.05},
	"goggle_lens": {"main_color": Color(0.98, 0.45, 0.08), "roughness": 0.05, "metallic": 0.75, "specular": 0.9,
		"clearcoat_amt": 1.0, "detail_strength": 0.0, "sheen": 0.0},
	"strap": {"main_color": Color(0.06, 0.06, 0.07), "accent_color": Color(0.42, 0.43, 0.45), "roughness": 0.7, "detail_strength": 0.5},
	"gaiter": {"main_color": Color(0.11, 0.12, 0.16), "accent_color": Color(0.19, 0.21, 0.27), "roughness": 0.95, "detail_strength": 0.5},
	"glove": {"main_color": Color(0.05, 0.05, 0.055), "accent_color": Color(0.15, 0.15, 0.16), "roughness": 0.65,
		"accent_roughness": 0.92, "detail_strength": 0.45},
	"boot": {"main_color": Color(0.17, 0.18, 0.2), "accent_color": Color(0.72, 0.73, 0.75), "dark_color": Color(0.03, 0.03, 0.03),
		"roughness": 0.35, "accent_roughness": 0.3, "accent_metallic": 0.9, "clearcoat_amt": 0.4, "detail_strength": 0.0, "sheen": 0.05},
}
var rider_mats := {}
var rig: SkierRig
var skeleton_view := false        # V: hide the clothes and show bones + joints
const BONES := [["pelvis", "hip_l"], ["pelvis", "hip_r"], ["hip_l", "knee_l"], ["knee_l", "ankle_l"], ["hip_r", "knee_r"],
	["knee_r", "ankle_r"], ["pelvis", "waist"], ["waist", "lumbar"], ["lumbar", "thoracic"], ["thoracic", "chest"], ["chest", "head"],
	["chest", "shoulder_l"], ["chest", "shoulder_r"], ["shoulder_l", "elbow_l"], ["elbow_l", "hand_l"], ["shoulder_r", "elbow_r"],
	["elbow_r", "hand_r"], ["ankle_l", "heel_l"], ["ankle_l", "toe_l"], ["heel_l", "toe_l"], ["ankle_r", "heel_r"], ["ankle_r", "toe_r"],
	["heel_r", "toe_r"]]
const SK_JOINTS := ["pelvis", "hip_l", "hip_r", "knee_l", "knee_r", "ankle_l", "ankle_r", "waist", "lumbar", "thoracic", "chest",
	"shoulder_l", "shoulder_r", "elbow_l", "elbow_r", "hand_l", "hand_r", "heel_l", "heel_r", "toe_l", "toe_r"]
## Foot points in the boot frame (origin at the ankle joint, sole 0.1 m below, toe toward -Z).
const HEEL := Vector3(0.0, -0.105, 0.1)
const TOE := Vector3(0.0, -0.105, -0.19)
var _ag := ""                     # grab pose being shown (preview or the skier's live grab)
var _gw := 0.0                    # how far into it, eased (blends in and out)
var _gp := 0.0                    # linear progress behind _gw
var _gw_legs := 0.0               # grab stages (see _compute_pose): knees up,
var _gw_cross := 0.0              # skis swing across into the X,
var _gw_hand := 0.0               # hand reaches the ski,
var _gw_body := 0.0               # spine curve / twist / tilt
var _grab_phase := ""             # reach / contact / hold / release / landing prep (dev view)
var _grab_hold_t := 0.0
var _tweak := 0.0                 # 0..1: the grab pulled in over the first half second of the hold              # spring-smoothed hand offsets: arms settle after the body


func grab_phase_name() -> String:
	return "%s  (reach %.2f, hold %.2f s, tweak %.2f)" % [_grab_phase if _grab_phase != "" else "-", _gp, _grab_hold_t, _tweak]


func setup(s: Skier) -> void:
	skier = s
	add_to_group("skier_body")
	top_level = true
	global_transform = Transform3D.IDENTITY
	_build()
	ragdoll.terrain = s.terrain
	for k in ["layout", "ftuck", "chatter", "pelvis_h", "pelvis_z", "pitch", "counter", "hand_spread", "plow", "feet_up", "arms_air", "tuck", "grab_l", "grab_r", "brake", "edgeb", "switch_look", "look_yaw"]:
		_p[k] = 0.0
	_p["pelvis_h"] = 0.9
	for gname in GRAB_POSES:
		_solved[gname] = _solve_grab(gname, 0.86, 0.06)


## All-black park outfit: long baggy hooded jacket, baggy pants stacked over the boots, black
## helmet with orange goggles, black gloves and charcoal twin-tips.  Slightly different blacks and
## roughness keep the jacket, pants and gear readable.
func _build() -> void:
	# outfit after the player's reference (a park skier): loose cream jacket, baggy light-grey pants
	# with dark grey patches, dark navy headwear, black gloves, dark boots and poles
	# jacket after the player's jacket photo: washed-black brushed cotton, boxy, high collar, two
	# flapped chest pockets, a hood; every piece is on the moving cloth shader (see _cloth_step)
	var jacket := SkierModel.cloth_material(Color(0.2, 0.2, 0.21))
	var jacket_dark := jacket
	# pants after the player's pants reference: plain warm taupe nylon, very wide, pooling on the boots
	var pants := SkierModel.fabric(Color(0.47, 0.42, 0.38), 0.85, 90.0, 0.55, 0.12)
	var pocket_m := SkierModel.fabric(Color(0.42, 0.375, 0.34), 0.85, 90.0, 0.55, 0.1)
	var helmet := SkierModel.mat(Color(0.1, 0.12, 0.18), 0.6, 0.0, {"clearcoat": 0.2})
	var skin := SkierModel.mat(Color(0.85, 0.66, 0.55), 0.6)
	var lens := SkierModel.mat(Color(0.12, 0.32, 0.85), 0.04, 0.85, {"clearcoat": 1.0})
	var strap := SkierModel.mat(Color(0.03, 0.03, 0.035), 0.6)
	var glove := SkierModel.fabric(Color(0.05, 0.05, 0.055), 0.5, 40.0, 0.4, 0.15)
	var gaiter := SkierModel.fabric(Color(0.1, 0.12, 0.18), 0.95, 120.0, 0.6, 0.1)
	var metal := SkierModel.mat(Color(0.7, 0.72, 0.75), 0.3, 0.9)
	var boot := SkierModel.mat(Color(0.2, 0.2, 0.22), 0.4, 0.0, {"clearcoat": 0.4})
	var bind := SkierModel.mat(Color(0.12, 0.12, 0.13), 0.4, 0.4)
	var pole_m := SkierModel.mat(Color(0.12, 0.12, 0.13), 0.35, 0.6)
	var grip_m := SkierModel.mat(Color(0.08, 0.08, 0.08), 0.6)
	var basket_m := SkierModel.mat(Color(0.45, 0.3, 0.14), 0.6)
	var accent := SkierModel.mat(Color(0.16, 0.165, 0.18), 0.7)
	_add("pelvis", SkierModel.pelvis(), pants)
	_add("torso", SkierModel.torso(), jacket)
	var hd := SkierModel.hood()
	_add("hood", hd[0], jacket)
	_add("hood_rim", hd[1], SkierModel.mat(Color(0.05, 0.05, 0.055), 0.95))
	_add("backpack", SkierModel.backpack(), SkierModel.mat(Color(0.14, 0.145, 0.16), 0.75))
	_add("collar", SkierModel.lathe([Vector2(0.0, -0.01), Vector2(0.085, -0.01), Vector2(0.08, 0.06), Vector2(0.0, 0.06)], 1.0, 1.0, 12), jacket_dark)
	_add("neck", SkierModel.limb(0.05, 0.048, 0.08), skin)
	_add("gaiter", SkierModel.gaiter(), gaiter, true)
	_add("jacket_details", SkierModel.jacket_details(), SkierModel.cloth_material(Color(0.16, 0.16, 0.17), Vector2(3.0, 3.0)))
	_add("head", SkierModel.sphere(0.105, 0.95, 1.12, 1.05), skin, true)
	_add("helmet", SkierModel.helmet(), helmet, true)
	var hdet := SkierModel.helmet_details()
	_add("helmet_trim", hdet[0], helmet, true)
	_add("helmet_dark", hdet[1], strap, true)
	var knit := SkierModel.fabric(Color(0.1, 0.12, 0.18), 0.95, 45.0, 0.9, 0.1)
	var bn := SkierModel.beanie()
	_add("beanie", bn[0], knit, true)
	_add("beanie_cuff", bn[1], knit, true)
	var g := SkierModel.goggles(0.8)       # sized for a beanie: on the face, strap round the hat
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
		_add("pocket_" + side, SkierModel.cargo_pocket(), pocket_m)
		var bh := SkierModel.boot_hardware()
		_add("buckles_" + side, bh[0], metal)
		_add("bootstrap_" + side, bh[1], strap)
		# joints: rounded caps so knees, elbows and shoulders bend like joints, not pipes
		# joint fills no bigger than the sleeve, so the shoulders and elbows don't bulge
		_add("shoulder_cap_" + side, SkierModel.sphere(0.084, 1.0, 1.0, 1.0), jacket)
		_add("elbow_cap_" + side, SkierModel.sphere(0.078), jacket)
		_add("knee_cap_" + side, SkierModel.sphere(0.128, 1.0, 1.0, 1.0), pants)   # fills the bend, stays inside the leg
		_add("stack_" + side, SkierModel.lathe([Vector2(0.0, -0.035), Vector2(0.155, -0.035), Vector2(0.176, 0.025), Vector2(0.168, 0.1), Vector2(0.0, 0.1)], 1.0, 1.12, 16), pants)
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
		_add("basket_" + side, pl[2], basket_m)
	# a stripe of accent colour on the jacket
	_add("stripe", SkierModel.lathe([Vector2(0.0, 0.0), Vector2(0.18, 0.0), Vector2(0.183, 0.035), Vector2(0.0, 0.035)], 1.19, 0.73, 18), accent)
	# the rider: skinned clothes and gear built offline (build/gen_rider.py), see SkierRig
	rig = SkierRig.new()
	rig.name = "rig"
	add_child(rig)
	var gear_shader: Shader = load("res://shaders/skier_gear.gdshader")
	var weave: Texture2D = load("res://assets/rider/weave_normal.png")
	for key in OUTFIT:
		var m := ShaderMaterial.new()
		m.shader = gear_shader
		m.set_shader_parameter("detail_nrm", weave)
		for prm in OUTFIT[key]:
			m.set_shader_parameter(prm, OUTFIT[key][prm])
		if key in ["jacket", "pants"]:
			m.set_shader_parameter("use_atlas", true)
			m.set_shader_parameter("atlas_tex", load("res://assets/rider/%s_albedo.png" % key))
			m.set_shader_parameter("atlas_nrm", load("res://assets/rider/%s_normal.png" % key))
		rider_mats[key] = m
	if rig.build(rider_mats, HEAD_LAYER):
		# weave tiles every ~1.2 cm whatever the atlas density
		for key in rider_mats:
			var garment: String = key if key != "glove" and key != "boot" else key + "_l"
			(rider_mats[key] as ShaderMaterial).set_shader_parameter("detail_scale", 83.0 / rig.uv_per_m(garment))
		for k in rig.meshes:
			parts[k] = rig.meshes[k]
		head_parts.append(rig.meshes["rig_head"])
	for k in HIDDEN_PARTS:
		parts[k].visible = false
	var bone_m := SkierModel.mat(Color(0.95, 0.95, 0.92), 0.6)
	var joint_m := SkierModel.mat(Color(1.0, 0.45, 0.1), 0.5)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.018
	cyl.bottom_radius = 0.018
	cyl.height = 1.0
	cyl.radial_segments = 8
	for b in BONES:
		_add("sk_" + b[0] + "_" + b[1], cyl, bone_m)
	for j in SK_JOINTS:
		_add("skj_" + j, SkierModel.sphere(0.035), joint_m)
	_add("skj_head", SkierModel.sphere(0.09, 0.9, 1.1, 1.0), bone_m)
	_set_skeleton(false)        # read as a toy band round the chest; the zip and pockets replace it


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
	joints.erase("lumbar")
	joints.erase("thoracic")
	if InputMap.has_action("skeleton_view") and Input.is_action_just_pressed("skeleton_view"):
		skeleton_view = not skeleton_view
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
	_cloth_step(dt)
	_apply_parts()
	_cloth_apply()


## Where each cloth spring hangs: the hood from the upper back, each pant leg from its lower leg,
## the sleeve ends and bloused waist from the chest.
func _cloth_anchor(key: String) -> Vector3:
	var tb := torso_basis
	match key:
		"hood":
			return joints["chest"] + tb.y * -0.1 + tb.z * 0.15
		"pant_l", "pant_r":
			var sd: String = key.right(1)
			return (joints["ankle_" + sd] as Vector3).lerp(joints["knee_" + sd], 0.3)
	return joints["chest"]


## Cloth: each spring is a damped mass on its anchor.  It lags the anchor's acceleration - a
## landing throws the hood and pant legs down and they bounce back, a spin swings them out, a flip
## carries them round - is blown back by the air (speed squared), and hangs toward gravity once
## he's tipped well past his skiing lean (upside down the hood falls toward his head).  Above
## ~15 km/h the fabric also flaps, the loose hood most.
func _cloth_step(dt: float) -> void:
	if dt <= 0.0 or not joints.has("chest") or not joints.has("knee_l"):
		return
	var c: Vector3 = joints["chest"]
	var first := _cloth.is_empty() or c.distance_to(_cloth_prev) > 3.0          # first frame / teleport
	if first:
		_cloth.clear()
	_cloth_prev = c
	# landing: the fabric keeps falling for a moment, then springs back up
	var air := skier.airborne
	var kick := 0.0
	if _cloth_air and not air:
		kick = clampf(-_cloth_vy, 0.0, 9.0)
	_cloth_air = air
	_cloth_vy = skier.vel.y
	var sp := skier.vel.length()
	for key in CLOTH_SPRING:
		var cfg: Array = CLOTH_SPRING[key]
		var a := _cloth_anchor(String(key))
		var st: Array = _cloth.get(key, [Vector3.ZERO, Vector3.ZERO, a, Vector3.ZERO, Vector3.ZERO])
		var x: Vector3 = st[0]
		var u: Vector3 = st[1]
		# anchor velocity smoothed before it's differentiated, so pose jitter doesn't shake the cloth
		var av: Vector3 = (st[3] as Vector3).lerp((a - (st[2] as Vector3)) / dt, 1.0 - exp(-30.0 * dt))
		var acc: Vector3 = (st[4] as Vector3).lerp((av - (st[3] as Vector3)) / dt, 1.0 - exp(-14.0 * dt))
		if first:
			av = skier.vel
			acc = Vector3.ZERO
		# the clothes were made hanging on an upright skier: measure gravity against his body's up
		var up := (torso_basis.y if key == "hood" or key == "sleeves" else pelvis_basis.y).normalized()
		# gravity counts once he's tipped past ~50 deg (layouts, inverted in flips), not in a crouch
		var g_dev := (Vector3.DOWN + up) * 9.81
		g_dev *= smoothstep(0.8, 1.4, g_dev.length() / 9.81)
		var k: float = cfg[0]
		var f := -k * x - 2.0 * float(cfg[1]) * sqrt(k) * u - acc.limit_length(80.0) * float(cfg[5]) \
			- av * av.length() * float(cfg[2]) + g_dev
		u += f * dt
		u += Vector3.DOWN * kick * float(cfg[4])
		x += u * dt
		if key == "hood":
			# it lifts off his back and flops, but can't sink into it
			var into := -x.dot(torso_basis.z.normalized())
			if into > 0.006:
				x += torso_basis.z.normalized() * (into - 0.006)
		elif key == "sleeves":
			x -= up * x.dot(up) * 0.5
		var lim: float = cfg[3]
		if x.length() > lim:
			# the fabric reaches the end of its play: stop there instead of sticking to the limit
			var dir := x.normalized()
			x = dir * lim
			u -= dir * maxf(u.dot(dir), 0.0)
		_cloth[key] = [x, u, a, av, acc]
	_cloth_flutter = clampf((sp - 4.0) * 0.0007, 0.0, 0.008)
	_cloth_hood_flap = clampf((sp - 5.0) * 0.0012, 0.0, 0.016)
	_cloth_pant_flap = clampf((sp - 5.0) * 0.0008, 0.0, 0.011)
	_cloth_phase = fmod(_cloth_phase + dt * (8.0 + sp * 1.3), TAU * 100.0)


## Hand the springs to the shaders (the rig's skeleton has no rotation: world = mesh space).
func _cloth_apply() -> void:
	if rider_mats.has("jacket"):
		var jm: ShaderMaterial = rider_mats["jacket"]
		jm.set_shader_parameter("sway", _cloth.get("sleeves", [Vector3.ZERO])[0])
		jm.set_shader_parameter("sway2", _cloth.get("hood", [Vector3.ZERO])[0])
		jm.set_shader_parameter("flutter", _cloth_flutter)
		jm.set_shader_parameter("flutter2", _cloth_hood_flap)
		jm.set_shader_parameter("phase", _cloth_phase)
		var pm: ShaderMaterial = rider_mats["pants"]
		pm.set_shader_parameter("sway", _cloth.get("pant_l", [Vector3.ZERO])[0])
		pm.set_shader_parameter("sway2", _cloth.get("pant_r", [Vector3.ZERO])[0])
		pm.set_shader_parameter("flutter", _cloth_pant_flap)
		pm.set_shader_parameter("flutter2", _cloth_pant_flap)
		pm.set_shader_parameter("phase", _cloth_phase + 1.3)


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
	# riding switch (and the 180 into or out of it): the body faces back up the hill
	var yaw_add := s.revert + s.stance_vis
	if absf(yaw_add) > 0.001:
		root.basis = Basis(up, yaw_add) * root.basis
	# flips: the whole body rotates about its centre of mass
	if s.airborne and absf(s.air_pitch) > 0.001:
		var piv := root.origin + up * 0.9
		var fr := Basis(root.basis.x.normalized(), -s.air_pitch)
		root = Transform3D(fr * root.basis, piv + fr * (root.origin - piv))
		up = root.basis.y
	# off-axis tricks: about the diagonal axis in his own frame (it spins round with the heading)
	if s.airborne and s.off_family != "" and s.off_angle > 0.0001:
		var piv2 := root.origin + up * 0.9
		var fr2 := Basis((root.basis * s.off_axis).normalized(), s.off_angle)
		root = Transform3D(fr2 * root.basis, piv2 + fr2 * (root.origin - piv2))
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
	# the lean is into the turn in the world; with the body turned round (switch) that's the other way
	var L := Transform3D(root.basis * Basis(Vector3(0, 0, 1), -_lean * cos(s.stance_vis)), root.origin)
	# off-axis grab: the whole body tilts in the air (legs and skis swing out to one side)
	var g_roll := float(GRAB_POSES[_ag].get("roll", 0.0)) * _gw_body if GRAB_POSES.has(_ag) else 0.0
	if absf(g_roll) > 0.0001:
		var piv := L.origin + L.basis.y * 0.9
		var R := Basis(L.basis.z.normalized(), g_roll)
		L = Transform3D(R * L.basis, piv + R * (L.origin - piv))
	# a tweaked grab twists the hips and legs against the chest (skis go across, chest faces on)
	var hips_yaw := float(GRAB_POSES[_ag].get("hips_yaw", 0.0)) * _gw_cross if GRAB_POSES.has(_ag) else 0.0
	var LH := Transform3D(L.basis * Basis(Vector3.UP, hips_yaw), L.origin)
	# upper body faces the direction of travel: when the skis pivot underneath, the torso lags
	# behind instead of snapping, and it counter-rotates slightly toward the outside of the turn
	# riding switch: he looks down the hill over a shoulder - the left one going straight or turning
	# right, the right one in a left turn.  The shoulder only changes once a turn has been held for
	# half a second, and the head swings across smoothly, so tapping the arrows can't whip it about.
	var want_side := -1.0 if s.steer < -0.35 else 1.0          # +1 = over the left shoulder
	if want_side != _look_side:
		_look_hold += dt
		if _look_hold > 0.5:
			_look_side = want_side
			_look_hold = 0.0
	else:
		_look_hold = 0.0
	# in the air he only looks once the rotation is done and touchdown is close (and he'll land switch)
	var look_on := 1.0 if s.riding_switch and not s.airborne else 0.0
	if s.airborne:
		var hv := Vector2(s.vel.x, s.vel.z)
		var land_sw := s.riding_switch != (absf(wrapf(s.heading - (Skier.yaw_of(s.vel) if hv.length() > 1.0 else s.heading), -PI, PI)) > PI * 0.5)
		var flip_done := absf(roundf(s.air_pitch / TAU) * TAU - s.air_pitch) < deg_to_rad(30.0)
		look_on = 1.0 if land_sw and flip_done and s.land_t < 0.45 and absf(s.spin_vel) < 2.5 else 0.0
	var sw_look := _sm("switch_look", look_on, 5.0, dt)
	var look_yaw := _sm("look_yaw", _look_side * 1.3, 4.0, dt) * sw_look
	if s.airborne and s.off_family == "rodeo":
		# throws his head back over the trailing shoulder at the pop, then spots the landing
		look_yaw += -s.off_dir * 0.9 * smoothstep(0.0, 0.1, s.off_t) * smoothstep(0.6, 0.3, s.off_t)
	var torso_t := look_yaw * 0.3                                  # the shoulders open toward the look
	if not s.airborne and s.speed > 1.5:
		# hockey stop: the skis pivot underneath while the upper body keeps facing downhill
		var lim := lerpf(0.7, 1.3, maxf(s.edge_brake, 1.0 if s.grind_slide and s.is_grinding() else 0.0))
		torso_t += clampf(wrapf(s.travel_yaw - s.heading, -PI, PI), -lim, lim) * lerpf(0.75, 0.9, s.edge_brake) + _lean * 0.22
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
	var live := s.grab_name if s.airborne and s.grab_held else ""
	var want := preview_grab if preview_grab != "" else live
	if want != "":
		if _ag != "" and want != _ag and preview_grab == "":
			_gp *= 0.6                      # switching grabs: ease out of the old one, into the new
		_ag = want
	# reaching a grab takes Skier.GRAB_IN, letting go Skier.GRAB_OUT (quicker once he has landed);
	# smoothstep eases the start and the end so the body moves into it rather than snapping
	var t_in := float(GRAB_POSES[want].get("time_in", Skier.GRAB_IN)) if GRAB_POSES.has(want) else Skier.GRAB_IN
	var g_rate := 1.0 / t_in if want != "" else (1.0 / Skier.GRAB_OUT if s.airborne else 6.0)
	_gp = move_toward(_gp, 1.0 if want != "" else 0.0, g_rate * dt)
	_gw = 1.0 if preview_grab != "" else smoothstep(0.0, 1.0, _gp)
	# stages of a grab: knees come up first (skis still parallel), then the skis swing across,
	# and the hand arrives on the ski as the cross finishes; the spine and tilt build throughout.
	# Letting go runs the same stages backwards.
	_gw_legs = _gw if preview_grab != "" else smoothstep(0.0, 0.45, _gp)
	_gw_cross = _gw if preview_grab != "" else smoothstep(0.3, 0.88, _gp)
	_gw_hand = _gw if preview_grab != "" else smoothstep(0.4, 1.0, _gp)
	_gw_body = _gw if preview_grab != "" else smoothstep(0.1, 0.95, _gp)
	if _gp < 0.005 and preview_grab == "":
		_ag = ""
	# phases (dev view) and the hold: once the hand is on the ski he keeps pulling it in for half a
	# second - the "tweak" - instead of freezing in the pose
	var prev_phase := _grab_phase
	if _ag == "":
		_grab_phase = "landing prep" if (s.airborne and s.land_t < 0.4) else ""
	elif want == "":
		_grab_phase = "release"
	elif _gw_hand < 0.97:
		_grab_phase = "reach"
	else:
		_grab_phase = "contact" if prev_phase == "reach" else "hold"
	if _grab_phase == "hold" or _grab_phase == "contact":
		_grab_hold_t += dt
	elif want == "":
		_grab_hold_t = maxf(_grab_hold_t - dt * 3.0, 0.0)
	else:
		_grab_hold_t = 0.0
	_tweak = smoothstep(0.0, 0.5, _grab_hold_t)
	if GRAB_POSES.has(_ag):
		if not _solved.has(_ag):
			_solved[_ag] = _solve_grab(_ag, 0.86, 0.06)
		pitch = lerpf(pitch, deg_to_rad(float(_solved[_ag]["pitch"])), _gw_body)
	pitch = _sm("pitch", pitch, 10.0, dt) + deg_to_rad(45.0) * _p["ftuck"]
	# angulation: legs take the full inclination, the torso stays much more upright
	var counter := _lean * 0.58
	# off-axis takeoff shapes (first ~0.35 s): a cork / bio drops the lead shoulder, a rodeo arches
	# back with the head thrown over the trailing shoulder, a misty curls forward over the chest
	var off_init := 0.0
	if s.airborne and s.off_family != "":
		off_init = smoothstep(0.0, 0.08, s.off_t) * smoothstep(0.45, 0.2, s.off_t)
		match s.off_family:
			"cork", "bio":
				counter += s.off_dir * 0.32 * off_init
			"rodeo":
				pitch -= deg_to_rad(18.0) * off_init
			"misty":
				pitch += deg_to_rad(28.0) * off_init
	var plow := _sm("plow", 0.0, 8.0, dt)
	# front flips are always tucked (knees to the chest, opening to spot the landing); backflips
	# start laid out and tuck when the flip is pulled on into a double
	var near_land := absf(roundf(s.air_pitch / TAU) * TAU - s.air_pitch) < deg_to_rad(55.0) and absf(s.air_pitch) > PI
	var front := s.airborne and s.flip_vel > 1.0 and s.air_pitch > deg_to_rad(15.0)
	var ft_want := s.flip_tuck if s.airborne else 0.0
	if front and not near_land:
		ft_want = 1.0
	# off-axis: the family's tuck once the rotation is going, opening up to spot the landing
	var off_open := 0.0
	if s.airborne and s.off_family != "":
		off_open = maxf(smoothstep(deg_to_rad(270.0), deg_to_rad(330.0), s.off_angle), smoothstep(0.45, 0.2, s.land_t))
		ft_want = float(Skier.OFFAXIS[s.off_family]["tuck"]) * smoothstep(0.05, 0.3, s.off_t) * (1.0 - off_open)
	var ftuck := _sm("ftuck", ft_want, 9.0, dt)
	var feet_up := _sm("feet_up", air * (0.05 + 0.26 * grab + 0.42 * ftuck), 8.0, dt)
	# layout backflip: body long from the shoulders to the knees, knees bent so the shins and skis
	# fold back behind the thighs and the skis run parallel to the body; opens up again to land
	var lay_t := air * smoothstep(1.2, 2.5, -s.flip_vel) * (0.0 if near_land else 1.0) * (1.0 - ftuck)
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
			# the cross happens in the hips: sweep from a tucked, parallel-ski leg (same hip and
			# knee bend, no side swing or rotation) to the grab's angles, so the skis visibly
			# swing across into the X instead of appearing crossed
			var la: Array = _solved[_ag]["legs"][sd_key]
			var ang := [la[0], lerpf(0.0, float(la[1]), _gw_cross), lerpf(0.0, float(la[2]), _gw_cross), la[3]]
			if la.size() > 4:
				ang.append(la[4])
			fk = _leg_fk(hip_local, side, ang)
			_fk["hip_" + sd_key] = LH * hip_local
			_fk["knee_" + sd_key] = LH * (fk[0] as Vector3)
		var foot := L * foot_local
		if not fk.is_empty():
			foot = (L * foot_local).lerp(LH * (fk[2] as Vector3), _gw_legs)
		if not s.airborne:
			# both skis stay on the snow: raise/lower each foot onto the ground plane
			var dy := (foot - root.origin).dot(up)
			var lup := L.basis.y
			foot -= lup * (dy / maxf(lup.dot(up), 0.3))
		var yaw := plow * side
		var sb := L.basis * Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), -PI * 0.5 * layout)
		if not gp.is_empty():
			sb = sb.orthonormalized().slerp((LH.basis * (fk[1] as Basis)).orthonormalized(), _gw_legs)
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
	var g_twist := float(gpt.get("twist", 0.0)) * _gw_body * (1.0 + 0.22 * _tweak)
	var g_side := float(gpt.get("side", 0.0)) * _gw_body
	var g_curve := float(GRAB_POSES[_ag].get("curve", 0.0)) * _gw_body * (1.0 + 0.2 * _tweak) if GRAB_POSES.has(_ag) else 0.0
	var g_tdist: Array = GRAB_POSES[_ag].get("twist_dist", [1.0, 1.0, 1.0]) if GRAB_POSES.has(_ag) else [1.0, 1.0, 1.0]
	var spine := spine_bases(L.basis * Basis(Vector3.UP, _torso_yaw), counter + g_side, g_curve, pitch, g_twist, g_tdist)
	var tb: Basis = spine[2]
	pelvis_basis = (spine[0] as Basis).orthonormalized()
	torso_basis = tb.orthonormalized()
	var hip_basis := (LH.basis * Basis(Vector3.UP, _torso_yaw * 0.45) * Basis(Vector3(0, 0, 1), counter * 0.3)).orthonormalized()
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
		var pole_dir := LH.basis * Vector3(sgn * 0.25, 0.0, -1.0)
		var pole_pt := hip + pole_dir
		if GRAB_POSES.has(_ag) and _fk.has("knee_" + sd):
			# knees point where the hip rotation puts them (the grab's joint angles)
			var fkk: Vector3 = _fk["knee_" + sd]
			pole_pt = pole_pt.lerp(fkk + (fkk - (hip + ank) * 0.5), _gw_legs)
		joints["knee_" + sd] = ik2(hip, ank, THIGH, SHIN, pole_pt)
	pelvis = (joints["hip_l"] + joints["hip_r"]) * 0.5 + hip_basis.y * 0.04
	joints["pelvis"] = pelvis
	var waist := pelvis + (spine[0] as Basis).y * 0.07
	joints["waist"] = waist
	# a spine, not a plank: the lower back takes a little of the bend, the mid back more, the upper
	# back the rest, so a bent-over skier curves instead of hinging at the waist
	var tb_low: Basis = spine[0]
	var tb_mid: Basis = spine[1]
	var lumbar := waist + tb_low.y * 0.16
	var thoracic := lumbar + tb_mid.y * 0.16
	var chest := thoracic + tb.y * (TORSO_LEN - 0.32)
	joints["lumbar"] = lumbar
	joints["thoracic"] = thoracic
	joints["chest"] = chest
	# head keeps the eyes level and looks into the turn
	var hb := tb * Basis(Vector3.UP, -_lean * 0.35 + look_yaw) * Basis(Vector3(0, 0, 1), _lean * 0.3) * Basis(Vector3(1, 0, 0), pitch * 0.8 - deg_to_rad(6.0))
	# grabbing: look at the ski you're reaching for (over the shoulder for a tail grab), within
	# what a neck can turn; the head turns first, then the hand follows
	var gl_pose: Dictionary = GRAB_POSES.get(_ag, {})
	var look_w := float(gl_pose.get("look", 0.0)) * _gw_legs
	if look_w > 0.001:
		var gspec: Array = gl_pose["r"] if gl_pose.has("r") else gl_pose["l"]
		var gsx: Transform3D = ski_l if gspec[0] == "l" else ski_r
		var target := gsx.origin + gsx.basis * Vector3(0.0, 0.05, float(gspec[1]))
		var loc := tb.orthonormalized().inverse() * (target - (chest + tb.y * 0.19)).normalized()
		var yaw := clampf(atan2(-loc.x, -loc.z), -deg_to_rad(NECK_YAW), deg_to_rad(NECK_YAW))
		var lp := clampf(atan2(loc.y, Vector2(loc.x, loc.z).length()), deg_to_rad(NECK_PITCH[0]), deg_to_rad(NECK_PITCH[1]))
		var hb_look := tb * Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), lp)
		hb = hb.orthonormalized().slerp(hb_look.orthonormalized(), clampf(look_w, 0.0, 1.0))
	head_basis = hb.orthonormalized()
	joints["head"] = chest + hb.y * 0.19
	# ---- arms
	var plant_side := _update_pole_plant(dt)
	for sd in ["l", "r"]:
		var sgn := -1.0 if sd == "l" else 1.0
		var sh := chest - tb.y * 0.07 + tb.x * (sgn * SHOULDER_HALF)
		# shoulder blade: a grab pulls the reaching shoulder back / down, the other one forward
		sh += tb * (gl_pose.get("shoulders", {}).get(sd, Vector3.ZERO) as Vector3) * _gw_body
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
			var reach_p := Vector3(sgn * 0.19, -0.2, -0.52)          # arms out in front, low enough for the tips to reach the snow
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
			g = _gw_hand if gpose.has(sd) else 0.0
			if gpose.has("free") and gpose["free"].has(sd):
				hand = hand.lerp(sh + tb * (gpose["free"][sd] as Vector3), _gw_body)   # the free arm styles it out
		if g > 0.01 and gpose.has(sd):
			var spec: Array = gpose[sd]
			var gs := -1.0 if spec[0] == "l" else 1.0
			var sx2: Transform3D = ski_l if spec[0] == "l" else ski_r
			var spec_live := spec.duplicate()
			var sal: Dictionary = _solved.get(_ag, {}).get("along", {})
			if sal.has(sd):
				spec_live[1] = sal[sd]
			var grip_pt := grip_point(sx2.origin, sx2.basis, gs, spec_live, sh, bool(gpose.get("auto_grip", false)))
			hand = hand.lerp(grip_pt - (grip_pt - sh).normalized() * PALM, g)     # palm on the ski, wrist just short of it
			grab_gap[sd] = maxf((hand - sh).length() - (UPPER_ARM + FOREARM), 0.0)
		elif g > 0.01:
			var sxf := ski_l if sd == "l" else ski_r
			var kind := s.grab_kind_l if sd == "l" else s.grab_kind_r
			var along := {"tip": -0.72, "tail": 0.62}.get(kind, -0.12) as float
			var grab_pt := sxf.origin + sxf.basis * Vector3(sgn * 0.07, 0.10, along)
			hand = hand.lerp(grab_pt, g)
		var elbow_pole := sh + tb * Vector3(sgn * 0.5, -0.2, 0.45)
		var el := ik2(sh, hand, UPPER_ARM, FOREARM, elbow_pole)
		if g > 0.01 and gpose.has(sd):
			# grabbing: if the arm would pass through a ski, swing the elbow round the shoulder-hand
			# line to the clearest side (sticking with the last choice unless another is clearly better)
			var clr := _arm_ski_clearance(sh, el, hand)
			if clr < 0.0 or _elbow_k.get(sd, 0) != 0:
				var axis := (hand - sh).normalized()
				var best_k := 0
				var best_c := clr
				var cands := {}
				for k in 12:
					var pole_k := sh + (elbow_pole - sh).rotated(axis, TAU * k / 12.0)
					var el_k := ik2(sh, hand, UPPER_ARM, FOREARM, pole_k)
					var c_k := _arm_ski_clearance(sh, el_k, hand) - 0.004 * minf(k, 12 - k)
					cands[k] = [el_k, c_k]
					if c_k > best_c:
						best_c = c_k
						best_k = k
				var prev: int = _elbow_k.get(sd, 0)
				if cands.has(prev) and float(cands[prev][1]) > best_c - 0.02:
					best_k = prev
				_elbow_k[sd] = best_k
				el = cands[best_k][0]
				clr = _arm_ski_clearance(sh, el, hand)
			arm_clear[sd] = clr
		else:
			_elbow_k[sd] = 0
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
		if g > 0.01:
			pd = pd.lerp(Vector3(sgn * 0.55, 0.3, 0.75), g)     # grabbing: the pole swings out and back, clear of the skis
		if plant_side == sgn:
			pd = pd.lerp(Vector3(sgn * 0.1, -0.96, -0.15), _pole_plant)
		var planted := false
		if _push_amt > 0.5 and not s.airborne and _push_ph > 0.22 and _push_ph < 0.68:
			# plant: the tip goes into the snow just behind the hand, then stays put while the
			# skier slides past it and the arms drive back
			# out of reach (the skier has slid past it, or a respawn left it behind): the pole
			# comes out of the snow for the rest of this stroke instead of stretching the arm
			if _pole_tip.has(sd) and (_pole_tip[sd] - sh).length() > (POLE_LEN + UPPER_ARM + FOREARM) * 0.97:
				_pole_tip.erase(sd)
				_pole_done[sd] = true
			if not _pole_tip.has(sd) and not _pole_done.get(sd, false):
				# the swinging pole plants where its tip actually reaches the snow (no jump to a
				# precomputed spot); if it hasn't got there by mid-stroke it plants where it is
				var cur: Vector3 = _pole_dir_s.get(sd, Vector3.DOWN)
				var probe := hand + cur * POLE_LEN
				var gnd_p := s.terrain.height(probe.x, probe.z)
				if probe.y <= gnd_p + 0.03:
					probe.y = gnd_p - 0.04
					_pole_tip[sd] = probe
				elif _push_ph > 0.34 and cur.y < -0.2:
					# not down yet: plant where the pole's own line meets the snow (no rotation;
					# the arm reaches a little further down along the pole instead)
					var gh := s.terrain.height(hand.x, hand.z)
					var t := clampf((hand.y - gh) / -cur.y, 0.0, POLE_LEN * 1.3)
					var tp := hand + cur * t
					tp.y = s.terrain.height(tp.x, tp.z) - 0.04
					_pole_tip[sd] = tp
		if _pole_tip.has(sd) and _push_amt > 0.5 and not s.airborne and _push_ph > 0.22 and _push_ph < 0.68:
			var tipw: Vector3 = _pole_tip[sd]
			var tg := hand - tipw
			if absf(tg.length() - POLE_LEN) > 0.001 or (hand - sh).length() > UPPER_ARM + FOREARM:
				# the hand stays on the grip of the planted pole AND within arm's reach of the
				# shoulder (the sleeve and glove are rigid, the arm can't stretch): alternate the two
				# constraints until they agree, finishing on the pole so its tip stays in the snow
				var arm_len := (UPPER_ARM + FOREARM) * 0.995
				for it in 8:
					if (hand - sh).length() > arm_len:
						hand = sh + (hand - sh).normalized() * arm_len
					hand = tipw + (hand - tipw).normalized() * POLE_LEN
				joints["hand_" + sd] = hand
				joints["elbow_" + sd] = ik2(sh, hand, UPPER_ARM, FOREARM, elbow_pole)
			# the arm spring carries on from where the hand really is, so it doesn't jump on release
			_hands[sd] = tb.orthonormalized().inverse() * (hand - sh)
			_hands[sd + "_v"] = Vector3.ZERO
			planted = true
		else:
			_pole_tip.erase(sd)
			if _push_ph < 0.22 or _push_ph >= 0.68 or _push_amt <= 0.5:
				_pole_done.erase(sd)     # next stroke may plant again
		if _push_amt > 0.02 and not planted:
			# recovery: poles swing forward, baskets trailing, ready for the next plant
			var rt := 1.0       # reaching for the snow (stroke started, tip not down yet)
			if _pole_done.get(sd, false):
				rt = 0.0         # released early: trailing behind like at the end of the drive
			elif _push_ph < 0.22:
				rt = (_push_ph + 0.32) / 0.54
			elif _push_ph >= 0.68:
				rt = (_push_ph - 0.68) / 0.54
			var swing := Vector3(sgn * 0.05, -0.4, 0.92).lerp(Vector3(sgn * 0.06, -0.96, 0.25), smoothstep(0.0, 1.0, clampf(rt, 0.0, 1.0)))
			pd = pd.lerp(swing, _push_amt)
		if g > 0.01:
			pd = pd.lerp(Vector3(sgn * 0.6, 0.2, 0.7), g)
		joints["pole_dir_" + sd] = (tb * pd).normalized()
		if planted:
			joints["pole_dir_" + sd] = (_pole_tip[sd] - hand).normalized()
		else:
			# a pole swings, it doesn't snap: ease toward the new direction (slower while pushing)
			var prev: Vector3 = _pole_dir_s.get(sd, joints["pole_dir_" + sd])
			var tgt: Vector3 = joints["pole_dir_" + sd]
			var reaching: bool = _push_amt > 0.02 and _push_ph > 0.15 and _push_ph < 0.68 and not bool(_pole_done.get(sd, false))
			if _push_amt > 0.02 and _push_ph > 0.22 and _push_ph < 0.68 and not _pole_done.get(sd, false):
				# reach the tip down to the snow (in the upright body frame: the bent torso mustn't
				# tilt the pole backwards, away from the snow)
				tgt = (L.basis * Vector3(sgn * 0.06, -0.98, 0.1)).normalized()
			var k := 1.0 - exp(-(9.0 if reaching else (5.0 if _push_amt > 0.02 else 14.0)) * dt)
			joints["pole_dir_" + sd] = prev.slerp(tgt, k).normalized() if prev.dot(tgt) > -0.99 else tgt
		_pole_dir_s[sd] = joints["pole_dir_" + sd]
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
	torso_basis = Basis(right, up, right.cross(up)).orthonormalized()           # right-handed (z = back)
	pelvis_basis = torso_basis
	var hup := (j_head - j_chest).normalized()
	head_basis = Basis(right, hup, right.cross(hup).normalized()).orthonormalized()
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
	if skeleton_view != _sk_shown:
		_set_skeleton(skeleton_view)
	if skeleton_view:
		_place_skeleton()
	if rig != null:
		rig.update(joints, pelvis_basis, torso_basis, head_basis, boot_l, boot_r)
	# skis bend under load (landings, crouching on the tails) and spring back in the air
	var bend := clampf(skier.compression * 1.2 + skier.tail_load * 0.6 + skier.charge * 0.3, 0.0, 1.2)
	if skier.airborne:
		bend = -0.15
	for sd in ["l", "r"]:
		(parts["ski_" + sd].material_override as ShaderMaterial).set_shader_parameter("bend", bend)
	var tb := torso_basis
	parts["pelvis"].global_transform = Transform3D(pelvis_basis, joints["pelvis"])
	# the jacket follows the spine's chord (waist to chest), so a curved back doesn't leave the
	# shoulders hanging off the side of a rigid torso
	var chord: Vector3 = joints["chest"] - joints.get("waist", joints["pelvis"])
	var torso_b := tb
	if chord.length() > 0.05:
		torso_b = _basis_y(chord.normalized(), tb.x)
	parts["torso"].global_transform = Transform3D(torso_b, joints.get("waist", joints["pelvis"]))
	parts["stripe"].global_transform = Transform3D(tb, joints["waist"] + tb.y * 0.27)
	parts["collar"].global_transform = Transform3D(tb, joints["chest"] - tb.y * 0.02)
	parts["hood"].global_transform = Transform3D(tb, joints["chest"] - tb.y * 0.1 + tb.z * 0.03)
	parts["hood_rim"].global_transform = Transform3D(tb * Basis(Vector3(1, 0, 0), -0.45), joints["chest"] + tb.y * 0.06 + tb.z * 0.12)
	parts["backpack"].global_transform = Transform3D(tb, joints["waist"] + tb.y * 0.16 + tb.z * 0.11)
	parts["neck"].global_transform = Transform3D(head_basis, joints["chest"])
	var hb := head_basis
	var hc: Vector3 = joints["head"]
	parts["head"].global_transform = Transform3D(hb, hc)
	parts["helmet"].global_transform = Transform3D(hb, hc + hb.y * 0.015)
	parts["beanie"].global_transform = Transform3D(hb, hc)
	parts["beanie_cuff"].global_transform = Transform3D(hb, hc)
	parts["goggle_band"].global_transform = Transform3D(hb, hc + hb.y * 0.022)
	parts["goggle_lens"].global_transform = Transform3D(hb, hc + hb.y * 0.022)
	parts["goggle_frame"].global_transform = Transform3D(hb, hc + hb.y * 0.022)
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
		parts["pocket_" + sd].global_transform = Transform3D(txf.basis, txf.origin + txf.basis * Vector3(sgn * 0.152, 0.24, 0.0))
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


var _sk_shown := false
var pelvis_basis := Basis.IDENTITY


## Spine as three segments on top of a base frame: lower back, mid back, upper back.  The forward
## bend (pitch) and the sideways bend (curve, + = top goes to his left) are shared out so the spine
## curves instead of hinging; `side` tilts the whole spine.  Returns [low, mid, top] bases.
static func spine_bases(base: Basis, side: float, curve: float, pitch: float, twist := 0.0, tdist := [1.0, 1.0, 1.0]) -> Array:
	# `twist` turns the spine about its long axis, shared out over the segments by `tdist`
	# (e.g. [0.15, 0.55, 1.0]: the upper back turns, the hips hardly at all)
	return [base * Basis(Vector3.UP, twist * float(tdist[0])) * Basis(Vector3(0, 0, 1), side + curve * 0.2) * Basis(Vector3(1, 0, 0), -pitch * 0.4),
		base * Basis(Vector3.UP, twist * float(tdist[1])) * Basis(Vector3(0, 0, 1), side + curve * 0.55) * Basis(Vector3(1, 0, 0), -pitch * 0.75),
		base * Basis(Vector3.UP, twist * float(tdist[2])) * Basis(Vector3(0, 0, 1), side + curve) * Basis(Vector3(1, 0, 0), -pitch)]


func _set_skeleton(on: bool) -> void:
	_sk_shown = on
	for k in parts:
		var name := String(k)
		var keep := name.begins_with("ski_") or name.begins_with("bind_") or name.begins_with("pole_") or name.begins_with("grip_") or name.begins_with("basket_")
		if name.begins_with("sk_") or name.begins_with("skj_"):
			parts[k].visible = on
		elif not (name in HIDDEN_PARTS) and not keep:
			parts[k].visible = not on


func _place_skeleton() -> void:
	var w: Vector3 = joints.get("waist", joints["pelvis"])
	if not joints.has("lumbar"):
		joints["lumbar"] = w.lerp(joints["chest"], 0.36)
		joints["thoracic"] = w.lerp(joints["chest"], 0.7)
	if not joints.has("waist"):
		joints["waist"] = w
	# feet: heel and toe follow the boot (and with it the ski)
	for sd in ["l", "r"]:
		var bb: Basis = (boot_l if sd == "l" else boot_r).orthonormalized()
		var an: Vector3 = joints["ankle_" + sd]
		joints["heel_" + sd] = an + bb * HEEL
		joints["toe_" + sd] = an + bb * TOE
	for b in BONES:
		var a: Vector3 = joints[b[0]]
		var c: Vector3 = joints[b[1]]
		var d := c - a
		var ln := d.length()
		var mi: MeshInstance3D = parts["sk_" + b[0] + "_" + b[1]]
		if ln < 0.001:
			mi.visible = false
			continue
		mi.visible = true
		var bb := _basis_y(d / ln, torso_basis.x)
		mi.global_transform = Transform3D(Basis(bb.x, bb.y * ln, bb.z), (a + c) * 0.5)
	for j in SK_JOINTS:
		parts["skj_" + j].global_transform = Transform3D(Basis.IDENTITY, joints[j])
	parts["skj_head"].global_transform = Transform3D(head_basis, joints["head"])


static func _basis_y(y: Vector3, hint: Vector3) -> Basis:
	y = y.normalized()
	var x := hint - y * hint.dot(y)
	if x.length() < 0.001:
		x = y.cross(Vector3.FORWARD)
	x = x.normalized()
	return Basis(x, y, x.cross(y).normalized())


func set_first_person(on: bool) -> void:
	for mi in head_parts:
		mi.visible = not on and not (String(mi.name) in HIDDEN_PARTS)
