extends Node3D
## Snow effects: ski spray, powder plumes, landing/crash/tree bursts, ambient wind-blown snow
## and ski tracks (ribbon meshes built in chunks).

const TRACK_STEP := 0.45
const CHUNK_POINTS := 96
const MAX_CHUNKS := 48

var skier: Skier
var body: SkierBody
var terrain: TerrainData
var spray_l: GPUParticles3D
var spray_r: GPUParticles3D
var powder: GPUParticles3D
var burst: GPUParticles3D
var puff: GPUParticles3D
var ambient: GPUParticles3D
var track_mat: StandardMaterial3D
var _tracks := {}
var _old_chunks: Array[MeshInstance3D] = []
var _detail := 2


func setup(s: Skier, b: SkierBody, td: TerrainData) -> void:
	skier = s
	body = b
	terrain = td
	top_level = true
	_detail = int(Settings.get_value("graphics", "detail"))
	var puff_tex: Texture2D = load("res://assets/textures/puff.png")
	var flake_tex: Texture2D = load("res://assets/textures/flake.png")
	spray_l = _make_spray(puff_tex)
	spray_r = _make_spray(puff_tex)
	powder = _make_powder(puff_tex)
	burst = _make_burst(puff_tex, 90, 1.4)
	puff = _make_burst(puff_tex, 50, 1.6)
	ambient = _make_ambient(flake_tex)
	track_mat = StandardMaterial3D.new()
	track_mat.vertex_color_use_as_albedo = true
	track_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	track_mat.roughness = 0.95
	track_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in ["l", "r"]:
		_tracks[side] = {"points": [], "mi": null, "last": Vector3.INF}
	s.landed.connect(_on_landed)
	s.crashed.connect(_on_crashed)
	s.tree_brush.connect(_on_tree)
	s.respawned.connect(_break_tracks)
	s.teleported.connect(_teleported)
	Settings.changed.connect(_on_settings)
	_make_prints()
	_apply_weather()


func _on_settings(section: String, _k: String) -> void:
	if section == "graphics" or section == "world":
		_detail = int(Settings.get_value("graphics", "detail"))
		_apply_weather()


## Falling snow follows the weather setting: none when clear, a blizzard in a storm.
func _apply_weather() -> void:
	var w := String(Settings.get_value("world", "weather"))
	var mul: float = {"clear": 0.0, "snowing": 1.0, "storm": 2.5, "fog": 0.3}.get(w, 1.0)
	ambient.emitting = mul > 0.0
	ambient.amount = maxi(int([300, 700, 1400, 2400][clampi(_detail, 0, 3)] * mul), 1)
	var pm := ambient.process_material as ParticleProcessMaterial
	var wind := 4.0 if w == "storm" else 1.0
	pm.initial_velocity_min = 1.0 * wind
	pm.initial_velocity_max = 3.5 * wind
	pm.gravity = Vector3(0.6 * wind * 2.0, -0.9, 0.3 * wind * 2.0)


# ------------------------------------------------------------------ boot prints
const MAX_PRINTS := 240
var _prints: MultiMesh
var _print_n := 0
var _last_step := 0


func _make_prints() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	var m := StandardMaterial3D.new()
	m.albedo_texture = gt
	m.albedo_color = Color(0.32, 0.42, 0.6, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.14, 0.32)
	_prints = MultiMesh.new()
	_prints.transform_format = MultiMesh.TRANSFORM_3D
	_prints.mesh = pm
	_prints.instance_count = MAX_PRINTS
	_prints.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _prints
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1, -1, -1) * 1e5, Vector3.ONE * 2e5)
	add_child(mi)


func _update_prints() -> void:
	if skier.mode != Skier.Mode.WALK or not skier.contact or skier.speed < 0.3:
		return
	var step := int(floor((skier.walk_phase + PI * 0.5) / PI))
	if step == _last_step:
		return
	_last_step = step
	var foot: Vector3 = body.joints.get("ankle_l" if step % 2 == 0 else "ankle_r", skier.position)
	foot.y = terrain.height(foot.x, foot.z) + 0.015
	var b := Basis(Vector3.UP, skier.heading)
	_prints.set_instance_transform(_print_n % MAX_PRINTS, Transform3D(b, foot))
	_print_n += 1
	_prints.visible_instance_count = mini(_print_n, MAX_PRINTS)


func _snow_material(tex: Texture2D, tint := Color(1, 1, 1)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.roughness = 1.0
	m.disable_receive_shadows = false
	return m


func _alpha_ramp(a0: float, a1: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, a0))
	g.set_color(1, Color(1, 1, 1, a1))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _grow_curve(s0: float, s1: float) -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0, s0))
	c.add_point(Vector2(1, s1))
	var t := CurveTexture.new()
	t.curve = c
	return t


