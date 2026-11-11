class_name CameraRig
extends Node3D
## Third-person / chase / first-person camera with smoothing, speed-driven distance and FOV,
## gentle roll into turns, terrain collision avoidance and mouse / right-stick look.

enum Mode { STANDARD, CHASE, FIRST_PERSON, ORBIT }

var mode := Mode.STANDARD
var last_follow_mode := Mode.STANDARD
var skier: Skier
var body: SkierBody
var terrain: TerrainData
var cam: Camera3D
var user_yaw := 0.0
var user_pitch := 0.0
var zoom := 1.0
var idle := 10.0
var shake := 0.0
var orbit_center := Vector3.ZERO
var orbit_radius := 30.0
var orbit_height := 8.0
var orbit_angle := 0.0

var _follow_yaw := 0.0
var _target := Vector3.ZERO
var _offset := Vector3.ZERO
var _fov := 72.0
var _roll := 0.0
var _initialized := false
var _sens := 1.0
var _invert := false
var _base_fov := 72.0
var _dist_mul := 1.0
var _speed_fx := true
var _shake_on := true
var _auto_center := true
var _fp_pitch := 0.0
var _fp_walk := false
var _fp_walk_yaw := 0.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.near = 0.08
	cam.far = 22000.0
	cam.current = true
	add_child(cam)
	top_level = true
	_read_settings()
	Settings.changed.connect(func(_s, _k): _read_settings())


func _read_settings() -> void:
	_sens = float(Settings.get_value("controls", "mouse_sens"))
	_invert = bool(Settings.get_value("controls", "invert_y"))
	_base_fov = float(Settings.get_value("camera", "fov"))
	_dist_mul = float(Settings.get_value("camera", "distance"))
	_speed_fx = bool(Settings.get_value("camera", "speed_fx"))
	_shake_on = bool(Settings.get_value("camera", "shake"))
	_auto_center = bool(Settings.get_value("camera", "auto_center"))
	var vd: int = int(Settings.get_value("graphics", "view_distance"))
	if cam:
		cam.far = [9000.0, 13000.0, 18000.0, 24000.0][clampi(vd, 0, 3)]


func set_mode(m: int) -> void:
	if m != Mode.ORBIT:
		last_follow_mode = m
	mode = m
	if body:
		body.set_first_person(m == Mode.FIRST_PERSON)
	cam.near = 0.04 if m == Mode.FIRST_PERSON else 0.08
	# hide head parts from the first-person camera
	cam.cull_mask = 0xFFFFF & ~(1 << (SkierBody.HEAD_LAYER - 1)) if m == Mode.FIRST_PERSON else 0xFFFFF
	_initialized = false


func cycle_mode() -> void:
	set_mode(Mode.CHASE if mode == Mode.STANDARD else Mode.STANDARD)


func toggle_first_person() -> void:
	set_mode(last_follow_mode if mode == Mode.FIRST_PERSON else Mode.FIRST_PERSON)
	if mode != Mode.FIRST_PERSON and last_follow_mode == Mode.FIRST_PERSON:
		set_mode(Mode.STANDARD)


func add_shake(amount: float) -> void:
	if _shake_on:
		shake = maxf(shake, amount)


func snap() -> void:
	_initialized = false


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	# mouse look: captured pointer, or drag with a held button when the browser refuses pointer lock
	if event is InputEventMouseMotion and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or (event as InputEventMouseMotion).button_mask != 0):
		var m: Vector2 = event.relative * 0.0025 * _sens
		user_yaw -= m.x
		user_pitch += (m.y if _invert else -m.y)
		user_pitch = clampf(user_pitch, -1.1, 0.9)
		idle = 0.0
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 0.9, 0.45, 2.6)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom * 1.1, 0.45, 2.6)


