class_name Menus
extends Control
## Main menu, pause menu, free-ride drop zone picker, challenge list and confirmation dialogs.
## Emits high-level requests that main.gd turns into game state changes.

signal request(action: String, arg: String)

var terrain: TerrainData
var main_panel: Control
var pause_panel: Control
var list_panel: PanelContainer
var list_box: VBoxContainer
var list_title: Label
var confirm_panel: PanelContainer
var confirm_label: Label
var _confirm_action := ""
var settings: SettingsMenu
var continue_btn: Button
var challenge_status: Label
var version_label: Label
var _stack: Array[Control] = []


func setup(td: TerrainData) -> void:
	terrain = td
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_main()
	_build_pause()
	_build_list()
	_build_confirm()
	settings = SettingsMenu.new()
	settings.visible = false
	settings.closed.connect(back)
	_centered().add_child(settings)
	hide_all()


## Full-screen CenterContainer so dialogs stay centred whatever their final size.
func _centered() -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


func _button(text: String, cb: Callable, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 52)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func():
		Sfx.ui()
		cb.call())
	b.mouse_entered.connect(func(): Sfx.ui("ui_hover"))
	parent.add_child(b)
	return b


func _build_main() -> void:
	main_panel = Control.new()
	main_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(main_panel)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.04, 0.08, 0.85))
	g.set_color(1, Color(0.02, 0.04, 0.08, 0.0))
	grad.gradient = g
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(0.7, 0)
	var tr := TextureRect.new()
	tr.texture = grad
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_panel.add_child(tr)
	var v := VBoxContainer.new()
	v.position = Vector2(90, 110)
	v.add_theme_constant_override("separation", 10)
	main_panel.add_child(v)
	var title := UITheme.label("SUMMIT", 112, UITheme.TEXT, 900, 10)
	v.add_child(title)
	var sub := UITheme.label("PARK SKIING", 22, UITheme.ACCENT, 700, 4)
	v.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	v.add_child(spacer)
	var parks: Array = terrain.layout.get("parks", [])
	var pg := GridContainer.new()          # parks two to a row so the menu fits short windows
	pg.columns = 2
	pg.add_theme_constant_override("h_separation", 10)
	pg.add_theme_constant_override("v_separation", 10)
	v.add_child(pg)
	for i in parks.size():
		var idx := str(i)
		_button(String(parks[i]["name"]), func(): request.emit("park", idx), pg)
	_button("Settings", func(): show_settings(), v)
	if not Settings.is_web():
		_button("Quit", func(): request.emit("quit", ""), v)
	challenge_status = UITheme.label("", 17, UITheme.DIM, 500, 3)
	v.add_child(challenge_status)
	version_label = UITheme.label("v%s  ·  Built with Godot Engine" % ProjectSettings.get_setting("application/config/version"), 14, UITheme.DIM, 500, 3)
	version_label.anchor_top = 1.0
	version_label.anchor_bottom = 1.0
	version_label.offset_left = 24
	version_label.offset_top = -36
	main_panel.add_child(version_label)


func _build_pause() -> void:
	pause_panel = Control.new()
	pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(pause_panel)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.07, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(shade)
	var v := VBoxContainer.new()
	v.position = Vector2(90, 140)
	v.add_theme_constant_override("separation", 10)
	pause_panel.add_child(v)
	v.add_child(UITheme.label("PAUSED", 56, UITheme.TEXT, 900, 6))
	_button("Resume", func(): request.emit("resume", ""), v)
	_button("Respawn", func(): request.emit("respawn", ""), v).name = "Respawn"
	_button("Restart Challenge", func(): request.emit("restart_challenge", ""), v).name = "Restart"
	_button("Abandon Challenge", func(): request.emit("abandon_challenge", ""), v).name = "Abandon"
	_button("Back to the Top", func(): request.emit("park_top", ""), v)
	_button("Choose Park", func(): show_parks(), v)
	_button("Settings", func(): show_settings(), v)
	_button("Main Menu", func(): request.emit("main_menu", ""), v)
	if not Settings.is_web():
		_button("Quit Game", func(): request.emit("quit", ""), v)
	pause_panel.set_meta("box", v)