func _quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	return q


func _make_spray(tex: Texture2D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 140
	p.lifetime = 0.9
	p.local_coords = false
	p.emitting = true
	p.amount_ratio = 0.0
	p.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 30, 60))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, -7.0, 0)
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.scale_min = 0.25
	pm.scale_max = 0.6
	pm.scale_curve = _grow_curve(0.5, 1.6)
	pm.color_ramp = _alpha_ramp(0.75, 0.0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.12, 0.05, 0.4)
	p.process_material = pm
	p.draw_pass_1 = _quad(1.0)
	p.material_override = _snow_material(tex)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _make_powder(tex: Texture2D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 110
	p.lifetime = 1.8
	p.local_coords = false
	p.emitting = true
	p.amount_ratio = 0.0
	p.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 40, 80))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.5
	pm.gravity = Vector3(0, -1.2, 0)
	pm.damping_min = 0.8
	pm.damping_max = 1.6
	pm.scale_min = 0.8
	pm.scale_max = 1.8
	pm.scale_curve = _grow_curve(0.6, 2.4)
	pm.color_ramp = _alpha_ramp(0.45, 0.0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.5, 0.2, 0.8)
	p.process_material = pm
	p.draw_pass_1 = _quad(1.0)
	p.material_override = _snow_material(tex)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _make_burst(tex: Texture2D, count: int, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = count
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-20, -10, -20), Vector3(40, 30, 40))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 75.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0, -5.0, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.scale_min = 0.5 * size
	pm.scale_max = 1.2 * size
	pm.scale_curve = _grow_curve(0.5, 1.8)
	pm.color_ramp = _alpha_ramp(0.7, 0.0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	p.process_material = pm
	p.draw_pass_1 = _quad(1.0)
	p.material_override = _snow_material(tex)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _make_ambient(tex: Texture2D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = [300, 700, 1400, 2400][clampi(_detail, 0, 3)]
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.local_coords = false
	p.emitting = true
	p.visibility_aabb = AABB(Vector3(-60, -40, -60), Vector3(120, 80, 120))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(40, 14, 40)
	pm.direction = Vector3(1, -0.3, 0.4)
	pm.spread = 25.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0.6, -0.9, 0.3)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	pm.turbulence_noise_scale = 4.0
	pm.scale_min = 0.012
	pm.scale_max = 0.035
	pm.color_ramp = _alpha_ramp(0.9, 0.0)
	p.process_material = pm
	p.draw_pass_1 = _quad(1.0)
	var m := _snow_material(tex)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# flakes right in front of the lens fade out instead of becoming big blobs
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 0.6
	m.distance_fade_max_distance = 3.5
	p.material_override = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


# ------------------------------------------------------------------ per frame
func _process(_delta: float) -> void:
	if skier == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam:
		ambient.global_position = cam.global_position + Vector3(0, 6, 0) - Vector3(1, -0.3, 0.4) * 10.0
	_update_prints()
	if skier.is_crashed or skier.mode != Skier.Mode.SKI:
		spray_l.amount_ratio = 0.0
		spray_r.amount_ratio = 0.0
		powder.amount_ratio = 0.0
		if skier.mode != Skier.Mode.SKI:
			_break_tracks()
		return
	var sp := skier.speed
	var grounded := not skier.airborne and skier.contact
	var pdepth := skier.surface.r * (1.0 - skier.surface.g)
	# spray from the outside edges, stronger while skidding / carving hard
	var intensity := 0.0
	if grounded and sp > 2.5:
		intensity = clampf(skier.skid * 1.2 + skier.carve_g / 16.0 + (sp - 2.5) / 40.0, 0.0, 1.0)
		intensity *= 1.0 - 0.6 * skier.surface.b * (1.0 - skier.surface.g)
	var hv := Vector3(skier.vel.x, 0.0, skier.vel.z)
	var back := -hv.normalized() if hv.length() > 0.5 else Vector3.ZERO
	var side_dir := Vector3.ZERO
	if absf(skier.yaw_rate) > 0.05:
		var right := Skier.forward_flat_s(skier.heading).cross(Vector3.UP)
		side_dir = right * -signf(skier.yaw_rate)      # outside of the turn
	if skier.edge_brake > 0.2 and hv.length() > 1.0:
		# hockey stop: a sheet of snow thrown ahead, in the direction of travel
		side_dir = hv.normalized() * 1.6
		back = Vector3.ZERO
		intensity = maxf(intensity, clampf(skier.edge_brake * sp / 8.0, 0.0, 1.0))
	for i in 2:
		var ps: GPUParticles3D = spray_l if i == 0 else spray_r
		var xf: Transform3D = body.ski_l if i == 0 else body.ski_r
		ps.global_position = xf.origin + xf.basis.z * 0.45 + Vector3.UP * 0.05
		var pm: ParticleProcessMaterial = ps.process_material
		var dir := (Vector3.UP * 0.9 + side_dir * 1.2 + back * 0.4).normalized()
		pm.direction = dir
		pm.initial_velocity_max = 2.0 + sp * 0.18 + skier.skid * 4.0
		ps.amount_ratio = intensity
	powder.global_position = skier.position + back * 0.6 + Vector3.UP * 0.2
	powder.amount_ratio = clampf(pdepth * (sp - 3.0) / 10.0, 0.0, 1.0) if grounded else 0.0
	_update_tracks(grounded, pdepth)


func _on_landed(info: Dictionary) -> void:
	var impact: float = info["impact"]
	if info["air_time"] < 0.3 and impact < 4.0:
		return
	burst.global_position = skier.position + Vector3.UP * 0.2
	(burst.process_material as ParticleProcessMaterial).initial_velocity_max = 3.0 + impact * 0.5
	burst.amount_ratio = clampf(0.35 + impact / 14.0, 0.3, 1.0)
	burst.restart()


func _on_crashed(_reason: String, v: Vector3) -> void:
	burst.global_position = skier.position + Vector3.UP * 0.4
	burst.amount_ratio = 1.0
	(burst.process_material as ParticleProcessMaterial).initial_velocity_max = 4.0 + v.length() * 0.3
	burst.restart()
	_break_tracks()


func _on_tree(pos: Vector3, strength: float) -> void:
	puff.global_position = pos + Vector3.UP * 1.5
	puff.amount_ratio = strength
	puff.restart()


## Moved to a new spot: no track joins the old spot to the new one, no spray carries over.
func _teleported() -> void:
	_break_tracks()
	spray_l.amount_ratio = 0.0
	spray_r.amount_ratio = 0.0
	powder.amount_ratio = 0.0


# ------------------------------------------------------------------ tracks
func _break_tracks() -> void:
	for side in _tracks:
		_freeze(side)
		_tracks[side]["last"] = Vector3.INF


func _update_tracks(grounded: bool, pdepth: float) -> void:
	for side in ["l", "r"]:
		var t: Dictionary = _tracks[side]
		if not grounded or skier.speed < 0.5:
			if not (t["points"] as Array).is_empty():
				_freeze(side)
			t["last"] = Vector3.INF
			continue
		var xf: Transform3D = body.ski_l if side == "l" else body.ski_r
		var p := xf.origin
		p.y = terrain.height(p.x, p.z)
		var last: Vector3 = t["last"]
		if last != Vector3.INF and p.distance_to(last) < TRACK_STEP:
			continue
		var n := terrain.normal(p.x, p.z, 1.0)
		var width := 0.07 + pdepth * 0.22 + skier.skid * 0.25
		var shade := 1.0 - 0.18 - pdepth * 0.12
		(t["points"] as Array).append([p + n * 0.05, n, width, shade])
		t["last"] = p
		_rebuild(side)
		if (t["points"] as Array).size() >= CHUNK_POINTS:
			_freeze(side)
			(t["points"] as Array).append([p + n * 0.05, n, width, shade])


func _rebuild(side: String) -> void:
	var t: Dictionary = _tracks[side]
	var pts: Array = t["points"]
	if t["mi"] == null:
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		mi.material_override = track_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		t["mi"] = mi
	var im: ImmediateMesh = (t["mi"] as MeshInstance3D).mesh
	im.clear_surfaces()
	if pts.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in pts.size():
		var a: Array = pts[i]
		var p: Vector3 = a[0]
		var n: Vector3 = a[1]
		var nxt: Vector3 = (pts[mini(i + 1, pts.size() - 1)] as Array)[0]
		var prv: Vector3 = (pts[maxi(i - 1, 0)] as Array)[0]
		var dir := (nxt - prv).normalized()
		var side_v := dir.cross(n).normalized() * float(a[2]) * 0.5
		var s: float = a[3]
		var c := Color(0.86 * s, 0.9 * s, 0.99 * s, 0.38)
		im.surface_set_color(c)
		im.surface_set_normal(n)
		im.surface_add_vertex(p - side_v)
		im.surface_set_color(c)
		im.surface_set_normal(n)
		im.surface_add_vertex(p + side_v)
	im.surface_end()


func _freeze(side: String) -> void:
	var t: Dictionary = _tracks[side]
	if t["mi"] != null:
		_old_chunks.append(t["mi"])
		t["mi"] = null
		while _old_chunks.size() > MAX_CHUNKS:
			var old: MeshInstance3D = _old_chunks.pop_front()
			old.queue_free()
	t["points"] = []
