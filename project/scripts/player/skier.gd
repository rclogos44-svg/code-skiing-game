class_name Skier
extends Node3D
## Physically motivated skiing controller (custom integrator, 120 Hz).
##
## Ground model: gravity along the slope, sidecut carving (turn radius = R_sidecut * cos(edge))
## limited by edge grip, lossless redirection while the edge holds and friction when it skids,
## snow friction per surface type, powder drag, aerodynamic drag (tuck vs upright) and the hockey
## stop.  The body's weight shifts fore/aft (arrow keys): leaning back loads the tails for a bigger
## pop, and a spin is wound up on the ground.  Air: ballistic flight; spin and flip rotation come
## from takeoff (wind-up, leaning at the pop, the lip itself) and change speed with body shape
## (tucked or grabbing spins faster); in-air control depends on the difficulty.  Landings are
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
const SPIN_MAX := 6.3                # ~1 turn per second, like a real 360 off a park jump
const SPIN_ACCEL := 20.0
const SPIN_DAMP := 7.0
const WALK_SPEED := 1.8
const JOG_SPEED := 3.4
const MAX_HIKE_SLOPE := 40.0
const GRABS := true
const GRAB_IN := 0.55               # seconds to reach a grab (it takes time to get the hand to the ski)
const GRAB_OUT := 0.35              # seconds to let go and open back up
const GRAB_AUTO_RELEASE := 0.3      # assisted difficulties let go this long before touchdown (s)
const WIND_SPIN := 5.4             # spin rate (rad/s) the unwinding body reaches after a full wind-up
const UNWIND_TIME := 0.35          # the spin builds up over this long after takeoff (hips follow shoulders)
const PUSH_MAX := 6.5              # W pole-pushes only below this speed (m/s, ~23 km/h); faster, it does nothing
const FLIP_POP := 3.8              # flip rate (rad/s) from leaning fully at the pop
## Easy / Normal / Realistic: in-air spin & flip authority (rad/s^2), spin damping, auto-levelling
## toward a clean landing, landing tolerance (deg), impact limit and edge catching.
const DIFFICULTY := [
	{"name": "Easy", "air_spin": 11.0, "spin_damp": 7.0, "air_flip": 9.0, "level": 3.0, "land_tol": 62.0, "impact": 24.0, "edge_catch": false, "rail": 1.0, "rail_assist": 3.0},
	{"name": "Normal", "air_spin": 7.5, "spin_damp": 3.0, "air_flip": 6.0, "level": 1.8, "land_tol": 50.0, "impact": 20.0, "edge_catch": false, "rail": 2.0, "rail_assist": 1.2},
	{"name": "Realistic", "air_spin": 4.5, "spin_damp": 0.8, "air_flip": 3.0, "level": 0.0, "land_tol": 40.0, "impact": 17.0, "edge_catch": true, "rail": 3.2, "rail_assist": 0.0},
]

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
var riding_switch := false         # going backwards (skis' tails first); the body faces back up the hill
var stance_vis := 0.0              # body yaw on top of the heading: 0 forward, PI switch, in between mid-180
var takeoff_switch := false        # was switch at the last takeoff (for trick names)
var _stance_left := 0.0            # ground 180 still to turn (rad), its direction, cooldown, button edge
var _stance_dir := 1.0
var _stance_cd := 0.0
var _stance_prev := false
var takeoff_pos := Vector3.ZERO
var max_air_height := 0.0
var pushing := 0.0
var _want_push := false
var push_phase := 0.0             # double-pole stroke 0..1: reach, plant + drive (0.25-0.65), recover
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
var wind := 0.0                    # upper body wound up for a spin (+ = a right spin: shoulders coiled left), on the ground
var flip_tuck := 0.0               # 0 = laid-out flip, 1 = tucked (pulled in after the first rotation)
var _spin_target := 0.0
var _unwind := 0.0
var _spin_latch := 0.0             # direction of the wind-up key still held after takeoff (ignored until released)
var tail_load := 0.0               # crouching while leaning back: extra pop
var flip_vel := 0.0                # rad/s, + = forward (front flip)
var air_pitch := 0.0               # flip rotation so far (rad)
var air_up := Vector3.UP           # body "up" in the air before flips: leaves the lip square to it and
                                   # tilts toward the slope (or pipe wall) he's going to land on
var land_n := Vector3.UP           # predicted landing surface normal, and how long until touchdown
var land_t := 9.0
var _land_probe := 0
var air_pitch_peak := 0.0          # largest |pitch| reached in this jump (corks)
var sketchy := 0.0                 # > 0 while recovering from a sketchy landing (s)
var grab_kind_l := ""              # "", "tip" or "tail"
var grab_held := false             # a grab key is held (the pose eases in while it is)
var grab_name := ""                # the grab being held: Mute, Safety, Japan, Tail, Tip, Truck Driver, Blunt
var grab_time := 0.0
var _jump_grab := ""               # the grab done on this jump (scored at landing)
var _s_grabbed := false           # S was used to pick a back-of-ski grab on this jump
var _brake_block := false          # ... and is still held after landing: it doesn't brake until re-pressed
var grab_kind_r := ""
var _ground_pitch := 0.0           # pitch of the snow along the direction of travel
var _ground_pitch_rate := 0.0      # how fast it changes (a kicker's lip throws you backward)
var rails: Array = []              # jib features {a, b (top line), kind, width, length}, set by the park
var grind := {}                    # the rail being slid
var grind_slide := false           # skis across the rail (slide) instead of along it (50-50)
var grind_switch := false
var _stance_off := 0.0             # skis' angle to the rail while on it (0 50-50, +-90 slide, 180 switch)
var _grind_yaw := 0.0
var _rspin_left := 0.0             # on-rail spin still to turn (rad), its direction, and the total
var _rspin_dir := 1.0
var _rspin_total := 0.0
var _set_x := 0                    # the Left/Right arrow last set (for on-rail spin taps)
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
## Arrow tricks (no jump key needed): hold an arrow to "set" (crouch / coil), then press the
## opposite arrow to pop and do that trick - set Up then Down = backflip, set Down then Up = front
## flip, set Right then Left = left spin, set Left then Right = right spin (set two arrows for a
## flip + spin). Let go of the set arrow without pressing the opposite = a straight pop (ollie).
var trick_set := Vector2i.ZERO     # x: +1 Right / -1 Left set; y: +1 Up / -1 Down set
var _set_time := 0.0
var _arrow_trick := false          # the coming takeoff is an arrow pop: flip from _pop_flip, not the lean
var _pop_flip := 0.0
var _latched := {}                 # set arrows still held after the pop: ignored until released
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
	off_family = ""
	off_angle = 0.0
	off_max_tilt = 0.0
	_reset_trick_input()
	if not keep_mode and mode != Mode.SKI:
		mode = Mode.SKI
		mode_changed.emit(mode)
	lift_seated = false
	var h := terrain.height(pos.x, pos.z)
	position = Vector3(pos.x, h + 0.02, pos.z)
	heading = yaw
	ground_n = terrain.normal(pos.x, pos.z, 1.2)
	air_up = Vector3.UP
	land_t = 9.0
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
	riding_switch = false
	stance_vis = 0.0
	_stance_left = 0.0
	_stance_cd = 0.0
	steep_time = 0.0
	stop_side = 0.0
	edge_brake = 0.0
	brake = 0.0
	tuck = 0.0
	lean_fa = 0.0
	wind = 0.0
	tail_load = 0.0
	flip_vel = 0.0
	air_pitch = 0.0
	air_pitch_peak = 0.0
	sketchy = 0.0
	_ground_pitch_rate = 0.0
	grind = {}


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