func _build_list() -> void:
	list_panel = PanelContainer.new()
	list_panel.custom_minimum_size = Vector2(760, 620)
	_centered().add_child(list_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	list_panel.add_child(v)
	list_title = UITheme.label("", 32, UITheme.TEXT, 800)
	v.add_child(list_title)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	sc.add_child(list_box)
	_button("Back", func(): back(), v)


func _build_confirm() -> void:
	confirm_panel = PanelContainer.new()
	confirm_panel.custom_minimum_size = Vector2(560, 200)
	_centered().add_child(confirm_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	confirm_panel.add_child(v)
	confirm_label = UITheme.label("", 22, UITheme.TEXT, 600)
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_label.custom_minimum_size = Vector2(500, 0)
	v.add_child(confirm_label)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	var yes := _button("Yes", func():
		var a := _confirm_action
		back()
		request.emit(a, ""), h)
	yes.custom_minimum_size = Vector2(200, 48)
	var no := _button("Cancel", func(): back(), h)
	no.custom_minimum_size = Vector2(200, 48)


# ------------------------------------------------------------------ navigation
func hide_all() -> void:
	for c in [main_panel, pause_panel, list_panel, confirm_panel, settings]:
		c.visible = false
	_stack.clear()
	visible = false


func _push(c: Control) -> void:
	for s in _stack:
		s.visible = false
	_stack.append(c)
	c.visible = true
	visible = true
	_focus_first(c)


func _focus_first(c: Control) -> void:
	var b := _find_button(c)
	if b:
		b.call_deferred("grab_focus")


func _find_button(n: Node) -> Button:
	for ch in n.get_children():
		if ch is Button and (ch as Button).visible and not (ch as Button).disabled:
			return ch
		var r := _find_button(ch)
		if r:
			return r
	return null


func back() -> bool:
	if _stack.size() <= 1:
		return false
	var top: Control = _stack.pop_back()
	top.visible = false
	var prev: Control = _stack[_stack.size() - 1]
	prev.visible = true
	if prev == main_panel or prev == pause_panel:
		refresh()
	_focus_first(prev)
	return true


func show_main() -> void:
	hide_all()
	refresh()
	_push(main_panel)


func show_pause(challenge_active: bool) -> void:
	hide_all()
	var box: VBoxContainer = pause_panel.get_meta("box")
	box.get_node("Restart").visible = challenge_active
	box.get_node("Abandon").visible = challenge_active
	box.get_node("Respawn").visible = not challenge_active
	_push(pause_panel)


func is_open() -> bool:
	return visible


func refresh() -> void:
	if continue_btn == null:
		return
	continue_btn.disabled = not Game.has_save()
	var c := Game.completion_counts()
	if Game.has_save():
		challenge_status.text = "Career: %d/%d drop zones · %d/%d viewpoints · %d/%d challenges" % [c["drops"], c["drops_total"], c["viewpoints"], c["viewpoints_total"], c["challenges"], c["challenges_total"]]
	else:
		challenge_status.text = ""


func _maybe_new_game() -> void:
	if Game.has_save():
		_confirm("Start a new career? Your discovered locations and challenge medals will be reset.", "new_game")
	else:
		request.emit("new_game", "")


func _confirm(text: String, action: String) -> void:
	confirm_label.text = text
	_confirm_action = action
	_push(confirm_panel)


func show_settings() -> void:
	_push(settings)


func show_parks() -> void:
	list_title.text = "CHOOSE A PARK"
	for ch in list_box.get_children():
		ch.queue_free()
	var parks: Array = terrain.layout.get("parks", [])
	for i in parks.size():
		var idx := str(i)
		var pk: Dictionary = parks[i]
		var b := _button("%s   ·   %d jumps, %d rails & boxes" % [pk["name"], pk["kickers"].size(), pk["rails"].size()],
			func(): request.emit("park", idx), list_box)
		b.custom_minimum_size = Vector2(680, 46)
	_push(list_panel)


func show_drop_list(freeride: bool) -> void:
	list_title.text = "FREE RIDE — CHOOSE A DROP ZONE" if freeride else "TRAVEL TO A DROP ZONE"
	for ch in list_box.get_children():
		ch.queue_free()
	var by_region := {}
	for d in terrain.layout.get("drop_zones", []):
		by_region[int(d["region"])] = by_region.get(int(d["region"]), []) + [d]
	for r in terrain.layout.get("regions", []):
		var list: Array = by_region.get(int(r["id"]), [])
		if list.is_empty():
			continue
		list_box.add_child(UITheme.label(r["name"].to_upper(), 18, UITheme.ACCENT, 700))
		for d in list:
			var name: String = d["name"]
			var unlocked := freeride or Game.is_drop_unlocked(name)
			var alt := int(float(d["y"]) + HUD.ALTITUDE_OFFSET)
			var b := _button("%s   ·   %d m" % [name, alt] if unlocked else "???   (undiscovered — spot it from afar)", func():
				request.emit("freeride_drop" if freeride else "travel_drop", name), list_box)
			b.disabled = not unlocked
			b.custom_minimum_size = Vector2(680, 46)
	_push(list_panel)


func show_challenges() -> void:
	list_title.text = "CHALLENGES"
	for ch in list_box.get_children():
		ch.queue_free()
	var types := {"race": "RACES", "trick_score": "FREESTYLE", "trick_specific": "FREESTYLE", "trick_combo": "FREESTYLE", "extreme": "EXTREME"}
	var cm := ChallengeManager.new()
	cm.terrain = terrain
	for group in ["RACES", "FREESTYLE", "EXTREME"]:
		var added := false
		for c in terrain.layout.get("challenges", []):
			if types.get(c["type"], "") != group:
				continue
			if not added:
				list_box.add_child(UITheme.label(group, 18, UITheme.ACCENT, 700))
				added = true
			var res := Game.challenge_result(c["id"])
			var drop: String = c.get("drop", "")
			var available := drop == "" or Game.is_drop_unlocked(drop) or not Game.has_save()
			var status := ""
			if res.get("completed", false):
				status = "   ✔ " + UITheme.medal_name(int(res.get("medal", 0)))
				if res.has("time"):
					status += " " + UITheme.format_time(res["time"])
				elif res.has("score"):
					status += " " + HUD._thousands(int(res["score"]))
			var id: String = c["id"]
			var txt := "%s — %s%s" % [c["name"], cm.describe(c), status]
			if not available:
				txt = "%s — discover %s to unlock" % [c["name"], drop]
			var b := _button(txt, func(): request.emit("challenge", id), list_box)
			b.disabled = not available
			b.custom_minimum_size = Vector2(680, 46)
			b.add_theme_font_size_override("font_size", 17)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if res.get("completed", false):
				b.add_theme_color_override("font_color", UITheme.medal_color(int(res.get("medal", 0))).lightened(0.3))
	cm.free()
	_push(list_panel)
