class_name Skier
extends Node3D
## Physically motivated skiing controller (custom integrator, 120 Hz).
##
## Ground model: gravity along the slope, sidecut carving (turn radius = R_sidecut * cos(edge))
## limited by edge grip, lossless redirection while the edge holds and friction when it skids,
## snow friction per surface type, powder drag, aerodynamic drag (automatic speed stance) and the hockey
## stop.  The body's weight shifts fore/aft (arrow keys): leaning back loads the tails for a bigger
## pop, and a spin is wound up on the ground.  Air: ballistic flight; spin and flip rotation come
## from takeoff (wind-up, leaning at the pop, the lip itself) and change speed with body shape
## (compact poses and grabs spin faster); in-air control depends on the difficulty.  Landings are
## judged on yaw, pitch and impact.  Takeoff happens naturally when the terrain falls away faster
## than gravity can follow (ballistic ground constraint).
## Rails and boxes: ride onto a box or pop onto a rail, slide it (balance with A/D, press the
## tips / tails with Up / Down) and pop off or ride off the end.
## Other modes: walking / hiking with the skis off, and sitting on a chairlift.

signal took_off
signal landed(info: Dictionary)
signal crashed(reason: String, velocity: Vector3)
signal respawned
signal tree_brush(pos: Vector3, strength: float)
signal jumped(strength: float)
signal mode_changed(mode: int)
signal jibbed(info: Dictionary)

enum Mode { SKI, WALK, LIFT }

const G := 9.81
const SIDECUT_R := 15.0
const CONTACT_EPS := 0.06
const AIR_THRESHOLD := 0.22
const CRASH_IMPACT := 20.0
const SPIN_MAX := 8.6
const SPIN_ACCEL := 20.0
const SPIN_DAMP := 7.0
const WALK_SPEED := 1.8
const JOG_SPEED := 3.4
const MAX_HIKE_SLOPE := 40.0
const WIND_SPIN := 7.5             # spin rate (rad/s) from a full wind-up at takeoff
const FLIP_POP := 4.4              # flip rate (rad/s) from leaning fully at the pop
## Easy / Normal / Realistic: in-air spin & flip authority (rad/s^2), spin damping, auto-levelling
## toward a clean landing, landing tolerance (deg), impact limit and edge catching.
const DIFFICULTY := [
	{"name": "Easy", "air_spin": 20.0, "spin_damp": 7.0, "air_flip": 9.0, "level": 3.0, "land_tol": 62.0, "impact": 24.0, "edge_catch": false, "rail": 1.0, "rail_assist": 3.0},
	{"name": "Normal", "air_spin": 11.0, "spin_damp": 3.0, "air_flip": 6.0, "level": 1.8, "land_tol": 50.0, "impact": 20.0, "edge_catch": false, "rail": 2.0, "rail_assist": 1.2},
	{"name": "Realistic", "air_spin": 4.5, "spin_damp": 0.8, "air_flip": 3.0, "level": 0.0, "land_tol": 40.0, "impact": 17.0, "edge_catch": true, "rail": 3.2, "rail_assist": 0.0},
]

@export_range(0.05, 0.4) var suspension_travel := 0.22
@export_range(20.0, 180.0) var suspension_stiffness := 80.0
@export_range(4.0, 30.0) var suspension_damping := 16.0
@export_range(0.25, 2.0) var air_control := 1.0
@export_range(0.3, 1.8) var edge_grip := 1.0
var ski_support := PackedFloat32Array([1.0, 1.0])
var ski_heights := PackedFloat32Array([0.0, 0.0])
var ski_normals := [Vector3.UP, Vector3.UP]
var leg_compression := PackedFloat32Array([0.0, 0.0])
var leg_velocity := PackedFloat32Array([0.0, 0.0])

var _box_lateral := 0.0
var _box_lateral_speed := 0.0

var terrain: TerrainData
var obstacles: Obstacles

# --- state
var vel := Vector3.ZERO
var heading := 0.0                 # ski yaw; forward = (-sin, 0, -cos)
var yaw_rate := 0.0
var airborne := false
var contact := true
var air_time := 0.0
var ground_time := 0.0
var ground_n := Vector3.UP
var ground_h := 0.0
var edge := 0.0                    # edge angle (rad), + = carving right
var steer := 0.0
var tuck := 0.0
var brake := 0.0
var edge_brake := 0.0
var charge := 0.0
var charging := false
var spin_vel := 0.0
var air_rotation := 0.0
var grab_l := 0.0
var grab_r := 0.0
var grab_time_l := 0.0
var grab_time_r := 0.0
var skid := 0.0
var carve_g := 0.0
var surface := Color(0.5, 0, 0, 0)
var rock := 0.0
var compression := 0.0
var compression_vel := 0.0
var is_crashed := false
var crash_time := 0.0
var speed := 0.0
var slope := 0.0
var time := 0.0
var frozen := false
var input_enabled := true
var revert := 0.0
var takeoff_pos := Vector3.ZERO
var max_air_height := 0.0
# Pole stroke: anticipation (0-.20), plant (.20-.30), drive (.30-.65), recovery.
@export_range(0.1, 15.0) var push_max_speed := 7.0
@export_range(0.2, 3.0) var push_duration := 1.05
@export_range(0.0, 15.0) var push_acceleration := 8.0
var push_phase := -1.0
var _push_cooldown := 0.0
var pushing := 0.0
var steep_time := 0.0
var carving := false
var aggressive := false
var steer_sens := 1.0
var lat_acc := 0.0                 # measured sideways acceleration of the path (m/s^2, + = turning right)
var travel_yaw := 0.0              # direction of travel
var _prev_vel_yaw := 0.0
var mode := Mode.SKI
var cam_yaw := 0.0                 # camera yaw (set by the camera rig): walking is camera-relative
var walk_phase := 0.0              # gait cycle (radians)
var gear_anim := 0.0               # 1 -> 0 while clicking in / out of the bindings
var stop_side := 0.0               # hockey stop: +1 skis pivot right of travel, -1 left
var lift_seated := false
var _raw_steer := 0.0
var _walk_vy := 0.0
var _walk_air := false
var _jump_prev := false
var _mode_before_lift := Mode.SKI
var difficulty := 1
var lean_fa := 0.0                 # body weight: + forward over the tips, - back on the tails
var wind := 0.0                    # upper body wound up for a spin (+ = right), on the ground
var tail_load := 0.0               # crouching while leaning back: extra pop
var flip_vel := 0.0                # rad/s, + = forward (front flip)
var air_pitch := 0.0               # flip rotation so far (rad)
var air_pitch_peak := 0.0          # largest |pitch| reached in this jump (corks)
var sketchy := 0.0                 # > 0 while recovering from a sketchy landing (s)
var grab_kind_l := ""              # "", "tip" or "tail"
var grab_kind_r := ""
var _ground_pitch := 0.0           # pitch of the snow along the direction of travel
var _ground_pitch_rate := 0.0      # how fast it changes (a kicker's lip throws you backward)
var rails: Array = []              # jib features {a, b (top line), kind, width, length}, set by the park
var grind := {}                    # the rail being slid
var grind_slide := false           # skis across the rail (slide) instead of along it (50-50)
var grind_switch := false
var grind_time := 0.0
var grind_press := 0.0             # seconds pressing the tips (+) or tails (-)
var rail_balance := 0.0            # -1..1, falls off past either end
var _rail_bal_vel := 0.0
var _grind_t := 0.0
var _grind_v := 0.0
var _grind_dir := 1.0
var _grind_entry := 0.0
var _rail_cd := 0.0

