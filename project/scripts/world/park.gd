extends Node3D
## Terrain park jib line below the kickers on Meadow Way: boxes you can ride onto and raised rails
## you pop onto, in three lanes.  Also adds the "Terrain Park" drop zone and the "Rail Session"
## challenge to the layout.  The skier slides them through `rails` (see Skier._try_mount).

const PISTE := "Meadow Way"
const PLAN := [["box", 8.0], ["rail", 9.0], ["box", 12.0], ["rail", 11.0], ["box", 9.0], ["rail", 8.0], ["tube", 14.0], ["flat_down", 12.0], ["box", 10.0]]
const HEIGHT := {"box": 0.35, "rail": 0.7, "tube": 0.6, "flat_down": 0.7}
const WIDTH := {"box": 1.2, "rail": 0.07, "tube": 0.5, "flat_down": 0.07}

var corridor: Array[Vector2] = []
var terrain: TerrainData
var rails: Array = []        # {a: Vector3, b: Vector3 (top line), kind, width, length}


func setup(td: TerrainData, obstacles: Obstacles) -> void:
	terrain = td
	var piste := {}
	for p in td.layout.get("pistes", []):
		if p["name"] == PISTE:
			piste = p
	var kickers: Array = td.layout.get("kickers", [])
	if piste.is_empty() or kickers.is_empty():
		return
	var pts: Array = piste["pts"]
	var last: Dictionary = kickers[kickers.size() - 1]
	var start := 0
	var best := INF
	for i in pts.size():
		var d := Vector2(pts[i][0] - last["x"], pts[i][1] - last["z"]).length()
		if d < best:
			best = d
			start = i
	# Three rows with forgiving boxes left, narrow jibs center and longer features right.
	var along := 0.0
	var next := 45.0
	var last_feature_index := start
	var row := 0
	for i in range(start + 1, pts.size()):
		along += Vector2(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]).length()
		if along < next or row >= 3:
			continue
		var p2 := Vector2(pts[i][0], pts[i][1])
		var t2 := (Vector2(pts[mini(i + 2, pts.size() - 1)][0], pts[mini(i + 2, pts.size() - 1)][1]) - Vector2(pts[i - 2][0], pts[i - 2][1])).normalized()
		var clear := true
		for lane in [-9.0, 0.0, 9.0]:
			var c: Vector2 = p2 + Vector2(-t2.y, t2.x) * lane
			clear = clear and terrain.slope_deg(c.x, c.y) < 22.0 and obstacles.clearance(c.x, c.y, 8.0) >= 4.0
		if not clear:
			next = along + 10.0
			continue
		for lane_index in 3:
			var idx := row * 3 + lane_index
			var c2 := p2 + Vector2(-t2.y, t2.x) * (lane_index - 1) * 9.0
			_add_feature(String(PLAN[idx][0]), float(PLAN[idx][1]), c2, t2, obstacles)
		last_feature_index = i
		row += 1
		next = along + 65.0
	if rails.is_empty():
		return
	td.layout["rails"] = rails.map(func(r): return [r["a"].x, r["a"].z, r["b"].x, r["b"].z, r["kind"]])
	# drop zone at the top of the jib line, and a challenge that uses it
	var first: Dictionary = rails[0]
	var dir: Vector3 = (first["b"] - first["a"]).normalized()
	var kickoff: Dictionary = kickers[0]
	var nearest := 0
	var nearest_distance := INF
	for i in pts.size():
		var distance := Vector2(pts[i][0] - kickoff["x"], pts[i][1] - kickoff["z"]).length()
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = i
	for i in range(maxi(nearest - 7, 0), mini(last_feature_index + 8, pts.size())):
		corridor.append(Vector2(pts[i][0], pts[i][1]))
	var launch: Array = pts[maxi(nearest - 5, 0)]
	var following: Array = pts[mini(maxi(nearest - 5, 0) + 1, pts.size() - 1)]
	dir = Vector3(following[0] - launch[0], 0, following[1] - launch[1]).normalized()
	var dz := Vector3(launch[0], 0, launch[1])
	dz.y = td.height(dz.x, dz.z)
	td.layout["drop_zones"].append({"name": "Terrain Park", "region": 4, "x": dz.x, "z": dz.z, "y": dz.y,
		"yaw": Skier.yaw_of(Vector3(dir.x, 0, dir.z)), "unlocked": true})
	td.layout["challenges"].append({"id": "jib_session", "type": "trick_specific", "name": "Rail Session", "region": 4,
		"drop": "Terrain Park", "trick": "jib", "count": 4, "time_limit": 150})
	var sign := Label3D.new()
	sign.text = "SUMMIT PARK\nKICKERS · BOXES · RAILS\nR — park start · B — retry feature"
	sign.font = UITheme.font(800)
	sign.font_size = 64
	sign.outline_size = 16
	sign.pixel_size = 0.006
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.modulate = Color(1.0, 0.75, 0.2)
	sign.position = dz + Vector3.UP * 3.0 + dir * 15.0 + dir.cross(Vector3.UP) * 10.0
	sign.visibility_range_end = 500.0
	add_child(sign)


