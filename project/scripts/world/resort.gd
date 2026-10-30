extends Node3D
## Mountain resort: village chalets, chairlifts with moving chairs, piste markers, signs and the
## terrain-park markers.  Lifts are ridden for real: stand on the marked loading point, the next
## chair picks you up from behind and drops you at the unloading ramp at the top.

signal ride_finished(lift_name: String)

const TOWER_SPACING := 110.0
const CHAIR_SPACING := 36.0        # ~7 s between chairs (real lifts: 6-10 s)
const CHAIR_SPEED := 5.5
const RIDE_BOOST := 3.0            # the lift runs "express" while the player is on it
const LINE_OFFSET := 3.4           # half the gap between the up and the down line
const STATION_CABLE_H := 3.25      # cable height at the terminals -> seat ~0.5 m above the snow
const SEAT_Y := -2.66              # seat surface below the cable grip
const LOAD_S := 7.0                # loading point, metres along the up line from the bottom wheel
const UNLOAD_BEFORE := 8.0         # unloading point, metres before the top wheel
const LIFT_COLORS := [Color(0.86, 0.16, 0.12), Color(0.12, 0.4, 0.88), Color(0.98, 0.74, 0.1), Color(0.2, 0.7, 0.35)]
const RIDER_JACKETS := [Color(0.9, 0.2, 0.15), Color(0.15, 0.45, 0.9), Color(0.95, 0.75, 0.1), Color(0.2, 0.65, 0.35),
	Color(0.55, 0.25, 0.75), Color(0.95, 0.45, 0.1), Color(0.1, 0.12, 0.16), Color(0.9, 0.9, 0.92), Color(0.0, 0.6, 0.65)]
const DIFF_COLORS := {"green": Color(0.15, 0.7, 0.3), "blue": Color(0.15, 0.4, 0.95), "red": Color(0.9, 0.15, 0.12), "black": Color(0.05, 0.05, 0.05)}

var terrain: TerrainData
var obstacles: Obstacles
var lifts: Array = []          # {name, bottom, top, towers, side, dir, mm, riders, loop, up_len, ...}
var ride := {}                 # the player's current ride: {lift, chair, phase: "wait"/"ride", skier}
var _t := 0.0
var dark_metal: StandardMaterial3D
var rider_mesh: ArrayMesh
var rider_mat: ShaderMaterial
var wood: StandardMaterial3D
var roof: StandardMaterial3D
var metal: StandardMaterial3D
var window_mat: StandardMaterial3D


func setup(td: TerrainData, obs: Obstacles) -> void:
	terrain = td
	obstacles = obs
	wood = _mat(Color(0.42, 0.27, 0.16), 0.85)
	roof = _mat(Color(0.94, 0.96, 1.0), 0.8)
	metal = _mat(Color(0.62, 0.64, 0.68), 0.45, 0.3)
	window_mat = _mat(Color(1.0, 0.8, 0.45), 0.4)
	window_mat.emission_enabled = true
	window_mat.emission = Color(1.0, 0.72, 0.35)
	window_mat.emission_energy_multiplier = 1.4
	dark_metal = _mat(Color(0.2, 0.21, 0.23), 0.5, 0.5)
	rider_mesh = _rider_mesh()
	rider_mat = ShaderMaterial.new()
	rider_mat.shader = load("res://shaders/rider.gdshader")
	process_priority = -10          # chairs move before the riding skier is drawn
	_build_village()
	var li := 0
	for lf in td.layout.get("lifts", []):
		_build_lift(lf, li)
		li += 1
	for p in td.layout.get("pistes", []):
		_build_piste_markers(p)
	_build_kicker_markers()


