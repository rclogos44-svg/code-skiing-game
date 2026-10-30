extends SceneTree
# Rasterizes the SVG app icon to PNG (used for window/exe icons).
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var src: String = args[0]
	var dst: String = args[1]
	var size := int(args[2]) if args.size() > 2 else 256
	var f := FileAccess.open(src, FileAccess.READ)
	var img := Image.new()
	var err := img.load_svg_from_buffer(f.get_buffer(f.get_length()), size / 256.0)
	if err != OK:
		push_error("svg load failed")
		quit(1)
		return
	img.save_png(dst)
	print("icon ", img.get_size())
	quit(0)