var _safe: Array = []
var _safe_timer := 0.0
var _last_land_t := -10.0
var _brush_cd := 0.0
var _jump_buffer := 0.0
var _coyote := 0.0
var _prev_xform := Transform3D.IDENTITY
var _cur_xform := Transform3D.IDENTITY
var _bound_warn := 0.0

# test hooks: when set, input comes from this dictionary instead of devices
var scripted_input = null


func setup(td: TerrainData, obs: Obstacles) -> void:
	terrain = td
	obstacles = obs
	Settings.changed.connect(_on_settings)
	_on_settings("controls", "")


func _on_settings(section: String, _key: String) -> void:
	if section == "controls":
		steer_sens = float(Settings.get_value("controls", "steer_sens"))
		difficulty = clampi(int(Settings.get_value("controls", "difficulty")), 0, 2)


func diff() -> Dictionary:
	return DIFFICULTY[difficulty]


func forward_flat(yaw := heading) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func forward_flat_s(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


func teleport(pos: Vector3, yaw: float, initial_speed := 0.0, keep_mode := false) -> void:
	if not keep_mode and mode != Mode.SKI:
		mode = Mode.SKI
		mode_changed.emit(mode)
	lift_seated = false
	var h := terrain.height(pos.x, pos.z)
	position = Vector3(pos.x, h + 0.02, pos.z)
	heading = yaw
	ground_n = terrain.normal(pos.x, pos.z, 1.2)
	var f := forward_flat()
	vel = (f - ground_n * f.dot(ground_n)).normalized() * initial_speed
	speed = initial_speed
	_reset_motion()
	_safe.clear()
	_record_safe(true)
	_cur_xform = _compose_xform()
	_prev_xform = _cur_xform


func _reset_motion() -> void:
	airborne = false
	contact = true
	air_time = 0.0
	spin_vel = 0.0
	air_rotation = 0.0
	yaw_rate = 0.0
	edge = 0.0
	steer = 0.0
	charge = 0.0
	charging = false
	grab_l = 0.0
	grab_r = 0.0
	grab_time_l = 0.0
	grab_time_r = 0.0
	compression = 0.0
	compression_vel = 0.0
	is_crashed = false
	revert = 0.0
	steep_time = 0.0
	stop_side = 0.0
	edge_brake = 0.0
	brake = 0.0
	tuck = 0.0
	push_phase = -1.0
	_push_cooldown = 0.0
	pushing = 0.0
	lean_fa = 0.0
	wind = 0.0
	tail_load = 0.0
	flip_vel = 0.0
	air_pitch = 0.0
	air_pitch_peak = 0.0
	sketchy = 0.0
	_ground_pitch_rate = 0.0
	grind = {}
	leg_compression.fill(0.0)
	leg_velocity.fill(0.0)
	ski_support.fill(1.0)


# ------------------------------------------------------------------ input
func _in(action: String) -> float:
	if not input_enabled:
		return 0.0
	if scripted_input != null:
		return float(scripted_input.get(action, 0.0))
	return Input.get_action_strength(action)


func _pressed(action: String) -> bool:
	return _in(action) > 0.5


# ------------------------------------------------------------------ main loop
func _physics_process(dt: float) -> void:
	if terrain == null:
		return
	_prev_xform = _cur_xform
	time += dt
	if is_crashed:
		crash_time += dt
		_cur_xform = _compose_xform()
		return
	gear_anim = maxf(gear_anim - dt * 1.6, 0.0)
	if mode == Mode.LIFT:
		return                      # the lift drives the transform (set_lift_xform)
	if frozen:
		vel = Vector3.ZERO
		speed = 0.0
		_cur_xform = _compose_xform()
		return
	step(dt)
	_cur_xform = _compose_xform()


## One physics step (public for automated tests).
func step(dt: float) -> void:
	# Bound travel per collision query at high speed, retaining the fixed 120 Hz clock.
	var steps := clampi(int(ceil(vel.length() * dt / 0.65)), 1, 8)
	for i in steps:
		_step_contact(dt / steps)
		if is_crashed:
			break


func _step_contact(dt: float) -> void:
	if mode == Mode.WALK:
		_walk_step(dt)
		return
	var raw_steer := _in("steer_right") - _in("steer_left")
	_raw_steer = raw_steer
	aggressive = _pressed("carve")
	var want_brake := _pressed("brake")
	var jump_held := _pressed("jump")
	# arrows: body lean fore/aft and wind-up / spin (Q/E still spin as well)
	var spin_in := clampf(_in("spin_right") - _in("spin_left") + _in("lean_right") - _in("lean_left"), -1.0, 1.0)
	var lean_in := _in("lean_forward") - _in("lean_back")
	lean_fa = move_toward(lean_fa, lean_in, 5.0 * dt)
	if not airborne:
		wind = move_toward(wind, spin_in, (2.5 if absf(spin_in) > 0.1 else 4.0) * dt)
		# loading builds while crouching with the weight back and fades slowly, so you can
		# straighten up just before the pop (big ollie) instead of popping into a backflip
		var load_t := charge * maxf(-lean_fa, 0.0)
		tail_load = move_toward(tail_load, load_t, (4.0 if load_t > tail_load else 1.0) * dt)
	sketchy = maxf(sketchy - dt, 0.0)
	# smooth inputs (no instant redirection)
	var srate := 3.2 * steer_sens if absf(raw_steer) > absf(steer) else 5.0
	steer = move_toward(steer, clampf(raw_steer, -1.0, 1.0), srate * dt)
	# Athletic stance follows speed; the push binding never changes drag or air rotation.
	tuck = move_toward(tuck, smoothstep(8.0, 22.0, vel.length()) if not airborne and not want_brake else 0.0, 3.0 * dt)
	_push_cooldown = maxf(0.0, _push_cooldown - dt)
	if airborne or mode != Mode.SKI or not grind.is_empty():
		push_phase = -1.0
		pushing = 0.0
	brake = move_toward(brake, 1.0 if want_brake else 0.0, 4.0 * dt)
	# jump charge
	if jump_held:
		charging = true
		charge = minf(charge + dt / 0.55, 1.0)
	elif charging:
		charging = false
		_jump_buffer = 0.12
	if _jump_buffer > 0.0:
		_jump_buffer -= dt
		if not airborne or _coyote > 0.0:
			_do_jump()
			_jump_buffer = 0.0
	if not charging and _jump_buffer <= 0.0:
		charge = move_toward(charge, 0.0, 3.0 * dt)
	_coyote = maxf(_coyote - dt, 0.0)
	if not grind.is_empty():
		_grind_step(dt)
		return

	var p := position
	ground_h = _sample_skis(p, true)
	var n: Vector3 = (ski_normals[0] + ski_normals[1]).normalized()
	var gap := p.y - ground_h
	contact = gap < CONTACT_EPS and ski_support[0] + ski_support[1] > 0.0
	# skis just above the snow after a small bump still steer partially (legs absorb the bump)
	var cf := 1.0 if contact else clampf(1.0 - (gap - CONTACT_EPS) / 0.3, 0.0, 1.0)
	cf *= clampf((ski_support[0] + ski_support[1]) * 0.5, 0.0, 1.0)
	for i in 2:
		var target := clampf(ski_heights[i] - p.y, -suspension_travel, suspension_travel) if not airborne else 0.0
		leg_velocity[i] += ((target - leg_compression[i]) * suspension_stiffness - leg_velocity[i] * suspension_damping) * dt
		leg_compression[i] = clampf(leg_compression[i] + leg_velocity[i] * dt, -suspension_travel, suspension_travel)
	if contact:
		ground_n = n
		surface = terrain.surface_at(p.x, p.z)
		slope = rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))
		rock = smoothstep(46.0, 56.0, slope)

	if airborne:
		_air_step(dt, spin_in, lean_in)
	else:
		_ground_step(dt, n, cf)

	# integrate
	p += vel * dt
	var h2 := _sample_skis(p, false)
	var n2 := terrain.normal(p.x, p.z, 1.2)
	if p.y <= h2:
		p.y = h2
		var vn := vel.dot(n2)
		if airborne:
			position = p
			_land(n2, -vn)
			p = position
		elif vn < 0.0:
			vel -= n2 * vn
	else:
		var g2 := p.y - h2
		if not airborne and g2 > AIR_THRESHOLD:
			_take_off()
	position = p
	_bounds()
	_collide(dt)
	speed = vel.length()
	_measure_turn(dt)
	_update_safe(dt)
	# landing / bump compression spring
	compression_vel += (-compression * 70.0 - compression_vel * 11.0) * dt
	compression = clampf(compression + compression_vel * dt, -0.2, 1.0)
	revert = move_toward(revert, 0.0, dt * 7.0)
	if airborne:
		air_time += dt
		ground_time = 0.0
		max_air_height = maxf(max_air_height, p.y - h2)
	else:
		ground_time += dt
	_rail_cd = maxf(_rail_cd - dt, 0.0)
	if not rails.is_empty() and not is_crashed and _rail_cd <= 0.0:
		_try_mount()