func _ink(action: String) -> float:
	return 0.0 if _latched.has(action) else _in(action)


## Arrow trick input - an explicit state machine (see the control table in FREESTYLE.md):
##   IDLE -> PREPARE: press an arrow on the snow: he loads into it (crouch, coil / lean), charge
##     builds to its cap in 0.55 s and stays there however long it's held.
##   PREPARE -> trick: a NEW press of a second arrow resolves the trick from (prepared, second):
##     opposite = a flip or spin, perpendicular = an off-axis trick (rodeo / misty / cork / bio).
##     Near a kicker lip it waits (PENDING) and goes at the takeoff, otherwise it pops right away.
##   PREPARE -> IDLE: let go of the prepared arrow alone = a straight pop (ollie); a short tap of
##     Left / Right on a rail = a rail spin; a tap under 0.1 s does nothing.
##   AIR: in the first 0.3 s off a lip, prepare + second arrow still starts a trick (weaker); after
##     that the arrows only adjust the rotation that's going (body english, within limits).
##   RECOVER: 0.25 s after touchdown new presses are ignored (no accidental tricks off a landing).
## Each initiation is consumed once: the arrows still held are latched and do nothing until let go.
enum TrickState { IDLE, PREPARE, PENDING, AIR, RECOVER }
const ARROW_BITS := {"lean_right": 1, "lean_left": 2, "lean_forward": 4, "lean_back": 8}
const PREP_MIN := 0.06              # a second arrow counts once the first has been held this long
const TAKEOFF_BUFFER := 0.9         # longest a trick waits for the lip (s)
const LATE_WINDOW := 0.3            # an off-the-lip initiation still counts this long into the air (s)
const RECOVER_TIME := 0.25
var trick_state := TrickState.IDLE
var prep_dir := Vector2i.ZERO        # prepared arrow: (1,0) Right, (-1,0) Left, (0,1) Up, (0,-1) Down
var _prep_t := 0.0
var _keys_prev := 0
var pending_trick := {}              # resolved, waiting for the lip
var _pending_t := 0.0
var _recover_t := 0.0
var trick_label := ""                # what the input resolved to (HUD)
var _late_used := false


static func _dir_of_bit(bit: int) -> Vector2i:
	match bit:
		1: return Vector2i(1, 0)
		2: return Vector2i(-1, 0)
		4: return Vector2i(0, 1)
		8: return Vector2i(0, -1)
	return Vector2i.ZERO


static func _bit_of_dir(d: Vector2i) -> int:
	if d.x == 1: return 1
	if d.x == -1: return 2
	if d.y == 1: return 4
	if d.y == -1: return 8
	return 0


## The trick for a prepared arrow followed by a second one.  The prepared arrow coils you the
## opposite way, the second snaps you in its own direction:
##   opposite:  Up>Down backflip, Down>Up front flip, Left>Right right spin, Right>Left left spin
##   flip-led off-axis (prepared Up / Down, then Left / Right):  Up>Right rodeo right,
##     Up>Left rodeo left, Down>Right misty right, Down>Left misty left
##   spin-led off-axis (prepared Left / Right, then Down / Up): Left>Down cork right,
##     Right>Down cork left, Left>Up bio right, Right>Up bio left
static func resolve_trick(prep: Vector2i, second: Vector2i) -> Dictionary:
	if second == -prep:
		if prep.y != 0:
			return {"kind": "flip", "flip": float(-prep.y), "label": "BACKFLIP" if prep.y > 0 else "FRONT FLIP"}
		return {"kind": "spin", "spin": float(-prep.x), "label": "RIGHT SPIN" if prep.x < 0 else "LEFT SPIN"}
	if prep.y != 0 and second.x != 0:
		var fam := "rodeo" if prep.y > 0 else "misty"
		return {"kind": "offaxis", "family": fam, "dir": float(second.x), "label": "%s %s" % [fam.to_upper(), "RIGHT" if second.x > 0 else "LEFT"]}
	if prep.x != 0 and second.y != 0:
		var fam2 := "cork" if second.y < 0 else "bio"
		var d := float(-prep.x)                    # prepared Left coils you for a RIGHT rotation
		return {"kind": "offaxis", "family": fam2, "dir": d, "label": "%s %s" % [fam2.to_upper(), "RIGHT" if d > 0 else "LEFT"]}
	return {}


func _reset_trick_input() -> void:
	trick_state = TrickState.IDLE
	prep_dir = Vector2i.ZERO
	trick_set = Vector2i.ZERO
	_prep_t = 0.0
	_set_time = 0.0
	pending_trick = {}
	_late_used = false


## Focus lost: forget the arrows without doing anything (a half-prepared trick doesn't pop).
func cancel_trick_input() -> void:
	if trick_state in [TrickState.PREPARE, TrickState.PENDING]:
		trick_state = TrickState.IDLE
	prep_dir = Vector2i.ZERO
	trick_set = Vector2i.ZERO
	pending_trick = {}
	_keys_prev = 0
	_latched.clear()


## Arrow trick input (state machine above).  `trick_set` mirrors the prepared arrow for the pose.
func _arrow_tricks(dt: float) -> void:
	var held := 0
	for a in ARROW_BITS:
		if _ink(a) > 0.5:
			held |= int(ARROW_BITS[a])
	var pressed := held & ~_keys_prev
	_keys_prev = held
	if is_crashed or mode != Mode.SKI:
		_reset_trick_input()
		return
	if trick_state == TrickState.RECOVER:
		_recover_t -= dt
		if _recover_t > 0.0:
			return
		trick_state = TrickState.IDLE
		pressed = 0                         # keys still down from the air don't start a new trick
	if airborne and _coyote <= 0.0:
		if trick_state == TrickState.PREPARE:
			# rolled off the lip prepared but never initiated: a straight air; the held arrow is latched
			_latch_set()
			prep_dir = Vector2i.ZERO
			trick_set = Vector2i.ZERO
			trick_state = TrickState.AIR
			_set_time = 0.0
		elif trick_state != TrickState.AIR:
			trick_state = TrickState.AIR
		# late initiation off a lip: two arrows (the second a new press) in the first LATE_WINDOW s
		if not _late_used and air_time < LATE_WINDOW and off_family == "" and absf(flip_vel) < 1.0 and absf(spin_vel) < 2.0:
			var first := held & ~pressed
			if first != 0 and pressed != 0:
				var t := resolve_trick(_dir_of_bit(_lowest_bit(first)), _dir_of_bit(_lowest_bit(pressed)))
				if not t.is_empty():
					_late_used = true
					_latch_keys(first)
					_start_trick_in_air(t, 0.65)
		return
	match trick_state:
		TrickState.AIR:
			trick_state = TrickState.IDLE
		TrickState.IDLE:
			if pressed != 0:
				# first arrow wins; two pressed on the same step: Up / Down before Left / Right
				var bit := 4 if pressed & 4 else (8 if pressed & 8 else (2 if pressed & 2 else 1))
				prep_dir = _dir_of_bit(bit)
				trick_set = prep_dir
				if prep_dir.x != 0:
					_set_x = prep_dir.x
				_prep_t = 0.0
				_set_time = 0.0
				trick_state = TrickState.PREPARE
		TrickState.PREPARE:
			_prep_t += dt
			_set_time = _prep_t
			charge = minf(charge + dt / 0.55, 1.0)      # crouch / load while prepared, capped
			var pbit := _bit_of_dir(prep_dir)
			var second := pressed & ~pbit
			if second != 0 and _prep_t >= PREP_MIN:
				var t2 := resolve_trick(prep_dir, _dir_of_bit(_lowest_bit(second)))
				# the prepared arrow is spent (it would fight the trick); keeping the second one held
				# drives the rotation on in the air (body english)
				_latch_keys(held & pbit)
				_initiate(t2)
			elif held & pbit == 0:
				# let go of the prepared arrow alone
				if not grind.is_empty() and prep_dir.x != 0 and _prep_t < 0.3:
					rail_spin(float(prep_dir.x))        # on a rail / box: a tap of Left / Right spins you on it
				elif _prep_t > 0.1:
					_initiate({"kind": "ollie", "label": "OLLIE"})
				prep_dir = Vector2i.ZERO
				trick_set = Vector2i.ZERO
				_set_time = 0.0
				if trick_state == TrickState.PREPARE:
					trick_state = TrickState.IDLE
		TrickState.PENDING:
			_pending_t -= dt
			if _pending_t <= 0.0:
				# no lip came: pop it here
				var t3 := pending_trick
				pending_trick = {}
				trick_state = TrickState.IDLE
				_pop_with(t3)


