class_name MapScreen
extends Control
## Full-screen trail map: painted relief (world/map.png, see build/map_render.py) with pistes,
## lifts, named peaks, discovered drop zones (click to travel), viewpoints, challenges, terrain
## features, landmarks and the player.  Scroll to zoom, drag to pan, hover for details.
## A side panel shows progress and the legend.

signal teleport_drop(name: String)
signal start_challenge(id: String)
signal closed

const DIFF_COLORS := {"green": Color(0.15, 0.68, 0.3), "blue": Color(0.12, 0.4, 0.95), "red": Color(0.9, 0.14, 0.12), "black": Color(0.04, 0.04, 0.05)}
const DIFF_NAMES := {"green": "Easy", "blue": "Intermediate", "red": "Advanced", "black": "Expert"}
const INK := Color(0.06, 0.1, 0.19)
const HALO := Color(1.0, 1.0, 1.0, 0.82)
const CLIFF_COL := Color(0.5, 0.13, 0.08)
const LIP_COL := Color(1.0, 0.55, 0.12)
const GULLY_COL := Color(0.42, 0.27, 0.78)
const TRAIL_COL := Color(0.08, 0.4, 0.22)
const VIEW_COL := Color(0.3, 0.75, 1.0)
const LIFT_COL := Color(0.1, 0.1, 0.12)
const PLAYER_COL := Color(1.0, 0.2, 0.14)
const ROUTE_COL := Color(1.0, 0.8, 0.15)
const SHADOW := Color(0.02, 0.03, 0.06, 0.9)
const LANDMARK_KIND := {"summit_cross": "Summit cross", "hut": "Mountain hut", "weather_station": "Weather station", "ruin": "Cabin ruin"}

var terrain: TerrainData
var skier: Skier
var tex: Texture2D
var map_rect := Rect2()          # map image rect in view coordinates
var _view: Control               # clipped map viewport (handles input)
var _image: TextureRect
var _overlay: Control
var _side: Control
var _zoom := 1.0
var _center := Vector2(0.5, 0.5) # map uv shown at the centre of the view
var _hover := {}
var _targets: Array = []
var _labels: Array = []
var _time := 0.0
var _region_font: FontVariation
var _counts := {}


func setup(td: TerrainData, s: Skier) -> void:
	terrain = td
	skier = s
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	tex = load("res://world/map.png")
	_region_font = FontVariation.new()
	_region_font.base_font = UITheme.font(800)
	_region_font.spacing_glyph = 3
	_view = Control.new()
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.mouse_default_cursor_shape = Control.CURSOR_DRAG
	add_child(_view)
	_image = TextureRect.new()
	_image.texture = tex
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_SCALE
	_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_image)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	_view.gui_input.connect(_view_input)
	_view.mouse_exited.connect(func():
		_hover = {}
		_overlay.queue_redraw())
	_side = Control.new()
	_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_side)
	_side.draw.connect(_draw_side)
	resized.connect(_layout)


func open() -> void:
	visible = true
	_zoom = 1.0
	_center = Vector2(0.5, 0.5)
	_hover = {}
	_counts = Game.completion_counts()
	_layout()


func _process(delta: float) -> void:
	if visible:
		_time += delta
		_overlay.queue_redraw()


# ------------------------------------------------------------------ layout & navigation
func _layout() -> void:
	if _view == null:
		return
	var vs := get_viewport_rect().size
	if size.x < vs.x * 0.5:
		size = vs
	vs = size
	var wide := vs.x >= 980.0
	var side_w := clampf(vs.x * 0.25, 280.0, 340.0) if wide else 0.0
	var top := 66.0
	var bottom := 22.0 if wide else 64.0
	_view.position = Vector2(22, top)
	_view.size = Vector2(vs.x - 44.0 - (side_w + 18.0 if wide else 0.0), vs.y - top - bottom)
	_overlay.size = _view.size
	_side.visible = wide
	_side.position = Vector2(vs.x - side_w - 22.0, top)
	_side.size = Vector2(side_w, vs.y - top - bottom)
	_update_rect()
	queue_redraw()
	_side.queue_redraw()


func _base_size() -> float:
	return minf(_view.size.x, _view.size.y) - 24.0


func _update_rect() -> void:
	var s := _base_size() * _zoom
	# keep the map covering the view once it is larger than it; centred otherwise
	for axis in 2:
		var half := _view.size[axis] * 0.5 / s
		_center[axis] = clampf(_center[axis], half, 1.0 - half) if half < 0.5 else 0.5
	map_rect = Rect2(_view.size * 0.5 - _center * s, Vector2(s, s))
	_image.position = map_rect.position
	_image.size = map_rect.size
	_overlay.queue_redraw()


func _zoom_at(p: Vector2, f: float) -> void:
	var uv := (p - map_rect.position) / map_rect.size
	_zoom = clampf(_zoom * f, 1.0, 6.0)
	var s := _base_size() * _zoom
	_center = uv - (p - _view.size * 0.5) / s
	_update_rect()