func _mat(c: Color, rough := 0.8, metal_v := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal_v
	return m


func _box(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	SkierModel._box(st, a, b)


# ------------------------------------------------------------------ village
func _chalet_meshes(w: float, d: float, h: float) -> Array:
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(body, Vector3(-w * 0.5, -3.0, -d * 0.5), Vector3(w * 0.5, h, d * 0.5))
	# chimney
	_box(body, Vector3(w * 0.18, h, -d * 0.15), Vector3(w * 0.32, h + w * 0.45, d * 0.02))
	body.generate_normals()
	var rf := SurfaceTool.new()
	rf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var o := 0.9
	var ridge := h + w * 0.42
	var pts := [Vector3(-w * 0.5 - o, h - 0.3, -d * 0.5 - o), Vector3(0, ridge, -d * 0.5 - o), Vector3(w * 0.5 + o, h - 0.3, -d * 0.5 - o),
		Vector3(-w * 0.5 - o, h - 0.3, d * 0.5 + o), Vector3(0, ridge, d * 0.5 + o), Vector3(w * 0.5 + o, h - 0.3, d * 0.5 + o)]
	for tri in [[0, 1, 4], [0, 4, 3], [1, 2, 5], [1, 5, 4], [0, 3, 1], [3, 4, 1], [2, 1, 5], [1, 4, 5]]:
		for k in tri:
			rf.add_vertex(pts[k] + Vector3(0, 0.25, 0))
	# underside of the roof (thickness)
	for tri in [[0, 4, 1], [0, 3, 4], [1, 5, 2], [1, 4, 5]]:
		for k in tri:
			rf.add_vertex(pts[k])
	rf.generate_normals()
	var win := SurfaceTool.new()
	win.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var x := lerpf(-w * 0.32, w * 0.32, i / 2.0)
		_box(win, Vector3(x - 0.45, h * 0.35, -d * 0.5 - 0.05), Vector3(x + 0.45, h * 0.35 + 1.1, -d * 0.5 + 0.02))
		_box(win, Vector3(x - 0.45, h * 0.35, d * 0.5 - 0.02), Vector3(x + 0.45, h * 0.35 + 1.1, d * 0.5 + 0.05))
	win.generate_normals()
	return [body.commit(), rf.commit(), win.commit()]


func _place_building(meshes: Array, pos: Vector3, yaw: float, radius: float) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	var mats := [wood, roof, window_mat]
	for i in meshes.size():
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[i]
		mi.material_override = mats[i]
		n.add_child(mi)
	add_child(n)
	obstacles.add(pos.x, pos.z, radius, pos.y - 3.0, pos.y + 12.0, Obstacles.Kind.BUILDING)


func _build_village() -> void:
	var v: Dictionary = terrain.layout.get("village", {})
	if v.is_empty():
		return
	var c := Vector3(v["x"], 0, v["z"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var variants := [_chalet_meshes(9.0, 12.0, 5.0), _chalet_meshes(12.0, 16.0, 6.5), _chalet_meshes(7.0, 9.0, 4.0)]
	var placed: Array[Vector3] = []
	var lift_lines := []
	for lf in terrain.layout.get("lifts", []):
		lift_lines.append([Vector2(lf["bottom"][0], lf["bottom"][1]), Vector2(lf["top"][0], lf["top"][1])])
	var tries := 0
	while placed.size() < 16 and tries < 400:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(70.0, 230.0)
		var p := c + Vector3(cos(a) * r, 0, sin(a) * r)
		if terrain.slope_deg(p.x, p.z) > 16.0:
			continue
		var ok := true
		for q in placed:
			if q.distance_to(p) < 26.0:
				ok = false
				break
		for ln in lift_lines:
			if Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), ln[0], ln[1]).distance_to(Vector2(p.x, p.z)) < 30.0:
				ok = false
		for pi in terrain.layout.get("pistes", []):
			var pts: Array = pi["pts"]
			for k in range(0, pts.size() - 1, 3):
				if Vector2(pts[k][0], pts[k][1]).distance_to(Vector2(p.x, p.z)) < 34.0:
					ok = false
					break
		if not ok:
			continue
		# sit the building on the lowest corner so it never floats
		var hmin := INF
		for dx in [-7.0, 7.0]:
			for dz in [-8.0, 8.0]:
				hmin = minf(hmin, terrain.height(p.x + dx, p.z + dz))
		p.y = hmin
		placed.append(p)
		var yaw := atan2(c.x - p.x, c.z - p.z) + rng.randf_range(-0.3, 0.3)
		_place_building(variants[placed.size() % 3], p, yaw, 7.5)
	# village sign
	var sign_pos := c + Vector3(0, terrain.height(c.x, c.z) + 3.5, 0)
	_label(sign_pos, "SUMMIT VILLAGE", 96, Color(1, 1, 1))


func _label(pos: Vector3, text: String, size := 64, color := Color.WHITE, billboard := true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 12
	l.modulate = color
	l.pixel_size = 0.01
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	l.font = UITheme.font(700)
	l.position = pos
	l.visibility_range_end = 400.0
	add_child(l)
	return l


# ------------------------------------------------------------------ lifts
func _build_lift(lf: Dictionary, index: int) -> void:
	var b := Vector3(lf["bottom"][0], 0, lf["bottom"][1])
	var t := Vector3(lf["top"][0], 0, lf["top"][1])
	b.y = terrain.height(b.x, b.z)
	t.y = terrain.height(t.x, t.z)
	var dir := Vector3(t.x - b.x, 0, t.z - b.z)
	var length := dir.length()
	dir /= length
	var side := dir.cross(Vector3.UP).normalized()      # the up line runs on this side
	var color: Color = LIFT_COLORS[index % LIFT_COLORS.size()]
	var color_mat := _mat(color, 0.5)
	# tower positions: one close to each terminal, the rest evenly spaced
	var dists: Array[float] = [0.0, 22.0]
	var inner := maxi(1, int(ceil((length - 44.0) / TOWER_SPACING)))
	for k in range(1, inner):
		dists.append(22.0 + (length - 44.0) * k / inner)
	dists.append(length - 22.0)
	dists.append(length)
	var ground: Array[Vector3] = []
	var hts: Array[float] = []
	for d in dists:
		var p := b.lerp(t, d / length)
		p.y = terrain.height(p.x, p.z)
		ground.append(p)
		hts.append(STATION_CABLE_H if (d == 0.0 or d == length) else 9.0)
	# raise towers until the cable clears the snow (less clearance needed near the terminals)
	var last := dists.size() - 1
	for _pass in 6:
		for i in range(1, dists.size()):
			var a := ground[i - 1] + Vector3.UP * hts[i - 1]
			var c := ground[i] + Vector3.UP * hts[i]
			var need := 0.0
			var worst_f := 0.5
			for k in range(1, 12):
				var f := k / 12.0
				var q := a.lerp(c, f)
				var along := lerpf(dists[i - 1], dists[i], f)
				var req := 1.2 + 6.0 * clampf(minf(along, length - along) / 40.0, 0.0, 1.0)
				var deficit := req - (q.y - terrain.height(q.x, q.z))
				if deficit > need:
					need = deficit
					worst_f = f
			if need <= 0.0:
				continue
			if i - 1 != 0 and i != last:
				hts[i - 1] += need
				hts[i] += need
			elif i != last:
				hts[i] += need / maxf(worst_f, 0.25)
			elif i - 1 != 0:
				hts[i - 1] += need / maxf(1.0 - worst_f, 0.25)
	var tower_pts: Array[Vector3] = []
	for i in dists.size():
		tower_pts.append(ground[i] + Vector3.UP * hts[i])
	var lb := Basis(side, Vector3.UP, -dir)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var band := SurfaceTool.new()
	band.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, last):
		var p := ground[i]
		var top := tower_pts[i]
		_seg_box(st, p - Vector3.UP * 1.0, top - Vector3.UP * 0.2, 0.32)
		_seg_box(st, top - side * (LINE_OFFSET + 0.6), top + side * (LINE_OFFSET + 0.6), 0.2)
		for s: float in [-1.0, 1.0]:
			# sheave trains under the cable
			_obox(st, top + side * (LINE_OFFSET * s) - Vector3.UP * 0.3, lb, Vector3(0.15, 0.15, 0.9))
		_seg_box(band, top - Vector3.UP * 2.4, top - Vector3.UP * 1.4, 0.36)
		obstacles.add(p.x, p.z, 0.6, p.y - 1.0, top.y, Obstacles.Kind.POLE)
	# cables (up line on +side, down line on -side)
	for s: float in [-1.0, 1.0]:
		for i in tower_pts.size() - 1:
			_seg_box(st, tower_pts[i] + side * (LINE_OFFSET * s), tower_pts[i + 1] + side * (LINE_OFFSET * s), 0.04)
	# terminals: pillar, bull wheel and a coloured housing over it
	for end in [0, last]:
		var g := ground[end]
		var top := tower_pts[end]
		_seg_box(st, g - Vector3.UP * 1.0, top + Vector3.UP * 0.6, 0.5)
		var away := -dir if end == 0 else dir
		_obox(band, top + Vector3.UP * 1.1, lb, Vector3(LINE_OFFSET + 0.9, 0.35, LINE_OFFSET + 1.0))
		obstacles.add(g.x, g.z, 0.9, g.y - 1.0, top.y + 2.0, Obstacles.Kind.POLE)
		var wheel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = LINE_OFFSET
		cyl.bottom_radius = LINE_OFFSET
		cyl.height = 0.22
		cyl.radial_segments = 28
		wheel.mesh = cyl
		wheel.material_override = dark_metal
		wheel.position = top + Vector3.UP * 0.12
		add_child(wheel)
		# small operator hut beside the terminal
		var hut := _chalet_meshes(4.0, 4.5, 2.8)
		var hp := g + away * 4.0 - side * (LINE_OFFSET + 6.5)
		hp.y = terrain.height(hp.x, hp.z) - 0.2
		_place_building(hut, hp, atan2(dir.x, dir.z), 3.2)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = metal
	add_child(mi)
	band.generate_normals()
	var bmi := MeshInstance3D.new()
	bmi.mesh = band.commit()
	bmi.material_override = color_mat
	add_child(bmi)
	# chairs (animated, colour-coded per lift) and the people riding them
	var entry := {"name": lf["name"], "bottom": b, "top": t, "towers": tower_pts, "side": side, "dir": dir,
		"color": color, "index": index, "vertical": float(lf.get("top_y", t.y)) - float(lf.get("bottom_y", b.y))}
	_prepare_loop(entry)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _chair_mesh(color_mat)
	mm.instance_count = int(float(entry["loop"]) / CHAIR_SPACING)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	entry["mm"] = mm
	entry["spacing"] = float(entry["loop"]) / mm.instance_count
	entry["t"] = 0.0
	entry["speed"] = CHAIR_SPEED
	var rng := RandomNumberGenerator.new()
	rng.seed = 91 + index
	var slots: Array = []
	for i in mm.instance_count:
		for x in [0.29, 0.86]:
			if rng.randf() < 0.42:
				slots.append([i, x])
	var rmm := MultiMesh.new()
	rmm.transform_format = MultiMesh.TRANSFORM_3D
	rmm.use_custom_data = true
	rmm.mesh = rider_mesh
	rmm.instance_count = slots.size()
	for k in slots.size():
		rmm.set_instance_custom_data(k, RIDER_JACKETS[rng.randi() % RIDER_JACKETS.size()])
	var rmi := MultiMeshInstance3D.new()
	rmi.multimesh = rmm
	rmi.material_override = rider_mat
	add_child(rmi)
	entry["riders"] = rmm
	entry["slots"] = slots
	lifts.append(entry)
	# loading point (marked mat) and signs
	var lp := load_point(entry)
	var mat_mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.8, 0.06, 1.6)
	mat_mi.mesh = bm
	mat_mi.material_override = _mat(Color(0.12, 0.35, 0.9), 0.6)
	mat_mi.position = lp + Vector3.UP * 0.02
	mat_mi.rotation.y = atan2(dir.x, dir.z)
	add_child(mat_mi)
	_label(lp + Vector3.UP * 2.6, "▼  LOAD HERE", 48, Color(0.75, 0.88, 1.0))
	var ride_min := maxi(1, int(round(float(entry["up_len"]) / (CHAIR_SPEED * RIDE_BOOST * 0.92) / 60.0)))
	var sign_pos := b - dir * 6.0 + side * (LINE_OFFSET + 5.0)
	sign_pos.y = terrain.height(sign_pos.x, sign_pos.z)
	_seg_box_mesh(sign_pos, sign_pos + Vector3.UP * 3.2, 0.09)
	var board := _label(sign_pos + Vector3.UP * 4.4, String(lf["name"]).to_upper(), 110, color.lightened(0.35))
	board.outline_size = 18
	_label(sign_pos + Vector3.UP * 3.55, "Quad chair  ·  %d m up  ·  %d min ride" % [int(round(float(entry["vertical"]))), ride_min], 56, Color(1, 1, 1))
	var up_pt := unload_point(entry)
	_label(up_pt + Vector3.UP * 3.0, "UNLOAD  ▶", 48, Color(1.0, 0.9, 0.6))
	var top_sign := t + dir * 7.0 - side * (LINE_OFFSET + 5.0)
	top_sign.y = terrain.height(top_sign.x, top_sign.z)
	_label(top_sign + Vector3.UP * 4.0, String(lf["name"]) + "  —  top", 64, color.lightened(0.4))


func _seg_box(st: SurfaceTool, a: Vector3, b: Vector3, r: float) -> void:
	var y := (b - a)
	var ln := y.length()
	if ln < 0.001:
		return
	y /= ln
	var x := y.cross(Vector3.FORWARD if absf(y.y) > 0.9 else Vector3.UP).normalized()
	var z := x.cross(y).normalized()
	var corners := []
	for e in [a, b]:
		for k in 4:
			var ang := TAU * k / 4.0 + PI * 0.25
			corners.append(e + (x * cos(ang) + z * sin(ang)) * r)
	for k in 4:
		var k2 := (k + 1) % 4
		for idx in [k, k2, k + 4, k2, k2 + 4, k + 4]:
			st.add_vertex(corners[idx])


## Oriented box: centre, axes and half extents.
func _obox(st: SurfaceTool, c: Vector3, b: Basis, h: Vector3) -> void:
	var v := []
	for k in [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
			Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]:
		v.append(c + b * (k * h))
	for f in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]:
		for idx in [f[0], f[1], f[2], f[0], f[2], f[3]]:
			st.add_vertex(v[idx])


