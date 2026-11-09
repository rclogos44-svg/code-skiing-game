class_name TrickSystem
extends Node
## Freestyle scoring.  Every trick is derived from what actually happened in the air: measured
## yaw rotation (rounded to 180 degree steps only when the landing is aligned), flip rotation
## (full flips, or a cork when the spin went off-axis and came back), grab type and hold times,
## air time and landing quality.  Tricks landed in quick succession form a combo that is banked
## after a few seconds on the snow and lost on a crash.

signal trick_landed(info: Dictionary)
signal combo_banked(total: int, count: int)
signal combo_lost(points: int)

const COMBO_WINDOW := 3.5
const SPIN_POINTS := {180: 200, 360: 500, 540: 900, 720: 1400, 900: 2000, 1080: 2700, 1260: 3500, 1440: 4400}
const FLIP_POINTS := {1: 1000, 2: 2400, 3: 4200}
const FLIP_NAMES := {1: "", 2: "Double ", 3: "Triple "}
const CORKS := false                 # off-axis spins come later

var skier: Skier
var combo_points := 0
var combo_count := 0
var multiplier := 1.0
var session_score := 0
var tricks_landed := 0
var history: Array = []          # recent trick infos (for challenges)


func setup(s: Skier) -> void:
	skier = s
	s.landed.connect(_on_landed)
	s.crashed.connect(_on_crashed)
	s.respawned.connect(_reset_combo)
	s.jibbed.connect(func(info: Dictionary): _add(evaluate_jib(info)))


func _process(_dt: float) -> void:
	if skier == null or combo_count == 0:
		return
	if not skier.airborne and not skier.is_crashed and skier.ground_time > COMBO_WINDOW:
		_bank()


func _bank() -> void:
	var total := int(round(combo_points * multiplier))
	session_score += total
	Game.stat_max("best_combo", total)
	combo_banked.emit(total, combo_count)
	_reset_combo()


func _reset_combo() -> void:
	combo_points = 0
	combo_count = 0
	multiplier = 1.0


func _on_crashed(_reason: String, _v: Vector3) -> void:
	if combo_count > 0:
		combo_lost.emit(combo_points)
	_reset_combo()


## Pure evaluation (also used by tests).
static func evaluate(info: Dictionary) -> Dictionary:
	var rot_deg := absf(rad_to_deg(float(info["rotation"])))
	var spins := int(floor((rot_deg + 55.0) / 180.0))
	var spin := spins * 180
	var air: float = info["air_time"]
	var gl: float = info["grab_l"]
	var gr: float = info["grab_r"]
	var parts: Array[String] = []
	var points := 0
	var tags: Array[String] = []
	var flip := float(info.get("flip", 0.0))
	var flips := int(floor((absf(rad_to_deg(flip)) + 60.0) / 360.0))
	var cork := CORKS and flips == 0 and spin >= 360 and rad_to_deg(float(info.get("pitch_peak", 0.0))) >= 50.0
	if flips >= 1:
		parts.append("%s%s" % [FLIP_NAMES.get(flips, "%dx " % flips), "Backflip" if flip < 0.0 else "Frontflip"])
		points += int(FLIP_POINTS.get(flips, 4200 + (flips - 3) * 2000))
		tags.append("flip")
		tags.append("backflip" if flip < 0.0 else "frontflip")
	if spin >= 180:
		var dir := "Right" if float(info["rotation"]) > 0.0 else "Left"
		parts.append("%s %s%d" % [dir, "Cork " if cork else "", spin])
		points += int(int(SPIN_POINTS.get(spin, 4400 + (spin - 1440) * 6)) * (1.3 if cork else 1.0))
		tags.append("spin")
		tags.append(str(spin))
		if cork:
			tags.append("cork")
	var grabs := 0
	var gname := String(info.get("grab_name", ""))
	var gtime := float(info.get("grab_time", 0.0))
	if gname != "" and gtime >= 0.2:
		# named grab: points for how long it's held, scaled by how hard it is to reach
		var hard := {"Safety": 0.9, "Mute": 1.0, "Tail": 1.0, "Tip": 1.1, "Truck Driver": 1.2, "Japan": 1.3, "Blunt": 1.3}.get(gname, 1.0) as float
		parts.append(gname)
		points += int((200 + 400.0 * minf(gtime, 2.0)) * hard)
		grabs = 2 if gname == "Truck Driver" else 1
		tags.append("grab")
		tags.append(gname.to_lower().replace(" ", "_"))
		gl = 0.0
		gr = 0.0
	if gl >= 0.25:
		grabs += 1
		points += 150 + int(300.0 * minf(gl, 2.0))
	if gr >= 0.25:
		grabs += 1
		points += 150 + int(300.0 * minf(gr, 2.0))
	if grabs == 2 and gname == "":
		parts.append("Double Grab")
		points = int(points * 1.25)
		tags.append("grab")
		tags.append("double_grab")
	elif gl >= 0.25 or gr >= 0.25:
		# tip / tail grabs (leaning while grabbing) score a little more than a plain grab
		var kind := String(info.get("grab_kind_l" if gl >= 0.25 else "grab_kind_r", ""))
		var side := "Left" if gl >= 0.25 else "Right"
		parts.append({"tip": "%s Tip Grab", "tail": "%s Tail Grab"}.get(kind, "%s Ski Grab") % side)
		if kind != "":
			points = int(points * 1.15)
		tags.append("grab")
	if air >= 1.0:
		points += int(120.0 * (air - 1.0) * 2.0)
		if air >= 2.5:
			parts.append("Big Air")
			points += 400
			tags.append("big_air")
	if parts.is_empty():
		if air >= 1.2:
			parts.append("Air")
			tags.append("air")
		else:
			return {}
	var misalign: float = info["misalign"]
	var impact: float = info["impact"]
	var quality := "OK"
	var q_mul := 1.0
	if misalign < 12.0 and impact < 9.0:
		quality = "Clean landing"
		q_mul = 1.25
	elif misalign > 30.0 or impact > 12.0:
		quality = "Sketchy landing"
		q_mul = 0.6
	if info.get("switch", false) and spin >= 180:
		tags.append("switch")
	points = int(round(points * q_mul))
	return {"name": " ".join(parts), "points": points, "quality": quality, "spin": spin, "grabs": grabs,
		"air_time": air, "tags": tags}