func _view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.2)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.2)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				set_meta("press", mb.position)
				set_meta("dragged", false)
			elif not get_meta("dragged", false):
				if not _hover.is_empty() and _hover["type"] in ["drop", "challenge", "waypoint"]:
					_activate(_hover)
				else:
					# click anywhere else on the map: set a waypoint there
					var uv := (mb.position - map_rect.position) / map_rect.size
					if uv.x > 0.0 and uv.y > 0.0 and uv.x < 1.0 and uv.y < 1.0:
						Game.waypoint = uv * terrain.world
						Sfx.ui("ui_hover")
						_overlay.queue_redraw()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask != 0:
			if mm.position.distance_to(get_meta("press", mm.position)) > 4.0 or mm.button_mask != MOUSE_BUTTON_MASK_LEFT:
				set_meta("dragged", true)
			if get_meta("dragged", false):
				_center -= mm.relative / map_rect.size
				_update_rect()
		_overlay.queue_redraw()
	elif event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		_zoom_at(g.position, g.factor)
	elif event is InputEventPanGesture:
		_center += (event as InputEventPanGesture).delta * 8.0 / map_rect.size
		_update_rect()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	var k := (event as InputEventKey).keycode
	var c := _view.size * 0.5
	match k:
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			_zoom_at(c, 1.25)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom_at(c, 0.8)
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			var d := Vector2(float(k == KEY_RIGHT) - float(k == KEY_LEFT), float(k == KEY_DOWN) - float(k == KEY_UP))
			_center += d * 60.0 / map_rect.size
			_update_rect()
		_:
			return
	get_viewport().set_input_as_handled()


func _activate(h: Dictionary) -> void:
	match String(h["type"]):
		"drop":
			Sfx.ui()
			teleport_drop.emit(h["name"])
		"challenge":
			if h.get("available", false):
				Sfx.ui()
				start_challenge.emit(h["id"])
		"waypoint":
			Game.waypoint = Vector2.INF
			Sfx.ui("ui_hover")
			_overlay.queue_redraw()


# ------------------------------------------------------------------ helpers
func _w2m(x: float, z: float) -> Vector2:
	return map_rect.position + Vector2(x, z) / terrain.world * map_rect.size


func _px_per_m() -> float:
	return map_rect.size.x / terrain.world


func _target(p: Vector2, r: float, data: Dictionary) -> void:
	data["pos"] = p
	data["r"] = r
	_targets.append(data)


## Queues a label; labels are drawn afterwards by priority, skipping any that would overlap.
func _label(text: String, anchor: Vector2, fsize: int, col: Color, pri: float, align := "right", pill := Color(0, 0, 0, 0), font: Font = null) -> void:
	var f: Font = font if font else UITheme.font(700)
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
	var pos := anchor + Vector2(11, fsize * 0.36)
	if align == "center":
		pos = anchor + Vector2(-sz.x * 0.5, fsize * 0.36)
	elif align == "below":
		pos = anchor + Vector2(-sz.x * 0.5, fsize + 8.0)
	var rect := Rect2(pos - Vector2(0, fsize * 0.8), Vector2(sz.x, fsize * 1.0)).grow(3.0 if pill.a > 0.0 else 1.5)
	_labels.append({"text": text, "pos": pos, "size": fsize, "col": col, "pri": pri, "rect": rect, "pill": pill, "font": f})


func _flush_labels(ci: CanvasItem) -> void:
	_labels.sort_custom(func(a, b): return a["pri"] > b["pri"])
	var placed: Array[Rect2] = []
	for l in _labels:
		var r: Rect2 = l["rect"]
		var free := true
		for q in placed:
			if q.intersects(r):
				free = false
				break
		if not free:
			continue
		placed.append(r)
		var f: Font = l["font"]
		if l["pill"].a > 0.0:
			var sb := StyleBoxFlat.new()
			sb.bg_color = l["pill"]
			sb.set_corner_radius_all(int(r.size.y * 0.5))
			ci.draw_style_box(sb, r.grow_individual(4, 1, 4, 1))
			ci.draw_string(f, l["pos"], l["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, l["size"], l["col"])
		else:
			ci.draw_string_outline(f, l["pos"], l["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, l["size"], 4, HALO)
			ci.draw_string(f, l["pos"], l["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, l["size"], l["col"])


func _dashed(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float, dash: float, gap: float) -> void:
	var on := true
	var left := dash
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var t := 0.0
		while t < seg:
			var step := minf(left, seg - t)
			if on:
				ci.draw_line(a.lerp(b, t / seg), a.lerp(b, (t + step) / seg), col, w, true)
			t += step
			left -= step
			if left <= 0.0:
				on = not on
				left = dash if on else gap


func _path_pts(path: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for q in path:
		pts.append(_w2m(q[0], q[1]))
	return pts


func _elev(x: float, z: float) -> String:
	return "%s m" % _thousands(int(round(terrain.height(x, z))))


func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _dist(x: float, z: float) -> String:
	if skier == null:
		return ""
	var d := Vector2(x - skier.position.x, z - skier.position.z).length()
	return "%.1f km away" % (d / 1000.0) if d >= 1000.0 else "%d m away" % int(round(d / 10.0) * 10.0)


# ------------------------------------------------------------------ symbols (shared with the legend)
func _diamond(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
	ci.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	ci.draw_polyline(pts, SHADOW, 1.6, true)


func _disk(ci: CanvasItem, p: Vector2, r: float, fill: Color) -> void:
	ci.draw_circle(p, r + 1.2, Color(1, 1, 1, 0.9))
	ci.draw_circle(p, r, fill)


func _binoculars(ci: CanvasItem, p: Vector2, found: bool) -> void:
	var col := VIEW_COL if found else Color(0.75, 0.82, 0.9)
	_disk(ci, p, 7.5, SHADOW if found else Color(0.25, 0.3, 0.38, 0.75))
	ci.draw_circle(p + Vector2(-2.6, 1.2), 2.5, col)
	ci.draw_circle(p + Vector2(2.6, 1.2), 2.5, col)
	ci.draw_rect(Rect2(p + Vector2(-3.6, -3.4), Vector2(2.2, 3.4)), col)
	ci.draw_rect(Rect2(p + Vector2(1.4, -3.4), Vector2(2.2, 3.4)), col)


func _flag(ci: CanvasItem, p: Vector2, col: Color) -> void:
	_disk(ci, p, 8.0, SHADOW)
	ci.draw_line(p + Vector2(-3, 5.5), p + Vector2(-3, -5.5), col, 1.6)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-2.4, -5.5), p + Vector2(5, -3.2), p + Vector2(-2.4, -0.8)]), col)


func _star(ci: CanvasItem, p: Vector2, col: Color) -> void:
	_disk(ci, p, 8.0, SHADOW)
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + i * PI / 5.0
		pts.append(p + Vector2(cos(a), sin(a)) * (5.6 if i % 2 == 0 else 2.4))
	ci.draw_colored_polygon(pts, col)


func _bolt(ci: CanvasItem, p: Vector2, col: Color) -> void:
	_disk(ci, p, 8.0, SHADOW)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(1.5, -6), p + Vector2(-3.5, 1), p + Vector2(-0.2, 1),
		p + Vector2(-1.5, 6), p + Vector2(3.5, -1), p + Vector2(0.2, -1)]), col)


func _challenge_icon(ci: CanvasItem, p: Vector2, type: String, col: Color) -> void:
	if type == "race":
		_flag(ci, p, col)
	elif type == "extreme":
		_bolt(ci, p, col)
	else:
		_star(ci, p, col)


func _peak(ci: CanvasItem, p: Vector2) -> void:
	var tri := PackedVector2Array([p + Vector2(0, -6.5), p + Vector2(6, 4.5), p + Vector2(-6, 4.5)])
	ci.draw_colored_polygon(tri, INK)
	tri.append(tri[0])
	ci.draw_polyline(tri, Color(1, 1, 1, 0.9), 1.4, true)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6.5), p + Vector2(2.4, -2.1), p + Vector2(0, -1.0), p + Vector2(-2.4, -2.1)]), Color(1, 1, 1, 0.95))


