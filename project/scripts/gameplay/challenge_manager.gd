class_name ChallengeManager
extends Node3D
## Runs one challenge at a time: races through checkpoint gates (medals by time), freestyle
## score / specific trick / combo challenges and extreme no-fall descents.

signal finished(id: String, result: Dictionary)

var terrain: TerrainData
var world: World
var skier: Skier
var tricks: TrickSystem
var hud: HUD
var active := {}
var phase := ""            # "" | countdown | running
var timer := 0.0
var countdown := 0.0
var cp_index := 0
var score := 0
var count := 0
var start_y := 0.0
var _gates: Array[Node3D] = []
var _beacon: MeshInstance3D
var _last_cp_pos := Vector3.ZERO
var _last_cp_yaw := 0.0
var _gate_mat: StandardMaterial3D
var _gate_next_mat: StandardMaterial3D
var _cd_shown := 0


func setup(w: World, t: TrickSystem, h: HUD) -> void:
	world = w
	terrain = w.terrain
	skier = w.skier
	tricks = t
	hud = h
	t.trick_landed.connect(_on_trick)
	t.combo_banked.connect(_on_banked)
	skier.crashed.connect(_on_crash)
	_gate_mat = StandardMaterial3D.new()
	_gate_mat.albedo_color = Color(0.2, 0.45, 1.0)
	_gate_next_mat = StandardMaterial3D.new()
	_gate_next_mat.albedo_color = Color(1.0, 0.45, 0.1)
	_gate_next_mat.emission_enabled = true
	_gate_next_mat.emission = Color(1.0, 0.4, 0.05)
	_gate_next_mat.emission_energy_multiplier = 1.5
	_beacon = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.6
	cyl.height = 120.0
	_beacon.mesh = cyl
	cyl.top_radius = 0.9
	cyl.bottom_radius = 0.9
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(1.0, 0.5, 0.12, 0.45)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.disable_fog = true
	bm.no_depth_test = false
	_beacon.material_override = bm
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# only visible from a distance: a guide toward the next gate, never a wall in front of the camera
	_beacon.visibility_range_begin = 45.0
	_beacon.visibility_range_begin_margin = 15.0
	_beacon.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_beacon.visible = false
	add_child(_beacon)


## Position of the next race gate (for the minimap), or Vector3.INF.
func next_gate() -> Vector3:
	if active.is_empty() or active.get("type", "") != "race" or cp_index >= _gates.size():
		return Vector3.INF
	return _gates[cp_index].global_position


func is_active() -> bool:
	return not active.is_empty()


func describe(c: Dictionary) -> String:
	match c["type"]:
		"race":
			return "Race through %d gates. Gold %s" % [c["checkpoints"].size(), UITheme.format_time(c["medals"][0])]
		"trick_score":
			return "Score %s points in %d s" % [HUD._thousands(int(c["target"][2])), int(c["time_limit"])]
		"trick_specific":
			return "Land %d × %s in %d s" % [int(c["count"]), _trick_label(c["trick"]), int(c["time_limit"])]
		"trick_combo":
			return "Bank a combo of %d+ tricks in %d s" % [int(c["combo"]), int(c["time_limit"])]
		"extreme":
			return "Descend %d m without crashing" % int(c["drop_req"])
	return ""


func _trick_label(t: String) -> String:
	if t == "grab":
		return "grab"
	if t == "jib":
		return "rail / box slide"
	return t + "° spin"


func start(id: String) -> void:
	stop(false)
	var c := terrain.challenge(id)
	if c.is_empty():
		return
	active = c
	timer = 0.0
	cp_index = 0
	score = 0
	count = 0
	# start position
	if c["type"] == "race":
		world.spawn(Vector3(c["start"][0], 0, c["start"][1]), float(c["yaw"]))
	else:
		world.spawn_at_drop(c["drop"])
	start_y = skier.position.y
	_last_cp_pos = skier.position
	_last_cp_yaw = skier.heading
	if c["type"] == "race":
		_build_gates()
	phase = "countdown"
	countdown = 3.0
	_cd_shown = 0
	skier.frozen = true
	_update_hud()


func restart() -> void:
	if is_active():
		start(active["id"])


func stop(show := true) -> void:
	for g in _gates:
		g.queue_free()
	_gates.clear()
	_beacon.visible = false
	if show and is_active():
		hud.notify("Challenge abandoned", "warning")
	active = {}
	phase = ""
	skier.frozen = false
	hud.set_challenge("", "")


