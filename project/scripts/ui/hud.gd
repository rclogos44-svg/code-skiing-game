class_name HUD
extends CanvasLayer
## In-game overlay: speed / altitude, region banner, trick popups, combo, challenge panel,
## notifications, crash message, spotting reticle, interaction prompt and control hints.

const ALTITUDE_OFFSET := 900.0     # world height 0 m == 900 m above sea level

var skier: Skier
var terrain: TerrainData
var root: Control
var speed_label: Label
var unit_label: Label
var alt_label: Label
var region_label: Label
var trick_box: VBoxContainer
var trick_name: Label
var trick_points: Label
var trick_combo: Label
var combo_label: Label
var challenge_panel: PanelContainer
var challenge_title: Label
var challenge_line1: Label
var challenge_line2: Label
var notif_box: VBoxContainer
var crash_box: VBoxContainer
var crash_reason: Label
var crash_hint: Label
var prompt_label: Label
var hint_label: Label
var reticle: Control
var reticle_progress := 0.0
var reticle_name := ""
var fps_label: Label
var big_center: Label
var _region := -1
var _region_tween: Tween
var _trick_tween: Tween
var _big_tween: Tween
var _hint_time := 0.0
var minimap: MiniMap
var lift_panel: Control
var _lift_info := {}
var _lift_skip := 0.0
var _streaks: ColorRect
var prep_ui: Control
var dev_label: Label
var _label_time := 0.0
var _last_label := ""


func setup(s: Skier, td: TerrainData) -> void:
	skier = s
	terrain = td
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	_build_speed()
	_build_region()
	_build_trick()
	_build_challenge()
	_build_notifications()
	_build_crash()
	_build_prompt()
	_build_reticle()
	_build_misc()
	_streaks = ColorRect.new()
	_streaks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_streaks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_streaks.material = ShaderMaterial.new()
	(_streaks.material as ShaderMaterial).shader = load("res://shaders/speed_lines.gdshader")
	root.add_child(_streaks)
	root.move_child(_streaks, 0)
	lift_panel = Control.new()
	lift_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lift_panel.anchor_left = 0.5
	lift_panel.anchor_right = 0.5
	lift_panel.anchor_top = 1.0
	lift_panel.anchor_bottom = 1.0
	lift_panel.offset_left = -230
	lift_panel.offset_right = 230
	lift_panel.offset_top = -200
	lift_panel.offset_bottom = -110
	lift_panel.draw.connect(_draw_lift_panel)
	root.add_child(lift_panel)
	s.crashed.connect(_on_crashed)
	s.respawned.connect(func(): crash_box.visible = false)
	Game.notify.connect(notify)


func attach_minimap(ch: ChallengeManager) -> void:
	minimap = MiniMap.new()
	minimap.name = "MiniMap"
	root.add_child(minimap)
	minimap.setup(terrain, skier, ch)


## Chairlift status: boarding countdown or ride progress, with the hold-to-skip meter.
func set_lift_status(info: Dictionary, skip_progress: float) -> void:
	if info.is_empty() and _lift_info.is_empty():
		return
	_lift_info = info
	_lift_skip = skip_progress
	lift_panel.queue_redraw()


