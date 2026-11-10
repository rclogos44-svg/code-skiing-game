extends Node
## Automated tests, driven from the command line:
##   -- --test=shots --out=/path          screenshots from several locations
##   -- --test=physics                     skiing physics checks (prints PASS/FAIL)
##   -- --test=smoke --seconds=20          scripted gameplay run with frame timing
## Results are printed with a "[TEST]" prefix; the process exits with code 0 on success.

var world: World
var out_dir := "user://test_out"
var failures := 0
var checks := 0


func run(w: World) -> void:
	world = w
	out_dir = Game.test_args.get("out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	match Game.test_mode:
		"shots":
			await _shots()
		"physics":
			await _physics()
		"smoke":
			await _smoke()
		"gameplay":
			_gameplay()
		"turns":
			await _turns()
		"features":
			await _features()
		"showcase":
			await _showcase()
		"showcase2":
			await _showcase2()
		"showcase3":
			await _showcase3()
		"showcase4":
			await _showcase4()
		"showcase5":
			await _showcase5()
		"parks":
			await _park_shots()
		"grabs":
			await _grab_shots()
		"grab_anim":
			await _grab_anim()
		"line":
			_line_report()
		"pipe":
			_pipe_report()
		"pipe_anim":
			await _pipe_anim()
		"switch_shots":
			await _switch_shots()
		"rider":
			await _rider_shots()
		_:
			print("[TEST] unknown test mode ", Game.test_mode)
			failures += 1
	print("[TEST] done: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


## UI flow test: drives the real menus and captures screenshots of each screen.
func run_ui(main: Node) -> void:
	world = main.world
	out_dir = Game.test_args.get("out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _frames(20)
	await _snap("ui_main_menu")
	main.menus.show_challenges()
	await _frames(3)
	await _snap("ui_challenges")
	main.menus.back()
	main._on_menu_request("freeride_drop", "Powder Bowl")
	await _frames(30)
	var s: Skier = world.skier
	s.scripted_input = {"tuck": 1.0, "steer_left": 0.5}
	await _frames(25)
	main.hud.show_trick({"name": "Right 360 Left Ski Grab", "points": 1234, "quality": "Clean landing", "combo_count": 2, "multiplier": 1.5})
	main.hud.notify("Viewpoint discovered: Valley Overlook", "discovery")
	await _frames(4)
	await _snap("ui_hud")
	main._pause()
	await _frames(3)
	await _snap("ui_pause")
	main.menus.show_settings()
	await _frames(3)
	await _snap("ui_settings")
	main.menus.back()
	main._open_map()
	await _frames(3)
	await _snap("ui_map")
	# zoomed in on the resort with the pointer over a drop zone (tooltip)
	var ms: MapScreen = main.map_screen
	var dz := world.terrain.drop_zone("Resort Top")
	ms._zoom = 2.6
	ms._center = Vector2(float(dz["x"]) + 300.0, float(dz["z"]) + 500.0) / world.terrain.world
	ms._update_rect()
	await _frames(2)
	var mp: Vector2 = ms._view.global_position + ms._w2m(dz["x"], dz["z"])
	var ev := InputEventMouseMotion.new()
	ev.position = mp
	ev.global_position = mp
	get_viewport().warp_mouse(mp)
	get_viewport().push_input(ev)
	await _frames(4)
	await _snap("ui_map_zoom")
	main._resume()
	main.challenges.start("race_village_sprint")
	await _frames(40)
	await _snap("ui_race")
	check("ui flow completed", true)
	print("[TEST] done: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0)


func check(name: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print("[TEST] %s %s %s" % ["PASS" if ok else "FAIL", name, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("[TEST] screenshot ", path)


# ------------------------------------------------------------------ screenshots
func _shots() -> void:
	var list: Array = Game.test_args.get("spots", "Resort Top,Summit Peak,Powder Bowl,Pinewood Ridge,Widowmaker,Village Base").split(",")
	for spot in list:
		world.spawn_at_drop(spot)
		var s := world.skier
		s.scripted_input = {}
		# ski a little so the pose and camera settle
		s.scripted_input = {"tuck": 1.0}
		await _frames(int(Game.test_args.get("frames", "40")))
		await _snap("shot_" + spot.to_lower().replace(" ", "_"))
	# overview from high above
	var cam := world.camera
	cam.set_process(false)
	var t := world.terrain
	var p := Vector3(4600, 0, 6000)
	p.y = t.height(p.x, p.z) + 900
	cam.global_transform = Transform3D(Basis.IDENTITY, p).looking_at(Vector3(3000, 1600, 1500), Vector3.UP)
	world.renderer.update_lod(p, true)
	await _frames(10)
	await _snap("overview_south")
	p = Vector3(3200, 0, 2600)
	p.y = t.height(p.x, p.z) + 60
	cam.global_transform = Transform3D(Basis.IDENTITY, p).looking_at(Vector3(3050, 2300, 900), Vector3.UP)
	world.renderer.update_lod(p, true)
	await _frames(10)
	await _snap("view_to_summit")
	cam.set_process(true)


# ------------------------------------------------------------------ physics
func _settle_on(pos: Vector3, yaw: float) -> Skier:
	var s := world.skier
	s.set_physics_process(false)
	s.teleport(pos, yaw)
	s.scripted_input = {}
	return s


func _run(s: Skier, seconds: float, input: Dictionary) -> void:
	s.scripted_input = input
	var dt := 1.0 / 120.0
	for i in int(seconds * 120.0):
		if s.is_crashed:
			break
		s.step(dt)
		s.time += dt


## Jump from the slope: crouch with `hold` for `charge_s`, then `before` for `pre_s`, release,
## then `air` in the air.  Returns {clear, rot, pitch, crash}.
func _pop(spot: Dictionary, hold: Dictionary, charge_s: float, before: Dictionary, pre_s: float, air: Dictionary, air_s := 0.6) -> Dictionary:
	var s := _settle_on(spot["pos"], spot["yaw"])
	_run(s, 1.5, {})
	_run(s, charge_s, hold)
	_run(s, pre_s, before)
	var res := {"clear": 0.0, "rot": 0.0, "pitch": 0.0, "crash": ""}
	s.scripted_input = air
	for i in int(air_s * 120.0):
		s.step(1.0 / 120.0)
		s.time += 1.0 / 120.0
		if s.airborne:
			res["clear"] = maxf(res["clear"], s.position.y - world.terrain.height(s.position.x, s.position.z))
			res["rot"] = s.air_rotation
			res["pitch"] = s.air_pitch
	return res


## Ride one park line top to bottom with no input after a push-off at `v0` (m/s). Per kicker on
## that line: speed arriving at the ramp, speed at takeoff, airtime, where he touched down
## (metres past the knuckle) and how far the landing runs, sideways drift, crash reason.
func _ride_line(pi: int, line: String, v0: float) -> Array:
	var s := world.skier
	var pk: Dictionary = world.terrain.layout["parks"][pi]
	var d := Vector3(pk["dir"][0], 0, pk["dir"][1])
	var side := Vector3(-d.z, 0, d.x)
	var o := Vector3(pk["origin"][0], 0, pk["origin"][1])
	var uc := float(pk["lines"][line])
	var ks := []
	for k in pk["kickers"]:
		if k["line"] == line:
			ks.append(k)
	ks.sort_custom(func(a, b): return float(a["start_s"]) < float(b["start_s"]))
	var out := []
	if ks.is_empty():
		return out
	var saved := s.difficulty
	s.difficulty = 0
	s.teleport(o + side * uc - d * 10.0, Skier.yaw_of(d), v0)
	s.scripted_input = {}
	var box := {}
	var cb := func(info): box["info"] = info
	s.landed.connect(cb)
	var ki := 0
	var cur := {}
	for f in 120 * 90:
		s.step(1.0 / 120.0)
		s.time += 1.0 / 120.0
		if ki >= ks.size():
			break
		var k: Dictionary = ks[ki]
		var ko := Vector3(k["origin"][0], 0, k["origin"][1])
		var kn := Vector3(k["knuckle"][0], 0, k["knuckle"][1])
		var ke := Vector3(k["end"][0], 0, k["end"][1])
		var along := (s.position - ko).dot(d)
		if cur.is_empty() and along >= 0.0:
			cur = {"size": k["size"], "v_in": s.speed, "v_lip": 0.0, "air": 0.0, "land": 0.0, "landing": (ke - kn).dot(d),
				"drift": (s.position - ko).dot(side), "crash": ""}
		if not cur.is_empty() and s.airborne and cur["v_lip"] == 0.0:
			cur["v_lip"] = s.vel.length()
		if box.has("info"):
			var info: Dictionary = box["info"]
			box.erase("info")
			if not cur.is_empty() and float(info["air_time"]) > float(cur["air"]):
				cur["air"] = info["air_time"]
				cur["land"] = (s.position - kn).dot(d)
				cur["crash"] = info["crash"]
		if s.is_crashed and not cur.is_empty():
			cur["crash"] = "crashed"
		var done := s.is_crashed or (not cur.is_empty() and not s.airborne and float(cur["air"]) > 0.3
			and (s.position - kn).dot(d) > float(cur["landing"]) + 2.0)
		if done or (not cur.is_empty() and (s.position - ke).dot(d) > 25.0):
			out.append(cur)
			cur = {}
			ki += 1
			if s.is_crashed or s.speed < 1.0:
				break
	if not cur.is_empty():
		out.append(cur)
	s.landed.disconnect(cb)
	s.difficulty = saved
	return out


## --test=line [--park=N] [--line=jump] [--v0=6]: ride the line and print each jump.
func _line_report() -> void:
	var line: String = Game.test_args.get("line", "jump")
	var v0 := float(Game.test_args.get("v0", "6"))
	for i in world.terrain.layout["parks"].size():
		if Game.test_args.has("park") and int(Game.test_args["park"]) != i:
			continue
		var pk: Dictionary = world.terrain.layout["parks"][i]
		for r in _ride_line(i, line, v0):
			print("[TEST] LINE %s %s %-2s in %.1f lip %.1f air %.2f land %.1f of %.1f drift %.2f %s" % [pk["name"], line, r["size"],
				r["v_in"], r["v_lip"], r["air"], r["land"], r["landing"], r["drift"], r["crash"]])


## Ride into a superpipe wall: start on the flat bottom `t0` m into the pipe, heading `ang` deg
## off the pipe's axis toward its right wall at `v0` m/s, no input.  Returns the hits: per wall,
## height reached above the coping, airtime, crash; and a short trace.
func _pipe_ride(t0: float, ang: float, v0: float, max_hits := 3, trace := false, air_input := {}, wall_ctl := Callable()) -> Dictionary:
	var s := world.skier
	var pp: Dictionary = {}
	for pk in world.terrain.layout.get("parks", []):
		for p2 in pk.get("pipes", []):
			pp = p2
	if pp.is_empty():
		return {}
	var d := Vector3(pp["dir"][0], 0, pp["dir"][1]).normalized()
	var side := Vector3(-d.z, 0, d.x)
	var o := Vector3(pp["origin"][0], 0, pp["origin"][1])
	var dir := (d * cos(deg_to_rad(ang)) + side * sin(deg_to_rad(ang))).normalized()
	var saved := s.difficulty
	s.difficulty = 1
	s.teleport(o + d * t0, Skier.yaw_of(dir), v0)
	s.scripted_input = {}
	var box := {}
	var cb := func(info): box["info"] = info
	var ccb := func(reason, _v): box["crash"] = reason
	s.landed.connect(cb)
	s.crashed.connect(ccb)
	var hits := []
	var peak := -INF
	var lines := []
	var last_up := Vector3.UP
	for f in 120 * 20:
		var hb := s.position.y - world.terrain.base_height(s.position.x, s.position.z)
		s.scripted_input = air_input if s.airborne else (wall_ctl.call(hb, float(pp["wall_h"])) if wall_ctl.is_valid() else {})
		if s.airborne:
			last_up = s.air_up
		s.step(1.0 / 120.0)
		s.time += 1.0 / 120.0
		var base := world.terrain.base_height(s.position.x, s.position.z)
		var coping := base + float(pp["wall_h"])
		if s.airborne:
			peak = maxf(peak, s.position.y - coping)
		if trace and f % 12 == 0:
			lines.append("t%.1f u%.1f h%.2f v%.1f %s fv%.2f ap%.0f set%s" % [f / 120.0, (s.position - o).dot(side), s.position.y - base, s.speed, "AIR" if s.airborne else "", s.flip_vel, rad_to_deg(s.air_pitch), str(s.trick_set)])
		if box.has("info"):
			var info: Dictionary = box["info"]
			box.erase("info")
			if float(info["air_time"]) > 0.3:
				hits.append({"above_coping": peak, "air": info["air_time"], "crash": info["crash"], "switch": info["switch"],
					"misalign": info["misalign"], "impact": info["impact"], "flip": rad_to_deg(float(info["flip"])),
					"tilt_err": rad_to_deg(last_up.angle_to(s.ground_n))})
				peak = -INF
		if s.is_crashed or hits.size() >= max_hits or s.speed < 1.0:
			break
	s.landed.disconnect(cb)
	s.crashed.disconnect(ccb)
	s.difficulty = saved
	return {"hits": hits, "trace": lines, "crashed": box.get("crash", "") if s.is_crashed else "", "speed": s.speed}


## Frames of a pipe air: across the flat into the right wall, backflip popped at the coping.
func _pipe_anim() -> void:
	var s := world.skier
	var body = world.body
	var pp: Dictionary = {}
	var pki := 0
	for i in world.terrain.layout["parks"].size():
		if not world.terrain.layout["parks"][i].get("pipes", []).is_empty():
			pp = world.terrain.layout["parks"][i]["pipes"][0]
			pki = i
	var st: Dictionary = world.park.park_start(pki)
	world.spawn(st["pos"], st["yaw"])
	await _frames(10)
	s.set_physics_process(false)
	body.set_process(false)
	var d := Vector3(pp["dir"][0], 0, pp["dir"][1]).normalized()
	var side := Vector3(-d.z, 0, d.x)
	var o := Vector3(pp["origin"][0], 0, pp["origin"][1])
	var dir := (d * cos(deg_to_rad(65.0)) + side * sin(deg_to_rad(65.0))).normalized()
	s.teleport(o + d * 50.0, Skier.yaw_of(dir), 15.0)
	var pop: String = Game.test_args.get("pop", "back")
	var set_a := "lean_forward" if pop == "back" else "lean_back"
	var pop_a := "lean_back" if pop == "back" else "lean_forward"
	var shot := 0
	var cam := o + d * 60.0 + side * 8.0
	cam.y = world.terrain.base_height(cam.x, cam.z) + 4.5
	for f in 120 * 4:
		var h := s.position.y - world.terrain.base_height(s.position.x, s.position.z)
		var wh := float(pp["wall_h"])
		s.scripted_input = {} if s.airborne else ({set_a: 1.0, pop_a: 1.0} if h > wh - 0.6 else ({set_a: 1.0} if h > 0.5 else {}))
		s.step(1.0 / 120.0)
		s.time += 1.0 / 120.0
		s._prev_xform = s._cur_xform
		s._cur_xform = s._compose_xform()
		body._compute_pose(1.0 / 120.0)
		body._cloth_step(1.0 / 120.0)
		if h > 2.0 and f % 15 == 0 and shot < 14:
			body._apply_parts()
			body._cloth_apply()
			_free_cam(cam, s.position + Vector3.UP * 0.6)
			await _frames(2)
			await _snap("pipe_%02d" % shot)
			shot += 1
		if s.is_crashed:
			break
	s.set_physics_process(true)


## Frames of the stance 180 into switch, then riding switch looking over each shoulder.
func _switch_shots() -> void:
	var s := world.skier
	var body = world.body
	var st: Dictionary = world.park.park_start(0)
	world.spawn(st["pos"], st["yaw"])
	await _frames(10)
	s.set_physics_process(false)
	body.set_process(false)
	var pk: Dictionary = world.park.parks[0]
	var d := Vector3(pk["dir"][0], 0, pk["dir"][1])
	s.teleport(Vector3(pk["origin"][0], 0, pk["origin"][1]) + d * 30.0 + d.cross(Vector3.UP) * 15.0, Skier.yaw_of(d), 8.0)
	var shot := 0
	for f in 120 * 5:
		var inp := {}
		if f >= 30 and f < 40:
			inp["switch_stance"] = 1.0
		if f >= 330:
			inp["steer_left"] = 1.0
		s.scripted_input = inp
		s.step(1.0 / 120.0)
		s.time += 1.0 / 120.0
		s._prev_xform = s._cur_xform
		s._cur_xform = s._compose_xform()
		body._process(1.0 / 120.0)
		if f in [36, 50, 64, 90, 250, 300, 480, 590]:
			var fw := Vector3(-sin(s.heading), 0, -cos(s.heading))
			var c: Vector3 = body.joints["pelvis"] + Vector3.UP * 0.4
			var cam := c + fw * 3.0 + fw.cross(Vector3.UP) * (1.6 if shot % 2 == 0 else -1.6) + Vector3.UP * 0.6
			_free_cam(cam, c)
			await _frames(2)
			await _snap("switch_%02d" % shot)
			shot += 1
	s.set_physics_process(true)


## --test=rider: close-ups of the rider for judging the model - skiing (8 angles), a carve, a tuck,
## a front flip (tucked), a grab.  --angles=N limits the turntable.
func _rider_shots() -> void:
	var s := world.skier
	var body = world.body
	var st: Dictionary = world.park.park_start(0)
	world.spawn(st["pos"], st["yaw"])
	await _frames(10)
	s.set_physics_process(false)
	body.set_process(false)
	var pk: Dictionary = world.park.parks[0]
	var d := Vector3(pk["dir"][0], 0, pk["dir"][1])
	s.teleport(Vector3(pk["origin"][0], 0, pk["origin"][1]) + d * 30.0 + d.cross(Vector3.UP) * 15.0, Skier.yaw_of(d), 9.0)
	var stepf := func(n: int, inp: Dictionary) -> void:
		for f in n:
			s.scripted_input = inp
			s.step(1.0 / 120.0)
			s.time += 1.0 / 120.0
			s._prev_xform = s._cur_xform
			s._cur_xform = s._compose_xform()
			body._process(1.0 / 120.0)
	var snap_around := func(tag: String, n: int, dist: float, h: float) -> void:
		# the pose, for build/gen_rider.py's posed previews
		var dump := {"joints": {}, "bases": {}}
		for k in body.joints:
			var jv = body.joints[k]
			if jv is Vector3:
				dump["joints"][k] = [jv.x, jv.y, jv.z]
		for bn in ["pelvis_basis", "torso_basis", "head_basis", "boot_l", "boot_r"]:
			var bb: Basis = body.get(bn)
			dump["bases"][bn] = [bb.x.x, bb.x.y, bb.x.z, bb.y.x, bb.y.y, bb.y.z, bb.z.x, bb.z.y, bb.z.z]
		var fdump := FileAccess.open(out_dir.path_join("pose_%s.json" % tag), FileAccess.WRITE)
		fdump.store_string(JSON.stringify(dump))
		fdump.close()
		var fw := Vector3(-sin(s.heading), 0, -cos(s.heading))
		var rt := fw.cross(Vector3.UP)
		var c: Vector3 = body.joints["pelvis"] + Vector3.UP * 0.25
		for k in n:
			var a := TAU * k / float(n)
			_free_cam(c + (fw * cos(a) + rt * sin(a)) * dist + Vector3.UP * h, c)
			await _frames(2)
			await _snap("rider_%s_%d" % [tag, k])
	var n_ang := int(Game.test_args.get("angles", "8"))
	await stepf.call(240, {})
	await snap_around.call("ski", n_ang, float(Game.test_args.get("dist", "2.4")), 0.35)
	if Game.test_args.get("only", "") == "ski":
		s.set_physics_process(true)
		return
	# a drop: the hood and pant legs fall on through the landing and bounce back
	s.position.y += 1.3
	s.airborne = true
	s.vel.y = -1.0
	s._cur_xform = s._compose_xform()
	s._prev_xform = s._cur_xform
	var guard := 0
	while s.airborne and guard < 240:
		await stepf.call(1, {})
		guard += 1
	var land_shots := [0, 8, 10, 12, 18, 30]
	var done_f := 0
	for k in land_shots.size():
		await stepf.call(land_shots[k] - done_f, {})
		done_f = land_shots[k]
		var fw := Vector3(-sin(s.heading), 0, -cos(s.heading))
		var rt := fw.cross(Vector3.UP)
		var c: Vector3 = body.joints["chest"]
		_free_cam(c - fw * 0.15 + rt * 1.0 + Vector3.UP * 0.1, c - fw * 0.15)
		await _frames(2)
		await _snap("rider_land_%d" % k)
	if Game.test_args.get("only", "") == "land":
		s.set_physics_process(true)
		return
	await stepf.call(90, {"steer_left": 1.0})
	await snap_around.call("carve", 2, 2.6, 0.5)
	await stepf.call(120, {"tuck": 1.0})
	await snap_around.call("tuck", 2, 2.6, 0.5)
	# front flip, mid rotation (tucked) and a backflip laid out
	for fl in [["front", 4.5, 2.2], ["back", -4.5, -2.2]]:
		s.airborne = true
		s.flip_vel = fl[1]
		s.air_pitch = fl[2]
		s.land_t = 2.0
		for f in 90:
			body._process(1.0 / 120.0)
		await snap_around.call("flip_" + fl[0], 2, 2.8, 0.4)
	s.flip_vel = 0.0
	s.air_pitch = 0.0
	body.preview_grab = "Japan"
	for f in 90:
		body._compute_pose(0.03)
	body._apply_parts()
	await snap_around.call("grab", 2, 2.6, 0.4)
	body.preview_grab = ""
	# spinning in the air: arms out
	s.spin_vel = 7.0
	s.land_t = 2.0
	for f in 90:
		body._process(1.0 / 120.0)
	await snap_around.call("spin", 2, 2.6, 0.4)
	s.spin_vel = 0.0
	s.airborne = false
	# a crash: the ragdoll
	s.vel = s.forward_flat() * 8.0
	s.crash("test")
	for f in 120:
		body._physics_process(1.0 / 120.0)
		body._process(1.0 / 120.0)
	await snap_around.call("crash", 2, 2.6, 0.6)
	s.teleport(s.position, s.heading)
	# on foot, walking
	s.speed = 0.0
	s.vel = Vector3.ZERO
	if s.toggle_skis():
		await stepf.call(150, {"tuck": 1.0})
		await snap_around.call("walk", 2, 2.6, 0.4)
	s.set_physics_process(true)


## --test=pipe [--t0=40 --ang=55 --v0=13]: ride into the pipe and print the hits and a trace.
func _pipe_report() -> void:
	var ai := {}
	if Game.test_args.has("air"):
		ai[Game.test_args["air"]] = 1.0
	var wc := Callable()
	if Game.test_args.has("pop"):         # hold one arrow up the wall, press the other near the coping
		var set_a: String = "lean_forward" if Game.test_args["pop"] == "back" else "lean_back"
		var pop_a: String = "lean_back" if Game.test_args["pop"] == "back" else "lean_forward"
		wc = func(h: float, wh: float) -> Dictionary:
			if h > wh - 0.6:
				return {set_a: 1.0, pop_a: 1.0}
			return {set_a: 1.0} if h > 0.5 else {}
	var r := _pipe_ride(float(Game.test_args.get("t0", "40")), float(Game.test_args.get("ang", "55")), float(Game.test_args.get("v0", "13")), 4, true, ai, wc)
	for ln in r.get("trace", []):
		print("[TEST] PIPE ", ln)
	for h in r.get("hits", []):
		print("[TEST] PIPE HIT %s" % str(h))
	print("[TEST] PIPE crashed %s speed %.1f" % [str(r.get("crashed", "")), float(r.get("speed", 0.0))])


## Every park kicker from a normal run-in (Easy, no input): air, and a landing past the knuckle.
func _park_kickers() -> void:
	var s := world.skier
	var saved := s.difficulty
	s.difficulty = 0
	for i in world.park.parks.size():
		var st: Dictionary = world.park.park_start(i)
		var p0: Vector3 = st["pos"]
		s.teleport(p0, st["yaw"])
		s.scripted_input = {"tuck": 1.0}
		for f in 960:
			s.step(1.0 / 120.0)
		var o := Vector3(world.park.parks[i]["origin"][0], 0, world.park.parks[i]["origin"][1])
		var past := (s.position - o).dot(Vector3(world.park.parks[i]["dir"][0], 0, world.park.parks[i]["dir"][1]))
		check("%s: pole-pushing from the top gets you into the park" % st["name"], past > 0.0 and s.speed > 4.0, "%.0f m past the drop-in at %.1f m/s after 8 s" % [past, s.speed])
		check("%s: W stops helping once you're moving" % st["name"], s.pushing == 0.0 or s.speed < Skier.PUSH_MAX)
	var worst_tilt := 0.0
	for pk in world.terrain.layout.get("parks", []):
		for k in pk["kickers"]:
			if k.get("rail_lip", false):
				continue                    # a gap-to-rail lip: you land on the rail (tested in _jibs)
			var d := Vector3(k["dir"][0], 0, k["dir"][1]).normalized()       # hips point off the fall line
			var knuckle := Vector3(k["knuckle"][0], 0, k["knuckle"][1])
			var origin := Vector3(k["origin"][0], 0, k["origin"][1])
			var end := Vector3(k["end"][0], 0, k["end"][1])
			s.teleport(origin - d * 12.0, Skier.yaw_of(d), float(k["approach_speed"]) - 1.0)
			s.scripted_input = {}
			var box := {}
			var cb := func(info): box["info"] = info
			s.landed.connect(cb)
			var max_air := 0.0
			var land_at := 0.0
			var crash := ""
			var launch := ""
			var up_before := Vector3.UP
			for i in 900:
				var was_air := s.airborne
				if s.airborne:
					up_before = s.air_up
				s.step(1.0 / 120.0)
				s.time += 1.0 / 120.0
				if s.airborne and not was_air and launch == "":
					var hv := Vector2(s.vel.x, s.vel.z).length()
					launch = " · launch %.1f m/s at %.0f deg, %.1f m from lip" % [s.vel.length(), rad_to_deg(atan2(s.vel.y, hv)),
						(s.position - Vector3(k["lip"][0], 0, k["lip"][1])).dot(d)]
				if s.is_crashed:
					crash = "crashed"
					break
				if box.has("info"):
					var info: Dictionary = box["info"]
					if float(info["air_time"]) > max_air:
						max_air = info["air_time"]
						land_at = (s.position - knuckle).dot(d)
						crash = info["crash"]
						worst_tilt = maxf(worst_tilt, rad_to_deg(up_before.angle_to(s.ground_n)))
					box.erase("info")
				if (s.position - knuckle).dot(d) > 45.0:
					break
			s.landed.disconnect(cb)
			check("%s %s %s (%s line) lands on the landing" % [pk["name"], k["size"], ("hip" if k.has("yaw") else ("step-down" if k.has("knuckle_h") else "kicker")), k["line"]], crash == "" and max_air > 0.4 and land_at > -1.0
				and land_at < (end - knuckle).dot(d) + 6.0,
				"%.2f s air, landed %.1f m past the knuckle (landing %.1f m)%s%s" % [max_air, land_at, (end - knuckle).dot(d),
				(" CRASH " + crash) if crash != "" else "", launch])
	check("in the air the body tilts to meet each kicker's landing slope", worst_tilt < 10.0, "worst %.1f deg off the landing at touchdown" % worst_tilt)
	# the Big Air and Sierra Main Park jump lines flow: ridden from the top with no input (after a
	# push-off), every jump is sized for the speed carried from the one before, so each lands
	for pi2 in world.terrain.layout.get("parks", []).size():
		var pk2: Dictionary = world.terrain.layout["parks"][pi2]
		if not (pk2["name"] in ["Big Air Park", "Sierra Main Park"]):
			continue
		var rows := _ride_line(pi2, "jump", 6.0)
		var ok := rows.size() == (pk2["kickers"] as Array).filter(func(k): return k["line"] == "jump").size()
		var desc := []
		for r in rows:
			ok = ok and r["crash"] == "" and float(r["air"]) > 0.5 and float(r["land"]) > -1.0 and float(r["land"]) < float(r["landing"]) + 1.0
			desc.append("%s %.1f m/s %.1fs @%.1f/%.1f%s" % [r["size"], r["v_in"], r["air"], r["land"], r["landing"], (" " + r["crash"]) if r["crash"] != "" else ""])
		check("%s jump line ridden top to bottom: all %d jumps land on their landings" % [pk2["name"], rows.size()], ok, ", ".join(desc))
	# switch: X turns you round with a 180 on the snow; mashing it does one 180, not several; landing
	# a 180 jump keeps you riding switch; riding switch the head looks over a shoulder, and tapping
	# left / right quickly doesn't swing it back and forth
	var sw_spot := _find_slope(12.0, 20.0)
	if not sw_spot.is_empty():
		var sk := _settle_on(sw_spot["pos"], sw_spot["yaw"])
		_run(sk, 1.5, {})
		var flips := 0
		var was := sk.riding_switch
		for f in 120:
			sk.scripted_input = {"switch_stance": 1.0} if (f / 6) % 2 == 0 else {}     # mashing X for 1 s
			sk.step(1.0 / 120.0)
			sk.time += 1.0 / 120.0
			if sk.riding_switch != was:
				flips += 1
				was = sk.riding_switch
		check("switch stance: X does one clean 180 into switch, mashing it doesn't stack more", sk.riding_switch and flips == 1
			and absf(absf(sk.stance_vis) - PI) < 0.01, "%d stance changes, body yaw %.0f deg" % [flips, rad_to_deg(sk.stance_vis)])
		var bd = world.body
		bd._look_side = 1.0
		bd._look_hold = 0.0
		var side_changes := 0
		var last_side: float = bd._look_side
		for f in 240:
			sk.scripted_input = {"steer_left": 1.0} if (f / 12) % 2 == 0 else {"steer_right": 1.0}   # tapping 0.1 s each
			sk.step(1.0 / 120.0)
			sk.time += 1.0 / 120.0
			sk._prev_xform = sk._cur_xform
			sk._cur_xform = sk._compose_xform()
			bd._process(1.0 / 120.0)
			if bd._look_side != last_side:
				side_changes += 1
				last_side = bd._look_side
		var held_changes := 0
		for f in 120:
			sk.scripted_input = {"steer_left": 1.0}                                   # a held left turn
			sk.step(1.0 / 120.0)
			sk.time += 1.0 / 120.0
			bd._process(1.0 / 120.0)
		check("riding switch: the head stays over one shoulder when the turn keys are tapped, moves for a held turn",
			side_changes == 0 and bd._look_side < 0.0, "%d swaps while tapping; held left -> %s shoulder" % [side_changes,
			"right" if bd._look_side < 0.0 else "left"])
		# mid-air the head stays forward through a flip / spin; a front flip is tucked, never laid out
		sk.airborne = true
		sk.riding_switch = true
		sk.flip_vel = 4.5
		sk.spin_vel = 0.0
		sk.air_pitch = 2.4
		sk.land_t = 0.3
		for f in 120:
			bd._process(1.0 / 120.0)
		var mid_look: float = bd._p["switch_look"]
		var fl_tuck: float = bd._p["ftuck"]
		var fl_lay: float = bd._p["layout"]
		sk.flip_vel = 0.0
		sk.air_pitch = 0.0
		sk.vel = sk.forward_flat() * 12.0
		for f in 90:
			bd._process(1.0 / 120.0)
		var end_look: float = bd._p["switch_look"]
		check("front flip is tucked, not laid out; head looks over the shoulder only once the flip is done and he's about to land switch",
			fl_tuck > 0.8 and fl_lay < 0.05 and mid_look < 0.05 and end_look > 0.6,
			"tuck %.2f layout %.2f, look mid-flip %.2f, before touchdown %.2f" % [fl_tuck, fl_lay, mid_look, end_look])
		sk.airborne = false
	# the mega pipe: across the flat into a wall, straight up out of it and back in; and wall to wall
	var pr := _pipe_ride(50.0, 65.0, 15.0, 1)
	if not pr.is_empty():
		var h0: Dictionary = pr["hits"][0] if not pr["hits"].is_empty() else {}
		check("mega pipe: up the wall, air above the coping, land back in", not h0.is_empty() and float(h0["above_coping"]) > 0.5
			and h0["crash"] == "", str(h0))
		var pr2 := _pipe_ride(50.0, 85.0, 15.0, 4)
		var clean: int = (pr2["hits"] as Array).filter(func(h): return h["crash"] == "").size()
		check("mega pipe: wall to wall, 3+ hits without a crash", clean >= 3 and pr2["crashed"] == "",
			"%d hits, %d clean, crash '%s'" % [pr2["hits"].size(), clean, pr2["crashed"]])
		# flips off the wall go the way they're popped: hold Up up the wall, Down at the coping = backflip
		for pop in [["lean_forward", "lean_back", -1.0, "backflip"], ["lean_back", "lean_forward", 1.0, "front flip"]]:
			var wc := func(h: float, wh: float) -> Dictionary:
				if h > wh - 0.6:
					return {pop[0]: 1.0, pop[1]: 1.0}
				return {pop[0]: 1.0} if h > 0.5 else {}
			var pf := _pipe_ride(50.0, 65.0, 15.0, 1, false, {}, wc)
			var hf: Dictionary = pf["hits"][0] if not pf["hits"].is_empty() else {}
			check("mega pipe: a %s off the wall rotates that way and lands" % pop[3], not hf.is_empty() and hf["crash"] == ""
				and float(hf["flip"]) * float(pop[2]) > 200.0 and float(hf["tilt_err"]) < 8.0, str(hf))
	# pole push: tips go into the snow and stay there while planted; speed comes in strokes
	var stp: Dictionary = world.park.park_start(0)
	s.teleport(stp["pos"], stp["yaw"])
	var body = world.body
	var worst_h := 0.0
	var worst_slide := 0.0
	var plants := 0
	var tip0 := {}
	var worst_swing := 0.0
	var worst_reach := -1.0
	var worst_fore := 0.0
	var prev_dir := {}
	for i in 360:
		s.scripted_input = {"tuck": 1.0}
		s.step(1.0 / 120.0)
		s.time += 1.0 / 120.0
		s._cur_xform = s._compose_xform()
		s._prev_xform = s._cur_xform
		body._compute_pose(1.0 / 120.0)
		for sd in ["l", "r"]:
			# the hand must stay on the arm: shoulder-to-hand never longer than the arm
			var sh_hand: float = (body.joints["hand_" + sd] - body.joints["shoulder_" + sd]).length()
			worst_reach = maxf(worst_reach, sh_hand - (body.UPPER_ARM + body.FOREARM))
			var el_hand: float = (body.joints["hand_" + sd] - body.joints["elbow_" + sd]).length()
			worst_fore = maxf(worst_fore, absf(el_hand - body.FOREARM))
			var pdir: Vector3 = body.joints["pole_dir_" + sd]
			if prev_dir.has(sd) and i > 30:
				var sw := rad_to_deg((prev_dir[sd] as Vector3).angle_to(pdir))
				if sw > worst_swing and Game.test_args.has("pole_debug"):
					print("[TEST]   pole %s swing %.1f deg at phase %.3f planted %s push_amt %.2f" % [sd, sw, s.push_phase, body._pole_tip.has(sd), body._push_amt])
				worst_swing = maxf(worst_swing, sw)
			prev_dir[sd] = pdir
		for sd in ["l", "r"]:
			if body._pole_tip.has(sd):
				var tip: Vector3 = body.joints["pole_grip_" + sd] + body.joints["pole_dir_" + sd] * 1.18
				worst_h = maxf(worst_h, absf(tip.y - world.terrain.height(tip.x, tip.z)))
				if not tip0.has(sd) or (body._pole_tip[sd] as Vector3).distance_to(tip0[sd + "_w"]) > 0.001:
					tip0[sd] = tip
					tip0[sd + "_w"] = body._pole_tip[sd]
					plants += 1
				worst_slide = maxf(worst_slide, Vector2(tip.x - tip0[sd].x, tip.z - tip0[sd].z).length())
			else:
				tip0.erase(sd)
	check("pole push: tips plant in the snow and hold still", plants >= 4 and worst_h < 0.12 and worst_slide < 0.05,
		"%d plants, tip height off the snow %.2f m, tip slide %.3f m" % [plants, worst_h, worst_slide])
	check("pole push: three seconds of pushing gets you rolling (stronger push)", s.speed > 5.2, "%.1f m/s (%.0f km/h)" % [s.speed, s.speed * 3.6])
	check("pole push: poles swing, never snap (max turn per 1/120 s frame)", worst_swing < 6.0, "%.1f deg" % worst_swing)
	check("pole push: hands stay on the arms (no stretching past arm length)", worst_reach <= 0.005 and worst_fore <= 0.005,
		"shoulder-to-hand at most %.3f m past full reach, forearm length off by %.3f m" % [maxf(worst_reach, 0.0), worst_fore])
	# grab timing: the pose eases in over ~0.55 s and out over ~0.35 s (it takes time irl)
	var gbody = world.body
	s.teleport(stp["pos"], stp["yaw"])
	s.position.y += 40.0
	s.airborne = true
	s.vel = Vector3.ZERO
	var w_at := {}
	for i in 150:
		s.scripted_input = {"grab_left": 1.0} if i < 96 else {}      # the mute takes 0.75 s to get into
		s.step(1.0 / 120.0)
		s._cur_xform = s._compose_xform()
		s._prev_xform = s._cur_xform
		gbody._compute_pose(1.0 / 120.0)
		if i in [12, 30, 94, 140]:
			w_at[i] = gbody._gw
	check("grabs ease in (mute ~0.75 s) and let go smoothly (~0.35 s)",
		w_at[12] < 0.08 and w_at[30] > 0.1 and w_at[30] < 0.5 and w_at[94] > 0.97 and w_at[140] < 0.05,
		"pose %.2f at 0.1 s, %.2f at 0.25 s, %.2f at 0.78 s, %.2f 0.37 s after letting go" % [w_at[12], w_at[30], w_at[94], w_at[140]])
	# every grab pose: the grabbing arm is a real reach (elbow not folded up) and clear of the skis
	var worst_elbow := 180.0
	var worst_clear := 1.0
	var worst_name := ""
	for gname in gbody.GRAB_POSES:
		s.teleport(stp["pos"], stp["yaw"])
		s.position.y += 40.0
		s.airborne = true
		s._cur_xform = s._compose_xform()
		s._prev_xform = s._cur_xform
		gbody.preview_grab = gname
		gbody.arm_clear = {}
		for i in 40:
			gbody._compute_pose(0.03)
		var gp: Dictionary = gbody.GRAB_POSES[gname]
		for sd in ["l", "r"]:
			if not gp.has(sd):
				continue
			var j: Dictionary = gbody.joints
			var ang := rad_to_deg((j["shoulder_" + sd] - j["elbow_" + sd]).angle_to(j["hand_" + sd] - j["elbow_" + sd]))
			if ang < worst_elbow:
				worst_elbow = ang
				worst_name = gname
			worst_clear = minf(worst_clear, float(gbody.arm_clear.get(sd, 1.0)))
	gbody.preview_grab = ""
	gbody._gp = 0.0                # start the next check from no grab
	gbody._gw = 0.0
	gbody._ag = ""
	check("grab arms reach (no folded elbows) and stay clear of the skis", worst_elbow > 110.0 and worst_clear >= 0.0,
		"most bent grabbing elbow %.0f deg (%s), closest arm-to-ski %.2f m" % [worst_elbow, worst_name, worst_clear])
	s.airborne = false
	# the mute's skis start parallel and swing across into the X over time (not crossed at once)
	s.teleport(stp["pos"], stp["yaw"])
	s.position.y += 40.0
	s.airborne = true
	s.vel = Vector3.ZERO
	var cross_at := {}
	for i in 110:
		s.scripted_input = {"grab_left": 1.0}
		s.step(1.0 / 120.0)
		s._cur_xform = s._compose_xform()
		s._prev_xform = s._cur_xform
		gbody._compute_pose(1.0 / 120.0)
		if i in [6, 24, 48, 72, 109]:
			# angle between the two skis, seen from above
			var a: Vector3 = -gbody.ski_l.basis.z
			var b: Vector3 = -gbody.ski_r.basis.z
			cross_at[i] = rad_to_deg(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z)))
	var c0: float = absf(cross_at[6])
	var c1: float = absf(cross_at[24])
	var c2: float = absf(cross_at[48])
	var c3: float = absf(cross_at[72])
	var c4: float = absf(cross_at[109])
	check("mute: skis swing across into the X gradually", c0 < 6.0 and c1 < 15.0 and c2 > c1 + 5.0 and c3 > c2 and c4 > 35.0,
		"angle between the skis %.0f / %.0f / %.0f / %.0f / %.0f deg at 0.05 / 0.2 / 0.4 / 0.6 / 0.9 s" % [c0, c1, c2, c3, c4])
	s.airborne = false
	# grabs off the medium kicker: grab after takeoff, let go ~0.4 s before touching down
	# [name, keys from the start of the grab, extra keys pressed 0.2 s later (as a player would)]
	for gt in [["Mute", {"grab_left": 1.0}, {}], ["Safety", {"grab_right": 1.0}, {}],
			["Japan", {"grab_left": 1.0}, {"brake": 1.0}], ["Tip", {"grab_left": 1.0}, {"tuck": 1.0}],
			["Tail", {"grab_right": 1.0}, {"brake": 1.0}], ["Blunt", {"grab_right": 1.0}, {"tuck": 1.0}],
			["Truck Driver", {"grab_left": 1.0}, {"grab_right": 1.0}]]:
		var mk: Dictionary = {}
		for k in world.terrain.layout["parks"][0]["kickers"]:
			if k["size"] == "M":
				mk = k
		var md := Vector3(mk["dir"][0], 0, mk["dir"][1])
		s.teleport(Vector3(mk["origin"][0], 0, mk["origin"][1]) - md * 12.0, Skier.yaw_of(md), float(mk["approach_speed"]) - 1.0)
		var gbox := {}
		var gcb := func(info): gbox["info"] = info
		s.landed.connect(gcb)
		var held_name := ""
		for i in 900:
			var below := s.position.y - world.terrain.height(s.position.x, s.position.z)
			var falling := s.vel.y < 0.0
			var keys := {}
			if s.airborne and s.air_time > 0.15 and not (falling and below < 2.2):
				keys = (gt[1] as Dictionary).duplicate()
				if s.air_time > 0.35:
					keys.merge(gt[2])
			s.scripted_input = keys
			s.step(1.0 / 120.0)
			s.time += 1.0 / 120.0
			if s.grab_name != "":
				held_name = s.grab_name
			if gbox.has("info") or s.is_crashed:
				break
		s.landed.disconnect(gcb)
		var gi: Dictionary = gbox.get("info", {})
		var tr: Dictionary = TrickSystem.evaluate(gi) if not gi.is_empty() else {}
		check("%s grab off the medium kicker: held, named, landed clean" % gt[0], held_name == gt[0] and not gi.is_empty() and gi["crash"] == ""
			and str(tr.get("name", "")).contains(gt[0]) and absf(float(gi["flip"])) < 0.6,
			"held '%s' %.2f s -> '%s' %s, flip %.0f deg" % [held_name, float(gi.get("grab_time", 0.0)), tr.get("name", "-"), gi.get("crash", "no landing"),
			rad_to_deg(float(gi.get("flip", 0.0)))])
	# arrow tricks: ollie (set and let go), arrow backflip, arrow left 360, arrow rail pop
	var ost: Dictionary = world.park.park_start(0)
	s.teleport(ost["pos"], ost["yaw"], 4.0)
	var popped := false
	var opitch := 0.0
	var orot := 0.0
	for i in 240:
		s.scripted_input = {"lean_forward": 1.0} if i < 48 else {}
		s.step(1.0 / 120.0)
		if s.airborne:
			popped = true
			opitch = maxf(opitch, absf(s.air_pitch))
			orot = maxf(orot, absf(s.air_rotation))
		elif popped:
			break
	check("arrows: hold Up and let go = straight ollie", popped and opitch < 0.35 and orot < 0.35,
		"popped %s, max flip %.0f deg, max spin %.0f deg" % [popped, rad_to_deg(opitch), rad_to_deg(orot)])
	for at in [["L", "backflip", {"lean_forward": 1.0}, {"lean_back": 1.0}], ["M", "left 360", {"lean_right": 1.0}, {"lean_left": 1.0}]]:
		var ak: Dictionary = {}
		for k in world.terrain.layout["parks"][0]["kickers"]:
			if k["size"] == at[0] and k["line"] == "jump":
				ak = k
		var adir := Vector3(ak["dir"][0], 0, ak["dir"][1])
		var alip := Vector3(ak["lip"][0], 0, ak["lip"][1])
		s.teleport(Vector3(ak["origin"][0], 0, ak["origin"][1]) - adir * 12.0, Skier.yaw_of(adir), float(ak["approach_speed"]) - 1.0)
		var abox := {}
		var acb := func(info): abox["info"] = info
		s.landed.connect(acb)
		for i in 1200:
			var keys: Dictionary = (at[2] as Dictionary).duplicate()
			if (alip - s.position).dot(adir) < 0.4 or s.airborne:
				keys.merge(at[3])
			if s.airborne:
				if at[1] == "backflip" and s.air_pitch < -TAU * 0.55:
					keys.erase("lean_back")
				if at[1] == "left 360" and absf(s.air_rotation) + s.spin_vel * s.spin_vel / (2.0 * float(s.diff()["spin_damp"])) > deg_to_rad(350.0):
					keys.erase("lean_left")
			s.scripted_input = keys
			s.step(1.0 / 120.0)
			s.time += 1.0 / 120.0
			if abox.has("info") or s.is_crashed:
				break
		s.landed.disconnect(acb)
		var ai: Dictionary = abox.get("info", {})
		var atr: Dictionary = TrickSystem.evaluate(ai) if not ai.is_empty() else {}
		var want := "Backflip" if at[1] == "backflip" else "Left 360"
		check("arrows: %s off the %s kicker (set, then the opposite arrow at the lip)" % [at[1], at[0]],
			not ai.is_empty() and ai["crash"] == "" and str(atr.get("name", "")).contains(want),
			"'%s' %s" % [atr.get("name", "-"), ai.get("crash", "no landing")])
	s.scripted_input = {}
	# grab keys (Q/E + W/S) never touch the flip: same rotation with and without a grab held
	var flip_with := {}
	for with_grab in [false, true]:
		s.teleport(stp["pos"], stp["yaw"])
		s.position.y += 40.0
		s.airborne = true
		s.vel = Vector3.ZERO
		s.air_pitch = 0.0
		s.flip_vel = -3.0
		for i in 48:
			var keys := {"lean_back": 1.0}
			if with_grab:
				keys.merge({"grab_left": 1.0, "tuck": 1.0})
			s.scripted_input = keys
			s.step(1.0 / 120.0)
		flip_with[with_grab] = s.air_pitch
	s.airborne = false
	check("a grab (Q + W) doesn't change the flip", absf(float(flip_with[true]) - float(flip_with[false])) < 0.01,
		"%.0f deg without, %.0f deg with the grab after 0.4 s" % [rad_to_deg(flip_with[false]), rad_to_deg(flip_with[true])])
	# backflip + tip grab off the large kicker: hold Down at the lip, Q + W in the air
	var lk: Dictionary = {}
	for k in world.terrain.layout["parks"][0]["kickers"]:
		if k["size"] == "L":
			lk = k
	var ld := Vector3(lk["dir"][0], 0, lk["dir"][1])
	var llip := Vector3(lk["lip"][0], 0, lk["lip"][1])
	s.teleport(Vector3(lk["origin"][0], 0, lk["origin"][1]) - ld * 12.0, Skier.yaw_of(ld), float(lk["approach_speed"]) - 1.0)
	var bbox := {}
	var bcb := func(info): bbox["info"] = info
	s.landed.connect(bcb)
	for i in 1200:
		var to_lip := (llip - s.position).dot(ld)
		var keys := {}
		if not s.airborne:
			keys = {"lean_forward": 1.0} if to_lip > 0.4 else {"lean_forward": 1.0, "lean_back": 1.0}
		else:
			if s.air_pitch > -TAU * 0.55:
				keys["lean_back"] = 1.0
			keys["lean_forward"] = 1.0       # the set arrow still held: must be ignored in the air
			var below := s.position.y - world.terrain.height(s.position.x, s.position.z)
			if s.air_time > 0.15 and not (s.vel.y < 0.0 and below < 2.4):
				keys.merge({"grab_left": 1.0, "tuck": 1.0})
		s.scripted_input = keys
		s.step(1.0 / 120.0)
		s.time += 1.0 / 120.0
		if bbox.has("info") or s.is_crashed:
			break
	s.landed.disconnect(bcb)
	var bi: Dictionary = bbox.get("info", {})
	var btr: Dictionary = TrickSystem.evaluate(bi) if not bi.is_empty() else {}
	check("Backflip Tip off the large kicker (hold Up, press Down at the lip, Q + W in the air)", not bi.is_empty() and bi["crash"] == ""
		and str(btr.get("name", "")).contains("Backflip") and str(btr.get("name", "")).contains("Tip"),
		"'%s' %s" % [btr.get("name", "-"), bi.get("crash", "no landing")])
	# S used for a Japan and still held when landing: no hockey stop until it's pressed again
	var sp_after := {}
	for hold_s in [false, true]:
		s.teleport(Vector3(lk["origin"][0], 0, lk["origin"][1]) - ld * 12.0, Skier.yaw_of(ld), float(lk["approach_speed"]) - 1.0)
		var landed_at := -1
		for i in 1200:
			var keys := {}
			var below := s.position.y - world.terrain.height(s.position.x, s.position.z)
			if s.airborne and s.air_time > 0.15 and not (s.vel.y < 0.0 and below < 2.4):
				keys = {"grab_left": 1.0, "brake": 1.0}
			elif s.airborne and hold_s:
				keys = {"brake": 1.0}
			elif not s.airborne and landed_at >= 0 and hold_s:
				keys = {"brake": 1.0}
			s.scripted_input = keys
			var was_air := s.airborne
			s.step(1.0 / 120.0)
			s.time += 1.0 / 120.0
			if was_air and not s.airborne and landed_at < 0:
				landed_at = i
			if landed_at >= 0 and i - landed_at >= 60:
				break
		sp_after[hold_s] = s.speed
	check("holding S through the landing after a Japan doesn't hockey-stop", float(sp_after[true]) > float(sp_after[false]) - 0.3,
		"%.1f m/s with S still held vs %.1f m/s without, 0.5 s after landing" % [sp_after[true], sp_after[false]])
	s.scripted_input = {}
	s.difficulty = saved


## Both skis stay on the boots in every flip attitude.
func _skis_attached(spot: Dictionary) -> void:
	var s := _settle_on(spot["pos"], spot["yaw"])
	var body := world.body
	var worst := 0.0
	s.airborne = true
	s.position.y += 5.0
	for k in 12:
		s.air_pitch = -TAU * k / 12.0
		s._cur_xform = s._compose_xform()
		s._prev_xform = s._cur_xform
		body._compute_pose(0.016)
		for sd in ["l", "r"]:
			var ski: Transform3D = body.ski_l if sd == "l" else body.ski_r
			worst = maxf(worst, ski.origin.distance_to(body.joints["ankle_" + sd]))
	s.airborne = false
	s.air_pitch = 0.0
	check("skis stay on the boots through a full flip", worst < 0.3, "max ski-to-ankle %.2f m" % worst)


func _body_physics(spot: Dictionary) -> void:
	var s := world.skier
	var saved := s.difficulty
	s.difficulty = 1
	var plain := _pop(spot, {"jump": 1.0}, 0.6, {"jump": 1.0}, 0.25, {})
	var loaded := _pop(spot, {"jump": 1.0, "lean_back": 1.0}, 0.6, {"jump": 1.0}, 0.25, {})
	check("leaning back loads the tails: bigger pop", loaded["clear"] > plain["clear"] * 1.15, "%.2f m vs %.2f m" % [loaded["clear"], plain["clear"]])
	var bf := _pop(spot, {"jump": 1.0, "lean_back": 1.0}, 0.6, {"jump": 1.0, "lean_back": 1.0}, 0.05, {"lean_back": 1.0}, 0.35)
	check("holding back at the pop starts a backflip", bf["pitch"] < -0.5, "%.0f deg after 0.35 s" % rad_to_deg(bf["pitch"]))
	var wound := _pop(spot, {"jump": 1.0, "lean_left": 1.0}, 0.8, {"jump": 1.0, "lean_left": 1.0}, 0.02, {}, 0.5)
	check("holding Left winds up a RIGHT spin", wound["rot"] > deg_to_rad(70.0), "%.0f deg in 0.5 s" % rad_to_deg(wound["rot"]))
	var held := _pop(spot, {"jump": 1.0, "lean_left": 1.0}, 0.8, {"jump": 1.0, "lean_left": 1.0}, 0.02, {"lean_left": 1.0}, 0.5)
	check("keeping Left held after the pop doesn't undo the spin", held["rot"] > deg_to_rad(70.0), "%.0f deg in 0.5 s" % rad_to_deg(held["rot"]))
	var both := _pop(spot, {"jump": 1.0, "lean_left": 1.0}, 0.8, {"jump": 1.0, "lean_left": 1.0}, 0.02, {"lean_right": 1.0}, 0.5)
	check("wind up Left, then Right in the air: faster right spin", both["rot"] > wound["rot"], "%.0f vs %.0f deg" % [rad_to_deg(both["rot"]), rad_to_deg(wound["rot"])])
	# multiple flips: keep pulling past ~3/4 of a turn and the body tucks; let go and it opens up
	s.teleport(s.position, s.heading)
	s.position.y += 60.0
	s.airborne = true
	s.air_pitch = -1.0
	s.flip_vel = -4.0
	s.scripted_input = {"lean_back": 1.0}
	for i in 24:
		s.step(1.0 / 120.0)
	check("the first flip stays laid out", s.flip_tuck < 0.05, "tuck %.2f at %.0f deg" % [s.flip_tuck, rad_to_deg(-s.air_pitch)])
	s.air_pitch = -TAU * 0.8
	for i in 36:
		s.step(1.0 / 120.0)
	var tucked := s.flip_tuck
	s.scripted_input = {}
	for i in 60:
		s.step(1.0 / 120.0)
	check("pulling a second flip tucks, letting go opens up", tucked > 0.8 and s.flip_tuck < 0.3, "tuck %.2f -> %.2f" % [tucked, s.flip_tuck])
	s.airborne = false
	s.air_pitch = 0.0
	var ctrl := []
	for d in 3:
		s.difficulty = d
		ctrl.append(_pop(spot, {"jump": 1.0}, 0.6, {"jump": 1.0}, 0.02, {"spin_right": 1.0}, 0.45)["rot"])
	check("air control: Easy > Normal > Realistic", ctrl[0] > ctrl[1] and ctrl[1] > ctrl[2], "%.0f / %.0f / %.0f deg" % [rad_to_deg(ctrl[0]), rad_to_deg(ctrl[1]), rad_to_deg(ctrl[2])])
	# landing upside down
	s.difficulty = 1
	s = _settle_on(spot["pos"], spot["yaw"])
	s.position.y += 1.5
	s.airborne = true
	s.air_pitch = -PI * 0.85
	s.air_time = 0.8
	s.vel = s.forward_flat() * 8.0 + Vector3.DOWN * 3.0
	var box := {}
	var cb := func(reason, _v): box["r"] = reason
	s.crashed.connect(cb)
	s.scripted_input = {}
	for i in 120:
		if s.is_crashed:
			break
		s.step(1.0 / 120.0)
	s.crashed.disconnect(cb)
	check("landing on your back crashes", String(box.get("r", "")) == "Landed on your back", String(box.get("r", "no crash")))
	s.difficulty = saved


## Rides at a park feature along its line from `back` metres before it.  Optional per-step
## controller `ctl(s) -> Dictionary` provides the input.  Returns {mounted, info, crash, slide}.
func _jib_run(r: Dictionary, back: float, v0: float, ctl: Callable, heading_off := 0.0, from_air := false, lateral := 0.0) -> Dictionary:
	var s := world.skier
	var a: Vector3 = r["a"]
	var dir: Vector3 = (r["b"] - a).normalized()
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	s.teleport(a - flat * back + flat.cross(Vector3.UP) * lateral, Skier.yaw_of(flat), v0)
	var res := {"mounted": false, "info": {}, "crash": "", "slide": false}
	if from_air:
		s.position = a + dir * 0.8 + Vector3.UP * 0.25
		s.airborne = true
		s.vel = dir * v0 + Vector3.DOWN * 1.0
		s.heading = Skier.yaw_of(flat) + heading_off
	var box := {}
	var cb := func(info): box["info"] = info
	var ccb := func(reason, _v): box["crash"] = reason
	s.jibbed.connect(cb)
	s.crashed.connect(ccb)
	for i in 600:
		if s.is_crashed or box.has("info"):
			break
		s.scripted_input = ctl.call(s)
		s.step(1.0 / 120.0)
		s.time += 1.0 / 120.0
		if s.is_grinding():
			res["mounted"] = true
			res["slide"] = s.grind_slide
	s.jibbed.disconnect(cb)
	s.crashed.disconnect(ccb)
	res["info"] = box.get("info", {})
	res["crash"] = box.get("crash", "")
	return res


func _run_shape(r: Dictionary, back: float, v0: float, ctl: Callable) -> Dictionary:
	var s := world.skier
	var a: Vector3 = r["pts"][0]
	var dir: Vector3 = ((r["pts"][1] as Vector3) - a).normalized()
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	s.teleport(a - flat * back, Skier.yaw_of(flat), v0)
	var res := {"mounted": false, "info": {}, "crash": ""}
	var box := {}
	var cb := func(info): box["info"] = info
	var ccb := func(reason, _v): box["crash"] = reason
	s.jibbed.connect(cb)
	s.crashed.connect(ccb)
	for i in 900:
		if s.is_crashed or box.has("info"):
			break
		s.scripted_input = ctl.call(s)
		s.step(1.0 / 120.0)
		s.time += 1.0 / 120.0
		if s.is_grinding():
			res["mounted"] = true
	s.jibbed.disconnect(cb)
	s.crashed.disconnect(ccb)
	res["info"] = box.get("info", {})
	res["crash"] = box.get("crash", "")
	return res


func _jibs() -> void:
	var s := world.skier
	var park = world.park
	if park == null or park.rails.is_empty():
		check("terrain park has rails and boxes", false)
		return
	var boxes: Array = park.rails.filter(func(r): return r["kind"] == "box" and r["shape"] == "straight")
	var rls: Array = park.rails.filter(func(r): return r["kind"] == "rail" and r["shape"] == "straight")
	check("terrain park has rails and boxes", not boxes.is_empty() and not rls.is_empty(), "%d boxes, %d rails" % [boxes.size(), rls.size()])
	var saved := s.difficulty
	var none := func(_s): return {}
	s.difficulty = 0
	var r1 := _jib_run(boxes[0], 10.0, 8.0, none)
	var name1 := str(TrickSystem.evaluate_jib(r1["info"]).get("name", "")) if not r1["info"].is_empty() else ""
	check("box: ride on from the snow and slide to the end", r1["mounted"] and r1["info"].get("how", "") == "end", "%s, %.1f s -> '%s'" % [r1["info"].get("how", "no slide"), float(r1["info"].get("time", 0.0)), name1])
	var r2 := _jib_run(rls[0], 10.0, 8.0, none)
	check("rail: cannot ride onto it at snow level", not r2["mounted"])
	var popper := func(sk: Skier):
		var dist: float = (rls[0]["a"] as Vector3 - sk.position).dot((rls[0]["b"] - rls[0]["a"]).normalized())
		return {"jump": 1.0} if dist > 4.0 else {}
	var r3 := _jib_run(rls[0], 11.0, 8.5, popper)
	check("rail: pop onto it", r3["mounted"], "%s %s" % [r3["info"].get("how", "no slide"), r3["crash"]])
	var arrow_popper := func(sk: Skier):
		var dist: float = (rls[0]["a"] as Vector3 - sk.position).dot((rls[0]["b"] - rls[0]["a"]).normalized())
		return {"lean_forward": 1.0} if dist > 4.0 else {}
	var r3b := _jib_run(rls[0], 11.0, 8.5, arrow_popper)
	check("rail: arrow ollie onto it (hold Up, let go)", r3b["mounted"], "%s %s" % [r3b["info"].get("how", "no slide"), r3b["crash"]])
	var longest: Dictionary = boxes[0]
	for b in boxes:          # the Main Park's longest box (steeper parks slide you off the end too fast to fall)
		if int(b["park"]) == 0 and float(b["length"]) > float(longest["length"]):
			longest = b
	s.difficulty = 2
	var r4 := _jib_run(longest, 10.0, 6.0, none, 0.0, false, 0.25)    # half a box width off-centre
	check("Realistic: entering off-centre with no balance input falls off", r4["mounted"] and r4["crash"] == "Fell off the rail", "%s %s" % [r4["info"].get("how", ""), r4["crash"]])
	var balancer := func(sk: Skier):
		if not sk.is_grinding():
			return {}
		var c := -sk.rail_balance * 3.0 - sk._rail_bal_vel * 1.5
		return {"steer_right": clampf(c, 0.0, 1.0), "steer_left": clampf(-c, 0.0, 1.0)}
	var r5 := _jib_run(longest, 10.0, 6.0, balancer, 0.0, false, 0.25)
	check("Realistic: balancing with A/D reaches the end", r5["info"].get("how", "") == "end", "%s %s, %.1f s" % [r5["info"].get("how", ""), r5["crash"], float(r5["info"].get("time", 0.0))])
	# Sierra Main Park: the wide car box rides on from the snow; the long lift-tower rail takes a pop
	s.difficulty = 0
	var wides: Array = park.rails.filter(func(r): return r["kind"] == "widebox")
	if not wides.is_empty():
		var rw := _jib_run(wides[0], 10.0, 8.0, none)
		check("wide car box: ride on from the snow and slide to the end", rw["mounted"] and rw["info"].get("how", "") == "end",
			"%s, %.1f s" % [rw["info"].get("how", "no slide"), float(rw["info"].get("time", 0.0))])
	var long_rail: Dictionary = rls[0]
	for r in rls:
		if float(r["length"]) > float(long_rail["length"]):
			long_rail = r
	var lpop := func(sk: Skier):
		var dist: float = (long_rail["a"] as Vector3 - sk.position).dot((long_rail["b"] - long_rail["a"]).normalized())
		return {"jump": 1.0} if dist > 4.0 else {}
	var rl := _jib_run(long_rail, 11.0, 9.0, lpop)
	check("long %.0f m lift-tower rail: pop on and slide it out" % float(long_rail["length"]), rl["mounted"] and rl["crash"] == "",
		"%s, %.1f s %s" % [rl["info"].get("how", "no slide"), float(rl["info"].get("time", 0.0)), rl["crash"]])
	# every shaped rail and box can be ridden to the end (Normal, balancing with A/D as needed): pop
	# onto rails, ride onto boxes; approach along the first section
	s.difficulty = 1
	var shapes_ok := {}
	for r in park.rails:
		var shp: String = r["shape"]
		if shp == "straight" or shp == "flat" or shapes_ok.has(shp + r["kind"]):
			continue
		var d0: Vector3 = ((r["pts"][1] as Vector3) - r["pts"][0]).normalized()
		var ctl := func(sk: Skier):
			if sk.is_grinding():
				var c := -sk.rail_balance * 3.0 - sk._rail_bal_vel * 1.5
				return {"steer_right": clampf(c, 0.0, 1.0), "steer_left": clampf(-c, 0.0, 1.0)}
			var dist: float = ((r["a"] as Vector3) - sk.position).dot(d0)
			return {"jump": 1.0} if dist > 4.0 else {}        # shaped boxes rise off the snow too: pop on
		var rr := _run_shape(r, 11.0, 9.0, ctl)
		shapes_ok[shp + r["kind"]] = true
		check("%s %s: ride it to the end" % [shp, r["kind"]], rr["mounted"] and rr["info"].get("how", "") == "end" and rr["crash"] == "",
			"%s, %.1f s %s -> '%s'" % [rr["info"].get("how", "no slide"), float(rr["info"].get("time", 0.0)), rr["crash"],
			str(TrickSystem.evaluate_jib(rr["info"]).get("name", "")) if not rr["info"].is_empty() else ""])
	# gap to rail: roll over the snow lip (no input) and the rail assist puts you on the level rail
	var lips: Array = []
	for pk in world.terrain.layout["parks"]:
		for k in pk["kickers"]:
			if k.get("rail_lip", false):
				lips.append(k)
	if not lips.is_empty():
		var lk: Dictionary = lips[0]
		var ld := Vector3(lk["dir"][0], 0, lk["dir"][1]).normalized()
		var lo := Vector3(lk["origin"][0], 0, lk["origin"][1])
		s.teleport(lo - ld * 10.0, Skier.yaw_of(ld), 9.0)
		s.scripted_input = {}
		var got := {}
		var lcb := func(info): got["info"] = info
		s.jibbed.connect(lcb)
		var mounted := false
		var crash_r := ""
		for f in 600:
			s.step(1.0 / 120.0)
			s.time += 1.0 / 120.0
			mounted = mounted or s.is_grinding()
			if s.is_crashed:
				crash_r = "crashed"
				break
			if got.has("info") and not s.airborne and not s.is_grinding():
				break
		s.jibbed.disconnect(lcb)
		check("gap to rail: pop off the lip onto the level rail and slide it out", mounted and got.get("info", {}).get("how", "") == "end"
			and crash_r == "", "%s %s" % [str(got.get("info", {}).get("how", "no slide")), crash_r])
	# rail assist: jumping at a rail 0.8 m off its line still lands you on it (not on Realistic)
	var popper2 := func(sk: Skier):
		var dist: float = (rls[0]["a"] as Vector3 - sk.position).dot((rls[0]["b"] - rls[0]["a"]).normalized())
		return {"jump": 1.0} if dist > 4.0 else {}
	var ra := _jib_run(rls[0], 11.0, 8.5, popper2, 0.0, false, 0.8)
	check("rail assist: jump at a rail 0.8 m off line and land on it", ra["mounted"], "%s %s" % [ra["info"].get("how", "missed"), ra["crash"]])
	# spin on a box: ride on, tap Right - a 180 on it, and the trick says so
	var tapper := func(sk: Skier):
		if sk.is_grinding() and sk.grind_time > 0.15 and sk.grind_time < 0.22:
			return {"lean_right": 1.0}
		return {}
	var rs := _jib_run(boxes[0], 10.0, 8.0, tapper)
	check("spin on a box: a tap of Right turns you 180 on it", rs["mounted"] and float(rs["info"].get("spin", 0.0)) >= 170.0,
		"%s spun %.0f deg -> '%s'" % [rs["info"].get("how", "no slide"), float(rs["info"].get("spin", 0.0)),
		str(TrickSystem.evaluate_jib(rs["info"]).get("name", "")) if not rs["info"].is_empty() else ""])
	var r6 := _jib_run(boxes[0], 0.0, 7.0, none, PI * 0.5, true)
	check("landing across a box gives a slide", r6["mounted"] and r6["slide"], str(TrickSystem.evaluate_jib(r6["info"]).get("name", "")) if not r6["info"].is_empty() else r6["crash"])
	s.difficulty = saved


func _on_foot(spot: Dictionary) -> void:
	var s := _settle_on(spot["pos"], spot["yaw"])
	_run(s, 2.0, {})
	check("cannot take skis off while moving fast", not s.toggle_skis(), "%.1f m/s" % s.speed)
	s = _settle_on(spot["pos"], spot["yaw"])
	check("skis come off at rest", s.toggle_skis() and s.mode == Skier.Mode.WALK)
	# walk downhill, then the same distance uphill
	var down := Skier.forward_flat_s(spot["yaw"])
	s.cam_yaw = spot["yaw"]
	var p0 := s.position
	_run(s, 3.0, {"tuck": 1.0})
	var d_down := Vector2(s.position.x - p0.x, s.position.z - p0.z).length()
	s.cam_yaw = Skier.yaw_of(-down)
	p0 = s.position
	_run(s, 3.0, {"tuck": 1.0})
	var d_up := Vector2(s.position.x - p0.x, s.position.z - p0.z).length()
	check("walking moves at walking pace", d_down > 3.0 and d_down < 7.0, "%.1f m in 3 s downhill" % d_down)
	check("hiking uphill is slower", d_up < d_down * 0.8 and d_up > 0.5, "%.1f m up vs %.1f m down (%.0f deg)" % [d_up, d_down, spot["slope"]])
	s.cam_yaw = spot["yaw"]
	p0 = s.position
	_run(s, 3.0, {"tuck": 1.0, "carve": 1.0})
	var d_jog := Vector2(s.position.x - p0.x, s.position.z - p0.z).length()
	check("jogging is faster", d_jog > d_down * 1.4, "%.1f m in 3 s" % d_jog)
	check("walker stays on the snow", absf(s.position.y - world.terrain.height(s.position.x, s.position.z)) < 0.05 and not s.is_crashed)
	var steep := _find_slope(46.0, 60.0)
	if not steep.is_empty():
		s = _settle_on(steep["pos"], steep["yaw"])
		s.toggle_skis()
		s.cam_yaw = steep["yaw"] + PI
		var h0 := s.position.y
		_run(s, 3.0, {"tuck": 1.0})
		check("cannot hike up a cliff face", s.position.y - h0 < 0.6, "climbed %.2f m on %.0f deg" % [s.position.y - h0, steep["slope"]])
	s = _settle_on(spot["pos"], spot["yaw"])
	s.toggle_skis()
	check("skis go back on", s.toggle_skis() and s.mode == Skier.Mode.SKI)


## Runs Village Sprint through the challenge system (teleporting gate to gate), then starts it
## again: the first finish stores a ghost, the second run shows it.
func _ghost_race() -> void:
	var ch = get_parent().get("challenges")
	if ch == null:
		return
	var s := world.skier
	Engine.time_scale = 4.0
	for run in 2:
		ch.start("race_village_sprint")
		while ch.phase == "countdown":
			await get_tree().process_frame
		if run == 1:
			await _frames(6)
			check("second run shows the ghost of the best run", ch._ghost != null and ch._ghost.visible)
		for cp in ch.active.get("checkpoints", []):
			s.teleport(Vector3(cp[0], 0, cp[1]), s.heading)
			await _frames(2)
		if run == 0:
			check("finishing a race stores a ghost", Game.save.get("ghosts", {}).get("race_village_sprint", []).size() > 8,
				"%d samples" % Game.save.get("ghosts", {}).get("race_village_sprint", []).size())
	ch.stop(false)
	Engine.time_scale = 1.0


func _lift_ride() -> void:
	var r = world.resort
	if r == null or r.lifts.is_empty():
		check("resort has lifts", false)
		return
	var s := world.skier
	for lf: Dictionary in r.lifts:
		var nm: String = lf["name"]
		var lp: Vector3 = r.load_point(lf)
		# every lift: standing on its mat selects that lift, not a neighbour's
		var near: Dictionary = r.lift_near(lp + (lf["dir"] as Vector3) * 1.0)
		check("%s: its mat selects it" % nm, not near.is_empty() and near["index"] == lf["index"], "got %s" % near.get("name", "none"))
		# skis stay clear of the snow along the whole up line (feet hang ~0.75 m below the seat)
		var lowest := INF
		var d: float = r.LOAD_S + 15.0
		while d < float(lf["up_len"]) - r.UNLOAD_BEFORE - 15.0:
			var q: Vector3 = r._sample_loop(lf, d).origin
			lowest = minf(lowest, q.y + r.SEAT_Y - 0.75 - world.terrain.height(q.x, q.z))
			d += 4.0
		check("%s: skis clear the snow" % nm, lowest > 0.3, "lowest %.1f m" % lowest)
		s.teleport(lp - (lf["dir"] as Vector3) * 2.0, Skier.yaw_of(lf["dir"]))
		Engine.time_scale = 4.0
		r.board(r.lift_near(s.position), s)
		var t := 0.0
		while t < 15.0 and s.mode != Skier.Mode.LIFT:
			await get_tree().process_frame
			t += get_process_delta_time()
		var info0: Dictionary = r.ride_info()
		check("%s: chair picks the skier up" % nm, s.mode == Skier.Mode.LIFT and info0.get("name", "") == nm, "after %.1f s" % t)
		var y0 := s.position.y
		for i in 90:
			await get_tree().process_frame
		var info: Dictionary = r.ride_info()
		check("%s: riding up" % nm, s.position.y > y0 + 1.0 and info.get("phase", "") == "ride", "climbed %.1f m, %.0f s to go" % [s.position.y - y0, float(info.get("remaining", 0.0))])
		r.skip_ride()
		await get_tree().process_frame
		var top: Vector3 = r.unload_point(lf)
		check("%s: unloads at the top on skis" % nm, s.mode == Skier.Mode.SKI and Vector2(s.position.x - top.x, s.position.z - top.z).length() < 6.0)
		Engine.time_scale = 1.0


func _find_slope(min_deg: float, max_deg: float, groomed := false) -> Dictionary:
	var t := world.terrain
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 20000:
		var x := rng.randf_range(400, t.world - 400)
		var z := rng.randf_range(400, t.world - 400)
		var sl := t.slope_deg(x, z)
		if sl < min_deg or sl > max_deg:
			continue
		if groomed and t.surface_at(x, z).g < 0.6:
			continue
		if world.obstacles.clearance(x, z, 30.0) < 25.0:
			continue
		# consistent slope ahead
		var n := t.normal(x, z, 4.0)
		var down := Vector3(n.x, 0, n.z).normalized()
		var ok := true
		for k in range(1, 8):
			var q := Vector3(x, 0, z) + down * k * 12.0
			var s2 := t.slope_deg(q.x, q.z)
			if s2 < min_deg - 6.0 or s2 > max_deg + 6.0 or world.obstacles.clearance(q.x, q.z, 20.0) < 10.0:
				ok = false
				break
		if ok:
			return {"pos": Vector3(x, 0, z), "yaw": Skier.yaw_of(down), "slope": sl}
	return {}


func _physics() -> void:
	var s := world.skier
	world.body.set_process(false)
	# 1. acceleration down a moderate slope
	var spot := _find_slope(18.0, 26.0)
	check("find moderate slope", not spot.is_empty())
	if spot.is_empty():
		return
	s = _settle_on(spot["pos"], spot["yaw"])
	_run(s, 3.0, {})
	var v3 := s.vel.length()
	check("accelerates downhill", v3 > 8.0 and v3 < 30.0, "speed after 3 s on %.0f deg: %.1f m/s" % [spot["slope"], v3])
	# jacket cloth: skiing fast, the hem and hood are blown back (against the direction of travel)
	var body = world.body
	var hood_along := 0.0
	var pant_along := 0.0
	var hood_max := 0.0
	for i in 150:
		s.step(1.0 / 120.0)
		s.time += 1.0 / 120.0
		s._prev_xform = s._cur_xform
		s._cur_xform = s._compose_xform()
		body._process(1.0 / 120.0)
		if i >= 90:
			var tdir := s.vel.normalized()
			hood_along += (body._cloth["hood"][0] as Vector3).dot(tdir) / 60.0
			pant_along += ((body._cloth["pant_l"][0] as Vector3).dot(tdir) + (body._cloth["pant_r"][0] as Vector3).dot(tdir)) / 120.0
			hood_max = maxf(hood_max, (body._cloth["hood"][0] as Vector3).length())
	check("cloth: at speed the hood and the pant legs blow back (0.5 s average), the hood flaps", hood_along < -0.012 and pant_along < -0.006
		and hood_max <= 0.0901 and body._cloth_hood_flap > 0.0,
		"%.1f m/s: hood %.3f m, legs %.3f m along travel, hood flap %.3f m" % [s.vel.length(), hood_along, pant_along, body._cloth_hood_flap])
	# landing: the hood drops, then bounces back up past where it hung
	body._cloth_air = true
	body._cloth_vy = -7.0
	var hood_y := []
	for i in 90:
		s.step(1.0 / 120.0)
		s.time += 1.0 / 120.0
		s._prev_xform = s._cur_xform
		s._cur_xform = s._compose_xform()
		body._process(1.0 / 120.0)
		hood_y.append((body._cloth["hood"][0] as Vector3).dot(body.torso_basis.y))
	var lo_i := 0
	for i in hood_y.size():
		if hood_y[i] < hood_y[lo_i]:
			lo_i = i
	var hi_after: float = hood_y.slice(lo_i).max()
	var series := []
	for i in range(0, hood_y.size(), 6):
		series.append("%.3f" % hood_y[i])
	check("cloth: landing drops the hood and it bounces back", hood_y[lo_i] < -0.02 and hi_after - hood_y[lo_i] > 0.03,
		"lowest %.3f m at %d ms, then up to %.3f m (every 50 ms: %s)" % [hood_y[lo_i], lo_i * 1000 / 120, hi_after, " ".join(series)])
	check("stays grounded on smooth slope", not s.airborne and not s.is_crashed)
	# 2. no tuck: once you're moving, W (pole push) adds nothing
	s = _settle_on(spot["pos"], spot["yaw"])
	_run(s, 2.0, {})
	_run(s, 2.0, {})
	var upright := s.vel.length()
	s = _settle_on(spot["pos"], spot["yaw"])
	_run(s, 2.0, {})
	_run(s, 2.0, {"tuck": 1.0})
	var tucked := s.vel.length()
	check("no tucking: W adds no speed once moving", absf(tucked - upright) < 0.05 and s.tuck == 0.0, "without %.2f vs with W %.2f m/s" % [upright, tucked])
	# 3. hockey stop: skis swing across the direction of travel and the skier stops
	s = _settle_on(spot["pos"], spot["yaw"])
	_run(s, 3.0, {})
	var before := s.vel.length()
	var max_slip := 0.0
	var t_stop := -1.0
	s.scripted_input = {"brake": 1.0}
	for i in 360:
		s.step(1.0 / 120.0)
		s.time += 1.0 / 120.0
		var hv := Vector3(s.vel.x, 0, s.vel.z)
		if hv.length() > 1.0:
			max_slip = maxf(max_slip, rad_to_deg(absf(hv.normalized().signed_angle_to(s.forward_flat(), Vector3.UP))))
		if t_stop < 0.0 and s.vel.length() < 1.0:
			t_stop = i / 120.0
	check("hockey stop stops", t_stop > 0.0 and t_stop < 2.6, "%.1f m/s -> stopped in %.2f s" % [before, t_stop])
	check("hockey stop turns skis across", max_slip > 60.0, "max ski angle to travel %.0f deg" % max_slip)
	check("stopped skier holds on the slope", s.vel.length() < 0.6 and not s.is_crashed, "%.2f m/s after 3 s holding" % s.vel.length())
	# 4. a short tap only checks speed (progressive), steering picks the side
	s = _settle_on(spot["pos"], spot["yaw"])
	_run(s, 3.0, {})
	var v_tap0 := s.vel.length()
	_run(s, 0.3, {"brake": 1.0})
	_run(s, 0.3, {})
	check("tapping brake only checks speed", s.vel.length() > v_tap0 * 0.4 and s.vel.length() < v_tap0 * 1.05, "%.1f -> %.1f m/s" % [v_tap0, s.vel.length()])
	s = _settle_on(spot["pos"], spot["yaw"])
	_run(s, 3.0, {})
	_run(s, 0.5, {"brake": 1.0, "steer_left": 1.0})
	check("steered hockey stop pivots that way", s.stop_side < 0.0, "stop side %.0f" % s.stop_side)
	# 5. carving turns gradually (no instant redirect) and changes direction
	s = _settle_on(spot["pos"], spot["yaw"])
	_run(s, 2.5, {})
	var dir0 := Vector3(s.vel.x, 0, s.vel.z).normalized()
	_run(s, 0.1, {"steer_left": 1.0})
	var dir1 := Vector3(s.vel.x, 0, s.vel.z).normalized()
	check("turning is not instant", rad_to_deg(dir0.angle_to(dir1)) < 12.0, "%.1f deg in 0.1 s" % rad_to_deg(dir0.angle_to(dir1)))
	_run(s, 1.2, {"steer_left": 1.0})
	var dir2 := Vector3(s.vel.x, 0, s.vel.z).normalized()
	check("carving changes direction", rad_to_deg(dir0.angle_to(dir2)) > 25.0, "%.1f deg in 1.3 s" % rad_to_deg(dir0.angle_to(dir2)))
	# 6. ollie: charge and release
	s = _settle_on(spot["pos"], spot["yaw"])
	_run(s, 1.5, {})
	_run(s, 0.6, {"jump": 1.0})
	var was_air := false
	var max_h := 0.0
	var air_t := 0.0
	s.scripted_input = {}
	for i in 480:
		s.step(1.0 / 120.0)
		s.time += 1.0 / 120.0
		if s.airborne:
			was_air = true
			air_t += 1.0 / 120.0
			max_h = maxf(max_h, s.position.y - world.terrain.height(s.position.x, s.position.z))
		elif was_air:
			break
	check("charged jump leaves the ground", was_air, "max clearance %.2f m" % max_h)
	check("jump airtime is reasonable", air_t > 0.4 and air_t < 2.5, "%.2f s on a %.0f deg slope" % [air_t, spot["slope"]])
	check("normal jump lands cleanly", not s.is_crashed)
	# 7. air spin produces rotation
	s = _settle_on(spot["pos"], spot["yaw"])
	_run(s, 1.5, {})
	_run(s, 0.6, {"jump": 1.0})
	_run(s, 0.02, {})
	_run(s, 0.5, {"spin_right": 1.0})
	# (Normal difficulty: in-air input only adds some rotation; most of a spin comes from the wind-up)
	check("spin input rotates in air", absf(s.air_rotation) > deg_to_rad(45.0) or not s.airborne, "%.0f deg" % rad_to_deg(s.air_rotation))
	# 8. flat terrain: speed decays
	var flat := _find_slope(0.0, 3.0)
	if not flat.is_empty():
		s = _settle_on(flat["pos"], flat["yaw"])
		var f := Skier.forward_flat_s(flat["yaw"])
		s.vel = f * 12.0
		_run(s, 6.0, {})
		check("flat terrain slows down", s.vel.length() < 9.0, "12 -> %.1f m/s in 6 s" % s.vel.length())
	# 9. cliff drop -> hard landing crash
	s = _settle_on(spot["pos"], spot["yaw"])
	s.position.y += 30.0
	s.airborne = true
	s.vel = Vector3.ZERO
	_run(s, 4.0, {})
	check("30 m flat drop crashes", s.is_crashed)
	# 10. respawn returns to safety
	s.respawn()
	check("respawn clears crash", not s.is_crashed)
	# 11. tree collision at speed crashes
	var tree_i := -1
	var obs := world.obstacles
	for i in obs.count():
		if obs.kinds[i] == Obstacles.Kind.TREE and obs.xs[i] > 300.0 and obs.zs[i] > 300.0 and obs.xs[i] < 5800.0 and obs.zs[i] < 5800.0 \
				and world.terrain.slope_deg(obs.xs[i], obs.zs[i]) < 15.0 and obs.clearance(obs.xs[i] + 8.0, obs.zs[i], 7.0) > 2.0:
			tree_i = i
			break
	if tree_i >= 0:
		var tp := Vector3(obs.xs[tree_i], 0, obs.zs[tree_i])
		var start := tp + Vector3(12, 0, 0)
		s = _settle_on(start, Skier.yaw_of(Vector3(-1, 0, 0)))
		s.vel = Vector3(-18, 0, 0)
		_run(s, 1.5, {})
		check("hitting a tree at speed crashes", s.is_crashed, "reason via signal")
	_body_physics(spot)
	_park_kickers()
	_skis_attached(spot)
	_jibs()
	_on_foot(spot)
	world.body.set_process(true)
	s.set_physics_process(true)
	await _lift_ride()
	await _ghost_race()


# ------------------------------------------------------------------ smoke
func _smoke() -> void:
	var seconds := float(Game.test_args.get("seconds", "20"))
	world.spawn_at_drop(Game.test_args.get("spot", "Resort Top"))
	var s := world.skier
	var frames := 0
	var worst := 0.0
	var total := 0.0
	var t_end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var phase := 0.0
	while Time.get_ticks_msec() < t_end:
		phase += get_process_delta_time()
		var steer := sin(phase * 0.8)
		s.scripted_input = {"steer_right": maxf(steer, 0.0), "steer_left": maxf(-steer, 0.0), "tuck": 1.0 if fmod(phase, 6.0) < 3.0 else 0.0}
		if s.is_crashed and s.crash_time > 1.5:
			s.respawn()
		await get_tree().process_frame
		var d := get_process_delta_time()
		frames += 1
		total += d
		worst = maxf(worst, d)
	print("[TEST] smoke frames=%d avg_ms=%.1f worst_ms=%.1f speed=%.1f km/h draw_calls=%d prims=%d patches=%d" % [
		frames, total / maxf(frames, 1) * 1000.0, worst * 1000.0, s.speed_kmh(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		world.renderer.patch_count()])
	check("smoke run produced frames", frames > 10)
	await _snap("smoke_end")


# ------------------------------------------------------------------ gameplay simulation
func _autopilot_step(s: Skier, target: Vector2, vmax := 32.0) -> Dictionary:
	var p := Vector2(s.position.x, s.position.z)
	var to := (target - p)
	var want := Skier.yaw_of(Vector3(to.x, 0, to.y))
	var cur := Skier.yaw_of(Vector3(s.vel.x, 0, s.vel.z)) if s.speed > 2.0 else s.heading
	var err := wrapf(want - cur, -PI, PI)        # + = target is to the left
	var inp := {}
	var steer := clampf(-err * 2.2, -1.0, 1.0)
	if steer > 0.0:
		inp["steer_right"] = steer
	else:
		inp["steer_left"] = -steer
	if absf(err) < 0.25 and s.speed < 28.0:
		inp["tuck"] = 1.0
	if s.speed > vmax or (absf(err) > 0.9 and s.speed > 14.0):
		inp["brake"] = 1.0
	if absf(err) > 1.2 and s.speed > 18.0:
		inp["carve"] = 1.0
	return inp


func _gameplay() -> void:
	var s := world.skier
	world.body.set_process(false)
	s.set_physics_process(false)
	var dt := 1.0 / 120.0
	# --- carve radius vs speed on a groomed piste
	var spot := _find_slope(14.0, 22.0, true)
	if spot.is_empty():
		spot = _find_slope(14.0, 22.0)
	for v0 in [8.0, 15.0, 22.0, 30.0]:
		s.teleport(spot["pos"], spot["yaw"], v0)
		s.scripted_input = {}
		for i in 30:
			s.step(dt)
		var y0 := Skier.yaw_of(s.vel)
		var t := 0.0
		var sp_sum := 0.0
		s.scripted_input = {"steer_left": 1.0}
		var air_n := 0
		var nc_n := 0
		var yr := 0.0
		var ed := 0.0
		var sk := 0.0
		while t < 1.5 and not s.is_crashed:
			s.step(dt)
			t += dt
			sp_sum += s.speed
			air_n += 1 if s.airborne else 0
			nc_n += 1 if not s.contact else 0
			yr += absf(s.yaw_rate)
			ed += absf(s.edge)
			sk += s.skid
		var nn := maxf(t / dt, 1.0)
		print("[TEST]   debug v0=%.0f: airborne %.0f%%, no-contact %.0f%%, avg yaw_rate %.2f, avg edge %.0f deg, avg skid %.2f, lat_acc %.1f" % [
			v0, 100.0 * air_n / nn, 100.0 * nc_n / nn, yr / nn, rad_to_deg(ed / nn), sk / nn, s.lat_acc])
		var turned := absf(wrapf(Skier.yaw_of(s.vel) - y0, -PI, PI))
		var avg := sp_sum / maxf(t / dt, 1.0)
		var radius := avg * t / maxf(turned, 0.001)
		print("[TEST] carve %4.0f km/h: avg %4.0f km/h, turned %3.0f deg in 1.5 s, radius %5.1f m, speed loss %4.1f km/h" % [
			v0 * 3.6, avg * 3.6, rad_to_deg(turned), radius, (v0 - s.speed) * 3.6])
	# --- straight tuck top speed on the steepest smooth slope we can find
	var steep := _find_slope(28.0, 34.0)
	if not steep.is_empty():
		s.teleport(steep["pos"], steep["yaw"])
		s.scripted_input = {"tuck": 1.0}
		var top := 0.0
		for i in int(8.0 / dt):
			if s.is_crashed:
				break
			s.step(dt)
			top = maxf(top, s.speed)
		print("[TEST] tuck on %.0f deg slope for 8 s: top speed %.0f km/h" % [steep["slope"], top * 3.6])
	# --- trick evaluation unit tests
	var base := {"air_time": 1.4, "grab_l": 0.0, "grab_r": 0.0, "misalign": 5.0, "impact": 4.0, "switch": false}
	var t360 := TrickSystem.evaluate(base.merged({"rotation": deg_to_rad(352.0)}, true))
	check("360 recognised", t360.get("spin", 0) == 360, str(t360.get("name", "")))
	var t180 := TrickSystem.evaluate(base.merged({"rotation": -deg_to_rad(170.0), "switch": true}, true))
	check("left 180 recognised", t180.get("spin", 0) == 180 and str(t180["name"]).begins_with("Left"), str(t180.get("name", "")))
	var tg := TrickSystem.evaluate(base.merged({"rotation": 0.2, "grab_l": 0.8}, true))
	check("grab recognised, no fake spin", tg.get("spin", -1) == 0 and tg.get("grabs", 0) == 1, str(tg.get("name", "")))
	var tn := TrickSystem.evaluate(base.merged({"rotation": 0.3, "air_time": 0.6}, true))
	check("small hop scores nothing", tn.is_empty())
	var tbf := TrickSystem.evaluate(base.merged({"rotation": 0.1, "flip": -TAU * 0.97}, true))
	check("backflip recognised", str(tbf.get("name", "")) == "Backflip", str(tbf.get("name", "")))
	var tdf := TrickSystem.evaluate(base.merged({"rotation": deg_to_rad(358.0), "flip": TAU * 2.02}, true))
	check("double frontflip 360 recognised", str(tdf.get("name", "")).begins_with("Double Frontflip"), str(tdf.get("name", "")))
	var tck := TrickSystem.evaluate(base.merged({"rotation": deg_to_rad(722.0), "flip": 0.1, "pitch_peak": deg_to_rad(80.0)}, true))
	if TrickSystem.CORKS:
		check("cork recognised", str(tck.get("name", "")).contains("Cork 720"), str(tck.get("name", "")))
	else:
		check("off-axis spins score as flat spins (corks come later)", str(tck.get("name", "")).ends_with("720") and not str(tck.get("name", "")).contains("Cork"), str(tck.get("name", "")))
	var ttip := TrickSystem.evaluate(base.merged({"rotation": 0.0, "grab_l": 0.8, "grab_kind_l": "tip"}, true))
	check("tip grab recognised", str(ttip.get("name", "")) == "Left Tip Grab", str(ttip.get("name", "")))
	var tsk := TrickSystem.evaluate(base.merged({"rotation": deg_to_rad(360.0), "misalign": 40.0}, true))
	check("sketchy landing scores less", int(tsk.get("points", 0)) < int(t360.get("points", 0)))
	# --- real 360 off the park's medium kicker, the way a player does it: hold Left on the run-in
	# (shoulders coil left), pop at the lip, Right in the air, let go to spot the landing
	var ok360 := false
	var kk: Dictionary = {}
	for k in world.terrain.layout["parks"][0]["kickers"]:
		if k["size"] == "M":
			kk = k
	var kd := Vector3(kk["dir"][0], 0, kk["dir"][1])
	var lip := Vector3(kk["lip"][0], 0, kk["lip"][1])
	s.difficulty = 0
	s.teleport(Vector3(kk["origin"][0], 0, kk["origin"][1]) - kd * 12.0, Skier.yaw_of(kd), float(kk["approach_speed"]) - 1.0)
	var box := {}
	var cb := func(info): box["info"] = info
	s.landed.connect(cb)
	var t2 := 0.0
	while t2 < 6.0 and not box.has("info"):
		var to_lip := (lip - s.position).dot(kd)
		if not s.airborne:
			s.scripted_input = {"lean_left": 1.0, "jump": 1.0} if to_lip > 0.4 else {}
		elif absf(s.air_rotation) + s.spin_vel * s.spin_vel / (2.0 * float(s.diff()["spin_damp"])) < deg_to_rad(350.0):
			s.scripted_input = {"lean_right": 1.0}
		else:
			s.scripted_input = {}
		s.step(dt)
		s.time += dt
		t2 += dt
	s.landed.disconnect(cb)
	var landed_info: Dictionary = box.get("info", {})
	if not landed_info.is_empty():
		var tr := TrickSystem.evaluate(landed_info)
		print("[TEST]   kicker 360: air %.2f s, rotation %.0f deg, misalign %.0f, crash '%s' -> %s" % [landed_info["air_time"],
			rad_to_deg(landed_info["rotation"]), landed_info["misalign"], landed_info["crash"], tr.get("name", "-")])
		ok360 = landed_info["crash"] == "" and tr.get("spin", 0) >= 360 and landed_info["rotation"] > 0.0
	check("a real right 360 off a kicker (wind up Left, spin Right) can be landed", ok360)
	# --- autopilot through every race: straight at each gate, or along the routed line;
	# the race counts as finishable if either strategy gets through every gate
	for c in world.terrain.layout.get("challenges", []):
		if c["type"] != "race":
			continue
		var best := {}
		for mode in ["gates", "line", "careful", "slow"]:
			var r := _race_attempt(s, c, mode, dt)
			if best.is_empty() or int(r["idx"]) > int(best["idx"]) or (r["idx"] == best["idx"] and float(r["t"]) < float(best["t"])):
				best = r
			if int(r["idx"]) >= c["checkpoints"].size():
				break
		var cps: Array = c["checkpoints"]
		var m: Array = c["medals"]
		print("[TEST] race %-18s autopilot (%s) %s  gates %d/%d  crashes %d %s  (gold %s silver %s bronze %s)" % [c["name"], best["mode"],
			UITheme.format_time(best["t"]), best["idx"], cps.size(), best["crashes"], str(best["reasons"]), UITheme.format_time(m[0]), UITheme.format_time(m[1]), UITheme.format_time(m[2])])
		if int(best["idx"]) < cps.size():
			var gate_p := Vector2(cps[best["idx"]][0], cps[best["idx"]][1])
			var sp: Vector3 = best["pos"]
			print("[TEST]     stuck near (%.0f, %.0f) h=%.0f slope=%.0f, next gate (%.0f, %.0f) h=%.0f dist %.0f" % [sp.x, sp.z, sp.y,
				world.terrain.slope_deg(sp.x, sp.z), gate_p.x, gate_p.y, world.terrain.height(gate_p.x, gate_p.y), Vector2(sp.x, sp.z).distance_to(gate_p)])
		check("race %s finishable" % c["name"], int(best["idx"]) >= cps.size())
	world.body.set_process(true)
	s.set_physics_process(true)


func _race_attempt(s: Skier, c: Dictionary, mode: String, dt: float) -> Dictionary:
	s.teleport(Vector3(c["start"][0], 0, c["start"][1]), float(c["yaw"]))
	var cps: Array = c["checkpoints"]
	var path: Array = c.get("path", cps)
	var pi := 0
	var idx := 0
	var t := 0.0
	var crashes := 0
	var reasons := {}
	var rcb := func(r, _v): reasons[r] = int(reasons.get(r, 0)) + 1
	s.crashed.connect(rcb)
	var stalled := 0.0
	var braking := false
	while idx < cps.size() and t < 600.0:
		var target := Vector2(cps[idx][0], cps[idx][1])
		var aim_at := target
		if mode != "gates":
			var pp := Vector2(s.position.x, s.position.z)
			var near_i := pi
			for k in range(maxi(pi - 3, 0), mini(pi + 12, path.size())):
				if pp.distance_to(Vector2(path[k][0], path[k][1])) < pp.distance_to(Vector2(path[near_i][0], path[near_i][1])):
					near_i = k
			pi = near_i
			var aim := pi
			while aim < path.size() - 1 and pp.distance_to(Vector2(path[aim][0], path[aim][1])) < (22.0 if mode == "line" else 14.0):
				aim += 1
			aim_at = Vector2(path[aim][0], path[aim][1])
			if pp.distance_to(target) < pp.distance_to(aim_at):
				aim_at = target
		var inp := _autopilot_step(s, aim_at)
		if mode == "careful" or mode == "slow":
			# speed checks on steep ground (or everywhere when slow), with hysteresis so it never stops dead
			var cap := lerpf(30.0, 15.0, clampf((world.terrain.slope_deg(s.position.x, s.position.z) - 30.0) / 12.0, 0.0, 1.0))
			if mode == "slow":
				cap = 12.5
			braking = s.speed > cap or (braking and s.speed > cap - 4.0)
			if braking:
				inp["brake"] = 1.0
				inp.erase("tuck")
		if s.speed < 0.3 and t > 5.0:
			inp["tuck"] = 1.0
		# pinned against a tree or stalled for a while: respawn like a player would (R)
		stalled = stalled + dt if s.speed < 0.6 and t > 5.0 else 0.0
		if stalled > 4.0:
			stalled = 0.0
			reasons["stuck (respawned)"] = int(reasons.get("stuck (respawned)", 0)) + 1
			s.respawn()
		s.scripted_input = inp
		s.step(dt)
		t += dt
		if s.is_crashed:
			crashes += 1
			if Game.test_args.has("race_debug") and crashes <= 3:
				print("[DBG] %s/%s crash %d at (%.0f, %.0f, %.0f) %s speed %.1f" % [c["name"], mode, crashes, s.position.x, s.position.z, s.position.y, str(reasons), s.speed])
				var ob := world.obstacles
				for oi in ob.query(s.position.x, s.position.z, 4.0):
					print("[DBG] crash at (%.0f, %.0f) near obstacle kind %d at (%.1f, %.1f) r %.1f" % [s.position.x, s.position.z, ob.kinds[oi], ob.xs[oi], ob.zs[oi], ob.radii[oi]])
			s.crash_time = 3.0
			s.respawn()
		if Vector2(s.position.x, s.position.z).distance_to(target) < 13.0:
			idx += 1
	s.crashed.disconnect(rcb)
	return {"mode": mode, "idx": idx, "t": t, "crashes": crashes, "reasons": reasons, "pos": s.position}


# ------------------------------------------------------------------ turn animation frames
func _turns() -> void:
	var spot := _find_slope(16.0, 24.0)
	var s := world.skier
	world.spawn(spot["pos"], spot["yaw"])
	s.teleport(spot["pos"], spot["yaw"], 12.0)
	var plan := [{"tuck": 1.0}, {"steer_right": 1.0}, {"steer_right": 1.0}, {"steer_left": 1.0}, {"steer_left": 1.0},
		{"steer_right": 1.0, "carve": 1.0}, {"steer_right": 1.0, "carve": 1.0}, {"steer_left": 1.0, "carve": 1.0}]
	var idx := 0
	for seg in plan:
		s.scripted_input = seg
		await _frames(int(Game.test_args.get("seg_frames", "6")))
		await _snap("turn_%02d" % idx)
		idx += 1


# ------------------------------------------------------------------ new mechanics, visually
func _free_cam(pos: Vector3, look: Vector3) -> void:
	var cam := world.camera
	cam.set_process(false)
	pos.y = maxf(pos.y, world.terrain.height(pos.x, pos.z) + 1.0)
	cam.global_transform = Transform3D(Basis.IDENTITY, pos).looking_at(look, Vector3.UP)
	world.renderer.update_lod(pos, true)


func _showcase() -> void:
	var s := world.skier
	var cam := world.camera
	var r = world.resort
	var lf: Dictionary = r.lifts[int(Game.test_args.get("lift", "0"))]
	var b: Vector3 = lf["bottom"]
	var dir: Vector3 = lf["dir"]
	var side: Vector3 = lf["side"]
	var lp: Vector3 = r.load_point(lf)
	world.spawn(lp - dir * 3.0, Skier.yaw_of(dir))
	await _frames(20)
	# the bottom terminal: bull wheel, loading mat, sign, chairs arriving
	_free_cam(b - dir * 16.0 + side * 16.0 + Vector3.UP * 5.0, b + dir * 14.0 + Vector3.UP * 2.0)
	await _frames(30)
	await _snap("lift_bottom")
	# the line from the side: chair spacing, riders going up, empty chairs coming down
	var mid: Vector3 = (lf["towers"][2] as Vector3)
	_free_cam(mid + side * 70.0 - dir * 30.0 + Vector3.UP * 4.0, mid + dir * 30.0)
	await _frames(20)
	await _snap("lift_line")
	# riding a chair
	cam.set_process(true)
	Engine.time_scale = 3.0
	r.board(lf, s)
	var t := 0.0
	while t < 15.0 and s.mode != Skier.Mode.LIFT:
		await get_tree().process_frame
		t += get_process_delta_time()
	await _frames(150)
	Engine.time_scale = 1.0
	await _frames(10)
	await _snap("lift_ride")
	_free_cam(s.position + side * 4.0 - dir * 1.0 + Vector3.UP * 0.5, s.position + Vector3.UP * 0.2)
	await _frames(3)
	await _snap("lift_seated")
	cam.set_process(true)
	r.skip_ride()
	await _frames(20)
	await _snap("lift_unload")
	# on foot
	var spot := _find_slope(8.0, 16.0)
	world.spawn(spot["pos"], spot["yaw"])
	await _frames(10)
	s.toggle_skis()
	s.scripted_input = {"tuck": 1.0}
	await _frames(70)
	await _snap("walk_behind")
	var f := Skier.forward_flat_s(s.heading)
	var rt := f.cross(Vector3.UP)
	s.scripted_input = {"tuck": 1.0}
	for k in 3:
		await _frames(9)
		f = Skier.forward_flat_s(s.heading)
		rt = f.cross(Vector3.UP)
		_free_cam(s.position + rt * 3.2 + f * 0.6 + Vector3.UP * 1.1, s.position + Vector3.UP * 0.9)
		await _snap("walk_side_%d" % k)
	cam.set_process(true)
	s.scripted_input = null
	s.toggle_skis()
	# hockey stop
	var hs := _find_slope(16.0, 24.0, true)
	if hs.is_empty():
		hs = _find_slope(16.0, 24.0)
	world.spawn(hs["pos"], hs["yaw"])
	s.teleport(hs["pos"], hs["yaw"], 12.0)
	s.scripted_input = {}
	await _frames(60)
	s.scripted_input = {"brake": 1.0}
	await _frames(int(Game.test_args.get("stop_frames", "26")))
	await _snap("hockey_stop_behind")
	var hv := Vector3(s.vel.x, 0, s.vel.z).normalized()
	_free_cam(s.position + hv * 6.0 + hv.cross(Vector3.UP) * 2.5 + Vector3.UP * 1.0, s.position + Vector3.UP * 0.8)
	await _snap("hockey_stop_front")
	cam.set_process(true)
	await _frames(90)
	await _snap("hockey_stop_end")
	s.scripted_input = null
	# HUD with the minimap while skiing a piste
	var hud = get_parent().get("hud")
	if hud:
		hud.visible = true
	world.spawn_at_drop("Resort Top")
	Game.waypoint = Vector2(world.terrain.drop_zone("Village Base")["x"], world.terrain.drop_zone("Village Base")["z"])
	s.scripted_input = {"tuck": 1.0}
	await _frames(150)
	await _snap("hud_minimap")
	s.scripted_input = null


func _showcase2() -> void:
	var s := world.skier
	var cam := world.camera
	var r = world.resort
	var lf: Dictionary = r.lifts[int(Game.test_args.get("lift", "0"))]
	var dir: Vector3 = lf["dir"]
	var side: Vector3 = lf["side"]
	var lp: Vector3 = r.load_point(lf)
	world.spawn(lp - dir * 3.0, Skier.yaw_of(dir))
	await _frames(10)
	r.board(lf, s)
	_free_cam(lp + side * 9.0 + dir * 4.0 + Vector3.UP * 2.2, lp + Vector3.UP * 1.0 - dir * 2.0)
	while r.ride_info().get("phase", "") == "wait" and float(r.ride_info().get("wait", 0.0)) > 1.4:
		await get_tree().process_frame
	await _snap("lift_load")
	while s.mode != Skier.Mode.LIFT:
		await get_tree().process_frame
	await _frames(2)
	await _snap("lift_pickup")
	cam.set_process(true)
	await _frames(40)
	await _snap("lift_ride2")
	r.skip_ride()
	# on foot
	var spot := _find_slope(6.0, 14.0)
	world.spawn(spot["pos"], spot["yaw"])
	await _frames(5)
	s.toggle_skis()
	s.scripted_input = {"tuck": 1.0}
	await _frames(40)
	for k in 3:
		await _frames(5)
		var f := Skier.forward_flat_s(s.heading)
		var rt := f.cross(Vector3.UP)
		_free_cam(s.position + rt * 3.4 + f * 0.4 + Vector3.UP * 1.0, s.position + Vector3.UP * 0.9)
		await _snap("walk2_side_%d" % k)
	s.scripted_input = null
	s.toggle_skis()
	# hockey stop sequence from a fixed camera downhill of the skier
	var hs := _find_slope(16.0, 24.0, true)
	if hs.is_empty():
		hs = _find_slope(16.0, 24.0)
	world.spawn(hs["pos"], hs["yaw"])
	s.teleport(hs["pos"], hs["yaw"], 13.0)
	s.set_physics_process(false)
	s.scripted_input = {}
	for i in 120:
		s.step(1.0 / 120.0)
		s.time += 1.0 / 120.0
	var hv := Vector3(s.vel.x, 0, s.vel.z).normalized()
	var cpos := s.position + hv * 14.0 + hv.cross(Vector3.UP) * 5.0 + Vector3.UP * 1.6
	s.scripted_input = {"brake": 1.0}
	for k in 6:
		for i in 18:
			s.step(1.0 / 120.0)
			s.time += 1.0 / 120.0
		s._cur_xform = s._compose_xform()
		s._prev_xform = s._cur_xform
		_free_cam(cpos, s.position + Vector3.UP * 0.8)
		await _frames(2)
		await _snap("stop_seq_%d" % k)
	s.set_physics_process(true)
	s.scripted_input = null


## Stepped simulation with a fixed side camera: wind-up, backflip, tip grab.
func _showcase3() -> void:
	var s := world.skier
	var spot := _find_slope(18.0, 26.0, true)
	if spot.is_empty():
		spot = _find_slope(18.0, 26.0)
	world.spawn(spot["pos"], spot["yaw"])
	s.set_physics_process(false)
	s.difficulty = 0
	var seq := [[{}, 150, ""], [{"jump": 1.0, "lean_back": 1.0, "lean_right": 0.0}, 70, "load"],
		[{"jump": 1.0, "lean_back": 1.0}, 2, ""], [{"lean_back": 1.0}, 22, "flip_a"], [{"lean_back": 1.0}, 22, "flip_b"],
		[{"lean_back": 1.0}, 22, "flip_c"], [{}, 22, "flip_d"], [{}, 60, ""], [{"jump": 1.0, "lean_right": 1.0}, 80, "windup"],
		[{"jump": 1.0, "lean_right": 1.0}, 2, ""], [{"grab_left": 1.0, "lean_forward": 1.0}, 40, "tipgrab"]]
	var cpos := Vector3.INF
	for st in seq:
		s.scripted_input = st[0]
		for i in int(st[1]):
			s.step(1.0 / 120.0)
			s.time += 1.0 / 120.0
		s._cur_xform = s._compose_xform()
		s._prev_xform = s._cur_xform
		if st[2] != "":
			var f := Skier.forward_flat_s(Skier.yaw_of(Vector3(s.vel.x, 0, s.vel.z)) if s.speed > 1.0 else s.heading)
			cpos = s.position + f.cross(Vector3.UP) * 7.0 + f * 1.0 + Vector3.UP * 1.2
			_free_cam(cpos, s.position + Vector3.UP * 0.9)
			await _frames(3)
			await _snap("phys_" + st[2])
	s.scripted_input = null
	s.set_physics_process(true)


func _showcase4() -> void:
	var s := world.skier
	var park = world.park
	var r0: Dictionary = park.rails[0]
	var a: Vector3 = r0["a"]
	var dir: Vector3 = (r0["b"] - a).normalized()
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	var side := flat.cross(Vector3.UP)
	world.spawn(a - flat * 30.0, Skier.yaw_of(flat))
	await _frames(10)
	var mid := park.rails[2]["a"] as Vector3
	_free_cam(a - flat * 25.0 + side * 22.0 + Vector3.UP * 12.0, mid)
	await _frames(20)
	await _snap("park_overview")
	s.set_physics_process(false)
	s.difficulty = 0
	var shots := [[park.rails[0], PI * 0.5, "park_boxslide"], [park.rails[1], 0.0, "park_rail5050"]]
	for sh in shots:
		var r: Dictionary = sh[0]
		var ra: Vector3 = r["a"]
		var rd: Vector3 = (r["b"] - ra).normalized()
		var rf := Vector3(rd.x, 0, rd.z).normalized()
		s.teleport(ra - rf * 2.0, Skier.yaw_of(rf), 6.0)
		s.position = ra + rd * 0.8 + Vector3.UP * 0.2
		s.airborne = true
		s.vel = rd * 6.0 + Vector3.DOWN
		s.heading = Skier.yaw_of(rf) + float(sh[1])
		s.scripted_input = {"lean_back": 1.0} if sh[2] == "park_rail5050" else {}
		for i in 50:
			s.step(1.0 / 120.0)
			s.time += 1.0 / 120.0
		s._cur_xform = s._compose_xform()
		s._prev_xform = s._cur_xform
		_free_cam(s.position + rf.cross(Vector3.UP) * 3.5 + rf * 2.0 + Vector3.UP * 1.0, s.position + Vector3.UP * 0.7)
		await _frames(3)
		await _snap(sh[2])
	s.scripted_input = null
	s.set_physics_process(true)


## The live grab animation frame by frame: hold the key in the air, snap every 0.1 s, then let go.
func _grab_anim() -> void:
	var s := world.skier
	var body = world.body
	var st: Dictionary = world.park.park_start(0)
	world.spawn(st["pos"], st["yaw"])
	await _frames(10)
	s.set_physics_process(false)
	body.skeleton_view = Game.test_args.get("skeleton", "0") == "1"
	body.set_process(false)            # the pose only advances with the simulated time below
	var key: String = Game.test_args.get("key", "grab_left")
	s.teleport(st["pos"], st["yaw"])
	s.position.y += 30.0
	s.airborne = true
	s.vel = Vector3.ZERO
	var fz: Vector3 = Vector3(-sin(s.heading), 0, -cos(s.heading))
	var view: String = Game.test_args.get("view", "front")
	var rt := fz.cross(Vector3.UP)
	var cdir: Vector3 = {"front": -fz * 2.4 + rt * 0.5, "side": rt * 2.4, "front3q": (-fz + rt * 0.8).normalized() * 2.4}[view]
	var shot := 0
	for i in 160:
		var keys := {}
		if i < 108:
			for k in key.split(","):
				keys[k] = 1.0
		s.scripted_input = keys
		s.step(1.0 / 120.0)
		s.time += 1.0 / 120.0
		s._cur_xform = s._compose_xform()
		s._prev_xform = s._cur_xform
		body._compute_pose(1.0 / 120.0)
		body._cloth_step(1.0 / 120.0)
		if i % 12 == 0:
			body._apply_parts()
			body._cloth_apply()
			var c: Vector3 = body.joints["pelvis"] + Vector3.UP * 0.15
			_free_cam(c + cdir + Vector3.UP * 0.3, c)
			await _frames(2)
			await _snap("anim_%02d" % shot)
			shot += 1
	s.set_physics_process(true)


## Preview renders of each grab pose in the air (two angles each).
func _grab_shots() -> void:
	var s := world.skier
	var body = world.body
	var st: Dictionary = world.park.park_start(0)
	world.spawn(st["pos"], st["yaw"])
	await _frames(10)
	s.set_physics_process(false)
	var only: String = Game.test_args.get("only", "")
	body.skeleton_view = Game.test_args.get("skeleton", "0") == "1"
	for gname in body.GRAB_POSES:
		if only != "" and gname != only:
			continue
		s.teleport(st["pos"], st["yaw"])
		s.position.y += 2.5
		s.airborne = true
		s.vel = Vector3.ZERO
		s._cur_xform = s._compose_xform()
		s._prev_xform = s._cur_xform
		body.preview_grab = gname
		body._grab_bend = 0.0
		body.grab_gap = {}
		body.arm_clear = {}
		for i in 60:
			body._compute_pose(0.03)
		var kl: float = rad_to_deg((body.joints["hip_l"] - body.joints["knee_l"]).angle_to(body.joints["ankle_l"] - body.joints["knee_l"]))
		var kr: float = rad_to_deg((body.joints["hip_r"] - body.joints["knee_r"]).angle_to(body.joints["ankle_r"] - body.joints["knee_r"]))
		print("[TEST] grab %-12s hand-to-ski gap %s  arm-to-ski clearance %s  knee angles %.0f / %.0f" % [gname,
			str(body.grab_gap), str(body.arm_clear), kl, kr])
		var elb := {}
		for sd in ["l", "r"]:
			var j: Dictionary = body.joints
			var ang := rad_to_deg((j["shoulder_" + sd] - j["elbow_" + sd]).angle_to(j["hand_" + sd] - j["elbow_" + sd]))
			var out_dir: Vector3 = (j["elbow_" + sd] - (j["shoulder_" + sd] + j["hand_" + sd]) * 0.5)
			var tbx: Basis = body.torso_basis
			elb[sd] = "%.0f deg (straight = 180), elbow points %s" % [ang, str((tbx.inverse() * out_dir.normalized()).snapped(Vector3(0.01, 0.01, 0.01)))]
		print("[TEST] grab %-12s elbows: L %s | R %s" % [gname, elb["l"], elb["r"]])
		print("[TEST] grab %-12s grip along the ski: %s" % [gname, str(body._solved.get(gname, {}).get("along", {}))])
		print("[TEST] grab %-12s solved: %s" % [gname, str(body._solved.get(gname, {}))])
		# joints in the skier's root frame (x his right, y up, z back), m
		var hb2: Basis = s.visual_xform().basis.orthonormalized()     # the skier's root (hips before the twist)
		var loc := {}
		for jn in ["shoulder_r", "elbow_r", "hand_r", "shoulder_l", "elbow_l", "hand_l", "knee_r", "knee_l", "ankle_r", "ankle_l"]:
			loc[jn] = (hb2.inverse() * (body.joints[jn] - body.joints["pelvis"])).snapped(Vector3(0.01, 0.01, 0.01))
		print("[TEST] grab %-12s joints: %s" % [gname, str(loc)])
		var ups := []
		for sx: Transform3D in [body.ski_l, body.ski_r]:
			ups.append("%.0f" % rad_to_deg(asin(clampf(-sx.basis.z.normalized().y, -1.0, 1.0))))
		print("[TEST] grab %-12s ski tip-up angle L / R: %s deg" % [gname, " / ".join(ups)])
		body._apply_parts()
		var fz: Vector3 = -body.pelvis_basis.z                # the way his hips face
		var fwd := Vector3(fz.x, 0, fz.z).normalized()
		var rt := fwd.cross(Vector3.UP)
		var c: Vector3 = body.joints["pelvis"]
		var tag := String(gname).replace(" ", "_")
		var mid_ank: Vector3 = (body.joints["ankle_l"] + body.joints["ankle_r"]) * 0.5 - body.joints["pelvis"]
		var up_spine: Vector3 = (body.joints["chest"] - body.joints["pelvis"]).normalized()
		var sv: Dictionary = body._solved.get(gname, {})
		print("[TEST] grab %-12s skis sideways from the pelvis %.2f m (+ = his right), %.2f m below it; chest leans %.0f deg forward, %.0f deg to his %s; solved pitch %.0f deg" % [
			gname, mid_ank.dot(rt), -mid_ank.y, rad_to_deg(asin(clampf(up_spine.dot(fwd), -1, 1))), absf(rad_to_deg(asin(clampf(up_spine.dot(rt), -1, 1)))),
			"right" if up_spine.dot(rt) > 0.0 else "left", float(sv.get("pitch", 0.0))])
		c += Vector3.UP * 0.15
		var views := [["front", fwd * 2.5 + Vector3.UP * 0.3], ["side", rt * 2.5 + Vector3.UP * 0.2],
				["back", -fwd * 2.4 + Vector3.UP * 0.4], ["above", -rt * 1.6 + fwd * 1.0 + Vector3.UP * 1.9]]
		if Game.test_args.get("angles", "4") == "8":
			views = []
			for k in 8:
				var a := TAU * k / 8.0
				views.append(["view%d" % k, (fwd * cos(a) + rt * sin(a)) * 2.3 + Vector3.UP * (0.25 if k % 2 == 0 else 0.9)])
			# like the reference photo (mirrored): low in front, a little to his left (the grab side),
			# looking up at him
			var az := deg_to_rad(float(Game.test_args.get("photo_az", "60")))     # from his front toward his left
			var el := deg_to_rad(float(Game.test_args.get("photo_el", "12")))     # camera below him
			var pd := (fwd * cos(az) - rt * sin(az)) * cos(el) + Vector3.DOWN * sin(el)
			views.append(["photo", pd * float(Game.test_args.get("photo_dist", "2.0")) + Vector3.UP * 0.25])
		for v in views:
			_free_cam(c + v[1], c)
			await _frames(3)
			await _snap("grab_%s_%s" % [tag, v[0]])
	body.preview_grab = ""
	s.set_physics_process(true)


## Park staging area, the skier's outfit, and a backflip off the large kicker.
func _park_shots() -> void:
	var s := world.skier
	var park = world.park
	var pi := int(Game.test_args.get("park", "0"))
	var st: Dictionary = park.park_start(pi)
	var pk: Dictionary = park.parks[pi]
	var d := Vector3(pk["dir"][0], 0, pk["dir"][1])
	var side := d.cross(Vector3.UP)
	world.spawn(st["pos"], st["yaw"])
	await _frames(20)
	var p0: Vector3 = s.position
	_free_cam(p0 - d * 14.0 + Vector3.UP * 9.0, p0 + d * 90.0)
	await _frames(20)
	await _snap("park_top")
	# the jump line: from above the first jump looking down the line, and from the side
	var o0 := Vector3(pk["origin"][0], 0, pk["origin"][1])
	var at := func(sd: float, up_m: float) -> Vector3:
		var q := o0 + d * sd
		return Vector3(q.x, world.terrain.height(q.x, q.z) + up_m, q.z)
	_free_cam(at.call(20.0, 14.0) - side * 6.0, at.call(170.0, 0.0))
	await _frames(20)
	await _snap("park_line")
	_free_cam(at.call(230.0, 30.0) + side * 85.0, at.call(230.0, 0.0))
	await _frames(20)
	await _snap("park_line_side")
	# the jib lane: from above its start looking down it, and a low close look at a row of rails
	var ju := float(pk["lines"].get("jib", 34.0))
	_free_cam(at.call(20.0, 9.0) + side * ju, at.call(150.0, 0.0) + side * ju)
	await _frames(20)
	await _snap("park_jib")
	_free_cam(at.call(40.0, 3.0) + side * (ju - 12.0), at.call(75.0, 0.5) + side * ju)
	await _frames(20)
	await _snap("park_jib_row")
	for pp in pk.get("pipes", []):
		var po := Vector3(pp["origin"][0], 0, pp["origin"][1])
		var pd := Vector3(pp["dir"][0], 0, pp["dir"][1]).normalized()
		var pat := func(t: float, uu: float, up_m: float) -> Vector3:
			var q := po + pd * t + side * uu
			return Vector3(q.x, world.terrain.base_height(q.x, q.z) + up_m, q.z)
		_free_cam(pat.call(float(pp["length"]) + 20.0, 0.0, 9.0), pat.call(float(pp["length"]) * 0.35, 0.0, 2.0))
		await _frames(20)
		await _snap("park_pipe")
		_free_cam(pat.call(60.0, -6.0, 1.6), pat.call(75.0, 14.0, 4.0))
		await _frames(20)
		await _snap("park_pipe_wall")
		_free_cam(pat.call(float(pp["length"]) * 0.5, 45.0, 22.0), pat.call(float(pp["length"]) * 0.5, 0.0, 0.0))
		await _frames(20)
		await _snap("park_pipe_side")
	_free_cam(p0 + d * 2.6 + side * 1.2 + Vector3.UP * 1.2, p0 + Vector3.UP * 0.95)
	await _frames(10)
	await _snap("park_outfit")
	# a jump-line kicker: the largest one in this park
	var k: Dictionary = {}
	for kk in pk["kickers"]:
		if kk["line"] == "jump" and (k.is_empty() or float(kk["height"]) > float(k["height"])):
			k = kk
	var o := Vector3(k["origin"][0], 0, k["origin"][1])
	var knuckle := Vector3(k["knuckle"][0], 0, k["knuckle"][1])
	knuckle.y = world.terrain.height(knuckle.x, knuckle.z)
	_free_cam(o - d * 16.0 + side * 14.0 + Vector3.UP * 6.0, knuckle)
	await _frames(10)
	await _snap("park_kicker")
	s.set_physics_process(false)
	s.difficulty = 0
	s.teleport(o - d * 12.0, Skier.yaw_of(d), float(k["approach_speed"]) - 1.0)
	var t := 0.0
	var snapped := false
	while t < 8.0:
		var lip_dist: float = (s.position - Vector3(k["lip"][0], 0, k["lip"][1])).dot(d)
		s.scripted_input = {"jump": 1.0, "lean_back": 1.0} if lip_dist > -2.5 and lip_dist < 0.0 else ({"lean_back": 1.0} if s.airborne else {})
		s.step(1.0 / 120.0)
		s.time += 1.0 / 120.0
		t += 1.0 / 120.0
		if s.airborne and not snapped and absf(wrapf(s.air_pitch, -PI, PI)) > 2.4:
			s._cur_xform = s._compose_xform()
			s._prev_xform = s._cur_xform
			_free_cam(s.position + side * 7.0 - d * 1.0 + Vector3.UP * 0.5, s.position)
			await _frames(3)
			await _snap("park_backflip")
			snapped = true
		if snapped and not s.airborne:
			break
	print("[TEST] park shots: %s, backflip snapped=%s" % [pk["name"], snapped])
	# close-ups of the outfit from three sides
	s.teleport(st["pos"], st["yaw"])
	for i in 30:
		s.step(1.0 / 120.0)
	s._cur_xform = s._compose_xform()
	s._prev_xform = s._cur_xform
	var fwd := Vector3(-sin(s.heading), 0, -cos(s.heading))
	var rt := fwd.cross(Vector3.UP)
	var c := s.position + Vector3.UP * 0.95
	for v in [["outfit_front", fwd * 2.4 + rt * 0.6], ["outfit_side", rt * 2.4 + fwd * 0.3], ["outfit_back", -fwd * 2.4 + rt * 0.7]]:
		_free_cam(c + v[1] + Vector3.UP * 0.25, c)
		await _frames(4)
		await _snap(v[0])
	var head: Vector3 = world.body.joints["head"]
	var hbz: Vector3 = world.body.ski_l.basis.z          # ski tips point -Z: the skier faces -hbz
	hbz = Vector3(hbz.x, 0, hbz.z).normalized()
	var hbx: Vector3 = hbz.cross(Vector3.UP)
	for v in [["helmet_front", -hbz * 0.75 + hbx * 0.3], ["helmet_side", hbx * 0.8 - hbz * 0.25]]:
		_free_cam(head + v[1] + Vector3.UP * 0.08, head)
		await _frames(4)
		await _snap(v[0])
	# pole push from a standstill on the staging area: frames through two strokes
	s.teleport(st["pos"], st["yaw"])
	for i in 24:
		s.scripted_input = {"tuck": 1.0}
		for f in 12:
			s.step(1.0 / 120.0)
			s.time += 1.0 / 120.0
		s._cur_xform = s._compose_xform()
		s._prev_xform = s._cur_xform
		if i >= 12 and i % 2 == 0:
			var pc := s.position + Vector3.UP * 0.9
			_free_cam(pc + rt * 3.0 + fwd * 0.6 + Vector3.UP * 0.2, pc)
			await _frames(2)
			await _snap("push_%d" % ((i - 12) / 2))
		else:
			await _frames(1)
	# a right 360 off the medium kicker: frames through the wind-up and the spin, and a double
	# backflip off the large one (first flip laid out, then tucked)
	for trick in ["mute", "360", "double"]:
		var kk: Dictionary = {}
		for k2 in pk["kickers"]:
			if k2["line"] == "jump" and k2["size"] == ("L" if trick == "double" else "M"):
				kk = k2
		if kk.is_empty():           # a park without that size (Big Air: L + XL): first jump-line kicker
			for k2 in pk["kickers"]:
				if k2["line"] == "jump" and kk.is_empty():
					kk = k2
		var ko := Vector3(kk["origin"][0], 0, kk["origin"][1])
		var lip := Vector3(kk["lip"][0], 0, kk["lip"][1])
		s.teleport(ko - d * 12.0, Skier.yaw_of(d), float(kk["approach_speed"]) - 1.0)
		var shot := 0
		var tt := 0.0
		var next_t := 0.0
		while tt < 6.0:
			var to_lip := (lip - s.position).dot(d)
			if trick == "mute":
				s.scripted_input = {"grab_left": 1.0} if (s.airborne and s.air_time > 0.15 and not (s.vel.y < 0.0 and s.position.y - world.terrain.height(s.position.x, s.position.z) < 2.2)) else {}
			elif trick == "360":
				if not s.airborne:
					s.scripted_input = {"lean_left": 1.0, "jump": 1.0} if to_lip > 0.4 else {}
				elif absf(s.air_rotation) + s.spin_vel * s.spin_vel / (2.0 * float(s.diff()["spin_damp"])) < deg_to_rad(350.0):
					s.scripted_input = {"lean_right": 1.0}
				else:
					s.scripted_input = {}
			else:
				s.scripted_input = {"jump": 1.0, "lean_back": 1.0} if (not s.airborne and to_lip > 0.4 and to_lip < 3.0) else ({"lean_back": 1.0} if s.airborne and s.air_pitch > -TAU * 1.75 else {})
			s.step(1.0 / 120.0)
			s.time += 1.0 / 120.0
			tt += 1.0 / 120.0
			if (to_lip < 4.0 or s.airborne) and tt >= next_t and shot < 8:
				s._cur_xform = s._compose_xform()
				s._prev_xform = s._cur_xform
				_free_cam(s.position + side * 6.0 - d * 2.0 + Vector3.UP * 1.0, s.position + Vector3.UP * 0.8)
				await _frames(2)
				await _snap("%s_%d" % [trick, shot])
				shot += 1
				next_t = tt + (0.12 if trick == "360" else 0.16)
			if shot > 0 and not s.airborne and to_lip < -3.0:
				break
		print("[TEST] %s: rotation %.0f deg, flips %.2f, crashed %s" % [trick, rad_to_deg(s.air_rotation), s.air_pitch / TAU, s.is_crashed])
	s.scripted_input = null
	s.set_physics_process(true)


## Time of day / weather, gear colours, boot prints and speed streaks.
func _showcase5() -> void:
	var s := world.skier
	var keep := [Settings.get_value("world", "time_of_day"), Settings.get_value("world", "weather"), Settings.get_value("gear", "jacket"),
		Settings.get_value("gear", "helmet")]
	world.spawn_at_drop("Powder Bowl")
	s.frozen = true
	await _frames(20)
	for c in [["morning", "clear"], ["day", "snowing"], ["golden", "clear"], ["dusk", "clear"], ["day", "storm"], ["day", "fog"]]:
		Settings.set_value("world", "time_of_day", c[0])
		Settings.set_value("world", "weather", c[1])
		await _frames(25)
		await _snap("cond_%s_%s" % c)
	Settings.set_value("world", "time_of_day", "day")
	Settings.set_value("world", "weather", "clear")
	Settings.set_value("gear", "jacket", 1)
	Settings.set_value("gear", "helmet", 2)
	s.frozen = false
	var spot := _find_slope(6.0, 12.0)
	world.spawn(spot["pos"], spot["yaw"])
	await _frames(5)
	s.toggle_skis()
	s.scripted_input = {"tuck": 1.0}
	await _frames(90)
	s.scripted_input = null
	var f := Skier.forward_flat_s(s.heading)
	_free_cam(s.position - f * 1.5 + f.cross(Vector3.UP) * 2.5 + Vector3.UP * 2.6, s.position - f * 2.5)
	await _frames(3)
	await _snap("gear_prints")
	world.camera.set_process(true)
	s.toggle_skis()
	var hud = get_parent().get("hud")
	if hud:
		hud.visible = true
	var steep := _find_slope(30.0, 38.0)
	world.spawn(steep["pos"], steep["yaw"])
	s.teleport(steep["pos"], steep["yaw"], 28.0)
	s.scripted_input = {"tuck": 1.0}
	await _frames(25)
	await _snap("speed_streaks")
	s.scripted_input = null
	Settings.set_value("world", "time_of_day", keep[0])
	Settings.set_value("world", "weather", keep[1])
	Settings.set_value("gear", "jacket", keep[2])
	Settings.set_value("gear", "helmet", keep[3])


# ------------------------------------------------------------------ terrain features
func _ski_line(s: Skier, start: Vector3, yaw: float, v0: float, seconds: float, aim := Vector3.INF) -> Dictionary:
	s.teleport(start, yaw, v0)
	s.scripted_input = {"tuck": 1.0}
	var res := {"air": 0.0, "crash": "", "impact": 0.0, "max_air": 0.0, "closest": INF, "v_at": 0.0}
	var target := start + Skier.forward_flat_s(yaw) * 45.0 if aim == Vector3.INF else aim
	var box := {}
	var cb := func(info): box["info"] = info
	s.landed.connect(cb)
	var ccb := func(reason, _v): box["crash"] = reason
	s.crashed.connect(ccb)
	var t := 0.0
	while t < seconds and not s.is_crashed:
		s.step(1.0 / 120.0)
		s.time += 1.0 / 120.0
		t += 1.0 / 120.0
		var dd := Vector2(s.position.x - target.x, s.position.z - target.z).length()
		if Game.test_args.get("trace", "") != "" and dd < 6.0:
			var gp := s.position.y - world.terrain.height(s.position.x, s.position.z)
			print("[TRACE] d=%.2f gap=%.3f air=%s contact=%s v=(%.1f,%.1f,%.1f) n.y=%.2f" % [dd, gp, s.airborne, s.contact, s.vel.x, s.vel.y, s.vel.z, s.ground_n.y])
		if Game.test_args.get("trace", "") != "" and s.airborne != bool(box.get("was_air", false)):
			box["was_air"] = s.airborne
			print("[TRACE] t=%.2f airborne=%s d=%.1f" % [t, s.airborne, dd])
		if dd < float(res["closest"]):
			res["closest"] = dd
			res["v_at"] = s.speed
		if box.has("info"):
			var info: Dictionary = box["info"]
			if float(info["air_time"]) > float(res["max_air"]):
				res["max_air"] = info["air_time"]
				res["impact"] = info["impact"]
				res["crash"] = info["crash"]
			box.erase("info")
	s.landed.disconnect(cb)
	s.crashed.disconnect(ccb)
	if s.is_crashed and res["crash"] == "":
		res["crash"] = box.get("crash", "crashed")
	if s.is_crashed:
		var dd := Skier.forward_flat_s(yaw)
		res["crash"] += " %.0f m past" % ((s.position - target).dot(dd))
	return res


func _features() -> void:
	var s := world.skier
	var t := world.terrain
	var feats: Array = t.layout.get("features", [])
	if Game.test_args.get("phys", "1") == "1":
		world.body.set_process(false)
		s.set_physics_process(false)
		for f in feats:
			match String(f["type"]):
				"cliff", "lip":
					if Game.test_args.get("trace", "") != "" and f["name"] != Game.test_args["trace"]:
						continue
					var d := Vector3(f["dx"], 0, f["dz"])
					# walk uphill from the feature (stop at a crest so the skier does not roll away)
					var c := Vector3(f["x"], 0, f["z"])
					var back := 45.0
					var hp := t.height(c.x - d.x * 12.0, c.z - d.z * 12.0)
					for k in range(13, 46):
						var hk := t.height(c.x - d.x * k, c.z - d.z * k)
						if hk < hp + 0.15:
							back = k - 1
							break
						hp = hk
					var start := c - d * back
					var r := _ski_line(s, start, Skier.yaw_of(d), 9.0 + (45.0 - back) * 0.25, 12.0, c)
					print("[TEST] %-6s %-16s %s: longest air %.2f s, impact %.1f m/s, %s  (passed %.1f m from centre at %.0f km/h, slope %.0f)" % [f["type"], f["name"],
						("drop %.1f m" % f["drop"]) if f["type"] == "cliff" else ("lip %.1f m" % f["height"]),
						r["max_air"], r["impact"], ("CRASH: " + r["crash"]) if r["crash"] != "" else "landed", r["closest"], float(r["v_at"]) * 3.6,
						t.slope_deg(f["x"] - f["dx"] * 20.0, f["z"] - f["dz"] * 20.0)])
				"gully":
					var pth: Array = f["path"]
					var a := Vector3(pth[2][0], 0, pth[2][1])
					var b := Vector3(pth[5][0], 0, pth[5][1])
					s.teleport(a, Skier.yaw_of(b - a), 10.0)
					var t0 := 0.0
					var maxwall := 0.0
					var side := 1.0
					while t0 < 12.0 and not s.is_crashed:
						s.scripted_input = {"steer_right": 1.0} if side > 0.0 else {"steer_left": 1.0}
						if fmod(t0, 2.4) < 1.0 / 120.0:
							side = -side
						s.step(1.0 / 120.0)
						s.time += 1.0 / 120.0
						t0 += 1.0 / 120.0
						maxwall = maxf(maxwall, t.slope_deg(s.position.x, s.position.z))
					print("[TEST] gully  %-16s rode %.1f s, steepest wall %.0f deg, speed %.0f km/h, crashed=%s" % [f["name"], t0, maxwall, s.speed_kmh(), s.is_crashed])
		world.body.set_process(true)
		s.set_physics_process(true)
	if Game.test_args.get("shots", "0") != "1":
		return
	var cam := world.camera
	cam.set_process(false)
	var shots := {}
	for f in feats:
		var ty := String(f["type"])
		if shots.has(ty) and ty != "cliff":
			continue
		if ty == "cliff" and int(shots.get("cliff", 0)) >= 2:
			continue
		if ty in ["trail", "moguls"]:
			continue
		shots[ty] = int(shots.get(ty, 0)) + 1
		var c := Vector3(f["x"], 0, f["z"])
		c.y = t.height(c.x, c.z)
		var d := Vector3(f.get("dx", 0.6), 0, f.get("dz", 0.8)).normalized()
		var side := d.cross(Vector3.UP)
		var pos := c + d * 55.0 + side * 35.0
		if ty == "lake":
			pos = c + Vector3(1, 0, 1).normalized() * (float(f["radius"]) + 60.0)
		pos.y = maxf(t.height(pos.x, pos.z), c.y - 30.0) + (40.0 if ty == "lake" else 10.0)
		cam.global_transform = Transform3D(Basis.IDENTITY, pos).looking_at(c + Vector3.UP * 2.0, Vector3.UP)
		world.renderer.update_lod(pos, true)
		await _frames(8)
		await _snap("feature_%s_%d" % [ty, shots[ty]])
	for m in t.layout.get("landmarks", []):
		var c := Vector3(m["x"], 0, m["z"])
		c.y = t.height(c.x, c.z)
		var pos := c + Vector3(16, 0, 12)
		pos.y = maxf(t.height(pos.x, pos.z), c.y) + 4.0
		cam.global_transform = Transform3D(Basis.IDENTITY, pos).looking_at(c + Vector3.UP * 3.0, Vector3.UP)
		world.renderer.update_lod(pos, true)
		await _frames(8)
		await _snap("landmark_%s" % String(m["type"]))
	cam.set_process(true)