func _seg_box_mesh(a: Vector3, b: Vector3, r: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_seg_box(st, a, b, r)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = metal
	add_child(mi)


## Quad chair hanging from its grip (origin = cable grip, -Z = direction of travel):
## metal frame + seat, backrest, safety bar and footrest; the seat and back carry the lift colour.
func _chair_mesh(color_mat: Material) -> ArrayMesh:
	var fr := SurfaceTool.new()
	fr.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(fr, Vector3(-0.14, -0.22, -0.3), Vector3(0.14, 0.08, 0.3))                       # grip
	_seg_box(fr, Vector3(0, -0.1, 0.0), Vector3(0, -1.9, 0.32), 0.05)                       # hanger arm
	_seg_box(fr, Vector3(0, -1.9, 0.32), Vector3(0, -2.6, 0.38), 0.05)
	_seg_box(fr, Vector3(-1.2, -2.66, 0.36), Vector3(1.2, -2.66, 0.36), 0.04)               # frame rail
	for x in [-1.2, 1.2]:
		_seg_box(fr, Vector3(x, -2.68, 0.32), Vector3(x, -2.68, -0.3), 0.035)               # armrests
		_seg_box(fr, Vector3(x, -2.68, -0.3), Vector3(x, -2.36, -0.3), 0.035)
	_seg_box(fr, Vector3(-1.15, -2.02, -0.62), Vector3(1.15, -2.02, -0.62), 0.03)           # safety bar
	for x in [-0.6, 0.6]:
		_seg_box(fr, Vector3(x, -2.02, -0.62), Vector3(x, -3.12, -0.72), 0.025)
	_seg_box(fr, Vector3(-1.0, -3.12, -0.72), Vector3(1.0, -3.12, -0.72), 0.03)              # footrest
	fr.generate_normals()
	var mesh := fr.commit()
	mesh.surface_set_material(0, metal)
	var seat := SurfaceTool.new()
	seat.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(seat, Vector3(-1.18, -2.78, -0.32), Vector3(1.18, -2.66, 0.3))
	_box(seat, Vector3(-1.18, -2.66, 0.28), Vector3(1.18, -1.98, 0.38))
	seat.generate_normals()
	seat.commit(mesh)
	mesh.surface_set_material(1, color_mat)
	return mesh


## A seated rider (origin = middle of the seat surface, facing -Z).  Vertex alpha 0 marks the
## jacket, which takes the per-instance colour.
func _rider_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pants := Color(0.16, 0.18, 0.24)
	var boots := Color(0.12, 0.12, 0.14)
	var jacket := Color(1, 1, 1, 0)
	var helmet := Color(0.9, 0.91, 0.93)
	var skin := Color(0.82, 0.64, 0.52)
	var ski := Color(0.85, 0.85, 0.88)
	for x in [-0.1, 0.1]:
		_cbox(st, Vector3(x - 0.08, 0.0, -0.46), Vector3(x + 0.08, 0.16, 0.05), pants)        # thigh
		_cbox(st, Vector3(x - 0.07, -0.40, -0.52), Vector3(x + 0.07, 0.02, -0.38), pants)     # shin
		_cbox(st, Vector3(x - 0.075, -0.56, -0.66), Vector3(x + 0.075, -0.38, -0.34), boots)  # boot
		_cbox(st, Vector3(x - 0.05, -0.60, -1.40), Vector3(x + 0.05, -0.57, 0.38), ski)        # ski
	_cbox(st, Vector3(-0.2, 0.1, -0.06), Vector3(0.2, 0.66, 0.2), jacket)                     # torso
	for x in [-0.25, 0.25]:
		_cbox(st, Vector3(x - 0.06, 0.28, -0.12), Vector3(x + 0.06, 0.62, 0.08), jacket)       # upper arm
		_cbox(st, Vector3(x - 0.055, 0.2, -0.4), Vector3(x + 0.055, 0.31, -0.06), jacket)      # forearm
	_cbox(st, Vector3(-0.06, 0.66, -0.0), Vector3(0.06, 0.74, 0.12), skin)                    # neck
	_cbox(st, Vector3(-0.12, 0.74, -0.08), Vector3(0.12, 0.98, 0.18), helmet)                 # helmet
	_cbox(st, Vector3(-0.1, 0.8, -0.1), Vector3(0.1, 0.86, -0.07), Color(1.0, 0.55, 0.15))    # goggles
	st.generate_normals()
	return st.commit()


func _cbox(st: SurfaceTool, a: Vector3, b: Vector3, c: Color) -> void:
	st.set_color(c)
	_box(st, a, b)


func _prepare_loop(lf: Dictionary) -> void:
	var towers: Array = lf["towers"]
	var side: Vector3 = lf["side"]
	var dir: Vector3 = lf["dir"]
	var pts := PackedVector3Array()
	for p in towers:
		pts.append((p as Vector3) + side * LINE_OFFSET)
	var up_count := pts.size()
	# around the top bull wheel
	var top: Vector3 = towers[towers.size() - 1]
	for k in range(1, 12):
		var a := PI * k / 12.0
		pts.append(top + side * (LINE_OFFSET * cos(a)) + dir * (LINE_OFFSET * sin(a)))
	for i in range(towers.size() - 1, -1, -1):
		pts.append((towers[i] as Vector3) - side * LINE_OFFSET)
	# around the bottom bull wheel
	var bot: Vector3 = towers[0]
	for k in range(1, 12):
		var a := PI - PI * k / 12.0
		pts.append(bot + side * (LINE_OFFSET * cos(a)) - dir * (LINE_OFFSET * sin(a)))
	pts.append(pts[0])
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	lf["loop_pts"] = pts
	lf["cum"] = cum
	lf["loop"] = cum[cum.size() - 1]
	lf["up_len"] = cum[up_count - 1]


func _sample_loop(lf: Dictionary, s: float) -> Transform3D:
	var pts: PackedVector3Array = lf["loop_pts"]
	var cum: PackedFloat32Array = lf["cum"]
	s = fposmod(s, float(lf["loop"]))
	var i := clampi(cum.bsearch(s, true) - 1, 0, pts.size() - 2)
	var a := pts[i]
	var b := pts[i + 1]
	var l := cum[i + 1] - cum[i]
	var p := a.lerp(b, (s - cum[i]) / maxf(l, 0.001))
	var fwd := b - a
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	return Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), p)