func _measure_turn(dt: float) -> void:
	var hv := Vector2(vel.x, vel.z)
	if hv.length() < 1.0 or airborne:
		lat_acc = lerpf(lat_acc, 0.0, 1.0 - exp(-6.0 * dt))
		travel_yaw = heading if hv.length() < 1.0 else atan2(-hv.x, -hv.y)
		_prev_vel_yaw = travel_yaw
		return
	travel_yaw = atan2(-hv.x, -hv.y)
	var turn_rate := wrapf(travel_yaw - _prev_vel_yaw, -PI, PI) / dt
	_prev_vel_yaw = travel_yaw
	# + = right turn (yaw decreasing); lightly filtered against bump noise
	lat_acc = lerpf(lat_acc, clampf(-turn_rate * hv.length(), -30.0, 30.0), 1.0 - exp(-12.0 * dt))


func _ground_step(dt: float, n: Vector3, cf: float) -> void:
	var g := Vector3(0, -G, 0)
	# full gravity; the ballistic ground constraint after integration supplies the normal force,
	# so the skier leaves the ground exactly when the terrain curves away faster than gravity.
	vel += g * dt
	if cf <= 0.0:
		push_phase = -1.0
		pushing = 0.0
		return
	if cf < 1.0 and vel.dot(n) < 2.5:
		# knees absorb small bumps: press the skis back onto the snow
		vel -= n * minf(16.0, maxf(gap_to_snow(), 0.0) * suspension_stiffness) * cf * dt
	var f := forward_flat()
	f = (f - n * f.dot(n)).normalized()
	var vn := vel.dot(n)
	var vt := vel - n * vn
	var sp := vt.length()
	# --- surface properties
	var powder := surface.r * (1.0 - surface.g)
	var groomed := surface.g
	var ice := surface.b * (1.0 - groomed)
	var grip := (1.0 - 0.45 * ice - 0.15 * powder - 0.6 * rock) * edge_grip
	if aggressive:
		grip = minf(grip * 1.35 + ice * 0.15, 1.45)
	# weight back on the tails: the tips wash out (less grip); forward: crisper turn entry
	grip *= 1.0 - 0.3 * maxf(-lean_fa, 0.0)
	if sketchy > 0.0:
		grip *= 0.7
	var a_lat_max := (2.2 if aggressive else 1.6) * G * maxf(n.y, 0.2) * grip * maxf(cf, 0.35)
	# --- edge angle follows steering (visual lean and carve radius)
	var max_edge := deg_to_rad(64.0 if aggressive else 48.0)
	var edge_target := steer * max_edge * clampf(sp / 7.0, 0.2, 1.0)
	edge = move_toward(edge, edge_target, (3.6 if aggressive else 2.6) * dt)
	# --- yaw rate: skidded pivot at low speed, sidecut carve at speed
	var omega_pivot := steer * lerpf(2.6, 0.8, clampf(sp / 14.0, 0.0, 1.0))
	var omega_carve := 0.0
	if absf(edge) > 0.03 and sp > 0.5:
		var r := SIDECUT_R * cos(absf(edge))
		omega_carve = signf(edge) * minf(sp / r, a_lat_max / sp)
	var w := clampf((sp - 3.0) / 7.0, 0.0, 1.0)
	var omega_target := lerpf(omega_pivot, omega_carve + steer * 0.12, w)
	omega_target *= (1.0 - 0.3 * tuck) * (1.0 + 0.2 * lean_fa)
	# hockey stop: the skis pivot across the direction of travel and the edges set.  It builds up
	# progressively (a tap checks speed, holding it stops), toward the hill or the steered side.
	var vdir := vt / sp if sp > 0.3 else f
	var stopping := brake > 0.5 and sp > 1.2
	if stopping and stop_side == 0.0:
		stop_side = _pick_stop_side(vdir)
	elif brake < 0.05 and edge_brake < 0.05:
		stop_side = 0.0
	edge_brake = move_toward(edge_brake, 1.0 if stopping else 0.0, (3.4 if stopping else 3.0) * dt)
	if edge_brake > 0.01 and sp > 0.3 and stop_side != 0.0:
		# signed slip: + = ski tips rotated to the right of the direction of travel
		var slip_s := -vdir.signed_angle_to(f, n)
		var err := stop_side * deg_to_rad(82.0) * minf(edge_brake * 1.6, 1.0) - slip_s
		omega_target = lerpf(omega_target, clampf(err * 9.0, -6.5, 6.5), edge_brake)
	yaw_rate = lerpf(yaw_rate, omega_target, 1.0 - exp(-dt / 0.07))
	# pitch of the snow along the travel direction; its rate of change at a lip becomes flip rotation
	if sp > 1.0:
		var gp := asin(clampf(-(vt / sp).y, -1.0, 1.0))
		_ground_pitch_rate = lerpf(_ground_pitch_rate, wrapf(gp - _ground_pitch, -PI, PI) / dt, 1.0 - exp(-7.0 * dt))
		_ground_pitch = gp
	heading = wrapf(heading - yaw_rate * dt, -PI, PI)
	f = forward_flat()
	f = (f - n * f.dot(n)).normalized()
	# --- velocity follows the skis through edge grip
	skid = move_toward(skid, 0.0, 3.0 * dt)
	carve_g = 0.0
	carving = false
	if sp > 0.3:
		vdir = vt / sp
		var target := f if vdir.dot(f) >= 0.0 else -f
		var ang := vdir.signed_angle_to(target, n)
		var max_turn := a_lat_max / sp * dt * (1.0 - 0.75 * edge_brake)
		if absf(ang) <= max_turn:
			vdir = target
			carve_g = absf(yaw_rate) * sp
			carving = absf(edge) > 0.15
		else:
			vdir = vdir.rotated(n, signf(ang) * max_turn).normalized()
			carve_g = a_lat_max
			# Realistic: skidding sideways fast on a flat ski catches the downhill edge
			if diff()["edge_catch"] and absf(ang) > deg_to_rad(65.0) and sp > 13.0 and absf(edge) < 0.12 and edge_brake < 0.3 and cf >= 1.0:
				crash("Caught an edge")
				return
			var mu_skid := 0.55 + 0.55 * edge_brake * clampf(grip, 0.55, 1.15)
			var dec := mu_skid * G * maxf(n.y, 0.2) * sin(minf(absf(ang), PI * 0.5))
			sp = maxf(sp - dec * dt, 0.0)
			skid = maxf(skid, clampf(absf(ang) * 2.0, 0.0, 1.0))
		# --- resistive forces
		var mu := lerpf(0.05, 0.042, groomed)
		mu = lerpf(mu, 0.028, ice)
		mu = lerpf(mu, 0.32, rock)
		var dec2 := mu * G * maxf(n.y, 0.2)
		dec2 += 0.09 * powder * sp                            # powder drag
		var cda := lerpf(0.0042, 0.0016, tuck)                 # 0.5*rho*CdA/m
		cda = lerpf(cda, 0.0032, charge * 0.5)
		dec2 += cda * sp * sp
		dec2 += 0.035 * carve_g * (1.5 if aggressive else 1.0)  # carving compresses snow
		if brake > 0.5 and sp < 3.0:
			dec2 += 2.6 * brake * maxf(n.y, 0.3)                # finishing the stop on the edges
		sp = maxf(sp - dec2 * dt, 0.0)
		vt = vdir * sp
	vel = vt + n * vn
	# A stroke only propels during pole drive, with assistance fading at speed.
	_pole_push(dt, f, n, sp)
	# --- static friction when nearly stopped
	var gt := (g - n * g.dot(n))
	if (vel - n * vel.dot(n)).length() < 0.35 and (absf(gt.dot(f)) < 0.06 * G or brake > 0.5) and pushing == 0.0:
		vel = n * minf(vel.dot(n), 0.0)
	# --- losing control on extreme faces
	if slope > 60.0 and sp > 6.0:
		steep_time += dt
		if steep_time > 0.6:
			crash("Lost control on a cliff face")
	else:
		steep_time = maxf(steep_time - dt, 0.0)