func _cliff_symbol(ci: CanvasItem, a: Vector2, b: Vector2, down: Vector2) -> void:
	ci.draw_line(a, b, Color(1, 1, 1, 0.7), 5.0, true)
	ci.draw_line(a, b, CLIFF_COL, 3.0, true)
	var along := (b - a).normalized()
	var n := maxi(3, int(a.distance_to(b) / 6.0))
	for i in n:
		var base := a.lerp(b, (i + 0.5) / n)
		ci.draw_colored_polygon(PackedVector2Array([base - along * 2.0, base + along * 2.0, base + down * 5.5]), CLIFF_COL)


func _lip_symbol(ci: CanvasItem, p: Vector2, dir: Vector2) -> void:
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([p + dir * 6.5, p - dir * 4.5 + side * 5.5, p - dir * 1.5, p - dir * 4.5 - side * 5.5])
	ci.draw_colored_polygon(pts, LIP_COL)
	pts.append(pts[0])
	ci.draw_polyline(pts, SHADOW, 1.3, true)


func _moguls_symbol(ci: CanvasItem, p: Vector2) -> void:
	_disk(ci, p, 8.0, Color(0.95, 0.97, 1.0))
	for i in 3:
		var c := p + Vector2(-4.0 + i * 4.0, 1.5)
		ci.draw_arc(c, 2.2, PI, TAU, 8, INK, 1.6, true)


func _landmark(ci: CanvasItem, p: Vector2, type: String) -> void:
	_disk(ci, p, 8.5, Color(0.98, 0.95, 0.88))
	ci.draw_arc(p, 8.5, 0, TAU, 20, Color(0.45, 0.28, 0.15), 1.4, true)
	var c := Color(0.45, 0.25, 0.12)
	match type:
		"summit_cross":
			ci.draw_line(p + Vector2(0, -5.5), p + Vector2(0, 5.5), c, 2.0)
			ci.draw_line(p + Vector2(-3.5, -2.2), p + Vector2(3.5, -2.2), c, 2.0)
		"hut":
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-5, 0), p + Vector2(0, -5), p + Vector2(5, 0)]), Color(0.75, 0.18, 0.12))
			ci.draw_rect(Rect2(p + Vector2(-3.5, 0), Vector2(7, 4.5)), c)
		"weather_station":
			ci.draw_line(p + Vector2(0, 5.5), p + Vector2(0, -5.5), c, 1.6)
			ci.draw_line(p + Vector2(-3.5, -4.5), p + Vector2(3.5, -4.5), c, 1.6)
			ci.draw_circle(p + Vector2(-3.5, -4.5), 1.3, Color(0.85, 0.15, 0.1))
			ci.draw_circle(p + Vector2(3.5, -4.5), 1.3, Color(0.85, 0.15, 0.1))
			ci.draw_rect(Rect2(p + Vector2(-2.5, 2), Vector2(5, 3.5)), c)
		_:
			ci.draw_polyline(PackedVector2Array([p + Vector2(-5, 4.5), p + Vector2(-5, -1), p + Vector2(-1.5, -4.5), p + Vector2(0.5, -2.5)]), c, 1.6)
			ci.draw_polyline(PackedVector2Array([p + Vector2(2, -1.5), p + Vector2(5, -1), p + Vector2(5, 4.5)]), c, 1.6)
			ci.draw_line(p + Vector2(-5, 4.5), p + Vector2(5, 4.5), c, 1.6)


