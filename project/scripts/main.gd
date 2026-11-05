extends Node
## Root of the game: builds the world and UI, and runs the game flow
## (main menu -> career / free ride / challenges, pause, map, lifts, respawns, saving).

enum State { MENU, PLAYING, PAUSED, MAP }

var world: World
var hud: HUD
var tricks: TrickSystem
var challenges: ChallengeManager
var pois: POIManager
var menus: Menus
var map_screen: MapScreen
var ui_layer: CanvasLayer
var fade: ColorRect
var state := State.MENU
var _save_timer := 0.0
var _skip_hold := 0.0
var park_i := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world = World.new()
	world.name = "World"
	add_child(world)
	if not world.build():
		push_error("Failed to build world")
		get_tree().quit(1)
		return
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	tricks = TrickSystem.new()
	tricks.name = "Tricks"
	tricks.add_to_group("trick_system")
	world.add_child(tricks)
	tricks.setup(world.skier)
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(world.skier, world.terrain)
	challenges = ChallengeManager.new()
	challenges.name = "Challenges"
	world.add_child(challenges)
	challenges.setup(world, tricks, hud)
	pois = POIManager.new()
	pois.name = "POIs"
	world.add_child(pois)
	pois.setup(world.terrain, world.skier, hud)
	# park game: no drop-zone discovery, flags or viewpoints
	pois.process_mode = Node.PROCESS_MODE_DISABLED
	pois.visible = false
	tricks.trick_landed.connect(hud.show_trick)
	tricks.combo_banked.connect(hud.show_banked)
	tricks.combo_lost.connect(hud.show_combo_lost)
	world.skier.crashed.connect(func(_r, _v): Game.save["stats"]["crashes"] = int(Game.save["stats"].get("crashes", 0)) + 1)
	world.skier.mode_changed.connect(func(_m): hud.show_controls_hint())
	if world.resort:
		world.resort.ride_finished.connect(func(n: String): hud.notify("Top of the %s" % n, "info"))
	# UI
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)
	map_screen = MapScreen.new()
	map_screen.visible = false
	ui_layer.add_child(map_screen)
	map_screen.setup(world.terrain, world.skier)
	map_screen.teleport_drop.connect(_travel_drop)
	map_screen.start_challenge.connect(_start_challenge)
	menus = Menus.new()
	ui_layer.add_child(menus)
	menus.setup(world.terrain)
	menus.request.connect(_on_menu_request)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(fade)

	if Game.test_mode == "ui":
		_enter_menu()
		var tr = load("res://scripts/tools/test_runner.gd").new()
		tr.name = "TestRunner"
		add_child(tr)
		tr.run_ui(self)
		return
	if Game.test_mode != "":
		hud.visible = Game.test_mode == "shots_hud"
		Game.mode = "freeride"
		var tr = load("res://scripts/tools/test_runner.gd").new()
		tr.name = "TestRunner"
		add_child(tr)
		tr.run(world)
		return
	_enter_menu()


# ------------------------------------------------------------------ states
func _enter_menu() -> void:
	state = State.MENU
	Game.mode = "menu"
	Engine.time_scale = 1.0           # leaving the game ends slow motion
	get_tree().paused = false
	challenges.stop(false)
	hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# cinematic backdrop: the skier waiting at a scenic drop zone, camera orbiting
	var st: Dictionary = world.park.park_start(park_i)
	world.spawn(st["pos"], st["yaw"])
	world.skier.frozen = true
	var cam := world.camera
	cam.orbit_center = world.skier.position
	cam.orbit_radius = 9.0
	cam.orbit_height = 2.2
	cam.set_mode(CameraRig.Mode.ORBIT)
	menus.show_main()


func _start_play(mode: String) -> void:
	Game.mode = mode
	state = State.PLAYING
	menus.hide_all()
	map_screen.visible = false
	hud.visible = true
	get_tree().paused = false
	world.skier.frozen = false
	world.camera.set_mode(CameraRig.Mode.STANDARD)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_controls_hint()
	pois.refresh()


## Slow motion: the whole game (physics included) runs at a quarter speed, so tricks play out
## exactly as they would, just slower.
const SLOW_MO := 0.25


func _set_slow_mo(on: bool) -> void:
	Engine.time_scale = SLOW_MO if on else 1.0
	hud.notify("Slow motion %s  ·  %s to toggle" % ["ON" if on else "OFF", Settings.binding_label("slow_mo")], "info")


func _pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menus.show_pause(challenges.is_active())


func _resume() -> void:
	state = State.PLAYING
	menus.hide_all()
	map_screen.visible = false
	hud.visible = true
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Tab (the old map key): back to the top of the current park.
func _open_map() -> void:
	if state not in [State.PLAYING, State.PAUSED] or world.park == null:
		return
	if state == State.PAUSED:
		_resume()
	challenges.stop(false)
	var st: Dictionary = world.park.park_start(park_i)
	_fade_then(func():
		world.spawn(st["pos"], st["yaw"])
		world.camera.snap())


func _fade_then(cb: Callable) -> void:
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(fade, "color:a", 1.0, 0.25)
	tw.tween_callback(cb)
	tw.tween_property(fade, "color:a", 0.0, 0.45)