func _chair_s(lf: Dictionary, i: int) -> float:
	return fposmod(float(lf["t"]) + i * float(lf["spacing"]), float(lf["loop"]))


func _process(delta: float) -> void:
	_t += delta
	for lf in lifts:
		# express while the player rides it, slowing down again before the unloading ramp
		var target := CHAIR_SPEED
		if not ride.is_empty() and ride["phase"] == "ride" and ride["lift"]["index"] == lf["index"]:
			var left := float(lf["up_len"]) - UNLOAD_BEFORE - _chair_s(lf, ride["chair"])
			target = CHAIR_SPEED * lerpf(1.0, RIDE_BOOST, clampf((left - 30.0) / 80.0, 0.0, 1.0))
		lf["speed"] = lerpf(float(lf["speed"]), target, 1.0 - exp(-1.2 * delta))
		lf["t"] = float(lf["t"]) + delta * float(lf["speed"])
	var cam := get_viewport().get_camera_3d()
	var cp := cam.global_position if cam else Vector3.ZERO
	var hidden := Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -500, 0))
	for lf in lifts:
		var b: Vector3 = lf["bottom"]
		var t: Vector3 = lf["top"]
		var mid := (b + t) * 0.5
		var riding: bool = not ride.is_empty() and ride["lift"]["index"] == lf["index"]
		if cp.distance_to(mid) > b.distance_to(t) * 0.5 + 1500.0 and not riding:
			continue
		var mm: MultiMesh = lf["mm"]
		var up_len: float = lf["up_len"]
		var xfs: Array[Transform3D] = []
		for i in mm.instance_count:
			var xf := _sample_loop(lf, float(lf["t"]) + i * float(lf["spacing"]))
			xfs.append(xf)
			mm.set_instance_transform(i, xf)
		# riders sit on the way up only (they get off at the top)
		var rmm: MultiMesh = lf["riders"]
		var slots: Array = lf["slots"]
		for k in slots.size():
			var ci: int = slots[k][0]
			var s := _chair_s(lf, ci)
			if s > LOAD_S and s < up_len - UNLOAD_BEFORE:
				rmm.set_instance_transform(k, xfs[ci] * Transform3D(Basis.IDENTITY, Vector3(slots[k][1], SEAT_Y, -0.02)))
			else:
				rmm.set_instance_transform(k, hidden)
	_update_ride()


