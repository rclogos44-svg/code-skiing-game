class_name SettingsMenu
extends PanelContainer
## Tabbed settings (graphics, controls with key rebinding, camera, audio).  Changes apply and
## save immediately.

signal closed

var _rebind_action := ""
var _rebind_buttons := {}
var _rows := {}
var tabs: TabContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UITheme.get_theme()
	custom_minimum_size = Vector2(900, 640)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	var title := UITheme.label("SETTINGS", 34, UITheme.TEXT, 800)
	v.add_child(title)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	tabs.add_child(_graphics_tab())
	tabs.add_child(_controls_tab())
	tabs.add_child(_camera_tab())
	tabs.add_child(_audio_tab())
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_close)
	v.add_child(back)
	Settings.changed.connect(_on_changed)


func _close() -> void:
	Sfx.ui()
	_rebind_action = ""
	closed.emit()


func _scroll(name: String) -> Array:
	var sc := ScrollContainer.new()
	sc.name = name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var g := GridContainer.new()
	g.columns = 2
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 10)
	sc.add_child(g)
	return [sc, g]


func _row(g: GridContainer, text: String, ctrl: Control) -> void:
	var l := UITheme.label(text, 19, UITheme.TEXT, 500)
	l.custom_minimum_size = Vector2(300, 0)
	g.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(ctrl)


func _option(section: String, key: String, items: Array, labels: Array, on_pick := Callable()) -> OptionButton:
	var ob := OptionButton.new()
	for i in labels.size():
		ob.add_item(labels[i], i)
	var cur = Settings.get_value(section, key)
	var idx := items.find(cur)
	ob.selected = maxi(idx, 0)
	ob.item_selected.connect(func(i: int):
		Sfx.ui()
		if on_pick.is_valid():
			on_pick.call(items[i])
		else:
			Settings.set_value(section, key, items[i]))
	_rows[section + "/" + key] = [ob, items]
	return ob


func _slider(section: String, key: String, lo: float, hi: float, step: float, fmt := "%.2f") -> HBoxContainer:
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(section, key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(260, 28)
	var val := UITheme.label(fmt % s.value, 18, UITheme.DIM, 500)
	val.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(x: float):
		val.text = fmt % x
		Settings.set_value(section, key, x))
	h.add_child(s)
	h.add_child(val)
	_rows[section + "/" + key] = [s, val, fmt]
	return h


