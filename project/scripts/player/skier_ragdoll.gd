class_name SkierRagdoll
extends RefCounted
## Verlet ragdoll for crashes: 15 body particles with bone and bracing constraints that collide
## with the terrain heightfield.  Skis either stay attached to the ankles or come off
## ("yard sale") and tumble on their own as two-particle sticks.

const GRAVITY := Vector3(0, -9.81, 0)
const ITER := 8

var terrain: TerrainData
var names: Array[String] = ["head", "chest", "pelvis", "shoulder_l", "shoulder_r", "elbow_l", "elbow_r", "hand_l", "hand_r",
	"hip_l", "hip_r", "knee_l", "knee_r", "ankle_l", "ankle_r"]
var radius := {"head": 0.13, "chest": 0.16, "pelvis": 0.14, "hand_l": 0.05, "hand_r": 0.05, "ankle_l": 0.1, "ankle_r": 0.1}
var x := {}
var xp := {}
var cons: Array = []      # [a, b, rest, stiffness]
var skis := {}            # side -> {tip, tail, tipp, tailp, attached}
var settled_time := 0.0
var _time := 0.0


func start(joints: Dictionary, ski_l: Transform3D, ski_r: Transform3D, vel: Vector3, detach: bool) -> void:
	x.clear()
	xp.clear()
	cons.clear()
	_time = 0.0
	settled_time = 0.0
	var dt := 1.0 / 120.0
	var spin := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized() * minf(vel.length() * 0.25, 4.0)
	var center: Vector3 = joints["pelvis"]
	for n in names:
		var p: Vector3 = joints[n]
		x[n] = p
		# tumbling: add rotation about the pelvis so the body pitches over
		var rel := p - center
		var tang := spin.cross(rel)
		xp[n] = p - (vel + tang) * dt
	var bones := [["head", "chest"], ["chest", "pelvis"], ["chest", "shoulder_l"], ["chest", "shoulder_r"],
		["shoulder_l", "elbow_l"], ["elbow_l", "hand_l"], ["shoulder_r", "elbow_r"], ["elbow_r", "hand_r"],
		["pelvis", "hip_l"], ["pelvis", "hip_r"], ["hip_l", "knee_l"], ["knee_l", "ankle_l"], ["hip_r", "knee_r"], ["knee_r", "ankle_r"]]
	var braces := [["shoulder_l", "shoulder_r"], ["hip_l", "hip_r"], ["shoulder_l", "hip_l"], ["shoulder_r", "hip_r"],
		["shoulder_l", "hip_r"], ["shoulder_r", "hip_l"], ["head", "shoulder_l"], ["head", "shoulder_r"], ["chest", "hip_l"], ["chest", "hip_r"]]
	for b in bones:
		cons.append([b[0], b[1], (x[b[0]] - x[b[1]]).length(), 1.0])
	for b in braces:
		cons.append([b[0], b[1], (x[b[0]] - x[b[1]]).length(), 0.6])
	# soft limits to stop limbs folding through the body
	cons.append(["hip_l", "ankle_l", 0.45, -1.0])
	cons.append(["hip_r", "ankle_r", 0.45, -1.0])
	cons.append(["shoulder_l", "hand_l", 0.22, -1.0])
	cons.append(["shoulder_r", "hand_r", 0.22, -1.0])
	skis.clear()
	for sd in ["l", "r"]:
		var xf: Transform3D = ski_l if sd == "l" else ski_r
		var tip := xf.origin - xf.basis.z * 0.9
		var tail := xf.origin + xf.basis.z * 0.86
		var sv := vel * (0.9 if detach else 1.0) + Vector3(randf_range(-2, 2), randf_range(1, 3), randf_range(-2, 2)) * (1.0 if detach else 0.0)
		skis[sd] = {"tip": tip, "tail": tail, "tipp": tip - sv * dt, "tailp": tail - sv * dt, "attached": not detach,
			"up": xf.basis.y, "prev_tip": tip, "prev_tail": tail}


