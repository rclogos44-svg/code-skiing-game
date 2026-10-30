class_name Obstacles
extends RefCounted
## Spatial grid of solid obstacles (tree trunks, rocks, buildings, lift towers) for the
## custom skier physics.  Vertical cylinders: (x, z, radius, base_y, top_y, kind).

enum Kind { TREE, ROCK, BUILDING, POLE }

const CELL := 8.0

var world := 6144.0
var cells := 0
var xs := PackedFloat32Array()
var zs := PackedFloat32Array()
var radii := PackedFloat32Array()
var bases := PackedFloat32Array()
var tops := PackedFloat32Array()
var kinds := PackedByteArray()
var _cell_start := PackedInt32Array()
var _cell_items := PackedInt32Array()
var _dirty := true


func setup(world_size: float) -> void:
	world = world_size
	cells = int(ceil(world / CELL)) + 1


func add(x: float, z: float, r: float, base_y: float, top_y: float, kind: int) -> void:
	xs.append(x)
	zs.append(z)
	radii.append(r)
	bases.append(base_y)
	tops.append(top_y)
	kinds.append(kind)
	_dirty = true


func count() -> int:
	return xs.size()


## Counting-sort the obstacles into grid cells (CSR layout).
func build() -> void:
	var total := cells * cells
	var counts := PackedInt32Array()
	counts.resize(total + 1)
	counts.fill(0)
	var cell_of := PackedInt32Array()
	cell_of.resize(xs.size())
	for i in xs.size():
		var c := _cell(xs[i], zs[i])
		cell_of[i] = c
		counts[c + 1] += 1
	for c in total:
		counts[c + 1] += counts[c]
	_cell_start = counts
	_cell_items.resize(xs.size())
	var fill := counts.duplicate()
	for i in xs.size():
		var c := cell_of[i]
		_cell_items[fill[c]] = i
		fill[c] += 1
	_dirty = false


func _cell(x: float, z: float) -> int:
	var cx := clampi(int(x / CELL), 0, cells - 1)
	var cz := clampi(int(z / CELL), 0, cells - 1)
	return cz * cells + cx


## Returns indices of obstacles whose centre lies within `radius` (+ their own radius) of (x, z).
func query(x: float, z: float, radius: float) -> PackedInt32Array:
	if _dirty:
		build()
	var out := PackedInt32Array()
	var r := radius + 4.0
	var x0 := clampi(int((x - r) / CELL), 0, cells - 1)
	var x1 := clampi(int((x + r) / CELL), 0, cells - 1)
	var z0 := clampi(int((z - r) / CELL), 0, cells - 1)
	var z1 := clampi(int((z + r) / CELL), 0, cells - 1)
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			var c := cz * cells + cx
			for k in range(_cell_start[c], _cell_start[c + 1]):
				var i := _cell_items[k]
				var dx := xs[i] - x
				var dz := zs[i] - z
				var rr := radius + radii[i]
				if dx * dx + dz * dz < rr * rr:
					out.append(i)
	return out


## Nearest obstacle distance (surface to point) among those within `radius`; INF if none.
func clearance(x: float, z: float, radius: float) -> float:
	var best := INF
	for i in query(x, z, radius):
		var d := Vector2(xs[i] - x, zs[i] - z).length() - radii[i]
		best = minf(best, d)
	return best