## Kept separate so stroke timing can be tested without render or terrain dependencies.
func _pole_push(dt: float, forward: Vector3, _normal: Vector3, tangent_speed: float) -> void:
	pushing = 0.0
	var allowed := contact and not airborne and not is_crashed and mode == Mode.SKI and grind.is_empty() and brake < 0.1 and not _pressed("brake") and tangent_speed < push_max_speed
	if not allowed:
		push_phase = -1.0
		return
	if push_phase < 0.0:
		if not _pressed("tuck") or _push_cooldown > 0.0:
			return
		push_phase = 0.0
		_push_cooldown = maxf(push_duration, 0.2)
	# Integrate the drive interval overlap, so boundary crossings don't depend on FPS.
	var next_phase := push_phase + dt / maxf(push_duration, 0.2)
	var drive_time := maxf(0.0, minf(next_phase, 0.65) - maxf(push_phase, 0.30)) * maxf(push_duration, 0.2)
	if drive_time > 0.0:
		var fade := 1.0 - smoothstep(0.0, maxf(push_max_speed, 0.1), tangent_speed)
		var uphill := 1.0 - 0.65 * clampf(forward.y / 0.5, 0.0, 1.0)
		var impulse := minf(push_acceleration * fade * uphill * drive_time, maxf(0.0, push_max_speed - tangent_speed))
		vel += forward * impulse
		pushing = 1.0
	push_phase = next_phase if next_phase < 1.0 else -1.0