func _check(section: String, key: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = "On"
	c.button_pressed = bool(Settings.get_value(section, key))
	c.toggled.connect(func(on: bool):
		Sfx.ui()
		Settings.set_value(section, key, on))
	_rows[section + "/" + key] = [c]
	return c


func _graphics_tab() -> Control:
	var sg := _scroll("Graphics")
	var g: GridContainer = sg[1]
	_row(g, "Time of day", _option("world", "time_of_day", ["morning", "day", "golden", "dusk"], ["Morning", "Midday", "Golden hour", "Dusk"]))
	_row(g, "Weather", _option("world", "weather", ["clear", "snowing", "storm", "fog"], ["Clear", "Light snow", "Snowstorm", "Valley fog"]))
	_row(g, "Quality preset", _option("graphics", "preset", ["low", "medium", "high", "ultra", "custom"], ["Low", "Medium", "High", "Ultra", "Custom"],
		func(v):
			if v != "custom":
				Settings.apply_preset(v)))
	if Settings.is_web():
		_row(g, "Display mode", _option("graphics", "window_mode", ["windowed", "borderless"], ["In page", "Fullscreen"]))
	else:
		_row(g, "Display mode", _option("graphics", "window_mode", ["windowed", "borderless", "fullscreen"], ["Windowed", "Borderless fullscreen", "Exclusive fullscreen"]))
		_row(g, "Resolution", _option("graphics", "resolution", Settings.RESOLUTIONS, Settings.RESOLUTIONS))
	_row(g, "Render scale", _slider("graphics", "render_scale", 0.5, 1.0, 0.05, "%.2f"))
	_row(g, "Shadow quality", _option("graphics", "shadows", [0, 1, 2, 3, 4], ["Off", "Low", "Medium", "High", "Ultra"]))
	_row(g, "View distance", _option("graphics", "view_distance", [0, 1, 2, 3], ["Near", "Medium", "Far", "Very far"]))
	_row(g, "Terrain & forest detail", _option("graphics", "detail", [0, 1, 2, 3], ["Low", "Medium", "High", "Ultra"]))
	_row(g, "Anti-aliasing", _option("graphics", "aa", ["off", "fxaa", "msaa2", "msaa4"], ["Off", "FXAA", "MSAA 2x", "MSAA 4x"]))
	_row(g, "Ambient occlusion", _check("graphics", "ssao"))
	_row(g, "Bloom", _check("graphics", "glow"))
	_row(g, "V-Sync", _check("graphics", "vsync"))
	_row(g, "Frame rate limit", _option("graphics", "max_fps", [0, 30, 60, 120, 144, 240], ["Unlimited", "30", "60", "120", "144", "240"]))
	_row(g, "Show FPS", _check("graphics", "show_fps"))
	return sg[0]


func _controls_tab() -> Control:
	var sg := _scroll("Controls")
	var g: GridContainer = sg[1]
	_row(g, "Difficulty", _option("controls", "difficulty", [0, 1, 2], ["Easy - forgiving landings, lots of air control",
		"Normal - some air control and assist", "Realistic - rotation only from your takeoff, edges can catch"]))
	_row(g, "Mouse sensitivity", _slider("controls", "mouse_sens", 0.2, 3.0, 0.05))
	_row(g, "Invert mouse Y", _check("controls", "invert_y"))
	_row(g, "Steering sensitivity", _slider("controls", "steer_sens", 0.4, 2.0, 0.05))
	for action in Settings.ACTIONS:
		var b := Button.new()
		b.text = Settings.binding_label(action)
		b.pressed.connect(func():
			Sfx.ui()
			_rebind_action = action
			b.text = "Press a key..."
			b.release_focus())
		_rebind_buttons[action] = b
		_row(g, Settings.ACTIONS[action]["label"], b)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.pressed.connect(func():
		Sfx.ui()
		Settings.reset_bindings())
	_row(g, "Key bindings", reset)
	var note := UITheme.label("Mouse: look around · Scroll: zoom · Esc: pause · Gamepad supported", 16, UITheme.DIM)
	g.add_child(note)
	return sg[0]


func _camera_tab() -> Control:
	var sg := _scroll("Camera")
	var g: GridContainer = sg[1]
	_row(g, "Field of view", _slider("camera", "fov", 55.0, 100.0, 1.0, "%.0f°"))
	_row(g, "Camera distance", _slider("camera", "distance", 0.6, 1.8, 0.05))
	_row(g, "Speed effects (FOV)", _check("camera", "speed_fx"))
	_row(g, "Camera shake", _check("camera", "shake"))
	_row(g, "Auto-center behind skier", _check("camera", "auto_center"))
	_row(g, "Show minimap", _check("camera", "minimap"))
	_row(g, "Minimap turns with the camera", _check("camera", "minimap_rotate"))
	return sg[0]


func _audio_tab() -> Control:
	var sg := _scroll("Audio")
	var g: GridContainer = sg[1]
	_row(g, "Master volume", _slider("audio", "master", 0.0, 1.0, 0.01, "%.2f"))
	_row(g, "Effects", _slider("audio", "sfx", 0.0, 1.0, 0.01, "%.2f"))
	_row(g, "Ambience", _slider("audio", "ambience", 0.0, 1.0, 0.01, "%.2f"))
	_row(g, "Interface", _slider("audio", "ui", 0.0, 1.0, 0.01, "%.2f"))
	return sg[0]


func _input(event: InputEvent) -> void:
	if _rebind_action == "" or not visible:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_rebind_action = ""
			_refresh_bindings()
		else:
			Settings.rebind(_rebind_action, event)
			_rebind_action = ""
		get_viewport().set_input_as_handled()


func _refresh_bindings() -> void:
	for action in _rebind_buttons:
		(_rebind_buttons[action] as Button).text = Settings.binding_label(action)


func _on_changed(section: String, key: String) -> void:
	if section == "controls" and key == "bindings":
		_refresh_bindings()
	if section == "graphics" and key == "preset":
		# a preset changes several values: refresh their widgets
		for k in _rows:
			var parts: PackedStringArray = k.split("/")
			var w: Array = _rows[k]
			var v = Settings.get_value(parts[0], parts[1])
			if w[0] is OptionButton:
				(w[0] as OptionButton).selected = maxi((w[1] as Array).find(v), 0)
			elif w[0] is HSlider:
				(w[0] as HSlider).set_value_no_signal(float(v))
				(w[1] as Label).text = String(w[2]) % float(v)
			elif w[0] is CheckBox:
				(w[0] as CheckBox).set_pressed_no_signal(bool(v))