func _lift_line(ci: CanvasItem, a: Vector2, b: Vector2) -> void:
	ci.draw_line(a, b, Color(1, 1, 1, 0.75), 4.5, true)
	ci.draw_line(a, b, LIFT_COL, 2.2, true)
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x)
	var n := int(a.distance_to(b) / 22.0)
	for i in range(1, n):
		var q := a.lerp(b, float(i) / n)
		ci.draw_line(q - side * 3.5, q + side * 3.5, LIFT_COL, 1.6, true)
	for q in [a, b]:
		ci.draw_rect(Rect2(q - Vector2(4, 4), Vector2(8, 8)), LIFT_COL)
		ci.draw_rect(Rect2(q - Vector2(4, 4), Vector2(8, 8)), Color(1, 1, 1, 0.9), false, 1.2)


# ------------------------------------------------------------------ map overlay
func _draw_overlay() -> void:
	if terrain == null:
		return
	var ci := _overlay
	_labels.clear()
	_targets.clear()
	var k := _px_per_m()
	var z := _zoom
	var spots_all := Game.mode == "freeride"
	# hovered race: show its route under everything else
	if _hover.get("type", "") == "challenge" and _hover.has("path"):
		var rp := _path_pts(_hover["path"])
		ci.draw_polyline(rp, Color(0, 0, 0, 0.35), 6.0, true)
		_dashed(ci, rp, ROUTE_COL, 3.5, 10.0, 6.0)
	# pistes: white casing + difficulty colour, names when zoomed in
	for pi in terrain.layout.get("pistes", []):
		var pts := _path_pts(pi["pts"])
		var col: Color = DIFF_COLORS.get(pi["difficulty"], Color.WHITE)
		var w := clampf(float(pi["width"]) * k * 0.55, 2.5, 9.0)
		ci.draw_polyline(pts, Color(1, 1, 1, 0.85), w + 2.5, true)
		ci.draw_polyline(pts, col, w, true)
		var mid: Array = pi["pts"][int(pi["pts"].size() * 0.45)]
		var mp := _w2m(mid[0], mid[1])
		_target(mp, 9.0, {"type": "piste", "name": pi["name"], "sub": "%s piste" % DIFF_NAMES.get(pi["difficulty"], ""), "x": mid[0], "z": mid[1]})
		if z >= 1.5:
			_label(pi["name"], mp, 12, col.darkened(0.15) if pi["difficulty"] != "black" else INK, 30.0)
	# glade trails and halfpipe gullies
	for f in terrain.layout.get("features", []):
		var ft := String(f["type"])
		if ft != "trail" and ft != "gully":
			continue
		if not (spots_all or Game.spot_found(f["name"])):
			continue
		var pts := _path_pts(f["path"])
		if ft == "trail":
			_dashed(ci, pts, Color(1, 1, 1, 0.8), 4.5, 5.0, 4.0)
			_dashed(ci, pts, TRAIL_COL, 2.5, 5.0, 4.0)
		else:
			ci.draw_polyline(pts, Color(1, 1, 1, 0.7), maxf(26.0 * k, 3.0) + 3.0, true)
			ci.draw_polyline(pts, GULLY_COL, maxf(26.0 * k, 3.0), true)
		var mp := pts[int(pts.size() * 0.5)]
		_target(mp, 9.0, {"type": "feature", "f": f})
		_label(f["name"], mp, 12, TRAIL_COL if ft == "trail" else GULLY_COL.darkened(0.25), 42.0)
	# lifts
	for lf in terrain.layout.get("lifts", []):
		var a := _w2m(lf["bottom"][0], lf["bottom"][1])
		var b := _w2m(lf["top"][0], lf["top"][1])
		_lift_line(ci, a, b)
		var mid := a.lerp(b, 0.5)
		_target(mid, 9.0, {"type": "lift", "lift": lf})
		if z >= 1.3:
			_label(lf["name"], mid, 12, INK, 35.0)
	# region names
	for r in terrain.layout.get("regions", []):
		var p := _w2m(r["x"], r["z"])
		_label(String(r["name"]).to_upper(), p, 16 if z < 2.0 else 20, Color(0.1, 0.2, 0.36, 0.85), 50.0, "center", Color(0, 0, 0, 0), _region_font)
	# terrain features (point symbols)
	for f in terrain.layout.get("features", []):
		var ft := String(f["type"])
		if ft == "trail" or ft == "gully":
			continue
		if not (spots_all or Game.spot_found(f["name"])):
			continue
		var p := _w2m(f["x"], f["z"])
		var dir := Vector2(f.get("dx", 0.0), f.get("dz", 1.0)).normalized()
		match ft:
			"cliff":
				var half := maxf(float(f["width"]) * 0.5 * k, 7.0)
				var side := Vector2(-dir.y, dir.x)
				_cliff_symbol(ci, p - side * half, p + side * half, dir)
				if z >= 1.6:
					_label("%s  %d m" % [f["name"], int(round(float(f["drop"])))], p + dir * 6.0, 11, CLIFF_COL, 40.0)
			"lip":
				_lip_symbol(ci, p, dir)
				if z >= 1.6:
					_label(f["name"], p, 11, Color(0.6, 0.3, 0.05), 40.0)
			"moguls":
				_moguls_symbol(ci, p)
				if z >= 1.3:
					_label(f["name"], p, 12, INK, 41.0)
			"lake":
				_label(f["name"], p, 13, Color(0.12, 0.33, 0.55), 56.0, "center", Color(0, 0, 0, 0), UITheme.font(600))
		_target(p, 9.0, {"type": "feature", "f": f})
	# peaks
	for pk in terrain.layout.get("peaks", []):
		var p := _w2m(pk["x"], pk["z"])
		_peak(ci, p)
		_target(p, 8.0, {"type": "peak", "peak": pk})
		_label("%s  %s m" % [pk["name"], _thousands(int(pk["y"]))], p, 12, INK, 70.0)
	# landmarks
	for m in terrain.layout.get("landmarks", []):
		if not (spots_all or Game.spot_found(m["name"])):
			continue
		var p := _w2m(m["x"], m["z"]) + Vector2(0, 12)
		_landmark(ci, p, m["type"])
		_target(p, 10.0, {"type": "landmark", "m": m})
		_label(m["name"], p, 12, Color(0.4, 0.2, 0.08), 55.0)
	# viewpoints
	for v in terrain.layout.get("viewpoints", []):
		var p := _w2m(v["x"], v["z"])
		var found: bool = v["name"] in Game.save["viewpoints"]
		_binoculars(ci, p, found)
		_target(p, 10.0, {"type": "viewpoint", "v": v, "found": found})
		if found:
			_label(v["name"], p, 12, Color(0.05, 0.35, 0.6), 52.0)
	# challenges (beside their drop zone)
	for c in terrain.layout.get("challenges", []):
		var pos := _challenge_pos(c)
		if pos == Vector2.INF:
			continue
		var avail := _challenge_available(c)
		var res := Game.challenge_result(c["id"])
		var col := UITheme.medal_color(int(res.get("medal", 0))) if res.get("completed", false) else Color(0.97, 0.97, 1.0)
		if not avail:
			col = Color(0.55, 0.6, 0.68)
		var p := _w2m(pos.x, pos.y) + _challenge_offset(c)
		var type := String(c["type"])
		_challenge_icon(ci, p, "race" if type == "race" else ("extreme" if type == "extreme" else "trick"), col)
		var t := {"type": "challenge", "id": c["id"], "c": c, "available": avail}
		if type == "race":
			t["path"] = c.get("path", [])
		_target(p, 10.0, t)
	# drop zones
	for d in terrain.layout.get("drop_zones", []):
		if not Game.is_drop_unlocked(d["name"]):
			continue
		var p := _w2m(d["x"], d["z"])
		var hov: bool = _hover.get("type", "") == "drop" and _hover.get("name", "") == d["name"]
		_diamond(ci, p, 9.5 if hov else 7.5, UITheme.ACCENT)
		_target(p, 11.0, {"type": "drop", "name": d["name"], "d": d})
		_label(d["name"], p + Vector2(4, 0), 13, Color(1, 1, 1), 90.0, "right", Color(0.06, 0.09, 0.14, 0.82))
	# waypoint pin
	if Game.waypoint != Vector2.INF:
		var wp := _w2m(Game.waypoint.x, Game.waypoint.y)
		_pin(ci, wp)
		_target(wp - Vector2(0, 14), 11.0, {"type": "waypoint"})
	# player: view cone, pulse and arrow
	if skier:
		var pp := _w2m(skier.position.x, skier.position.z)
		var cam := get_viewport().get_camera_3d()
		if cam:
			var fwd := -cam.global_transform.basis.z
			var a0 := atan2(fwd.z, fwd.x)
			var cone := PackedVector2Array([pp])
			for i in 9:
				var a := a0 - 0.6 + i * 0.15
				cone.append(pp + Vector2(cos(a), sin(a)) * 46.0)
			ci.draw_colored_polygon(cone, Color(1, 1, 1, 0.22))
		var ph := fmod(_time * 0.8, 1.0)
		ci.draw_arc(pp, 10.0 + ph * 18.0, 0, TAU, 32, Color(PLAYER_COL, 0.7 * (1.0 - ph)), 2.5, true)
		var f := Skier.forward_flat_s(skier.heading)
		var dir := Vector2(f.x, f.z).normalized()
		var side := Vector2(-dir.y, dir.x)
		var arrow := PackedVector2Array([pp + dir * 13.0, pp - dir * 8.0 + side * 7.5, pp - dir * 4.0, pp - dir * 8.0 - side * 7.5])
		ci.draw_colored_polygon(arrow, PLAYER_COL)
		arrow.append(arrow[0])
		ci.draw_polyline(arrow, Color.WHITE, 2.0, true)
		_target(pp, 10.0, {"type": "player"})
		_label("YOU", pp + Vector2(4, -14), 12, Color.WHITE, 100.0, "right", Color(PLAYER_COL, 0.9))
	# hover target (drawn last so it is the topmost)
	var mouse := _overlay.get_local_mouse_position()
	var best := {}
	var bd := INF
	if Rect2(Vector2.ZERO, _view.size).has_point(mouse):
		for t in _targets:
			var d: float = mouse.distance_to(t["pos"])
			if d < float(t["r"]) + 3.0 and d < bd:
				bd = d
				best = t
	_hover = best
	_flush_labels(ci)
	_draw_compass(ci, Vector2(_view.size.x - 40.0, 40.0))
	_draw_scale(ci, Vector2(18.0, _view.size.y - 22.0))
	if not _hover.is_empty():
		ci.draw_arc(_hover["pos"], float(_hover["r"]) + 4.0, 0, TAU, 28, Color(1, 1, 1, 0.9), 2.0, true)
		_draw_tooltip(ci, _hover)
	_view.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _clickable(_hover) else Control.CURSOR_DRAG