func _draw_lift_panel() -> void:
	if _lift_info.is_empty():
		return
	var w := lift_panel.size.x
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.12, 0.82)
	sb.set_corner_radius_all(10)
	sb.border_width_left = 4
	sb.border_color = UITheme.ACCENT
	lift_panel.draw_style_box(sb, Rect2(Vector2.ZERO, lift_panel.size))
	var fb := UITheme.font(800)
	var fm := UITheme.font(600)
	lift_panel.draw_string(fb, Vector2(20, 30), String(_lift_info["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, UITheme.TEXT)
	var key := Settings.binding_label("interact")
	if _lift_info["phase"] == "wait":
		var txt := "Stay on the blue mat · chair arrives in %d s" % int(ceil(float(_lift_info["wait"])))
		lift_panel.draw_string(fm, Vector2(20, 56), txt, HORIZONTAL_ALIGNMENT_LEFT, w - 40, 16, UITheme.DIM)
		lift_panel.draw_string(fm, Vector2(20, 78), "%s  cancel" % key, HORIZONTAL_ALIGNMENT_LEFT, w - 40, 14, UITheme.DIM)
		return
	var rem := float(_lift_info["remaining"])
	var t := "%d:%02d to the top" % [int(rem / 60.0), int(rem) % 60]
	var tw := fm.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	lift_panel.draw_string(fm, Vector2(w - 20 - tw, 30), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UITheme.DIM)
	var bar := Rect2(Vector2(20, 44), Vector2(w - 40, 6))
	lift_panel.draw_rect(bar, Color(1, 1, 1, 0.15))
	lift_panel.draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(_lift_info["progress"]), 6)), UITheme.ACCENT)
	var hint := "Hold %s to skip to the top · mouse to look around" % key
	lift_panel.draw_string(fm, Vector2(20, 76), hint, HORIZONTAL_ALIGNMENT_LEFT, w - 40, 14, UITheme.DIM)
	if _lift_skip > 0.0:
		lift_panel.draw_rect(Rect2(Vector2(20, 82), Vector2((w - 40) * clampf(_lift_skip, 0.0, 1.0), 3)), UITheme.GOLD)


func _anchor(c: Control, preset: int, offset := Vector2.ZERO) -> void:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 24)
	c.position += offset


func _build_speed() -> void:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", -8)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	speed_label = UITheme.label("0", 64, UITheme.TEXT, 700, 6)
	unit_label = UITheme.label(" km/h", 22, UITheme.DIM, 600, 4)
	unit_label.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(speed_label)
	row.add_child(unit_label)
	box.add_child(row)
	alt_label = UITheme.label("", 18, UITheme.DIM, 600, 4)
	alt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(alt_label)
	root.add_child(box)
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -320
	box.offset_right = -36
	box.offset_top = -130
	box.offset_bottom = -28
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN


func _build_region() -> void:
	region_label = UITheme.label("", 30, UITheme.TEXT, 600, 6)
	region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	region_label.anchor_left = 0.0
	region_label.anchor_right = 1.0
	region_label.offset_top = 70
	region_label.modulate.a = 0.0
	root.add_child(region_label)


func _build_trick() -> void:
	trick_box = VBoxContainer.new()
	trick_box.alignment = BoxContainer.ALIGNMENT_CENTER
	trick_box.anchor_left = 0.0
	trick_box.anchor_right = 1.0
	trick_box.anchor_top = 0.2
	trick_box.anchor_bottom = 0.2
	trick_box.offset_bottom = 140
	trick_box.add_theme_constant_override("separation", -4)
	trick_name = UITheme.label("", 40, UITheme.TEXT, 800, 8)
	trick_points = UITheme.label("", 30, UITheme.ACCENT, 700, 6)
	trick_combo = UITheme.label("", 22, UITheme.GOLD, 700, 5)
	for l in [trick_name, trick_points, trick_combo]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		trick_box.add_child(l)
	trick_box.modulate.a = 0.0
	trick_box.pivot_offset = Vector2(800, 60)
	root.add_child(trick_box)
	combo_label = UITheme.label("", 24, UITheme.GOLD, 700, 5)
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.anchor_left = 0.0
	combo_label.anchor_right = 1.0
	combo_label.anchor_top = 0.2
	combo_label.offset_top = -40
	root.add_child(combo_label)
	big_center = UITheme.label("", 72, UITheme.TEXT, 800, 10)
	big_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_center.anchor_left = 0.0
	big_center.anchor_right = 1.0
	big_center.anchor_top = 0.38
	big_center.modulate.a = 0.0
	root.add_child(big_center)


