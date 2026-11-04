extends Node3D
## Landmarks placed by the world generator: summit crosses on cairns, a mountain hut, a weather
## station with a spinning anemometer and an old cabin ruin.  Procedural meshes, with collision.

var terrain: TerrainData
var obstacles: Obstacles
var resort: Node
var _spinners: Array[Node3D] = []
var wood: StandardMaterial3D
var dark_wood: StandardMaterial3D
var metal: StandardMaterial3D
var stone: ShaderMaterial
var red: StandardMaterial3D


func setup(td: TerrainData, obs: Obstacles, resort_node: Node) -> void:
	terrain = td
	obstacles = obs
	resort = resort_node
	wood = _mat(Color(0.45, 0.3, 0.18), 0.85)
	dark_wood = _mat(Color(0.22, 0.15, 0.1), 0.9)
	metal = _mat(Color(0.72, 0.74, 0.78), 0.35, 0.6)
	red = _mat(Color(0.85, 0.12, 0.1), 0.5)
	stone = ShaderMaterial.new()
	stone.shader = load("res://shaders/rock.gdshader")
	stone.set_shader_parameter("rock_albedo", load("res://assets/textures/rock_albedo.png"))
	stone.set_shader_parameter("rock_normal", load("res://assets/textures/rock_normal.png"))
	for m in td.layout.get("landmarks", []):
		var p := Vector3(m["x"], 0.0, m["z"])
		p.y = _ground_min(p, 3.0)
		match String(m["type"]):
			"summit_cross":
				_cross(p, m["name"])
			"hut":
				_hut(p, m["name"])
			"weather_station":
				_station(p, m["name"])
			"ruin":
				_ruin(p, m["name"])

	for feature in td.layout.get("features", []):
		if not feature.has("line_grade"):
			continue
		var f := Vector3(feature["dx"], 0, feature["dz"])
		var p := Vector3(feature["x"], 0, feature["z"]) - f * 48.0 + f.cross(Vector3.UP) * 6.0
		p.y = td.height(p.x, p.z)
		var marker := Node3D.new()
		add_child(marker)
		marker.position = p
		_cyl(0.06, 2.4, dark_wood, Vector3.UP * 1.2, marker)
		var label := Label3D.new()
		label.text = "%s DROP\n%.0f m · %s\nApproach slowly" % [String(feature["line_grade"]).to_upper(), feature["drop"], feature["name"]]
		label.font_size = 48
		label.pixel_size = 0.009
		label.outline_size = 8
		label.modulate = Color(0.95, 0.65, 0.15)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3.UP * 2.5
		marker.add_child(label)