static func _lowest_bit(m: int) -> int:
	for b in [4, 8, 2, 1]:
		if m & b:
			return b
	return 0


func _latch_keys(held: int) -> void:
	for a in ARROW_BITS:
		if held & int(ARROW_BITS[a]):
			_latched[a] = true


func _latch_set() -> void:
	if prep_dir.x != 0:
		_latched["lean_right" if prep_dir.x == 1 else "lean_left"] = true
	if prep_dir.y != 0:
		_latched["lean_forward" if prep_dir.y == 1 else "lean_back"] = true


## A trick has been resolved: wait for the lip if one is coming, otherwise pop now.
func _initiate(t: Dictionary) -> void:
	prep_dir = Vector2i.ZERO
	trick_set = Vector2i.ZERO
	_set_time = 0.0
	if t.is_empty():
		trick_state = TrickState.IDLE
		return
	trick_label = String(t.get("label", ""))
	if t["kind"] != "ollie" and grind.is_empty() and _lip_ahead():
		pending_trick = t.duplicate()
		pending_trick["charge"] = charge
		_pending_t = TAKEOFF_BUFFER
		trick_state = TrickState.PENDING
		return
	trick_state = TrickState.IDLE
	_pop_with(t)


## Is a kicker lip (or step-up) coming within ~0.7 s along the way he's going?
func _lip_ahead() -> bool:
	var hv := Vector3(vel.x, 0.0, vel.z)
	if hv.length() < 3.0:
		return false
	var dirv := hv.normalized()
	var best := 0.0
	var prev := terrain.feature_offset(position.x, position.z)
	for i in range(1, 8):
		var q := position + dirv * hv.length() * 0.1 * i
		var f := terrain.feature_offset(q.x, q.z)
		if f > 0.25 and f >= prev - 0.02:
			best = maxf(best, f)
		prev = f
	return best > 0.25


## Pop off the snow (or a rail) into trick t.
func _pop_with(t: Dictionary) -> void:
	_arrow_trick = true
	match String(t["kind"]):
		"flip":
			_pop_flip = float(t["flip"])
			wind = 0.0
		"spin":
			_pop_flip = 0.0
			wind = float(t["spin"]) * maxf(absf(wind), 0.75)    # + = right spin; the coil while prepared adds
		_:
			_pop_flip = 0.0
			wind = 0.0
	if airborne:
		airborne = false        # popped a moment after leaving the lip: still counts as the takeoff
	_do_jump()
	_arrow_trick = false
	_spin_latch = 0.0
	if t["kind"] == "offaxis":
		_start_offaxis(String(t["family"]), float(t["dir"]), charge_at_pop)


## A trick resolved at the lip (PENDING) or late in the air.
func _start_trick_in_air(t: Dictionary, strength: float) -> void:
	trick_label = String(t.get("label", ""))
	match String(t["kind"]):
		"flip":
			flip_vel += float(t["flip"]) * FLIP_POP * strength * (0.75 + 0.25 * charge_at_pop)
		"spin":
			_spin_target = float(t["spin"]) * WIND_SPIN * strength * (0.7 + 0.3 * charge_at_pop)
			_unwind = UNWIND_TIME
		"offaxis":
			_start_offaxis(String(t["family"]), float(t["dir"]), charge_at_pop * strength)


# ------------------------------------------------------------------ off-axis tricks
## Off-axis families (FREESTYLE.md has the research): a spin about the takeoff vertical (kept in
## `heading`, so the camera, switch landings and naming work as for spins) plus ONE off-axis flip
## about a diagonal body axis that turns with the spin - full flip + whole half-turns of spin
## always ends upright.  The axis mixes the backflip (+X) or front flip (-X) axis with a roll
## toward the lead shoulder, and leans up toward the spin axis by `elev` (a cork stays a cork -
## never fully inverted - while rodeos and mistys go feet over head).  Spin-led families start the
## spin at once and drop into the off-axis flip; flip-led ones go back / forward first and the
## spin grows.  Rates are rad/s at no charge -> full charge.
##   flip: +1 back, -1 forward; roll / elev in degrees; flip_in / spin_in: ramp-in times (s)
const OFFAXIS := {
	"cork": {"flip": 1.0, "roll": 60.0, "elev": 42.0, "min_tilt": 80.0, "flip_rate": [3.6, 4.8], "spin_rate": [4.4, 6.8], "flip_in": 0.25, "spin_in": 0.05,
		"tuck": 0.85, "spin_max": 8.5},
	"bio": {"flip": -1.0, "roll": 55.0, "elev": 36.0, "min_tilt": 60.0, "flip_rate": [3.6, 4.8], "spin_rate": [4.2, 6.4], "flip_in": 0.25, "spin_in": 0.05,
		"tuck": 0.8, "spin_max": 8.0},
	"rodeo": {"flip": 1.0, "roll": 28.0, "elev": 6.0, "min_tilt": 120.0, "flip_rate": [4.4, 5.8], "spin_rate": [1.9, 3.0], "flip_in": 0.05, "spin_in": 0.35,
		"tuck": 0.6, "spin_max": 6.0},
	"misty": {"flip": -1.0, "roll": 30.0, "elev": 6.0, "min_tilt": 120.0, "flip_rate": [4.4, 5.8], "spin_rate": [2.0, 3.2], "flip_in": 0.05, "spin_in": 0.35,
		"tuck": 0.9, "spin_max": 6.0},
}
const OFF_MIN_AIR := 0.75           # less air than this (predicted) and an off-axis becomes a flat spin
var off_family := ""
var off_dir := 0.0                  # +1 right, -1 left
var off_axis := Vector3.ZERO        # body frame (x right, y up, z back), turns with the spin
var off_angle := 0.0                # off-axis flip so far (rad)
var off_rate := 0.0                 # flip rate (rad/s)
var off_spin_rate := 0.0            # spin rate (rad/s, magnitude)
var off_t := 0.0
var off_max_tilt := 0.0             # largest angle of his body's up from the sky's (deg): the inversion
var charge_at_pop := 0.0


