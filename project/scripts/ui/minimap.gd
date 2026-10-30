class_name MiniMap
extends Control
## Round minimap in the top-right corner: the painted map around the player, turning with the
## camera (or north-up), with pistes, lifts, open drop zones, the next race gate and the map
## waypoint (pinned to the rim with its distance when it is out of view).

const SIZE := 210.0
const DIFF_COLORS := {"green": Color(0.15, 0.68, 0.3), "blue": Color(0.12, 0.4, 0.95), "red": Color(0.9, 0.14, 0.12), "black": Color(0.04, 0.04, 0.05)}

var terrain: TerrainData
var skier: Skier
var challenges: ChallengeManager
var radius_m := 360.0
var _img: TextureRect
var _ov: Control
var _mat: ShaderMaterial
var _yaw := 0.0
var _rotate := true


func setup(td: TerrainData, s: Skier, ch: ChallengeManager) -> void:
	terrain = td
	skier = s
	challenges = ch
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -SIZE - 24.0
	offset_right = -24.0
	offset_top = 24.0
	offset_bottom = 24.0 + SIZE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/minimap.gdshader")
	_img = TextureRect.new()
	_img.texture = load("res://world/map.png")
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_SCALE
	_img.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_img.material = _mat
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_img.size = Vector2(SIZE, SIZE)
	add_child(_img)
	_ov = Control.new()
	_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov.size = Vector2(SIZE, SIZE)
	add_child(_ov)
	_ov.draw.connect(_draw_overlay)
	Settings.changed.connect(func(_s, _k): _read_settings())
	_read_settings()


func _read_settings() -> void:
	visible = bool(Settings.get_value("camera", "minimap"))
	_rotate = bool(Settings.get_value("camera", "minimap_rotate"))


func _process(delta: float) -> void:
	if not visible or skier == null:
		return
	var target_r := lerpf(300.0, 650.0, clampf(skier.speed / 30.0, 0.0, 1.0))
	radius_m = lerpf(radius_m, target_r, 1.0 - exp(-1.5 * delta))
	_yaw = skier.cam_yaw if _rotate else 0.0
	var p := skier.position
	_mat.set_shader_parameter("center_uv", Vector2(p.x, p.z) / terrain.world)
	_mat.set_shader_parameter("radius_uv", radius_m / terrain.world)
	_mat.set_shader_parameter("yaw", _yaw)
	_ov.queue_redraw()


## World (x, z) -> minimap pixels.
func _to_px(x: float, z: float) -> Vector2:
	var dx := x - skier.position.x
	var dz := z - skier.position.z
	var c := cos(_yaw)
	var s := sin(_yaw)
	var k := SIZE * 0.5 / radius_m
	return Vector2(SIZE * 0.5, SIZE * 0.5) + Vector2(dx * c - dz * s, dx * s + dz * c) * k


func _inside(p: Vector2, margin := 0.0) -> bool:
	return p.distance_to(Vector2(SIZE * 0.5, SIZE * 0.5)) < SIZE * 0.5 - margin


func _clip_line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var c := Vector2(SIZE * 0.5, SIZE * 0.5)
	var r := SIZE * 0.5 - 2.0
	var ia := a.distance_to(c) < r
	var ib := b.distance_to(c) < r
	if ia and ib:
		_ov.draw_line(a, b, col, w, true)
		return
	# segment / circle intersection
	var d := b - a
	var f := a - c
	var qa := d.dot(d)
	var qb := 2.0 * f.dot(d)
	var qc := f.dot(f) - r * r
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0 or qa < 1e-6:
		return
	var sq := sqrt(disc)
	var t1 := clampf((-qb - sq) / (2.0 * qa), 0.0, 1.0)
	var t2 := clampf((-qb + sq) / (2.0 * qa), 0.0, 1.0)
	if t2 - t1 > 1e-4:
		_ov.draw_line(a + d * t1, a + d * t2, col, w, true)