func _air_step(dt: float, spin_in: float, flip_in: float) -> void:
	vel += Vector3(0, -G, 0) * dt
	var sp := vel.length()
	var compact := maxf(tuck, (grab_l + grab_r) * 0.5)
	var cda := lerpf(0.0042, 0.0022, compact)
	vel -= vel * cda * sp * dt
	var d := diff()
	# body english: how much you can change your rotation once airborne depends on the difficulty
	if absf(spin_in) > 0.1:
		spin_vel = move_toward(spin_vel, signf(spin_in) * SPIN_MAX, float(d["air_spin"]) * air_control * dt)
	else:
		spin_vel = move_toward(spin_vel, 0.0, float(d["spin_damp"]) * dt)
	if absf(flip_in) > 0.1:
		flip_vel = move_toward(flip_vel, signf(flip_in) * SPIN_MAX * 0.7, float(d["air_flip"]) * air_control * dt)
	elif float(d["level"]) > 0.0 and absf(roundf(air_pitch / TAU) * TAU - air_pitch) < deg_to_rad(60.0):
		# assist: settle a small tilt toward a clean landing (it cannot rescue an upside-down one)
		var target := roundf(air_pitch / TAU) * TAU
		flip_vel += ((target - air_pitch) * float(d["level"]) * 2.0 - flip_vel * float(d["level"])) * dt
	# Compact poses and grabs: smaller moment of inertia, faster rotation
	var w_mul := 1.0 + 0.3 * compact
	heading = wrapf(heading - spin_vel * w_mul * dt, -PI, PI)
	air_rotation += spin_vel * w_mul * dt
	air_pitch += flip_vel * w_mul * dt
	air_pitch_peak = maxf(air_pitch_peak, absf(air_pitch))
	# light air steering ("body english")
	var hv := Vector3(vel.x, 0, vel.z)
	if hv.length() > 1.0:
		var right := hv.normalized().cross(Vector3.UP)
		vel += right * steer * 1.1 * air_control * dt
	var gl := _pressed("grab_left")
	var gr := _pressed("grab_right")
	# where the hand goes: leaning forward reaches the tip, leaning back the tail
	var kind := "tip" if flip_in > 0.5 else ("tail" if flip_in < -0.5 else "")
	if gl and grab_l < 0.05:
		grab_kind_l = kind
	if gr and grab_r < 0.05:
		grab_kind_r = kind
	grab_l = move_toward(grab_l, 1.0 if gl else 0.0, 7.0 * dt)
	grab_r = move_toward(grab_r, 1.0 if gr else 0.0, 7.0 * dt)
	if grab_l > 0.8:
		grab_time_l += dt
	if grab_r > 0.8:
		grab_time_r += dt
	edge = move_toward(edge, 0.0, 2.0 * dt)
	skid = 0.0
	carve_g = 0.0


func _do_jump() -> void:
	if not grind.is_empty():
		_leave_rail("pop")
		ground_n = Vector3.UP
	var n := ground_n
	# crouch depth, loaded tails (lean back while crouching) and rebound off a compression
	var strength := 2.6 + 2.6 * charge + 1.6 * tail_load + 1.2 * clampf(compression, 0.0, 1.0)
	vel += (n * 0.75 + Vector3.UP * 0.25).normalized() * strength
	tail_load = 0.0
	position.y += 0.05
	charge = 0.0
	_coyote = 0.0
	jumped.emit(strength)
	_take_off(true)


func _take_off(from_jump := false) -> void:
	push_phase = -1.0
	pushing = 0.0
	if airborne:
		return
	airborne = true
	air_time = 0.0
	air_rotation = 0.0
	grab_time_l = 0.0
	grab_time_r = 0.0
	takeoff_pos = position
	max_air_height = 0.0
	_coyote = 0.0 if from_jump else 0.12
	# rotation is set at takeoff: carving rotation and the wound-up upper body give the spin ...
	spin_vel = clampf(yaw_rate * 0.5 + wind * WIND_SPIN, -SPIN_MAX, SPIN_MAX)
	wind = 0.0
	# ... the lip pitches you backward, and leaning at the pop starts a front / back flip
	flip_vel = clampf(_ground_pitch_rate * 0.35, -1.0, 1.0)
	if from_jump:
		flip_vel += lean_fa * FLIP_POP
	air_pitch = 0.0
	air_pitch_peak = 0.0
	grab_kind_l = ""
	grab_kind_r = ""
	took_off.emit()


func _land(n: Vector3, impact: float) -> void:
	airborne = false
	var hv := vel - n * vel.dot(n)
	var sp := hv.length()
	var vel_yaw := yaw_of(hv) if sp > 0.5 else heading
	var diff := wrapf(heading - vel_yaw, -PI, PI)
	var adiff := absf(diff)
	var is_switch := adiff > PI * 0.5
	var misalign := minf(adiff, PI - adiff)
	var grabbing := grab_l > 0.5 or grab_r > 0.5
	var pitch_off := absf(wrapf(air_pitch, -PI, PI))
	var d := diff()
	var tol := deg_to_rad(float(d["land_tol"]))
	var info := {
		"impact": impact, "misalign": rad_to_deg(misalign), "switch": is_switch, "air_time": air_time,
		"rotation": air_rotation, "grab_l": grab_time_l, "grab_r": grab_time_r, "speed": sp,
		"height": max_air_height, "distance": Vector2(position.x - takeoff_pos.x, position.z - takeoff_pos.z).length(),
		"crash": "", "flip": air_pitch, "pitch_peak": air_pitch_peak, "pitch_off": rad_to_deg(pitch_off),
		"grab_kind_l": grab_kind_l, "grab_kind_r": grab_kind_r,
	}
	ground_n = n
	compression = clampf(impact / 14.0, 0.1, 1.0) * (1.0 if air_time > 0.25 else 0.4)
	compression_vel = 0.0
	# crash conditions
	var reason := ""
	if pitch_off > tol + deg_to_rad(15.0) and air_time > 0.3:
		reason = "Landed on your back" if wrapf(air_pitch, -PI, PI) < 0.0 else "Landed on your head"
	elif impact > float(d["impact"]):
		reason = "Hard landing"
	elif impact > float(d["impact"]) - 7.0 and (misalign > deg_to_rad(32.0) or pitch_off > deg_to_rad(30.0)):
		reason = "Hard landing"
	elif misalign > tol and sp > 5.0 and air_time > 0.3:
		reason = "Landed sideways"
	elif grabbing and impact > 7.0 and air_time > 0.3:
		reason = "Held the grab too long"
	info["crash"] = reason
	if reason == "" and air_time > 0.3 and (misalign > deg_to_rad(25.0) or pitch_off > deg_to_rad(20.0) or impact > float(d["impact"]) - 6.0):
		sketchy = 0.8                  # arms windmilling, less grip for a moment
	vel = hv
	if reason == "":
		# absorb part of the impact
		vel *= 1.0 - clampf((impact - 5.0) * 0.012, 0.0, 0.12)
		if is_switch:
			heading = wrapf(heading + PI, -PI, PI)
			revert = PI * (1.0 if spin_vel >= 0.0 else -1.0)
		yaw_rate = 0.0
	spin_vel = 0.0
	flip_vel = 0.0
	air_pitch = 0.0
	grab_l = 0.0
	grab_r = 0.0
	_last_land_t = time
	landed.emit(info)
	if reason != "":
		crash(reason)


