extends SceneTree
# Turns build/.cache/rider_raw.{json,bin} (written by build/gen_rider.py) into the rider's mesh
# resources: res://assets/rider/rider_body.res, rider_head.res (one surface per garment, named
# "material:garment") and rider.json (bone names and the bind pose, read by SkierRig).
# usage: godot --headless --path PROJECT --script import_rider.gd -- RAW_JSON RAW_BIN


func _bytes(blob: PackedByteArray, span: Array) -> PackedByteArray:
	return blob.slice(int(span[0]), int(span[0]) + int(span[1]))


func _vec3(blob: PackedByteArray, span: Array) -> PackedVector3Array:
	var f := _bytes(blob, span).to_float32_array()
	var out := PackedVector3Array()
	out.resize(f.size() / 3)
	for i in out.size():
		out[i] = Vector3(f[i * 3], f[i * 3 + 1], f[i * 3 + 2])
	return out


func _vec2(blob: PackedByteArray, span: Array) -> PackedVector2Array:
	var f := _bytes(blob, span).to_float32_array()
	var out := PackedVector2Array()
	out.resize(f.size() / 2)
	for i in out.size():
		out[i] = Vector2(f[i * 2], f[i * 2 + 1])
	return out


func _color(blob: PackedByteArray, span: Array) -> PackedColorArray:
	var f := _bytes(blob, span).to_float32_array()
	var out := PackedColorArray()
	out.resize(f.size() / 4)
	for i in out.size():
		out[i] = Color(f[i * 4], f[i * 4 + 1], f[i * 4 + 2], f[i * 4 + 3])
	return out


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(args[0])) if args.size() >= 2 else null
	if not parsed is Dictionary:
		printerr("import_rider: can't read %s (give absolute paths)" % str(args))
		quit(1)
		return
	var meta: Dictionary = parsed
	var blob := FileAccess.get_file_as_bytes(args[1])
	var groups := {"body": ArrayMesh.new(), "head": ArrayMesh.new()}
	var info := []
	for s: Dictionary in meta["surfaces"]:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vec3(blob, s["pos"])
		arrays[Mesh.ARRAY_NORMAL] = _vec3(blob, s["nrm"])
		arrays[Mesh.ARRAY_TANGENT] = _bytes(blob, s["tan"]).to_float32_array()
		arrays[Mesh.ARRAY_TEX_UV] = _vec2(blob, s["uv"])
		arrays[Mesh.ARRAY_COLOR] = _color(blob, s["col"])
		arrays[Mesh.ARRAY_BONES] = _bytes(blob, s["bones"]).to_int32_array()
		arrays[Mesh.ARRAY_WEIGHTS] = _bytes(blob, s["weights"]).to_float32_array()
		arrays[Mesh.ARRAY_INDEX] = _bytes(blob, s["idx"]).to_int32_array()
		var m: ArrayMesh = groups[s["group"]]
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_name(m.get_surface_count() - 1, "%s:%s" % [s["material"], s["name"]])
		info.append({"name": s["name"], "material": s["material"], "group": s["group"], "uv_per_m": s["uv_per_m"]})
	for g in groups:
		var path := "res://assets/rider/rider_%s.res" % g
		var err := ResourceSaver.save(groups[g], path, ResourceSaver.FLAG_COMPRESS)
		print("rider: saved %s (%d surfaces) err %d" % [path, (groups[g] as ArrayMesh).get_surface_count(), err])
	var out := {"bones": meta["bones"], "bind": meta["bind"], "bind_bases": meta["bind_bases"], "surfaces": info}
	var f := FileAccess.open("res://assets/rider/rider.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	quit(0)