func _start_offaxis(fam: String, d: float, chg: float) -> void:
	var F: Dictionary = OFFAXIS[fam]
	var T := _predict_air_time()
	if T < OFF_MIN_AIR:
		# not enough air for the off-axis part: a flat spin that way instead
		_spin_target = d * WIND_SPIN * (0.7 + 0.3 * chg)
		_unwind = UNWIND_TIME
		trick_label = "TOO LOW · SPIN"
		return
	var roll := deg_to_rad(float(F["roll"]))
	var elev := deg_to_rad(float(F["elev"]))
	var flipax := Vector3(float(F["flip"]), 0.0, 0.0)
	var rollax := Vector3(0.0, 0.0, -d)                  # dropping the lead shoulder
	var spinax := Vector3(0.0, -d, 0.0)                  # the way the spin turns
	off_axis = ((flipax * cos(roll) + rollax * sin(roll)) * cos(elev) + spinax * sin(elev)).normalized()
	off_family = fam
	off_dir = d
	off_angle = 0.0
	off_t = 0.0
	off_max_tilt = 0.0
	var fr: Array = F["flip_rate"]
	var sr: Array = F["spin_rate"]
	off_rate = lerpf(fr[0], fr[1], clampf(chg, 0.0, 1.0))
	off_spin_rate = lerpf(sr[0], sr[1], clampf(chg, 0.0, 1.0))
	# the off-axis replaces the plain flip / spin of the pop
	flip_vel = 0.0
	air_pitch = 0.0
	_spin_target = 0.0
	_unwind = 0.0
	spin_vel = 0.0


## Ballistic time to the snow from here (the same probe the landing tilt uses).
func _predict_air_time() -> float:
	var p := position
	var v := vel
	for i in 150:
		v += Vector3.DOWN * G * 0.02
		p += v * 0.02
		if p.y <= terrain.height(p.x, p.z):
			return (i + 1) * 0.02
	return 3.0


## One air step of an off-axis trick: the flip and spin follow the family's timing; the arrows
## speed up / slow down each within limits; past 300 deg of flip he opens up so the flip finishes
## at touchdown; near touchdown a nearly-finished spin is eased onto the half-turn (difficulty
## `level`, none on Realistic).
func _offaxis_step(dt: float, spin_in: float, flip_in: float) -> void:
	var F: Dictionary = OFFAXIS[off_family]
	var d := diff()
	off_t += dt
	# body english: spin key the trick's way spins faster, the other way slower (never reverses)
	var smax: float = F["spin_max"]
	var sr: Array = F["spin_rate"]
	if absf(spin_in) > 0.1:
		var want := smax if signf(spin_in) == off_dir else float(sr[0]) * 0.5
		off_spin_rate = move_toward(off_spin_rate, want, float(d["air_spin"]) * 0.6 * dt)
	# flip key the trick's way (Down for back families, Up for forward) flips faster, the other slower
	var flip_key := -flip_in * float(F["flip"])        # flip_in: + = forward lean
	if absf(flip_key) > 0.1:
		off_rate = move_toward(off_rate, 7.0 if flip_key > 0.0 else 2.4, float(d["air_flip"]) * 0.5 * dt)
	var rate := off_rate
	if off_angle >= TAU - 0.01 and absf(flip_key) < 0.1:
		# flip finished: he's opened right up and waits for the snow (still pulling = over-rotating)
		off_rate = move_toward(off_rate, 0.0, 30.0 * dt)
		rate = off_rate
	elif off_angle > deg_to_rad(300.0):
		# opening up: just enough to finish the flip at touchdown (never faster than he was going)
		var need := (TAU - off_angle) / maxf(land_t - 0.1, 0.15)
		off_rate = move_toward(off_rate, clampf(need, 0.6, off_rate), 9.0 * dt)
		rate = off_rate
	off_angle = minf(off_angle + rate * smoothstep(0.0, float(F["flip_in"]) + 0.001, off_t) * dt, TAU + 0.35)
	var spin := off_spin_rate * smoothstep(0.0, float(F["spin_in"]) + 0.001, off_t)
	# spin landing help: within 35 deg of a half-turn just before touchdown, ease onto it
	if float(d["level"]) > 0.0 and land_t < 0.4:
		var rot := absf(air_rotation)
		var rem := roundf(rot / PI) * PI - rot
		if absf(rem) < deg_to_rad(35.0) and rem > -deg_to_rad(35.0):
			var need_s := rem / maxf(land_t, 0.08)
			spin = move_toward(spin, clampf(spin + need_s * 0.6, 0.0, smax), float(d["level"]) * 6.0 * dt)
	spin_vel = off_dir * spin
	# how inverted he really is (for naming): his body's up against the sky
	var b := Basis(off_axis.normalized(), off_angle)
	var up_world := _cur_xform.basis * (b * Vector3.UP)
	off_max_tilt = maxf(off_max_tilt, rad_to_deg(up_world.angle_to(Vector3.UP)))


## Angle between his body's up now and where it would be with the off-axis flip finished (rad).
func offaxis_error() -> float:
	if off_family == "":
		return 0.0
	var horiz := sqrt(maxf(1.0 - off_axis.y * off_axis.y, 0.0))
	return 2.0 * asin(clampf(horiz * absf(sin(off_angle * 0.5)), 0.0, 1.0))


## One physics step (public for automated tests).
func step(dt: float) -> void:
	if mode == Mode.WALK:
		_walk_step(dt)
		return
	var raw_steer := _in("steer_right") - _in("steer_left")
	_raw_steer = raw_steer
	aggressive = _pressed("carve")
	var want_tuck := _pressed("tuck")
	var want_brake := _pressed("brake")
	# S in the air picks a grab, not the brake: don't let it hockey-stop you on landing
	if airborne:
		want_brake = false
	elif _brake_block:
		if want_brake:
			want_brake = false
		else:
			_brake_block = false
	var jump_held := _pressed("jump")
	# arrows: body lean fore/aft and wind-up / spin (gamepad shoulders also spin)
	for a in _latched.keys():
		if _in(a) < 0.5:
			_latched.erase(a)
	var spin_in := clampf(_in("spin_right") - _in("spin_left") + _ink("lean_right") - _ink("lean_left"), -1.0, 1.0)
	var lean_in := _ink("lean_forward") - _ink("lean_back")
	lean_fa = move_toward(lean_fa, lean_in, 5.0 * dt)
	if not airborne:
		# hold Left to coil the shoulders left, which loads a RIGHT spin (and the other way round)
		wind = move_toward(wind, -spin_in, (2.5 if absf(spin_in) > 0.1 else 4.0) * dt)
		# loading builds while crouching with the weight back and fades slowly, so you can
		# straighten up just before the pop (big ollie) instead of popping into a backflip
		var load_t := charge * maxf(-lean_fa, 0.0)
		tail_load = move_toward(tail_load, load_t, (4.0 if load_t > tail_load else 1.0) * dt)
	sketchy = maxf(sketchy - dt, 0.0)
	# smooth inputs (no instant redirection)
	var srate := 3.2 * steer_sens if absf(raw_steer) > absf(steer) else 5.0
	steer = move_toward(steer, clampf(raw_steer, -1.0, 1.0), srate * dt)
	tuck = 0.0
	_want_push = want_tuck and not want_brake and not riding_switch     # no pole-pushing backwards
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
	if not jump_held and not charging and _jump_buffer <= 0.0:
		_arrow_tricks(dt)
	if not charging and _jump_buffer <= 0.0 and trick_set == Vector2i.ZERO:
		charge = move_toward(charge, 0.0, 3.0 * dt)
	_coyote = maxf(_coyote - dt, 0.0)
	_stance_cd = maxf(_stance_cd - dt, 0.0)
	if not grind.is_empty():
		_grind_step(dt)
		return

	var p := position
	ground_h = terrain.height(p.x, p.z)
	var n := _snow_normal(p)
	var gap := p.y - ground_h
	contact = gap < CONTACT_EPS
	# skis just above the snow after a small bump still steer partially (legs absorb the bump)
	var cf := 1.0 if contact else clampf(1.0 - (gap - CONTACT_EPS) / 0.3, 0.0, 1.0)
	if contact:
		ground_n = n
		surface = terrain.surface_at(p.x, p.z)
		slope = rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))
		rock = smoothstep(46.0, 56.0, slope) * (0.0 if terrain.feature_offset(p.x, p.z) > 0.05 else 1.0)  # pipe walls are snow

	if airborne:
		_air_step(dt, spin_in, lean_in)
	else:
		_ground_step(dt, n, cf)

	# integrate
	p += vel * dt
	var h2 := terrain.height(p.x, p.z)
	var n2 := _snow_normal(p)
	if p.y <= h2:
		if not airborne and terrain.pipe_offset(p.x, p.z) > 0.0:
			# pipe wall: lifting the skier back onto the curve costs speed (otherwise each step's
			# correction is free height and he'd climb higher than his speed allows)
			var climb := h2 - p.y
			vel *= sqrt(maxf(vel.length_squared() - 2.0 * G * climb, 0.0)) / maxf(vel.length(), 0.001)
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