# ------------------------------------------------------------------ riding
func load_point(lf: Dictionary) -> Vector3:
	var p := _sample_loop(lf, LOAD_S).origin
	p.y = terrain.height(p.x, p.z)
	return p


func unload_point(lf: Dictionary) -> Vector3:
	var p := _sample_loop(lf, float(lf["up_len"]) - UNLOAD_BEFORE).origin
	p.y = terrain.height(p.x, p.z)
	return p


## The lift whose loading point is near `pos`, or {}.
func lift_near(pos: Vector3, radius := 25.0) -> Dictionary:
	for lf in lifts:
		var lp := load_point(lf)
		if Vector2(pos.x - lp.x, pos.z - lp.z).length() < radius:
			return lf
	return {}


func is_riding() -> bool:
	return not ride.is_empty()


## Walk / ski onto the loading point and wait for the next chair (it arrives from behind).
func board(lf: Dictionary, s: Skier) -> void:
	if s.mode == Skier.Mode.WALK:
		s.toggle_skis()
	var mm: MultiMesh = lf["mm"]
	var best := 0
	var best_wait := INF
	for i in mm.instance_count:
		var wait := fposmod(LOAD_S - _chair_s(lf, i), float(lf["loop"])) / float(lf["speed"])
		if wait < 1.6:
			wait += float(lf["loop"]) / float(lf["speed"])
		if wait < best_wait:
			best_wait = wait
			best = i
	ride = {"lift": lf, "chair": best, "phase": "wait", "skier": s}
	var dir: Vector3 = lf["dir"]
	s.teleport(load_point(lf), Skier.yaw_of(dir), 0.0, true)
	s.frozen = true