func crash(reason: String) -> void:
	push_phase = -1.0
	pushing = 0.0
	if is_crashed:
		return
	is_crashed = true
	crash_time = 0.0
	airborne = false
	charging = false
	charge = 0.0
	crashed.emit(reason, vel)


func respawn() -> void:
	if mode == Mode.LIFT:
		return
	var s := _pick_safe()
	if s.is_empty():
		return
	teleport(s["pos"], s["yaw"], 0.0, mode == Mode.WALK)
	respawned.emit()


# ------------------------------------------------------------------ obstacles & bounds
func _collide(dt: float) -> void:
	if obstacles == null:
		return
	_brush_cd = maxf(_brush_cd - dt, 0.0)
	var p := position
	for i in obstacles.query(p.x, p.z, 2.2):
		var kind := obstacles.kinds[i]
		var top := obstacles.tops[i]
		var base := obstacles.bases[i]
		if p.y > top or p.y + 1.7 < base:
			continue
		var o := Vector3(obstacles.xs[i], p.y, obstacles.zs[i])
		var r := obstacles.radii[i]
		var d := Vector2(p.x - o.x, p.z - o.z)
		var dist := d.length()
		if kind == Obstacles.Kind.TREE:
			var trunk := r * 0.22 + 0.32
			if dist < r and dist > trunk and _brush_cd <= 0.0:
				# brushing through snowy branches
				vel *= 1.0 - 0.5 * dt * 8.0
				tree_brush.emit(p + Vector3.UP * 1.2, clampf(speed / 15.0, 0.2, 1.0))
				_brush_cd = 0.25
			if dist >= trunk:
				continue
			r = trunk
		else:
			r += 0.3
			if dist >= r:
				continue
		var nrm := Vector3(d.x, 0, d.y) / maxf(dist, 0.001)
		var vn := vel.dot(nrm)
		if vn < 0.0:
			var limit := 9.0 if kind == Obstacles.Kind.TREE else 8.0
			if -vn > limit:
				position = Vector3(o.x, p.y, o.z) + nrm * r
				vel -= nrm * vn * 1.2
				crash("Hit a tree" if kind == Obstacles.Kind.TREE else "Collision")
				return
			vel -= nrm * vn * 1.3
			vel *= 0.75
		position = Vector3(o.x + nrm.x * r, position.y, o.z + nrm.z * r)


func _bounds() -> void:
	var m := 60.0
	var w := terrain.world
	var p := position
	var hit := false
	if p.x < m:
		p.x = m
		vel.x = maxf(vel.x, 0.0)
		hit = true
	elif p.x > w - m:
		p.x = w - m
		vel.x = minf(vel.x, 0.0)
		hit = true
	if p.z < m:
		p.z = m
		vel.z = maxf(vel.z, 0.0)
		hit = true
	elif p.z > w - m:
		p.z = w - m
		vel.z = minf(vel.z, 0.0)
		hit = true
	if hit:
		p.y = maxf(p.y, terrain.height(p.x, p.z))
		position = p
		if time - _bound_warn > 4.0:
			_bound_warn = time
			Game.notify.emit("Edge of the mountain range", "warning")


# ------------------------------------------------------------------ safe respawn points
func _update_safe(dt: float) -> void:
	_safe_timer += dt
	if _safe_timer < 1.0:
		return
	_safe_timer = 0.0
	_record_safe(false)


func _record_safe(force: bool) -> void:
	if not force:
		if airborne or is_crashed or time - _last_land_t < 1.0:
			return
		if slope > 38.0 or speed < 0.5:
			return
		if obstacles and obstacles.clearance(position.x, position.z, 4.0) < 3.0:
			return
	_safe.append({"pos": position, "yaw": yaw_of(vel) if speed > 1.0 else heading, "t": time})
	if _safe.size() > 40:
		_safe.pop_front()


func _pick_safe() -> Dictionary:
	if _safe.is_empty():
		return {}
	var ref_t := time - (crash_time if is_crashed else 0.0)
	for i in range(_safe.size() - 1, -1, -1):
		if ref_t - float(_safe[i]["t"]) >= 2.5:
			return _safe[i]
	return _safe[0]


# ------------------------------------------------------------------ transforms
func _compose_xform() -> Transform3D:
	var up := ground_n if (not airborne and mode == Mode.SKI) else Vector3.UP
	var f := forward_flat()
	f = (f - up * f.dot(up)).normalized()
	var x := f.cross(up).normalized()
	var b := Basis(x, up, -f)
	return Transform3D(b, position)


## Interpolated root transform for rendering (physics runs at 120 Hz).
func visual_xform() -> Transform3D:
	var t := Engine.get_physics_interpolation_fraction()
	var a := _prev_xform
	var b := _cur_xform
	if a.origin.distance_squared_to(b.origin) > 100.0:
		return b
	return Transform3D(a.basis.slerp(b.basis, t).orthonormalized(), a.origin.lerp(b.origin, t))


func lean_angle() -> float:
	# body inclination that balances the measured sideways acceleration of the path
	if airborne:
		return 0.0
	var a := atan2(lat_acc, G) * 0.92
	# hockey stop: lean into the hill against the skid
	a += edge_brake * stop_side * 0.55 * clampf(speed / 5.0, 0.3, 1.0)
	if not grind.is_empty():
		a = rail_balance * 0.6
	return clampf(a, -0.85, 0.85)


func speed_kmh() -> float:
	return speed * 3.6