## Ground normal: smoothed over 2.4 m on the mountain, but tight on park kickers so the lip's angle
## isn't averaged away with the flat deck behind it.
func _snow_normal(p: Vector3) -> Vector3:
	return terrain.normal(p.x, p.z, 0.25 if terrain.feature_offset(p.x, p.z) > 0.0 else 1.2)


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
		return
	if cf < 1.0 and vel.dot(n) < 2.5:
		# knees absorb small bumps: press the skis back onto the snow
		vel -= n * 16.0 * dt
	var f := forward_flat()
	f = (f - n * f.dot(n)).normalized()
	var vn := vel.dot(n)
	var vt := vel - n * vn
	var sp := vt.length()
	# --- surface properties
	var powder := surface.r * (1.0 - surface.g)
	var groomed := surface.g
	var ice := surface.b * (1.0 - groomed)
	var grip := 1.0 - 0.45 * ice - 0.15 * powder - 0.6 * rock
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
	# --- switch stance: X does a clean 180 on the snow (0.45 s) into or out of riding switch; a
	# press only counts if the last 180 has finished and its 0.9 s cooldown has run out
	var sw_now := _pressed("switch_stance")
	if sw_now and not _stance_prev and _stance_left <= 0.0 and _stance_cd <= 0.0 and sp > 1.5 and edge_brake < 0.2:
		_stance_left = PI
		_stance_dir = -1.0 if steer > 0.1 else 1.0       # spin the way you're turning, else to the left
		_stance_cd = 0.9
	_stance_prev = sw_now
	if _stance_left > 0.0:
		var st := minf(_stance_left, 7.0 * dt)
		_stance_left -= st
		stance_vis = wrapf(stance_vis + _stance_dir * st, -PI, PI)
		vel *= 1.0 - 0.3 * dt                               # the skis skid through the 180
		if _stance_left <= 0.0:
			riding_switch = not riding_switch
			stance_vis = PI if riding_switch else 0.0
	# --- pole push / skating on the flats
	pushing = 0.0
	if _want_push and sp < PUSH_MAX and brake < 0.1:
		# the speed comes in bursts while the poles are planted and the arms drive back
		if push_phase == 0.0:
			push_phase = 0.2                     # first press: reach and plant straight away
		push_phase = fmod(push_phase + dt * 1.15, 1.0)
		if push_phase > 0.25 and push_phase < 0.65:
			var acc := 13.0 * sin(PI * (push_phase - 0.25) / 0.4) * (1.0 - pow(sp / PUSH_MAX, 2.0))
			vel += f * acc * dt
		pushing = 1.0
	else:
		push_phase = 0.0
	# --- static friction when nearly stopped
	var gt := (g - n * g.dot(n))
	if (vel - n * vel.dot(n)).length() < 0.35 and (absf(gt.dot(f)) < 0.06 * G or brake > 0.5) and pushing == 0.0:
		vel = n * minf(vel.dot(n), 0.0)
	# --- losing control on extreme faces
	if slope > 60.0 and sp > 6.0 and terrain.pipe_offset(position.x, position.z) <= 0.0:   # pipe walls are meant to be ridden
		steep_time += dt
		if steep_time > 0.6:
			crash("Lost control on a cliff face")
	else:
		steep_time = maxf(steep_time - dt, 0.0)