# ------------------------------------------------------------------ menu requests
func _on_menu_request(action: String, arg: String) -> void:
	match action:
		"new_game":
			Game.new_game()
			_fade_then(func():
				world.spawn_at_drop("Resort Top")
				_start_play("career")
				hud.notify("Welcome to SUMMIT. Ride the lifts, spot distant drop zones by looking at them, and find viewpoints to unlock the mountains.", "info"))
		"continue":
			_fade_then(func():
				var last: Dictionary = Game.save.get("last", {})
				if last.has("x"):
					world.spawn(Vector3(last["x"], 0, last["z"]), float(last.get("yaw", 0.0)))
				else:
					world.spawn_at_drop("Resort Top")
				_start_play("career"))
		"freeride_drop":
			_fade_then(func():
				world.spawn_at_drop(arg)
				_start_play("freeride"))
		"travel_drop":
			_travel_drop(arg)
		"challenge":
			_start_challenge(arg)
		"resume":
			_resume()
		"respawn":
			_resume()
			_respawn()
		"restart_challenge":
			_resume()
			challenges.restart()
		"abandon_challenge":
			_resume()
			challenges.stop(true)
		"map":
			_open_map()
		"park":
			park_i = int(arg)
			var st: Dictionary = world.park.park_start(park_i)
			_fade_then(func():
				world.spawn(st["pos"], st["yaw"])
				_start_play("freeride")
				hud.notify("%s  ·  Tab: back to the top" % st["name"], "info"))
		"park_top":
			_resume()
			_open_map()
		"main_menu":
			_store_position()
			Game.save_game()
			_fade_then(_enter_menu)
		"quit":
			_store_position()
			Game.save_game()
			get_tree().quit()


func _travel_drop(name: String) -> void:
	if not Game.is_drop_unlocked(name):
		return
	challenges.stop(false)
	var mode := Game.mode if Game.mode != "menu" else "career"
	_fade_then(func():
		world.spawn_at_drop(name)
		_start_play(mode))


func _start_challenge(id: String) -> void:
	var mode := Game.mode
	if mode == "menu":
		mode = "career" if Game.has_save() else "freeride"
		if mode == "career" and not Game.has_save():
			Game.new_game()
	_fade_then(func():
		_start_play(mode)
		challenges.start(id))


# ------------------------------------------------------------------ input & loop
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	match state:
		State.PLAYING:
			if event.is_action("menu") or event.is_action("pause"):
				_pause()
			elif event.is_action("map"):
				_open_map()
			elif event.is_action("camera_switch"):
				world.camera.cycle_mode()
			elif event.is_action("first_person"):
				world.camera.toggle_first_person()
			elif event.is_action("respawn"):
				_respawn()
			elif event.is_action("interact"):
				_try_lift()
			elif event.is_action("skis"):
				_toggle_skis()
			elif event.is_action("slow_mo"):
				_set_slow_mo(Engine.time_scale > 0.99)
			elif event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				return
			get_viewport().set_input_as_handled()
		State.PAUSED:
			if event.is_action("menu") or event.is_action("pause"):
				if not menus.back():
					_resume()
				get_viewport().set_input_as_handled()
		State.MAP:
			if event.is_action("map") or event.is_action("menu"):
				_resume()
				get_viewport().set_input_as_handled()
		State.MENU:
			if event.is_action("menu"):
				menus.back()
				get_viewport().set_input_as_handled()


func _respawn() -> void:
	if challenges.respawn_in_challenge():
		return
	world.skier.respawn()
	world.camera.snap()


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	var s := world.skier
	# automatic respawn a few seconds after a crash
	if s.is_crashed and s.crash_time > 3.2 and (world.body.ragdoll.settled_time > 0.5 or s.crash_time > 6.0):
		_respawn()
	# lifts
	var prompt := ""
	var ride_info := {}
	if world.resort:
		ride_info = world.resort.ride_info()
		if ride_info.is_empty() and not s.is_crashed and not challenges.is_active():
			var lf: Dictionary = world.resort.lift_near(s.position)
			if not lf.is_empty() and s.speed < 6.0:
				prompt = "Press %s to ride the %s" % [Settings.binding_label("interact"), lf["name"]]
		# hold the interact key while riding to skip to the top
		if ride_info.get("phase", "") == "ride" and Input.is_action_pressed("interact"):
			_skip_hold += delta
			if _skip_hold > 0.7:
				_skip_hold = -10.0
				_fade_then(func():
					world.resort.skip_ride()
					world.camera.snap())
		else:
			_skip_hold = 0.0
	if s.mode == Skier.Mode.WALK and prompt == "" and s.speed < 0.2:
		prompt = "%s  put your skis back on" % Settings.binding_label("skis")
	hud.set_prompt(prompt)
	hud.set_lift_status(ride_info, maxf(_skip_hold, 0.0) / 0.7)
	_save_timer += delta
	if _save_timer > 20.0 and Game.mode == "career":
		_save_timer = 0.0
		_store_position()
		Game.stat_add("distance", 0.0)
		Game.save_game()
	Game.stat_max("top_speed", s.speed_kmh())


func _try_lift() -> void:
	if world.resort == null:
		return
	var r = world.resort
	var s := world.skier
	if r.is_riding():
		if r.ride["phase"] == "wait":
			r.cancel_wait()
		return
	var lf: Dictionary = r.lift_near(s.position)
	if lf.is_empty() or s.speed >= 6.0 or s.is_crashed or challenges.is_active():
		return
	r.board(lf, s)
	world.camera.snap()


func _toggle_skis() -> void:
	var s := world.skier
	if challenges.is_active() or (world.resort and world.resort.is_riding()):
		return
	if not s.toggle_skis():
		if s.mode == Skier.Mode.SKI and s.speed >= 3.0:
			hud.notify("Stop first to take your skis off", "warning")


func _store_position() -> void:
	if Game.mode != "career":
		return
	var s := world.skier
	if s.is_crashed:
		return
	Game.set_last_position(s.position, s.heading)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_store_position()
		Game.save_game()