# ------------------------------------------------------------------ hockey stop side
## Which way the skis pivot: the steered side if any, otherwise toward the hill (the natural
## "stop into the slope"), otherwise the direction of the current turn.
func _pick_stop_side(vdir: Vector3) -> float:
	if absf(_raw_steer) > 0.3:
		return signf(_raw_steer)
	var right := Vector3(vdir.x, 0.0, vdir.z).normalized().cross(Vector3.UP)
	var downhill := Vector3(ground_n.x, 0.0, ground_n.z)
	var across := downhill.dot(right)
	if absf(across) > 0.05:
		return -signf(across)          # downhill on the right -> tips turn left, up the hill
	if absf(lat_acc) > 1.0:
		return signf(lat_acc)
	return 1.0


# ------------------------------------------------------------------ on foot
func can_toggle_skis() -> bool:
	return mode != Mode.LIFT and not is_crashed and not airborne and not frozen and (mode == Mode.WALK or speed < 3.0)


## Takes the skis off (walk / hike) or clicks back into them.
func toggle_skis() -> bool:
	if not can_toggle_skis():
		return false
	if mode == Mode.SKI:
		push_phase = -1.0
		pushing = 0.0
		mode = Mode.WALK
		heading = travel_yaw if speed > 0.5 else heading
	else:
		mode = Mode.SKI
		_reset_motion()
	vel = Vector3.ZERO
	speed = 0.0
	_walk_vy = 0.0
	_walk_air = false
	gear_anim = 1.0
	mode_changed.emit(mode)
	return true


func _walk_step(dt: float) -> void:
	var fwd_in := _in("tuck") - _in("brake")
	var side_in := _in("steer_right") - _in("steer_left")
	var mv := Vector2(side_in, fwd_in)
	if mv.length() > 1.0:
		mv = mv.normalized()
	# camera-relative movement
	var cf := forward_flat_s(cam_yaw)
	var cr := cf.cross(Vector3.UP)
	var want := cf * mv.y + cr * mv.x
	var p := position
	var n := terrain.normal(p.x, p.z, 1.2)
	ground_n = n
	slope = rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))
	surface = terrain.surface_at(p.x, p.z)
	var powder := surface.r * (1.0 - surface.g)
	var target_speed := (JOG_SPEED if _pressed("carve") else WALK_SPEED) * want.length()
	var dir := Vector3.ZERO
	if want.length() > 0.05:
		dir = want.normalized()
		# hiking uphill is slow, deep snow is slower, and too steep is impossible
		# grade over a couple of metres, so small bumps do not stop the hike
		var grade := rad_to_deg(atan((terrain.height(p.x + dir.x * 1.6, p.z + dir.z * 1.6) - terrain.height(p.x - dir.x * 1.6, p.z - dir.z * 1.6)) / 3.2))
		var up_f := clampf(1.0 - maxf(grade - 6.0, 0.0) / 34.0, 0.22, 1.0)
		if grade > MAX_HIKE_SLOPE:
			up_f = 0.0
		target_speed *= up_f * (1.0 - 0.35 * powder)
		heading = lerp_angle(heading, yaw_of(dir), 1.0 - exp(-10.0 * dt))
	var hv := Vector3(vel.x, 0.0, vel.z)
	hv = hv.lerp(dir * target_speed, 1.0 - exp(-9.0 * dt))
	# ground too steep to stand on: slide down slowly
	if slope > MAX_HIKE_SLOPE + 4.0 and not _walk_air:
		hv += Vector3(n.x, 0.0, n.z).normalized() * (slope - MAX_HIKE_SLOPE) * 0.25 * dt
	vel = hv
	p.x += hv.x * dt
	p.z += hv.z * dt
	var gh := terrain.height(p.x, p.z)
	var jump := _pressed("jump")
	if _walk_air:
		_walk_vy -= G * dt
		p.y += _walk_vy * dt
		if p.y <= gh:
			p.y = gh
			_walk_air = false
			_walk_vy = 0.0
	else:
		p.y = gh
		if jump and not _jump_prev:
			_walk_vy = 3.4
			_walk_air = true
	_jump_prev = jump
	position = p
	airborne = false
	contact = not _walk_air
	_bounds()
	_collide(dt)
	speed = hv.length()
	travel_yaw = heading
	lat_acc = 0.0
	tuck = 0.0
	brake = 0.0
	edge_brake = 0.0
	edge = 0.0
	skid = 0.0
	carve_g = 0.0
	# gait: one full cycle = two steps of ~0.7 m (longer strides when jogging)
	var stride := lerpf(0.7, 1.05, clampf((speed - WALK_SPEED) / (JOG_SPEED - WALK_SPEED), 0.0, 1.0))
	walk_phase = fmod(walk_phase + speed * dt / (stride * 2.0) * TAU, TAU * 64.0)
	_update_safe(dt)


# ------------------------------------------------------------------ chairlift
func begin_lift() -> void:
	if mode != Mode.LIFT:
		_mode_before_lift = mode
	mode = Mode.LIFT
	lift_seated = true
	_reset_motion()
	vel = Vector3.ZERO
	mode_changed.emit(mode)


## Called by the lift every frame while riding: the seat transform (origin on the seat, -Z forward).
func set_lift_xform(xf: Transform3D, v: Vector3) -> void:
	position = xf.origin
	vel = v
	speed = v.length()
	var f := -xf.basis.z
	heading = yaw_of(f)
	travel_yaw = heading
	ground_n = Vector3.UP
	_cur_xform = xf
	_prev_xform = xf


func end_lift(pos: Vector3, yaw: float, push: float) -> void:
	lift_seated = false
	mode = _mode_before_lift if _mode_before_lift != Mode.LIFT else Mode.SKI
	var walking := mode == Mode.WALK
	teleport(pos, yaw, 0.0 if walking else push, true)
	mode_changed.emit(mode)


# ------------------------------------------------------------------ rails and boxes
func is_grinding() -> bool:
	return not grind.is_empty()


## Boxes (low) can be ridden onto from the snow; rails (higher) need a pop.
func _try_mount() -> void:
	for r: Dictionary in rails:
		var a: Vector3 = r["a"]
		var ab: Vector3 = r["b"] - a
		var length := ab.length()
		var dir := ab / length
		var t := (position - a).dot(dir)
		if t < 0.3 or t > length - 0.6:
			continue
		var top := a + dir * t
		var side := dir.cross(Vector3.UP).normalized()
		var lat := (position - top).dot(side)
		if absf(lat) > float(r["width"]) * 0.5 + 0.12:
			continue
		var dy := position.y - top.y
		if dy < (-0.42 if r["kind"] == "box" else -0.1) or dy > 0.45:
			continue
		var vh := vel.dot(dir)
		if absf(vh) < 2.0 or (airborne and vel.y > 1.0):
			continue
		_mount(r, t, lat / (float(r["width"]) * 0.5 + 0.3), vh)
		return