func _on_landed(info: Dictionary) -> void:
	if info["crash"] != "":
		return
	if info["air_time"] < 0.35:
		return
	Game.stat_max("longest_air", float(info["air_time"]))
	_add(evaluate(info))


## Rail / box slides: stance, presses, switch, spin on, time on the feature.
static func evaluate_jib(info: Dictionary) -> Dictionary:
	var dur := float(info["time"])
	if dur < 0.4 or (info["how"] == "fall" and dur < 0.8):
		return {}
	var slide: bool = info["slide"]
	var parts: Array[String] = []
	var points := 250.0 + 300.0 * dur
	var on := int(floor((absf(rad_to_deg(float(info["entry_rot"]))) + 45.0) / 90.0)) * 90
	if on >= 180:
		parts.append("%d On" % on)
		points += 250.0 * (on / 90.0 - 1.0)
	if info["switch"]:
		parts.append("Switch")
		points *= 1.2
	parts.append("50-50" if not slide else {"box": "Box Slide", "widebox": "Box Slide", "tube": "Tube Slide"}.get(info["kind"], "Rail Slide"))
	if slide:
		points *= 1.3
	var press := float(info["press"])
	if absf(press) >= 0.4:
		parts.append("to Nose Press" if press > 0.0 else "to Tail Press")
		points *= 1.25
	if info["kind"] == "rail":
		points *= 1.2
	var tags: Array[String] = ["jib", String(info["kind"])]
	return {"name": " ".join(parts), "points": int(round(points)), "quality": "Clean" if info["how"] != "fall" else "Slipped off",
		"spin": 0, "grabs": 0, "air_time": 0.0, "tags": tags}


func _add(t: Dictionary) -> void:
	if t.is_empty():
		return
	combo_count += 1
	combo_points += int(t["points"])
	multiplier = minf(1.0 + 0.5 * (combo_count - 1), 4.0)
	t["combo_count"] = combo_count
	t["multiplier"] = multiplier
	t["combo_points"] = combo_points
	tricks_landed += 1
	history.append(t)
	if history.size() > 50:
		history.pop_front()
	Game.stat_max("best_trick", float(t["points"]))
	trick_landed.emit(t)
	Sfx.play("trick", -6.0, 1.0 + 0.05 * mini(combo_count, 6))