func _build_gates() -> void:
	var cps: Array = active["checkpoints"]
	var prev := Vector3(active["start"][0], 0, active["start"][1])
	for i in cps.size():
		var c: Array = cps[i]
		var p := Vector3(c[0], terrain.height(c[0], c[1]), c[1])
		var dir := Vector3(p.x - prev.x, 0, p.z - prev.z).normalized()
		prev = p
		var g := Node3D.new()
		g.position = p
		g.basis = Basis.looking_at(dir, Vector3.UP)
		for s in [-1.0, 1.0]:
			var pole := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.09
			cm.bottom_radius = 0.09
			cm.height = 3.6
			pole.mesh = cm
			pole.position = Vector3(s * 7.0, 1.6, 0)
			g.add_child(pole)
		var banner := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(14.2, 0.9, 0.08)
		banner.mesh = bm
		banner.position = Vector3(0, 3.4, 0)
		g.add_child(banner)
		var l := Label3D.new()
		l.text = "FINISH" if i == cps.size() - 1 else str(i + 1)
		l.font = UITheme.font(800)
		l.font_size = 96
		l.pixel_size = 0.01
		l.outline_size = 16
		l.position = Vector3(0, 3.4, -0.1)
		l.rotation.y = PI
		g.add_child(l)
		add_child(g)
		_gates.append(g)
	_color_gates()


func _color_gates() -> void:
	for i in _gates.size():
		var m := _gate_next_mat if i == cp_index else _gate_mat
		for ch in _gates[i].get_children():
			if ch is MeshInstance3D:
				(ch as MeshInstance3D).material_override = m
		_gates[i].visible = i >= cp_index and i < cp_index + 4
	if cp_index < _gates.size():
		_beacon.visible = true
		_beacon.global_position = _gates[cp_index].global_position + Vector3.UP * 60.0


func respawn_in_challenge() -> bool:
	if not is_active() or phase != "running":
		return false
	if active["type"] == "race":
		skier.teleport(_last_cp_pos, _last_cp_yaw)
		world.camera.snap()
		return true
	if active["type"] == "extreme":
		restart()
		return true
	return false


func _process(delta: float) -> void:
	if not is_active():
		return
	if phase == "countdown":
		countdown -= delta
		var now := int(ceil(countdown))
		if now != _cd_shown and now > 0:
			_cd_shown = now
			hud.big_message(str(now), UITheme.TEXT, 0.6)
			Sfx.play("beep", -4.0)
		if countdown <= 0.0:
			phase = "running"
			skier.frozen = false
			hud.big_message("GO!", UITheme.ACCENT, 0.7)
			Sfx.play("go", -2.0)
		_update_hud()
		return
	if phase != "running":
		return
	timer += delta
	match active["type"]:
		"race":
			_race_update()
		"extreme":
			if start_y - skier.position.y >= float(active["drop_req"]):
				var lim := float(active["time_limit"])
				var medal := 3 if timer < lim * 0.45 else (2 if timer < lim * 0.7 else 1)
				_finish({"completed": true, "medal": medal, "time": timer})
				return
	if active.has("time_limit") and active["type"] != "race" and timer >= float(active["time_limit"]):
		_time_up()
		return
	_update_hud()


func _race_update() -> void:
	var cps: Array = active["checkpoints"]
	if cp_index >= cps.size():
		return
	var c: Array = cps[cp_index]
	var gp := Vector2(c[0], c[1])
	var p := Vector2(skier.position.x, skier.position.z)
	if gp.distance_to(p) < 13.0:
		cp_index += 1
		_last_cp_pos = Vector3(c[0], 0, c[1])
		_last_cp_yaw = skier.heading
		if cp_index >= cps.size():
			var m: Array = active["medals"]
			var medal := 3 if timer <= m[0] else (2 if timer <= m[1] else (1 if timer <= m[2] else 0))
			_finish({"completed": medal > 0, "medal": medal, "time": timer})
			return
		Sfx.play("checkpoint", -4.0)
		_color_gates()


func _time_up() -> void:
	var t: String = active["type"]
	var result := {"completed": false, "medal": 0, "score": score}
	if t == "trick_score":
		var tg: Array = active["target"]
		var medal := 3 if score >= tg[0] else (2 if score >= tg[1] else (1 if score >= tg[2] else 0))
		result = {"completed": medal > 0, "medal": medal, "score": score}
	_finish(result)