func _clickable(h: Dictionary) -> bool:
	return h.get("type", "") in ["drop", "waypoint"] or (h.get("type", "") == "challenge" and h.get("available", false))


func _pin(ci: CanvasItem, p: Vector2) -> void:
	ci.draw_line(p, p - Vector2(0, 14), Color(0.02, 0.05, 0.1), 2.5, true)
	ci.draw_circle(p - Vector2(0, 16), 7.5, Color(0.02, 0.05, 0.1))
	ci.draw_circle(p - Vector2(0, 16), 5.5, Color(0.3, 0.85, 1.0))
	ci.draw_circle(p, 2.5, Color(0.02, 0.05, 0.1))


func _draw_compass(ci: CanvasItem, c: Vector2) -> void:
	ci.draw_circle(c, 24.0, Color(0.05, 0.08, 0.12, 0.72))
	ci.draw_arc(c, 24.0, 0, TAU, 40, Color(1, 1, 1, 0.5), 1.2, true)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -17), c + Vector2(5, 0), c + Vector2(-5, 0)]), PLAYER_COL)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, 17), c + Vector2(5, 0), c + Vector2(-5, 0)]), Color(0.92, 0.94, 0.98))
	var f := UITheme.font(800)
	var w := f.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	ci.draw_string_outline(f, c + Vector2(-w * 0.5, -27), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.6))
	ci.draw_string(f, c + Vector2(-w * 0.5, -27), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)


