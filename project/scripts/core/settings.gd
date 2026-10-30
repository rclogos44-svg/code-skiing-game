extends Node
## Persistent user settings: graphics, controls (rebindable), camera and audio.
## Saved automatically to user://settings.cfg whenever a value changes.

signal changed(section: String, key: String)

const PATH := "user://settings.cfg"

## Rebindable gameplay actions. "keys" are physical keycodes or mouse buttons (negative = mouse button).
const ACTIONS := {
	"tuck": {"label": "Tuck / Pole push", "keys": [KEY_W]},
	"brake": {"label": "Brake (hockey stop)", "keys": [KEY_S]},
	"steer_left": {"label": "Carve left", "keys": [KEY_A]},
	"steer_right": {"label": "Carve right", "keys": [KEY_D]},
	"carve": {"label": "Aggressive carve", "keys": [KEY_SHIFT]},
	"jump": {"label": "Crouch / Jump", "keys": [KEY_SPACE]},
	"spin_left": {"label": "Spin left (air)", "keys": [KEY_Q]},
	"spin_right": {"label": "Spin right (air)", "keys": [KEY_E]},
	"grab_left": {"label": "Left ski grab", "keys": [KEY_Z]},
	"grab_right": {"label": "Right ski grab", "keys": [KEY_X]},
	"camera_switch": {"label": "Switch camera", "keys": [KEY_C]},
	"first_person": {"label": "First-person view", "keys": [KEY_F]},
	"respawn": {"label": "Respawn", "keys": [KEY_R]},
	"interact": {"label": "Interact / Ride lift", "keys": [KEY_G]},
	"skis": {"label": "Skis off / on (walk)", "keys": [KEY_T]},
	"map": {"label": "Mountain map", "keys": [KEY_TAB]},
	"pause": {"label": "Pause", "keys": [KEY_P]},
}

## Gamepad defaults (not rebindable through the UI, always present).
const JOY_BUTTONS := {
	"jump": [JOY_BUTTON_A],
	"grab_left": [JOY_BUTTON_X],
	"grab_right": [JOY_BUTTON_B],
	"respawn": [JOY_BUTTON_Y],
	"spin_left": [JOY_BUTTON_LEFT_SHOULDER],
	"spin_right": [JOY_BUTTON_RIGHT_SHOULDER],
	"camera_switch": [JOY_BUTTON_RIGHT_STICK],
	"first_person": [JOY_BUTTON_LEFT_STICK],
	"interact": [JOY_BUTTON_DPAD_UP],
	"skis": [JOY_BUTTON_DPAD_DOWN],
	"map": [JOY_BUTTON_BACK],
	"pause": [JOY_BUTTON_START],
}
const JOY_AXES := {
	"steer_left": [JOY_AXIS_LEFT_X, -1.0],
	"steer_right": [JOY_AXIS_LEFT_X, 1.0],
	"tuck": [JOY_AXIS_LEFT_Y, -1.0],
	"brake": [JOY_AXIS_LEFT_Y, 1.0],
	"carve": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
}

const PRESETS := {
	"low": {"shadows": 1, "view_distance": 0, "aa": "off", "ssao": false, "glow": false, "detail": 0, "render_scale": 0.85},
	"medium": {"shadows": 2, "view_distance": 1, "aa": "fxaa", "ssao": false, "glow": true, "detail": 1, "render_scale": 1.0},
	"high": {"shadows": 3, "view_distance": 2, "aa": "msaa2", "ssao": true, "glow": true, "detail": 2, "render_scale": 1.0},
	"ultra": {"shadows": 4, "view_distance": 3, "aa": "msaa4", "ssao": true, "glow": true, "detail": 3, "render_scale": 1.0},
}

const RESOLUTIONS := ["1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160"]

var data := {}
var _defaults := {
	"graphics": {
		"preset": "high", "window_mode": "borderless", "resolution": "1920x1080", "vsync": true, "max_fps": 0,
		"render_scale": 1.0, "shadows": 3, "view_distance": 2, "aa": "msaa2", "ssao": true, "glow": true,
		"detail": 2, "show_fps": false,
	},
	"controls": {"mouse_sens": 1.0, "invert_y": false, "steer_sens": 1.0, "bindings": {}},
	"camera": {"fov": 72.0, "distance": 1.0, "speed_fx": true, "shake": true, "auto_center": true,
		"minimap": true, "minimap_rotate": true},
	"audio": {"master": 0.8, "sfx": 1.0, "ambience": 0.8, "ui": 0.7},
}
var _save_pending := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_web():
		# browser (WebGL 2) build: start windowed in the page, lighter defaults
		_defaults["graphics"].merge({"preset": "medium", "window_mode": "windowed", "shadows": 2, "view_distance": 1,
			"aa": "off", "ssao": false, "detail": 1, "render_scale": 1.0}, true)
	load_settings()
	apply_input()
	apply_audio()
	# window/graphics are applied once the main scene is ready (needs a viewport)
	call_deferred("apply_display")


static func is_web() -> bool:
	return OS.has_feature("web")


func get_value(section: String, key: String):
	if data.has(section) and data[section].has(key):
		return data[section][key]
	return _defaults[section][key]


func set_value(section: String, key: String, value, mark_custom := true) -> void:
	if not data.has(section):
		data[section] = {}
	data[section][key] = value
	if section == "graphics" and mark_custom and key in ["shadows", "view_distance", "aa", "ssao", "glow", "detail", "render_scale"]:
		data["graphics"]["preset"] = "custom"
	match section:
		"graphics":
			apply_display()
		"audio":
			apply_audio()
	changed.emit(section, key)
	_queue_save()