func _on_trick(t: Dictionary) -> void:
	if phase != "running":
		return
	match active.get("type", ""):
		"trick_specific":
			var want: String = active["trick"]
			var ok := false
			if want == "grab":
				ok = int(t["grabs"]) > 0
			elif want == "jib":
				ok = "jib" in t.get("tags", [])
			else:
				ok = int(t["spin"]) >= int(want)
			if ok:
				count += 1
				Sfx.play("checkpoint", -6.0)
				if count >= int(active["count"]):
					var lim := float(active["time_limit"])
					var medal := 3 if timer < lim * 0.5 else (2 if timer < lim * 0.75 else 1)
					_finish({"completed": true, "medal": medal, "time": timer})
	_update_hud()


func _on_banked(total: int, n: int) -> void:
	if phase != "running":
		return
	match active.get("type", ""):
		"trick_score":
			score += total
			var tg: Array = active["target"]
			if score >= int(tg[0]):
				_finish({"completed": true, "medal": 3, "score": score})
		"trick_combo":
			if n >= int(active["combo"]):
				var medal := 3 if total >= 6000 else (2 if total >= 3000 else 1)
				_finish({"completed": true, "medal": medal, "score": total})
	_update_hud()


func _on_crash(_reason: String, _v: Vector3) -> void:
	if phase == "running" and active.get("type", "") == "extreme":
		_finish({"completed": false, "medal": 0, "failed": "Crashed"})


func _finish(result: Dictionary) -> void:
	var id: String = active["id"]
	var name: String = active["name"]
	var improved := Game.record_challenge(id, result)
	var medal := int(result.get("medal", 0))
	if result.get("completed", false):
		hud.big_message(UITheme.medal_name(medal).to_upper() + "!", UITheme.medal_color(medal), 2.5, 80)
		Sfx.play("medal", -2.0)
		var detail := ""
		if result.has("time"):
			detail = UITheme.format_time(result["time"])
		elif result.has("score"):
			detail = HUD._thousands(int(result["score"])) + " pts"
		hud.notify("%s complete — %s medal  %s%s" % [name, UITheme.medal_name(medal), detail, "  (new best)" if improved else ""], "score")
	else:
		hud.big_message("FAILED", Color(1, 0.45, 0.4), 2.0, 72)
		Sfx.play("fail", -4.0)
		hud.notify("%s failed%s — press %s to retry from the pause menu" % [name, (": " + str(result["failed"])) if result.has("failed") else "", "Esc"], "warning")
	finished.emit(id, result)
	stop(false)


func _update_hud() -> void:
	if not is_active():
		return
	var c := active
	var title: String = c["name"].to_upper()
	var t: String = c["type"]
	var line1 := ""
	var line2 := ""
	if phase == "countdown":
		line1 = describe(c)
		line2 = "Get ready..."
		hud.set_challenge(title, line1, line2)
		return
	match t:
		"race":
			line1 = "%s    Gate %d / %d" % [UITheme.format_time(timer), mini(cp_index + 1, c["checkpoints"].size()), c["checkpoints"].size()]
			var m: Array = c["medals"]
			line2 = "Gold %s · Silver %s · Bronze %s" % [UITheme.format_time(m[0]), UITheme.format_time(m[1]), UITheme.format_time(m[2])]
		"trick_score":
			var tg: Array = c["target"]
			line1 = "%s pts    %d s left" % [HUD._thousands(score), int(ceil(float(c["time_limit"]) - timer))]
			line2 = "Gold %s · Silver %s · Bronze %s (banked combos)" % [HUD._thousands(int(tg[0])), HUD._thousands(int(tg[1])), HUD._thousands(int(tg[2]))]
		"trick_specific":
			line1 = "%d / %d × %s    %d s left" % [count, int(c["count"]), _trick_label(c["trick"]), int(ceil(float(c["time_limit"]) - timer))]
		"trick_combo":
			line1 = "Combo of %d+ tricks    %d s left" % [int(c["combo"]), int(ceil(float(c["time_limit"]) - timer))]
			line2 = "Gold 6,000 · Silver 3,000 points"
		"extreme":
			line1 = "Descended %d / %d m" % [int(maxf(start_y - skier.position.y, 0.0)), int(c["drop_req"])]
			line2 = "%s · don't crash" % UITheme.format_time(timer)
	hud.set_challenge(title, line1, line2)