## Drops any ride in progress (teleports, menus).
func abort_ride() -> void:
	if ride.is_empty():
		return
	var s: Skier = ride["skier"]
	s.frozen = false
	ride = {}
	if s.mode == Skier.Mode.LIFT:
		s.end_lift(s.position, s.heading, 0.0)


func cancel_wait() -> void:
	if not ride.is_empty() and ride["phase"] == "wait":
		(ride["skier"] as Skier).frozen = false
		ride = {}


func _seat_xform(lf: Dictionary, i: int) -> Transform3D:
	return _sample_loop(lf, float(lf["t"]) + i * float(lf["spacing"])) * Transform3D(Basis.IDENTITY, Vector3(-0.29, SEAT_Y, -0.02))


func _update_ride() -> void:
	if ride.is_empty():
		return
	var lf: Dictionary = ride["lift"]
	var i: int = ride["chair"]
	var s: Skier = ride["skier"]
	var cs := _chair_s(lf, i)
	if ride["phase"] == "wait":
		if fposmod(cs - LOAD_S, float(lf["loop"])) < 2.0:
			ride["phase"] = "ride"
			s.frozen = false
			s.begin_lift()
		else:
			return
	if cs >= float(lf["up_len"]) - UNLOAD_BEFORE:
		_unload()
		return
	var xf := _seat_xform(lf, i)
	var s0 := float(lf["t"]) + i * float(lf["spacing"])
	s.set_lift_xform(xf, (_sample_loop(lf, s0 + 1.0).origin - _sample_loop(lf, s0).origin) * float(lf["speed"]))


