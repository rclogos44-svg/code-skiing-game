class_name TerrainData
extends RefCounted
## CPU-side access to the generated world: heights, normals, snow surface types, layout.
## The same heightmap drives the GPU terrain mesh, so physics and visuals agree.

var n := 0                   # core samples per side
var sp := 2.0                # core spacing (m)
var world := 6144.0          # core size (m)
var heights := PackedByteArray()        # 16-bit big-endian samples (also the GPU texture data)
var h_min := 0.0
var h_scale := 1.0
var far_n := 0
var far_sp := 32.0
var far_origin := -6144.0
var far_heights := PackedByteArray()
var far_min := 0.0
var far_scale := 1.0
var surface: Image           # R powder, G groomed, B ice, A tree density
var surf_n := 0
var layout := {}
var min_h := 0.0
var max_h := 3000.0
var sun_dir := Vector3(-0.5, 0.71, 0.5).normalized()
# park kickers, added on top of the heightmap analytically (the 2 m grid can't hold a sharp lip)
var _kickers: Array = []     # {o: Vector2, d: Vector2, h, lr, ld, ll, hw}
var _kick_cells := {}        # 64 m cell key -> Array of kicker indices
const KICK_CELL := 64.0


func load_data(base := "res://world/") -> bool:
	var lf := FileAccess.open(base + "layout.json", FileAccess.READ)
	if lf == null:
		push_error("TerrainData: missing layout.json")
		return false
	var parsed = JSON.parse_string(lf.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("TerrainData: invalid layout.json")
		return false
	layout = parsed
	var meta: Dictionary = layout["meta"]
	n = int(meta["n"])
	sp = float(meta["spacing"])
	world = float(meta["world_size"])
	far_n = int(meta["far_n"])
	far_sp = float(meta["far_spacing"])
	far_origin = float(meta["far_origin"])
	min_h = float(meta["min_h"])
	max_h = float(meta["max_h"])
	var sd: Array = meta.get("sun_dir", [-0.5, 0.71, 0.5])
	sun_dir = Vector3(sd[0], sd[1], sd[2]).normalized()
	h_min = float(meta["core_min"])
	h_scale = float(meta["core_scale"])
	far_min = float(meta["far_min"])
	far_scale = float(meta["far_scale"])
	heights = _load_bytes(base + "height16.bin", n * n * 2)
	far_heights = _load_bytes(base + "far16.bin", far_n * far_n * 2)
	if heights.is_empty() or far_heights.is_empty():
		return false
	var tex: Texture2D = load(base + "surface.png")
	if tex == null:
		push_error("TerrainData: missing surface.png")
		return false
	surface = tex.get_image()
	if surface.is_compressed():
		surface.decompress()
	surface.convert(Image.FORMAT_RGBA8)
	surf_n = surface.get_width()
	_load_kickers()
	return true


var _pipes: Array = []        # superpipes: {o, d, len, hf (half flat), r, ww, wh, deck, outer, taper}


func _load_kickers() -> void:
	for pk in layout.get("parks", []):
		for pp in pk.get("pipes", []):
			_pipes.append({"o": Vector2(pp["origin"][0], pp["origin"][1]), "d": Vector2(pp["dir"][0], pp["dir"][1]).normalized(),
				"len": float(pp["length"]), "hf": float(pp["flat"]) * 0.5, "r": float(pp["radius"]), "ww": float(pp["wall_w"]),
				"wh": float(pp["wall_h"]), "deck": float(pp["deck"]), "outer": float(pp["outer"]), "taper": float(pp["taper"])})
	for pk in layout.get("parks", []):
		for k in pk["kickers"]:
			var o := Vector2(k["origin"][0], k["origin"][1])
			var d := Vector2(k["dir"][0], k["dir"][1]).normalized()
			var kk := {"o": o, "d": d, "h": float(k["height"]), "lr": float(k["ramp"]), "ld": float(k["deck"]),
				"ll": float(k["landing"]), "hw": float(k["half_width"]), "h2": float(k.get("knuckle_h", k["height"]))}
			var idx := _kickers.size()
			_kickers.append(kk)
			var total: float = kk["lr"] + kk["ld"] + kk["ll"]
			var side: Vector2 = Vector2(-d.y, d.x) * (float(kk["hw"]) + 2.0)
			var lo := o
			var hi := o
			for c in [o + side, o - side, o + d * total + side, o + d * total - side]:
				lo = lo.min(c)
				hi = hi.max(c)
			for cz in range(int(floor(lo.y / KICK_CELL)), int(floor(hi.y / KICK_CELL)) + 1):
				for cx in range(int(floor(lo.x / KICK_CELL)), int(floor(hi.x / KICK_CELL)) + 1):
					var key := cz * 4096 + cx
					if not _kick_cells.has(key):
						_kick_cells[key] = []
					_kick_cells[key].append(idx)


## Extra height of the park kickers at (x, z): parabolic ramp up to the lip, flat deck, straight landing.
func kicker_offset(x: float, z: float) -> float:
	var key := int(floor(z / KICK_CELL)) * 4096 + int(floor(x / KICK_CELL))
	if not _kick_cells.has(key):
		return 0.0
	var best := 0.0
	for idx in _kick_cells[key]:
		var k: Dictionary = _kickers[idx]
		var rel := Vector2(x, z) - (k["o"] as Vector2)
		var d: Vector2 = k["d"]
		var t := rel.dot(d)
		var u := absf(rel.x * -d.y + rel.y * d.x)
		var hw: float = k["hw"]
		if t <= 0.0 or u >= hw + 2.0:
			continue
		var h: float = k["h"]
		var lr: float = k["lr"]
		var ld: float = k["ld"]
		var ll: float = k["ll"]
		var h2: float = k["h2"]        # knuckle height: below the lip on a step-down (the deck slopes down)
		var y := 0.0
		if t < lr:
			y = h * (t / lr) * (t / lr)
		elif t < lr + ld:
			y = lerpf(h, h2, (t - lr) / ld)
		elif t < lr + ld + ll:
			y = h2 * (1.0 - (t - lr - ld) / ll)
		y *= clampf((hw + 2.0 - u) * 0.5, 0.0, 1.0)
		best = maxf(best, y)
	return best


func _load_bytes(path: String, count: int) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("TerrainData: cannot open " + path)
		return PackedByteArray()
	var arr := f.get_buffer(f.get_length())
	if arr.size() != count:
		push_error("TerrainData: %s has %d bytes, expected %d" % [path, arr.size(), count])
		return PackedByteArray()
	return arr


## Raw core sample i (row-major) in metres.
func core_sample(i: int) -> float:
	return float((heights[2 * i] << 8) | heights[2 * i + 1]) * h_scale + h_min


func in_core(x: float, z: float) -> bool:
	return x >= 0.0 and z >= 0.0 and x <= world and z <= world


## Ground height (m): heightmap plus park kickers and pipes.
func height(x: float, z: float) -> float:
	return base_height(x, z) + feature_offset(x, z)


## Height of the park's shaped snow (kickers, pipe walls) above the regraded slope.
func feature_offset(x: float, z: float) -> float:
	var k := kicker_offset(x, z) if not _kick_cells.is_empty() else 0.0
	return maxf(k, pipe_offset(x, z)) if not _pipes.is_empty() else k


## Superpipe walls: flat bottom, quarter-circle transitions steepening to the coping, a deck, an
## outer bank.  The walls grow in over `taper` m at the top and fade out at the bottom.
func pipe_offset(x: float, z: float) -> float:
	var best := 0.0
	for pp in _pipes:
		var rel := Vector2(x, z) - (pp["o"] as Vector2)
		var d: Vector2 = pp["d"]
		var t := rel.dot(d)
		var ln: float = pp["len"]
		if t < 0.0 or t > ln + 15.0:
			continue
		var a := absf(rel.x * -d.y + rel.y * d.x) - float(pp["hf"])
		if a <= 0.0:
			continue
		var r: float = pp["r"]
		var ww: float = pp["ww"]
		var wh: float = pp["wh"]
		var y := 0.0
		if a < ww:
			y = r - sqrt(maxf(r * r - a * a, 0.0))
		elif a < ww + float(pp["deck"]):
			y = wh
		elif a < ww + float(pp["deck"]) + float(pp["outer"]):
			y = wh * (1.0 - (a - ww - float(pp["deck"])) / float(pp["outer"]))
		else:
			continue
		y *= smoothstep(0.0, float(pp["taper"]), t) * smoothstep(ln + 15.0, ln, t)
		best = maxf(best, y)
	return best


## Unit vector across the pipe pointing out toward the nearer wall (x, z), or ZERO outside a pipe's
## walls - used to send riders straight up off the coping.
func pipe_out(x: float, z: float) -> Vector2:
	for pp in _pipes:
		var rel := Vector2(x, z) - (pp["o"] as Vector2)
		var d: Vector2 = pp["d"]
		var t := rel.dot(d)
		if t < 0.0 or t > float(pp["len"]) + 15.0:
			continue
		var side := Vector2(-d.y, d.x)
		var u := rel.dot(side)
		if absf(u) > float(pp["hf"]) and absf(u) < float(pp["hf"]) + float(pp["ww"]) + float(pp["deck"]) + 1.0:
			return side * signf(u)
	return Vector2.ZERO


## Bilinear heightmap height (m). Outside the core the 32 m backdrop grid is used.
func base_height(x: float, z: float) -> float:
	if x >= 0.0 and z >= 0.0 and x <= world and z <= world:
		var fx := x / sp
		var fz := z / sp
		var ix := mini(int(fx), n - 2)
		var iz := mini(int(fz), n - 2)
		var tx := fx - ix
		var tz := fz - iz
		var i := (iz * n + ix) * 2
		var r := n * 2
		var a := float((heights[i] << 8) | heights[i + 1])
		var b := float((heights[i + 2] << 8) | heights[i + 3])
		var c := float((heights[i + r] << 8) | heights[i + r + 1])
		var d := float((heights[i + r + 2] << 8) | heights[i + r + 3])
		return ((a + (b - a) * tx) * (1.0 - tz) + (c + (d - c) * tx) * tz) * h_scale + h_min
	return far_height(x, z)


func far_height(x: float, z: float) -> float:
	var fx := clampf((x - far_origin) / far_sp, 0.0, far_n - 1.001)
	var fz := clampf((z - far_origin) / far_sp, 0.0, far_n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := (iz * far_n + ix) * 2
	var r := far_n * 2
	var a := float((far_heights[i] << 8) | far_heights[i + 1])
	var b := float((far_heights[i + 2] << 8) | far_heights[i + 3])
	var c := float((far_heights[i + r] << 8) | far_heights[i + r + 1])
	var d := float((far_heights[i + r + 2] << 8) | far_heights[i + r + 3])
	return ((a + (b - a) * tx) * (1.0 - tz) + (c + (d - c) * tx) * tz) * far_scale + far_min


## Smooth surface normal from central differences (e = half-width in metres).
func normal(x: float, z: float, e := 1.0) -> Vector3:
	var hl := height(x - e, z)
	var hr := height(x + e, z)
	var hd := height(x, z - e)
	var hu := height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


## Snow surface at a point: r = powder depth, g = groomed, b = ice, a = tree density (all 0..1).
func surface_at(x: float, z: float) -> Color:
	if surf_n == 0:
		return Color(0.5, 0, 0, 0)
	var u := clampf(x / world, 0.0, 1.0) * (surf_n - 1)
	var v := clampf(z / world, 0.0, 1.0) * (surf_n - 1)
	var ix := mini(int(u), surf_n - 2)
	var iz := mini(int(v), surf_n - 2)
	var tx := u - ix
	var tz := v - iz
	var a := surface.get_pixel(ix, iz)
	var b := surface.get_pixel(ix + 1, iz)
	var c := surface.get_pixel(ix, iz + 1)
	var d := surface.get_pixel(ix + 1, iz + 1)
	return a.lerp(b, tx).lerp(c.lerp(d, tx), tz)


## Slope in degrees.
func slope_deg(x: float, z: float) -> float:
	return rad_to_deg(acos(clampf(normal(x, z).y, -1.0, 1.0)))


## Ray march against the terrain. Returns the hit fraction along from->to (1.0 = no hit).
func raycast(from: Vector3, to: Vector3, step := 2.0) -> float:
	var d := to - from
	var length := d.length()
	if length < 0.001:
		return 1.0
	var steps := maxi(1, int(ceil(length / step)))
	var prev_t := 0.0
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var p := from + d * t
		if p.y < height(p.x, p.z):
			var lo := prev_t
			var hi := t
			for _k in 8:
				var mid := (lo + hi) * 0.5
				var q := from + d * mid
				if q.y < height(q.x, q.z):
					hi = mid
				else:
					lo = mid
			return lo
		prev_t = t
	return 1.0


func region_at(x: float, z: float) -> int:
	var best := 0
	var best_w := -1.0
	for r in layout.get("regions", []):
		var s := float(r.get("s", 900.0))
		var dx := x - float(r["x"])
		var dz := z - float(r["z"])
		var w := exp(-(dx * dx + dz * dz) / (2.0 * s * s))
		if w > best_w:
			best_w = w
			best = int(r["id"])
	return best


func region_name(id: int) -> String:
	for r in layout.get("regions", []):
		if int(r["id"]) == id:
			return r["name"]
	return ""


func drop_zone(name: String) -> Dictionary:
	for d in layout.get("drop_zones", []):
		if d["name"] == name:
			return d
	return {}


func challenge(id: String) -> Dictionary:
	for c in layout.get("challenges", []):
		if c["id"] == id:
			return c
	return {}