func _mount(r: Dictionary, t: float, lat01: float, vh: float) -> void:
	if airborne and absf(wrapf(air_pitch, -PI, PI)) > deg_to_rad(50.0):
		crash("Missed the rail")
		return
	grind = r
	var along: Vector3 = (r["b"] - r["a"]).normalized()
	_box_lateral = (position - (r["a"] + along * t)).dot(along.cross(Vector3.UP).normalized())
	_box_lateral_speed = vel.dot(along.cross(Vector3.UP).normalized())
	_grind_dir = signf(vh)
	_grind_t = t
	_grind_v = absf(vh) * 0.95
	var axis: Vector3 = (r["b"] - r["a"]).normalized() * _grind_dir
	var ay := yaw_of(Vector3(axis.x, 0.0, axis.z))
	# stance from how you land on it: along the rail (50-50) or across it (slide)
	var rel := wrapf(heading - ay, -PI, PI)
	grind_slide = absf(rel) > PI * 0.25 and absf(rel) < PI * 0.75
	grind_switch = absf(rel) >= PI * 0.75
	heading = wrapf(ay + (signf(rel) * PI * 0.5 if grind_slide else (PI if grind_switch else 0.0)), -PI, PI)
	_grind_entry = air_rotation if airborne else 0.0
	airborne = false
	spin_vel = 0.0
	flip_vel = 0.0
	air_pitch = 0.0
	yaw_rate = 0.0
	rail_balance = clampf(lat01 * 0.4, -0.5, 0.5)
	_rail_bal_vel = 0.0
	grind_time = 0.0
	grind_press = 0.0
	compression = 0.3


func _grind_step(dt: float) -> void:
	var r := grind
	var a: Vector3 = r["a"]
	var dir: Vector3 = (r["b"] - a).normalized()
	var axis := dir * _grind_dir
	var d := diff()
	# speed along the rail: gravity, sliding friction (more when sideways), air drag
	var mu := (0.035 if r["kind"] == "rail" else 0.06) + (0.04 if grind_slide else 0.0)
	_grind_v += (-G * axis.y - mu * G - 0.003 * _grind_v * _grind_v) * dt
	_grind_t += _grind_v * dt * _grind_dir
	grind_time += dt
	ground_time = 0.0
	if absf(lean_fa) > 0.5:
		grind_press += signf(lean_fa) * dt
	# balance: an inverted pendulum held with A/D (assist and instability depend on difficulty)
	var k := float(d["rail"])
	var wobble := sin(time * 2.3 + _grind_t * 1.7) * 0.6 + sin(time * 5.3) * 0.4
	_rail_bal_vel += (rail_balance * (2.0 * k - float(d["rail_assist"])) + wobble * k * 0.5 + _raw_steer * 5.0) * dt
	_rail_bal_vel *= 1.0 - 1.8 * dt
	rail_balance += _rail_bal_vel * dt
	var top := a + dir * _grind_t
	position = top
	vel = axis * _grind_v
	if r["kind"] == "box":
		var across := dir.cross(Vector3.UP).normalized()
		_box_lateral_speed = move_toward(_box_lateral_speed, _raw_steer * 1.6, 2.5 * dt)
		_box_lateral += _box_lateral_speed * dt
		position += across * _box_lateral
		vel += across * _box_lateral_speed
		if absf(_box_lateral) > float(r["width"]) * 0.5:
			_leave_rail("edge")
			_take_off()
			return
	speed = _grind_v
	contact = false
	ground_n = Vector3.UP
	travel_yaw = yaw_of(Vector3(axis.x, 0.0, axis.z))
	lat_acc = 0.0
	if r["kind"] != "box" and absf(rail_balance) >= 1.0:
		var side := dir.cross(Vector3.UP).normalized() * signf(rail_balance)
		_leave_rail("fall")
		if bool(d["edge_catch"]):
			crash("Fell off the rail")
			return
		position += side * 0.35
		vel += side * 1.5 + Vector3.UP * 1.0
		_take_off()
	elif _grind_t > float(r["length"]) and r.has("next") and _grind_dir > 0.0:
		# Continue the same trick across the joint without resetting balance or score.
		_grind_t -= float(r["length"])
		grind = r["next"]
	elif _grind_t < 0.0 or _grind_t > float(r["length"]) or _grind_v < 0.3:
		_leave_rail("end" if _grind_v >= 0.3 else "stall")
		vel += Vector3.UP * 0.4
		_take_off()


func _leave_rail(how: String) -> void:
	var r := grind
	grind = {}
	_rail_cd = 0.4
	jibbed.emit({"kind": r["kind"], "time": grind_time, "slide": grind_slide, "switch": grind_switch,
		"press": grind_press, "entry_rot": _grind_entry, "how": how})


func gap_to_snow() -> float:
	return position.y - ground_h


## Three longitudinal samples per ski. A ski bridges small hollows; a whole unsupported
## ski loses grip independently. The finite footprint filters chatter without moving the map.
func _sample_skis(at: Vector3, update_support: bool) -> float:
	var f := forward_flat()
	var right := f.cross(Vector3.UP)
	var center_n := terrain.normal(at.x, at.z, 1.2)
	var sum_height := 0.0
	var high_support := -INF
	var low_support := INF
	for i in 2:
		var off := right * (-0.15 if i == 0 else 0.15)
		var c := at + off
		var tip := c + f * 0.72
		var tail := c - f * 0.72
		var ht := terrain.height(tip.x, tip.z)
		var hc := terrain.height(c.x, c.z)
		var hb := terrain.height(tail.x, tail.z)
		var h := (ht + 2.0 * hc + hb) * 0.25
		var lateral := -(center_n.x * off.x + center_n.z * off.z) / maxf(center_n.y, 0.2)
		sum_height += h - lateral
		high_support = maxf(high_support, h - lateral)
		low_support = minf(low_support, h - lateral)
		if update_support:
			ski_heights[i] = h
			var along := (f * 1.44 + Vector3.UP * (ht - hb)).normalized()
			var rn := terrain.normal(c.x, c.z, 0.6)
			var across := (right - rn * right.dot(rn)).normalized()
			ski_normals[i] = across.cross(along).normalized()
			var clearance := at.y + lateral - h
			ski_support[i] = 1.0 - smoothstep(CONTACT_EPS, suspension_travel, clearance)
	# A ski hanging over a ledge cannot pull the supported ski through the snow.
	return high_support if high_support - low_support > suspension_travel else sum_height * 0.5
