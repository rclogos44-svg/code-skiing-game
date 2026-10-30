extends SceneTree
# Writes the Godot Engine license and third-party notices (required when distributing a Godot game).
func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var f := FileAccess.open(out.path_join("GODOT_ENGINE_LICENSE.txt"), FileAccess.WRITE)
	f.store_string("This game uses Godot Engine, available under the following license:\n\n" + Engine.get_license_text())
	f = FileAccess.open(out.path_join("THIRD_PARTY_NOTICES.txt"), FileAccess.WRITE)
	var s := "Godot Engine includes the following third-party components:\n\n"
	for comp in Engine.get_copyright_info():
		s += "- %s\n" % comp["name"]
		for part in comp["parts"]:
			for c in part["copyright"]:
				s += "    (c) %s\n" % c
			s += "    License: %s\n" % part["license"]
		s += "\n"
	s += "\n\nFull license texts:\n\n"
	var lic: Dictionary = Engine.get_license_info()
	for k in lic:
		s += "==== %s ====\n%s\n\n" % [k, lic[k]]
	f.store_string(s)
	print("licenses written to ", out)
	quit(0)
