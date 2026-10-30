extends Node
## Skier sound: continuous layers (wind, snow slide, carve, powder, ice, ambience) mixed from the
## physics state, plus one-shots for jumps, landings, crashes and tree hits.

var skier: Skier
var layers := {}
var _pole_cd := 0.0
var _last_step := 0
var _prev_edgeb := 0.0


func setup(s: Skier) -> void:
	skier = s
	for n in ["wind", "slide", "carve", "powder", "ice", "rail"]:
		layers[n] = _loop(n + "_loop", "SFX")
	layers["ambient"] = _loop("ambient_loop", "Ambience")
	(layers["ambient"] as AudioStreamPlayer).volume_db = -14.0
	s.jumped.connect(func(_st): Sfx.play("jump", -6.0, randf_range(0.95, 1.08)))
	s.landed.connect(_on_landed)
	s.crashed.connect(_on_crashed)
	s.tree_brush.connect(func(_p, st): Sfx.play("tree_hit", -12.0 + st * 6.0, randf_range(0.9, 1.1)))
	s.mode_changed.connect(func(m: int):
		if m != Skier.Mode.LIFT:
			Sfx.play("binding", -8.0, randf_range(0.95, 1.05)))


func _loop(name: String, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var st := Sfx.get_stream(name)
	if st is AudioStreamWAV:
		var w := st as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	p.stream = st
	p.bus = bus
	p.volume_db = -60.0
	p.autoplay = false
	add_child(p)
	if st:
		p.play()
	return p


func _mix(name: String, vol: float, pitch := 1.0, dt := 0.016) -> void:
	var p: AudioStreamPlayer = layers[name]
	var target := linear_to_db(maxf(vol, 0.0005))
	p.volume_db = lerpf(p.volume_db, target, 1.0 - exp(-10.0 * dt))
	p.pitch_scale = clampf(lerpf(p.pitch_scale, pitch, 1.0 - exp(-6.0 * dt)), 0.5, 2.5)


func _process(delta: float) -> void:
	if skier == null:
		return
	var dt := minf(delta, 0.05)
	var sp := skier.speed
	var on_snow := not skier.airborne and skier.contact and not skier.is_crashed and skier.mode == Skier.Mode.SKI
	var groomed := skier.surface.g
	var powder := skier.surface.r * (1.0 - groomed)
	var ice := skier.surface.b * (1.0 - groomed)
	var v := clampf(sp / 30.0, 0.0, 1.0)
	_mix("wind", 0.04 + 0.9 * v * v, 0.8 + 0.6 * v, dt)
	var slide := clampf(sp / 18.0, 0.0, 1.0) * (1.0 - powder * 0.7) if on_snow else 0.0
	_mix("slide", slide * 0.45, 0.85 + 0.35 * v, dt)
	var carve := clampf(skier.carve_g / 14.0 + skier.skid * 0.9, 0.0, 1.0) * (1.0 if on_snow else 0.0) * clampf(sp / 6.0, 0.0, 1.0)
	_mix("carve", carve * 0.6, 0.9 + 0.3 * v, dt)
	_mix("powder", (clampf(sp / 15.0, 0.0, 1.0) * powder if on_snow else 0.0) * 0.7, 0.9 + 0.2 * v, dt)
	_mix("ice", (clampf(sp / 15.0, 0.0, 1.0) * ice if on_snow else 0.0) * 0.4, 1.0 + 0.3 * v, dt)
	var on_rail := skier.is_grinding()
	_mix("rail", clampf(sp / 8.0, 0.25, 1.0) * 0.55 if on_rail else 0.0, (1.0 if on_rail and skier.grind["kind"] == "rail" else 0.7) + sp * 0.01, dt)
	# footsteps on foot: one crunch per half gait cycle
	if skier.mode == Skier.Mode.WALK and skier.contact:
		var step := int(floor((skier.walk_phase + PI * 0.5) / PI))
		if step != _last_step:
			_last_step = step
			if skier.speed > 0.3:
				Sfx.play("step%d" % (step % 2), -15.0 + skier.speed * 1.5, randf_range(0.9, 1.1))
	# hockey stop: edges biting in
	if skier.edge_brake > 0.3 and _prev_edgeb <= 0.3 and sp > 5.0:
		Sfx.play("hockey_stop", -12.0 + minf(sp, 20.0) * 0.4, randf_range(0.92, 1.06))
	_prev_edgeb = skier.edge_brake
	# pole plants when pushing on the flats
	_pole_cd -= dt
	if skier.pushing > 0.5 and _pole_cd <= 0.0:
		Sfx.play("pole", -16.0, randf_range(0.9, 1.1))
		_pole_cd = 0.9


func _on_landed(info: Dictionary) -> void:
	var impact: float = info["impact"]
	if info["air_time"] < 0.25 and impact < 3.0:
		return
	if impact > 9.0:
		Sfx.play("land_hard", -2.0, randf_range(0.92, 1.05))
	else:
		Sfx.play("land_soft", -8.0 + impact * 0.6, randf_range(0.95, 1.1))


func _on_crashed(_reason: String, _v: Vector3) -> void:
	Sfx.play("crash", -1.0, randf_range(0.9, 1.05))