func _air_step(dt: float, spin_in: float, flip_in: float) -> void:
	vel += Vector3(0, -G, 0) * dt
	_tilt_for_landing(dt)
	_rail_assist(dt)
	var sp := vel.length()
	var compact := maxf(tuck, (grab_l + grab_r) * 0.5)
	var cda := lerpf(0.0042, 0.0022, compact)
	vel -= vel * cda * sp * dt
	var d := diff()
	# body english: how much you can change your rotation once airborne depends on the difficulty
	if _spin_latch != 0.0 and signf(spin_in) != _spin_latch:
		_spin_latch = 0.0
	if _spin_latch != 0.0:
		spin_in = 0.0
	if off_family != "":
		_offaxis_step(dt, spin_in, flip_in)
	elif _unwind > 0.0:
		_unwind -= dt
		spin_vel = move_toward(spin_vel, _spin_target, absf(_spin_target) / UNWIND_TIME * 1.4 * dt)
	if off_family != "":
		pass
	elif absf(spin_in) > 0.1:
		spin_vel = move_toward(spin_vel, signf(spin_in) * SPIN_MAX, float(d["air_spin"]) * dt)
	elif _unwind > 0.0:
		pass
	else:
		spin_vel = move_toward(spin_vel, 0.0, float(d["spin_damp"]) * dt)
	if off_family != "":
		flip_vel = 0.0
	elif absf(flip_in) > 0.1:
		flip_vel = move_toward(flip_vel, signf(flip_in) * SPIN_MAX * 0.7, float(d["air_flip"]) * dt)
	elif float(d["level"]) > 0.0 and absf(roundf(air_pitch / TAU) * TAU - air_pitch) < deg_to_rad(60.0) \
			and not (absf(air_pitch) < PI and absf(flip_vel) > 2.0):     # leave a popped flip alone till it's past halfway
		# assist: settle a small tilt toward a clean landing (it cannot rescue an upside-down one)
		var target := roundf(air_pitch / TAU) * TAU
		flip_vel += ((target - air_pitch) * float(d["level"]) * 2.0 - flip_vel * float(d["level"])) * dt
	# flips start laid out; keep pulling the flip past ~3/4 of a turn and the body tucks to rotate
	# faster (doubles, triples); let go and it opens up again to slow down and spot the landing
	var pulling := absf(flip_in) > 0.1 and absf(air_pitch) > TAU * 0.7 and signf(flip_in) == signf(flip_vel)
	flip_tuck = move_toward(flip_tuck, 1.0 if pulling else 0.0, (4.0 if pulling else 3.0) * dt)
	var w_mul := 1.0 + 0.3 * compact
	heading = wrapf(heading - spin_vel * w_mul * dt, -PI, PI)
	air_rotation += spin_vel * w_mul * dt
	air_pitch += flip_vel * lerpf(0.85, 1.4, flip_tuck) * dt
	air_pitch_peak = maxf(air_pitch_peak, absf(air_pitch))
	# light air steering ("body english")
	var hv := Vector3(vel.x, 0, vel.z)
	if hv.length() > 1.0:
		var right := hv.normalized().cross(Vector3.UP)
		vel += right * steer * 1.1 * dt
	# grabs let go by themselves just before touchdown (time to the real snow, from the landing
	# probe) so the legs can come down for the landing - Easy / Normal; on Realistic it's on you
	var auto_off := float(d["level"]) > 0.0 and land_t < GRAB_AUTO_RELEASE
	var gl := GRABS and _pressed("grab_left") and not auto_off
	var gr := GRABS and _pressed("grab_right") and not auto_off
	grab_held = gl or gr
	# which grab: Q = left hand, E = right hand, both = Truck Driver; W / S (pressed any time during
	# the grab) pick the front / back of the ski and stick until you let go. The arrows never pick
	# grabs, so flips and spins work the same with or without a grab.
	var gv := _in("tuck") - _in("brake")
	if gl or gr:
		if gv < -0.5:
			_s_grabbed = true
		var want := grab_name
		if gl and gr:
			want = "Truck Driver"
		elif gl:
			if gv > 0.5:
				want = "Tip"
			elif gv < -0.5:
				want = "Japan"
			elif not (want in ["Tip", "Japan"]):
				want = "Mute"
		else:
			if gv > 0.5:
				want = "Blunt"
			elif gv < -0.5:
				want = "Tail"
			elif not (want in ["Blunt", "Tail"]):
				want = "Safety"
		grab_name = want
	elif grab_l < 0.05 and grab_r < 0.05:
		grab_name = ""
	if grab_name != "":
		_jump_grab = grab_name
	if (gl or gr) and (grab_l > 0.8 or grab_r > 0.8):
		grab_time += dt
	# where the hand goes: leaning forward reaches the tip, leaning back the tail
	var kind := "tip" if gv > 0.5 else ("tail" if gv < -0.5 else "")
	if gl and grab_l < 0.05:
		grab_kind_l = kind
	if gr and grab_r < 0.05:
		grab_kind_r = kind
	# the hand gets to the ski over GRAB_IN and lets go over GRAB_OUT; a grab only scores once
	# the hand is actually on the ski (> 0.8)
	grab_l = move_toward(grab_l, 1.0 if gl else 0.0, (1.0 / GRAB_IN if gl else 1.0 / GRAB_OUT) * dt)
	grab_r = move_toward(grab_r, 1.0 if gr else 0.0, (1.0 / GRAB_IN if gr else 1.0 / GRAB_OUT) * dt)
	if grab_l > 0.8:
		grab_time_l += dt
	if grab_r > 0.8:
		grab_time_r += dt
	edge = move_toward(edge, 0.0, 2.0 * dt)
	skid = 0.0
	carve_g = 0.0


## Where the flight comes down (ballistic, checked a few times a second) and the snow's normal
## there; the body's "up" turns from the takeoff surface toward it, faster as touchdown nears, so he
## meets a steep landing or a pipe wall square instead of snapping onto it.
func _tilt_for_landing(dt: float) -> void:
	_land_probe -= 1
	if _land_probe <= 0:
		_land_probe = 4
		var p := position
		var v := vel
		land_t = 9.0
		for i in 100:
			v += Vector3.DOWN * G * 0.04
			p += v * 0.04
			if p.y <= terrain.height(p.x, p.z):
				land_t = (i + 1) * 0.04
				land_n = terrain.normal(p.x, p.z, 0.25 if terrain.feature_offset(p.x, p.z) > 0.0 else 1.2)
				break
	else:
		land_t = maxf(land_t - dt, 0.0)
	if land_t > 8.0:
		return
	var k := lerpf(1.6, 7.0, clampf(1.0 - land_t / 0.8, 0.0, 1.0))
	var a := air_up.angle_to(land_n)
	if a > 0.001:
		var ax := air_up.cross(land_n)
		if ax.length() > 1e-5:
			air_up = air_up.rotated(ax.normalized(), a * (1.0 - exp(-k * dt))).normalized()


func _do_jump() -> void:
	charge_at_pop = charge
	if not grind.is_empty():
		_leave_rail("pop")
		ground_n = Vector3.UP
	var n := ground_n
	# crouch depth, loaded tails (lean back while crouching) and rebound off a compression
	# a real ollie adds ~1.5-3 m/s of pop, not a launch: the kicker does the work
	var strength := 1.6 + 1.9 * charge + 0.7 * tail_load + 0.5 * clampf(compression, 0.0, 1.0)
	var pop_dir := (n * 0.75 + Vector3.UP * 0.25).normalized()
	if n.y < 0.6 and terrain.pipe_out(position.x, position.z) != Vector2.ZERO:
		pop_dir = Vector3.UP            # on a pipe wall you pop up out of it, not off it into the middle
		strength *= 0.45                # ... and the wall already sends you up: a coping pop adds a little
	vel += pop_dir * strength
	tail_load = 0.0
	position.y += 0.05
	charge = 0.0
	_coyote = 0.0
	jumped.emit(strength)
	_take_off(true)


func _take_off(from_jump := false) -> void:
	if airborne:
		return
	if not from_jump and trick_set.x != 0:
		wind = 0.0              # set but not popped: rolling off the lip doesn't unwind into a spin
	airborne = true
	takeoff_switch = riding_switch
	if _stance_left > 0.0:          # popped mid-180: finish it as part of the air
		_stance_left = 0.0
		stance_vis = PI if riding_switch else 0.0
	air_up = ground_n                # he leaves square to the snow he took off from
	_land_probe = 0
	# superpipe: off the coping you go straight up (a real wall is vertical at the top), not out over
	# the deck - drop the outward part of the velocity
	var po := terrain.pipe_out(position.x, position.z)
	var pipe_air := po != Vector2.ZERO and ground_n.y < 0.6
	if pipe_air:
		var out := Vector3(po.x, 0.0, po.y)
		var vo := vel.dot(out)
		if vo > 0.0:
			vel -= out * vo
		# the skis point the way he's actually going along the wall (heading is a yaw, and on a near-
		# vertical wall it lags the travel); straight up, it stays as it was
		var hz := Vector2(vel.x, vel.z)
		if hz.length() > 1.0:
			heading = yaw_of(vel)
	air_time = 0.0
	air_rotation = 0.0
	grab_time_l = 0.0
	grab_time_r = 0.0
	takeoff_pos = position
	max_air_height = 0.0
	_coyote = 0.0 if from_jump else 0.12
	# rotation is set at takeoff: carving rotation and the wound-up upper body give the spin ...
	# the shoulders unwind first and the hips and skis follow, so the spin builds up over UNWIND_TIME
	_spin_target = clampf(yaw_rate * 0.5 + wind * WIND_SPIN, -SPIN_MAX, SPIN_MAX)
	spin_vel = _spin_target * 0.3
	_unwind = UNWIND_TIME if absf(wind) > 0.15 else 0.0
	_spin_latch = -signf(wind) if absf(wind) > 0.15 else 0.0
	wind = 0.0
	flip_tuck = 0.0
	# ... the lip pitches you backward, and leaning at the pop starts a front / back flip
	# (not in a pipe: rolling over the coping onto the deck would read as a lip and throw every air
	# into a front flip - flips there come from the arrows only)
	flip_vel = 0.0 if pipe_air else clampf(_ground_pitch_rate * 0.35, -1.0, 1.0)
	if from_jump:
		flip_vel += (_pop_flip * (0.75 + 0.25 * charge_at_pop) if _arrow_trick else lean_fa) * FLIP_POP
	air_pitch = 0.0
	air_pitch_peak = 0.0
	grab_kind_l = ""
	grab_kind_r = ""
	grab_name = ""
	grab_held = false
	grab_time = 0.0
	_s_grabbed = false
	_jump_grab = ""
	_late_used = false
	off_family = ""
	if trick_state == TrickState.PENDING and not pending_trick.is_empty():
		# the trick waited for the lip: a little pop off it, then the rotation
		var t := pending_trick
		pending_trick = {}
		charge_at_pop = float(t.get("charge", 0.5))
		vel += ground_n * (0.4 + 0.8 * charge_at_pop)
		_start_trick_in_air(t, 1.0)
		_late_used = true
	trick_state = TrickState.AIR
	took_off.emit()


