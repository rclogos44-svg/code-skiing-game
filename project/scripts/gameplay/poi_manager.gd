class_name POIManager
extends Node3D
## Exploration: viewpoints (reach them), drop zones (spot them by looking at them from afar, or
## ski close to them) and markers in the world.

const SPOT_RANGE := 2600.0
const SPOT_ANGLE := 9.0
const SPOT_TIME := 1.2

var terrain: TerrainData
var skier: Skier
var hud: HUD
var _spot := {}
var _spot_target := ""
var _timer := 0.0
var _markers := {}
var _vp_markers := {}
var _wp_beam: MeshInstance3D
var _wp_label: Label3D


func setup(td: TerrainData, s: Skier, h: HUD) -> void:
	terrain = td
	skier = s
	hud = h
	var flag_mat := StandardMaterial3D.new()
	flag_mat.albedo_color = Color(1.0, 0.45, 0.1)
	flag_mat.emission_enabled = true
	flag_mat.emission = Color(1.0, 0.4, 0.05)
	flag_mat.emission_energy_multiplier = 0.6
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.2, 0.2, 0.22)
	for d in td.layout.get("drop_zones", []):
		var n := _flag(Vector3(d["x"], d["y"], d["z"]), flag_mat, pole_mat, d["name"])
		_markers[d["name"]] = n
	var vp_mat := StandardMaterial3D.new()
	vp_mat.albedo_color = Color(0.3, 0.75, 1.0)
	vp_mat.emission_enabled = true
	vp_mat.emission = Color(0.3, 0.7, 1.0)
	vp_mat.emission_energy_multiplier = 0.8
	for v in td.layout.get("viewpoints", []):
		var n := _flag(Vector3(v["x"], v["y"], v["z"]), vp_mat, pole_mat, "Viewpoint: " + v["name"])
		_vp_markers[v["name"]] = n
	Game.progress_changed.connect(refresh)
	refresh()
	# map waypoint: a tall cyan light beam with its distance
	_wp_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.7
	cyl.bottom_radius = 0.7
	cyl.height = 160.0
	cyl.radial_segments = 12
	_wp_beam.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.3, 0.85, 1.0, 0.4)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.disable_fog = true
	_wp_beam.material_override = bm
	_wp_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wp_beam.visibility_range_begin = 30.0
	_wp_beam.visible = false
	add_child(_wp_beam)
	_wp_label = Label3D.new()
	_wp_label.font = UITheme.font(800)
	_wp_label.font_size = 64
	_wp_label.outline_size = 14
	_wp_label.pixel_size = 0.02
	_wp_label.fixed_size = false
	_wp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_wp_label.modulate = Color(0.6, 0.92, 1.0)
	_wp_label.no_depth_test = true
	_wp_label.visible = false
	add_child(_wp_label)


func _flag(p: Vector3, flag_mat: Material, pole_mat: Material, text: String) -> Node3D:
	var n := Node3D.new()
	n.position = p
	var pole := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.05
	c.bottom_radius = 0.07
	c.height = 4.0
	pole.mesh = c
	pole.material_override = pole_mat
	pole.position = Vector3(0, 2.0, 0)
	n.add_child(pole)
	var flag := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(1.2, 0.7, 0.03)
	flag.mesh = b
	flag.material_override = flag_mat
	flag.position = Vector3(0.62, 3.55, 0)
	n.add_child(flag)
	var l := Label3D.new()
	l.text = text
	l.font = UITheme.font(700)
	l.font_size = 72
	l.outline_size = 14
	l.pixel_size = 0.012
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, 5.2, 0)
	l.visibility_range_end = 900.0
	l.no_depth_test = false
	n.add_child(l)
	add_child(n)
	return n


func refresh() -> void:
	var p := skier.position if skier else Vector3.ZERO
	for name in _markers:
		var m: Node3D = _markers[name]
		# hide the flag while standing at it (it would fill the camera)
		m.visible = Game.is_drop_unlocked(name) and Vector2(m.position.x - p.x, m.position.z - p.z).length() > 25.0
	for name in _vp_markers:
		var discovered: bool = name in Game.save["viewpoints"]
		var n: Node3D = _vp_markers[name]
		n.visible = true
		(n.get_child(2) as Label3D).modulate = Color(0.6, 0.9, 1.0) if not discovered else Color(0.8, 0.8, 0.8, 0.6)


