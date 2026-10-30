extends Node3D
## Terrain park jib line below the kickers on Meadow Way: boxes you can ride onto and raised rails
## you pop onto, in two lanes.  Also adds the "Terrain Park" drop zone and the "Rail Session"
## challenge to the layout.  The skier slides them through `rails` (see Skier._try_mount).

const PISTE := "Meadow Way"
const PLAN := [["box", 8.0], ["rail", 9.0], ["box", 12.0], ["rail", 11.0], ["box", 9.0], ["rail", 8.0]]
const HEIGHT := {"box": 0.35, "rail": 0.7}
const WIDTH := {"box": 0.5, "rail": 0.07}

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
	# walk down the piste from the last kicker, placing a feature every ~45 m, lanes alternating
	var along := 0.0
	var next := 45.0
	var idx := 0
	for i in range(start + 1, pts.size()):
		along += Vector2(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]).length()
		if along < next or idx >= PLAN.size():
			continue
		var p2 := Vector2(pts[i][0], pts[i][1])
		var t2 := (Vector2(pts[mini(i + 2, pts.size() - 1)][0], pts[mini(i + 2, pts.size() - 1)][1]) - Vector2(pts[i - 2][0], pts[i - 2][1])).normalized()
		var lane := 7.0 if idx % 2 == 0 else -7.0
		var c2 := p2 + Vector2(-t2.y, t2.x) * lane
		if terrain.slope_deg(c2.x, c2.y) > 22.0 or obstacles.clearance(c2.x, c2.y, 8.0) < 4.0:
			next = along + 10.0
			continue
		_add_feature(String(PLAN[idx][0]), float(PLAN[idx][1]), c2, t2, obstacles)
		idx += 1
		next = along + 45.0
	if rails.is_empty():
		return
	td.layout["rails"] = rails.map(func(r): return [r["a"].x, r["a"].z, r["b"].x, r["b"].z, r["kind"]])
	# drop zone at the top of the jib line, and a challenge that uses it
	var first: Dictionary = rails[0]
	var dir: Vector3 = (first["b"] - first["a"]).normalized()
	var dz := first["a"] as Vector3 - dir * 40.0
	dz.y = td.height(dz.x, dz.z)
	td.layout["drop_zones"].append({"name": "Terrain Park", "region": 4, "x": dz.x, "z": dz.z, "y": dz.y,
		"yaw": Skier.yaw_of(Vector3(dir.x, 0, dir.z)), "unlocked": true})
	td.layout["challenges"].append({"id": "jib_session", "type": "trick_specific", "name": "Rail Session", "region": 4,
		"drop": "Terrain Park", "trick": "jib", "count": 4, "time_limit": 150})
	var sign := Label3D.new()
	sign.text = "TERRAIN PARK"
	sign.font = UITheme.font(800)
	sign.font_size = 96
	sign.outline_size = 16
	sign.pixel_size = 0.012
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.modulate = Color(1.0, 0.75, 0.2)
	sign.position = dz + Vector3.UP * 4.0 + dir * 8.0
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
	rails.append({"a": a, "b": b, "kind": kind, "width": float(WIDTH[kind]), "length": length})
	var side := dir.cross(Vector3.UP).normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(ceil(length / 2.5))
	if kind == "rail":
		_bar(deck, a - Vector3.UP * 0.035, b - Vector3.UP * 0.035, 0.035)
		for k in n + 1:
			var q := a.lerp(b, float(k) / n) - Vector3.UP * 0.07
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
	top.material_override = _mat(Color(0.92, 0.93, 0.95) if kind == "box" else Color(0.95, 0.85, 0.15), 0.25, 0.6 if kind == "rail" else 0.0)
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