func _land(n: Vector3, impact: float) -> void:
	airborne = false
	if _s_grabbed and _pressed("brake"):
		_brake_block = true          # S was a grab key on this jump: no hockey stop until it's re-pressed
	var hv := vel - n * vel.dot(n)
	var sp := hv.length()
	# travel direction from the horizontal part only: coming straight down a pipe wall there is none
	# to speak of, and the skis can't be "sideways" to it
	var vel_yaw := yaw_of(hv) if Vector2(hv.x, hv.z).length() > 1.0 else heading
	var diff := wrapf(heading - vel_yaw, -PI, PI)
	var adiff := absf(diff)
	var is_switch := adiff > PI * 0.5
	var misalign := minf(adiff, PI - adiff)
	var grabbing := grab_l > 0.5 or grab_r > 0.5
	var pitch_off := absf(wrapf(air_pitch, -PI, PI))
	if off_family != "":
		pitch_off = offaxis_error()           # off-axis: how far his body's up is from finishing the flip
	var d := diff()
	var tol := deg_to_rad(float(d["land_tol"]))
	var info := {
		"impact": impact, "misalign": rad_to_deg(misalign), "switch": is_switch, "air_time": air_time,
		"rotation": air_rotation, "grab_l": grab_time_l, "grab_r": grab_time_r, "speed": sp,
		"height": max_air_height, "distance": Vector2(position.x - takeoff_pos.x, position.z - takeoff_pos.z).length(),
		"crash": "", "flip": air_pitch, "pitch_peak": air_pitch_peak, "pitch_off": rad_to_deg(pitch_off),
		"grab_kind_l": grab_kind_l, "grab_kind_r": grab_kind_r, "grab_name": _jump_grab, "grab_time": grab_time,
		"takeoff_switch": takeoff_switch,
		"offaxis": off_family, "off_dir": off_dir, "off_flip": rad_to_deg(off_angle), "off_tilt": off_max_tilt,
	}
	ground_n = n
	# the legs absorb the landing: the impact sets them sinking (the compression spring peaks ~0.13 s
	# later at this depth and comes back up), instead of snapping straight into a crouch
	var depth := clampf(impact / 14.0, 0.1, 1.0) * (1.0 if air_time > 0.25 else 0.4)
	compression_vel = maxf(compression_vel, depth * 17.0)
	# crash conditions
	var reason := ""
	if pitch_off > tol + deg_to_rad(15.0) and air_time > 0.3:
		if off_family != "":
			reason = "Landed on your back" if float(OFFAXIS[off_family]["flip"]) > 0.0 else "Landed on your head"
		else:
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
			# landed the other way round: you ride away in that stance (switch, or back to forward)
			heading = wrapf(heading + PI, -PI, PI)
			riding_switch = not riding_switch
			stance_vis = PI if riding_switch else 0.0
		yaw_rate = 0.0
	spin_vel = 0.0
	flip_vel = 0.0
	air_pitch = 0.0
	off_family = ""
	off_angle = 0.0
	trick_state = TrickState.RECOVER
	_recover_t = RECOVER_TIME
	grab_l = 0.0
	grab_r = 0.0
	_last_land_t = time
	landed.emit(info)
	if reason != "":
		crash(reason)


func crash(reason: String) -> void:
	if is_crashed:
		return
	is_crashed = true
	crash_time = 0.0
	airborne = false
	charging = false
	charge = 0.0
	off_family = ""
	_reset_trick_input()
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
	if airborne and mode == Mode.SKI:
		up = air_up
	var f := forward_flat()
	f = f - up * f.dot(up)
	if f.length() < 0.25:
		f = Vector3.UP - up * up.dot(Vector3.UP)        # heading into a wall: the skis point up it
	f = f.normalized()
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
	var jump := _pressed("jump") or _pressed("lean_forward")     # on foot: Up hops
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
## Point, unit direction and segment index on a rail's path at arc length `s` (rails, boxes and
## tubes are polylines: straight, kinked, rainbow, S-shaped...).
static func rail_at(r: Dictionary, s: float) -> Array:
	var pts: Array = r["pts"]
	var cum: Array = r["cum"]
	var i := 0
	while i < pts.size() - 2 and s > float(cum[i + 1]):
		i += 1
	var a: Vector3 = pts[i]
	var seg := maxf(float(cum[i + 1]) - float(cum[i]), 0.0001)
	var dir: Vector3 = ((pts[i + 1] as Vector3) - a) / seg
	return [a + dir * (s - float(cum[i])), dir, i]


func _try_mount() -> void:
	var k := float(diff()["rail_assist"])
	var lat_extra := 0.15 * k if airborne else 0.0          # rail assist: a little more reach when you jump at it
	for r: Dictionary in rails:
		var pts: Array = r["pts"]
		var cum: Array = r["cum"]
		var total := float(r["length"])
		if Vector2(position.x - (r["a"] as Vector3).x, position.z - (r["a"] as Vector3).z).length() > total + 4.0:
			continue
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var ab: Vector3 = (pts[i + 1] as Vector3) - a
			var length := ab.length()
			var dir := ab / length
			var t := (position - a).dot(dir)
			var s := float(cum[i]) + t
			if t < -0.05 or t > length + 0.05 or s < 0.3 or s > total - 0.6:
				continue
			var top := a + dir * t
			var side := dir.cross(Vector3.UP).normalized()
			var lat := (position - top).dot(side)
			var reach := float(r["width"]) * 0.5 + 0.3
			if absf(lat) > reach + lat_extra:
				continue
			var dy := position.y - top.y
			# boxes and tubes can be ridden onto from the snow, rails need a pop
			if dy < {"box": -0.42, "widebox": -0.5, "tube": -0.62}.get(r["kind"], -0.1) or dy > 0.45 + 0.1 * k:
				continue
			var vh := vel.dot(dir)
			if absf(vh) < 2.0 or (airborne and vel.y > 1.0):
				continue
			_mount(r, s, clampf(lat / reach, -1.0, 1.0), vh, dir)
			return