func _unload() -> void:
	var lf: Dictionary = ride["lift"]
	var s: Skier = ride["skier"]
	var dir: Vector3 = lf["dir"]
	var side: Vector3 = lf["side"]
	ride = {}
	# slide off the chair down the unload ramp, away from the bull wheel
	var p := unload_point(lf) + dir * 1.5 + side * 0.6
	s.end_lift(p, Skier.yaw_of((dir + side * 0.9).normalized()), 4.0)
	ride_finished.emit(lf["name"])


## Jumps to the top (hold the interact key while riding).
func skip_ride() -> void:
	if not ride.is_empty() and ride["phase"] == "ride":
		_unload()


## {name, phase, remaining (s), progress 0..1, wait (s)} while boarding / riding, else {}.
func ride_info() -> Dictionary:
	if ride.is_empty():
		return {}
	var lf: Dictionary = ride["lift"]
	var cs := _chair_s(lf, ride["chair"])
	var up_end := float(lf["up_len"]) - UNLOAD_BEFORE
	if ride["phase"] == "wait":
		return {"name": lf["name"], "phase": "wait", "wait": fposmod(LOAD_S - cs, float(lf["loop"])) / float(lf["speed"])}
	return {"name": lf["name"], "phase": "ride", "remaining": maxf(up_end - cs, 0.0) / (CHAIR_SPEED * RIDE_BOOST * 0.92),
		"progress": clampf((cs - LOAD_S) / (up_end - LOAD_S), 0.0, 1.0)}