func _update_waypoint() -> void:
	var on := Game.waypoint != Vector2.INF and Game.mode != "menu"
	_wp_beam.visible = on
	_wp_label.visible = on
	if not on:
		return
	var w := Game.waypoint
	var gy := terrain.height(w.x, w.y)
	_wp_beam.position = Vector3(w.x, gy + 80.0, w.y)
	var d := Vector2(skier.position.x, skier.position.z).distance_to(w)
	if d < 25.0:
		Game.waypoint = Vector2.INF
		hud.notify("Waypoint reached", "info")
		return
	# the label stays readable at any distance (scaled with it), floating above the beam's base
	_wp_label.position = Vector3(w.x, gy + 6.0 + d * 0.02, w.y)
	_wp_label.pixel_size = 0.004 + d * 0.00004
	_wp_label.text = "WAYPOINT  %s" % (("%.1f km" % (d / 1000.0)) if d >= 1000.0 else ("%d m" % int(d)))


func _process(delta: float) -> void:
	if skier == null:
		return
	_update_waypoint()
	if Game.mode == "menu":
		return
	_timer += delta
	if _timer < 0.1:
		return
	var dt := _timer
	_timer = 0.0
	var p := skier.position
	for name in _markers:
		var m: Node3D = _markers[name]
		m.visible = Game.is_drop_unlocked(name) and Vector2(m.position.x - p.x, m.position.z - p.z).length() > 25.0
	# viewpoints: reach them
	for v in terrain.layout.get("viewpoints", []):
		if v["name"] in Game.save["viewpoints"]:
			continue
		if Vector2(p.x - v["x"], p.z - v["z"]).length() < 45.0:
			Game.discover_viewpoint(v["name"])
			Sfx.play("discovery", -4.0)
			hud.big_message("VIEWPOINT", UITheme.TEXT, 1.6, 54)
			# a viewpoint reveals the drop zones of its region
			for d in terrain.layout.get("drop_zones", []):
				if int(d["region"]) == int(v["region"]):
					Game.unlock_drop(d["name"])
	_check_spots(p)
	if Game.mode != "career":
		hud.set_spotting(0.0, "")
		return
	# drop zones: proximity or spotting
	var cam := get_viewport().get_camera_3d()
	var best := ""
	var best_angle := SPOT_ANGLE
	for d in terrain.layout.get("drop_zones", []):
		var name: String = d["name"]
		if Game.is_drop_unlocked(name):
			continue
		var target := Vector3(d["x"], float(d["y"]) + 3.0, d["z"])
		var dist := Vector2(p.x - target.x, p.z - target.z).length()
		if dist < 140.0:
			_discover(name)
			continue
		if cam == null or dist > SPOT_RANGE:
			continue
		var to := (target - cam.global_position).normalized()
		var ang := rad_to_deg(acos(clampf(to.dot(-cam.global_basis.z), -1.0, 1.0)))
		if ang < best_angle:
			if terrain.raycast(cam.global_position, target, 6.0) >= 0.995:
				best = name
				best_angle = ang
	if best != _spot_target:
		_spot.clear()
		_spot_target = best
	if best != "":
		_spot[best] = float(_spot.get(best, 0.0)) + dt / SPOT_TIME
		if _spot[best] >= 1.0:
			_discover(best)
			_spot.clear()
			_spot_target = ""
			hud.set_spotting(0.0, "")
			return
		hud.set_spotting(_spot[best], "unknown drop zone")
	else:
		hud.set_spotting(0.0, "")


## Named terrain features and landmarks: announced (and saved) the first time you ski them.
func _check_spots(p: Vector3) -> void:
	var p2 := Vector2(p.x, p.z)
	for f in terrain.layout.get("features", []):
		var name: String = f["name"]
		if name in Game.save.get("spots", []):
			continue
		var near := false
		match String(f["type"]):
			"cliff":
				near = p2.distance_to(Vector2(f["x"], f["z"])) < float(f["width"]) * 0.5 + 15.0
			"lake":
				near = p2.distance_to(Vector2(f["x"], f["z"])) < float(f["radius"]) + 10.0
			"gully", "trail":
				for q in f["path"]:
					if p2.distance_to(Vector2(q[0], q[1])) < 18.0:
						near = true
						break
			_:
				near = p2.distance_to(Vector2(f["x"], f["z"])) < 35.0
		if near:
			var detail := ""
			match String(f["type"]):
				"cliff":
					detail = "%d m cliff band" % int(round(float(f["drop"])))
				"lip":
					detail = "natural kicker"
				"gully":
					detail = "%d m halfpipe gully" % int(f["length"])
				"lake":
					detail = "frozen lake"
				"moguls":
					detail = "mogul field"
				"trail":
					detail = "glade trail"
			if Game.discover_spot(name, detail):
				Sfx.play("discovery", -10.0, 1.2)
	for m in terrain.layout.get("landmarks", []):
		if p2.distance_to(Vector2(m["x"], m["z"])) < 40.0:
			if Game.discover_spot(m["name"], "landmark"):
				Sfx.play("discovery", -8.0)


func _discover(name: String) -> void:
	Game.unlock_drop(name)
	Sfx.play("discovery", -4.0)
