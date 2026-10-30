extends Node
## Project validation (run headless): every script compiles with autoloads present, required
## resources exist and load, input actions are defined, and the world layout is sane.
## Prints "[VALIDATE] ..." lines; exit code 1 on any failure.

var failures := 0


func _fail(msg: String) -> void:
	failures += 1
	print("[VALIDATE] FAIL ", msg)


func _scan(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if d.current_is_dir():
			if not f.begins_with("."):
				_scan(dir.path_join(f), out)
		else:
			out.append(dir.path_join(f))
		f = d.get_next()


func _ready() -> void:
	var files: Array = []
	_scan("res://scripts", files)
	var n_scripts := 0
	for f in files:
		if f.ends_with(".gd") and f != get_script().resource_path:
			n_scripts += 1
			var s: Script = load(f)
			if s == null or not s.can_instantiate():
				_fail("script does not compile: " + f)
	print("[VALIDATE] scripts checked: ", n_scripts)
	for r in ["res://scenes/main.tscn", "res://shaders/terrain.gdshader", "res://shaders/sky.gdshader", "res://shaders/rock.gdshader",
			"res://world/normal.png", "res://world/surface.png", "res://world/bake.png", "res://world/far_bake.png", "res://world/map.png",
			"res://assets/textures/snow_normal.png", "res://assets/textures/rock_albedo.png", "res://assets/textures/rock_normal.png",
			"res://assets/textures/noise.png", "res://assets/textures/puff.png", "res://assets/textures/flake.png",
			"res://default_bus_layout.tres"]:
		if not ResourceLoader.exists(r) or load(r) == null:
			_fail("missing resource " + r)
	for a in ["wind_loop", "slide_loop", "carve_loop", "powder_loop", "ice_loop", "ambient_loop", "jump", "land_soft", "land_hard",
			"crash", "tree_hit", "ui_click", "ui_hover", "checkpoint", "trick", "discovery", "medal", "fail", "beep", "go", "pole"]:
		if Sfx.get_stream(a) == null:
			_fail("missing audio " + a)
	for b in ["height16.bin", "far16.bin", "trees.bin", "rocks.bin", "layout.json"]:
		if not FileAccess.file_exists("res://world/" + b):
			_fail("missing world data " + b)
	# input actions used by gameplay
	for act in Settings.ACTIONS.keys() + ["menu"]:
		if not InputMap.has_action(act) or InputMap.action_get_events(act).is_empty():
			_fail("input action missing or unbound: " + act)
	# world data
	var td := TerrainData.new()
	if not td.load_data():
		_fail("terrain data failed to load")
	else:
		print("[VALIDATE] terrain %dx%d, heights %.0f..%.0f m" % [td.n, td.n, td.min_h, td.max_h])
		var names := {}
		for d in td.layout.get("drop_zones", []):
			names[d["name"]] = true
			var x: float = d["x"]
			var z: float = d["z"]
			if x < 100 or z < 100 or x > td.world - 100 or z > td.world - 100:
				_fail("drop zone outside playable area: " + d["name"])
			var h := td.height(x, z)
			if absf(h - float(d["y"])) > 3.0:
				_fail("drop zone height mismatch: %s (%.1f vs %.1f)" % [d["name"], h, d["y"]])
			if td.slope_deg(x, z) > 45.0:
				_fail("drop zone on a cliff: %s (%.0f deg)" % [d["name"], td.slope_deg(x, z)])
		for c in td.layout.get("challenges", []):
			if c.has("drop") and c["drop"] != null and not names.has(c["drop"]):
				_fail("challenge %s references missing drop zone %s" % [c["id"], c["drop"]])
			if c["type"] == "race" and (c["checkpoints"] as Array).size() < 3:
				_fail("race %s has too few checkpoints" % c["id"])
		for v in td.layout.get("viewpoints", []):
			if absf(td.height(v["x"], v["z"]) - float(v["y"])) > 3.0:
				_fail("viewpoint height mismatch " + v["name"])
		print("[VALIDATE] layout: %d drop zones, %d viewpoints, %d challenges, %d lifts, %d pistes" % [
			td.layout["drop_zones"].size(), td.layout["viewpoints"].size(), td.layout["challenges"].size(),
			td.layout["lifts"].size(), td.layout["pistes"].size()])
	print("[VALIDATE] %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures > 0 else 0)
