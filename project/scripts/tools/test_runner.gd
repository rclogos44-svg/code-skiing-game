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
	# 2. tuck is faster than upright
	s = _settle_on(spot["pos"], spot["yaw"])
	_run(s, 4.0, {})
	var upright := s.vel.length()
	s = _settle_on(spot["pos"], spot["yaw"])
	_run(s, 4.0, {"tuck": 1.0})
	var tucked := s.vel.length()
	check("tuck reduces drag", tucked > upright, "upright %.1f vs tuck %.1f m/s" % [upright, tucked])
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
	check("spin input rotates in air", absf(s.air_rotation) > deg_to_rad(90.0) or not s.airborne, "%.0f deg" % rad_to_deg(s.air_rotation))
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
	_on_foot(spot)
	world.body.set_process(true)
	s.set_physics_process(true)
	await _lift_ride()


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
func _autopilot_step(s: Skier, target: Vector2) -> Dictionary:
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
	if s.speed > 32.0 or (absf(err) > 0.9 and s.speed > 14.0):
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
	# --- autopilot through every race
	for c in world.terrain.layout.get("challenges", []):
		if c["type"] != "race":
			continue
		s.teleport(Vector3(c["start"][0], 0, c["start"][1]), float(c["yaw"]))
		var cps: Array = c["checkpoints"]
		var idx := 0
		var t := 0.0
		var crashes := 0
		var reasons := {}
		var rcb := func(r, _v): reasons[r] = int(reasons.get(r, 0)) + 1
		s.crashed.connect(rcb)
		while idx < cps.size() and t < 600.0:
			var target := Vector2(cps[idx][0], cps[idx][1])
			s.scripted_input = _autopilot_step(s, target)
			s.step(dt)
			t += dt
			if s.is_crashed:
				crashes += 1
				s.crash_time = 3.0
				s.respawn()
			if Vector2(s.position.x, s.position.z).distance_to(target) < 13.0:
				idx += 1
			if s.speed < 0.3 and t > 5.0:
				s.scripted_input = {"tuck": 1.0}
		s.crashed.disconnect(rcb)
		var m: Array = c["medals"]
		print("[TEST] race %-18s autopilot %s  gates %d/%d  crashes %d %s  (gold %s silver %s bronze %s)" % [c["name"],
			UITheme.format_time(t), idx, cps.size(), crashes, str(reasons), UITheme.format_time(m[0]), UITheme.format_time(m[1]), UITheme.format_time(m[2])])
		if idx < cps.size():
			var gate_p := Vector2(cps[idx][0], cps[idx][1])
			print("[TEST]     stuck near (%.0f, %.0f) h=%.0f slope=%.0f, next gate (%.0f, %.0f) h=%.0f dist %.0f" % [s.position.x, s.position.z, s.position.y,
				world.terrain.slope_deg(s.position.x, s.position.z), gate_p.x, gate_p.y, world.terrain.height(gate_p.x, gate_p.y), Vector2(s.position.x, s.position.z).distance_to(gate_p)])
		check("race %s finishable" % c["name"], idx >= cps.size())
	world.body.set_process(true)
	s.set_physics_process(true)


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