func _build_challenge() -> void:
	challenge_panel = PanelContainer.new()
	challenge_panel.position = Vector2(24, 24)
	challenge_panel.custom_minimum_size = Vector2(360, 0)
	var v := VBoxContainer.new()
	challenge_title = UITheme.label("", 22, UITheme.ACCENT, 700)
	challenge_line1 = UITheme.label("", 20, UITheme.TEXT, 600)
	challenge_line2 = UITheme.label("", 17, UITheme.DIM, 500)
	v.add_child(challenge_title)
	v.add_child(challenge_line1)
	v.add_child(challenge_line2)
	challenge_panel.add_child(v)
	challenge_panel.visible = false
	root.add_child(challenge_panel)


func _build_notifications() -> void:
	notif_box = VBoxContainer.new()
	notif_box.anchor_left = 1.0
	notif_box.anchor_right = 1.0
	notif_box.offset_left = -460
	notif_box.offset_right = -24
	notif_box.offset_top = 24
	notif_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	notif_box.add_theme_constant_override("separation", 8)
	root.add_child(notif_box)


func _build_crash() -> void:
	crash_box = VBoxContainer.new()
	crash_box.anchor_left = 0.0
	crash_box.anchor_right = 1.0
	crash_box.anchor_top = 0.55
	crash_reason = UITheme.label("", 36, Color(1.0, 0.55, 0.45), 800, 8)
	crash_hint = UITheme.label("", 20, UITheme.TEXT, 600, 5)
	for l in [crash_reason, crash_hint]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		crash_box.add_child(l)
	crash_box.visible = false
	root.add_child(crash_box)


func _build_prompt() -> void:
	prompt_label = UITheme.label("", 22, UITheme.TEXT, 600, 6)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.anchor_left = 0.0
	prompt_label.anchor_right = 1.0
	prompt_label.anchor_top = 1.0
	prompt_label.anchor_bottom = 1.0
	prompt_label.offset_top = -120
	prompt_label.visible = false
	root.add_child(prompt_label)
	hint_label = UITheme.label("", 16, UITheme.DIM, 500, 4)
	hint_label.anchor_top = 1.0
	hint_label.anchor_bottom = 1.0
	hint_label.offset_left = 28
	hint_label.offset_top = -86
	hint_label.anchor_right = 1.0
	hint_label.offset_right = -330
	hint_label.offset_bottom = -14
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN   # extra lines push up, never off-screen
	root.add_child(hint_label)


func _build_reticle() -> void:
	reticle = Control.new()
	reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.draw.connect(_draw_reticle)
	root.add_child(reticle)


func _build_misc() -> void:
	fps_label = UITheme.label("", 14, UITheme.DIM, 500, 3)
	fps_label.position = Vector2(8, 4)
	root.add_child(fps_label)
	# trick preparation: a small arrow + charge ring low in the middle (clear of the skier and the
	# landing), the trick the arrows resolved to, "at the lip" while it waits for the takeoff
	prep_ui = Control.new()
	prep_ui.anchor_left = 0.5
	prep_ui.anchor_right = 0.5
	prep_ui.anchor_top = 1.0
	prep_ui.anchor_bottom = 1.0
	prep_ui.offset_left = -140
	prep_ui.offset_right = 140
	prep_ui.offset_top = -190
	prep_ui.offset_bottom = -110
	prep_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prep_ui.draw.connect(_draw_prep)
	root.add_child(prep_ui)
	dev_label = UITheme.label("", 13, UITheme.TEXT, 500, 3)
	dev_label.position = Vector2(10, 26)
	dev_label.visible = false
	root.add_child(dev_label)


const ARROW_GLYPH := {Vector2i(1, 0): "→", Vector2i(-1, 0): "←", Vector2i(0, 1): "↑", Vector2i(0, -1): "↓"}