func apply_preset(name: String) -> void:
	if not PRESETS.has(name):
		return
	for k in PRESETS[name]:
		data["graphics"][k] = PRESETS[name][k]
	data["graphics"]["preset"] = name
	apply_display()
	changed.emit("graphics", "preset")
	_queue_save()


func load_settings() -> void:
	data = _defaults.duplicate(true)
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for section in _defaults:
		for key in _defaults[section]:
			if cfg.has_section_key(section, key):
				var v = cfg.get_value(section, key)
				if typeof(v) == typeof(_defaults[section][key]) or (typeof(v) in [TYPE_INT, TYPE_FLOAT] and typeof(_defaults[section][key]) in [TYPE_INT, TYPE_FLOAT]):
					data[section][key] = v


func save_settings() -> void:
	_save_pending = false
	var cfg := ConfigFile.new()
	for section in data:
		for key in data[section]:
			cfg.set_value(section, key, data[section][key])
	cfg.save(PATH)


func _queue_save() -> void:
	if not _save_pending:
		_save_pending = true
		call_deferred("save_settings")


# ------------------------------------------------------------------ display
func apply_display() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if DisplayServer.get_name() == "headless":
		return
	var mode: String = get_value("graphics", "window_mode")
	var res: String = get_value("graphics", "resolution")
	var parts := res.split("x")
	var size := Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i(1920, 1080)
	if is_web():
		# in a browser the page owns the canvas size; only fullscreen on/off applies
		var want_fs := mode != "windowed"
		var is_fs := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		if want_fs != is_fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED)
		mode = "windowed"
	match mode:
		"fullscreen":
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var screen := DisplayServer.screen_get_size()
			var s := Vector2i(mini(size.x, screen.x), mini(size.y, screen.y - 60))
			if not is_web() and DisplayServer.window_get_size() != s:
				DisplayServer.window_set_size(s)
				DisplayServer.window_set_position((screen - s) / 2)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("graphics", "vsync") else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(get_value("graphics", "max_fps"))
	# render scale: in fullscreen the chosen resolution is emulated through 3D scaling
	var scale: float = float(get_value("graphics", "render_scale"))
	if mode != "windowed":
		var screen2 := DisplayServer.screen_get_size()
		if screen2.x > 0:
			scale *= clampf(float(size.x) / float(screen2.x), 0.25, 1.0)
	vp.scaling_3d_scale = clampf(scale, 0.25, 1.0)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	var aa: String = get_value("graphics", "aa")
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	match aa:
		"fxaa":
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		"msaa2":
			vp.msaa_3d = Viewport.MSAA_2X
		"msaa4":
			vp.msaa_3d = Viewport.MSAA_4X
	var sh: int = int(get_value("graphics", "shadows"))
	var atlas: int = [1024, 1024, 2048, 4096, 4096][clampi(sh, 0, 4)]
	RenderingServer.directional_shadow_atlas_set_size(atlas, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][clampi(sh, 0, 4)])


# ------------------------------------------------------------------ audio
func apply_audio() -> void:
	_set_bus("Master", float(get_value("audio", "master")))
	_set_bus("SFX", float(get_value("audio", "sfx")))
	_set_bus("Ambience", float(get_value("audio", "ambience")))
	_set_bus("UI", float(get_value("audio", "ui")))


func _set_bus(name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.001)


# ------------------------------------------------------------------ input
func apply_input() -> void:
	var saved: Dictionary = get_value("controls", "bindings")
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		var codes: Array = saved.get(action, ACTIONS[action]["keys"])
		for code in codes:
			InputMap.action_add_event(action, _make_event(int(code)))
		for b in JOY_BUTTONS.get(action, []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			InputMap.action_add_event(action, jb)
		if JOY_AXES.has(action):
			var ja := InputEventJoypadMotion.new()
			ja.axis = JOY_AXES[action][0]
			ja.axis_value = JOY_AXES[action][1]
			InputMap.action_add_event(action, ja)
	# Escape always opens the pause menu (not rebindable)
	if not InputMap.has_action("menu"):
		InputMap.add_action("menu")
		var esc := InputEventKey.new()
		esc.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("menu", esc)


func _make_event(code: int) -> InputEvent:
	if code < 0:
		var mb := InputEventMouseButton.new()
		mb.button_index = -code
		return mb
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	return ev


func get_binding(action: String) -> int:
	var saved: Dictionary = get_value("controls", "bindings")
	var codes: Array = saved.get(action, ACTIONS[action]["keys"])
	return int(codes[0]) if codes.size() > 0 else 0


func rebind(action: String, event: InputEvent) -> void:
	var code := 0
	if event is InputEventKey:
		code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	elif event is InputEventMouseButton:
		code = -event.button_index
	if code == 0:
		return
	var b: Dictionary = data["controls"].get("bindings", {}).duplicate()
	# swap with any action that already uses this key
	for other in ACTIONS:
		if other != action and get_binding(other) == code:
			b[other] = [get_binding(action)]
	b[action] = [code]
	data["controls"]["bindings"] = b
	apply_input()
	changed.emit("controls", "bindings")
	_queue_save()


func reset_bindings() -> void:
	data["controls"]["bindings"] = {}
	apply_input()
	changed.emit("controls", "bindings")
	_queue_save()


func binding_label(action: String) -> String:
	return code_label(get_binding(action))


static func code_label(code: int) -> String:
	if code < 0:
		match -code:
			MOUSE_BUTTON_LEFT:
				return "Mouse L"
			MOUSE_BUTTON_RIGHT:
				return "Mouse R"
			MOUSE_BUTTON_MIDDLE:
				return "Mouse M"
			_:
				return "Mouse %d" % (-code)
	var kc := 0 if OS.has_feature("web") else DisplayServer.keyboard_get_keycode_from_physical(code)
	var s := OS.get_keycode_string(kc if kc != 0 else code)
	return s if s != "" else "?"
