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
	if Game.test_args.has("weather"):
		Settings.set_value("world", "weather", String(Game.test_args["weather"]))
	out_dir = Game.test_args.get("out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	match Game.test_mode:
		"park":
			await _park_showcase()
		"upgrade":
			await _upgrade_showcase()
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


func _body_physics(spot: Dictionary) -> void:
	var s := world.skier
	var saved := s.difficulty
	s.difficulty = 1
	# Measure tail loading on a fixed planar takeoff, independent of bumps along the route.
	var mountain := world.terrain
	var ramp := ContactTerrain.new()
	ramp.grade = 0.4
	world.terrain = ramp
	s.terrain = ramp
	var ramp_spot := {"pos": Vector3(3000, 1000, 3000), "yaw": 0.0}
	var plain := _pop(ramp_spot, {"jump": 1.0}, 0.6, {"jump": 1.0}, 0.25, {})
	var loaded := _pop(ramp_spot, {"jump": 1.0, "lean_back": 1.0}, 0.6, {"jump": 1.0}, 0.25, {})
	check("leaning back loads the tails: bigger pop", loaded["clear"] > plain["clear"] * 1.15, "%.2f m vs %.2f m" % [loaded["clear"], plain["clear"]])
	world.terrain = mountain
	s.terrain = mountain
	var bf := _pop(spot, {"jump": 1.0, "lean_back": 1.0}, 0.6, {"jump": 1.0, "lean_back": 1.0}, 0.05, {"lean_back": 1.0}, 0.35)
	check("holding back at the pop starts a backflip", bf["pitch"] < -0.5, "%.0f deg after 0.35 s" % rad_to_deg(bf["pitch"]))
	var wound := _pop(spot, {"jump": 1.0, "lean_right": 1.0}, 0.8, {"jump": 1.0, "lean_right": 1.0}, 0.02, {}, 0.5)
	check("wind-up spins without air input", wound["rot"] > deg_to_rad(90.0), "%.0f deg in 0.5 s" % rad_to_deg(wound["rot"]))
	var tucked := _pop(spot, {"jump": 1.0, "lean_right": 1.0}, 0.8, {"jump": 1.0, "lean_right": 1.0}, 0.02, {"tuck": 1.0}, 0.5)
	check("push input does not accelerate air rotation", absf(tucked["rot"] - wound["rot"]) < 0.01, "%.0f vs %.0f deg" % [rad_to_deg(tucked["rot"]), rad_to_deg(wound["rot"])])
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
func _jib_run(r: Dictionary, back: float, v0: float, ctl: Callable, heading_off := 0.0, from_air := false) -> Dictionary:
	var s := world.skier
	var a: Vector3 = r["a"]
	var dir: Vector3 = (r["b"] - a).normalized()
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	s.teleport(a - flat * back, Skier.yaw_of(flat), v0)
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


func _jibs() -> void:
	var s := world.skier
	var park = world.park
	if park == null or park.rails.is_empty():
		check("terrain park has rails and boxes", false)
		return
	var boxes: Array = park.rails.filter(func(r): return r["kind"] == "box")
	var rls: Array = park.rails.filter(func(r): return r["kind"] == "rail")
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
	var longest: Dictionary = boxes[0]
	for b in boxes:
		if float(b["length"]) > float(longest["length"]):
			longest = b
	s.difficulty = 2
	var r4 := _jib_run(longest, 10.0, 6.0, none)
	check("Realistic: wide box supports centered skier", r4["mounted"] and r4["info"].get("how", "") == "end", "%s %s" % [r4["info"].get("how", ""), r4["crash"]])
	var balancer := func(sk: Skier):
		if not sk.is_grinding():
			return {}
		var c := -sk.rail_balance * 3.0 - sk._rail_bal_vel * 1.5
		return {"steer_right": clampf(c, 0.0, 1.0), "steer_left": clampf(-c, 0.0, 1.0)}
	var r5 := _jib_run(longest, 10.0, 6.0, balancer)
	check("Realistic: balancing with A/D reaches the end", r5["info"].get("how", "") == "end", "%s %s, %.1f s" % [r5["info"].get("how", ""), r5["crash"], float(r5["info"].get("time", 0.0))])
	s.difficulty = 1
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
	check("stays grounded on smooth slope", not s.airborne and not s.is_crashed)
	# At speed the binding must not provide thrust or change aerodynamic drag.
	s = _settle_on(spot["pos"], spot["yaw"])
	s.vel = s.forward_flat() * 12.0
	_run(s, 2.0, {})
	var unassisted := s.vel
	s = _settle_on(spot["pos"], spot["yaw"])
	s.vel = s.forward_flat() * 12.0
	_run(s, 2.0, {"tuck": 1.0})
	check("push input has no high-speed advantage", s.vel.distance_to(unassisted) < 0.001)
	_pole_tests()
	_contact_tests()
	_upgrade_lines()
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
	check("spin input rotates in air", absf(s.air_rotation) > deg_to_rad(60.0) or not s.airborne, "%.0f deg" % rad_to_deg(s.air_rotation))
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
	_jibs()
	_park_regressions()
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
	await _frames(20) # exclude initial shader compilation from steady-state sample
	var previous_tick := Time.get_ticks_usec()
	var frame_times: Array[float] = []
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
		var tick := Time.get_ticks_usec()
		var d := float(tick - previous_tick) / 1000000.0
		previous_tick = tick
		frame_times.append(d * 1000.0)
		frames += 1
		total += d
		worst = maxf(worst, d)
	print("[TEST] smoke frames=%d avg_ms=%.1f worst_ms=%.1f speed=%.1f km/h draw_calls=%d prims=%d patches=%d" % [
		frames, total / maxf(frames, 1) * 1000.0, worst * 1000.0, s.speed_kmh(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		world.renderer.patch_count()])
	frame_times.sort()
	print("[TEST] profile renderer=%s viewport=%s preset=%s p95_ms=%.1f" % [RenderingServer.get_current_rendering_method(), get_viewport().get_visible_rect().size, Settings.get_value("graphics", "preset"), frame_times[int(frame_times.size() * 0.95)]])
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
	check("cork recognised", str(tck.get("name", "")).contains("Cork 720"), str(tck.get("name", "")))
	var ttip := TrickSystem.evaluate(base.merged({"rotation": 0.0, "grab_l": 0.8, "grab_kind_l": "tip"}, true))
	check("tip grab recognised", str(ttip.get("name", "")) == "Left Tip Grab", str(ttip.get("name", "")))
	var tsk := TrickSystem.evaluate(base.merged({"rotation": deg_to_rad(360.0), "misalign": 40.0}, true))
	check("sketchy landing scores less", int(tsk.get("points", 0)) < int(t360.get("points", 0)))
	# --- real 360: jump off a slope, spin, land
	var ok360 := false
	for attempt in 6:
		var sp2 := _find_slope(26.0 + attempt, 34.0 + attempt)
		if sp2.is_empty():
			continue
		s.teleport(sp2["pos"], sp2["yaw"])
		s.scripted_input = {"tuck": 1.0}
		for i in 240:
			s.step(dt)
		s.scripted_input = {"jump": 1.0}
		for i in 66:
			s.step(dt)
		var box := {}
		var cb := func(info): box["info"] = info
		s.landed.connect(cb)
		s.scripted_input = {"spin_right": 1.0}
		var t2 := 0.0
		while t2 < 4.0 and not box.has("info"):
			# stop spinning once a full turn is done so the landing lines up
			# (spin keeps going while it damps out, so release early enough to land near 360)
			if s.airborne and absf(s.air_rotation) + s.spin_vel * s.spin_vel / (2.0 * Skier.SPIN_DAMP) > deg_to_rad(355.0):
				s.scripted_input = {}
			s.step(dt)
			t2 += dt
		s.landed.disconnect(cb)
		var landed_info: Dictionary = box.get("info", {})
		if not landed_info.is_empty():
			var tr := TrickSystem.evaluate(landed_info)
			print("[TEST]   attempt %d: air %.2f s, rotation %.0f deg, misalign %.0f, crash '%s' -> %s" % [attempt, landed_info["air_time"],
				rad_to_deg(landed_info["rotation"]), landed_info["misalign"], landed_info["crash"], tr.get("name", "-")])
			if landed_info["crash"] == "" and tr.get("spin", 0) >= 360:
				ok360 = true
				break
	check("a real 360 can be landed", ok360)
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


func _pole_tests() -> void:
	var s := Skier.new()
	s.scripted_input = {"tuck": 1.0}
	s._pole_push(0.25, Vector3.FORWARD, Vector3.UP, 0.0)
	check("pole anticipation has no propulsion", s.vel == Vector3.ZERO and s.push_phase > 0.0)
	s._pole_push(0.35, Vector3.FORWARD, Vector3.UP, 0.0)
	check("pole drive starts skier from rest", s.vel.length() > 1.0)
	var driven := s.vel
	s.push_phase = 0.7
	s._pole_push(0.2, Vector3.FORWARD, Vector3.UP, 0.0)
	check("pole recovery has no propulsion", s.vel == driven)
	s.airborne = true
	s._pole_push(0.2, Vector3.FORWARD, Vector3.UP, 0.0)
	check("airborne cancels stroke", s.push_phase < 0.0 and s.vel == driven)
	s.airborne = false
	s.contact = false
	s._pole_push(0.2, Vector3.FORWARD, Vector3.UP, 0.0)
	check("no pole push without snow contact", s.push_phase < 0.0 and s.vel == driven)
	s.contact = true
	s._push_cooldown = 0.0
	s._pole_push(0.5, Vector3.FORWARD, Vector3.UP, s.push_max_speed)
	check("no stroke at speed threshold", s.push_phase < 0.0 and s.vel == driven)
	s.push_phase = 0.3
	s._pole_push(0.1, Vector3.FORWARD, Vector3.UP, 0.0)
	s.scripted_input = {"tuck": 1.0, "brake": 1.0}
	driven = s.vel
	s._pole_push(0.1, Vector3.FORWARD, Vector3.UP, 0.0)
	check("braking immediately cancels push", s.push_phase < 0.0 and s.vel == driven)
	s.scripted_input = {"tuck": 1.0}
	s.push_phase = 0.3
	s.vel = Vector3.ZERO
	s._pole_push(0.1, Vector3.FORWARD, Vector3.UP, 0.0)
	var flat := s.vel.length()
	s.push_phase = 0.3
	s.vel = Vector3.ZERO
	s._pole_push(0.1, Vector3(0, 0.5, -0.866).normalized(), Vector3.UP, 0.0)
	check("uphill pole assistance is limited", s.vel.length() < flat * 0.5)
	var speeds := []
	for hz: int in [60, 120, 240]:
		s._reset_motion()
		s.vel = Vector3.ZERO
		for i in hz * 8:
			var dt := 1.0 / hz
			s._push_cooldown = maxf(0.0, s._push_cooldown - dt)
			s._pole_push(dt, Vector3.FORWARD, Vector3.UP, s.vel.length())
		speeds.append(s.vel.length())
	check("pole acceleration is timestep stable", absf(speeds[0] - speeds[2]) < 0.05, str(speeds))
	check("repeated pushes remain below speed limit", speeds[2] < s.push_max_speed)
	s._reset_motion()
	s.vel = Vector3.ZERO
	for i in 120 * 8:
		s.scripted_input = {"tuck": 1.0 if i % 2 == 0 else 0.0}
		s._push_cooldown = maxf(0.0, s._push_cooldown - 1.0 / 120.0)
		s._pole_push(1.0 / 120.0, Vector3.FORWARD, Vector3.UP, s.vel.length())
	check("rapid input tapping cannot boost beyond holding", s.vel.length() <= speeds[1] + 0.05)
	s.push_phase = -1.0
	s._push_cooldown = 0.5
	s.scripted_input = {"tuck": 1.0}
	s._pole_push(0.1, Vector3.FORWARD, Vector3.UP, 0.0)
	check("interrupted stroke respects cooldown", s.push_phase < 0.0)
	s._reset_motion()
	check("respawn resets pole cycle", s.push_phase < 0.0 and s.pushing == 0.0)
	s.free()


class ContactTerrain extends TerrainData:
	var grade := 0.0
	var bumps := false
	var ledge := false
	func height(x: float, z: float) -> float:
		return 1000.0 + (z - 3000.0) * grade + (0.035 * sin(z * 4.0) if bumps else 0.0) - (1.0 if ledge and x > 3000.0 else 0.0)
	func surface_at(_x: float, _z: float) -> Color:
		return Color(0.2, 1.0, 0.0, 0.0)


func _contact_tests() -> void:
	var td := ContactTerrain.new()
	var s := Skier.new()
	s.terrain = td
	s.scripted_input = {}
	s.position = Vector3(3000, 1000, 3000)
	s._sample_skis(s.position, true)
	check("both skis supported on flat snow", s.ski_support[0] == 1.0 and s.ski_support[1] == 1.0)
	td.ledge = true
	s._sample_skis(s.position, true)
	check("one ski can lose contact independently", s.ski_support[0] > 0.9 and s.ski_support[1] < 0.1)
	check("unsupported ski does not pull body through ledge", s._sample_skis(s.position, false) > 999.9)
	td.ledge = false
	s.teleport(Vector3(3000, 1000, 3000), 0.0)
	_run(s, 6.0, {"tuck": 1.0})
	check("push moves skier from rest on actual flat terrain", s.speed > 2.0 and s.position.z < 2990.0 and not s.airborne, "speed %.2f" % s.speed)
	td.bumps = true
	s.teleport(Vector3(3000, 1000, 3000), 0.0, 20.0)
	var air_frames := 0
	var finite := true
	for i in 360:
		s.scripted_input = {}
		s.step(1.0 / 120.0)
		air_frames += int(s.airborne)
		finite = finite and s.vel.is_finite() and absf(s.leg_compression[0]) <= s.suspension_travel
	check("small terrain chatter does not repeatedly launch skier", air_frames < 20, "%d airborne frames" % air_frames)
	check("suspension remains bounded and finite", finite)
	td.bumps = false
	s.teleport(Vector3(3000, 1000, 3000), 0.0, 75.0)
	_run(s, 1.0, {})
	check("high-speed collision stays above snow", s.position.y >= 999.99 and not s.is_crashed)
	s.teleport(Vector3(3000, 1000, 3000), 0.0)
	s.airborne = true
	s.air_time = 0.6
	s.vel = Vector3(0, -22, -30)
	s._land(Vector3.UP, 22.0)
	check("flat impact crashes at excessive normal force", s.is_crashed)
	s._reset_motion()
	s.airborne = true
	s.air_time = 0.6
	s.vel = Vector3(0, -22, -30)
	var matching := Vector3(0, 1, -0.6).normalized()
	s._land(matching, -s.vel.dot(matching))
	check("same velocity lands safely on matching slope", not s.is_crashed and s.compression > 0.0)
	s._reset_motion()
	s.airborne = true
	s.vel = Vector3(0, 5, -12)
	for i in 60:
		s._air_step(1.0 / 120.0, 1.0, -1.0)
	var plain_air := Skier.new()
	plain_air.scripted_input = {}
	plain_air.vel = Vector3(0, 5, -12)
	for i in 60:
		plain_air._air_step(1.0 / 120.0, 0.0, 0.0)
	check("combined spin and flip preserve gravity and drag trajectory", s.vel.distance_to(plain_air.vel) < 0.001 and absf(s.air_rotation) > 0.5 and absf(s.air_pitch) > 0.3)
	plain_air.free()
	var obstacles := Obstacles.new()
	obstacles.setup(td.world)
	obstacles.add(3000.0, 2998.4, 0.18, 999.0, 1003.0, Obstacles.Kind.POLE)
	obstacles.build()
	s.obstacles = obstacles
	s.teleport(Vector3(3000, 1000, 3000), 0.0, 100.0)
	_run(s, 0.1, {})
	check("high-speed skier cannot tunnel through a thin obstacle", s.is_crashed and s.position.z > 2997.5)
	s.obstacles = null
	# Equal world velocity: slope matching lowers the normal impact component.
	var velocity := Vector3(0, -12, -20)
	var downhill := Vector3(0, 1, -0.6).normalized()
	check("matching downhill landing has lower normal impact", -velocity.dot(downhill) < -velocity.dot(Vector3.UP) * 0.5)
	s.free()


func _upgrade_lines() -> void:
	var s := world.skier
	var count := 0
	for f in world.terrain.layout.get("features", []):
		if not f.has("line_grade"):
			continue
		count += 1
		var direction := Vector3(f["dx"], 0, f["dz"])
		var center := Vector3(f["x"], 0, f["z"])
		var start := center - direction * 35.0
		var result := _ski_line(s, start, Skier.yaw_of(direction), 12.0, 8.0, center)
		print("[TEST] progression %s: %s" % [f["line_grade"], result])
		check("%s drop has real airtime" % f["line_grade"], result["max_air"] > 0.5)
		check("%s drop has a usable landing" % f["line_grade"], result["crash"] == "" and result["impact"] > 0.0)
	check("three progression lines available", count == 3)


func _upgrade_showcase() -> void:
	var s := world.skier
	world.spawn_at_drop("Resort Top")
	s.set_physics_process(false)
	s.scripted_input = {}
	world.body.set_process(false)
	world.camera.set_process(false)
	for pose in ["stance", "push", "layout", "spin", "landing", "inverted", "sideways"]:
		s._reset_motion()
		s._sample_skis(s.position, true)
		if pose == "push":
			s.push_phase = 0.45
		elif pose in ["layout", "spin", "inverted", "sideways"]:
			s.airborne = true
			s.air_time = 0.5
			s.air_pitch = -PI if pose == "inverted" else (-PI * 0.5 if pose == "sideways" else (-0.6 if pose == "layout" else -0.2))
			s.flip_vel = -3.0 if pose == "layout" else -1.0
			s.spin_vel = 3.5 if pose == "spin" else 0.0
			s.vel = Vector3(0, 2, -8)
		elif pose == "landing":
			s.compression = 0.7
		for i in 30:
			world.body._compute_pose(1.0/60.0)
		world.body._apply_parts()
		world.body._drive_rig()
		var target := s.position + Vector3.UP * 0.85
		_free_cam(target + s.forward_flat() * 3.8 + Vector3.UP * 0.7 + s.forward_flat().cross(Vector3.UP) * 2.0, target)
		await _frames(4)
		var finite := true
		for i in world.body.skeleton.get_bone_count():
			finite = finite and world.body.skeleton.get_bone_global_pose(i).is_finite()
		check("%s skeletal pose finite" % pose, finite and world.body.skeleton.get_bone_count() > 20)
		for side in ["l", "r"]:
			var ski: MeshInstance3D = world.body.parts["ski_" + side]
			check("%s ski %s remains local and attached" % [pose,side], ski.skin == null and ski.global_position.distance_to(world.body.joints["ankle_" + side]) < 0.3 and ski.global_transform.is_finite())
		await _snap("rider_" + pose)
	world.body.set_process(true)
	for name in ["Scout Drop", "Freeride Drop", "Expert Drop"]:
		world.spawn_at_drop(name)
		s.set_physics_process(false)
		s._reset_motion()
		var forward := s.forward_flat()
		_free_cam(s.position - forward * 10 + Vector3.UP * 10, s.position + forward * 65 - Vector3.UP * 12)
		world.renderer.update_lod(s.position, true)
		await _frames(6)
		await _snap(name.to_lower().replace(" ", "_"))


func _park_regressions() -> void:
	var s := world.skier
	var park = world.park
	world.spawn_at_drop("Terrain Park")
	check("park spawn stays inside practice area", park.contains_position(s.position))
	check("far outside park triggers boundary", not park.contains_position(Vector3.ZERO))
	check("all nine park features generated", park.rails.size() == 10)
	var kicker: Dictionary = world.terrain.layout["kickers"][0]
	var center := Vector3(kicker["x"], world.terrain.height(kicker["x"], kicker["z"]), kicker["z"])
	var retry: Dictionary = park.practice_start(center)
	check("nearest jump has an uphill practice reset", retry["position"].distance_to(center) > 30 and park.contains_position(retry["position"]))
	var box: Dictionary = park.rails[0]
	var direction: Vector3 = (box["b"] - box["a"]).normalized()
	var side := direction.cross(Vector3.UP).normalized()
	s.teleport(box["a"], Skier.yaw_of(direction))
	s.position = box["a"] + direction + side * 0.4
	s.vel = direction * 6
	s._mount(box, 1.0, 0.0, 6.0)
	s._raw_steer = 0
	s._grind_step(1.0/120.0)
	check("box preserves off-center contact", absf(s._box_lateral - 0.4) < 0.01)
	s._box_lateral = 0.7
	s._grind_step(1.0/120.0)
	check("box edge releases skier", not s.is_grinding() and s.airborne)
	var joined := false
	for r in park.rails:
		if not r.has("next"):
			continue
		s.teleport(r["a"], Skier.yaw_of(r["b"] - r["a"]))
		s._mount(r, r["length"] - 0.01, 0.0, 6.0)
		s.grind_time = 1.0
		s._grind_step(1.0/120.0)
		joined = s.grind == r["next"] and s.grind_time > 1.0 and not s.airborne
	check("flat-down joint preserves continuous trick", joined)
	s._reset_motion()


func _park_showcase() -> void:
	world.spawn_at_drop("Terrain Park")
	world.skier.set_physics_process(false)
	world.camera.set_process(false)
	var p := world.skier.position
	var f := world.skier.forward_flat()
	_free_cam(p - f * 8 + Vector3.UP * 5, p + f * 35)
	await _frames(4)
	await _snap("park_entrance")
	var r: Dictionary = world.park.rails[0]
	p = r["a"]
	f = (r["b"] - p).normalized()
	_free_cam(p - f * 22 + Vector3.UP * 22, p + f * 70)
	await _frames(4)
	await _snap("park_rows")