# ------------------------------------------------------------------ pistes
func _build_piste_markers(p: Dictionary) -> void:
	var pts: Array = p["pts"]
	var col: Color = DIFF_COLORS.get(p["difficulty"], Color.WHITE)
	var m := _mat(col, 0.5)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.035
	pole.bottom_radius = 0.035
	pole.height = 1.8
	pole.radial_segments = 6
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pole
	var xf: Array[Transform3D] = []
	var w: float = p["width"] * 0.62
	var acc := 0.0
	for i in range(1, pts.size()):
		var a := Vector2(pts[i - 1][0], pts[i - 1][1])
		var b := Vector2(pts[i][0], pts[i][1])
		acc += a.distance_to(b)
		if acc < 45.0:
			continue
		acc = 0.0
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)
		for s: float in [-1.0, 1.0]:
			var q: Vector2 = b + n * w * s
			xf.append(Transform3D(Basis.IDENTITY, Vector3(q.x, terrain.height(q.x, q.y) + 0.8, q.y)))
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.visibility_range_end = 700.0
	add_child(mmi)
	if pts.size() > 2:
		var s0 := Vector3(pts[1][0], 0, pts[1][1])
		s0.y = terrain.height(s0.x, s0.z) + 3.0
		_label(s0, "%s  (%s)" % [p["name"], String(p["difficulty"]).capitalize()], 56, col.lightened(0.35))


func _build_kicker_markers() -> void:
	var m := _mat(Color(1.0, 0.45, 0.05), 0.5)
	for k in terrain.layout.get("kickers", []):
		var d := Vector2(k["dx"], k["dz"]).normalized()
		var n := Vector2(-d.y, d.x)
		var lip := Vector2(k["x"], k["z"])
		for s: float in [-1.0, 1.0]:
			var q := lip + n * 9.5 * s
			var c := CylinderMesh.new()
			c.top_radius = 0.05
			c.bottom_radius = 0.05
			c.height = 2.4
			var mi := MeshInstance3D.new()
			mi.mesh = c
			mi.material_override = m
			mi.position = Vector3(q.x, terrain.height(q.x, q.y) + 1.1, q.y)
			add_child(mi)
	if not terrain.layout.get("kickers", []).is_empty():
		var k0: Dictionary = terrain.layout["kickers"][0]
		_label(Vector3(k0["x"], terrain.height(k0["x"], k0["z"]) + 6.0, k0["z"]) - Vector3(k0["dx"], 0, k0["dz"]).normalized() * 20.0, "TERRAIN PARK", 90, Color(1, 0.6, 0.2))
