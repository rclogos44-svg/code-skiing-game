class_name World
extends Node3D
## Builds and owns the 3D world: terrain, atmosphere, vegetation, resort, player and camera.

signal ready_to_play

var terrain: TerrainData
var obstacles: Obstacles
var renderer: TerrainRenderer
var atmosphere: Atmosphere
var vegetation: Vegetation
var skier: Skier
var body: SkierBody
var camera: CameraRig
var fx: Node3D
var audio: Node
var resort: Node3D
var park: Node3D
var load_ms := {}


func build() -> bool:
	var t0 := Time.get_ticks_msec()
	terrain = Game.terrain
	if terrain == null:
		terrain = TerrainData.new()
		if not terrain.load_data():
			push_error("World: terrain data failed to load")
			return false
		Game.terrain = terrain
	load_ms["terrain_data"] = Time.get_ticks_msec() - t0
	obstacles = Obstacles.new()
	obstacles.setup(terrain.world)

	var t1 := Time.get_ticks_msec()
	renderer = TerrainRenderer.new()
	renderer.name = "Terrain"
	add_child(renderer)
	renderer.setup(terrain)
	load_ms["terrain_renderer"] = Time.get_ticks_msec() - t1

	atmosphere = Atmosphere.new()
	atmosphere.name = "Atmosphere"
	atmosphere.terrain_renderer = renderer
	add_child(atmosphere)
	atmosphere.setup(terrain)

	var t2 := Time.get_ticks_msec()
	vegetation = Vegetation.new()
	vegetation.name = "Vegetation"
	add_child(vegetation)
	vegetation.setup(terrain, obstacles)
	load_ms["vegetation"] = Time.get_ticks_msec() - t2

	var t3 := Time.get_ticks_msec()
	if ClassDB.class_exists("Node") and ResourceLoader.exists("res://scripts/world/resort.gd"):
		resort = load("res://scripts/world/resort.gd").new()
		resort.name = "Resort"
		add_child(resort)
		resort.setup(terrain, obstacles)
	if ResourceLoader.exists("res://scripts/world/landmarks.gd"):
		var lm = load("res://scripts/world/landmarks.gd").new()
		lm.name = "Landmarks"
		add_child(lm)
		lm.setup(terrain, obstacles, resort)
	if resort and ResourceLoader.exists("res://scripts/world/npc_skiers.gd"):
		var npc = load("res://scripts/world/npc_skiers.gd").new()
		npc.name = "NPCSkiers"
		add_child(npc)
		npc.setup(terrain, resort.rider_mat)
	if ResourceLoader.exists("res://scripts/world/park.gd"):
		park = load("res://scripts/world/park.gd").new()
		park.name = "Park"
		add_child(park)
		park.setup(terrain, obstacles)
	load_ms["resort"] = Time.get_ticks_msec() - t3
	obstacles.build()

	skier = Skier.new()
	skier.name = "Skier"
	add_child(skier)
	skier.setup(terrain, obstacles)
	if park:
		skier.rails = park.rails

	body = SkierBody.new()
	body.name = "SkierBody"
	add_child(body)
	body.setup(skier)

	if ResourceLoader.exists("res://scripts/fx/ski_fx.gd"):
		fx = load("res://scripts/fx/ski_fx.gd").new()
		fx.name = "SkiFX"
		add_child(fx)
		fx.setup(skier, body, terrain)
	if ResourceLoader.exists("res://scripts/player/skier_audio.gd"):
		audio = load("res://scripts/player/skier_audio.gd").new()
		audio.name = "SkierAudio"
		add_child(audio)
		audio.setup(skier)

	camera = CameraRig.new()
	camera.name = "CameraRig"
	add_child(camera)
	camera.skier = skier
	skier.teleported.connect(camera.snap)          # any teleport frames him at once, no sweep from the old spot
	camera.body = body
	camera.terrain = terrain
	renderer.lod_camera = camera
	skier.landed.connect(func(info: Dictionary):
		if float(info["air_time"]) > 0.3:
			camera.add_shake(clampf(float(info["impact"]) / 12.0, 0.1, 1.2)))
	skier.crashed.connect(func(_r, v: Vector3): camera.add_shake(clampf(v.length() / 15.0, 0.4, 1.5)))
	load_ms["total"] = Time.get_ticks_msec() - t0
	print("World built in %d ms: %s" % [load_ms["total"], str(load_ms)])
	return true


func spawn_at_drop(name: String) -> void:
	var d := terrain.drop_zone(name)
	if d.is_empty():
		return
	spawn(Vector3(d["x"], 0, d["z"]), float(d["yaw"]))


func spawn(pos: Vector3, yaw: float) -> void:
	if resort and resort.has_method("abort_ride"):
		resort.abort_ride()
	skier.teleport(clear_spot(pos), yaw)
	camera.snap()


## Nearest point to `pos` that is clear of buildings/trees/rocks and not too steep.
func clear_spot(pos: Vector3) -> Vector3:
	if obstacles == null:
		return pos
	for r in [0.0, 6.0, 12.0, 18.0, 26.0, 36.0, 48.0, 62.0]:
		var steps := 1 if r == 0.0 else 12
		for k in steps:
			var a := TAU * k / steps
			var p := pos + Vector3(cos(a) * r, 0.0, sin(a) * r)
			if obstacles.clearance(p.x, p.z, 8.0) > 5.0 and terrain.slope_deg(p.x, p.z) < 38.0:
				return p
	return pos