func _draw_scale(ci: CanvasItem, p: Vector2) -> void:
	var k := _px_per_m()
	var length := 2000.0
	for l in [100.0, 250.0, 500.0, 1000.0, 2000.0]:
		if l * k >= 70.0:
			length = l
			break
	var w := length * k
	ci.draw_rect(Rect2(p + Vector2(-8, -22), Vector2(w + 16, 32)), Color(0.05, 0.08, 0.12, 0.72))
	for i in 4:
		ci.draw_rect(Rect2(p + Vector2(w * i / 4.0, 0), Vector2(w / 4.0, 5)), Color.WHITE if i % 2 == 0 else Color(0.1, 0.1, 0.12))
	ci.draw_rect(Rect2(p, Vector2(w, 5)), Color(1, 1, 1, 0.9), false, 1.0)
	var txt := "%d km" % int(length / 1000.0) if length >= 1000.0 else "%d m" % int(length)
	ci.draw_string(UITheme.font(700), p + Vector2(0, -7), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


func _tooltip_lines(h: Dictionary) -> Dictionary:
	var title := ""
	var sub := ""
	var lines: Array = []
	var action := ""
	match String(h["type"]):
		"drop":
			var d: Dictionary = h["d"]
			title = d["name"]
			sub = "Drop zone · %s" % terrain.region_name(int(d.get("region", terrain.region_at(d["x"], d["z"]))))
			lines = [_elev(d["x"], d["z"]), _dist(d["x"], d["z"])]
			action = "Click to travel here"
		"challenge":
			var c: Dictionary = h["c"]
			title = c["name"]
			var type := String(c["type"])
			sub = "Race · %.1f km" % (float(c.get("length", 0.0)) / 1000.0) if type == "race" else ("Extreme" if type == "extreme" else "Freestyle")
			var res := Game.challenge_result(c["id"])
			if res.get("completed", false):
				var best := UITheme.medal_name(int(res.get("medal", 0)))
				if res.has("time"):
					best += " · best %s" % UITheme.format_time(float(res["time"]))
				elif res.has("score"):
					best += " · best %s pts" % _thousands(int(res["score"]))
				lines.append(best)
			else:
				lines.append("Not completed yet")
			if h.get("available", false):
				action = "Click to start"
			else:
				lines.append("Discover %s to unlock" % c.get("drop", "its drop zone"))
		"viewpoint":
			var v: Dictionary = h["v"]
			title = v["name"]
			sub = "Viewpoint"
			lines = ["Visited" if h["found"] else "Not visited: ride here to reveal nearby drop zones", _elev(v["x"], v["z"]), _dist(v["x"], v["z"])]
		"feature":
			var f: Dictionary = h["f"]
			title = f["name"]
			match String(f["type"]):
				"cliff":
					sub = "Cliff drop · %d m" % int(round(float(f["drop"])))
					lines = ["%d m wide band" % int(round(float(f["width"]))), "Land it straight and fast"]
				"lip":
					sub = "Natural kicker · %.1f m lip" % float(f["height"])
				"gully":
					sub = "Halfpipe gully · %s m long" % _thousands(int(f.get("length", 0)))
				"trail":
					sub = "Glade trail through the trees"
				"lake":
					sub = "Frozen lake"
				"moguls":
					sub = "Mogul field"
			lines.append(_elev(f["x"], f["z"]))
			lines.append(_dist(f["x"], f["z"]))
		"landmark":
			var m: Dictionary = h["m"]
			title = m["name"]
			sub = LANDMARK_KIND.get(m["type"], "Landmark")
			lines = [_elev(m["x"], m["z"]), _dist(m["x"], m["z"])]
		"peak":
			var pk: Dictionary = h["peak"]
			title = pk["name"]
			sub = "Summit · %s m" % _thousands(int(pk["y"]))
			lines = [_dist(pk["x"], pk["z"])]
		"lift":
			var lf: Dictionary = h["lift"]
			title = lf["name"]
			sub = "Chairlift · %d m vertical" % int(round(float(lf.get("top_y", 0.0)) - float(lf.get("bottom_y", 0.0))))
			lines = ["Ride it from the bottom station"]
		"piste":
			title = h["name"]
			sub = h["sub"]
		"waypoint":
			title = "Waypoint"
			sub = "Shown on the minimap and as a beam of light"
			lines = [_elev(Game.waypoint.x, Game.waypoint.y), _dist(Game.waypoint.x, Game.waypoint.y)]
			action = "Click to remove"
		"player":
			title = "You are here"
			sub = terrain.region_name(terrain.region_at(skier.position.x, skier.position.z))
			lines = [_elev(skier.position.x, skier.position.z), "%d km/h" % int(skier.speed_kmh())]
	return {"title": title, "sub": sub, "lines": lines, "action": action}


func _draw_tooltip(ci: CanvasItem, h: Dictionary) -> void:
	var info := _tooltip_lines(h)
	if info["title"] == "":
		return
	var fb := UITheme.font(800)
	var fm := UITheme.font(600)
	var fr := UITheme.font(500)
	var rows: Array = [[fb, 17, String(info["title"]), Color.WHITE]]
	if info["sub"] != "":
		rows.append([fm, 13, String(info["sub"]), UITheme.DIM])
	for l in info["lines"]:
		if String(l) != "":
			rows.append([fr, 13, String(l), Color(0.86, 0.9, 0.95)])
	if info["action"] != "":
		rows.append([fb, 14, String(info["action"]), UITheme.ACCENT])
	var w := 0.0
	var hgt := 12.0
	for r in rows:
		w = maxf(w, (r[0] as Font).get_string_size(r[2], HORIZONTAL_ALIGNMENT_LEFT, -1, r[1]).x)
		hgt += float(r[1]) + 7.0
	var box := Rect2(Vector2(h["pos"]) + Vector2(18, 14), Vector2(w + 28.0, hgt + 4.0))
	if box.end.x > _view.size.x - 8.0:
		box.position.x = Vector2(h["pos"]).x - box.size.x - 18.0
	if box.end.y > _view.size.y - 8.0:
		box.position.y = _view.size.y - 8.0 - box.size.y
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.11, 0.94)
	sb.set_corner_radius_all(8)
	sb.border_width_left = 3
	sb.border_color = UITheme.ACCENT
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	ci.draw_style_box(sb, box)
	var y := box.position.y + 8.0
	for r in rows:
		y += float(r[1]) + 2.0
		ci.draw_string(r[0], Vector2(box.position.x + 15.0, y), r[2], HORIZONTAL_ALIGNMENT_LEFT, -1, r[1], r[3])
		y += 5.0


