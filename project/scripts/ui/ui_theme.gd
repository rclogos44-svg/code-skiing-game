class_name UITheme
extends RefCounted
## Shared look for all menus and the HUD.

const ACCENT := Color(1.0, 0.47, 0.12)
const TEXT := Color(0.96, 0.97, 1.0)
const DIM := Color(0.72, 0.78, 0.86)
const PANEL := Color(0.05, 0.08, 0.12, 0.78)
const GOLD := Color(1.0, 0.82, 0.25)
const SILVER := Color(0.82, 0.86, 0.92)
const BRONZE := Color(0.85, 0.55, 0.3)

static var _theme: Theme
static var _fonts := {}


static func font(weight := 600) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI", "Helvetica Neue", "SF Pro Display", "Ubuntu", "Noto Sans", "DejaVu Sans", "Arial"])
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	_fonts[weight] = f
	return f


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font(500)
	t.default_font_size = 20
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.08, 0.11, 0.16, 0.72)
	btn.set_corner_radius_all(8)
	btn.content_margin_left = 22
	btn.content_margin_right = 22
	btn.content_margin_top = 10
	btn.content_margin_bottom = 10
	btn.border_width_left = 3
	btn.border_color = Color(1, 1, 1, 0.0)
	var hover := btn.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.14, 0.19, 0.27, 0.88)
	hover.border_color = ACCENT
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.22, 0.14, 0.08, 0.92)
	var disabled := btn.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.08, 0.1, 0.13, 0.4)
	var focus := hover.duplicate() as StyleBoxFlat
	focus.draw_center = false
	focus.border_width_left = 3
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.55, 0.6))
	t.set_font("font", "Button", font(600))
	t.set_font_size("font_size", "Button", 22)
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.set_corner_radius_all(12)
	panel.content_margin_left = 24
	panel.content_margin_right = 24
	panel.content_margin_top = 18
	panel.content_margin_bottom = 18
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 20)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.55))
	# sliders / checkboxes / option buttons
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color(1, 1, 1, 0.18)
	slider.set_corner_radius_all(3)
	slider.content_margin_top = 3
	slider.content_margin_bottom = 3
	var area := slider.duplicate() as StyleBoxFlat
	area.bg_color = ACCENT
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", area)
	t.set_stylebox("grabber_area_highlight", "HSlider", area)
	var ob := btn.duplicate() as StyleBoxFlat
	ob.content_margin_top = 6
	ob.content_margin_bottom = 6
	t.set_stylebox("normal", "OptionButton", ob)
	t.set_stylebox("hover", "OptionButton", hover)
	t.set_stylebox("pressed", "OptionButton", pressed)
	t.set_stylebox("focus", "OptionButton", focus)
	t.set_font_size("font_size", "OptionButton", 18)
	t.set_font_size("font_size", "CheckBox", 18)
	t.set_font_size("font_size", "PopupMenu", 18)
	var tab := btn.duplicate() as StyleBoxFlat
	tab.content_margin_top = 8
	tab.content_margin_bottom = 8
	var tab_sel := hover.duplicate() as StyleBoxFlat
	tab_sel.border_width_left = 0
	tab_sel.border_width_bottom = 3
	t.set_stylebox("tab_unselected", "TabContainer", tab)
	t.set_stylebox("tab_hovered", "TabContainer", hover)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	var tpanel := panel.duplicate() as StyleBoxFlat
	tpanel.bg_color = Color(0.05, 0.08, 0.12, 0.6)
	t.set_stylebox("panel", "TabContainer", tpanel)
	t.set_font_size("font_size", "TabContainer", 20)
	_theme = t
	return t


static func label(text: String, size := 20, color := TEXT, weight := 500, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	return l


static func medal_color(m: int) -> Color:
	match m:
		3:
			return GOLD
		2:
			return SILVER
		1:
			return BRONZE
	return DIM


static func medal_name(m: int) -> String:
	return ["", "Bronze", "Silver", "Gold"][clampi(m, 0, 3)]


static func format_time(t: float) -> String:
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%d:%05.2f" % [m, s]