func _add_feature(kind: String, length: float, c2: Vector2, t2: Vector2, obstacles: Obstacles) -> void:
	var dir := Vector3(t2.x, 0, t2.y)
	var h: float = HEIGHT[kind]
	var a := Vector3(c2.x, 0, c2.y) - dir * length * 0.5
	var b := Vector3(c2.x, 0, c2.y) + dir * length * 0.5
	a.y = terrain.height(a.x, a.z) + h
	b.y = terrain.height(b.x, b.z) + h
	# keep the top line clear of a snow bulge in the middle
	var lift := 0.0
	for k in range(1, 10):
		var q := a.lerp(b, k / 10.0)
		lift = maxf(lift, terrain.height(q.x, q.z) + h * 0.6 - q.y)
	a.y += lift
	b.y += lift
	var points: Array[Vector3] = [a, b]
	if kind == "flat_down":
		var middle := a.lerp(b, 0.5)
		middle.y = a.y
		points = [a, middle, b]
	var first_segment := rails.size()
	for j in range(points.size() - 1):
		rails.append({"a": points[j], "b": points[j+1], "kind": "box" if kind == "box" else "rail", "width": float(WIDTH[kind]), "length": points[j].distance_to(points[j+1])})
	if kind == "flat_down":
		rails[first_segment]["next"] = rails[first_segment+1]
	var side := dir.cross(Vector3.UP).normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(ceil(length / 2.5))
	if kind != "box":
		var radius := 0.25 if kind == "tube" else 0.035
		for j in range(points.size() - 1):
			_bar(deck, points[j] - Vector3.UP * radius, points[j+1] - Vector3.UP * radius, radius)
		for k in n + 1:
			var fraction := float(k) / n
			var q := (points[0].lerp(points[1], fraction * 2.0) if fraction <= 0.5 else points[1].lerp(points[2], (fraction - 0.5) * 2.0)) if kind == "flat_down" else a.lerp(b, fraction)
			q -= Vector3.UP * radius * 2.0
			_bar(st, q, Vector3(q.x, terrain.height(q.x, q.z) - 0.3, q.z), 0.045)
			obstacles.add(q.x, q.z, 0.2, q.y - 1.6, q.y + 0.05, Obstacles.Kind.POLE)
	else:
		var w: float = WIDTH[kind] * 0.5
		for k in n:
			var q0 := a.lerp(b, float(k) / n)
			var q1 := a.lerp(b, float(k + 1) / n)
			_quad(deck, q0 - side * w, q0 + side * w, q1 + side * w, q1 - side * w)
			for s: float in [-1.0, 1.0]:
				var g0 := Vector3(q0.x, terrain.height(q0.x, q0.z) - 0.3, q0.z) + side * (w * s)
				var g1 := Vector3(q1.x, terrain.height(q1.x, q1.z) - 0.3, q1.z) + side * (w * s)
				if s > 0.0:
					_quad(st, q0 + side * w, g0, g1, q1 + side * w)
				else:
					_quad(st, q1 - side * w, g1, g0, q0 - side * w)
	st.generate_normals()
	deck.generate_normals()
	var body := MeshInstance3D.new()
	body.mesh = st.commit()
	body.material_override = _mat(Color(1.0, 0.55, 0.05) if kind == "box" else Color(0.15, 0.15, 0.17), 0.5)
	add_child(body)
	var top := MeshInstance3D.new()
	top.mesh = deck.commit()
	top.material_override = _mat(Color(0.12, 0.25, 0.34) if kind == "box" else Color(0.95, 0.85, 0.15), 0.25, 0.6 if kind == "rail" else 0.0)
	add_child(top)


func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	for v in [p0, p1, p2, p0, p2, p3]:
		st.add_vertex(v)


func _bar(st: SurfaceTool, a: Vector3, b: Vector3, r: float) -> void:
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	for k in 8:
		var a0 := TAU * k / 8.0
		var a1 := TAU * (k + 1) / 8.0
		var o0 := (x * cos(a0) + z * sin(a0)) * r
		var o1 := (x * cos(a1) + z * sin(a1)) * r
		_quad(st, a + o0, b + o0, b + o1, a + o1)


func contains_position(p: Vector3) -> bool:
	for i in range(1, corridor.size()):
		if Geometry2D.get_closest_point_to_segment(Vector2(p.x,p.z), corridor[i-1],corridor[i]).distance_to(Vector2(p.x,p.z)) < 60.0:
			return true
	return false


func practice_start(p: Vector3) -> Dictionary:
	var best := INF
	var result := {}
	for feature in rails:
		var a: Vector3 = feature["a"]
		var distance := p.distance_squared_to(a)
		if distance < best:
			best = distance
			var direction: Vector3 = (feature["b"] - a).normalized()
			result = {"position": a - direction * 20.0, "yaw": Skier.yaw_of(direction)}
	for kicker in terrain.layout.get("kickers", []):
		var center := Vector3(kicker["x"], terrain.height(kicker["x"], kicker["z"]), kicker["z"])
		if p.distance_squared_to(center) < best:
			best = p.distance_squared_to(center)
			var direction := Vector3(kicker["dx"], 0, kicker["dz"]).normalized()
			result = {"position": center - direction * 35.0, "yaw": Skier.yaw_of(direction)}
	return result