func _challenge_pos(c: Dictionary) -> Vector2:
	if c["type"] == "race":
		return Vector2(c["start"][0], c["start"][1])
	var d := terrain.drop_zone(c.get("drop", ""))
	if d.is_empty():
		return Vector2.INF
	return Vector2(d["x"], d["z"])


## Spreads the challenge icons that share a drop zone around it.
func _challenge_offset(c: Dictionary) -> Vector2:
	var key := _challenge_pos(c)
	var idx := 0
	for o in terrain.layout.get("challenges", []):
		if o["id"] == c["id"]:
			break
		if _challenge_pos(o).distance_to(key) < 60.0:
			idx += 1
	var a := PI * 0.55 + idx * 0.75
	return Vector2(cos(a), sin(a)) * 17.0


func _challenge_available(c: Dictionary) -> bool:
	var drop: String = c.get("drop", "")
	return drop == "" or Game.is_drop_unlocked(drop)


# ------------------------------------------------------------------ frame & side panel
func _draw() -> void:
	if terrain == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.045, 0.075, 0.97))
	var fb := UITheme.font(800)
	draw_string(fb, Vector2(24, 44), "MOUNTAIN MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, UITheme.TEXT)
	var tw := fb.get_string_size("MOUNTAIN MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	if skier:
		var here := "%s  ·  %s" % [terrain.region_name(terrain.region_at(skier.position.x, skier.position.z)), _elev(skier.position.x, skier.position.z)]
		draw_string(UITheme.font(600), Vector2(24 + tw + 22, 43), here, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UITheme.DIM)
	if Game.mode == "freeride":
		var t := "FREE RIDE · every drop zone is open"
		var fw := UITheme.font(700).get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(UITheme.font(700), Vector2(_view.position.x + _view.size.x - fw, 43), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.ACCENT)
	var r := Rect2(_view.position, _view.size)
	draw_rect(r.grow(1.0), Color(1, 1, 1, 0.16), false, 1.0)
	if not _side.visible:
		var c := _counts
		var txt := "Drop zones %d/%d  ·  Viewpoints %d/%d  ·  Challenges %d/%d  ·  Discoveries %d/%d" % [c.get("drops", 0), c.get("drops_total", 0),
			c.get("viewpoints", 0), c.get("viewpoints_total", 0), c.get("challenges", 0), c.get("challenges_total", 0), c.get("spots", 0), c.get("spots_total", 0)]
		draw_string(UITheme.font(600), Vector2(24, size.y - 34), txt, HORIZONTAL_ALIGNMENT_LEFT, size.x - 48, 15, UITheme.TEXT)
		draw_string(UITheme.font(500), Vector2(24, size.y - 12), "Scroll or +/- zoom  ·  Drag to pan  ·  Click a drop zone to travel  ·  Click elsewhere: waypoint  ·  Tab / Esc close", HORIZONTAL_ALIGNMENT_LEFT, size.x - 48, 13, UITheme.DIM)


func _draw_side() -> void:
	var ci := _side
	var w := _side.size.x
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.14, 0.9)
	sb.set_corner_radius_all(10)
	ci.draw_style_box(sb, Rect2(Vector2.ZERO, _side.size))
	var fb := UITheme.font(800)
	var fm := UITheme.font(600)
	var fr := UITheme.font(500)
	var x := 20.0
	var y := 34.0
	ci.draw_string(fb, Vector2(x, y), "PROGRESS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.ACCENT)
	y += 14.0
	var c := _counts
	for row in [["Drop zones", "drops"], ["Viewpoints", "viewpoints"], ["Challenges", "challenges"], ["Discoveries", "spots"]]:
		var have := int(c.get(row[1], 0))
		var total := int(c.get(row[1] + "_total", 0))
		y += 20.0
		ci.draw_string(fm, Vector2(x, y), row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.TEXT)
		var num := "%d / %d" % [have, total]
		var nw := fm.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		ci.draw_string(fm, Vector2(w - x - nw, y), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.DIM)
		y += 8.0
		var bw := w - x * 2.0
		ci.draw_rect(Rect2(Vector2(x, y), Vector2(bw, 5)), Color(1, 1, 1, 0.12))
		ci.draw_rect(Rect2(Vector2(x, y), Vector2(bw * (float(have) / maxf(total, 1)), 5)), UITheme.ACCENT)
		y += 8.0
	y += 26.0
	ci.draw_string(fb, Vector2(x, y), "LEGEND", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.ACCENT)
	y += 8.0
	var entries := [
		["Drop zone", func(p): _diamond(ci, p, 7.0, UITheme.ACCENT)],
		["Viewpoint", func(p): _binoculars(ci, p, true)],
		["Race", func(p): _flag(ci, p, Color.WHITE)],
		["Freestyle", func(p): _star(ci, p, Color.WHITE)],
		["Extreme", func(p): _bolt(ci, p, Color.WHITE)],
		["Peak", func(p): _peak(ci, p)],
		["Cliff drop", func(p): _cliff_symbol(ci, p - Vector2(8, 2), p + Vector2(8, -2), Vector2(0, 1))],
		["Kicker", func(p): _lip_symbol(ci, p, Vector2(0, 1))],
		["Halfpipe gully", func(p): ci.draw_line(p - Vector2(9, 0), p + Vector2(9, 0), GULLY_COL, 4.0)],
		["Glade trail", func(p): _dashed(ci, PackedVector2Array([p - Vector2(10, 0), p + Vector2(10, 0)]), TRAIL_COL, 2.5, 4.0, 3.0)],
		["Landmark", func(p): _landmark(ci, p, "hut")],
		["Chairlift", func(p): _lift_line(ci, p - Vector2(10, 0), p + Vector2(10, 0))],
		["Waypoint", func(p): _pin(ci, p + Vector2(0, 9))],
	]
	var colw := (w - x * 2.0) * 0.5
	for i in entries.size():
		var e: Array = entries[i]
		var ex := x + (i % 2) * colw
		var ey := y + 26.0 + floorf(i * 0.5) * 27.0
		e[1].call(Vector2(ex + 11.0, ey - 5.0))
		ci.draw_string(fr, Vector2(ex + 28.0, ey), e[0], HORIZONTAL_ALIGNMENT_LEFT, colw - 30.0, 14, UITheme.TEXT)
	y += 26.0 + ceili(entries.size() / 2.0) * 27.0
	var keys := ["green", "blue", "red", "black"]
	for i in keys.size():
		var px := x + (i % 2) * colw
		var py := y + floorf(i * 0.5) * 20.0
		ci.draw_rect(Rect2(Vector2(px + 2, py - 8), Vector2(18, 6)), Color(1, 1, 1, 0.85))
		ci.draw_rect(Rect2(Vector2(px + 3, py - 7), Vector2(16, 4)), DIFF_COLORS[keys[i]])
		ci.draw_string(fr, Vector2(px + 28, py - 1), DIFF_NAMES[keys[i]], HORIZONTAL_ALIGNMENT_LEFT, colw - 30.0, 13, UITheme.DIM)
	y += 40.0
	var hint_y := _side.size.y - 64.0
	if hint_y > y + 20.0:
		for i in 3:
			var t: String = ["Scroll or +/- to zoom · drag to pan", "Click a drop zone to travel there", "Click anywhere else to set a waypoint"][i]
			ci.draw_string(fr, Vector2(x, hint_y + i * 19.0), t, HORIZONTAL_ALIGNMENT_LEFT, w - x * 2.0, 13, UITheme.DIM)