func _draw_prep() -> void:
	if skier == null or skier.mode != Skier.Mode.SKI:
		return
	var c := Vector2(prep_ui.size.x * 0.5, 30.0)
	var f := UITheme.font(700)
	var st := skier.trick_state
	if st == Skier.TrickState.PREPARE:
		var a := clampf(skier._prep_t / 0.12, 0.0, 1.0)
		prep_ui.draw_circle(c, 24.0, Color(0, 0, 0, 0.35 * a))
		prep_ui.draw_arc(c, 24.0, -PI * 0.5, -PI * 0.5 + TAU * skier.charge, 40, Color(UITheme.ACCENT, a), 4.0, true)
		var g: String = ARROW_GLYPH.get(skier.prep_dir, "")
		var w := f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		prep_ui.draw_string(f, c + Vector2(-w * 0.5, 9), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, a))
		if skier.charge >= 0.999:
			prep_ui.draw_arc(c, 28.0, 0.0, TAU, 40, Color(1, 1, 1, 0.5 * a), 2.0, true)
	var lbl := ""
	if st == Skier.TrickState.PENDING:
		lbl = skier.trick_label + "  ·  at the lip"
	elif _label_time > 0.0:
		lbl = skier.trick_label
	if lbl != "":
		var w2 := f.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var p2 := Vector2(prep_ui.size.x * 0.5 - w2 * 0.5, 74)
		prep_ui.draw_string_outline(f, p2, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 5, Color(0, 0, 0, 0.6))
		prep_ui.draw_string(f, p2, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UITheme.TEXT)


func _update_dev() -> void:
	var s := skier
	var body = get_tree().get_first_node_in_group("skier_body")
	var gph := ""
	if body:
		gph = body.grab_phase_name()
	var lines := [
		"DEV  (F3)  ·  slow-mo %s" % ("x%.2f" % Engine.time_scale if Engine.time_scale < 0.99 else "off"),
		"input  %s  prep %s  charge %.2f  pending %s" % [Skier.TrickState.keys()[s.trick_state], ARROW_GLYPH.get(s.prep_dir, "-"), s.charge,
			s.pending_trick.get("label", "-")],
		"trick  %s  %s" % [s.trick_label if s.trick_label != "" else "-", ("%s %s" % [s.off_family, "R" if s.off_dir > 0 else "L"]) if s.off_family != "" else ""],
		"state  %s%s  speed %.1f m/s" % ["AIR" if s.airborne else "ground", (" %.2fs" % s.air_time) if s.airborne else "", s.speed],
		"rotation  spin %.1f rad/s (%.0f deg)  flip %.1f rad/s (%.0f deg)  off-axis %.1f rad/s (%.0f deg, tilt %.0f)" % [s.spin_vel,
			rad_to_deg(s.air_rotation), s.flip_vel, rad_to_deg(s.air_pitch), s.off_rate, rad_to_deg(s.off_angle), s.off_max_tilt],
		"landing  in %.2f s  normal %s" % [s.land_t if s.land_t < 8.0 else -1.0, str(s.land_n.snapped(Vector3(0.01, 0.01, 0.01)))],
		"grab  %s  %s" % [s.grab_name if s.grab_name != "" else "-", gph],
	]
	dev_label.text = "\n".join(lines)


func _draw_reticle() -> void:
	if reticle_progress <= 0.0:
		return
	var c := reticle.size * 0.5
	reticle.draw_arc(c, 34.0, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 3.0, true)
	reticle.draw_arc(c, 34.0, -PI * 0.5, -PI * 0.5 + TAU * reticle_progress, 48, UITheme.ACCENT, 4.0, true)
	var f := UITheme.font(700)
	var txt := "Spotting: " + reticle_name
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	reticle.draw_string_outline(f, c + Vector2(-w * 0.5, 64), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.6))
	reticle.draw_string(f, c + Vector2(-w * 0.5, 64), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UITheme.TEXT)