func step(dt: float) -> void:
	_time += dt
	var moving := 0.0
	for n in names:
		var p: Vector3 = x[n]
		var v: Vector3 = p - xp[n]
		xp[n] = p
		var nxt: Vector3 = p + v * 0.995 + GRAVITY * dt * dt
		x[n] = nxt
		moving = maxf(moving, v.length() / dt)
	for sd in skis:
		var s: Dictionary = skis[sd]
		s["prev_tip"] = s["tip"]
		s["prev_tail"] = s["tail"]
		if s["attached"]:
			continue
		for k in ["tip", "tail"]:
			var p: Vector3 = s[k]
			var v: Vector3 = p - s[k + "p"]
			s[k + "p"] = p
			s[k] = p + v * 0.995 + GRAVITY * dt * dt
	for _i in ITER:
		for c in cons:
			var a: Vector3 = x[c[0]]
			var b: Vector3 = x[c[1]]
			var d := b - a
			var ln := d.length()
			if ln < 0.0001:
				continue
			var rest: float = c[2]
			var k: float = c[3]
			if k < 0.0:
				if ln >= rest:
					continue
				k = 0.5
			var diff := (ln - rest) / ln * 0.5 * k
			x[c[0]] = a + d * diff
			x[c[1]] = b - d * diff
		for sd in skis:
			var s: Dictionary = skis[sd]
			if s["attached"]:
				continue
			var a: Vector3 = s["tip"]
			var b: Vector3 = s["tail"]
			var d := b - a
			var ln := d.length()
			if ln > 0.0001:
				var diff := (ln - 1.76) / ln * 0.5
				s["tip"] = a + d * diff
				s["tail"] = b - d * diff
		_collide()
	if moving < 0.6:
		settled_time += dt
	else:
		settled_time = 0.0


func _collide() -> void:
	for n in names:
		var p: Vector3 = x[n]
		var r: float = radius.get(n, 0.07)
		var h := terrain.height(p.x, p.z) + r
		if p.y < h:
			var nrm := terrain.normal(p.x, p.z, 1.0)
			p += nrm * (h - p.y) * nrm.y
			p.y = maxf(p.y, h - 0.01)
			x[n] = p
			# friction: damp tangential motion
			var prev: Vector3 = xp[n]
			var v := p - prev
			var vn := nrm * v.dot(nrm)
			var vt := v - vn
			xp[n] = p - vt * 0.86 - vn * -0.15
	for sd in skis:
		var s: Dictionary = skis[sd]
		if s["attached"]:
			continue
		for k in ["tip", "tail"]:
			var p: Vector3 = s[k]
			var h := terrain.height(p.x, p.z) + 0.03
			if p.y < h:
				p.y = h
				s[k] = p
				var prev: Vector3 = s[k + "p"]
				var v := p - prev
				v.y = minf(v.y, 0.0) * -0.2
				s[k + "p"] = p - Vector3(v.x * 0.9, v.y, v.z * 0.9)


func get_pos(n: String, f: float) -> Vector3:
	return (xp[n] as Vector3).lerp(x[n], f)


func pole_dir(sd: String) -> Vector3:
	var e: Vector3 = x["elbow_" + sd]
	var h: Vector3 = x["hand_" + sd]
	var d := (h - e).normalized()
	return (d + Vector3(0, -0.3, 0)).normalized()


func ski_xform(sd: String, f: float) -> Transform3D:
	var s: Dictionary = skis[sd]
	if s["attached"]:
		var ank: Vector3 = (xp["ankle_" + sd] as Vector3).lerp(x["ankle_" + sd], f)
		var knee: Vector3 = (xp["knee_" + sd] as Vector3).lerp(x["knee_" + sd], f)
		var up := (knee - ank).normalized()
		var hr: Vector3 = x["hip_r"]
		var hl: Vector3 = x["hip_l"]
		var right := (hr - hl).normalized()
		var fwd := right.cross(up).normalized()
		right = up.cross(fwd).normalized()
		var b := Basis(right, up, -fwd)
		return Transform3D(b, ank - up * 0.15)
	var tip: Vector3 = (s["prev_tip"] as Vector3).lerp(s["tip"], f)
	var tail: Vector3 = (s["prev_tail"] as Vector3).lerp(s["tail"], f)
	var z := (tail - tip).normalized()
	var up2: Vector3 = s["up"]
	var xx := up2.cross(z)
	if xx.length() < 0.01:
		xx = Vector3.UP.cross(z)
	xx = xx.normalized()
	var yy := z.cross(xx).normalized()
	return Transform3D(Basis(xx, yy, z), (tip + tail) * 0.5)


func center() -> Vector3:
	return x.get("pelvis", Vector3.ZERO)