func _mat(c: Color, rough := 0.8, metal_v := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal_v
	return m


func _ground_min(p: Vector3, r: float) -> float:
	var h := INF
	for dx in [-r, 0.0, r]:
		for dz in [-r, 0.0, r]:
			h = minf(h, terrain.height(p.x + dx, p.z + dz))
	return h


func _box_mesh(size: Vector3, m: Material, pos: Vector3, parent: Node3D, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _cyl(r: float, h: float, m: Material, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _rock(scale: Vector3, pos: Vector3, parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 9
	s.rings = 5
	mi.mesh = s
	mi.material_override = stone
	mi.scale = scale
	mi.position = pos
	mi.rotation.y = randf() * TAU
	parent.add_child(mi)


func _label(parent: Node3D, text: String, y: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = UITheme.font(700)
	l.font_size = 72
	l.outline_size = 14
	l.pixel_size = 0.012
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, y, 0)
	l.visibility_range_end = 600.0
	l.modulate = Color(1.0, 0.92, 0.8)
	parent.add_child(l)


func _root(p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = p
	add_child(n)
	return n


func _cross(p: Vector3, name: String) -> void:
	var n := _root(p)
	# stone cairn
	_rock(Vector3(2.2, 1.0, 2.0), Vector3(0, 0.4, 0), n)
	_rock(Vector3(1.5, 0.8, 1.4), Vector3(0.2, 1.3, -0.1), n)
	_rock(Vector3(0.9, 0.6, 0.9), Vector3(-0.1, 2.0, 0.1), n)
	# summit cross
	_box_mesh(Vector3(0.22, 5.2, 0.22), metal, Vector3(0, 4.6, 0), n)
	_box_mesh(Vector3(2.4, 0.2, 0.2), metal, Vector3(0, 5.9, 0), n)
	_box_mesh(Vector3(0.5, 0.35, 0.06), red, Vector3(0, 5.2, 0.14), n)
	_label(n, name, 8.2)
	obstacles.add(p.x, p.z, 2.0, p.y - 1.0, p.y + 7.0, Obstacles.Kind.ROCK)


func _hut(p: Vector3, name: String) -> void:
	var n := _root(p)
	n.rotation.y = randf() * TAU
	if resort and resort.has_method("_chalet_meshes"):
		var meshes: Array = resort._chalet_meshes(10.0, 13.0, 5.5)
		var mats := [resort.wood, resort.roof, resort.window_mat]
		for i in meshes.size():
			var mi := MeshInstance3D.new()
			mi.mesh = meshes[i]
			mi.material_override = mats[i]
			n.add_child(mi)
	# flag pole with a red flag
	_cyl(0.06, 8.0, metal, Vector3(7.5, 4.0, 0), n)
	_box_mesh(Vector3(1.6, 0.9, 0.03), red, Vector3(8.35, 7.4, 0), n)
	# benches outside
	_box_mesh(Vector3(3.0, 0.12, 0.5), wood, Vector3(0, 0.55, -8.0), n)
	_box_mesh(Vector3(3.0, 0.6, 0.12), wood, Vector3(0, 0.85, -8.3), n)
	_label(n, name, 11.0)
	obstacles.add(p.x, p.z, 8.0, p.y - 3.0, p.y + 12.0, Obstacles.Kind.BUILDING)


func _station(p: Vector3, name: String) -> void:
	var n := _root(p)
	_box_mesh(Vector3(2.4, 2.2, 2.0), metal, Vector3(0, 1.1, 0), n)
	_cyl(0.07, 10.0, metal, Vector3(1.6, 5.0, 0), n)
	for k in 3:
		_box_mesh(Vector3(0.05, 0.05, 1.4), metal, Vector3(1.6, 3.0 + k * 2.5, 0), n, Vector3(0, k * 1.2, 0))
	var spin := Node3D.new()
	spin.position = Vector3(1.6, 10.1, 0)
	n.add_child(spin)
	for k in 3:
		var arm := Node3D.new()
		arm.rotation.y = TAU * k / 3.0
		spin.add_child(arm)
		_box_mesh(Vector3(0.5, 0.03, 0.03), metal, Vector3(0.25, 0, 0), arm)
		var cup := _cyl(0.07, 0.09, red, Vector3(0.5, 0, 0), arm)
		cup.rotation.z = PI * 0.5
	_spinners.append(spin)
	_box_mesh(Vector3(1.0, 0.6, 0.06), _mat(Color(0.95, 0.8, 0.1), 0.5), Vector3(0, 2.6, 1.05), n)
	_label(n, name, 12.0)
	obstacles.add(p.x, p.z, 2.2, p.y - 1.0, p.y + 10.0, Obstacles.Kind.BUILDING)


func _ruin(p: Vector3, name: String) -> void:
	var n := _root(p)
	n.rotation.y = randf() * TAU
	# collapsed log walls of uneven height, no roof, a fallen beam and snow on top
	var snow := _mat(Color(0.93, 0.95, 1.0), 0.85)
	var walls := [[Vector3(7.0, 2.2, 0.35), Vector3(0, 1.1, -3.0)], [Vector3(4.0, 1.4, 0.35), Vector3(-1.5, 0.7, 3.0)],
		[Vector3(0.35, 1.8, 6.0), Vector3(3.5, 0.9, 0)], [Vector3(0.35, 0.9, 3.5), Vector3(-3.5, 0.45, -1.2)]]
	for w in walls:
		_box_mesh(w[0], dark_wood, w[1], n)
		_box_mesh(Vector3(w[0].x, 0.12, w[0].z) + Vector3(0.05, 0, 0.05), snow, w[1] + Vector3(0, w[0].y * 0.5 + 0.06, 0), n)
	_box_mesh(Vector3(0.3, 0.3, 7.5), dark_wood, Vector3(0.5, 0.9, 0.2), n, Vector3(0.35, 0.4, 0.1))
	_box_mesh(Vector3(1.0, 2.4, 1.0), _mat(Color(0.4, 0.38, 0.36), 0.9), Vector3(-2.8, 1.2, -2.4), n)
	_label(n, name, 4.5)
	obstacles.add(p.x, p.z, 4.5, p.y - 1.0, p.y + 2.5, Obstacles.Kind.BUILDING)


func _process(delta: float) -> void:
	for s in _spinners:
		s.rotate_y(delta * 6.0)