# ------------------------------------------------------------------ updates
func _process(delta: float) -> void:
	if skier == null:
		return
	speed_label.text = str(int(round(skier.speed_kmh())))
	var p := skier.position
	alt_label.text = "ALT %s m   ·   %d°" % [_thousands(int(p.y + ALTITUDE_OFFSET)), int(round(skier.slope))]
	if crash_box.visible:
		var left := maxf(3.0 - skier.crash_time, 0.0)
		crash_hint.text = "Press %s to respawn%s" % [Settings.binding_label("respawn"), ("   (auto in %.0f)" % ceil(left)) if left > 0.0 else ""]
	if combo_label:
		var tricks := get_tree().get_first_node_in_group("trick_system")
		if tricks and tricks.combo_count > 0:
			combo_label.text = "COMBO  %s  ×%.1f" % [_thousands(tricks.combo_points), tricks.multiplier]
		else:
			combo_label.text = ""
	# speed streaks above ~65 km/h (Settings > Camera > speed effects)
	var fx_on := bool(Settings.get_value("camera", "speed_fx")) and skier.mode == Skier.Mode.SKI and not skier.is_crashed
	var amt := clampf((skier.speed_kmh() - 65.0) / 45.0, 0.0, 1.0) if fx_on else 0.0
	_streaks.visible = amt > 0.01
	if _streaks.visible:
		var sm := _streaks.material as ShaderMaterial
		sm.set_shader_parameter("amount", amt)
		sm.set_shader_parameter("t", Time.get_ticks_msec() * 0.001)
		sm.set_shader_parameter("aspect", root.size.x / maxf(root.size.y, 1.0))
	if minimap:
		notif_box.offset_top = (24.0 + MiniMap.SIZE + 14.0) if minimap.visible else 24.0
	_hint_time += delta
	hint_label.modulate.a = clampf(1.0 - (_hint_time - 25.0) / 3.0, 0.0, 1.0)
	if fps_label.visible != bool(Settings.get_value("graphics", "show_fps")):
		fps_label.visible = bool(Settings.get_value("graphics", "show_fps"))
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	reticle.queue_redraw()
	# the resolved trick's name stays up a moment after the pop
	if skier.trick_label != _last_label:
		_last_label = skier.trick_label
		_label_time = 1.2
	if skier.trick_state == Skier.TrickState.PENDING:
		_label_time = 1.2
	_label_time = maxf(_label_time - delta, 0.0)
	prep_ui.queue_redraw()
	if InputMap.has_action("dev_view") and Input.is_action_just_pressed("dev_view"):
		dev_label.visible = not dev_label.visible
	if dev_label.visible:
		_update_dev()


func show_controls_hint() -> void:
	_hint_time = 0.0
	var b := func(a: String) -> String: return Settings.binding_label(a)
	if skier and skier.mode == Skier.Mode.WALK:
		hint_label.text = "ON FOOT:  %s%s%s%s walk · %s jog · %s hop · %s skis on · %s ride lift · %s map" % [
			b.call("tuck"), b.call("steer_left"), b.call("brake"), b.call("steer_right"), b.call("carve"), b.call("lean_forward"),
			b.call("skis"), b.call("interact"), b.call("map")]
		return
	if skier and skier.mode == Skier.Mode.LIFT:
		hint_label.text = "Mouse: look around · hold %s to skip to the top · %s map" % [b.call("interact"), b.call("map")]
		return
	var u: String = b.call("lean_forward")
	var dn: String = b.call("lean_back")
	var l: String = b.call("lean_left")
	var r: String = b.call("lean_right")
	hint_label.text = ("%s/%s turn · %s push · %s stop · %s/%s grabs (+%s/%s: other grabs) · %s switch · %s top · %s slow-mo · %s dev view\n"
		+ "TRICKS: hold an arrow to load, tap a 2nd to go · %s%s backflip · %s%s front flip · %s%s / %s%s spin · %s+side rodeo · %s+side misty · side+%s cork · side+%s bio · let go alone: ollie") % [
		b.call("steer_left"), b.call("steer_right"), b.call("tuck"), b.call("brake"),
		b.call("grab_left"), b.call("grab_right"), b.call("tuck"), b.call("brake"),
		b.call("switch_stance"), b.call("map"), b.call("slow_mo"), b.call("dev_view"),
		u, dn, dn, u, l, r, r, l, u, dn, dn, u]