func _process(delta: float) -> void:
	if skier == null or terrain == null:
		return
	var dt := minf(delta, 0.05)
	idle += dt
	# right stick look
	var rs := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if rs.length() > 0.18:
		user_yaw -= rs.x * 2.6 * dt * _sens
		user_pitch += (rs.y if _invert else -rs.y) * 1.8 * dt * _sens
		user_pitch = clampf(user_pitch, -1.1, 0.9)
		idle = 0.0
	match mode:
		Mode.FIRST_PERSON:
			_first_person(dt)
		Mode.ORBIT:
			_orbit(dt)
		_:
			_third_person(dt)
	shake = maxf(shake - dt * 1.8, 0.0)
	# subtle buffeting at very high speed
	if skier.speed > 24.0 and not skier.airborne and _shake_on:
		shake = maxf(shake, clampf((skier.speed - 24.0) / 40.0, 0.0, 0.25))


func _third_person(dt: float) -> void:
	var chase := mode == Mode.CHASE
	var root := skier.visual_xform()
	var focus := root.origin
	if skier.is_crashed and body and body.in_ragdoll:
		focus = body.joints.get("pelvis", focus) - Vector3.UP * 0.6
	var speed := skier.speed
	var desired_target := focus + Vector3.UP * (1.1 if not chase else 1.0)
	# travel direction drives the follow yaw (spins in the air do not whip the camera)
	var hv := Vector3(skier.vel.x, 0.0, skier.vel.z)
	var dir_yaw := Skier.yaw_of(hv) if hv.length() > 1.5 else skier.heading
	if not _initialized:
		_follow_yaw = dir_yaw
		_target = desired_target
		user_yaw = 0.0
		user_pitch = 0.0
	var follow_rate := lerpf(1.6, 4.0, clampf(speed / 25.0, 0.0, 1.0))
	if skier.airborne:
		follow_rate *= 0.5
	var walking := skier.mode == Skier.Mode.WALK
	var on_lift := skier.mode == Skier.Mode.LIFT
	if on_lift:
		follow_rate = 0.8
	# on foot the mouse alone steers the view (movement is camera-relative)
	if not skier.is_crashed and not walking:
		_follow_yaw = lerp_angle(_follow_yaw, dir_yaw, 1.0 - exp(-follow_rate * dt))
	if _auto_center and idle > 1.6 and speed > 3.0 and not walking:
		user_yaw = lerp_angle(user_yaw, 0.0, 1.0 - exp(-1.4 * dt))
		user_pitch = lerpf(user_pitch, 0.0, 1.0 - exp(-1.0 * dt))
	# follow the body closely sideways and along, but take its vertical motion slowly and never more
	# than ~0.8 m behind it: a landing or a bump doesn't yank the view down and back up
	var ty := _target.y
	_target = _target.lerp(desired_target, 1.0 - exp(-(22.0 if not chase else 30.0) * dt))
	_target.y = clampf(lerpf(ty, desired_target.y, 1.0 - exp(-7.0 * dt)), desired_target.y - 0.8, desired_target.y + 0.8)
	# on a chairlift the default view is from the side, so you can see yourself (and the valley)
	var yaw := _follow_yaw + user_yaw + (1.05 if on_lift else 0.0)
	# look a little more downhill on steep slopes
	var slope_pitch := -deg_to_rad(clampf(skier.slope, 0.0, 45.0)) * 0.22 if not skier.airborne else 0.0
	var pitch := (-0.12 if not chase else -0.09) + user_pitch + slope_pitch
	if skier.is_crashed:
		pitch -= 0.28          # a bail: look down on him from higher, so the fall reads over the landing
	pitch = clampf(pitch, -1.25, 0.6)
	# low and close behind the skier, park-video style
	var dist := (3.9 + speed * 0.04) if not chase else (2.7 + speed * 0.022)
	if skier.is_crashed:
		dist += 1.2
	if walking:
		dist = 3.6 if not chase else 2.6
	elif on_lift:
		dist = 6.5
	dist *= zoom * _dist_mul
	var off := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * dist
	if not _initialized:
		_offset = off
		_initialized = true
	_offset = _offset.lerp(off, 1.0 - exp(-10.0 * dt))
	var pos := _target + _offset
	# terrain collision: never below the snow, pull in if the view is blocked
	var hit := terrain.raycast(_target, pos, 1.0)
	if hit < 1.0:
		pos = _target + (pos - _target) * maxf(hit - 0.08, 0.15)
	var gh := terrain.height(pos.x, pos.z)
	pos.y = maxf(pos.y, gh + 0.6)
	var look := _target + Skier.forward_flat_s(_follow_yaw) * (2.0 + speed * 0.05)
	look.y = lerpf(look.y, _target.y, 0.7)
	var t := Transform3D(Basis.IDENTITY, pos).looking_at(look, Vector3.UP)
	# gentle roll into turns
	var roll_t := -skier.lean_angle() * (0.12 if not chase else 0.25) if not skier.is_crashed else 0.0
	_roll = lerpf(_roll, roll_t, 1.0 - exp(-4.0 * dt))
	t.basis = t.basis * Basis(Vector3(0, 0, 1), _roll)
	if shake > 0.0:
		var tt := Time.get_ticks_msec() * 0.001
		t.origin += t.basis * Vector3(sin(tt * 37.0), sin(tt * 43.0 + 1.0), 0.0) * shake * 0.06
	global_transform = t
	skier.cam_yaw = yaw
	_update_fov(dt, speed if not on_lift else 0.0)


