extends Node
## Global game state: mode, progression and the save file.

signal discovered(kind: String, name: String)
signal progress_changed
signal notify(text: String, kind: String)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

var terrain: TerrainData = null
var mode := "menu"            # menu | career | freeride
var save := {}
## Request handed from menus to the world: {"type": "drop"/"challenge"/"continue", "name"/"id": ...}
var pending_request := {}
## Player-placed map waypoint (x, z) or Vector2.INF
var waypoint := Vector2.INF
## Command line flags (automated tests)
var test_mode := ""
var test_args := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			test_mode = a.substr(7)
		elif a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			test_args[kv[0]] = kv[1]
	_reset_save()
	load_game()


func _reset_save() -> void:
	save = {
		"version": SAVE_VERSION,
		"started": false,
		"drops": [],
		"viewpoints": [],
		"spots": [],
		"challenges": {},
		"stats": {"top_speed": 0.0, "longest_air": 0.0, "best_trick": 0, "distance": 0.0, "crashes": 0, "best_combo": 0},
		"last": {},
	}


func has_save() -> bool:
	return bool(save.get("started", false))


func new_game() -> void:
	_reset_save()
	save["started"] = true
	if terrain:
		for d in terrain.layout.get("drop_zones", []):
			if d.get("unlocked", false):
				save["drops"].append(d["name"])
	save_game()


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY and int(parsed.get("version", 0)) == SAVE_VERSION:
		for k in parsed:
			save[k] = parsed[k]


func save_game() -> void:
	if test_mode != "" and test_mode != "save":
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save, "  "))


# ------------------------------------------------------------------ progression
func is_drop_unlocked(name: String) -> bool:
	if mode == "freeride":
		return true
	return name in save["drops"]


func unlock_drop(name: String) -> void:
	if name in save["drops"]:
		return
	save["drops"].append(name)
	discovered.emit("drop", name)
	notify.emit("Drop zone discovered: %s" % name, "discovery")
	progress_changed.emit()
	save_game()


func discover_viewpoint(name: String) -> void:
	if name in save["viewpoints"]:
		return
	save["viewpoints"].append(name)
	discovered.emit("viewpoint", name)
	notify.emit("Viewpoint discovered: %s" % name, "discovery")
	progress_changed.emit()
	save_game()


func discover_spot(name: String, detail := "") -> bool:
	if not save.has("spots"):
		save["spots"] = []
	if name in save["spots"]:
		return false
	save["spots"].append(name)
	notify.emit("Discovered: %s%s" % [name, ("  —  " + detail) if detail != "" else ""], "discovery")
	discovered.emit("spot", name)
	progress_changed.emit()
	save_game()
	return true


func spot_found(name: String) -> bool:
	return Game.mode == "freeride" or name in save.get("spots", [])


func challenge_result(id: String) -> Dictionary:
	return save["challenges"].get(id, {})


## result: {"medal": 0..3 (3 = gold), "time": float, "score": int, "completed": bool}
func record_challenge(id: String, result: Dictionary) -> bool:
	var prev: Dictionary = save["challenges"].get(id, {})
	var improved := false
	var merged := prev.duplicate()
	if int(result.get("medal", 0)) > int(prev.get("medal", 0)):
		merged["medal"] = int(result["medal"])
		improved = true
	if result.has("time") and (not prev.has("time") or float(result["time"]) < float(prev["time"])):
		merged["time"] = float(result["time"])
		improved = true
	if result.has("score") and int(result["score"]) > int(prev.get("score", 0)):
		merged["score"] = int(result["score"])
		improved = true
	if result.get("completed", false):
		merged["completed"] = true
	save["challenges"][id] = merged
	progress_changed.emit()
	save_game()
	return improved


func stat_max(key: String, value: float) -> bool:
	var stats: Dictionary = save["stats"]
	if value > float(stats.get(key, 0.0)):
		stats[key] = value
		return true
	return false


func stat_add(key: String, value: float) -> void:
	var stats: Dictionary = save["stats"]
	stats[key] = float(stats.get(key, 0.0)) + value


func set_last_position(pos: Vector3, yaw: float) -> void:
	save["last"] = {"x": pos.x, "y": pos.y, "z": pos.z, "yaw": yaw}


func completion_counts() -> Dictionary:
	var total_ch := 0
	var done_ch := 0
	if terrain:
		for c in terrain.layout.get("challenges", []):
			total_ch += 1
			if challenge_result(c["id"]).get("completed", false):
				done_ch += 1
	return {
		"drops": save["drops"].size(),
		"drops_total": terrain.layout.get("drop_zones", []).size() if terrain else 0,
		"viewpoints": save["viewpoints"].size(),
		"viewpoints_total": terrain.layout.get("viewpoints", []).size() if terrain else 0,
		"challenges": done_ch,
		"challenges_total": total_ch,
		"spots": save.get("spots", []).size(),
		"spots_total": (terrain.layout.get("features", []).size() + terrain.layout.get("landmarks", []).size()) if terrain else 0,
	}