func show_region(name: String) -> void:
	region_label.text = name.to_upper()
	if _region_tween:
		_region_tween.kill()
	_region_tween = create_tween()
	_region_tween.tween_property(region_label, "modulate:a", 1.0, 0.6)
	_region_tween.tween_interval(2.5)
	_region_tween.tween_property(region_label, "modulate:a", 0.0, 1.0)


func show_trick(t: Dictionary) -> void:
	trick_name.text = t["name"]
	var pts := "+%s" % _thousands(int(t["points"]))
	if t["quality"] != "OK":
		pts += "   " + t["quality"]
	trick_points.text = pts
	trick_combo.text = ("Combo ×%.1f" % t["multiplier"]) if t["combo_count"] > 1 else ""
	if _trick_tween:
		_trick_tween.kill()
	trick_box.pivot_offset = Vector2(trick_box.size.x * 0.5, 50)
	trick_box.scale = Vector2(1.35, 1.35)
	trick_box.modulate.a = 1.0
	_trick_tween = create_tween()
	_trick_tween.tween_property(trick_box, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_trick_tween.tween_interval(1.6)
	_trick_tween.tween_property(trick_box, "modulate:a", 0.0, 0.6)


func show_banked(total: int, count: int) -> void:
	big_message("+%s" % _thousands(total), UITheme.GOLD, 1.4, 54)
	if count > 1:
		notify("%d-trick combo banked: %s pts" % [count, _thousands(total)], "score")


func show_combo_lost(points: int) -> void:
	notify("Combo lost (%s pts)" % _thousands(points), "warning")


func big_message(text: String, color := UITheme.TEXT, duration := 1.2, size := 72) -> void:
	big_center.text = text
	big_center.add_theme_color_override("font_color", color)
	big_center.add_theme_font_size_override("font_size", size)
	if _big_tween:
		_big_tween.kill()
	big_center.modulate.a = 1.0
	_big_tween = create_tween()
	_big_tween.tween_interval(duration)
	_big_tween.tween_property(big_center, "modulate:a", 0.0, 0.4)


func notify(text: String, kind := "info") -> void:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.12, 0.8)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.border_width_left = 4
	sb.border_color = {"discovery": UITheme.GOLD, "warning": Color(1, 0.45, 0.35), "score": UITheme.ACCENT}.get(kind, Color(0.5, 0.75, 1.0))
	pc.add_theme_stylebox_override("panel", sb)
	var l := UITheme.label(text, 18, UITheme.TEXT, 600)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	pc.add_child(l)
	notif_box.add_child(pc)
	pc.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(pc, "modulate:a", 1.0, 0.25)
	tw.tween_interval(4.5)
	tw.tween_property(pc, "modulate:a", 0.0, 0.6)
	tw.tween_callback(pc.queue_free)
	while notif_box.get_child_count() > 5:
		notif_box.get_child(0).queue_free()
		break


func set_challenge(title: String, line1: String, line2 := "") -> void:
	challenge_panel.visible = title != ""
	challenge_title.text = title
	challenge_line1.text = line1
	challenge_line2.text = line2
	challenge_line2.visible = line2 != ""


func set_prompt(text: String) -> void:
	prompt_label.visible = text != ""
	prompt_label.text = text


func set_spotting(progress: float, name: String) -> void:
	reticle_progress = progress
	reticle_name = name


func _on_crashed(reason: String, _v: Vector3) -> void:
	crash_reason.text = reason.to_upper()
	crash_box.visible = true


static func _thousands(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out