func _first_person(dt: float) -> void:
	if body == null:
		return
	var head: Vector3 = body.joints.get("head", skier.position + Vector3.UP * 1.6)
	var hb: Basis = body.head_basis
	if not _initialized:
		user_yaw = 0.0
		user_pitch = 0.0
		_initialized = true
	var walking := skier.mode == Skier.Mode.WALK
	if _auto_center and idle > 1.2 and not walking:
		user_yaw = lerp_angle(user_yaw, 0.0, 1.0 - exp(-2.0 * dt))
		user_pitch = lerpf(user_pitch, 0.0, 1.0 - exp(-2.0 * dt))
	var base_yaw := skier.heading + skier.revert
	if walking:
		# on foot the view is mouse-only; the body turns toward where it walks
		if not _fp_walk:
			_fp_walk = true
			_fp_walk_yaw = base_yaw + user_yaw
			user_yaw = 0.0
		base_yaw = _fp_walk_yaw
	else:
		_fp_walk = false
	var yaw := base_yaw + user_yaw
	var pitch := -0.12 + user_pitch
	if skier.is_crashed:
		pitch = -0.6
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var roll_t := -skier.lean_angle() * 0.55 if not skier.is_crashed else 0.0
	_roll = lerpf(_roll, roll_t, 1.0 - exp(-6.0 * dt))
	b = b * Basis(Vector3(0, 0, 1), _roll)
	var pos := head + hb.y * 0.04 - hb.z * 0.08
	pos.y = maxf(pos.y, terrain.height(pos.x, pos.z) + 0.25)
	var t := Transform3D(b, pos)
	if shake > 0.0:
		var tt := Time.get_ticks_msec() * 0.001
		t.origin += t.basis * Vector3(sin(tt * 41.0), sin(tt * 47.0), 0.0) * shake * 0.03
	global_transform = t
	skier.cam_yaw = yaw
	_update_fov(dt, skier.speed)


## Current view direction as a yaw angle (Skier convention).
func view_yaw() -> float:
	var f := -global_transform.basis.z
	return Skier.yaw_of(Vector3(f.x, 0.0, f.z))


func _orbit(dt: float) -> void:
	orbit_angle += dt * 0.05
	var p := orbit_center + Vector3(sin(orbit_angle), 0.0, cos(orbit_angle)) * orbit_radius
	p.y = maxf(orbit_center.y + orbit_height, terrain.height(p.x, p.z) + 3.0)
	global_transform = Transform3D(Basis.IDENTITY, p).looking_at(orbit_center + Vector3.UP * 1.5, Vector3.UP)
	cam.fov = lerpf(cam.fov, 60.0, 1.0 - exp(-2.0 * dt))


func _update_fov(dt: float, speed: float) -> void:
	var f := _base_fov
	if _speed_fx:
		f += clampf((speed - 8.0) * 0.42, 0.0, 16.0)
	if mode == Mode.FIRST_PERSON:
		f += 6.0
	_fov = lerpf(_fov, f, 1.0 - exp(-3.0 * dt))
	cam.fov = _fov