## Rail assist (like Riders Republic / Skate): in the air, heading for a rail roughly along it,
## your sideways drift is steered so you arrive over it.  Strength by difficulty (none on Realistic).
func _rail_assist(dt: float) -> void:
	var k := float(diff()["rail_assist"])
	if k <= 0.0 or rails.is_empty() or _rail_cd > 0.0:
		return
	var hv := Vector3(vel.x, 0.0, vel.z)
	var sp := hv.length()
	if sp < 2.0:
		return
	var best_lat := INF
	var best := {}
	for r: Dictionary in rails:
		if Vector2(position.x - (r["a"] as Vector3).x, position.z - (r["a"] as Vector3).z).length() > float(r["length"]) + 10.0:
			continue
		var pts: Array = r["pts"]
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var ab: Vector3 = (pts[i + 1] as Vector3) - a
			var length := ab.length()
			var dir := ab / length
			var dh := Vector3(dir.x, 0.0, dir.z).normalized()
			var along := hv.dot(dh) / sp
			if absf(along) < 0.75:
				continue                       # more than ~40 deg off the rail
			var t := (position - a).dot(dir)
			if t < -6.0 or t > length - 0.4:
				continue
			var top := a + dir * clampf(t, 0.3, length)
			var side := dh.cross(Vector3.UP)
			var lat := (position - top).dot(side)
			var dy := position.y - top.y
			if absf(lat) > 2.0 or dy < -0.4 or dy > 3.5:
				continue
			if absf(lat) < best_lat:
				best_lat = absf(lat)
				best = {"lat": lat, "side": side, "ahead": maxf(-t, 0.0) + 0.6, "v": absf(hv.dot(dh))}
	if best.is_empty():
		return
	var side2: Vector3 = best["side"]
	var t_reach := maxf(float(best["ahead"]) / maxf(float(best["v"]), 1.0), 0.15)
	var want := -float(best["lat"]) / t_reach
	var cur := vel.dot(side2)
	vel += side2 * (move_toward(cur, want, k * 6.0 * dt) - cur)


func _mount(r: Dictionary, s: float, lat01: float, vh: float, dir: Vector3) -> void:
	if airborne and absf(wrapf(air_pitch, -PI, PI)) > deg_to_rad(50.0):
		crash("Missed the rail")
		return
	grind = r
	_grind_dir = signf(vh)
	_grind_t = s
	_grind_v = absf(vh) * 0.95
	var axis: Vector3 = dir * _grind_dir
	var ay := yaw_of(Vector3(axis.x, 0.0, axis.z))
	# stance from how you land on it: along the rail (50-50) or across it (slide), or switch
	var rel := wrapf(heading - ay, -PI, PI)
	grind_slide = absf(rel) > PI * 0.25 and absf(rel) < PI * 0.75
	grind_switch = absf(rel) >= PI * 0.75
	_stance_off = signf(rel) * PI * 0.5 if grind_slide else (PI if grind_switch else 0.0)
	if riding_switch and not grind_slide:
		grind_switch = not grind_switch          # the body is the other way round already
	heading = wrapf(ay + _stance_off, -PI, PI)
	_grind_entry = air_rotation if airborne else 0.0
	_grind_yaw = ay
	_rspin_left = 0.0
	_rspin_total = 0.0
	airborne = false
	spin_vel = 0.0
	flip_vel = 0.0
	air_pitch = 0.0
	yaw_rate = 0.0
	rail_balance = clampf(lat01 * 0.4, -0.5, 0.5)
	_rail_bal_vel = 0.0
	grind_time = 0.0
	grind_press = 0.0
	compression_vel = maxf(compression_vel, 4.0)      # soak up the landing on the rail


## Spin on a rail or box: a tap of Left / Right turns you 180 deg on it (through a slide).
func rail_spin(sgn: float) -> void:
	if grind.is_empty():
		return
	_rspin_left += PI
	_rspin_dir = sgn


func _grind_step(dt: float) -> void:
	var r := grind
	var ra := rail_at(r, _grind_t)
	var dir: Vector3 = ra[1]
	var axis := dir * _grind_dir
	var d := diff()
	# speed along the rail: gravity (each section: up, flat, down), sliding friction (more when
	# sideways), air drag
	var mu := (0.035 if r["kind"] == "rail" else 0.06) + (0.04 if grind_slide else 0.0)
	_grind_v += (-G * axis.y - mu * G - 0.003 * _grind_v * _grind_v) * dt
	_grind_t += _grind_v * dt * _grind_dir
	grind_time += dt
	ground_time = 0.0
	if absf(lean_fa) > 0.5:
		grind_press += signf(lean_fa) * dt
	# balance: an inverted pendulum held with A/D (assist and instability depend on difficulty);
	# a curving rail (S-rail) throws you to the outside of each bend
	var k := float(d["rail"])
	var ay := yaw_of(Vector3(axis.x, 0.0, axis.z))
	var turn := wrapf(ay - _grind_yaw, -PI, PI) / maxf(dt, 0.001)
	_grind_yaw = ay
	var wobble := sin(time * 2.3 + _grind_t * 1.7) * 0.6 + sin(time * 5.3) * 0.4
	_rail_bal_vel += (rail_balance * (2.0 * k - float(d["rail_assist"])) + wobble * k * 0.5 + _raw_steer * 5.0
		+ turn * _grind_v * 0.12 * maxf(k, 1.0)) * dt
	_rail_bal_vel *= 1.0 - 1.8 * dt
	rail_balance += _rail_bal_vel * dt
	# spinning on it
	if _rspin_left > 0.0:
		var step := minf(_rspin_left, 10.5 * dt)          # 180 deg in 0.3 s
		_rspin_left -= step
		_rspin_total += step
		_stance_off = wrapf(_stance_off - _rspin_dir * step, -PI, PI)
		var a2 := absf(_stance_off)
		grind_slide = a2 > PI * 0.25 and a2 < PI * 0.75
		grind_switch = a2 >= PI * 0.75
	heading = wrapf(ay + _stance_off, -PI, PI)
	var top: Vector3 = rail_at(r, _grind_t)[0]
	position = top
	vel = axis * _grind_v
	speed = _grind_v
	contact = false
	ground_n = Vector3.UP
	travel_yaw = ay
	lat_acc = 0.0
	if absf(rail_balance) >= 1.0:
		var side := dir.cross(Vector3.UP).normalized() * signf(rail_balance)
		_leave_rail("fall")
		if bool(d["edge_catch"]):
			crash("Fell off the rail")
			return
		position += side * 0.35
		vel += side * 1.5 + Vector3.UP * 1.0
		_take_off()
	elif _grind_t < 0.0 or _grind_t > float(r["length"]) or _grind_v < 0.3:
		_leave_rail("end" if _grind_v >= 0.3 else "stall")
		vel += Vector3.UP * 0.4
		_take_off()


func _leave_rail(how: String) -> void:
	var r := grind
	grind = {}
	_rail_cd = 0.4
	jibbed.emit({"kind": r["kind"], "time": grind_time, "slide": grind_slide, "switch": grind_switch,
		"press": grind_press, "entry_rot": _grind_entry, "how": how, "spin": rad_to_deg(_rspin_total),
		"shape": r.get("shape", "straight")})