func _draw_overlay() -> void:
	if skier == null:
		return
	var c := Vector2(SIZE * 0.5, SIZE * 0.5)
	var reach := radius_m * 1.6
	var pp := Vector2(skier.position.x, skier.position.z)
	# pistes
	for pi in terrain.layout.get("pistes", []):
		var col: Color = DIFF_COLORS.get(pi["difficulty"], Color.WHITE)
		var pts: Array = pi["pts"]
		var prev := Vector2.INF
		for i in range(0, pts.size(), 2):
			var q := Vector2(pts[i][0], pts[i][1])
			if q.distance_to(pp) > reach:
				prev = Vector2.INF
				continue
			var sp := _to_px(q.x, q.y)
			if prev != Vector2.INF:
				_clip_line(prev, sp, Color(1, 1, 1, 0.8), 4.5)
				_clip_line(prev, sp, col, 2.6)
			prev = sp
	# lifts
	for lf in terrain.layout.get("lifts", []):
		var a := _to_px(lf["bottom"][0], lf["bottom"][1])
		var b := _to_px(lf["top"][0], lf["top"][1])
		_clip_line(a, b, Color(1, 1, 1, 0.8), 4.0)
		_clip_line(a, b, Color(0.08, 0.08, 0.1), 2.0)
		for e in [a, b]:
			if _inside(e, 4.0):
				_ov.draw_rect(Rect2(e - Vector2(3, 3), Vector2(6, 6)), Color(0.08, 0.08, 0.1))
	# open drop zones
	for d in terrain.layout.get("drop_zones", []):
		if not Game.is_drop_unlocked(d["name"]):
			continue
		var p := _to_px(d["x"], d["z"])
		if _inside(p, 6.0):
			var r := 5.0
			var dia := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
			_ov.draw_colored_polygon(dia, UITheme.ACCENT)
	# next race gate and the waypoint: pinned to the rim when out of view
	if challenges:
		var g := challenges.next_gate()
		if g != Vector3.INF:
			_marker(_to_px(g.x, g.z), Color(1.0, 0.5, 0.1), Vector2(g.x, g.z).distance_to(pp))
	if Game.waypoint != Vector2.INF:
		_marker(_to_px(Game.waypoint.x, Game.waypoint.y), Color(0.3, 0.85, 1.0), Game.waypoint.distance_to(pp))
	# rim, compass and the player
	_ov.draw_arc(c, SIZE * 0.5 - 1.0, 0.0, TAU, 72, Color(0.04, 0.06, 0.1, 0.9), 3.0, true)
	_ov.draw_arc(c, SIZE * 0.5 - 3.0, 0.0, TAU, 72, Color(1, 1, 1, 0.55), 1.2, true)
	var north := Vector2(sin(_yaw), -cos(_yaw))
	var npos := c + north * (SIZE * 0.5 - 12.0)
	_ov.draw_circle(npos, 9.0, Color(0.04, 0.06, 0.1, 0.9))
	var f := UITheme.font(800)
	var nw := f.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	_ov.draw_string(f, npos + Vector2(-nw * 0.5, 4.5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.4, 0.3))
	var fw := Skier.forward_flat_s(skier.heading)
	var tip := _to_px(skier.position.x + fw.x, skier.position.z + fw.z) - c
	var dir := tip.normalized() if tip.length() > 0.001 else Vector2.UP
	var side := Vector2(-dir.y, dir.x)
	var arrow := PackedVector2Array([c + dir * 10.0, c - dir * 6.0 + side * 6.5, c - dir * 3.0, c - dir * 6.0 - side * 6.5])
	_ov.draw_colored_polygon(arrow, Color(1.0, 0.22, 0.15))
	arrow.append(arrow[0])
	_ov.draw_polyline(arrow, Color.WHITE, 1.6, true)


func _marker(p: Vector2, col: Color, dist: float) -> void:
	var c := Vector2(SIZE * 0.5, SIZE * 0.5)
	var rim := SIZE * 0.5 - 10.0
	var off := p - c
	var inside := off.length() <= rim
	if not inside:
		p = c + off.normalized() * rim
	_ov.draw_circle(p, 6.5, Color(0.04, 0.06, 0.1, 0.9))
	_ov.draw_circle(p, 4.5, col)
	if not inside:
		var txt := "%.1f km" % (dist / 1000.0) if dist >= 1000.0 else "%d m" % int(dist)
		var f := UITheme.font(700)
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var tp := p - off.normalized() * 16.0 + Vector2(-w * 0.5, 4.0)
		_ov.draw_string_outline(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(0, 0, 0, 0.8))
		_ov.draw_string(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
